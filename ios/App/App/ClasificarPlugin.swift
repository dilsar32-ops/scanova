import Foundation
import Capacitor
import Vision

// CLASIFICAR (11 oct 2026): el reconocedor de objetos del propio iPhone (Vision, ~1,300
// categorias de Apple). Gratis, sin internet, y la foto NO sale del telefono.
// Devuelve las etiquetas de Apple (en ingles) con su confianza; la parte web (www) pone
// el espanol, escoge la mas concreta y la ensena como "sugerido" para que la cuadrilla
// la corrija. `path` es relativo a Documents, igual que Subir.md5: lo que el Filesystem
// de Capacitor guarda en DATA (contenidos/<trabajo>/foto-<k>.jpg).
//
//   imagen({ path, maximo? })  -> { etiquetas: [{ id, conf }], motor: "apple-vision" }
//   disponible()               -> { ok: true, motor }
@objc(ClasificarPlugin)
public class ClasificarPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "ClasificarPlugin"
    public let jsName = "Clasificar"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "imagen", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "disponible", returnType: CAPPluginReturnPromise)
    ]

    @objc func disponible(_ call: CAPPluginCall) {
        call.resolve(["ok": true, "motor": "apple-vision"])
    }

    private func archivo(_ call: CAPPluginCall) -> URL? {
        guard let rel = call.getString("path"), !rel.isEmpty, !rel.contains(".."),
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = docs.appendingPathComponent(rel)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @objc func imagen(_ call: CAPPluginCall) {
        guard let url = archivo(call) else { call.reject("No se encontro la foto", "ruta"); return }
        let maximo = max(1, min(call.getInt("maximo") ?? 12, 40))
        DispatchQueue.global(qos: .userInitiated).async {
            let req = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(url: url, options: [:])
            do {
                try handler.perform([req])
                let obs = (req.results ?? [])
                    .filter { $0.confidence >= 0.02 }
                    .sorted { $0.confidence > $1.confidence }
                    .prefix(maximo)
                let etiquetas: [[String: Any]] = obs.map { ["id": $0.identifier, "conf": Double($0.confidence)] }
                call.resolve(["etiquetas": etiquetas, "motor": "apple-vision"])
            } catch {
                call.reject("No se pudo clasificar: " + error.localizedDescription, "vision")
            }
        }
    }
}
