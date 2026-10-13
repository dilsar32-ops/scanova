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
        CAPPluginMethod(name: "viewModel", returnType: CAPPluginReturnPromise)
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
            let vc = RoomScanViewController()
            vc.modalPresentationStyle = .fullScreen
            // La planta donde esta parado, escogida en la pantalla de Escanear.
            // La camara la dice en la barra y en la voz; el plano la guarda para
            // que Medidas sepa que cuartos son de ese piso.
            vc.nivelBase = call.getString("nivelBase") ?? ""
            // Los niveles REALES del proyecto, para la bandeja de la cámara.
            if let lista = call.getArray("niveles", String.self) { vc.nivelesDelProyecto = lista }
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
                        call.resolve(dict)
                    }
                }
            }
            presenter.present(vc, animated: true)
        }
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
