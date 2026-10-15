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

    static func outlineGaps(wallsFt: [(CGPoint, CGPoint)]) -> [OutlineGap] { contornoYHuecos(wallsFt: wallsFt).gaps }

    // El mismo encadenado de outlineGaps, devolviendo también el contorno
    // (para saber si un punto cae dentro de un cuarto).
    static func contornoYHuecos(wallsFt: [(CGPoint, CGPoint)]) -> (poly: [CGPoint], gaps: [OutlineGap]) {
        func dist(_ p: CGPoint, _ q: CGPoint) -> Double { hypot(q.x - p.x, q.y - p.y) }
        let walls = wallsFt.filter { dist($0.0, $0.1) > 0.05 }
        if walls.count < 3 { return (walls.map { $0.0 }, []) }
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
        guard var poly = kept.first else { return ([], []) }
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
        return (poly, gaps)
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

    // ============ LOS MARCOS DE CADA CAPTURA Y EL PARCHE (14-oct) ============
    //
    // La casa de Harold: "puso un cuarto encima de la cocina". Cada captura
    // de RoomPlan arranca con SU propio origen (ARKit pone el 0,0 donde está
    // el teléfono al empezar). Apple junta los cuartos con StructureBuilder,
    // pero el parche de "Completar escaneo" se pegaba a su cuarto como si
    // estuviera en las mismas coordenadas, y las poses y fotos de la
    // caminata se dibujaban sobre el plano unido sin moverlas. Aquí está la
    // geometría PURA para pasar cada cosa a su lugar y para decidir qué
    // pedazo del parche de verdad cierra lo que faltaba. Sin tipos de
    // RoomPlan: se prueba en la Mac (tests/marcos/correr.sh copia lo
    // que está entre BEGIN PURO y END PURO).
    // BEGIN PURO
    /// Un movimiento rígido en el piso (x, z del mundo): girar `th` y mover (tx, ty).
    struct Rigido2D {
        var th: Double, tx: Double, ty: Double
        static let identidad = Rigido2D(th: 0, tx: 0, ty: 0)
        func aplicar(_ p: CGPoint) -> CGPoint {
            let c = cos(th), s = sin(th)
            return CGPoint(x: c * p.x - s * p.y + tx, y: s * p.x + c * p.y + ty)
        }
        var inverso: Rigido2D {
            let c = cos(-th), s = sin(-th)
            return Rigido2D(th: -th, tx: -(c * tx - s * ty), ty: -(s * tx + c * ty))
        }
        /// Primero self, después `b`.
        func luego(_ b: Rigido2D) -> Rigido2D {
            let o = b.aplicar(aplicar(.zero))
            return Rigido2D(th: th + b.th, tx: o.x, ty: o.y)
        }
        /// Un punto en pies (el movimiento está en metros).
        func aplicarPies(_ p: CGPoint, f: Double) -> CGPoint {
            let q = aplicar(CGPoint(x: p.x / f, y: p.y / f))
            return CGPoint(x: q.x * f, y: q.y * f)
        }
    }

    /// El movimiento que lleva cada pared de "antes" a la misma pared "después"
    /// (mismo identificador). El giro sale del eje de las paredes (una pared
    /// puede volver al revés). El movimiento se saca de lo que una pared SÍ
    /// dice con certeza: dónde está de lado a lado (su perpendicular); a lo
    /// largo casi no pesa, porque al juntar cuartos Apple alarga o recorta
    /// paredes para que se toquen. El sentido bueno del giro (θ o θ+180°) es
    /// el que deja menos error. Pide al menos dos paredes que no sean
    /// paralelas, y que el error que queda sea chico: si no, nil (mejor no
    /// mover nada que moverlo mal).
    /// `tambienLargo`: el respaldo para una captura con puras superficies
    /// paralelas (un pasillo abierto por las dos puntas): se pesa también lo
    /// largo de cada pared, como antes, en vez de no dar nada.
    static func ajusteRigido(_ pares: [(a0: CGPoint, b0: CGPoint, a1: CGPoint, b1: CGPoint, peso: Double)],
                             errorMaximo: Double = 0.25, tambienLargo: Bool = false, pesosLargo: [Double]? = nil) -> Rigido2D? {
        guard pares.count >= 2 else { return nil }
        func medio(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        var s2 = 0.0, c2 = 0.0
        for p in pares {
            let d = atan2(Double(p.b1.y - p.a1.y), Double(p.b1.x - p.a1.x)) - atan2(Double(p.b0.y - p.a0.y), Double(p.b0.x - p.a0.x))
            s2 += sin(2 * d) * p.peso; c2 += cos(2 * d) * p.peso
        }
        guard s2 * s2 + c2 * c2 > 1e-12 else { return nil }
        let eje = atan2(s2, c2) / 2
        var mejor: (r: Rigido2D, err: Double)? = nil, segundo: Double = .infinity
        for th in [eje, eje + Double.pi] {
            let c = cos(th), s = sin(th)
            // Mínimos cuadrados con la perpendicular de cada pared (y un
            // poquito de su largo, para que el sistema nunca quede suelto).
            var a11 = 0.0, a12 = 0.0, a22 = 0.0, b1 = 0.0, b2 = 0.0
            var n11 = 0.0, n12 = 0.0, n22 = 0.0
            for (k, p) in pares.enumerated() {
                let m0 = medio(p.a0, p.b0), m1 = medio(p.a1, p.b1)
                let dx = Double(p.b1.x - p.a1.x), dy = Double(p.b1.y - p.a1.y), L = hypot(dx, dy)
                guard L > 1e-6 else { continue }
                let ux = dx / L, uy = dy / L, nx = -uy, ny = ux
                let rx = Double(m1.x) - (c * Double(m0.x) - s * Double(m0.y))
                let ry = Double(m1.y) - (s * Double(m0.x) + c * Double(m0.y))
                // Lo largo de una pared casi no cuenta (Apple las estira al
                // juntar); en el respaldo pesa lo largo de puertas y ventanas.
                let w = p.peso, e = tambienLargo ? (pesosLargo.map { k < $0.count ? $0[k] : 1.0 } ?? 1.0) : 0.02
                a11 += w * (nx * nx + e * ux * ux); a12 += w * (nx * ny + e * ux * uy); a22 += w * (ny * ny + e * uy * uy)
                n11 += w * nx * nx; n12 += w * nx * ny; n22 += w * ny * ny
                let rn = nx * rx + ny * ry, ru = ux * rx + uy * ry
                b1 += w * (nx * rn + e * ux * ru); b2 += w * (ny * rn + e * uy * ru)
            }
            // Todas paralelas: el movimiento de lado a lado de una sola
            // dirección no alcanza para saber dónde va el cuarto.
            let trazaN = n11 + n22
            guard trazaN > 0, tambienLargo || (n11 * n22 - n12 * n12) / (trazaN * trazaN) > 0.02 else { return nil }
            let det = a11 * a22 - a12 * a12
            guard abs(det) > 1e-12 else { return nil }
            let tx = (b1 * a22 - b2 * a12) / det, ty = (a11 * b2 - a12 * b1) / det
            let r = Rigido2D(th: th, tx: tx, ty: ty)
            var err = 0.0, w = 0.0
            for (k, p) in pares.enumerated() {
                let q = r.aplicar(medio(p.a0, p.b0)), m1 = medio(p.a1, p.b1)
                let dx = Double(p.b1.x - p.a1.x), dy = Double(p.b1.y - p.a1.y), L = hypot(dx, dy)
                guard L > 1e-6 else { continue }
                let rn = Double(q.x - m1.x) * (-dy / L) + Double(q.y - m1.y) * (dx / L)
                let ru = Double(q.x - m1.x) * (dx / L) + Double(q.y - m1.y) * (dy / L)
                // Lo largo se cobra con el mismo peso con que se ajustó (una pared
                // que Apple estiró no puede tumbar un ajuste bueno).
                let e = pesosLargo.map { k < $0.count ? $0[k] : 1.0 } ?? 1.0
                err += (tambienLargo ? sqrt(rn * rn + e * ru * ru) : abs(rn)) * p.peso
                w += p.peso
            }
            guard w > 0 else { return nil }
            err /= w
            if mejor == nil || err < mejor!.err { if let m = mejor { segundo = m.err }; mejor = (r, err) } else { segundo = min(segundo, err) }
        }
        guard let m = mejor, m.err <= errorMaximo else { return nil }
        // En el respaldo, si los dos sentidos dan casi lo mismo, no se adivina.
        if tambienLargo && segundo < m.err + 0.1 { return nil }
        return m.r
    }

    /// Cuántos pies de las paredes `parche` caen sobre paredes de `base` (casi
    /// paralelas, a menos de 0.7 ft). Un parche bien acomodado vuelve a ver
    /// parte de lo que el cuarto ya tenía; uno que no toca nada no se pega.
    static func largoCubierto(_ parche: [(CGPoint, CGPoint)], por base: [(CGPoint, CGPoint)]) -> (cubierto: Double, total: Double) {
        var cub = 0.0, tot = 0.0
        for (a, b) in parche {
            let l = hypot(b.x - a.x, b.y - a.y)
            tot += l
            let libre = tramosSinCubrir(a, b, base).reduce(0.0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
            cub += max(0, l - libre)
        }
        return (cub, tot)
    }

    static func distSegmento(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy
        guard l2 > 0.0001 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
        return hypot(p.x - (a.x + dx * t), p.y - (a.y + dy * t))
    }
    static func enPoligono(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        guard poly.count >= 3 else { return false }
        var dentro = false
        var j = poly.count - 1
        for i in poly.indices {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { dentro.toggle() }
            j = i
        }
        return dentro
    }
    static func distAlBorde(_ p: CGPoint, _ poly: [CGPoint]) -> Double {
        guard poly.count >= 2 else { return .infinity }
        var m = Double.infinity
        for i in poly.indices { m = min(m, distSegmento(p, poly[i], poly[(i + 1) % poly.count])) }
        return m
    }
    /// Lo que queda de la pared AB que ninguna pared de `refs` ya cubre (casi
    /// paralela, a menos de 0.7 ft de su línea). El mismo de antes, aquí para
    /// poderlo probar.
    static func tramosSinCubrir(_ a: CGPoint, _ b: CGPoint, _ refs: [(CGPoint, CGPoint)]) -> [(CGPoint, CGPoint)] {
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
    /// LO QUE EL PARCHE SÍ AGREGA. De cada pared del parche (ya en el marco
    /// del cuarto) se quita lo que ya está (paredes del cuarto y de los
    /// otros cuartos); de lo que sobra se queda solo el pedazo que cae en un
    /// hueco del contorno del cuarto (cerca de la línea que lo cierra) y que
    /// no se mete en el piso de otro cuarto. Un parche que vio otro espacio
    /// no agrega nada: el cuarto se queda como estaba (incompleto), nunca
    /// con paredes inventadas encima de los vecinos.
    static func piezasDeParche(parcheFt: [(CGPoint, CGPoint)], propiasFt: [(CGPoint, CGPoint)],
                               otrasFt: [(CGPoint, CGPoint)], otrosContornos: [[CGPoint]]) -> [(CGPoint, CGPoint)] {
        // Los huecos se buscan con las mismas paredes con que se avisan: sin
        // las del cuarto de al lado que RoomPlan metió en este (si no, salen
        // diagonales que no existen y el pedazo bueno no cae en ninguna).
        let ajenas = paredesAjenas(propias: propiasFt, otras: otrasFt)
        let base = propiasFt.enumerated().filter { !ajenas.contains($0.offset) }.map { $0.element }
        let huecos = outlineGaps(wallsFt: base).filter { $0.ft >= 1.0 && !gapCoveredByWalls($0, walls: base) }
        guard !huecos.isEmpty else { return [] }
        var out: [(CGPoint, CGPoint)] = []
        for (a, b) in parcheFt {
            for (u, v) in tramosSinCubrir(a, b, propiasFt + otrasFt) {
                let largo = hypot(v.x - u.x, v.y - u.y)
                guard largo >= 1.0 else { continue }
                let n = max(4, Int(ceil(largo / 0.5)))
                let muestras = (0...n).map { k -> CGPoint in
                    let t = Double(k) / Double(n)
                    return CGPoint(x: u.x + (v.x - u.x) * t, y: u.y + (v.y - u.y) * t)
                }
                let cerca = huecos.contains { h in muestras.allSatisfy { distSegmento($0, h.a, h.b) <= max(1.5, 0.55 * h.ft) } }
                guard cerca else { continue }
                let dentroDeOtro = muestras.filter { m in otrosContornos.contains { enPoligono(m, $0) && distAlBorde(m, $0) >= 0.75 } }.count
                guard Double(dentroDeOtro) / Double(muestras.count) < 0.3 else { continue }
                out.append((u, v))
            }
        }
        return out
    }
    /// PAREDES AJENAS: RoomPlan a veces mete en un cuarto una pared del
    /// cuarto de al lado (la casa de Harold: la pared del Hallway dentro de
    /// la sala, colgando). Al buscar huecos, el contorno se encadena por esa
    /// punta suelta y sale un "lado faltante" en diagonal que no existe y que
    /// ningún "Completar" puede cerrar. Candidata: una pared que otra pared de
    /// OTRO cuarto cubre en un 70% o más. Se ignora (solo para buscar huecos;
    /// nunca se borra nada del plano) si al quitarla los huecos que se avisan
    /// se achican de verdad - una pared del cuarto que sí es suya, al
    /// quitarla, abre un hueco: esa nunca se quita. Devuelve qué paredes se
    /// ignoraron.
    static func paredesAjenas(propias: [(CGPoint, CGPoint)], otras: [(CGPoint, CGPoint)]) -> Set<Int> {
        guard !otras.isEmpty, propias.count > 3 else { return [] }
        func faltante(_ fuera: Set<Int>, _ perdonan: [(CGPoint, CGPoint)]) -> Double {
            let w = propias.enumerated().filter { !fuera.contains($0.offset) }.map { $0.element }
            return outlineGaps(wallsFt: w)
                .filter { $0.ft > outlineGapWarnFt && !gapCoveredByWalls($0, walls: w) && !gapCoveredByWalls($0, walls: perdonan) }
                .reduce(0) { $0 + $1.ft }
        }
        let candidatas = propias.indices.filter { i in
            let c = largoCubierto([propias[i]], por: otras)
            return c.total > 0.5 && c.cubierto >= 0.7 * c.total
        }
        var fuera = Set<Int>()
        var actual = faltante(fuera, otras)
        var mejoro = true
        while mejoro && actual > 0 {
            mejoro = false
            var mejor: (i: Int, f: Double)? = nil
            for i in candidatas where !fuera.contains(i) {
                // Si al quitarla el contorno se cierra con un puente que corre
                // justo por donde estaba ella, ES pared del contorno (la
                // compartida con el vecino): quitarla solo dejaría que la
                // pared del vecino tape un hueco de verdad en la misma línea.
                let sin = propias.enumerated().filter { !fuera.union([i]).contains($0.offset) }.map { $0.element }
                let puentes = outlineGaps(wallsFt: sin).map { ($0.a, $0.b) }
                let porAhi = largoCubierto([propias[i]], por: puentes)
                if porAhi.total > 0, porAhi.cubierto >= 0.5 * porAhi.total { continue }
                // El hueco que se abre al quitarla no lo puede perdonar la MISMA
                // pared del vecino que la tapa a ella (si no, una pared real
                // compartida "desaparece" y su vecino tapa el hueco de al lado).
                let perdonan = otras.filter { largoCubierto([propias[i]], por: [$0]).cubierto < 0.5 }
                let f = faltante(fuera.union([i]), perdonan)
                if f <= actual - 1.0, mejor == nil || f < mejor!.f { mejor = (i, f) }
            }
            if let m = mejor { fuera.insert(m.i); actual = m.f; mejoro = true }
        }
        return fuera
    }
    // END PURO

    /// El movimiento de las paredes de un cuarto ANTES a las mismas paredes
    /// DESPUÉS (por identificador), en metros, en el piso (x, z).
    static func rigidoEntre(_ antes: [CapturedRoom.Surface], _ despues: [CapturedRoom.Surface]) -> Rigido2D? {
        var porId: [UUID: CapturedRoom.Surface] = [:]
        for w in despues { porId[w.identifier] = w }
        var pares: [(a0: CGPoint, b0: CGPoint, a1: CGPoint, b1: CGPoint, peso: Double)] = []
        var esAbertura: [Bool] = []
        for w in antes {
            guard let d = porId[w.identifier] else { continue }
            if case .wall = w.category { esAbertura.append(false) } else { esAbertura.append(true) }
            let (a0, b0) = wallEndpoints(w), (a1, b1) = wallEndpoints(d)
            pares.append((CGPoint(x: Double(a0.x), y: Double(a0.y)), CGPoint(x: Double(b0.x), y: Double(b0.y)),
                          CGPoint(x: Double(a1.x), y: Double(a1.y)), CGPoint(x: Double(b1.x), y: Double(b1.y)),
                          max(Double(w.dimensions.x), 0.1)))
        }
        let hayAberturas = esAbertura.contains(true)
        let largo = esAbertura.map { $0 ? 1.0 : (hayAberturas ? 0.02 : 1.0) }
        return ajusteRigido(pares) ?? ajusteRigido(pares, errorMaximo: 0.35, tambienLargo: true, pesosLargo: largo)
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
                // shoelace in the floor surface's own LOCAL plane (x, y; z = 0
                // there), then to feet. With x/z it came back 0 every time.
                var a = 0.0
                for i in 0..<pts.count {
                    let p = pts[i], q = pts[(i + 1) % pts.count]
                    a += Double(p.x * q.y - q.x * p.y)
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
