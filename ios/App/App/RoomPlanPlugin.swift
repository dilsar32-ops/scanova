import Foundation
import Capacitor
import RoomPlan
import QuickLook

// Bridges the JS side ("Capacitor.Plugins.RoomScan.scan()") to the native
// LiDAR floor-plan capture screen. Same shape as ARMeasurePlugin - native
// only, no web fallback, resolves exactly once via a closure the presented
// screen calls when it's done. A multi-room walkthrough (stop/prompt/scan
// another/finish) all happens inside that one presented screen before the
// single scan() promise ever resolves - see RoomScanViewController.
@objc(RoomPlanPlugin)
public class RoomPlanPlugin: CAPPlugin, CAPBridgedPlugin, QLPreviewControllerDataSource {
    public let identifier = "RoomPlanPlugin"
    public let jsName = "RoomScan"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "scan", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isSupported", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "exportModel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "viewModel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pendientes", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "soltar", returnType: CAPPluginReturnPromise)
    ]

    // Kept only so a later exportModel()/viewModel() call (from the
    // "Exportar modelo 3D"/"Ver en 3D" buttons on the finished plan) has
    // something real to export - the JS side only ever receives plain
    // geometry JSON, never these native objects. `lastStructure` is a
    // CapturedStructure (iOS 17+) stored as Any since this property can't
    // be @available-gated itself.
    private var lastRooms: [CapturedRoom] = []
    private var lastDeletedIndices: Set<Int> = []
    private var lastStructure: Any?
    // (17-oct) La entrega del último escaneo terminado ("" sin ella): "Ver en 3D" de un plano solo enseña ESE escaneo.
    private var lastEntrega = ""
    private var previewURL: URL?
    private var scanInProgress = false

    // First room the tech did NOT voice-delete - the only honest choice
    // for the single-room 3D export/preview fallbacks.
    private var firstKeptRoom: CapturedRoom? {
        for (idx, room) in lastRooms.enumerated() where !lastDeletedIndices.contains(idx) {
            return room
        }
        return nil
    }

    @objc func isSupported(_ call: CAPPluginCall) {
        call.resolve(["value": RoomCaptureSession.isSupported])
    }

    @objc func scan(_ call: CAPPluginCall) {
        guard RoomCaptureSession.isSupported else {
            call.resolve(["cancelled": true, "error": "Este teléfono no tiene LiDAR - no se puede escanear el plano."])
            return
        }
        DispatchQueue.main.async {
            // Reentrancy guard: a double-tap on the scan button used to
            // present a second scanner over the first and leak a promise
            // that could never resolve.
            guard !self.scanInProgress else {
                call.resolve(["cancelled": true])
                return
            }
            guard let presenter = self.bridge?.viewController else {
                call.resolve(["cancelled": true, "error": "No se pudo abrir la cámara."])
                return
            }
            self.scanInProgress = true
            // (17-oct) LA ENTREGA. Con el escáner abierto iOS puede matar el motor web por memoria; Capacitor recarga la
            // página y la respuesta de scan() ya no la espera nadie (se perdía sin aviso). Si la página manda su trabajo y
            // un id de entrega, el escaneo se escribe en el teléfono ANTES de responder y la página lo recoge con
            // pendientes(). Sin los dos (Field Reports, páginas viejas) no se escribe nada: igual que siempre.
            let trabajo = call.getString("trabajo") ?? "", entrega = call.getString("entrega") ?? ""
            // Y el nivel que la página tenía en pantalla al empezar (su id): recogido después, el escaneo va a ese nivel
            // aunque en la bandeja se haya escrito uno que no es del proyecto (igual que si la respuesta hubiera llegado).
            let nivelPedido = call.getString("nivelId") ?? ""
            let vc = RoomScanViewController()
            vc.modalPresentationStyle = .fullScreen
            // La planta donde esta parado, escogida en la pantalla de Escanear.
            // La camara la dice en la barra y en la voz; el plano la guarda para
            // que Medidas sepa que cuartos son de ese piso.
            vc.nivelBase = call.getString("nivelBase") ?? ""
            // Los niveles REALES del proyecto, para la bandeja de la cámara.
            if let lista = call.getArray("niveles", String.self) { vc.nivelesDelProyecto = lista }
            // Los cuartos que el personal ya creó en el proyecto (opcional; sin ellos, como antes).
            if let l = call.getArray("cuartosDelNivel", String.self) { vc.cuartosDelNivel = l }
            if let o = call.getObject("cuartosPorNivel") {
                var m: [String: [String]] = [:]
                for (k, v) in o { if let arr = v as? [Any] { m[k] = arr.compactMap { $0 as? String } } }
                vc.cuartosPorNivel = m
            }
            vc.onFinish = { [weak self, weak vc] outcome in
                self?.scanInProgress = false
                guard let vc = vc else { return }
                vc.dismiss(animated: true) {
                    switch outcome {
                    case .cancelled:
                        call.resolve(["cancelled": true])
                    case .finished(let rooms, let structure, let merged, let levels, let voiceNames, let equipment, let deletedIndices, let inspection, let surfaceAnswers):
                        self?.lastRooms = rooms
                        self?.lastDeletedIndices = deletedIndices
                        self?.lastStructure = structure
                        self?.lastEntrega = entrega
                        var dict = FloorPlanEncoder.encodeStructure(rooms: rooms, merged: merged, levels: levels, voiceNames: voiceNames, equipment: equipment, deletedIndices: deletedIndices, surfaceAnswers: surfaceAnswers)
                        if let inspection = inspection { dict["inspection"] = inspection }
                        // EL PARCHE: lo que se escaneó con "Completar escaneo" se une a su
                        // cuarto (paredes que faltaban, puertas y ventanas nuevas); ya viene
                        // acomodado al plano entregado.
                        if var insp = dict["inspection"] as? [String: Any],
                           let parches = insp["parches"] as? [String: [String: Any]],
                           var cuartos = dict["rooms"] as? [[String: Any]] {
                            for (k, p) in parches {
                                guard let i = Int(k), cuartos.indices.contains(i) else { continue }
                                for clave in ["walls", "doors", "windows", "openings"] {
                                    let extra = p[clave] as? [[String: Any]] ?? []
                                    if !extra.isEmpty { cuartos[i][clave] = ((cuartos[i][clave] as? [[String: Any]]) ?? []) + extra }
                                }
                                cuartos[i]["_completado"] = true
                            }
                            dict["rooms"] = cuartos
                            insp["parches"] = nil
                            insp["parchesUnidos"] = parches.count
                            dict["inspection"] = insp
                        }
                        if let insp = dict["inspection"] as? [String: Any], let inc = insp["incompleteRooms"] as? [Int],
                           var cuartos = dict["rooms"] as? [[String: Any]] {
                            for i in inc where cuartos.indices.contains(i) { cuartos[i]["incomplete"] = true }
                            dict["rooms"] = cuartos
                        }
                        // El nivel que escogió en la bandeja (puede no ser el que mandó la web).
                        if !vc.nivelBase.isEmpty { dict["nivelBase"] = vc.nivelBase }
                        // Primero al teléfono, después a la página (si el archivo no se puede escribir, se responde igual).
                        // La página recibe EL MISMO escaneo limpio que quedó en el archivo: con un NaN, Capacitor no puede
                        // mandar la respuesta cruda y la página recibía {}.
                        if !trabajo.isEmpty && !entrega.isEmpty {
                            dict = PlanosSinEntregar.entregar(trabajo: trabajo, entrega: entrega, nivelPedido: nivelPedido, escaneo: dict)
                            // Y se avisa: una página recargada con el escáner abierto ya no espera esta respuesta, pero sí oye el
                            // aviso (Floor Plan guarda la copia, o Home dice de qué proyecto quedó). Se queda guardado si nadie oye.
                            self?.notifyListeners("escaneoEnTelefono", data: ["trabajo": trabajo, "entrega": entrega], retainUntilConsumed: true)
                        }
                        call.resolve(dict)
                    }
                }
            }
            presenter.present(vc, animated: true)
        }
    }

    // (17-oct) Los escaneos de este trabajo que la página todavía no tiene a salvo, y soltarlos cuando ya los tiene.
    // Sin trabajo: qué proyectos tienen alguno (para el aviso de Home), sin abrir los archivos.
    @objc func pendientes(_ call: CAPPluginCall) {
        let t = call.getString("trabajo") ?? ""
        if t.isEmpty { call.resolve(["escaneos": [], "trabajos": PlanosSinEntregar.resumen()]); return }
        call.resolve(["escaneos": PlanosSinEntregar.leer(trabajo: t)])
    }
    @objc func soltar(_ call: CAPPluginCall) {
        let t = call.getString("trabajo") ?? ""
        for e in (call.getArray("ids") as? [String]) ?? [] { PlanosSinEntregar.borrar(trabajo: t, entrega: e) }
        call.resolve()
    }

    @objc func exportModel(_ call: CAPPluginCall) {
        // Real, native, free capability - RoomPlan's own CapturedRoom and
        // CapturedStructure both expose a USDZ export method. Reads the
        // written file straight back as base64 and resolves with that
        // (rather than a native file path) so the web layer can reuse its
        // existing saveAndShareNative() blob-based share pipeline exactly
        // as-is, with no new cross-plugin filesystem-path handling needed.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plano-\(UUID().uuidString).usdz")
        do {
            if #available(iOS 17.0, *), let structure = lastStructure as? CapturedStructure {
                try structure.export(to: url)
            } else if let room = firstKeptRoom {
                try room.export(to: url)
            } else {
                call.resolve(["error": "No hay ningún plano escaneado todavía para exportar."])
                return
            }
            let data = try Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)
            call.resolve(["base64": data.base64EncodedString()])
        } catch {
            call.resolve(["error": "No se pudo exportar el modelo 3D: \(error.localizedDescription)"])
        }
    }

    // In-app 3D view via Apple's own QLPreviewController (Quick Look) -
    // real, standard, native rotate/pan/zoom on the same USDZ file
    // exportModel() produces, plus Quick Look's own built-in AR button to
    // place it in the room. No custom SceneKit/RealityKit renderer needed;
    // this is what Files/Mail/Messages already use to preview a USDZ.
    @objc func viewModel(_ call: CAPPluginCall) {
        guard let presenter = self.bridge?.viewController else {
            call.resolve(["error": "No se pudo abrir la vista 3D."])
            return
        }
        // (17-oct) La página dice de qué escaneo es el plano en pantalla: si no es el último de este teléfono, no se
        // enseña otro (antes salía en AR un escaneo que nunca se guardó). Sin "entrega" (Field Reports), como siempre.
        if let pedida = call.getString("entrega"), !pedida.isEmpty, pedida.lowercased() != lastEntrega.lowercased() {
            call.resolve(["error": "The 3D model of this plan is not on this phone."])
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("plano-preview.usdz")
        do {
            if #available(iOS 17.0, *), let structure = lastStructure as? CapturedStructure {
                try structure.export(to: url)
            } else if let room = firstKeptRoom {
                try room.export(to: url)
            } else {
                call.resolve(["error": "No hay ningún plano escaneado todavía."])
                return
            }
        } catch {
            call.resolve(["error": "No se pudo generar el modelo 3D: \(error.localizedDescription)"])
            return
        }
        previewURL = url
        DispatchQueue.main.async {
            let ql = QLPreviewController()
            ql.dataSource = self
            presenter.present(ql, animated: true) {
                call.resolve([:])
            }
        }
    }

    public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return previewURL == nil ? 0 : 1
    }
    public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return (previewURL! as NSURL)
    }
}

// (17-oct) EL ESCANEO QUE LA PÁGINA NO RECIBIÓ (su escaneo 2 del 17-oct: la página se recargó con el escáner abierto y el
// plano se perdió sin aviso). Antes de responder, el escaneo terminado se escribe aquí; la página lo suelta en cuanto lo
// tiene a salvo (en su lista del teléfono o en el servidor) y, si nunca le llegó, lo recoge al abrir ese proyecto (Home
// avisa cuál). Un archivo por escaneo: planos-sin-entregar/<trabajo>/<entrega>.json. Un archivo que sigue aquí es un
// escaneo que NO está guardado en ningún lado (leerlo no lo guarda: lo guarda soltarlo), así que solo se va solo por su edad:
// 180 días después de escaneado, se haya leído o no.
enum PlanosSinEntregar {
    static var base: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first   // var: las pruebas la cambian
    static let diasMaximo: Double = 180     // desde que se escaneó (se escribió el archivo)
    static let raiz = "planos-sin-entregar"
    // Solo letras, números y guiones (un id raro nunca sale de su carpeta).
    static func limpio(_ s: String) -> String {
        String(s.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }.prefix(100)).lowercased()
    }
    static func carpeta(_ trabajo: String) -> URL? {
        let t = limpio(trabajo)
        guard !t.isEmpty, let b = base else { return nil }
        return b.appendingPathComponent(raiz, isDirectory: true).appendingPathComponent(t, isDirectory: true)
    }
    static func archivo(trabajo: String, entrega: String) -> URL? {
        let e = limpio(entrega)
        guard !e.isEmpty, let dir = carpeta(trabajo) else { return nil }
        return dir.appendingPathComponent(e + ".json")
    }
    static func fecha(_ u: URL) -> Date? { (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
    // Lo que JSONSerialization no sabe escribir: NaN o infinito -> null, una fecha -> su texto, otro tipo -> se quita
    // (en una lista queda null, para no correr los índices). Con eso no tira un error: lanza una excepción que cierra la app.
    static func seguro(_ v: Any) -> Any? {
        switch v {
        case is NSNull, is String: return v
        case let d as Date: return ISO8601DateFormatter().string(from: d)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n }
            return n.doubleValue.isFinite ? n : NSNull()
        case let o as [String: Any]:
            var r: [String: Any] = [:]
            for (k, x) in o { if let y = seguro(x) { r[k] = y } }
            return r
        case let a as [Any]: return a.map { seguro($0) ?? NSNull() }
        default: return nil
        }
    }
    // Lo que se le entrega a la página: el escaneo con su entrega, la hora del escaneo y el nivel que se pidió, LIMPIO,
    // escrito primero al teléfono. La página recibe este mismo diccionario (nunca el crudo).
    static func entregar(trabajo: String, entrega: String, nivelPedido: String, escaneo: [String: Any], ahora: Date = Date()) -> [String: Any] {
        var d = escaneo
        d["_entrega"] = entrega
        d["_escaneado"] = ISO8601DateFormatter().string(from: ahora)
        if !nivelPedido.isEmpty { d["_nivelPedido"] = nivelPedido }
        let listo = (seguro(d) as? [String: Any]) ?? d
        escribir(trabajo: trabajo, entrega: entrega, escaneo: listo)
        return listo
    }
    @discardableResult
    static func escribir(trabajo: String, entrega: String, escaneo: [String: Any]) -> Bool {
        guard let url = archivo(trabajo: trabajo, entrega: entrega) else { return false }
        guard let limpio = seguro(escaneo) as? [String: Any], JSONSerialization.isValidJSONObject(limpio) else {
            NSLog("PlanosSinEntregar: el escaneo no se puede escribir como JSON"); return false
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let datos = try JSONSerialization.data(withJSONObject: limpio)
            try datos.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { NSLog("PlanosSinEntregar: no se pudo escribir \(error)"); return false }
    }
    // Los de este trabajo, del más viejo al más nuevo (así se guardan en el orden en que se escanearon). Leer no cambia nada.
    static func leer(trabajo: String) -> [[String: Any]] {
        limpiarViejos()
        guard let dir = carpeta(trabajo),
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        let f = { (u: URL) -> Date in fecha(u) ?? .distantPast }
        return urls.filter { $0.pathExtension == "json" }
            .sorted { (f($0), $0.lastPathComponent) < (f($1), $1.lastPathComponent) }
            .compactMap { u in
                guard let d = try? Data(contentsOf: u),
                      let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                      let e = o["_entrega"] as? String, !e.isEmpty else { return nil }
                return o
            }
    }
    // Qué trabajos tienen escaneos sin entregar: [{trabajo, n, desde}] (desde = el más viejo). No abre los archivos.
    static func resumen() -> [[String: Any]] {
        limpiarViejos()
        guard let b = base else { return [] }
        let fm = FileManager.default, iso = ISO8601DateFormatter()
        var out: [[String: Any]] = []
        for t in (try? fm.contentsOfDirectory(at: b.appendingPathComponent(raiz, isDirectory: true), includingPropertiesForKeys: nil)) ?? [] {
            let js = ((try? fm.contentsOfDirectory(at: t, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []).filter { $0.pathExtension == "json" }
            if js.isEmpty { continue }
            let desde = js.compactMap { fecha($0) }.min() ?? Date()
            out.append(["trabajo": t.lastPathComponent, "n": js.count, "desde": iso.string(from: desde)])
        }
        return out.sorted { ($0["desde"] as? String ?? "") < ($1["desde"] as? String ?? "") }
    }
    static func borrar(trabajo: String, entrega: String) {
        guard let url = archivo(trabajo: trabajo, entrega: entrega) else { return }
        try? FileManager.default.removeItem(at: url)
        let dir = url.deletingLastPathComponent()
        if ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).isEmpty { try? FileManager.default.removeItem(at: dir) }
    }
    // En todos los trabajos: lo escaneado hace más de 180 días. Solo cuando la página pregunta (leer, resumen), nunca al
    // escribir un escaneo nuevo. Las marcas .visto de una prueba anterior se quitan (ya no se usan).
    static func limpiarViejos(ahora: Date = Date()) {
        guard let b = base else { return }
        let fm = FileManager.default
        let viejo = ahora.addingTimeInterval(-diasMaximo * 86400)
        for t in (try? fm.contentsOfDirectory(at: b.appendingPathComponent(raiz, isDirectory: true), includingPropertiesForKeys: nil)) ?? [] {
            for a in (try? fm.contentsOfDirectory(at: t, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                if a.pathExtension == "json" { if let f = fecha(a), f < viejo { try? fm.removeItem(at: a) } }
                else if a.pathExtension == "visto" { try? fm.removeItem(at: a) }
            }
            if ((try? fm.contentsOfDirectory(atPath: t.path)) ?? []).isEmpty { try? fm.removeItem(at: t) }
        }
    }
}
