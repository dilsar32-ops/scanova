import Foundation
import simd

// LA MALLA DEL CUARTO (16 oct, su prueba en la casa con dos fotos: "la malla debería irse mostrando de cuarto en cuarto…
// en la otra esquina me fui y no la puso bien… la malla se tiene que ayudar del localizador de cuarto y de a dónde mira el
// teléfono, se tienen que ayudar ambas").
//
// La ubicación (UbicadorEnPlano) acomoda TODO el plano con un solo giro y un solo movimiento: unas pulgadas cerca de donde
// se encontró y hasta un pie o más en la otra punta de la casa (un grado de giro son 2 in a 10 ft). Aquí, POR CUARTO, ese
// acomodo se AFINA con las paredes que el láser está viendo (los planos verticales de ARKit):
//   1. un giro y un movimiento chiquitos que pegan las paredes del plano a las de verdad (mínimos cuadrados, en dos pasadas:
//      una holgada que agarra, otra apretada que afina y tira lo que no cuadra: la cara de un mueble, la del otro cuarto);
//   2. cada pared que se ve se pega a su plano, y cada esquina sale donde se cruzan las dos paredes.
// Lo que no se ve se queda como lo dice la ubicación. Una esquina que la persona TOCA en la pantalla entra como amarre fuerte.
// Si lo que sale es mucho (más de 10° o más de 1 m) no se cree: se queda la ubicación sola.
enum MallaDelCuarto {
    typealias Ac = DemolicionEnPlano.Acomodo2D
    // Una pared que ve el LiDAR: de `a` a `b`, en metros, en el piso del AR (x, z). `n`: hacia dónde estaba el teléfono
    // cuando la vio (la cara de la pared que se ve desde ESTE cuarto mira para adentro; la del cuarto de al lado, para
    // afuera). nil = no se sabe.
    struct Vista { var a: SIMD2<Double>; var b: SIMD2<Double>; var n: SIMD2<Double>? = nil }
    // Una esquina tocada: dónde está en el plano (pies) y dónde la encontró el láser (metros, piso del AR).
    struct Pin { var plano: SIMD2<Double>; var ar: SIMD2<Double> }
    // Una pared ya acomodada, en metros del piso del AR. `vista`: pegada a lo que ve el láser. `finaA/B`: esa esquina salió
    // del cruce de dos paredes vistas (es de verdad, no de la ubicación).
    struct ParedAR { var a: SIMD2<Double>; var b: SIMD2<Double>; var vista = false; var finaA = false; var finaB = false }
    struct Ajuste {
        var ac: Ac
        var paredes: [ParedAR]          // en el mismo orden que las paredes del plano
        var vistas: Int                 // paredes del cuarto pegadas a lo que ve el láser
        var pines: Int
        var giro: Double                // lo que se corrigió (radianes)
        var mov: Double                 // cuánto se movió el centro del cuarto (metros)
        var afinado: Bool { vistas > 0 || pines > 0 }
    }
    static let k = DemolicionEnPlano.piesPorMetro
    static let maxGiro = 10.0 * .pi / 180
    static let maxMov = 1.5

    // ---------------- EL PLANO EN EL AR (en Double: aquí se suman muchos centímetros) ----------------
    static func ar(_ q: SIMD2<Double>, _ ac: Ac) -> SIMD2<Double> {
        DemolicionEnPlano.girar(q - ac.mov, -ac.giro) / k
    }
    static func perp(_ v: SIMD2<Double>) -> SIMD2<Double> { SIMD2(-v.y, v.x) }

    // P' = R(th)·(P - c) + c + t, metido en el acomodo (el plano sigue igual; lo que cambia es dónde cae en el AR).
    static func componer(_ ac: Ac, th: Double, t: SIMD2<Double>, c: SIMD2<Double>) -> Ac {
        let g = ac.giro
        let mov = ac.mov + DemolicionEnPlano.girar(c, g) * k - DemolicionEnPlano.girar(c + t, g - th) * k
        return Ac(giro: g - th, mov: mov)
    }

    // ---------------- 1. QUÉ PLANO DEL LÁSER ES DE QUÉ PARED ----------------
    struct Pareja { var pared: Int; var vista: Int; var t0: Double; var t1: Double; var dist: Double }
    // La normal de una pared que mira para ADENTRO del cuarto (hacia su centro).
    static func adentro(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>) -> SIMD2<Double> {
        let n = perp(simd_normalize(b - a))
        return simd_dot(n, c - (a + b) / 2) >= 0 ? n : -n
    }
    // ¿La vio desde este lado? (si no se sabe, sí)
    static func deEsteLado(_ v: Vista, _ ni: SIMD2<Double>) -> Bool { v.n.map { simd_dot($0, ni) > 0.3 } ?? true }
    // Paralelo (`grados` o menos), a `maxDist` metros o menos de la línea de la pared, vista desde este cuarto, y encima de
    // ella (se enciman 30 cm o más, o la mitad de una pared corta). Si varios califican: EL DE MÁS AFUERA. Lo que está
    // delante de una pared (un librero, un mueble de cocina, la tele) siempre queda más adentro que la pared.
    static func emparejar(_ pa: [(a: SIMD2<Double>, b: SIMD2<Double>)], _ vistas: [Vista], c: SIMD2<Double>,
                          maxDist: Double, grados: Double) -> [Pareja] {
        let coseno = cos(grados * .pi / 180)
        var out: [Pareja] = []
        for (i, w) in pa.enumerated() {
            let d = w.b - w.a, L = simd_length(d)
            guard L >= 0.3 else { continue }
            let u = d / L, ni = adentro(w.a, w.b, c)
            var mejor: (Pareja, Double)? = nil
            for (j, v) in vistas.enumerated() where deEsteLado(v, ni) {
                let dv0 = v.b - v.a, lv = simd_length(dv0)
                guard lv >= 0.3 else { continue }
                let dv = dv0 / lv
                guard abs(simd_dot(u, dv)) >= coseno else { continue }
                let s0 = simd_dot(v.a - w.a, u), s1 = simd_dot(v.b - w.a, u)
                let lo = max(0, min(s0, s1)), hi = min(L, max(s0, s1))
                guard hi - lo >= min(0.3, 0.5 * L) else { continue }
                let tm = (lo + hi) / 2
                let pm = v.a + dv * simd_dot(w.a + u * tm - v.a, dv)      // el punto del plano frente a la mitad de lo encimado
                let dist = simd_dot(w.a + u * tm - pm, perp(dv))
                guard abs(dist) <= maxDist else { continue }
                let afuera = simd_dot(pm - (w.a + u * tm), -ni)              // + = el plano queda más afuera que la pared
                if mejor == nil || afuera > mejor!.1 { mejor = (Pareja(pared: i, vista: j, t0: lo, t1: hi, dist: dist), afuera) }
            }
            if let m = mejor { out.append(m.0) }
        }
        return out
    }

    // ---------------- 0. PRIMERO EL GIRO (con las direcciones, que no dependen de dónde quedó) ----------------
    // Cada plano casi paralelo (12° o menos) a una pared del cuarto vota por la diferencia de ángulo; gana la que junta más
    // metros de pared (a 1.5° o menos), promediada.
    static func giroPorDirecciones(_ pa: [(a: SIMD2<Double>, b: SIMD2<Double>)], _ vistas: [Vista]) -> Double? {
        func ang(_ v: SIMD2<Double>) -> Double { atan2(v.y, v.x) }
        func a90(_ x0: Double) -> Double { var x = x0.truncatingRemainder(dividingBy: .pi); if x > .pi / 2 { x -= .pi } else if x <= -.pi / 2 { x += .pi }; return x }
        let lim = 12.0 * .pi / 180, ven = 1.5 * .pi / 180
        var votos: [(d: Double, w: Double)] = []
        for v in vistas {
            let lv = simd_length(v.b - v.a)
            guard lv >= 0.4 else { continue }
            for w in pa {
                let lw = simd_length(w.b - w.a)
                guard lw >= 0.5 else { continue }
                let d = a90(ang(v.b - v.a) - ang(w.b - w.a))
                if abs(d) <= lim { votos.append((d, min(lv, lw))) }
            }
        }
        guard !votos.isEmpty else { return nil }
        var mejor: (d: Double, s: Double)? = nil
        for x in votos {
            let s = votos.filter { abs($0.d - x.d) <= ven }.reduce(0) { $0 + $1.w }
            if mejor == nil || s > mejor!.s { mejor = (x.d, s) }
        }
        let cerca = votos.filter { abs($0.d - mejor!.d) <= ven }
        return cerca.reduce(0) { $0 + $1.d * $1.w } / cerca.reduce(0) { $0 + $1.w }
    }

    // ---------------- 1. LUEGO EL MOVIMIENTO (votado, por cada dirección de paredes) ----------------
    // Con el giro ya bien, cada plano paralelo a una pared (de este lado, a 1.5 m o menos, y no más de 1.5 m pasado de sus
    // puntas) vota por cuánto hay que mover esa pared de frente. De cada pared solo vota el plano de más afuera (lo de
    // delante es mueble). Por cada dirección gana lo que junta más metros a 8 cm o menos, prefiriendo lo que se mueve
    // menos (la ubicación casi nunca se va más de un metro). Dos direcciones que se cruzan dan el movimiento completo; una
    // sola, solo de frente (a lo largo lo sigue diciendo la ubicación).
    static func movPorVotos(_ pa: [(a: SIMD2<Double>, b: SIMD2<Double>)], _ vistas: [Vista], c: SIMD2<Double>) -> SIMD2<Double>? {
        var grupos: [(n: SIMD2<Double>, votos: [(d: Double, w: Double)])] = []
        for w in pa {
            let dw = w.b - w.a, L = simd_length(dw)
            guard L >= 0.5 else { continue }
            let u = dw / L, ni = adentro(w.a, w.b, c)
            var nc = ni
            if nc.x < -1e-9 || (abs(nc.x) <= 1e-9 && nc.y < 0) { nc = -nc }
            var mios: [(d: Double, w: Double, afuera: Double, lo: Double, hi: Double)] = []
            for v in vistas where deEsteLado(v, ni) {
                let dv0 = v.b - v.a, lv = simd_length(dv0)
                guard lv >= 0.4, abs(simd_dot(u, dv0 / lv)) >= cos(6 * .pi / 180) else { continue }
                let s0 = simd_dot(v.a - w.a, u), s1 = simd_dot(v.b - w.a, u)
                guard max(s0, s1) > -1.5, min(s0, s1) < L + 1.5 else { continue }
                let mid = (v.a + v.b) / 2
                let d = simd_dot(mid - w.a, nc)
                guard abs(d) <= 1.5 else { continue }
                mios.append((d, min(lv, L), simd_dot(mid - w.a, -ni), min(s0, s1), max(s0, s1)))
            }
            // Lo que tiene otro plano DETRÁS (encimados a lo largo, 5-60 cm más afuera) es un mueble: no vota.
            let limpios = mios.filter { x in !mios.contains { y in
                y.afuera - x.afuera > 0.05 && y.afuera - x.afuera < 0.6 && min(x.hi, y.hi) - max(x.lo, y.lo) > 0.2 } }
            guard !limpios.isEmpty else { continue }
            if let g = grupos.firstIndex(where: { abs(simd_dot($0.n, nc)) > cos(10 * .pi / 180) }) {
                let s = simd_dot(grupos[g].n, nc) > 0 ? 1.0 : -1.0
                grupos[g].votos += limpios.map { ($0.d * s, $0.w) }
            } else { grupos.append((nc, limpios.map { ($0.d, $0.w) })) }
        }
        var lados: [(n: SIMD2<Double>, d: Double, s: Double)] = []
        for g in grupos {
            var mejor: (d: Double, s: Double)? = nil
            for x in g.votos {
                let s = g.votos.filter { abs($0.d - x.d) <= 0.08 }.reduce(0) { $0 + $1.w } / (1 + (x.d / 0.9) * (x.d / 0.9))
                if mejor == nil || s > mejor!.s { mejor = (x.d, s) }
            }
            guard let m = mejor else { continue }
            let cerca = g.votos.filter { abs($0.d - m.d) <= 0.08 }
            lados.append((g.n, cerca.reduce(0) { $0 + $1.d * $1.w } / cerca.reduce(0) { $0 + $1.w }, m.s))
        }
        lados.sort { $0.s > $1.s }
        guard let l1 = lados.first else { return nil }
        if let l2 = lados.dropFirst().first(where: { abs(l1.n.x * $0.n.y - l1.n.y * $0.n.x) > 0.5 }) {
            let det = l1.n.x * l2.n.y - l1.n.y * l2.n.x
            return SIMD2((l1.d * l2.n.y - l1.n.y * l2.d) / det, (l1.n.x * l2.d - l1.d * l2.n.x) / det)
        }
        return l1.n * l1.d
    }

    // ---------------- 2. EL GIRO Y EL MOVIMIENTO QUE MEJOR LOS PEGA ----------------
    // Incógnitas (th, tx, ty) alrededor del centro del cuarto `c`. Cada pareja da dos renglones (las dos puntas de lo que se
    // encima: la distancia de la pared a la línea del plano). Cada esquina tocada, dos (x y y), pesando más. Un empujón
    // chiquito hacia "no mover" deja quieto lo que nada dice (con una sola pared vista, a lo largo de ella manda la ubicación).
    static func resolver(_ pa: [(a: SIMD2<Double>, b: SIMD2<Double>)], _ vistas: [Vista], _ parejas: [Pareja],
                         pines: [(s: SIMD2<Double>, m: SIMD2<Double>)], c: SIMD2<Double>, radio: Double) -> (th: Double, t: SIMD2<Double>) {
        var A = [[Double]](repeating: [0, 0, 0], count: 3), B = [0.0, 0, 0]
        func renglon(_ r: [Double], _ y: Double, _ w: Double) {
            for i in 0..<3 { for j in 0..<3 { A[i][j] += w * r[i] * r[j] }; B[i] += w * r[i] * y }
        }
        for p in parejas {
            let w = pa[p.pared], u = simd_normalize(w.b - w.a), v = vistas[p.vista]
            let nP = perp(simd_normalize(v.b - v.a))
            let peso = min(2.0, (p.t1 - p.t0) / 2)
            for t in [p.t0, p.t1] {
                let S = w.a + u * t
                renglon([simd_dot(nP, perp(S - c)), nP.x, nP.y], -simd_dot(nP, S - v.a), peso)
            }
        }
        for q in pines {
            let j = perp(q.s - c)
            renglon([j.x, 1, 0], q.m.x - q.s.x, 3)
            renglon([j.y, 0, 1], q.m.y - q.s.y, 3)
        }
        let lam = 0.05
        A[0][0] += lam * max(1, radio * radio); A[1][1] += lam; A[2][2] += lam
        guard let x = resolver3(A, B) else { return (0, .zero) }
        return (x[0], SIMD2(x[1], x[2]))
    }
    static func resolver3(_ A0: [[Double]], _ B0: [Double]) -> [Double]? {
        var A = A0, B = B0
        for col in 0..<3 {
            guard let piv = (col..<3).max(by: { abs(A[$0][col]) < abs(A[$1][col]) }), abs(A[piv][col]) > 1e-12 else { return nil }
            A.swapAt(col, piv); B.swapAt(col, piv)
            for r in 0..<3 where r != col {
                let f = A[r][col] / A[col][col]
                for cc in 0..<3 { A[r][cc] -= f * A[col][cc] }
                B[r] -= f * B[col]
            }
        }
        return (0..<3).map { B[$0] / A[$0][$0] }
    }
    // Qué tan lejos queda la pared de su plano después del ajuste (metros, el peor de las dos puntas).
    static func residuo(_ p: Pareja, _ pa: [(a: SIMD2<Double>, b: SIMD2<Double>)], _ vistas: [Vista], th: Double, t: SIMD2<Double>, c: SIMD2<Double>) -> Double {
        let w = pa[p.pared], u = simd_normalize(w.b - w.a), v = vistas[p.vista]
        let nP = perp(simd_normalize(v.b - v.a))
        return [p.t0, p.t1].map { tt -> Double in
            let S = w.a + u * tt
            let S2 = DemolicionEnPlano.girar(S - c, th) + c + t
            return abs(simd_dot(nP, S2 - v.a))
        }.max() ?? 0
    }
    static func centro(_ pa: [(a: SIMD2<Double>, b: SIMD2<Double>)]) -> (c: SIMD2<Double>, radio: Double) {
        let pts = pa.flatMap { [$0.a, $0.b] }
        guard !pts.isEmpty else { return (.zero, 1) }
        let c = pts.reduce(.zero, +) / Double(pts.count)
        return (c, pts.map { simd_distance($0, c) }.max() ?? 1)
    }

    // ---------------- TODO JUNTO ----------------
    static func ajustar(paredes: [DemolicionEnPlano.Pared], ac: Ac, vistas: [Vista], pines: [Pin] = []) -> Ajuste {
        func enAR(_ a: Ac) -> [(a: SIMD2<Double>, b: SIMD2<Double>)] { paredes.map { (ar($0.a, a), ar($0.b, a)) } }
        let inicio = enAR(ac)
        let (c0, _) = centro(inicio)
        func sinAjuste() -> Ajuste {
            Ajuste(ac: ac, paredes: inicio.map { ParedAR(a: $0.a, b: $0.b) }, vistas: 0, pines: 0, giro: 0, mov: 0)
        }
        guard !paredes.isEmpty else { return sinAjuste() }
        // Solo los planos cerca del cuarto (lo del resto de la casa no cuenta).
        let xs = inicio.flatMap { [$0.a.x, $0.b.x] }, ys = inicio.flatMap { [$0.a.y, $0.b.y] }
        let caja = (x: (xs.min()! - 1.8)...(xs.max()! + 1.8), y: (ys.min()! - 1.8)...(ys.max()! + 1.8))
        let cerca = vistas.filter { v in [v.a, v.b, (v.a + v.b) / 2].contains { caja.x.contains($0.x) && caja.y.contains($0.y) } }
        var acF = ac
        if let th = giroPorDirecciones(enAR(acF), cerca) { acF = componer(acF, th: th, t: .zero, c: c0) }
        do {
            let pa = enAR(acF), (c, _) = centro(pa)
            if let t = movPorVotos(pa, cerca, c: c) { acF = componer(acF, th: 0, t: t, c: c) }
        }
        var hubo = false
        for (paso, umbral) in [(0.25, 8.0), (0.12, 5.0)].enumerated() {
            let pa = enAR(acF)
            let (c, radio) = centro(pa)
            var parejas = emparejar(pa, cerca, c: c, maxDist: umbral.0, grados: umbral.1)
            let pins = pines.map { (s: ar($0.plano, acF), m: $0.ar) }
            guard !parejas.isEmpty || !pins.isEmpty else { break }
            var r = resolver(pa, cerca, parejas, pines: pins, c: c, radio: radio)
            // Fuera lo que no cuadra con lo demás (si queda algo con qué ajustar).
            let buenas = parejas.filter { residuo($0, pa, cerca, th: r.th, t: r.t, c: c) <= (paso == 0 ? 0.15 : 0.08) }
            if buenas.count < parejas.count, !buenas.isEmpty || !pins.isEmpty {
                parejas = buenas
                r = resolver(pa, cerca, parejas, pines: pins, c: c, radio: radio)
            }
            acF = componer(acF, th: r.th, t: r.t, c: c)
            hubo = true
        }
        guard hubo else { return sinAjuste() }
        // ¿Cuánto se movió en total? Mucho = algo se emparejó mal: no se cree.
        var dg = (acF.giro - ac.giro).truncatingRemainder(dividingBy: 2 * .pi)
        if dg > .pi { dg -= 2 * .pi } else if dg < -.pi { dg += 2 * .pi }
        let movCentro = simd_distance(ar(DemolicionEnPlano.girar(c0 * k, ac.giro) + ac.mov, acF), c0)
        guard abs(dg) <= maxGiro, movCentro <= maxMov else { return sinAjuste() }

        // Cada pared vista se pega a su plano (pasada final, más apretada todavía): SOLO de frente. La dirección se queda la
        // del ajuste de todo el cuarto (los ángulos del plano de RoomPlan son buenos; un plano chico del láser, no tanto).
        let pa = enAR(acF)
        let (cF, _) = centro(pa)
        var salida = pa.map { ParedAR(a: $0.a, b: $0.b) }
        let finales = emparejar(pa, cerca, c: cF, maxDist: 0.10, grados: 5)
        for p in finales {
            let v = cerca[p.vista], nP = perp(simd_normalize(v.b - v.a))
            let u = simd_normalize(pa[p.pared].b - pa[p.pared].a)
            let d = [p.t0, p.t1].map { simd_dot(pa[p.pared].a + u * $0 - v.a, nP) }.reduce(0, +) / 2
            salida[p.pared].a = pa[p.pared].a - nP * d; salida[p.pared].b = pa[p.pared].b - nP * d; salida[p.pared].vista = true
        }
        // Las esquinas: donde se cruzan dos paredes que se tocan en el plano (a 1 ft o menos) y hacen 30° o más.
        let lineas = salida
        for i in 0..<paredes.count {
            for j in (i + 1)..<max(i + 1, paredes.count) where j < paredes.count {
                for ei in 0..<2 {
                    for ej in 0..<2 {
                        let pi = ei == 0 ? paredes[i].a : paredes[i].b, pj = ej == 0 ? paredes[j].a : paredes[j].b
                        guard simd_distance(pi, pj) <= 1.0 else { continue }
                        let di = lineas[i].b - lineas[i].a, dj = lineas[j].b - lineas[j].a
                        guard simd_length(di) > 0.05, simd_length(dj) > 0.05 else { continue }
                        let ui = simd_normalize(di), uj = simd_normalize(dj)
                        let den = ui.x * uj.y - ui.y * uj.x
                        guard abs(den) >= 0.5 else { continue }                       // 30° o más
                        let w = lineas[j].a - lineas[i].a
                        let s = (w.x * uj.y - w.y * uj.x) / den
                        let X = lineas[i].a + ui * s
                        let actualI = ei == 0 ? salida[i].a : salida[i].b, actualJ = ej == 0 ? salida[j].a : salida[j].b
                        guard simd_distance(X, actualI) <= 0.6, simd_distance(X, actualJ) <= 0.6 else { continue }
                        let fina = lineas[i].vista && lineas[j].vista
                        if ei == 0 { salida[i].a = X; salida[i].finaA = fina } else { salida[i].b = X; salida[i].finaB = fina }
                        if ej == 0 { salida[j].a = X; salida[j].finaA = fina } else { salida[j].b = X; salida[j].finaB = fina }
                    }
                }
            }
        }
        return Ajuste(ac: acF, paredes: salida, vistas: finales.count, pines: pines.count, giro: dg, mov: movCentro)
    }

    // ---------------- LAS ESQUINAS TOCADAS ----------------
    // Las esquinas del cuarto (pies del plano): las puntas que se juntan, promediadas.
    static func esquinas(_ paredes: [DemolicionEnPlano.Pared]) -> [SIMD2<Double>] {
        var grupos: [[SIMD2<Double>]] = []
        for p in paredes.flatMap({ [$0.a, $0.b] }) {
            if let g = grupos.firstIndex(where: { simd_distance($0[0], p) <= 1.0 }) { grupos[g].append(p) } else { grupos.append([p]) }
        }
        return grupos.map { $0.reduce(.zero, +) / Double($0.count) }
    }
    // La esquina del cuarto más cerca de lo que tocó el láser (metros del AR), a 0.75 m o menos: su punto del plano y dónde
    // está ahora en el AR (con la malla como va). nil = no tocó cerca de una esquina.
    static func esquinaCercana(_ m: SIMD2<Double>, paredes: [DemolicionEnPlano.Pared], enAR: [ParedAR]) -> (plano: SIMD2<Double>, ar: SIMD2<Double>)? {
        var mejor: (SIMD2<Double>, SIMD2<Double>, Double)? = nil
        for q in esquinas(paredes) {
            var pos: [SIMD2<Double>] = []
            for (i, w) in paredes.enumerated() where i < enAR.count {
                if simd_distance(w.a, q) <= 1.0 { pos.append(enAR[i].a) }
                if simd_distance(w.b, q) <= 1.0 { pos.append(enAR[i].b) }
            }
            guard !pos.isEmpty else { continue }
            let p = pos.reduce(.zero, +) / Double(pos.count)
            let d = simd_distance(p, m)
            if d <= 0.75, mejor == nil || d < mejor!.2 { mejor = (q, p, d) }
        }
        return mejor.map { ($0.0, $0.1) }
    }

    // ---------------- LA MEMORIA DE CADA PARED (16 oct: "si ya había una pared demolida… la tele") ----------------
    // Lo quitado de una pared, en pies desde su punta `a`: lo que ya se sabía se queda, MENOS donde el láser acaba de ver
    // (ahí manda lo de ahora). Así, si ayer la tele tapaba un pedazo y hoy se movió, lo de detrás se agrega y lo demás no
    // se pierde; y si hoy se ve entero un pedazo que ayer se creía cortado, se corrige.
    typealias Corte = (t0: Double, t1: Double, alto: Double)
    static func mezclar(viejos: [Corte], nuevos: [Corte], vistos: [(Double, Double)]) -> [Corte] {
        var out: [Corte] = []
        for c in viejos {
            var pedazos = [(c.t0, c.t1)]
            for v in vistos {
                pedazos = pedazos.flatMap { p -> [(Double, Double)] in
                    guard v.1 > p.0, v.0 < p.1 else { return [p] }
                    return [(p.0, max(p.0, v.0)), (min(p.1, v.1), p.1)].filter { $0.1 - $0.0 >= 0.1 }
                }
            }
            out += pedazos.map { ($0.0, $0.1, c.alto) }
        }
        out += nuevos
        return out.sorted { $0.t0 < $1.t0 }
    }
    // Junta tramos que se enciman o se tocan.
    static func unir(_ a: [(Double, Double)]) -> [(Double, Double)] {
        var out: [(Double, Double)] = []
        for x in a.map({ (min($0.0, $0.1), max($0.0, $0.1)) }).sorted(by: { $0.0 < $1.0 }) {
            if let u = out.last, x.0 <= u.1 + 0.05 { out[out.count - 1].1 = max(u.1, x.1) } else { out.append(x) }
        }
        return out
    }
}
