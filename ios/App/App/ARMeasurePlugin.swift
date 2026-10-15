import Foundation
import Capacitor
import ARKit

// Bridges the JS side ("Capacitor.Plugins.ARMeasure.measure()") to the
// native camera-measuring screen. No web implementation exists - this only
// ever runs inside the iOS app, never in a plain browser tab.
@objc(ARMeasurePlugin)
public class ARMeasurePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "ARMeasurePlugin"
    public let jsName = "ARMeasure"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "measure", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isSupported", returnType: CAPPluginReturnPromise)
    ]

    @objc func isSupported(_ call: CAPPluginCall) {
        call.resolve(["value": ARWorldTrackingConfiguration.isSupported])
    }

    // The JS side already knows each material's companion (if any) from its
    // own MATERIAL_COMPANION table, and sends it along with every option -
    // this just unpacks that shape, it doesn't decide anything itself.
    private func parseMaterials(_ call: CAPPluginCall) -> [ARMaterialOption] {
        let raw = (call.getArray("materials") as? [[String: Any]]) ?? []
        return raw.compactMap { dict in
            guard let value = dict["value"] as? String, let label = dict["label"] as? String else { return nil }
            let companion = dict["companion"] as? [String: Any]
            return ARMaterialOption(
                value: value,
                label: label,
                companionValue: companion?["value"] as? String,
                companionEn: companion?["labelEn"] as? String,
                companionEs: companion?["labelEs"] as? String,
                // Se cuenta en vez de medirse (27 sep 2026). Lo decide el lado
                // JS con su tabla MEASURE_POR_PIEZA; aqui solo se desempaca.
                porPieza: (dict["porPieza"] as? Bool) ?? false,
                // La unidad de ese material ("SF" | "LF" | "EA"), decidida por la web (15 oct 2026).
                unidad: dict["unidad"] as? String
            )
        }
    }

    @objc func measure(_ call: CAPPluginCall) {
        guard ARWorldTrackingConfiguration.isSupported else {
            call.resolve(["cancelled": true, "error": "Este dispositivo no es compatible con la cámara de medir."])
            return
        }
        let materials = parseMaterials(call)
        DispatchQueue.main.async {
            guard let presenter = self.bridge?.viewController else {
                call.resolve(["cancelled": true, "error": "No se pudo abrir la cámara."])
                return
            }
            // Los colores de la app que la abre (Scanova manda los suyos; sin tema, los de siempre). Antes de crear la
            // pantalla: sus botones toman el color al armarse.
            ARMeasureViewController.tema = TemaCamara(call.getObject("tema"))
            let arVC = ARMeasureViewController()
            arVC.modalPresentationStyle = .fullScreen
            arVC.materials = materials
            // De que tarjeta vino (piso/pared/techo/cocina): el asistente lo
            // necesita para avisar cuando la camara ve una cosa y la medida
            // es de otra.
            arVC.section = call.getString("section") ?? ""
            // Lo que la web ya sabe y la camara necesita para dejar de ser
            // una herramienta ciega: quien la trae, de que cuarto es, y
            // cuanto mide ese cuarto en el plano ya escaneado.
            arVC.crewName = call.getString("crewName") ?? ""
            arVC.roomName = call.getString("roomName") ?? ""
            arVC.roomAreaSqFt = call.getDouble("roomAreaSqFt") ?? 0

            // ---- Modo recorrido: los catalogos completos ----
            // Sin esto la camara no puede cambiar de seccion sola, que es todo
            // el punto: los materiales de las CUATRO secciones, la lista de
            // cuartos, la de niveles, y cuanto mide cada cuarto en el plano.
            arVC.modo = call.getString("modo") ?? "unaSeccion"
            // EL NIVEL YA VIENE RESUELTO DESDE LA PANTALLA. Se escoge con el
            // dedo en Medidas, una sola vez, antes de abrir la camara: adentro
            // ya no se pregunta y se estampa en cada medida del recorrido.
            arVC.alcance = call.getString("alcance") ?? "nivel"
            arVC.nivelActual = call.getString("nivel") ?? ""
            if let secciones = call.getObject("secciones") {
                var mapa: [String: [ARMaterialOption]] = [:]
                for (clave, valor) in secciones {
                    guard let lista = valor as? [[String: Any]] else { continue }
                    mapa[clave] = lista.compactMap { dict in
                        guard let value = dict["value"] as? String,
                              let label = dict["label"] as? String else { return nil }
                        let companion = dict["companion"] as? [String: Any]
                        return ARMaterialOption(value: value, label: label,
                                                companionValue: companion?["value"] as? String,
                                                companionEn: companion?["labelEn"] as? String,
                                                companionEs: companion?["labelEs"] as? String,
                                                porPieza: (dict["porPieza"] as? Bool) ?? false,
                                                unidad: dict["unidad"] as? String)
                    }
                }
                arVC.seccionesDisponibles = mapa
            }
            arVC.cuartosDisponibles = (call.getArray("cuartos") as? [String]) ?? []
            // ---- Los cuartos y las areas DE CADA PLANTA ----
            // Sin esto, `cuartosDisponibles` se fijaba una sola vez al abrir y
            // en un recorrido de varios niveles seguia siendo la del piso
            // anterior: subia al tercero y le ofrecian los cuartos del segundo.
            if let porPlanta = call.getObject("cuartosPorPlanta") {
                var mapa: [String: [String]] = [:]
                for (planta, valor) in porPlanta {
                    if let lista = valor as? [String] { mapa[planta] = lista }
                }
                arVC.cuartosPorPlanta = mapa
            }
            if let areas = call.getObject("areasPorPlanta") {
                var mapa: [String: [String: Double]] = [:]
                for (planta, valor) in areas {
                    guard let dict = valor as? [String: Any] else { continue }
                    var porCuarto: [String: Double] = [:]
                    for (cuarto, a) in dict {
                        if let d = a as? Double { porCuarto[cuarto] = d }
                        else if let n = a as? NSNumber { porCuarto[cuarto] = n.doubleValue }
                    }
                    mapa[planta] = porCuarto
                }
                arVC.areasPorPlanta = mapa
            }
            arVC.nivelesDisponibles = (call.getArray("niveles") as? [String]) ?? []
            if let areas = call.getObject("areasPorCuarto") {
                var mapa: [String: Double] = [:]
                for (clave, valor) in areas {
                    if let d = valor as? Double { mapa[clave] = d }
                    else if let n = valor as? NSNumber { mapa[clave] = n.doubleValue }
                }
                arVC.areasPorCuarto = mapa
            }
            // Resolve exactly once, from whichever button the crew ends up
            // tapping (cancel, length-only, or both measurements) - the
            // dismiss happens here, not inside the view controller, so
            // there is only ever one dismissal path to reason about.
            arVC.onFinish = { [weak arVC] outcome in
                guard let arVC = arVC else { return }
                arVC.dismiss(animated: true) {
                    switch outcome {
                    case .cancelled:
                        call.resolve(["cancelled": true])
                    case .measured(let items):
                        let measurements: [[String: Any]] = items.map { item in
                            var d: [String: Any] = ["length": item.length, "material": item.material,
                                                    "nivel": item.nivel, "cuarto": item.cuarto,
                                                    "seccion": item.seccion]
                            if let width = item.width { d["width"] = width }
                            if let companion = item.companion { d["companion"] = companion }
                            return d
                        }
                        call.resolve(["cancelled": false, "measurements": measurements])
                    }
                }
            }
            presenter.present(arVC, animated: true)
        }
    }
}
