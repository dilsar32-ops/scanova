// leer_barrido — corre EL MISMO comparador del teléfono sobre una grabación de "Probar lo demolido" (15 oct 2026).
// Dice, pared por pared, lo que vio (largo, alto, pies cuadrados, % visto, alarmas) junto a lo que dijo el teléfono, y
// saca un PNG del alzado de cada pared (naranja = quitado y contado, amarillo = raro, rayado = falta ver).
// Compilar y usar (en la Mac):
//   xcrun swiftc -O -parse-as-library ios/App/App/ComparadorDeDemolicion.swift ios/App/App/GrabadoraDeBarrido.swift tools/leer_barrido.swift -o /tmp/leer_barrido
//   /tmp/leer_barrido barrido.scb [carpeta-para-los-png]
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main
struct LeerBarrido {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else { print("uso: leer_barrido <grabacion.scb> [carpeta para los PNG]"); exit(2) }
        let url = URL(fileURLWithPath: args[1])
        let carpeta = args.count >= 3 ? URL(fileURLWithPath: args[2]) : url.deletingLastPathComponent()
        do {
            let registros = try LectorDeBarrido.leer(url)
            var meta: [String: Any] = [:]
            var fotos = 0, cuadros = 0
            for r in registros {
                if case .meta(let m) = r { meta = m }
                if case .foto = r { fotos += 1 }
                if case .cuadro(let c) = r, !c.suavizada { cuadros += 1 }
            }
            print("Grabación: \(url.lastPathComponent) · \(meta["modelo"] ?? "?") iOS \(meta["ios"] ?? "?") · \(cuadros) cuadros de profundidad · \(fotos) fotos")
            let paredes = LectorDeBarrido.repetir(registros)
            for (i, p) in paredes.enumerated() {
                let r = p.comparador.resultado()
                print("\nPared \(i + 1) (\(p.cuadros) cuadros):")
                print("  Mac:      " + texto(r))
                if let t = p.resumenTelefono?["texto"] as? String { print("  Teléfono: " + t) }
                let img = p.comparador.pintar(r, px: 4)
                let png = carpeta.appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-pared\(i + 1).png")
                if guardarPNG(img, png) { print("  Alzado:   \(png.path)") }
            }
        } catch {
            print("No se pudo leer: \(error)"); exit(1)
        }
    }

    static func piesPulgadas(_ m: Float) -> String {
        let pulg = Int((m / 0.0254).rounded())
        return pulg >= 12 ? "\(pulg / 12) ft \(pulg % 12) in" : "\(pulg) in"
    }
    static func texto(_ r: ComparadorDeDemolicion.Resultado) -> String {
        var s = "visto \(piesPulgadas(r.largo)) de largo"
        if let a = r.alto, let lo = r.altoMin, let hi = r.altoMax { s += " · alto \(piesPulgadas(a)) (\(piesPulgadas(lo)) – \(piesPulgadas(hi)))" }
        s += String(format: " · %.1f SF · visto %.0f%%", r.area / (0.3048 * 0.3048), r.vistoPct * 100)
        if let sep = r.separacionStuds { s += " · studs cada \(Int(sep)) in" }
        if !r.alarmas.isEmpty { s += " · alarmas \(r.alarmas)" }
        return s
    }
    static func guardarPNG(_ img: (ancho: Int, alto: Int, rgba: [UInt8]), _ url: URL) -> Bool {
        // Fondo blanco con la rejilla gris clara, y la pintura encima.
        var px = [UInt8](repeating: 255, count: img.ancho * img.alto * 4)
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = Float(img.rgba[i + 3]) / 255
            for k in 0..<3 { px[i + k] = UInt8(Float(img.rgba[i + k]) * a + 255 * (1 - a)) }
            px[i + 3] = 255
        }
        guard let prov = CGDataProvider(data: Data(px) as CFData),
              let cg = CGImage(width: img.ancho, height: img.alto, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: img.ancho * 4,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, cg, nil)
        return CGImageDestinationFinalize(dest)
    }
}
