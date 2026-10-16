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
    // La deriva A LO LARGO de la pared (m), medida contra las orillas ya vistas (ver `corrimientoALoLargo`).
    private(set) var derivaU: Float = 0
    private var ultimoU: (corrimiento: Float, cuadro: Int)? = nil
    private var ultimoBrincoU: (du: Float, cuadro: Int)? = nil, sinBrincosUHasta = 0
    // Lo del último cuadro, para los avisos.
    private(set) var ultimoLejos: Float = 0
    private(set) var ultimoVotantes = 0
    // Cuántos brincos del rastreo se volvieron a registrar (ver `votar`), para el aviso.
    private(set) var brincos = 0
    // Lo que los brincos corrieron la cara a lo largo de la normal (in): los rayos se cruzan con la pared donde quedó.
    private(set) var brincoNormal: Float = 0

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
        // El piso es la capa PAREJA más baja: muchos puntos en 2 cm. En un cuarto, cerca de la esquina también caen aquí
        // puntos de la pared de al lado (de 0 a 1 m de alto, repartidos): con el percentil 20 subían el piso varias
        // pulgadas y el drywall de arriba caía donde está el hueco (casa 3D, 16 oct). Sin capa pareja, este cuadro no
        // mueve el piso.
        if bajos.count >= 40, let piso = Self.capaMasBaja(&bajos) {
            if let ref = pisoRef { derivaV = piso - ref } else { pisoRef = piso; derivaV = 0 }
        }
        var (pares, banda, muestras, lejos, cerca) = proyectar(puntos, camara: camara, cara: cara)
        pares.sort { $0.0 < $1.0 }
        // La banda del drywall entero (por instrucción se fijó ARRIBA del corte): solo lo que cae cerca de la cara.
        func cercaDeLaCara() -> [(u: Float, s: Float)] { banda.filter { abs($0.s - (desvio + pendiente * $0.u)) < 1.0 } }
        var referencia = cercaDeLaCara()
        // EL BRINCO DEL RASTREO (16 oct): si el mundo se corre 2.5-6 in hacia la pared y el ancla no, la banda ya no pasa
        // la compuerta de 1 in, el desvío se congelaba y el drywall entero se leía como cavidad (inventaba 4-8 SF en una
        // pared sin corte). Sin banda que pase, lo que este cuadro ve del drywall YA DECIDIDO (arriba del corte, a los lados)
        // dice cuánto se corrió: si todo se corrió lo mismo, el cuadro se vuelve a registrar antes de votar.
        if referencia.count < 30 {
            if let d = corrimientoContraLoVisto(pares) {
                // Solo un brinco HACIA la pared (0.6-8 in): es el que hace pasar drywall por cavidad. Hacia el cuarto el
                // drywall sale "tapado" y nunca se cobra; y lo de delante (un vanity, un gabinete) también da negativo y
                // corría la cara 21 in. Las diferencias chicas cuadro tras cuadro se acumulaban (cerca de una puerta subía
                // 0.2 in por cuadro).
                if d >= Self.brincoMin, d <= 8 {
                    desvio += d
                    brincoNormal += d
                    brincos += 1
                    (pares, banda, muestras, lejos, cerca) = proyectar(puntos, camara: camara, cara: cara)   // los rayos cruzan donde está la pared
                    pares.sort { $0.0 < $1.0 }
                    referencia = cercaDeLaCara()
                }
            }
        }
        // Y A LO LARGO (u): el drywall parejo no lo ve, pero sí las orillas ya vistas (los studs dentro del corte, las puntas
        // del corte). Un brinco de 3 in en u corría la punta 3 in (+3% en un corte de 8 ft). Lo que se mide contra lo de
        // antes trae su sesgo (visto de lado, la huella del stud se corre ~1 in hacia el teléfono), así que solo cuenta el
        // CAMBIO de 2 in o más contra el cuadro de antes: un brinco, nunca la deriva lenta.
        if let est = corrimientoALoLargo(muestras) {
            if let antes = ultimoU, cuadros - antes.cuadro <= 3, cuadros >= sinBrincosUHasta,
               abs(est - antes.corrimiento) >= 1.9 * Self.pulgada, corridoParejo(muestras, est) {
                var du = est - antes.corrimiento
                // Si el cuadro siguiente pide OTRA vez lo mismo, la corrección no pegó (junto a un espejo lo de antes no
                // alcanza para medirlo y se encadenaban 6 in): se deshace y no se corrige más por 6 s.
                if let u = ultimoBrincoU, cuadros - u.cuadro <= 3, du * u.du > 0 { du = -u.du; sinBrincosUHasta = cuadros + 30; ultimoBrincoU = nil }
                else { ultimoBrincoU = (du, cuadros) }
                derivaU += du
                brincos += 1
                ultimoU = (antes.corrimiento, cuadros)
                (pares, banda, muestras, lejos, cerca) = proyectar(puntos, camara: camara, cara: cara)
                pares.sort { $0.0 < $1.0 }
                referencia = cercaDeLaCara()
            } else { ultimoU = (est, cuadros) }
        }
        ultimoLejos = (lejos + cerca) > 0 ? Float(lejos) / Float(lejos + cerca) : 0
        ultimoVotantes = pares.count
        ajustarCara(referencia)
        guard !pares.isEmpty else { return }
        // Un voto por cuadro y por cuadrito: la mediana de ese cuadro, ya corregida por el desvío.
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

    // Los puntos de este cuadro en la cara: (cuadrito, s en pulgadas) y la banda de arriba (u, s) sin compuerta. Después
    // de un brinco el rayo se cruza con la pared donde quedó (la cara corrida lo que brincó): con 6 in de brinco y el rayo
    // a 40°, el cruce con la cara vieja caía 5 in más arriba y el hueco se partía.
    private func proyectar(_ puntos: [SIMD3<Float>], camara: SIMD3<Float>, cara: Cara)
        -> (pares: [(Int, Float)], banda: [(u: Float, s: Float)], muestras: [SIMD3<Float>], lejos: Int, cerca: Int) {
        var pares: [(Int, Float)] = []
        pares.reserveCapacity(puntos.count)
        var muestras: [SIMD3<Float>] = []         // (u, v, s) de cada punto que vota
        muestras.reserveCapacity(puntos.count)
        var banda: [(u: Float, s: Float)] = []
        var lejos = 0, cerca = 0
        let denominadorVotos = Float(1) / Self.pulgada
        let origenAhora = cara.origen - cara.n * (brincoNormal * Self.pulgada)
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
            let t = simd_dot(origenAhora - camara, cara.n) / cosN
            guard t > 0 else { continue }
            let x = camara + dir * t
            var q = cara.enCara(x)
            q.y -= derivaV
            q.x -= derivaU
            guard let c = Self.columnaDe(q.x), let r = Self.renglonDe(q.y) else { continue }
            let s = -simd_dot(p - cara.origen, cara.n) * denominadorVotos     // pulgadas; + = más hondo que la cara
            pares.append((Self.indice(c, r), s))
            muestras.append(SIMD3(q.x, q.y, s))
            // La banda: de 4 in abajo del punto fijado a 30 in arriba, a todo lo largo.
            if q.y > -0.10, q.y < 0.80 { banda.append((q.x, s)) }
        }
        return (pares, banda, muestras, lejos, cerca)
    }

    // ¿Cuánto más hondo (in) lee este cuadro lo que ya estaba decidido? La mediana, por cuadrito, contra lo que ese
    // cuadrito ya tenía. nil = muy poco con qué comparar, o no se corrió todo junto (no es un brinco del rastreo).
    static let brincoMin: Float = 0.6
    private func corrimientoContraLoVisto(_ pares: [(Int, Float)]) -> Float? {
        var difs: [Float] = []
        var grupo: [Float] = []
        var i = 0
        while i < pares.count {
            let k = pares[i].0
            grupo.removeAll(keepingCapacity: true)
            while i < pares.count, pares[i].0 == k { grupo.append(pares[i].1); i += 1 }
            guard grupo.count >= 3, let antes = decididoEn(k) else { continue }
            let cero = desvio + pendiente * Self.uDeColumna(k % Self.columnas)
            difs.append(Self.mediana(&grupo) - cero - antes)
        }
        guard difs.count >= 25 else { return nil }
        let d = Self.mediana(&difs)
        let juntos = difs.reduce(0) { $0 + (abs($1 - d) < 0.5 ? 1 : 0) }
        return Float(juntos) >= 0.6 * Float(difs.count) ? d : nil
    }
    // ¿Cuánto se corrió este cuadro a lo largo de la pared (m)? Se prueba de -6 a +6 in, cada 1/2 in, cuál corrimiento
    // pone mejor lo hondo de este cuadro (más de 2 in detrás de la cara) sobre la fracción honda que ya tenía cada
    // cuadrito. nil = no hay orillas vistas (pared entera) o no hay un mejor claro.
    static let corrimientoUMax = 12      // medias pulgadas
    // Un brinco corre TODO el cuadro: la mitad izquierda y la derecha tienen que pedir el mismo corrimiento (±1 in). Un
    // secador o un air mover que entra por un lado cambia lo que se ve de ese lado nada más (corría 2-3 in en falso).
    private func corridoParejo(_ muestras: [SIMD3<Float>], _ est: Float) -> Bool {
        guard let lo = muestras.map({ $0.x }).min(), let hi = muestras.map({ $0.x }).max() else { return false }
        let mitad = (lo + hi) / 2
        guard let a = corrimientoALoLargo(muestras.filter { $0.x < mitad }), let b = corrimientoALoLargo(muestras.filter { $0.x >= mitad }) else { return false }
        return abs(a - est) <= Self.pulgada && abs(b - est) <= Self.pulgada
    }
    private func corrimientoALoLargo(_ muestras: [SIMD3<Float>]) -> Float? {
        guard muestras.count >= 300 else { return nil }
        var c0 = Int.max, c1 = Int.min, r0 = Int.max, r1 = Int.min
        for m in muestras {
            guard let c = Self.columnaDe(m.x), let r = Self.renglonDe(m.y) else { continue }
            c0 = min(c0, c); c1 = max(c1, c); r0 = min(r0, r); r1 = max(r1, r)
        }
        guard c0 <= c1 else { return nil }
        c0 = max(0, c0 - 4); c1 = min(Self.columnas - 1, c1 + 4)
        let w = c1 - c0 + 1
        // Lo de antes: la fracción honda de cada cuadrito ya visto (-1 = sin ver).
        var antes = [Float](repeating: -1, count: w * (r1 - r0 + 1))
        var hayHueco = false
        for r in r0...r1 { for c in c0...c1 {
            let k = Self.indice(c, r)
            guard Int(cuenta[k]) >= Self.votosMin else { continue }
            let x = min(1, max(0, fraccionHonda[k] / Float(cuenta[k])))
            antes[(r - r0) * w + (c - c0)] = x
            if x > 0.5 { hayHueco = true }
        } }
        guard hayHueco else { return nil }
        let n = 2 * Self.corrimientoUMax + 1, paso = Self.pulgada / 2
        var costo = [Float](repeating: 0, count: n), cuantos = [Int](repeating: 0, count: n)
        for m in muestras {
            let rel = m.z - (desvio + pendiente * m.x)
            // Lo de delante y lo MUY hondo (un espejo, un paso abierto) no dicen dónde está el stud.
            guard rel > -1, rel < Self.hondoDesde, let r = Self.renglonDe(m.y) else { continue }
            let hondo: Float = rel > 2 ? 1 : 0
            let fila = (r - r0) * w
            for j in 0..<n {
                let c = Int(((m.x - Float(j - Self.corrimientoUMax) * paso - Self.uMin) / Self.celda).rounded(.down)) - c0
                guard c >= 0, c < w else { continue }
                let x = antes[fila + c]
                guard x >= 0 else { continue }
                costo[j] += (hondo - x) * (hondo - x); cuantos[j] += 1
            }
        }
        let j0 = Self.corrimientoUMax
        guard cuantos[j0] >= 200 else { return nil }
        var cs = [Float](repeating: .infinity, count: n)
        for j in 0..<n where cuantos[j] * 5 >= cuantos[j0] * 4 { cs[j] = costo[j] / Float(cuantos[j]) }
        let validos = cs.filter { $0.isFinite }
        guard validos.count >= n / 2, let minimo = validos.min() else { return nil }
        let promedio = validos.reduce(0, +) / Float(validos.count)
        // Un mínimo claro (la mitad del promedio o menos) y ANGOSTO: lo que queda cerca del mínimo cabe en 2 in y no toca la
        // orilla de la búsqueda. Viendo solo la punta del corte, todo lo corrido hacia el drywall da cero y no dice nada.
        let cerca = (0..<n).filter { cs[$0] <= minimo + 0.2 * (promedio - minimo) }
        guard minimo <= 0.5 * promedio, let j1 = cerca.first, let j2 = cerca.last, j2 - j1 <= 4, j1 > 0, j2 < n - 1 else { return nil }
        return (Float(j1 + j2) / 2 - Float(j0)) * paso
    }

    // El drywall ya decidido en un cuadrito (votos juntos a menos de 0.3 in de la cara): su mediana (in). El fondo de la
    // cavidad no sirve: su lectura cambia con el ángulo (los lados del stud) y corría la cara media pulgada.
    private func decididoEn(_ k: Int) -> Float? {
        guard Int(cuenta[k]) >= Self.votosMin else { return nil }
        var vs = votosDe(k)
        let m = Self.mediana(&vs)
        guard vs[(vs.count * 3) / 4] - vs[vs.count / 4] <= 0.5 else { return nil }
        return abs(m) < Self.sigueHasta ? m : nil
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
        // Hueco desde el piso hasta este alto y ARRIBA algo muy hondo (el vidrio de una ventana, un espejo): se cuenta
        // solo lo hueco que se vio (casa 3D, 16 oct: antes se tiraba la columna entera y bajo la ventana no se cobraba nada).
        case bajoAbertura(Float)
    }
    // La solera y el zócalo: los primeros 8 in no cortan la columna. (El plan decía 4-6 in; mirando de arriba hacia el
    // fondo de la cavidad, el ángulo y la cara de arriba de la solera dejan 4-6 in "dudosos" casi siempre.)
    static let solera: Float = 8 * pulgada
    static let abiertoMin: Float = 12 * pulgada
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
        // Drywall entero pegado al piso y el hueco empieza 8 in o más arriba: un corte que no llega al piso (antes se
        // perdía entero sin aviso). Se sube como cualquier hueco, pero solo si se vio dónde empieza (abajoDelCorte): sin
        // eso se cobraría desde el piso.
        if primera == nil, let rb = inicioArribaDelPiso(c, piso: piso), abajoDelCorte(c, piso: piso) > 0 { primera = rb }
        guard let inicio = primera else {
            // No arranca ninguna cavidad pegada al piso: ¿qué hay ahí abajo? Se mira el PRIMER pie (16 oct: con los primeros
            // 2 ft, en un corte de 1 ft entraba el drywall entero de arriba del corte y la columna de la sombra del stud de la
            // esquina salía "entera": el corte no llegaba a la esquina).
            let arriba = min(Self.renglones - 1, r0 + 6)         // el primer pie
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
            // Hay corte más arriba pero lo de abajo no es hueco: no se inventa. Si nada está DELANTE (solo la cara del
            // stud, ambigua), es la tira de un stud y no algo que tapa (casa 3D, 16 oct: partía un corte en dos).
            if cav >= 3 { return (t + tapadas == 0 && a + ambiguas > 0) ? .ambigua : .tapada }
            if s >= 4 && a <= s { return .entera }
            if a + s + ambiguas >= 4 { return .ambigua }
            return .noVista
        }
        // Para arriba mientras sea cavidad; una caja o un tubo (isla de 6 in o menos) no corta.
        var r = inicio, tope = inicio
        var hondoArriba = false
        while r < Self.renglones {
            let e = estado(c, r)
            if e == .cavidad { tope = r; r += 1; continue }
            if e == .hondo { hondoArriba = true; break }
            if let salto = islaEn(c, r) { r += salto; continue }
            break
        }
        // En un paso abierto el piso del otro cuarto se ve "hueco" en las primeras pulgadas: un hueco que termina en algo
        // muy hondo solo cuenta si mide 12 in o más (ningún antepecho de ventana está más bajo).
        if hondoArriba {
            let h = altoBajoAbertura(c, tope, piso: piso)
            return h >= Self.abiertoMin ? .bajoAbertura(h) : .alarma
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
        guard let rc = primeraCara else {
            // ¿Arriba hay una abertura (ventana, espejo)? Entre el hueco y el vidrio puede haber hasta 10 in de la solera
            // de la ventana, el repisón (delante) o nada visto.
            var ra = tope + 1
            while ra <= min(tope + 5, Self.renglones - 1) {
                let e = estado(c, ra)
                if e == .hondo { let h = altoBajoAbertura(c, tope, piso: piso); return h >= Self.abiertoMin ? .bajoAbertura(h) : .alarma }
                if e == .cavidad || e == .sigue { break }
                ra += 1
            }
            return .sinOrilla(Self.vAbajo(tope + 1) - piso)
        }
        // La orilla, integrada: desde abajo del último hueco, cada cuadrito de la transición aporta la fracción de sus
        // puntos que pasaron de largo (1 = todo hueco, 0 = todo drywall). Un corte es un escalón: eso es su altura.
        var orilla = Self.vAbajo(tope)
        for rt in tope..<rc { orilla += Self.celda * min(1, max(0, fraccion(c, rt))) }
        // Nunca fuera de los dos centros (el último hueco seguro y el primer drywall seguro).
        orilla = min(max(orilla, Self.vAbajo(tope) + Self.celda / 2), Self.vAbajo(rc) + Self.celda / 2)
        return .cortada(orilla - piso)
    }

    // ---------------- EL CORTE QUE NO LLEGA AL PISO ----------------
    // Abajo quedó drywall: una tira de 2-6 in, o el de detrás del zócalo (para salvarlo se corta arriba de él). El seguro
    // solo paga lo quitado. Lo prueba un cuadrito PAREJO (sus votos caben en 0.3 in) en la cara del drywall o con algo
    // pegado delante (el zócalo). Ojo con la solera: su cara mide 1.5 in y queda 1/2 in DETRÁS, pero con la cara de
    // referencia corrida (corte de 6 ft, pared fuera de plomo) se lee "sigue" (16 oct, banco de ataques). Por eso lo que
    // empieza a menos de 1.75 in del piso se juzga por el ESCALÓN hasta el fondo de la cavidad de junto: la tira es la
    // misma hoja que la de arriba del corte (mismo escalón que allá); la solera, media pulgada menos. Son cuadritos
    // vecinos, los ven los mismos cuadros: no les afecta que la cara de referencia se corra.
    static let bandaAltaMax: Float = 48 * pulgada        // hasta dónde se busca dónde empieza el hueco
    static let parejoMax: Float = 0.3                    // q3 - q1 de un cuadrito de una sola cara (pulgadas)
    static let caraSolera: Float = 1.75 * pulgada        // hasta aquí se puede ver la cara de la solera
    func medianaYAncho(_ c: Int, _ r: Int) -> (mediana: Float, ancho: Float)? {
        var vs = votosDe(Self.indice(c, r))
        guard vs.count >= Self.votosMin else { return nil }
        let m = Self.mediana(&vs)
        return (m, vs[(vs.count * 3) / 4] - vs[vs.count / 4])
    }
    // Dónde EMPIEZA el corte de la columna (m desde el piso; 0 = sale del piso). Antes siempre era el piso: con una tira
    // de 4 in o el zócalo puesto se cobraba +20%. La orilla de abajo se integra como la de arriba: desde arriba del primer
    // hueco se resta la fracción honda de cada cuadrito de la transición (el último drywall incluido). Sin drywall seguro
    // a 3 cuadritos o menos debajo del hueco, o con algo tapado o muy hondo abajo, es el piso (lo de antes).
    func abajoDelCorte(_ c: Int, piso: Float) -> Float {
        guard let r0 = Self.renglonDe(piso), estado(c, r0) != .cavidad else { return 0 }
        let rMax = min(Self.renglones - 1, Self.renglonDe(piso + Self.bandaAltaMax) ?? (Self.renglones - 1))
        var rb = r0 + 1
        while rb <= rMax {
            let e = estado(c, rb)
            if e == .cavidad { break }
            if e == .tapado || e == .hondo { return 0 }
            rb += 1
        }
        guard rb <= rMax else { return 0 }
        // El escalón de arriba del corte: del drywall que sigue (sin la orilla) al fondo de la cavidad de debajo.
        func medianaDe(_ rs: [Int], _ e: Estado) -> Float? {
            var v = rs.compactMap { r in estado(c, r) == e ? medianaYAncho(c, r)?.mediana : nil }
            return v.isEmpty ? nil : Self.mediana(&v)
        }
        var rc = rb
        while rc < Self.renglones, estado(c, rc) != .sigue { rc += 1 }
        let cara = rc + 1 < Self.renglones ? medianaDe(Array((rc + 1)..<min(Self.renglones, rc + 4)), .sigue) : nil
        let fondoArriba = medianaDe(Array(max(rb, rc - 3)..<max(rb, rc)), .cavidad)
        let fondoAbajo = medianaDe(Array(rb...min(rb + 2, Self.renglones - 1)), .cavidad)
        // Lo de encima de la tira es el hueco o su orilla (votos revueltos). Algo PAREJO detrás de la cara y antes del fondo
        // es la cara de arriba de la solera: abajo está su cara, revuelta con el piso (baño con vanity, 16 oct).
        func caraDetras(_ r: Int) -> Bool {
            guard r < rb, let (m, ancho) = medianaYAncho(c, r) else { return false }
            return m > Self.sigueHasta && m < Self.cavidad2x4.lowerBound && ancho <= 0.4
        }
        var solido: Int? = nil
        for r in (r0 + 1)..<rb {
            guard let (m, ancho) = medianaYAncho(c, r), ancho <= Self.parejoMax, m > -Self.tapadoDesde else { continue }
            if Self.vAbajo(r) - piso >= Self.caraSolera { if m < Self.sigueHasta { solido = r } }
            else if let fa = fondoAbajo, let fb = fondoArriba, let a = cara, fa - m >= (fb - a) - 0.2, !caraDetras(r + 1) { solido = r }
        }
        guard let rs = solido, rb - rs <= 3 else { return 0 }
        var orilla = Self.vAbajo(rb) + Self.celda
        for rt in rs...rb { orilla -= Self.celda * min(1, max(0, fraccion(c, rt))) }
        // Nunca fuera de los dos centros (el último drywall seguro y el primer hueco seguro).
        orilla = min(max(orilla, Self.vAbajo(rs) + Self.celda / 2), Self.vAbajo(rb) + Self.celda / 2)
        return max(0, orilla - piso)
    }
    // Sin hueco en los primeros 8 in: ¿empieza más arriba? Drywall entero ("sigue") desde el piso (3 cuadritos o más,
    // nada delante ni muy hondo), su orilla de abajo vista (transición de 2 cuadritos o menos) y luego 6 in o más de
    // cavidad: un cuadrito suelto o el repisón de una ventana no arrancan nada.
    private func inicioArribaDelPiso(_ c: Int, piso: Float) -> Int? {
        guard let r0 = Self.renglonDe(piso) else { return nil }
        let rMax = min(Self.renglones - 1, Self.renglonDe(piso + Self.bandaAltaMax) ?? (Self.renglones - 1))
        var sigue = 0, ultimo: Int? = nil
        var r = r0 + 1
        while r <= rMax {
            let e = estado(c, r)
            if e == .cavidad { break }
            if e == .sigue { sigue += 1; ultimo = r } else if e != .ambiguo && e != .noVisto { return nil }
            r += 1
        }
        guard r + 2 <= rMax, sigue >= 3, let u = ultimo, r - u <= 3,
              (r...(r + 2)).allSatisfy({ estado(c, $0) == .cavidad }) else { return nil }
        return r
    }

    // El alto de un hueco que termina en una abertura: hasta arriba del último cuadrito hueco, más la fracción honda del
    // siguiente (la orilla). Nunca más que medio cuadrito arriba del último hueco.
    private func altoBajoAbertura(_ c: Int, _ tope: Int, piso: Float) -> Float {
        var h = Self.vAbajo(tope) + Self.celda
        if tope + 1 < Self.renglones, estado(c, tope + 1) != .hondo { h += Self.celda / 2 * min(1, max(0, fraccion(c, tope + 1))) }
        return h - piso
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
        var esquinaIni = false, esquinaFin = false   // llega a la esquina de la pared (con `limites`)
        var abajo: Float = 0                 // dónde EMPIEZA el corte (m, desde el piso; 0 = sale del piso)
    }
    // noLlegaAlPiso: un hueco que empieza 8 in o más arriba y no se ve como corte (corto o sin dos studs: ¿nicho,
    // botiquín, caja abierta?). No se cobra, pero no se pierde callado.
    enum Alarma: Equatable { case sinPiso, hondo(Int), tapadoAbajo, sinStuds, ambiguo(Int), sinOrilla(Int), bajoAbertura(Int), noLlegaAlPiso(Int) }
    struct Resultado: Equatable {
        var tramos: [Tramo] = []
        var largo: Float = 0, area: Float = 0
        var alto: Float? = nil, altoMin: Float? = nil, altoMax: Float? = nil
        var vistoPct: Float = 0
        var alarmas: [Alarma] = []
        var columnas: [Columna] = []          // de colMin a colMax
        var abajos: [Float] = []              // por columna: dónde empieza su corte (m desde el piso; 0 = el piso)
        var colIni = 0
        var patronStuds = false
        var separacionStuds: Float? = nil     // pulgadas (16 o 24)
    }

    // Lo que dice hasta ahora. `piso`: dónde está el piso, en la coordenada v de la cara (nil = no se ha visto).
    // `piso` = nil: el que midió el comparador (lo normal en el teléfono).
    // `limites`: dónde están las DOS ESQUINAS de la pared en la cara (u, m), si se saben por la ubicación en el plano. Lo
    // de fuera (la pared de al lado) no cuenta ni avisa, y un tramo que llega a 12 in o menos de una esquina pasando solo
    // por la cara del stud de la esquina (visto, nunca drywall entero) se lleva hasta la esquina (casa 3D, 16 oct).
    static let esquinaHasta: Float = 12 * pulgada
    // LA PRUEBA DE QUE HUBO DRYWALL (16 oct, puertas cerradas y nichos que se cobraban): un corte de verdad deja ver las
    // caras de los studs cada 16 o 24 in. La hoja de una puerta cerrada, la de atrás de unas corredizas, la boca de un
    // retorno o un nicho son un hueco PLANO sin studs. Entre dos studs caben 14.5 in: un pedazo de más de 16 in sin stud
    // adentro, o una corrida sin ningún stud (ni la esquina), no se cuenta y avisa (sinStuds).
    static let sinStudMax: Float = 16 * pulgada
    // Junto a una puerta del plano (corrida unas pulgadas por la ubicación), lo hueco del alto de una puerta es la hoja.
    static let altoDePuerta: Float = 60 * pulgada
    // `ventanas` / `puertas`: dónde están, en la cara (u, m), las del plano. Bajo una ventana el vidrio no devuelve nada
    // y la orilla de arriba nunca se ve: el hueco visto desde el piso (12 in o más) se cuenta hasta donde llega. En una
    // puerta no hay drywall: nada se cuenta ahí y lo muy hondo no avisa (ya se sabe que es la puerta).
    func resultado(piso pisoDado: Float? = nil, limites: ClosedRange<Float>? = nil,
                   ventanas: [ClosedRange<Float>] = [], puertas: [ClosedRange<Float>] = []) -> Resultado {
        var res = Resultado()
        guard colMin <= colMax else { return res }
        guard let piso = pisoDado ?? pisoRef else { res.alarmas = [.sinPiso]; return res }
        res.colIni = colMin
        func fuera(_ i: Int) -> Bool {
            guard let l = limites else { return false }
            let u = Self.uDeColumna(colMin + i)
            return u < l.lowerBound || u > l.upperBound
        }
        var abiertas = 0
        func dentro(_ i: Int, _ rangos: [ClosedRange<Float>]) -> Bool { let u = Self.uDeColumna(colMin + i); return rangos.contains { $0.contains(u) } }
        var enPuerta = Set<Int>(), bajoVentana = Set<Int>()
        var cols = (colMin...colMax).enumerated().map { (i, c) -> Columna in
            if fuera(i) { return .noVista }
            if dentro(i, puertas) { enPuerta.insert(i); return .noVista }
            var col = columna(c, piso: piso)
            if dentro(i, ventanas), case .sinOrilla(let h) = col, h >= Self.abiertoMin { col = .bajoAbertura(h) }
            if case .bajoAbertura(let h) = col { abiertas += 1; bajoVentana.insert(i); return .cortada(h) }
            return col
        }
        // La puerta del plano viene corrida unas pulgadas (la ubicación) y se toma 2 in más angosta: la hoja cerrada que
        // asoma a su lado (hueco del alto de una puerta) es la misma puerta, no un corte. Se le junta hasta 12 in por lado.
        var hojas: [Int] = []
        for i in enPuerta {
            for paso in [-1, 1] where !enPuerta.contains(i + paso) {
                var x = i + paso, ultima: Int? = nil
                while x >= 0, x < cols.count, abs(x - i) <= 6 {
                    if case .cortada(let h) = cols[x], h >= Self.altoDePuerta { ultima = x }
                    else if cols[x] != .noVista && !Self.esSinOrilla(cols[x]) { break }
                    x += paso
                }
                if let u = ultima { hojas += Array(stride(from: i + paso, through: u, by: paso)) }
            }
        }
        for x in hojas { enPuerta.insert(x); cols[x] = .noVista }
        // Dónde empieza cada corte (0 = el piso). Lo que se puentea abajo (studs, una columna rara) lleva el MÁS ALTO de
        // sus dos lados: nunca de más.
        var abajos = cols.indices.map { i -> Float in Self.esCortada(cols[i]) ? abajoDelCorte(colMin + i, piso: piso) : 0 }
        // Bajo una ventana el tope del hueco es la solera de la ventana: una línea derecha. Una columna que se vio más
        // baja (visto de lado, el tope sale ambiguo) se sube a la mediana de las de su ventana; nunca más arriba.
        do {
            var i = 0
            while i < cols.count {
                guard bajoVentana.contains(i) else { i += 1; continue }
                var j = i
                var hs: [Float] = []
                while j < cols.count, bajoVentana.contains(j) || (Self.puedeSerStud(cols[j]) && j + 1 < cols.count && bajoVentana.contains(j + 1)) {
                    if bajoVentana.contains(j), case .cortada(let h) = cols[j] { hs.append(h) }
                    j += 1
                }
                if hs.count >= 3 {
                    let m = Self.mediana(&hs)
                    for k in i..<j where bajoVentana.contains(k) { if case .cortada(let h) = cols[k], h < m { cols[k] = .cortada(m) } }
                }
                i = j
            }
        }
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
               (i..<j).allSatisfy({ Self.puedeSerStud(cols[$0]) && !enPuerta.contains($0) }),
               // Lo que está DELANTE de la cara (el casing de una puerta) no es un stud: el corte termina ahí.
               !(i..<j).contains(where: { delante(colMin + $0, piso: piso, alto: min(a, b)) }) {
                // Mismo alto: el promedio. Alto distinto (el lado de una ventana: stud rey y de apoyo entre el corte de 4 ft
                // y el de bajo la ventana): el MÁS BAJO, nunca de más.
                let h = Self.altoDelPuente(a, b, ventanaIzq: bajoVentana.contains(i - 1), ventanaDer: bajoVentana.contains(j))
                // Solo es un stud si se vio su CARA (ambigua o "sigue"): una columna de hueco sin orilla o sin ver no lo es, y
                // contarla ponía un stud falso a la mitad y rompía el patrón de 16 in (casa 3D, 16 oct).
                let esStud = (i..<j).contains { cols[$0] == .ambigua || cols[$0] == .entera }
                for k in i..<j { cols[k] = .cortada(h); abajos[k] = max(abajos[i - 1], abajos[j]) }
                if esStud { studs.append(Self.uDeColumna(colMin + i) + Float(ancho - 1) * Self.celda / 2) }
            } else if i > 0, j < cols.count, ancho == 1, case .cortada(let a) = cols[i - 1], case .cortada(let b) = cols[j],
                      abs(a - b) <= 3 * Self.pulgada, !enPuerta.contains(i) {
                // UNA sola columna rara (2 in: un tubo delante, un cuadrito de ruido) en medio de un corte parejo no lo parte.
                cols[i] = .cortada((a + b) / 2)
                abajos[i] = max(abajos[i - 1], abajos[j])
            } else if i > 0, j < cols.count, ancho <= 5, case .cortada(let a) = cols[i - 1], case .cortada(let b) = cols[j],
                      !(i..<j).contains(where: { enPuerta.contains($0) }),
                      (i..<j).allSatisfy({ x in
                          switch cols[x] { case .ambigua, .noVista: return true
                          case .sinOrilla(let h): return h >= min(a, b) / 2
                          default: return false } }),
                      !(i..<j).contains(where: { delante(colMin + $0, piso: piso, alto: min(a, b)) }) {
                // Hasta 10 in de caras de stud, hueco visto desde el piso sin su orilla (visto de lado) o sin ver, entre dos
                // pedazos cortados y SIN drywall entero en medio: es el mismo corte (casa 3D, 16 oct: cerca de la esquina se
                // partía; al lado de una ventana quedaban fuera el stud rey y el de apoyo). Al alto del más bajo.
                let h = Self.altoDelPuente(a, b, ventanaIzq: bajoVentana.contains(i - 1), ventanaDer: bajoVentana.contains(j))
                for k in i..<j { cols[k] = .cortada(h); abajos[k] = max(abajos[i - 1], abajos[j]) }
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
        var sinOrilla = 0, ambiguas = 0, hondas = 0, tapadas = 0, decididas = 0, conVotos = 0, altas = 0
        var sinPrueba = 0          // corridas o pedazos huecos que no se cuentan por no tener studs
        while k < cols.count {
            if fuera(k) { k += 1; continue }
            switch cols[k] {
            case .cortada, .entera: decididas += 1; conVotos += 1
            case .sinOrilla: sinOrilla += 1; conVotos += 1
            case .ambigua: ambiguas += 1; conVotos += 1
            case .alarma: hondas += 1; conVotos += 1
            case .tapada: tapadas += 1; conVotos += 1
            case .noVista: if columnaTieneVotos(colMin + k) { conVotos += 1 }
            case .bajoAbertura: decididas += 1; conVotos += 1
            }
            guard case .cortada = cols[k] else { k += 1; continue }
            var f = k
            var colAltos: [Float] = []
            while f < cols.count, case .cortada(let a) = cols[f] { colAltos.append(a); f += 1 }
            // Una punta de 6 in o menos del alto de una puerta pegada a un corte bajo es la hoja que asoma junto a la jamba
            // (sin casing), no el mismo corte: se queda fuera. La del final queda como corrida aparte, que no tiene studs.
            var medio = colAltos
            if colAltos.count > 4, Self.mediana(&medio) < Self.altoDePuerta {
                let a0 = colAltos.prefix(4).prefix { $0 >= Self.altoDePuerta }.count
                let a1 = colAltos.suffix(4).reversed().prefix { $0 >= Self.altoDePuerta }.count
                if a0 > 0, a0 <= 3 { k += a0; colAltos.removeFirst(a0); sinPrueba += 1 }
                if a1 > 0, a1 <= 3 { f -= a1; colAltos.removeLast(a1); sinPrueba += 1 }
            }
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
                let altoCorrida = colAltos.sorted()[colAltos.count / 2]
                // ¿Llega a la esquina? Entre la punta y la esquina solo la cara del stud de la esquina (ambigua o sin
                // orilla, VISTA; a lo más 2 columnas sin ver) y a 12 in o menos. La columna pegada a la esquina (la junta
                // con la otra pared) no se juzga.
                func hastaEsquina(_ lado: Int, _ punta: Float) -> Float? {
                    guard let l = limites else { return nil }
                    let esquina = lado < 0 ? l.lowerBound : l.upperBound
                    let hueco = lado < 0 ? punta - esquina : esquina - punta
                    guard hueco <= Self.esquinaHasta else { return nil }
                    guard hueco > 0 else { return esquina }      // ya llegó (o se pasó): se queda en la esquina
                    let paso = lado < 0 ? -1 : 1
                    var x = lado < 0 ? k - 1 : f
                    var vistas = 0, sinVer = 0
                    while x >= 0, x < cols.count, !fuera(x) {
                        if abs(Self.uDeColumna(colMin + x) - esquina) <= Self.celda * 1.25 { break }
                        switch cols[x] {
                        case .ambigua, .sinOrilla:
                            if delante(colMin + x, piso: piso, alto: altoCorrida) { return nil }   // moldura o plástico, no el stud
                            vistas += 1
                        case .noVista: sinVer += 1
                        default: return nil                     // drywall entero, algo delante o muy hondo: no
                        }
                        x += paso
                    }
                    return sinVer <= 2 && (vistas > 0 || hueco <= Self.celda * 2) ? esquina : nil
                }
                // ¿Llega a una PUERTA (la del plano, o lo muy hondo de un paso)? El drywall va hasta el marco: entre la punta
                // y la puerta solo los studs del marco (rey y de apoyo: ambiguos, sin orilla o sin ver), 8 in o menos.
                func hastaAbertura(_ lado: Int, _ punta: Float) -> Float? {
                    let paso = lado < 0 ? -1 : 1
                    var x = lado < 0 ? k - 1 : f
                    var n = 0
                    // Pasado el marco (las caras de los studs, ambiguas), lo hueco que sigue ya es la puerta (la hoja cerrada):
                    // la puerta del plano trae el error de la ubicación, así que la punta se queda en el marco.
                    var vioMarco = false, finMarco: Int? = nil
                    while x >= 0, x < cols.count, n <= 4, !fuera(x) {
                        if enPuerta.contains(x) || cols[x] == .alarma {
                            let borde = Self.uDeColumna(colMin + (finMarco ?? x)) - Float(paso) * Self.celda / 2
                            return lado < 0 ? (borde < punta ? borde : nil) : (borde > punta ? borde : nil)
                        }
                        switch cols[x] { case .ambigua, .sinOrilla, .noVista: break; default: return nil }
                        // El casing o la moldura (delante de la cara): el corte llega hasta ahí, no hasta la puerta o el espejo.
                        if cols[x] != .noVista, delante(colMin + x, piso: piso, alto: altoCorrida) { return nil }
                        if cols[x] == .ambigua { vioMarco = true } else if vioMarco, finMarco == nil { finMarco = x }
                        x += paso; n += 1
                    }
                    return nil
                }
                // Escalones: el corte puede cambiar de alto (2 ft aquí, 4 ft allá). Se parte donde los 3 de un lado y los
                // 3 del otro difieren en más de 3 in; cada pedazo con su propia recta de tiza.
                let cortes = Self.escalones(colAltos)
                var deLaCorrida: [(tramo: Tramo, altos: [Float])] = []
                for z in 0..<(cortes.count - 1) {
                    let s0 = cortes[z], s1 = cortes[z + 1]
                    let pedazo = Array(colAltos[s0..<s1])
                    let eI = z == 0 ? extra(-1) : 0, eF = z == cortes.count - 2 ? extra(1) : 0
                    var uIni = Self.uDeColumna(colMin + k + s0) - Self.celda / 2 - eI
                    var uFin = Self.uDeColumna(colMin + k + s1 - 1) + Self.celda / 2 + eF
                    let recta = Self.rectaDeTiza(pedazo)
                    // Dónde empieza el pedazo: la mediana de sus columnas (la tira o el zócalo van a todo lo largo; unas
                    // pocas columnas de menos de 8 in no mueven nada: ahí manda lo de antes). Si empieza arriba, ninguna
                    // columna empieza más abajo que eso; una columna que empieza a 8 in o más nunca se cobra desde el piso.
                    // El área es lo quitado: de abajo a la recta de tiza.
                    var copia = Array(abajos[(k + s0)..<(k + s1)])
                    let abajoT = Self.mediana(&copia)
                    for x in (k + s0)..<(k + s1) { abajos[x] = abajoT > 0 ? max(abajos[x], abajoT) : (abajos[x] >= Self.solera ? abajos[x] : 0) }
                    let bajos = Array(abajos[(k + s0)..<(k + s1)])
                    let banda = max(0, recta - abajoT)
                    var area = zip(pedazo, bajos).reduce(Float(0)) { $0 + max(0, $1.0 - $1.1) } * Self.celda + (eI + eF) * banda
                    // Si quedaron columnas altas sueltas, el pedazo dice el promedio (así el plano no lo lleva a la medida
                    // de corte desde el piso).
                    let abajoTramo = abajoT > 0 ? abajoT : bajos.reduce(0, +) / Float(bajos.count)
                    var escI = false, escF = false
                    if z == 0, let e = hastaEsquina(-1, uIni) { area += max(0, uIni - e) * banda; uIni = e; escI = true }
                    else if z == 0, let e = hastaAbertura(-1, uIni) { area += (uIni - e) * banda; uIni = e }
                    if z == cortes.count - 2, let e = hastaEsquina(1, uFin) { area += max(0, e - uFin) * banda; uFin = e; escF = true }
                    else if z == cortes.count - 2, let e = hastaAbertura(1, uFin) { area += (e - uFin) * banda; uFin = e }
                    let ordenados = pedazo.sorted()
                    let m = pedazo.count
                    let tramoStuds = studs.filter { $0 >= uIni && $0 <= uFin }.count
                    // Un hueco que empieza 8 in o más arriba solo es corte si se ve como uno: 3 ft o más con dos studs
                    // adentro. Un nicho, un botiquín o una caja abierta no se cobran (quedan en ámbar) pero avisan.
                    if abajoT >= Self.solera && (uFin - uIni < 3 * 12 * Self.pulgada || tramoStuds < 2) { altas += m; continue }
                    // Un pedazo de más de 16 in sin stud adentro (ni la esquina), o uno del alto de una puerta, es un hueco
                    // plano: la hoja de una puerta que sigue a un corte de verdad. No se cuenta.
                    if tramoStuds == 0, !escI, !escF, Float(m) * Self.celda > Self.sinStudMax || recta >= Self.altoDePuerta { sinPrueba += 1; continue }
                    deLaCorrida.append((Tramo(uIni: uIni, uFin: uFin, largo: uFin - uIni, alto: recta,
                                              altoMin: ordenados[Int(Float(m - 1) * 0.1)], altoMax: ordenados[Int(Float(m - 1) * 0.9)],
                                              area: area, studs: tramoStuds, esquinaIni: escI, esquinaFin: escF, abajo: abajoTramo), pedazo))
                }
                // Y la corrida entera necesita un stud visto (o llegar a la esquina, que tiene el suyo): un retorno de aire,
                // un nicho o el hueco del lavaplatos caben entre dos studs y no son corte.
                if deLaCorrida.contains(where: { $0.tramo.studs > 0 || $0.tramo.esquinaIni || $0.tramo.esquinaFin }) {
                    for t in deLaCorrida { res.tramos.append(t.tramo); altos.append(contentsOf: t.altos) }
                } else if !deLaCorrida.isEmpty { sinPrueba += 1 }
            }
            k = f
        }
        // En una pared corta solo hay uno o dos studs adentro: si el corte llega a la esquina, el stud de la esquina también
        // cuenta para el patrón (16 oct, el frente de un cajón de 3 ft).
        if !res.patronStuds, let l = limites, res.tramos.contains(where: { $0.esquinaIni || $0.esquinaFin }) {
            var con = studs
            for t in res.tramos {
                if t.esquinaIni, l.lowerBound.isFinite { con.append(l.lowerBound + 0.75 * Self.pulgada) }
                if t.esquinaFin, l.upperBound.isFinite { con.append(l.upperBound - 0.75 * Self.pulgada) }
            }
            con.sort()
            if con.count >= 2 {
                for k in 1..<con.count {
                    let d = (con[k] - con[k - 1]) / Self.pulgada
                    if abs(d - 16) <= 1.5 || abs(d - 24) <= 1.5 { res.patronStuds = true; res.separacionStuds = abs(d - 16) <= 1.5 ? 16 : 24; break }
                }
            }
        }
        // Sin patrón de studs no se pinta naranja ni se cuenta (un sótano sin terminar, una puerta, un espejo...).
        let cortado = res.tramos.reduce(Float(0)) { $0 + $1.largo }
        if (!res.patronStuds && cortado >= 3 * 12 * Self.pulgada) || sinPrueba > 0 { res.alarmas.append(.sinStuds) }
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
        if abiertas > 0 { res.alarmas.append(.bajoAbertura(abiertas)) }
        if tapadas >= 3 { res.alarmas.append(.tapadoAbajo) }
        if ambiguas >= 6 { res.alarmas.append(.ambiguo(ambiguas)) }
        if sinOrilla >= 3 { res.alarmas.append(.sinOrilla(sinOrilla)) }
        if altas >= 3 { res.alarmas.append(.noLlegaAlPiso(altas)) }
        res.abajos = abajos
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
    // ¿Esta columna está DELANTE de la cara (casing, moldura, plástico)? Sale "ambigua" igual que la cara del stud, pero el
    // stud queda DETRÁS (+1/2 in) y la moldura delante (-1/2 a -3/4 in): un corte no pasa por encima de una moldura.
    // Se mira la franja del corte (de la solera a `alto` del piso; 6 in por lo menos).
    func delante(_ c: Int, piso: Float, alto: Float) -> Bool {
        guard let ra = Self.renglonDe(piso + Self.solera), let rb = Self.renglonDe(piso + max(alto, Self.solera + 6 * Self.pulgada)) else { return false }
        var ms: [Float] = []
        for r in ra...rb {
            let k = Self.indice(c, r)
            guard Int(cuenta[k]) >= Self.votosMin else { continue }
            var vs = votosDe(k)
            ms.append(Self.mediana(&vs))
        }
        return ms.count >= 3 && Self.mediana(&ms) < -Self.sigueHasta
    }

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

    // La capa más baja con al menos 30 puntos (y el 15 % de todos) dentro de 2 cm: su mediana. nil = no hay capa pareja.
    static func capaMasBaja(_ v: inout [Float]) -> Float? {
        v.sort()
        let minimo = max(30, v.count * 15 / 100)
        var j = 0
        for i in 0..<v.count {
            if j < i { j = i }
            while j + 1 < v.count, v[j + 1] - v[i] <= 0.02 { j += 1 }
            if j - i + 1 >= minimo { return v[(i + j) / 2] }
        }
        return nil
    }

    // El alto que se le da a lo que se puentea: mismo alto -> el promedio; alto distinto -> el más bajo (nunca de más),
    // salvo junto a una ventana: los studs rey y de apoyo están FUERA de la ventana y llevan el alto del corte de afuera.
    static func altoDelPuente(_ a: Float, _ b: Float, ventanaIzq: Bool, ventanaDer: Bool) -> Float {
        if abs(a - b) <= 3 * pulgada { return (a + b) / 2 }
        if ventanaIzq != ventanaDer { return ventanaIzq ? b : a }
        return min(a, b)
    }

    // Dónde cambia de alto un tramo: [0, ..., n]. Un escalón es donde los 3 de un lado y los 3 del otro difieren en más
    // de 3 in; el lugar exacto es el que mejor parte en dos niveles (±2 columnas), y ningún pedazo mide menos de 8 in
    // (un pedazo chico se junta con el vecino de alto más parecido: es la orilla del escalón).
    static func escalones(_ altos: [Float]) -> [Int] {
        let n = altos.count
        var cortes = [0]
        var q = 3
        while q <= n - 3 {
            var a = Array(altos[(q - 3)..<q]), b = Array(altos[q..<(q + 3)])
            guard abs(mediana(&a) - mediana(&b)) > 3 * pulgada else { q += 1; continue }
            let lo = max(cortes.last! + 1, q - 2), hi = min(n - 1, q + 3)
            var mejor = q, costo = Float.infinity
            for j in lo...max(lo, hi) {
                let w0 = max(cortes.last!, j - 5), w1 = min(n, j + 5)
                guard w0 < j, j < w1 else { continue }
                var l = Array(altos[w0..<j]), r = Array(altos[j..<w1])
                let ml = mediana(&l), mr = mediana(&r)
                var c: Float = 0
                for x in altos[w0..<j] { c += (x - ml) * (x - ml) }
                for x in altos[j..<w1] { c += (x - mr) * (x - mr) }
                if c < costo { costo = c; mejor = j }
            }
            cortes.append(mejor)
            q = mejor + 3
        }
        cortes.append(n)
        // Se repite hasta que no cambie nada: dos pedazos vecinos del mismo alto (3 in o menos) son el mismo corte (un
        // bache de ruido no lo parte), y un pedazo de menos de 4 columnas (8 in) se junta con el vecino de alto más
        // parecido (es la orilla del escalón).
        func med(_ z: Int) -> Float { var v = Array(altos[cortes[z]..<cortes[z + 1]]); return mediana(&v) }
        var cambio = true
        while cambio && cortes.count > 2 {
            cambio = false
            var z0 = 1
            while z0 < cortes.count - 1 {
                if abs(med(z0 - 1) - med(z0)) <= 3 * pulgada + 1e-4 { cortes.remove(at: z0); cambio = true } else { z0 += 1 }
            }
            for z in 0..<(cortes.count - 1) where cortes[z + 1] - cortes[z] < 4 {
                let mp = med(z)
                let dIzq = z > 0 ? abs(med(z - 1) - mp) : Float.infinity
                let dDer = z + 2 < cortes.count ? abs(med(z + 1) - mp) : Float.infinity
                if dIzq == .infinity && dDer == .infinity { break }
                cortes.remove(at: dIzq <= dDer ? z : z + 1)
                cambio = true
                break
            }
        }
        return cortes
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

    func pintar(_ res: Resultado, piso pisoDado: Float? = nil, px: Int = 4, limites: ClosedRange<Float>? = nil) -> (ancho: Int, alto: Int, rgba: [UInt8]) {
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
            if let l = limites, !l.contains(Self.uDeColumna(c)) { continue }     // la pared de al lado: no se pinta
            switch col {
            case .cortada(let a):
                let rTope = Self.renglonDe(piso + a - Self.celda / 2) ?? r0
                // Lo hueco que no quedó en ningún tramo (sin studs: una puerta cerrada, un nicho) va en ámbar.
                let u = Self.uDeColumna(c)
                let enTramo = res.tramos.contains { u >= $0.uIni - Self.celda / 2 && u <= $0.uFin + Self.celda / 2 }
                // Desde donde empieza el corte: la tira de abajo (o lo de detrás del zócalo) no se pinta.
                let b = i < res.abajos.count ? res.abajos[i] : 0
                let rBase = b > 0 ? (Self.renglonDe(piso + b + Self.celda / 2) ?? r0) : r0
                for r in rBase...max(rBase, rTope) { llenar(c, r, seCuenta && enTramo ? Self.naranja : Self.ambar) }
            case .alarma:
                for r in r0...rBanda where estado(c, r) == .hondo || estado(c, r) == .cavidad { llenar(c, r, Self.amarillo) }
            case .noVista, .sinOrilla, .tapada:
                for r in r0...rBanda where estado(c, r) != .cavidad || col == .noVista { llenar(c, r, Self.grisRaya, raya: true) }
                if case .sinOrilla = col { for r in r0...rBanda where estado(c, r) == .cavidad { llenar(c, r, Self.ambar) } }
            case .entera, .ambigua, .bajoAbertura: break
            }
        }
        return (w, h, img)
    }
}
