import UIKit
import RoomPlan
import ARKit
import simd
import Speech
import AVFoundation
import SceneKit
import Vision

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
// ARSession itself alive via stop(pauseARSession: false)) and the user
// chooses to scan another room or finish. CORRECCIÓN (14-oct): eso no deja
// los cuartos en un mismo espacio - cada captura trae su propio origen y es
// StructureBuilder el que los junta (ver "LOS MARCOS"). Only the thin button/prompt bar around
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
    // Solo para enseñar la pantalla en el simulador (no hay LiDAR ahí): no
    // arranca nada, solo dibuja. Nunca se prende en un teléfono.
    var soloVistaPrevia = false
    var vistaPreviaEstado = 0
    // Las cinco plantas en orden, para nombrar el nivel 2, 3... si dice "otro
    // nivel". Se topa en el atico: no hay a donde seguir subiendo.
    private static let plantas = ["Basement", "First Floor", "Second Floor", "Third Floor", "Attic"]
    private static let plantasHabladas = ["el sótano", "el primer piso", "el segundo piso", "el tercer piso", "el ático"]
    // Los valores que manda la web son los de LEVEL_OPTIONS, en ingles.
    private static let plantaDelValor: [String: Int] = [
        "Basement": 0, "1st Floor": 1, "2nd Floor": 2, "3rd Floor": 3, "Attic": 4
    ]
    // Como se llama el nivel N en esta casa.
    private func nombreDelNivel(_ n: Int) -> String {
        if let propio = nombresDeNivel[n] { return Self.nombreVisible(propio) }
        guard let i0 = Self.plantaDelValor[nivelBase] else {
            // Un nivel con nombre propio del proyecto (Scanova): el primero se
            // llama como él; los de arriba, por número.
            return (n <= 1 && !nivelBase.isEmpty) ? nivelBase : "Nivel \(n)"
        }
        let i = min(i0 + max(0, n - 1), Self.plantas.count - 1)
        return Self.plantas[i]
    }
    private func nombrePlantaEstandar(_ n: Int) -> String? {
        guard let i0 = Self.plantaDelValor[nivelBase] else { return n == 1 ? nivelBase : nil }
        return Self.plantaValores[min(i0 + max(0, n - 1), Self.plantaValores.count - 1)]
    }

    private func nombreHablado(_ n: Int) -> String {
        if nombresDeNivel[n] != nil { return nombreDelNivel(n) }
        guard let i0 = Self.plantaDelValor[nivelBase] else { return nombreDelNivel(n) }
        return Self.plantasHabladas[min(i0 + max(0, n - 1), Self.plantasHabladas.count - 1)]
    }

    // `voiceNames` is parallel to capturedRooms - the room name heard/
    // tapped for each room, if any (nil = never named, falls back to the
    // existing rule-based guess on the web side).
    private var voiceNames: [String?] = [] { didSet { pedirPintarNombre() } }
    // Whatever name has been heard or tapped for the room CURRENTLY being
    // scanned - applied the moment that room's capture actually finishes
    // (captureView(didPresent:) below), then reset for the next one. A
    // single unified slot: naming works the same way for the first room
    // and every later room, whether you speak or tap, before the room
    // finishes or right after.
    private var pendingCurrentRoomName: String? {
        didSet {
            // Ya escogió el nombre de ESTE cuarto: la bandeja baja y deja solo
            // los botones, para ver más cámara.
            if pendingCurrentRoomName != nil, state == .scanningRoom, !eligiendoNivel, !bandejaRecogida {
                bandejaRecogida = true
                DispatchQueue.main.async { [weak self] in self?.animarBandeja() }
            }
            pedirPintarNombre()
        }
    }

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
    // La casa juntada por Apple en el último merge en vivo (CapturedStructure,
    // iOS 17): la vista 3D de la revisión la exporta entera.
    private var liveStructure: Any?

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
    // EL DISEÑO NUEVO DE LA CÁMARA (sus dos imágenes del 13 de octubre).
    // SOLO PRESENTACIÓN: el escáner y el guardado funcionan igual que antes.
    // Cámara amplia, linterna arriba a la izquierda (sin X: Cancelar está
    // abajo), minimapa arriba a la derecha, y UNA bandeja plateada abajo que
    // primero pide el nivel y luego, la misma, el cuarto.
    private let torchButton = UIButton(type: .system)
    private let torchLabel = UILabel()
    private var isTorchOn = false
    private lazy var planCard = Self.plata(radio: 24)
    private let planCardTitle = UILabel()
    private let planCardExpand = UIButton(type: .system)
    private let minimapa = MinimapaVista()
    private var planCardW: NSLayoutConstraint?
    private var planCardH: NSLayoutConstraint?
    private var planCardGrande = false
    private let scanCaptionIcon = UIImageView()
    private let scanCaptionLabel = UILabel()
    private let scanCaption = UIStackView()
    private lazy var bottomSheet = Self.plata(radio: 32)
    private let sheetStack = UIStackView()
    private let sheetTitle = UILabel()
    private let sheetSubRow = UIStackView()
    private let sheetSubLabel = UILabel()
    private let cambiarNivelButton = UIButton(type: .system)
    private let campoCaja = UIView()
    private let campo = UITextField()
    private let nivelesCaption = UILabel()
    private let chipsScroll = UIScrollView()
    private let chipsStack = UIStackView()
    private let sheetDivider = UIView()
    private let buttonRow = UIStackView()
    private let continuarButton = UIButton(type: .system)
    private let terminarLink = UIButton(type: .system)
    private let sheetStatusRow = UIStackView()
    private let sheetStatusSpinner = UIActivityIndicatorView(style: .medium)
    private let sheetStatusLabel = UILabel()
    // El paso del nivel: la bandeja lo pide al abrir. El escáner corre igual
    // que antes debajo; esto solo decide qué muestra la bandeja.
    private var eligiendoNivel = true
    private var nivelSeleccionado: String?
    // Los niveles REALES del proyecto, mandados por la web (Scanova: los del
    // trabajo; Field Reports: sus plantas). Si no llegan, las de siempre.
    var nivelesDelProyecto: [String] = []
    // LOS CUARTOS QUE YA HIZO EL PERSONAL (17-oct, Scanova): primero se crean
    // los niveles y cuartos a mano en Photos y el plano se escanea después. La
    // web manda los cuartos de cada nivel; los botones los enseñan primero y lo
    // dicho/escrito se empareja con el nombre del proyecto. Vacío (Field
    // Reports, páginas viejas) = exactamente como antes.
    var cuartosDelNivel: [String] = []
    var cuartosPorNivel: [String: [String]] = [:]
    private func cuartosDelProyectoAhora() -> [String] {
        let nivel = nivelSeleccionado ?? nivelBase
        if let l = cuartosPorNivel[nivel] { return l }
        if let k = cuartosPorNivel.keys.first(where: { Self.sinAcentos($0) == Self.sinAcentos(nivel) }) { return cuartosPorNivel[k] ?? [] }
        return nivel == nivelBase || cuartosPorNivel.isEmpty ? cuartosDelNivel : []
    }
    private func nombreDelProyecto(_ dicho: String) -> String {
        let lista = cuartosDelProyectoAhora()
        let otros = usadosPorOtros()
        let n = CuartosDelProyecto.emparejar(dicho, con: lista, traducir: Self.enIngles, usados: otros) ?? dicho
        // Con cuartos del proyecto: nunca dos cuartos con el mismo nombre.
        guard !lista.isEmpty else { return n }
        let tomados = Set(otros.map { CuartosDelProyecto.normal($0) })
        guard tomados.contains(CuartosDelProyecto.normal(n)) else { return n }
        var k = 2
        while tomados.contains(CuartosDelProyecto.normal("\(n) \(k)")) { k += 1 }
        return "\(n) \(k)"
    }
    // Nombres ya puestos a OTROS cuartos de este escaneo (sin el cuarto activo).
    private func usadosPorOtros() -> [String] {
        var u = voiceNames.compactMap { $0 }
        if let a = nombreActual(), let i = u.lastIndex(where: { CuartosDelProyecto.normal($0) == CuartosDelProyecto.normal(a) }) { u.remove(at: i) }
        return u
    }
    private var posicionTimer: Timer?
    private var posicionCamara: CGPoint?
    private var terminarAlAcabarCuarto = false
    private var campoTimer: Timer?
    private var instruccionActual: String?
    private var micTocadoEn: Date?
    private var descartarCapturaActual = false
    private var ignorarCampo = false
    private var validacionGen = 0
    private var instruccionApple: String?
    private var instruccionCalidad: String?
    private var enFlujoFinal = false
    private var revisandoTodo = false
    private var nombresDeNivel: [Int: String] = [:]
    private var problemasFinales: [Problema] = []
    private var segundoCerebro: [String: Any] = [:]
    struct Problema { let grupo: Int; let tipo: String; let ft: Double; let a: CGPoint; let b: CGPoint }
    private var siguienteAlAcabarCuarto = false
    // COMPLETAR UN CUARTO (su "escanear solo lo que falta y unirlo", 13-oct).
    // RoomPlan no deja reabrir un cuarto entregado, así que la parte que falta
    // se escanea como una captura aparte (un "parche") y al terminar se une
    // a su cuarto: las paredes que el cuarto ya tenía no se repiten.
    private var completandoIndice: Int?
    private var indicesParche = Set<Int>()
    private var parcheDe: [Int: Int] = [:]
    private var incompletos = Set<Int>()
    private var huecosPorGrupo: [Int: [(CGPoint, CGPoint)]] = [:]
    // LOS MARCOS (14-oct, la casa de Harold: "puso un cuarto encima de la
    // cocina"). Cada captura de RoomPlan arranca con SU propio origen: ARKit
    // pone el (0,0) donde está el teléfono al empezar. Las paredes de dos
    // capturas distintas NO se pueden juntar ni comparar tal cual; antes se
    // juntaban (el parche con su cuarto, la caminata con todos los cuartos,
    // el minimapa con todo) y de ahí salían cuartos encimados y avisos que no
    // eran. Aquí se lleva la cuenta de qué captura es cada cuarto y del
    // movimiento que lleva cada uno al plano.
    private var capturaActual = 0
    private var capturaDeCuarto: [Int: Int] = [:]
    // Cuarto i (como lo entregó RoomPlan) -> el plano en vivo (el último
    // merge de Apple). Se saca de las MISMAS paredes antes y después.
    private var marcoVivo: [Int: FloorPlanEncoder.Rigido2D] = [:]
    // Parche p -> su cuarto. Lo saca Apple juntando los dos (StructureBuilder
    // con solo esos dos); si no cuadra, el parche NO se pega.
    private var alineacionParche: [Int: FloorPlanEncoder.Rigido2D] = [:]
    private var parcheSinAlinear = Set<Int>()
    private var alineandoParches = false
    private var alListosLosMarcos: [() -> Void] = []
    // "Terminar" tocado con la captura siguiente ya andando: si lo que trajo
    // es el mismo cuarto donde estaba parado, se junta con ese cuarto (como
    // un parche) en vez de guardarse como otro cuarto encima.
    private var posiblesDuplicados = Set<Int>()
    // El nivel en que iba antes de "Completar" un cuarto de otro piso.
    private var nivelAntesDeCompletar: Int?
    // La entrega va con los cuartos tal como se escanearon (sin StructureBuilder:
    // un solo cuarto, merge que falló o el vigilante): cada uno ya está en su marco.
    private var entregaCruda = false
    private struct ParAlineado { let t: FloorPlanEncoder.Rigido2D; let frac: Double; let dentro: Bool }
    private struct Aviso { let grupo: Int; let titulo: String; let terminar: Bool }
    private var aviso: Aviso?
    private var enRevisionFinal = false
    private var excluidosDelMerge: Set<Int> { deletedRoomIndices.union(indicesParche) }
    private func parches(de g: Int) -> [Int] { parcheDe.filter { $0.value == g }.map { $0.key }.sorted() }
    private func grupoDe(_ i: Int) -> Int { parcheDe[i] ?? i }
    // El aviso ámbar y la revisión final, dentro de la misma bandeja.
    private let avisoCaja = UIView()
    private let avisoTitulo = UILabel()
    private let avisoSub = UILabel()
    private let completarButton = UIButton(type: .system)
    private let continuarIgualButton = UIButton(type: .system)
    private let avisoNota = UILabel()
    private let avisoBadge = UILabel()
    private let revisionCaja = UIStackView()
    private let revisionSelector = UISegmentedControl(items: ["2D", "3D"])
    private let revisionVisor = UIView()
    private let planoGrande = MinimapaVista()
    private let vista3D = SCNView()
    private var tresDCargado = false
    private let revisionDatos = UILabel()
    private let guardarButton = UIButton(type: .system)
    private let seguirButton = UIButton(type: .system)
    private let otroNivelButton = UIButton(type: .system)
    // La barra con el cuarto ya escogido (su diseño del 13-oct): "Kitchen ·
    // First Floor", el campo, y "Siguiente cuarto" | "Terminar".
    private let filaSiguiente = UIStackView()
    private let siguienteButton = UIButton(type: .system)
    private let terminarButton = UIButton(type: .system)
    // EL CUARTO EN VIVO (su "sí, dibujarlo en vivo" del 13-oct): se escucha
    // al escáner por un intermediario que le pasa TODO primero al dueño
    // original (la pantalla de Apple) y solo después nos da una copia, como
    // mucho dos veces por segundo.
    private let enVivo = DelegadoEnVivo()
    private var cuartoEnVivo: MiniCuarto?
    private var huecosEnVivo: [(CGPoint, CGPoint)] = []
    // RoomPlan va corrigiendo el cuarto y a veces suelta una pared un
    // momento. Cada pared (y abertura) que ya se vio se sostiene unos
    // segundos en el dibujo, para que el mapita no parpadee.
    private var paredesVistas: [UUID: (linea: (CGPoint, CGPoint), t: CFTimeInterval)] = [:]
    private var aberturasVistas: [UUID: (linea: (CGPoint, CGPoint), tipo: MiniCuarto.Tipo, t: CFTimeInterval)] = [:]
    // La bandeja recogida: con el cuarto ya nombrado, solo quedan los botones.
    private var bandejaRecogida = false
    private var nombrePendienteDePintar = false
    private var chipsFirma = ""
    private let voiceCaptionLabel = UILabel()

    // Quick-pick room-name buttons (tap OR speak - either names the room).
    // A job site is noisy and speech recognition can fail for reasons that
    // have nothing to do with this app (a fan running, a mask muffling the
    // voice) - tapping a button always works, and is available the whole
    // time a room is being scanned, not just at fixed prompt moments.
    private static let roomOptionNames = [
        "Sala", "Cocina", "Recámara", "Baño", "Clóset", "Comedor",
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
        NSLog("[RoomScan] build tag: 2026-10-14-marcos (cada captura en su marco, parche acomodado por Apple)")
        view.backgroundColor = .black
        captureView.delegate = self
        // Sin el modelito 3D de Apple abajo: el plano en vivo ya está en el
        // minimapa, y él pidió la cámara libre (13-oct).
        captureView.isModelEnabled = false
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
        scanAnotherButton.setTitle("Escanear otro cuarto", for: .normal)
        nextLevelButton.setTitle("Otro nivel (ej. piso de arriba)", for: .normal)
        finishButton.setTitle("Terminar y unir plano", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelarBandejaTapped), for: .touchUpInside)
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
        promptStack.alignment = .center
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
        micToggleButton.addTarget(self, action: #selector(micCampoTapped), for: .touchUpInside)
        micToggleButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(micLargoTapped(_:))))

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

        armarDisenoNuevo()
        view.addSubview(statusLabel)
        view.addSubview(voiceCaptionLabel)
        view.addSubview(undoDeleteButton)
        // El croquis negro de arriba ya no se enseña: lo reemplaza el
        // minimapa. Se sigue alimentando igual (no se tocó el merge en vivo).
        floorPlanPanelView.isHidden = true
        if soloVistaPrevia {
            let fondo = CAGradientLayer()
            fondo.colors = [UIColor(red: 0.62, green: 0.57, blue: 0.50, alpha: 1).cgColor,
                            UIColor(red: 0.40, green: 0.36, blue: 0.31, alpha: 1).cgColor]
            fondo.frame = UIScreen.main.bounds
            let capa = UIView(frame: UIScreen.main.bounds)
            capa.layer.addSublayer(fondo)
            let aviso = UILabel(frame: CGRect(x: 0, y: UIScreen.main.bounds.midY * 0.75, width: UIScreen.main.bounds.width, height: 40))
            aviso.text = "(aquí se ve la cámara)"
            aviso.textAlignment = .center
            aviso.textColor = UIColor.white.withAlphaComponent(0.6)
            aviso.font = .systemFont(ofSize: 17)
            capa.addSubview(aviso)
            view.insertSubview(capa, aboveSubview: captureView)
        }

        // Márgenes parejos: 20 arriba y a los lados; abajo, junto a la raya
        // de inicio del iPhone (nunca debajo de ella).
        let pieDeBandeja = sheetStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6)
        pieDeBandeja.priority = .defaultHigh
        planCardW = planCard.widthAnchor.constraint(equalToConstant: 136)
        planCardH = planCard.heightAnchor.constraint(equalToConstant: 124)

        NSLayoutConstraint.activate([
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

            // La cámara ocupa TODA la pantalla.
            captureView.topAnchor.constraint(equalTo: view.topAnchor),
            captureView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            captureView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            captureView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            torchButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            torchButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            torchButton.widthAnchor.constraint(equalToConstant: 56),
            torchButton.heightAnchor.constraint(equalToConstant: 56),
            torchLabel.topAnchor.constraint(equalTo: torchButton.bottomAnchor, constant: 4),
            torchLabel.centerXAnchor.constraint(equalTo: torchButton.centerXAnchor),

            planCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            planCard.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            planCardW!, planCardH!,
            planCardTitle.topAnchor.constraint(equalTo: planCard.contentView.topAnchor, constant: 9),
            planCardTitle.leadingAnchor.constraint(equalTo: planCard.contentView.leadingAnchor, constant: 12),
            planCardTitle.trailingAnchor.constraint(lessThanOrEqualTo: planCardExpand.leadingAnchor, constant: -4),
            planCardExpand.centerYAnchor.constraint(equalTo: planCardTitle.centerYAnchor),
            planCardExpand.trailingAnchor.constraint(equalTo: planCard.contentView.trailingAnchor, constant: -6),
            planCardExpand.widthAnchor.constraint(equalToConstant: 30),
            planCardExpand.heightAnchor.constraint(equalToConstant: 30),
            minimapa.topAnchor.constraint(equalTo: planCardTitle.bottomAnchor, constant: 2),
            minimapa.leadingAnchor.constraint(equalTo: planCard.contentView.leadingAnchor, constant: 4),
            minimapa.trailingAnchor.constraint(equalTo: planCard.contentView.trailingAnchor, constant: -4),
            minimapa.bottomAnchor.constraint(equalTo: planCard.contentView.bottomAnchor, constant: -4),

            bottomSheet.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomSheet.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomSheet.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 40),
            sheetStack.topAnchor.constraint(equalTo: bottomSheet.contentView.topAnchor, constant: 20),
            sheetStack.leadingAnchor.constraint(equalTo: bottomSheet.contentView.leadingAnchor, constant: 20),
            sheetStack.trailingAnchor.constraint(equalTo: bottomSheet.contentView.trailingAnchor, constant: -20),
            pieDeBandeja,
            sheetStack.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -10),

            scanCaption.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanCaption.bottomAnchor.constraint(equalTo: bottomSheet.topAnchor, constant: -18),
            scanCaption.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),

            campoCaja.heightAnchor.constraint(equalToConstant: 50),
            campo.leadingAnchor.constraint(equalTo: campoCaja.leadingAnchor, constant: 20),
            campo.centerYAnchor.constraint(equalTo: campoCaja.centerYAnchor),
            campo.trailingAnchor.constraint(equalTo: micToggleButton.leadingAnchor, constant: -8),
            micToggleButton.trailingAnchor.constraint(equalTo: campoCaja.trailingAnchor, constant: -5),
            micToggleButton.centerYAnchor.constraint(equalTo: campoCaja.centerYAnchor),
            micToggleButton.widthAnchor.constraint(equalToConstant: 40),
            micToggleButton.heightAnchor.constraint(equalToConstant: 40),

            chipsScroll.heightAnchor.constraint(equalToConstant: 40),
            chipsStack.topAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.topAnchor),
            chipsStack.bottomAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.bottomAnchor),
            chipsStack.leadingAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.leadingAnchor),
            chipsStack.trailingAnchor.constraint(equalTo: chipsScroll.contentLayoutGuide.trailingAnchor),
            chipsStack.heightAnchor.constraint(equalTo: chipsScroll.frameLayoutGuide.heightAnchor),

            sheetDivider.heightAnchor.constraint(equalToConstant: 1),
            buttonRow.heightAnchor.constraint(equalToConstant: 48),
            roomSplitButtonsStack.heightAnchor.constraint(equalToConstant: 48),

            voiceCaptionLabel.topAnchor.constraint(equalTo: planCard.bottomAnchor, constant: 12),
            voiceCaptionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            voiceCaptionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            voiceCaptionLabel.heightAnchor.constraint(equalToConstant: 30),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            undoDeleteButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            undoDeleteButton.topAnchor.constraint(equalTo: voiceCaptionLabel.bottomAnchor, constant: 10)
        ])

        updateUI()
    }

    // MARK: - El diseño nuevo de la cámara (solo presentación)

    private static let tinta = UIColor(white: 0.08, alpha: 1)
    private static let tintaSuave = UIColor(white: 0.36, alpha: 1)
    private static let plataControl = UIColor.white.withAlphaComponent(0.55)
    private static let bordePlata = UIColor.white.withAlphaComponent(0.75)

    // El vidrio plateado translúcido de su diseño.
    private static func plata(radio: CGFloat) -> UIVisualEffectView {
        let v = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight))
        v.translatesAutoresizingMaskIntoConstraints = false
        v.overrideUserInterfaceStyle = .light
        v.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.42)
        v.layer.cornerRadius = radio
        v.layer.cornerCurve = .continuous
        v.clipsToBounds = true
        v.layer.borderWidth = 1
        v.layer.borderColor = bordePlata.cgColor
        return v
    }

    private static func capsula(_ b: UIButton, titulo: String, azul: Bool, tam: CGFloat = 18) {
        var c = UIButton.Configuration.filled()
        c.cornerStyle = .capsule
        c.title = titulo
        c.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 26, bottom: 0, trailing: 26)
        c.titleLineBreakMode = .byClipping
        c.baseBackgroundColor = azul ? .systemBlue : plataControl
        c.baseForegroundColor = azul ? .white : tinta
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var a = a; a.font = UIFont.systemFont(ofSize: tam, weight: .regular); return a
        }
        b.configuration = c
        b.setTitle(titulo, for: .normal)
        b.setTitleColor(azul ? .white : tinta, for: .normal)
        b.backgroundColor = nil
        b.layer.cornerRadius = 24
        b.setContentHuggingPriority(.required, for: .horizontal)
        b.setContentCompressionResistancePriority(.required, for: .horizontal)
        b.titleLabel?.numberOfLines = 1
        b.layer.cornerCurve = .continuous
        b.layer.borderWidth = azul ? 0 : 1
        b.layer.borderColor = bordePlata.cgColor
    }

    private func armarDisenoNuevo() {
        let sombra: (UIView) -> Void = { v in
            v.layer.shadowColor = UIColor.black.cgColor
            v.layer.shadowOpacity = 0.55
            v.layer.shadowRadius = 4
            v.layer.shadowOffset = .zero
        }

        // El letrero flotante del diseño viejo no sale nunca (todos sus caminos).
        voiceCaptionLabel.alpha = 0
        // --- Linterna (arriba a la izquierda, con su nombre debajo)
        torchButton.translatesAutoresizingMaskIntoConstraints = false
        torchButton.backgroundColor = UIColor.white.withAlphaComponent(0.42)
        torchButton.layer.cornerRadius = 28
        torchButton.layer.borderWidth = 1
        torchButton.layer.borderColor = Self.bordePlata.cgColor
        torchButton.tintColor = .white
        torchButton.setImage(UIImage(systemName: "flashlight.off.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)), for: .normal)
        torchButton.accessibilityLabel = "Linterna"
        torchButton.addTarget(self, action: #selector(torchTapped), for: .touchUpInside)
        torchLabel.translatesAutoresizingMaskIntoConstraints = false
        torchLabel.text = "Linterna"
        torchLabel.textColor = .white
        torchLabel.font = .systemFont(ofSize: 15, weight: .medium)
        sombra(torchLabel)
        let hayLinterna = (AVCaptureDevice.default(for: .video)?.hasTorch ?? false) || soloVistaPrevia
        torchButton.isHidden = !hayLinterna
        torchLabel.isHidden = !hayLinterna
        view.addSubview(torchButton)
        view.addSubview(torchLabel)

        // --- Minimapa (arriba a la derecha)
        view.addSubview(planCard)
        planCardTitle.translatesAutoresizingMaskIntoConstraints = false
        planCardTitle.textColor = Self.tintaSuave
        planCardTitle.font = .systemFont(ofSize: 13, weight: .medium)
        planCardExpand.translatesAutoresizingMaskIntoConstraints = false
        planCardExpand.tintColor = Self.tintaSuave
        planCardExpand.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)), for: .normal)
        planCardExpand.accessibilityLabel = "Agrandar el plano"
        planCardExpand.addTarget(self, action: #selector(planCardExpandTapped), for: .touchUpInside)
        minimapa.translatesAutoresizingMaskIntoConstraints = false
        [planCardTitle, planCardExpand, minimapa].forEach { planCard.contentView.addSubview($0) }

        // --- Lo que dice arriba de la bandeja ("Escaneando Cocina…")
        scanCaption.translatesAutoresizingMaskIntoConstraints = false
        scanCaption.axis = .vertical
        scanCaption.alignment = .center
        scanCaption.spacing = 10
        scanCaptionIcon.image = UIImage(systemName: "iphone.radiowaves.left.and.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 40, weight: .light))
        scanCaptionIcon.tintColor = .white
        scanCaptionLabel.textColor = .white
        scanCaptionLabel.font = .systemFont(ofSize: 18, weight: .medium)
        scanCaptionLabel.textAlignment = .center
        scanCaptionLabel.numberOfLines = 2
        sombra(scanCaptionIcon); sombra(scanCaptionLabel)
        scanCaption.isUserInteractionEnabled = true
        scanCaption.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(captionTocado)))
        scanCaption.addArrangedSubview(scanCaptionIcon)
        scanCaption.addArrangedSubview(scanCaptionLabel)
        view.addSubview(scanCaption)

        // --- La bandeja plateada de abajo
        view.addSubview(bottomSheet)
        bottomSheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        sheetStack.translatesAutoresizingMaskIntoConstraints = false
        sheetStack.axis = .vertical
        sheetStack.spacing = 12
        bottomSheet.contentView.addSubview(sheetStack)

        sheetTitle.textColor = Self.tinta
        sheetTitle.font = .systemFont(ofSize: 22, weight: .semibold)

        sheetSubLabel.textColor = Self.tintaSuave
        sheetSubLabel.font = .systemFont(ofSize: 15)
        cambiarNivelButton.setTitle("Cambiar nivel", for: .normal)
        cambiarNivelButton.setTitleColor(Self.tintaSuave, for: .normal)
        cambiarNivelButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        cambiarNivelButton.contentHorizontalAlignment = .leading
        cambiarNivelButton.addTarget(self, action: #selector(cambiarNivelTapped), for: .touchUpInside)
        sheetSubRow.axis = .horizontal
        sheetSubRow.spacing = 4
        sheetSubRow.addArrangedSubview(sheetSubLabel)
        sheetSubRow.addArrangedSubview(cambiarNivelButton)
        sheetSubRow.addArrangedSubview(UIView())

        // El campo: escribir, o dictar con el micrófono azul de adentro.
        campoCaja.backgroundColor = UIColor.white.withAlphaComponent(0.62)
        campoCaja.layer.cornerRadius = 25
        campoCaja.layer.cornerCurve = .continuous
        campoCaja.layer.borderWidth = 1
        campoCaja.layer.borderColor = Self.bordePlata.cgColor
        campo.translatesAutoresizingMaskIntoConstraints = false
        campo.font = .systemFont(ofSize: 19)
        campo.textColor = Self.tinta
        campo.tintColor = .systemBlue
        campo.autocapitalizationType = .sentences
        campo.autocorrectionType = .no
        campo.returnKeyType = .done
        campo.clearButtonMode = .never
        campo.addTarget(self, action: #selector(campoReturn), for: .editingDidEndOnExit)
        campo.addTarget(self, action: #selector(campoCambio), for: .editingChanged)
        campo.addTarget(self, action: #selector(campoListo), for: .editingDidEnd)
        micToggleButton.translatesAutoresizingMaskIntoConstraints = false
        micToggleButton.setTitle(nil, for: .normal)
        micToggleButton.layer.cornerRadius = 20
        micToggleButton.layer.masksToBounds = true
        micToggleButton.accessibilityLabel = "Dictar"
        campoCaja.addSubview(campo)
        campoCaja.addSubview(micToggleButton)

        nivelesCaption.text = "Niveles del proyecto"
        nivelesCaption.textColor = Self.tintaSuave
        nivelesCaption.font = .systemFont(ofSize: 15)

        chipsScroll.showsHorizontalScrollIndicator = false
        chipsScroll.clipsToBounds = false
        chipsStack.translatesAutoresizingMaskIntoConstraints = false
        chipsStack.axis = .horizontal
        chipsStack.spacing = 8
        chipsStack.alignment = .center
        chipsScroll.addSubview(chipsStack)

        sheetDivider.backgroundColor = UIColor.black.withAlphaComponent(0.08)

        Self.capsula(cancelButton, titulo: "Cancelar", azul: false)
        Self.capsula(doneButton, titulo: "Cuarto listo", azul: true)
        Self.capsula(continuarButton, titulo: "Continuar", azul: true)
        continuarButton.addTarget(self, action: #selector(continuarTapped), for: .touchUpInside)
        // Una fila compacta, centrada: cada botón mide lo que su texto.
        buttonRow.axis = .horizontal
        buttonRow.spacing = 12
        buttonRow.alignment = .center
        let orillaIzq = UIView(), orillaDer = UIView()
        [orillaIzq, cancelButton, doneButton, continuarButton, orillaDer].forEach { buttonRow.addArrangedSubview($0) }
        orillaIzq.widthAnchor.constraint(equalTo: orillaDer.widthAnchor).isActive = true
        [cancelButton, doneButton, continuarButton].forEach {
            $0.heightAnchor.constraint(equalToConstant: 48).isActive = true
            $0.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        }

        Self.capsula(siguienteButton, titulo: "Siguiente cuarto", azul: true)
        Self.capsula(terminarButton, titulo: "Terminar", azul: false)
        siguienteButton.addTarget(self, action: #selector(siguienteTapped), for: .touchUpInside)
        terminarButton.addTarget(self, action: #selector(terminarTapped), for: .touchUpInside)
        siguienteButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        filaSiguiente.axis = .horizontal
        filaSiguiente.spacing = 12
        filaSiguiente.addArrangedSubview(siguienteButton)
        filaSiguiente.addArrangedSubview(terminarButton)
        siguienteButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        terminarButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        terminarButton.widthAnchor.constraint(equalTo: siguienteButton.widthAnchor, multiplier: 0.58).isActive = true
        terminarLink.setTitle("Terminar", for: .normal)
        terminarLink.setTitleColor(.systemBlue, for: .normal)
        terminarLink.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        terminarLink.addTarget(self, action: #selector(terminarTapped), for: .touchUpInside)

        // Los botones de "cuarto listo" (otro cuarto, otro nivel, terminar)
        // con la misma forma; el principal en azul.
        for b in [scanAnotherButton, nextLevelButton, finishButton] {
            Self.capsula(b, titulo: b.currentTitle ?? "", azul: b === scanAnotherButton, tam: 17)
            b.heightAnchor.constraint(equalToConstant: 48).isActive = true
        }
        repeatRoomButton.layer.cornerRadius = 24
        repeatRoomButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        promptStack.spacing = 10
        promptStack.alignment = .center

        // "¿Cuarto nuevo o corregir?": los mismos botones, con este estilo.
        Self.capsula(newRoomButton, titulo: "Cuarto nuevo", azul: true, tam: 17)
        Self.capsula(correctNameButton, titulo: "Corregir nombre", azul: false, tam: 17)
        newRoomButton.layer.cornerRadius = 24
        correctNameButton.layer.cornerRadius = 24

        roomSummaryLabel.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        roomSummaryLabel.textColor = Self.tinta
        roomSummaryLabel.font = .systemFont(ofSize: 14, weight: .medium)
        roomSummaryLabel.layer.cornerRadius = 16

        sheetStatusRow.axis = .horizontal
        sheetStatusRow.spacing = 10
        sheetStatusRow.alignment = .center
        sheetStatusRow.isLayoutMarginsRelativeArrangement = true
        sheetStatusRow.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        sheetStatusSpinner.color = Self.tinta
        sheetStatusLabel.textColor = Self.tinta
        sheetStatusLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        let relleno1 = UIView(), relleno2 = UIView()
        [relleno1, sheetStatusSpinner, sheetStatusLabel, relleno2].forEach { sheetStatusRow.addArrangedSubview($0) }
        relleno1.widthAnchor.constraint(equalTo: relleno2.widthAnchor).isActive = true

        armarAvisoYRevision()
        [sheetTitle, sheetSubRow, roomSummaryLabel, avisoCaja, completarButton, continuarIgualButton, avisoNota,
         revisionCaja, campoCaja, nivelesCaption, chipsScroll,
         roomSplitButtonsStack, sheetDivider, buttonRow, filaSiguiente, terminarLink, promptStack, sheetStatusRow].forEach {
            sheetStack.addArrangedSubview($0)
        }
        sheetStack.setCustomSpacing(2, after: sheetTitle)
        sheetStack.setCustomSpacing(12, after: sheetSubRow)
        sheetStack.setCustomSpacing(8, after: nivelesCaption)
        sheetStack.setCustomSpacing(14, after: chipsScroll)
        sheetStack.setCustomSpacing(14, after: sheetDivider)

        // Lo que mandó la web: el nivel ya escogido queda marcado.
        if nivelesDelProyecto.isEmpty { nivelesDelProyecto = Self.plantaValores }
        if !nivelBase.isEmpty {
            nivelSeleccionado = nivelBase
            if !nivelesDelProyecto.contains(nivelBase) { nivelesDelProyecto.append(nivelBase) }
        }
        pintarMic()
    }

    // MARK: Niveles

    private static let plantaValores = ["Basement", "1st Floor", "2nd Floor", "3rd Floor", "Attic"]
    private static let plantaVisible: [String: String] = [
        "1st Floor": "First Floor", "2nd Floor": "Second Floor", "3rd Floor": "Third Floor"
    ]
    private static func nombreVisible(_ valor: String) -> String { plantaVisible[valor] ?? valor }

    private static func sinAcentos(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Lo escrito o dictado -> uno de los niveles del proyecto. Primero por su
    // nombre tal cual; después por las palabras de siempre (en los dos idiomas).
    // Lo escrito o dictado -> uno de los niveles del proyecto. Por PALABRAS
    // enteras ("espérame un segundo" ya no es Second Floor) y solo frases
    // cortas; un número solo cuenta si viene casi solo ("2", "piso 2").
    private func nivelDeTexto(_ texto: String) -> String? {
        let t = Self.sinAcentos(texto)
        guard !t.isEmpty else { return nil }
        let tokens = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !tokens.isEmpty, tokens.count <= 3 else { return nil }
        for v in nivelesDelProyecto {
            let a = Self.sinAcentos(v), b = Self.sinAcentos(Self.nombreVisible(v))
            if t == a || t == b { return v }
        }
        for v in nivelesDelProyecto {
            let a = Self.sinAcentos(v), b = Self.sinAcentos(Self.nombreVisible(v))
            if (a.count >= 4 && t.contains(a)) || (b.count >= 4 && t.contains(b)) { return v }
        }
        let pisoWords: Set<String> = ["piso", "floor", "nivel", "planta", "level"]
        let soloOConPiso = tokens.count == 1 || (tokens.count <= 3 && tokens.contains(where: { pisoWords.contains($0) }))
        // Sótano y ático se reconocen solos; los ordinales ("segundo",
        // "primero", "2") solo si van solos o con piso/nivel/floor/planta:
        // "espérame un segundo" ya no es Second Floor.
        let tiene: (String) -> Bool = { w in
            let esLugar = ["sotano", "basement", "atico", "attic"].contains(w)
            return tokens.contains(w) && (esLugar || soloOConPiso)
        }
        let numeroSolo = soloOConPiso
        let claves: [(String, [String], String)] = [
            ("Basement", ["sotano", "basement"], ""),
            ("Attic", ["atico", "attic"], ""),
            ("3rd Floor", ["tercer", "tercero", "third"], "3"),
            ("2nd Floor", ["segundo", "second"], "2"),
            ("1st Floor", ["primer", "primero", "first"], "1")
        ]
        for (valor, palabras, digito) in claves where palabras.contains(where: tiene) || (numeroSolo && !digito.isEmpty && tokens.contains(digito)) {
            if let v = nivelesDelProyecto.first(where: { $0 == valor || Self.sinAcentos(Self.nombreVisible($0)) == Self.sinAcentos(Self.nombreVisible(valor)) }) {
                return v
            }
        }
        return nil
    }

    private func seleccionarNivel(_ valor: String) {
        nivelSeleccionado = valor
        if !campo.isEditing { campo.text = Self.nombreVisible(valor) }
        pintarBandeja()
    }

    // Continuar: el nivel queda puesto para este cuarto y los siguientes,
    // hasta Terminar. La bandeja cambia a "Seleccionar cuarto".
    @objc private func continuarTapped() {
        guard let v = nivelSeleccionado, !v.isEmpty else { return }
        cerrarCampoSinAplicar()
        let primeraVez = eligiendoNivel && capturedRooms.isEmpty && !cambiandoNivel
        if capturedRooms.isEmpty {
            nivelBase = v
            nombresDeNivel = Self.plantaValores.contains(v) ? [:] : [1: v]
            currentLevel = 1
        } else if nombresDeNivel.isEmpty, let i0 = Self.plantaValores.firstIndex(of: nivelBase),
                  let i1 = Self.plantaValores.firstIndex(of: v), i1 - i0 + 1 >= 1 {
            currentLevel = i1 - i0 + 1
        } else if !nombresDeNivel.isEmpty || Self.plantaDelValor[nivelBase] == nil || Self.plantaDelValor[v] == nil {
            // Al mezclar niveles con nombre propio, TODOS van por nombre: se
            // anotan primero los que ya se usaron, para que nunca dos niveles
            // distintos compartan número.
            if nombresDeNivel.isEmpty {
                for lvl in Set(roomLevels + [currentLevel]) { nombresDeNivel[lvl] = nombrePlantaEstandar(lvl) ?? nivelBase }
            }
            // Niveles con nombre propio (los del trabajo en Scanova): cada uno
            // con su número, por el nombre; el mismo nombre vuelve al mismo nivel.
            if nombresDeNivel.isEmpty { nombresDeNivel[1] = nivelBase }
            if let k = nombresDeNivel.first(where: { $0.value == v })?.key {
                currentLevel = k
            } else {
                let k = (Array(nombresDeNivel.keys) + roomLevels + [currentLevel]).max()! + 1
                nombresDeNivel[k] = v
                currentLevel = k
            }
        } else if v != nivelBase {
            // Un plano guarda los niveles contados desde el primero que se
            // escaneó; uno de abajo no cabe en el mismo plano.
            let a = UIAlertController(title: "No se puede en este plano",
                                      message: "Ese nivel queda abajo del primero que escaneó. Termine este plano y empiece otro en \(Self.nombreVisible(v)).",
                                      preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Entendido", style: .default))
            present(a, animated: true)
            return
        }
        eligiendoNivel = false
        cambiandoNivel = false
        campo.text = nil
        updateUI()
        if primeraVez && !soloVistaPrevia {
            speak("Listo, \(nombreHablado(currentLevel)). Recorre el cuarto y di listo cuando termines.") {}
        }
    }

    private var cambiandoNivel = false
    private func animarBandeja() {
        guard !campo.isEditing else { return }
        UIView.animate(withDuration: 0.25) {
            self.updateUI()
            self.view.layoutIfNeeded()
        }
    }

    // Tocar "Escaneando Cocina…" vuelve a abrir la bandeja para cambiar el nombre.
    @objc private func captionTocado() {
        guard state == .scanningRoom, bandejaRecogida else { return }
        bandejaRecogida = false
        animarBandeja()
    }

    @objc private func cambiarNivelTapped() {
        guard state == .scanningRoom || state == .roomDonePrompt else { return }
        cambiandoNivel = true
        eligiendoNivel = true
        bandejaRecogida = false
        nivelSeleccionado = capturedRooms.isEmpty ? nivelBase : nil
        campo.text = nil
        updateUI()
    }

    // MARK: Campo, chips y botones

    @objc private func campoCambio() {
        let t = (campo.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if eligiendoNivel {
            nivelSeleccionado = nivelDeTexto(t) ?? (t.isEmpty ? nil : t)
            pintarBandeja()
        } else if !cuartosDelProyectoAhora().isEmpty {
            pintarChips()
            // Mientras lo escrito aún da sugerencias del proyecto y no es un nombre
            // exacto, no se guarda solo: espera a que toque una o cierre el teclado.
            let libres = CuartosDelProyecto.disponibles(proyecto: cuartosDelProyectoAhora(), usados: voiceNames.compactMap { $0 }, conservar: nombreActual())
            let s = CuartosDelProyecto.sugerencias(t, en: libres)
            if !t.isEmpty, !s.isEmpty, !s.contains(where: { CuartosDelProyecto.normal($0) == CuartosDelProyecto.normal(t) }) {
                campoTimer?.invalidate()
                campoTimer = nil
                return
            }
        }
        // Lo escrito (o dictado con el teclado) se guarda solo al dejar de
        // escribir: ya no hay que tocar un botón de abajo para que cuente.
        campoTimer?.invalidate()
        campoTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in
            self?.aplicarCampo(final: false)
        }
    }

    private func aplicarCampo(final: Bool) {
        campoTimer?.invalidate()
        campoTimer = nil
        let t = (campo.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if eligiendoNivel {
            // Solo pasa solo si es uno de los niveles del proyecto; un nombre
            // propio espera a que toque Continuar.
            if let v = nivelDeTexto(t) {
                seleccionarNivel(v)
                let exacto = Self.sinAcentos(t) == Self.sinAcentos(v) || Self.sinAcentos(t) == Self.sinAcentos(Self.nombreVisible(v))
                if final || exacto { continuarTapped() }
            }
            return
        }
        guard state == .scanningRoom || state == .roomDonePrompt, aviso == nil, !enRevisionFinal, !revisandoTodo else { return }
        let crudo = nombreActual() ?? ""
        guard Self.sinAcentos(t) != Self.sinAcentos(crudo), Self.sinAcentos(t) != Self.sinAcentos(Self.enIngles(crudo)) else {
            if final { animarBandeja() }
            return
        }
        applyHeardOrTappedName(t, viaButton: true)
        if final { animarBandeja() }
    }

    @objc private func campoReturn() {}

    // Cerrar el teclado SIN que cuente lo escrito (Cancelar, o un botón que
    // ya decidió otra cosa).
    private func cerrarCampoSinAplicar() {
        campoTimer?.invalidate()
        campoTimer = nil
        ignorarCampo = true
        campo.resignFirstResponder()
        ignorarCampo = false
    }

    @objc private func campoListo() {
        if ignorarCampo { return }
        let t = (campo.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if eligiendoNivel {
            if !t.isEmpty { nivelSeleccionado = nivelDeTexto(t) ?? t }
            pintarBandeja()
            aplicarCampo(final: true)
            return
        }
        guard !t.isEmpty else { pintarNombre(); return }
        aplicarCampo(final: true)
    }

    private func nombresDeCuarto() -> [String] {
        // Con cuartos del proyecto en este nivel: SOLO esos, sin los ya puestos en este
        // escaneo, y al escribir solo los que empiezan con lo escrito.
        let delProyecto = cuartosDelProyectoAhora()
        if !delProyecto.isEmpty {
            let libres = CuartosDelProyecto.disponibles(proyecto: delProyecto, usados: voiceNames.compactMap { $0 }, conservar: nombreActual())
            let escrito = campo.isFirstResponder ? (campo.text ?? "") : ""
            if !libres.isEmpty {
                let s = CuartosDelProyecto.sugerencias(escrito, en: libres)
                return s.isEmpty ? libres : s
            }
            // Ya se usaron todos los del proyecto: los de siempre, para que la bandeja nunca quede vacía.
            let tomados = Set(voiceNames.compactMap { $0 }.map { CuartosDelProyecto.normal($0) })
            return Self.roomOptionNames.filter { !tomados.contains(CuartosDelProyecto.normal($0)) }
        }
        var nombres = CuartosDelProyecto.botones(proyecto: cuartosDelProyectoAhora(), deSiempre: Self.roomOptionNames)
        // Los del proyecto: los que ya se usaron en este plano y los que este
        // teléfono ya aprendió de él.
        let usados = voiceNames.compactMap { $0 } + learnedRoomNames.sorted().map { $0.prefix(1).uppercased() + $0.dropFirst() }
        for n in usados where !Self.traeOrden(n) && !nombres.contains(where: { Self.sinAcentos($0) == Self.sinAcentos(n) }) {
            nombres.append(n)
        }
        return nombres
    }

    private func nombreActual() -> String? {
        if state == .roomDonePrompt, let last = capturedRooms.last {
            return voiceNames.last.flatMap { $0 } ?? suggestedRoomName(for: last)
        }
        return pendingCurrentRoomName
    }

    private func pintarChips() {
        let opciones: [(titulo: String, valor: String)]
        let activo: String?
        if eligiendoNivel {
            opciones = nivelesDelProyecto.map { (Self.nombreVisible($0), $0) }
            activo = nivelSeleccionado
        } else {
            opciones = nombresDeCuarto().map { ($0, $0) }
            activo = nombreActual()
        }
        let firma = (eligiendoNivel ? "N|" : "C|") + opciones.map { $0.valor }.joined(separator: "|") + "#" + (activo ?? "")
        guard firma != chipsFirma else { return }
        chipsFirma = firma
        chipsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for o in opciones {
            let encendido = activo.map { Self.sinAcentos($0) == Self.sinAcentos(o.valor) } ?? false
            let b = UIButton(type: .system)
            var c = UIButton.Configuration.filled()
            c.cornerStyle = .capsule
            c.title = o.titulo
            c.baseBackgroundColor = encendido ? .systemBlue : Self.plataControl
            c.baseForegroundColor = encendido ? .white : Self.tinta
            c.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 18)
            c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
                var a = a; a.font = UIFont.systemFont(ofSize: 16, weight: .regular); return a
            }
            b.configuration = c
            b.layer.cornerRadius = 20
            b.layer.borderWidth = encendido ? 0 : 1
            b.layer.borderColor = Self.bordePlata.cgColor
            b.heightAnchor.constraint(equalToConstant: 40).isActive = true
            b.setContentHuggingPriority(.required, for: .horizontal)
            b.setContentCompressionResistancePriority(.required, for: .horizontal)
            let valor = o.valor
            b.addAction(UIAction { [weak self] _ in
                guard let self = self else { return }
                if self.eligiendoNivel {
                    self.seleccionarNivel(valor)
                } else {
                    self.cerrarCampoSinAplicar()
                    self.applyHeardOrTappedName(valor, viaButton: true)
                }
            }, for: .touchUpInside)
            chipsStack.addArrangedSubview(b)
        }
    }

    private func pintarBandeja() {
        let elegido = !(nivelSeleccionado ?? "").isEmpty
        var c = continuarButton.configuration
        c?.baseBackgroundColor = elegido ? .systemBlue : UIColor(white: 0.62, alpha: 0.75)
        c?.baseForegroundColor = elegido ? .white : UIColor.white.withAlphaComponent(0.85)
        continuarButton.configuration = c
        continuarButton.isEnabled = elegido
        pintarChips()
    }

    // El nombre que se ve en el campo: el del cuarto que se está escaneando
    // (o el que acaba de terminar); si no tiene, el campo lo pide.
    private func pedirPintarNombre() {
        guard !nombrePendienteDePintar else { return }
        nombrePendienteDePintar = true
        DispatchQueue.main.async { [weak self] in
            self?.nombrePendienteDePintar = false
            self?.pintarNombre()
        }
    }

    private func pintarNombre() {
        if eligiendoNivel {
            campo.placeholder = "Escribe o dicta el nivel"
            if !campo.isEditing { campo.text = nivelSeleccionado.map { Self.nombreVisible($0) } }
        } else {
            let n = state == .roomDonePrompt ? max(numeroSiguiente - 1, 1) : numeroSiguiente
            campo.placeholder = "Cuarto \(n) · escribe o dicta"
            if !campo.isEditing { campo.text = nombreActual().map { Self.enIngles($0) } }
        }
        pintarBandeja()
        refrescarMinimapa()
    }

    private func pintarMic() {
        let simbolo = micMuted ? "mic.slash.fill" : "mic.fill"
        micToggleButton.setTitle(nil, for: .normal)
        micToggleButton.setImage(UIImage(systemName: simbolo, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)), for: .normal)
        micToggleButton.backgroundColor = micMuted ? UIColor(white: 0.6, alpha: 0.8) : .systemBlue
        micToggleButton.tintColor = .white
    }

    private func armarAvisoYRevision() {
        // El aviso ámbar: "Falta un lado del cuarto / Puedes completarlo o continuar."
        avisoCaja.backgroundColor = UIColor(red: 1.0, green: 0.93, blue: 0.80, alpha: 0.92)
        avisoCaja.layer.cornerRadius = 22
        avisoCaja.layer.cornerCurve = .continuous
        avisoCaja.layer.borderWidth = 1
        avisoCaja.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        let icono = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill",
                                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)))
        icono.tintColor = .systemOrange
        icono.contentMode = .scaleAspectFit
        icono.translatesAutoresizingMaskIntoConstraints = false
        icono.setContentHuggingPriority(.required, for: .horizontal)
        avisoTitulo.font = .systemFont(ofSize: 18, weight: .semibold)
        avisoTitulo.textColor = UIColor(red: 0.55, green: 0.33, blue: 0.0, alpha: 1)
        avisoSub.font = .systemFont(ofSize: 15)
        avisoSub.textColor = Self.tintaSuave
        avisoSub.text = "Puedes completarlo o continuar."
        let textos = UIStackView(arrangedSubviews: [avisoTitulo, avisoSub])
        textos.axis = .vertical
        textos.spacing = 2
        textos.translatesAutoresizingMaskIntoConstraints = false
        avisoCaja.addSubview(icono)
        avisoCaja.addSubview(textos)
        NSLayoutConstraint.activate([
            icono.leadingAnchor.constraint(equalTo: avisoCaja.leadingAnchor, constant: 22),
            icono.centerYAnchor.constraint(equalTo: avisoCaja.centerYAnchor),
            icono.widthAnchor.constraint(equalToConstant: 30),
            icono.heightAnchor.constraint(equalToConstant: 28),
            textos.leadingAnchor.constraint(equalTo: icono.trailingAnchor, constant: 16),
            textos.trailingAnchor.constraint(equalTo: avisoCaja.trailingAnchor, constant: -16),
            textos.topAnchor.constraint(equalTo: avisoCaja.topAnchor, constant: 14),
            textos.bottomAnchor.constraint(equalTo: avisoCaja.bottomAnchor, constant: -14)
        ])
        Self.capsula(completarButton, titulo: "Completar escaneo", azul: true)
        Self.capsula(continuarIgualButton, titulo: "Continuar de todos modos", azul: false)
        for b in [completarButton, continuarIgualButton] {
            b.heightAnchor.constraint(equalToConstant: 52).isActive = true
            b.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        completarButton.addTarget(self, action: #selector(completarTapped), for: .touchUpInside)
        continuarIgualButton.addTarget(self, action: #selector(continuarIgualTapped), for: .touchUpInside)
        avisoNota.text = "Se guardará como escaneo incompleto."
        avisoNota.font = .systemFont(ofSize: 14)
        avisoNota.textColor = Self.tintaSuave
        avisoNota.textAlignment = .center
        // El "!" junto al minimapa.
        avisoBadge.translatesAutoresizingMaskIntoConstraints = false
        avisoBadge.text = "!"
        avisoBadge.textAlignment = .center
        avisoBadge.textColor = .white
        avisoBadge.font = .systemFont(ofSize: 15, weight: .heavy)
        avisoBadge.backgroundColor = .systemOrange
        avisoBadge.layer.cornerRadius = 12
        avisoBadge.layer.masksToBounds = true
        avisoBadge.isHidden = true
        view.addSubview(avisoBadge)
        NSLayoutConstraint.activate([
            avisoBadge.widthAnchor.constraint(equalToConstant: 24),
            avisoBadge.heightAnchor.constraint(equalToConstant: 24),
            avisoBadge.centerXAnchor.constraint(equalTo: planCard.trailingAnchor),
            avisoBadge.centerYAnchor.constraint(equalTo: planCard.centerYAnchor, constant: 8)
        ])

        // La revisión final: 2D / 3D, los datos, y Guardar · Seguir escaneando · Otro nivel.
        revisionCaja.axis = .vertical
        revisionCaja.spacing = 12
        revisionSelector.selectedSegmentIndex = 0
        revisionSelector.selectedSegmentTintColor = .systemBlue
        revisionSelector.setTitleTextAttributes([.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 15, weight: .semibold)], for: .selected)
        revisionSelector.setTitleTextAttributes([.foregroundColor: Self.tinta, .font: UIFont.systemFont(ofSize: 15)], for: .normal)
        revisionSelector.addTarget(self, action: #selector(revisionSelectorCambio), for: .valueChanged)
        revisionVisor.backgroundColor = UIColor.white.withAlphaComponent(0.55)
        revisionVisor.layer.cornerRadius = 20
        revisionVisor.layer.cornerCurve = .continuous
        revisionVisor.layer.borderWidth = 1
        revisionVisor.layer.borderColor = Self.bordePlata.cgColor
        revisionVisor.clipsToBounds = true
        revisionVisor.heightAnchor.constraint(equalToConstant: min(320, UIScreen.main.bounds.height * 0.36)).isActive = true
        for v in [planoGrande, vista3D] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            revisionVisor.addSubview(v)
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: revisionVisor.topAnchor, constant: 8),
                v.leadingAnchor.constraint(equalTo: revisionVisor.leadingAnchor, constant: 8),
                v.trailingAnchor.constraint(equalTo: revisionVisor.trailingAnchor, constant: -8),
                v.bottomAnchor.constraint(equalTo: revisionVisor.bottomAnchor, constant: -8)
            ])
        }
        vista3D.backgroundColor = .clear
        vista3D.allowsCameraControl = true
        vista3D.autoenablesDefaultLighting = true
        vista3D.isHidden = true
        revisionDatos.font = .systemFont(ofSize: 15)
        revisionDatos.textColor = Self.tintaSuave
        revisionDatos.numberOfLines = 2
        Self.capsula(guardarButton, titulo: "Guardar", azul: true)
        Self.capsula(seguirButton, titulo: "Seguir escaneando", azul: false, tam: 16)
        Self.capsula(otroNivelButton, titulo: "Otro nivel", azul: false, tam: 16)
        for b in [seguirButton, otroNivelButton] {
            var c = b.configuration
            c?.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
            b.configuration = c
        }
        for b in [guardarButton, seguirButton, otroNivelButton] {
            b.heightAnchor.constraint(equalToConstant: 50).isActive = true
            b.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        guardarButton.addTarget(self, action: #selector(guardarTapped), for: .touchUpInside)
        seguirButton.addTarget(self, action: #selector(seguirTapped), for: .touchUpInside)
        otroNivelButton.addTarget(self, action: #selector(otroNivelTapped), for: .touchUpInside)
        let fila = UIStackView(arrangedSubviews: [seguirButton, otroNivelButton])
        fila.axis = .horizontal
        fila.spacing = 12
        fila.distribution = .fillEqually
        [revisionSelector, revisionVisor, revisionDatos, guardarButton, fila].forEach { revisionCaja.addArrangedSubview($0) }
        revisionCaja.isHidden = true
        [avisoCaja, completarButton, continuarIgualButton, avisoNota].forEach { $0.isHidden = true }
    }

    // MARK: Aviso, completar y revisión final

    // Los cuartos se numeran sin contar los parches.
    private func numeroDeCuarto(_ g: Int) -> Int { capturedRooms.indices.filter { $0 <= g && !indicesParche.contains($0) }.count }
    private var numeroSiguiente: Int { capturedRooms.indices.filter { !indicesParche.contains($0) }.count + 1 }

    private func nombreDelGrupo(_ g: Int) -> String {
        let n = (g < voiceNames.count ? voiceNames[g] : nil) ?? (g < capturedRooms.count ? suggestedRoomName(for: capturedRooms[g]) : nil)
        return n.map { Self.enIngles($0) } ?? "Room \(numeroDeCuarto(g))"
    }

    private func mostrarAviso(grupo g: Int, terminar: Bool) {
        let mios = problemasFinales.filter { $0.grupo == g }
        let otros = Set(problemasFinales.map { $0.grupo }).subtracting([g]).count
        let lados = mios.filter { $0.tipo == "lado" }.count
        var titulo = lados > 0
            ? (lados == 1 ? "Falta un lado del cuarto" : "Faltan \(lados) lados del cuarto")
            : "Una esquina del cuarto no cerró"
        if otros > 0 { titulo += " (y \(otros) cuarto\(otros == 1 ? "" : "s") más)" }
        aviso = Aviso(grupo: g, titulo: titulo, terminar: terminar)
        avisoTitulo.text = titulo
        huecosPorGrupo[g] = mios.map { ($0.a, $0.b) }
        refrescarMinimapa()
        updateUI()
        speak("\(titulo). Puedes completarlo o continuar.") {}
    }

    @objc private func completarTapped() {
        guard let a = aviso, state == .roomDonePrompt else { return }
        aviso = nil
        completandoIndice = a.grupo
        pendingRoomNameAfterGap = nil
        // El parche se escanea en el nivel de SU cuarto; al terminarlo se
        // regresa al nivel en que iba.
        if nivelAntesDeCompletar == nil { nivelAntesDeCompletar = currentLevel }
        if a.grupo < roomLevels.count { currentLevel = roomLevels[a.grupo] }
        let nombre = a.grupo < voiceNames.count ? voiceNames[a.grupo] : nil
        startCapturingRoom()
        if let nombre = nombre { pendingCurrentRoomName = nombre }
        bandejaRecogida = true
        updateUI()
        speak("Escanea solo la parte que falta. Lo que ya está se conserva.") {}
    }

    @objc private func continuarIgualTapped() {
        guard let a = aviso, state == .roomDonePrompt else { return }
        aviso = nil
        // Todo lo que quedó pendiente se guarda como incompleto, y a revisar.
        for p in problemasFinales { incompletos.insert(p.grupo) }
        incompletos.insert(a.grupo)
        problemasFinales = []
        if a.terminar {
            abrirRevisionFinal()
        } else {
            scanAnotherTapped()
        }
    }

    private func gruposDelNivel(_ nivel: Int?) -> [Int] {
        capturedRooms.indices.filter { i in
            !excluidosDelMerge.contains(i) && (nivel == nil || (i < roomLevels.count ? roomLevels[i] : 1) == nivel!)
        }
    }

    // ===== LOS MARCOS =====
    // Del cuarto i (como lo entregó RoomPlan) al plano en vivo. Un parche
    // pasa primero a su cuarto y de ahí al plano. nil = todavía no se sabe:
    // ese cuarto no se dibuja junto a los demás ni se compara con ellos
    // (mejor que falte un momento a que salga encimado).
    private func marcoEnPlano(_ i: Int) -> FloorPlanEncoder.Rigido2D? {
        if let g = parcheDe[i] {
            guard let a = alineacionParche[i], let m = marcoVivo[g] else { return nil }
            return a.luego(m)
        }
        return marcoVivo[i]
    }

    private func lineaPies(_ s: CapturedRoom.Surface) -> (CGPoint, CGPoint) {
        let f = FloorPlanEncoder.metersToFeet
        let (a, b) = FloorPlanEncoder.wallEndpoints(s)
        return (CGPoint(x: Double(a.x) * f, y: Double(a.y) * f), CGPoint(x: Double(b.x) * f, y: Double(b.y) * f))
    }
    private func centroPies(_ s: CapturedRoom.Surface) -> CGPoint {
        let f = FloorPlanEncoder.metersToFeet
        return CGPoint(x: Double(s.transform.columns.3.x) * f, y: Double(s.transform.columns.3.z) * f)
    }
    private func moverLinea(_ l: (CGPoint, CGPoint), _ t: FloorPlanEncoder.Rigido2D) -> (CGPoint, CGPoint) {
        let f = FloorPlanEncoder.metersToFeet
        return (t.aplicarPies(l.0, f: f), t.aplicarPies(l.1, f: f))
    }

    // LO QUE LOS PARCHES SÍ LE AGREGAN A SU CUARTO, en las coordenadas del
    // cuarto (pies): solo los pedazos que caen en un hueco de su contorno y
    // que no se meten en el piso de otro cuarto, y las puertas o ventanas
    // pegadas a esos pedazos que el cuarto no tenía. Un parche que no se
    // pudo alinear no agrega nada.
    private struct PiezasDeGrupo {
        var paredes: [(CGPoint, CGPoint)] = []
        var aberturas: [(CGPoint, CGPoint, MiniCuarto.Tipo)] = []
        var pasos: [(CGPoint, Double)] = []
    }
    // Las paredes de los otros cuartos del nivel, llevadas al marco del
    // cuarto g (solo si el plano en vivo ya los juntó), cuarto por cuarto.
    private func vecinosEnMarcoDe(_ g: Int) -> [[(CGPoint, CGPoint)]] {
        guard let mg = marcoVivo[g] else { return [] }
        let alCuarto = mg.inverso
        let nivel = g < roomLevels.count ? roomLevels[g] : 1
        return gruposDelNivel(nivel).filter { $0 != g }.compactMap { j in
            guard let mj = marcoVivo[j] else { return nil }
            let t = mj.luego(alCuarto)
            return capturedRooms[j].walls.map { moverLinea(lineaPies($0), t) }
        }
    }

    private func piezasDelGrupo(_ g: Int) -> PiezasDeGrupo {
        var out = PiezasDeGrupo()
        guard g < capturedRooms.count, !parches(de: g).isEmpty else { return out }
        let f = FloorPlanEncoder.metersToFeet
        // Los otros cuartos del nivel, llevados al marco de este cuarto (si
        // el plano en vivo ya los juntó).
        let vecinos = vecinosEnMarcoDe(g)
        let otras = vecinos.flatMap { $0 }
        let contornos = vecinos.map { FloorPlanEncoder.contornoYHuecos(wallsFt: $0).poly }
        var aceptadas = capturedRooms[g].walls.map(lineaPies)
        let viejas = (capturedRooms[g].doors + capturedRooms[g].windows + capturedRooms[g].openings).map(centroPies)
        for p in parches(de: g) where p < capturedRooms.count {
            guard let a = alineacionParche[p] else { continue }
            let r = capturedRooms[p]
            let pared = r.walls.map { moverLinea(lineaPies($0), a) }
            let piezas = FloorPlanEncoder.piezasDeParche(parcheFt: pared, propiasFt: aceptadas, otrasFt: otras, otrosContornos: contornos)
            out.paredes += piezas
            aceptadas += piezas
            let tipos: [([CapturedRoom.Surface], MiniCuarto.Tipo)] = [(r.doors, .puerta), (r.windows, .ventana), (r.openings, .paso)]
            for (lista, tipo) in tipos {
                for o in lista {
                    let c = a.aplicarPies(centroPies(o), f: f)
                    guard piezas.contains(where: { FloorPlanEncoder.distSegmento(c, $0.0, $0.1) <= 1.0 }) else { continue }
                    guard !viejas.contains(where: { hypot($0.x - c.x, $0.y - c.y) < 1.5 }),
                          !out.pasos.contains(where: { hypot($0.0.x - c.x, $0.0.y - c.y) < 1.5 }) else { continue }
                    let l = moverLinea(lineaPies(o), a)
                    out.aberturas.append((l.0, l.1, tipo))
                    out.pasos.append((c, Double(o.dimensions.x) * f))
                }
            }
        }
        return out
    }

    // Las paredes del cuarto con lo que sus parches sí agregaron, y sus
    // pasos (puertas, ventanas, aberturas), todo en el marco del cuarto.
    private func paredesDelGrupo(_ g: Int) -> (paredes: [(CGPoint, CGPoint)], pasos: [(CGPoint, Double)]) {
        guard g < capturedRooms.count else { return ([], []) }
        let f = FloorPlanEncoder.metersToFeet
        let r = capturedRooms[g]
        let pz = piezasDelGrupo(g)
        let pasos = (r.doors + r.windows + r.openings).map { (centroPies($0), Double($0.dimensions.x) * f) } + pz.pasos
        return (r.walls.map(lineaPies) + pz.paredes, pasos)
    }

    // ¿El contorno del cuarto cierra? Lados abiertos y esquinas sin cerrar,
    // con lo que sus parches alineados sí agregaron. Se guarda por grupo
    // (el cuarto y sus parches).
    @discardableResult
    private func revisarGrupo(_ g: Int) -> (gaps: [FloorPlanEncoder.OutlineGap], esquinas: [FloorPlanEncoder.CornerFinding]) {
        let (todas, pasos) = paredesDelGrupo(g)
        // Una pared del cuarto de al lado que RoomPlan metió en este no cuenta
        // para buscar huecos (paredesAjenas); un hueco que cubre la pared de
        // otro cuarto tampoco es hueco.
        let otras = vecinosEnMarcoDe(g).flatMap { $0 }
        let ajenas = FloorPlanEncoder.paredesAjenas(propias: todas, otras: otras)
        let sketchWalls = todas.enumerated().filter { !ajenas.contains($0.offset) }.map { $0.element }
        let openGaps = FloorPlanEncoder.outlineGaps(wallsFt: sketchWalls)
            .filter { $0.ft > FloorPlanEncoder.outlineGapWarnFt
                      && !FloorPlanEncoder.gapCoveredByWalls($0, walls: sketchWalls)
                      && (otras.isEmpty || !FloorPlanEncoder.gapCoveredByWalls($0, walls: otras)) }
        roomGapsByIndex[g] = openGaps.map { $0.ft }
        huecosPorGrupo[g] = openGaps.map { ($0.a, $0.b) }
        let esquinas = FloorPlanEncoder.cornerFindings(wallsFt: sketchWalls, portsFt: pasos.map { (center: $0.0, widthFt: $0.1) })
        roomCornersByIndex[g] = esquinas
        huecosPorGrupo[g, default: []] += esquinas.filter { $0.d >= 2 }.flatMap { [($0.a, $0.vertex), ($0.vertex, $0.b)] }
        for p in parches(de: g) { roomGapsByIndex[p] = []; roomCornersByIndex[p] = [] }
        return (openGaps, esquinas)
    }

    // Las esquinas del cuarto que acaba de terminar, en el panel del plano
    // (que dibuja el plano JUNTADO): solo si ya se sabe dónde va ese cuarto.
    private func marcarEsquinasEnPanel(_ g: Int?) {
        guard let g = g, let m = marcoEnPlano(g) else { floorPlanPanelView.marcarEsquinas([]); return }
        let f = FloorPlanEncoder.metersToFeet
        floorPlanPanelView.marcarEsquinas((roomCornersByIndex[g] ?? []).map { m.aplicarPies($0.vertex, f: f) })
    }

    // El cuarto con lo que sus parches SÍ le agregaron (ya acomodado), en
    // el marco del cuarto. Antes se le sumaban las paredes del parche tal
    // cual, en las coordenadas de otra captura.
    private func miniGrupo(_ g: Int) -> MiniCuarto {
        let base = miniCuarto(capturedRooms[g], nombre: nombreDelGrupo(g))
        let pz = piezasDelGrupo(g)
        return MiniCuarto(nombre: base.nombre, paredes: base.paredes + pz.paredes, aberturas: base.aberturas + pz.aberturas)
    }

    // El mismo, llevado al plano. nil si todavía no se sabe dónde va.
    private func miniGrupoEnPlano(_ g: Int) -> MiniCuarto? {
        guard let m = marcoEnPlano(g) else { return nil }
        let c = miniGrupo(g)
        return MiniCuarto(nombre: c.nombre, paredes: c.paredes.map { moverLinea($0, m) },
                          aberturas: c.aberturas.map { let l = moverLinea(($0.0, $0.1), m); return (l.0, l.1, $0.2) })
    }

    // Los cuartos del nivel para dibujar JUNTOS: en el plano los que ya se
    // sabe dónde van. Si ninguno se sabe (sin merge), cada uno en su marco
    // puesto en fila, sin encimarlos, como el panel de arriba.
    private func gruposParaDibujar(_ grupos: [Int]) -> [MiniCuarto] {
        let enPlano = grupos.compactMap { miniGrupoEnPlano($0) }
        if !enPlano.isEmpty || grupos.isEmpty { return enPlano }
        var cursor: CGFloat = 0
        return grupos.map { g in
            let c = miniGrupo(g)
            let xs = c.paredes.flatMap { [$0.0.x, $0.1.x] }
            let dx = cursor - (xs.min() ?? 0)
            cursor = (xs.max() ?? 0) + dx + 3
            func mv(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + dx, y: p.y) }
            return MiniCuarto(nombre: c.nombre, paredes: c.paredes.map { (mv($0.0), mv($0.1)) },
                              aberturas: c.aberturas.map { (mv($0.0), mv($0.1), $0.2) })
        }
    }

    private func abrirRevisionFinal() {
        enFlujoFinal = false
        enRevisionFinal = true
        tresDCargado = false
        vista3D.scene = nil
        revisionSelector.selectedSegmentIndex = 0
        planoGrande.isHidden = false
        vista3D.isHidden = true
        let grupos = gruposDelNivel(currentLevel)
        planoGrande.pintar(guardados: gruposParaDibujar(grupos), actual: nil, punto: nil)
        let total = gruposDelNivel(nil).count
        let niveles = Set(gruposDelNivel(nil).map { $0 < roomLevels.count ? roomLevels[$0] : 1 }).count
        var datos = "\(total) cuarto\(total == 1 ? "" : "s")" + (niveles > 1 ? " · \(niveles) niveles" : "") + " · se ve \(nombreDelNivel(currentLevel))"
        if !incompletos.isEmpty { datos += "\n\(incompletos.count) guardado\(incompletos.count == 1 ? "" : "s") como incompleto" }
        revisionDatos.text = datos
        updateUI()
        speak("Listo. Revisa el plano y toca guardar.") {}
    }

    @objc private func revisionSelectorCambio() {
        let tres = revisionSelector.selectedSegmentIndex == 1
        planoGrande.isHidden = tres
        vista3D.isHidden = !tres
        if tres && !tresDCargado { cargar3D() }
    }

    // El 3D: la casa juntada por Apple, exportada entera (cajas limpias).
    private func cargar3D() {
        tresDCargado = true
        // La casa JUNTADA por Apple (el último merge en vivo), en un solo
        // archivo. Antes se exportaba cada cuarto por separado y se ponían
        // juntos "porque venían en las mismas coordenadas": no venían. Cada
        // captura trae su propio origen, y en 3D salían encimados (y los
        // parches, encima de su cuarto).
        let estructura = liveStructure
        let visibles = gruposDelNivel(nil)
        let cuartos = visibles.map { capturedRooms[$0] }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("revision3d-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // (archivo, cuánto se corre en x para no encimarse)
            var archivos: [(URL, Float)] = []
            if #available(iOS 17.0, *), let s = estructura as? CapturedStructure {
                let u = dir.appendingPathComponent("casa.usdz")
                if (try? s.export(to: u, exportOptions: .parametric)) != nil { archivos.append((u, 0)) }
            } else {
                // Sin casa juntada (falló el merge o iOS 16): cada cuarto en fila,
                // separado, igual que el plano 2D de la revisión. Nunca encimados
                // ni una pantalla vacía.
                var cursor: Float = 0
                for (i, r) in cuartos.enumerated() {
                    let u = dir.appendingPathComponent("cuarto\(i).usdz")
                    guard (try? r.export(to: u, exportOptions: .parametric)) != nil else { continue }
                    let xs = r.walls.flatMap { w -> [Float] in let (a, b) = FloorPlanEncoder.wallEndpoints(w); return [a.x, b.x] }
                    let dx = cursor - (xs.min() ?? 0)
                    cursor = (xs.max() ?? 0) + dx + 1
                    archivos.append((u, dx))
                }
            }
            DispatchQueue.main.async {
                guard let self = self, self.enRevisionFinal else { return }
                let escena = SCNScene()
                for (u, dx) in archivos {
                    guard let s = try? SCNScene(url: u, options: nil) else { continue }
                    let nodo = SCNNode()
                    nodo.position = SCNVector3(dx, 0, 0)
                    for c in s.rootNode.childNodes { nodo.addChildNode(c) }
                    escena.rootNode.addChildNode(nodo)
                }
                self.vista3D.scene = escena
            }
        }
    }

    @objc private func guardarTapped() {
        guard enRevisionFinal else { return }
        enRevisionFinal = false
        finishTapped()
    }

    @objc private func seguirTapped() {
        guard enRevisionFinal else { return }
        enRevisionFinal = false
        enFlujoFinal = false
        scanAnotherTapped()
    }

    @objc private func otroNivelTapped() {
        guard enRevisionFinal else { return }
        enRevisionFinal = false
        if let i0 = Self.plantaValores.firstIndex(of: nivelBase) {
            // Se arranca el escáner y la bandeja pide el nivel, con el de
            // arriba ya marcado.
            let siguiente = min(i0 + currentLevel, Self.plantaValores.count - 1)
            startCapturingRoom()
            cambiandoNivel = true
            eligiendoNivel = true
            bandejaRecogida = false
            nivelSeleccionado = Self.plantaValores[siguiente]
            updateUI()
        } else {
            // Niveles con nombre propio: la bandeja los ofrece, sin adivinar.
            startCapturingRoom()
            cambiandoNivel = true
            eligiendoNivel = true
            bandejaRecogida = false
            nivelSeleccionado = nil
            updateUI()
        }
    }

    // EL SEGUNDO CEREBRO, AL TERMINAR (13-oct). Revisa el nivel completo y
    // solo avisa lo que de verdad falta. Un hueco en el contorno de un cuarto
    // NO es pared faltante si:
    //   1) lo cubre la pared de OTRO cuarto (el hallway que se escaneó después),
    //   2) hay una puerta, ventana o paso de cualquier cuarto ahí,
    //   3) la cámara pasó por ahí (nadie atraviesa una pared), o
    //   4) las fotos que apuntaban a ese lugar se ven como puerta o ventana
    //      (el reconocedor de imágenes del iPhone, sin internet).
    // Mientras tanto la bandeja dice "Revisando el plano completo…".
    private func validarAlTerminar() {
        enFlujoFinal = true
        revisandoTodo = true
        aviso = nil
        validacionGen += 1
        let gen = validacionGen
        updateUI()
        // Los cuartos se comparan entre sí YA acomodados en el plano: primero
        // se espera a que el merge en vivo y los parches terminen.
        esperarMarcos { [weak self] in
            guard let self = self, self.revisandoTodo, !self.sessionDelivered, self.validacionGen == gen else { return }
            self.validarConMarcos(gen: gen)
        }
    }

    private func validarConMarcos(gen: Int) {
        typealias R = FloorPlanEncoder.Rigido2D
        struct G {
            let g: Int; let nivel: Int
            let paredes: [(CGPoint, CGPoint)]; let pasos: [(CGPoint, Double)]
            let enPlano: Bool
            let marco: R?
            // Qué capturas tienen sus poses y fotos en el marco de este grupo,
            // y cómo pasarlas a ese marco (metros).
            let capturas: [Int: R]
        }
        let f = FloorPlanEncoder.metersToFeet
        var grupos: [G] = []
        for g in gruposDelNivel(nil) {
            var (paredes, pasos) = paredesDelGrupo(g)
            let marco = marcoEnPlano(g)
            if let m = marco {
                paredes = paredes.map { moverLinea($0, m) }
                pasos = pasos.map { (m.aplicarPies($0.0, f: f), $0.1) }
            }
            // La captura del cuarto y la de cada parche que sí se acomodó.
            var capturas: [Int: R] = [:]
            if let c = capturaDeCuarto[g] { capturas[c] = marco ?? .identidad }
            for p in parches(de: g) {
                guard let c = capturaDeCuarto[p], let a = alineacionParche[p] else { continue }
                capturas[c] = marco.map { a.luego($0) } ?? a
            }
            grupos.append(G(g: g, nivel: g < roomLevels.count ? roomLevels[g] : 1, paredes: paredes, pasos: pasos,
                            enPlano: marco != nil, marco: marco, capturas: capturas))
        }
        let rec = keyframeRecorder
        let alTerminar: ([ScanKeyframeRecorder.PoseRecord], [ScanKeyframeRecorder.KeyframeMeta]) -> Void = { [weak self] poses, fotos in
            DispatchQueue.global(qos: .userInitiated).async {
                var problemas: [Problema] = []
                var cuenta = ["revisados": 0, "otroCuarto": 0, "puerta": 0, "camino": 0, "foto": 0]
                let empezo = Date()
                // Las capturas que ya se sabe dónde van en el plano.
                var alPlano: [Int: R] = [:]
                for G0 in grupos where G0.enPlano { for (c, t) in G0.capturas { alPlano[c] = t } }
                for G0 in grupos {
                    // Lo de los otros cuartos solo cuenta si los dos están en el
                    // plano; un cuarto que todavía no se acomodó se revisa solo.
                    let vecinos = G0.enPlano ? grupos.filter { $0.g != G0.g && $0.nivel == G0.nivel && $0.enPlano } : []
                    let otras = vecinos.flatMap { $0.paredes }
                    let pasos = G0.pasos + vecinos.flatMap { $0.pasos }
                    // El camino de la cámara, en el marco de este cuarto: las
                    // capturas que se sabe cómo traer, nada más.
                    let traer = G0.enPlano ? alPlano : G0.capturas
                    let camino: [CGPoint] = poses.compactMap { p in
                        guard p.level == G0.nivel, let t = traer[p.captura] else { return nil }
                        return t.aplicarPies(CGPoint(x: Double(p.transform.columns.3.x) * f, y: Double(p.transform.columns.3.z) * f), f: f)
                    }
                    let vistas: [(file: URL, punto: CGPoint)] = fotos.compactMap { k in
                        guard k.level == G0.nivel, let h = k.hit, let t = traer[k.captura] else { return nil }
                        return (k.file, t.aplicarPies(CGPoint(x: Double(h.x) * f, y: Double(h.z) * f), f: f))
                    }
                    // Una pared del cuarto de al lado que RoomPlan metió en
                    // este no cuenta para buscar huecos: encadenar por su
                    // punta suelta da un "lado faltante" en diagonal que no
                    // existe (la sala y la cocina de Harold).
                    let ajenas = FloorPlanEncoder.paredesAjenas(propias: G0.paredes, otras: otras)
                    let paredes = G0.paredes.enumerated().filter { !ajenas.contains($0.offset) }.map { $0.element }
                    if !ajenas.isEmpty { cuenta["paredAjena", default: 0] += ajenas.count }
                    let huecos = FloorPlanEncoder.outlineGaps(wallsFt: paredes)
                        .filter { $0.ft > FloorPlanEncoder.outlineGapWarnFt && !FloorPlanEncoder.gapCoveredByWalls($0, walls: paredes) }
                    for h in huecos {
                        cuenta["revisados", default: 0] += 1
                        if !otras.isEmpty, FloorPlanEncoder.gapCoveredByWalls(h, walls: otras) { cuenta["otroCuarto", default: 0] += 1; continue }
                        // Puerta, camino y fotos solo perdonan huecos del tamaño de
                        // un paso: una pared faltante de 12 ft con una puerta en
                        // ese lado sigue siendo pared faltante.
                        if pasos.contains(where: { Self.distSegmento($0.0, h.a, h.b) < 1.0 && $0.1 >= h.ft - 1.5 }) { cuenta["puerta", default: 0] += 1; continue }
                        if h.ft <= 6, Self.caminoCruza(camino, h.a, h.b) { cuenta["camino", default: 0] += 1; continue }
                        if h.ft <= 8, Date().timeIntervalSince(empezo) < 2.5,
                           Self.fotosVenPaso(vistas, a: h.a, b: h.b) { cuenta["foto", default: 0] += 1; continue }
                        problemas.append(Problema(grupo: G0.g, tipo: "lado", ft: h.ft, a: h.a, b: h.b))
                    }
                    let esquinas = FloorPlanEncoder.cornerFindings(wallsFt: paredes, portsFt: pasos.map { (center: $0.0, widthFt: $0.1) })
                        .filter { $0.d >= 2 }
                    for e in esquinas {
                        cuenta["revisados", default: 0] += 1
                        if otras.contains(where: { Self.distSegmento(e.vertex, $0.0, $0.1) < 1.2 }) { cuenta["otroCuarto", default: 0] += 1; continue }
                        if Self.caminoCruza(camino, e.a, e.vertex) || Self.caminoCruza(camino, e.vertex, e.b) { cuenta["camino", default: 0] += 1; continue }
                        problemas.append(Problema(grupo: G0.g, tipo: "esquina", ft: e.d, a: e.a, b: e.b))
                    }
                }
                DispatchQueue.main.async {
                    guard let self = self, self.revisandoTodo, !self.sessionDelivered, self.validacionGen == gen else { return }
                    self.revisandoTodo = false
                    self.segundoCerebro = ["revisados": cuenta["revisados"] ?? 0,
                                           "resueltosPorOtroCuarto": cuenta["otroCuarto"] ?? 0,
                                           "resueltosPorPuerta": cuenta["puerta"] ?? 0,
                                           "resueltosPorCamino": cuenta["camino"] ?? 0,
                                           "resueltosPorFoto": cuenta["foto"] ?? 0,
                                           "paredesAjenasIgnoradas": cuenta["paredAjena"] ?? 0,
                                           "pendientes": problemas.count,
                                           "cuartosSinAcomodar": grupos.filter { !$0.enPlano }.count]
                    NSLog("[RoomScan] segundo cerebro: %@", String(describing: self.segundoCerebro))
                    // Lo que ya se marcó como incompleto no se vuelve a preguntar.
                    // Los puntos del problema vienen en el marco en que se revisó
                    // (el plano, o el del cuarto): el aviso los pinta en el
                    // marco del cuarto (huecosPorGrupo), así que se regresan.
                    self.problemasFinales = problemas.filter { !self.incompletos.contains($0.grupo) }.map { pr in
                        // Con el MISMO marco con que se revisó (el merge pudo
                        // cambiar mientras tanto).
                        guard let m = grupos.first(where: { $0.g == pr.grupo })?.marco else { return pr }
                        let inv = m.inverso
                        return Problema(grupo: pr.grupo, tipo: pr.tipo, ft: pr.ft, a: inv.aplicarPies(pr.a, f: f), b: inv.aplicarPies(pr.b, f: f))
                    }
                    if let primero = self.problemasFinales.first {
                        self.mostrarAviso(grupo: primero.grupo, terminar: true)
                    } else {
                        self.abrirRevisionFinal()
                    }
                }
            }
        }
        // Solo una respuesta cuenta: la del recorder, o a los 4 s la que revisa
        // solo con paredes y puertas (la cola del recorder ya se ha trabado en
        // el campo; aquí no se puede quedar "Revisando…" para siempre).
        let lock = NSLock()
        var listo = false
        let una: ([ScanKeyframeRecorder.PoseRecord], [ScanKeyframeRecorder.KeyframeMeta]) -> Void = { p, k in
            lock.lock(); let ya = listo; listo = true; lock.unlock()
            if !ya { alTerminar(p, k) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { una([], []) }
        guard let r = rec else { una([], []); return }
        r.snapshotPoses { poses in r.snapshotKeyframes { fotos in una(poses, fotos) } }
    }

    // ¿El camino de la cámara cruzó el segmento AB? (pasos cortos: un salto
    // largo es el rastreo perdiéndose, no una persona caminando).
    static func caminoCruza(_ camino: [CGPoint], _ a: CGPoint, _ b: CGPoint) -> Bool {
        guard camino.count > 1 else { return false }
        func lado(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> Double { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
        for i in 1..<camino.count {
            let p = camino[i - 1], q = camino[i]
            guard hypot(q.x - p.x, q.y - p.y) < 3 else { continue }
            if lado(a, b, p) * lado(a, b, q) < 0 && lado(p, q, a) * lado(p, q, b) < 0 { return true }
        }
        return false
    }

    // ¿Las fotos que apuntaban a ese hueco se ven como puerta o ventana?
    // Las fotos llegan con el punto al que apuntaban YA en el marco en que se
    // revisa (el plano o el del cuarto), y solo las del mismo nivel.
    static func fotosVenPaso(_ fotos: [(file: URL, punto: CGPoint)], a: CGPoint, b: CGPoint) -> Bool {
        let cerca = fotos.filter { distSegmento($0.punto, a, b) < 2.0 }.prefix(3)
        for k in cerca {
            let req = VNClassifyImageRequest()
            guard (try? VNImageRequestHandler(url: k.file, options: [:]).perform([req])) != nil,
                  let res = req.results else { continue }
            if res.contains(where: { ($0.identifier == "door" || $0.identifier == "window") && $0.confidence >= 0.3 }) { return true }
        }
        return false
    }

    @objc private func siguienteTapped() {
        guard state == .scanningRoom, !eligiendoNivel else { return }
        campo.resignFirstResponder()
        siguienteAlAcabarCuarto = true
        doneTapped()
    }

    // Los nombres se ENSEÑAN en inglés (en el plano salen así). La misma
    // tabla que usa la web de Field Reports para el seguro; lo que no está
    // se enseña como lo dijeron.
    private static let cuartosEnIngles: [String: String] = [
        "recamara principal": "Master Bedroom", "cuarto principal": "Master Bedroom",
        "dormitorio principal": "Master Bedroom", "habitacion principal": "Master Bedroom",
        "recamara": "Bedroom", "dormitorio": "Bedroom", "habitacion": "Bedroom", "alcoba": "Bedroom",
        "bano principal": "Master Bathroom", "bano": "Bathroom", "sanitario": "Bathroom",
        "medio bano": "Half Bathroom", "cocina": "Kitchen", "sala": "Living Room",
        "sala familiar": "Family Room", "cuarto familiar": "Family Room", "comedor": "Dining Room",
        "pasillo": "Hallway", "corredor": "Hallway", "sotano": "Basement", "atico": "Attic",
        "closet": "Closet", "ropero": "Closet", "armario": "Closet",
        "lavanderia": "Laundry Room", "cuarto de lavado": "Laundry Room", "lavado": "Laundry Room",
        "garaje": "Garage", "cochera": "Garage", "oficina": "Office", "estudio": "Office",
        "cuarto de los ninos": "Kids Bedroom", "cuarto de ninos": "Kids Bedroom",
        "recamara de los ninos": "Kids Bedroom", "recamara de ninos": "Kids Bedroom",
        "cuarto de visitas": "Guest Bedroom", "cuarto de huespedes": "Guest Bedroom",
        "recamara de visitas": "Guest Bedroom", "recamara de huespedes": "Guest Bedroom",
        "bano de visitas": "Guest Bathroom", "bano de huespedes": "Guest Bathroom",
        "cuarto de tv": "TV Room", "sala de tv": "TV Room", "cuarto de television": "TV Room",
        "bodega": "Storage Room", "cuarto de bodega": "Storage Room",
        "cuarto de maquinas": "Utility Room", "cuarto de servicio": "Utility Room",
        "escaleras": "Stairs", "escalera": "Stairs", "gimnasio": "Gym", "despensa": "Pantry",
        "cuarto de juegos": "Game Room", "sala de juegos": "Game Room", "entrada": "Entry",
        "recibidor": "Foyer", "vestibulo": "Foyer", "vestidor": "Walk-in Closet",
        "bano de la recamara": "Master Bathroom", "cocineta": "Kitchenette", "patio": "Patio",
        "terraza": "Deck", "porche": "Porch", "balcon": "Balcony", "cuarto": "Room",
        "sala comedor": "Living / Dining Room"
    ]
    static func enIngles(_ nombre: String) -> String {
        let crudo = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !crudo.isEmpty else { return crudo }
        var base = sinAcentos(crudo)
        var num = ""
        // "habitación dos" = "habitación 2".
        let numeros = ["uno": "1", "dos": "2", "tres": "3", "cuatro": "4", "cinco": "5", "seis": "6"]
        if let u = base.split(separator: " ").last, base.contains(" "), let d = numeros[String(u)] {
            base = String(base.dropLast(u.count)).trimmingCharacters(in: .whitespaces) + " " + d
        }
        if let r = base.range(of: #"\s*(\d+)$"#, options: .regularExpression) {
            num = " " + base[r].trimmingCharacters(in: .whitespaces)
            base = String(base[..<r.lowerBound])
        }
        if let en = cuartosEnIngles[base] { return en + num }
        return crudo.prefix(1).uppercased() + crudo.dropFirst()
    }

    // Terminar: el cuarto que va se cierra igual que con "Cuarto listo" y,
    // si no regresó con un aviso, el plano se termina como con el botón de
    // siempre. Son los mismos dos pasos de antes, uno detrás del otro.
    @objc private func terminarTapped() {
        campo.resignFirstResponder()
        if state == .scanningRoom && !eligiendoNivel {
            // Lo que se empezó después del último cuarto, sin nombre y casi sin
            // paredes, no se guarda como cuarto (era un duplicado del anterior).
            // Se decide al llegar el cuarto (didPresent), con sus paredes reales.
            if pendingCurrentRoomName == nil && pendingCurrentEquipment.isEmpty && completandoIndice == nil
                && !gruposDelNivel(nil).isEmpty { descartarCapturaActual = true }
            terminarAlAcabarCuarto = true
            doneTapped()
        } else if state == .roomDonePrompt && aviso == nil && !enRevisionFinal && !revisandoTodo {
            validarAlTerminar()
        }
    }

    // Cancelar desde la bandeja: nunca tira todo de un toque.
    @objc private func cancelarBandejaTapped() {
        cerrarCampoSinAplicar()
        if eligiendoNivel && cambiandoNivel {
            // Solo se deja de cambiar el nivel; se sigue en el mismo.
            eligiendoNivel = false
            cambiandoNivel = false
            campo.text = nil
            updateUI()
            return
        }
        if state == .scanningRoom, pendingCurrentRoomName != nil, !bandejaRecogida {
            // Estaba corrigiendo el nombre: se vuelve a la barra de antes.
            bandejaRecogida = true
            animarBandeja()
            return
        }
        let n = gruposDelNivel(nil).count
        guard n > 0 else { cancelTapped(); return }
        let a = UIAlertController(title: "¿Cancelar todo el escaneo?",
                                  message: "Se pierden \(n == 1 ? "el cuarto escaneado" : "los \(n) cuartos escaneados"). Para terminar y guardar, toque Terminar.",
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Seguir escaneando", style: .cancel))
        a.addAction(UIAlertAction(title: "Sí, cancelar todo", style: .destructive) { [weak self] _ in self?.cancelTapped() })
        present(a, animated: true)
    }

    // MARK: Minimapa

    @objc private func planCardExpandTapped() {
        planCardGrande.toggle()
        let ancho = view.bounds.width - 28
        planCardW?.constant = planCardGrande ? ancho : 136
        planCardH?.constant = planCardGrande ? min(ancho * 0.85, view.bounds.height * 0.42) : 124
        planCardExpand.setImage(UIImage(systemName: planCardGrande ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)), for: .normal)
        torchButton.alpha = planCardGrande ? 0 : 1
        torchLabel.alpha = planCardGrande ? 0 : 1
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    // Lo que de verdad lleva: los cuartos ya guardados de ESTE nivel en
    // gris (acomodados en el plano), y donde está parado ahora en azul.
    // Mientras escanea solo sale lo que ve y dónde está: su captura tiene su
    // propio origen hasta que se guarda y Apple la junta con las demás.
    private func refrescarMinimapa() {
        planCardTitle.text = nivelBase.isEmpty && eligiendoNivel ? "Plano" : nombreDelNivel(currentLevel)
        guard !soloVistaPrevia else { return }
        // El cuarto que se está completando, o el que trae aviso, va en azul
        // (con lo que falta en ámbar); los demás guardados, en gris.
        let destacado: Int? = completandoIndice ?? (state == .roomDonePrompt ? aviso?.grupo : nil)
        let nivelVisto = destacado.map { $0 < roomLevels.count ? roomLevels[$0] : currentLevel } ?? currentLevel
        planCardTitle.text = nombreDelNivel(nivelVisto)
        let actual: String?
        if state == .scanningRoom && !eligiendoNivel {
            actual = pendingCurrentRoomName.map { Self.enIngles($0) } ?? "Room \(numeroSiguiente)"
        } else {
            actual = nil
        }
        let enCurso = state == .scanningRoom
        let f = FloorPlanEncoder.metersToFeet
        if let g = destacado, g < capturedRooms.count, !enCurso {
            // La cámara solo se pinta si sigue en la captura de ese cuarto (si
            // no, su posición está en otro marco).
            let mismaCaptura = capturaDeCuarto[g] == capturaActual
            if let m = marcoEnPlano(g), let azul = miniGrupoEnPlano(g) {
                let otros = gruposDelNivel(nivelVisto).filter { $0 != g }.compactMap { miniGrupoEnPlano($0) }
                minimapa.pintar(guardados: otros, actual: nombreDelGrupo(g),
                                punto: mismaCaptura ? posicionCamara.map { m.aplicarPies($0, f: f) } : nil,
                                enVivo: azul, huecos: (huecosPorGrupo[g] ?? []).map { moverLinea($0, m) }, huecosAmbar: true)
            } else {
                minimapa.pintar(guardados: [], actual: nombreDelGrupo(g), punto: mismaCaptura ? posicionCamara : nil,
                                enVivo: miniGrupo(g), huecos: huecosPorGrupo[g] ?? [], huecosAmbar: true)
            }
            return
        }
        if enCurso {
            // Escaneando: esta captura arrancó con su propio origen y todavía
            // no se sabe dónde cae en el plano. Se dibuja SOLO lo que se está
            // viendo y dónde está parado (los dos en el mismo marco). Los
            // cuartos guardados vuelven a salir, juntos y bien puestos, en
            // cuanto se guarda este. Antes salían encima, cada uno en su
            // propio marco.
            minimapa.pintar(guardados: [], actual: actual, punto: posicionCamara,
                            enVivo: cuartoEnVivo, huecos: huecosEnVivo)
            return
        }
        minimapa.pintar(guardados: gruposParaDibujar(gruposDelNivel(nivelVisto)), actual: actual, punto: nil,
                        enVivo: nil, huecos: [])
    }

    private func engancharEnVivo() {
        guard !soloVistaPrevia, !sessionDelivered, let ses = captureView.captureSession, !(ses.delegate === enVivo) else { return }
        enVivo.original = ses.delegate
        enVivo.alActualizar = { [weak self] room in self?.cuartoActualizado(room) }
        enVivo.alIndicar = { [weak self] texto in
            guard let self = self, self.instruccionApple != texto else { return }
            self.instruccionApple = texto
            self.instruccionActual = self.instruccionCalidad ?? self.instruccionApple
            if self.state == .scanningRoom { self.updateUI() }
        }
        ses.delegate = enVivo
        NSLog("[RoomScan] cuarto en vivo enganchado (delegado original: %@)", enVivo.original == nil ? "ninguno" : "sí, se le pasa todo")
    }

    private func cuartoActualizado(_ room: CapturedRoom) {
        guard state == .scanningRoom, !sessionDelivered else { return }
        let ahora = CACurrentMediaTime()
        let f = FloorPlanEncoder.metersToFeet
        func linea(_ x: CapturedRoom.Surface) -> (CGPoint, CGPoint) {
            let (a, b) = FloorPlanEncoder.wallEndpoints(x)
            return (CGPoint(x: Double(a.x) * f, y: Double(a.y) * f), CGPoint(x: Double(b.x) * f, y: Double(b.y) * f))
        }
        for w in room.walls { paredesVistas[w.identifier] = (linea(w), ahora) }
        for d in room.doors { aberturasVistas[d.identifier] = (linea(d), .puerta, ahora) }
        for w in room.windows { aberturasVistas[w.identifier] = (linea(w), .ventana, ahora) }
        for o in room.openings { aberturasVistas[o.identifier] = (linea(o), .paso, ahora) }
        let sostener: CFTimeInterval = 3
        paredesVistas = paredesVistas.filter { ahora - $0.value.t <= sostener }
        aberturasVistas = aberturasVistas.filter { ahora - $0.value.t <= sostener }
        let c = MiniCuarto(nombre: nil, paredes: paredesVistas.values.map { $0.linea },
                           aberturas: aberturasVistas.values.map { ($0.linea.0, $0.linea.1, $0.tipo) })
        // Completando un cuarto, lo nuevo NO se junta aquí con lo que ya
        // estaba: son dos capturas con origen distinto. Se junta al
        // terminar, acomodado por Apple (alinearParchesPendientes). Y los
        // huecos de un pedazo de cuarto no son huecos: no se pintan.
        cuartoEnVivo = c
        huecosEnVivo = completandoIndice != nil ? [] : FloorPlanEncoder.outlineGaps(wallsFt: c.paredes).map { ($0.a, $0.b) }
        refrescarMinimapa()
    }

    private func miniCuarto(_ room: CapturedRoom, nombre: String?) -> MiniCuarto {
        let f = FloorPlanEncoder.metersToFeet
        func linea(_ s: CapturedRoom.Surface) -> (CGPoint, CGPoint) {
            let (a, b) = FloorPlanEncoder.wallEndpoints(s)
            return (CGPoint(x: Double(a.x) * f, y: Double(a.y) * f), CGPoint(x: Double(b.x) * f, y: Double(b.y) * f))
        }
        var ab: [(CGPoint, CGPoint, MiniCuarto.Tipo)] = []
        for d in room.doors { let (a, b) = linea(d); ab.append((a, b, .puerta)) }
        for w in room.windows { let (a, b) = linea(w); ab.append((a, b, .ventana)) }
        for o in room.openings { let (a, b) = linea(o); ab.append((a, b, .paso)) }
        return MiniCuarto(nombre: nombre, paredes: room.walls.map(linea), aberturas: ab)
    }

    private func arrancarPosicion() {
        posicionTimer?.invalidate()
        let arSession = captureView.captureSession.arSession
        posicionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak arSession] _ in
            guard let self = self, self.state == .scanningRoom,
                  let t = arSession?.currentFrame?.camera.transform else { return }
            let f = FloorPlanEncoder.metersToFeet
            self.posicionCamara = CGPoint(x: Double(t.columns.3.x) * f, y: Double(t.columns.3.z) * f)
            self.refrescarMinimapa()
        }
    }

    // La linterna: el LED se maneja directo con AVCaptureDevice, la forma
    // que ARKit permite (igual que en la cinta de medir).
    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            isTorchOn = on
            torchButton.setImage(UIImage(systemName: on ? "flashlight.on.fill" : "flashlight.off.fill",
                                         withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)), for: .normal)
            torchButton.backgroundColor = on ? UIColor.systemYellow.withAlphaComponent(0.95) : UIColor.white.withAlphaComponent(0.42)
            torchButton.tintColor = on ? .black : .white
        } catch {}
    }

    @objc private func torchTapped() { setTorch(!isTorchOn) }

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
        keyframeRecorder?.update(roomIndex: capturedRooms.count, level: currentLevel, scanning: state == .scanningRoom, captura: capturaActual)
        // Only mention the level once a second one's actually in play -
        // the common single-level scan stays uncluttered.
        // Con la planta escogida se dice SIEMPRE, aunque sea la primera: si esta
        // parado en el segundo piso, verlo escrito es lo que le confirma que la
        // app lo sabe. Sin planta escogida se calla hasta el nivel 2, como antes.
        // El diseño nuevo dice la planta PRIMERO: "Primer piso · Cuarto 1".
        let levelPrefix = !nivelBase.isEmpty ? "\(nombreDelNivel(currentLevel)) · "
                        : (currentLevel > 1 ? "Nivel \(currentLevel) · " : "")
        switch state {
        case .scanningRoom:
            cancelButton.isHidden = false
            doneButton.isHidden = false
            statusLabel.isHidden = true
            promptStack.isHidden = true
            roomSummaryLabel.isHidden = true
            planPanelStatusLabel.text = "\(levelPrefix)Cuarto \(capturedRooms.count + 1)"
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
            let lvlDone = roomLevels.last ?? currentLevel
            let prefDone = !nivelBase.isEmpty ? "\(nombreDelNivel(lvlDone)) · "
                         : (lvlDone > 1 ? "Nivel \(lvlDone) · " : "")
            planPanelStatusLabel.text = "\(prefDone)Cuarto \(capturedRooms.count) listo"
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
        // LA BANDEJA (solo presentación): lo de arriba sigue decidiendo qué
        // se puede hacer; aquí solo se acomoda. Primero el nivel, luego el
        // cuarto, en la misma bandeja.
        let modoNivel = eligiendoNivel && (state == .scanningRoom || state == .roomDonePrompt)
        sheetTitle.text = modoNivel ? "Seleccionar nivel" : (state == .roomDonePrompt ? "Cuarto guardado" : "Seleccionar cuarto")
        sheetTitle.isHidden = state == .processingRoom || state == .finishingSession
        sheetSubLabel.text = "\(nombreDelNivel(currentLevel)) ·"
        sheetSubRow.isHidden = modoNivel || sheetTitle.isHidden
        nivelesCaption.isHidden = !modoNivel
        let conCampo = modoNivel || !roomOptionsScroll.isHidden
        campoCaja.isHidden = !conCampo
        chipsScroll.isHidden = !conCampo
        if modoNivel {
            roomSummaryLabel.isHidden = true
            promptStack.isHidden = true
            roomSplitButtonsStack.isHidden = true
            cancelButton.isHidden = state != .scanningRoom
            doneButton.isHidden = true
            continuarButton.isHidden = false
        } else {
            continuarButton.isHidden = true
        }
        // Recogida: solo los botones (el nombre ya está escogido).
        let recogida = bandejaRecogida && state == .scanningRoom && !modoNivel && roomSplitButtonsStack.isHidden
        if recogida {
            // "Kitchen · First Floor", el campo con su micrófono, y
            // "Siguiente cuarto" | "Terminar". Sin botones de nombres.
            let tituloNombre = completandoIndice.map { nombreDelGrupo($0) } ?? Self.enIngles(pendingCurrentRoomName ?? "")
            let t = NSMutableAttributedString(string: tituloNombre,
                                              attributes: [.font: UIFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: Self.tinta])
            t.append(NSAttributedString(string: "  ·  \(nombreDelNivel(currentLevel))",
                                        attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: Self.tintaSuave]))
            sheetTitle.attributedText = t
            sheetTitle.isHidden = false
            sheetSubRow.isHidden = true
            campoCaja.isHidden = false
            chipsScroll.isHidden = true
            cancelButton.isHidden = true
            doneButton.isHidden = true
        }
        filaSiguiente.isHidden = !recogida
        // "Terminar" también sin nombre, pero solo cuando ya hay cuartos ("aún no hay").
        terminarLink.isHidden = !(state == .scanningRoom && !modoNivel && !recogida && completandoIndice == nil && !gruposDelNivel(nil).isEmpty)
        buttonRow.isHidden = cancelButton.isHidden && doneButton.isHidden && continuarButton.isHidden
        sheetDivider.isHidden = buttonRow.isHidden || !conCampo || modoNivel || recogida
        sheetStack.setCustomSpacing(recogida ? 14 : 2, after: sheetTitle)
        let ocupado = state == .processingRoom || state == .finishingSession
        sheetStatusRow.isHidden = !ocupado
        if ocupado {
            sheetStatusLabel.text = planPanelStatusLabel.text
            sheetStatusSpinner.startAnimating()
        } else {
            sheetStatusSpinner.stopAnimating()
        }
        if modoNivel {
            scanCaptionIcon.isHidden = false
            scanCaptionLabel.text = cambiandoNivel ? "Escoge el nivel" : "Selecciona un nivel para comenzar"
            scanCaption.isHidden = false
        } else if state == .scanningRoom {
            scanCaptionIcon.isHidden = true
            scanCaptionLabel.text = "Escaneando \(pendingCurrentRoomName.map { Self.enIngles($0) } ?? "Cuarto \(numeroSiguiente)")…"
                + (instruccionActual.map { "\n" + $0 } ?? "")
            scanCaption.isHidden = false
        } else {
            scanCaption.isHidden = true
        }
        // El aviso ámbar y la revisión final ocupan la bandeja solos.
        let enAviso = aviso != nil && state == .roomDonePrompt
        let enRev = enRevisionFinal && state == .roomDonePrompt
        let guardadoDePaso = state == .roomDonePrompt && !enAviso && !enRev && !modoNivel && !revisandoTodo
        if enAviso || enRev || guardadoDePaso || (revisandoTodo && state == .roomDonePrompt) {
            [sheetSubRow, campoCaja, chipsScroll, nivelesCaption, buttonRow, filaSiguiente, promptStack,
             roomSummaryLabel, roomSplitButtonsStack, sheetDivider].forEach { $0.isHidden = true }
            scanCaption.isHidden = true
        }
        [avisoCaja, completarButton, continuarIgualButton, avisoNota].forEach { $0.isHidden = !enAviso }
        if enAviso || enRev || guardadoDePaso || revisandoTodo { terminarLink.isHidden = true }
        if revisandoTodo && state == .roomDonePrompt {
            sheetTitle.isHidden = true
            sheetStatusRow.isHidden = false
            sheetStatusSpinner.startAnimating()
            sheetStatusLabel.text = "Revisando el plano completo…"
        }
        revisionCaja.isHidden = !enRev
        avisoBadge.isHidden = !enAviso
        if let a = aviso, enAviso {
            let t = NSMutableAttributedString(string: nombreDelGrupo(a.grupo),
                                              attributes: [.font: UIFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: Self.tinta])
            let nivelDelAviso = a.grupo < roomLevels.count ? roomLevels[a.grupo] : currentLevel
            t.append(NSAttributedString(string: "  ·  \(nombreDelNivel(nivelDelAviso))",
                                        attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: Self.tintaSuave]))
            sheetTitle.attributedText = t
            sheetTitle.isHidden = false
            sheetStack.setCustomSpacing(14, after: sheetTitle)
        } else if enRev {
            sheetTitle.text = "Revisión final"
            sheetTitle.isHidden = false
            sheetStack.setCustomSpacing(12, after: sheetTitle)
        } else if guardadoDePaso {
            // El momento entre "guardado" y el siguiente cuarto: nada que revisar.
            sheetTitle.isHidden = true
            sheetStatusRow.isHidden = false
            sheetStatusSpinner.startAnimating()
            sheetStatusLabel.text = "Guardando y pasando al siguiente…"
        }
        if state == .scanningRoom, completandoIndice != nil {
            scanCaptionLabel.text = "Completando \(pendingCurrentRoomName.map { Self.enIngles($0) } ?? "el cuarto")…"
                + (instruccionActual.map { "\n" + $0 } ?? "")
        }
        planPanelSpinner.stopAnimating()
        statusLabel.isHidden = true
        pintarNombre()
    }

    private var hasAppeared = false
    // Camino 2: qué configuración de ARKit corre RoomPlan por dentro. Se lee
    // UNA vez, en main, unos segundos después de arrancar - solo se lee.
    private var arConfigProbe: [String: Any]?

    private func leerConfiguracionDeARKit() {
        let session = captureView.captureSession.arSession
        var d: [String: Any] = [:]
        d["supportsMeshClassification"] = ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
        d["supportsSceneDepth"] = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        if let cfg = session.configuration {
            d["type"] = String(describing: type(of: cfg))
            if let w = cfg as? ARWorldTrackingConfiguration {
                switch w.sceneReconstruction {
                case .meshWithClassification: d["sceneReconstruction"] = "meshWithClassification"
                case .mesh: d["sceneReconstruction"] = "mesh"
                default: d["sceneReconstruction"] = "none"
                }
                d["sceneDepth"] = w.frameSemantics.contains(.sceneDepth)
                d["smoothedSceneDepth"] = w.frameSemantics.contains(.smoothedSceneDepth)
                d["planesVertical"] = w.planeDetection.contains(.vertical)
                d["planesHorizontal"] = w.planeDetection.contains(.horizontal)
            }
        } else {
            d["type"] = "nil"
        }
        arConfigProbe = d
        NSLog("[RoomScan] sonda ARKit: %@", String(describing: d))
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // One-shot setup: a re-appear (returning from a presented alert or
        // the app coming back to foreground) used to restart capture from
        // ANY state, orphan the running recorder (deleting every keyframe
        // taken so far), and rebuild the voice stack over a live engine.
        guard !hasAppeared else { return }
        hasAppeared = true
        if soloVistaPrevia {
            // 0 = escoger nivel · 1 = escaneando un cuarto · 2 = procesando.
            // Los cuartos del minimapa aquí son de EJEMPLO, solo para ver la forma.
            if vistaPreviaEstado >= 1 {
                eligiendoNivel = false
                nivelBase = nivelBase.isEmpty ? "1st Floor" : nivelBase
                pendingCurrentRoomName = "Cocina"
                minimapa.pintar(guardados: [MiniCuarto(nombre: "Living Room", paredes: [
                    (CGPoint(x: 0, y: 0), CGPoint(x: 14, y: 0)), (CGPoint(x: 14, y: 0), CGPoint(x: 14, y: 12)),
                    (CGPoint(x: 14, y: 12), CGPoint(x: 0, y: 12)), (CGPoint(x: 0, y: 12), CGPoint(x: 0, y: 0))],
                    aberturas: [(CGPoint(x: 14, y: 4), CGPoint(x: 14, y: 7), .puerta),
                                (CGPoint(x: 4, y: 0), CGPoint(x: 9, y: 0), .ventana),
                                (CGPoint(x: 0, y: 5), CGPoint(x: 0, y: 8.5), .ventana)])],
                                actual: "Kitchen", punto: CGPoint(x: 20, y: 7),
                                enVivo: MiniCuarto(nombre: nil, paredes: [
                                    (CGPoint(x: 14, y: 2), CGPoint(x: 24, y: 2)), (CGPoint(x: 24, y: 2), CGPoint(x: 24, y: 6)),
                                    (CGPoint(x: 24, y: 9), CGPoint(x: 24, y: 12)), (CGPoint(x: 24, y: 12), CGPoint(x: 14, y: 12))],
                                    aberturas: [(CGPoint(x: 17, y: 12), CGPoint(x: 20, y: 12), .ventana)]),
                                huecos: [(CGPoint(x: 24, y: 6), CGPoint(x: 24, y: 9))])
            }
            if vistaPreviaEstado == 2 { state = .processingRoom }
            let sala = MiniCuarto(nombre: "Living Room", paredes: [
                (CGPoint(x: 0, y: 0), CGPoint(x: 14, y: 0)), (CGPoint(x: 14, y: 0), CGPoint(x: 14, y: 12)),
                (CGPoint(x: 14, y: 12), CGPoint(x: 0, y: 12)), (CGPoint(x: 0, y: 12), CGPoint(x: 0, y: 0))],
                aberturas: [(CGPoint(x: 14, y: 4), CGPoint(x: 14, y: 7), .puerta), (CGPoint(x: 4, y: 0), CGPoint(x: 9, y: 0), .ventana)])
            let cocina = MiniCuarto(nombre: "Kitchen", paredes: [
                (CGPoint(x: 14, y: 2), CGPoint(x: 24, y: 2)), (CGPoint(x: 24, y: 2), CGPoint(x: 24, y: 5)),
                (CGPoint(x: 24, y: 12), CGPoint(x: 14, y: 12))],
                aberturas: [(CGPoint(x: 17, y: 12), CGPoint(x: 20, y: 12), .ventana)])
            if vistaPreviaEstado == 3 {
                state = .roomDonePrompt
                pendingCurrentRoomName = nil
                aviso = Aviso(grupo: 0, titulo: "Falta un lado del cuarto", terminar: false)
                avisoTitulo.text = "Falta un lado del cuarto"
                voiceNames = ["Cocina"]
                minimapa.pintar(guardados: [sala], actual: "Kitchen", punto: CGPoint(x: 19, y: 7),
                                enVivo: cocina, huecos: [(CGPoint(x: 24, y: 5), CGPoint(x: 24, y: 12))], huecosAmbar: true)
            }
            if vistaPreviaEstado == 4 {
                state = .roomDonePrompt
                pendingCurrentRoomName = nil
                enRevisionFinal = true
                let cocina2 = MiniCuarto(nombre: "Kitchen", paredes: cocina.paredes + [(CGPoint(x: 24, y: 5), CGPoint(x: 24, y: 12))], aberturas: cocina.aberturas)
                planoGrande.pintar(guardados: [sala, cocina2], actual: nil, punto: nil)
                minimapa.pintar(guardados: [sala, cocina2], actual: nil, punto: nil)
                revisionDatos.text = "2 cuartos · se ve First Floor"
            }
            updateUI()
            return
        }
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
        recorder.update(roomIndex: 0, level: currentLevel, scanning: true, captura: capturaActual)
        // EL ASISTENTE DE MADERAS, EN VIVO. Su pedido del 12 de septiembre:
        // "cuando vea todas esas maderas, sepa identificar que ahí hay una
        // pared". RoomPlan no la va a dibujar (no tiene categoría de
        // madera), pero la cámara SÍ la reconoce mientras camina, y se lo
        // dice en el momento, para que escanee los dos lados sin pelearse
        // con el escáner. Al terminar, el plano trae la partición propuesta
        // justo donde la cámara vio las maderas - y ELLA decide si se parte.
        recorder.onCalidad = { [weak self] texto in
            guard let self = self else { return }
            self.instruccionCalidad = texto
            self.instruccionActual = self.instruccionCalidad ?? self.instruccionApple
            if self.state == .scanningRoom { self.updateUI() }
        }
        recorder.onStudsSeen = { [weak self] roomIdx in
            self?.avisarMaderas(roomIdx, reintento: true)
        }
        recorder.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.leerConfiguracionDeARKit()
        }
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
        arrancarPosicion()
        // Primero el nivel (la bandeja lo pide); el escáner ya corre debajo.
        let intro = eligiendoNivel
            ? "¿En qué nivel estás? Dímelo o tócalo abajo."
            : "Recorre el cuarto y di listo cuando termines. Si quieres, dime el nombre mientras."
        speak(intro) { [weak self] in
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
        if isTorchOn { setTorch(false) }
        posicionTimer?.invalidate()
        posicionTimer = nil
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
        bandejaRecogida = false
        // Un aviso o una revisión final de antes no sigue abierto en el cuarto nuevo.
        aviso = nil
        enRevisionFinal = false
        // He said the next room's name mid-scan, but a missing-wall
        // warning held the auto-advance back. Carry the name forward so
        // he is not asked to repeat himself.
        if pendingCurrentRoomName == nil, let held = pendingRoomNameAfterGap {
            pendingCurrentRoomName = held
        }
        pendingRoomNameAfterGap = nil
        pendingMirroredPort = nil
        // Una captura nueva = un marco nuevo (ARKit reinicia el origen en
        // run()). Se cuenta ANTES de updateUI para que la grabadora marque
        // desde ya las poses con esta captura.
        capturaActual += 1
        isSessionRunning = true
        state = .scanningRoom
        // Si el nombre ya venía dicho, la bandeja sale recogida (solo botones).
        if pendingCurrentRoomName != nil && !eligiendoNivel && completandoIndice == nil { bandejaRecogida = true }
        updateUI()
        cuartoEnVivo = nil
        huecosEnVivo = []
        paredesVistas = [:]
        aberturasVistas = [:]
        engancharEnVivo()
        var config = RoomCaptureSession.Configuration()
        // Sin la guía de Apple ("Move device to start" con el teléfono que
        // sube y baja): él lo pidió fuera, igual que el modelito 3D. Sus
        // indicaciones se dicen en español abajo, en el letrero.
        config.isCoachingEnabled = false
        captureView.captureSession.run(configuration: config)
        // Si la pantalla de Apple vuelve a poner su delegado al arrancar, se
        // envuelve otra vez (pasándole todo a él primero).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.engancharEnVivo() }
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
        // Lo escrito en el campo cuenta ANTES de cerrar el cuarto (si no, se
        // perdía o le caía al cuarto siguiente).
        if campo.isFirstResponder { campo.resignFirstResponder() }
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
        // (world tracking) alive. OJO (14-oct, medido en la casa de Harold):
        // eso NO deja el cuarto siguiente en las mismas coordenadas - cada
        // run() arranca con su propio origen (el camino brinca a (0,0) en cada
        // captura). StructureBuilder es lo que los junta; ver "LOS MARCOS".
        // Apple's own finishing/refinement pass runs
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
    // EL VIGILANTE DE 30 s. Se arma en cuanto se pide terminar, aunque haya un
    // merge o un acomodo de parche todavía en vuelo (antes se armaba solo
    // dentro de finishSession, y si Apple se colgaba antes de llegar ahí la
    // pantalla se quedaba en "Uniendo cuartos…" para siempre). Si ya está
    // armado, no se vuelve a armar.
    private func armarVigilanteFinal() {
        guard finishingWatchdogTimer?.isValid != true else { return }
        finishingWatchdogTimer?.invalidate()
        finishingWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            guard let self = self, !self.sessionDelivered else { return }
            NSLog("[RoomScan] finishing watchdog fired - delivering %d rooms unmerged", self.capturedRooms.count)
            self.sessionDelivered = true
            self.keyframeRecorder?.stopAndDeleteAll()
            self.keyframeRecorder = nil
            // Lo que seguía sin resolverse no se pierde: una captura "posible
            // duplicado" sale como su propio cuarto (como antes de este cambio)
            // y un parche sin acomodar deja su cuarto incompleto.
            for p in self.posiblesDuplicados { self.indicesParche.remove(p); self.parcheDe[p] = nil }
            self.posiblesDuplicados = []
            for p in self.parchesPorAlinear { self.parcheSinAlinear.insert(p) }
            self.entregaCruda = true
            let x = self.sinParches()
            // Lo que viaja con el plano (niveles, incompletos, parches) no
            // se pierde por entregar de emergencia.
            var insp: [String: Any] = ["version": 1, "status": "skipped", "reason": "finish_watchdog"]
            insp.merge(self.extrasDeEntrega(x.rooms, juntado: false)) { _, nuevo in nuevo }
            self.onFinish?(.finished(rooms: x.rooms, structure: nil, merged: false,
                                     levels: x.levels, voiceNames: x.names,
                                     equipment: x.equipment, deletedIndices: x.deleted,
                                     inspection: insp,
                                     surfaceAnswers: self.voiceSurfaceAnswers))
        }
    }

    private func requestFinishSession() {
        armarVigilanteFinal()
        keyframeRecorder?.pauseTicking()
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
        // Ya hay plano: las guardas de 3 s y 5 s de abajo aseguran la entrega,
        // y un plano juntado nunca se cambia por uno sin unir.
        finishingWatchdogTimer?.invalidate()
        finishingWatchdogTimer = nil
        entregaCruda = structure == nil
        let preMergeRooms = capturedRooms
        let preMergeLevels = roomLevels
        let preMergeDeleted = deletedRoomIndices.union(indicesParche)
        // Lo que se completó y lo que se dejó incompleto (y los niveles), ya
        // con el índice del plano entregado.
        let extras = extrasDeEntrega(rooms, juntado: merged)
        // Dónde quedó cada cuarto en el plano entregado, y cada captura.
        let (marcoCuarto, capturas) = marcosDeEntrega(rooms, juntado: merged)
        // La captura de cada foto, aunque su cuarto no vaya en el plano (un
        // cuarto borrado, un parche que no se pegó): para no heredarle a una
        // foto el número de otro cuarto.
        var cuartoDeCaptura: [Int: Int] = [:]
        for (i, c) in capturaDeCuarto { cuartoDeCaptura[c] = grupoDe(i) }
        let recorder = keyframeRecorder
        keyframeRecorder = nil
        let newSessionDir = recorder?.sessionDir
        // Las esquinas que el teléfono avisó, por cuarto ENTREGADO (índice
        // del plano), para que Plan review diga "flagged on site". Viajan
        // dentro de la inspección; nunca mueven nada.
        var esquinasPorSalida: [String: [[String: Any]]] = [:]
        for (out, room) in rooms.enumerated() {
            guard let pre = originalRoomIndex(for: room), let lista = roomCornersByIndex[pre], !lista.isEmpty else { continue }
            // Las esquinas se sacaron en el marco del cuarto; van al plano.
            guard let m = marcoCuarto[pre] else { continue }
            let f = FloorPlanEncoder.metersToFeet
            esquinasPorSalida[String(out)] = lista.map { e0 -> [String: Any] in
                let v = m.aplicarPies(e0.vertex, f: f)
                let e = (vertex: v, d: e0.d, legA: e0.legA, legB: e0.legB)
                return ["x": (Double(e.vertex.x) * 100).rounded() / 100, "y": (Double(e.vertex.y) * 100).rounded() / 100,
                 "d": (e.d * 100).rounded() / 100, "legA": (e.legA * 100).rounded() / 100, "legB": (e.legB * 100).rounded() / 100]
            }
        }
        let probeLock = NSLock()
        var meshProbe: [String: Any]?
        let finish: ([String: Any]?) -> Void = { [weak self] inspectionIn in
            DispatchQueue.main.async {
                guard let self = self, !self.sessionDelivered else { return }
                var inspection = inspectionIn
                // Camino 2: lo que la sonda vio viaja con el plano para
                // poder leerlo después. No cambia nada del plano.
                if !extras.isEmpty {
                    var d = inspection ?? ["version": 1, "status": "skipped"]
                    d.merge(extras) { _, nuevo in nuevo }
                    inspection = d
                }
                if !self.segundoCerebro.isEmpty {
                    var d = inspection ?? ["version": 1, "status": "skipped"]
                    d["segundoCerebro"] = self.segundoCerebro
                    inspection = d
                }
                probeLock.lock(); let mp = meshProbe; probeLock.unlock()
                if mp != nil || self.arConfigProbe != nil {
                    var d = inspection ?? ["version": 1, "status": "skipped"]
                    var b: [String: Any] = ["version": 1]
                    if let mp = mp { b["mesh"] = mp }
                    if let c = self.arConfigProbe { b["arConfig"] = c }
                    d["brainProbe"] = b
                    inspection = d
                }
                if !esquinasPorSalida.isEmpty {
                    var d = inspection ?? ["version": 1, "status": "skipped"]
                    d["scanCorners"] = esquinasPorSalida
                    // Van en el plano entregado (o en su cuarto, sin merge), y la
                    // web lo tiene que saber aunque la inspección se saltara.
                    if d["frame"] == nil { d["frame"] = merged ? "plano" : "cuarto" }
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
        // Las fotos y el camino de un parche son de su cuarto.
        for (p, g) in parcheDe { if let k = mapaIndices[g] { mapaIndices[p] = k } }
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
            probeLock.lock(); meshProbe = trace.meshProbe; probeLock.unlock()
            NSLog("[RoomScan] sonda malla: %@", String(describing: trace.meshProbe))
            DispatchQueue.global(qos: .userInitiated).async {
                // isDelivered doubles as the cancellation signal: once any
                // watchdog ships the plan, inspect stops burning a hot
                // phone's CPU on a result nobody will read.
                let inspection = ScanInspector.remapRoomIndices(
                    ScanInspector.inspect(rooms: preMergeRooms, deletedIndices: preMergeDeleted,
                                          levels: preMergeLevels, trace: trace,
                                          marcoCuarto: marcoCuarto, capturas: capturas, juntado: merged,
                                          cuartoDeCaptura: cuartoDeCaptura,
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
        armarVigilanteFinal()
        // Los parches que todavía no se acomodaron se acomodan AHORA, uno por
        // uno con Apple, antes del merge final. Un parche sin acomodo no se
        // pega (y su cuarto queda incompleto).
        let porAlinear = parchesPorAlinear
        if !porAlinear.isEmpty {
            if #available(iOS 17.0, *) {
                let pares = porAlinear.compactMap { p -> (Int, CapturedRoom, CapturedRoom)? in
                    guard let g = parcheDe[p] else { return nil }
                    return (p, capturedRooms[g], capturedRooms[p])
                }
                NSLog("[RoomScan] acomodando %d parche(s) antes del merge final", pares.count)
                Task { [weak self] in
                    var hechos: [Int: ParAlineado] = [:]
                    for (p, base, parche) in pares {
                        if let t = await Self.alinearPar(base: base, parche: parche) { hechos[p] = t }
                    }
                    await MainActor.run {
                        guard let self = self, !self.sessionDelivered else { return }
                        self.guardarAlineaciones(hechos: hechos, fallidos: porAlinear.filter { hechos[$0] == nil })
                        self.finishSession()
                    }
                }
                return
            }
            guardarAlineaciones(hechos: [:], fallidos: porAlinear)
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
        // Los parches no son cuartos: no entran al merge; se unen a su cuarto
        // al entregar (deliverFinished -> inspection["parches"]).
        let keptIdx = capturedRooms.indices.filter { !excluidosDelMerge.contains($0) }
        let dropIdx = capturedRooms.indices.filter { deletedRoomIndices.contains($0) && !indicesParche.contains($0) }
        guard keptIdx.count > 1 else {
            entregarSinMerge(merged: true)
            return
        }
        if #available(iOS 17.0, *) {
            // El merge final tiene sus 30 s propios (la espera del merge en vivo
            // no le quita tiempo). Si el merge en vivo se colgó, nunca se llega
            // aquí y el vigilante armado al pedir terminar entrega.
            finishingWatchdogTimer?.invalidate()
            finishingWatchdogTimer = nil
            armarVigilanteFinal()
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
                        self.entregarSinMerge(merged: false)
                    }
                }
            }
        } else {
            // No StructureBuilder before iOS 17 - each room stays at its
            // own local origin, honestly flagged as unmerged.
            entregarSinMerge(merged: false)
        }
    }

    // Los cuartos tal como se escanearon, sin los parches (que se unen a su
    // cuarto al entregar) y con los índices de borrados ya acomodados a esa
    // lista. Antes el camino del error mandaba los cuartos sin borrados pero
    // los niveles y nombres de TODOS: se corrían de cuarto.
    private func sinParches() -> (rooms: [CapturedRoom], levels: [Int], names: [String?], equipment: [[String: EquipmentEntry]], deleted: Set<Int>) {
        var r: [CapturedRoom] = [], l: [Int] = [], n: [String?] = [], e: [[String: EquipmentEntry]] = [], d = Set<Int>()
        for i in capturedRooms.indices where !indicesParche.contains(i) || posiblesDuplicados.contains(i) {
            if deletedRoomIndices.contains(i) { d.insert(r.count) }
            r.append(capturedRooms[i])
            l.append(i < roomLevels.count ? roomLevels[i] : 1)
            n.append(i < voiceNames.count ? voiceNames[i] : nil)
            e.append(i < roomEquipment.count ? roomEquipment[i] : [:])
        }
        return (r, l, n, e, d)
    }

    // Dónde quedó cada cuarto (índice de capturedRooms) en el plano que se
    // entrega, y cada captura (con su parche). Del cuarto: el movimiento de
    // sus MISMAS paredes antes y después del merge (sin merge, el mismo
    // cuarto: no se mueve). De un parche: su acomodo en el cuarto y luego el
    // del cuarto.
    private func marcosDeEntrega(_ rooms: [CapturedRoom], juntado: Bool) -> ([Int: FloorPlanEncoder.Rigido2D], [Int: ScanInspector.MarcoDeCaptura]) {
        var marcoCuarto: [Int: FloorPlanEncoder.Rigido2D] = [:]
        // Sin merge el cuarto que se entrega ES el escaneado: no se mueve (y no
        // se calcula, que con puras paredes paralelas el ajuste no sale).
        if !juntado || entregaCruda {
            for room in rooms {
                guard let pre = originalRoomIndex(for: room), pre < capturedRooms.count, !deletedRoomIndices.contains(pre) else { continue }
                marcoCuarto[pre] = .identidad
            }
        }
        for room in rooms where juntado && !entregaCruda {
            // Un cuarto rechazado viaja tal como se escaneó (fuera del merge,
            // en su propio marco): no tiene lugar en el plano juntado, y su
            // caminata no debe mezclarse con la de los demás.
            guard let pre = originalRoomIndex(for: room), pre < capturedRooms.count, marcoCuarto[pre] == nil,
                  !deletedRoomIndices.contains(pre) else { continue }
            let antes = capturedRooms[pre]
            if let t = FloorPlanEncoder.rigidoEntre(antes.walls + antes.doors + antes.windows + antes.openings,
                                                    room.walls + room.doors + room.windows + room.openings) {
                marcoCuarto[pre] = t
            }
        }
        var capturas: [Int: ScanInspector.MarcoDeCaptura] = [:]
        for (i, c) in capturaDeCuarto {
            if let g = parcheDe[i] {
                guard let a = alineacionParche[i], let m = marcoCuarto[g] else { continue }
                capturas[c] = ScanInspector.MarcoDeCaptura(propio: i, grupo: g, marco: a.luego(m))
            } else if let m = marcoCuarto[i] {
                capturas[c] = ScanInspector.MarcoDeCaptura(propio: i, grupo: i, marco: m)
            }
        }
        return (marcoCuarto, capturas)
    }

    // Lo que viaja con el plano además de los cuartos: los nombres de los
    // niveles, lo que los parches sí agregaron, qué cuartos quedaron
    // incompletos y cuántos parches no se pudieron pegar. Lo usan la entrega
    // normal y la de emergencia (el vigilante), para que nunca se pierda.
    private func extrasDeEntrega(_ rooms: [CapturedRoom], juntado: Bool) -> [String: Any] {
        var d: [String: Any] = [:]
        if !nombresDeNivel.isEmpty {
            d["nombresDeNivel"] = Dictionary(uniqueKeysWithValues: nombresDeNivel.map { (String($0.key), $0.value) })
        }
        let parchesEntrega = parchesParaEntregar(rooms, juntado: juntado)
        if !parchesEntrega.isEmpty { d["parches"] = parchesEntrega }
        // Un cuarto cuyo parche no se pudo acomodar (o sigue sin acomodarse), y
        // ninguno otro sí, sigue incompleto: el hueco que se quiso cerrar sigue ahí.
        let pendientes = Set(parchesPorAlinear).subtracting(posiblesDuplicados)
        // Un parche acomodado cuyo cuarto no se pudo ubicar en el plano que se
        // entrega tampoco se pega: se dice.
        let (marcosEnt, _) = marcosDeEntrega(rooms, juntado: juntado)
        let sinLugar = Set(alineacionParche.keys.filter { p in parcheDe[p].map { marcosEnt[$0] == nil } ?? false })
        let noPegados = parcheSinAlinear.union(pendientes).union(sinLugar)
        let sinUnir = Set(noPegados.compactMap { parcheDe[$0] }).filter { g in
            !parches(de: g).contains { alineacionParche[$0] != nil && !noPegados.contains($0) }
        }
        let inc = incompletos.union(sinUnir).filter { !deletedRoomIndices.contains($0) }
        let incompletosEntrega = inc.compactMap { g in rooms.firstIndex { originalRoomIndex(for: $0) == g } }.sorted()
        if !incompletosEntrega.isEmpty { d["incompleteRooms"] = incompletosEntrega }
        let descartados = noPegados.filter { p in parcheDe[p].map { !deletedRoomIndices.contains($0) } ?? false }.count
        if descartados > 0 { d["parchesDescartados"] = descartados }
        // El nombre que el teléfono enseñó como sugerencia (por los muebles)
        // viaja aparte, nunca como nombre dicho: el plano lo usa marcado como
        // sugerido. Antes solo viajaba el nombre dicho, y un cuarto que en el
        // teléfono decía "Dining Room" salía "ROOM 1" en el plano.
        var sugeridos: [String: String] = [:]
        for (k, room) in rooms.enumerated() {
            guard let pre = originalRoomIndex(for: room), pre < capturedRooms.count,
                  !(pre < voiceNames.count && voiceNames[pre] != nil) else { continue }
            if let n = suggestedRoomName(for: capturedRooms[pre]) { sugeridos[String(k)] = Self.enIngles(n) }
        }
        if !sugeridos.isEmpty { d["nombresSugeridos"] = sugeridos }
        return d
    }

    // EL PARCHE UNIDO A SU CUARTO. El parche ya viene acomodado en su cuarto
    // (alinearPar: Apple juntó los dos); ese acomodo, seguido del movimiento
    // del cuarto al plano entregado, lo pone en su lugar. Antes se le
    // aplicaba solo el movimiento del cuarto - como si el parche estuviera
    // en las mismas coordenadas, y no lo estaba: así cayó una caja de paredes
    // encima de la cocina de Harold. De lo escaneado en el parche solo pasa
    // lo que cae en un hueco del cuarto y no se mete en otro cuarto
    // (FloorPlanEncoder.piezasDeParche), y las puertas o ventanas pegadas a
    // esos pedazos que el cuarto no tenía. Nada se borra ni se mueve del
    // cuarto original. Un parche sin acomodo no se pega.
    private func parchesParaEntregar(_ rooms: [CapturedRoom], juntado: Bool) -> [String: [String: Any]] {
        var out: [String: [String: Any]] = [:]
        let f = FloorPlanEncoder.metersToFeet
        func conf(_ c: CapturedRoom.Confidence) -> String {
            switch c { case .high: return "high"; case .medium: return "medium"; default: return "low" }
        }
        let (marcoCuarto, _) = marcosDeEntrega(rooms, juntado: juntado)
        func enPies(_ s: CapturedRoom.Surface) -> (CGPoint, CGPoint) { lineaPies(s) }
        for g in Set(parcheDe.values) where !deletedRoomIndices.contains(g) && g < capturedRooms.count {
            guard let k = rooms.firstIndex(where: { originalRoomIndex(for: $0) == g }), let mg = marcoCuarto[g] else { continue }
            let dest = rooms[k]
            let nivel = g < roomLevels.count ? roomLevels[g] : 1
            // Los demás cuartos del mismo nivel, como se entregan. Sin merge cada
            // cuarto está en el marco de su propia captura: no se comparan.
            var otras: [(CGPoint, CGPoint)] = [], contornos: [[CGPoint]] = []
            if !juntado {
                // Sin merge el cuarto entregado está en su propio marco, el mismo
                // en que el teléfono acomodó a sus vecinos: lo entregado sale
                // igual a lo que se vio (si no, la pared ajena volvía a esconder
                // el hueco y el parche bueno se tiraba).
                let v = vecinosEnMarcoDe(g)
                otras = v.flatMap { $0 }
                contornos = v.map { FloorPlanEncoder.contornoYHuecos(wallsFt: $0).poly }
            }
            for (j, r) in rooms.enumerated() where juntado && j != k {
                guard let pre = originalRoomIndex(for: r), !deletedRoomIndices.contains(pre),
                      (pre < roomLevels.count ? roomLevels[pre] : 1) == nivel else { continue }
                let ps = r.walls.map(enPies)
                otras += ps
                contornos.append(FloorPlanEncoder.contornoYHuecos(wallsFt: ps).poly)
            }
            var propias: [(CGPoint, CGPoint)] = dest.walls.map(enPies)
            var conId: [(id: String, a: CGPoint, b: CGPoint)] = dest.walls.map { w in
                let (a, b) = enPies(w); return (w.identifier.uuidString, a, b)
            }
            var paredes: [[String: Any]] = []
            var aberturas: [String: [[String: Any]]] = ["doors": [], "windows": [], "openings": []]
            for p in parches(de: g) where p < capturedRooms.count {
                guard let a = alineacionParche[p] else { continue }
                let t = a.luego(mg)
                let r = capturedRooms[p]
                var piezasDeEste: [(CGPoint, CGPoint)] = []
                for w in r.walls {
                    let l = moverLinea(enPies(w), t)
                    let piezas = FloorPlanEncoder.piezasDeParche(parcheFt: [l], propiasFt: propias, otrasFt: otras, otrosContornos: contornos)
                    for (u, v) in piezas {
                        let largo = hypot(v.x - u.x, v.y - u.y)
                        let id = w.identifier.uuidString + "-p\(paredes.count)"
                        paredes.append(["id": id, "start": ["x": u.x, "y": u.y], "end": ["x": v.x, "y": v.y],
                                        "lengthFt": largo, "heightFt": Double(w.dimensions.y) * f,
                                        "confidence": conf(w.confidence), "_parche": true])
                        conId.append((id, u, v))
                    }
                    piezasDeEste += piezas
                    propias += piezas
                }
                let tipos: [(String, [CapturedRoom.Surface], [CapturedRoom.Surface])] = [
                    ("doors", r.doors, dest.doors), ("windows", r.windows, dest.windows), ("openings", r.openings, dest.openings)
                ]
                for (clave, nuevas, viejas) in tipos {
                    for o in nuevas {
                        let c = t.aplicarPies(centroPies(o), f: f)
                        // Solo junto a un pedazo que el parche sí agregó.
                        guard piezasDeEste.contains(where: { Self.distSegmento(c, $0.0, $0.1) <= 1.0 }) else { continue }
                        // Ya la tenía el cuarto: no se repite.
                        let repetida = viejas.contains { v in let q = centroPies(v); return hypot(q.x - c.x, q.y - c.y) < 1.5 }
                            || (aberturas[clave] ?? []).contains { d in
                                let pos = d["position"] as? [String: Double] ?? [:]
                                return hypot((pos["x"] ?? 0) - c.x, (pos["y"] ?? 0) - c.y) < 1.5 }
                        guard !repetida else { continue }
                        var dic: [String: Any] = ["id": o.identifier.uuidString, "position": ["x": c.x, "y": c.y],
                                                  "widthFt": Double(o.dimensions.x) * f, "heightFt": Double(o.dimensions.y) * f,
                                                  "confidence": conf(o.confidence), "_parche": true]
                        if let w = conId.min(by: { Self.distSegmento(c, $0.a, $0.b) < Self.distSegmento(c, $1.a, $1.b) }) {
                            dic["wallId"] = w.id
                        }
                        aberturas[clave, default: []].append(dic)
                    }
                }
            }
            guard !paredes.isEmpty || aberturas.values.contains(where: { !$0.isEmpty }) else { continue }
            var entrada: [String: Any] = ["walls": paredes]
            for (clave, lista) in aberturas where !lista.isEmpty { entrada[clave] = lista }
            out[String(k)] = entrada
            NSLog("[RoomScan] parche unido al cuarto %d: %d tramos de pared", k, paredes.count)
        }
        return out
    }

    static func distSegmento(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy
        guard l2 > 0.0001 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
        return hypot(p.x - (a.x + dx * t), p.y - (a.y + dy * t))
    }

    // Lo que queda de la pared AB que ninguna pared de `refs` ya cubre
    // (casi paralela, a menos de 0.7 ft de su línea).
    static func loQueNoCubren(_ a: CGPoint, _ b: CGPoint, _ refs: [(CGPoint, CGPoint)]) -> [(CGPoint, CGPoint)] {
        let dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy
        guard l2 > 0.01 else { return [] }
        let l = sqrt(l2)
        var cortes: [(Double, Double)] = []
        for (c, d) in refs {
            let ex = d.x - c.x, ey = d.y - c.y, m = hypot(ex, ey)
            guard m > 0.1, abs((dx * ex + dy * ey) / (l * m)) > 0.978 else { continue }
            let dist = { (p: CGPoint) -> Double in abs((p.x - a.x) * dy - (p.y - a.y) * dx) / l }
            guard dist(c) < 0.7, dist(d) < 0.7 else { continue }
            let tc = ((c.x - a.x) * dx + (c.y - a.y) * dy) / l2
            let td = ((d.x - a.x) * dx + (d.y - a.y) * dy) / l2
            let lo = max(0, min(tc, td)), hi = min(1, max(tc, td))
            if hi > lo { cortes.append((lo, hi)) }
        }
        cortes.sort { $0.0 < $1.0 }
        var tramos: [(CGPoint, CGPoint)] = []
        var t0 = 0.0
        func punto(_ t: Double) -> CGPoint { CGPoint(x: a.x + dx * t, y: a.y + dy * t) }
        for (lo, hi) in cortes {
            if lo > t0 { tramos.append((punto(t0), punto(lo))) }
            t0 = max(t0, hi)
        }
        if t0 < 1 { tramos.append((punto(t0), punto(1))) }
        return tramos
    }

    private func entregarSinMerge(merged: Bool) {
        let x = sinParches()
        deliverFinished(rooms: x.rooms, structure: nil, merged: merged, levels: x.levels, voiceNames: x.names, equipment: x.equipment, deletedIndices: x.deleted)
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
        let visibleIndices = capturedRooms.indices.filter { !excluidosDelMerge.contains($0) }
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
            marcoVivo = [:]
            liveStructure = nil
            floorPlanPanelView.update(rooms: [], merged: true)
            alTerminarMergeEnVivo()
            return
        }
        guard visibleRooms.count > 1 else {
            mergeGeneration += 1
            let idx = visibleIndices[0]
            let name = voiceNames.indices.contains(idx) ? voiceNames[idx] : nil
            liveStructureRooms = [roomSketch(for: visibleRooms[0], name: name)]
            liveMerged = true
            // Un solo cuarto: su propio marco ES el plano.
            marcoVivo = [idx: .identidad]
            liveStructure = nil
            floorPlanPanelView.update(rooms: liveStructureRooms, merged: true)
            alTerminarMergeEnVivo()
            return
        }
        guard #available(iOS 17.0, *) else {
            mergeGeneration += 1
            applyTiledFallback(visibleRooms: visibleRooms, visibleIndices: visibleIndices)
            alTerminarMergeEnVivo()
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
                        // Dónde quedó cada cuarto en el plano: el movimiento
                        // de sus MISMAS paredes (mismo identificador) antes y
                        // después del merge.
                        var marcos: [Int: FloorPlanEncoder.Rigido2D] = [:]
                        for room in structure.rooms {
                            guard let idx = self.originalRoomIndex(for: room), idx < self.capturedRooms.count else { continue }
                            let antes = self.capturedRooms[idx]
                            if let t = FloorPlanEncoder.rigidoEntre(antes.walls + antes.doors + antes.windows + antes.openings,
                                                                    room.walls + room.doors + room.windows + room.openings) {
                                marcos[idx] = t
                            }
                        }
                        self.marcoVivo = marcos
                        self.liveStructure = structure
                        self.floorPlanPanelView.update(rooms: sketches, merged: true)
                        self.revisarPuertasSinPareja(structure.rooms)
                        // Con los vecinos ya en su lugar, los huecos de cada
                        // cuarto se vuelven a revisar (una pared del cuarto de
                        // al lado que RoomPlan metió en este ya no cuenta). No
                        // mientras hay un aviso abierto: ese pinta lo suyo.
                        if self.aviso == nil { for g in self.gruposDelNivel(nil) { self.revisarGrupo(g) } }
                        self.marcarEsquinasEnPanel(self.gruposDelNivel(nil).last)
                        self.refrescarMinimapa()
                    }
                    if self.pendingFinishSession {
                        self.pendingFinishSession = false
                        self.finishSession()
                        return
                    }
                    self.drainQueuedMergeIfNeeded()
                    self.alTerminarMergeEnVivo()
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
                    self.alTerminarMergeEnVivo()
                }
            }
        }
    }

    private func drainQueuedMergeIfNeeded() {
        guard mergeQueued else { return }
        mergeQueued = false
        refreshLiveStructure()
    }

    // ===== EL PARCHE, ACOMODADO EN SU CUARTO (14-oct) =====
    //
    // "Completar escaneo" es otra captura: arranca con su propio origen. Para
    // saber dónde cae lo que se escaneó, se le pide a Apple que junte SOLO el
    // cuarto y su parche (StructureBuilder con esos dos); el movimiento sale
    // de las mismas paredes antes y después. Si Apple no puede, o si lo que
    // propone no vuelve a ver nada de lo que el cuarto ya tenía, el parche NO
    // se pega: el cuarto se queda como estaba y se dice. Una vez, la casa de
    // Harold recibió una caja de paredes encima de la cocina por pegar un
    // parche sin acomodarlo; eso no vuelve a pasar.
    private var parchesPorAlinear: [Int] {
        indicesParche.filter { p in
            alineacionParche[p] == nil && !parcheSinAlinear.contains(p)
                && (parcheDe[p].map { !deletedRoomIndices.contains($0) && $0 < capturedRooms.count } ?? false)
                && p < capturedRooms.count
        }.sorted()
    }

    private func alinearParchesPendientes() {
        let pendientes = parchesPorAlinear
        guard !pendientes.isEmpty else { drenarEsperas(); return }
        // Una cosa a la vez con Apple: si hay un merge en vivo, este espera
        // a que termine (alTerminarMergeEnVivo lo vuelve a llamar).
        guard !mergeInFlight, !alineandoParches else { return }
        guard #available(iOS 17.0, *) else {
            guardarAlineaciones(hechos: [:], fallidos: pendientes)
            drenarEsperas()
            return
        }
        mergeInFlight = true
        alineandoParches = true
        let pares = pendientes.compactMap { p -> (Int, CapturedRoom, CapturedRoom)? in
            guard let g = parcheDe[p] else { return nil }
            return (p, capturedRooms[g], capturedRooms[p])
        }
        Task { [weak self] in
            var hechos: [Int: ParAlineado] = [:]
            for (p, base, parche) in pares {
                if let t = await Self.alinearPar(base: base, parche: parche) { hechos[p] = t }
            }
            await MainActor.run {
                guard let self = self else { return }
                self.mergeInFlight = false
                self.alineandoParches = false
                self.guardarAlineaciones(hechos: hechos, fallidos: pendientes.filter { hechos[$0] == nil })
                if self.pendingFinishSession {
                    self.pendingFinishSession = false
                    self.finishSession()
                    return
                }
                self.drainQueuedMergeIfNeeded()
                self.alTerminarMergeEnVivo()
            }
        }
    }

    @available(iOS 17.0, *)
    private static func alinearPar(base: CapturedRoom, parche: CapturedRoom) async -> ParAlineado? {
        guard let s = try? await StructureBuilder(options: []).capturedStructure(from: [base, parche]) else {
            NSLog("[RoomScan] parche: Apple no pudo juntarlo con su cuarto")
            return nil
        }
        let salida = s.rooms.flatMap { $0.walls + $0.doors + $0.windows + $0.openings }
        guard let tb = FloorPlanEncoder.rigidoEntre(base.walls + base.doors + base.windows + base.openings, salida),
              let tp = FloorPlanEncoder.rigidoEntre(parche.walls + parche.doors + parche.windows + parche.openings, salida) else {
            NSLog("[RoomScan] parche: no se pudo saber cómo se movió")
            return nil
        }
        let t = tp.luego(tb.inverso)
        // ¿De verdad cuadra? Un parche bien acomodado vuelve a ver parte de
        // lo que el cuarto ya tenía (las paredes junto al hueco).
        let f = FloorPlanEncoder.metersToFeet
        func pies(_ w: CapturedRoom.Surface) -> (CGPoint, CGPoint) {
            let (a, b) = FloorPlanEncoder.wallEndpoints(w)
            return (CGPoint(x: Double(a.x) * f, y: Double(a.y) * f), CGPoint(x: Double(b.x) * f, y: Double(b.y) * f))
        }
        let movidas = parche.walls.map { w -> (CGPoint, CGPoint) in let (a, b) = pies(w); return (t.aplicarPies(a, f: f), t.aplicarPies(b, f: f)) }
        let propias = base.walls.map(pies)
        let c = FloorPlanEncoder.largoCubierto(movidas, por: propias)
        guard c.cubierto >= max(3.0, 0.2 * c.total) else {
            NSLog("[RoomScan] parche: no vuelve a ver nada del cuarto (%.1f de %.1f ft) - no se pega", c.cubierto, c.total)
            return nil
        }
        NSLog("[RoomScan] parche acomodado: giro %.1f°, %.1f de %.1f ft sobre el cuarto", t.th * 180 / .pi, c.cubierto, c.total)
        // ¿Lo traído es el MISMO cuarto? Cada pared traída tiene que caer dentro
        // del cuarto o en su borde (un clóset o baño pegado por fuera comparte
        // paredes pero cae afuera; una cocina en L tiene su centro afuera, por
        // eso se mira pared por pared). Y cuánto cae encima cuenta también lo
        // que llena los huecos de su contorno (la pared que antes no vio).
        let cy = FloorPlanEncoder.contornoYHuecos(wallsFt: propias)
        let dentro = !movidas.isEmpty && movidas.allSatisfy { w in
            let m = CGPoint(x: (w.0.x + w.1.x) / 2, y: (w.0.y + w.1.y) / 2)
            // Una pared que el cuarto ya tenía (aunque sea la ajena que RoomPlan
            // le metió) no prueba que lo traído sea otro cuarto.
            let ya = FloorPlanEncoder.largoCubierto([w], por: propias)
            return FloorPlanEncoder.enPoligono(m, cy.poly) || FloorPlanEncoder.distAlBorde(m, cy.poly) <= 1.0
                || (ya.total > 0 && ya.cubierto >= 0.7 * ya.total)
        }
        let cd = FloorPlanEncoder.largoCubierto(movidas, por: propias + cy.gaps.map { ($0.a, $0.b) })
        return ParAlineado(t: t, frac: cd.total > 0 ? cd.cubierto / cd.total : 0, dentro: dentro)
    }

    private func guardarAlineaciones(hechos: [Int: ParAlineado], fallidos: [Int]) {
        let grupos = Set((Array(hechos.keys) + fallidos).compactMap { parcheDe[$0] })
        var parchesFallidos: [Int] = [], absorbidos: [Int] = [], sonCuartos: [Int] = []
        for (p, par) in hechos {
            if posiblesDuplicados.contains(p) {
                // Lo que trajo después de "Terminar": si casi todo cae sobre el
                // cuarto donde estaba, ES ese cuarto; si no, es otro cuarto.
                if par.dentro && par.frac >= 0.8 { alineacionParche[p] = par.t; absorbidos.append(p) } else { sonCuartos.append(p) }
            } else {
                alineacionParche[p] = par.t
            }
        }
        for p in fallidos {
            if posiblesDuplicados.contains(p) { sonCuartos.append(p) } else { parcheSinAlinear.insert(p); parchesFallidos.append(p) }
        }
        for p in absorbidos + sonCuartos { posiblesDuplicados.remove(p) }
        // Lo que se dijo de equipo durante esa captura es del cuarto donde estaba.
        for p in absorbidos {
            guard let g = parcheDe[p], g < roomEquipment.count, p < roomEquipment.count, !roomEquipment[p].isEmpty else { continue }
            for (k, v) in roomEquipment[p] { roomEquipment[g][k] = v }
            roomEquipment[p] = [:]
        }
        for p in sonCuartos {
            indicesParche.remove(p)
            parcheDe[p] = nil
            revisarGrupo(p)
        }
        if aviso == nil { for g in grupos { revisarGrupo(g) } }
        if !sonCuartos.isEmpty { refreshLiveStructure() }
        marcarEsquinasEnPanel(grupos.max())
        refrescarMinimapa()
        if !absorbidos.isEmpty, state != .finishingSession, !sessionDelivered {
            showVoiceCaption("Era el mismo cuarto: no se guardó aparte")
        }
        // Si la revisión del final ya se hizo (o se está haciendo) sin este
        // acomodo, se repite: el aviso viejo podía pedir completar algo que el
        // parche ya cerró.
        if state == .roomDonePrompt, !sessionDelivered, revisandoTodo || enRevisionFinal || aviso?.terminar == true {
            // Si ya lo había dejado como incompleto ("Continuar de todos modos"),
            // el parche que acaba de pegarse puede haberlo cerrado: se vuelve a
            // revisar desde cero (si el hueco sigue, se le vuelve a avisar).
            for (p, _) in hechos where alineacionParche[p] != nil { if let g = parcheDe[p] { incompletos.remove(g) } }
            enRevisionFinal = false
            validarAlTerminar()
        }
        let fallidos = parchesFallidos
        if !fallidos.isEmpty, state != .finishingSession, !sessionDelivered {
            let nombres = Set(fallidos.compactMap { parcheDe[$0] }).map { nombreDelGrupo($0) }.sorted()
            showVoiceCaption("No se pudo unir lo nuevo a \(nombres.joined(separator: ", "))")
            speak("No pude acomodar lo que escaneaste en \(nombres.joined(separator: " y ")). Ese cuarto se queda como estaba.") {}
        }
        updateUI()
    }

    // Después de cada merge en vivo (o cuando no hubo que hacer uno): si hay
    // parches esperando, se acomodan; si ya no queda nada pendiente, sigue lo
    // que estaba esperando los marcos (la revisión del final).
    private func alTerminarMergeEnVivo() {
        guard !mergeInFlight else { return }
        if !parchesPorAlinear.isEmpty, state != .finishingSession {
            alinearParchesPendientes()
            return
        }
        drenarEsperas()
    }

    private func drenarEsperas() {
        guard !mergeInFlight, !mergeQueued, parchesPorAlinear.isEmpty || state == .finishingSession else { return }
        let w = alListosLosMarcos
        alListosLosMarcos = []
        w.forEach { $0() }
    }

    // Lo que necesita los cuartos juntos (la revisión del final) espera a que
    // el merge en vivo y los parches terminen; nunca más de unos segundos:
    // lo que no esté listo se revisa solo, sin compararlo con los demás.
    private func esperarMarcos(maximo: TimeInterval = 8, _ listo: @escaping () -> Void) {
        var hecho = false
        let una: () -> Void = { if !hecho { hecho = true; listo() } }
        if !mergeInFlight && !mergeQueued && parchesPorAlinear.isEmpty { una(); return }
        alListosLosMarcos.append(una)
        if !mergeInFlight { alTerminarMergeEnVivo() }
        DispatchQueue.main.asyncAfter(deadline: .now() + maximo) { una() }
    }

    // UNA PUERTA QUE UN CUARTO MODELÓ Y SU VECINO NO, sobre el plano juntado
    // (los cuartos de Apple ya en un mismo espacio). Los índices se regresan
    // a los de capturedRooms, que es lo que usa la tarjeta.
    private func revisarPuertasSinPareja(_ juntados: [CapturedRoom]) {
        let niveles = juntados.map { levelForMergedRoom($0) }
        let lista = ScanInspector.mirroredPortCheck(rooms: juntados, deletedIndices: [],
                                                    levels: niveles, alreadyReported: reportedMirroredPorts)
        guard let m = lista.first,
              let dueno = originalRoomIndex(for: juntados[m.ownerRoomIndex]),
              let otro = originalRoomIndex(for: juntados[m.otherRoomIndex]) else { return }
        reportedMirroredPorts.insert(m.portId)
        pendingMirroredPort = ScanInspector.MirroredPort(portId: m.portId, isDoor: m.isDoor, widthFt: m.widthFt,
                                                         ownerRoomIndex: dueno, otherRoomIndex: otro, distFt: m.distFt)
        NSLog("[RoomScan] mirrored port: %@ %.2fft room %d not in room %d (%.4f ft)",
              m.isDoor ? "door" : "opening", m.widthFt, dueno, otro, m.distFt)
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
        // Sin merge no se sabe cómo se juntan: ningún cuarto se compara con
        // otro ni se dibuja junto a otro.
        marcoVivo = [:]
        liveStructure = nil
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
                speak("Este cuarto tuvo un problema al procesarse.") {}
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
        // "Terminar" con la captura siguiente ya andando: con 3 paredes o más
        // ya no se tira, pero tampoco se guarda a ciegas como otro cuarto
        // (sería el mismo cuarto donde estaba, encima del anterior): se junta
        // con el cuarto anterior y Apple dice si es el mismo (ver
        // guardarAlineaciones).
        var posibleDuplicado = false
        if descartarCapturaActual && processedResult.walls.count >= 3 { descartarCapturaActual = false; posibleDuplicado = true }
        if descartarCapturaActual {
            // "Terminar" sin nombre, sin equipo y casi sin paredes: lo que se
            // empezó después del último cuarto no es un cuarto. No se guarda.
            descartarCapturaActual = false
            terminarAlAcabarCuarto = false
            pendingCurrentRoomName = nil
            // El equipo que dijo mientras se procesaba es del cuarto donde
            // estaba (el último guardado de este nivel), no se tira.
            if !pendingCurrentEquipment.isEmpty,
               let previo = (0..<capturedRooms.count).last(where: { !excluidosDelMerge.contains($0) && ($0 < roomLevels.count ? roomLevels[$0] : 1) == currentLevel }),
               previo < roomEquipment.count {
                for (k, v) in pendingCurrentEquipment { roomEquipment[previo][k] = v }
            }
            pendingCurrentEquipment = [:]
            if completandoIndice != nil {
                completandoIndice = nil
                if let n = nivelAntesDeCompletar { currentLevel = n }
                nivelAntesDeCompletar = nil
            }
            state = .roomDonePrompt
            updateUI()
            validarAlTerminar()
            return
        }
        capturedRooms.append(processedResult)
        capturaDeCuarto[capturedRooms.count - 1] = capturaActual
        roomLevels.append(currentLevel)
        voiceNames.append(pendingCurrentRoomName)
        pendingCurrentRoomName = nil
        roomEquipment.append(pendingCurrentEquipment)
        pendingCurrentEquipment = [:]
        let nuevo = capturedRooms.count - 1
        if let g = completandoIndice {
            // Un parche: se une a su cuarto, no es un cuarto aparte. Lo que se
            // dijo mientras (equipo, otro nombre) es de ese cuarto.
            indicesParche.insert(nuevo)
            parcheDe[nuevo] = g
            completandoIndice = nil
            // El parche lleva el nivel de su cuarto; lo que sigue, el nivel
            // en que iba antes de completar.
            if let n = nivelAntesDeCompletar { currentLevel = n }
            nivelAntesDeCompletar = nil
            if g < roomEquipment.count, nuevo < roomEquipment.count, !roomEquipment[nuevo].isEmpty {
                for (k, v) in roomEquipment[nuevo] { roomEquipment[g][k] = v }
                roomEquipment[nuevo] = [:]
            }
            if g < voiceNames.count, nuevo < voiceNames.count, let nm = voiceNames[nuevo], nm != voiceNames[g] {
                voiceNames[g] = nm
            }
        }
        if posibleDuplicado, parcheDe[nuevo] == nil,
           let previo = (0..<nuevo).last(where: { !excluidosDelMerge.contains($0) && ($0 < roomLevels.count ? roomLevels[$0] : 1) == currentLevel }) {
            indicesParche.insert(nuevo)
            parcheDe[nuevo] = previo
            posiblesDuplicados.insert(nuevo)
        }
        let grupo = grupoDe(nuevo)
        let miembros = [grupo] + parches(de: grupo)
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
        // Con un parche, el cuarto se revisa con lo que el parche SÍ agregó,
        // ya acomodado en el marco del cuarto. El parche recién escaneado
        // todavía no está acomodado (eso lo hace Apple juntando los dos, en
        // seguida): mientras tanto se revisa el cuarto como estaba, nunca
        // las dos capturas revueltas en coordenadas distintas.
        let (openGaps, esquinas) = revisarGrupo(grupo)
        _ = miembros
        marcarEsquinasEnPanel(grupo)
        if !esquinas.isEmpty {
            NSLog("[RoomScan] open corners in room %d: %@", capturedRooms.count - 1,
                  esquinas.map { String(format: "%.1fft (legs %.1f/%.1f)", $0.d, $0.legA, $0.legB) }.joined(separator: ", "))
        }
        // Una puerta que un cuarto modeló y su vecino no: se revisa sobre el
        // plano JUNTADO, cuando el merge en vivo termina (refreshLiveStructure).
        // Aquí, con los cuartos cada uno en su propio marco, comparar una
        // puerta de un cuarto con las paredes de otro no significa nada.
        if !openGaps.isEmpty {
            NSLog("[RoomScan] outline gaps in room %d: %@", capturedRooms.count - 1,
                  openGaps.map { String(format: "%.1fft", $0.ft) }.joined(separator: ", "))
        }
        // AI scan coach: score how well the camera actually covered the
        // room that just finished, from the pose trace so far - shown as
        // a live percentage on the room-done card, with a spoken rescan
        // hint when coverage is thin. Background math, main-thread UI.
        let coverageRoomIndex = capturedRooms.count - 1
        let coverageCaptura = capturaDeCuarto[coverageRoomIndex] ?? -1
        keyframeRecorder?.snapshotPoses { [weak self] poses in
            // Solo las poses de ESTA captura: las de otras están en otro marco.
            let result = ScanInspector.quickRoomCoverage(room: processedResult,
                                                         captura: coverageCaptura,
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
                // El segundo asistente no regaña cuarto por cuarto: todo se
                // revisa junto al tocar Terminar (validarAlTerminar).
                if true { return }
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
        let gapsHere = roomGapsByIndex[grupo] ?? []
        // Una esquina abierta de 2 ft o más también frena el auto-continuar:
        // se le va a preguntar si repite, y eso no se pregunta desde el
        // cuarto siguiente.
        let esquinaGrande = (peorEsquina(grupo)?.d ?? 0) >= 2
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
        // "Terminar" mientras escaneaba: el cuarto ya se guardó; si no trae
        // ningún aviso, se termina el plano como con el botón de siempre.
        // EL FLUJO NUEVO (su diseño del 13-oct): al guardar un cuarto se
        // revisa. Completo -> el siguiente cuarto sin ninguna revisión (o la
        // revisión final, si tocó Terminar). Le falta un lado o una esquina
        // -> el aviso ámbar en la bandeja: Completar escaneo o Continuar de
        // todos modos. Las preguntas habladas de antes ya no se hacen aquí.
        let pidioTerminar = terminarAlAcabarCuarto
        terminarAlAcabarCuarto = false
        siguienteAlAcabarCuarto = false
        // EL SEGUNDO ASISTENTE NO INTERRUMPE (13-oct): al pasar de cuarto no
        // se avisa nada - un hueco de ahora puede cerrarlo el cuarto que
        // sigue (el hallway que se escanea después). Todo se revisa junto al
        // tocar Terminar; si se estaba completando algo de esa revisión, se
        // vuelve a revisar.
        _ = gapsHere; _ = esquinaGrande
        if pidioTerminar || enFlujoFinal {
            validarAlTerminar()
            return
        }
        showVoiceCaption("✓ \(nombreDelGrupo(grupo)) guardado")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self, self.state == .roomDonePrompt, self.aviso == nil, !self.enRevisionFinal else { return }
            self.scanAnotherTapped()
        }
        if true { return }
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
    private func applyHeardOrTappedName(_ dichoONombre: String, viaButton: Bool) {
        // Lo dicho o escrito toma el nombre del cuarto del proyecto si se parece claro.
        // Un botón de la lista de siempre ("Bedroom") es una elección: no se cambia.
        let name = viaButton && Self.roomOptionNames.contains(dichoONombre) ? dichoONombre : nombreDelProyecto(dichoONombre)
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
        // El letrero flotante era del diseño viejo (13-oct: "no tiene que
        // aparecer enfrente de la pantalla"). Lo que antes decía ahí ya lo
        // dicen la voz y la bandeja; se deja de enseñar.
        voiceCaptionLabel.text = "  \(name) ✓  "
        voiceCaptionLabel.isHidden = true
        return
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideVoiceCaption), object: nil)
        perform(#selector(hideVoiceCaption), with: nil, afterDelay: 2.5)
    }

    @objc private func hideVoiceCaption() {
        voiceCaptionLabel.isHidden = true
    }

    // EL MICRÓFONO DEL CAMPO (un solo asistente, 13-oct): tocarlo nunca lo
    // apaga - antes lo apagaba y él terminaba dictando con el teclado del
    // iPhone, que solo escribe y no guarda. Ahora cierra el teclado y deja
    // escuchando al asistente. Apagarlo: dejarlo apretado, o decir "cállate".
    @objc private func micCampoTapped() {
        campo.resignFirstResponder()
        micTocadoEn = Date()
        if micMuted { micToggleTapped() }
        showVoiceCaption(eligiendoNivel ? "🎤 Te escucho: di el nivel" : "🎤 Te escucho: di el nombre del cuarto")
    }

    @objc private func micLargoTapped(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        micToggleTapped()
        showVoiceCaption(micMuted ? "Micrófono apagado (déjalo apretado para prenderlo)" : "Micrófono prendido")
    }

    @objc private func micToggleTapped() {
        micMuted.toggle()
        pintarMic()
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
        // Las muletillas del principio ("Sí, en la cocina" se guardó como
        // "Sí en la cocina", 13-oct): se quitan antes que nada, varias si hay.
        let muletillas = ["sí", "si", "no", "ok", "okay", "bueno", "pues", "ya", "ahora", "eh", "mmm"]
        var quitoAlgo = true
        while quitoAlgo {
            quitoAlgo = false
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:¡!¿?"))
            let l = text.lowercased()
            for m in muletillas where l.hasPrefix(m + " ") || l.hasPrefix(m + ",") || l.hasPrefix(m + ".") {
                text = String(text.dropFirst(m.count))
                quitoAlgo = true
                break
            }
        }
        let fillers = [
            "ahora estoy en la ", "ahora estoy en el ",
            "estoy en la ", "estoy en el ", "estoy en ",
            "esto es la ", "esto es el ", "es la ", "es el ",
            "vamos a la ", "vamos al ", "en la ", "en el ",
            "i'm in the ", "i am in the ", "this is the ", "it's the ", "in the ",
            "la ", "el "
        ]
        let lower = text.lowercased()
        for filler in fillers where lower.hasPrefix(filler) {
            text = String(text.dropFirst(filler.count))
            break
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:¡!¿?"))
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

        // Las ordenes de pasar de cuarto NUNCA son un nombre. "Nuevo cuarto"
        // lleva la palabra "cuarto" y pasaba como nombre conocido ("cuarto de
        // Chucho"): en Scanova salieron dos cuartos llamados "Nuevo cuarto"
        // (14-oct). Mientras escanea se ignora; al terminar el cuarto se
        // contesta arriba como "otro cuarto".
        if Self.isMoveOnPhrase(lower) { return .ignored }
        if let name = cleanVoiceRoomName(raw) {
            return .roomName(name)
        }
        return .ignored
    }
    // Una frase que trae una orden (listo, terminar, siguiente, otro cuarto…)
    // no es un nombre de cuarto: no se aprende ni sale como botón. En builds
    // viejos se aprendieron "Nuevo cuarto" y "Sí en la cocina"; tocarlos le
    // ponía ese nombre al cuarto.
    static func traeOrden(_ nombre: String) -> Bool {
        let k = " " + normalizedName(nombre) + " "
        if isMoveOnPhrase(normalizedName(nombre)) { return true }
        let ordenes = ["listo", "lista", "terminar", "terminamos", "termine", "siguiente", "completar", "continuar", "guardar", "cancelar"]
        if ordenes.contains(where: { k.contains(" " + $0 + " ") }) { return true }
        let muletillas = ["si", "no", "ok", "okay", "este", "esta", "eh", "ah", "todo", "ya", "quedo", "bueno", "eso"]
        let partes = normalizedName(nombre).split(separator: " ").map(String.init)
        if let primera = partes.first, muletillas.contains(primera) { return true }
        // Una sola palabra que no es nombre ("El", "Pues", "Estoy").
        if partes.count == 1, ["el", "la", "los", "las", "mi", "su", "ese", "esa", "pues", "estoy", "estas", "estamos"].contains(partes[0]) { return true }
        // "Cocina está", "Baño ya quedó": una frase que termina en relleno no es un nombre.
        let rellenoFinal = ["esta", "ya", "quedo", "estuvo", "todo", "bien", "listo", "lista"]
        if partes.count > 1, let u = partes.last, rellenoFinal.contains(u) { return true }
        return false
    }

    static func isMoveOnPhrase(_ lower: String) -> Bool {
        let key = normalizedName(lower)
        let frases = ["nuevo cuarto", "cuarto nuevo", "otro cuarto", "siguiente cuarto", "otro nivel", "es nuevo", "el siguiente", "el que sigue"]
        return frases.contains(where: { key == normalizedName($0) || key.hasPrefix(normalizedName($0) + " ") || key.hasSuffix(" " + normalizedName($0)) })
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
        let vivos = capturedRooms.indices.filter { !excluidosDelMerge.contains($0) }
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
        if !nivelBase.isEmpty { frase += ". Vas en \(nombreHablado(currentLevel))" }
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
        // Lo aprendido que en realidad era una orden se tira (y se guarda la
        // lista limpia), para que no vuelva a salir como botón.
        let todos = d.stringArray(forKey: Self.learnedNamesKey) ?? []
        learnedRoomNames = Set(todos.filter { !Self.traeOrden($0) })
        if learnedRoomNames.count != Set(todos).count { d.set(Array(learnedRoomNames), forKey: Self.learnedNamesKey) }
        ownSpeechLevel = d.float(forKey: Self.ownLevelKey)
        ownSpeechSamples = d.integer(forKey: Self.ownLevelKey + ":n")
    }

    // Cada nombre que EL confirma queda aprendido: la proxima casa esa
    // palabra ya entra sin preguntar. Aqui es donde deja de ser una lista
    // nuestra y empieza a ser su vocabulario.
    private func learnRoomName(_ name: String) {
        let key = Self.normalizedName(name)
        guard !key.isEmpty, !Self.knownRoomWords.contains(key), !learnedRoomNames.contains(key), !Self.traeOrden(key) else { return }
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
        // Los de la tabla de inglés (habitación, dormitorio, gimnasio…) también,
        // dichos en español o en inglés ("kitchen", "bedroom"), con número o con
        // "principal" al final ("dormitorio 2", "habitación principal").
        var sinCola = key.replacingOccurrences(of: #"\s+(\d+|uno|dos|tres|cuatro|principal|grande|chico|chica)$"#, with: "", options: .regularExpression)
        sinCola = sinCola.trimmingCharacters(in: .whitespaces)
        if cuartosEnIngles[key] != nil || cuartosEnIngles[sinCola] != nil { return true }
        if cuartosEnIngles.values.contains(where: { normalizedName($0) == key || normalizedName($0) == sinCola }) { return true }
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
        // LA BANDEJA PIDE EL NIVEL: mientras está en ese paso, lo que se dice
        // es el nivel y nada más (ni "listo", ni nombres de cuarto).
        if eligiendoNivel && (state == .scanningRoom || state == .roomDonePrompt) {
            let dicho = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let v = nivelDeTexto(dicho) {
                seleccionarNivel(v)
                continuarTapped()
            } else if !dicho.isEmpty, dicho.split(separator: " ").count <= 4 {
                // Por voz SOLO entra un nivel del proyecto. Antes cualquier
                // cosa dicha quedaba como nivel: "living room" se volvió el
                // nivel y el plano decía "Living Room" donde va el piso.
                let opciones = nivelesDelProyecto.prefix(3).map { Self.nombreVisible($0) }.joined(separator: ", ")
                speak("Primero el nivel. Di o toca uno: \(opciones).") {}
            }
            return
        }
        // UN SOLO ASISTENTE (13-oct): la voz sigue a la bandeja y nada más.
        // Lo que la bandeja pide es lo que se escucha; ya no hay preguntas
        // aparte de "¿es el nombre?" o "¿cuarto nuevo o corrijo?".
        do {
            let l = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:¡!¿?"))
            let n = l.split(separator: " ").count
            func dice(_ ws: [String]) -> Bool { ws.contains { l == $0 || l.contains($0) } }
            // Los comandos de siempre ("cállate", "cómo vamos") siguen su camino
            // de abajo; un "sí"/"no" suelto no es un nombre.
            let generales = ["silencio", "cállate", "callate", "ya no hables", "cállese", "callese",
                             "cómo vamos", "como vamos", "qué llevo", "que llevo", "cuántos cuartos",
                             "cuantos cuartos", "qué tengo", "que tengo"]
            let esGeneral = n <= 4 && dice(generales)
            let esSiNo = n <= 2 && (Self.isYes(l) || Self.isNo(l))
            let controles = ["siguiente", "otro cuarto", "cuarto nuevo", "nuevo cuarto", "cuarto listo",
                             "terminar", "terminamos", "termina el plano", "terminé", "termine", "ya terminé", "ya termine"]
            let esControl = n <= 3 && (dice(controles) || l == "listo")
            // ¿Se le puede creer que es un nombre? Un nombre de cuarto conocido,
            // o la bandeja está pidiendo el nombre, o acaba de tocar el micrófono.
            let micReciente = micTocadoEn.map { Date().timeIntervalSince($0) < 12 } ?? false
            func esNombreCreible(_ nombre: String, pidiendo: Bool) -> Bool {
                let k = nombre.split(separator: " ").count
                guard k <= 4, !esGeneral, !esSiNo, !esControl, !Self.isMoveOnPhrase(nombre.lowercased()), !Self.traeOrden(nombre) else { return false }
                return isKnownRoomWord(nombre) || CuartosDelProyecto.emparejar(nombre, con: cuartosDelProyectoAhora(), traducir: Self.enIngles, usados: voiceNames.compactMap { $0 }) != nil || micReciente || (pidiendo && k <= 3)
            }
            if !esGeneral {
                if state == .roomDonePrompt, aviso != nil {
                    if n <= 4, dice(["completar", "completa", "complétalo", "completalo"]) { completarTapped(); return }
                    if n <= 4, dice(["continuar", "continúa", "continua", "sigue así", "sigue asi", "de todos modos"]) { continuarIgualTapped(); return }
                    return
                }
                if state == .roomDonePrompt, enRevisionFinal {
                    if n <= 3, dice(["guardar", "guarda", "guárdalo", "guardalo"]) { guardarTapped(); return }
                    if n <= 3, dice(["otro nivel"]) { otroNivelTapped(); return }
                    if n <= 4, dice(["seguir", "sigue escaneando", "otro cuarto"]) { seguirTapped(); return }
                    return
                }
                if revisandoTodo { return }
                // Entre un cuarto y el siguiente: un nombre ahí es del que SIGUE.
                if state == .processingRoom || (state == .roomDonePrompt && aviso == nil && !enRevisionFinal) {
                    // El equipo dicho justo después de "listo" es del cuarto que
                    // se acaba de cerrar (antes se tiraba sin avisar).
                    if case .logEquipment(let items) = classifyVoiceCommand(raw) {
                        applyEquipmentLog(items, rawHeard: raw)
                        return
                    }
                    if case .removeEquipment(let type, let count) = classifyVoiceCommand(raw) {
                        applyEquipmentRemoval(type: type, count: count)
                        return
                    }
                    if case .roomName(let nombre) = classifyVoiceCommand(raw), !Self.traeOrden(nombre), esNombreCreible(nombre, pidiendo: false) {
                        let nombre = nombreDelProyecto(nombre)
                        learnRoomName(nombre)
                        pendingRoomNameAfterGap = nombre
                        speak("Entendido, el siguiente es \(Self.enIngles(nombre)).") {}
                    }
                    return
                }
                if state == .scanningRoom && !eligiendoNivel {
                    if n <= 3, dice(["siguiente", "otro cuarto", "cuarto nuevo", "nuevo cuarto", "cuarto listo"]) || l == "listo" {
                        noteOwnSpeechLevel(level)
                        siguienteTapped()
                        return
                    }
                    // El nombre y "listo" de corrido ("sala listo", "listo, la
                    // cocina"): se separan, el nombre se pone (si de verdad es un
                    // nombre de cuarto) y el cuarto se cierra, como con "listo".
                    // Antes el cuarto se llamaba "Sala listo". Una frase con duda o
                    // negación ("no está listo", "casi lista", "¿estás listo?")
                    // NUNCA cierra el cuarto.
                    var palabras = l.split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:¡!¿?")) }.filter { !$0.isEmpty }
                    while palabras.count > 1, let p0 = palabras.first, ["si", "sí", "bueno", "ok", "okay", "pues", "ya", "ahora", "eh", "y"].contains(p0) { palabras.removeFirst() }
                    // "ya listo", "pues listo", "ok listo": es "listo".
                    if palabras.count == 1, ["listo", "lista"].contains(palabras[0]), n <= 3 {
                        noteOwnSpeechLevel(level)
                        siguienteTapped()
                        return
                    }
                    if palabras.count >= 2, palabras.count <= 8,
                       let pos = [0, palabras.count - 1].first(where: { ["listo", "lista"].contains(palabras[$0]) }) {
                        var resto = palabras
                        resto.remove(at: pos)
                        let duda: Set<String> = ["no", "todavia", "aun", "casi", "falta", "estas", "estan", "esta?"]
                        if resto.contains(where: { duda.contains(Self.sinAcentos($0)) }) { return }
                        // "listo, otro nivel": aquí no se cierra nada (mientras se escanea
                        // no hay orden de otro nivel; se pide al terminar el cuarto).
                        if resto.joined(separator: " ").contains("otro nivel") { return }
                        // "listo, terminamos": se termina el plano, como siempre. ("ya
                        // terminé" quiere decir este cuarto, como en el resto del
                        // asistente: eso es "listo".)
                        if dice(["terminar", "terminamos", "termina el plano"]) {
                            noteOwnSpeechLevel(level)
                            terminarTapped()
                            return
                        }
                        // "la cocina está lista", "el baño ya quedó listo", "estoy listo":
                        // el relleno y los artículos no son parte del nombre.
                        let relleno: Set<String> = ["esta", "ya", "quedo", "estuvo", "todo", "bien", "estoy", "estamos"]
                        let articulos: Set<String> = ["el", "la", "los", "las", "mi", "su", "ese", "esa", "este", "esta"]
                        var cambio = true
                        while cambio, let u = resto.last {
                            cambio = false
                            let k = Self.sinAcentos(u)
                            if relleno.contains(k) || articulos.contains(k) || k == "cuarto" { resto.removeLast(); cambio = true }
                        }
                        let dichoNombre = resto.joined(separator: " ")
                        noteOwnSpeechLevel(level)
                        // "dos ventiladores listo": el equipo se guarda con el cuarto
                        // antes de cerrarlo. Si no dijo cuántos, no se cierra: se
                        // le pregunta como siempre.
                        let queEs = dichoNombre.isEmpty ? VoiceIntent.ignored : classifyVoiceCommand(dichoNombre)
                        if case .logEquipment(let items) = queEs {
                            applyEquipmentLog(items, rawHeard: raw)
                            if items.allSatisfy({ $0.count != nil }) { siguienteTapped() }
                            return
                        }
                        if case .removeEquipment(let type, let count) = queEs {
                            applyEquipmentRemoval(type: type, count: count)
                            siguienteTapped()
                            return
                        }
                        // El resto es nombre solo si es nombre de cuarto (o se lo
                        // estaban pidiendo y son pocas palabras), y nunca cambia en
                        // silencio un nombre que ya tenía.
                        let pidiendoNombre = pendingCurrentRoomName == nil && completandoIndice == nil && !bandejaRecogida
                        if !dichoNombre.isEmpty, case .roomName(let nombre) = queEs,
                           !Self.traeOrden(nombre),
                           isKnownRoomWord(nombre) || (pidiendoNombre && (micReciente || nombre.split(separator: " ").count <= 3)),
                           pendingCurrentRoomName == nil || Self.sinAcentos(pendingCurrentRoomName!) == Self.sinAcentos(nombre) {
                            learnRoomName(nombre)
                            pendingCurrentRoomName = nombre
                            if !campo.isEditing { campo.text = Self.enIngles(nombre) }
                        }
                        siguienteTapped()
                        return
                    }
                    if n <= 3, dice(["terminar", "terminamos", "termina el plano"]) {
                        noteOwnSpeechLevel(level)
                        terminarTapped()
                        return
                    }
                    if esSiNo { return }
                    let intento = classifyVoiceCommand(raw)
                    if case .roomName(let nombre) = intento {
                        let pidiendo = pendingCurrentRoomName == nil && !bandejaRecogida
                        guard esNombreCreible(nombre, pidiendo: pidiendo) else { return }
                        // El nombre se guarda directo (o corrige el que tenía).
                        pendingUnsureName = nil
                        roomSplitConfirmationTimer?.invalidate()
                        roomSplitConfirmationTimer = nil
                        pendingRoomSplitCandidateName = nil
                        learnRoomName(nombre)
                        let isRename = pendingCurrentRoomName != nil && pendingCurrentRoomName != nombre
                        if let g = completandoIndice, g < voiceNames.count { voiceNames[g] = nombre }
                        pendingCurrentRoomName = nombre
                        if !campo.isEditing { campo.text = Self.enIngles(nombre) }
                        confirmName(Self.enIngles(nombre), isRename: isRename)
                        animarBandeja()
                        return
                    }
                }
            }
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
        if wordCount <= 4, ["silencio", "cállate", "callate", "ya no hables", "cállese", "callese"]
            .contains(where: { lower.contains($0) }) {
            noteOwnSpeechLevel(level)
            speak("Me callo. Toca el micrófono en la pantalla cuando quieras que vuelva.") { [weak self] in
                guard let self = self, !self.micMuted else { return }
                self.micMuted = true
                self.pintarMic()
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
            if lower.contains("otro cuarto") || lower.contains("siguiente cuarto") ||
               lower.contains("nuevo cuarto") || lower.contains("cuarto nuevo") { scanAnotherTapped(); return }
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
        case .scanningRoom, .processingRoom:
            // Procesando: el cuarto que se acaba de cerrar todavía no se
            // guardó; lo pendiente se le pone al guardarse (didPresent).
            for item in items {
                let vocab = Self.equipmentVocabulary.first { $0.type == item.type }
                pendingCurrentEquipment[item.type] = EquipmentEntry(
                    type: item.type, label: vocab?.label ?? item.type, count: item.count,
                    mode: "set", confidence: item.count != nil ? "heard" : "unclear", rawHeard: rawHeard
                )
            }
        case .roomDonePrompt:
            // Un parche no es un cuarto: lo dicho es de su cuarto.
            guard let ultimo = capturedRooms.indices.last else { return }
            let index = grupoDe(ultimo)
            guard roomEquipment.indices.contains(index) else { return }
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
        case .scanningRoom, .processingRoom:
            guard var existing = pendingCurrentEquipment[type], let existingCount = existing.count else { return }
            existing.count = max(0, existingCount - removed)
            pendingCurrentEquipment[type] = existing
        case .roomDonePrompt:
            // Un parche no es un cuarto: lo de su cuarto.
            guard let ultimo = capturedRooms.indices.last else { return }
            let index = grupoDe(ultimo)
            guard roomEquipment.indices.contains(index),
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

// EL MINIMAPA de la cámara: los cuartos YA guardados de este nivel en gris y
// dónde está parado ahora en azul. Lo que se le pasa ya viene en UN marco (el
// plano, o el de la captura en curso): mezclar marcos de capturas distintas
// es lo que encimaba cuartos.
// Un cuarto del minimapa: sus paredes y sus aberturas (puerta, ventana o
// paso sin puerta), en pies, en las coordenadas de la cámara.
struct MiniCuarto {
    enum Tipo { case puerta, ventana, paso }
    let nombre: String?
    let paredes: [(CGPoint, CGPoint)]
    let aberturas: [(CGPoint, CGPoint, Tipo)]
}

final class MinimapaVista: UIView {
    private var guardados: [MiniCuarto] = []
    private var actual: String?
    private var punto: CGPoint?
    private var enVivo: MiniCuarto?
    private var huecos: [(CGPoint, CGPoint)] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var huecosAmbar = false
    func pintar(guardados: [MiniCuarto], actual: String?, punto: CGPoint?,
                enVivo: MiniCuarto? = nil, huecos: [(CGPoint, CGPoint)] = [], huecosAmbar: Bool = false) {
        self.huecosAmbar = huecosAmbar
        self.guardados = guardados
        self.actual = actual
        self.punto = punto
        self.enVivo = enVivo
        self.huecos = huecos
        setNeedsDisplay()
    }

    // Lo que queda de una pared después de quitarle los huecos de las
    // aberturas que caen sobre ella.
    static func tramosSinAberturas(_ a: CGPoint, _ b: CGPoint, _ ab: [(CGPoint, CGPoint, MiniCuarto.Tipo)]) -> [(CGPoint, CGPoint)] {
        let dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy
        guard l2 > 0.0001 else { return [] }
        let l = sqrt(l2)
        var cortes: [(CGFloat, CGFloat)] = []
        for (p, q, _) in ab {
            // ¿Está sobre esta pared? (cerca de su línea, en sus pies)
            let dist = { (r: CGPoint) -> CGFloat in abs((r.x - a.x) * dy - (r.y - a.y) * dx) / l }
            guard dist(p) < 0.7, dist(q) < 0.7 else { continue }
            let tp = ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2
            let tq = ((q.x - a.x) * dx + (q.y - a.y) * dy) / l2
            let lo = max(0, min(tp, tq)), hi = min(1, max(tp, tq))
            if hi > lo { cortes.append((lo, hi)) }
        }
        cortes.sort { $0.0 < $1.0 }
        var tramos: [(CGPoint, CGPoint)] = []
        var t0: CGFloat = 0
        func punto(_ t: CGFloat) -> CGPoint { CGPoint(x: a.x + dx * t, y: a.y + dy * t) }
        for (lo, hi) in cortes {
            if lo > t0 { tramos.append((punto(t0), punto(lo))) }
            t0 = max(t0, hi)
        }
        if t0 < 1 { tramos.append((punto(t0), punto(1))) }
        return tramos
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let gris = UIColor(white: 0.45, alpha: 1)
        var pts = guardados.flatMap { $0.paredes.flatMap { [$0.0, $0.1] } }
        if let v = enVivo { pts += v.paredes.flatMap { [$0.0, $0.1] } }
        if let p = punto { pts.append(p) }
        if guardados.isEmpty && enVivo == nil {
            let texto = "Aquí sale cada cuarto" as NSString
            let par = NSMutableParagraphStyle(); par.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: gris, .paragraphStyle: par]
            let caja = CGRect(x: 4, y: rect.height - 18, width: rect.width - 8, height: 16)
            texto.draw(in: caja, withAttributes: attrs)
        }
        guard !pts.isEmpty else { return }
        let minX = pts.map(\.x).min()!, maxX = pts.map(\.x).max()!
        let minY = pts.map(\.y).min()!, maxY = pts.map(\.y).max()!
        let spanX = max(maxX - minX, 6), spanY = max(maxY - minY, 6)
        let alto = (guardados.isEmpty && enVivo == nil) ? rect.height - 18 : rect.height
        let scale = min((rect.width - 24) / spanX, (alto - 22) / spanY)
        let ox = (rect.width - (maxX - minX) * scale) / 2, oy = (alto - (maxY - minY) * scale) / 2
        func pr(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - minX) * scale + ox, y: (p.y - minY) * scale + oy) }

        // Cuartos guardados: gris, con el hueco de cada puerta y ventana.
        ctx.setStrokeColor(gris.cgColor)
        ctx.setLineWidth(2.2)
        ctx.setLineCap(.butt)
        for r in guardados {
            for (a, b) in r.paredes {
                for (u, v) in Self.tramosSinAberturas(a, b, r.aberturas) {
                    ctx.move(to: pr(u)); ctx.addLine(to: pr(v))
                }
            }
        }
        ctx.strokePath()
        for r in guardados {
            for (a, b, tipo) in r.aberturas {
                let pa = pr(a), pb = pr(b)
                let dx = pb.x - pa.x, dy = pb.y - pa.y, l = max(hypot(dx, dy), 0.001)
                let nx = -dy / l * 3, ny = dx / l * 3
                switch tipo {
                case .ventana:
                    // Ventana: línea doble delgada en el hueco.
                    ctx.setStrokeColor(gris.withAlphaComponent(0.85).cgColor)
                    ctx.setLineWidth(1)
                    ctx.move(to: CGPoint(x: pa.x + nx * 0.5, y: pa.y + ny * 0.5)); ctx.addLine(to: CGPoint(x: pb.x + nx * 0.5, y: pb.y + ny * 0.5))
                    ctx.move(to: CGPoint(x: pa.x - nx * 0.5, y: pa.y - ny * 0.5)); ctx.addLine(to: CGPoint(x: pb.x - nx * 0.5, y: pb.y - ny * 0.5))
                    ctx.strokePath()
                case .puerta:
                    // Puerta: el hueco con sus dos marcos.
                    ctx.setStrokeColor(gris.cgColor)
                    ctx.setLineWidth(2)
                    for p in [pa, pb] {
                        ctx.move(to: CGPoint(x: p.x - nx, y: p.y - ny)); ctx.addLine(to: CGPoint(x: p.x + nx, y: p.y + ny))
                    }
                    ctx.strokePath()
                case .paso:
                    break
                }
            }
        }
        for r in guardados {
            guard let n = r.nombre, !n.isEmpty, !r.paredes.isEmpty else { continue }
            let xs = r.paredes.flatMap { [$0.0.x, $0.1.x] }, ys = r.paredes.flatMap { [$0.0.y, $0.1.y] }
            let c = pr(CGPoint(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2))
            let anchoCuarto = (xs.max()! - xs.min()!) * scale - 8
            // Un nombre que no cabe en su cuarto se achica; si ni así, no se pone.
            // Un renglón si cabe; si no, dos ("Living / Room"); si ni así, nada.
            let altoCuarto = (ys.max()! - ys.min()!) * scale - 6
            let par = NSMutableParagraphStyle(); par.alignment = .center; par.lineBreakMode = .byWordWrapping
            for tam in [10.0, 9.0, 8.0] as [CGFloat] {
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: tam, weight: .medium), .foregroundColor: gris, .paragraphStyle: par]
                let t = n as NSString
                let caja = t.boundingRect(with: CGSize(width: max(anchoCuarto, 1), height: 200), options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
                let palabraMasLarga = n.split(separator: " ").map { ($0 as NSString).size(withAttributes: attrs).width }.max() ?? 0
                if palabraMasLarga <= anchoCuarto, caja.height <= min(altoCuarto, tam * 2.6) {
                    t.draw(in: CGRect(x: c.x - anchoCuarto / 2, y: c.y - caja.height / 2, width: anchoCuarto, height: caja.height + 2), withAttributes: attrs)
                    break
                }
            }
        }

        // El cuarto que va: azul, con sus puertas y ventanas; lo que todavía
        // no se cierra, punteado.
        var centroEnVivo: CGPoint?
        var anchoEnVivo: CGFloat = 0
        if let v = enVivo, !v.paredes.isEmpty {
            let azul = UIColor.systemBlue
            ctx.setStrokeColor(azul.cgColor)
            ctx.setLineWidth(2.2)
            ctx.setLineCap(.butt)
            ctx.setLineDash(phase: 0, lengths: [])
            for (a, b) in v.paredes {
                for (u, w) in Self.tramosSinAberturas(a, b, v.aberturas) { ctx.move(to: pr(u)); ctx.addLine(to: pr(w)) }
            }
            ctx.strokePath()
            for (a, b, tipo) in v.aberturas {
                let pa = pr(a), pb = pr(b)
                let dx = pb.x - pa.x, dy = pb.y - pa.y, l = max(hypot(dx, dy), 0.001)
                let nx = -dy / l * 3, ny = dx / l * 3
                if tipo == .ventana {
                    ctx.setLineWidth(1)
                    ctx.move(to: CGPoint(x: pa.x + nx * 0.5, y: pa.y + ny * 0.5)); ctx.addLine(to: CGPoint(x: pb.x + nx * 0.5, y: pb.y + ny * 0.5))
                    ctx.move(to: CGPoint(x: pa.x - nx * 0.5, y: pa.y - ny * 0.5)); ctx.addLine(to: CGPoint(x: pb.x - nx * 0.5, y: pb.y - ny * 0.5))
                    ctx.strokePath()
                } else if tipo == .puerta {
                    ctx.setLineWidth(2)
                    for q in [pa, pb] { ctx.move(to: CGPoint(x: q.x - nx, y: q.y - ny)); ctx.addLine(to: CGPoint(x: q.x + nx, y: q.y + ny)) }
                    ctx.strokePath()
                }
            }
            if !huecos.isEmpty {
                if huecosAmbar { ctx.setStrokeColor(UIColor.systemOrange.cgColor) }
                ctx.setLineWidth(huecosAmbar ? 3 : 2.5)
                ctx.setLineDash(phase: 0, lengths: [4, 3])
                for (a, b) in huecos { ctx.move(to: pr(a)); ctx.addLine(to: pr(b)) }
                ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: [])
            }
            let xs = v.paredes.flatMap { [$0.0.x, $0.1.x] }, ys = v.paredes.flatMap { [$0.0.y, $0.1.y] }
            centroEnVivo = pr(CGPoint(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2))
            anchoEnVivo = (xs.max()! - xs.min()!) * scale - 8
        }
        if let c = centroEnVivo, let n = actual, !n.isEmpty {
            // Que quepa dentro de su cuarto: se achica antes que tocar la pared.
            for tam in [10.0, 9.0, 8.0] as [CGFloat] {
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: tam, weight: .semibold), .foregroundColor: UIColor.systemBlue]
                let t = n as NSString, sz = t.size(withAttributes: attrs)
                if sz.width <= anchoEnVivo || tam == 8 {
                    t.draw(at: CGPoint(x: c.x - sz.width / 2, y: c.y - sz.height - 3), withAttributes: attrs)
                    break
                }
            }
        }

        // Donde está parado: el punto azul.
        if let p = punto {
            let c = pr(p)
            ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.18).cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20))
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - 5.5, y: c.y - 5.5, width: 11, height: 11))
            ctx.setFillColor(UIColor.systemBlue.cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8))
            if centroEnVivo == nil, let n = actual, !n.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: UIColor.systemBlue]
                let t = n as NSString, sz = t.size(withAttributes: attrs)
                var x = c.x - sz.width / 2
                x = max(2, min(rect.width - sz.width - 2, x))
                let y = c.y - 16 - sz.height < 0 ? c.y + 14 : c.y - 16 - sz.height
                t.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
            }
        }
    }
}


// El intermediario del cuarto en vivo. RoomPlan tiene UN solo delegado de
// sesión; si la pantalla de Apple ya lo usa, se le sigue pasando TODO,
// primero y completo, para que su vista en vivo no cambie en nada. A la app
// solo le llega una copia del cuarto, como mucho dos veces por segundo, en
// el hilo principal, y solo se dibuja: no se guarda nada de aquí.
final class DelegadoEnVivo: NSObject, RoomCaptureSessionDelegate {
    var original: RoomCaptureSessionDelegate?
    var alActualizar: ((CapturedRoom) -> Void)?
    // Las indicaciones de Apple ("más despacio", "acércate"), en español,
    // ahora que su guía en pantalla está apagada.
    var alIndicar: ((String?) -> Void)?
    private let lock = NSLock()
    private var ultimo: CFTimeInterval = 0

    private func avisar(_ room: CapturedRoom) {
        lock.lock()
        let ahora = CACurrentMediaTime()
        let toca = ahora - ultimo >= 0.5
        if toca { ultimo = ahora }
        lock.unlock()
        guard toca, let f = alActualizar else { return }
        DispatchQueue.main.async { f(room) }
    }

    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        original?.captureSession(session, didUpdate: room); avisar(room)
    }
    func captureSession(_ session: RoomCaptureSession, didAdd room: CapturedRoom) {
        original?.captureSession(session, didAdd: room); avisar(room)
    }
    func captureSession(_ session: RoomCaptureSession, didChange room: CapturedRoom) {
        original?.captureSession(session, didChange: room); avisar(room)
    }
    func captureSession(_ session: RoomCaptureSession, didRemove room: CapturedRoom) {
        original?.captureSession(session, didRemove: room)
    }
    func captureSession(_ session: RoomCaptureSession, didProvide instruction: RoomCaptureSession.Instruction) {
        original?.captureSession(session, didProvide: instruction)
        let texto: String?
        switch instruction {
        case .moveCloseToWall: texto = "Acércate un poco a la pared"
        case .moveAwayFromWall: texto = "Aléjate un poco de la pared"
        case .slowDown: texto = "Más despacio"
        case .turnOnLight: texto = "Falta luz: prende la linterna"
        case .lowTexture: texto = "Apunta a algo con más detalle"
        default: texto = nil
        }
        guard let f = alIndicar else { return }
        DispatchQueue.main.async { f(texto) }
    }
    func captureSession(_ session: RoomCaptureSession, didStartWith configuration: RoomCaptureSession.Configuration) {
        original?.captureSession(session, didStartWith: configuration)
    }
    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) {
        original?.captureSession(session, didEndWith: data, error: error)
    }
}

// EMPAREJAR CON LOS CUARTOS DEL PROYECTO (17-oct). Lógica pura (se prueba sola con swiftc).
// Solo emparejamientos claros: igual (sin mayúsculas/acentos, o traducido), o lo dicho cabe
// entero en UN solo cuarto del proyecto ("master" -> "Master Bedroom"). Si cabe en dos, o los
// números no cuadran ("bedroom 2" vs "Bedroom 1"), no se empareja: se queda lo dicho.
struct CuartosDelProyecto {
    static let relleno: Set<String> = ["the", "a", "room", "el", "la", "los", "las", "de", "del", "cuarto", "my", "mi"]
    static func normal(_ s: String) -> String {
        let b = s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
        let solo = b.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined()
        return solo.split(separator: " ").joined(separator: " ")
    }
    static func palabras(_ s: String) -> [String] { normal(s).split(separator: " ").map(String.init) }
    // Palabras de tipo de cuarto: lo que falte decir del nombre del proyecto solo puede ser
    // de estas ("master" -> "Master Bedroom" sí; "bedroom" -> "Master Bedroom" no).
    static let tipos: Set<String> = ["bedroom", "bed", "bathroom", "bath", "closet", "kitchen", "hallway", "hall", "office", "garage", "laundry", "living", "dining", "family", "den", "basement", "attic", "stairs", "entry", "foyer", "pantry", "utility", "storage", "dormitorio", "recamara", "habitacion", "bano", "cocina", "sala", "comedor", "pasillo", "oficina", "lavanderia", "sotano", "garaje", "escalera"]
    static func emparejar(_ dicho: String, con lista: [String], traducir: (String) -> String = { $0 }, usados: [String] = []) -> String? {
        let limpios = lista.filter { !normal($0).isEmpty }
        guard !limpios.isEmpty else { return nil }
        let formas = Array(Set([normal(dicho), normal(traducir(dicho))])).filter { !$0.isEmpty }
        guard !formas.isEmpty else { return nil }
        // 1. Igual.
        let iguales = limpios.filter { c in formas.contains(normal(c)) || formas.contains(normal(traducir(c))) }
        if Set(iguales.map { normal($0) }).count == 1 { return iguales[0] }
        if iguales.count > 1 { return nil }
        // 2. Lo dicho cabe entero en un solo cuarto.
        func cabe(_ forma: String, _ c: String) -> Bool {
            let d = forma.split(separator: " ").map(String.init).filter { !relleno.contains($0) }
            guard !d.isEmpty else { return false }
            let cs = Array(Set(palabras(c) + palabras(traducir(c))))
            let numsD = Set(d.filter { $0.allSatisfy(\.isNumber) })
            let numsC = Set(palabras(c).filter { $0.allSatisfy(\.isNumber) })
            if numsD != numsC { return false }
            let pega: (String, String) -> Bool = { w, x in x == w || (w.count >= 4 && x.hasPrefix(w)) }
            guard d.allSatisfy({ w in cs.contains { pega(w, $0) } }) else { return false }
            // Lo que no se dijo del nombre del proyecto solo puede ser tipo de cuarto o relleno.
            let pc = palabras(c).filter { !relleno.contains($0) }
            return pc.allSatisfy { x in tipos.contains(x) || d.contains { pega($0, x) } }
        }
        let tomados = Set(usados.map { normal($0) })
        let caben = limpios.filter { c in !tomados.contains(normal(c)) && formas.contains { cabe($0, c) } }
        if Set(caben.map { normal($0) }).count == 1 { return caben[0] }
        return nil
    }
    // Los del proyecto que aún no tiene otro cuarto de este escaneo (el activo se queda).
    static func disponibles(proyecto: [String], usados: [String], conservar: String? = nil) -> [String] {
        let tomados = Set(usados.map { normal($0) }).subtracting(conservar.map { [normal($0)] } ?? [])
        return botones(proyecto: proyecto, deSiempre: []).filter { !tomados.contains(normal($0)) }
    }
    // Sugerencias al escribir: el nombre o alguna de sus palabras empieza con lo escrito.
    static func sugerencias(_ escrito: String, en lista: [String]) -> [String] {
        let e = normal(escrito)
        guard !e.isEmpty else { return lista }
        return lista.filter { c in
            let n = normal(c)
            return n.hasPrefix(e) || palabras(c).contains { $0.hasPrefix(e) }
        }
    }
    static func botones(proyecto: [String], deSiempre: [String]) -> [String] {
        var out: [String] = []
        for n in proyecto + deSiempre {
            let t = n.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !out.contains(where: { normal($0) == normal(t) }) { out.append(t) }
        }
        return out
    }
}
