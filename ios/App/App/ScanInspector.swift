import Foundation
import RoomPlan
import simd

// The frame-based half of the post-scan verification pipeline: given the
// captured rooms and the pose trace ScanKeyframeRecorder collected,
// compute per-element VISUAL COVERAGE - which walls/doors/windows/
// openings the camera actually got a good look at during the walkthrough.
// This is pure geometry over the pose trace (no image is ever decoded -
// cost is independent of photo count).
//
// CORRECCIÓN (14-oct): antes aquí decía que todo vivía en UN solo espacio
// de ARKit. No es cierto: cada captura de RoomPlan (cada run()) arranca con
// su propio origen, y la caminata de cada cuarto viene en el marco de SU
// captura. Por eso la geometría y las poses se pasan primero al plano
// entregado con el movimiento de cada captura (inspect: marcoCuarto y
// capturas); lo que no se sabe dónde va, no entra.
//
// HONESTY RULE (structural, enforced by the web verdict model): coverage
// can only DOWNGRADE an element - trigger a question or a report note -
// never upgrade one. The occlusion test knows only RoomPlan-modeled
// walls; unmodeled occluders (people, boxes, furniture) can make
// "observed" a false positive. Low coverage is reliable ("nobody pointed
// the camera there"); high coverage is opportunity-to-observe, not proof.
enum ScanInspector {

    // Room-boundary scan coach: a fast coverage score for the room that
    // JUST finished, computed from that room's own poses while the
    // walkthrough continues. Deliberately lighter than inspect() - no
    // occlusion casting, surface corner+center samples only. This is a
    // coaching hint spoken in the moment; the full inspect() at session
    // end remains the verification that ships with the plan.
    static func quickRoomCoverage(room: CapturedRoom, captura: Int,
                                  poses: [ScanKeyframeRecorder.PoseRecord])
        -> (percent: Int, total: Int, wellSeen: Int, worstType: String?, worstLengthFt: Double?) {
        struct El { let normal: SIMD3<Float>; let samples: [SIMD3<Float>]; let type: String; let lengthFt: Double }
        var elements: [El] = []
        func addSurface(_ s: CapturedRoom.Surface, _ type: String) {
            let T = s.transform
            let hw = s.dimensions.x / 2 * 0.9, hh = s.dimensions.y / 2 * 0.9
            var pts: [SIMD3<Float>] = []
            for (lx, ly) in [(Float(0), Float(0)), (-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)] {
                let w = T * SIMD4<Float>(lx, ly, 0, 1)
                pts.append(SIMD3(w.x, w.y, w.z))
            }
            let n = SIMD3(T.columns.2.x, T.columns.2.y, T.columns.2.z)
            elements.append(El(normal: simd_normalize(n), samples: pts, type: type,
                               lengthFt: Double(s.dimensions.x) * FloorPlanEncoder.metersToFeet))
        }
        room.walls.forEach { addSurface($0, "pared") }
        room.doors.forEach { addSurface($0, "puerta") }
        room.windows.forEach { addSurface($0, "ventana") }
        // Passages were missing from the coach's denominator entirely, so
        // a doorless opening the camera never saw was invisible to it
        // while the printed verdict counted it. inspect() has always
        // included them.
        room.openings.forEach { addSurface($0, "paso") }
        guard !elements.isEmpty else { return (100, 0, 0, nil, nil) }
        struct Cam { let inv: simd_float4x4; let pos: SIMD3<Float> }
        // Solo las poses de la captura de este cuarto: cada captura de
        // RoomPlan tiene su propio origen, y una pose de otra captura está en
        // otro marco (antes se filtraba por el número de cuarto, que una
        // captura descartada reusa).
        let own = poses.filter { $0.captura == captura }
        let cams = own.map {
            Cam(inv: $0.transform.inverse,
                pos: SIMD3($0.transform.columns.3.x, $0.transform.columns.3.y, $0.transform.columns.3.z))
        }
        var well = 0
        var worst: (frac: Float, type: String, lengthFt: Double)?
        for el in elements {
            var seen = [Int](repeating: 0, count: el.samples.count)
            for (pi, pose) in own.enumerated() {
                let cam = cams[pi]
                for (si, sample) in el.samples.enumerated() {
                    let pc = cam.inv * SIMD4<Float>(sample.x, sample.y, sample.z, 1)
                    let d = -pc.z
                    guard d > 0.3, d < 4.0 else { continue }
                    let u = pose.fx * (pc.x / d) + pose.cx
                    let v = pose.cy - pose.fy * (pc.y / d)
                    let W = Float(pose.imageW), H = Float(pose.imageH)
                    guard u > W * 0.05, u < W * 0.95, v > H * 0.05, v < H * 0.95 else { continue }
                    let ray = simd_normalize(sample - cam.pos)
                    guard abs(simd_dot(ray, el.normal)) > 0.342 else { continue }
                    seen[si] += 1
                }
            }
            let seenCount = seen.filter { $0 >= 2 }.count
            let frac = Float(seenCount) / Float(el.samples.count)
            // Same bar the DOCUMENT prints (coverage >= 0.8), not a
            // looser one. With 0.6 the card told him "64%" for a room the
            // report then called 27% - the number he saw in the field and
            // the number the adjuster reads have to be the same number.
            if frac >= 0.8 { well += 1 }
            if worst == nil || frac < worst!.frac { worst = (frac, el.type, el.lengthFt) }
        }
        let pct = Int((Float(well) / Float(elements.count) * 100).rounded())
        let bad = (worst?.frac ?? 1) < 0.2
        return (pct, elements.count, well, bad ? worst?.type : nil, bad ? worst?.lengthFt : nil)
    }

    // El rastro de la camara, adelgazado: una muestra cada medio pie como
    // minimo, con tope duro por si un escaneo largo produce miles. Se
    // guarda por cuarto y por nivel para poder preguntar "¿entro a este
    // cuarto?" y "¿camino por este hueco?".
    // UNA PUERTA QUE UN CUARTO MODELO Y EL VECINO NO.
    //
    // Una puerta vive en UNA pared, y esa pared la comparten dos cuartos.
    // Si un cuarto la modelo y el otro no, el plano que se entrega tiene
    // la puerta de un lado y pared ciega del otro. Pasa en la casa real:
    // el Hallway modelo una puerta de 3.19 ft que cae a 0.0141 ft - 0.17
    // PULGADAS - de la pared de 7.71 ft del Living Room, en medio del
    // segmento. Misma particion fisica; el Living Room no la dibujo.
    //
    // No usa nada de Apple mas alla de la geometria que ya esta en la
    // mano, no toca poses, no toca la sesion, y corre en microsegundos
    // sobre un puñado de cuartos. Se llama al terminar CADA cuarto, para
    // que el tecnico se entere estando todavia en la casa.
    //
    // Los cuatro numeros estan medidos contra los dos escaneos reales
    // guardados: emparejar a 1.0 ft, ancho minimo 1.5 ft, distancia a la
    // pared 0.5 ft, y t entre 0.05 y 0.95 (dentro del segmento, no en la
    // punta: toda esquina tiene paredes ajenas cerca). Con esas rejas:
    // 1 acierto, 0 falsos, en los dos escaneos. El siguiente puerto suelto
    // esta a 2.34 ft, o sea 166 veces mas lejos: no es un umbral delicado.
    struct MirroredPort {
        let portId: UUID
        let isDoor: Bool
        let widthFt: Double
        let ownerRoomIndex: Int
        let otherRoomIndex: Int
        let distFt: Double
    }

    static func mirroredPortCheck(rooms: [CapturedRoom],
                                  deletedIndices: Set<Int>,
                                  levels: [Int],
                                  alreadyReported: Set<UUID>) -> [MirroredPort] {
        let f = FloorPlanEncoder.metersToFeet
        struct Port { let id: UUID; let isDoor: Bool; let w: Double
                      let x: Double; let y: Double; let room: Int; let level: Int }
        var ports: [Port] = []
        for (ri, room) in rooms.enumerated() {
            // Un cuarto que el tecnico rechazo con "Repetir este cuarto"
            // sigue dentro de capturedRooms - sin este filtro cada repeticion
            // deja puertas fantasma acusando a los cuartos buenos.
            if deletedIndices.contains(ri) { continue }
            let lvl = levels.indices.contains(ri) ? levels[ri] : 1
            for s in room.doors + room.openings {
                let t = s.transform
                ports.append(Port(id: s.identifier,
                                  isDoor: room.doors.contains { $0.identifier == s.identifier },
                                  w: Double(s.dimensions.x) * f,
                                  x: Double(t.columns.3.x) * f, y: Double(t.columns.3.z) * f,
                                  room: ri, level: lvl))
            }
        }
        // El MISMO objeto visto desde los dos lados queda resuelto.
        var paired = Set<Int>()
        for i in ports.indices { for j in ports.indices where j > i {
            if ports[i].room == ports[j].room || ports[i].level != ports[j].level { continue }
            if hypot(ports[i].x - ports[j].x, ports[i].y - ports[j].y) <= 1.0 {
                paired.insert(i); paired.insert(j)
            }
        }}
        var out: [MirroredPort] = []
        for (i, pt) in ports.enumerated() {
            if paired.contains(i) { continue }
            if alreadyReported.contains(pt.id) { continue }   // una vez por sesion
            if pt.w < 1.5 { continue }                        // ruido de media pulgada
            var best: (d: Double, rj: Int)? = nil
            for (rj, other) in rooms.enumerated() {
                if rj == pt.room || deletedIndices.contains(rj) { continue }
                let lvl = levels.indices.contains(rj) ? levels[rj] : 1
                if lvl != pt.level { continue }
                for w in other.walls {
                    let (s0, e0) = FloorPlanEncoder.wallEndpoints(w)
                    let ax = Double(s0.x) * f, ay = Double(s0.y) * f
                    let bx = Double(e0.x) * f, by = Double(e0.y) * f
                    let dx = bx - ax, dy = by - ay, L2 = dx*dx + dy*dy
                    if L2 < 1e-6 { continue }
                    let t = ((pt.x - ax)*dx + (pt.y - ay)*dy) / L2
                    if t < 0.05 || t > 0.95 { continue }
                    let d = hypot(pt.x - (ax + dx*t), pt.y - (ay + dy*t))
                    if d > 0.5 { continue }
                    if best == nil || d < best!.d { best = (d, rj) }
                }
            }
            if let b = best {
                out.append(MirroredPort(portId: pt.id, isDoor: pt.isDoor, widthFt: pt.w,
                                        ownerRoomIndex: pt.room, otherRoomIndex: b.rj, distFt: b.d))
            }
        }
        return out
    }

    // Las fotos, los elementos y el camino se etiquetaron con el índice
    // PRE-merge (capturedRooms, que solo crece); el plano entregado es
    // structure.rooms + los rechazados, en OTRO orden si hubo un "repetir"
    // en medio. Se traduce cada índice con el mapa pre → entregado; un
    // índice sin traducción se queda como está.
    static func remapRoomIndices(_ insp: [String: Any]?, mapa: [Int: Int]) -> [String: Any]? {
        guard var d = insp, mapa.contains(where: { $0.key != $0.value }) else { return insp }
        let f: (Any?) -> Any? = { v in
            if let n = v as? Int, let m = mapa[n] { return m }
            return v
        }
        if let kfs = d["keyframes"] as? [[String: Any]] {
            d["keyframes"] = kfs.map { var k = $0; k["roomIndex"] = f(k["roomIndex"]); return k }
        }
        if let els = d["elements"] as? [[String: Any]] {
            d["elements"] = els.map { var e = $0; e["roomIndex"] = f(e["roomIndex"]); return e }
        }
        if let path = d["path"] as? [[String: Any]] {
            d["path"] = path.map { var p = $0; p["r"] = f(p["r"]); return p }
        }
        return d
    }

    // Las poses ya llegan en el plano entregado (o en su cuarto, si no se
    // juntó), con el cuarto al que pertenecen; las de una captura que no se
    // sabe dónde va ni siquiera llegan.
    static func pathTrace(_ poses: [(x: Float, y: Float, cuarto: Int, nivel: Int)]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        var lastX = Float.infinity, lastY = Float.infinity
        var lastRoom = -999
        for p in poses {
            let x = p.x, y = p.y
            if p.cuarto == lastRoom, hypot(x - lastX, y - lastY) < 0.15 { continue }  // ~0.5 ft
            lastX = x; lastY = y; lastRoom = p.cuarto
            out.append([
                "x": (Double(x) * FloorPlanEncoder.metersToFeet * 100).rounded() / 100,
                "y": (Double(y) * FloorPlanEncoder.metersToFeet * 100).rounded() / 100,
                "r": p.cuarto, "l": p.nivel
            ])
            if out.count >= 1200 { break }
        }
        return out
    }

    // El movimiento en el piso como matriz 3D: girar en el piso (x, z),
    // mover, y subir o bajar `dy` (para poner el piso de cada captura en 0).
    static func matriz(_ r: FloorPlanEncoder.Rigido2D, dy: Float) -> simd_float4x4 {
        let c = Float(cos(r.th)), s = Float(sin(r.th))
        return simd_float4x4(columns: (SIMD4(c, 0, s, 0), SIMD4(0, 1, 0, 0), SIMD4(-s, 0, c, 0),
                                       SIMD4(Float(r.tx), dy, Float(r.ty), 1)))
    }

    // La altura del piso en el marco de un cuarto: donde terminan sus
    // paredes por abajo (la mediana, por si una pared viene rara).
    static func alturaDelPiso(_ room: CapturedRoom) -> Float {
        let bajos = room.walls.map { $0.transform.columns.3.y - $0.dimensions.y / 2 }.sorted()
        return bajos.isEmpty ? 0 : bajos[bajos.count / 2]
    }

    // Una captura: de qué cuarto es (el suyo, que da la altura del piso), a
    // qué cuarto del plano pertenece (un parche, al de su cuarto) y cómo se
    // lleva al plano entregado.
    struct MarcoDeCaptura { let propio: Int; let grupo: Int; let marco: FloorPlanEncoder.Rigido2D }

    // LOS MARCOS (14-oct). Cada captura de RoomPlan arranca con su propio
    // origen, así que la geometría de cada cuarto y las poses de cada captura
    // se pasan primero al plano entregado (`marcoCuarto`, `capturas`). Un
    // cuarto o una captura sin movimiento conocido no entra. Si el plano NO se
    // juntó (`juntado` false), cada cuarto se revisa solo, con las poses de su
    // propia captura: comparar entre cuartos sin merge no significa nada.
    static func inspect(rooms: [CapturedRoom], deletedIndices: Set<Int>, levels: [Int],
                        trace: ScanKeyframeRecorder.Trace,
                        marcoCuarto: [Int: FloorPlanEncoder.Rigido2D],
                        capturas: [Int: MarcoDeCaptura],
                        juntado: Bool,
                        cuartoDeCaptura: [Int: Int] = [:],
                        isCancelled: () -> Bool = { false }) -> [String: Any] {
        guard !trace.poses.isEmpty else { return ["version": 1, "status": "skipped", "reason": "no_poses"] }
        let pisoDe: [Int: Float] = Dictionary(uniqueKeysWithValues: rooms.indices.map { ($0, alturaDelPiso(rooms[$0])) })
        let M: [Int: simd_float4x4] = marcoCuarto.reduce(into: [:]) { acc, kv in acc[kv.key] = matriz(kv.value, dy: -(pisoDe[kv.key] ?? 0)) }
        func aPlano(_ m: simd_float4x4, _ p: SIMD3<Float>) -> SIMD3<Float> { let q = m * SIMD4(p.x, p.y, p.z, 1); return SIMD3(q.x, q.y, q.z) }
        func aPlano2(_ m: simd_float4x4, _ p: SIMD2<Float>) -> SIMD2<Float> { let q = m * SIMD4(p.x, 0, p.y, 1); return SIMD2(q.x, q.z) }
        func giro(_ m: simd_float4x4, _ n: SIMD3<Float>) -> SIMD3<Float> { let q = m * SIMD4(n.x, n.y, n.z, 0); return SIMD3(q.x, q.y, q.z) }
        // Cada pose, ya en el plano, con el cuarto al que pertenece.
        struct PoseEnPlano { let rec: ScanKeyframeRecorder.PoseRecord; let t: simd_float4x4; let cuarto: Int }
        let posesEnPlano: [PoseEnPlano] = trace.poses.compactMap { p in
            guard let c = capturas[p.captura] else { return nil }
            let m = matriz(c.marco, dy: -(pisoDe[c.propio] ?? 0))
            return PoseEnPlano(rec: p, t: m * p.transform, cuarto: c.grupo)
        }
        // Sin ninguna pose ubicada no hay cobertura ni camino, pero las fotos
        // SÍ se mandan (sin posición): antes se perdían todas.
        let sinUbicar = posesEnPlano.isEmpty

        // --- Occluder set: every non-deleted wall as a 2D XZ segment,
        // with the door/opening spans that allow seeing through it. ---
        struct Occluder {
            let a: SIMD2<Float>, b: SIMD2<Float>
            let level: Int
            let room: Int
            let wallId: UUID
            let passSpans: [(center: SIMD2<Float>, halfWidth: Float)]
        }
        var occluders: [Occluder] = []
        for (idx, room) in rooms.enumerated() {
            guard !deletedIndices.contains(idx), let m = M[idx] else { continue }
            let lvl = levels.indices.contains(idx) ? levels[idx] : 1
            for wall in room.walls {
                let (s0, e0) = FloorPlanEncoder.wallEndpoints(wall)
                let s = aPlano2(m, s0), e = aPlano2(m, e0)
                var spans: [(SIMD2<Float>, Float)] = []
                // Windows included: without them, a window plane modeled a
                // few cm behind its wall centerline is "blocked" by its own
                // host wall and falsely reads as never-observed.
                for opening in room.doors + room.openings + room.windows {
                    let p = aPlano2(m, SIMD2<Float>(opening.transform.columns.3.x, opening.transform.columns.3.z))
                    // An opening belongs to this wall if it sits on its line.
                    let ab = e - s
                    let len2 = simd_length_squared(ab)
                    guard len2 > 0.0001 else { continue }
                    let t = simd_dot(p - s, ab) / len2
                    guard t > -0.1, t < 1.1 else { continue }
                    let proj = s + ab * max(0, min(1, t))
                    guard simd_distance(p, proj) < 0.3 else { continue }
                    spans.append((p, opening.dimensions.x / 2 + 0.15))
                }
                occluders.append(Occluder(a: s, b: e, level: lvl, room: idx, wallId: wall.identifier, passSpans: spans))
            }
        }

        func segmentsIntersect(_ p1: SIMD2<Float>, _ p2: SIMD2<Float>, _ p3: SIMD2<Float>, _ p4: SIMD2<Float>) -> SIMD2<Float>? {
            let d1 = p2 - p1, d2 = p4 - p3
            let denom = d1.x * d2.y - d1.y * d2.x
            guard abs(denom) > 1e-6 else { return nil }
            let t = ((p3.x - p1.x) * d2.y - (p3.y - p1.y) * d2.x) / denom
            let u = ((p3.x - p1.x) * d1.y - (p3.y - p1.y) * d1.x) / denom
            guard t > 0.02, t < 0.98, u > 0.0, u < 1.0 else { return nil }
            return p1 + d1 * t
        }

        // --- Elements: every surface FloorPlanEncoder encodes, with 3D
        // sample points and an outward normal. ---
        struct Element {
            let id: String
            let type: String
            let roomIndex: Int
            let level: Int
            let center: SIMD3<Float>
            let normal: SIMD3<Float>
            let samples: [SIMD3<Float>]
            let ownWallId: UUID?
        }
        var elements: [Element] = []
        for (idx, room) in rooms.enumerated() {
            guard !deletedIndices.contains(idx), let m = M[idx] else { continue }
            let lvl = levels.indices.contains(idx) ? levels[idx] : 1
            for wall in room.walls {
                let (s2, e2) = FloorPlanEncoder.wallEndpoints(wall)
                let y = wall.transform.columns.3.y
                var pts: [SIMD3<Float>] = []
                for t in [Float(0), 0.25, 0.5, 0.75, 1] {
                    let p = s2 + (e2 - s2) * t
                    pts.append(aPlano(m, SIMD3(p.x, y, p.y)))
                }
                let n = giro(m, SIMD3(wall.transform.columns.2.x, wall.transform.columns.2.y, wall.transform.columns.2.z))
                elements.append(Element(id: wall.identifier.uuidString, type: "wall", roomIndex: idx, level: lvl,
                                        center: pts[2], normal: simd_normalize(n), samples: pts, ownWallId: wall.identifier))
            }
            func rectElement(_ surface: CapturedRoom.Surface, _ type: String) {
                let T = m * surface.transform
                let hw = surface.dimensions.x / 2 * 0.9, hh = surface.dimensions.y / 2 * 0.9
                var pts: [SIMD3<Float>] = []
                for (lx, ly) in [(Float(0),Float(0)), (-hw,-hh), (hw,-hh), (hw,hh), (-hw,hh)] {
                    let world = T * SIMD4<Float>(lx, ly, 0, 1)
                    pts.append(SIMD3(world.x, world.y, world.z))
                }
                let n = SIMD3(T.columns.2.x, T.columns.2.y, T.columns.2.z)
                elements.append(Element(id: surface.identifier.uuidString, type: type, roomIndex: idx, level: lvl,
                                        center: pts[0], normal: simd_normalize(n), samples: pts, ownWallId: nil))
            }
            room.doors.forEach { rectElement($0, "door") }
            room.windows.forEach { rectElement($0, "window") }
            room.openings.forEach { rectElement($0, "opening") }
        }

        // --- Coverage: project every sample into every pose's camera. ---
        let metersToFeet = FloorPlanEncoder.metersToFeet
        var results: [[String: Any]] = []
        let keyframesById = Dictionary(uniqueKeysWithValues: trace.keyframes.map { ($0.id, $0) })

        // Per-pose camera data hoisted out of the element loop - computing
        // transform.inverse per element x pose was ~(element count)x
        // redundant work and the main risk to the caller's 5s budget.
        struct PoseCam {
            let inv: simd_float4x4
            let camPos: SIMD3<Float>
        }
        let poseCams: [PoseCam] = posesEnPlano.map {
            PoseCam(inv: $0.t.inverse,
                    camPos: SIMD3($0.t.columns.3.x, $0.t.columns.3.y, $0.t.columns.3.z))
        }

        for el in elements where !sinUbicar {
            // The caller's watchdog may have already shipped the plan
            // without us - stop burning a hot phone's CPU on a result
            // nobody will read.
            if isCancelled() { return ["version": 1, "status": "skipped", "reason": "cancelled"] }
            var perSampleSeen = [Int](repeating: 0, count: el.samples.count)
            var viewRecords = 0, photoViews = 0
            var minDist: Float = .greatestFiniteMagnitude
            var bestScore: Float = -1
            var bestKeyframe: String?

            for (pi, pp) in posesEnPlano.enumerated() {
                let pose = pp.rec
                guard pose.level == el.level else { continue }
                let camPos = poseCams[pi].camPos
                let toElement = simd_distance(SIMD2(camPos.x, camPos.z), SIMD2(el.center.x, el.center.z))
                // A pose counts toward its own room's elements plus
                // anything within 6 m (open-plan sharing) - a pose in
                // the kitchen never "observes" a distant bedroom. Sin plano
                // juntado, solo las de su propio cuarto.
                guard pp.cuarto == el.roomIndex || (juntado && toElement < 6) else { continue }
                let inv = poseCams[pi].inv
                var seenHere = 0
                var sumIncidence: Float = 0
                var centerU: Float = -1, centerV: Float = -1, centerDepth: Float = -1
                for (si, sample) in el.samples.enumerated() {
                    let pc4 = inv * SIMD4<Float>(sample.x, sample.y, sample.z, 1)
                    let d = -pc4.z
                    guard d > 0.3, d < 6.0 else { continue }
                    let u = pose.fx * (pc4.x / d) + pose.cx
                    let v = pose.cy - pose.fy * (pc4.y / d)
                    let W = Float(pose.imageW), H = Float(pose.imageH)
                    guard u > W*0.05, u < W*0.95, v > H*0.05, v < H*0.95 else { continue }
                    // Incidence: a grazing sweep down a hallway did not
                    // observe a side wall.
                    let ray = simd_normalize(sample - camPos)
                    let cosInc = abs(simd_dot(ray, el.normal))
                    guard cosInc > 0.342 else { continue } // < 70 degrees
                    // 2D occlusion against modeled walls, seeing through
                    // doorway spans allowed.
                    let a2 = SIMD2(camPos.x, camPos.z), b2 = SIMD2(sample.x, sample.z)
                    var blocked = false
                    for occ in occluders {
                        guard occ.level == el.level, occ.wallId != el.ownWallId, juntado || occ.room == el.roomIndex else { continue }
                        if let hit = segmentsIntersect(a2, b2, occ.a, occ.b) {
                            let throughDoor = occ.passSpans.contains { simd_distance(hit, $0.center) <= $0.halfWidth }
                            if !throughDoor { blocked = true; break }
                        }
                    }
                    guard !blocked else { continue }
                    if d < 4.0 { perSampleSeen[si] += 1 }
                    seenHere += 1
                    sumIncidence += cosInc
                    minDist = min(minDist, d)
                    // Center sample: walls sample their midpoint at index 2,
                    // rect elements their center at index 0.
                    let centerIdx = el.type == "wall" ? 2 : 0
                    if si == centerIdx { centerU = u; centerV = v; centerDepth = d }
                }
                if seenHere > 0 {
                    viewRecords += 1
                    if let photoId = pose.photoId {
                        photoViews += 1
                        // Best keyframe: element center inside the
                        // central 80%, comfortable distance band.
                        if centerDepth > 0.6, centerDepth < 7,
                           centerU > Float(pose.imageW)/10, centerU < Float(pose.imageW)*9/10,
                           centerV > Float(pose.imageH)/10, centerV < Float(pose.imageH)*9/10 {
                            let meanInc = sumIncidence / Float(seenHere)
                            let band: Float
                            if centerDepth >= 1.0 && centerDepth <= 3.5 { band = 1.0 }
                            else if centerDepth < 1.0 { band = max(0.3, 0.3 + 0.7*(centerDepth-0.6)/0.4) }
                            else { band = max(0.3, 1.0 - 0.7*(centerDepth-3.5)/3.5) }
                            let score = Float(seenHere) * meanInc * band
                            if score > bestScore, keyframesById[photoId] != nil {
                                bestScore = score
                                bestKeyframe = photoId
                            }
                        }
                    }
                }
            }

            let observedSamples = perSampleSeen.filter { $0 >= 2 }.count
            let coverage = Double(observedSamples) / Double(max(el.samples.count, 1))
            let observed: String
            if coverage >= 0.8 && viewRecords >= 3 { observed = "well" }
            else if coverage < 0.4 || viewRecords <= 1 { observed = "poor" }
            else { observed = "partial" }

            var entry: [String: Any] = [
                "id": el.id, "type": el.type, "roomIndex": el.roomIndex,
                "coverage": (coverage * 100).rounded() / 100,
                "views": viewRecords, "photoViews": photoViews,
                "observed": observed
            ]
            if minDist < .greatestFiniteMagnitude { entry["minDistFt"] = (Double(minDist) * metersToFeet * 10).rounded() / 10 }
            if let bk = bestKeyframe { entry["bestKeyframe"] = bk }
            results.append(entry)
        }

        // La NOTA DE STUDS de cada foto (DetectorDeStuds, si el modelo viene en
        // el paquete) y la POSE de la cámara al tomarla, en pies y en el mismo
        // espacio que la geometría: x, z y hacia dónde miraba (yaw). Con eso
        // la web puede enseñar la foto y saber qué tramo del plano miraba.
        // Las fotos que el escaneo ya miró EN VIVO traen su nota; las demás
        // se miran ahora - pero NO en un teléfono caliente (las fotos sin
        // nota son justamente las de cuando hubo calor), y nunca más de
        // 1.5 s: esta inspección entera vive bajo un vigilante de 5 s y
        // perderla por unas notas de maderas costaría la cobertura, el
        // camino y los botones de foto de todo el plano.
        let caliente = trace.maxThermal.rawValue >= ProcessInfo.ThermalState.serious.rawValue
            || ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        let limiteNotas = Date().addingTimeInterval(1.5)
        let notasStuds = caliente ? [:] : DetectorDeStuds.notas(
            fotos: trace.keyframes.filter { $0.studScore == nil }.map { (id: $0.id, archivo: $0.file) },
            isCancelled: { isCancelled() || Date() > limiteNotas })
        var poseDeFoto: [String: simd_float4x4] = [:]
        for p in posesEnPlano { if let id = p.rec.photoId { poseDeFoto[id] = p.t } }
        let kfDicts: [[String: Any]] = trace.keyframes.map {
            // La foto se queda aunque su captura no se sepa dónde va; solo
            // pierde la posición (no se inventa).
            let cap = capturas[$0.captura]
            var d: [String: Any] = ["id": $0.id, "file": $0.file.path, "level": $0.level, "w": $0.w, "h": $0.h]
            // El cuarto de la foto es el de SU captura (aunque ese cuarto no vaya
            // en el plano). Una foto de una captura que no dio cuarto (se
            // descartó) no lleva cuarto: antes heredaba el número del siguiente.
            if let g = cap?.grupo ?? cuartoDeCaptura[$0.captura] { d["roomIndex"] = g }
            if let n = $0.studScore ?? notasStuds[$0.id] { d["studScore"] = Double(n) }
            if let t = poseDeFoto[$0.id] {
                let c = t.columns
                // La cámara mira por -Z de su propio marco.
                let fwd = SIMD3<Float>(-c.2.x, -c.2.y, -c.2.z)
                d["x"] = Double(c.3.x) * 3.28084
                d["z"] = Double(c.3.z) * 3.28084
                d["yaw"] = Double(atan2(fwd.x, fwd.z))
            }
            // A qué le apuntaba la cámara, en pies y en las coordenadas del
            // plano (x, y = z del mundo, igual que las paredes del encoder):
            // el punto donde estaba lo que salió en la foto.
            if let h0 = $0.hit, let c = cap {
                let h = aPlano(matriz(c.marco, dy: -(pisoDe[c.propio] ?? 0)), SIMD3(h0.x, h0.y, h0.z))
                d["hitX"] = (Double(h.x) * 3.28084 * 100).rounded() / 100
                d["hitY"] = (Double(h.z) * 3.28084 * 100).rounded() / 100
            }
            return d
        }
        let thermalName: String
        switch trace.maxThermal {
        case .critical: thermalName = "critical"
        case .serious: thermalName = "serious"
        case .fair: thermalName = "fair"
        default: thermalName = "nominal"
        }
        var salida: [String: Any] = [
            "version": 1,
            "status": sinUbicar ? "skipped" : (trace.keyframes.isEmpty ? "no_photos" : "ok"),
            "sessionDir": trace.dir.path,
            "poseSamples": trace.poses.count,
            // NUESTRA propia medida, no la de Apple: por donde el tecnico
            // camino de verdad, en el MISMO espacio que la geometria.
            // 500 posiciones se calculaban y se tiraban; solo viajaba el
            // numero. Con el camino, el plano puede CONTRADECIR a la
            // geometria - un hueco por el que alguien camino es una
            // puerta, no una pared que falta, y una pared que el camino
            // atraviesa no puede existir. Se manda en pies, 2D, sin
            // muestras a menos de medio pie una de otra (unos pocos KB).
            "path": pathTrace(posesEnPlano.map { (x: $0.t.columns.3.x, y: $0.t.columns.3.z, cuarto: $0.cuarto, nivel: $0.rec.level) }),
            // En qué coordenadas viene todo lo de arriba: "plano" = el plano
            // entregado ya juntado; "cuarto" = cada cuarto en el suyo (sin
            // merge). Antes venía en el marco de cada captura, revuelto.
            "frame": juntado ? "plano" : "cuarto",
            "thermal": ["maxState": thermalName,
                        "photosSuppressedSec": Dictionary(uniqueKeysWithValues: trace.suppressedSecPerRoom.map { (String($0.key), $0.value) })],
            "keyframes": kfDicts,
            "elements": results
        ]
        if sinUbicar { salida["reason"] = "no_frames" }
        return salida
    }
}
