import Foundation

// (17-oct) Lo guardado en la cámara queda en el teléfono AL MOMENTO: si la app se cierra, se cae o se acaba la batería,
// la página lo recupera la próxima vez. Un archivo por sesión: borradores-camara/<trabajo>/<sesion>.json.
// Sin trabajo (Field Reports) no se escribe nada.
enum BorradorCamara {
    static var base: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first   // var: las pruebas la cambian
    static func carpeta(_ trabajo: String) -> URL? {
        let limpio = trabajo.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        guard !limpio.isEmpty, let b = base else { return nil }
        return b.appendingPathComponent("borradores-camara", isDirectory: true).appendingPathComponent(limpio, isDirectory: true)
    }
    static func escribir(trabajo: String, sesion: String, orden: Double, medidas: [[String: Any]]) {
        guard let dir = carpeta(trabajo) else { return }
        let url = dir.appendingPathComponent(sesion + ".json")
        if medidas.isEmpty { try? FileManager.default.removeItem(at: url); return }   // todo deshecho: nada que recuperar
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let datos = try JSONSerialization.data(withJSONObject: ["sesion": sesion, "orden": orden, "medidas": medidas])
            try datos.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { NSLog("BorradorCamara: no se pudo escribir \(error)") }
    }
    // La sesión que la cámara tiene abierta ahora mismo: ni se entrega ni se borra hasta que la cámara termina
    // (si no, un Deshacer después de recogerla dejaría una medida fantasma en la tarjeta de la página).
    static var abierta: String?
    static let diasMaximo: Double = 30
    // Lo de trabajos que nunca se vuelven a abrir: los archivos de más de 30 días se van, en todos los trabajos.
    static func limpiarViejos() {
        guard let b = base else { return }
        let raiz = b.appendingPathComponent("borradores-camara", isDirectory: true), fm = FileManager.default
        let limite = Date().addingTimeInterval(-diasMaximo * 86400)
        for t in (try? fm.contentsOfDirectory(at: raiz, includingPropertiesForKeys: nil)) ?? [] {
            let archivos = (try? fm.contentsOfDirectory(at: t, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for a in archivos where a.deletingPathExtension().lastPathComponent != abierta {
                if let f = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, f < limite { try? fm.removeItem(at: a) }
            }
            if ((try? fm.contentsOfDirectory(atPath: t.path)) ?? []).isEmpty { try? fm.removeItem(at: t) }
        }
    }
    static func borrar(trabajo: String, sesion: String) {
        guard let dir = carpeta(trabajo), !sesion.isEmpty, !sesion.contains("/"), sesion != abierta else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(sesion + ".json"))
    }
    static func leer(trabajo: String) -> [[String: Any]] {
        limpiarViejos()
        guard let dir = carpeta(trabajo),
              let nombres = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return nombres.filter { $0.hasSuffix(".json") && $0 != (abierta ?? "") + ".json" }.sorted().compactMap { n in
            guard let d = try? Data(contentsOf: dir.appendingPathComponent(n)),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let m = o["medidas"] as? [[String: Any]], !m.isEmpty else { return nil }
            return o
        }
    }
}
