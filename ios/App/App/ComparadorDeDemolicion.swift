// ComparadorDeDemolicion.swift — "PROBAR LO DEMOLIDO", versión 0 de laboratorio (15 oct 2026).
//
// Su pedido: "que el láser pueda detectar que antes estaba una pared... si cortaron un solo pie... compilar esa
// información y sacar las medidas". La investigación (notas/demolicion/PLAN.md) llegó a esto: la cara de la pared se
// mide en la MISMA sesión (el drywall que sigue arriba del corte), y cada rayo del láser vota en el cuadrito donde CRUZA
// esa cara: si pegó en la cara, la pared sigue; si pasó de largo 3.5 in (2x4) o 5.5 in (2x6), ahí hay una cavidad
// abierta entre studs; si pegó en algo delante, está tapado. Lo que no se vio no se cobra nunca.
//
// Swift puro (Foundation + simd, nada de ARKit ni UIKit): el teléfono lo corre en vivo, la Mac lo corre igual sobre una
// grabación (tools/leer_barrido.swift) y la prueba lo compila con swiftc (tests/demolicion_test.sh). Archivo idéntico
// en Scanova y Field Reports. Este laboratorio NO manda nada a Measurements: solo enseña y graba.
//
// Unidades: todo por dentro en METROS; las bandas de decisión se escriben en pulgadas porque así se piensa una pared.

import Foundation
import simd

struct ComparadorDeDemolicion {

    // ---------------- LA CARA DE LA PARED ----------------
    // origen = el punto de drywall entero que se fijó (arriba del corte); u = a lo largo de la pared (horizontal);
    // v = para arriba (el "arriba" del mundo); n = la normal, apuntando AL CUARTO (hacia donde está el teléfono).
    struct Cara: Equatable {
        var origen: SIMD3<Float>
        var u: SIMD3<Float>
        var v: SIMD3<Float>
        var n: SIMD3<Float>
        // Una cara a partir de un punto y una normal cualquiera: la normal se acuesta (las paredes son verticales) y se
        // voltea para que mire al teléfono.
        static func desde(punto: SIMD3<Float>, normal: SIMD3<Float>, telefono: SIMD3<Float>) -> Cara? {
            var nn = SIMD3<Float>(normal.x, 0, normal.z)
            guard simd_length(nn) > 0.2 else { return nil }   // eso no es una pared (es piso o techo)
            nn = simd_normalize(nn)
            if simd_dot(telefono - punto, nn) < 0 { nn = -nn }
            let vv = SIMD3<Float>(0, 1, 0)
            let uu = simd_normalize(simd_cross(vv, nn))
            return Cara(origen: punto, u: uu, v: vv, n: nn)
        }
        func enCara(_ p: SIMD3<Float>) -> SIMD2<Float> { SIMD2(simd_dot(p - origen, u), simd_dot(p - origen, v)) }
        func alMundo(_ q: SIMD2<Float>) -> SIMD3<Float> { origen + u * q.x + v * q.y }
    }

    // ---------------- LO QUE DICE CADA CUADRITO ----------------
    enum Estado: UInt8 { case noVisto = 0, sigue, ambiguo, cavidad, hondo, tapado }

    // Las bandas (en pulgadas, sobre la MEDIANA de cuánto más hondo que la cara pegó el rayo).
    // La cara del stud, el papel kraft y la insulación pareja quedan a 1/2-5/8 in detrás de la cara del drywall: caen
    // en AMBIGUO, nunca en "sigue" ni en "quitado". La cavidad abierta de un 2x4 da ~3.5 in y la de un 2x6 ~5.5 in.
    static let pulgada: Float = 0.0254
    static let sigueHasta: Float = 0.3
    static let ambiguoHasta: Float = 1.5
    static let cavidad2x4 = ClosedRange<Float>(uncheckedBounds: (2.5, 4.75))
    static let cavidad2x6 = ClosedRange<Float>(uncheckedBounds: (5.0, 6.75))
    static let hondoDesde: Float = 8.0
    static let tapadoDesde: Float = 1.5           // más de 1.5 in DELANTE de la cara
    static let fondoPlanoMax: Float = 1.0         // la cavidad tiene fondo parejo (el sheathing o el drywall del otro lado)

    // Quién vota: puntos a 0.3-2.5 m del teléfono y a menos de 60° de la perpendicular de la pared. Lo MUY hondo (un
    // paso abierto, un espejo) vota aunque esté más lejos (hasta 6 m): no se mide, pero tiene que avisar.
    static let distanciaMin: Float = 0.3, distanciaMax: Float = 2.5, distanciaHonda: Float = 6
    static let cosenoMin: Float = 0.5
    // Cuándo decide un cuadrito: al menos 4 cuadros, desde posiciones que abarquen 30 cm o más.
    static let votosMin = 4
    static let abanicoMin: Float = 0.30

    // ---------------- LA REJILLA ----------------
    static let celda: Float = 2 * pulgada                 // 2 x 2 in
    static let uMin: Float = -6.1, uMax: Float = 6.1        // 12 m a lo largo, centrado en lo que se fijó
    static let vMin: Float = -2.5, vMax: Float = 1.0        // del punto fijado: 2.5 m para abajo (el piso) y 1 m arriba
    static let columnas = Int(((uMax - uMin) / celda).rounded(.up))
    static let renglones = Int(((vMax - vMin) / celda).rounded(.up))
    static let votosPorCelda = 16

    private(set) var votos: [Float]          // pulgadas, anillo de votosPorCelda por cuadrito
    private(set) var cuenta: [UInt16]
    // Por cuadrito: la suma, cuadro por cuadro, de la fracción de puntos HONDOS (más de 2 in detrás de la cara). En el
    // cuadrito de la orilla (mitad hueco, mitad drywall) dice dónde va la orilla con más finura que los 2 in de la rejilla.
    private(set) var fraccionHonda: [Float]
    private(set) var camMin: [SIMD3<Float>]
    private(set) var camMax: [SIMD3<Float>]
    private(set) var colMin = Int.max, colMax = Int.min      // lo barrido
    private(set) var cuadros = 0
    // La corrección de cada cuadro: cuánto se corrió la cara a lo largo de la normal (el rastreo se mueve centímetros
    // en 20-40 s de caminata). Se mide con el drywall entero alrededor del punto fijado.
    private(set) var desvio: Float = 0
    // Y lo torcida que viene (la normal del ancla de ARKit trae medio grado o más de error: a 2 m del punto fijado eso
    // son 0.7 in, y el drywall bueno saldría "ambiguo"). s corregido = s - (desvio + pendiente·u), en pulgadas.
    private(set) var pendiente: Float = 0
    // EL PISO LOCAL (lo pide el plan: "el plano horizontal visto a 1-2 ft frente a ESA pared"), medido por el mismo
    // comparador con los puntos del piso. `pisoRef` es la altura del piso en la cara (m, coordenada v) del primer cuadro
    // que lo vio; en cada cuadro el piso visto se compara con ese y la diferencia es la deriva vertical del rastreo, que se
    // quita antes de votar (igual que el desvío de la normal). Sin piso visto no hay número.
    private(set) var pisoRef: Float?
    private(set) var derivaV: Float = 0
    // Lo del último cuadro, para los avisos.
    private(set) var ultimoLejos: Float = 0
    private(set) var ultimoVotantes = 0

    init() {
        let n = Self.columnas * Self.renglones
        votos = [Float](repeating: 0, count: n * Self.votosPorCelda)
        cuenta = [UInt16](repeating: 0, count: n)
        fraccionHonda = [Float](repeating: 0, count: n)
        camMin = [SIMD3<Float>](repeating: SIMD3(repeating: .infinity), count: n)
        camMax = [SIMD3<Float>](repeating: SIMD3(repeating: -.infinity), count: n)
    }

    mutating func reiniciar() { self = ComparadorDeDemolicion() }

    @inline(__always) static func indice(_ c: Int, _ r: Int) -> Int { r * columnas + c }
    static func columnaDe(_ u: Float) -> Int? { let c = Int(((u - uMin) / celda).rounded(.down)); return c >= 0 && c < columnas ? c : nil }
    static func renglonDe(_ v: Float) -> Int? { let r = Int(((v - vMin) / celda).rounded(.down)); return r >= 0 && r < renglones ? r : nil }
    static func uDeColumna(_ c: Int) -> Float { uMin + (Float(c) + 0.5) * celda }
    static func vAbajo(_ r: Int) -> Float { vMin + Float(r) * celda }

    // ---------------- VOTAR UN CUADRO ----------------
    // `puntos`: lo que vio el láser en este cuadro, ya en el mundo (ver `puntos(...)` abajo). `cara`: la cara de
    // AHORA (si el ancla de la pared se corrigió, la cara viaja con ella y los votos, que están en la cara, también).
    mutating func votar(camara: SIMD3<Float>, puntos: [SIMD3<Float>], cara: Cara) {
        cuadros += 1
        // Primero el piso de este cuadro: puntos de 6 in a 30 in DELANTE de la pared, bastante abajo del punto fijado.
        // El percentil 20 de su altura (lo más bajo que se ve ahí es el piso; un secador o una caja quedan arriba).
        var bajos: [Float] = []
        for p in puntos {
            let s = -simd_dot(p - cara.origen, cara.n) / Self.pulgada
            guard s < -6, s > -30 else { continue }
            let v = simd_dot(p - cara.origen, cara.v)
            if v < -0.3 { bajos.append(v) }
        }
        if bajos.count >= 40 {
            bajos.sort()
            let piso = bajos[bajos.count / 5]
            if let ref = pisoRef { derivaV = piso - ref } else { pisoRef = piso; derivaV = 0 }
        }
        var pares: [(Int, Float)] = []
        pares.reserveCapacity(puntos.count)
        var referencia: [(u: Float, s: Float)] = []
        var lejos = 0, cerca = 0
        let denominadorVotos = Float(1) / Self.pulgada
        for p in puntos {
            let d = p - camara
            let dist = simd_length(d)
            if dist > Self.distanciaMax {
                lejos += 1
                let sLejos = -simd_dot(p - cara.origen, cara.n) * denominadorVotos
                guard dist <= Self.distanciaHonda, sLejos > Self.hondoDesde + 4 else { continue }
            } else {
                guard dist >= Self.distanciaMin else { continue }
                cerca += 1
            }
            let dir = d / dist
            let cosN = simd_dot(dir, cara.n)
            guard cosN <= -Self.cosenoMin else { continue }      // el rayo tiene que ir HACIA la pared y no rasante
            // Dónde cruza el rayo la cara de la pared (si pegó antes, se extiende el rayo).
            let t = simd_dot(cara.origen - camara, cara.n) / cosN
            guard t > 0 else { continue }
            let x = camara + dir * t
            var q = cara.enCara(x)
            q.y -= derivaV
            guard let c = Self.columnaDe(q.x), let r = Self.renglonDe(q.y) else { continue }
            let s = -simd_dot(p - cara.origen, cara.n) * denominadorVotos     // pulgadas; + = más hondo que la cara
            pares.append((Self.indice(c, r), s))
            // La banda del drywall entero (por instrucción se fijó ARRIBA del corte): de 4 in abajo del punto fijado a
            // 30 in arriba, a todo lo largo, y solo lo que cae cerca de la cara (una cavidad nunca entra).
            if q.y > -0.10, q.y < 0.80, abs(s - (desvio + pendiente * q.x)) < 1.0 { referencia.append((q.x, s)) }
        }
        ultimoLejos = (lejos + cerca) > 0 ? Float(lejos) / Float(lejos + cerca) : 0
        ultimoVotantes = pares.count
        ajustarCara(referencia)
        guard !pares.isEmpty else { return }
        // Un voto por cuadro y por cuadrito: la mediana de ese cuadro, ya corregida por el desvío.
        pares.sort { $0.0 < $1.0 }
        var i = 0
        var grupo: [Float] = []
        while i < pares.count {
            let k = pares[i].0
            grupo.removeAll(keepingCapacity: true)
            let uCelda = Self.uDeColumna(k % Self.columnas)
            let cero = desvio + pendiente * uCelda
            while i < pares.count, pares[i].0 == k { grupo.append(pares[i].1 - cero); i += 1 }
            let hondos = grupo.reduce(0) { $0 + ($1 > 2.0 ? 1 : 0) }
            fraccionHonda[k] += Float(hondos) / Float(grupo.count)
            let m = Self.mediana(&grupo)
            let n = Int(cuenta[k])
            votos[k * Self.votosPorCelda + (n % Self.votosPorCelda)] = m
            cuenta[k] = UInt16(min(n + 1, 60000))
            camMin[k] = simd_min(camMin[k], camara)
            camMax[k] = simd_max(camMax[k], camara)
            let c = k % Self.columnas
            colMin = min(colMin, c); colMax = max(colMax, c)
        }
    }

    // La recta del drywall entero en este cuadro: s = a + b·u. La pendiente se promedia en el tiempo (la de un solo cuadro
    // es ruidosa) y nunca pasa de 2°; el desvío es el de este cuadro (el rastreo se corre a lo largo de la normal).
    private mutating func ajustarCara(_ ref: [(u: Float, s: Float)]) {
        guard ref.count >= 30 else { return }
        let us = ref.map { $0.u }
        if let lo = us.min(), let hi = us.max(), hi - lo >= 0.6, ref.count >= 60 {
            let n = Float(ref.count)
            let mu = us.reduce(0, +) / n, ms = ref.reduce(Float(0)) { $0 + $1.s } / n
            var sxy: Float = 0, sxx: Float = 0
            for p in ref { sxy += (p.u - mu) * (p.s - ms); sxx += (p.u - mu) * (p.u - mu) }
            if sxx > 1e-4 {
                let b = sxy / sxx                                  // pulgadas por metro
                let tope: Float = tan(2 * .pi / 180) / Self.pulgada
                if abs(b) < tope { pendiente = pendiente * 0.85 + b * 0.15 }
            }
        }
        var resto = ref.map { $0.s - pendiente * $0.u }
        desvio = Self.mediana(&resto)
    }

    // ---------------- DECIDIR UN CUADRITO ----------------
    func fraccion(_ c: Int, _ r: Int) -> Float {
        let k = Self.indice(c, r)
        return cuenta[k] > 0 ? fraccionHonda[k] / Float(cuenta[k]) : 0
    }
    func votosDe(_ k: Int) -> [Float] {
        let n = min(Int(cuenta[k]), Self.votosPorCelda)
        return Array(votos[(k * Self.votosPorCelda)..<(k * Self.votosPorCelda + n)])
    }
    func estado(_ c: Int, _ r: Int) -> Estado {
        let k = Self.indice(c, r)
        guard Int(cuenta[k]) >= Self.votosMin, simd_length(camMax[k] - camMin[k]) >= Self.abanicoMin else { return .noVisto }
        var vs = votosDe(k)
        let m = Self.mediana(&vs)
        if m < -Self.tapadoDesde { return .tapado }
        if abs(m) < Self.sigueHasta { return .sigue }
        if m > Self.hondoDesde { return .hondo }
        if Self.cavidad2x4.contains(m) || Self.cavidad2x6.contains(m) {
            // Fondo parejo: la mitad de en medio de los votos cabe en 1 in.
            vs.sort()
            let q1 = vs[vs.count / 4], q3 = vs[(vs.count * 3) / 4]
            return q3 - q1 <= Self.fondoPlanoMax ? .cavidad : .ambiguo
        }
        return .ambiguo
    }

    // ---------------- LAS COLUMNAS (del piso para arriba) ----------------
    enum Columna: Equatable {
        case noVista              // no se vio lo suficiente
        case entera               // drywall hasta el piso: no se quitó nada
        case ambigua              // cara de stud, kraft o insulación: no se sabe
        case tapada               // algo delante (secador, plástico, escombro)
        case sinOrilla(Float)     // hay corte pero no se vio dónde termina (alto mínimo)
        case cortada(Float)       // quitado desde el piso hasta este alto (m)
        case alarma               // muy hondo: ¿puerta, paso, espejo, de los dos lados?
    }
    // La solera y el zócalo: los primeros 8 in no cortan la columna. (El plan decía 4-6 in; mirando de arriba hacia el
    // fondo de la cavidad, el ángulo y la cara de arriba de la solera dejan 4-6 in "dudosos" casi siempre.)
    static let solera: Float = 8 * pulgada
    static let isla: Int = 3                           // una caja o un tubo de hasta 6 in no corta la columna

    func columna(_ c: Int, piso: Float) -> Columna {
        guard let r0 = Self.renglonDe(piso) else { return .noVista }
        let rSolera = min(Self.renglones - 1, Self.renglonDe(piso + Self.solera) ?? (Self.renglones - 1))
        var primera: Int? = nil
        var vistas = 0, tapadas = 0, sigue = 0, ambiguas = 0, hondas = 0
        for r in r0...rSolera {
            let e = estado(c, r)
            // El cuadrito del piso (la junta con la pared) es ruido: ahí caen puntos del piso a 1 in de la pared, que se
            // leen "delante". Solo cuenta si ya es hueco.
            if r == r0 && e != .cavidad { continue }
            switch e {
            case .cavidad: if primera == nil { primera = r }
            case .hondo: hondas += 1
            case .tapado: tapadas += 1
            case .sigue: sigue += 1; vistas += 1
            case .ambiguo: ambiguas += 1; vistas += 1
            case .noVisto: break
            }
            if primera != nil { break }
        }
        guard let inicio = primera else {
            // No arranca ninguna cavidad pegada al piso: ¿qué hay ahí abajo?
            let arriba = min(Self.renglones - 1, r0 + 12)        // los primeros 2 ft
            var s = 0, a = 0, t = 0, h = 0, cav = 0
            for r in min(r0 + 1, arriba)...arriba {
                switch estado(c, r) {
                case .sigue: s += 1
                case .ambiguo: a += 1
                case .tapado: t += 1
                case .hondo: h += 1
                case .cavidad: cav += 1
                case .noVisto: break
                }
            }
            if h + hondas >= 3 { return .alarma }
            if t + tapadas >= 3 { return .tapada }
            if cav >= 3 { return .tapada }       // hay corte más arriba pero lo de abajo no se ve: no se inventa
            if s >= 6 && a <= s { return .entera }
            if a + s + ambiguas >= 6 { return .ambigua }
            return .noVista
        }
        // Para arriba mientras sea cavidad; una caja o un tubo (isla de 6 in o menos) no corta.
        var r = inicio, tope = inicio
        while r < Self.renglones {
            let e = estado(c, r)
            if e == .cavidad { tope = r; r += 1; continue }
            if e == .hondo { return .alarma }
            if let salto = islaEn(c, r) { r += salto; continue }
            break
        }
        // La orilla se tiene que haber VISTO: drywall seguro ("sigue") a 3 cuadritos o menos arriba del último hueco, y
        // en medio solo lo mezclado de la orilla (ambiguo o sin ver). Un sótano que nunca tuvo drywall no tiene orilla.
        // El corte queda a la mitad entre el centro del último hueco y el centro del primer drywall: más fino que 2 in.
        var primeraCara: Int? = nil
        var rr = tope + 1
        while rr <= min(tope + 3, Self.renglones - 1) {
            let e = estado(c, rr)
            if e == .sigue { primeraCara = rr; break }
            if e != .ambiguo && e != .noVisto { break }
            rr += 1
        }
        guard let rc = primeraCara else { return .sinOrilla(Self.vAbajo(tope + 1) - piso) }
        // La orilla, integrada: desde abajo del último hueco, cada cuadrito de la transición aporta la fracción de sus
        // puntos que pasaron de largo (1 = todo hueco, 0 = todo drywall). Un corte es un escalón: eso es su altura.
        var orilla = Self.vAbajo(tope)
        for rt in tope..<rc { orilla += Self.celda * min(1, max(0, fraccion(c, rt))) }
        // Nunca fuera de los dos centros (el último hueco seguro y el primer drywall seguro).
        orilla = min(max(orilla, Self.vAbajo(tope) + Self.celda / 2), Self.vAbajo(rc) + Self.celda / 2)
        return .cortada(orilla - piso)
    }

    // ¿Hay aquí una isla (caja eléctrica, tubo) de hasta 6 in, rodeada de cavidad? Devuelve cuántos renglones brincar.
    private func islaEn(_ c: Int, _ r: Int) -> Int? {
        for alto in 1...Self.isla {
            let arriba = r + alto
            guard arriba < Self.renglones, estado(c, arriba) == .cavidad else { continue }
            // A los lados (8 in), en esos mismos renglones, tiene que seguir la cavidad.
            var lados = 0
            for dc in [-4, 4] {
                let cc = c + dc
                guard cc >= 0, cc < Self.columnas else { continue }
                if (r..<arriba).allSatisfy({ estado(cc, $0) == .cavidad }) { lados += 1 }
            }
            return lados >= 1 ? alto : nil
        }
        return nil
    }

    // ---------------- EL RESULTADO ----------------
    struct Tramo: Equatable {
        var uIni: Float, uFin: Float         // en la cara (m)
        var largo: Float                     // solo lo visto (m)
        var alto: Float                      // la recta de tiza del tramo (m, desde el piso)
        var altoMin: Float, altoMax: Float   // percentiles 10 y 90 de las columnas
        var area: Float                      // m², la suma de cada columna por su ancho
        var studs: Int
    }
    enum Alarma: Equatable { case sinPiso, hondo(Int), tapadoAbajo, sinStuds, ambiguo(Int), sinOrilla(Int) }
    struct Resultado: Equatable {
        var tramos: [Tramo] = []
        var largo: Float = 0, area: Float = 0
        var alto: Float? = nil, altoMin: Float? = nil, altoMax: Float? = nil
        var vistoPct: Float = 0
        var alarmas: [Alarma] = []
        var columnas: [Columna] = []          // de colMin a colMax
        var colIni = 0
        var patronStuds = false
        var separacionStuds: Float? = nil     // pulgadas (16 o 24)
    }

    // Lo que dice hasta ahora. `piso`: dónde está el piso, en la coordenada v de la cara (nil = no se ha visto).
    // `piso` = nil: el que midió el comparador (lo normal en el teléfono).
    func resultado(piso pisoDado: Float? = nil) -> Resultado {
        var res = Resultado()
        guard colMin <= colMax else { return res }
        guard let piso = pisoDado ?? pisoRef else { res.alarmas = [.sinPiso]; return res }
        res.colIni = colMin
        var cols = (colMin...colMax).map { columna($0, piso: piso) }
        // La tira del stud: 1 o 2 columnas que no salieron huecas entre dos cortadas cuentan como quitado (la cara del
        // stud queda a 1/2 in: sale ambigua o "sigue", y el drywall de enfrente sí se quitó).
        var studs: [Float] = []
        var i = 0
        while i < cols.count {
            if Self.esCortada(cols[i]) { i += 1; continue }
            var j = i
            while j < cols.count, !Self.esCortada(cols[j]) { j += 1 }
            let ancho = j - i
            // Hasta 3 columnas (6 in): el stud mide 1.5 in, pero cae entre dos cuadritos y sus orillas salen borrosas.
            if i > 0, j < cols.count, ancho <= 3, case .cortada(let a) = cols[i - 1], case .cortada(let b) = cols[j],
               (i..<j).allSatisfy({ Self.puedeSerStud(cols[$0]) }) {
                for k in i..<j { cols[k] = .cortada((a + b) / 2) }
                studs.append(Self.uDeColumna(colMin + i) + Float(ancho - 1) * Self.celda / 2)
            }
            i = j
        }
        res.columnas = cols
        // El patrón de studs: al menos una separación de 16 o 24 in (±1.5 in) entre studs vistos.
        studs.sort()
        var separaciones: [Float] = []
        if studs.count >= 2 { for k in 1..<studs.count { separaciones.append((studs[k] - studs[k - 1]) / Self.pulgada) } }
        let buena = separaciones.first { abs($0 - 16) <= 1.5 || abs($0 - 24) <= 1.5 }
        res.patronStuds = buena != nil
        res.separacionStuds = buena.map { abs($0 - 16) <= 1.5 ? 16 : 24 }
        // Los tramos: corridas de columnas cortadas.
        var altos: [Float] = []
        var k = 0
        var sinOrilla = 0, ambiguas = 0, hondas = 0, tapadas = 0, decididas = 0, conVotos = 0
        while k < cols.count {
            switch cols[k] {
            case .cortada, .entera: decididas += 1; conVotos += 1
            case .sinOrilla: sinOrilla += 1; conVotos += 1
            case .ambigua: ambiguas += 1; conVotos += 1
            case .alarma: hondas += 1; conVotos += 1
            case .tapada: tapadas += 1; conVotos += 1
            case .noVista: if columnaTieneVotos(colMin + k) { conVotos += 1 }
            }
            guard case .cortada = cols[k] else { k += 1; continue }
            var f = k
            var colAltos: [Float] = []
            while f < cols.count, case .cortada(let a) = cols[f] { colAltos.append(a); f += 1 }
            let n = colAltos.count
            if n >= 2 {   // un solo cuadrito (2 in) no es un tramo
                // Las puntas, igual que la orilla de arriba: a la mitad entre la última columna cortada y la primera
                // columna ENTERA vista (si hay una columna mezclada en medio, se gana media columna). Sin columna entera
                // vista al lado, la punta se queda en la orilla del cuadrito (nunca se estira).
                func extra(_ lado: Int) -> Float {
                    // Hasta 2 columnas mezcladas (la orilla del corte, la cara del stud) antes de una columna ENTERA vista.
                    let paso = lado < 0 ? -1 : 1
                    var transicion: [Int] = []
                    var x = lado < 0 ? k - 1 : f
                    while x >= 0, x < cols.count, transicion.count < 2,
                          cols[x] == .ambigua || cols[x] == .noVista || Self.esSinOrilla(cols[x]) { transicion.append(x); x += paso }
                    guard !transicion.isEmpty, x >= 0, x < cols.count, cols[x] == .entera else { return 0 }
                    // Cada columna mezclada aporta la fracción de su ancho que pasó de largo (en la franja de en medio
                    // del corte, lejos del piso y de la orilla de arriba). La cara del stud no es honda: no aporta.
                    let altoT = colAltos.sorted()[colAltos.count / 2]
                    guard let ra = Self.renglonDe(piso + 8 * Self.pulgada), let rb = Self.renglonDe(piso + altoT - 4 * Self.pulgada), rb >= ra else { return 0 }
                    var total: Float = 0
                    for cx in transicion {
                        let fs = (ra...rb).compactMap { r -> Float? in cuenta[Self.indice(colMin + cx, r)] > 0 ? fraccion(colMin + cx, r) : nil }
                        guard !fs.isEmpty else { break }
                        let fr = min(1, max(0, fs.reduce(0, +) / Float(fs.count)))
                        total += Self.celda * fr
                        if fr < 0.5 { break }      // de aquí en adelante ya es la cara (del stud o del drywall)
                    }
                    return total
                }
                let eI = extra(-1), eF = extra(1)
                let uIni = Self.uDeColumna(colMin + k) - Self.celda / 2 - eI, uFin = Self.uDeColumna(colMin + f - 1) + Self.celda / 2 + eF
                let ordenados = colAltos.sorted()
                let recta = Self.rectaDeTiza(colAltos)
                let tramoStuds = studs.filter { $0 >= uIni && $0 <= uFin }.count
                res.tramos.append(Tramo(uIni: uIni, uFin: uFin, largo: uFin - uIni, alto: recta,
                                        altoMin: ordenados[Int(Float(n - 1) * 0.1)], altoMax: ordenados[Int(Float(n - 1) * 0.9)],
                                        area: colAltos.reduce(0, +) * Self.celda + (eI + eF) * recta, studs: tramoStuds))
                altos.append(contentsOf: colAltos)
            }
            k = f
        }
        // Sin patrón de studs no se pinta naranja ni se cuenta (un sótano sin terminar, una puerta, un espejo...).
        let cortado = res.tramos.reduce(Float(0)) { $0 + $1.largo }
        if !res.patronStuds && cortado >= 3 * 12 * Self.pulgada { res.alarmas.append(.sinStuds) }
        if res.patronStuds || cortado < 3 * 12 * Self.pulgada {
            res.largo = cortado
            res.area = res.tramos.reduce(0) { $0 + $1.area }
            if !altos.isEmpty {
                var a = altos
                res.alto = Self.mediana(&a)
                a.sort()
                res.altoMin = a[Int(Float(a.count - 1) * 0.1)]; res.altoMax = a[Int(Float(a.count - 1) * 0.9)]
            }
        }
        if !res.patronStuds && cortado >= 3 * 12 * Self.pulgada { res.largo = 0; res.area = 0 }
        if hondas > 0 { res.alarmas.append(.hondo(hondas)) }
        if tapadas >= 3 { res.alarmas.append(.tapadoAbajo) }
        if ambiguas >= 6 { res.alarmas.append(.ambiguo(ambiguas)) }
        if sinOrilla >= 3 { res.alarmas.append(.sinOrilla(sinOrilla)) }
        res.vistoPct = conVotos > 0 ? Float(decididas) / Float(conVotos) : 0
        return res
    }
    static func esCortada(_ c: Columna) -> Bool { if case .cortada = c { return true }; return false }
    static func esSinOrilla(_ c: Columna) -> Bool { if case .sinOrilla = c { return true }; return false }
    // Lo que puede ser la tira de un stud (1.5 in): la cara del stud sale ambigua o "sigue", y en el 15 Pro o más nuevo
    // la orilla del stud muchas veces sale con confianza baja (no vista). Lo tapado o muy hondo nunca.
    static func puedeSerStud(_ c: Columna) -> Bool {
        switch c { case .ambigua, .entera, .noVista, .sinOrilla: return true; default: return false }
    }
    func columnaTieneVotos(_ c: Int) -> Bool { (0..<Self.renglones).contains { cuenta[Self.indice(c, $0)] > 0 } }

    // La recta de tiza: el corte va con línea, así que el alto del tramo es el de una recta ajustada a los topes de las
    // columnas (sin las que se salen más de 2 in de la mediana). Se reporta el alto de esa recta a la mitad del tramo.
    static func rectaDeTiza(_ altos: [Float]) -> Float {
        var copia = altos
        let m = mediana(&copia)
        let buenos = altos.enumerated().filter { abs($0.element - m) <= 2 * pulgada }
        guard buenos.count >= 2 else { return m }
        let n = Float(buenos.count)
        let sx = buenos.reduce(Float(0)) { $0 + Float($1.offset) }, sy = buenos.reduce(Float(0)) { $0 + $1.element }
        let sxx = buenos.reduce(Float(0)) { $0 + Float($1.offset * $1.offset) }, sxy = buenos.reduce(Float(0)) { $0 + Float($1.offset) * $1.element }
        let den = n * sxx - sx * sx
        guard abs(den) > 1e-6 else { return sy / n }
        let b = (n * sxy - sx * sy) / den, a = (sy - b * sx) / n
        return a + b * Float(altos.count - 1) / 2
    }

    static func mediana(_ v: inout [Float]) -> Float {
        guard !v.isEmpty else { return 0 }
        v.sort()
        return v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
    }

    // ---------------- DEL MAPA DE PROFUNDIDAD A PUNTOS DEL MUNDO ----------------
    // Lo mismo en el teléfono y en la Mac. El mapa viene "acostado" (como la foto del sensor, 256 x 192); los
    // intrínsecos son los de la foto grande escalados a ese tamaño; la profundidad es la distancia al PLANO de la cámara.
    // Cámara de ARKit: x a la derecha, y para arriba, mira hacia -z; en la imagen la y crece para abajo.
    static func puntos(profundidad: [Float], confianza: [UInt8]?, ancho: Int, alto: Int,
                       fx: Float, fy: Float, cx: Float, cy: Float, camaraAMundo: simd_float4x4,
                       paso: Int = 2, confianzaMin: UInt8 = 2) -> [SIMD3<Float>] {
        var out: [SIMD3<Float>] = []
        out.reserveCapacity((ancho / paso) * (alto / paso))
        var y = 0
        while y < alto {
            var x = 0
            while x < ancho {
                let k = y * ancho + x
                let d = profundidad[k]
                if d.isFinite, d > 0.1, (confianza.map { $0[k] >= confianzaMin } ?? true) {
                    let local = SIMD4<Float>((Float(x) - cx) / fx * d, -(Float(y) - cy) / fy * d, -d, 1)
                    let w = camaraAMundo * local
                    out.append(SIMD3(w.x, w.y, w.z))
                }
                x += paso
            }
            y += paso
        }
        return out
    }

    // ---------------- LA PINTURA (la capa sobre la pared y el PNG de la Mac) ----------------
    // RGBA de toda la rejilla, `px` pixeles por cuadrito. Naranja = quitado y contado; amarillo = algo raro (muy hondo);
    // ámbar = hueco pero sin patrón de studs (no cuenta); rayado gris = falta ver (dentro de lo barrido, de piso a corte).
    // Lo demás, transparente. El renglón 0 de la imagen es ARRIBA.
    static let naranja: (UInt8, UInt8, UInt8, UInt8) = (255, 120, 0, 150)
    static let amarillo: (UInt8, UInt8, UInt8, UInt8) = (255, 214, 0, 160)
    static let ambar: (UInt8, UInt8, UInt8, UInt8) = (255, 176, 64, 110)
    static let grisRaya: (UInt8, UInt8, UInt8, UInt8) = (90, 90, 90, 120)

    func pintar(_ res: Resultado, piso pisoDado: Float? = nil, px: Int = 4) -> (ancho: Int, alto: Int, rgba: [UInt8]) {
        let piso = pisoDado ?? pisoRef
        let w = Self.columnas * px, h = Self.renglones * px
        var img = [UInt8](repeating: 0, count: w * h * 4)
        func llenar(_ c: Int, _ r: Int, _ col: (UInt8, UInt8, UInt8, UInt8), raya: Bool = false) {
            for yy in 0..<px {
                let fila = (Self.renglones - 1 - r) * px + yy
                for xx in 0..<px {
                    let xg = c * px + xx
                    if raya && ((xg + fila) % 6) > 1 { continue }
                    let o = (fila * w + xg) * 4
                    img[o] = col.0; img[o + 1] = col.1; img[o + 2] = col.2; img[o + 3] = col.3
                }
            }
        }
        guard colMin <= colMax else { return (w, h, img) }
        guard let piso = piso, let r0 = Self.renglonDe(piso) else {
            // Sin piso no hay número: se enseñan los huecos vistos en ámbar, para que se sepa que el láser sí los ve.
            for c in colMin...colMax { for r in 0..<Self.renglones where estado(c, r) == .cavidad { llenar(c, r, Self.ambar) } }
            return (w, h, img)
        }
        let topeBanda = (res.altoMax ?? 2 * 12 * Self.pulgada) + 6 * Self.pulgada
        let rBanda = min(Self.renglones - 1, Self.renglonDe(piso + topeBanda) ?? (Self.renglones - 1))
        let seCuenta = res.patronStuds || res.largo > 0
        for (i, col) in res.columnas.enumerated() {
            let c = res.colIni + i
            switch col {
            case .cortada(let a):
                let rTope = Self.renglonDe(piso + a - Self.celda / 2) ?? r0
                for r in r0...max(r0, rTope) { llenar(c, r, seCuenta ? Self.naranja : Self.ambar) }
            case .alarma:
                for r in r0...rBanda where estado(c, r) == .hondo || estado(c, r) == .cavidad { llenar(c, r, Self.amarillo) }
            case .noVista, .sinOrilla, .tapada:
                for r in r0...rBanda where estado(c, r) != .cavidad || col == .noVista { llenar(c, r, Self.grisRaya, raya: true) }
                if case .sinOrilla = col { for r in r0...rBanda where estado(c, r) == .cavidad { llenar(c, r, Self.ambar) } }
            case .entera, .ambigua: break
            }
        }
        return (w, h, img)
    }
}
