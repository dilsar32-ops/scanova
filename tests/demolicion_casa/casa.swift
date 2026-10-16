// LA CASA EN 3D para probar lo demolido CON LA UBICACIÓN (16 oct 2026).
// A diferencia del banco de una sola pared (tests/demolicion/escena.swift), aquí hay un CUARTO de verdad: cuatro paredes
// que se tocan en las esquinas (cada una con su stud de esquina y su cuerpo sólido detrás), piso, techo, puertas,
// ventanas y cortes de cualquier forma en cualquier pared: de la esquina a la mitad, de esquina a esquina, dos cortes en
// la misma pared, escalones de alto, cortes que doblan la esquina. Usa azar/gauss/Caja/cruzaCaja de escena.swift.
import Foundation
import simd

struct Corte { var x0: Float; var x1: Float; var alto: Float }   // en la pared: desde su esquina a, en metros
struct Puerta { var x0: Float; var x1: Float }                   // paso de 6'-8"
struct Ventana { var x0: Float; var x1: Float; var y0: Float; var y1: Float }

struct ParedCasa {
    var nombre: String
    var a: SIMD2<Float>, b: SIMD2<Float>          // esquinas en el piso (x, z del mundo)
    var n: SIMD2<Float>                           // la normal hacia el cuarto (x, z)
    var alto: Float = 8 * pie
    var marco: Float = 3.5 * pulg
    var separacion: Float = 16 * pulg
    var drywall: Float = 0.5 * pulg
    var esquina: Float = 1.5 * pulg               // el stud de cada esquina
    var cortes: [Corte] = []
    var puertas: [Puerta] = []
    var ventanas: [Ventana] = []
    var insulacion = false
    var largo: Float { simd_length(b - a) }
    var ex: SIMD2<Float> { simd_normalize(b - a) }
    // Del mundo a lo local: x a lo largo (desde a), y para arriba, z hacia el cuarto (cara en z = 0).
    func local(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let q = SIMD2(p.x, p.z) - a
        return SIMD3(simd_dot(q, ex), p.y, simd_dot(q, n))
    }
    func localDir(_ d: SIMD3<Float>) -> SIMD3<Float> { SIMD3(simd_dot(SIMD2(d.x, d.z), ex), d.y, simd_dot(SIMD2(d.x, d.z), n)) }
    func enCorte(_ p: SIMD3<Float>) -> Corte? { cortes.first { p.x >= $0.x0 && p.x <= $0.x1 && p.y >= 0 && p.y <= $0.alto } }
    // Los studs, en lo local: los de la cuadrícula, los de las dos esquinas, la solera, y el cuerpo sólido fuera de la pared.
    func cajasDetras() -> [Caja] {
        var out: [Caja] = []
        let fondo = -(drywall + marco), cara = -drywall
        var x = separacion
        while x < largo - esquina { out.append(Caja(lo: SIMD3(x - 0.75 * pulg, 0, fondo), hi: SIMD3(x + 0.75 * pulg, alto, cara))); x += separacion }
        out.append(Caja(lo: SIMD3(0, 0, fondo), hi: SIMD3(esquina, alto, cara)))
        out.append(Caja(lo: SIMD3(largo - esquina, 0, fondo), hi: SIMD3(largo, alto, cara)))
        out.append(Caja(lo: SIMD3(0, 0, fondo), hi: SIMD3(largo, 1.5 * pulg, cara)))
        // Puertas y ventanas: stud rey + stud de apoyo (3 in) a cada lado; la ventana con su solera (1.5 in) abajo.
        for pu in puertas {
            out.append(Caja(lo: SIMD3(pu.x0 - 3 * pulg, 0, fondo), hi: SIMD3(pu.x0, alto, cara)))
            out.append(Caja(lo: SIMD3(pu.x1, 0, fondo), hi: SIMD3(pu.x1 + 3 * pulg, alto, cara)))
        }
        for v in ventanas {
            out.append(Caja(lo: SIMD3(v.x0 - 3 * pulg, 0, fondo), hi: SIMD3(v.x0, alto, cara)))
            out.append(Caja(lo: SIMD3(v.x1, 0, fondo), hi: SIMD3(v.x1 + 3 * pulg, alto, cara)))
            out.append(Caja(lo: SIMD3(v.x0, v.y0 - 1.5 * pulg, fondo), hi: SIMD3(v.x1, v.y0, cara)))
        }
        out.append(Caja(lo: SIMD3(-3, -1, -3), hi: SIMD3(0, alto + 1, cara)))
        out.append(Caja(lo: SIMD3(largo, -1, -3), hi: SIMD3(largo + 3, alto + 1, cara)))
        return out
    }
    // Lo primero que pega el rayo en ESTA pared (t a lo largo del rayo), o nil.
    func lanzar(_ ow: SIMD3<Float>, _ dw: SIMD3<Float>) -> Float? {
        let o = local(ow), d = localDir(dw)
        guard d.z < -1e-6 else { return nil }
        let tCara = -o.z / d.z
        guard tCara > 1e-5 else { return nil }
        let p = o + d * tCara
        guard p.y >= 0, p.y <= alto, p.x >= 0, p.x <= largo else { return nil }
        if puertas.contains(where: { p.x >= $0.x0 && p.x <= $0.x1 && p.y <= 80 * pulg }) { return (-3 - o.z) / d.z }
        if ventanas.contains(where: { p.x >= $0.x0 && p.x <= $0.x1 && p.y >= $0.y0 && p.y <= $0.y1 }) { return (-4 - o.z) / d.z }
        guard enCorte(p) != nil else { return tCara }
        var t = Float.infinity
        for c in cajasDetras() { if let tc = cruzaCaja(o, d, c) { t = min(t, tc) } }
        if insulacion { t = min(t, (-drywall - o.z) / d.z) }
        t = min(t, (-(drywall + marco) - o.z) / d.z)
        return t
    }
}

struct Casa {
    var paredes: [ParedCasa]
    var alto: Float = 8 * pie
    var cajas: [Caja] = []                       // secadores, cajas
    // El cuarto de L x D con la pared 0 (la que se mide) en z = 0, de x = 0 a x = L. Las demás en orden contra reloj.
    static func cuarto(L: Float, D: Float) -> Casa {
        Casa(paredes: [
            ParedCasa(nombre: "sur", a: SIMD2(0, 0), b: SIMD2(L, 0), n: SIMD2(0, 1)),
            ParedCasa(nombre: "este", a: SIMD2(L, 0), b: SIMD2(L, D), n: SIMD2(-1, 0)),
            ParedCasa(nombre: "norte", a: SIMD2(L, D), b: SIMD2(0, D), n: SIMD2(0, -1)),
            ParedCasa(nombre: "oeste", a: SIMD2(0, D), b: SIMD2(0, 0), n: SIMD2(1, 0)),
        ])
    }
    func lanzar(_ o: SIMD3<Float>, _ d: SIMD3<Float>) -> Float? {
        var mejor = Float.infinity
        for c in cajas { if let t = cruzaCaja(o, d, c) { mejor = min(mejor, t) } }
        if d.y < -1e-6 { mejor = min(mejor, -o.y / d.y) }
        if d.y > 1e-6 { mejor = min(mejor, (alto - o.y) / d.y) }
        for p in paredes { if let t = p.lanzar(o, d) { mejor = min(mejor, t) } }
        return mejor.isFinite ? mejor : nil
    }
}
