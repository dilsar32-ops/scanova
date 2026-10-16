// DemolicionEnPlano.swift — lo demolido CON LA UBICACIÓN EN EL PLANO (16 oct 2026).
//
// Su idea: "ya sabemos dónde estamos, ya sabe cuáles son paredes interiores y exteriores... ¿qué pasaría si no está
// demolida toda la pared, si solo se cortó la mitad?". El comparador (ComparadorDeDemolicion) mide en la cara de UNA
// pared; esto le pone lo que sabe el plano:
//   1. QUÉ pared del plano es la que ve el láser (con la ubicación: el plano de ARKit pasado al plano de la casa).
//   2. DÓNDE están sus dos esquinas en la cara, afinadas con los planos de ARKit de las paredes de al lado (centímetros;
//      la ubicación sola trae unas pulgadas de error). Con eso el corte que llega a la esquina se mide hasta la esquina y
//      lo que está del otro lado de la esquina (la otra pared) ya no cuenta ni avisa.
//   3. EL REPORTE como lo dice la cuadrilla: "de la esquina 0'-0" a 6'-0", alto 2'-0"", si es pared de afuera, y qué
//      pedazo de la pared falta ver.
// La ubicación NUNCA pone pulgadas: escoge la pared y la esquina. Las pulgadas las mide el láser.
//
// Swift puro (Foundation + simd): lo corre el teléfono y la prueba de la Mac (tests/demolicion_casa). Idéntico en las
// dos apps.

import Foundation
import simd

struct DemolicionEnPlano {

    // plano (pies) = R(giro) · (ARKit x,z en pies) + mov — lo mismo que UbicadorEnPlano.Acomodo.
    struct Acomodo2D { var giro: Double; var mov: SIMD2<Double> }
    struct Pared { var a: SIMD2<Double>; var b: SIMD2<Double>; var exterior: Bool }      // pies, en el plano
    struct PlanoAR { var punto: SIMD3<Float>; var normal: SIMD3<Float> }                  // un plano vertical de ARKit
    struct Abertura { var centro: SIMD2<Double>; var ancho: Double; var esPuerta: Bool }  // pies, en el plano (sobre la pared)
    static let piesPorMetro = 3.28084

    static func alPlano(_ p: SIMD2<Float>, _ ac: Acomodo2D) -> SIMD2<Double> {
        let q = SIMD2<Double>(Double(p.x), Double(p.y)) * piesPorMetro
        let c = cos(ac.giro), s = sin(ac.giro)
        return SIMD2(c * q.x - s * q.y, s * q.x + c * q.y) + ac.mov
    }
    static func alAR(_ q: SIMD2<Double>, _ ac: Acomodo2D) -> SIMD2<Float> {
        let r = q - ac.mov
        let c = cos(-ac.giro), s = sin(-ac.giro)
        let p = SIMD2(c * r.x - s * r.y, s * r.x + c * r.y) / piesPorMetro
        return SIMD2(Float(p.x), Float(p.y))
    }
    static func girar(_ v: SIMD2<Double>, _ g: Double) -> SIMD2<Double> { SIMD2(cos(g) * v.x - sin(g) * v.y, sin(g) * v.x + cos(g) * v.y) }

    // ---------------- 1. ¿QUÉ PARED DEL PLANO ES? ----------------
    // La pared paralela (25° o menos) cuya línea pasa a 2 ft o menos del plano de ARKit, y que lo tiene enfrente (no más
    // de 1 ft pasado de sus puntas). Si dos califican, la más cerca. nil = el plano no es de ninguna pared conocida.
    static func paredDe(_ plano: PlanoAR, paredes: [Pared], acomodo ac: Acomodo2D) -> Int? {
        let p = alPlano(SIMD2(plano.punto.x, plano.punto.z), ac)
        var n = girar(SIMD2(Double(plano.normal.x), Double(plano.normal.z)), ac.giro)
        guard simd_length(n) > 0.3 else { return nil }
        n = simd_normalize(n)
        var mejor: (Int, Double)? = nil
        for (i, w) in paredes.enumerated() {
            let d = w.b - w.a, largo = simd_length(d)
            guard largo > 0.5 else { continue }
            let u = d / largo
            guard abs(simd_dot(u, n)) < 0.42 else { continue }              // paralela: la normal casi perpendicular a la pared
            let t = simd_dot(p - w.a, u)
            guard t > -1, t < largo + 1 else { continue }
            let dist = abs(simd_dot(p - w.a, SIMD2(-u.y, u.x)))
            guard dist < 2.0 else { continue }
            if mejor == nil || dist < mejor!.1 { mejor = (i, dist) }
        }
        return mejor?.0
    }

    // ---------------- LA CARA PARA ESA PARED ----------------
    // El plano de ARKit dice dónde está la cara (milímetros); el plano de la casa dice dónde está la mitad de la pared
    // (para centrar la rejilla de 12 m). El origen queda a `alto` del piso: arriba de un corte de 4 ft.
    static let altoOrigen: Float = 1.30
    static func cara(para pared: Pared, plano: PlanoAR, acomodo ac: Acomodo2D, pisoY: Float, telefono: SIMD3<Float>,
                     alto: Float = altoOrigen) -> ComparadorDeDemolicion.Cara? {
        let m2 = alAR((pared.a + pared.b) / 2, ac)
        var m = SIMD3<Float>(m2.x, pisoY + alto, m2.y)
        var n = SIMD3<Float>(plano.normal.x, 0, plano.normal.z)
        guard simd_length(n) > 0.2 else { return nil }
        n = simd_normalize(n)
        m -= n * simd_dot(m - plano.punto, n)
        m.y = pisoY + alto
        return ComparadorDeDemolicion.Cara.desde(punto: m, normal: n, telefono: telefono)
    }

    // ---------------- 2. LAS ESQUINAS EN LA CARA ----------------
    // Las puntas de la pared del plano, pasadas a la cara (u, m). Cada una se afina con el plano de ARKit de la pared que
    // la cruza (60° o más de ángulo) si cae a 1 ft o menos de lo que dice el plano. Una esquina que NO se afinó trae el
    // error de la ubicación (unas pulgadas): ahí no se recorta ni se lleva el corte hasta la esquina (podría cobrar de más).
    struct Esquinas {
        var u: ClosedRange<Float>; var uDeA: Float
        var afinadaMenor = false, afinadaMayor = false
        var afinadas: Int { (afinadaMenor ? 1 : 0) + (afinadaMayor ? 1 : 0) }
        // Lo que se le pasa al comparador: solo las esquinas afinadas cortan.
        var limites: ClosedRange<Float> { (afinadaMenor ? u.lowerBound : -.infinity)...(afinadaMayor ? u.upperBound : .infinity) }
    }
    static func esquinas(_ cara: ComparadorDeDemolicion.Cara, pared: Pared, acomodo ac: Acomodo2D, otros: [PlanoAR]) -> Esquinas {
        func uDe(_ q: SIMD2<Double>) -> Float {
            let p = alAR(q, ac)
            return simd_dot(SIMD3(p.x, cara.origen.y, p.y) - cara.origen, cara.u)
        }
        var ua = uDe(pared.a), ub = uDe(pared.b)
        var finaA = false, finaB = false
        // La línea de la cara en el piso: origen + u·t. La de otro plano: punto + w·s (w acostada, perpendicular a su normal).
        let o2 = SIMD2(cara.origen.x, cara.origen.z), d2 = simd_normalize(SIMD2(cara.u.x, cara.u.z))
        var cruces: [Float] = []
        for pl in otros {
            var n2 = SIMD2(pl.normal.x, pl.normal.z)
            guard simd_length(n2) > 0.3 else { continue }
            n2 = simd_normalize(n2)
            guard abs(simd_dot(n2, d2)) > 0.86 else { continue }        // 60° o más con la cara (la normal casi a lo largo)
            // n2 · (o2 + d2·t - p2) = 0
            let den = simd_dot(n2, d2)
            let t = simd_dot(n2, SIMD2(pl.punto.x, pl.punto.z) - o2) / den
            cruces.append(t)
        }
        let unPie: Float = 0.3048
        for (i, esq) in [ua, ub].enumerated() {
            guard let c = cruces.min(by: { abs($0 - esq) < abs($1 - esq) }), abs(c - esq) <= unPie else { continue }
            if i == 0 { ua = c; finaA = true } else { ub = c; finaB = true }
        }
        var e = Esquinas(u: min(ua, ub)...max(ua, ub), uDeA: ua)
        e.afinadaMenor = ua <= ub ? finaA : finaB
        e.afinadaMayor = ua <= ub ? finaB : finaA
        return e
    }

    // ---------------- 3. EL REPORTE EN LA PARED ----------------
    struct Tramo: Equatable {
        var desde: Float, hasta: Float        // m, medidos desde la esquina `a` de la pared del plano
        var alto: Float                       // m
        var area: Float                       // m²
        var hastaEsquinaA: Bool, hastaEsquinaB: Bool
    }
    struct Reporte {
        var tramos: [Tramo] = []
        var area: Float = 0
        var faltaVer: [ClosedRange<Float>] = []   // m desde la esquina `a`: pedazos de 1 ft o más que el láser no vio
        var largoPared: Float = 0
        var exterior = false
        var alarmas: [ComparadorDeDemolicion.Alarma] = []
    }
    // Las puertas y ventanas del plano que caen en ESTA pared, pasadas a la cara (u, m). La ubicación trae unas pulgadas
    // de error: la PUERTA se toma 2 in más angosta de cada lado (su orilla se deja sin juzgar antes que borrar un corte
    // de verdad); la VENTANA 4 in más ancha (bajo ella solo cuenta el hueco visto desde el piso, que nunca cobra de más:
    // al lado de la ventana el corte ya tiene su orilla vista y no se toca).
    static func aberturasEnCara(_ cara: ComparadorDeDemolicion.Cara, pared: Pared, aberturas: [Abertura], acomodo ac: Acomodo2D)
        -> (ventanas: [ClosedRange<Float>], puertas: [ClosedRange<Float>]) {
        let d = pared.b - pared.a, largo = simd_length(d)
        guard largo > 0.5 else { return ([], []) }
        let u = d / largo
        var vs: [ClosedRange<Float>] = [], ps: [ClosedRange<Float>] = []
        let pulg = ComparadorDeDemolicion.pulgada
        for ab in aberturas {
            let t = simd_dot(ab.centro - pared.a, u)
            guard t > -0.5, t < largo + 0.5, abs(simd_dot(ab.centro - pared.a, SIMD2(-u.y, u.x))) < 1.5 else { continue }
            let p = alAR(ab.centro, ac)
            let uc = simd_dot(SIMD3(p.x, cara.origen.y, p.y) - cara.origen, cara.u)
            let medio = Float(ab.ancho / piesPorMetro) / 2 + (ab.esPuerta ? -2 * pulg : 4 * pulg)
            guard medio > 0 else { continue }
            if ab.esPuerta { ps.append((uc - medio)...(uc + medio)) } else { vs.append((uc - medio)...(uc + medio)) }
        }
        return (vs, ps)
    }

    static func reporte(_ comp: ComparadorDeDemolicion, esquinas e: Esquinas, pared: Pared, piso: Float? = nil,
                        ventanas: [ClosedRange<Float>] = [], puertas: [ClosedRange<Float>] = [], desdeLaIzquierda: Bool = false) -> Reporte {
        let res = comp.resultado(piso: piso, limites: e.limites, ventanas: ventanas, puertas: puertas)
        return reporte(res, comp: comp, esquinas: e, pared: pared, puertas: puertas, desdeLaIzquierda: desdeLaIzquierda)
    }
    // Con el resultado ya calculado (el teléfono lo calcula una vez por cuadro y lo usa también para pintar la pared).
    // `desdeLaIzquierda`: las distancias desde la esquina de la IZQUIERDA viendo la pared (u menor), no desde la `a` del
    // plano: así se lo dice uno a la cuadrilla parado frente a la pared.
    static func reporte(_ res: ComparadorDeDemolicion.Resultado, comp: ComparadorDeDemolicion, esquinas e: Esquinas, pared: Pared,
                        puertas: [ClosedRange<Float>] = [], desdeLaIzquierda: Bool = false) -> Reporte {
        var rep = Reporte()
        rep.largoPared = e.u.upperBound - e.u.lowerBound
        rep.exterior = pared.exterior
        rep.alarmas = res.alarmas
        rep.area = res.area
        let aEsMenor = desdeLaIzquierda || abs(e.uDeA - e.u.lowerBound) <= abs(e.uDeA - e.u.upperBound)
        func desdeA(_ u: Float) -> Float { aEsMenor ? u - e.u.lowerBound : e.u.upperBound - u }
        if res.area > 0 {
            rep.tramos = res.tramos.map { t in
                let x0 = desdeA(t.uIni), x1 = desdeA(t.uFin)
                // Desde la esquina del plano: sin afinar puede salir una pulgada antes de 0 o después del largo.
                let lo = max(0, min(x0, x1)), hi = min(rep.largoPared, max(x0, x1))
                return Tramo(desde: lo, hasta: hi, alto: t.alto, area: t.area,
                             hastaEsquinaA: aEsMenor ? t.esquinaIni : t.esquinaFin, hastaEsquinaB: aEsMenor ? t.esquinaFin : t.esquinaIni)
            }.sorted { $0.desde < $1.desde }
        }
        // Lo que falta ver: columnas dentro de la pared que no se decidieron (sin ver, o hueco sin su orilla de arriba),
        // en pedazos de 1 ft o más. Las puertas no cuentan (ahí no hay pared que ver).
        let celda = ComparadorDeDemolicion.celda
        var u = e.u.lowerBound + celda / 2
        var ini: Float? = nil
        func decidida(_ c: Int) -> Bool {
            let k = c - res.colIni
            guard k >= 0, k < res.columnas.count else { return false }
            switch res.columnas[k] { case .noVista, .sinOrilla: return false; default: return true }
        }
        func cerrar(_ hasta: Float) {
            guard let i = ini else { return }
            if hasta - i >= 0.3048 { let x0 = desdeA(i), x1 = desdeA(hasta); rep.faltaVer.append(min(x0, x1)...max(x0, x1)) }
            ini = nil
        }
        while u < e.u.upperBound {
            var visto = puertas.contains { $0.contains(u) }
            if !visto, let c = ComparadorDeDemolicion.columnaDe(u) { visto = decidida(c) }
            if !visto { if ini == nil { ini = u - celda / 2 } } else { cerrar(u - celda / 2) }
            u += celda
        }
        cerrar(e.u.upperBound)
        rep.faltaVer.sort { $0.lowerBound < $1.lowerBound }
        return rep
    }
}
