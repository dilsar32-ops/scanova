// La escena del banco sintético (compartida por tests/demolicion/main.swift y tests/demolicion_grabacion/main.swift).
import Foundation
import simd

let pulg: Float = 0.0254, pie: Float = 0.3048

// ---------------- números al azar repetibles ----------------
var semilla: UInt64 = 0x5EED
func azar() -> Float { semilla = semilla &* 6364136223846793005 &+ 1442695040888963407; return Float(semilla >> 40) / Float(1 << 24) }
func gauss() -> Float { let a = max(azar(), 1e-6), b = azar(); return sqrt(-2 * log(a)) * cos(2 * .pi * b) }

// ---------------- LA ESCENA ----------------
// La pared está en z = 0 (la cara del drywall), el cuarto en z > 0, el piso en y = 0, la pared corre en x.
struct Caja { var lo: SIMD3<Float>; var hi: SIMD3<Float> }
func cruzaCaja(_ o: SIMD3<Float>, _ d: SIMD3<Float>, _ b: Caja) -> Float? {
    var t0: Float = 0, t1: Float = .infinity
    for i in 0..<3 {
        if abs(d[i]) < 1e-9 { if o[i] < b.lo[i] || o[i] > b.hi[i] { return nil }; continue }
        var a = (b.lo[i] - o[i]) / d[i], c = (b.hi[i] - o[i]) / d[i]
        if a > c { swap(&a, &c) }
        t0 = max(t0, a); t1 = min(t1, c)
        if t0 > t1 { return nil }
    }
    return t0 > 1e-5 ? t0 : nil
}
struct Escena {
    var x0: Float = 0, x1: Float = 14 * pie, alto: Float = 8 * pie   // la pared
    var corte: (x0: Float, x1: Float, alto: Float)? = nil              // lo demolido, desde el piso
    var marco: Float = 3.5 * pulg                                      // 2x4 = 3.5 in, 2x6 = 5.5 in
    var separacion: Float = 16 * pulg
    var drywall: Float = 0.5 * pulg
    var insulacion = false                                             // la batt quedó puesta, pareja con los studs
    var sinDrywallNunca = false                                        // sótano sin terminar: studs a la vista hasta arriba
    var puerta: (x0: Float, x1: Float)? = nil                          // un paso abierto de 6'-8"
    var espejo: (x0: Float, x1: Float, y0: Float, y1: Float)? = nil
    var cajas: [Caja] = []                                             // lo que tapa (un secador)
    var manchaY: Float? = nil                                          // la línea del agua: el relleno de Apple la "ve" 0.6 in
    // Studs dentro del corte (o de toda la pared si nunca tuvo drywall).
    func studs() -> [Caja] {
        var out: [Caja] = []
        var x = x0
        let fondo = -(drywall + marco)
        while x < x1 {
            out.append(Caja(lo: SIMD3(x, 0, fondo), hi: SIMD3(x + 1.5 * pulg, alto, -drywall)))
            x += separacion
        }
        out.append(Caja(lo: SIMD3(x0, 0, fondo), hi: SIMD3(x1, 1.5 * pulg, -drywall)))   // la solera
        return out
    }
    func enCorte(_ p: SIMD3<Float>) -> Bool {
        if sinDrywallNunca { return p.x >= x0 && p.x <= x1 && p.y >= 0 && p.y <= alto }
        guard let c = corte else { return false }
        return p.x >= c.x0 && p.x <= c.x1 && p.y >= 0 && p.y <= c.alto
    }
    // El rango (distancia a lo largo del rayo) a lo primero que pega.
    func lanzar(_ o: SIMD3<Float>, _ d: SIMD3<Float>) -> Float? {
        var mejor: Float = .infinity
        for b in cajas { if let t = cruzaCaja(o, d, b) { mejor = min(mejor, t) } }
        if d.y < 0 { let t = -o.y / d.y; let p = o + d * t; if p.z >= 0, t < mejor { mejor = t } }      // el piso del cuarto
        guard d.z < 0 else { return mejor.isFinite ? mejor : nil }
        let tCara = -o.z / d.z
        guard tCara < mejor else { return mejor }
        let p = o + d * tCara
        guard p.x >= x0 - 3, p.x <= x1 + 3, p.y >= 0, p.y <= alto else { return mejor.isFinite ? mejor : nil }
        if p.x < x0 || p.x > x1 { return tCara }              // las otras paredes del cuarto, en el mismo plano
        if let pu = puerta, p.x >= pu.x0, p.x <= pu.x1, p.y <= 80 * pulg {
            let tFondo = (-3 - o.z) / d.z                       // el otro cuarto, 3 m atrás
            return min(mejor, tFondo)
        }
        if let e = espejo, p.x >= e.x0, p.x <= e.x1, p.y >= e.y0, p.y <= e.y1 {
            return tCara * 2 + 0.6                              // el reflejo: muy hondo, como si siguiera
        }
        if !enCorte(p) { return tCara }                         // drywall entero
        // Dentro del corte: studs, solera, la insulación o el fondo de la cavidad.
        var t = mejor
        for b in studs() { if let tb = cruzaCaja(o, d, b) { t = min(t, tb) } }
        if insulacion { let ti = (-drywall - o.z) / d.z; t = min(t, ti) }
        let tFondo = (-(drywall + marco) - o.z) / d.z
        t = min(t, tFondo)
        return t
    }
}

