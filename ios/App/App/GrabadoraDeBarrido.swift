// GrabadoraDeBarrido.swift — la grabación de cada prueba de "Probar lo demolido" (15 oct 2026).
//
// Para qué: el laboratorio contesta una sola pregunta, ¿el láser ve el corte y lo mide bien? La respuesta sale de comparar
// contra la cinta, y los umbrales se ajustan en la Mac SIN volver a la obra: tools/leer_barrido.swift corre el MISMO
// comparador sobre esta grabación y tiene que dar el mismo número que dio el teléfono.
//
// Qué guarda (todo comprimido al vuelo, registro por registro, con tope de 3 minutos):
//   · la profundidad del láser (sceneDepth) 5 veces por segundo, en milímetros (UInt16) con su confianza;
//   · la profundidad suavizada 1 vez por segundo (solo para comparar después);
//   · la pose del teléfono, los intrínsecos ya escalados al mapa, el rastreo, la luz y la temperatura;
//   · los planos que ve ARKit 1 vez por segundo, 1 foto chica por segundo, y los eventos (fijar pared, otra pared).
// No guarda nada del cliente. El archivo sale por la hoja de Compartir (AirDrop) y nunca se sube solo.
//
// Formato: "SCNVBARR" + versión (1 byte), luego registros [tipo 1 byte][largo comprimido UInt32][largo original
// UInt32][datos LZFSE]. Foundation + simd: compila igual en el iPhone y en la Mac.

import Foundation
import simd

final class GrabadoraDeBarrido {
    static let magia = Array("SCNVBARR".utf8)
    static let version: UInt8 = 1
    static let topeSegundos: Double = 180
    enum Tipo: UInt8 { case meta = 1, profundidad = 2, suavizada = 3, planos = 4, foto = 5, evento = 6 }

    let url: URL
    private var archivo: FileHandle?
    private(set) var bytes = 0
    private(set) var cuadros = 0
    private var inicio: Double?
    private(set) var cerrada = false
    var segundos: Double { inicio.map { ultimoT - $0 } ?? 0 }
    private var ultimoT: Double = 0
    var llena: Bool { segundos >= Self.topeSegundos }

    init?(url: URL, meta: [String: Any]) {
        self.url = url
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let h = try? FileHandle(forWritingTo: url) else { return nil }
        archivo = h
        var cab = Data(Self.magia); cab.append(Self.version)
        h.write(cab); bytes = cab.count
        escribir(.meta, Self.json(meta))
    }

    // ---------------- lo que se agrega ----------------
    func profundidad(t: Double, ancho: Int, alto: Int, metros: [Float], confianza: [UInt8]?, pose: simd_float4x4,
                     fx: Float, fy: Float, cx: Float, cy: Float, extra: [String: Any], suavizada: Bool = false) {
        guard !cerrada, !llena else { return }
        if inicio == nil { inicio = t }
        ultimoT = t
        var d = Data(capacity: 128 + ancho * alto * 3)
        Self.poner(&d, t)
        Self.poner(&d, Int32(ancho)); Self.poner(&d, Int32(alto))
        for c in 0..<4 { for f in 0..<4 { Self.poner(&d, pose[c][f]) } }
        for v in [fx, fy, cx, cy] { Self.poner(&d, v) }
        var mm = [UInt16](repeating: 0, count: ancho * alto)
        for i in 0..<min(mm.count, metros.count) {
            let m = metros[i]
            mm[i] = m.isFinite && m > 0 ? UInt16(min(65535, (m * 1000).rounded())) : 0
        }
        mm.withUnsafeBytes { d.append(contentsOf: $0) }
        let conf = confianza ?? [UInt8](repeating: 2, count: ancho * alto)
        d.append(contentsOf: conf.prefix(ancho * alto))
        let ex = Self.json(extra)
        Self.poner(&d, UInt32(ex.count)); d.append(ex)
        escribir(suavizada ? .suavizada : .profundidad, d)
        if !suavizada { cuadros += 1 }
    }
    func planos(t: Double, _ lista: [[String: Any]]) { guard !cerrada, !llena else { return }; escribir(.planos, Self.json(["t": t, "planos": lista])) }
    func foto(t: Double, jpeg: Data) {
        guard !cerrada, !llena else { return }
        var d = Data(); Self.poner(&d, t); d.append(jpeg)
        escribir(.foto, d)
    }
    func evento(t: Double, _ e: [String: Any]) {
        guard !cerrada else { return }
        var e2 = e; e2["t"] = t
        escribir(.evento, Self.json(e2))
    }
    func cerrar() {
        guard !cerrada else { return }
        cerrada = true
        try? archivo?.synchronize()
        try? archivo?.close()
        archivo = nil
    }

    // ---------------- por dentro ----------------
    private func escribir(_ tipo: Tipo, _ datos: Data) {
        guard let h = archivo else { return }
        let comp = (try? (datos as NSData).compressed(using: .lzfse) as Data) ?? datos
        var r = Data([tipo.rawValue])
        Self.poner(&r, UInt32(comp.count)); Self.poner(&r, UInt32(datos.count))
        r.append(comp)
        h.write(r)
        bytes += r.count
    }
    static func poner<T>(_ d: inout Data, _ v: T) { withUnsafeBytes(of: v) { d.append(contentsOf: $0) } }
    static func json(_ o: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: limpio(o), options: [.sortedKeys])) ?? Data("{}".utf8)
    }
    // JSONSerialization no acepta Float ni NaN: todo a Double finito.
    private static func limpio(_ v: Any) -> Any {
        if let d = v as? [String: Any] { return d.mapValues { limpio($0) } }
        if let a = v as? [Any] { return a.map { limpio($0) } }
        if let f = v as? Float { return f.isFinite ? Double(f) : NSNull() }
        if let x = v as? Double { return x.isFinite ? x : NSNull() }
        return v
    }
}

// ---------------- LEER UNA GRABACIÓN (la Mac, y la prueba) ----------------
struct LectorDeBarrido {
    struct Cuadro {
        var t: Double
        var ancho: Int, alto: Int
        var pose: simd_float4x4
        var fx: Float, fy: Float, cx: Float, cy: Float
        var metros: [Float]
        var confianza: [UInt8]
        var extra: [String: Any]
        var suavizada: Bool
    }
    enum Registro {
        case meta([String: Any])
        case cuadro(Cuadro)
        case planos([String: Any])
        case foto(Double, Data)
        case evento([String: Any])
    }
    enum Problema: Error { case noEsBarrido, cortado }

    static func leer(_ url: URL) throws -> [Registro] {
        let todo = try Data(contentsOf: url)
        guard todo.count >= 9, Array(todo.prefix(8)) == GrabadoraDeBarrido.magia else { throw Problema.noEsBarrido }
        var i = 9
        var out: [Registro] = []
        while i + 9 <= todo.count {
            let tipo = todo[todo.startIndex + i]
            let nComp = Int(leerU32(todo, i + 1)), nOrig = Int(leerU32(todo, i + 5))
            i += 9
            guard i + nComp <= todo.count else { throw Problema.cortado }
            let comp = todo.subdata(in: (todo.startIndex + i)..<(todo.startIndex + i + nComp))
            i += nComp
            let datos = nComp == nOrig ? comp : ((try? (comp as NSData).decompressed(using: .lzfse) as Data) ?? comp)
            switch GrabadoraDeBarrido.Tipo(rawValue: tipo) {
            case .meta: out.append(.meta(objeto(datos)))
            case .planos: out.append(.planos(objeto(datos)))
            case .evento: out.append(.evento(objeto(datos)))
            case .foto:
                let t = datos.withUnsafeBytes { $0.loadUnaligned(as: Double.self) }
                out.append(.foto(t, datos.subdata(in: (datos.startIndex + 8)..<datos.endIndex)))
            case .profundidad, .suavizada:
                if let c = cuadro(datos, suavizada: tipo == GrabadoraDeBarrido.Tipo.suavizada.rawValue) { out.append(.cuadro(c)) }
            case .none: break
            }
        }
        return out
    }
    private static func leerU32(_ d: Data, _ o: Int) -> UInt32 {
        d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) }
    }
    private static func objeto(_ d: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:] }
    private static func cuadro(_ d: Data, suavizada: Bool) -> Cuadro? {
        return d.withUnsafeBytes { b -> Cuadro? in
            var o = 0
            func lee<T>(_: T.Type) -> T { let v = b.loadUnaligned(fromByteOffset: o, as: T.self); o += MemoryLayout<T>.size; return v }
            guard b.count >= 8 + 8 + 64 + 16 else { return nil }
            let t = lee(Double.self)
            let w = Int(lee(Int32.self)), h = Int(lee(Int32.self))
            var pose = matrix_identity_float4x4
            for c in 0..<4 { for f in 0..<4 { pose[c][f] = lee(Float.self) } }
            let fx = lee(Float.self), fy = lee(Float.self), cx = lee(Float.self), cy = lee(Float.self)
            let n = w * h
            guard b.count >= o + n * 3 + 4 else { return nil }
            var metros = [Float](repeating: 0, count: n)
            for k in 0..<n { let mm = lee(UInt16.self); metros[k] = mm == 0 ? .nan : Float(mm) / 1000 }
            let conf = Array(b[o..<(o + n)]); o += n
            let nEx = Int(lee(UInt32.self))
            let ex = nEx > 0 && o + nEx <= b.count ? objeto(Data(b[o..<(o + nEx)])) : [:]
            return Cuadro(t: t, ancho: w, alto: h, pose: pose, fx: fx, fy: fy, cx: cx, cy: cy, metros: metros, confianza: conf, extra: ex, suavizada: suavizada)
        }
    }

    // La cara que usó el teléfono en ese cuadro (viaja en `extra`), para correr el comparador IGUAL en la Mac.
    static func cara(_ ex: [String: Any]) -> ComparadorDeDemolicion.Cara? {
        guard let c = ex["cara"] as? [Double], c.count == 12 else { return nil }
        let f = c.map { Float($0) }
        return ComparadorDeDemolicion.Cara(origen: SIMD3(f[0], f[1], f[2]), u: SIMD3(f[3], f[4], f[5]), v: SIMD3(f[6], f[7], f[8]), n: SIMD3(f[9], f[10], f[11]))
    }
    static func caraComoLista(_ c: ComparadorDeDemolicion.Cara) -> [Double] {
        [c.origen, c.u, c.v, c.n].flatMap { [Double($0.x), Double($0.y), Double($0.z)] }
    }
}

// ---------------- CORRER OTRA VEZ EL COMPARADOR SOBRE UNA GRABACIÓN ----------------
// Lo usa la Mac (tools/leer_barrido.swift) y la prueba. Cada "fijar" empieza una pared nueva; "reiniciar" la vuelve a
// empezar (el ancla brincó o se perdió el rastreo). Los puntos salen con el MISMO paso y la misma confianza mínima que
// usó el teléfono (vienen en la cabecera).
extension LectorDeBarrido {
    struct Pared {
        var cara: ComparadorDeDemolicion.Cara
        var comparador = ComparadorDeDemolicion()
        var cuadros = 0
        var resumenTelefono: [String: Any]? = nil
    }
    static func repetir(_ registros: [Registro]) -> [Pared] {
        var paso = 2, confMin: UInt8 = 2
        var paredes: [Pared] = []
        for r in registros {
            switch r {
            case .meta(let m):
                if let p = m["paso"] as? Int { paso = p }
                if let c = m["confianzaMin"] as? Int { confMin = UInt8(c) }
            case .evento(let e):
                let que = e["evento"] as? String ?? ""
                if que == "fijar", let c = cara(e) { paredes.append(Pared(cara: c)) }
                if que == "reiniciar", var p = paredes.popLast() { p.comparador.reiniciar(); p.cuadros = 0; paredes.append(p) }
                if que == "resumen", var p = paredes.popLast() { p.resumenTelefono = e; paredes.append(p) }
            case .cuadro(let c):
                guard !c.suavizada, var p = paredes.popLast() else { continue }
                let caraAhora = cara(c.extra) ?? p.cara
                let pts = ComparadorDeDemolicion.puntos(profundidad: c.metros, confianza: c.confianza, ancho: c.ancho, alto: c.alto,
                                                        fx: c.fx, fy: c.fy, cx: c.cx, cy: c.cy, camaraAMundo: c.pose,
                                                        paso: paso, confianzaMin: confMin)
                let cam = SIMD3<Float>(c.pose.columns.3.x, c.pose.columns.3.y, c.pose.columns.3.z)
                p.comparador.votar(camara: cam, puntos: pts, cara: caraAhora)
                p.cuadros += 1
                paredes.append(p)
            default: break
            }
        }
        return paredes
    }
}
