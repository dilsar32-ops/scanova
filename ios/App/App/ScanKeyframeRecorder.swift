import Foundation
import ARKit
import CoreImage
import Metal
import UIKit

// A pure OBSERVER of the scan - records a 2 Hz camera pose trace plus
// thermally-throttled keyframe JPEGs during a RoomPlan capture session.
// It never touches RoomCaptureSession or ARSession state and never
// installs any delegate (RoomPlan owns the ARSessionDelegate); it only
// reads arSession.currentFrame (public API since iOS 16). Every failure
// path degrades to "fewer/no photos, pose trace continues" - the scan
// itself can never be affected because the recorder has no write-path
// into the session.
//
// The pose trace is the coverage signal for ScanInspector and is
// essentially free (~128 B / tick); JPEG encoding is the only expensive
// part and is the FIRST thing shed under thermal pressure - this feature
// must never compete with RoomPlan for headroom on a phone that has
// already shown heat-related camera failures in the field.
final class ScanKeyframeRecorder {

    struct PoseRecord {
        let t: TimeInterval
        let roomIndex: Int
        let level: Int
        let transform: simd_float4x4
        let fx: Float, fy: Float, cx: Float, cy: Float
        let imageW: Int, imageH: Int
        var photoId: String?
    }
    struct KeyframeMeta {
        let id: String
        let file: URL
        let roomIndex: Int
        let level: Int
        let t: TimeInterval
        let w: Int, h: Int
        let bytes: Int
        // La nota de "pared de solo maderas" (0 a 1) que el detector le puso a
        // esta foto EN VIVO, o nil si no se miró (sin modelo, o con calor):
        // entonces se mira después del escaneo, como antes.
        var studScore: Float? = nil
        // A qué le apuntaba el centro de la cámara al tomarla: un punto del
        // mundo, en metros, en el mismo espacio que la geometría. Con eso
        // una foto de maderas se vuelve UN PUNTO EN EL PLANO (donde estaba
        // la pared), no solo una foto.
        var hit: SIMD3<Float>? = nil
    }

    // Se llama en el hilo principal, una vez por cuarto, cuando dos fotos
    // SEGUIDAS del mismo cuarto vieron maderas: la pantalla se lo dice al
    // técnico mientras camina. Nada de esto toca la sesión de RoomPlan.
    var onStudsSeen: ((Int) -> Void)?
    static let umbralStudsEnVivo: Float = 0.7
    // EL SEGUNDO CEREBRO, EN VIVO (13-oct): lo que ARKit sabe y RoomPlan no
    // enseña - si el rastreo está limitado (y por qué) y si el LiDAR está
    // midiendo con poca confianza. Solo lee el cuadro; se llama en main,
    // solo cuando el aviso CAMBIA (nil = ya todo bien).
    var onCalidad: ((String?) -> Void)?
    struct Trace {
        let poses: [PoseRecord]
        let keyframes: [KeyframeMeta]
        let dir: URL
        let maxThermal: ProcessInfo.ThermalState
        let suppressedSecPerRoom: [Int: Double]
        // Camino 2 ("segundo cerebro"): lo que la sonda de la malla vio.
        let meshProbe: [String: Any]
    }

    private let arSessionProvider: () -> ARSession?
    private let queue = DispatchQueue(label: "amg.scan.keyframes", qos: .utility)
    // JPEG encoding lives on its OWN queue so a wedged Metal/CoreImage
    // call (observed in the field on a thermally-stressed phone) can only
    // ever cost photos - the control queue keeps ticking poses and,
    // critically, stays able to run stop()'s completion so the finished
    // plan is never held hostage by a stuck encode.
    private let encodeQueue = DispatchQueue(label: "amg.scan.keyframes.encode", qos: .utility)
    private var encodeInFlight = false // control-queue only; never resets if an encode wedges - photos just stop
    private var timer: DispatchSourceTimer?
    private let ciContext: CIContext
    private let dir: URL
    var sessionDir: URL { dir }

    // Stall forensics, readable from ANY thread (never touches the queues,
    // which may be the very thing that's stuck).
    private let statsLock = NSLock()
    private var lastActivityPhase = "init"
    private var lastActivityAt = Date()
    private func noteActivity(_ phase: String) {
        statsLock.lock()
        lastActivityPhase = phase
        lastActivityAt = Date()
        statsLock.unlock()
    }
    func stallDiagnostic() -> String {
        statsLock.lock()
        defer { statsLock.unlock() }
        return "\(lastActivityPhase) \(Int(Date().timeIntervalSince(lastActivityAt)))s ago"
    }

    // All below touched only on `queue` (kfCounter: encodeQueue only).
    private var poses: [PoseRecord] = []
    private var keyframes: [KeyframeMeta] = []
    private var roomIndex = 0
    private var level = 1
    private var scanning = false
    private var lastPhotoTime: TimeInterval = 0
    private var lastPhotoTransform: simd_float4x4?
    private var photosThisRoom = 0
    private var totalBytes = 0
    private var maxThermal: ProcessInfo.ThermalState = .nominal
    private var suppressedSecPerRoom: [Int: Double] = [:]
    private var backoffMultiplier: Double = 1
    private var hitCriticalThisRoom = false
    private var kfCounter = 0
    // SONDA DE LA MALLA (camino 2). Solo MIRA y CUENTA: cada 5 s, mientras
    // se escanea y sin calor, lee las anclas que ARKit ya trae en el cuadro
    // (malla del LiDAR con su etiqueta por cara, y planos con la suya) para
    // saber si RoomPlan nos deja ver puertas y ventanas por segunda vía.
    // Nunca crea, cambia ni quita nada de la sesión.
    private var meshTicks = 0
    private var calidadUltima: String?
    private var calidadTicks = 0
    private var profundidadBaja: [Int: (suma: Double, n: Int)] = [:]
    private var meshSamples = 0
    private var meshFramesWithMesh = 0
    private var meshMaxAnchors = 0
    private var meshMaxFaces = 0
    private var meshClassified = false
    private var meshDepthSeen = false
    private var meshMaxMs: Double = 0
    private var meshFacesBest: [String: Int] = [:]
    private var meshPlanesBest: [String: Int] = [:]
    private var meshPerRoom: [Int: [String: Int]] = [:]
    static let meshClassNames = ["none", "wall", "floor", "ceiling", "table", "seat", "window", "door"]
    private var rachaStuds = 0                       // fotos seguidas con maderas, en el cuarto actual
    private var rachaCuarto = -1                     // el cuarto al que pertenece la racha
    private var cuartosConAvisoDeStuds = Set<Int>()  // a los que ya se les avisó
    // Leído desde la cola de codificar justo antes de mirar una foto, y
    // escrito desde la de control (update/pause/stop): el detector solo
    // corre mientras se ESTÁ escaneando. Un encode que ya iba en vuelo al
    // decir "listo" no se pone a mirar su foto encima del refinamiento de
    // RoomPlan. Con candado, nunca con un sync entre colas.
    private let permisoLock = NSLock()
    private var _permitirDetector = false
    private var permitirDetector: Bool {
        get { permisoLock.lock(); defer { permisoLock.unlock() }; return _permitirDetector }
        set { permisoLock.lock(); _permitirDetector = newValue; permisoLock.unlock() }
    }

    init(arSessionProvider: @escaping () -> ARSession?) {
        self.arSessionProvider = arSessionProvider
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device)
        } else {
            ciContext = CIContext()
        }
        let tmp = FileManager.default.temporaryDirectory
        // One dir per scan session. Old sessions' dirs are NOT wiped here:
        // the saved plan in the web layer still references the PREVIOUS
        // scan's photos by path, and starting (then perhaps cancelling) a
        // new scan must not kill the photo buttons on the existing plan.
        // Cleanup happens only when a new scan actually REPLACES the plan
        // - see cleanupOldSessions(keeping:).
        dir = tmp.appendingPathComponent("scan-keyframes-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // Called after a new scan's result is delivered (it replaces the saved
    // plan, so only ITS photos are referenced from now on).
    static func cleanupOldSessions(keeping: URL) {
        DispatchQueue.global(qos: .utility).async {
            let tmp = FileManager.default.temporaryDirectory
            guard let entries = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return }
            for url in entries where url.lastPathComponent.hasPrefix("scan-keyframes-")
                && url.lastPathComponent != keeping.lastPathComponent {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self = self, self.timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            self.timer = t
        }
    }

    func update(roomIndex: Int, level: Int, scanning: Bool) {
        queue.async { [weak self] in
            guard let self = self else { return }
            if roomIndex != self.roomIndex {
                self.photosThisRoom = 0
                // Hysteresis: after .critical suppressed photos, resume
                // only at a NEW room start (and only if cool enough) -
                // no mid-room flapping.
                self.hitCriticalThisRoom = false
                self.rachaStuds = 0
            }
            self.roomIndex = roomIndex
            self.level = level
            self.scanning = scanning
            self.permitirDetector = scanning
        }
    }

    // Stops the 2 Hz tick WITHOUT collecting the trace - called the
    // moment the finish/merge step begins. Scanning is over at that
    // point, so there is nothing left worth recording, and continuing to
    // poll arSession.currentFrame while StructureBuilder finalizes the
    // merge is the prime suspect for a field-reported merge hang (the
    // merge worked reliably before this recorder existed). stop() can
    // still be called afterward to collect the trace.
    func pauseTicking() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.permitirDetector = false
        }
    }

    // A copy of the pose trace SO FAR, for the room-boundary scan coach:
    // the just-finished room's walls are projected into these to score
    // how well the camera actually covered it, while the walkthrough
    // continues. Read on the recorder's own queue - never mid-mutation.
    func snapshotPoses(_ completion: @escaping ([PoseRecord]) -> Void) {
        queue.async { [weak self] in
            completion(self?.poses ?? [])
        }
    }

    func stop(_ completion: @escaping (Trace) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.timer?.cancel()
            self.timer = nil
            self.permitirDetector = false
            self.onStudsSeen = nil
            completion(Trace(poses: self.poses, keyframes: self.keyframes, dir: self.dir,
                             maxThermal: self.maxThermal, suppressedSecPerRoom: self.suppressedSecPerRoom,
                             meshProbe: self.meshProbeSummary()))
        }
    }

    func stopAndDeleteAll() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.timer?.cancel()
            self.timer = nil
            // Un resultado que llegue después (una foto que ya se estaba
            // mirando) no puede avisar sobre una pantalla que se cierra.
            self.permitirDetector = false
            self.onStudsSeen = nil
            try? FileManager.default.removeItem(at: self.dir)
            self.poses = []
            self.keyframes = []
        }
    }

    // MARK: - Tick (always on `queue`)

    private func tick() {
        noteActivity("tick.readFrame")
        guard let frame = arSessionProvider()?.currentFrame else { noteActivity("tick.noFrame"); return }
        // Limited/relocalizing poses would poison coverage and their
        // images are blurry - skip the whole tick.
        // El rastreo de ARKit: si está limitado se dice por qué, en español.
        var aviso: String? = nil
        switch frame.camera.trackingState {
        case .limited(.excessiveMotion): aviso = "Más despacio: la cámara se mueve muy rápido"
        case .limited(.insufficientFeatures): aviso = "Apunta a algo con más detalle (o prende la linterna)"
        case .limited(.relocalizing): aviso = "Ubicándose otra vez: regresa la cámara a donde estaba"
        case .limited(.initializing): aviso = nil
        case .notAvailable: aviso = "La cámara perdió su ubicación"
        default: break
        }
        guard case .normal = frame.camera.trackingState else {
            avisarCalidad(aviso)
            noteActivity("tick.limitedTracking")
            return
        }
        // La confianza del LiDAR, cada ~2 s: qué parte de la profundidad viene
        // marcada "baja" por ARKit. Mucha baja = datos poco fiables (vidrio,
        // espejo, muy lejos, muy oscuro). Se guarda por cuarto y se avisa.
        calidadTicks += 1
        if scanning, calidadTicks % 4 == 0 {
            var baja: Double? = nil
            if let conf = frame.sceneDepth?.confidenceMap ?? frame.smoothedSceneDepth?.confidenceMap {
                baja = Self.fraccionBaja(conf)
            }
            if let b = baja {
                let previo = profundidadBaja[roomIndex] ?? (0, 0)
                profundidadBaja[roomIndex] = (previo.suma + b, previo.n + 1)
                aviso = b > 0.5 ? "El LiDAR no ve bien aquí: acércate o ve más despacio" : nil
            }
            avisarCalidad(aviso)
        } else if calidadUltima != nil && calidadUltima!.hasPrefix("Más despacio") || calidadUltima?.hasPrefix("Ubicándose") == true || calidadUltima?.hasPrefix("La cámara perdió") == true {
            // El rastreo ya volvió a la normalidad: se quita su aviso.
            avisarCalidad(nil)
        }

        let thermal = ProcessInfo.processInfo.thermalState
        if thermal.rawValue > maxThermal.rawValue { maxThermal = thermal }

        let cam = frame.camera
        let record = PoseRecord(
            t: frame.timestamp, roomIndex: roomIndex, level: level,
            transform: cam.transform,
            fx: cam.intrinsics[0][0], fy: cam.intrinsics[1][1],
            cx: cam.intrinsics[2][0], cy: cam.intrinsics[2][1],
            imageW: Int(cam.imageResolution.width), imageH: Int(cam.imageResolution.height),
            photoId: nil
        )
        let poseIndex = poses.count
        poses.append(record)

        if scanning && thermal.rawValue < ProcessInfo.ThermalState.serious.rawValue {
            meshTicks += 1
            if meshTicks % 10 == 1 { probeMesh(frame) }
        }

        if !encodeInFlight && shouldKeepPhoto(frame: frame, thermal: thermal) {
            // Bookkeeping updates NOW (optimistically) - if the encode
            // later fails, one photo slot is wasted, which is harmless.
            encodeInFlight = true
            photosThisRoom += 1
            lastPhotoTime = frame.timestamp
            lastPhotoTransform = cam.transform
            // Hand the encode queue a DEEP COPY of the pixel buffer -
            // never the ARFrame or its live buffer. ARKit recycles camera
            // buffers from a small fixed pool; a slow (or wedged) encode
            // holding a live buffer steals one from the pool and degrades
            // tracking. The ~4MB memcpy at most every 1.5s is far cheaper.
            guard let copied = Self.copyPixelBuffer(frame.capturedImage) else {
                encodeInFlight = false
                noteActivity("tick.copyFailed")
                return
            }
            let img = CIImage(cvPixelBuffer: copied)
            let ts = frame.timestamp
            let room = roomIndex
            let lvl = level
            // A qué le apuntaba la cámara, leído del MISMO cuadro que la
            // foto (el LiDAR, o los puntos de rastreo): se resuelve aquí,
            // antes de soltar el cuadro, porque en la cola de codificar ya
            // no existe.
            let hit = Self.centerHit(frame: frame)
            encodeQueue.async { [weak self] in
                guard let self = self else { return }
                self.noteActivity("encode.start")
                let started = Date()
                var meta = self.encodeKeyframe(image: img, timestamp: ts, roomIndex: room, level: lvl, thermal: thermal)
                // Self-backoff: a slow encode is a heat/starvation proxy -
                // permanently widen the interval for the rest of the session.
                let slow = Date().timeIntervalSince(started) > 0.5
                // EL DETECTOR DE MADERAS, EN VIVO. Mira el JPEG recién
                // escrito aquí mismo, en la cola de codificar (nunca en la
                // de control, que tiene que seguir marcando poses). Se
                // vuelve a preguntar AHORA - no en el tick de hace medio
                // segundo - si todavía se está escaneando y cómo va el
                // calor: es lo primero que se apaga. A .serious no se mira
                // nada y la nota se saca después del escaneo, si se puede.
                if let listo = meta, self.permitirDetector, DetectorDeStuds.disponible,
                   ProcessInfo.processInfo.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue {
                    self.noteActivity("studs.start")
                    meta?.studScore = DetectorDeStuds.nota(archivo: listo.file)
                }
                meta?.hit = hit
                self.noteActivity("encode.done")
                self.queue.async {
                    self.encodeInFlight = false
                    if slow { self.backoffMultiplier *= 2 }
                    if let meta = meta {
                        self.keyframes.append(meta)
                        self.totalBytes += meta.bytes
                        if poseIndex < self.poses.count && self.poses[poseIndex].t == ts {
                            self.poses[poseIndex].photoId = meta.id
                        }
                        self.contarMaderas(meta)
                    }
                }
            }
        }
        noteActivity("tick.done")
    }

    private func shouldKeepPhoto(frame: ARFrame, thermal: ProcessInfo.ThermalState) -> Bool {
        // ZERO encodes outside active scanning - never stacked on
        // RoomPlan's own refinement burst, the exact moment the
        // field-reported black-camera failures clustered.
        guard scanning else { return false }
        // Thermal ladder: critical kills photos outright (with per-room
        // hysteresis); the pose trace keeps recording regardless.
        if thermal == .critical { hitCriticalThisRoom = true }
        if hitCriticalThisRoom || thermal == .critical {
            suppressedSecPerRoom[roomIndex, default: 0] += 0.5
            return false
        }
        let minInterval = (thermal == .serious ? 6.0 : 1.5) * backoffMultiplier
        guard frame.timestamp - lastPhotoTime >= minInterval else { return false }
        // Pose novelty: standing still produces zero photos by construction.
        if let last = lastPhotoTransform {
            let dT = simd_distance(SIMD3(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y, frame.camera.transform.columns.3.z),
                                   SIMD3(last.columns.3.x, last.columns.3.y, last.columns.3.z))
            let qa = simd_quatf(simd_float3x3(SIMD3(last.columns.0.x, last.columns.0.y, last.columns.0.z),
                                              SIMD3(last.columns.1.x, last.columns.1.y, last.columns.1.z),
                                              SIMD3(last.columns.2.x, last.columns.2.y, last.columns.2.z)))
            let qb = simd_quatf(simd_float3x3(SIMD3(frame.camera.transform.columns.0.x, frame.camera.transform.columns.0.y, frame.camera.transform.columns.0.z),
                                              SIMD3(frame.camera.transform.columns.1.x, frame.camera.transform.columns.1.y, frame.camera.transform.columns.1.z),
                                              SIMD3(frame.camera.transform.columns.2.x, frame.camera.transform.columns.2.y, frame.camera.transform.columns.2.z)))
            let angle = abs(simd_quatf(from: qa.act(SIMD3(0,0,1)), to: qb.act(SIMD3(0,0,1))).angle) * 180 / .pi
            let minMove: Float = thermal == .serious ? 1.5 : 0.75
            let minTurn: Float = thermal == .serious ? 35 : 20
            if dT < minMove && Float(angle) < minTurn { return false }
        }
        // Hard caps - at the caps, capture stops (cluster-thinning
        // eviction is a later phase).
        guard photosThisRoom < 40, keyframes.count < 300, totalBytes < 70_000_000 else { return false }
        return true
    }

    // Dos fotos SEGUIDAS con maderas en el mismo cuarto = un aviso, una
    // sola vez por cuarto. Una foto sola puede ser una tarima o un
    // estante; dos seguidas mientras camina es una pared. Solo se le dice
    // a la pantalla (en el hilo principal); la pantalla habla. Corre en la
    // cola de control.
    private func contarMaderas(_ meta: KeyframeMeta) {
        // Solo fotos del cuarto que se está escaneando: el resultado tardío
        // de la última foto del cuarto anterior (un encode lento) no puede
        // contar para la racha del cuarto nuevo.
        guard let s = meta.studScore, meta.roomIndex == roomIndex else { return }
        if meta.roomIndex != rachaCuarto { rachaCuarto = meta.roomIndex; rachaStuds = 0 }
        rachaStuds = s >= Self.umbralStudsEnVivo ? rachaStuds + 1 : 0
        guard rachaStuds >= 2, !cuartosConAvisoDeStuds.contains(meta.roomIndex) else { return }
        cuartosConAvisoDeStuds.insert(meta.roomIndex)
        let room = meta.roomIndex
        DispatchQueue.main.async { [weak self] in self?.onStudsSeen?(room) }
    }

    // A QUÉ LE APUNTABA LA CÁMARA: el punto del mundo (metros) que estaba
    // en el centro de la imagen. Primero el LiDAR (el mapa de profundidad
    // del cuadro); si RoomPlan no lo expone en sus cuadros, los puntos de
    // rastreo de ARKit que caen a menos de ~4° del eje óptico. Sin ninguno
    // de los dos, nil: la foto sigue sirviendo, solo no se sabe a qué
    // distancia estaba la pared. SOLO LEE el cuadro; nunca toca la sesión.
    //
    // EN UNA PARED PELADA EL CENTRO CAE EN EL HUECO. Un stud mide 3.8 cm y
    // va cada 40 cm: un parche chico en el centro casi siempre ve la pared
    // del FONDO, no la de maderas. Por eso se mira un parche ancho (31x31
    // píxeles, unos 28 cm a 2 m: casi siempre agarra un stud) y se toma lo
    // MÁS CERCANO que haya en él (el percentil 8, no el mínimo, para no
    // caer en un píxel de ruido): en una pared abierta los studs son lo más
    // cercano; en una pared normal el percentil 8 es la misma pared.
    static let parcheProfundidad = 15   // radio: 31x31
    private func avisarCalidad(_ texto: String?) {
        guard texto != calidadUltima else { return }
        calidadUltima = texto
        guard let f = onCalidad else { return }
        DispatchQueue.main.async { f(texto) }
    }

    // Qué fracción de los pixeles de confianza vienen en "baja" (0).
    static func fraccionBaja(_ mapa: CVPixelBuffer) -> Double? {
        CVPixelBufferLockBaseAddress(mapa, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mapa, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mapa) else { return nil }
        let w = CVPixelBufferGetWidth(mapa), h = CVPixelBufferGetHeight(mapa)
        let bpr = CVPixelBufferGetBytesPerRow(mapa)
        guard w > 0, h > 0 else { return nil }
        var bajos = 0, total = 0
        // Uno de cada 4 en cada dirección basta (256x192 -> ~3000 muestras).
        for y in stride(from: 0, to: h, by: 4) {
            let fila = base.advanced(by: y * bpr).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: 0, to: w, by: 4) {
                if fila[x] == 0 { bajos += 1 }
                total += 1
            }
        }
        return total > 0 ? Double(bajos) / Double(total) : nil
    }

    // Una copia de las fotos tomadas hasta ahora (para que el segundo cerebro
    // mire las que apuntaban a un hueco).
    func snapshotKeyframes(_ completion: @escaping ([KeyframeMeta]) -> Void) {
        queue.async { [weak self] in completion(self?.keyframes ?? []) }
    }

    // MARK: - Sonda de la malla (always on `queue`)

    private func probeMesh(_ frame: ARFrame) {
        let t0 = CACurrentMediaTime()
        meshSamples += 1
        if frame.sceneDepth != nil || frame.smoothedSceneDepth != nil { meshDepthSeen = true }
        var anchors = 0, faces = 0
        var counts = [Int](repeating: 0, count: Self.meshClassNames.count)
        var planes: [String: Int] = [:]
        var budget = 400_000 // caras leídas como máximo por muestra
        for a in frame.anchors {
            if let m = a as? ARMeshAnchor {
                anchors += 1
                let g = m.geometry
                faces += g.faces.count
                if let c = g.classification, budget > 0 {
                    meshClassified = true
                    let n = min(c.count, budget)
                    budget -= n
                    let base = c.buffer.contents().advanced(by: c.offset)
                    for i in 0..<n {
                        let v = Int(base.advanced(by: i * c.stride).assumingMemoryBound(to: UInt8.self).pointee)
                        if v >= 0 && v < counts.count { counts[v] += 1 }
                    }
                }
            } else if let p = a as? ARPlaneAnchor {
                planes[Self.planeName(p.classification), default: 0] += 1
            }
        }
        if anchors > 0 { meshFramesWithMesh += 1 }
        meshMaxAnchors = max(meshMaxAnchors, anchors)
        var dict: [String: Int] = [:]
        for (i, n) in counts.enumerated() where n > 0 { dict[Self.meshClassNames[i]] = n }
        if faces >= meshMaxFaces {
            meshMaxFaces = faces
            meshFacesBest = dict
        }
        if planes.values.reduce(0, +) >= meshPlanesBest.values.reduce(0, +) { meshPlanesBest = planes }
        if !dict.isEmpty { meshPerRoom[roomIndex] = dict }
        meshMaxMs = max(meshMaxMs, (CACurrentMediaTime() - t0) * 1000)
    }

    private static func planeName(_ c: ARPlaneAnchor.Classification) -> String {
        switch c {
        case .wall: return "wall"
        case .floor: return "floor"
        case .ceiling: return "ceiling"
        case .table: return "table"
        case .seat: return "seat"
        case .window: return "window"
        case .door: return "door"
        default: return "none"
        }
    }

    private func meshProbeSummary() -> [String: Any] {
        var perRoom: [String: [String: Int]] = [:]
        for (k, v) in meshPerRoom { perRoom[String(k)] = v }
        return [
            "samples": meshSamples,
            "framesWithMesh": meshFramesWithMesh,
            "maxAnchors": meshMaxAnchors,
            "maxFaces": meshMaxFaces,
            "classified": meshClassified,
            "sceneDepth": meshDepthSeen,
            "faces": meshFacesBest,
            "planes": meshPlanesBest,
            "perRoom": perRoom,
            "maxMs": (meshMaxMs * 10).rounded() / 10,
            "profundidadBajaPorCuarto": Dictionary(uniqueKeysWithValues: profundidadBaja.map {
                (String($0.key), (($0.value.suma / Double(max($0.value.n, 1))) * 100).rounded() / 100)
            })
        ]
    }

    static func centerHit(frame: ARFrame) -> SIMD3<Float>? {
        let t = frame.camera.transform
        let pos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let fwd = simd_normalize(SIMD3<Float>(-t.columns.2.x, -t.columns.2.y, -t.columns.2.z))
        let masCercano = { (vals: [Float]) -> Float in
            let v = vals.sorted()
            return v[min(v.count - 1, Int(Float(v.count) * 0.08))]
        }
        var dist: Float?
        if let depth = frame.sceneDepth?.depthMap ?? frame.smoothedSceneDepth?.depthMap,
           CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32 {
            CVPixelBufferLockBaseAddress(depth, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
            if let base = CVPixelBufferGetBaseAddress(depth) {
                let w = CVPixelBufferGetWidth(depth), h = CVPixelBufferGetHeight(depth)
                let bpr = CVPixelBufferGetBytesPerRow(depth)
                let r = Self.parcheProfundidad
                var vals: [Float] = []
                vals.reserveCapacity((2 * r + 1) * (2 * r + 1))
                for dy in -r...r {
                    for dx in -r...r {
                        let x = w / 2 + dx, y = h / 2 + dy
                        guard x >= 0, y >= 0, x < w, y < h else { continue }
                        let v = base.advanced(by: y * bpr + x * 4).assumingMemoryBound(to: Float32.self).pointee
                        if v.isFinite && v > 0.2 && v < 10 { vals.append(v) }
                    }
                }
                if vals.count >= 50 { dist = masCercano(vals) }
            }
        }
        if dist == nil, let pts = frame.rawFeaturePoints?.points, pts.count >= 10 {
            var alongs: [Float] = []
            for p in pts {
                let v = p - pos
                let along = simd_dot(v, fwd)
                guard along > 0.3, along < 8 else { continue }
                let perp = simd_length(v - fwd * along)
                if perp / along < 0.07 { alongs.append(along) }
            }
            // Mismo criterio: lo más cercano del cono, no la mediana.
            if alongs.count >= 4 { dist = masCercano(alongs) }
        }
        guard let d = dist else { return nil }
        return pos + fwd * d
    }

    // Plane-by-plane deep copy so the camera's own buffer goes straight
    // back to ARKit's pool. Runs on the control queue (before the encode
    // is dispatched).
    private static func copyPixelBuffer(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(src), h = CVPixelBufferGetHeight(src)
        var dstOpt: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, w, h, CVPixelBufferGetPixelFormatType(src), nil, &dstOpt) == kCVReturnSuccess,
              let dst = dstOpt else { return nil }
        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        defer {
            CVPixelBufferUnlockBaseAddress(src, .readOnly)
            CVPixelBufferUnlockBaseAddress(dst, [])
        }
        let copyPlane = { (s: UnsafeMutableRawPointer, d: UnsafeMutableRawPointer, sBPR: Int, dBPR: Int, rows: Int) in
            if sBPR == dBPR {
                memcpy(d, s, rows * sBPR)
            } else {
                let bytes = min(sBPR, dBPR)
                for r in 0..<rows { memcpy(d + r * dBPR, s + r * sBPR, bytes) }
            }
        }
        if CVPixelBufferIsPlanar(src) {
            for p in 0..<CVPixelBufferGetPlaneCount(src) {
                guard let s = CVPixelBufferGetBaseAddressOfPlane(src, p),
                      let d = CVPixelBufferGetBaseAddressOfPlane(dst, p) else { return nil }
                copyPlane(s, d, CVPixelBufferGetBytesPerRowOfPlane(src, p),
                          CVPixelBufferGetBytesPerRowOfPlane(dst, p),
                          CVPixelBufferGetHeightOfPlane(src, p))
            }
        } else {
            guard let s = CVPixelBufferGetBaseAddress(src),
                  let d = CVPixelBufferGetBaseAddress(dst) else { return nil }
            copyPlane(s, d, CVPixelBufferGetBytesPerRow(src), CVPixelBufferGetBytesPerRow(dst), h)
        }
        return dst
    }

    // Runs on encodeQueue ONLY. kfCounter is effectively encode-queue
    // state: encodeInFlight guarantees a single encode at a time.
    private func encodeKeyframe(image: CIImage, timestamp: TimeInterval, roomIndex: Int, level: Int,
                                thermal: ProcessInfo.ThermalState) -> KeyframeMeta? {
        let longEdge: CGFloat = thermal == .serious ? 640 : 1280
        // The sensor image is landscape; the tech scans in portrait -
        // bake the upright orientation in now so the web layer never
        // does image math.
        var img = image.oriented(.right)
        let scale = longEdge / max(img.extent.width, img.extent.height)
        if scale < 1 { img = img.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let data = ciContext.jpegRepresentation(of: img, colorSpace: srgb,
                    options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: thermal == .serious ? 0.5 : 0.6])
        else { return nil }
        kfCounter += 1
        let id = String(format: "kf-%04d", kfCounter)
        let url = dir.appendingPathComponent("\(id).jpg")
        do { try data.write(to: url) } catch { return nil }
        return KeyframeMeta(id: id, file: url, roomIndex: roomIndex, level: level,
                            t: timestamp,
                            w: Int(img.extent.width.rounded()), h: Int(img.extent.height.rounded()),
                            bytes: data.count)
    }
}
