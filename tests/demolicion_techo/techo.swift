// EL TECHO EN 3D para probar lo demolido (15 oct 2026, su pedido "ahora pruébela para el techo").
// Un cuarto de L x D con su techo a 8 ft: drywall de 1/2 in, encima las vigas (2x8, 2x10...) cada 16 o 24 in y el
// subpiso del piso de arriba; o el ático: cuerdas de abajo de las cerchas (2x4) y el techo de la casa muy arriba.
// Los huecos son rectángulos (x, z) en el techo; también lámparas empotradas, rejillas, un abanico. Usa azar/gauss/
// Caja/cruzaCaja de tests/demolicion/escena.swift.
import Foundation
import simd

struct Hueco { var x0: Float; var x1: Float; var z0: Float; var z1: Float }

struct CuartoTecho {
    var L: Float = 14 * pie, D: Float = 12 * pie, H: Float = 8 * pie
    var drywall: Float = 0.5 * pulg
    var viga: Float = 7.25 * pulg                 // 2x8; 2x10 = 9.25; cuerda de cercha 2x4 = 3.5
    var separacion: Float = 16 * pulg
    var vigasEnX = false                          // las vigas corren a lo largo de x (si no, a lo largo de z)
    var atico = false                             // arriba del techo hay ático (muy hondo), no un subpiso
    var huecos: [Hueco] = []
    var empotradas: [SIMD2<Float>] = []           // lámparas de 6 in, 7 in de hondo
    var rejillas: [Hueco] = []                    // rejilla del aire: un hueco chico de 4 in de hondo
    var cajas: [Caja] = []                        // un abanico, una lámpara colgada (delante del techo)
    var mancha: SIMD2<Float>? = nil               // la mancha del agua (anillo de 3 ft): el relleno de Apple ve 0.6 in

    func enHueco(_ x: Float, _ z: Float) -> Bool { huecos.contains { x >= $0.x0 && x <= $0.x1 && z >= $0.z0 && z <= $0.z1 } }
    // Las vigas (o cuerdas) como cajas, la placa de arriba de cada pared y el subpiso.
    func cajasArriba() -> [Caja] {
        var out: [Caja] = []
        let y0 = H + drywall, y1 = H + drywall + viga
        let largo = vigasEnX ? D : L
        var s = separacion
        while s < largo - 1 * pulg {
            if vigasEnX { out.append(Caja(lo: SIMD3(-1, y0, s - 0.75 * pulg), hi: SIMD3(L + 1, y1, s + 0.75 * pulg))) }
            else { out.append(Caja(lo: SIMD3(s - 0.75 * pulg, y0, -1), hi: SIMD3(s + 0.75 * pulg, y1, D + 1))) }
            s += separacion
        }
        // La placa de arriba de las cuatro paredes (3.5 in), justo arriba del techo.
        let pl = 3.5 * pulg
        out.append(Caja(lo: SIMD3(-1, y0, -1), hi: SIMD3(pl, y0 + 3 * pulg, D + 1)))
        out.append(Caja(lo: SIMD3(L - pl, y0, -1), hi: SIMD3(L + 1, y0 + 3 * pulg, D + 1)))
        out.append(Caja(lo: SIMD3(-1, y0, -1), hi: SIMD3(L + 1, y0 + 3 * pulg, pl)))
        out.append(Caja(lo: SIMD3(-1, y0, D - pl), hi: SIMD3(L + 1, y0 + 3 * pulg, D + 1)))
        return out
    }
    func lanzar(_ o: SIMD3<Float>, _ d: SIMD3<Float>) -> Float? {
        var mejor = Float.infinity
        for c in cajas { if let t = cruzaCaja(o, d, c) { mejor = min(mejor, t) } }
        if d.y < -1e-6 { mejor = min(mejor, -o.y / d.y) }                                   // el piso
        // Las paredes (planos x = 0, x = L, z = 0, z = D), hasta el techo.
        for (eje, valor) in [(0, Float(0)), (0, L), (2, Float(0)), (2, D)] {
            let dd = d[eje]; guard abs(dd) > 1e-6 else { continue }
            let t = (valor - o[eje]) / dd
            guard t > 1e-5, t < mejor else { continue }
            let p = o + d * t
            if p.y >= 0 && p.y <= H { mejor = t }
        }
        guard d.y > 1e-6 else { return mejor.isFinite ? mejor : nil }
        let tCara = (H - o.y) / d.y
        guard tCara < mejor else { return mejor }
        let p = o + d * tCara
        guard p.x >= 0, p.x <= L, p.z >= 0, p.z <= D else { return mejor.isFinite ? mejor : nil }
        // Lámpara empotrada: un tubo de 6 in con el foco a 5 in.
        for e in empotradas where simd_length(SIMD2(p.x, p.z) - e) < 3 * pulg { return min(mejor, (H + 5 * pulg - o.y) / d.y) }
        // Rejilla: 4 in de hondo.
        for r in rejillas where p.x >= r.x0 && p.x <= r.x1 && p.z >= r.z0 && p.z <= r.z1 { return min(mejor, (H + 4 * pulg - o.y) / d.y) }
        guard enHueco(p.x, p.z) else {
            // Drywall entero (con la mancha del agua que el relleno "ve" como un escalón).
            if let m = mancha, abs(simd_length(SIMD2(p.x, p.z) - m) - 1.5 * pie) < 1 * pulg { return min(mejor, tCara + 0.6 * pulg / d.y) }
            return min(mejor, tCara)
        }
        var t = mejor
        for c in cajasArriba() { if let tc = cruzaCaja(o, d, c) { t = min(t, tc) } }
        let arriba: Float = atico ? H + 1.6 : H + drywall + viga
        t = min(t, (arriba - o.y) / d.y)
        return t
    }
}
