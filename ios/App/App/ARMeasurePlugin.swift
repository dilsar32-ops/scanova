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
            // La bandera de la cámara nueva (Fase 0): sin ella, la cámara de siempre.
            arVC.experiencia = call.getString("experiencia") ?? "hoy"
            // "Probar lo demolido" (laboratorio): solo si la página lo manda (solo para el manager). Sin ella no existe.
            arVC.laboratorio = call.getBool("laboratorio") ?? false
            // La parte sale del movimiento del teléfono + qué pared es según el plano (16 oct): solo si la página lo manda.
            arVC.porMovimiento = call.getBool("porMovimiento") ?? false
            // De qué trabajo es: lo que contesta del nivel al empezar se guarda por trabajo y nivel.
            arVC.trabajoId = call.getString("trabajo") ?? ""
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
            // Las paredes del plano por cuarto (largo y si es de afuera): la tarjeta de guardar sugiere la insulación.
            if let paredes = call.getObject("paredesPorCuarto") {
                var mapa: [String: [(largo: Double, exterior: Bool)]] = [:]
                for (cuarto, valor) in paredes {
                    guard let lista = valor as? [[String: Any]] else { continue }
                    mapa[cuarto] = lista.compactMap { d in
                        let largo = (d["largo"] as? Double) ?? (d["largo"] as? NSNumber)?.doubleValue
                        guard let l = largo, l > 0 else { return nil }
                        return (largo: l, exterior: (d["exterior"] as? Bool) ?? false)
                    }
                }
                arVC.paredesPorCuarto = mapa
            }
            // La forma de cada cuarto (paredes con sus puntas, ventanas y puertas): para ubicarse dentro del plano.
            if let formas = call.getObject("planoPorCuarto") {
                func num(_ x: Any?) -> Double? { (x as? Double) ?? (x as? NSNumber)?.doubleValue }
                var mapa: [String: (paredes: [UbicadorEnPlano.ParedPlano], senas: [UbicadorEnPlano.SenaPlano])] = [:]
                var marcos: [String: Int] = [:]
                for (cuarto, valor) in formas {
                    guard let f = valor as? [String: Any] else { continue }
                    if let m = num(f["marco"]) { marcos[cuarto] = Int(m) }
                    let paredes: [UbicadorEnPlano.ParedPlano] = ((f["paredes"] as? [[Any]]) ?? []).compactMap { w in
                        guard w.count >= 5, let x1 = num(w[0]), let y1 = num(w[1]), let x2 = num(w[2]), let y2 = num(w[3]) else { return nil }
                        return UbicadorEnPlano.ParedPlano(seg: UbicadorEnPlano.Segmento(a: SIMD2(x1, y1), b: SIMD2(x2, y2)), exterior: (num(w[4]) ?? 0) > 0.5,
                                                          alto: w.count >= 6 ? (num(w[5]) ?? 0) : 0)
                    }
                    let senas: [UbicadorEnPlano.SenaPlano] = ((f["senas"] as? [[Any]]) ?? []).compactMap { x in
                        guard x.count >= 3, let px = num(x[0]), let py = num(x[1]) else { return nil }
                        return UbicadorEnPlano.SenaPlano(p: SIMD2(px, py), esVentana: (num(x[2]) ?? 0) > 0.5, ancho: x.count >= 4 ? (num(x[3]) ?? 0) : 0,
                                                         abajo: x.count >= 5 ? (num(x[4]) ?? -1) : -1, alto: x.count >= 6 ? (num(x[5]) ?? 0) : 0)
                    }
                    if paredes.count >= 3 { mapa[cuarto] = (paredes, senas) }
                }
                arVC.planoPorCuarto = mapa
                arVC.marcoPorCuarto = marcos
            }
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
            // La bitácora del laboratorio (16 oct): cada lote va a la página como evento "bitacora" (ella lo sube).
            arVC.onBitacora = { [weak self] lote in self?.notifyListeners("bitacora", data: lote) }
            arVC.onFinish = { [weak arVC] outcome in
                guard let arVC = arVC else { return }
                arVC.dismiss(animated: true) {
                    switch outcome {
                    case .cancelled:
                        call.resolve(["cancelled": true])
                    case .measured(let items):
                        call.resolve(["cancelled": false, "measurements": Self.comoDiccionarios(items)])
                    case .fallo(let items, let porque):
                        // La cámara se cayó: lo guardado se entrega igual, con el porqué en "aviso".
                        // Sin medidas, es un cancelado con su "error" (la web ya sabe enseñarlo).
                        if items.isEmpty {
                            call.resolve(["cancelled": true, "error": porque])
                        } else {
                            call.resolve(["cancelled": false, "measurements": Self.comoDiccionarios(items), "aviso": porque])
                        }
                    }
                }
            }
            presenter.present(arVC, animated: true)
        }
    }

    static func comoDiccionarios(_ items: [ARMeasureItem]) -> [[String: Any]] {
        items.map { item in
            var d: [String: Any] = ["length": item.length, "material": item.material,
                                    "nivel": item.nivel, "cuarto": item.cuarto,
                                    "seccion": item.seccion]
            if let width = item.width { d["width"] = width }
            if let companion = item.companion { d["companion"] = companion }
            // La pared entera (16 oct): lo que se resta de puertas y ventanas, y qué fue. Las páginas viejas no lo leen.
            if item.menos > 0 { d["menos"] = item.menos; d["menosQue"] = item.menosQue }
            return d
        }
    }

#if targetEnvironment(simulator)
    // MODO MAQUETA (Fase 2 de la cámara nueva, 15 oct 2026). ARKit no corre en el simulador, así que para enseñar la
    // pantalla nueva antes de construir lo siguiente se abre sola sobre una foto, con datos de ejemplo:
    //   xcrun simctl launch booted <app> -maquetaCamara 4
    // Solo existe en el simulador: en un teléfono este bloque ni se compila.
    override public func load() {
        let paso = UserDefaults.standard.integer(forKey: "maquetaCamara")
        guard paso > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.abrirMaqueta(paso) }
    }
    private func abrirMaqueta(_ paso: Int) {
        guard let presenter = bridge?.viewController else { return }
        ARMeasureViewController.tema = TemaCamara(["escogido": "#2563EBF2", "pastilla": "#0F1A2EBD", "tarjeta": "#151E2E",
                                                   "neutro": "#243046", "primario": "#2563EBF2", "listo": "#1D4ED8F2", "fondo": "#0D1420"])
        func op(_ v: String, _ l: String, _ u: String, comp: (String, String)? = nil) -> ARMaterialOption {
            ARMaterialOption(value: v, label: l, companionValue: comp?.0, companionEn: comp?.0, companionEs: comp?.1,
                             porPieza: u == "EA", unidad: u)
        }
        let secciones: [String: [ARMaterialOption]] = [
            "wall": [op("Drywall", "Drywall / Tablaroca", "SF", comp: ("Insulation", "Insulación")), op("Plaster", "Plaster / Yeso", "SF"),
                     op("Stud / Framing", "Stud / Framing / Armazón", "SF"), op("Insulation", "Insulación / Insulation", "SF"),
                     op("Baseboard", "Baseboard / Zócalo", "LF", comp: ("Shoe Molding", "Moldura de zapata")), op("Shoe Molding", "Shoe Molding / Moldura de Zapata", "LF"),
                     op("Trim", "Trim / Marco", "LF"), op("Crown Molding", "Crown Molding / Moldura de Corona", "LF")],
            "floor": [op("Laminate", "Laminate / Laminado", "SF", comp: ("Underlayment", "Base")), op("Tile", "Tile / Baldosa", "SF"),
                      op("Hardwood", "Hardwood / Madera", "SF"), op("Carpet", "Carpet / Alfombra", "SF", comp: ("Carpet Pad", "Almohadilla")),
                      op("Tackless Strip", "Tackless Strip / Tira de clavos", "LF")],
            "ceiling": [op("Drywall", "Drywall / Tablaroca", "SF", comp: ("Insulation", "Insulación")), op("Plaster", "Plaster / Yeso", "SF")],
            "kitchen": [op("Cabinets", "Cabinets / Gabinetes", "LF"), op("Countertop", "Countertop / Cubierta", "SF"),
                        op("Toe Kick", "Toe Kick / Zócalo de gabinete", "LF"), op("Dishwasher", "Dishwasher / Lavaplatos", "EA")],
            "bathroom": [op("Shower Tile", "Shower Tile / Azulejo de regadera", "SF"), op("Vanity", "Vanity / Mueble del lavabo", "LF"),
                         op("Toilet", "Toilet / Inodoro", "EA")],
            "materiales": [op("6 mil containment plastic", "Plástico de contención / 6 mil plastic", "SF")]
        ]
        let arVC = ARMeasureViewController()
        arVC.modalPresentationStyle = .fullScreen
        arVC.experiencia = "nueva"
        arVC.maqueta = paso
        arVC.laboratorio = (11...13).contains(paso) || (18...23).contains(paso)
        // 24-37: medir primero, el material al final (16 oct).
        arVC.porMovimiento = (24...42).contains(paso)
        arVC.modo = "recorrido"
        arVC.alcance = "nivel"
        arVC.nivelActual = "2nd Floor"
        arVC.nivelesDisponibles = ["1st Floor", "2nd Floor"]
        arVC.crewName = "Juan"
        arVC.section = "floor"
        arVC.seccionesDisponibles = secciones
        arVC.materials = secciones["floor"] ?? []
        let cuartos = ["Living Room", "Kitchen", "Hallway", "Master Bedroom", "Bathroom", "Laundry Room"]
        arVC.cuartosDisponibles = cuartos
        arVC.cuartosPorPlanta = ["2nd Floor": cuartos]
        arVC.onFinish = { [weak arVC] _ in arVC?.dismiss(animated: true) }
        presenter.present(arVC, animated: false)
    }
#endif
}
