// LA GRABADORA DE PUNTA A PUNTA (15 oct 2026). Se arman mapas de profundidad COMO LOS DEL iPHONE (256 x 192, acostados,
// intrínsecos de la foto de 1920 x 1440 escalados, profundidad = distancia al plano de la cámara) de la pared sintética
// con un corte de 2 ft, se graban con GrabadoraDeBarrido, se leen otra vez y el comparador corre sobre lo leído. Tiene
// que dar lo mismo que corrido en vivo (lo único que cambia es el redondeo a milímetros).
import Foundation
import simd

typealias C = ComparadorDeDemolicion
var pasan = 0, fallan = 0
func ok(_ l: String, _ c: Bool, _ d: String = "") { if c { pasan += 1; print("  ok  " + l) } else { fallan += 1; print("  FALLA " + l + "  " + d) } }

let carpeta = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory())
let archivo = carpeta.appendingPathComponent("barrido-prueba.scb")
// El corte termina a la mitad de un stud en las dos puntas (así se corta en obra, para clavar el drywall nuevo).
var e = Escena(); e.corte = (32.75 * pulg, 128.75 * pulg, 2 * pie)
let fijar = SIMD3<Float>(7 * pie, 1.10, 0)
guard let cara = C.Cara.desde(punto: fijar, normal: SIMD3(0, 0, 1), telefono: SIMD3(fijar.x, 1, 1)) else { fatalError() }
let W = 256, H = 192, esc: Float = 256.0 / 1920.0
let fx: Float = 1450 * esc, fy: Float = 1450 * esc, cx: Float = 959.5 * esc, cy: Float = 719.5 * esc
let paso = 2
guard let grab = GrabadoraDeBarrido(url: archivo, meta: ["modelo": "banco", "ios": "-", "paso": paso, "confianzaMin": 2]) else { fatalError("no se pudo crear") }
grab.evento(t: 0, ["evento": "fijar", "cara": LectorDeBarrido.caraComoLista(cara)])
var vivo = C()
let cuadros = 150
for k in 0..<cuadros {
    let f = Float(k) / Float(cuadros - 1)
    // El teléfono acostado (landscape) mirando la pared, a 1.2 m, cabeceando 12-34° hacia abajo.
    let pitch = (12 + 22 * (0.5 + 0.5 * sin(Float(k) * 0.35))) * Float.pi / 180
    let cam = SIMD3<Float>(-0.3 + (14 * pie + 0.6) * f, 1.0, 1.2)
    let adelante = SIMD3<Float>(0, -sin(pitch), -cos(pitch))
    let derecha = SIMD3<Float>(1, 0, 0)
    let arriba = simd_cross(derecha, adelante)
    // camaraAMundo: columnas = x (derecha), y (arriba), z (= -adelante), posición.
    var m = matrix_identity_float4x4
    m.columns.0 = SIMD4(derecha, 0); m.columns.1 = SIMD4(arriba, 0); m.columns.2 = SIMD4(-adelante, 0); m.columns.3 = SIMD4(cam, 1)
    var prof = [Float](repeating: .nan, count: W * H)
    var conf = [UInt8](repeating: 0, count: W * H)
    // Ruido como el del sensor: parejo (2 mm) y que se mueve junto (el relleno de Apple), distinto en cada cuadro.
    let a1 = gauss() * 0.0015, a2 = gauss() * 0.0015, p1 = azar(), p2 = azar()
    for y in 0..<H { for x in 0..<W {
        let dl = SIMD3<Float>((Float(x) - cx) / fx, -(Float(y) - cy) / fy, -1)
        let d = simd_normalize(derecha * dl.x + arriba * dl.y + adelante * 1)
        guard let t = e.lanzar(cam, d), t < 5 else { continue }
        // profundidad = distancia al PLANO de la cámara = t·(d·adelante)
        prof[y * W + x] = t * simd_dot(d, adelante) + gauss() * 0.002
            + a1 * sin(2 * .pi * (Float(x) / Float(W) * 1.7 + p1)) + a2 * sin(2 * .pi * (Float(y) / Float(H) * 1.3 + p2))
        conf[y * W + x] = 2
    } }
    // Las orillas: donde la profundidad brinca más de 3 cm, la confianza baja (casi siempre) y se tira.
    for y in 1..<(H - 1) { for x in 1..<(W - 1) {
        let k = y * W + x, v = prof[k]
        guard v.isFinite else { continue }
        if [prof[k - 1], prof[k + 1], prof[k - W], prof[k + W]].contains(where: { $0.isFinite && abs($0 - v) > 0.03 }), azar() < 0.75 { conf[k] = 1 }
    } }
    let ex: [String: Any] = ["cara": LectorDeBarrido.caraComoLista(cara), "rastreo": "normal"]
    grab.profundidad(t: Double(k) * 0.2, ancho: W, alto: H, metros: prof, confianza: conf, pose: m, fx: fx, fy: fy, cx: cx, cy: cy, extra: ex)
    let pts = C.puntos(profundidad: prof, confianza: conf, ancho: W, alto: H, fx: fx, fy: fy, cx: cx, cy: cy, camaraAMundo: m, paso: paso)
    vivo.votar(camara: cam, puntos: pts, cara: cara)
}
let rVivo = vivo.resultado()
grab.evento(t: 30, ["evento": "resumen", "texto": "en vivo: \(rVivo.area)"])
grab.cerrar()
let mb = Double(grab.bytes) / 1_048_576
print(String(format: "  grabación: %d cuadros, %.1f MB (%.1f MB por minuto)", grab.cuadros, mb, mb / 30 * 60))
do {
    let regs = try LectorDeBarrido.leer(archivo)
    let paredes = LectorDeBarrido.repetir(regs)
    ok("se lee la grabación: 1 pared, \(cuadros) cuadros", paredes.count == 1 && paredes.first?.cuadros == cuadros)
    if let p = paredes.first {
        let r = p.comparador.resultado()
        print(String(format: "  en vivo: %.2f SF, alto %.2f in · leído: %.2f SF, alto %.2f in", rVivo.area / (pie * pie), (rVivo.alto ?? 0) / pulg, r.area / (pie * pie), (r.alto ?? 0) / pulg))
        ok("lo leído da el mismo número que en vivo (±1%)", rVivo.area > 0 && abs(r.area - rVivo.area) <= rVivo.area * 0.01)
        ok("y el mismo alto (±0.1 in)", abs((r.alto ?? -1) - (rVivo.alto ?? -2)) <= 0.1 * pulg)
        ok("con mapas como los del iPhone (256 x 192) el corte de 2 ft x 8 ft sale a ±1 in y entre -6% y +3%", abs((r.alto ?? 0) - 2 * pie) <= 1 * pulg && r.area >= 16 * pie * pie * 0.94 && r.area <= 16 * pie * pie * 1.03)
        ok("el resumen del teléfono viaja en la grabación", (p.resumenTelefono?["texto"] as? String)?.hasPrefix("en vivo") == true)
    }
    ok("pesa menos de 35 MB por minuto (tope de 3 min)", mb / 30 * 60 < 35)
} catch { ok("leer la grabación", false, "\(error)") }
print("\n  \(pasan) pasan, \(fallan) fallan")
exit(fallan == 0 ? 0 : 1)
