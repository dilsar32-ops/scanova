import Foundation
import Capacitor
#if canImport(FoundationModels)
import FoundationModels
#endif

// EL CEREBRO DEL ASISTENTE: UN MODELO DE IA, NO UNA LISTA DE REGLAS.
//
// Su correccion del 6 oct 2026: "no quiero listas fijas ni reglas como base
// principal. Quiero que un modelo de inteligencia artificial interprete toda
// la conversacion, mantenga contexto y entienda correcciones. Las listas solo
// deben servir para validar".
//
// ---- QUE MODELO, Y POR QUE ESTE ----
// El de Apple, DENTRO DEL TELEFONO (FoundationModels, iOS 26). Se escogio
// sobre mandar el audio a un servicio por tres razones que importan en este
// negocio:
//   * No sale del aparato. En una frase de trabajo van el nombre del cliente y
//     su direccion. Eso no tiene por que viajar a ningun servidor.
//   * No cuesta por uso ni necesita llave. Sus cinco tokens de Matterport ya
//     estan ocupados; esto no agrega otra cuenta que administrar.
//   * Funciona sin senal, que es justo donde trabaja la cuadrilla.
//
// ---- LO QUE HACE QUE LAS CORRECCIONES FUNCIONEN ----
// UNA SOLA `LanguageModelSession` por conversacion. La sesion se acuerda de lo
// que ya se dijo, asi que "no, eran cinco" tiene a que referirse. Si cada
// frase abriera su propia sesion, una correccion no tendria contra que
// corregir - y eso es precisamente lo que el pidio que dejara de pasar.
//
// ---- LO QUE ESTO NO HACE ----
//  * NO escribe en ningun lado. Devuelve lo que entendio y ya. Modo prueba.
//  * NO inventa cantidades: si no se dijo cuantos, manda -1 y la pantalla lo
//    ensena como "¿cuantos?".
//  * NO pregunta por deporte. Solo si de verdad quedo una duda; si no, el
//    campo `pregunta` va vacio.
//  * Si Apple Intelligence esta apagada o el telefono no la soporta, LO DICE
//    con su motivo, para que arriba se pueda caer al parser de reglas y el
//    usuario sepa cual de los dos lo esta oyendo.

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct VozItem {
    @Guide(description: "Las palabras EXACTAS que trae la transcripcion para este articulo, aunque no se entiendan. No las arregles aqui.")
    var nombre: String
    @Guide(description: "El nombre EXACTO de la lista del trabajo al que corresponde. Si no puedes estar seguro de cual es, dejalo VACIO y haz la pregunta. Nunca escojas uno por parecido lejano.")
    var delCatalogo: String
    @Guide(description: "Cuantos. Usa -1 SOLO si la persona no dijo ninguna cantidad. Nunca inventes un numero.")
    var cantidad: Int
    @Guide(description: "puso si los instalo o dejo; quito si los retiro o recogio; sigue si solo esta diciendo que YA ESTABAN ahi (\"todavia quedan dos\", \"ahi siguen\"). Si no se dice nada, puso.")
    var accion: String
    @Guide(description: "alta si no hay duda; media si es probable pero conviene confirmar; baja si de verdad no se sabe.")
    var certeza: String
    @Guide(description: "En una linea, QUE te hizo decidirlo: la palabra que uso, el parecido, o lo que estaba alrededor. Ej: 'dijo plato y dijo debajo de los dehus'.")
    var porque: String
}

@available(iOS 26.0, *)
@Generable
struct VozHabitacion {
    @Guide(description: "Nombre del cuarto como lo dijo la persona. Vacio si no nombro ninguno.")
    var nombre: String
    var items: [VozItem]
}

@available(iOS 26.0, *)
@Generable
struct VozLectura {
    @Guide(description: "Siempre exactamente Equipment. Por ahora no se anota otra cosa.")
    var modulo: String
    @Guide(description: "Una entrada por cada cuarto mencionado. Pueden ser varios en la misma frase.")
    var habitaciones: [VozHabitacion]
    @Guide(description: "SOLO los que la persona haya dicho con todas sus letras. Si no dijo ninguno, deja la lista VACIA. Jamas pongas un campo con un valor de relleno.")
    var datos: [VozDato]
    @Guide(description: "UNA pregunta corta SOLO si quedo una duda real que impida anotar. Si no hay duda, dejalo VACIO.")
    var pregunta: String
    @Guide(description: "Si el dictado oyo mal una palabra y la arreglaste por el contexto, dilo asi: 'ventanas -> Fans'. Una por linea. VACIO si no corregiste nada.")
    var corrigio: String
    @Guide(description: "true SOLO si esta frase CORRIGE algo que ya se habia anotado ('perdon, era en la cocina', 'no, eran cinco'). false si agrega algo nuevo. Importa mucho: una correccion mueve o reemplaza, no suma.")
    var corrige: Bool
}

@available(iOS 26.0, *)
@Generable
struct VozDato {
    @Guide(description: "cliente, direccion, fecha, visita, lider, cuadrilla o causa")
    var campo: String
    @Guide(description: "El valor TAL COMO lo dijo. Tiene que aparecer en la transcripcion. Si no lo dijo, este campo no deberia existir.")
    var valor: String
}
#endif

@objc(CerebroVozPlugin)
public class CerebroVozPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CerebroVozPlugin"
    public let jsName = "CerebroVoz"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "disponible", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "nuevaConversacion", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "interpretar", returnType: CAPPluginReturnPromise)
    ]

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static var sesion: LanguageModelSession?
    #endif
    // CUANTAS FRASES LLEVA ESTA SESION. La memoria del modelo es chica y la
    // conversacion se le va acumulando: a los pocos turnos ya no le cabe nada
    // y empieza a fallar. Se empieza una sesion nueva cada tantas frases - no
    // se pierde nada, porque lo ya anotado se le vuelve a mandar en
    // "llevamos".
    private static var turnos = 0
    private static let TURNOS_ANTES_DE_RENOVAR = 6

    // LAS INSTRUCCIONES. Esto es el programa de verdad: aqui se le dice como
    // oir, no en una lista de palabras.
    // LAS INSTRUCCIONES, CORTAS A PROPOSITO.
    //
    // El modelo que vive DENTRO del telefono es chico y su memoria de trabajo
    // tambien: unas 4 mil palabras contando todo. Yo le estaba mandando 2.400
    // solo de instrucciones y catalogo, mas la conversacion que se acumula
    // turno tras turno - y a los pocos turnos se ahogaba y fallaba. Esa es la
    // razon por la que en el telefono salia "Reglas de respaldo".
    //
    // Asi que esto esta escrito corto a proposito. Cada linea que se agregue
    // aqui le quita sitio a la conversacion, que es lo que de verdad importa.
    private static let instrucciones = """
    Anotas lo que dice un tecnico de restauracion mientras trabaja. Mezcla
    espanol e ingles; es normal. ESTO ES UNA CONVERSACION: el habla varias
    veces, tu preguntas y el contesta.

    QUE EQUIPO ES, en este orden:
    1. Las otras lecturas del mismo audio.
    2. Como lo dice la cuadrilla: el catalogo trae sus formas.
    3. El parecido de sonido. El dictado OYE MAL: una palabra que no existe en
       el oficio pero suena como un equipo del catalogo, es ese equipo.
    4. LO QUE ESTA ALREDEDOR: un tubo del dehumidifier al techo es el ducto;
       un plato debajo es la bandeja. El catalogo trae esas pistas.
    5. Lo ya dicho en esta conversacion.
    El sonido solo no basta: hay palabras normales que suenan a equipo. Si la
    frase no habla de equipo, no inventes equipo. El catalogo define que
    existe. NUNCA conviertas una mala transcripcion en regla: cada frase se
    decide con su propio contexto.

    CUANTA SEGURIDAD TIENES (campo certeza):
    - alta: anotalo y sigue, sin interrumpir.
    - media: anotalo PERO pregunta, escribiendo el NOMBRE DE VERDAD y lo que
      se oyo. Ejemplo de la forma, no del texto: Oi "jepa", ¿es HEPAs?
    - baja: NO lo anotes. delCatalogo vacio y pregunta que fue.
    Preguntar esta bien; adivinar no. No escojas por parecido lejano.

    REGLAS:
    - delCatalogo = un nombre EXACTO del catalogo, o vacio.
    - Si no dijo cuantos, cantidad -1. Nunca inventes un numero.
    - Puede nombrar VARIOS cuartos en una frase: uno por cuarto.
    - "ahi" o "el mismo" = el ultimo cuarto que menciono.
    - El nombre del cuarto es el que EL diga. No lo cambies por uno de
      catalogo.
    - accion: puso / quito / sigue (sigue = ya estaban ahi).
    - Una correccion REEMPLAZA y marca corrige=true. Nunca dos renglones del
      mismo equipo en el mismo cuarto. Eso incluye corregir el CUARTO: ahi el
      equipo se mueve, no aparece en los dos.
    - Si la frase RESPONDE a tu pregunta anterior, aplicala a lo que
      preguntaste.
    - Lo ya anotado no se repite: manda solo lo que esta frase agrega.
    - Si todo quedo claro, pregunta VACIA. No preguntes por cortesia.
    - Solo se anota EQUIPO. modulo siempre "Equipment".
    - datos vacio salvo que lo haya dicho con todas sus letras.
    """

    @objc func disponible(_ call: CAPPluginCall) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                call.resolve(["ok": true, "motivo": ""])
            case .unavailable(let razon):
                let m: String
                switch razon {
                case .deviceNotEligible:          m = "este_telefono_no"
                case .appleIntelligenceNotEnabled: m = "apple_intelligence_apagada"
                case .modelNotReady:               m = "modelo_bajando"
                @unknown default:                  m = "no_disponible"
                }
                call.resolve(["ok": false, "motivo": m])
            }
            return
        }
        #endif
        call.resolve(["ok": false, "motivo": "ios_viejo"])
    }

    @objc func nuevaConversacion(_ call: CAPPluginCall) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { CerebroVozPlugin.sesion = nil }
        #endif
        call.resolve(["ok": true])
    }

    @objc func interpretar(_ call: CAPPluginCall) {
        let texto = call.getString("texto") ?? ""
        guard !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            call.reject("Nada que interpretar.", "vacio"); return
        }
        // Los cuartos REALES del trabajo abierto, si los hay. No son una reja:
        // son una pista, porque el puede nombrar uno que el plano no tiene.
        let cuartos = (call.getArray("cuartos") as? [String]) ?? []
        // LA INCERTIDUMBRE DEL DICTADO, tal como la mando el reconocedor.
        // No se limpia aqui: se le pasa al modelo para que RESUELVA con el
        // contexto, que es la estrategia general que el pidio en vez de
        // parchar palabras una por una.
        let otras = (call.getArray("otras") as? [String]) ?? []
        // EL CATALOGO REAL DEL TRABAJO. Es la lista contra la que tiene que
        // caer cada articulo; si no cae en ninguna, se pregunta.
        let catalogo = (call.getArray("catalogo") as? [String]) ?? []
        // Lo que este trabajador ya confirmo en otras frases. Sube la
        // confianza PARA EL; nunca se vuelve regla para toda la cuadrilla.
        let aprendido = (call.getArray("aprendido") as? [String]) ?? []
        // LO QUE YA SE LLEVA ANOTADO en esta conversacion. Sin esto el modelo
        // repetiria lo mismo o se contradiria de una frase a otra.
        let llevamos = (call.getArray("llevamos") as? [String]) ?? []
        // A QUE SUENA lo que se oyo, medido contra el catalogo. No es una
        // tabla de equivalencias: es cuanto se parece AL OIDO, con las reglas
        // del espanol. Es la misma pista que usa una persona cuando oye mal
        // una palabra pero reconoce el sonido.
        let suenaA = (call.getArray("suenaA") as? [String]) ?? []
        let dudosos = (call.getArray("dudosos") as? [[String: Any]]) ?? []

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                call.reject("El modelo del telefono no esta disponible.", "sin_modelo"); return
            }
            // UNA sesion para toda la conversacion: es lo que deja que
            // "no, eran cinco" tenga a que referirse.
            let s: LanguageModelSession
            if CerebroVozPlugin.turnos >= CerebroVozPlugin.TURNOS_ANTES_DE_RENOVAR {
                CerebroVozPlugin.sesion = nil
                CerebroVozPlugin.turnos = 0
                NSLog("[Cerebro] sesion renovada para que quepa la conversacion")
            }
            if let ya = CerebroVozPlugin.sesion { s = ya }
            else {
                s = LanguageModelSession(instructions: CerebroVozPlugin.instrucciones)
                CerebroVozPlugin.sesion = s
            }
            CerebroVozPlugin.turnos += 1
            var pista = cuartos.isEmpty ? ""
                : "\n\nCuartos que tiene este trabajo (usalos si encajan, pero si nombra otro, respeta el que dijo): " + cuartos.joined(separator: ", ")
            if !catalogo.isEmpty {
                pista += "\n\nCATALOGO DEL TRABAJO. delCatalogo tiene que ser uno de estos nombres, exacto, o vacio:\n" + catalogo.joined(separator: "\n")
            }
            if !suenaA.isEmpty {
                pista += "\n\nPARECIDO DE SONIDO con el catalogo (pista, no verdad):\n- " + suenaA.joined(separator: "\n- ")
            }
            if !llevamos.isEmpty {
                pista += "\n\nYA SE LLEVA ANOTADO en esta conversacion:\n- " + llevamos.joined(separator: "\n- ")
                pista += "\nNO lo repitas. Manda SOLO lo que esta frase agrega o corrige."
            }
            if !aprendido.isEmpty {
                // Lo que ESTE trabajador ya confirmo antes. Sube la confianza
                // para el, no crea una regla para todos.
                pista += "\n\nESTE TRABAJADOR YA CONFIRMO ANTES (vale para el, no es una regla general):\n- " + aprendido.joined(separator: "\n- ")
            }
            if !otras.isEmpty {
                pista += "\n\nOTRAS LECTURAS del mismo audio (una viene del oido en ingles):\n- " + otras.joined(separator: "\n- ")
            }
            if !dudosos.isEmpty {
                let lineas: [String] = dudosos.compactMap { d in
                    guard let w = d["palabra"] as? String, !w.isEmpty else { return nil }
                    let par = (d["parecidas"] as? [String]) ?? []
                    return par.isEmpty ? "\"\(w)\"" : "\"\(w)\" (tambien pudo ser: " + par.joined(separator: ", ") + ")"
                }
                if !lineas.isEmpty {
                    pista += "\n\nPALABRAS DUDOSAS: " + lineas.joined(separator: "; ")
                }
            }
            Task {
                do {
                    let r = try await s.respond(to: texto + pista, generating: VozLectura.self)
                    let v = r.content
                    call.resolve([
                        "ok": true,
                        "porIA": true,
                        "modulo": v.modulo,
                        "pregunta": v.pregunta,
                        "corrigio": v.corrigio,
                        "corrige": v.corrige,
                        "datos": v.datos.map { ["campo": $0.campo, "valor": $0.valor] },
                        "habitaciones": v.habitaciones.map { h in
                            ["nombre": h.nombre,
                             "items": h.items.map { ["nombre": $0.nombre, "delCatalogo": $0.delCatalogo,
                                                     "cantidad": $0.cantidad, "accion": $0.accion,
                                                     "certeza": $0.certeza, "porque": $0.porque] }]
                        }
                    ])
                } catch {
                    // La sesion pudo quedar en mal estado; la siguiente frase
                    // empieza limpia en vez de arrastrar el error.
                    CerebroVozPlugin.sesion = nil
                    CerebroVozPlugin.turnos = 0
                    // Y SE DICE QUE PASO. Tragarse esto fue lo que me tuvo
                    // adivinando: en el telefono solo salia "Reglas de
                    // respaldo", sin motivo.
                    NSLog("[Cerebro] fallo: %@", String(describing: error))
                    call.reject("El modelo no pudo con eso: \(error.localizedDescription)", "modelo")
                }
            }
            return
        }
        #endif
        call.reject("Este telefono no trae el modelo.", "sin_modelo")
    }
}
