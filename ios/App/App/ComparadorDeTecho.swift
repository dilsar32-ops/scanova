// ComparadorDeTecho.swift — "PROBAR LO DEMOLIDO" en el TECHO (15 oct 2026, su pedido "ahora pruébela para el techo").
//
// Lo mismo que ComparadorDeDemolicion hace en una pared, pero en el techo: cada rayo del láser vota en el cuadrito
// (2 x 2 in) donde CRUZA la cara del techo. Si pegó en la cara, el drywall sigue; si pasó de largo y pegó parejo entre
// 4.5 y 13 in más arriba, ahí hay un hueco entre vigas (con el subpiso de arriba); si se fue muy lejos, se ve el ático;
// si pegó en algo DEBAJO del techo (un abanico, una lámpara), está tapado. Lo que no se vio no se cobra nunca.
//
// En el techo el corte no sale del piso: es un HUECO en cualquier parte. Se juntan los cuadritos quitados (con las
// tiras de las vigas que quedan en medio) en huecos, y un hueco cuenta solo si:
//   - la mitad o más de su orilla es drywall ENTERO visto o la pared (si no, nunca tuvo drywall: un sótano sin terminar);
//   - mide 8 in o más por lado y 0.75 SF o más (una lámpara empotrada o una rejilla del aire no son demolición);
//   - si mide 3 ft o más de los dos lados, se le ven las vigas a 16 o 24 in.
// Swift puro (Foundation + simd): lo corre el teléfono y la prueba de la Mac (tests/demolicion_techo). Idéntico en las
// dos apps. Unidades: metros por dentro, las bandas en pulgadas.

import Foundation
import simd

struct ComparadorDeTecho {

    // La cara del techo: origen en la cara, u y v en el plano del techo (u a lo largo de la pared que se escoja), n la
    // normal hacia ABAJO (hacia el cuarto, donde está el teléfono).
    struct Cara: Equatable {
        var origen: SIMD3<Float>
        var u: SIMD3<Float>
        var v: SIMD3<Float>
        var n: SIMD3<Float>
        // `eje`: la dirección (horizontal) que va a ser u; si es casi vertical o cero, se usa x.
        static func desde(punto: SIMD3<Float>, eje: SIMD3<Float>, telefono: SIMD3<Float>) -> Cara {
            var n = SIMD3<Float>(0, -1, 0)
            if telefono.y > punto.y { n = -n }                         // (un piso visto desde arriba: no debería pasar)
            var e = SIMD3<Float>(eje.x, 0, eje.z)
            if simd_length(e) < 0.2 { e = SIMD3(1, 0, 0) }
            let u = simd_normalize(e)
            let v = simd_normalize(simd_cross(n, u))
            return Cara(origen: punto, u: u, v: v, n: n)
        }
        func enCara(_ p: SIMD3<Float>) -> SIMD2<Float> { SIMD2(simd_dot(p - origen, u), simd_dot(p - origen, v)) }
        func alMundo(_ q: SIMD2<Float>) -> SIMD3<Float> { origen + u * q.x + v * q.y }
    }

    // `encima`: algo ARRIBA de donde estaba el drywall (1.2 in o más), pero no el subpiso parejo: un tubo, un ducto,
    // cables (su pregunta del 15 oct: "hay tubos que pasan ahí"). El drywall ya no está; cuenta dentro de un hueco.
    enum Estado: UInt8 { case noVisto = 0, sigue, ambiguo, cavidad, hondo, tapado, encima }

    static let pulgada: Float = 0.0254
    static let sigueHasta: Float = 0.3
    static let ambiguoHasta: Float = 1.5
    static let cavidad = ClosedRange<Float>(uncheckedBounds: (4.5, 13))   // 2x6 a 2x12, con el subpiso de arriba
    static let hondoDesde: Float = 13                                       // el ático
    static let tapadoDesde: Float = 1.5                                     // algo DEBAJO del techo
    static let fondoPlanoMax: Float = 1.0
    static let distanciaMin: Float = 0.3, distanciaMax: Float = 2.5, distanciaHonda: Float = 6
    static let cosenoMin: Float = 0.5
    static let votosMin = 4
    static let abanicoMin: Float = 0.30

    static let celda: Float = 2 * pulgada
    static let radio: Float = 4.5                                           // 9 x 9 m centrado en el origen
    static let lado = Int((2 * radio / celda).rounded(.up))
    static let votosPorCelda = 16

    private(set) var votos: [Float]
    private(set) var cuenta: [UInt16]
    private(set) var fraccionHonda: [Float]
    private(set) var camMin: [SIMD3<Float>]
    private(set) var camMax: [SIMD3<Float>]
    private(set) var cuadros = 0
    // La cara medida: s corregido = s - (desvio + pu·u + pv·v), en pulgadas (el rastreo se corre y el plano de ARKit
    // viene un poco torcido).
    private(set) var desvio: Float = 0
    private(set) var pu: Float = 0, pv: Float = 0
    private(set) var ultimoLejos: Float = 0
    private(set) var ultimoVotantes = 0

    init() {
        let n = Self.lado * Self.lado
        votos = [Float](repeating: 0, count: n * Self.votosPorCelda)
        cuenta = [UInt16](repeating: 0, count: n)
        fraccionHonda = [Float](repeating: 0, count: n)
        camMin = [SIMD3<Float>](repeating: SIMD3(repeating: .infinity), count: n)
        camMax = [SIMD3<Float>](repeating: SIMD3(repeating: -.infinity), count: n)
    }
    mutating func reiniciar() { self = ComparadorDeTecho() }

    @inline(__always) static func indice(_ c: Int, _ r: Int) -> Int { r * lado + c }
    static func celdaDe(_ x: Float) -> Int? { let c = Int(((x + radio) / celda).rounded(.down)); return c >= 0 && c < lado ? c : nil }
    static func centro(_ c: Int) -> Float { -radio + (Float(c) + 0.5) * celda }

    // ---------------- VOTAR UN CUADRO ----------------
    mutating func votar(camara: SIMD3<Float>, puntos: [SIMD3<Float>], cara: Cara) {
        cuadros += 1
        var pares: [(Int, Float)] = []
        pares.reserveCapacity(puntos.count)
        var referencia: [(u: Float, v: Float, s: Float)] = []
        var lejos = 0, cerca = 0
        let inv = 1 / Self.pulgada
        for p in puntos {
            let d = p - camara
            let dist = simd_length(d)
            if dist > Self.distanciaMax {
                lejos += 1
                let sLejos = -simd_dot(p - cara.origen, cara.n) * inv
                guard dist <= Self.distanciaHonda, sLejos > Self.hondoDesde + 4 else { continue }
            } else {
                guard dist >= Self.distanciaMin else { continue }
                cerca += 1
            }
            let dir = d / dist
            let cosN = simd_dot(dir, cara.n)
            guard cosN <= -Self.cosenoMin else { continue }        // hacia el techo y no rasante
            let t = simd_dot(cara.origen - camara, cara.n) / cosN
            guard t > 0 else { continue }
            let q = cara.enCara(camara + dir * t)
            guard let c = Self.celdaDe(q.x), let r = Self.celdaDe(q.y) else { continue }
            let s = -simd_dot(p - cara.origen, cara.n) * inv
            pares.append((Self.indice(c, r), s))
            if abs(s - modelo(q.x, q.y)) < 1.0 { referencia.append((q.x, q.y, s)) }
        }
        ultimoLejos = (lejos + cerca) > 0 ? Float(lejos) / Float(lejos + cerca) : 0
        ultimoVotantes = pares.count
        ajustarCara(referencia)
        guard !pares.isEmpty else { return }
        pares.sort { $0.0 < $1.0 }
        var i = 0
        var grupo: [Float] = []
        while i < pares.count {
            let k = pares[i].0
            grupo.removeAll(keepingCapacity: true)
            let cero = modelo(Self.centro(k % Self.lado), Self.centro(k / Self.lado))
            while i < pares.count, pares[i].0 == k { grupo.append(pares[i].1 - cero); i += 1 }
            let hondos = grupo.reduce(0) { $0 + ($1 > 2.0 ? 1 : 0) }
            fraccionHonda[k] += Float(hondos) / Float(grupo.count)
            let m = Self.mediana(&grupo)
            let n = Int(cuenta[k])
            votos[k * Self.votosPorCelda + (n % Self.votosPorCelda)] = m
            cuenta[k] = UInt16(min(n + 1, 60000))
            camMin[k] = simd_min(camMin[k], camara)
            camMax[k] = simd_max(camMax[k], camara)
        }
    }
    func modelo(_ u: Float, _ v: Float) -> Float { desvio + pu * u + pv * v }

    // La cara medida con el drywall entero de este cuadro (lo que cae a 1 in o menos del modelo): un plano s = a + b·u + c·v.
    // La inclinación se promedia en el tiempo y nunca pasa de 2°; el desvío es el de este cuadro.
    private mutating func ajustarCara(_ ref: [(u: Float, v: Float, s: Float)]) {
        guard ref.count >= 30 else { return }
        let n = Float(ref.count)
        let mu = ref.reduce(Float(0)) { $0 + $1.u } / n, mv = ref.reduce(Float(0)) { $0 + $1.v } / n
        let ms = ref.reduce(Float(0)) { $0 + $1.s } / n
        var suu: Float = 0, svv: Float = 0, suv: Float = 0, sus: Float = 0, svs: Float = 0
        for p in ref {
            let du = p.u - mu, dv = p.v - mv, ds = p.s - ms
            suu += du * du; svv += dv * dv; suv += du * dv; sus += du * ds; svs += dv * ds
        }
        let det = suu * svv - suv * suv
        if ref.count >= 60, suu > 0.05 * n * 0.09, svv > 0.05 * n * 0.09, abs(det) > 1e-6 {
            let b = (sus * svv - svs * suv) / det, c = (svs * suu - sus * suv) / det
            let tope: Float = tan(2 * .pi / 180) / Self.pulgada
            if abs(b) < tope { pu = pu * 0.85 + b * 0.15 }
            if abs(c) < tope { pv = pv * 0.85 + c * 0.15 }
        }
        var resto = ref.map { $0.s - pu * $0.u - pv * $0.v }
        desvio = Self.mediana(&resto)
    }

    // ---------------- CADA CUADRITO ----------------
    func fraccion(_ k: Int) -> Float { cuenta[k] > 0 ? fraccionHonda[k] / Float(cuenta[k]) : 0 }
    func votosDe(_ k: Int) -> [Float] {
        let n = min(Int(cuenta[k]), Self.votosPorCelda)
        return Array(votos[(k * Self.votosPorCelda)..<(k * Self.votosPorCelda + n)])
    }
    // En el techo las vigas son HONDAS (7 a 11 in): visto de lado, el rayo pega en el costado de la viga y no llega
    // arriba. Por eso no se usa la mediana sino LO MÁS HONDO QUE SE VE de forma pareja: el cuarto de arriba de los votos.
    // El drywall entero nunca deja ver más hondo (todos sus votos están en la cara); el hueco sí, cuando se ve derecho.
    // Fondo parejo = los votos de arriba (del 70 al 90 %) caben en 1 in (el subpiso). Algo DELANTE se ve en la mediana.
    func estado(_ k: Int) -> Estado {
        guard Int(cuenta[k]) >= Self.votosMin, simd_length(camMax[k] - camMin[k]) >= Self.abanicoMin else { return .noVisto }
        var vs = votosDe(k)
        vs.sort()
        let n = vs.count
        let m = vs[n / 2], q60 = vs[min(n - 1, n * 6 / 10)], q70 = vs[min(n - 1, n * 7 / 10)], q75 = vs[min(n - 1, n * 3 / 4)], q90 = vs[min(n - 1, n * 9 / 10)]
        if m < -Self.tapadoDesde { return .tapado }
        if abs(q75) < Self.sigueHasta && abs(m) < Self.sigueHasta { return .sigue }
        if q75 > Self.hondoDesde && q60 > Self.hondoDesde * 0.5 { return .hondo }
        // Fondo parejo: lo más hondo que se ve (del 70 al 90 %) cabe en 1 in. Junto a una viga honda la mayoría de los
        // votos pega en su costado; solo los que miran derecho llegan al subpiso, y esos sí son parejos.
        if Self.cavidad.contains(q75), q90 - q70 <= Self.fondoPlanoMax { return .cavidad }
        // Más arriba de la cara del drywall de forma pareja (la mediana a 1.2 in o más): ahí ya no hay drywall.
        if m > 1.2 && q75 > 1.5 { return .encima }
        return .ambiguo
    }

    // ¿Se ve aquí la cara de ABAJO de una viga (o de la cuerda de una cercha)? Al menos un cuarto de los votos pegan a la
    // altura de la cara del drywall (1/2 in): el que mira derecho siempre pega en ella. Sirve dentro de un hueco, donde lo
    // de alrededor se ve hondo.
    func caraDeViga(_ k: Int) -> Bool {
        guard Int(cuenta[k]) >= Self.votosMin else { return false }
        var vs = votosDe(k)
        vs.sort()
        let q25 = vs[vs.count / 4]
        return q25 > 0.15 && q25 < 1.8
    }

    // ---------------- LOS HUECOS ----------------
    struct Hueco: Equatable {
        var u0: Float, u1: Float, v0: Float, v1: Float     // m, en la cara (la caja del hueco, con sus orillas)
        var area: Float                                    // m², lo quitado de verdad (no la caja)
        var vigas: Int                                     // tiras de viga vistas adentro
        var separacion: Float?                             // pulgadas (16 o 24) si se ven bien
        var atico: Bool                                    // la mayoría se ve hasta el ático
        var hastaPared: [Bool]                             // llega a la pared: [u0, u1, v0, v1]
        var celdas: [Int32] = []                           // los cuadritos del hueco (para pintarlo)
        var ancho: Float { u1 - u0 }
        var fondo: Float { v1 - v0 }
    }
    enum Alarma: Equatable { case sinOrilla(Int), sinVigas(Int), tapado, ambiguo }
    struct Resultado: Equatable {
        var huecos: [Hueco] = []
        var area: Float = 0
        var alarmas: [Alarma] = []
        var vistoPct: Float = 0
        var chicos = 0                                     // huecos chicos que no cuentan (lámparas, rejillas)
        var techoVisto: Float? = nil                       // con `limites`: qué parte del techo del cuarto ya se vio (0-1)
        var faltaVer: SIMD2<Float>? = nil                  // con `limites`: el centro (u, v) de lo que más falta ver
    }

    static let huecoMinLado: Float = 8 * pulgada
    static let huecoMinArea: Float = 0.75 * 0.3048 * 0.3048
    static let vigasDesde: Float = 36 * pulgada
    static let paredHasta: Float = 7 * pulgada
    static let juntaDePared: Float = 4.5 * pulgada     // la placa de arriba de la pared (3.5 in) y la esquina del drywall

    // `limites`: el techo del cuarto en la cara (u y v, m), si se sabe por el plano: lo de fuera no cuenta, y un hueco
    // que llega a 6 in o menos de la pared pasando solo por cosas mezcladas (la placa de arriba de la pared) llega a la pared.
    func resultado(limites: (u: ClosedRange<Float>, v: ClosedRange<Float>)? = nil) -> Resultado {
        var res = Resultado()
        let n = Self.lado
        func dentro(_ c: Int, _ r: Int) -> Bool {
            guard let l = limites else { return true }
            return l.u.contains(Self.centro(c)) && l.v.contains(Self.centro(r))
        }
        // El estado de cada cuadrito, una sola vez.
        var est = [Estado](repeating: .noVisto, count: n * n)
        var visto = 0, decidido = 0
        var tapados = 0, ambiguos = 0
        for r in 0..<n { for c in 0..<n where dentro(c, r) {
            let k = Self.indice(c, r)
            guard cuenta[k] > 0 else { continue }
            let e = estado(k)
            est[k] = e
            if e != .noVisto { visto += 1; if e == .sigue || e == .cavidad || e == .hondo || e == .encima { decidido += 1 } }
            if e == .tapado { tapados += 1 }
            if e == .ambiguo { ambiguos += 1 }
        } }
        res.vistoPct = visto > 0 ? Float(decidido) / Float(visto) : 0
        // Con el techo del cuarto: qué tanto se vio (sin la franja de la junta con las paredes) y dónde falta más (el
        // centro de los cuadritos sin ver, por cuadrantes de 2 ft).
        if let l = limites {
            var total = 0, vistos = 0
            var sinVer: [SIMD2<Int>: Int] = [:]
            for r in 0..<n { for c in 0..<n where dentro(c, r) {
                let u = Self.centro(c), v = Self.centro(r)
                guard u - l.u.lowerBound > 3 * Self.celda, l.u.upperBound - u > 3 * Self.celda,
                      v - l.v.lowerBound > 3 * Self.celda, l.v.upperBound - v > 3 * Self.celda else { continue }
                total += 1
                if est[Self.indice(c, r)] != .noVisto { vistos += 1 }
                else { sinVer[SIMD2(Int((u - l.u.lowerBound) / 0.6096), Int((v - l.v.lowerBound) / 0.6096)), default: 0] += 1 }
            }}
            if total > 0 {
                res.techoVisto = Float(vistos) / Float(total)
                if let peor = sinVer.max(by: { $0.value < $1.value }), peor.value >= 40 {
                    res.faltaVer = SIMD2(l.u.lowerBound + (Float(peor.key.x) + 0.5) * 0.6096, l.v.lowerBound + (Float(peor.key.y) + 0.5) * 0.6096)
                }
            }
        }
        // Lo quitado: hueco entre vigas o hasta el ático.
        var quitado = [Bool](repeating: false, count: n * n)
        for k in 0..<(n * n) where est[k] == .cavidad || est[k] == .hondo { quitado[k] = true }
        // Las tiras de viga (o de cuerda) en medio de lo quitado: hasta 3 cuadritos (6 in) que no son drywall entero ni
        // algo delante, con lo quitado a los dos lados, en cualquiera de las dos direcciones.
        var viga = [Bool](repeating: false, count: n * n)
        var ancho = [Bool](repeating: false, count: n * n)     // puenteado por tubo/ducto (más de 3 cuadritos)
        func tiras(_ porFila: Bool) {
            func k(_ x: Int, _ a: Int) -> Int { porFila ? Self.indice(x, a) : Self.indice(a, x) }
            for a in 0..<n {
                var b = 1
                while b < n {
                    guard !quitado[k(b, a)], quitado[k(b - 1, a)] else { b += 1; continue }
                    // Hasta 3 cuadritos (una viga), o hasta 8 (16 in) si es "algo arriba" (un tubo, un ducto: su pregunta del
                    // 15 oct). Siempre con hueco de verdad a los dos lados: así la orilla del corte nunca crece.
                    var e = b, sirve = true, arriba = 0
                    while e < n, !quitado[k(e, a)] {
                        let es = est[k(e, a)]
                        if es == .sigue || es == .tapado { sirve = false }
                        if es == .encima { arriba += 1 }
                        e += 1
                        if e - b > 8 || (e - b > 3 && arriba * 2 < e - b) { sirve = false; break }
                    }
                    if sirve, e < n, quitado[k(e, a)] { for x in b..<e { viga[k(x, a)] = true; if e - b > 3 { ancho[k(x, a)] = true } } }
                    b = max(e, b + 1)
                }
            }
        }
        tiras(true); tiras(false)
        // Lo puenteado por un tubo o ducto (más de 3 cuadritos) nunca es la orilla del corte: si tiene drywall entero a 2
        // cuadritos o menos, no se puentea (si no, la fila de la orilla se rellenaba a lo largo y el hueco crecía).
        for k in 0..<(n * n) where viga[k] && ancho[k] {
            let c = k % n, r = k / n
            let cerca = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { (dc, dr) in
                (1...2).contains { p in
                    let cc = c + dc * p, rr = r + dr * p
                    return cc >= 0 && cc < n && rr >= 0 && rr < n && est[Self.indice(cc, rr)] == .sigue
                }
            }
            if cerca { viga[k] = false }
        }
        for k in 0..<(n * n) where quitado[k] && caraDeViga(k) { viga[k] = true }
        var en = [Bool](repeating: false, count: n * n)
        for k in 0..<(n * n) { en[k] = quitado[k] || viga[k] }
        // Los huecos: grupos conectados (4 vecinos).
        var marca = [Int32](repeating: -1, count: n * n)
        var grupo: Int32 = 0
        var sinOrilla = 0, sinVigas = 0, soloEncima = 0
        for k0 in 0..<(n * n) where en[k0] && marca[k0] < 0 {
            var pila = [k0]; marca[k0] = grupo
            var celdas: [Int] = []
            while let k = pila.popLast() {
                celdas.append(k)
                let c = k % n, r = k / n
                for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let cc = c + dc, rr = r + dr
                    guard cc >= 0, cc < n, rr >= 0, rr < n else { continue }
                    let kk = Self.indice(cc, rr)
                    if en[kk] && marca[kk] < 0 { marca[kk] = grupo; pila.append(kk) }
                }
            }
            grupo += 1
            // Un hueco de verdad deja ver el subpiso o el ático en buena parte (30 % o más). Puro "algo arriba" (insulación
            // colgando, un plafón más alto) no se cobra solo: se pregunta.
            let abiertos = celdas.filter { est[$0] == .cavidad || est[$0] == .hondo }.count
            if abiertos * 10 < celdas.count * 3 { if celdas.count >= 20 { soloEncima += 1 }; continue }
            // La orilla: los vecinos de fuera del hueco (para ver si tuvo drywall alrededor).
            var orilla = 0, buena = 0
            var cMin = n, cMax = -1, rMin = n, rMax = -1
            var hondas = 0
            var borde = Set<Int>(), fuera = Set<Int>()
            let enGrupo = Set(celdas)
            for k in celdas {
                let c = k % n, r = k / n
                cMin = min(cMin, c); cMax = max(cMax, c); rMin = min(rMin, r); rMax = max(rMax, r)
                if est[k] == .hondo { hondas += 1 }
                for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let cc = c + dc, rr = r + dr
                    guard cc >= 0, cc < n, rr >= 0, rr < n else { continue }
                    let kk = Self.indice(cc, rr)
                    guard !enGrupo.contains(kk) else { continue }
                    borde.insert(k)
                    if dentro(cc, rr) { fuera.insert(kk) }
                    orilla += 1
                    // La orilla del corte casi siempre es un cuadrito mezclado (mitad drywall, mitad hueco): el drywall
                    // entero se busca hasta 2 cuadritos más allá en la misma dirección.
                    var esBuena = !dentro(cc, rr) || est[kk] == .sigue
                    var paso = 2
                    while !esBuena && paso <= 3 {
                        let c3 = c + dc * paso, r3 = r + dr * paso
                        guard c3 >= 0, c3 < n, r3 >= 0, r3 < n else { break }
                        let k3 = Self.indice(c3, r3)
                        if en[k3] { break }
                        if !dentro(c3, r3) || est[k3] == .sigue { esBuena = true }
                        paso += 1
                    }
                    if esBuena { buena += 1 }
                }
            }
            // LAS ORILLAS FINAS. Adentro del hueco, cada cuadrito deja ver hondo una parte fHueco de sus puntos (menos de
            // todos: las vigas tapan de lado); el drywall, ninguna. Un cuadrito de la orilla que deja ver hondo f tiene
            // f / fHueco de su área hueca. El área es: los de adentro enteros + esa parte de los de la orilla (de los dos
            // lados de la orilla). Las vigas cuentan enteras (su cara de abajo no deja ver hondo, pero ya no tiene drywall).
            var fs = celdas.filter { !borde.contains($0) && !viga[$0] }.map { fraccion($0) }
            let fHueco = max(0.2, fs.isEmpty ? 0.8 : Self.mediana(&fs))
            func peso(_ k: Int) -> Float { viga[k] && enGrupo.contains(k) ? 1 : min(1, max(0, fraccion(k) / fHueco)) }
            let a = Self.celda * Self.celda
            var area = Float(celdas.count - borde.count) * a
            for k in borde { area += peso(k) * a }
            for k in fuera { area += peso(k) * a }
            // Cada lado: en las filas (o columnas) que llegan a ese lado, la orilla = la del cuadrito de la orilla corrida
            // por su parte hueca y la del vecino de fuera; la mediana de todas.
            func lado(_ porFila: Bool, _ menor: Bool) -> Float {
                var orillas: [Float] = []
                let lineas = porFila ? Array(rMin...rMax) : Array(cMin...cMax)
                for l in lineas {
                    let xs = celdas.filter { porFila ? $0 / n == l : $0 % n == l }.map { porFila ? $0 % n : $0 / n }
                    guard let ext = menor ? xs.min() : xs.max(), ext == (menor ? (porFila ? cMin : rMin) : (porFila ? cMax : rMax)) else { continue }
                    let k = porFila ? Self.indice(ext, l) : Self.indice(l, ext)
                    let afuera = ext + (menor ? -1 : 1)
                    var w2: Float = 0
                    if afuera >= 0 && afuera < n { let kf = porFila ? Self.indice(afuera, l) : Self.indice(l, afuera); if fuera.contains(kf) { w2 = peso(kf) } }
                    let borde0 = Self.centro(ext) + (menor ? -1 : 1) * Self.celda / 2
                    let corrida = (menor ? 1 : -1) * (1 - peso(k)) * Self.celda + (menor ? -1 : 1) * w2 * Self.celda
                    orillas.append(borde0 + corrida)
                }
                if orillas.isEmpty { return Self.centro(menor ? (porFila ? cMin : rMin) : (porFila ? cMax : rMax)) + (menor ? -1 : 1) * Self.celda / 2 }
                return Self.mediana(&orillas)
            }
            var u0 = lado(true, true), u1 = lado(true, false), v0 = lado(false, true), v1 = lado(false, false)
            // ¿Llega a la pared? Entre el hueco y la pared, 6 in o menos, sin drywall entero ni algo delante.
            var aPared = [false, false, false, false]
            if let l = limites {
                // Sin drywall entero ni algo delante (hasta 1 de cada 10 cuadritos raros: la esquina con la otra pared).
                func libre(_ cs: [Int]) -> Bool {
                    let juzgados = cs.filter { est[$0] != .noVisto }
                    let malos = juzgados.filter { est[$0] == .sigue || est[$0] == .tapado }.count
                    return malos * 10 <= juzgados.count
                }
                let filas = Array(rMin...rMax), cols = Array(cMin...cMax)
                // La junta con la pared (la placa de arriba de 3.5 in y la esquina del drywall): lo que cae a 4.5 in de la
                // pared no se juzga.
                func franja(_ desde: Float, _ hasta: Float, porU: Bool) -> [Int] {
                    let a = Self.celdaDe(min(desde, hasta) + 0.001), b = Self.celdaDe(max(desde, hasta) - 0.001)
                    guard let a = a, let b = b, a <= b else { return [] }
                    return (a...b).filter { x in
                        let c = Self.centro(x)
                        let aLaPared = porU ? min(abs(c - l.u.lowerBound), abs(c - l.u.upperBound)) : min(abs(c - l.v.lowerBound), abs(c - l.v.upperBound))
                        return aLaPared > Self.juntaDePared
                    }.flatMap { x in porU ? filas.map { Self.indice(x, $0) } : cols.map { Self.indice($0, x) } }
                }
                let largoV = v1 - v0
                if u0 - l.u.lowerBound <= Self.paredHasta, libre(franja(l.u.lowerBound, u0, porU: true)) { area += (u0 - l.u.lowerBound) * largoV; u0 = l.u.lowerBound; aPared[0] = true }
                if l.u.upperBound - u1 <= Self.paredHasta, libre(franja(u1, l.u.upperBound, porU: true)) { area += (l.u.upperBound - u1) * largoV; u1 = l.u.upperBound; aPared[1] = true }
                if v0 - l.v.lowerBound <= Self.paredHasta, libre(franja(l.v.lowerBound, v0, porU: false)) { area += (v0 - l.v.lowerBound) * (u1 - u0); v0 = l.v.lowerBound; aPared[2] = true }
                if l.v.upperBound - v1 <= Self.paredHasta, libre(franja(v1, l.v.upperBound, porU: false)) { area += (l.v.upperBound - v1) * (u1 - u0); v1 = l.v.upperBound; aPared[3] = true }
            }
            // Un corte en el techo es un rectángulo (se corta con línea): si lo visto llena el 92 % o más de su caja, el
            // área es largo x ancho con las orillas medidas (las muescas son la junta con la pared o un cuadrito sin ver).
            // Una L o un hueco raro no llena su caja y se queda con lo visto.
            let caja = (u1 - u0) * (v1 - v0)
            if caja > 0, area >= caja * 0.92 { area = max(area, caja) }
            // Las vigas: las tiras (columnas o filas enteras de viga dentro del hueco) y su separación.
            func separacion(_ porColumna: Bool) -> (Int, Float?) {
                var centros: [Float] = []
                let rango = porColumna ? Array(cMin...cMax) : Array(rMin...rMax)
                let otro = porColumna ? Array(rMin...rMax) : Array(cMin...cMax)
                var enTira = false, ini = 0
                for x in rango {
                    let ks = otro.map { porColumna ? Self.indice(x, $0) : Self.indice($0, x) }.filter { en[$0] }
                    let vigas = ks.filter { viga[$0] }.count
                    let esTira = ks.count >= 4 && Float(vigas) >= Float(ks.count) * 0.6
                    if esTira && !enTira { enTira = true; ini = x }
                    if !esTira && enTira { enTira = false; centros.append((Self.centro(ini) + Self.centro(x - 1)) / 2) }
                }
                if enTira, let ult = rango.last { centros.append((Self.centro(ini) + Self.centro(ult)) / 2) }
                var sep: Float? = nil
                if centros.count >= 2 {
                    for i in 1..<centros.count {
                        let d = (centros[i] - centros[i - 1]) / Self.pulgada
                        if abs(d - 16) <= 1.5 { sep = 16; break }
                        if abs(d - 24) <= 1.5 { sep = 24; break }
                    }
                }
                return (centros.count, sep)
            }
            let (vu, su) = separacion(true), (vv, sv) = separacion(false)
            let h = Hueco(u0: u0, u1: u1, v0: v0, v1: v1, area: area, vigas: max(vu, vv), separacion: su ?? sv,
                          atico: hondas * 2 > celdas.count, hastaPared: aPared, celdas: celdas.map { Int32($0) })
            // ¿Cuenta?
            if h.ancho < Self.huecoMinLado || h.fondo < Self.huecoMinLado || h.area < Self.huecoMinArea { res.chicos += 1; continue }
            let tocaPared = aPared.contains(true)
            if orilla == 0 || (Float(buena) < Float(orilla) * 0.5 && !tocaPared) { sinOrilla += 1; continue }
            // Un hueco grande tiene que enseñar sus vigas: al menos una tira entera de viga (con vigas cada 24 in, un
            // hueco de 4 ft enseña una sola). La separación (16 o 24 in) solo se informa.
            if h.ancho >= Self.vigasDesde && h.fondo >= Self.vigasDesde && h.vigas == 0 { sinVigas += 1; continue }
            res.huecos.append(h)
        }
        res.huecos.sort { ($0.v0, $0.u0) < ($1.v0, $1.u0) }
        res.area = res.huecos.reduce(0) { $0 + $1.area }
        if sinOrilla > 0 { res.alarmas.append(.sinOrilla(sinOrilla)) }
        if sinVigas > 0 { res.alarmas.append(.sinVigas(sinVigas)) }
        if tapados >= 12 { res.alarmas.append(.tapado) }
        if (ambiguos >= 60 && res.huecos.isEmpty) || soloEncima > 0 { res.alarmas.append(.ambiguo) }
        return res
    }

    // ---------------- LA PINTURA (la capa sobre el techo) ----------------
    // RGBA de toda la rejilla, `px` pixeles por cuadrito: naranja = los huecos que cuentan (su caja con orillas si es un
    // rectángulo, si no sus cuadritos). El renglón 0 de la imagen es v MÁXIMO.
    static let naranja: (UInt8, UInt8, UInt8, UInt8) = (255, 120, 0, 150)
    func pintar(_ res: Resultado, px: Int = 2) -> (ancho: Int, alto: Int, rgba: [UInt8]) {
        let n = Self.lado, w = n * px
        var img = [UInt8](repeating: 0, count: w * w * 4)
        func llenar(_ c: Int, _ r: Int) {
            for yy in 0..<px { let fila = (n - 1 - r) * px + yy
                for xx in 0..<px { let o = (fila * w + c * px + xx) * 4
                    img[o] = Self.naranja.0; img[o + 1] = Self.naranja.1; img[o + 2] = Self.naranja.2; img[o + 3] = Self.naranja.3 } }
        }
        for h in res.huecos {
            let caja = h.ancho * h.fondo
            if caja > 0, h.area >= caja * 0.92, let c0 = Self.celdaDe(h.u0 + 0.001), let c1 = Self.celdaDe(h.u1 - 0.001),
               let r0 = Self.celdaDe(h.v0 + 0.001), let r1 = Self.celdaDe(h.v1 - 0.001) {
                for r in r0...r1 { for c in c0...c1 { llenar(c, r) } }
            } else { for k in h.celdas { llenar(Int(k) % n, Int(k) / n) } }
        }
        return (w, w, img)
    }

    static func mediana(_ v: inout [Float]) -> Float {
        guard !v.isEmpty else { return 0 }
        v.sort()
        return v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
    }
}
