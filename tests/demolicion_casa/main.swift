// PRUEBA EN 3D DE LO DEMOLIDO EN UNA CASA (16 oct 2026): cortes parciales, esquinas, puertas, ventanas.
// El teléfono camina DENTRO del cuarto (no puede pasar por las esquinas: voltea a verlas), la cara de la pared la da el
// plano de ARKit (no un toque de "Fijar pared"), y el resultado se reporta como en el plano: desde qué esquina, cuánto.
import Foundation
import simd

typealias C = ComparadorDeDemolicion

struct Camino {
    var distancia: Float = 1.2
    var altura: Float = 1.0
    var inclinacionMin: Float = 12, inclinacionMax: Float = 34
    var margen: Float = 0.45            // lo más cerca que llega de la esquina (m)
    var voltea: Float = 38              // grados que voltea a ver cada esquina al llegar
    var segundos: Float = 34
    var ancho = 72, alto = 96
    var fovH: Float = 48, fovV: Float = 62
    var deriva: Float = 0.0010
    var desdeX: Float? = nil, hastaX: Float? = nil   // si no camina toda la pared
}

// Lo que vio el láser de UNA pared, con la cara puesta por el plano de ARKit (medio grado torcida, 3 mm corrida).
func barrer(_ casa: Casa, pared ip: Int, camino k: Camino, origenAlto: Float, cara caraDada: C.Cara? = nil) -> (C.Resultado, C, xMid: Float) {
    var comp = C()
    let w = casa.paredes[ip]
    let L = w.largo
    let xMid = L / 2
    let giro: Float = 0.5 * .pi / 180
    func mundo(_ p: SIMD3<Float>) -> SIMD3<Float> { let q = w.a + w.ex * p.x + w.n * p.z; return SIMD3(q.x, p.y, q.y) }
    func mundoDir(_ d: SIMD3<Float>) -> SIMD3<Float> { let q = w.ex * d.x + w.n * d.z; return SIMD3(q.x, d.y, q.y) }
    let nLocal = simd_normalize(SIMD3<Float>(sin(giro), 0, cos(giro)))
    let origen = mundo(SIMD3(xMid, origenAlto, 0.003))
    guard let cara = caraDada ?? C.Cara.desde(punto: origen, normal: mundoDir(nLocal), telefono: mundo(SIMD3(xMid, 1, 1))) else { fatalError("cara") }
    let cuadros = Int(k.segundos * 5)
    var deriva = SIMD3<Float>(repeating: 0)
    let xa = k.desdeX ?? k.margen, xb = k.hastaX ?? (L - k.margen)
    for c in 0..<cuadros {
        let f = Float(c) / Float(max(cuadros - 1, 1))
        let fase = Float(c) * 0.35
        let pitch = (k.inclinacionMin + (k.inclinacionMax - k.inclinacionMin) * (0.5 + 0.5 * sin(fase))) * .pi / 180
        // Al llegar a cada punta voltea a ver la esquina (si camina hasta ella).
        func liso(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(1, max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t) }
        var yawG = 8 * sin(Float(c) * 0.21)
        if k.desdeX == nil { yawG -= k.voltea * (1 - liso(0, 0.16, f)) }
        if k.hastaX == nil { yawG += k.voltea * liso(0.84, 1, f) }
        let yaw = yawG * .pi / 180
        let camL = SIMD3<Float>(xa + (xb - xa) * f + 0.05 * sin(Float(c) * 0.5), k.altura + 0.04 * sin(Float(c) * 0.8), k.distancia + 0.08 * sin(Float(c) * 0.13))
        let cam = mundo(camL)
        deriva += SIMD3(gauss(), gauss(), gauss()) * k.deriva
        let adelL = SIMD3<Float>(sin(yaw) * cos(pitch), -sin(pitch), -cos(yaw) * cos(pitch))
        let adelante = mundoDir(adelL)
        let derecha = simd_normalize(simd_cross(adelante, SIMD3(0, 1, 0)))
        let arriba = simd_cross(derecha, adelante)
        let a1 = gauss() * 0.0015, a2 = gauss() * 0.0015, a3 = gauss() * 0.0012
        let p1 = azar(), p2 = azar(), p3 = azar()
        var rangos = [Float](repeating: .nan, count: k.ancho * k.alto)
        var dirs = [SIMD3<Float>](repeating: .zero, count: k.ancho * k.alto)
        for j in 0..<k.alto { for i in 0..<k.ancho {
            let hx = tan((Float(i) / Float(k.ancho - 1) - 0.5) * k.fovH * .pi / 180)
            let vy = tan((0.5 - Float(j) / Float(k.alto - 1)) * k.fovV * .pi / 180)
            let d = simd_normalize(adelante + derecha * hx + arriba * vy)
            dirs[j * k.ancho + i] = d
            if let t = casa.lanzar(cam, d) { rangos[j * k.ancho + i] = t }
        } }
        var puntos: [SIMD3<Float>] = []
        for j in 0..<k.alto { for i in 0..<k.ancho {
            let k2 = j * k.ancho + i
            var r = rangos[k2]
            guard r.isFinite, r < 5 else { continue }
            var vecino: Float? = nil
            for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let ii = i + di, jj = j + dj
                guard ii >= 0, ii < k.ancho, jj >= 0, jj < k.alto else { continue }
                let rv = rangos[jj * k.ancho + ii]
                if rv.isFinite, abs(rv - r) > 0.03 { vecino = rv; break }
            }
            if let v = vecino { if azar() < 0.75 { continue }; r += (v - r) * azar() }
            r += a1 * sin(2 * .pi * (Float(i) / Float(k.ancho) * 1.7 + p1)) + a2 * sin(2 * .pi * (Float(j) / Float(k.alto) * 1.3 + p2))
                + a3 * sin(2 * .pi * (Float(i + j) / Float(k.ancho) * 2.1 + p3)) + gauss() * 0.0015
            puntos.append(cam + dirs[k2] * r + deriva)
        } }
        comp.votar(camara: cam + deriva, puntos: puntos, cara: cara)
    }
    return (comp.resultado(), comp, xMid)
}

func pies(_ m: Float) -> String {
    let inT = (m / pulg).rounded()
    let f = Int(inT / 12), i = Int(inT) - f * 12
    return "\(f)'-\(i)\""
}
func describir(_ r: C.Resultado, xMid: Float) -> String {
    let t = r.tramos.map { "[\(pies($0.uIni + xMid)) → \(pies($0.uFin + xMid)), alto \(pies($0.alto)), \(String(format: "%.1f", $0.area / (pie * pie))) SF]" }.joined(separator: " ")
    return "\(t.isEmpty ? "(nada)" : t) · total \(String(format: "%.1f", r.area / (pie * pie))) SF · studs \(r.separacionStuds.map { "\(Int($0))" } ?? "no") · alarmas \(r.alarmas)"
}

let modo = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "crudo"
let L: Float = 14 * pie, D: Float = 12 * pie

struct CasoCasa { var nombre: String; var casa: Casa; var camino = Camino(); var origenAlto: Float = 1.10; var verdad: [Corte] }
var casos: [CasoCasa] = []
func agregar(_ nombre: String, _ cortes: [Corte], camino: Camino = Camino(), origenAlto: Float = 1.10, ajustar: (inout ParedCasa) -> Void = { _ in }) {
    var casa = Casa.cuarto(L: L, D: D)
    casa.paredes[0].cortes = cortes
    ajustar(&casa.paredes[0])
    casos.append(CasoCasa(nombre: nombre, casa: casa, camino: camino, origenAlto: origenAlto, verdad: cortes))
}
agregar("A. de la esquina izquierda a la mitad (0 → 6 ft, 2 ft)", [Corte(x0: 0, x1: 6 * pie, alto: 2 * pie)])
agregar("B. de la mitad a la esquina derecha (8 → 14 ft, 2 ft)", [Corte(x0: 8 * pie, x1: L, alto: 2 * pie)])
agregar("C. en medio (3 → 11 ft, 2 ft)", [Corte(x0: 3 * pie, x1: 11 * pie, alto: 2 * pie)])
agregar("D. de esquina a esquina (2 ft)", [Corte(x0: 0, x1: L, alto: 2 * pie)])
agregar("E. dos cortes en la misma pared (0 → 4 y 8 → 12 ft)", [Corte(x0: 0, x1: 4 * pie, alto: 2 * pie), Corte(x0: 8 * pie, x1: 12 * pie, alto: 2 * pie)])
agregar("F. escalón: 2 ft de 0 → 6, 4 ft de 6 → 10", [Corte(x0: 0, x1: 6 * pie, alto: 2 * pie), Corte(x0: 6 * pie, x1: 10 * pie, alto: 4 * pie)],
        camino: { var k = Camino(); k.distancia = 1.5; k.altura = 1.15; k.inclinacionMin = 0; k.inclinacionMax = 32; return k }(), origenAlto: 1.55)
agregar("G. termina a 1 ft de la esquina (0 → 13 ft)", [Corte(x0: 0, x1: 13 * pie, alto: 2 * pie)])
agregar("H. termina en el centro de un stud (0 → 5'-4\")", [Corte(x0: 0, x1: 64 * pulg, alto: 2 * pie)])
agregar("I. con puerta de 3 ft (6 → 9 ft): corte a los dos lados", [Corte(x0: 0, x1: 6 * pie, alto: 2 * pie), Corte(x0: 9 * pie, x1: L, alto: 2 * pie)]) { $0.puertas = [Puerta(x0: 6 * pie, x1: 9 * pie)] }
agregar("J. corte de 4 ft bajo una ventana (sill 3 ft, 5 → 9 ft)", [Corte(x0: 2 * pie, x1: 12 * pie, alto: 4 * pie)],
        camino: { var k = Camino(); k.distancia = 1.5; k.altura = 1.15; k.inclinacionMin = 0; k.inclinacionMax = 32; return k }(), origenAlto: 1.55) {
    $0.ventanas = [Ventana(x0: 5 * pie, x1: 9 * pie, y0: 3 * pie, y1: 7 * pie)]
}
agregar("K. no caminó hasta la esquina derecha (llega a 9 ft), corte 0 → 14", [Corte(x0: 0, x1: L, alto: 2 * pie)],
        camino: { var k = Camino(); k.hastaX = 9 * pie; return k }())
agregar("L. esquina con 3 studs (corte 0 → 6 ft)", [Corte(x0: 0, x1: 6 * pie, alto: 2 * pie)]) { $0.esquina = 4.5 * pulg }
agregar("M. termina a 4 in de la esquina (queda una tira de drywall)", [Corte(x0: 4 * pulg, x1: 7 * pie, alto: 2 * pie)])
agregar("N. pedazo chico de 2 ft en medio", [Corte(x0: 6 * pie, x1: 8 * pie, alto: 2 * pie)])
agregar("O. pared de afuera 2x6, de la esquina a la mitad", [Corte(x0: 0, x1: 9 * pie, alto: 2 * pie)]) { $0.marco = 5.5 * pulg }
agregar("P. corte de 4 ft de esquina a esquina", [Corte(x0: 0, x1: L, alto: 4 * pie)],
        camino: { var k = Camino(); k.distancia = 1.5; k.altura = 1.15; k.inclinacionMin = 0; k.inclinacionMax = 32; return k }(), origenAlto: 1.55)
agregar("Q. CONTROL: nada demolido", [])
agregar("R. termina a la mitad entre dos studs (0 → 6'-8\")", [Corte(x0: 0, x1: 80 * pulg, alto: 2 * pie)])

// La verdad de un caso, sin lo que tapa la puerta/ventana: el área de drywall quitado.
func areaVerdad(_ c: CasoCasa) -> Float {
    let w = c.casa.paredes[0]
    var a: Float = 0
    for k in c.verdad {
        a += (k.x1 - k.x0) * k.alto
        for v in w.ventanas { let dx = max(0, min(k.x1, v.x1) - max(k.x0, v.x0)), dy = max(0, min(k.alto, v.y1) - v.y0); a -= dx * dy }
    }
    return a
}

if modo == "crudo" { for c in casos {
    print("\n" + c.nombre)
    print("   verdad: " + c.verdad.map { "[\(pies($0.x0)) → \(pies($0.x1)), alto \(pies($0.alto))]" }.joined(separator: " ") + String(format: " · %.1f SF", areaVerdad(c) / (pie * pie)))
    for s in 1...2 {
        semilla = UInt64(0xCA5A + s * 7919)
        let (r, _, xMid) = barrer(c.casa, pared: 0, camino: c.camino, origenAlto: c.origenAlto)
        print("   láser\(s): " + describir(r, xMid: xMid))
    }
} }

// ---- DEPURAR: las columnas cerca de cada esquina ----
func letra(_ c: C.Columna) -> String {
    switch c { case .noVista: return "·"; case .entera: return "E"; case .ambigua: return "a"; case .tapada: return "T"
    case .sinOrilla: return "s"; case .cortada(let h): return h > 1.15 ? "4" : (h > 0.8 ? "3" : (h > 0.5 ? "2" : "1")); case .alarma: return "!"; case .bajoAbertura: return "v" }
}
if modo == "columnas" {
    for (i, c) in casos.enumerated() where ["A", "B", "F", "L", "J", "D"].contains(String(c.nombre.prefix(1))) {
        semilla = UInt64(0xCA5A + 1 * 7919)
        let (r, comp, xMid) = barrer(c.casa, pared: 0, camino: c.camino, origenAlto: c.origenAlto)
        _ = i
        // columna -> x en la pared
        var linea = ""
        for (k, col) in r.columnas.enumerated() {
            let x = C.uDeColumna(r.colIni + k) + xMid
            if x < -0.3 || x > L + 0.3 { continue }
            linea += letra(col)
        }
        let x0 = C.uDeColumna(r.colIni) + xMid
        print(c.nombre.prefix(2) + String(format: " (empieza x=%.1f in): ", x0 / pulg) + linea)
        _ = comp
    }
}
if modo == "celdas" {
    let c = casos[1]
    semilla = UInt64(0xCA5A + 1 * 7919)
    let (r, comp, xMid) = barrer(c.casa, pared: 0, camino: c.camino, origenAlto: c.origenAlto)
    let piso = comp.pisoRef!
    let r0 = C.renglonDe(piso)!
    for (k, col) in r.columnas.enumerated() {
        let x = C.uDeColumna(r.colIni + k) + xMid
        guard x > 120 * pulg, x < 136 * pulg else { continue }
        var s = ""
        for rr in r0..<(r0 + 16) {
            switch comp.estado(r.colIni + k, rr) { case .noVisto: s += "·"; case .sigue: s += "S"; case .ambiguo: s += "a"; case .cavidad: s += "c"; case .hondo: s += "H"; case .tapado: s += "T" }
        }
        var vs = comp.votosDe(C.indice(r.colIni + k, r0 + 2)); let m = C.mediana(&vs)
        print(String(format: "x=%.1f in %@  %@   mediana fila2 %.2f in, votos %d", x / pulg, letra(col), s, m, vs.count))
    }
}

// ================== CON LA UBICACIÓN EN EL PLANO ==================
// La verdad en pedazos: cada corte, y bajo una ventana su alto baja hasta el antepecho.
struct Pieza { var x0: Float; var x1: Float; var alto: Float }
func piezas(_ c: CasoCasa) -> [Pieza] {
    let w = c.casa.paredes[0]
    var out: [Pieza] = []
    for k in c.verdad {
        var cortesX = [k.x0, k.x1]
        for v in w.ventanas where v.y0 < k.alto { for x in [v.x0, v.x1] where x > k.x0 && x < k.x1 { cortesX.append(x) } }
        cortesX.sort()
        for i in 0..<(cortesX.count - 1) {
            let a = cortesX[i], b = cortesX[i + 1], mid = (a + b) / 2
            var h = k.alto
            // Bajo la ventana el drywall llega hasta la solera de la ventana (1.5 in abajo del vidrio).
            for v in w.ventanas where mid > v.x0 && mid < v.x1 && v.y0 - 1.5 * pulg < h { h = v.y0 - 1.5 * pulg }
            if let u = out.last, abs(u.x1 - a) < 1e-4, abs(u.alto - h) < 1e-4 { out[out.count - 1].x1 = b } else { out.append(Pieza(x0: a, x1: b, alto: h)) }
        }
    }
    return out
}
typealias P = DemolicionEnPlano
var pasan = 0, fallan = 0
func ok(_ l: String, _ c: Bool, _ d: String = "") { if c { pasan += 1; print("  ok  " + l) } else { fallan += 1; print("  FALLA " + l + "  " + d) } }

struct Corrida { var rep: P.Reporte; var pared: Int?; var errEsqA: Float; var errEsqB: Float; var afinadas: Int; var comp: C? = nil; var esq: P.Esquinas? = nil }
func conPlano(_ c: CasoCasa, semillaN: Int, refinar: Bool = true, ip: Int = 0, camino: Camino? = nil, errGrados: Double = 1, errPies: Double = 0.25) -> Corrida {
    semilla = UInt64(0xB0CA + semillaN * 7919)
    let gV = 0.6, mV = SIMD2<Double>(20, -7)            // el plano de la casa: girado y movido respecto a ARKit
    let verdad = P.Acomodo2D(giro: gV, mov: mV)
    // La ubicación con su error de siempre: 1° y 0.25 ft. El ubicador acomoda las paredes que ve, así que su error de giro
    // es alrededor del cuarto (no del origen de ARKit, que puede estar en otro cuarto): se gira alrededor del centro.
    let centroAR = SIMD2<Float>(L / 2, D / 2)
    let centroPlano = P.alPlano(centroAR, verdad)
    let gE = gV + Double(gauss()) * errGrados * .pi / 180
    let girado = P.girar(SIMD2(Double(centroAR.x), Double(centroAR.y)) * P.piesPorMetro, gE)
    let est = P.Acomodo2D(giro: gE, mov: centroPlano - girado + SIMD2(Double(gauss()), Double(gauss())) * errPies)
    let paredesPlano = c.casa.paredes.enumerated().map { (i, w) in
        P.Pared(a: P.alPlano(w.a, verdad), b: P.alPlano(w.b, verdad), exterior: i <= 1)
    }
    // Los planos de ARKit de cada pared: medio grado torcidos, 3 mm corridos, el centro en algún lugar de la pared.
    let planos = c.casa.paredes.map { w -> P.PlanoAR in
        let t = 0.3 + 0.4 * azar()
        let q = w.a + (w.b - w.a) * t + w.n * 0.003
        let g = (azar() < 0.5 ? -1 : 1) * Float(0.5 * .pi / 180)
        let n2 = SIMD2(cos(g) * w.n.x - sin(g) * w.n.y, sin(g) * w.n.x + cos(g) * w.n.y)
        return P.PlanoAR(punto: SIMD3(q.x, 1.5, q.y), normal: SIMD3(n2.x, 0, n2.y))
    }
    let w = c.casa.paredes[ip]
    let elegida = P.paredDe(planos[ip], paredes: paredesPlano, acomodo: est)
    let mid = (w.a + w.b) / 2 + w.n * 1.2
    guard let idx = elegida, let cara = P.cara(para: paredesPlano[idx], plano: planos[ip], acomodo: est, pisoY: gauss() * 0.01,
                                                telefono: SIMD3(mid.x, 1, mid.y)) else {
        return Corrida(rep: P.Reporte(), pared: elegida, errEsqA: 99, errEsqB: 99, afinadas: 0)
    }
    let (_, comp, _) = barrer(c.casa, pared: ip, camino: camino ?? c.camino, origenAlto: c.origenAlto, cara: cara)
    let otros = refinar ? planos.enumerated().filter { $0.offset != ip }.map { $0.element } : []
    let esq = P.esquinas(cara, pared: paredesPlano[idx], acomodo: est, otros: otros)
    // Las puertas y ventanas del plano (en pies, con la ubicación verdadera: así las dibujó el escáner).
    let aberts = w.puertas.map { P.Abertura(centro: P.alPlano(w.a + w.ex * (($0.x0 + $0.x1) / 2), verdad), ancho: Double($0.x1 - $0.x0) * P.piesPorMetro, esPuerta: true) }
        + w.ventanas.map { P.Abertura(centro: P.alPlano(w.a + w.ex * (($0.x0 + $0.x1) / 2), verdad), ancho: Double($0.x1 - $0.x0) * P.piesPorMetro, esPuerta: false) }
    let enCara = P.aberturasEnCara(cara, pared: paredesPlano[idx], aberturas: aberts, acomodo: est)
    let rep = P.reporte(comp, esquinas: esq, pared: paredesPlano[idx], ventanas: enCara.ventanas, puertas: enCara.puertas)
    // El error de las esquinas (u verdadera de las esquinas de la pared).
    func uVerdad(_ q: SIMD2<Float>) -> Float { simd_dot(SIMD3(q.x, cara.origen.y, q.y) - cara.origen, cara.u) }
    let ua = uVerdad(w.a), ub = uVerdad(w.b)
    let errA = abs(esq.uDeA - ua), errB = abs((esq.uDeA == esq.u.lowerBound ? esq.u.upperBound : esq.u.lowerBound) - ub)
    return Corrida(rep: rep, pared: elegida, errEsqA: errA, errEsqB: errB, afinadas: esq.afinadas, comp: comp, esq: esq)
}
func texto(_ r: P.Reporte) -> String {
    let t = r.tramos.map { "[\(pies($0.desde))\($0.hastaEsquinaA ? "⌐" : "") → \(pies($0.hasta))\($0.hastaEsquinaB ? "¬" : ""), alto \(pies($0.alto)), \(String(format: "%.1f", $0.area / (pie * pie))) SF]" }.joined(separator: " ")
    let f = r.faltaVer.map { "\(pies($0.lowerBound))–\(pies($0.upperBound))" }.joined(separator: ", ")
    return "\(t.isEmpty ? "(nada)" : t) · \(String(format: "%.1f", r.area / (pie * pie))) SF\(f.isEmpty ? "" : " · falta ver " + f)"
}
func evaluar(_ c: CasoCasa, _ r: Corrida, etiqueta: String, tolPunta: Float = 3 * pulg) {
    let verdad = piezas(c)
    let areaV = verdad.reduce(Float(0)) { $0 + ($1.x1 - $1.x0) * $1.alto }
    ok("\(etiqueta): escoge la pared correcta del plano", r.pared == 0)
    var problemas: [String] = []
    for v in verdad {
        guard let t = r.rep.tramos.first(where: { min($0.hasta, v.x1) - max($0.desde, v.x0) > 0.1 }) else { problemas.append("falta \(pies(v.x0))→\(pies(v.x1))"); continue }
        if abs(t.desde - v.x0) > tolPunta { problemas.append("empieza \(pies(t.desde)) (verdad \(pies(v.x0)))") }
        if abs(t.hasta - v.x1) > tolPunta { problemas.append("termina \(pies(t.hasta)) (verdad \(pies(v.x1)))") }
        if abs(t.alto - v.alto) > 1.5 * pulg { problemas.append("alto \(pies(t.alto)) (verdad \(pies(v.alto)))") }
    }
    for t in r.rep.tramos where !verdad.contains(where: { min(t.hasta, $0.x1) - max(t.desde, $0.x0) > 0.1 }) { problemas.append("sobra \(pies(t.desde))→\(pies(t.hasta))") }
    ok("\(etiqueta): cada pedazo empieza y termina a ±\(Int(tolPunta / pulg)) in y su alto a ±1.5 in", problemas.isEmpty, problemas.joined(separator: "; "))
    let errA = areaV > 0 ? (r.rep.area - areaV) / areaV : (r.rep.area > 0 ? 1 : 0)
    ok("\(etiqueta): área entre -6% y +3% (\(String(format: "%.1f", r.rep.area / (pie * pie))) vs \(String(format: "%.1f", areaV / (pie * pie))) SF, \(String(format: "%+.1f", errA * 100))%)",
       areaV > 0 ? (errA >= -0.06 && errA <= 0.03) : r.rep.area == 0)
}

if modo == "plano" {
    print("\nCON LA UBICACIÓN (3 semillas por caso, error de ubicación 1° y 0.25 ft al azar)")
    for c in casos {
        print("\n" + c.nombre + "   verdad: " + piezas(c).map { "[\(pies($0.x0)) → \(pies($0.x1)), alto \(pies($0.alto))]" }.joined(separator: " "))
        for s in 1...3 {
            let r = conPlano(c, semillaN: s)
            print("   \(s): " + texto(r.rep) + String(format: " · esquinas a ±%.2f / ±%.2f in (afinadas %d)", r.errEsqA / pulg, r.errEsqB / pulg, r.afinadas))
            if c.nombre.hasPrefix("K.") {
                ok("K.\(s): dice que falta ver hasta la esquina derecha", r.rep.faltaVer.contains { $0.upperBound > L - 6 * pulg && $0.lowerBound < 11 * pie })
                ok("K.\(s): lo que sí vio empieza en la esquina y no inventa lo que no vio", r.rep.tramos.first.map { $0.desde < 1 * pulg && $0.hasta < 10.6 * pie } ?? false)
            } else {
                evaluar(c, r, etiqueta: "\(c.nombre.prefix(1)).\(s)")
            }
        }
    }
    // ---- Más difícil ----
    print("\nMÁS DIFÍCIL")
    let cA = casos.first { $0.nombre.hasPrefix("A.") }!, cD = casos.first { $0.nombre.hasPrefix("D.") }!
    for s in 1...3 {
        let r = conPlano(cA, semillaN: s, errGrados: 2, errPies: 0.5)
        print("   ubicación con el doble de error (2°, 0.5 ft) .\(s): " + texto(r.rep) + String(format: " · esquinas ±%.2f/±%.2f in", r.errEsqA / pulg, r.errEsqB / pulg))
        evaluar(cA, r, etiqueta: "A con doble error.\(s)")
        ok("A con doble error.\(s): las esquinas a ±1.5 in (las afinan los planos de al lado)", r.errEsqA < 1.5 * pulg && r.errEsqB < 1.5 * pulg)
    }
    for s in 1...3 {
        let r = conPlano(cD, semillaN: s, refinar: false)
        print("   sin ver las paredes de al lado .\(s): " + texto(r.rep))
        let areaV = 28 * pie * pie
        ok("D sin paredes de al lado.\(s): no se lleva el corte a una esquina que no se afinó (nunca cobra de más)", r.rep.area <= areaV * 1.0 && !(r.rep.tramos.first?.hastaEsquinaA ?? false))
        ok("D sin paredes de al lado.\(s): pero mide lo que vio (más de 95%)", r.rep.area >= areaV * 0.95)
    }
    // El corte dobla la esquina: la pared OESTE (de (0,D) a (0,0)) cortada sus últimos 5 ft, pegada al corte de la sur.
    var casaW = Casa.cuarto(L: L, D: D)
    casaW.paredes[0].cortes = [Corte(x0: 0, x1: 6 * pie, alto: 2 * pie)]
    casaW.paredes[3].cortes = [Corte(x0: D - 5 * pie, x1: D, alto: 2 * pie)]
    let cW = CasoCasa(nombre: "W", casa: casaW, verdad: [Corte(x0: D - 5 * pie, x1: D, alto: 2 * pie)])
    for s in 1...3 {
        let r = conPlano(cW, semillaN: s, ip: 3)
        print("   la pared de al lado, el corte dobla la esquina .\(s): " + texto(r.rep))
        ok("W.\(s): escoge la pared oeste", r.pared == 3)
        let t = r.rep.tramos
        ok("W.\(s): un pedazo de 5 ft (±3 in) que llega a la esquina", t.count == 1 && abs((t[0].hasta - t[0].desde) - 5 * pie) <= 3 * pulg && t[0].hastaEsquinaB,
           texto(r.rep))
    }
    print("\n  \(pasan) pasan, \(fallan) fallan")
    exit(fallan == 0 ? 0 : 1)
}

if modo == "plano-col" {
    let quien = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "IJMP"
    for c in casos where quien.contains(c.nombre.prefix(1)) {
        for sN in 1...3 {
            let r = conPlano(c, semillaN: sN)
            guard let comp = r.comp, let e = r.esq else { continue }
            let w0 = c.casa.paredes[0]
            let paredesPlano0 = P.Pared(a: SIMD2(0, 0), b: SIMD2(1, 0), exterior: true)
            _ = paredesPlano0; _ = w0
            let res = comp.resultado(limites: e.limites)
            var linea = ""
            for (k, col) in res.columnas.enumerated() {
                let u = C.uDeColumna(res.colIni + k)
                guard u >= e.u.lowerBound - 0.05, u <= e.u.upperBound + 0.05 else { continue }
                linea += letra(col)
            }
            print("\(c.nombre.prefix(1)).\(sN): \(linea)")
        }
    }
}
if modo == "plano-celdas" {
    let quien = CommandLine.arguments[2], sN = Int(CommandLine.arguments[3]) ?? 1
    let desdeIn = Float(CommandLine.arguments[4]) ?? 0, hastaIn = Float(CommandLine.arguments[5]) ?? 24
    let c = casos.first { $0.nombre.hasPrefix(quien) }!
    let r = conPlano(c, semillaN: sN)
    let comp = r.comp!, e = r.esq!
    print(String(format: "desvío %.3f in, pendiente %.3f in/m, piso %.3f", comp.desvio, comp.pendiente, comp.pisoRef ?? -99))
    let piso = comp.pisoRef!
    let r0 = C.renglonDe(piso)!
    let aEsMenor = abs(e.uDeA - e.u.lowerBound) <= abs(e.uDeA - e.u.upperBound)
    var col = C.columnaDe(e.u.lowerBound)!
    while C.uDeColumna(col) < e.u.upperBound {
        let u = C.uDeColumna(col)
        let x = aEsMenor ? u - e.u.lowerBound : e.u.upperBound - u
        if x >= desdeIn * pulg && x <= hastaIn * pulg {
            var s = ""
            for rr in r0..<(r0 + 34) {
                switch comp.estado(col, rr) { case .noVisto: s += "·"; case .sigue: s += "S"; case .ambiguo: s += "a"; case .cavidad: s += "c"; case .hondo: s += "H"; case .tapado: s += "T" }
            }
            var vs = comp.votosDe(C.indice(col, r0 + 30)); let m = C.mediana(&vs)
            print(String(format: "x=%6.1f in  %@  fila30 mediana %.2f in (%d votos)", x / pulg, s, m, vs.count))
        }
        col += 1
    }
}
if modo == "plano-camino" {
    // P con otras formas de caminar: ¿es el ángulo con que se ve la esquina?
    let c = casos.first { $0.nombre.hasPrefix("P") }!
    for (nom, dist, alt, marg, volt, incMin, incMax) in [("1.5 m lejos (igual)", Float(1.5), Float(1.15), Float(0.45), Float(38), Float(0), Float(32)),
                                                     ("1.2 m, 1.15 alto", 1.2, 1.15, 0.45, 38, 0, 32),
                                                     ("1.0 m, se acerca a 0.3 de la esquina", 1.0, 1.15, 0.3, 25, 0, 35),
                                                     ("1.5 m pero termina de frente a la esquina", 1.5, 1.15, 0.25, 15, 0, 32)] {
        var k = c.camino; k.distancia = dist; k.altura = alt; k.margen = marg; k.voltea = volt; k.inclinacionMin = incMin; k.inclinacionMax = incMax
        for s in 1...3 { let r = conPlano(c, semillaN: s, camino: k); print("\(nom).\(s): " + texto(r.rep)) }
    }
}
if modo == "plano-votos" {
    let c = casos.first { $0.nombre.hasPrefix("P") }!
    let r = conPlano(c, semillaN: 1)
    let comp = r.comp!, e = r.esq!
    let r0 = C.renglonDe(comp.pisoRef!)!
    for xIn in [Float(141), 147, 153, 157] {
        let u = e.u.upperBound - xIn * pulg >= e.u.lowerBound ? (abs(e.uDeA - e.u.lowerBound) < 0.01 ? e.u.lowerBound + xIn * pulg : e.u.upperBound - xIn * pulg) : 0
        let col = C.columnaDe(u)!
        for rr in [r0 + 6, r0 + 12, r0 + 18, r0 + 22] {
            let vs = comp.votosDe(C.indice(col, rr)).map { String(format: "%.1f", $0) }.joined(separator: " ")
            print(String(format: "x=%.0f in, %.0f in del piso: ", xIn, Float(rr - r0) * 2) + vs)
        }
    }
}

if modo == "estadistica" {
    let N = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 10 : 10
    print("ESTADÍSTICA: \(N) corridas por caso (error de ubicación 1° y 0.25 ft, ruido del láser distinto cada vez)")
    print("caso | área: peor de menos / promedio / peor de más | puntas: dentro de ±3 in | peor punta")
    var todasMas: Float = 0
    for c in casos where !c.nombre.hasPrefix("K.") {
        let verdad = piezas(c)
        let areaV = verdad.reduce(Float(0)) { $0 + ($1.x1 - $1.x0) * $1.alto }
        var errs: [Float] = [], puntasBien = 0, puntas = 0, peor: Float = 0
        for sN in 1...N {
            let r = conPlano(c, semillaN: 100 + sN)
            errs.append(areaV > 0 ? (r.rep.area - areaV) / areaV : r.rep.area / (pie * pie))
            var mala = false
            for v in verdad {
                // El pedazo que más se encima con la verdad (no el primero que la toca).
                guard let t = r.rep.tramos.max(by: { min($0.hasta, v.x1) - max($0.desde, v.x0) < min($1.hasta, v.x1) - max($1.desde, v.x0) }),
                      min(t.hasta, v.x1) - max(t.desde, v.x0) > 0.1 else { puntas += 2; peor = max(peor, v.x1 - v.x0); mala = true; continue }
                for d in [t.desde - v.x0, t.hasta - v.x1] { puntas += 1; if abs(d) <= 3 * pulg { puntasBien += 1 } else if abs(d) > 6 * pulg { mala = true }; peor = max(peor, abs(d)) }
            }
            if mala && CommandLine.arguments.count > 3 { print("      corrida \(sN): " + texto(r.rep)) }
        }
        let mn = errs.min() ?? 0, mx = errs.max() ?? 0, pr = errs.reduce(0, +) / Float(max(errs.count, 1))
        if areaV > 0 { todasMas = max(todasMas, mx) }
        let nom = String(c.nombre.prefix(42)).padding(toLength: 42, withPad: " ", startingAt: 0)
        if areaV > 0 {
            print(String(format: "%@ | %+5.1f%% / %+5.1f%% / %+5.1f%% | %3d de %3d | %4.1f in", nom, mn * 100, pr * 100, mx * 100, puntasBien, puntas, peor / pulg))
        } else {
            print(String(format: "%@ | control: peor %.2f SF de más", nom, mx))
        }
    }
    print(String(format: "Lo PEOR de más en todos los casos con corte: %+.1f%%", todasMas * 100))
}

if modo == "ventana-col" {
    // Las columnas de la ventana, ANTES del puente (lo que ve el comparador por columna).
    let c = casos.first { $0.nombre.hasPrefix("J.") }!
    for sN in [101, 102, 103, 109] {
        let r = conPlano(c, semillaN: sN)
        guard let comp = r.comp, let e = r.esq else { continue }
        let piso = comp.pisoRef!
        var linea = ""
        var u = e.u.lowerBound + C.celda / 2
        while u < e.u.upperBound {
            if let col = C.columnaDe(u) { linea += letra(comp.columna(col, piso: piso)) }
            u += C.celda
        }
        print("J.\(sN) crudo: " + linea)
    }
}
if modo == "una-col" {
    let quien = CommandLine.arguments[2], sN = Int(CommandLine.arguments[3])!
    let c = casos.first { $0.nombre.hasPrefix(quien) }!
    let r = conPlano(c, semillaN: sN)
    let comp = r.comp!, e = r.esq!
    let piso = comp.pisoRef!
    var crudo = "", final = ""
    let res = comp.resultado(limites: e.limites)
    var u = e.u.lowerBound + C.celda / 2
    while u < e.u.upperBound {
        if let col = C.columnaDe(u) {
            crudo += letra(comp.columna(col, piso: piso))
            let k = col - res.colIni
            final += k >= 0 && k < res.columnas.count ? letra(res.columnas[k]) : " "
        }
        u += C.celda
    }
    print("crudo: " + crudo); print("final: " + final); print(texto(r.rep))
}
if modo == "escalon" {
    let c = casos.first { $0.nombre.hasPrefix(CommandLine.arguments[2]) }!
    let r = conPlano(c, semillaN: Int(CommandLine.arguments[3])!)
    let res = r.comp!.resultado(limites: r.esq!.limites)
    var altos: [Float] = []
    for col in res.columnas { if case .cortada(let h) = col { altos.append(h) } else if !altos.isEmpty { break } }
    print(altos.map { String(format: "%.0f", $0 / pulg) }.joined(separator: " "))
    print("escalones: \(C.escalones(altos))")
}

// ================== LA PRUEBA (lo que corre tests/demolicion_casa_test.sh) ==================
// Reglas del lado peligroso (nunca cobrar de más) y del lado útil (que mida), sobre varias corridas por caso con error
// de ubicación y ruido distintos. Los límites conocidos están escritos con su número.
if modo == "prueba" {
    let N = 6
    print("\nLO DEMOLIDO EN UNA CASA 3D, CON LA UBICACIÓN: \(N) corridas por caso")
    for c in casos where !c.nombre.hasPrefix("K.") {
        let verdad = piezas(c)
        let areaV = verdad.reduce(Float(0)) { $0 + ($1.x1 - $1.x0) * $1.alto }
        var errs: [Float] = [], bien = 0, puntas = 0, paredOk = true
        for sN in 1...N {
            let r = conPlano(c, semillaN: 200 + sN)
            if r.pared != 0 { paredOk = false }
            errs.append(areaV > 0 ? (r.rep.area - areaV) / areaV : r.rep.area)
            for v in verdad {
                guard let t = r.rep.tramos.max(by: { min($0.hasta, v.x1) - max($0.desde, v.x0) < min($1.hasta, v.x1) - max($1.desde, v.x0) }),
                      min(t.hasta, v.x1) - max(t.desde, v.x0) > 0.1 else { puntas += 2; continue }
                for d in [t.desde - v.x0, t.hasta - v.x1] { puntas += 1; if abs(d) <= 3 * pulg { bien += 1 } }
            }
        }
        let letraC = String(c.nombre.prefix(1))
        let mx = errs.max() ?? 0, pr = errs.reduce(0, +) / Float(N)
        print(String(format: "  [%@] área: promedio %+.1f%%, peor de más %+.1f%% · puntas a ±3 in: %d de %d", c.nombre, pr * 100, mx * 100, bien, puntas))
        ok("\(letraC): escoge la pared correcta en las \(N)", paredOk)
        if areaV == 0 { ok("\(letraC): CONTROL, 0 pies en las \(N)", mx == 0); continue }
        // El límite conocido: una tira de drywall de 4 in o menos pegada a la esquina se confunde con el stud de la esquina.
        let topeMas: Float = letraC == "M" ? 0.05 : 0.03
        ok("\(letraC): nunca cobra más de \(Int(topeMas * 100))% de más", mx <= topeMas)
        // Un pedazo chico (2 ft) pierde más en porcentaje con la misma pulgada de menos en cada punta.
        // Dos cortes de 4 ft con 4 puntas a media pared (E) igual.
        let minProm: Float = letraC == "N" ? -0.08 : (letraC == "M" || letraC == "E" ? -0.06 : -0.04)
        ok("\(letraC): en promedio mide la verdad a \(Int(-minProm * 100))% o menos de diferencia", pr >= minProm)
        let minPuntas = letraC == "J" ? 0.75 : (letraC == "M" ? 0.6 : 0.85)
        ok("\(letraC): las puntas a ±3 in en el \(Int(minPuntas * 100))% o más", Float(bien) >= Float(puntas) * Float(minPuntas))
    }
    let cK = casos.first { $0.nombre.hasPrefix("K.") }!
    for s in 1...3 {
        let r = conPlano(cK, semillaN: 200 + s)
        ok("K.\(s): dice que falta ver hasta la esquina derecha", r.rep.faltaVer.contains { $0.upperBound > L - 6 * pulg && $0.lowerBound < 11 * pie })
        ok("K.\(s): lo que vio empieza en la esquina y no inventa lo que no vio", r.rep.tramos.first.map { $0.desde < 1 * pulg && $0.hasta < 10.6 * pie } ?? false)
    }
    let cA = casos.first { $0.nombre.hasPrefix("A.") }!, cD = casos.first { $0.nombre.hasPrefix("D.") }!
    for s in 1...3 {
        let r = conPlano(cA, semillaN: 200 + s, errGrados: 2, errPies: 0.5)
        ok("doble error de ubicación (2°, 0.5 ft).\(s): escoge la pared y afina las esquinas a ±1.5 in", r.pared == 0 && r.errEsqA < 1.5 * pulg && r.errEsqB < 1.5 * pulg)
        let rD = conPlano(cD, semillaN: 200 + s, refinar: false)
        ok("sin ver las paredes de al lado.\(s): no lleva el corte a una esquina que no afinó (nunca de más) y mide más del 95%",
           rD.rep.area <= 28 * pie * pie && rD.rep.area >= 28 * pie * pie * 0.95 && !(rD.rep.tramos.first?.hastaEsquinaA ?? false))
    }
    var casaW = Casa.cuarto(L: L, D: D)
    casaW.paredes[0].cortes = [Corte(x0: 0, x1: 6 * pie, alto: 2 * pie)]
    casaW.paredes[3].cortes = [Corte(x0: D - 5 * pie, x1: D, alto: 2 * pie)]
    let cW = CasoCasa(nombre: "W", casa: casaW, verdad: [])
    for s in 1...3 {
        let r = conPlano(cW, semillaN: 200 + s, ip: 3)
        let t = r.rep.tramos
        ok("el corte dobla la esquina, la otra pared.\(s): 5 ft (±3 in) hasta la esquina", r.pared == 3 && t.count == 1 && abs((t[0].hasta - t[0].desde) - 5 * pie) <= 3 * pulg && t[0].hastaEsquinaB)
    }
    print("\n  \(pasan) pasan, \(fallan) fallan")
    exit(fallan == 0 ? 0 : 1)
}
if modo == "res" {
    let c = casos.first { $0.nombre.hasPrefix(CommandLine.arguments[2]) }!
    let r = conPlano(c, semillaN: Int(CommandLine.arguments[3])!)
    let res = r.comp!.resultado(limites: r.esq!.limites)
    print("studs \(res.patronStuds) sep \(String(describing: res.separacionStuds)) tramos \(res.tramos.count) area \(res.area) alarmas \(res.alarmas)")
    for t in res.tramos { print(String(format: "  u %.3f → %.3f, alto %.3f, studs %d", t.uIni, t.uFin, t.alto, t.studs)) }
    print("limites \(r.esq!.limites)")
}

// ================== EL DIBUJO (JSON para tools: una pared por caso, verdad y lo medido) ==================
if modo == "dibujo" {
    var salida: [[String: Any]] = []
    for c in casos where !c.nombre.hasPrefix("Q.") {
        let r = conPlano(c, semillaN: 201)
        let w = c.casa.paredes[0]
        let verdad = piezas(c)
        salida.append([
            "nombre": c.nombre, "largo": Double(L / pie), "alto": Double(8),
            "verdad": verdad.map { ["x0": Double($0.x0 / pie), "x1": Double($0.x1 / pie), "alto": Double($0.alto / pie)] },
            "medido": r.rep.tramos.map { ["x0": Double($0.desde / pie), "x1": Double($0.hasta / pie), "alto": Double($0.alto / pie), "sf": Double($0.area / (pie * pie)), "escA": $0.hastaEsquinaA, "escB": $0.hastaEsquinaB] },
            "faltaVer": r.rep.faltaVer.map { [Double($0.lowerBound / pie), Double($0.upperBound / pie)] },
            "puertas": w.puertas.map { [Double($0.x0 / pie), Double($0.x1 / pie)] },
            "ventanas": w.ventanas.map { [Double($0.x0 / pie), Double($0.x1 / pie), Double($0.y0 / pie), Double($0.y1 / pie)] },
            "sfVerdad": Double(verdad.reduce(Float(0)) { $0 + ($1.x1 - $1.x0) * $1.alto } / (pie * pie)),
            "sfMedido": Double(r.rep.area / (pie * pie)),
        ])
    }
    let d = try! JSONSerialization.data(withJSONObject: salida, options: [.prettyPrinted])
    FileManager.default.createFile(atPath: CommandLine.arguments[2], contents: d)
}
