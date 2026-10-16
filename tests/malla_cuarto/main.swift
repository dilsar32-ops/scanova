import Foundation
import simd

// Banco de la malla por cuarto (16 oct): la ubicación trae un error (giro + movimiento) y el láser ve algunas paredes
// (con ruido, recortadas, más caras de muebles y del cuarto de al lado). ¿Las esquinas de la malla caen donde están?
typealias Ac = DemolicionEnPlano.Acomodo2D
typealias Pared = DemolicionEnPlano.Pared
var semilla: UInt64 = 7
func rnd() -> Double { semilla = semilla &* 6364136223846793005 &+ 1442695040888963407; return Double(semilla >> 11) / Double(1 << 53) }
func gauss(_ s: Double) -> Double { let u = max(1e-9, rnd()), v = rnd(); return s * sqrt(-2 * log(u)) * cos(2 * .pi * v) }

func cuarto(_ pts: [SIMD2<Double>]) -> [Pared] { (0..<pts.count).map { Pared(a: pts[$0], b: pts[($0 + 1) % pts.count], exterior: false, alto: 8) } }
let rect = cuarto([SIMD2(0, 0), SIMD2(14, 0), SIMD2(14, 12), SIMD2(0, 12)])
let ele = cuarto([SIMD2(0, 0), SIMD2(16, 0), SIMD2(16, 8), SIMD2(9, 8), SIMD2(9, 15), SIMD2(0, 15)])
// El cuarto está lejos del origen del plano (como la otra punta de la casa).
func mover(_ ps: [Pared], _ d: SIMD2<Double>) -> [Pared] { ps.map { Pared(a: $0.a + d, b: $0.b + d, exterior: false, alto: 8) } }

// Lo que ve el láser de una pared verdadera: un pedazo (desde f0 hasta f1 de su largo), con ruido.
// `empuje` + = hacia adentro del cuarto (un mueble), - = hacia afuera (la cara del cuarto de al lado, vista desde allá).
var centroVerdad = SIMD2<Double>(0, 0)
func vista(_ w: Pared, _ ac: Ac, f0: Double, f1: Double, ruido: Double = 0.01, empuje: Double = 0, conLado: Bool = true) -> MallaDelCuarto.Vista {
    let a = MallaDelCuarto.ar(w.a, ac), b = MallaDelCuarto.ar(w.b, ac)
    let ni = MallaDelCuarto.adentro(a, b, centroVerdad)
    let p0 = a + (b - a) * f0 + ni * (empuje + gauss(ruido)), p1 = a + (b - a) * f1 + ni * (empuje + gauss(ruido))
    return MallaDelCuarto.Vista(a: p0, b: p1, n: conLado ? (empuje < -0.05 ? -ni : ni) : nil)
}
func ponerCentro(_ ps: [Pared], _ ac: Ac) { let pts = ps.flatMap { [MallaDelCuarto.ar($0.a, ac), MallaDelCuarto.ar($0.b, ac)] }; centroVerdad = pts.reduce(.zero, +) / Double(pts.count) }
// El error de la ubicación: un giro `g` (grados) alrededor de un punto lejos `piv` (pies del plano) y un movimiento (pies).
func malUbicado(_ ac: Ac, grados: Double, piv: SIMD2<Double>, mov: SIMD2<Double>) -> Ac {
    let c = MallaDelCuarto.ar(piv, ac)
    return MallaDelCuarto.componer(ac, th: grados * .pi / 180, t: mov / MallaDelCuarto.k, c: c)
}
func errorEsquinas(_ ps: [Pared], _ verdad: Ac, _ aj: MallaDelCuarto.Ajuste) -> Double {
    var peor = 0.0
    for (i, w) in ps.enumerated() {
        peor = max(peor, simd_distance(aj.paredes[i].a, MallaDelCuarto.ar(w.a, verdad)), simd_distance(aj.paredes[i].b, MallaDelCuarto.ar(w.b, verdad)))
    }
    return peor / 0.0254
}
func errorSinAjuste(_ ps: [Pared], _ verdad: Ac, _ ac: Ac) -> Double {
    ps.flatMap { [simd_distance(MallaDelCuarto.ar($0.a, ac), MallaDelCuarto.ar($0.a, verdad)), simd_distance(MallaDelCuarto.ar($0.b, ac), MallaDelCuarto.ar($0.b, verdad))] }.max()! / 0.0254
}

var fallas = 0
func caso(_ nombre: String, _ ps: [Pared], verdad: Ac, ac: Ac, vistas: [MallaDelCuarto.Vista], pines: [MallaDelCuarto.Pin] = [],
          maxIn: Double, minVistas: Int = 0, debeAjustar: Bool = true) {
    let aj = MallaDelCuarto.ajustar(paredes: ps, ac: ac, vistas: vistas, pines: pines)
    let antes = errorSinAjuste(ps, verdad, ac), despues = errorEsquinas(ps, verdad, aj)
    let ok = despues <= maxIn && aj.vistas >= minVistas && aj.afinado == debeAjustar
    if !ok { fallas += 1 }
    print(String(format: "%@ %-58@ antes %5.1f in → después %5.1f in · vistas %d · pines %d · giro %.2f° · mov %.2f m",
                 ok ? "OK  " : "FALLA", nombre as NSString, antes, despues, aj.vistas, aj.pines, aj.giro * 180 / .pi, aj.mov))
}

let verdad = Ac(giro: 0.4, mov: SIMD2(3, -2))
let lejos = SIMD2<Double>(-25, -10)   // la ubicación se encontró en la otra punta de la casa
let r = mover(rect, SIMD2(10, 6)), l = mover(ele, SIMD2(8, 4))

ponerCentro(r, verdad)
// 1. Las 4 paredes vistas a pedazos, ubicación 2° + 6 in mal.
var ac = malUbicado(verdad, grados: 2, piv: lejos, mov: SIMD2(0.5, -0.3))
caso("rect · 4 paredes vistas (60%)", r, verdad: verdad, ac: ac, vistas: r.map { vista($0, verdad, f0: 0.2, f1: 0.8) }, maxIn: 1.5, minVistas: 4)
// 2. Solo dos paredes que se tocan.
caso("rect · 2 paredes de una esquina", r, verdad: verdad, ac: ac, vistas: [vista(r[0], verdad, f0: 0.3, f1: 1), vista(r[1], verdad, f0: 0, f1: 0.6)], maxIn: 1.0, minVistas: 2)
// 3. Una pared + la esquina de enfrente tocada.
let piv3 = MallaDelCuarto.ar(r[2].b, verdad)
caso("rect · 1 pared + 1 esquina tocada", r, verdad: verdad, ac: ac, vistas: [vista(r[0], verdad, f0: 0.1, f1: 0.9)],
     pines: [MallaDelCuarto.Pin(plano: r[2].b, ar: piv3 + SIMD2(0.01, -0.01))], maxIn: 1.5, minVistas: 1)
// 4. Muebles: cara de un librero 35 cm adentro (más larga que lo visto de la pared) + la cara del otro cuarto 12 cm afuera.
var v4 = r.map { vista($0, verdad, f0: 0.25, f1: 0.75) }
v4.append(vista(r[0], verdad, f0: 0.05, f1: 0.9, empuje: 0.35))
v4.append(vista(r[1], verdad, f0: 0.1, f1: 0.9, empuje: -0.12))
// 4b. Lo mismo SIN saber de qué lado se vio (la cara del otro cuarto puede ganar: se mide cuánto).
var v4b = r.map { vista($0, verdad, f0: 0.25, f1: 0.75, conLado: false) }
v4b.append(vista(r[0], verdad, f0: 0.05, f1: 0.9, empuje: 0.35, conLado: false))
caso("rect · con cara de mueble y cara del otro cuarto", r, verdad: verdad, ac: ac, vistas: v4, maxIn: 1.5, minVistas: 3)
caso("rect · mueble, sin saber el lado", r, verdad: verdad, ac: ac, vistas: v4b, maxIn: 1.5, minVistas: 3)
// 5. Ubicación muy mal: 4° + 1.5 ft.
let ac5 = malUbicado(verdad, grados: 4, piv: lejos, mov: SIMD2(1.2, 0.9))
caso("rect · ubicación 4° + 1.5 ft mal, 3 paredes", r, verdad: verdad, ac: ac5, vistas: Array(r.prefix(3)).map { vista($0, verdad, f0: 0.2, f1: 0.9) }, maxIn: 1.5, minVistas: 3)
// 6. Sin nada visto: la malla queda como la ubicación.
caso("rect · nada visto", r, verdad: verdad, ac: ac, vistas: [], maxIn: 999, debeAjustar: false)
// 7. Solo planos de OTRO cuarto (lejos): nada se empareja.
let otro = mover(rect, SIMD2(40, 30))
caso("rect · planos de otro cuarto lejos", r, verdad: verdad, ac: ac, vistas: otro.map { vista($0, verdad, f0: 0, f1: 1) }, maxIn: 999, debeAjustar: false)
// 8. Cuarto en L, 4 de 6 paredes vistas.
ponerCentro(l, verdad)
caso("L · 4 de 6 paredes vistas", l, verdad: verdad, ac: ac, vistas: [0, 1, 3, 5].map { vista(l[$0], verdad, f0: 0.15, f1: 0.85) }, maxIn: 1.5, minVistas: 4)
ponerCentro(r, verdad)
// 9. Una sola pared vista: lo de lado (a lo largo) lo dice la ubicación; lo de frente y el giro, el láser.
let aj9 = MallaDelCuarto.ajustar(paredes: r, ac: ac, vistas: [vista(r[0], verdad, f0: 0.2, f1: 0.8)])
let dPerp = abs(simd_dot(aj9.paredes[0].a - MallaDelCuarto.ar(r[0].a, verdad), MallaDelCuarto.perp(simd_normalize(aj9.paredes[0].b - aj9.paredes[0].a)))) / 0.0254
print(String(format: "%@ rect · 1 pared: la pared vista queda pegada (%.2f in de frente)", dPerp <= 1.0 ? "OK  " : "FALLA", dPerp)); if dPerp > 1.0 { fallas += 1 }
// 10. Ruido grande (3 cm) y planos chicos.
semilla = 99
caso("rect · ruido 3 cm, planos de 30%", r, verdad: verdad, ac: ac, vistas: r.map { let f = rnd() * 0.6; return vista($0, verdad, f0: f, f1: f + 0.3, ruido: 0.03) }, maxIn: 2.5, minVistas: 3)
// 11. Algo emparejado mal a propósito: un plano que daría un giro enorme → no se cree.
let malo = MallaDelCuarto.Vista(a: MallaDelCuarto.ar(r[0].a, verdad) + SIMD2(0, 0.4), b: MallaDelCuarto.ar(r[0].b, verdad) + SIMD2(0, -0.4))
caso("rect · un solo plano chueco (no se debe creer de más)", r, verdad: verdad, ac: ac, vistas: [malo], maxIn: 30, debeAjustar: false)

// Estadística: 200 casas al azar (error de ubicación 0-4°, 0-1.5 ft; 2-4 paredes vistas; muebles al azar).
semilla = 2026
var lista: [Double] = [], peores = 0, antesLista: [Double] = []
for _ in 0..<200 {
    let ps = rnd() < 0.5 ? r : l
    ponerCentro(ps, verdad)
    let a = malUbicado(verdad, grados: (rnd() * 2 - 1) * 4, piv: lejos, mov: SIMD2((rnd() * 2 - 1) * 1.5, (rnd() * 2 - 1) * 1.5))
    var vs: [MallaDelCuarto.Vista] = []
    let cuantas = 2 + Int(rnd() * 3)
    var idx = Array(0..<ps.count); idx.shuffle(using: &SystemRandomNumberGenerator.shared)
    for i in idx.prefix(cuantas) { let f = rnd() * 0.4; vs.append(vista(ps[i], verdad, f0: f, f1: f + 0.3 + rnd() * 0.3, ruido: 0.015)) }
    // Un mueble alto delante de una pared: el láser ve la pared por arriba o por un lado (un mueble bajo ni cuenta: la
    // cámara no usa planos que no pasan de 1.2 m). Que SOLO se vea el mueble alto y nada más de esa dirección es el
    // caso que no se puede saber: va aparte.
    if rnd() < 0.5 {
        let i = Int(rnd() * Double(ps.count))
        vs.append(vista(ps[i], verdad, f0: 0.1, f1: 0.9, empuje: 0.3 + rnd() * 0.3))
        let f = rnd() * 0.5; vs.append(vista(ps[i], verdad, f0: f, f1: f + 0.35, ruido: 0.015))
    }
    if rnd() < 0.3 { let i = Int(rnd() * Double(ps.count)); vs.append(vista(ps[i], verdad, f0: 0.1, f1: 0.9, empuje: -0.12)) }
    let aj = MallaDelCuarto.ajustar(paredes: ps, ac: a, vistas: vs)
    // Lo que importa: las esquinas de las paredes VISTAS (lo demás puede quedar como la ubicación si no hay cómo saber).
    var peor = 0.0
    for (i, w) in ps.enumerated() where aj.paredes[i].vista {
        peor = max(peor, simd_distance(aj.paredes[i].a, MallaDelCuarto.ar(w.a, verdad)) * (aj.paredes[i].finaA ? 1 : 0),
                   simd_distance(aj.paredes[i].b, MallaDelCuarto.ar(w.b, verdad)) * (aj.paredes[i].finaB ? 1 : 0))
    }
    lista.append(peor / 0.0254); antesLista.append(errorSinAjuste(ps, verdad, a))
    if peor / 0.0254 > 2 { peores += 1
        if peores <= 6 {
            let vistasIdx = (0..<ps.count).filter { aj.paredes[$0].vista }
            print(String(format: "   mal: %@ peor %.1f in · error ubic %.1f in · vistas %@ · planos %d · giro %.2f° mov %.2f", ps.count == 4 ? "rect" : "L", peor / 0.0254, errorSinAjuste(ps, verdad, a), vistasIdx.description, vs.count, aj.giro * 180 / .pi, aj.mov))
            let antesVerdad = MallaDelCuarto.ajustar(paredes: ps, ac: verdad, vistas: vs)
            print(String(format: "        mismo caso desde la verdad: peor %.1f in", errorEsquinas(ps, verdad, antesVerdad)))
        }
    }
}
lista.sort(); antesLista.sort()
print(String(format: "ESTADÍSTICA 200 · esquinas de paredes vistas: mediana %.2f in · p95 %.2f in · peor %.2f in · >2 in: %d   (la ubicación sola: mediana %.1f in, p95 %.1f in)",
             lista[100], lista[190], lista.last!, peores, antesLista[100], antesLista[190]))
if lista[190] > 2 { fallas += 1 }
// El caso que NO se puede saber: solo se ve la cara de un mueble alto (refri, librero) en una dirección. Se mide y se dice.
semilla = 5
let solo = MallaDelCuarto.ajustar(paredes: r, ac: ac, vistas: [vista(r[0], verdad, f0: 0.1, f1: 0.9, empuje: 0.45), vista(r[1], verdad, f0: 0.2, f1: 0.8)])
print(String(format: "AVISO rect · SOLO la cara de un refri en una dirección: esa pared queda %.1f in corrida (no se puede saber sin ver la pared; para eso se toca la esquina)", errorEsquinas(r, verdad, solo)))
let soloPin = MallaDelCuarto.ajustar(paredes: r, ac: ac, vistas: [vista(r[0], verdad, f0: 0.1, f1: 0.9, empuje: 0.45), vista(r[1], verdad, f0: 0.2, f1: 0.8)],
                                     pines: [MallaDelCuarto.Pin(plano: r[0].a, ar: MallaDelCuarto.ar(r[0].a, verdad))])
print(String(format: "      … y tocando una esquina: %.1f in", errorEsquinas(r, verdad, soloPin)))
// La memoria: ayer se vio un corte de 1 ft de 2 a 10 ft, la tele tapaba de 10 a 14. Hoy se mueve la tele y se ve de 9 a 15:
// hay corte de 10 a 14 también. Debe quedar de 2 a 14 (en dos pedazos que se tocan).
do {
    let ayer: [MallaDelCuarto.Corte] = [(2, 10, 1)]
    let hoy = MallaDelCuarto.mezclar(viejos: ayer, nuevos: [(9, 14, 1)], vistos: [(9, 15)])
    let total = hoy.reduce(0) { $0 + ($1.t1 - $1.t0) }
    let ok = abs(total - 12) < 0.01 && hoy.first!.t0 == 2 && hoy.last!.t1 == 14
    print(String(format: "%@ memoria · la tele: ayer 2-10, hoy se ve 9-15 con corte 9-14 → %@ (%.1f ft)", ok ? "OK  " : "FALLA", hoy.map { "\($0.t0)-\($0.t1)" }.joined(separator: ", "), total)); if !ok { fallas += 1 }
    // Hoy se ve entero de 0 a 6 (ahí NO hay corte): lo de ayer de 2 a 6 se corrige; de 6 a 10 se queda.
    let hoy2 = MallaDelCuarto.mezclar(viejos: ayer, nuevos: [], vistos: [(0, 6)])
    let ok2 = hoy2.count == 1 && hoy2[0].t0 == 6 && hoy2[0].t1 == 10
    print("\(ok2 ? "OK  " : "FALLA") memoria · hoy se ve entero 0-6: queda \(hoy2.map { "\($0.t0)-\($0.t1)" })"); if !ok2 { fallas += 1 }
    let u = MallaDelCuarto.unir([(5, 7), (0, 2), (1.5, 3), (7.02, 8)])
    let ok3 = u.count == 2 && u[0] == (0, 3) && u[1] == (5, 8)
    print("\(ok3 ? "OK  " : "FALLA") memoria · unir lo visto: \(u)"); if !ok3 { fallas += 1 }
}
// EL TECHO: el contorno del cuarto sale de las paredes ya acomodadas (en cualquier orden y sentido), en rect y en L.
do {
    func enAR(_ ps: [Pared]) -> [MallaDelCuarto.ParedAR] { ps.map { MallaDelCuarto.ParedAR(a: MallaDelCuarto.ar($0.a, verdad), b: MallaDelCuarto.ar($0.b, verdad)) } }
    func area(_ p: [SIMD2<Double>]) -> Double { var a = 0.0; for i in 0..<p.count { let x = p[i], y = p[(i + 1) % p.count]; a += x.x * y.y - y.x * x.y }; return abs(a) / 2 * 10.7639 }
    var revuelto = enAR(r); revuelto.swapAt(0, 2); let t = revuelto[1].a; revuelto[1].a = revuelto[1].b; revuelto[1].b = t
    let c1 = MallaDelCuarto.contorno(revuelto), c2 = MallaDelCuarto.contorno(enAR(l))
    let ok1 = c1 != nil && abs(area(c1!) - 168) < 1, ok2 = c2 != nil && abs(area(c2!) - (16 * 8 + 9 * 7)) < 1
    print(String(format: "%@ techo · contorno del cuarto revuelto: %.1f SF (14x12 = 168) · en L: %.1f SF (191)", ok1 && ok2 ? "OK  " : "FALLA", c1.map(area) ?? -1, c2.map(area) ?? -1)); if !(ok1 && ok2) { fallas += 1 }
    var falta = enAR(r); falta.remove(at: 1)
    let ok3 = MallaDelCuarto.contorno(falta) == nil
    print("\(ok3 ? "OK  " : "FALLA") techo · si falta una pared no inventa el contorno (usa la caja)"); if !ok3 { fallas += 1 }
    let ok4 = MallaDelCuarto.dentro(SIMD2(0.5, 0.5), [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)]) && !MallaDelCuarto.dentro(SIMD2(1.5, 0.5), [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)])
    print("\(ok4 ? "OK  " : "FALLA") techo · dentro/fuera del contorno"); if !ok4 { fallas += 1 }
    func q(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double) -> [SIMD2<Double>] { [SIMD2(x0, y0), SIMD2(x1, y0), SIMD2(x1, y1), SIMD2(x0, y1)] }
    let viejos = [q(0, 4, 0, 4), q(8, 10, 8, 10)]
    let poco = MallaDelCuarto.mezclarTecho(viejos: viejos, nuevos: [q(3, 6, 3, 6)], visto: 0.3)
    let mucho = MallaDelCuarto.mezclarTecho(viejos: viejos, nuevos: [q(3, 6, 3, 6)], visto: 0.8)
    let ok5 = poco.count == 2 && mucho.count == 1
    print("\(ok5 ? "OK  " : "FALLA") techo · memoria: viendo poco se junta con lo de antes (\(poco.count) pedazos), viendo casi todo manda lo de ahora (\(mucho.count))"); if !ok5 { fallas += 1 }
}
// LO QUE SE VE A TRAVÉS: una pared de 14 ft (4.27 m) con una puerta de 3 ft (de 6 a 9 ft, hasta 6'-8") que el plano no
// tenía, y una ventana de 3 ft (de 10 a 13 ft, de 3 a 7 ft de alto). El teléfono camina frente a ella; los puntos que caen en
// la pared pegan en ella y los de los huecos pegan 2 m detrás. Debe salir 1 puerta y 1 ventana, en su lugar.
do {
    let pie = 0.3048
    let a = SIMD2<Double>(0, 0), b = SIMD2<Double>(14 * pie, 0)
    var tr = MallaDelCuarto.Traspaso(a: a, b: b, alto: 8 * pie)
    semilla = 11
    func hueco(_ x: Double, _ y: Double) -> Bool { (x >= 6 * pie && x <= 9 * pie && y <= 6.67 * pie) || (x >= 10 * pie && x <= 13 * pie && y >= 3 * pie && y <= 7 * pie) }
    for paso in 0..<40 {
        let C = SIMD3<Float>(Float(1 + Double(paso) * 0.06), 1.2, 1.5)      // el teléfono a 1.5 m de la pared (z = 0), caminando
        for _ in 0..<400 {
            let x = rnd() * 14 * pie, y = rnd() * 8 * pie
            if hueco(x, y) {
                // pasa por el hueco y pega en algo 2 m detrás (z = -2)
                let dir = SIMD3<Float>(Float(x), Float(y), 0) - C
                let P = C + dir * Float((1.5 + 2) / 1.5)
                tr.votar(camara: C, punto: P + SIMD3<Float>(Float(gauss(0.01)), Float(gauss(0.01)), Float(gauss(0.01))), piso: 0)
            } else {
                tr.votar(camara: C, punto: SIMD3<Float>(Float(x), Float(y), Float(gauss(0.01))), piso: 0)
            }
        }
    }
    let ab = tr.aberturas()
    let puertas = ab.filter { $0.puerta }, ventanas = ab.filter { !$0.puerta }
    let okP = puertas.count == 1 && abs(puertas[0].t0 / pie - 6) < 0.5 && abs(puertas[0].t1 / pie - 9) < 0.5 && abs(puertas[0].arriba / pie - 6.67) < 0.6
    let okV = ventanas.count == 1 && abs(ventanas[0].t0 / pie - 10) < 0.5 && abs(ventanas[0].t1 / pie - 13) < 0.5 && abs(ventanas[0].abajo / pie - 3) < 0.6
    print(String(format: "%@ a través · puerta que el plano no tenía: %@ · ventana: %@", okP && okV ? "OK  " : "FALLA",
                 puertas.map { String(format: "%.1f-%.1f ft hasta %.1f", $0.t0 / pie, $0.t1 / pie, $0.arriba / pie) }.joined(), ventanas.map { String(format: "%.1f-%.1f ft de %.1f a %.1f", $0.t0 / pie, $0.t1 / pie, $0.abajo / pie, $0.arriba / pie) }.joined()))
    if !(okP && okV) { fallas += 1 }
    // Una pared entera (sin huecos): nada.
    var entera = MallaDelCuarto.Traspaso(a: a, b: b, alto: 8 * pie)
    for paso in 0..<40 { let C = SIMD3<Float>(Float(1 + Double(paso) * 0.06), 1.2, 1.5); for _ in 0..<400 { entera.votar(camara: C, punto: SIMD3<Float>(Float(rnd() * 14 * pie), Float(rnd() * 8 * pie), Float(gauss(0.015))), piso: 0) } }
    let ok2 = entera.aberturas().isEmpty
    print("\(ok2 ? "OK  " : "FALLA") a través · pared entera: ninguna abertura"); if !ok2 { fallas += 1 }
    // La malla corrida 20 cm de la pared de verdad (todavía sin pegar): no inventa huecos.
    var corrida = MallaDelCuarto.Traspaso(a: a + SIMD2(0, 0.2), b: b + SIMD2(0, 0.2), alto: 8 * pie)
    for paso in 0..<40 { let C = SIMD3<Float>(Float(1 + Double(paso) * 0.06), 1.2, 1.5); for _ in 0..<400 { corrida.votar(camara: C, punto: SIMD3<Float>(Float(rnd() * 14 * pie), Float(rnd() * 8 * pie), Float(gauss(0.015))), piso: 0) } }
    let ok3 = corrida.aberturas().isEmpty
    print("\(ok3 ? "OK  " : "FALLA") a través · malla corrida 20 cm: no inventa huecos"); if !ok3 { fallas += 1 }
}

// LA COCINA DE LA BITÁCORA (16 oct, sesión 1): parado en la puerta mirando la cocina chica (7.9 x 8.25 ft), el láser ve los
// gabinetes de arriba (30-40 cm delante de las paredes), el costado del refri pegado por ARKit al plano de la pared de la sala
// (largo, casi todo fuera de la cocina) y, de espaldas, las caras de la sala de las dos paredes que comparte con ella. La
// malla se iba 0.8 m (2.8 ft). Datos de verdad: paredes del plano, la ubicación del teléfono y los planos de ARKit (con su
// lado: la normal del ancla). Verdad = lo que el mismo teléfono afinó después, ya viendo las 5 paredes (t 138.4).
do {
    let cocina = [Pared(a: SIMD2(-11.57, 14.19), b: SIMD2(-11.57, 5.94), exterior: false, alto: 8.3), Pared(a: SIMD2(-3.67, 5.94), b: SIMD2(-3.67, 14.19), exterior: false, alto: 8.3), Pared(a: SIMD2(-3.67, 14.19), b: SIMD2(-11.57, 14.19), exterior: true, alto: 8.3), Pared(a: SIMD2(-6.28, 5.94), b: SIMD2(-3.67, 5.94), exterior: false, alto: 8.3), Pared(a: SIMD2(-11.57, 5.94), b: SIMD2(-6.28, 5.94), exterior: false, alto: 8.3)]
    let verdadCocina = Ac(giro: 4.6634, mov: SIMD2(-15.25, 9.11))
    func planosAR(_ xs: [(Double, Double, Double, Double)]) -> [MallaDelCuarto.Vista] {
        xs.map { let a = SIMD2($0.0, $0.1), b = SIMD2($0.2, $0.3), dv = simd_normalize(b - a); return MallaDelCuarto.Vista(a: a, b: b, n: SIMD2(dv.y, -dv.x)) }
    }
    caso("cocina real · t 98 (gabinetes + refri + caras de la sala)", cocina, verdad: verdadCocina, ac: Ac(giro: 4.6821, mov: SIMD2(-15.5, 9.34)),
         vistas: planosAR([(3.99, 3.79, 4.33, -2.37), (-1.35, -2.66, -1.42, 0.89), (-1.14, -0.75, -1.43, 0.72), (-1.62, 3.08, -1.23, 3.17), (-0.56, 1.43, -1.56, 1.37), (3.17, 5.51, 3.25, 3.86), (3.25, 3.73, 4, 3.79), (-0.2, 2.74, 2.45, 2.87), (-1.74, 0.92, 1.1, 1.09), (0.95, 1.11, 0.88, 2.76), (4.35, -2.47, -0.99, -2.54), (-1.56, 1, -1.71, 3.44), (1.64, 1.03, 1.86, 1.24), (1.59, 1.04, 1.89, 1.22), (0.7, -2.44, -0.84, -2.28)]), maxIn: 3, debeAjustar: true)
    caso("cocina real · t 128 (ya se ve la cara de una pared)", cocina, verdad: verdadCocina, ac: Ac(giro: 4.681, mov: SIMD2(-15.49, 9.34)),
         vistas: planosAR([(-1.34, -2.66, -1.42, 0.89), (-1.14, -0.75, -1.43, 0.72), (-1.7, 3.08, -0.32, 3.19), (-0.11, 1.45, -1.6, 1.36), (3.17, 5.51, 3.25, 3.86), (3.25, 3.73, 4, 3.79), (-0.15, 2.74, 2.45, 2.87), (-1.74, 0.92, 1.1, 1.09), (0.95, 1.11, 0.88, 2.76), (4.35, -2.47, -0.99, -2.54), (-1.58, 1, -1.73, 3.49), (1.64, 1.03, 1.86, 1.24), (1.59, 1.04, 1.89, 1.22), (0.7, -2.44, -0.84, -2.28), (-0.26, 1.13, -1.26, 1.05)]), maxIn: 3, debeAjustar: true)
    // El mismo caso del refri de arriba, pero con la cara del otro cuarto de esa pared vista de espaldas: ya se puede saber.
    semilla = 5
    caso("rect · refri en una dirección + la cara del otro cuarto", r, verdad: verdad, ac: ac,
         vistas: [vista(r[0], verdad, f0: 0.1, f1: 0.9, empuje: 0.45), vista(r[1], verdad, f0: 0.2, f1: 0.8), vista(r[0], verdad, f0: 0.3, f1: 0.9, empuje: -0.12)], maxIn: 1.5, minVistas: 1)
}
extension SystemRandomNumberGenerator { static var shared = SystemRandomNumberGenerator() }
print(fallas == 0 ? "TODO BIEN" : "FALLAS: \(fallas)")
exit(fallas == 0 ? 0 : 1)
