import Foundation
import Vision
import CoreVideo

// EL ASISTENTE QUE MIRA POR LA CAMARA.
//
// Su pedido: "agentes y bots que ayuden como asistentes al comando y que puedan
// ver por la cámara lo que se va a medir".
//
// ============ LO QUE ESTO SI PUEDE, Y LO QUE NO ============
//
// SI PUEDE: Apple trae un clasificador de imagenes DENTRO del telefono
// (Vision, `VNClassifyImageRequest`). Reconoce mas de mil cosas comunes -
// alfombra, loseta, madera, gabinete, lavadora, refrigerador, inodoro, tina -
// sin descargar nada, sin internet y sin costo. Se le pasa un cuadro de lo que
// la camara esta viendo y contesta que cree que es.
//
// NO PUEDE, y hay que decirlo claro porque es la diferencia entre una
// herramienta y una promesa falsa:
//   - NO distingue laminado de madera de vinil. Los tres son tablas cafes con
//     veta; ni una persona los distingue seguro en una foto. Para eso hay que
//     tocarlos o ver el canto.
//   - NO mide nada. Las medidas salen de ARKit y de las esquinas que el marca.
//   - NO acierta siempre. Es un clasificador general, no de restauracion.
//
// POR ESO ESTO NUNCA ESCOGE: SUGIERE Y EL CONTESTA. Exactamente como el
// escaner de planos, que propone el nombre del cuarto y espera un "sí". Una
// sugerencia equivocada cuesta un "no"; un material escogido solo y equivocado
// cuesta una linea mal facturada que nadie ve hasta que el ajustador la rebota.
enum OjoDeLaCamara {

    struct Vistazo {
        let etiquetas: [(nombre: String, confianza: Float)]
        let material: String?      // del catalogo de ESTA seccion
        let cuarto: String?        // por los muebles que se ven
        let confianza: Float
    }

    // Lo que Vision devuelve -> lo que la app llama a esa cosa.
    //
    // Las llaves son PEDAZOS del nombre que da Vision: su taxonomia usa cosas
    // como "carpet", "floor_tile", "hardwood". Se busca por pedazo para no
    // depender de nombres exactos que Apple puede cambiar entre versiones de
    // iOS - si cambian, esto deja de sugerir, que es fallar por el lado bueno.
    private static let aMaterial: [(clave: String, valor: String)] = [
        ("carpet",        "Carpet"),
        ("rug",           "Carpet"),
        ("tile",          "Tile"),
        ("ceramic",       "Tile"),
        ("marble",        "Tile"),
        ("hardwood",      "Hardwood"),
        ("wood_floor",    "Hardwood"),
        ("parquet",       "Hardwood"),
        ("laminate",      "Laminate"),
        ("linoleum",      "Vinyl (LVP)"),
        ("vinyl",         "Vinyl (LVP)"),
        ("plywood",       "Plywood"),
        ("concrete",      "Concrete"),
        ("cement",        "Concrete"),
        ("drywall",       "Drywall"),
        ("plaster",       "Plaster"),
        ("insulation",    "Insulation"),
        // LO MAS ESPECIFICO PRIMERO (18 sep 2026). Estas llaves se buscan por
        // orden y la primera que casa gana: con "molding" arriba, una "crown
        // molding" se clasificaba como ZOCALO. Lo cazo ojo_test.sh.
        ("crown molding", "Crown Molding"),
        ("door trim",     "Trim"),
        ("window trim",   "Trim"),
        ("baseboard",     "Baseboard"),
        // "molding" a secas se queda con el zocalo: es como la cuadrilla llama
        // al rodapie, y es lo que mas se ve en una foto de piso mojado.
        ("molding",       "Baseboard"),
        ("cabinet",       "Cabinets"),
        ("cupboard",      "Cabinets"),
        ("countertop",    "Countertop"),
        ("sink",          "Sink"),
        ("refrigerator",  "Refrigerator"),
        ("stove",         "Stove / Range"),
        ("oven",          "Stove / Range"),
        ("backsplash",    "Backsplash")
    ]

    // Los muebles dicen en que cuarto esta parado mejor que las paredes. Es la
    // misma idea que ya usa el escaner de planos con lo que ve RoomPlan, y ahi
    // funciono: un inodoro quiere decir baño, y no hay vuelta de hoja.
    private static let aCuarto: [(clave: String, valor: String)] = [
        ("toilet",          "Bathroom"),
        ("bathtub",         "Bathroom"),
        ("shower",          "Bathroom"),
        ("bathroom",        "Bathroom"),
        ("washing_machine", "Laundry Room"),
        // "dishwasher" VA ANTES QUE "washer", y no es capricho: se busca por
        // pedazo y gana el primero que case, y "dish-WASHER" trae "washer"
        // adentro. Al reves, un lavaplatos de cocina decia "cuarto de lavado".
        ("dishwasher",      "Kitchen"),
        ("washer",          "Laundry Room"),
        ("dryer",           "Laundry Room"),
        ("refrigerator",    "Kitchen"),
        ("stove",           "Kitchen"),
        ("oven",            "Kitchen"),
        ("kitchen",         "Kitchen"),
        ("bed",             "Bedroom"),
        ("bedroom",         "Bedroom"),
        ("closet",          "Closet"),
        ("sofa",            "Living Room"),
        ("couch",           "Living Room"),
        ("television",      "Living Room"),
        ("staircase",       "Hallway"),
        ("stairs",          "Hallway")
    ]

    // Debajo de esto no se abre la boca. Un clasificador general suelta
    // docenas de etiquetas con confianza minima; decirlas seria ruido, y peor,
    // seria sugerir un material por una corazonada.
    private static let minimo: Float = 0.25

    private static var trabajando = false

    // Mira UN cuadro y contesta que ve.
    //
    // `materiales` son los de la seccion en la que anda: sugerir "gabinetes"
    // mientras mide el piso no ayuda a nadie, aunque de verdad haya un gabinete
    // en la foto.
    static func mirar(_ cuadro: CVPixelBuffer,
                      entre materiales: [String],
                      completion: @escaping (Vistazo?) -> Void) {
        // Uno a la vez. La camara suelta sesenta cuadros por segundo y encimar
        // peticiones de Vision calienta el telefono y atranca el dibujado de
        // ARKit - que es la pantalla que el esta mirando.
        guard !trabajando else { completion(nil); return }
        trabajando = true

        let peticion = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: cuadro, orientation: .right, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            defer { trabajando = false }
            do { try handler.perform([peticion]) }
            catch { DispatchQueue.main.async { completion(nil) }; return }

            guard let obs = peticion.results as? [VNClassificationObservation] else {
                DispatchQueue.main.async { completion(nil) }; return
            }
            let buenas = obs.filter { $0.confidence >= minimo }.prefix(12)
            guard !buenas.isEmpty else { DispatchQueue.main.async { completion(nil) }; return }

            var material: String?
            var confianza: Float = 0
            for o in buenas {
                let id = o.identifier.lowercased()
                guard let par = aMaterial.first(where: { id.contains($0.clave) }) else { continue }
                // Solo si ESA seccion lo tiene: el catalogo manda.
                guard materiales.contains(par.valor) else { continue }
                material = par.valor; confianza = o.confidence
                break
            }
            var cuarto: String?
            for o in buenas {
                let id = o.identifier.lowercased()
                if let par = aCuarto.first(where: { id.contains($0.clave) }) { cuarto = par.valor; break }
            }
            let etiquetas = buenas.map { (nombre: $0.identifier, confianza: $0.confidence) }
            DispatchQueue.main.async {
                completion(Vistazo(etiquetas: Array(etiquetas), material: material,
                                   cuarto: cuarto, confianza: confianza))
            }
        }
    }

    // Como se lo dice en voz alta. Siempre PREGUNTANDO, nunca afirmando: el
    // que sabe que piso es, es el que esta parado encima.
    static func comoLoDice(_ v: Vistazo, etiquetaDe: (String) -> String) -> String? {
        if let m = v.material {
            return "¿Es \(etiquetaDe(m).lowercased())?"
        }
        return nil
    }
}
