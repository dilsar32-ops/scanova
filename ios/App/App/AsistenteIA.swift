import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// EL CEREBRO DEL ASISTENTE, cuando el telefono lo trae.
//
// Su pedido: "insértale asistentes al comando de voz para que pueda entender y
// tener conversaciones fluidas".
//
// QUE ES ESTO DE VERDAD: el modelo de lenguaje que Apple trae DENTRO del
// iPhone (Foundation Models, iOS 26). Corre en el telefono, no en internet.
// Eso importa aqui mas que en ninguna otra app:
//   - Una casa inundada muchas veces no tiene señal.
//   - No cuesta por uso. Un servicio de nube cobraria cada frase, todo el dia,
//     por cada tecnico.
//   - Lo que se dice en casa de un cliente no sale del telefono.
//
// COMO ENTRA, Y ESTO ES LO IMPORTANTE: NO reemplaza las ordenes de siempre.
// Las ordenes cerradas y la tabla de patrones siguen primero porque son
// INSTANTANEAS y no fallan. El modelo entra SOLO cuando esas no entendieron -
// que es justo donde antes contestaba "no le entendí" y lo dejaba parado.
//
// Y NUNCA EJECUTA NADA POR SU CUENTA: devuelve una intencion, y esa intencion
// pasa por los MISMOS candados que un boton (que el boton se vea, que la etapa
// sea la correcta). El modelo puede equivocarse; los candados no lo dejan
// equivocarse caro. JAMAS INVENTA UN NUMERO: no hay ninguna intencion que
// pueda tocar una medida, y eso es a proposito y no se cambia. Los numeros los
// lee `piesDichos`, que es determinista y esta probado frase por frase.
//
// SI EL TELEFONO NO LO TRAE (iOS viejo, Apple Intelligence apagado, modelo sin
// descargar), TODO sigue funcionando exactamente como hoy. Esto suma, no
// sustituye.
enum AsistenteIA {

    // Lo que el modelo puede pedir que se haga. Es una lista CERRADA a
    // proposito: el modelo escoge de aqui, no inventa acciones.
    //
    // `CaseIterable` NO ES ADORNO: esta lista se le manda al modelo escrita en
    // el prompt, y antes estaba tecleada a mano en DOS lugares. Dos copias de
    // la misma lista es una lista que se va a separar - se agrega una intencion
    // al enum, se olvida el texto, y el modelo nunca se entera de que existe.
    // Ahora el texto se arma del enum y no pueden discrepar.
    enum Intencion: String, CaseIterable {
        case marcar, terminarRecorrido, medirAncho, guardar, terminar
        case deshacer, cancelar, ayuda, dondeVoy, silencio
        case cuantoLlevo, queMaterial, cambiarMaterial, abrirLista
        case escogerMaterial     // viene con `valor`
        // ---- El recorrido: medir la casa sin salir de la camara ----
        case otroCuarto          // "ya acabamos aqui"
        case escogerCuarto       // viene con `valor`: el nombre del cuarto
        case escogerSeccion      // viene con `valor`: piso / pared / techo / cocina
        case escogerNivel        // viene con `valor`: el nivel
        // ---- Lo demas que ya se puede hacer hablando ----
        case otraIgual, ponerCompanero, quitarCompanero
        case esperame, yaEstoy, queComandos
        case si, no              // contestar la pregunta abierta
        case responder           // solo hablar: el pregunto o platico
        case nada
    }

    struct Resultado {
        let intencion: Intencion
        let valor: String?
        let respuesta: String?
    }

    // ¿Este telefono puede? Se pregunta cada vez: el usuario puede prender o
    // apagar Apple Intelligence en cualquier momento.
    static var disponible: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    // Por que NO esta disponible, en palabras que el entienda. Se le dice una
    // vez, no se esconde: si compro un telefono que lo trae y esta apagado,
    // tiene derecho a saber que le falta un interruptor.
    static var porQueNo: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(let razon):
                switch razon {
                case .appleIntelligenceNotEnabled:
                    return "Para que el asistente entienda frases libres, prenda Apple Intelligence en Ajustes."
                case .modelNotReady:
                    return "El asistente todavía está descargando su modelo. Inténtelo en un rato."
                case .deviceNotEligible:
                    return nil   // este telefono no puede: no tiene caso repetirselo
                @unknown default:
                    return nil
                }
            }
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static var sesion: LanguageModelSession?

    // EL OFICIO, METIDO EN SU CABEZA.
    //
    // Esto es lo que reemplaza a "que busque en internet". Un modelo generico
    // no sabe que un zocalo se cobra por pie LINEAL y una pared por pie
    // CUADRADO, ni que la tablaroca lleva insulacion detras, ni que cuando el
    // dice "carpeta" quiere decir alfombra. Sin esto contesta como folleto; con
    // esto contesta como alguien que ha estado en una casa inundada.
    //
    // Y NO LLEVA LA SECCION ADENTRO, a proposito. Antes si, y por eso habia que
    // tirar la sesion cada vez que cambiaba de seccion - o sea, cada pocos
    // minutos en un recorrido - y con la sesion se iba la CONVERSACION entera.
    // Le preguntaba algo, cambiaba a pared, y el modelo ya no se acordaba de
    // nada. La seccion ahora viaja en el estado, que se manda en cada turno, y
    // la sesion vive todo el recorrido.
    @available(iOS 26.0, *)
    private static let instrucciones = """
    Eres el asistente de voz de una cuadrilla de restauración por daños de agua. \
    El técnico está midiendo una casa con la cámara del teléfono, con las dos \
    manos ocupadas, a veces parado en agua. Habla español mexicano y mezcla \
    palabras en inglés: "drywall", "baseboard", "carpet", "trim".

    EL OFICIO, para que entiendas de qué te habla:
    - Se mide en seis secciones: PISO, PARED, TECHO, COCINA, BAÑO y MATERIALES (el plástico o \
      nailo para cubrir, el plástico de 6 mil de contención y la protección de piso: se cobran \
      por pie cuadrado). Cocina y Baño tienen su propia pastilla, igual que Piso, Pared y Techo: \
      se escogen a mano y no dependen de cómo se llame el cuarto.
    - Piso: laminado, loseta, madera, vinil (LVP), alfombra, plywood, subpiso, concreto.
    - Pared y techo: tablaroca (drywall), yeso, marcos (studs), insulación, zócalo (baseboard).
    - Cocina: gabinetes, cubierta (countertop), estufa, refrigerador, fregadero, backsplash, toe kick.
    - Baño: lo que se demuele primero - azulejo de la regadera, mortero, tabla de cemento (Durock), \
      barrera de vapor, tablaroca verde - y despues las piezas: tina, tocador, inodoro, base de \
      regadera, puerta de regadera, botiquin, extractor, espejo.
    - LO QUE SE CUENTA, no se mide: inodoro, tina, base y puerta de regadera, botiquin, extractor, \
      espejo, toallero, estufa, refrigerador, fregadero. Se anotan por PIEZA (EA), no en pies.
    - PIE CUADRADO contra PIE LINEAL: una superficie demolida (pared, piso, techo) \
      se cobra en pies CUADRADOS y necesita largo Y ancho. Un zócalo o un trim se \
      cobra en pies LINEALES y solo necesita el largo.
    - Un corte de pared casi siempre es de 2 pies de alto: es lo que se corta \
      arriba del piso cuando el agua subió. Ese 2 es el ANCHO de esa medida.
    - Lo que va debajo: tablaroca lleva INSULACIÓN; alfombra lleva ALMOHADILLA \
      (pad); laminado y vinil llevan UNDERLAYMENT.
    - Un piso o un techo se miden con DOS esquinas. Una pared puede dar la \
      vuelta por varias esquinas seguidas.
    - Cómo habla la cuadrilla: "carpeta" es alfombra, "béisbol" es baseboard, \
      "elevepé" es LVP, "tablaroca" es drywall, "insulación" es insulation.

    LA APP, para que puedas contestar dónde va cada cosa. Tiene nueve pestañas:
    - HORAS: a qué hora entró y salió cada quien.
    - MANO DE OBRA: el trabajo hecho, por trabajador.
    - EQUIPO: los ventiladores y deshumidificadores puestos y recogidos.
    - COMUNICACIÓN: lo que se habló con el cliente y con la aseguranza.
    - SECADO: las lecturas de humedad, día por día.
    - MATERIALES: lo que se usó y lo que se compró.
    - MEDIDAS: donde caen las medidas que toma con esta cámara. Cada tarjeta es
      un cuarto de un nivel, y dentro van los cortes.
    - PLANO: el plano de la casa escaneado con el otro botón de cámara.
    - MANUAL: el protocolo de la cuadrilla.
    Esta cámara de medir se abre desde MEDIDAS: con el botón de cada tarjeta, o
    con "Medir un recorrido", que mide la casa entera sin salir de la cámara.

    TU TRABAJO: convertir lo que dijo en UNA acción de la lista que te doy.

    Si te pregunta algo, o nada más te está hablando, usa "responder" y escribe \
    la contestación en el campo respuesta: UNA o DOS frases cortas, en español, \
    como le contestaría un compañero de trabajo - no como un manual. Usa los \
    datos del ESTADO. Si no sabes algo, dilo sin rodeos.

    NUNCA INVENTES UN NÚMERO NI UNA MEDIDA. Ninguna acción tuya puede cambiar \
    una medida; si te dice un número, otra parte de la app lo anota.

    Si está hablando con otra persona y no contigo, usa "nada" y no digas nada.
    """
    #endif

    // La sesion se rehace sola cuando el modelo falla. Ya no hace falta tirarla
    // al cambiar de seccion - ese cambio ahora viaja en el estado - y por eso
    // la conversacion sobrevive un recorrido completo.
    static func reiniciarSesion() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { sesion = nil }
        #endif
    }

    // Entiende una frase que las ordenes de siempre no reconocieron.
    //
    // `estado` es lo que esta pasando ahorita, en una linea: sirve para que
    // "quítale eso" o "¿me falta algo?" tengan sentido.
    static func entender(_ frase: String,
                         seccion: String,
                         estado: String,
                         materiales: [String],
                         cuartos: [String] = [],
                         niveles: [String] = [],
                         conversacion: String = "",
                         aprendido: [String] = [],
                         completion: @escaping (Resultado?) -> Void) {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), disponible else { completion(nil); return }
        Task { @MainActor in
            do {
                if sesion == nil {
                    sesion = LanguageModelSession(instructions: instrucciones)
                }
                var prompt = """
                ESTADO: \(estado)
                MATERIALES DE ESTA SECCIÓN: \(materiales.joined(separator: ", "))
                """
                if !cuartos.isEmpty { prompt += "\nCUARTOS DE LA CASA: \(cuartos.joined(separator: ", "))" }
                if !niveles.isEmpty { prompt += "\nNIVELES: \(niveles.joined(separator: ", "))" }
                // LO QUE YA LLEVAN PLATICADO, de dias anteriores tambien. Sin
                // esto "¿te acuerdas de lo que te dije?" no tiene respuesta
                // posible: la sesion del modelo muere al cerrar la camara.
                if !conversacion.isEmpty { prompt += "\n\nDE LO QUE YA HAN HABLADO:\n\(conversacion)" }
                // Y como trabaja EL, sacado de lo que ha hecho - no de lo que
                // ha dicho. Sirve para que conteste "como siempre" con
                // fundamento en vez de adivinar.
                if !aprendido.isEmpty {
                    prompt += "\n\nCOMO MIDE ÉL (aprendido de sus medidas):\n- " + aprendido.joined(separator: "\n- ")
                }
                prompt += """

                ACCIONES POSIBLES: \(Intencion.allCases.map { $0.rawValue }.joined(separator: ", "))

                EL TÉCNICO DIJO: "\(frase)"
                """
                let r = try await sesion?.respond(to: prompt,
                                                  generating: SalidaIA.self,
                                                  options: GenerationOptions(temperature: 0.3))
                guard let s = r?.content else { completion(nil); return }
                let intencion = Intencion(rawValue: s.accion) ?? .nada
                completion(Resultado(intencion: intencion,
                                     valor: s.valor?.isEmpty == false ? s.valor : nil,
                                     respuesta: s.respuesta?.isEmpty == false ? s.respuesta : nil))
            } catch {
                // Si el modelo falla - se quedo sin memoria, la conversacion
                // crecio de mas, lo apagaron a medias - la app NO se cae ni se
                // queda muda: se tira la sesion para que la siguiente frase
                // arranque limpia, y mientras tanto siguen las ordenes de
                // siempre, que es como funcionaba antes de todo esto.
                sesion = nil
                completion(nil)
            }
        }
        #else
        completion(nil)
        #endif
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct SalidaIA {
    @Guide(description: "Una sola acción de la lista de ACCIONES POSIBLES. Si te habla a ti pero no es ninguna acción, usa 'responder'. Si le hablaba a otra persona, usa 'nada'.")
    var accion: String

    @Guide(description: "El dato que pide la acción, exacto de la lista que te di: el material para escogerMaterial, el cuarto para escogerCuarto, piso/pared/techo/cocina para escogerSeccion, el nivel para escogerNivel. Vacío para todo lo demás.")
    var valor: String?

    @Guide(description: "Solo si la acción es responder: una o dos frases cortas en español contestando lo que dijo, como le hablaría un compañero de trabajo.")
    var respuesta: String?
}
#endif
