// PRUEBA DEL COMPARADOR DE DEMOLICIÓN (15 oct 2026) — un banco SINTÉTICO, en la Mac, sin teléfono.
// Arma una pared de verdad en 3D (drywall, studs cada 16 o 24 in, solera, cavidad de 2x4 o 2x6, el piso del cuarto)
// con el corte de la demolición, camina un teléfono simulado frente a ella a 5 cuadros por segundo y le pasa al
// comparador lo que "vería" el láser: con ruido parejo, ruido que se mueve junto (como el relleno de Apple), orillas
// borrosas que se pierden por confianza baja, y el rastreo que se va corriendo milímetro a milímetro.
//
// SIRVE PARA ENCONTRAR ERRORES, NO PARA DECIDIR SI SIRVE: el sensor de los 15/16/17 Pro rellena casi todo con la foto y
// eso no se puede imitar aquí. Lo que decide es la prueba con cinta (Fase 1). Por eso cada caso reporta el error CON
// SIGNO (+ = cobraría de más) y las reglas duras son las del lado peligroso: un control nunca da pies, una puerta o un
// espejo nunca cuentan, lo tapado nunca suma.
import Foundation
import simd

typealias C = ComparadorDeDemolicion

// ---------------- EL TELÉFONO QUE CAMINA ----------------
struct Barrido {
    var distancia: Float = 1.2          // de la pared (m)
    var altura: Float = 1.0             // a la cintura
    var inclinacionMin: Float = 12, inclinacionMax: Float = 34   // grados hacia abajo (cabecea al caminar)
    var x0: Float = -0.3, x1: Float = 14 * pie + 0.3
    var segundos: Float = 30
    var ancho = 72, alto = 96           // rayos por cuadro (retrato)
    var fovH: Float = 48, fovV: Float = 62
    var deriva: Float = 0.0010          // m por cuadro (paso de la caminata al azar)
}

struct Caso {
    var nombre: String
    var escena: Escena
    var barrido = Barrido()
    var fijar: SIMD3<Float>             // dónde se toca "Fijar pared" (drywall entero arriba del corte)
    var conPiso = true
    var esperado: (largo: Float, alto: Float, area: Float)   // la verdad (m, m, m²); 0 = no se quitó nada contable
}

func correr(_ caso: Caso) -> (C.Resultado, C) {
    var comp = C()
    let e = caso.escena, b = caso.barrido
    // La cara como la daría el ancla de ARKit: medio grado torcida y 3 mm corrida.
    let giro: Float = 0.5 * .pi / 180
    let nCara = simd_normalize(SIMD3<Float>(sin(giro), 0, cos(giro)))
    guard let cara = C.Cara.desde(punto: caso.fijar + SIMD3(0, 0, 0.003), normal: nCara, telefono: SIMD3(caso.fijar.x, 1, 1)) else { fatalError("cara") }
    let cuadros = Int(b.segundos * 5)
    var deriva = SIMD3<Float>(repeating: 0)
    for k in 0..<cuadros {
        let f = Float(k) / Float(max(cuadros - 1, 1))
        let fase = Float(k) * 0.35
        let pitch = (b.inclinacionMin + (b.inclinacionMax - b.inclinacionMin) * (0.5 + 0.5 * sin(fase))) * .pi / 180
        let yaw = 8 * sin(Float(k) * 0.21) * .pi / 180
        let cam = SIMD3<Float>(b.x0 + (b.x1 - b.x0) * f + 0.05 * sin(Float(k) * 0.5), b.altura + 0.04 * sin(Float(k) * 0.8), b.distancia + 0.08 * sin(Float(k) * 0.13))
        deriva += SIMD3(gauss(), gauss(), gauss()) * b.deriva
        let adelante = SIMD3<Float>(sin(yaw) * cos(pitch), -sin(pitch), -cos(yaw) * cos(pitch))
        let derecha = simd_normalize(simd_cross(adelante, SIMD3(0, 1, 0)))
        let arriba = simd_cross(derecha, adelante)
        // Ruido que se mueve junto (el relleno de Apple), distinto en cada cuadro.
        let a1 = gauss() * 0.0015, a2 = gauss() * 0.0015, a3 = gauss() * 0.0012
        let p1 = azar(), p2 = azar(), p3 = azar()
        var rangos = [Float](repeating: .nan, count: b.ancho * b.alto)
        var dirs = [SIMD3<Float>](repeating: .zero, count: b.ancho * b.alto)
        for j in 0..<b.alto {
            for i in 0..<b.ancho {
                let hx = tan((Float(i) / Float(b.ancho - 1) - 0.5) * b.fovH * .pi / 180)
                let vy = tan((0.5 - Float(j) / Float(b.alto - 1)) * b.fovV * .pi / 180)
                let d = simd_normalize(adelante + derecha * hx + arriba * vy)
                dirs[j * b.ancho + i] = d
                if let t = e.lanzar(cam, d) { rangos[j * b.ancho + i] = t }
            }
        }
        var puntos: [SIMD3<Float>] = []
        for j in 0..<b.alto {
            for i in 0..<b.ancho {
                let k2 = j * b.ancho + i
                var r = rangos[k2]
                guard r.isFinite, r < 5 else { continue }
                // Orillas: si un vecino está a más de 3 cm, el relleno se confunde: casi siempre baja la confianza (se
                // tira), y si no, mezcla las dos profundidades (un "pixel volador").
                var vecino: Float? = nil
                for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let ii = i + di, jj = j + dj
                    guard ii >= 0, ii < b.ancho, jj >= 0, jj < b.alto else { continue }
                    let rv = rangos[jj * b.ancho + ii]
                    if rv.isFinite, abs(rv - r) > 0.03 { vecino = rv; break }
                }
                if let v = vecino {
                    if azar() < 0.75 { continue }
                    r += (v - r) * azar()
                }
                r += a1 * sin(2 * .pi * (Float(i) / Float(b.ancho) * 1.7 + p1)) + a2 * sin(2 * .pi * (Float(j) / Float(b.alto) * 1.3 + p2))
                    + a3 * sin(2 * .pi * (Float(i + j) / Float(b.ancho) * 2.1 + p3)) + gauss() * 0.0015
                var p = cam + dirs[k2] * r
                // La línea del agua: el relleno de Apple "ve" un escalón donde la foto cambia de color.
                if let m = e.manchaY, abs(p.y - m) < 1.0 * pulg, p.z > -0.001 { p.z -= 0.6 * pulg }
                puntos.append(p + deriva)
            }
        }
        comp.votar(camara: cam + deriva, puntos: puntos, cara: cara)
    }
    // El piso lo mide el comparador (como en el teléfono). `conPiso` = false: el teléfono nunca apuntó al piso.
    return (comp.resultado(), comp)
}

// ---------------- LOS CASOS ----------------
var pasan = 0, fallan = 0
func ok(_ l: String, _ c: Bool, _ d: String = "") { if c { pasan += 1; print("  ok  " + l) } else { fallan += 1; print("  FALLA " + l + "  " + d) } }
func pulgadas(_ m: Float) -> String { String(format: "%+.2f in", m / pulg) }
func reporte(_ nombre: String, _ r: C.Resultado, _ esp: (largo: Float, alto: Float, area: Float)) {
    let a = r.area / (pie * pie), ea = esp.area / (pie * pie)
    let errA = esp.area > 0 ? (r.area - esp.area) / esp.area * 100 : 0
    print(String(format: "  [%@] largo %.1f in (verdad %.1f, %@) · alto %@ (verdad %.1f in, %@) · área %.2f SF (verdad %.2f, %+.1f%%) · visto %.0f%% · studs %@ · alarmas %@",
                 nombre, r.largo / pulg, esp.largo / pulg, pulgadas(r.largo - esp.largo),
                 r.alto.map { String(format: "%.2f in", $0 / pulg) } ?? "—", esp.alto / pulg, r.alto.map { pulgadas($0 - esp.alto) } ?? "—",
                 a, ea, errA, r.vistoPct * 100, r.separacionStuds.map { "\(Int($0)) in" } ?? "no", "\(r.alarmas)"))
}

let fijarBajo = SIMD3<Float>(7 * pie, 1.10, 0)   // drywall entero arriba de un corte de 2 ft
let fijarAlto = SIMD3<Float>(7 * pie, 1.55, 0)   // arriba de un corte de 4 ft

// 1. Pared de adentro, 2x4, corte de 2 ft a lo largo de 8 ft (con drywall entero a los dos lados).
var e1 = Escena(); e1.corte = (3 * pie, 11 * pie, 2 * pie)
let caso1 = Caso(nombre: "2x4, corte 2 ft x 8 ft", escena: e1, fijar: fijarBajo, esperado: (8 * pie, 2 * pie, 16 * pie * pie))
// 2. Corte de 4 ft: hay que ver más alto (cabecea más).
var e2 = Escena(); e2.corte = (3 * pie, 11 * pie, 4 * pie)
var b2 = Barrido(); b2.distancia = 1.5; b2.altura = 1.15; b2.inclinacionMin = 0; b2.inclinacionMax = 32; b2.segundos = 36
let caso2 = Caso(nombre: "2x4, corte 4 ft x 8 ft", escena: e2, barrido: b2, fijar: fijarAlto, esperado: (8 * pie, 4 * pie, 32 * pie * pie))
// 3. Pared de afuera, 2x6.
var e3 = Escena(); e3.corte = (3 * pie, 11 * pie, 2 * pie); e3.marco = 5.5 * pulg
let caso3 = Caso(nombre: "2x6 de afuera, corte 2 ft", escena: e3, fijar: fijarBajo, esperado: (8 * pie, 2 * pie, 16 * pie * pie))
// 4. Studs cada 24 in.
var e4 = Escena(); e4.corte = (3 * pie, 11 * pie, 2 * pie); e4.separacion = 24 * pulg
let caso4 = Caso(nombre: "studs cada 24 in", escena: e4, fijar: fijarBajo, esperado: (8 * pie, 2 * pie, 16 * pie * pie))
// 5. CONTROL: pared entera con la línea del agua a 18 in.
var e5 = Escena(); e5.manchaY = 18 * pulg
let caso5 = Caso(nombre: "control: pared entera con la mancha del agua", escena: e5, fijar: fijarBajo, esperado: (0, 0, 0))
// 6. Cortada pero la insulación quedó puesta.
var e6 = Escena(); e6.corte = (3 * pie, 11 * pie, 2 * pie); e6.insulacion = true
let caso6 = Caso(nombre: "cortada con la insulación puesta", escena: e6, fijar: fijarBajo, esperado: (0, 0, 0))
// 7. Un secador delante de parte del corte.
var e7 = Escena(); e7.corte = (3 * pie, 11 * pie, 2 * pie)
e7.cajas = [Caja(lo: SIMD3(6 * pie, 0, 0.05), hi: SIMD3(7.6 * pie, 0.48, 0.50))]
let caso7 = Caso(nombre: "un secador delante", escena: e7, fijar: fijarBajo, esperado: (8 * pie, 2 * pie, 16 * pie * pie))
// 8. Un espejo arriba de parte del corte (baño).
var e8 = Escena(); e8.corte = (3 * pie, 11 * pie, 2 * pie); e8.espejo = (5 * pie, 7 * pie, 2 * pie, 5 * pie)
let caso8 = Caso(nombre: "espejo arriba del corte", escena: e8, fijar: SIMD3(9 * pie, 1.10, 0), esperado: (8 * pie, 2 * pie, 16 * pie * pie))
// 9. Un paso abierto (puerta sin hoja), sin corte.
var e9 = Escena(); e9.puerta = (6 * pie, 9 * pie)
let caso9 = Caso(nombre: "paso abierto de 3 ft, sin corte", escena: e9, fijar: SIMD3(3 * pie, 1.10, 0), esperado: (0, 0, 0))
// 10. Sótano sin terminar: studs a la vista hasta arriba, nunca hubo drywall (no hay orilla).
var e10 = Escena(); e10.sinDrywallNunca = true
let caso10 = Caso(nombre: "sótano sin terminar (nunca tuvo drywall)", escena: e10, fijar: fijarBajo, esperado: (0, 0, 0))
// 11. Sin ver el piso (el teléfono alto y derecho, nunca apunta abajo): no hay número.
var b11 = Barrido(); b11.altura = 1.5; b11.inclinacionMin = 0; b11.inclinacionMax = 4
let caso11 = Caso(nombre: "sin piso visto", escena: e1, barrido: b11, fijar: fijarBajo, conPiso: false, esperado: (0, 0, 0))

print("\nBANCO SINTÉTICO (error con signo: + = cobraría de más). Cada caso con 3 ruidos distintos: las reglas valen en los 3.")
// Cada caso se corre con 3 semillas; `todos` dice si la regla se cumple en las tres.
func tres(_ caso: Caso, _ nombre: String) -> [C.Resultado] {
    (1...3).map { k -> C.Resultado in semilla = UInt64(0x5EED + k * 7919); let (r, _) = correr(caso); reporte("\(nombre).\(k)", r, caso.esperado); return r }
}
let R1 = tres(caso1, "1")
ok("1: alto a ±1 in", R1.allSatisfy { r1 in r1.alto.map { abs($0 - caso1.esperado.alto) <= 1 * pulg } ?? false })
ok("1: largo a ±4 in", R1.allSatisfy { r1 in abs(r1.largo - caso1.esperado.largo) <= 4 * pulg })
ok("1: área entre -6% y +3%", R1.allSatisfy { r1 in r1.area >= caso1.esperado.area * 0.94 && r1.area <= caso1.esperado.area * 1.03 })
ok("1: encuentra los studs cada 16 in", R1.allSatisfy { r1 in r1.separacionStuds == 16 })
let R2 = tres(caso2, "2")
ok("2: alto a ±1 in", R2.allSatisfy { r2 in r2.alto.map { abs($0 - caso2.esperado.alto) <= 1 * pulg } ?? false })
ok("2: área entre -8% y +3%", R2.allSatisfy { r2 in r2.area >= caso2.esperado.area * 0.92 && r2.area <= caso2.esperado.area * 1.03 })
let R3 = tres(caso3, "3")
ok("3: 2x6 alto a ±1 in", R3.allSatisfy { r3 in r3.alto.map { abs($0 - caso3.esperado.alto) <= 1 * pulg } ?? false })
ok("3: 2x6 área entre -6% y +3%", R3.allSatisfy { r3 in r3.area >= caso3.esperado.area * 0.94 && r3.area <= caso3.esperado.area * 1.03 })
let R4 = tres(caso4, "4")
ok("4: encuentra los studs cada 24 in", R4.allSatisfy { r4 in r4.separacionStuds == 24 })
ok("4: área entre -6% y +3%", R4.allSatisfy { r4 in r4.area >= caso4.esperado.area * 0.94 && r4.area <= caso4.esperado.area * 1.03 })
let R5 = tres(caso5, "5")
ok("5: CONTROL da 0 pies (la mancha del agua no es corte)", R5.allSatisfy { r5 in r5.area == 0 && r5.tramos.isEmpty })
let R6 = tres(caso6, "6")
ok("6: con la insulación puesta NO cuenta nada (se pregunta)", R6.allSatisfy { r6 in r6.area == 0 })
ok("6: y lo dice (ambiguo)", R6.allSatisfy { r6 in r6.alarmas.contains { if case .ambiguo = $0 { return true }; return false } })
let R7 = tres(caso7, "7")
ok("7: lo tapado NUNCA suma (cobra de menos, no de más)", R7.allSatisfy { r7 in r7.area <= caso7.esperado.area * 1.02 })
ok("7: y avisa que algo tapa abajo", R7.allSatisfy { r7 in r7.alarmas.contains(.tapadoAbajo) })
let R8 = tres(caso8, "8")
ok("8: el espejo NO cuenta (área menor que la verdad)", R8.allSatisfy { r8 in r8.area <= caso8.esperado.area * 1.02 })
ok("8: y sale la alarma de muy hondo", R8.allSatisfy { r8 in r8.alarmas.contains { if case .hondo = $0 { return true }; return false } })
let R9 = tres(caso9, "9")
ok("9: el paso abierto da 0 pies", R9.allSatisfy { r9 in r9.area == 0 })
ok("9: y sale la alarma de muy hondo", R9.allSatisfy { r9 in r9.alarmas.contains { if case .hondo = $0 { return true }; return false } })
let R10 = tres(caso10, "10")
ok("10: el sótano sin terminar da 0 pies (no hay orilla: no hay prueba de que hubo drywall)", R10.allSatisfy { r10 in r10.area == 0 })
let R11 = tres(caso11, "11")
ok("11: sin piso no hay número", R11.allSatisfy { r11 in r11.area == 0 && r11.alto == nil && r11.alarmas.contains(.sinPiso) })

// ---------------- LA CONVENCIÓN DE LA CÁMARA (la que usa el teléfono) ----------------
// Un mapa de 256 x 192 "acostado" de un plano conocido, con los intrínsecos escalados de 1920 x 1440: los puntos que
// salen de `puntos(...)` tienen que caer en ese plano, en el lugar correcto.
do {
    let W = 256, H = 192, esc: Float = 256.0 / 1920.0
    let fx: Float = 1440 * esc, fy: Float = 1440 * esc, cx: Float = 960 * esc, cy: Float = 720 * esc
    // La cámara en (1, 1.2, 2) mirando hacia -z, girada 20° a la izquierda.
    let ang: Float = 20 * .pi / 180
    var m = matrix_identity_float4x4
    m.columns.0 = SIMD4(cos(ang), 0, -sin(ang), 0)
    m.columns.2 = SIMD4(sin(ang), 0, cos(ang), 0)
    m.columns.3 = SIMD4(1, 1.2, 2, 1)
    // El plano z = 0 del mundo. Para cada pixel, la profundidad (distancia al PLANO de la cámara) donde pega.
    var prof = [Float](repeating: 0, count: W * H)
    for y in 0..<H { for x in 0..<W {
        let dl = SIMD3<Float>((Float(x) - cx) / fx, -(Float(y) - cy) / fy, -1)      // en la cámara, con z = -1
        let dw4 = m * SIMD4(dl.x, dl.y, dl.z, 0); let dw = SIMD3(dw4.x, dw4.y, dw4.z)
        let t = -m.columns.3.z / dw.z
        prof[y * W + x] = t      // con z local = -1, t es la profundidad
    } }
    let pts = C.puntos(profundidad: prof, confianza: nil, ancho: W, alto: H, fx: fx, fy: fy, cx: cx, cy: cy, camaraAMundo: m, paso: 4)
    let peor = pts.map { abs($0.z) }.max() ?? 1
    ok("convención: los puntos caen en el plano de la pared (peor \(String(format: "%.2f", peor * 1000)) mm)", peor < 0.001)
    // El pixel de arriba a la izquierda tiene que quedar ARRIBA y a la IZQUIERDA del centro (visto desde la cámara).
    let p0 = C.puntos(profundidad: [prof[0]], confianza: nil, ancho: 1, alto: 1, fx: fx, fy: fy, cx: cx, cy: cy, camaraAMundo: m, paso: 1)
    ok("convención: la y de la imagen crece para abajo (el pixel 0,0 queda arriba)", p0.first.map { $0.y > 1.2 } ?? false)
}

// ---------------- LA PINTURA ----------------
do {
    let (r, comp) = correr(caso1)
    let img = comp.pintar(r, px: 4)
    var naranja = 0
    for i in stride(from: 0, to: img.rgba.count, by: 4) where img.rgba[i] == C.naranja.0 && img.rgba[i + 1] == C.naranja.1 && img.rgba[i + 3] > 0 { naranja += 1 }
    let areaPintada = Float(naranja) / 16 * C.celda * C.celda
    ok("pintura: lo naranja es lo que se cuenta (\(String(format: "%.1f", areaPintada / (pie * pie))) SF pintados vs \(String(format: "%.1f", r.area / (pie * pie))) SF)", abs(areaPintada - r.area) <= r.area * 0.08)
}

do {
    semilla = 0x5EED
    let (_, comp) = correr(caso1)
    let verdad = 0 - fijarBajo.y
    ok("el piso que mide el comparador (frente a la pared) cae a ±0.5 in del de verdad (\(String(format: "%+.2f", ((comp.pisoRef ?? 99) - verdad) / pulg)) in)", comp.pisoRef.map { abs($0 - verdad) <= 0.5 * pulg } ?? false)
}

print("\n  \(pasan) pasan, \(fallan) fallan")
exit(fallan == 0 ? 0 : 1)
