import UIKit
import RoomPlan
import simd
import Speech
import AVFoundation

enum RoomScanOutcome {
    case cancelled
    // `merged` tells the caller whether every room in `rooms` genuinely
    // shares one coordinate space (StructureBuilder succeeded) or each
    // room only has its own local origin (single room, iOS 16, or a
    // failed merge) - see FloorPlanEncoder.encodeStructure. `structure` is
    // the real merged object (non-nil only when a multi-room merge
    // actually succeeded) - kept around only so a later "export 3D model"
    // action can export the whole merged structure, not just one room.
    // `levels` is parallel to `rooms` (same index = same room) - which
    // building level (1, 2, 3...) each room was tagged with when scanned.
    // "Scan another level" uses the exact same continuous-tracking/merge
    // mechanism as "scan another room" - levels are just rooms with an
    // extra tag, not a separate native capture mode - so the honest
    // merged/unmerged fallback already built for rooms covers levels too.
    // `voiceNames` is also parallel to `rooms` - the room name captured by
    // the voice assistant, if any (nil = not answered/recognized, falls
    // back to the existing rule-based guess on the web side). `equipment`
    // is likewise parallel to `rooms` - each room's own logged equipment,
    // by type. `deletedIndices` flags rooms removed by voice mid-session
    // (a soft flag, not discarded scan data - see FloorPlanEncoder).
    // `inspection` is the post-scan verification block (pose-trace
    // coverage + keyframe manifest from ScanInspector), nil when the
    // pipeline was skipped/unavailable.
    case finished(rooms: [CapturedRoom], structure: Any?, merged: Bool, levels: [Int], voiceNames: [String?], equipment: [[String: EquipmentEntry]], deletedIndices: Set<Int>, inspection: [String: Any]?, surfaceAnswers: [String: String])
}

// Wraps RoomPlan's own RoomCaptureView, which already renders the live 3D
// wireframe overlay and Apple's built-in scan-quality coaching text during
// capture. Multi-room: after each room, capture stops (keeping the
// ARSession itself alive via stop(pauseARSession: false) - the real
// precondition for StructureBuilder to align the next room into the same
// coordinate space, confirmed against Apple's WWDC23 RoomPlan session and
// developer-forum guidance rather than assumed) and the user chooses to
// scan another room or finish. Only the thin button/prompt bar around
// Apple's own camera screen is custom here - no custom SceneKit/RealityKit
// renderer, same as Phase 1.
class RoomScanViewController: UIViewController, RoomCaptureViewDelegate, AVSpeechSynthesizerDelegate {

    var onFinish: ((RoomScanOutcome) -> Void)?

    private enum State {
        case scanningRoom
        case processingRoom   // stopped, waiting for didPresent to hand back the refined room
        case roomDonePrompt   // "otro cuarto" / "terminar" choice
        case finishingSession // running StructureBuilder (or already done, on a single room)
    }

    private let captureView = RoomCaptureView(frame: .zero)
    private var isSessionRunning = false
    private var state: State = .scanningRoom
    private var capturedRooms: [CapturedRoom] = []
    // Parallel to capturedRooms (same index = same room) - which level that
    // room was tagged with when it was scanned. currentLevel only changes
    // via "Otro nivel," never via "Otro cuarto."
    private var roomLevels: [Int] = []
    private var currentLevel = 1

    // LA PLANTA DONDE EMPEZO, escogida con el dedo en la pantalla de Escanear
    // antes de abrir la camara ("Sótano", "2do Piso"...).
    //
    // `currentLevel` es el ORDEN del escaneo, no la planta: escanear solo el
    // segundo piso dejaba todo en "Nivel 1". El numero se queda como esta - lo
    // usan el editor del plano, el mapa de humedad y la logica de puertas -
    // pero la pantalla y la voz dicen el nombre de verdad, que es el mismo que
    // usa Medidas. Vacio = no se escogio, y entonces se dice "Nivel N" como
    // siempre.
    var nivelBase: String = ""
    // Las cinco plantas en orden, para nombrar el nivel 2, 3... si dice "otro
    // nivel". Se topa en el atico: no hay a donde seguir subiendo.
    private static let plantas = ["Sótano", "1er Piso", "2do Piso", "3er Piso", "Ático"]
    // Los valores que manda la web son los de LEVEL_OPTIONS, en ingles.
    private static let plantaDelValor: [String: Int] = [
        "Basement": 0, "1st Floor": 1, "2nd Floor": 2, "3rd Floor": 3, "Attic": 4
    ]
    // Como se llama el nivel N en esta casa.
    private func nombreDelNivel(_ n: Int) -> String {
        guard let i0 = Self.plantaDelValor[nivelBase] else { return "Nivel \(n)" }
        let i = min(i0 + max(0, n - 1), Self.plantas.count - 1)
        return Self.plantas[i]
    }

    // `voiceNames` is parallel to capturedRooms - the room name heard/
    // tapped for each room, if any (nil = never named, falls back to the
    // existing rule-based guess on the web side).
    private var voiceNames: [String?] = []
    // Whatever name has been heard or tapped for the room CURRENTLY being
    // scanned - applied the moment that room's capture actually finishes
    // (captureView(didPresent:) below), then reset for the next one. A
    // single unified slot: naming works the same way for the first room
    // and every later room, whether you speak or tap, before the room
    // finishes or right after.
    private var pendingCurrentRoomName: String?

    // `roomEquipment` is parallel to capturedRooms (same index = same
    // room) - each room's own logged equipment, keyed by canonical type
    // for cheap update-in-place ("dos deshumidificadores" then later
    // "quita uno" both just touch roomEquipment[i]["dehumidifiers"]).
    // `pendingCurrentEquipment` is the in-progress room's own version of
    // pendingCurrentRoomName - equipment heard while still scanning,
    // committed into roomEquipment the moment that room finishes.
    private var roomEquipment: [[String: EquipmentEntry]] = []
    private var pendingCurrentEquipment: [String: EquipmentEntry] = [:]

    // Rooms removed by voice mid-session - a soft flag only (there's no
    // RoomPlan API to un-scan a room), matching how hiding a piece of
    // furniture already worked. `pendingDeleteRoomIndex` is set the
    // moment "elimina este cuarto" is heard and cleared either by a
    // spoken "sí" (executes the deletion) or by deleteConfirmationTimer
    // expiring - deletion never happens from the delete phrase alone.
    private var deletedRoomIndices = Set<Int>()
    private var pendingDeleteRoomIndex: Int?
    private var deleteConfirmationTimer: Timer?
    // The chip shown for a few seconds right after a deletion executes -
    // the "tap to cancel" safety net on top of the spoken "sí" itself.
    private var lastDeletedIndexForUndo: Int?
    private var undoDeleteTimer: Timer?
    private let undoDeleteButton = UIButton(type: .system)
    // Fires if RoomPlan's post-"listo" refinement never calls back (dead
    // camera/session) so the walkthrough is salvaged instead of hanging.
    private var processingWatchdogTimer: Timer?

    // The walkthrough recorder for the post-scan verification pipeline -
    // a pure observer (pose trace + throttled keyframe photos), created
    // lazily so its temp-dir setup never delays screen presentation.
    private var keyframeRecorder: ScanKeyframeRecorder?

    // "Uniendo cuartos…" was the ONE waiting state with no escape hatch:
    // if StructureBuilder (or anything in the finish path) hung, the
    // whole walkthrough was lost to a frozen screen - reported from the
    // field on a simple 2-room scan. After 30s, deliver the rooms
    // UNMERGED (each at its own origin, honestly flagged) rather than
    // hold the scan hostage. `sessionDelivered` guards so the fallback
    // and a late-completing merge can never both resolve the promise.
    private var sessionDelivered = false
    private var finishingWatchdogTimer: Timer?

    // Ambiguity gate for a genuinely DIFFERENT room name heard by voice
    // while the room currently being scanned already has one - it could
    // mean "correct this room's name" or "I've moved to a new room," and
    // both produce byte-identical cleaned text, so there is no way to
    // tell them apart from the words alone. Per explicit instruction:
    // never silently overwrite an existing room just because a new name
    // was spoken - so this asks rather than guesses. Lives entirely
    // inside .scanningRoom (no new top-level State case), so every other
    // .scanningRoom behavior - equipment logging, quick-pick taps, the
    // continuous listener itself - keeps working unmodified underneath
    // an open question.
    private var pendingRoomSplitCandidateName: String?
    private var roomSplitConfirmationTimer: Timer?
    // Set only inside resolveRoomSplit(asNewRoom: true); consumed once by
    // captureView(didPresent:) to skip .roomDonePrompt and auto-continue
    // straight into scanning the next room, pre-named with what the tech
    // already said - that screen only exists to ask a question the tech
    // just answered out loud.
    private var autoContinueNextRoomName: String?

    // LA CONVERSACION AL TERMINAR UN CUARTO.
    //
    // Antes el asistente soltaba tres opciones de un golpe ("¿Otro cuarto,
    // otro nivel, o terminar?"). El tecnico esta parado en una casa mojada
    // sosteniendo el telefono: no puede acordarse de tres frases. Ahora se
    // pregunta UNA cosa a la vez y siempre se contesta si o no.
    //
    // Ninguna de estas preguntas hace algo irreversible al contestar que
    // si, por eso aqui un "si" pelado SI se acepta - al reves que la
    // pregunta de cuarto-nuevo (resolveRoomSplit), donde un "si" ambiguo
    // podria cortar una captura y perder geometria que no vuelve.
    // ============ QUE ES UNA VOZ DE TRABAJO Y QUE ES RUIDO ============
    //
    // EL PROBLEMA REAL, en sus palabras: "de repente estan hablando y el que
    // va escaneando va pasando por ese lugar, y el voice command detecta otra
    // voz o conversacion muy distinta. El voice command puede cambiar el
    // nombre del cuarto."
    //
    // Y tenia razon: cleanVoiceRoomName aceptaba CUALQUIER frase de 5 palabras
    // o menos como nombre de cuarto, sin preguntar. Un "ya vamonos de aqui"
    // dicho por otra persona al otro lado del cuarto bautizaba el cuarto
    // "Ya vamonos de aqui" y nadie se enteraba hasta ver el plano.
    //
    // Tres defensas, de la mas fisica a la mas lista:
    //   1. QUE TAN FUERTE ENTRO. El tecnico trae el telefono en la mano, a un
    //      palmo de la boca. Una platica al otro lado del cuarto entra mucho
    //      mas bajita. Eso no se puede fingir y no depende del idioma.
    //   2. SI ES UNA PALABRA DE CUARTO. Un nombre de cuarto se parece a un
    //      nombre de cuarto. "Ya vamonos de aqui" no.
    //   3. LO QUE EL YA HA DICHO. Cada nombre que el confirma se guarda en
    //      este telefono; la proxima vez esa palabra ya es de confianza sin
    //      preguntar. Aqui es donde el asistente aprende de EL.
    //
    // Y la regla que las amarra: si una palabra NO pasa los filtros, la app
    // NO la tira a la basura ni la acepta a ciegas - PREGUNTA. Asi el puede
    // inventar el nombre que quiera y la app nunca corrompe un plano sola.
    private static let knownRoomWords: Set<String> = [
        "cocina", "baño", "bano", "medio baño", "medio bano", "recámara", "recamara",
        "cuarto", "cuarto de lavado", "lavado", "sala", "comedor", "closet", "clóset",
        "pasillo", "oficina", "garaje", "garage", "sótano", "sotano", "ático", "atico",
        "entrada", "escaleras", "escalera", "despensa", "pantry", "bodega", "estudio",
        "family room", "living room", "master", "recámara principal", "recamara principal",
        "cuarto principal", "vestidor", "terraza", "patio", "porche", "balcón", "balcon",
        "cochera", "lavandería", "lavanderia", "hall", "recibidor", "alacena"
    ]
    // Lo aprendido de EL, en este telefono. Se llena solo, cada vez que
    // confirma un nombre.
    private static let learnedNamesKey = "voiceLearnedRoomNames:v1"
    private var learnedRoomNames: Set<String> = []
    // Que tan fuerte habla EL. Se aprende de las veces que la app tuvo la
    // certeza de que era el (contesto una pregunta, o toco un boton y hablo).
    private static let ownLevelKey = "voiceOwnSpeechLevel:v1"
    private var ownSpeechLevel: Float = 0        // 0 = todavia no se sabe
    private var ownSpeechSamples: Int = 0
    // Pico de volumen desde el ultimo despacho, medido en el tap del micro.
    private var levelPeakSinceDispatch: Float = 0
    // El nivel con el que entro la frase que se esta atendiendo ahorita.
    private var currentUtteranceLevel: Float = 0
    // Un nombre que sono raro y esta esperando un si o un no.
    private var pendingUnsureName: String?
    // Lo que EL dijo que era una abertura que RoomPlan no supo clasificar,
    // por identificador de superficie. Viaja al plano con el escaneo.
    // El tecnico parado en el cuarto sabe mas que el escaner: esto NO
    // inventa geometria, solo corrige una etiqueta con su respuesta.
    private var voiceSurfaceAnswers: [String: String] = [:]

    private enum DoneQuestion {
        case repeatRoom          // "¿Lo escaneamos otra vez?"
        case confirmName(String) // "¿Es el cuarto de lavado?"
        case askName             // espera un NOMBRE, no un si/no
        case nextRoom            // "¿Vamos al siguiente cuarto?"
        case openingIsDoor       // "Vi una abertura de 3 pies. ¿Es una puerta?"
    }
    private var pendingDoneQuestion: DoneQuestion?
    private var pendingOpeningId: String?
    private let newRoomButton = UIButton(type: .system)
    private let correctNameButton = UIButton(type: .system)
    private lazy var roomSplitButtonsStack = UIStackView(arrangedSubviews: [newRoomButton, correctNameButton])

    // A live, cumulative sketch of every room finished SO FAR - grows one
    // room per pause, never blanks/resets when a new room starts.
    // refreshLiveStructure() is only ever called FROM
    // captureView(didPresent:), never from the stop/start trigger, so the
    // panel keeps showing exactly what it showed a moment ago all the way
    // through the mandatory stop-wait-run gap between rooms - that gap is
    // real (RoomPlan's refinement pass) and isn't shortened by any of
    // this, but the plan-so-far never disappears while the tech waits it
    // out. Recomputed via StructureBuilder over the FULL room set each
    // time (its only public surface is capturedStructure(from: [CapturedRoom])
    // - there's no incremental/delta API), single-flight with at most one
    // coalesced pending rerun so concurrent room completions never launch
    // overlapping merges.
    private let floorPlanPanelView = FloorPlanPanelView()
    private let planPanelStatusLabel = UILabel()
    private let planPanelSpinner = UIActivityIndicatorView(style: .medium)
    private var liveStructureRooms: [RoomSketch] = []
    private var liveMerged = true
    private var mergeGeneration = 0
    private var mergeInFlight = false
    private var mergeQueued = false

    private let speechSynthesizer = AVSpeechSynthesizer()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
    // Completions keyed by their OWN utterance, not a single shared slot.
    // A single slot had a real, reachable bug: AVSpeechSynthesizer queues
    // utterances, so a second speak() before the first finished silently
    // overwrote the first's completion - and the very FIRST speak in the
    // whole flow (the intro line) carries the most important completion
    // in the app, startVoiceAssistant(). A quick-pick tap during those
    // few seconds of intro speech would clobber it and the mic would
    // never start for the entire session.
    private var speechCompletions: [AVSpeechUtterance: () -> Void] = [:]

    // MARK: Continuous voice assistant
    //
    // Rebuilt from a scripted "ask a question, listen 4s, give up" flow
    // into an always-on assistant that listens for as long as the scan
    // screen is open - say a room's name whenever it's natural (before,
    // during, or right after scanning it) and it's applied immediately,
    // no waiting to be asked. SFSpeechRecognitionTask enforces a real
    // ~60s cap per task (Apple's own header: "the framework stops speech
    // recognition tasks that last longer than one minute") - continuous
    // listening is built by proactively restarting a fresh task every 50s
    // on the SAME still-running AVAudioEngine tap, so listening itself
    // never actually stops, just the recognizer bookkeeping underneath it.
    private var micMuted = false
    private var voicePermissionGranted = false
    private var voiceAudioEngine: AVAudioEngine?
    private var voiceRequest: SFSpeechAudioBufferRecognitionRequest?
    private var voiceTask: SFSpeechRecognitionTask?
    private var voiceRestartTimer: Timer?
    private var voiceTaskGeneration = 0
    private var voiceErrorRestartCount = 0
    private var allowServerRecognition = false
    private var isSpeakingConfirmation = false
    private let micToggleButton = UIButton(type: .system)
    private let voiceCaptionLabel = UILabel()

    // Quick-pick room-name buttons (tap OR speak - either names the room).
    // A job site is noisy and speech recognition can fail for reasons that
    // have nothing to do with this app (a fan running, a mask muffling the
    // voice) - tapping a button always works, and is available the whole
    // time a room is being scanned, not just at fixed prompt moments.
    private static let roomOptionNames = [
        "Sala", "Cocina", "Recámara", "Baño", "Comedor",
        "Pasillo", "Sótano", "Garaje", "Oficina", "Cuarto de lavado"
    ]
    private var roomsNamedByButton = Set<Int>()
    // AI scan coach: per-room camera-coverage score, computed the moment
    // each room's geometry arrives (see quickRoomCoverage).
    private var roomCoverageByIndex: [Int: (percent: Int, total: Int, wellSeen: Int, worstType: String?, worstLengthFt: Double?)] = [:]
    // Open runs in a room's outline, in feet, per room index. A missing
    // wall is the most expensive scan failure and the ONLY one the
    // coverage machinery is blind to: an element RoomPlan never modelled
    // cannot be graded, so inspect() never sees it.
    private var roomGapsByIndex: [Int: [Double]] = [:]
    // ESQUINAS QUE NO CERRARON en cada cuarto (asistente de esquinas, 13 de
    // septiembre): dos paredes que no llegaron a encontrarse. Se dice cuál
    // esquina, con los largos de las dos paredes, mientras sigue parado ahí.
    private var roomCornersByIndex: [Int: [FloorPlanEncoder.CornerFinding]] = [:]
    // Puertas ya avisadas: una vez por sesion. Sin esto, el mismo hallazgo
    // verdadero se repite en cada cuarto que se termine despues.
    private var reportedMirroredPorts: Set<UUID> = []
    private var pendingMirroredPort: ScanInspector.MirroredPort?
    // A room name heard mid-scan whose auto-advance a gap warning held
    // back - reused for the next room so he is not asked to say it twice.
    private var pendingRoomNameAfterGap: String?

    // "13 pies 9" reads back to a contractor the way a tape measure does;
    // "13.78 feet" does not. Same convention as the plan's own labels.
    static func feetInchesText(_ ft: Double) -> String {
        let total = Int((ft * 12).rounded())
        let f = total / 12, i = total % 12
        return i == 0 ? "\(f) pies" : "\(f) pies \(i)"
    }
    private let roomOptionsScroll = UIScrollView()
    private lazy var roomOptionsStack = UIStackView(arrangedSubviews: Self.roomOptionNames.map(makeRoomOptionButton))

    private let cancelButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private let roomSummaryLabel = UILabel()
    private let statusLabel = UILabel()

    private let scanAnotherButton = UIButton(type: .system)
    private let nextLevelButton = UIButton(type: .system)
    private let finishButton = UIButton(type: .system)
    private let repeatRoomButton = UIButton(type: .system)
    private lazy var promptStack = UIStackView(arrangedSubviews: [repeatRoomButton, scanAnotherButton, nextLevelButton, finishButton])

    override func viewDidLoad() {
        super.viewDidLoad()
        // El detector de maderas se carga AHORA, en segundo plano, y no
        // sobre la primera foto del escaneo.
        DetectorDeStuds.precalentar()
        // Su vocabulario y su volumen, de trabajos anteriores en ESTE telefono.
        loadVoiceLearning()
        // Build tag: proves in the console (and in `strings` on the
        // binary) exactly which build a field scan ran on - a scan came
        // back with a payload only an older build could emit, and this
        // removes that ambiguity permanently. Bump per deploy.
        NSLog("[RoomScan] build tag: 2026-09-26-LC (KY + la pantalla del temporal vuelve a bajar: Sus horas y Su historial arriba, el calendario abajo)")
        view.backgroundColor = .black
        captureView.delegate = self
        speechSynthesizer.delegate = self
        captureView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureView)

        // A distinct, OPAQUE full-width strip at the very top - never a
        // translucent overlay floating on the camera feed, so it can
        // never visually collide with Apple's own non-themeable RoomPlan
        // coaching overlay (they now occupy disjoint screen regions
        // entirely, by construction, not just by convention).
        floorPlanPanelView.translatesAutoresizingMaskIntoConstraints = false
        floorPlanPanelView.backgroundColor = .black
        view.addSubview(floorPlanPanelView)
        let planPanelHairline = UIView()
        planPanelHairline.translatesAutoresizingMaskIntoConstraints = false
        planPanelHairline.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        floorPlanPanelView.addSubview(planPanelHairline)

        [cancelButton, doneButton, scanAnotherButton, nextLevelButton, finishButton, repeatRoomButton].forEach(styleBarButton)
        cancelButton.setTitle("Cancelar", for: .normal)
        // Big, green, and explicit - the field report was that scans kept
        // absorbing far-away geometry (a closet measuring way oversized)
        // because it wasn't obvious there IS a "done with this room"
        // action. Same button, unmissable now, and "listo" spoken works
        // too (see handleVoiceCommand's session-control branch).
        doneButton.setTitle("✓ Cuarto listo", for: .normal)
        doneButton.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.9)
        scanAnotherButton.setTitle("Escanear otro cuarto", for: .normal)
        nextLevelButton.setTitle("Otro nivel (ej. piso de arriba)", for: .normal)
        finishButton.setTitle("Terminar y unir plano", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        // The app has been telling the tech "puedes escanearlo otra vez"
        // for months without giving him anywhere to do it - his only route
        // was to scan another room and then voice-delete the bad one.
        // Shown only when this room actually came back with a hole in it.
        repeatRoomButton.setTitle("↻ Repetir este cuarto", for: .normal)
        repeatRoomButton.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.9)
        repeatRoomButton.addTarget(self, action: #selector(repeatRoomTapped), for: .touchUpInside)
        scanAnotherButton.addTarget(self, action: #selector(scanAnotherTapped), for: .touchUpInside)
        nextLevelButton.addTarget(self, action: #selector(scanAnotherLevelTapped), for: .touchUpInside)
        finishButton.addTarget(self, action: #selector(finishTapped), for: .touchUpInside)

        // Lives INSIDE the plan panel (top-left) - "Cuarto N" while
        // scanning, swapping to "Procesando…" + a small spinner during the
        // stop-wait-run gap between rooms. This, plus the spinner, is the
        // ONLY visible change during that wait - the panel's drawing itself
        // is untouched until the next room's geometry actually arrives.
        planPanelStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        planPanelStatusLabel.textColor = .white
        planPanelStatusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        planPanelSpinner.translatesAutoresizingMaskIntoConstraints = false
        planPanelSpinner.color = .white
        planPanelSpinner.hidesWhenStopped = true
        floorPlanPanelView.addSubview(planPanelStatusLabel)
        floorPlanPanelView.addSubview(planPanelSpinner)

        // Shown once a room finishes: its suggested name (same rule-based
        // guess the web layer makes post-session, ported here so it can
        // show up immediately instead of only at the very end) plus that
        // room's own wall/door/window/object counts.
        roomSummaryLabel.translatesAutoresizingMaskIntoConstraints = false
        roomSummaryLabel.textColor = .white
        roomSummaryLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        roomSummaryLabel.textAlignment = .center
        roomSummaryLabel.numberOfLines = 0
        roomSummaryLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        roomSummaryLabel.layer.cornerRadius = 10
        roomSummaryLabel.layer.masksToBounds = true
        roomSummaryLabel.isHidden = true

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        statusLabel.textAlignment = .center
        statusLabel.text = "Procesando…"
        statusLabel.isHidden = true

        promptStack.translatesAutoresizingMaskIntoConstraints = false
        promptStack.axis = .vertical
        promptStack.spacing = 10
        promptStack.isHidden = true

        // Quick-pick room-name row: tap a name instead of (or as well as)
        // saying it. Shown any time a room is actively being scanned or
        // just finished - naming works the same way for every room.
        roomOptionsScroll.translatesAutoresizingMaskIntoConstraints = false
        roomOptionsScroll.showsHorizontalScrollIndicator = false
        roomOptionsScroll.isHidden = true
        roomOptionsStack.translatesAutoresizingMaskIntoConstraints = false
        roomOptionsStack.axis = .horizontal
        roomOptionsStack.spacing = 8
        roomOptionsScroll.addSubview(roomOptionsStack)

        // Mic mute toggle - always visible, always under the tech's own
        // control. Muting fully tears down the audio engine (not just
        // ignores results) so it's honest about when the mic is live.
        micToggleButton.translatesAutoresizingMaskIntoConstraints = false
        micToggleButton.setTitle("🎤", for: .normal)
        micToggleButton.titleLabel?.font = .systemFont(ofSize: 18)
        micToggleButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        micToggleButton.layer.cornerRadius = 20
        micToggleButton.layer.masksToBounds = true
        micToggleButton.addTarget(self, action: #selector(micToggleTapped), for: .touchUpInside)

        // Brief confirmation caption ("Sala ✓") whenever a name is heard
        // or tapped while a room is actively being scanned - the room-done
        // summary card already gives this same feedback once a room
        // finishes, but there's nothing on screen during the scan itself
        // without this.
        voiceCaptionLabel.translatesAutoresizingMaskIntoConstraints = false
        voiceCaptionLabel.textColor = .white
        voiceCaptionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        voiceCaptionLabel.textAlignment = .center
        voiceCaptionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        voiceCaptionLabel.layer.cornerRadius = 8
        voiceCaptionLabel.layer.masksToBounds = true
        voiceCaptionLabel.numberOfLines = 1
        voiceCaptionLabel.isHidden = true

        // "Deshacer" chip shown briefly after a voice-confirmed room
        // deletion - the tap-to-cancel safety net on top of the spoken
        // "sí" itself, matching the app's existing confirm+Undo pattern
        // for other destructive edits (e.g. wall removal).
        undoDeleteButton.translatesAutoresizingMaskIntoConstraints = false
        undoDeleteButton.setTitle("Deshacer eliminación", for: .normal)
        undoDeleteButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        undoDeleteButton.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        undoDeleteButton.setTitleColor(.white, for: .normal)
        undoDeleteButton.layer.cornerRadius = 16
        undoDeleteButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        undoDeleteButton.isHidden = true
        undoDeleteButton.addTarget(self, action: #selector(undoDeleteTapped), for: .touchUpInside)

        // Room-split disambiguation buttons - occupy the exact same
        // screen slot as the quick-pick room-name row, which they
        // temporarily replace only while a question is open. A deliberate
        // tap always resolves it immediately; "Cuarto nuevo" is the ONLY
        // button in this whole screen (besides "Listo" itself) that can
        // lead to captureSession.stop() being called.
        newRoomButton.setTitle("🆕 Cuarto nuevo", for: .normal)
        correctNameButton.setTitle("✏️ Corregir nombre", for: .normal)
        [newRoomButton, correctNameButton].forEach { b in
            b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            b.setTitleColor(.white, for: .normal)
            b.layer.cornerRadius = 10
        }
        newRoomButton.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.85)
        correctNameButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
        newRoomButton.addTarget(self, action: #selector(newRoomButtonTapped), for: .touchUpInside)
        correctNameButton.addTarget(self, action: #selector(correctNameButtonTapped), for: .touchUpInside)
        roomSplitButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        roomSplitButtonsStack.axis = .horizontal
        roomSplitButtonsStack.spacing = 8
        roomSplitButtonsStack.distribution = .fillEqually
        roomSplitButtonsStack.isHidden = true

        view.addSubview(cancelButton)
        view.addSubview(doneButton)
        view.addSubview(roomSummaryLabel)
        view.addSubview(statusLabel)
        view.addSubview(roomOptionsScroll)
        view.addSubview(promptStack)
        view.addSubview(micToggleButton)
        view.addSubview(voiceCaptionLabel)
        view.addSubview(undoDeleteButton)
        view.addSubview(roomSplitButtonsStack)

        NSLayoutConstraint.activate([
            // The plan panel claims its own dedicated strip at the very
            // top - the camera view is pinned BELOW it (not overlaid),
            // so the two never share pixels with Apple's own coaching
            // overlay. Fixed 160pt height on every supported device,
            // never grows with room count.
            floorPlanPanelView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            floorPlanPanelView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            floorPlanPanelView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            floorPlanPanelView.heightAnchor.constraint(equalToConstant: 160),

            planPanelHairline.leadingAnchor.constraint(equalTo: floorPlanPanelView.leadingAnchor),
            planPanelHairline.trailingAnchor.constraint(equalTo: floorPlanPanelView.trailingAnchor),
            planPanelHairline.bottomAnchor.constraint(equalTo: floorPlanPanelView.bottomAnchor),
            planPanelHairline.heightAnchor.constraint(equalToConstant: 1),

            planPanelStatusLabel.topAnchor.constraint(equalTo: floorPlanPanelView.topAnchor, constant: 8),
            planPanelStatusLabel.leadingAnchor.constraint(equalTo: floorPlanPanelView.leadingAnchor, constant: 10),

            planPanelSpinner.centerYAnchor.constraint(equalTo: planPanelStatusLabel.centerYAnchor),
            planPanelSpinner.leadingAnchor.constraint(equalTo: planPanelStatusLabel.trailingAnchor, constant: 6),

            captureView.topAnchor.constraint(equalTo: floorPlanPanelView.bottomAnchor),
            captureView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            captureView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            captureView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -70),

            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            doneButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            doneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            micToggleButton.topAnchor.constraint(equalTo: floorPlanPanelView.bottomAnchor, constant: 12),
            micToggleButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            micToggleButton.widthAnchor.constraint(equalToConstant: 40),
            micToggleButton.heightAnchor.constraint(equalToConstant: 40),

            voiceCaptionLabel.topAnchor.constraint(equalTo: micToggleButton.bottomAnchor, constant: 8),
            voiceCaptionLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            voiceCaptionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 110),
            voiceCaptionLabel.heightAnchor.constraint(equalToConstant: 26),

            roomSummaryLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            roomSummaryLabel.bottomAnchor.constraint(equalTo: roomOptionsScroll.topAnchor, constant: -10),
            roomSummaryLabel.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.85),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            roomOptionsScroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            roomOptionsScroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            roomOptionsScroll.bottomAnchor.constraint(equalTo: promptStack.topAnchor, constant: -10),
            roomOptionsScroll.heightAnchor.constraint(equalToConstant: 40),

            roomOptionsStack.topAnchor.constraint(equalTo: roomOptionsScroll.topAnchor),
            roomOptionsStack.bottomAnchor.constraint(equalTo: roomOptionsScroll.bottomAnchor),
            roomOptionsStack.leadingAnchor.constraint(equalTo: roomOptionsScroll.leadingAnchor),
            roomOptionsStack.trailingAnchor.constraint(equalTo: roomOptionsScroll.trailingAnchor),
            roomOptionsStack.heightAnchor.constraint(equalTo: roomOptionsScroll.heightAnchor),

            promptStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            promptStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            promptStack.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),

            undoDeleteButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            undoDeleteButton.topAnchor.constraint(equalTo: floorPlanPanelView.bottomAnchor, constant: 16),

            roomSplitButtonsStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            roomSplitButtonsStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            roomSplitButtonsStack.bottomAnchor.constraint(equalTo: promptStack.topAnchor, constant: -10),
            roomSplitButtonsStack.heightAnchor.constraint(equalToConstant: 40)
        ])

        updateUI()
    }

    private func styleBarButton(_ b: UIButton) {
        b.translatesAutoresizingMaskIntoConstraints = false
        b.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        b.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        b.setTitleColor(.white, for: .normal)
        b.layer.cornerRadius = 10
        b.contentEdgeInsets = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
    }

    private func makeRoomOptionButton(_ name: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(name, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        b.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        b.setTitleColor(.white, for: .normal)
        b.layer.cornerRadius = 16
        b.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        b.addTarget(self, action: #selector(roomOptionTapped(_:)), for: .touchUpInside)
        return b
    }

    // Names whichever room is relevant right now: the one still being
    // scanned (sets the pending name for when it finishes) or the one
    // that just finished (corrects it directly, same room the room-done
    // summary card is already showing).
    @objc private func roomOptionTapped(_ sender: UIButton) {
        guard let name = sender.currentTitle else { return }
        applyHeardOrTappedName(name, viaButton: true)
    }

    // Same rule-based room-name guess the web layer makes (Part 3's
    // suggestFloorplanRoomName) - not a trained classifier, just "if these
    // fixtures are here, it's probably this kind of room." Ported here so
    // the in-scan summary can show it immediately instead of only at the
    // very end of the whole session.
    private static let roomNameRules: [(name: String, categories: Set<String>)] = [
        ("Cocina", ["stove", "oven", "refrigerator", "dishwasher", "sink"]),
        ("Baño", ["toilet", "bathtub"]),
        ("Recámara", ["bed"]),
        ("Cuarto de lavado", ["washerDryer"]),
        ("Sala", ["sofa", "television", "fireplace"]),
        ("Comedor", ["table", "chair"])
    ]
    private func suggestedRoomName(for room: CapturedRoom) -> String? {
        let cats = Set(room.objects.map { String(describing: $0.category) })
        var best: (name: String, matches: Int)?
        for rule in Self.roomNameRules {
            let matches = rule.categories.intersection(cats).count
            if matches > 0 && (best == nil || matches > best!.matches) {
                best = (rule.name, matches)
            }
        }
        return best?.name
    }

    private func updateUI() {
        // Keep the walkthrough recorder's room/level tag and its
        // photos-allowed flag in sync with the scan state (photos are
        // gated to .scanningRoom; the pose trace never stops).
        keyframeRecorder?.update(roomIndex: capturedRooms.count, level: currentLevel, scanning: state == .scanningRoom)
        // Only mention the level once a second one's actually in play -
        // the common single-level scan stays uncluttered.
        // Con la planta escogida se dice SIEMPRE, aunque sea la primera: si esta
        // parado en el segundo piso, verlo escrito es lo que le confirma que la
        // app lo sabe. Sin planta escogida se calla hasta el nivel 2, como antes.
        let levelSuffix = !nivelBase.isEmpty ? " · \(nombreDelNivel(currentLevel))"
                        : (currentLevel > 1 ? " · Nivel \(currentLevel)" : "")
        switch state {
        case .scanningRoom:
            cancelButton.isHidden = false
            doneButton.isHidden = false
            statusLabel.isHidden = true
            promptStack.isHidden = true
            roomSummaryLabel.isHidden = true
            planPanelStatusLabel.text = "Cuarto \(capturedRooms.count + 1)\(levelSuffix)"
            planPanelSpinner.stopAnimating()
            // The room-split question, when open, temporarily replaces
            // the quick-pick row in the exact same screen slot rather
            // than stacking alongside it.
            let splitOpen = pendingRoomSplitCandidateName != nil
            roomOptionsScroll.isHidden = splitOpen
            roomSplitButtonsStack.isHidden = !splitOpen
        case .processingRoom:
            cancelButton.isHidden = true
            doneButton.isHidden = true
            statusLabel.isHidden = true
            promptStack.isHidden = true
            roomSummaryLabel.isHidden = true
            // The ONLY visible change during the mandatory stop-wait-run
            // gap between rooms - the plan panel's own drawing is left
            // completely untouched (refreshLiveStructure() is only ever
            // called from captureView(didPresent:), never from here), so
            // the plan-so-far never blanks or resets while this shows.
            planPanelStatusLabel.text = "Procesando…"
            planPanelSpinner.startAnimating()
            roomOptionsScroll.isHidden = true
            roomSplitButtonsStack.isHidden = true
        case .roomDonePrompt:
            cancelButton.isHidden = true
            doneButton.isHidden = true
            statusLabel.isHidden = true
            promptStack.isHidden = false
            // Offered only when this room came back with a hole - it is a
            // destructive action, and on a clean room it would just be
            // one more button between him and the next room.
            repeatRoomButton.isHidden = (roomGapsByIndex[capturedRooms.count - 1] ?? []).isEmpty
                && (roomCornersByIndex[capturedRooms.count - 1] ?? []).isEmpty
            planPanelStatusLabel.text = "Cuarto \(capturedRooms.count) listo"
            planPanelSpinner.stopAnimating()
            roomSummaryLabel.isHidden = false
            roomOptionsScroll.isHidden = false
            roomSplitButtonsStack.isHidden = true
            if let last = capturedRooms.last {
                let namedByButton = capturedRooms.indices.last.map { roomsNamedByButton.contains($0) } ?? false
                let voiceName = voiceNames.last.flatMap { $0 }
                let nameText: String
                if namedByButton, let voiceName = voiceName {
                    nameText = "\(voiceName) (elegido)"
                } else {
                    nameText = voiceName.map { "\($0) (por voz)" }
                        ?? suggestedRoomName(for: last).map { "\($0) (sugerido)" }
                        ?? "sin nombre sugerido"
                }
                let lvl = roomLevels.last ?? 1
                let levelText = !nivelBase.isEmpty ? " · \(nombreDelNivel(lvl))"
                              : (lvl > 1 ? " · Nivel \(lvl)" : "")
                var text = "  Cuarto \(capturedRooms.count) escaneado\(levelText) — \(nameText)\n\(last.walls.count) paredes · \(last.doors.count) puertas · \(last.windows.count) ventanas · \(last.objects.count) objetos"
                if let index = capturedRooms.indices.last, !equipmentSummaryText(for: index).isEmpty {
                    text += "\n\(equipmentSummaryText(for: index))"
                }
                if let gaps = roomGapsByIndex[capturedRooms.count - 1], !gaps.isEmpty {
                    let worst = gaps.max() ?? 0
                    text += gaps.count == 1
                        ? "\n⚠︎ Falta un lado: hueco de \(Self.feetInchesText(worst)) en el contorno"
                        : "\n⚠︎ Faltan \(gaps.count) lados; el mayor, \(Self.feetInchesText(worst))"
                }
                if let esq = peorEsquina(capturedRooms.count - 1) {
                    text += "\n⚠︎ Esquina sin cerrar \(Self.feetInchesText(esq.d)) entre la pared de \(Self.feetInchesText(esq.wallALenFt)) y la de \(Self.feetInchesText(esq.wallBLenFt))"
                }
                if let m = pendingMirroredPort {
                    text += "\n⚠︎ \(roomLabel(for: m.ownerRoomIndex)) tiene una "
                        + (m.isDoor ? "puerta" : "abertura")
                        + " de \(Self.feetInchesText(m.widthFt)) que \(roomLabel(for: m.otherRoomIndex)) no dibujo"
                }
                if let cov = roomCoverageByIndex[capturedRooms.count - 1] {
                    // NOT a percentage of area - quickRoomCoverage has no
                    // notion of floor or area at all. It is the share of
                    // this room's walls, doors, windows and passages that
                    // the camera got a good look at. Said as a count, it
                    // cannot be misread as square footage, and it matches
                    // the shape of the verdict the document later prints.
                    text += "\nCámara: \(cov.wellSeen) de \(cov.total) paredes, puertas y ventanas bien vistas"
                }
                roomSummaryLabel.text = text + "  "
            }
        case .finishingSession:
            cancelButton.isHidden = true
            doneButton.isHidden = true
            statusLabel.text = capturedRooms.count > 1 ? "Uniendo cuartos…" : "Terminando…"
            statusLabel.isHidden = false
            roomOptionsScroll.isHidden = true
            roomSplitButtonsStack.isHidden = true
            promptStack.isHidden = true
            roomSummaryLabel.isHidden = true
            planPanelStatusLabel.text = capturedRooms.count > 1 ? "Uniendo cuartos…" : "Terminando…"
            planPanelSpinner.startAnimating()
        }
    }

    private var hasAppeared = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // One-shot setup: a re-appear (returning from a presented alert or
        // the app coming back to foreground) used to restart capture from
        // ANY state, orphan the running recorder (deleting every keyframe
        // taken so far), and rebuild the voice stack over a live engine.
        guard !hasAppeared else { return }
        hasAppeared = true
        guard !isSessionRunning else { return }
        startCapturingRoom()
        // Start the walkthrough recorder once the capture session is
        // live - it only ever READS arSession.currentFrame. The ARSession
        // reference is resolved HERE, on the main thread, exactly once:
        // the recorder's 2 Hz tick runs on a background queue, and the
        // first version's provider dereferenced captureView (a UIView)
        // from that queue - UIKit off-main, capable of stalling right at
        // the finish/merge step. ARSession.currentFrame itself is
        // documented thread-safe; UIView property access is not.
        let arSession = captureView.captureSession.arSession
        let recorder = ScanKeyframeRecorder(arSessionProvider: { [weak arSession] in
            arSession
        })
        keyframeRecorder = recorder
        recorder.update(roomIndex: 0, level: currentLevel, scanning: true)
        // EL ASISTENTE DE MADERAS, EN VIVO. Su pedido del 12 de septiembre:
        // "cuando vea todas esas maderas, sepa identificar que ahí hay una
        // pared". RoomPlan no la va a dibujar (no tiene categoría de
        // madera), pero la cámara SÍ la reconoce mientras camina, y se lo
        // dice en el momento, para que escanee los dos lados sin pelearse
        // con el escáner. Al terminar, el plano trae la partición propuesta
        // justo donde la cámara vio las maderas - y ELLA decide si se parte.
        recorder.onStudsSeen = { [weak self] roomIdx in
            self?.avisarMaderas(roomIdx, reintento: true)
        }
        recorder.start()
        // The audio session is configured and ACTIVATED once, up front,
        // BEFORE the first utterance - not lazily when the mic engine
        // starts. The old ordering was the likely root of the persistent
        // silent-voice reports: the intro was queued against an
        // unconfigured session, and beginContinuousRecognition then
        // reconfigured the session MID-UTTERANCE (via the 6s failsafe
        // firing before the ~6s intro finished), which can stall
        // AVSpeechSynthesizer for the rest of the session.
        configureAudioSessionIfNeeded()
        // Short on purpose: less time talking = less to go wrong before
        // the mic starts, and it teaches the one word that matters most.
        // Ya no EXIGE el nombre por adelantado: al terminar el cuarto la app
        // lo propone y el solo aprueba. Decirlo mientras escanea sigue
        // funcionando igual, pero ahora es opcional, no una tarea mas.
        speak("Recorre el cuarto y di listo cuando termines. Si quieres, dime el nombre mientras.") { [weak self] in
            self?.startVoiceAssistantOnce()
        }
        // FAILSAFE: the mic must never depend solely on a TTS completion
        // firing. Whichever path runs first wins; the other is a no-op.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.startVoiceAssistantOnce()
        }
        // Honest heads-up when the phone is running hot - sustained
        // LiDAR + camera + tracking is exactly the workload that trips
        // RoomPlan's own deviceTooHot failure (a black camera feed),
        // so at least say so instead of failing silently.
        NotificationCenter.default.addObserver(self, selector: #selector(thermalStateChanged),
                                               name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        // A phone call / Siri / alarm mid-scan takes the audio session and,
        // without these, killed BOTH the mic and every spoken prompt for
        // the rest of the walkthrough (audioSessionConfigured stayed true
        // while the session was actually gone, blocking reactivation).
        NotificationCenter.default.addObserver(self, selector: #selector(audioSessionInterrupted(_:)),
                                               name: AVAudioSession.interruptionNotification,
                                               object: AVAudioSession.sharedInstance())
        NotificationCenter.default.addObserver(self, selector: #selector(audioEngineConfigurationChanged(_:)),
                                               name: .AVAudioEngineConfigurationChange, object: nil)
    }

    @objc private func audioSessionInterrupted(_ note: Notification) {
        guard let info = note.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch type {
            case .began:
                // Tear down cleanly so audioSessionConfigured reflects
                // reality (the system already deactivated our session).
                self.stopVoiceAssistant()
                self.voiceCaptionLabel.text = "  🎤 Pausado  "
                self.voiceCaptionLabel.isHidden = false
            case .ended:
                guard !self.sessionDelivered, !self.micMuted else { return }
                self.configureAudioSessionIfNeeded()
                self.startVoiceAssistant()
            @unknown default:
                break
            }
        }
    }

    // Route change (headphones/Bluetooth connect or disconnect) changes
    // the input format under the tap - rebuild the engine on the new route.
    @objc private func audioEngineConfigurationChanged(_ note: Notification) {
        guard let engine = voiceAudioEngine, (note.object as? AVAudioEngine) === engine else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.sessionDelivered, !self.micMuted else { return }
            self.stopVoiceAssistant()
            self.configureAudioSessionIfNeeded()
            self.startVoiceAssistant()
        }
    }

    private var audioSessionConfigured = false
    private func configureAudioSessionIfNeeded() {
        guard !audioSessionConfigured else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            audioSessionConfigured = true
        } catch {}
    }

    private var warnedAboutHeat = false
    @objc private func thermalStateChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.warnedAboutHeat else { return }
            let state = ProcessInfo.processInfo.thermalState
            guard state == .serious || state == .critical else { return }
            self.warnedAboutHeat = true
            self.showVoiceCaption("📱 Teléfono caliente - la cámara puede fallar")
            self.speak("El teléfono está caliente. Si la cámara se pone negra, deja enfriar el teléfono un momento.") {}
        }
    }

    private var voiceAssistantStartRequested = false
    private func startVoiceAssistantOnce() {
        guard !voiceAssistantStartRequested else { return }
        voiceAssistantStartRequested = true
        startVoiceAssistant()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        processingWatchdogTimer?.invalidate()
        processingWatchdogTimer = nil
        NotificationCenter.default.removeObserver(self, name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        if isSessionRunning {
            captureView.captureSession.stop()
            isSessionRunning = false
        }
        stopVoiceAssistant()
    }

    private func startCapturingRoom() {
        // A delete confirmation armed on the PREVIOUS room must not
        // survive into the next room's scan - without this, tapping
        // "Escanear otro cuarto" during the 6s window left it armed, and
        // any utterance starting with "sí" in the new room silently
        // deleted the previous one.
        deleteConfirmationTimer?.invalidate()
        deleteConfirmationTimer = nil
        pendingDeleteRoomIndex = nil
        // Lo mismo para la pregunta abierta del cuarto anterior: si quedara
        // armada, el primer "si" del cuarto NUEVO contestaria una pregunta
        // sobre el cuarto VIEJO.
        pendingDoneQuestion = nil
        // He said the next room's name mid-scan, but a missing-wall
        // warning held the auto-advance back. Carry the name forward so
        // he is not asked to repeat himself.
        if pendingCurrentRoomName == nil, let held = pendingRoomNameAfterGap {
            pendingCurrentRoomName = held
        }
        pendingRoomNameAfterGap = nil
        pendingMirroredPort = nil
        isSessionRunning = true
        state = .scanningRoom
        updateUI()
        let config = RoomCaptureSession.Configuration()
        captureView.captureSession.run(configuration: config)
    }

    @objc private func cancelTapped() {
        // Cancel during .finishingSession: the promise may already be
        // resolved (or a watchdog/merge is about to) - the delivery guard
        // makes cancel and a concurrent finish mutually exclusive.
        guard !sessionDelivered else { return }
        sessionDelivered = true
        finishingWatchdogTimer?.invalidate()
        finishingWatchdogTimer = nil
        // A manual whole-session cancel always wins over a pending room-
        // split question - discard the candidate rather than apply it.
        roomSplitConfirmationTimer?.invalidate()
        roomSplitConfirmationTimer = nil
        pendingRoomSplitCandidateName = nil
        // Any already-in-flight live-merge Task captured its own
        // generation number before this - bumping past it here guarantees
        // a late-arriving result is discarded as stale rather than
        // touching a view controller that's about to be dismissed.
        mergeGeneration += 1
        keyframeRecorder?.stopAndDeleteAll()
        keyframeRecorder = nil
        if isSessionRunning {
            captureView.captureSession.stop()
            isSessionRunning = false
        }
        stopVoiceAssistant()
        onFinish?(.cancelled)
    }

    @objc private func doneTapped() {
        // A manual "Listo" tap always wins over a pending room-split
        // question too - the tech tapping the button is a stronger,
        // more deliberate signal than whatever they were about to say.
        // (resolveRoomSplit(asNewRoom: true) already clears these before
        // calling doneTapped() itself, so this is a harmless no-op on
        // that path and a real safety net on the direct-tap path.)
        // The gate's question caption has its auto-hide suspended while
        // the question is open - discarding the gate here (not through
        // resolveRoomSplit, which shows its own follow-up caption) must
        // also hide it, or the stale question stays stuck on screen.
        if pendingRoomSplitCandidateName != nil { hideVoiceCaption() }
        roomSplitConfirmationTimer?.invalidate()
        roomSplitConfirmationTimer = nil
        pendingRoomSplitCandidateName = nil
        // Stopping with pauseARSession:false keeps the underlying ARSession
        // (world tracking) alive so the *next* room, if any, lands in the
        // same coordinate space - stopping the room capture is not the same
        // as pausing tracking. Apple's own finishing/refinement pass runs
        // next; the refined room comes back via captureView(didPresent:).
        // That overload only exists on iOS 17+ (matching StructureBuilder's
        // own minimum) - on iOS 16 there's no multi-room merge to preserve
        // anyway, so a plain stop() is the honest equivalent there.
        state = .processingRoom
        updateUI()
        // If RoomPlan's refinement pass never calls back (the camera/
        // session died mid-scan - reported in the field as "the camera
        // goes black"), don't hang on "Procesando…" forever: after 25s,
        // salvage whatever rooms already finished instead of losing the
        // whole walkthrough to a frozen screen.
        processingWatchdogTimer?.invalidate()
        processingWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            guard let self = self, self.state == .processingRoom else { return }
            self.autoContinueNextRoomName = nil
            if self.capturedRooms.isEmpty {
                guard !self.sessionDelivered else { return }
                self.sessionDelivered = true
                self.keyframeRecorder?.stopAndDeleteAll()
                self.keyframeRecorder = nil
                self.onFinish?(.cancelled)
            } else {
                // Mic torn down FIRST (its teardown deactivates the audio
                // session), then the session re-activated for this one
                // last announcement - the other order silenced it.
                self.stopVoiceAssistant()
                self.configureAudioSessionIfNeeded()
                self.speak("La cámara falló. Guardando los cuartos ya escaneados.") {}
                self.state = .finishingSession
                self.updateUI()
                self.requestFinishSession()
            }
        }
        if #available(iOS 17.0, *) {
            captureView.captureSession.stop(pauseARSession: false)
        } else {
            captureView.captureSession.stop()
        }
    }

    @objc private func scanAnotherTapped() {
        startCapturingRoom()
    }

    // Re-scan the room that just came back wrong. A SOFT delete, exactly
    // like the voice one: the rejected capture still ships flagged
    // deleted, so the web layer's Undo can bring it back if the re-scan
    // turns out worse. Its name is carried into the new capture.
    @objc private func repeatRoomTapped() {
        guard state == .roomDonePrompt, let index = capturedRooms.indices.last else { return }
        deletedRoomIndices.insert(index)
        showUndoDeleteChip(for: index)
        if pendingCurrentRoomName == nil, voiceNames.indices.contains(index) {
            pendingCurrentRoomName = voiceNames[index]
        }
        roomGapsByIndex[index] = nil
        roomCornersByIndex[index] = nil
        floorPlanPanelView.marcarEsquinas([])
        refreshLiveStructure()
        speak("Repitiendo \(roomLabel(for: index)).") {}
        startCapturingRoom()
    }

    // La esquina peor de un cuarto, para la voz y la tarjeta.
    private func peorEsquina(_ index: Int) -> FloorPlanEncoder.CornerFinding? {
        return (roomCornersByIndex[index] ?? []).max { $0.d < $1.d }
    }
    private func nombreDeEsquina(_ e: FloorPlanEncoder.CornerFinding) -> String {
        let a = Self.feetInchesText(e.wallALenFt), b = Self.feetInchesText(e.wallBLenFt)
        return a == b ? "una esquina entre dos paredes de \(a)" : "la esquina entre la pared de \(a) y la de \(b)"
    }

    @objc private func scanAnotherLevelTapped() {
        currentLevel += 1
        startCapturingRoom()
    }

    @objc private func finishTapped() {
        isSessionRunning = false
        state = .finishingSession
        // Invalidate any live-panel merge still in flight and drop its
        // queued rerun - finishSession() runs its own StructureBuilder,
        // and a stale live result landing mid-finish has nothing valid
        // left to update.
        mergeGeneration += 1
        mergeQueued = false
        updateUI()
        stopVoiceAssistant()
        requestFinishSession()
    }

    // Two concurrent StructureBuilder calls is the exact race the live
    // panel's single-flight design exists to prevent - if a live-panel
    // merge is still in flight, the final merge waits its turn (consumed
    // in the live merge's completion) instead of running alongside it.
    private var pendingFinishSession = false
    private func requestFinishSession() {
        if mergeInFlight {
            pendingFinishSession = true
            mergeQueued = false
        } else {
            finishSession()
        }
    }

    // StructureBuilder doesn't document that its output room order matches
    // the input order it was given, so levels/voice-names aren't matched
    // back up by array position - each merged room is matched to the
    // original pre-merge room it came from by checking which one shares
    // wall identifiers with it (RoomPlan keeps each wall/object's UUID
    // stable through the merge - it aligns coordinate spaces, it doesn't
    // regenerate element identity).
    private func originalRoomIndex(for mergedRoom: CapturedRoom) -> Int? {
        let mergedWallIds = Set(mergedRoom.walls.map { $0.identifier })
        for (idx, original) in capturedRooms.enumerated() {
            let originalWallIds = Set(original.walls.map { $0.identifier })
            if !mergedWallIds.isDisjoint(with: originalWallIds) {
                return idx
            }
        }
        return nil
    }

    // Falls back to level 1 if nothing matches, which should only happen
    // if the wall-identifier assumption above turns out to be wrong.
    private func levelForMergedRoom(_ mergedRoom: CapturedRoom) -> Int {
        guard let idx = originalRoomIndex(for: mergedRoom), roomLevels.indices.contains(idx) else { return 1 }
        return roomLevels[idx]
    }

    private func voiceNameForMergedRoom(_ mergedRoom: CapturedRoom) -> String? {
        guard let idx = originalRoomIndex(for: mergedRoom), voiceNames.indices.contains(idx) else { return nil }
        return voiceNames[idx]
    }

    private func equipmentForMergedRoom(_ mergedRoom: CapturedRoom) -> [String: EquipmentEntry] {
        guard let idx = originalRoomIndex(for: mergedRoom), roomEquipment.indices.contains(idx) else { return [:] }
        return roomEquipment[idx]
    }

    // Re-expresses deletedRoomIndices (indices into capturedRooms) as
    // indices into the merged structure's own room order, via the same
    // wall-identifier matching every other per-room fact already uses.
    private func deletedIndicesForMergedRooms(_ mergedRooms: [CapturedRoom]) -> Set<Int> {
        var result = Set<Int>()
        for (mergedIdx, room) in mergedRooms.enumerated() {
            if let originalIdx = originalRoomIndex(for: room), deletedRoomIndices.contains(originalIdx) {
                result.insert(mergedIdx)
            }
        }
        return result
    }

    // Every .finished outcome funnels through here: stop the walkthrough
    // recorder, run the coverage inspection on a background queue under a
    // hard 5-second watchdog (the inspection must never be able to cost
    // the user their scan - on timeout or error the plan ships untouched
    // with status "skipped"), then deliver on main. The inspection
    // projects against the PRE-MERGE per-room geometry (the exact
    // ARSession world space the poses were recorded in); its element ids
    // are the same surface UUIDs the encoder emits, which StructureBuilder
    // preserves through the merge - the same fact originalRoomIndex(for:)
    // already relies on.
    private func deliverFinished(rooms: [CapturedRoom], structure: Any?, merged: Bool,
                                 levels: [Int], voiceNames: [String?],
                                 equipment: [[String: EquipmentEntry]], deletedIndices: Set<Int>) {
        let preMergeRooms = capturedRooms
        let preMergeLevels = roomLevels
        let preMergeDeleted = deletedRoomIndices
        let recorder = keyframeRecorder
        keyframeRecorder = nil
        let newSessionDir = recorder?.sessionDir
        // Las esquinas que el teléfono avisó, por cuarto ENTREGADO (índice
        // del plano), para que Plan review diga "flagged on site". Viajan
        // dentro de la inspección; nunca mueven nada.
        var esquinasPorSalida: [String: [[String: Any]]] = [:]
        for (out, room) in rooms.enumerated() {
            guard let pre = originalRoomIndex(for: room), let lista = roomCornersByIndex[pre], !lista.isEmpty else { continue }
            esquinasPorSalida[String(out)] = lista.map { e in
                ["x": (Double(e.vertex.x) * 100).rounded() / 100, "y": (Double(e.vertex.y) * 100).rounded() / 100,
                 "d": (e.d * 100).rounded() / 100, "legA": (e.legA * 100).rounded() / 100, "legB": (e.legB * 100).rounded() / 100]
            }
        }
        let finish: ([String: Any]?) -> Void = { [weak self] inspectionIn in
            DispatchQueue.main.async {
                guard let self = self, !self.sessionDelivered else { return }
                var inspection = inspectionIn
                if !esquinasPorSalida.isEmpty {
                    var d = inspection ?? ["version": 1, "status": "skipped"]
                    d["scanCorners"] = esquinasPorSalida
                    inspection = d
                }
                self.sessionDelivered = true
                self.finishingWatchdogTimer?.invalidate()
                self.finishingWatchdogTimer = nil
                // This scan now replaces the saved plan - only ITS photos
                // are referenced from here on, so older sessions' photo
                // dirs finally become safe to remove.
                if let keep = newSessionDir { ScanKeyframeRecorder.cleanupOldSessions(keeping: keep) }
                self.onFinish?(.finished(rooms: rooms, structure: structure, merged: merged,
                                         levels: levels, voiceNames: voiceNames,
                                         equipment: equipment, deletedIndices: deletedIndices,
                                         inspection: inspection,
                                         surfaceAnswers: self.voiceSurfaceAnswers))
            }
        }
        guard let recorder = recorder else { finish(nil); return }
        // Las fotos, los elementos y el camino llevan el índice PRE-merge;
        // el plano entregado puede ir en otro orden (un cuarto rechazado en
        // medio). El mapa se arma AQUÍ, en main, con los mismos ids de
        // pared que ya casan niveles y nombres; se aplica al resultado.
        var mapaIndices: [Int: Int] = [:]
        for (out, room) in rooms.enumerated() {
            if let pre = originalRoomIndex(for: room) { mapaIndices[pre] = out }
        }
        var delivered = false
        var traceArrived = false
        let lock = NSLock()
        let isDelivered: () -> Bool = {
            lock.lock(); defer { lock.unlock() }
            return delivered
        }
        let deliverOnce: ([String: Any]?) -> Void = { inspection in
            lock.lock(); defer { lock.unlock() }
            guard !delivered else {
                NSLog("[RoomScan] late inspection result discarded (plan already delivered)")
                return
            }
            delivered = true
            finish(inspection)
        }
        recorder.stop { trace in
            NSLog("[RoomScan] recorder trace collected: %d poses, %d keyframes", trace.poses.count, trace.keyframes.count)
            lock.lock(); traceArrived = true; lock.unlock()
            DispatchQueue.global(qos: .userInitiated).async {
                // isDelivered doubles as the cancellation signal: once any
                // watchdog ships the plan, inspect stops burning a hot
                // phone's CPU on a result nobody will read.
                let inspection = ScanInspector.remapRoomIndices(
                    ScanInspector.inspect(rooms: preMergeRooms, deletedIndices: preMergeDeleted,
                                          levels: preMergeLevels, trace: trace,
                                          isCancelled: isDelivered),
                    mapa: mapaIndices)
                deliverOnce(inspection)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                deliverOnce(["version": 1, "status": "skipped", "reason": "inspect_timeout"])
            }
        }
        // Field-observed failure (console log 2026-08-29): StructureBuilder
        // merged 4 rooms in 0.19s, but recorder.stop's completion never ran -
        // the recorder's serial queue was wedged (stuck encode/frame read) -
        // so the MERGED plan sat undelivered until the 30s watchdog shipped
        // it unmerged. Delivery must never wait on that queue: if the trace
        // doesn't arrive fast, ship the merged plan without the photo check.
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            // Guards only the recorder handoff. Once the trace is in hand
            // the 5s inspect_timeout above governs - without this check, an
            // inspection merely slower than 3s was discarded and mislabeled
            // as a recorder stall.
            lock.lock()
            let stillWaitingOnRecorder = !traceArrived && !delivered
            lock.unlock()
            guard stillWaitingOnRecorder else { return }
            let diag = recorder.stallDiagnostic()
            NSLog("[RoomScan] recorder stalled - delivering without inspection (last activity: %@)", diag)
            deliverOnce(["version": 1, "status": "skipped", "reason": "recorder_stall", "detail": diag])
        }
    }

    private func finishSession() {
        // A finish requested before a cancel (or another delivery) landed
        // has nothing left to deliver to.
        guard !sessionDelivered else { return }
        // Quiet the recorder BEFORE StructureBuilder starts: its 2 Hz
        // arSession.currentFrame polling concurrent with the merge is the
        // prime suspect for the field-reported "Uniendo cuartos" hang
        // (merges were reliable before the recorder existed). The trace
        // is still collected later via stop() in deliverFinished.
        keyframeRecorder?.pauseTicking()
        guard !capturedRooms.isEmpty else {
            keyframeRecorder?.stopAndDeleteAll()
            keyframeRecorder = nil
            sessionDelivered = true
            onFinish?(.finished(rooms: [], structure: nil, merged: true, levels: [], voiceNames: [], equipment: [], deletedIndices: [], inspection: nil, surfaceAnswers: [:]))
            return
        }
        // Arm the finishing escape hatch: 30s covers a normal
        // StructureBuilder merge + inspection many times over; anything
        // longer is a hang, and the rooms ship unmerged instead of
        // never.
        finishingWatchdogTimer?.invalidate()
        finishingWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            guard let self = self, !self.sessionDelivered else { return }
            NSLog("[RoomScan] finishing watchdog fired - delivering %d rooms unmerged", self.capturedRooms.count)
            self.sessionDelivered = true
            self.keyframeRecorder?.stopAndDeleteAll()
            self.keyframeRecorder = nil
            self.onFinish?(.finished(rooms: self.capturedRooms, structure: nil, merged: false,
                                     levels: self.roomLevels, voiceNames: self.voiceNames,
                                     equipment: self.roomEquipment, deletedIndices: self.deletedRoomIndices,
                                     inspection: ["version": 1, "status": "skipped", "reason": "finish_watchdog"],
                                     surfaceAnswers: self.voiceSurfaceAnswers))
        }
        // A room the tech explicitly rejected must not steer the merge.
        // StructureBuilder aligns the WHOLE house from the rooms it is
        // given, so a bad room dragged the good ones with it - and the
        // plan delivered was not the plan he watched build in the live
        // panel, which has filtered deleted rooms since the day it
        // shipped (refreshLiveStructure, below). The count guard had the
        // same blind spot: scan 2, delete 1, finish ran a 2-room merge.
        //
        // The rejected captures are appended AFTER the merged rooms
        // rather than dropped, so the web layer's soft delete keeps its
        // Undo - a natively discarded room could never be restored in
        // the office. They sit in pre-merge space, but every renderer and
        // every total skips a room flagged deleted, so nothing draws them
        // in the wrong place.
        let keptIdx = capturedRooms.indices.filter { !deletedRoomIndices.contains($0) }
        let dropIdx = capturedRooms.indices.filter { deletedRoomIndices.contains($0) }
        guard keptIdx.count > 1 else {
            deliverFinished(rooms: capturedRooms, structure: nil, merged: true, levels: roomLevels, voiceNames: voiceNames, equipment: roomEquipment, deletedIndices: deletedRoomIndices)
            return
        }
        if #available(iOS 17.0, *) {
            let rooms = keptIdx.map { capturedRooms[$0] }
            let leftOut = dropIdx.map { capturedRooms[$0] }
            NSLog("[RoomScan] final merge starting: %d rooms (%d rejected, kept out of the merge)", rooms.count, leftOut.count)
            Task { [weak self] in
                do {
                    // StructureBuilder merges already-refined CapturedRoom
                    // values (not raw CapturedRoomData) into one aligned
                    // CapturedStructure - confirmed via Apple's WWDC23
                    // RoomPlan session and developer-forum guidance. Exact
                    // initializer/options to confirm against the installed
                    // SDK headers when this first builds; an empty options
                    // set is a safe default if none apply.
                    let builder = StructureBuilder(options: [])
                    let structure = try await builder.capturedStructure(from: rooms)
                    NSLog("[RoomScan] final merge completed: %d merged rooms", structure.rooms.count)
                    await MainActor.run {
                        guard let self = self else { return }
                        // Merged rooms first, then the rejected captures.
                        // levelForMergedRoom / voiceNameForMergedRoom /
                        // equipmentForMergedRoom all resolve through
                        // originalRoomIndex(for:), i.e. by WALL UUID and
                        // never by array position, so they are correct for
                        // both halves of this list.
                        let outRooms = structure.rooms + leftOut
                        let levels = outRooms.map { self.levelForMergedRoom($0) }
                        let names = outRooms.map { self.voiceNameForMergedRoom($0) }
                        let equipment = outRooms.map { self.equipmentForMergedRoom($0) }
                        let deleted = Set(structure.rooms.count ..< outRooms.count)
                        self.deliverFinished(rooms: outRooms, structure: structure, merged: true, levels: levels, voiceNames: names, equipment: equipment, deletedIndices: deleted)
                    }
                } catch {
                    NSLog("[RoomScan] final merge threw: %@", String(describing: error))
                    // Honest fallback: if the merge fails (e.g. tracking
                    // broke between rooms), hand back each room on its own
                    // rather than guessing how they connect.
                    await MainActor.run {
                        guard let self = self else { return }
                        self.deliverFinished(rooms: rooms, structure: nil, merged: false, levels: self.roomLevels, voiceNames: self.voiceNames, equipment: self.roomEquipment, deletedIndices: self.deletedRoomIndices)
                    }
                }
            }
        } else {
            // No StructureBuilder before iOS 17 - each room stays at its
            // own local origin, honestly flagged as unmerged.
            deliverFinished(rooms: capturedRooms, structure: nil, merged: false, levels: roomLevels, voiceNames: voiceNames, equipment: roomEquipment, deletedIndices: deletedRoomIndices)
        }
    }

    // MARK: - Live plan panel

    // Grows the live plan panel by exactly the room(s) captured so far.
    // Called ONLY from captureView(didPresent:) (once a room's real
    // geometry has actually arrived) and from the delete/undo sites (so
    // a deleted room disappears, an undone one reappears) - never from
    // the stop/start trigger, so the panel never blanks or resets
    // mid-transition. StructureBuilder's only public surface is
    // capturedStructure(from: [CapturedRoom]) - there's no incremental/
    // delta API - so every call recomputes over the FULL current room
    // set; single-flight with at most one coalesced pending rerun bounds
    // concurrent StructureBuilder calls to exactly one at all times,
    // however fast rooms finish (never a stacked/overlapping merge).
    private func refreshLiveStructure() {
        // Once the session is finishing, the live panel is done - and
        // kicking off another live merge here would race finishSession()'s
        // own StructureBuilder call (the single-flight bookkeeping only
        // covers LIVE merges, not the final one).
        guard state != .finishingSession else { return }
        let visibleIndices = capturedRooms.indices.filter { !deletedRoomIndices.contains($0) }
        let visibleRooms = visibleIndices.map { capturedRooms[$0] }

        guard !visibleRooms.isEmpty else {
            // Every synchronous panel update also invalidates any merge
            // still in flight - without this, voice-deleting a room down
            // to 0/1 visible while a 2-room merge was still computing let
            // that stale result land afterward and resurrect the deleted
            // room on the panel.
            mergeGeneration += 1
            liveStructureRooms = []
            liveMerged = true
            floorPlanPanelView.update(rooms: [], merged: true)
            return
        }
        guard visibleRooms.count > 1 else {
            mergeGeneration += 1
            let idx = visibleIndices[0]
            let name = voiceNames.indices.contains(idx) ? voiceNames[idx] : nil
            liveStructureRooms = [roomSketch(for: visibleRooms[0], name: name)]
            liveMerged = true
            floorPlanPanelView.update(rooms: liveStructureRooms, merged: true)
            return
        }
        guard #available(iOS 17.0, *) else {
            mergeGeneration += 1
            applyTiledFallback(visibleRooms: visibleRooms, visibleIndices: visibleIndices)
            return
        }
        guard !mergeInFlight else {
            // Invalidate the in-flight result too: it was computed over a
            // room set that just changed (e.g. a deletion) - without this
            // bump, the stale merge repainted a just-deleted room and only
            // the queued rerun then corrected it.
            mergeGeneration += 1
            mergeQueued = true
            return
        }
        mergeInFlight = true
        mergeGeneration += 1
        let myGeneration = mergeGeneration
        let snapshot = visibleRooms
        Task { [weak self] in
            do {
                let structure = try await StructureBuilder(options: []).capturedStructure(from: snapshot)
                await MainActor.run {
                    guard let self = self else { return }
                    self.mergeInFlight = false
                    if myGeneration == self.mergeGeneration {
                        let sketches = structure.rooms.map { room in
                            self.roomSketch(for: room, name: self.voiceNameForMergedRoom(room))
                        }
                        self.liveStructureRooms = sketches
                        self.liveMerged = true
                        self.floorPlanPanelView.update(rooms: sketches, merged: true)
                    }
                    if self.pendingFinishSession {
                        self.pendingFinishSession = false
                        self.finishSession()
                        return
                    }
                    self.drainQueuedMergeIfNeeded()
                }
            } catch {
                // Honest fallback for the live panel too, same as
                // finishSession()'s own catch - never guess a connection.
                await MainActor.run {
                    guard let self = self else { return }
                    self.mergeInFlight = false
                    if myGeneration == self.mergeGeneration {
                        self.applyTiledFallback(visibleRooms: snapshot, visibleIndices: visibleIndices)
                    }
                    if self.pendingFinishSession {
                        self.pendingFinishSession = false
                        self.finishSession()
                        return
                    }
                    self.drainQueuedMergeIfNeeded()
                }
            }
        }
    }

    private func drainQueuedMergeIfNeeded() {
        guard mergeQueued else { return }
        mergeQueued = false
        refreshLiveStructure()
    }

    // iOS 16 (no StructureBuilder) or a failed merge attempt - each room
    // tiled left-to-right at a fixed margin so they never overlap or
    // claim a false adjacency, the same honest "not really combined"
    // shape finishSession() itself already uses for the final plan.
    private func applyTiledFallback(visibleRooms: [CapturedRoom], visibleIndices: [Int]) {
        var cursorX: CGFloat = 0
        let margin: CGFloat = 3
        var sketches: [RoomSketch] = []
        for (i, room) in visibleRooms.enumerated() {
            let idx = visibleIndices[i]
            let name = voiceNames.indices.contains(idx) ? voiceNames[idx] : nil
            let raw = roomSketch(for: room, name: name)
            guard !raw.walls.isEmpty else { sketches.append(raw); continue }
            let xs = raw.walls.flatMap { [$0.0.x, $0.1.x] }
            let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
            let shift = cursorX - minX
            let shifted = RoomSketch(name: raw.name, walls: raw.walls.map {
                (CGPoint(x: $0.0.x + shift, y: $0.0.y), CGPoint(x: $0.1.x + shift, y: $0.1.y))
            })
            sketches.append(shifted)
            cursorX = maxX + shift + margin
        }
        liveStructureRooms = sketches
        liveMerged = false
        floorPlanPanelView.update(rooms: sketches, merged: false)
    }

    // Converts one CapturedRoom's real wall geometry into feet-space line
    // segments, reusing FloorPlanEncoder's exact wall-endpoint math and
    // meters-to-feet conversion (not a second, parallel implementation)
    // so a room's shape here matches the final exported plan.
    private func roomSketch(for room: CapturedRoom, name: String?) -> RoomSketch {
        let f = FloorPlanEncoder.metersToFeet
        let walls: [(CGPoint, CGPoint)] = room.walls.map { wall in
            let (start, end) = FloorPlanEncoder.wallEndpoints(wall)
            return (CGPoint(x: Double(start.x) * f, y: Double(start.y) * f),
                    CGPoint(x: Double(end.x) * f, y: Double(end.y) * f))
        }
        return RoomSketch(name: name, walls: walls)
    }

    // MARK: - RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        return true
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        // A late RoomPlan callback - after the finishing watchdog already
        // resolved the session, or after Cancelar - must not append rooms
        // or re-enter the finish path (double-resolve / corrupted state).
        guard state == .processingRoom, !sessionDelivered else { return }
        processingWatchdogTimer?.invalidate()
        processingWatchdogTimer = nil
        if let error = error {
            // Defensive: a RoomPlan processing failure during a voice-
            // triggered split must not leave a stale flag armed to misfire
            // on some later, unrelated room completion.
            autoContinueNextRoomName = nil
            NSLog("[RoomScan] didPresent error: %@ (room walls: %d)", String(describing: error), processedResult.walls.count)
            // RoomPlan hands over the processed room even alongside an
            // error - if it has real geometry, KEEP it and let the tech
            // decide (re-scan it, continue, or finish) instead of
            // force-ending the whole walkthrough over one room's error.
            if !processedResult.walls.isEmpty {
                speak("Este cuarto tuvo un problema al procesarse. Revísalo, o vuelve a escanearlo.") {}
            } else if capturedRooms.isEmpty {
                // First room, nothing usable: nothing to salvage.
                keyframeRecorder?.stopAndDeleteAll()
                keyframeRecorder = nil
                sessionDelivered = true
                onFinish?(.cancelled)
                return
            } else {
                // Unusable room but earlier rooms succeeded - finish with
                // what we have rather than losing the whole walkthrough.
                speak("La cámara falló en este cuarto. Guardando los cuartos ya escaneados.") {}
                state = .finishingSession
                updateUI()
                requestFinishSession()
                return
            }
        }
        capturedRooms.append(processedResult)
        roomLevels.append(currentLevel)
        voiceNames.append(pendingCurrentRoomName)
        pendingCurrentRoomName = nil
        roomEquipment.append(pendingCurrentEquipment)
        pendingCurrentEquipment = [:]
        // Grows the live plan panel by exactly this one room - never
        // called from the stop/start trigger, only from here, once this
        // room's real geometry has actually arrived.
        refreshLiveStructure()
        // Does this room's outline actually CLOSE? Computed synchronously,
        // right here, on purpose: it is arithmetic over the wall endpoints
        // already in hand (tens of points, microseconds, no allocation, no
        // queue, no session call), and a missing-wall warning must not be
        // hostage to the recorder's pose queue - that queue has wedged in
        // the field, which is why the 3s stall guard exists.
        //
        // A gap another wall already covers is not a gap. Own-room walls
        // are enough: pre-merge there is nothing else, and on the real
        // house own-room recovery reproduces the post-merge answer.
        let sketchWalls = roomSketch(for: processedResult, name: nil).walls
        let openGaps = FloorPlanEncoder.outlineGaps(wallsFt: sketchWalls)
            .filter { $0.ft > FloorPlanEncoder.outlineGapWarnFt
                      && !FloorPlanEncoder.gapCoveredByWalls($0, walls: sketchWalls) }
        roomGapsByIndex[capturedRooms.count - 1] = openGaps.map { $0.ft }
        // LAS ESQUINAS QUE NO CERRARON: misma aritmética que el chequeo de
        // huecos, con las puertas, ventanas y aberturas de este cuarto para
        // no confundir un paso con una esquina. Solo se avisa; el plano
        // propone cerrarla (o la cierra sola si es chica) - ver
        // fpCornerFindings en www/index.html.
        let f = FloorPlanEncoder.metersToFeet
        let portsFt: [(center: CGPoint, widthFt: Double)] = (processedResult.doors + processedResult.windows + processedResult.openings).map { p in
            let t = p.transform
            return (center: CGPoint(x: Double(t.columns.3.x) * f, y: Double(t.columns.3.z) * f),
                    widthFt: Double(p.dimensions.x) * f)
        }
        let esquinas = FloorPlanEncoder.cornerFindings(wallsFt: sketchWalls, portsFt: portsFt)
        roomCornersByIndex[capturedRooms.count - 1] = esquinas
        floorPlanPanelView.marcarEsquinas(esquinas.map { $0.vertex })
        if !esquinas.isEmpty {
            NSLog("[RoomScan] open corners in room %d: %@", capturedRooms.count - 1,
                  esquinas.map { String(format: "%.1fft (legs %.1f/%.1f)", $0.d, $0.legA, $0.legB) }.joined(separator: ", "))
        }
        // Una puerta que ESTE cuarto (o uno anterior) modelo y su vecino no.
        // Misma clase de arithmetic que el chequeo de contorno: sobre la
        // geometria ya en la mano, en main, en microsegundos, sin poses.
        let mirrored = ScanInspector.mirroredPortCheck(rooms: capturedRooms,
                                                       deletedIndices: deletedRoomIndices,
                                                       levels: roomLevels,
                                                       alreadyReported: reportedMirroredPorts)
        if let m = mirrored.first {
            reportedMirroredPorts.insert(m.portId)
            pendingMirroredPort = m
            NSLog("[RoomScan] mirrored port: %@ %.2fft room %d not in room %d (%.4f ft)",
                  m.isDoor ? "door" : "opening", m.widthFt, m.ownerRoomIndex, m.otherRoomIndex, m.distFt)
        }
        if !openGaps.isEmpty {
            NSLog("[RoomScan] outline gaps in room %d: %@", capturedRooms.count - 1,
                  openGaps.map { String(format: "%.1fft", $0.ft) }.joined(separator: ", "))
        }
        // AI scan coach: score how well the camera actually covered the
        // room that just finished, from the pose trace so far - shown as
        // a live percentage on the room-done card, with a spoken rescan
        // hint when coverage is thin. Background math, main-thread UI.
        let coverageRoomIndex = capturedRooms.count - 1
        keyframeRecorder?.snapshotPoses { [weak self] poses in
            let result = ScanInspector.quickRoomCoverage(room: processedResult,
                                                         roomIndex: coverageRoomIndex,
                                                         poses: poses)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.roomCoverageByIndex[coverageRoomIndex] = (result.percent, result.total,
                                                               result.wellSeen, result.worstType,
                                                               result.worstLengthFt)
                // The state guard used to sit here, so on the voice
                // auto-continue path - which returns BEFORE the state ever
                // reaches .roomDonePrompt - the number was computed,
                // stored, and never spoken or shown. That is the path the
                // app pushes hardest. Now the room is named out loud
                // instead, so a warning can never be about a room he has
                // already walked out of without knowing which one.
                guard self.state != .finishingSession,
                      self.capturedRooms.count - 1 == coverageRoomIndex else { return }
                self.updateUI()
                guard result.percent < 70, result.total >= 4 else { return }
                // ONE spoken warning per room. If a wall is missing, that
                // is strictly more actionable than thin coverage, and two
                // warnings about the same room teach him to ignore the
                // second. The card still carries both lines.
                if let g = self.roomGapsByIndex[coverageRoomIndex], !g.isEmpty { return }
                if self.peorEsquina(coverageRoomIndex) != nil { return }
                let hint = result.worstType.map { t -> String in
                    // "Una pared casi no se vio" identified nothing in a
                    // room with four unseen walls. Its length does.
                    if let ft = result.worstLengthFt, ft > 1 {
                        return "La \(t) de \(Self.feetInchesText(ft)) casi no se vio. "
                    }
                    return "Una \(t) casi no se vio. "
                } ?? ""
                let past = self.state == .roomDonePrompt
                    ? "este cuarto" : "el cuarto anterior, \(self.roomLabel(for: coverageRoomIndex))"
                self.showVoiceCaption("Cámara: \(result.wellSeen) de \(result.total) bien vistas")
                // Este aviso llega TARDE y sin horario fijo: el conteo de
                // cobertura se calcula en segundo plano, asi que puede caer
                // despues de que el asistente ya dejo una pregunta hecha.
                // Hablar encima de una pregunta abierta deja al tecnico sin
                // saber que le estan preguntando, asi que el aviso se dice
                // y en seguida se REPITE la pregunta: lo ultimo que oye
                // vuelve a ser lo que tiene que contestar.
                let abierta = self.pendingDoneQuestion
                self.pendingDoneQuestion = nil
                self.speak("La cámara vio bien \(result.wellSeen) de \(result.total) paredes, puertas y ventanas de \(past). \(hint)Puedes escanearlo otra vez antes de seguir.") {}
                switch abierta {
                case .repeatRoom?:        self.ask(.repeatRoom, "¿Lo escaneamos otra vez?")
                case .confirmName(let g)?: self.ask(.confirmName(g), "¿Es \(Self.spokenWithArticle(g))?")
                case .askName?:            self.ask(.askName, "¿Como se llama este cuarto?")
                case .openingIsDoor?:      self.ask(.openingIsDoor, "¿Esa abertura es una puerta?")
                case .nextRoom?:           self.askNextRoomQuestion(prefix: "")
                case nil:                  break
                }
            }
        }
        // A voice-confirmed "cuarto nuevo" already answered the only
        // question .roomDonePrompt exists to ask - skip it and go
        // straight back into scanning the next room, pre-named with what
        // the tech already said, instead of making them tap through a
        // screen that would just be asking them to repeat themselves.
        // A gap cancels the auto-continue. The whole point of catching a
        // missing wall while he is still standing in the room is that he
        // can re-sweep it NOW - marching him into the next room is
        // exactly the wrong outcome. He lands on the room-done card with
        // the warning instead, and the name he said is kept.
        let gapsHere = roomGapsByIndex[capturedRooms.count - 1] ?? []
        // Una esquina abierta de 2 ft o más también frena el auto-continuar:
        // se le va a preguntar si repite, y eso no se pregunta desde el
        // cuarto siguiente.
        let esquinaGrande = (peorEsquina(capturedRooms.count - 1)?.d ?? 0) >= 2
        if let nextName = autoContinueNextRoomName, gapsHere.isEmpty, !esquinaGrande {
            autoContinueNextRoomName = nil
            pendingCurrentRoomName = nextName
            // A short breather before re-running the capture session -
            // calling run() synchronously INSIDE RoomPlan's own
            // completion callback (which only the voice auto-continue
            // path did; a manual tap always had human delay built in) is
            // the prime suspect for the camera going black after a few
            // voice-driven room transitions.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                // Still waiting where we left off? (Cancelar/dismissal in
                // the meantime changes nothing here - don't restart over it.)
                guard let self = self, self.state == .processingRoom else { return }
                self.startCapturingRoom()
            }
            showVoiceCaption(nextName)
            speak("Escaneando \(nextName).") {}
            return
        }
        if autoContinueNextRoomName != nil {
            // Held back by a gap: keep the name he already said so he is
            // not asked to repeat himself, and drop the auto-advance.
            pendingRoomNameAfterGap = autoContinueNextRoomName
            autoContinueNextRoomName = nil
        }
        state = .roomDonePrompt
        updateUI()
        // Se habla, no solo se pintan botones: el tecnico trae el telefono
        // en alto y las manos ocupadas. Pero UNA pregunta a la vez.
        //
        // Orden: primero lo urgente (un cuarto al que le falta un lado hay
        // que repetirlo AHORA, estando parado en el), despues el nombre,
        // y hasta el final el paso al siguiente cuarto.
        if !gapsHere.isEmpty {
            let worst = gapsHere.max() ?? 0
            let lados = gapsHere.count == 1
                ? "le falta un lado, un hueco de unos \(Self.feetInchesText(worst))"
                : "le faltan \(gapsHere.count) lados, el mayor de unos \(Self.feetInchesText(worst))"
            showVoiceCaption("⚠︎ Falta un lado de este cuarto")
            ask(.repeatRoom, "Cuarto guardado. Ojo: a este cuarto \(lados). ¿Lo escaneamos otra vez?")
            return
        }
        // LA ESQUINA QUE NO CERRÓ. Un hueco grande gana (arriba); después la
        // esquina, UNA por cuarto, la peor. De 2 ft para arriba se pregunta
        // si repite, porque el remedio bueno es apuntarle desde los dos
        // lados estando parado ahí; de 1 a 2 ft solo se avisa y sigue el
        // flujo - en el plano se propone cerrada, y ella decide.
        if let esq = peorEsquina(capturedRooms.count - 1) {
            let nombre = nombreDeEsquina(esq)
            if esq.d >= 2 {
                showVoiceCaption("⚠︎ Esquina sin cerrar \(Self.feetInchesText(esq.d))")
                ask(.repeatRoom, "Cuarto guardado. Ojo: \(nombre) no cerró; le faltan como \(Self.feetInchesText(esq.d)). Si lo repites, párate en esa esquina y apúntale desde los dos lados. ¿Lo escaneamos otra vez?")
                return
            }
            showVoiceCaption("Esquina abierta \(Self.feetInchesText(esq.d))")
            speak("Cuarto guardado. \(nombre) quedó abierta como \(Self.feetInchesText(esq.d)). En el plano te la propongo cerrada.") {}
        }
        // Todo cuarto tiene por donde entrar. Si el escaner no vio NI UNA
        // puerta ni una abertura, no es que el cuarto no tenga: es que esa
        // pared se quedo sin escanear. Se pregunta aqui, mientras sigue
        // parado adentro y todavia se puede arreglar.
        if let ultimo = capturedRooms.indices.last,
           capturedRooms[ultimo].doors.isEmpty, capturedRooms[ultimo].openings.isEmpty,
           !capturedRooms[ultimo].walls.isEmpty {
            showVoiceCaption("⚠︎ Ninguna puerta detectada")
            ask(.repeatRoom, "Cuarto guardado. Ojo: no vi ninguna puerta en este cuarto. ¿Lo escaneamos otra vez?")
            return
        }
        if let m = pendingMirroredPort {
            // Una sola advertencia hablada por cuarto: si ya hay un hueco
            // en el contorno, ese es mas urgente y este se queda en la
            // tarjeta. Nunca dos avisos seguidos sobre el mismo cuarto -
            // eso enseña a ignorar el segundo.
            //
            // Se dice como AVISO, no como pregunta: antes ofrecia "puedes
            // volver a ese cuarto" y esa orden NO EXISTE por voz - solo se
            // puede repetir el ultimo cuarto, no uno de mas atras. Prometer
            // algo que la app no puede hacer es peor que no decir nada.
            let que = m.isDoor ? "una puerta" : "una abertura"
            speak("Cuarto guardado. Ojo: \(roomLabel(for: m.ownerRoomIndex)) tiene \(que) que \(roomLabel(for: m.otherRoomIndex)) no agarro. Revisalo al final.") { [weak self] in
                self?.askRoomNameQuestion(prefix: "")
            }
            return
        }
        askRoomNameQuestion(prefix: "Cuarto guardado. ")
    }

    // MARK: - La conversacion de fin de cuarto

    // Deja UNA pregunta abierta y la dice. La ventana para contestar se
    // abre cuando la frase TERMINA de sonar, no mientras suena: el micro
    // descarta audio mientras el telefono habla (isSpeakingConfirmation),
    // asi que armarla antes seria darle al tecnico cero tiempo real.
    //
    // No lleva temporizador a proposito. Si nadie contesta, la tarjeta con
    // los botones sigue en pantalla y no pasa nada: aqui el silencio no
    // tiene que decidir nada, al reves que en la pregunta de cuarto-nuevo,
    // donde callar TIENE que resolverse por el lado que no pierde datos.
    private func ask(_ question: DoneQuestion, _ phrase: String) {
        pendingDoneQuestion = nil
        speak(phrase) { [weak self] in
            guard let self = self, self.state == .roomDonePrompt else { return }
            self.pendingDoneQuestion = question
        }
    }

    // El nombre: la app PROPONE y el aprueba, en vez de preguntar a ciegas.
    // Solo puede proponer aqui, al final del cuarto - al empezarlo RoomPlan
    // todavia no ha visto un solo mueble y no habria con que adivinar.
    private func askRoomNameQuestion(prefix: String) {
        guard let index = capturedRooms.indices.last else {
            askNextRoomQuestion(prefix: prefix); return
        }
        // Ya tiene nombre (lo dijo mientras escaneaba): no se vuelve a
        // preguntar lo que ya contesto.
        if let existing = voiceNames.indices.contains(index) ? voiceNames[index] : nil,
           !existing.trimmingCharacters(in: .whitespaces).isEmpty {
            askNextRoomQuestion(prefix: prefix)
            return
        }
        if let guess = suggestedRoomName(for: capturedRooms[index]) {
            let visto = seenFixturePhrase(for: capturedRooms[index])
            ask(.confirmName(guess), "\(prefix)\(visto)¿Es \(Self.spokenWithArticle(guess))?")
        } else {
            ask(.askName, "\(prefix)¿Como se llama este cuarto?")
        }
    }

    private func askNextRoomQuestion(prefix: String) {
        // Antes de pasar al siguiente cuarto, lo que quedo sin resolver de
        // ESTE - preguntado aqui a proposito, mientras todavia esta parado
        // adentro y le puede echar un ojo a la pared.
        if let (id, ancho) = nextUnansweredOpening() {
            pendingOpeningId = id
            ask(.openingIsDoor, "\(prefix)Vi una abertura de \(ancho). ¿Es una puerta?")
            return
        }
        ask(.nextRoom, "\(prefix)¿Vamos al siguiente cuarto?")
    }

    // Una abertura es un hueco en la pared que RoomPlan NO pudo llamar ni
    // puerta ni ventana. En un plano de seguro no es lo mismo un vano de
    // puerta que un hueco cualquiera, y el que esta adentro lo sabe de un
    // vistazo. Solo se pregunta por las anchas: un hueco de menos de dos
    // pies no es una puerta y preguntarlo seria hacerle perder el tiempo.
    private func nextUnansweredOpening() -> (String, String)? {
        guard let room = capturedRooms.indices.last.map({ capturedRooms[$0] }) else { return nil }
        for op in room.openings {
            let id = op.identifier.uuidString
            if voiceSurfaceAnswers[id] != nil { continue }
            let anchoFt = Double(op.dimensions.x) * 3.28084
            guard anchoFt >= 2.0, anchoFt <= 6.0 else { continue }
            return (id, Self.feetInchesText(anchoFt))
        }
        return nil
    }

    // "Veo una lavadora. " - el POR QUE de la propuesta, en una frase.
    // Sin esto la app suena adivina; con esto el tecnico entiende en que
    // se fijo y puede corregirla con confianza.
    private func seenFixturePhrase(for room: CapturedRoom) -> String {
        let cats = room.objects.map { String(describing: $0.category) }
        for (cat, nombre) in Self.spokenFixtureNames where cats.contains(cat) {
            return "Veo \(nombre). "
        }
        return ""
    }
    // "¿Es cuarto de lavado?" suena a maquina. Lleva articulo o no se dice.
    private static func spokenWithArticle(_ name: String) -> String {
        let el: Set<String> = ["Baño", "Cuarto de lavado", "Comedor"]
        return (el.contains(name) ? "el " : "la ") + name.lowercased()
    }
    private static let spokenFixtureNames: [(String, String)] = [
        ("washerDryer", "una lavadora"), ("toilet", "un inodoro"), ("bathtub", "una tina"),
        ("stove", "una estufa"), ("oven", "un horno"), ("refrigerator", "un refrigerador"),
        ("dishwasher", "un lavaplatos"), ("bed", "una cama"), ("sofa", "un sofa"),
        ("television", "una television"), ("fireplace", "una chimenea"), ("sink", "un lavamanos"),
        ("table", "una mesa")
    ]

    // Contesta la pregunta abierta. Devuelve true si la consumio, para que
    // el resto del reconocedor no vuelva a tratar el mismo "si" como si
    // fuera el nombre de un cuarto.
    private func answerDoneQuestion(yes: Bool) -> Bool {
        guard let q = pendingDoneQuestion else { return false }
        pendingDoneQuestion = nil
        switch q {
        case .repeatRoom:
            if yes { repeatRoomTapped() }
            else {
                // Si lo que se preguntó fue por una esquina, se le dice qué
                // va a pasar: no se promete cerrarla sola.
                let porEsquina = (roomGapsByIndex[capturedRooms.count - 1] ?? []).isEmpty && peorEsquina(capturedRooms.count - 1) != nil
                askRoomNameQuestion(prefix: porEsquina ? "Ok. En el plano te la propongo cerrada. " : "")
            }
        case .confirmName(let guess):
            if yes {
                applyHeardOrTappedName(guess, viaButton: false)  // dice "Entendido, X."
                askNextRoomQuestion(prefix: "")
            } else {
                ask(.askName, "Ok. ¿Como se llama?")
            }
        case .askName:
            // Un si/no no es un nombre. Se repite la pregunta en vez de
            // bautizar un cuarto "Si".
            ask(.askName, "Dime el nombre del cuarto.")
        case .openingIsDoor:
            if let id = pendingOpeningId {
                // Se guarda la respuesta sea cual sea: un "no" tambien es
                // informacion, y ademas evita volver a preguntar por el
                // mismo hueco en el siguiente paso.
                voiceSurfaceAnswers[id] = yes ? "door" : "opening"
                pendingOpeningId = nil
            }
            showVoiceCaption(yes ? "Puerta ✓" : "Abertura ✓")
            askNextRoomQuestion(prefix: "")
        case .nextRoom:
            if yes {
                scanAnotherTapped()
            } else {
                speak("Ok, aqui te espero. Di terminar cuando quieras cerrar el plano.") {}
            }
        }
        return true
    }

    // MARK: - Voice assistant

    // Applies a name (heard or tapped) to whichever room is relevant right
    // now. Voice is only accepted while a room is actively being scanned,
    // NOT during the few seconds RoomPlan spends finalizing it after
    // "Listo" is tapped - a real bug had that window still open, so
    // casual talk/movement right after finishing a room could silently
    // overwrite the correct name moments before it was saved. A button
    // tap is always a deliberate action, never incidental, so it stays
    // accepted through that same window. Once the room-done card is
    // showing, the same action corrects that room's name directly and
    // refreshes the card immediately.
    private func applyHeardOrTappedName(_ name: String, viaButton: Bool) {
        // A deliberate tap always resolves an open room-split question
        // immediately as a plain rename, never as a new room - only
        // "Cuarto nuevo" (voice or its own button) can ever split a room.
        if viaButton, pendingRoomSplitCandidateName != nil {
            roomSplitConfirmationTimer?.invalidate()
            roomSplitConfirmationTimer = nil
            pendingRoomSplitCandidateName = nil
            updateUI()
        }
        switch state {
        case .scanningRoom, .processingRoom:
            if case .processingRoom = state, !viaButton { return }
            // A genuinely DIFFERENT name heard BY VOICE while this room
            // already has one is ambiguous - it could be a correction, or
            // it could mean the tech has moved to a new room (RoomPlan
            // itself has no way to detect a room-boundary crossing mid-
            // scan - see startCapturingRoom). Never silently overwrite:
            // ask instead of guessing which one it is.
            if !viaButton, state == .scanningRoom, let existing = pendingCurrentRoomName, existing != name {
                requestRoomSplitConfirmation(candidateName: name)
                return
            }
            // Distinguishes "first name heard for this room" from
            // "renaming what I already have" so the spoken confirmation
            // can say which one happened.
            let isRename = pendingCurrentRoomName != nil && pendingCurrentRoomName != name
            pendingCurrentRoomName = name
            showVoiceCaption(name)
            confirmName(name, isRename: isRename)
        case .roomDonePrompt:
            guard let index = capturedRooms.indices.last else { return }
            if viaButton {
                roomsNamedByButton.insert(index)
            } else {
                roomsNamedByButton.remove(index)
            }
            let isRename = voiceNames.indices.contains(index) && voiceNames[index] != nil && voiceNames[index] != name
            voiceNames[index] = name
            updateUI()
            // Si lo que estaba abierto era justo la pregunta del nombre,
            // acaba de quedar contestada: se sigue solo al siguiente cuarto
            // en vez de dejarlo esperando a ver si la app dice algo mas.
            var chainNext = false
            if case .askName = pendingDoneQuestion {
                chainNext = true
                pendingDoneQuestion = nil
            }
            confirmName(name, isRename: isRename)
            if chainNext { askNextRoomQuestion(prefix: "") }
        case .finishingSession:
            break
        }
    }

    // Spoken "Entendido, X" (or "Cambié el nombre a X" when replacing an
    // already-set name) - the audible half of confirming a heard/tapped
    // name, on top of the on-screen caption. Muting the mic tap for the
    // duration (isSpeakingConfirmation) stops the continuous recognizer
    // from picking up this exact phrase through the phone's own speaker
    // and mistaking it for a new room name.
    private func confirmName(_ name: String, isRename: Bool) {
        let phrase = isRename ? "Cambié el nombre a \(name)." : "Entendido, \(name)."
        speak(phrase) {}
    }

    // Opens the room-split ambiguity question. Capture keeps running,
    // completely untouched, for as long as this is open - the ONLY way
    // out of it that can ever lead to captureSession.stop() being called
    // is an explicit, separate, positive "cuarto nuevo" signal
    // (resolveRoomSplit(asNewRoom: true)), never silence and never the
    // mere act of asking the question.
    private func requestRoomSplitConfirmation(candidateName: String) {
        pendingRoomSplitCandidateName = candidateName
        updateUI()
        roomSplitConfirmationTimer?.invalidate()
        roomSplitConfirmationTimer = nil
        // The 6s answer window starts AFTER the spoken question finishes,
        // not concurrently with it - the mic tap discards audio while the
        // phone itself is talking (isSpeakingConfirmation), so a timer
        // racing the question's own ~5s of speech left effectively zero
        // real time to answer by voice: the gate always timed out to
        // rename and a genuinely-moved tech's next room got scanned into
        // the previous room. The completion is safe to rely on now that
        // completions are per-utterance (speechCompletions).
        speak("¿'\(candidateName)' es un cuarto nuevo, o corrijo el nombre de este cuarto? Di cuarto nuevo, o corrige.") { [weak self] in
            guard let self = self, self.pendingRoomSplitCandidateName == candidateName else { return }
            self.roomSplitConfirmationTimer?.invalidate()
            self.roomSplitConfirmationTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
                self?.resolveRoomSplit(asNewRoom: false)
            }
        }
        // BACKSTOP: if the utterance is cancelled or the synthesizer
        // stalls, its completion never fires and the gate would stay
        // armed forever, swallowing later room names. 15s covers the
        // spoken question + the 6s window with margin; whichever timer
        // lands first resolves (safe branch), the other is invalidated.
        roomSplitConfirmationTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            guard let self = self, self.pendingRoomSplitCandidateName == candidateName else { return }
            self.resolveRoomSplit(asNewRoom: false)
        }
        voiceCaptionLabel.text = "  ¿Cuarto nuevo o corrección? \"\(candidateName)\"  "
        voiceCaptionLabel.isHidden = false
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideVoiceCaption), object: nil)
    }

    // The ONLY function in this file that can lead to captureSession.
    // stop() being called as a result of hearing a room name - and only
    // on the asNewRoom branch, which requires an explicit positive
    // signal. Reused verbatim for the timeout path (asNewRoom: false) so
    // an ignored/unanswered question always fails toward the reversible
    // branch (a rename costs nothing to fix later) and never toward the
    // irreversible one (ending a capture loses real, unrecoverable
    // geometry) - silence can never be read as consent to split a room.
    private func resolveRoomSplit(asNewRoom: Bool) {
        guard let candidateName = pendingRoomSplitCandidateName else { return }
        roomSplitConfirmationTimer?.invalidate()
        roomSplitConfirmationTimer = nil
        pendingRoomSplitCandidateName = nil
        updateUI()
        if asNewRoom {
            autoContinueNextRoomName = candidateName
            speak("Guardando este cuarto y pasando a \(candidateName).") {}
            showVoiceCaption("Nuevo cuarto: \(candidateName)")
            doneTapped()
        } else {
            let isRename = pendingCurrentRoomName != nil && pendingCurrentRoomName != candidateName
            pendingCurrentRoomName = candidateName
            showVoiceCaption(candidateName)
            confirmName(candidateName, isRename: isRename)
        }
    }

    @objc private func newRoomButtonTapped() {
        guard pendingRoomSplitCandidateName != nil else { return }
        resolveRoomSplit(asNewRoom: true)
    }

    @objc private func correctNameButtonTapped() {
        guard pendingRoomSplitCandidateName != nil else { return }
        resolveRoomSplit(asNewRoom: false)
    }

    private func showVoiceCaption(_ name: String) {
        voiceCaptionLabel.text = "  \(name) ✓  "
        voiceCaptionLabel.isHidden = false
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideVoiceCaption), object: nil)
        perform(#selector(hideVoiceCaption), with: nil, afterDelay: 2.5)
    }

    @objc private func hideVoiceCaption() {
        voiceCaptionLabel.isHidden = true
    }

    @objc private func micToggleTapped() {
        micMuted.toggle()
        micToggleButton.setTitle(micMuted ? "🔇" : "🎤", for: .normal)
        if micMuted {
            // Callar es callar AHORA, no al acabar la frase que va sonando.
            speechSynthesizer.stopSpeaking(at: .immediate)
            stopVoiceAssistant()
        } else {
            startVoiceAssistant()
        }
    }

    // El aviso de maderas NUNCA pisa una pregunta abierta ni una frase que
    // esté sonando: el micrófono se apaga mientras el teléfono habla, y la
    // ventana de "¿cuarto nuevo o corrección?" dura 6 s - un aviso encima
    // se la comería y el cuarto siguiente se escanearía dentro del anterior
    // (el fallo que la puerta de partición ya arregló una vez). Si el
    // momento es malo, se reintenta UNA vez a los 8 s; si sigue malo, se
    // queda con la propuesta del plano, que llega igual. Solo mientras se
    // escanea ese mismo cuarto, y nunca después de Cancelar.
    private func avisarMaderas(_ roomIdx: Int, reintento: Bool) {
        guard state == .scanningRoom, !sessionDelivered, capturedRooms.count == roomIdx else { return }
        let ocupado = pendingRoomSplitCandidateName != nil || pendingUnsureName != nil
            || pendingDeleteRoomIndex != nil || speechSynthesizer.isSpeaking
        if ocupado {
            guard reintento else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.avisarMaderas(roomIdx, reintento: false)
            }
            return
        }
        showVoiceCaption("Veo una pared de solo maderas")
        speak("Veo una pared de solo maderas. Sigue con los dos lados como un solo cuarto; al terminar te propongo el corte.") {}
    }

    private func speak(_ text: String, then: @escaping () -> Void) {
        // SILENCIADO NO HABLA. Aqui no habia NINGUN guardia: tocar el 🔇
        // apagaba el oido y dejaba la voz intacta, asi que el telefono seguia
        // hablando (el aviso de calor, el reporte de calidad del escaneo, el
        // resumen de progreso...). Es la mitad de su reporte del 12 de
        // septiembre.
        //
        // PERO EL `then` SE LLAMA IGUAL, y eso no es un detalle: veintidos
        // frases de esta pantalla llevan un completion que SIGUE EL FLUJO
        // (arrancar el asistente, abrir una pregunta, guardar un cuarto). Si
        // callar dejara de llamarlos, callar trabaria el escaneo - y en este
        // archivo ya hay un FAILSAFE por un caso asi.
        if micMuted {
            DispatchQueue.main.async { then() }
            return
        }
        // Misma voz y mismo ritmo que la camara de medir (ver VozAsistente).
        let utterance = VozAsistente.frase(text)
        utterance.volume = 1.0
        speechCompletions[utterance] = then
        speechSynthesizer.speak(utterance)
    }

    // isSpeakingConfirmation gates the mic tap below (installTap's closure)
    // for as long as ANY utterance is queued/playing - read live off the
    // synthesizer itself rather than tracked per-utterance, since
    // AVSpeechSynthesizer queues multiple speak() calls and this only
    // needs to answer "is the phone talking right now," not track which
    // specific utterance is active.
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeakingConfirmation = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeakingConfirmation = synthesizer.isSpeaking
        let completion = speechCompletions.removeValue(forKey: utterance)
        completion?()
    }

    // A cancelled utterance's completion is dropped, not fired - firing
    // e.g. startVoiceAssistant() while the screen is being torn down is
    // exactly what cancellation is supposed to prevent.
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeakingConfirmation = synthesizer.isSpeaking
        // EL COMPLETION SE LLAMA IGUAL. Antes se tiraba, y con eso una frase
        // cortada se llevaba por delante lo que venia despues - arrancar el
        // asistente, abrir una pregunta, seguir con el cuarto siguiente.
        //
        // Hasta hoy nada de esta pantalla cortaba la voz (cero
        // `stopSpeaking` en todo el archivo), asi que el caso no se daba. El
        // boton 🔇 ahora si la corta, y el flujo no puede depender de que el
        // audio termine de sonar.
        let completion = speechCompletions.removeValue(forKey: utterance)
        DispatchQueue.main.async { completion?() }
    }

    // Speech recognition and microphone access are two SEPARATE iOS
    // permission systems (Settings > Privacy has both "Speech Recognition"
    // and "Microphone" as distinct toggles, matching this app's Info.plist
    // having both NSSpeechRecognitionUsageDescription and
    // NSMicrophoneUsageDescription keys) - both are requested explicitly,
    // in order, before any audio code runs. Once granted, the answer is
    // cached (voicePermissionGranted) so muting/unmuting later doesn't
    // re-prompt - the system dialog only ever appears once.
    private var voiceStartRetryCount = 0
    private func startVoiceAssistant() {
        guard !micMuted, voiceAudioEngine == nil else { return }
        guard let recognizer = speechRecognizer else { return }
        // A recognizer that is momentarily unavailable at launch (model
        // still loading) used to kill voice for the whole session - the
        // one-shot had been consumed. Retry a few times with backoff.
        guard recognizer.isAvailable else {
            voiceStartRetryCount += 1
            guard voiceStartRetryCount <= 5 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(voiceStartRetryCount) * 2) { [weak self] in
                self?.startVoiceAssistant()
            }
            return
        }
        if voicePermissionGranted {
            beginContinuousRecognition(recognizer: recognizer)
            return
        }
        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            DispatchQueue.main.async {
                guard let self = self, speechStatus == .authorized else { return }
                self.requestMicPermission { granted in
                    guard granted else { return }
                    self.voicePermissionGranted = true
                    guard !self.micMuted else { return }
                    self.beginContinuousRecognition(recognizer: recognizer)
                }
            }
        }
    }

    // AVAudioApplication.requestRecordPermission is the modern API
    // (iOS 17+); AVAudioSession.requestRecordPermission is the same
    // request under its pre-17 name, still functional at this app's
    // iOS 16.0 floor (deprecated, not removed).
    private func requestMicPermission(_ completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    // Starts the audio engine ONCE and leaves it running continuously;
    // only the recognizer-side task (which has a real ~60s cap) gets
    // cycled underneath it, via restartRecognitionTask below.
    private func beginContinuousRecognition(recognizer: SFSpeechRecognizer) {
        // Session config lives in configureAudioSessionIfNeeded (category
        // .playAndRecord, mode .default - NOT .measurement, whose header-
        // documented lower output level silenced every spoken reply) and
        // is normally already done by viewDidAppear, BEFORE anything
        // spoke - reconfiguring here mid-utterance was itself a way to
        // stall the synthesizer. The call below only does work on the
        // mute -> unmute path, where stopVoiceAssistant deactivated the
        // session (and nothing is speaking).
        configureAudioSessionIfNeeded()
        guard audioSessionConfigured else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, !self.isSpeakingConfirmation else { return }
            self.voiceRequest?.append(buffer)
            // Que tan fuerte entro este pedacito de audio. Se guarda el PICO
            // desde la ultima frase atendida: una frase se juzga por su parte
            // mas fuerte, no por el promedio, porque el promedio lo hunde el
            // silencio entre palabra y palabra.
            //
            // Corre en la cola del audio, no en la principal. Es un solo
            // Float y solo lo escribe este tap; leerlo desde la principal a
            // lo mucho da un valor de hace unos milisegundos, que para
            // "¿esto entro fuerte o bajito?" da exactamente igual.
            guard let ch = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            var sum: Float = 0
            for i in 0..<n { let v = ch[i]; sum += v*v }
            let rms = (sum / Float(n)).squareRoot()
            if rms > self.levelPeakSinceDispatch { self.levelPeakSinceDispatch = rms }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            return
        }

        voiceAudioEngine = engine
        // Visible proof the mic is actually live - the tech reported a
        // session where the assistant silently never started and nothing
        // on screen said so; now listening announces itself.
        voiceCaptionLabel.text = "  🎤 Escuchando  "
        voiceCaptionLabel.isHidden = false
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideVoiceCaption), object: nil)
        perform(#selector(hideVoiceCaption), with: nil, afterDelay: 3.0)
        restartRecognitionTask(recognizer: recognizer)
    }

    // Swaps in a fresh SFSpeechAudioBufferRecognitionRequest + task without
    // touching the audio engine/tap - called proactively every 50s (ahead
    // of the real ~60s per-task cap) and reactively whenever a task ends
    // with an error (including that same cap being hit), so listening
    // itself never has a gap. voiceTaskGeneration guards against an old,
    // just-canceled task's own completion callback triggering a second,
    // redundant restart on top of the deliberate one already in progress.
    private var flushPendingTranscript: (() -> Void)?
    private func restartRecognitionTask(recognizer: SFSpeechRecognizer) {
        // Speech in the last ~1.2s before a rotation was silently dropped:
        // the quiet-timer was still counting down when cancel() + the
        // generation bump killed it. Flush the pending portion first.
        flushPendingTranscript?()
        flushPendingTranscript = nil
        voiceTask?.cancel()
        voiceRestartTimer?.invalidate()
        voiceTaskGeneration += 1
        let myGeneration = voiceTaskGeneration

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device first (private, offline, fast) - but if the on-device
        // Spanish model errors out repeatedly (not installed/ready on this
        // phone), fall back to server-based recognition rather than
        // retrying a broken configuration forever with a dead mic.
        request.requiresOnDeviceRecognition = !allowServerRecognition
        voiceRequest = request

        var lastHandledText = ""
        var latestText = ""
        var quietTimer: Timer?
        // bestTranscription is CUMULATIVE over this whole recognition
        // task's life (up to ~50s) - every new utterance arrives APPENDED
        // to everything already said in the window. Handling the whole
        // string re-ran old commands with the new words tacked on (a real
        // bug: "elimina este cuarto" then "sí" arrived as "elimina este
        // cuarto sí", which re-triggered the delete request instead of
        // confirming it - the confirmation was literally unreachable).
        // Dispatch only the NEW portion; fall back to the full text only
        // if the recognizer revised earlier words (prefix no longer
        // matches - rare).
        let dispatchPending: () -> Void = { [weak self] in
            guard let self = self, self.voiceTaskGeneration == myGeneration else { return }
            let text = latestText
            guard text != lastHandledText, !text.isEmpty else { return }
            let newPortion: String
            if !lastHandledText.isEmpty, text.hasPrefix(lastHandledText) {
                newPortion = String(text.dropFirst(lastHandledText.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                newPortion = text
            }
            lastHandledText = text
            guard !newPortion.isEmpty else { return }
            // El pico de esta frase, y se reinicia para la siguiente.
            let level = self.levelPeakSinceDispatch
            self.levelPeakSinceDispatch = 0
            self.handleVoiceCommand(newPortion, viaButton: false, level: level)
        }
        flushPendingTranscript = {
            quietTimer?.invalidate()
            dispatchPending()
        }

        voiceTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self, self.voiceTaskGeneration == myGeneration else { return }
                if let result = result {
                    // A real result means recognition is genuinely working -
                    // reset the error-restart backoff.
                    self.voiceErrorRestartCount = 0
                    latestText = result.bestTranscription.formattedString
                    // A short pause after speech stops is treated as "that
                    // was one utterance" - mirrors the old single-shot
                    // silence-timeout idea, just as an ongoing background
                    // habit instead of a one-time countdown.
                    quietTimer?.invalidate()
                    quietTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { _ in
                        dispatchPending()
                    }
                }
                if error != nil, self.voiceAudioEngine != nil, !self.micMuted {
                    self.scheduleRecognitionRestart(recognizer: recognizer)
                }
            }
        }

        voiceRestartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
            guard let self = self, self.voiceAudioEngine != nil, !self.micMuted else { return }
            self.restartRecognitionTask(recognizer: recognizer)
        }
    }

    // Error-path restarts are DELAYED with growing backoff instead of
    // immediate - a task that fails instantly (recognizer briefly
    // unavailable, on-device model not ready) used to respin in a tight
    // infinite loop, each failure immediately spawning the next attempt.
    // The 50s proactive restart and genuine results both reset the count.
    private func scheduleRecognitionRestart(recognizer: SFSpeechRecognizer) {
        voiceErrorRestartCount += 1
        if voiceErrorRestartCount >= 3 { allowServerRecognition = true }
        let delay = min(Double(voiceErrorRestartCount), 5.0)
        voiceRestartTimer?.invalidate()
        voiceRestartTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self, self.voiceAudioEngine != nil, !self.micMuted else { return }
            self.restartRecognitionTask(recognizer: recognizer)
        }
    }

    private func stopVoiceAssistant() {
        // Deliberately NOT flushed: dispatching a half-heard command into
        // a session that is being torn down is worse than dropping it.
        flushPendingTranscript = nil
        voiceRestartTimer?.invalidate()
        voiceRestartTimer = nil
        voiceTaskGeneration += 1
        voiceTask?.cancel()
        voiceTask = nil
        voiceRequest?.endAudio()
        voiceRequest = nil
        if let engine = voiceAudioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        voiceAudioEngine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        audioSessionConfigured = false
    }

    // Strips filler phrases so "estoy en la cocina" becomes "Cocina" - a
    // small cleanup, not a language model; anything not matching a known
    // filler is left as-is and just capitalized. Also used as a coarse
    // "does this look like a room name and not just background chatter"
    // filter for the continuous listener: very long transcriptions (more
    // than a handful of words) are treated as not a room-naming utterance
    // at all, to avoid mistaking a passing conversation for a name.
    private func cleanVoiceRoomName(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let fillers = [
            "estoy en la ", "estoy en el ", "estoy en ",
            "esto es la ", "esto es el ", "es la ", "es el ",
            "i'm in the ", "i am in the ", "this is the ", "it's the "
        ]
        let lower = text.lowercased()
        for filler in fillers where lower.hasPrefix(filler) {
            text = String(text.dropFirst(filler.count))
            break
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard text.split(separator: " ").count <= 5 else { return nil }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    // MARK: - Equipment vocabulary & voice command classification
    //
    // Reuses the app's own existing Equipment-tab vocabulary (DEFAULT_
    // EQUIPMENT in www/index.html) rather than inventing new terms, so a
    // count logged here means the same thing it would mean typed into
    // that tab. Apple's NaturalLanguage framework was actually tested
    // against Spanish number words on this machine and missed over half
    // of them (and "un/una" every time) - this is a hand-rolled table on
    // purpose, not a shortcut skipped for convenience.
    private static let spanishNumberWords: [String: Int] = [
        "un": 1, "uno": 1, "una": 1,
        "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5,
        "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10,
        "once": 11, "doce": 12, "trece": 13, "catorce": 14, "quince": 15,
        "dieciséis": 16, "dieciseis": 16, "diecisiete": 17,
        "dieciocho": 18, "diecinueve": 19, "veinte": 20
    ]

    // `label` keeps the bilingual "Spanish / English" display convention
    // this app already uses elsewhere; `keywords` are what the recognizer
    // actually needs to hear - the es-MX locale means everything spoken
    // here is Spanish, so English synonyms aren't included (there's
    // nothing for them to match against).
    private static let equipmentVocabulary: [(type: String, label: String, keywords: [String])] = [
        ("fans", "Ventiladores / Fans", ["ventilador", "ventiladores", "extractor de aire", "extractores de aire", "extractor", "extractores"]),
        ("dehumidifiers", "Deshumidificadores / Dehumidifiers", ["deshumidificador", "deshumidificadores"]),
        ("hepas", "HEPAs", ["hepa", "hepas", "filtro hepa", "filtros hepa"]),
        ("dryMats", "Tapetes Secos / Dry Mats", ["tapete seco", "tapetes secos", "tapete", "tapetes"]),
        ("generators", "Generadores / Generators", ["generador", "generadores"]),
        ("airDucts", "Ductos de Aire / Air Ducts", ["ducto de aire", "ductos de aire", "ducto", "ductos"]),
        ("ozoneMachine", "Máquina de Ozono / Ozone Machine", ["máquina de ozono", "maquina de ozono", "ozono"]),
        ("heaters", "Calentadores / Heaters", ["calentador", "calentadores"])
    ]

    private static let removalVerbs = [
        "quítale", "quitale", "quita", "quitar", "remueve", "remover",
        "elimina", "eliminar", "borra", "borrar", "saca", "sacar"
    ]
    private static let deleteRoomAnchors = ["este cuarto", "esta habitación", "esta habitacion", "cuarto", "habitación", "habitacion"]

    private enum VoiceIntent {
        case removeEquipment(type: String, count: Int?)
        case deleteRoomRequested
        case logEquipment([(type: String, count: Int?)])
        case roomName(String)
        case ignored
    }

    // A fixed, ordered checklist, most-specific-first, so e.g. "quita un
    // extractor" (an equipment noun IS present) can never be misread as
    // "quita este cuarto" (delete the whole room) - equipment removal is
    // always checked before room deletion. Genuinely ambiguous removal
    // phrases (a removal verb with neither an equipment noun nor a room
    // anchor - e.g. "quita la sala," where "sala" could mean either the
    // living-room name or "this room") are deliberately dropped rather
    // than guessed - never applied as a room name, per the project's
    // "never fabricate/guess" discipline.
    private func classifyVoiceCommand(_ raw: String) -> VoiceIntent {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return .ignored }

        if Self.removalVerbs.contains(where: { lower.contains($0) }) {
            for entry in Self.equipmentVocabulary {
                if let keyword = entry.keywords.first(where: { lower.contains($0) }) {
                    return .removeEquipment(type: entry.type, count: numberBefore(keyword, in: lower))
                }
            }
            if Self.deleteRoomAnchors.contains(where: { lower.contains($0) }) {
                return .deleteRoomRequested
            }
            return .ignored
        }

        // Equipment count: every (number, equipment noun) pair anywhere in
        // the utterance, not just the first - "dos deshumidificadores y
        // seis ventiladores" logs both in one sentence.
        var found: [(type: String, count: Int?)] = []
        for entry in Self.equipmentVocabulary {
            if let keyword = entry.keywords.first(where: { lower.contains($0) }) {
                found.append((entry.type, numberBefore(keyword, in: lower)))
            }
        }
        if !found.isEmpty {
            return .logEquipment(found)
        }

        if let name = cleanVoiceRoomName(raw) {
            return .roomName(name)
        }
        return .ignored
    }

    // Looks a few words back from a keyword's position for a number word
    // or digit - "dos deshumidificadores" -> 2. Returns nil (not zero)
    // when no number is heard ("necesito deshumidificadores"), since that
    // means "needs manual entry," never a guessed count.
    private func numberBefore(_ keyword: String, in text: String) -> Int? {
        guard let range = text.range(of: keyword) else { return nil }
        let before = text[text.startIndex..<range.lowerBound]
        guard let lastWord = before.split(separator: " ").map(String.init).last else { return nil }
        if let n = Int(lastWord) { return n }
        return Self.spanishNumberWords[lastWord]
    }

    private func equipmentDisplayName(_ type: String) -> String {
        guard let vocab = Self.equipmentVocabulary.first(where: { $0.type == type }) else { return type }
        return vocab.label.components(separatedBy: " / ").first ?? vocab.label
    }

    private func equipmentSummaryText(for roomIndex: Int) -> String {
        guard roomEquipment.indices.contains(roomIndex) else { return "" }
        let entries = roomEquipment[roomIndex].values.sorted { $0.type < $1.type }
        guard !entries.isEmpty else { return "" }
        return entries.map { entry -> String in
            let name = equipmentDisplayName(entry.type)
            return entry.count.map { "\(name): \($0)" } ?? "\(name): ?"
        }.joined(separator: " · ")
    }

    // "Llevas 3 cuartos: Cocina, Baño y Sala." Los sin nombre se cuentan
    // pero se dicen como "uno sin nombre" - callarlos seria esconder
    // justo lo que le falta por hacer.
    private func speakProgressSummary() {
        let vivos = capturedRooms.indices.filter { !deletedRoomIndices.contains($0) }
        guard !vivos.isEmpty else {
            speak("Todavía no hay ningún cuarto guardado.") {}
            return
        }
        let nombres = vivos.compactMap { i -> String? in
            guard voiceNames.indices.contains(i), let n = voiceNames[i],
                  !n.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return n
        }
        let sinNombre = vivos.count - nombres.count
        var frase = vivos.count == 1 ? "Llevas 1 cuarto" : "Llevas \(vivos.count) cuartos"
        if !nombres.isEmpty {
            let lista = nombres.count == 1 ? nombres[0]
                : nombres.dropLast().joined(separator: ", ") + " y " + nombres[nombres.count-1]
            frase += ": " + lista
        }
        if sinNombre > 0 {
            frase += nombres.isEmpty
                ? (sinNombre == 1 ? ", sin nombre" : ", todos sin nombre")
                : (sinNombre == 1 ? ", y uno sin nombre" : ", y \(sinNombre) sin nombre")
        }
        if !nivelBase.isEmpty { frase += ". Vas en el \(nombreDelNivel(currentLevel))" }
        else if currentLevel > 1 { frase += ". Vas en el nivel \(currentLevel)" }
        speak(frase + ".") {}
    }

    private func roomLabel(for index: Int) -> String {
        let number = index + 1
        if let name = voiceNames.indices.contains(index) ? voiceNames[index] : nil {
            return "Cuarto \(number) - \(name)"
        }
        return "Cuarto \(number)"
    }

    // Solo palabra completa. Un hasPrefix("si") pelado tambien pegaba con
    // "siganme" y "simbolo" y los tomaba por un si - ya mordio una vez en
    // la confirmacion de borrar, asi que aqui se hace igual de estricto.
    // La lista vive en VozAsistente para que las dos pantallas contesten
    // igual. Los nombres se quedan aqui porque las pruebas los sacan de este
    // archivo por nombre.
    private static func isYes(_ lower: String) -> Bool { return VozAsistente.esSi(lower) }
    private static func isNo(_ lower: String) -> Bool { return VozAsistente.esNo(lower) }

    // MARK: - Lo que el asistente aprende del tecnico

    // Se carga una vez al abrir el escaner. Vive en ESTE telefono: es la voz
    // y el vocabulario de quien lo trae en la mano, no de la compania.
    private func loadVoiceLearning() {
        let d = UserDefaults.standard
        learnedRoomNames = Set(d.stringArray(forKey: Self.learnedNamesKey) ?? [])
        ownSpeechLevel = d.float(forKey: Self.ownLevelKey)
        ownSpeechSamples = d.integer(forKey: Self.ownLevelKey + ":n")
    }

    // Cada nombre que EL confirma queda aprendido: la proxima casa esa
    // palabra ya entra sin preguntar. Aqui es donde deja de ser una lista
    // nuestra y empieza a ser su vocabulario.
    private func learnRoomName(_ name: String) {
        let key = Self.normalizedName(name)
        guard !key.isEmpty, !Self.knownRoomWords.contains(key), !learnedRoomNames.contains(key) else { return }
        learnedRoomNames.insert(key)
        // Tope sano: 200 palabras es mucho mas de lo que un tecnico usa, y
        // evita que un mal dia de reconocimiento llene el telefono de basura.
        if learnedRoomNames.count > 200 { learnedRoomNames.remove(learnedRoomNames.first!) }
        UserDefaults.standard.set(Array(learnedRoomNames), forKey: Self.learnedNamesKey)
    }

    // Que tan fuerte habla EL. Solo se aprende de frases donde la app tiene
    // CERTEZA de que fue el: contestar algo que la app pregunto, o tocar un
    // boton. Aprender del audio suelto seria aprender tambien de los vecinos,
    // y el filtro se envenenaria solo hasta dejar de filtrar nada.
    private func noteOwnSpeechLevel(_ level: Float) {
        guard level > 0, level < Float.greatestFiniteMagnitude else { return }
        // Promedio corrido. Se mueve despacio a proposito: un grito suelto no
        // debe subir la vara y dejarlo sin asistente el resto del trabajo.
        ownSpeechLevel = ownSpeechSamples == 0 ? level
            : (ownSpeechLevel * Float(min(ownSpeechSamples, 30)) + level) / Float(min(ownSpeechSamples, 30) + 1)
        ownSpeechSamples += 1
        let d = UserDefaults.standard
        d.set(ownSpeechLevel, forKey: Self.ownLevelKey)
        d.set(ownSpeechSamples, forKey: Self.ownLevelKey + ":n")
    }

    // ¿Esto entro demasiado bajito para ser el que trae el telefono?
    //
    // Callado hasta tener con que comparar: con menos de 5 frases suyas
    // medidas, NO filtra nada. Un filtro que adivina el primer dia es peor
    // que no tener filtro - lo dejaria sin asistente sin saber por que.
    private func isTooFarToBeHim(_ level: Float) -> Bool {
        return Self.tooFarToBeHim(level: level, ownLevel: ownSpeechLevel, samples: ownSpeechSamples)
    }
    // Aparte y sin estado para poder probarla: este calculo decide si una voz
    // toca el plano o no, y equivocarse en cualquiera de los dos sentidos
    // cuesta - de mas, le corrompe el trabajo; de menos, lo deja sin
    // asistente en media casa.
    // La regla vive en VozAsistente para que las dos pantallas juzguen igual
    // la distancia. El nombre se queda aqui porque las pruebas lo buscan.
    private static func tooFarToBeHim(level: Float, ownLevel: Float, samples: Int) -> Bool {
        return VozAsistente.vieneDeLejos(nivel: level, suNivel: ownLevel, muestras: samples)
    }

    private static func normalizedName(_ s: String) -> String {
        return s.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // ¿Esta palabra se parece a un nombre de cuarto?
    private func isKnownRoomWord(_ name: String) -> Bool {
        return Self.isRoomWord(name, learned: learnedRoomNames)
    }
    private static func isRoomWord(_ name: String, learned: Set<String>) -> Bool {
        let key = normalizedName(name)
        guard !key.isEmpty else { return false }
        if learned.contains(key) { return true }
        // Sin acentos de los dos lados: el reconocedor a veces escribe "bano".
        if knownRoomWords.contains(where: { normalizedName($0) == key }) { return true }
        // "Cuarto de lavado" cuando la lista trae "lavado", o al reves. Y
        // "cuarto de Chucho": en español bautizar asi un cuarto es normal y
        // hay que dejarlo pasar.
        //
        // PERO con tope de palabras. Sin el, "cuarto" al principio dejaba
        // entrar CUALQUIER frase que empezara con esa palabra - "cuarto donde
        // estaba la señora cuando se inundó" habria sido un nombre de cuarto
        // valido. Un nombre son dos o tres palabras; lo demas es una platica.
        guard key.split(separator: " ").count <= 4 else { return false }
        return knownRoomWords.contains(where: { w in
            let k = normalizedName(w)
            return k.count >= 4 && (key.hasPrefix(k + " ") || key.hasSuffix(" " + k))
        })
    }

    // El unico camino por el que una voz puede ponerle nombre a un cuarto.
    // Conocida -> se aplica. Desconocida -> se PREGUNTA, nunca se aplica sola
    // y nunca se tira: asi puede inventar el nombre que quiera y aun asi una
    // platica ajena jamas corrompe un plano.
    private func acceptRoomName(_ name: String, viaButton: Bool) {
        if viaButton || isKnownRoomWord(name) {
            learnRoomName(name)
            applyHeardOrTappedName(name, viaButton: viaButton)
            return
        }
        pendingUnsureName = name
        showVoiceCaption("¿\"\(name)\"?")
        speak("¿\(name) es el nombre del cuarto?") {}
    }

    private func resolveUnsureName(accepted: Bool) {
        guard let name = pendingUnsureName else { return }
        pendingUnsureName = nil
        if accepted {
            learnRoomName(name)
            applyHeardOrTappedName(name, viaButton: false)
        } else {
            showVoiceCaption("Ignorado")
        }
    }

    // Single entry point the continuous-recognition transcript handler
    // calls (replacing the old direct cleanVoiceRoomName+applyHeardOr-
    // TappedName call) - intercepts a pending delete confirmation first
    // (so "sí" is never itself misread as a room-name utterance), then
    // classifies and dispatches everything else.
    private func handleVoiceCommand(_ raw: String, viaButton: Bool, level: Float = 0) {
        // Un boton es una decision deliberada: siempre de maxima confianza.
        currentUtteranceLevel = viaButton ? Float.greatestFiniteMagnitude : level
        // LA PUERTA DE ENTRADA. Va aqui arriba, antes de TODO - antes del si
        // que borra un cuarto, antes del equipo, antes de los nombres - porque
        // una voz ajena no debe poder tocar nada, no solo los nombres.
        if !viaButton, isTooFarToBeHim(level) {
            showVoiceCaption("🔉 Se oyó lejos — ignorado")
            return
        }
        // Un nombre que sono raro y quedo esperando un si o un no. Va antes
        // que todo lo demas para que ese "si" no se lea como otra cosa.
        if pendingUnsureName != nil {
            let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if lower.split(separator: " ").count <= 3 {
                if Self.isYes(lower) { noteOwnSpeechLevel(level); resolveUnsureName(accepted: true); return }
                if Self.isNo(lower)  { noteOwnSpeechLevel(level); resolveUnsureName(accepted: false); return }
            }
            // Cualquier otra cosa: la pregunta se cae sola y la frase nueva
            // sigue su camino normal. No se queda trabada esperando.
            pendingUnsureName = nil
        }
        if pendingDeleteRoomIndex != nil {
            let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            // Word-boundary match only: bare hasPrefix("sí") also matched
            // "síganme"/"símbolo"-style words and treated them as consent.
            if lower == "sí" || lower == "si" || lower.hasPrefix("sí ") || lower.hasPrefix("si ") {
                noteOwnSpeechLevel(level)
                confirmPendingDeletion()
                return
            }
            if lower == "no" || lower.hasPrefix("no ") {
                cancelPendingDeletion(spoken: true)
                return
            }
        }
        if pendingRoomSplitCandidateName != nil {
            let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let newRoomPhrases = ["cuarto nuevo", "nuevo cuarto", "es nuevo", "otro cuarto"]
            let correctionPhrases = ["corrige", "correccion", "corrección", "corregir", "mismo cuarto", "sigo aqui", "sigo aquí"]
            // Splitting is IRREVERSIBLE (an early stop() can't be undone),
            // so a bare ambiguous "sí" is no longer accepted here - only
            // the explicit new-room phrases reach the split. "Sí" alone
            // falls through to the rename-safe timeout default instead.
            if newRoomPhrases.contains(where: { lower.contains($0) }) {
                resolveRoomSplit(asNewRoom: true)
                return
            }
            if correctionPhrases.contains(where: { lower.contains($0) }) || lower == "no" || lower.hasPrefix("no ") {
                resolveRoomSplit(asNewRoom: false)
                return
            }
            // A session-control word ("listo", "terminar", "otro nivel")
            // answers the open question implicitly: resolve the gate the
            // safe way (rename, same as the timeout default) and fall
            // through so the command itself still runs - previously
            // "listo" here re-targeted the question to the room name
            // "Listo" and the tech couldn't end the room by voice.
            let controlWords = ["listo", "terminar", "terminamos", "otro nivel", "ya terminé", "ya termine"]
            if controlWords.contains(where: { lower.contains($0) }) {
                resolveRoomSplit(asNewRoom: false)
                // no return - the checklist below handles the command
            } else if case .roomName(let newCandidate) = classifyVoiceCommand(raw) {
                // A third, yet-different room name just re-targets the same
                // question rather than stacking a second one; anything else
                // (an equipment command, for instance) falls through
                // unhandled to the normal checklist below, so logging
                // equipment still works while this question is open.
                requestRoomSplitConfirmation(candidateName: newCandidate)
                return
            }
        }
        // Session control by voice - the scan flow itself, not just
        // names/equipment. Checked BEFORE the classifier because these
        // words would otherwise fall through to the room-name branch and
        // literally rename a room to "Terminar" or "Otro cuarto."
        let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = lower.split(separator: " ").count

        // ---- Comandos que valen en cualquier momento del escaneo ----
        //
        // "Callate": hay casas con el cliente presente y momentos en que el
        // telefono hablando estorba. Se dice ADONDE esta el boton para
        // volver, porque callar apaga el micro y la voz ya no puede
        // reactivarse a si misma - decir "callate" sin avisar eso lo dejaria
        // creyendo que el asistente se murio.
        if wordCount <= 3, ["silencio", "cállate", "callate", "ya no hables", "cállese", "callese"]
            .contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) {
            noteOwnSpeechLevel(level)
            speak("Me callo. Toca el micrófono en la pantalla cuando quieras que vuelva.") { [weak self] in
                guard let self = self, !self.micMuted else { return }
                self.micMuted = true
                self.micToggleButton.setTitle("🔇", for: .normal)
                self.stopVoiceAssistant()
            }
            return
        }
        // "¿Como vamos?": va con el telefono en alto y sin poder leer la
        // pantalla. Que le diga lo que lleva, en voz alta.
        if wordCount <= 4, ["cómo vamos", "como vamos", "qué llevo", "que llevo",
                            "cuántos cuartos", "cuantos cuartos", "qué tengo", "que tengo"]
            .contains(where: { lower.contains($0) }) {
            noteOwnSpeechLevel(level)
            speakProgressSummary()
            return
        }

        if state == .scanningRoom, wordCount <= 3,
           (lower == "listo" || lower.contains("cuarto listo") || lower.contains("ya terminé") || lower.contains("ya termine") || lower == "terminé" || lower == "termine") {
            speak("Guardando el cuarto.") {}
            doneTapped()
            return
        }
        if state == .roomDonePrompt {
            // Checked BEFORE "otro cuarto": "repetir el cuarto" contains
            // neither, but "repite este cuarto" must never be heard as a
            // request to move on. Only offered when the room actually
            // came back with a hole, same gate as the button.
            if wordCount <= 4, lower.contains("repetir") || lower.contains("repite") ||
               lower.contains("otra vez") || lower.contains("de nuevo") {
                // Antes solo se dejaba repetir si la app habia detectado un
                // hueco - o sea, la app decidia si su queja era valida. El
                // que estuvo adentro sabe si el escaneo salio mal por
                // razones que ningun detector ve (se metio en un closet,
                // paso alguien enfrente, se le fue la mano). Si lo pide, se
                // repite: el cuarto rechazado igual viaja marcado y se
                // puede recuperar con Deshacer.
                noteOwnSpeechLevel(level)
                pendingDoneQuestion = nil
                repeatRoomTapped(); return
            }
            // "Otro nivel" ya NO se ofrece en voz alta - la pregunta es si
            // o no y nada mas. Pero se sigue ESCUCHANDO, por dos razones:
            // el segundo piso tiene que seguir siendo posible sin soltar el
            // telefono, y si se quitara, decir "otro nivel" caeria hasta el
            // clasificador de nombres y bautizaria el cuarto "Otro nivel".
            if lower.contains("otro nivel") { scanAnotherLevelTapped(); return }
            if lower.contains("otro cuarto") || lower.contains("siguiente cuarto") { scanAnotherTapped(); return }
            if wordCount <= 3, (lower.contains("terminar") || lower.contains("terminamos") || lower.contains("termina el plano")) {
                finishTapped()
                return
            }
            // Si/no contestan la pregunta que quedo abierta. Va DESPUES de
            // las ordenes de arriba a proposito: si el dice "otro cuarto",
            // eso manda, sin importar que se le haya preguntado.
            if wordCount <= 3 {
                // Contestar algo que la app pregunto es la prueba mas limpia
                // de que la voz fue la SUYA: de ahi se aprende su volumen.
                if Self.isYes(lower), answerDoneQuestion(yes: true) { noteOwnSpeechLevel(level); return }
                if Self.isNo(lower), answerDoneQuestion(yes: false) { noteOwnSpeechLevel(level); return }
            }
        }
        switch classifyVoiceCommand(raw) {
        case .roomName(let name):
            acceptRoomName(name, viaButton: viaButton)
        case .logEquipment(let items):
            applyEquipmentLog(items, rawHeard: raw)
        case .removeEquipment(let type, let count):
            applyEquipmentRemoval(type: type, count: count)
        case .deleteRoomRequested:
            requestRoomDeletion()
        case .ignored:
            break
        }
    }

    // Logs equipment against whichever room is relevant: the one still
    // being scanned (pending, committed when it finishes) or the one that
    // just finished (corrected directly, same room the room-done card is
    // already showing) - same two-slot pattern as room naming.
    private func applyEquipmentLog(_ items: [(type: String, count: Int?)], rawHeard: String) {
        guard !items.isEmpty else { return }
        switch state {
        case .scanningRoom:
            for item in items {
                let vocab = Self.equipmentVocabulary.first { $0.type == item.type }
                pendingCurrentEquipment[item.type] = EquipmentEntry(
                    type: item.type, label: vocab?.label ?? item.type, count: item.count,
                    mode: "set", confidence: item.count != nil ? "heard" : "unclear", rawHeard: rawHeard
                )
            }
        case .roomDonePrompt:
            guard let index = capturedRooms.indices.last else { return }
            for item in items {
                let vocab = Self.equipmentVocabulary.first { $0.type == item.type }
                roomEquipment[index][item.type] = EquipmentEntry(
                    type: item.type, label: vocab?.label ?? item.type, count: item.count,
                    mode: "set", confidence: item.count != nil ? "heard" : "unclear", rawHeard: rawHeard
                )
            }
        default:
            return
        }
        let captionParts = items.map { item -> String in
            let name = equipmentDisplayName(item.type)
            return item.count.map { "\(name): \($0)" } ?? "\(name): ?"
        }
        showVoiceCaption(captionParts.joined(separator: ", "))
        updateUI()
        let spokenParts = items.map { item -> String in
            let name = equipmentDisplayName(item.type)
            return item.count.map { "\($0) \(name)" } ?? name
        }
        speak("Entendido, \(spokenParts.joined(separator: ", ")).") {}
    }

    // Removing one unit (or a spoken count) is applied immediately, same
    // low-stakes confirm-and-continue pattern as a rename - never gated
    // behind the delete-room-style confirmation, since it can't lose a
    // whole room's scan.
    private func applyEquipmentRemoval(type: String, count: Int?) {
        let name = equipmentDisplayName(type)
        let removed = count ?? 1
        switch state {
        case .scanningRoom:
            guard var existing = pendingCurrentEquipment[type], let existingCount = existing.count else { return }
            existing.count = max(0, existingCount - removed)
            pendingCurrentEquipment[type] = existing
        case .roomDonePrompt:
            guard let index = capturedRooms.indices.last,
                  var existing = roomEquipment[index][type], let existingCount = existing.count else { return }
            existing.count = max(0, existingCount - removed)
            roomEquipment[index][type] = existing
        default:
            return
        }
        showVoiceCaption("\(name) −\(removed)")
        updateUI()
        speak("Quité \(removed) \(name).") {}
    }

    // Only acts on the room whose summary card is actually showing
    // (.roomDonePrompt) - the room still being scanned isn't a finished
    // CapturedRoom yet, so "delete this room" while scanning a NEW room
    // would be ambiguous about which room is meant; restricting to the
    // moment right after a room finishes keeps it unambiguous.
    private func requestRoomDeletion() {
        guard state == .roomDonePrompt, let index = capturedRooms.indices.last, !deletedRoomIndices.contains(index) else { return }
        pendingDeleteRoomIndex = index
        deleteConfirmationTimer?.invalidate()
        deleteConfirmationTimer = nil
        // Same as the room-split gate: the answer window only starts once
        // the question itself has finished speaking, since the mic tap
        // discards audio while the phone is talking.
        speak("¿Eliminar \(roomLabel(for: index))? Di sí para confirmar.") { [weak self] in
            guard let self = self, self.pendingDeleteRoomIndex == index else { return }
            self.deleteConfirmationTimer?.invalidate()
            self.deleteConfirmationTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
                self?.cancelPendingDeletion(spoken: false)
            }
        }
        // BACKSTOP mirror of the room-split gate: a cancelled/stalled
        // utterance must not leave the delete gate armed forever (where a
        // later stray "sí" would delete the room).
        deleteConfirmationTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            guard let self = self, self.pendingDeleteRoomIndex == index else { return }
            self.cancelPendingDeletion(spoken: false)
        }
    }

    private func confirmPendingDeletion() {
        // Belt-and-suspenders alongside the startCapturingRoom cleanup:
        // deletion only ever executes while the room-done card the tech
        // is answering about is still the thing on screen.
        guard state == .roomDonePrompt, let index = pendingDeleteRoomIndex else { return }
        deleteConfirmationTimer?.invalidate()
        deleteConfirmationTimer = nil
        pendingDeleteRoomIndex = nil
        deletedRoomIndices.insert(index)
        showUndoDeleteChip(for: index)
        refreshLiveStructure()
        speak("Cuarto eliminado.") {}
        updateUI()
    }

    private func cancelPendingDeletion(spoken: Bool) {
        deleteConfirmationTimer?.invalidate()
        deleteConfirmationTimer = nil
        pendingDeleteRoomIndex = nil
        if spoken { speak("Cancelado.") {} }
    }

    private func showUndoDeleteChip(for index: Int) {
        lastDeletedIndexForUndo = index
        undoDeleteButton.isHidden = false
        undoDeleteTimer?.invalidate()
        undoDeleteTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            self?.undoDeleteButton.isHidden = true
            self?.lastDeletedIndexForUndo = nil
        }
    }

    @objc private func undoDeleteTapped() {
        undoDeleteTimer?.invalidate()
        undoDeleteButton.isHidden = true
        guard let index = lastDeletedIndexForUndo else { return }
        lastDeletedIndexForUndo = nil
        deletedRoomIndices.remove(index)
        refreshLiveStructure()
        speak("Deshecho.") {}
        updateUI()
    }
}
