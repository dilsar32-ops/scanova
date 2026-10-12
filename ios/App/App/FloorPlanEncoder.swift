import Foundation
import CoreGraphics
import RoomPlan
import simd

// One piece of equipment logged by voice against a room (Part 7's
// voice-driven equipment logging) - `count` is nil, never 0, when a bare
// plural was heard with no number ("necesito deshumidificadores"), since
// that means "needs manual entry," not "zero were heard." `confidence`
// is "heard" (a number was actually recognized), "unclear" (equipment
// named but no number), or "assumed" (reserved for a future inferred
// default, unused by the voice parser itself, which never guesses a
// count). `mode` is "set" (replace the room's count for this type) or
// "add" (increment it) - Phase 1's voice parser always produces "set";
// "add" is reserved for a later "más/otro" hardening pass, per the plan.
struct EquipmentEntry {
    let type: String
    let label: String
    var count: Int?
    var mode: String = "set"
    var confidence: String
    var rawHeard: String
}

// Pure data transform: CapturedRoom -> plain [String: Any] JSON the web
// layer can render. No UIKit, no rendering - this file's only job is
// "what did RoomPlan actually measure," converted to feet (matching
// ARMeasurePlugin's existing meters->feet convention) so the web layer
// stays unit-agnostic, same as today.
enum FloorPlanEncoder {

    // internal (not private): FloorPlanPanelView reuses this exact
    // conversion for its live in-scan sketch, rather than a second,
    // parallel constant that could drift from the final exported plan.
    static let metersToFeet = 3.28084

    private static func equipmentEntryDict(_ entry: EquipmentEntry) -> [String: Any] {
        var d: [String: Any] = [
            "type": entry.type,
            "label": entry.label,
            "mode": entry.mode,
            "confidence": entry.confidence,
            "rawHeard": entry.rawHeard
        ]
        if let count = entry.count { d["count"] = count }
        return d
    }

    private static func confidenceString(_ c: CapturedRoom.Confidence) -> String {
        switch c {
        case .high: return "high"
        case .medium: return "medium"
        case .low: return "low"
        @unknown default: return "low"
        }
    }

    // A wall's centerline in the horizontal (floor) plane: transform's
    // translation is the wall's center, its local +X axis runs along the
    // wall's length, dimensions.x is the wall's length.
    // internal (not private): FloorPlanPanelView reuses this exact wall-
    // endpoint math for its live in-scan sketch, so a room's geometry
    // reads the same way there as it will in the final exported plan.
    // MARK: - Outline gaps (a missing wall, caught while he is still in the room)
    //
    // A wall RoomPlan never modelled does not exist as an element, so
    // ScanInspector cannot grade it: the missing wall is invisible to
    // every quality check the app has. The one thing that DOES see it is
    // whether the room's walls chain into a closed ring. That check was
    // written months ago - in the web layer, where it only runs hours
    // later in the office. This is the same algorithm, on the phone, so
    // the tech hears about it while he can still walk back and re-sweep.
    //
    // Ported line for line from fpOrderedRoomPolygon / 
    // fpAiSegmentCoveredByOtherWalls in www/index.html. Feet in, feet out,
    // matching roomSketch(for:) - so every constant transfers literally
    // and there is no second unit convention to get wrong.
    struct OutlineGap { let a: CGPoint; let b: CGPoint; let ft: Double }

    // 5 ft, not the web's 6. Measured on the real house: the largest break
    // that must stay SILENT is 3.47 ft (the Living Room / Kitchen doorway)
    // and the smallest real defect is 6.58 ft (the Hallway, with the wall
    // the owner later had to draw by hand removed). 5.0 sits 1.5 ft clear
    // of both; 6.0 sat 0.58 ft from missing the real one, which is the
    // expensive direction to be wrong in.
    static let outlineGapWarnFt = 5.0

    static func outlineGaps(wallsFt: [(CGPoint, CGPoint)]) -> [OutlineGap] {
        func dist(_ p: CGPoint, _ q: CGPoint) -> Double { hypot(q.x - p.x, q.y - p.y) }
        let walls = wallsFt.filter { dist($0.0, $0.1) > 0.05 }
        if walls.count < 3 { return [] }
        let tol = 1.0
        var used = [Bool](repeating: false, count: walls.count)
        var chains: [[CGPoint]] = []
        for s in walls.indices {
            if used[s] { continue }
            used[s] = true
            var chain = [walls[s].0, walls[s].1]
            var extended = true
            while extended {
                extended = false
                let head = chain[0], tail = chain[chain.count - 1]
                var bestD = Double.infinity, bestI = -1, bestFar = CGPoint.zero, bestAtTail = true
                for i in walls.indices where !used[i] {
                    let cands: [(Double, CGPoint, Bool)] = [
                        (dist(walls[i].0, tail), walls[i].1, true),
                        (dist(walls[i].1, tail), walls[i].0, true),
                        (dist(walls[i].0, head), walls[i].1, false),
                        (dist(walls[i].1, head), walls[i].0, false)
                    ]
                    for c in cands where c.0 < bestD { bestD = c.0; bestI = i; bestFar = c.1; bestAtTail = c.2 }
                }
                if bestI >= 0 && bestD <= tol {
                    used[bestI] = true
                    if bestAtTail { chain.append(bestFar) } else { chain.insert(bestFar, at: 0) }
                    extended = true
                }
            }
            chains.append(chain)
        }
        func chainLen(_ c: [CGPoint]) -> Double {
            guard c.count > 1 else { return 0 }
            var t = 0.0
            for i in 1..<c.count { t += dist(c[i-1], c[i]) }
            return t
        }
        var kept = chains.filter { chainLen($0) >= 2.5 }
        if kept.isEmpty { kept = chains }
        kept.sort { chainLen($0) > chainLen($1) }
        guard var poly = kept.first else { return [] }
        var rest = Array(kept.dropFirst())
        var gaps: [OutlineGap] = []
        while !rest.isEmpty {
            // Already closed? Then this IS the outline, and everything left
            // over is an interior wall of the room - not a piece of its
            // boundary. Bridging out to it draws a figure eight across the
            // room's own floor and invents gaps that are not there.
            if poly.count >= 3 && dist(poly[0], poly[poly.count - 1]) <= tol { break }
            let tail = poly[poly.count - 1]
            var bd = Double.infinity, bi = -1, bflip = false
            for (i, c) in rest.enumerated() {
                let dS = dist(c[0], tail), dE = dist(c[c.count - 1], tail)
                if dS < bd { bd = dS; bi = i; bflip = false }
                if dE < bd { bd = dE; bi = i; bflip = true }
            }
            if bi < 0 { break }
            let c = rest.remove(at: bi)
            let seg = bflip ? c.reversed().map { $0 } : c
            if bd > tol { gaps.append(OutlineGap(a: tail, b: seg[0], ft: bd)) }
            for (i, p) in seg.enumerated() {
                if i == 0 && bd <= tol { continue }
                poly.append(p)
            }
        }
        let closeDist = dist(poly[0], poly[poly.count - 1])
        if closeDist > tol { gaps.append(OutlineGap(a: poly[poly.count - 1], b: poly[0], ft: closeDist)) }
        return gaps
    }

    // A "gap" that another wall already runs along is not a gap - the
    // building is closed there and the chain simply walked around it.
    // Verified on the real house: the Bathroom's 7.4 ft break is its OWN
    // wall, and without this test the phone would cry wolf on it.
    static func gapCoveredByWalls(_ gap: OutlineGap, walls: [(CGPoint, CGPoint)]) -> Bool {
        let vx = gap.b.x - gap.a.x, vy = gap.b.y - gap.a.y
        let L = hypot(vx, vy)
        if L < 0.0001 { return true }
        let ux = vx / L, uy = vy / L, nx = -uy, ny = ux
        var spans: [(Double, Double)] = []
        for w in walls {
            let dx = w.1.x - w.0.x, dy = w.1.y - w.0.y
            let wl = hypot(dx, dy)
            if wl < 0.0001 { continue }
            if abs((dx / wl) * ux + (dy / wl) * uy) < 0.95 { continue }
            let offA = (w.0.x - gap.a.x) * nx + (w.0.y - gap.a.y) * ny
            let offB = (w.1.x - gap.a.x) * nx + (w.1.y - gap.a.y) * ny
            if abs(offA) > 0.8 || abs(offB) > 0.8 { continue }
            let t0 = (w.0.x - gap.a.x) * ux + (w.0.y - gap.a.y) * uy
            let t1 = (w.1.x - gap.a.x) * ux + (w.1.y - gap.a.y) * uy
            let lo = max(0, min(t0, t1)), hi = min(L, max(t0, t1))
            if hi > lo { spans.append((lo, hi)) }
        }
        spans.sort { $0.0 < $1.0 }
        var covered = 0.0, cursor = 0.0
        for (lo, hi) in spans where hi > cursor {
            covered += hi - max(lo, cursor)
            cursor = max(cursor, hi)
        }
        return covered >= L * 0.7
    }

    // ============ EL ASISTENTE DE ESQUINAS, EN EL TELÉFONO ============
    //
    // Su pedido del 13 de septiembre de 2026: "a la hora del escaneo tienes
    // que chequear bien las esquinas... si una esquina no se pudo lograr
    // llegar a escanear, que rectifique esa esquina, que pared a pared vayan
    // a encontrarse en esa esquina".
    //
    // La regla C (vértice cortado) de fpCornerFindings (www/index.html),
    // portada línea por línea: MISMAS constantes y los candados que se
    // pueden evaluar con lo que hay en la mano al cerrar un cuarto - sus
    // paredes y sus puertas/ventanas/aberturas. Los candados que necesitan
    // el camino andado o los cuartos vecinos se quedan para el plano. Aquí
    // SOLO SE AVISA (y se dice en qué esquina, con los largos de las dos
    // paredes): nunca se mueve una pared en el teléfono. Se llama en main,
    // al cerrar cada cuarto, sobre unas decenas de puntos.
    struct CornerFinding {
        let vertex: CGPoint          // donde se encontrarían las dos paredes
        let a: CGPoint, b: CGPoint   // las dos puntas sueltas
        let d: Double                // el puente entre las puntas (ft)
        let legA: Double, legB: Double       // lo que le falta a cada pared para llegar al vértice
        let wallALenFt: Double, wallBLenFt: Double
        let thetaDeg: Double
    }
    static let esqDMin = 1.0, esqDMax = 6.0, esqLegMin = 0.75, esqWallMin = 1.0
    static let esqThetaMin = 60.0, esqThetaMax = 120.0
    static let esqNodeFt = 0.35

    static func cornerFindings(wallsFt: [(CGPoint, CGPoint)], portsFt: [(center: CGPoint, widthFt: Double)]) -> [CornerFinding] {
        func dist(_ p: CGPoint, _ q: CGPoint) -> Double { hypot(q.x - p.x, q.y - p.y) }
        let walls = wallsFt.filter { dist($0.0, $0.1) > 0.05 }
        if walls.count < 3 { return [] }
        // Las puntas y su grado (cuántas puntas caen en el mismo nodo).
        struct Punta { let wall: Int; let tip: CGPoint; let far: CGPoint }
        var puntas: [Punta] = []
        for (i, w) in walls.enumerated() {
            puntas.append(Punta(wall: i, tip: w.0, far: w.1))
            puntas.append(Punta(wall: i, tip: w.1, far: w.0))
        }
        func grado(_ p: CGPoint) -> Int { puntas.filter { dist($0.tip, p) <= esqNodeFt }.count }
        func puntaEn(_ p: CGPoint) -> Punta? { puntas.first { dist($0.tip, p) <= esqNodeFt && grado($0.tip) == 1 } }
        func unit(_ from: CGPoint, _ to: CGPoint) -> CGPoint {
            let L = dist(from, to)
            return L > 0 ? CGPoint(x: (to.x - from.x) / L, y: (to.y - from.y) / L) : CGPoint(x: 1, y: 0)
        }
        // ¿Otra pared del cuarto ya corre por este tramo? (doble trazo, o un
        // hueco que en realidad está cerrado). `excluir` deja fuera la pared
        // que se está juzgando.
        func cubierto(_ a: CGPoint, _ b: CGPoint, excluir: Int?) -> Bool {
            let otras = walls.enumerated().filter { $0.offset != excluir }.map { $0.element }
            return gapCoveredByWalls(OutlineGap(a: a, b: b, ft: dist(a, b)), walls: otras)
        }
        func puertaCerca(_ p: CGPoint, _ ft: Double) -> Bool { portsFt.contains { dist($0.center, p) <= ft } }
        func distToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
            let dx = b.x - a.x, dy = b.y - a.y, L2 = dx * dx + dy * dy
            if L2 < 1e-9 { return dist(p, a) }
            var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / L2
            t = max(0, min(1, t))
            return dist(p, CGPoint(x: a.x + dx * t, y: a.y + dy * t))
        }
        var out: [CornerFinding] = []
        // Los puentes del encadenado son exactamente los de outlineGaps (tol 1 ft).
        for gap in outlineGaps(wallsFt: walls) where gap.ft > esqDMin && gap.ft <= esqDMax {
            guard let A = puntaEn(gap.a), let B = puntaEn(gap.b), A.wall != B.wall else { continue } // candado 2
            let u1 = unit(A.far, A.tip), u2 = unit(B.far, B.tip)
            let theta = acos(max(-1, min(1, abs(u1.x * u2.x + u1.y * u2.y)))) * 180 / .pi
            if theta < esqThetaMin || theta > esqThetaMax { continue }                        // candado 3
            let lenA = dist(walls[A.wall].0, walls[A.wall].1), lenB = dist(walls[B.wall].0, walls[B.wall].1)
            if lenA < esqWallMin || lenB < esqWallMin { continue }                            // candado 4a
            let den = u1.x * u2.y - u1.y * u2.x
            if abs(den) < 1e-6 { continue }
            let t = ((B.tip.x - A.tip.x) * u2.y - (B.tip.y - A.tip.y) * u2.x) / den
            let c = CGPoint(x: A.tip.x + u1.x * t, y: A.tip.y + u1.y * t)
            let s = (c.x - B.tip.x) * u2.x + (c.y - B.tip.y) * u2.y
            if t < esqLegMin || s < esqLegMin { continue }                                      // candado 4b
            if max(t, s) > min(6, 1.5 * gap.ft) { continue }
            if cubierto(walls[A.wall].0, walls[A.wall].1, excluir: A.wall)
                || cubierto(walls[B.wall].0, walls[B.wall].1, excluir: B.wall) { continue }   // candado 5
            if cubierto(gap.a, gap.b, excluir: nil) { continue }                              // candado 6: ya hay pared
            let mid = CGPoint(x: (gap.a.x + gap.b.x) / 2, y: (gap.a.y + gap.b.y) / 2)
            if portsFt.contains(where: { dist($0.center, mid) <= gap.ft / 2 + 0.8 }) { continue } //   una puerta en el tramo
            if puertaCerca(gap.a, 1) || puertaCerca(gap.b, 1) { continue }                    //   una abertura junto a la punta
            // El vértice no puede caer encima de otra pared del cuarto.
            var sobrePared = false
            for (i, w) in walls.enumerated() where i != A.wall && i != B.wall {
                if distToSegment(c, w.0, w.1) < 0.4 { sobrePared = true; break }
            }
            if sobrePared { continue }
            out.append(CornerFinding(vertex: c, a: gap.a, b: gap.b, d: gap.ft, legA: t, legB: s,
                                     wallALenFt: lenA, wallBLenFt: lenB, thetaDeg: theta))
        }
        return out
    }

    static func wallEndpoints(_ surface: CapturedRoom.Surface) -> (start: SIMD2<Float>, end: SIMD2<Float>) {
        let t = surface.transform
        let center = SIMD2<Float>(t.columns.3.x, t.columns.3.z)
        let xAxis = SIMD2<Float>(t.columns.0.x, t.columns.0.z)
        let dir = simd_length(xAxis) > 0.0001 ? simd_normalize(xAxis) : SIMD2<Float>(1, 0)
        let half = surface.dimensions.x / 2
        return (center - dir * half, center + dir * half)
    }

    private static func point2D(_ surface: CapturedRoom.Surface) -> SIMD2<Float> {
        let t = surface.transform
        return SIMD2<Float>(t.columns.3.x, t.columns.3.z)
    }

    private static func point2D(_ object: CapturedRoom.Object) -> SIMD2<Float> {
        let t = object.transform
        return SIMD2<Float>(t.columns.3.x, t.columns.3.z)
    }

    private static func distanceToSegment(point p: SIMD2<Float>, start a: SIMD2<Float>, end b: SIMD2<Float>) -> Float {
        let ab = b - a
        let lenSq = simd_length_squared(ab)
        if lenSq < 0.0001 { return simd_distance(p, a) }
        var t = simd_dot(p - a, ab) / lenSq
        t = max(0, min(1, t))
        let proj = a + ab * t
        return simd_distance(p, proj)
    }

    // Which wall a door/window/opening belongs to is worked out
    // geometrically (closest wall centerline to that surface's own
    // position) rather than relying on a parent-surface API field, so this
    // doesn't depend on an SDK detail that could differ across RoomPlan
    // versions - it always computes a real, defensible answer from the
    // actual captured geometry.
    private static func nearestWallId(to point: SIMD2<Float>, walls: [(id: String, start: SIMD2<Float>, end: SIMD2<Float>)]) -> String? {
        var bestId: String?
        var bestDist = Float.greatestFiniteMagnitude
        for wall in walls {
            let d = distanceToSegment(point: point, start: wall.start, end: wall.end)
            if d < bestDist {
                bestDist = d
                bestId = wall.id
            }
        }
        return bestId
    }

    // Everything one CapturedRoom contributes to the JSON, minus any
    // session-level wrapping (cancelled/merged/buildingSummary) - reused
    // both for a single-room scan and for each room inside a merged
    // multi-room CapturedStructure, since a merged room is still just a
    // CapturedRoom whose walls/objects happen to share a coordinate space
    // with its neighbors.
    // MARK: - API probe
    //
    // Apple hands this app several things it has never read, and the ONE
    // question the headers cannot answer is whether they are actually
    // POPULATED on a real, refined, post-StructureBuilder room - declared
    // is not the same as filled in. The most important is
    // floors[].polygonCorners: the app currently reconstructs each room's
    // outline by chaining wall segments and guessing at the gaps, which is
    // the root of a whole family of bugs, while Apple may simply be
    // handing over the floor polygon.
    //
    // So this rides along in the saved plan instead of an NSLog nobody
    // will ever see: one small dict per room, read once, no per-frame
    // work, no session interaction. It reads NOTHING that could change
    // behaviour - it only records what is there. Next real scan answers
    // every one of these questions at once, off the phone, with devicectl.
    static func apiProbe(_ room: CapturedRoom) -> [String: Any] {
        var out: [String: Any] = [:]
        out["walls"] = room.walls.count
        out["doors"] = room.doors.count
        out["windows"] = room.windows.count
        out["openings"] = room.openings.count
        out["objects"] = room.objects.count

        // iOS 16: which sides of each wall RoomPlan never finished. A wall
        // missing .left/.right is Apple saying it never closed that end -
        // the upstream cause of the chain failing and a gap being reported.
        var edgeCounts: [Int] = []
        var missingEnds = 0
        for w in room.walls {
            let n = w.completedEdges.count
            edgeCounts.append(n)
            if !w.completedEdges.contains(.left) || !w.completedEdges.contains(.right) { missingEnds += 1 }
        }
        out["completedEdgeCounts"] = edgeCounts
        out["wallsMissingAnEnd"] = missingEnds

        // Doors carry an open/closed flag that the encoder discards.
        var doorsOpen = 0, doorsClosed = 0
        for d in room.doors {
            if case .door(let isOpen) = d.category { isOpen ? (doorsOpen += 1) : (doorsClosed += 1) }
        }
        out["doorsOpen"] = doorsOpen
        out["doorsClosed"] = doorsClosed

        if #available(iOS 17.0, *) {
            // THE big one. If this comes back with real polygons, the app
            // can stop guessing at room outlines entirely.
            out["floorCount"] = room.floors.count
            out["floorCornerCounts"] = room.floors.map { $0.polygonCorners.count }
            out["floorAreasSqFt"] = room.floors.map { f -> Double in
                let pts = f.polygonCorners
                guard pts.count >= 3 else { return 0 }
                // shoelace in the floor surface's own plane, then to feet
                var a = 0.0
                for i in 0..<pts.count {
                    let p = pts[i], q = pts[(i + 1) % pts.count]
                    a += Double(p.x * q.z - q.x * p.z)
                }
                return abs(a / 2) * metersToFeet * metersToFeet
            }
            // Apple's OWN answer to "how many distinct spaces are in this
            // capture", which the app re-derives from scratch with a grid
            // flood fill - and got wrong on a real house.
            out["sectionCount"] = room.sections.count
            out["sectionLabels"] = room.sections.map { String(describing: $0.label) }
            out["sectionCenters"] = room.sections.map {
                ["x": Double($0.center.x) * metersToFeet, "y": Double($0.center.z) * metersToFeet]
            }
            out["story"] = room.story
            // Apple's own wall<->opening parentage. FloorPlanEncoder
            // deliberately chose geometric nearest-wall matching instead;
            // this records whether the real field would have worked.
            let parented = room.doors.filter { $0.parentIdentifier != nil }.count
                + room.windows.filter { $0.parentIdentifier != nil }.count
                + room.openings.filter { $0.parentIdentifier != nil }.count
            out["openingsWithParent"] = parented
            out["openingsTotal"] = room.doors.count + room.windows.count + room.openings.count
            out["wallCornerCounts"] = room.walls.map { $0.polygonCorners.count }
            out["objectsWithAttributes"] = room.objects.filter { !$0.attributes.isEmpty }.count
        }
        return out
    }

    // `surfaceAnswers` = lo que el TECNICO contesto por voz sobre una
    // superficie que RoomPlan no supo clasificar, por identificador. El que
    // esta parado en el cuarto ve mejor que el escaner. No inventa nada:
    // solo cambia una etiqueta, nunca una medida ni una pared.
    private static func roomDict(_ room: CapturedRoom, surfaceAnswers: [String: String] = [:]) -> [String: Any] {
        var wallDicts: [[String: Any]] = []
        var wallLookup: [(id: String, start: SIMD2<Float>, end: SIMD2<Float>)] = []
        var perimeterFt: Double = 0

        for wall in room.walls {
            let id = wall.identifier.uuidString
            let (start, end) = wallEndpoints(wall)
            wallLookup.append((id, start, end))
            let lengthFt = Double(wall.dimensions.x) * metersToFeet
            let heightFt = Double(wall.dimensions.y) * metersToFeet
            perimeterFt += lengthFt
            wallDicts.append([
                "id": id,
                "start": ["x": Double(start.x) * metersToFeet, "y": Double(start.y) * metersToFeet],
                "end":   ["x": Double(end.x) * metersToFeet,   "y": Double(end.y) * metersToFeet],
                "lengthFt": lengthFt,
                "heightFt": heightFt,
                "confidence": confidenceString(wall.confidence)
            ])
        }

        func encodeOpening(_ surface: CapturedRoom.Surface) -> [String: Any] {
            let p = point2D(surface)
            let sid = surface.identifier.uuidString
            var d: [String: Any] = [
                "id": sid,
                "position": ["x": Double(p.x) * metersToFeet, "y": Double(p.y) * metersToFeet],
                "widthFt": Double(surface.dimensions.x) * metersToFeet,
                "heightFt": Double(surface.dimensions.y) * metersToFeet,
                "confidence": confidenceString(surface.confidence)
            ]
            if let wallId = nearestWallId(to: p, walls: wallLookup) { d["wallId"] = wallId }
            if let dicho = surfaceAnswers[sid] { d["voiceIs"] = dicho }
            return d
        }

        let doorDicts = room.doors.map(encodeOpening)
        let windowDicts = room.windows.map(encodeOpening)
        let openingDicts = room.openings.map(encodeOpening)

        let objectDicts: [[String: Any]] = room.objects.map { obj in
            let p = point2D(obj)
            let t = obj.transform
            // Rotation about the vertical axis, derived from the local X
            // axis projected onto the floor plane - RoomPlan doesn't hand
            // this back as a single angle directly.
            let xAxis = SIMD2<Float>(t.columns.0.x, t.columns.0.z)
            let rotationDeg = Double(atan2(xAxis.y, xAxis.x)) * 180 / Double.pi
            return [
                "id": obj.identifier.uuidString,
                "category": String(describing: obj.category),
                "center": ["x": Double(p.x) * metersToFeet, "y": Double(p.y) * metersToFeet],
                "widthFt": Double(obj.dimensions.x) * metersToFeet,
                "depthFt": Double(obj.dimensions.z) * metersToFeet,
                "heightFt": Double(obj.dimensions.y) * metersToFeet,
                "rotationDeg": rotationDeg,
                "confidence": confidenceString(obj.confidence)
            ]
        }

        // Shoelace formula over each wall's start point, in scan order - an
        // approximation (real room perimeters aren't always one clean
        // convex loop), good enough for a "roughly how big is this room"
        // number, not a certified square-footage figure.
        var areaSqFt: Double = 0
        if wallLookup.count >= 3 {
            var sum: Float = 0
            for i in 0..<wallLookup.count {
                let a = wallLookup[i].start
                let b = wallLookup[(i + 1) % wallLookup.count].start
                sum += a.x * b.y - b.x * a.y
            }
            areaSqFt = Double(abs(sum) / 2) * metersToFeet * metersToFeet
        }

        return [
            "summary": [
                "floorAreaSqFt": (areaSqFt * 10).rounded() / 10,
                "perimeterFt": (perimeterFt * 10).rounded() / 10,
                "wallCount": wallDicts.count,
                "doorCount": doorDicts.count,
                "windowCount": windowDicts.count,
                "objectCount": objectDicts.count
            ],
            "walls": wallDicts,
            "doors": doorDicts,
            "windows": windowDicts,
            "openings": openingDicts,
            "objects": objectDicts
        ]
    }

    // Session-level result for a (possibly multi-room, possibly multi-level)
    // scan: `merged` tells the web layer whether every room in `rooms`
    // genuinely shares one coordinate space (StructureBuilder succeeded) or
    // each room is independently positioned at its own local origin (iOS 16,
    // or a failed/unavailable merge) - the web layer must not draw them as
    // one connected plan unless this is true. `levels` is parallel to
    // `rooms` (same index = same room, 1-based) - which building level each
    // room was tagged with when scanned (RoomScanViewController.swift);
    // pass an empty array if levels weren't tracked (defaults every room to
    // level 1). `voiceNames` is likewise parallel to `rooms` - the room
    // name the voice assistant heard, if any; omitted from the dict
    // entirely when nil so the web layer's `room.voiceName` check is a
    // simple truthiness check, not a null check. `equipment` is also
    // parallel to `rooms` - each room's own [type: EquipmentEntry] map,
    // logged by the voice assistant while scanning that room; a room's
    // "equipment" key is omitted entirely when nothing was logged, same
    // omit-when-absent convention as `voiceName`. `deletedIndices` flags
    // rooms the tech deleted by voice mid-session - a SOFT flag only
    // (there's no API to un-scan a room), so a deleted room still carries
    // its own real geometry/equipment but gets a `deleted: true` marker
    // for the web layer to exclude from the rendered plan and totals.
    static func encodeStructure(rooms: [CapturedRoom], merged: Bool, levels: [Int] = [], voiceNames: [String?] = [], equipment: [[String: EquipmentEntry]] = [], deletedIndices: Set<Int> = [], surfaceAnswers: [String: String] = [:]) -> [String: Any] {
        let roomDicts = rooms.enumerated().map { idx, room -> [String: Any] in
            var dict = roomDict(room, surfaceAnswers: surfaceAnswers)
            dict["level"] = levels.indices.contains(idx) ? levels[idx] : 1
            if let voiceName = voiceNames.indices.contains(idx) ? voiceNames[idx] : nil {
                dict["voiceName"] = voiceName
            }
            if equipment.indices.contains(idx), !equipment[idx].isEmpty {
                dict["equipment"] = equipment[idx].values.map(equipmentEntryDict)
            }
            if deletedIndices.contains(idx) {
                dict["deleted"] = true
            }
            dict["_apiProbe"] = apiProbe(room)
            return dict
        }
        // Deleted rooms are excluded from the building total, same as they
        // will be from the rendered plan - the whole point of the soft
        // flag is that the number the tech sees matches what they asked
        // to keep, even though the underlying scan data isn't discarded.
        let totalAreaSqFt = roomDicts.enumerated().reduce(0.0) { sum, pair in
            let (idx, dict) = pair
            guard !deletedIndices.contains(idx) else { return sum }
            let s = dict["summary"] as? [String: Any]
            return sum + ((s?["floorAreaSqFt"] as? Double) ?? 0)
        }
        let keptRoomCount = roomDicts.count - deletedIndices.count
        let levelCount = Set(roomDicts.enumerated().compactMap { idx, dict -> Int? in
            guard !deletedIndices.contains(idx) else { return nil }
            return dict["level"] as? Int
        }).count
        return [
            "cancelled": false,
            "merged": merged,
            "rooms": roomDicts,
            "buildingSummary": [
                "totalAreaSqFt": (totalAreaSqFt * 10).rounded() / 10,
                "roomCount": max(keptRoomCount, 0),
                "levelCount": max(levelCount, 1)
            ]
        ]
    }
}
