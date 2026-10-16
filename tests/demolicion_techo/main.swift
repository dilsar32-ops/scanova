// PRUEBA EN 3D DE LO DEMOLIDO EN EL TECHO (15 oct 2026).
// El teléfono camina por el cuarto mirando para arriba (de 50 a 85°), en dos pasadas; el comparador del techo junta
// lo que ve en huecos. Con el plano se sabe dónde están las paredes: un hueco que llega a la pared se mide hasta la pared.
import Foundation
import simd

typealias T = ComparadorDeTecho

struct CaminoTecho {
    var altura: Float = 1.25
    var pasadas: [Float] = [0.22, 0.5, 0.78]     // a qué fondo del cuarto (fracción de D)
    var segundos: Float = 18                     // por pasada
    var inclinacionMin: Float = 48, inclinacionMax: Float = 82
    var ancho = 72, alto = 96
    var fovH: Float = 48, fovV: Float = 62
    var deriva: Float = 0.0010
    var margen: Float = 0.5
}

func barrerTecho(_ cu: CuartoTecho, camino k: CaminoTecho, cara: T.Cara) -> T {
    var comp = T()
    var deriva = SIMD3<Float>(repeating: 0)
    var c = 0
    for (ip, zf) in k.pasadas.enumerated() {
        let cuadros = Int(k.segundos * 5)
        let ida = ip % 2 == 0
        for j in 0..<cuadros {
            let f = Float(j) / Float(max(cuadros - 1, 1))
            let x = ida ? k.margen + (cu.L - 2 * k.margen) * f : cu.L - k.margen - (cu.L - 2 * k.margen) * f
            let z = cu.D * zf + 0.15 * sin(Float(c) * 0.23)
            let pitch = (k.inclinacionMin + (k.inclinacionMax - k.inclinacionMin) * (0.5 + 0.5 * sin(Float(c) * 0.31))) * .pi / 180
            // Mira hacia donde camina, volteando a los lados (para ver la orilla del techo junto a las paredes).
            // Voltea a los lados (±70°) y, al llegar a cada punta, da la vuelta mirando lo de atrás.
            var rumbo: Float = (ida ? 0 : .pi) + 1.2 * sin(Float(c) * 0.17)
            if f < 0.08 { rumbo += .pi * (1 - f / 0.08) }
            if f > 0.92 { rumbo += .pi * (f - 0.92) / 0.08 }
            let cam = SIMD3<Float>(x, k.altura + 0.04 * sin(Float(c) * 0.8), z)
            deriva += SIMD3(gauss(), gauss(), gauss()) * k.deriva
            let horiz = SIMD3<Float>(cos(rumbo), 0, sin(rumbo))
            let adelante = simd_normalize(horiz * cos(pitch) + SIMD3(0, sin(pitch), 0))
            let derecha = simd_normalize(simd_cross(adelante, SIMD3(0, 1, 0)))
            let arriba = simd_cross(derecha, adelante)
            let a1 = gauss() * 0.0015, a2 = gauss() * 0.0015
            let p1 = azar(), p2 = azar()
            var rangos = [Float](repeating: .nan, count: k.ancho * k.alto)
            var dirs = [SIMD3<Float>](repeating: .zero, count: k.ancho * k.alto)
            for jj in 0..<k.alto { for ii in 0..<k.ancho {
                let hx = tan((Float(ii) / Float(k.ancho - 1) - 0.5) * k.fovH * .pi / 180)
                let vy = tan((0.5 - Float(jj) / Float(k.alto - 1)) * k.fovV * .pi / 180)
                let d = simd_normalize(adelante + derecha * hx + arriba * vy)
                dirs[jj * k.ancho + ii] = d
                if let t = cu.lanzar(cam, d) { rangos[jj * k.ancho + ii] = t }
            } }
            var puntos: [SIMD3<Float>] = []
            for jj in 0..<k.alto { for ii in 0..<k.ancho {
                let k2 = jj * k.ancho + ii
                var r = rangos[k2]
                guard r.isFinite, r < 5 else { continue }
                var vecino: Float? = nil
                for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let i2 = ii + di, j2 = jj + dj
                    guard i2 >= 0, i2 < k.ancho, j2 >= 0, j2 < k.alto else { continue }
                    let rv = rangos[j2 * k.ancho + i2]
                    if rv.isFinite, abs(rv - r) > 0.03 { vecino = rv; break }
                }
                if let v = vecino { if azar() < 0.75 { continue }; r += (v - r) * azar() }
                r += a1 * sin(2 * .pi * (Float(ii) / Float(k.ancho) * 1.7 + p1)) + a2 * sin(2 * .pi * (Float(jj) / Float(k.alto) * 1.3 + p2)) + gauss() * 0.0015
                puntos.append(cam + dirs[k2] * r + deriva)
            } }
            comp.votar(camara: cam + deriva, puntos: puntos, cara: cara)
            c += 1
        }
    }
    return comp
}

func pies(_ m: Float) -> String { let t = Int((m / pulg).rounded()); return "\(t / 12)'-\(t % 12)\"" }
var pasan = 0, fallan = 0
func ok(_ l: String, _ c: Bool, _ d: String = "") { if c { pasan += 1; print("  ok  " + l) } else { fallan += 1; print("  FALLA " + l + "  " + d) } }

let modo = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "crudo"
struct CasoTecho { var nombre: String; var cu: CuartoTecho; var camino = CaminoTecho() }
var casos: [CasoTecho] = []
func agregar(_ nombre: String, _ ajustar: (inout CuartoTecho) -> Void) { var cu = CuartoTecho(); ajustar(&cu); casos.append(CasoTecho(nombre: nombre, cu: cu)) }
let L: Float = 14 * pie, D: Float = 12 * pie
agregar("A. hueco de 4 x 6 ft en medio (vigas 2x8 cada 16)") { $0.huecos = [Hueco(x0: 5 * pie, x1: 11 * pie, z0: 4 * pie, z1: 8 * pie)] }
agregar("B. tira de 2 ft pegada a la pared de afuera (todo lo largo)") { $0.huecos = [Hueco(x0: 0, x1: L, z0: 0, z1: 2 * pie)] }
agregar("C. hueco en la esquina del cuarto (4 x 4 ft)") { $0.huecos = [Hueco(x0: 0, x1: 4 * pie, z0: 0, z1: 4 * pie)] }
agregar("D. dos huecos (2 x 3 y 3 x 4 ft)") { $0.huecos = [Hueco(x0: 2 * pie, x1: 5 * pie, z0: 3 * pie, z1: 5 * pie), Hueco(x0: 8 * pie, x1: 12 * pie, z0: 6 * pie, z1: 9 * pie)] }
agregar("E. todo el techo") { $0.huecos = [Hueco(x0: 0, x1: L, z0: 0, z1: D)] }
agregar("F. vigas 2x10 cada 24, corren a lo largo (hueco 4 x 6)") { $0.viga = 9.25 * pulg; $0.separacion = 24 * pulg; $0.vigasEnX = true; $0.huecos = [Hueco(x0: 5 * pie, x1: 11 * pie, z0: 4 * pie, z1: 8 * pie)] }
agregar("G. ático (cerchas 2x4 cada 24), hueco 4 x 6") { $0.atico = true; $0.viga = 3.5 * pulg; $0.separacion = 24 * pulg; $0.huecos = [Hueco(x0: 5 * pie, x1: 11 * pie, z0: 4 * pie, z1: 8 * pie)] }
agregar("H. hueco chico de inspección (1 x 1 ft)") { $0.huecos = [Hueco(x0: 6 * pie, x1: 7 * pie, z0: 5 * pie, z1: 6 * pie)] }
agregar("I. CONTROL: techo entero con 4 lámparas empotradas, una rejilla y un abanico") {
    $0.empotradas = [SIMD2(3.5 * pie, 3 * pie), SIMD2(10.5 * pie, 3 * pie), SIMD2(3.5 * pie, 9 * pie), SIMD2(10.5 * pie, 9 * pie)]
    $0.rejillas = [Hueco(x0: 1 * pie, x1: 1 * pie + 10 * pulg, z0: 5.5 * pie, z1: 5.5 * pie + 6 * pulg)]
    $0.cajas = [Caja(lo: SIMD3(6.5 * pie, 8 * pie - 10 * pulg, 5.5 * pie), hi: SIMD3(7.5 * pie, 8 * pie, 6.5 * pie))]
}
agregar("J. CONTROL: la mancha del agua") { $0.mancha = SIMD2(7 * pie, 6 * pie) }
agregar("K. hueco en forma de L (4x6 + 2x4)") { $0.huecos = [Hueco(x0: 5 * pie, x1: 11 * pie, z0: 4 * pie, z1: 8 * pie), Hueco(x0: 9 * pie, x1: 11 * pie, z0: 8 * pie, z1: 11 * pie)] }

func areaVerdad(_ c: CasoTecho) -> Float {
    // Los huecos pueden encimarse (la L): se cuenta por cuadrito de 1 in.
    var a: Float = 0
    let paso = 1 * pulg
    var x = paso / 2
    while x < c.cu.L { var z = paso / 2; while z < c.cu.D { if c.cu.enHueco(x, z) { a += paso * paso }; z += paso }; x += paso }
    return a
}

// La cara: la del plano de ARKit del techo (medio grado torcida, 3 mm corrida), con u a lo largo de la pared sur.
func caraDelTecho(_ cu: CuartoTecho) -> T.Cara {
    let g: Float = 0.5 * .pi / 180
    var c = T.Cara.desde(punto: SIMD3(cu.L / 2, cu.H - 0.003, cu.D / 2), eje: SIMD3(1, 0, 0), telefono: SIMD3(cu.L / 2, 1, cu.D / 2))
    c.n = simd_normalize(SIMD3(sin(g), -cos(g), 0))
    c.u = simd_normalize(simd_cross(c.v, c.n)); c.v = simd_normalize(simd_cross(c.n, c.u))
    return c
}
func describir(_ r: T.Resultado, cara: T.Cara) -> String {
    let o = cara.origen
    let h = r.huecos.map { h -> String in
        // De la cara al cuarto: x = u + o.x, z = v + o.z (u a lo largo de x).
        let pared = h.hastaPared.enumerated().filter { $0.element }.map { ["oeste", "este", "sur", "norte"][$0.offset] }
        return "[x \(pies(h.u0 + o.x))→\(pies(h.u1 + o.x)), z \(pies(h.v0 + o.z))→\(pies(h.v1 + o.z)) · \(pies(h.ancho)) x \(pies(h.fondo)) · \(String(format: "%.1f", h.area / (pie * pie))) SF\(h.vigas > 0 ? " · \(h.vigas) vigas" : "")\(h.separacion.map { " a \(Int($0)) in" } ?? "")\(h.atico ? " · ático" : "")\(pared.isEmpty ? "" : " · hasta pared " + pared.joined(separator: "+"))]"
    }.joined(separator: " ")
    let v = r.techoVisto.map { String(format: " · visto %.0f%% del techo", $0 * 100) } ?? ""
    return "\(h.isEmpty ? "(nada)" : h) · total \(String(format: "%.1f", r.area / (pie * pie))) SF\(v) · chicos \(r.chicos) · alarmas \(r.alarmas)"
}

if modo == "crudo" || modo == "plano" {
    for c in casos {
        print("\n" + c.nombre + String(format: "   verdad %.1f SF", areaVerdad(c) / (pie * pie)))
        for s in 1...2 {
            semilla = UInt64(0x7EC0 + s * 7919)
            let cara = caraDelTecho(c.cu)
            let comp = barrerTecho(c.cu, camino: c.camino, cara: cara)
            let lim: (u: ClosedRange<Float>, v: ClosedRange<Float>)? = modo == "plano" ? ((0 - cara.origen.x)...(c.cu.L - cara.origen.x), (0 - cara.origen.z)...(c.cu.D - cara.origen.z)) : nil
            let r = comp.resultado(limites: lim)
            print("   láser\(s): " + describir(r, cara: cara))
        }
    }
}
if modo == "mapa" {
    let c = casos.first { $0.nombre.hasPrefix(CommandLine.arguments[2]) }!
    semilla = UInt64(0x7EC0 + (Int(CommandLine.arguments[3]) ?? 1) * 7919)
    let cara = caraDelTecho(c.cu)
    let comp = barrerTecho(c.cu, camino: c.camino, cara: cara)
    // Un caracter cada 2 cuadritos (4 in); filas = z (norte arriba), columnas = x.
    var z = c.cu.D - 2 * pulg
    while z > 0 {
        var linea = ""
        var x = 1 * pulg
        while x < c.cu.L {
            let q = SIMD2<Float>(x - cara.origen.x, z - cara.origen.z)
            if let cc = T.celdaDe(q.x), let rr = T.celdaDe(q.y) {
                switch comp.estado(T.indice(cc, rr)) { case .noVisto: linea += "·"; case .sigue: linea += "#"; case .ambiguo: linea += "a"; case .cavidad: linea += "c"; case .hondo: linea += "H"; case .tapado: linea += "T" }
            }
            x += 4 * pulg
        }
        print(String(format: "%5.1f ", z / pie) + linea)
        z -= 4 * pulg
    }
}

// ================== LA PRUEBA (tests/demolicion_techo_test.sh) ==================
if modo == "prueba" || modo == "estadistica" {
    let N = modo == "prueba" ? 5 : (CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 10 : 10)
    print("\nLO DEMOLIDO EN EL TECHO, CON EL PLANO: \(N) corridas por caso")
    var peorMas: Float = -1
    for c in casos {
        let verdad = areaVerdad(c)
        var errs: [Float] = [], cuentas: [Int] = [], vistos: [Float] = []
        for s in 1...N {
            semilla = UInt64(0x7EC0 + (300 + s) * 7919)
            let cara = caraDelTecho(c.cu)
            let comp = barrerTecho(c.cu, camino: c.camino, cara: cara)
            let r = comp.resultado(limites: ((0 - cara.origen.x)...(c.cu.L - cara.origen.x), (0 - cara.origen.z)...(c.cu.D - cara.origen.z)))
            errs.append(verdad > 0 ? (r.area - verdad) / verdad : r.area / (pie * pie))
            cuentas.append(r.huecos.count); vistos.append(r.techoVisto ?? 0)
            if CommandLine.arguments.count > 3 { print("      \(s): " + describir(r, cara: cara)) }
        }
        let mn = errs.min()!, mx = errs.max()!, pr = errs.reduce(0, +) / Float(N)
        let letra = String(c.nombre.prefix(1))
        if verdad > 0 {
            print(String(format: "  [%@] área: peor de menos %+.1f%%, promedio %+.1f%%, peor de más %+.1f%%", c.nombre, mn * 100, pr * 100, mx * 100))
            peorMas = max(peorMas, mx)
            let esperados = c.cu.huecos.count == 2 && letra == "D" ? 2 : 1
            // La orilla se mide a ±1 in (cuadritos de 2 in): en un hueco de 4 x 6 eso es ±3-4 %. Nunca más de 4 % (o 0.1 SF
            // en un hueco chico).
            ok("\(letra): nunca cobra más de 4% de más (0.1 SF en uno chico)", mx <= max(0.04, 0.1 * pie * pie / verdad))
            ok("\(letra): en promedio a 6% o menos de la verdad", pr >= -0.06)
            ok("\(letra): encuentra \(esperados) hueco\(esperados == 1 ? "" : "s") en las \(N)", cuentas.allSatisfy { $0 == esperados })
        } else {
            print(String(format: "  [%@] control: peor %.2f SF", c.nombre, mx))
            ok("\(letra): CONTROL, 0 pies en las \(N) (lámparas, rejillas, abanico y mancha no cuentan)", mx == 0)
        }
    }
    print(String(format: "\n  Lo peor de más en todos: %+.1f%%", peorMas * 100))
    // Sin plano (sin paredes): el hueco en medio igual se mide.
    let cA = casos[0]
    semilla = UInt64(0x7EC0 + 999 * 7919)
    let cara = caraDelTecho(cA.cu)
    let r = barrerTecho(cA.cu, camino: cA.camino, cara: cara).resultado()
    ok("sin plano el hueco de en medio igual se mide (a 6%)", abs(r.area - 24 * pie * pie) <= 24 * pie * pie * 0.06)
    // No caminó por todo el cuarto: lo dice.
    var kCorto = cA.camino; kCorto.pasadas = [0.22]
    semilla = UInt64(0x7EC0 + 998 * 7919)
    let rc = barrerTecho(cA.cu, camino: kCorto, cara: cara).resultado(limites: ((0 - cara.origen.x)...(cA.cu.L - cara.origen.x), (0 - cara.origen.z)...(cA.cu.D - cara.origen.z)))
    ok("si solo caminó por un lado, dice cuánto del techo vio y dónde falta (\(Int((rc.techoVisto ?? 0) * 100))%)", (rc.techoVisto ?? 1) < 0.9 && rc.faltaVer != nil)
    print("\n  \(pasan) pasan, \(fallan) fallan")
    exit(fallan == 0 ? 0 : 1)
}
if modo == "perfil" {
    // El perfil de una línea que cruza la orilla: estado, fracción honda, q25/q50/q75 de los votos.
    let c = casos.first { $0.nombre.hasPrefix(CommandLine.arguments[2]) }!
    semilla = UInt64(0x7EC0 + 301 * 7919)
    let cara = caraDelTecho(c.cu)
    let comp = barrerTecho(c.cu, camino: c.camino, cara: cara)
    let porZ = CommandLine.arguments[3] == "z"
    let fijo = Float(CommandLine.arguments[4])! * pie, desde = Float(CommandLine.arguments[5])! * pie, hasta = Float(CommandLine.arguments[6])! * pie
    var t = desde
    while t <= hasta {
        let x = porZ ? fijo : t, z = porZ ? t : fijo
        if let cc = T.celdaDe(x - cara.origen.x), let rr = T.celdaDe(z - cara.origen.z) {
            let k = T.indice(cc, rr)
            var vs = comp.votosDe(k); vs.sort()
            let q = vs.isEmpty ? "" : String(format: "q25 %5.2f q50 %5.2f q75 %5.2f", vs[vs.count / 4], vs[vs.count / 2], vs[vs.count * 3 / 4])
            print(String(format: "%@ %6.1f in  %@  f %.2f  %@", porZ ? "z" : "x", t / pulg, "\(comp.estado(k))".padding(toLength: 8, withPad: " ", startingAt: 0), comp.fraccion(k), q))
        }
        t += 2 * pulg
    }
}
