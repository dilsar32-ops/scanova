import AVFoundation

// LA VOZ DEL ASISTENTE, UNA SOLA PARA TODA LA APP.
//
// Su queja: "la voz no me gusta, podemos tener otro tipo de voz mas femenina".
//
// LO PRIMERO, QUE ES LO QUE NADIE DICE: la voz que ya estaba oyendo SI es
// femenina. `AVSpeechSynthesisVoice(language: "es-MX")` devuelve la voz por
// omision del sistema, que en español de Mexico es Paulina. Lo que no le
// gusta no es el sexo de la voz, es la CALIDAD: iOS trae de fabrica la
// version "super-compacta", que es la robotica y metalica.
//
// Y aqui esta el limite honesto: NINGUN cambio de codigo hace que la voz
// super-compacta suene bien. Es un archivo de unos pocos megabytes hecho para
// caber, no para sonar. Las versiones buenas de LA MISMA voz (Mejorada y
// Premium) son una descarga gratis dentro de Ajustes, y suenan a otra cosa.
// Por eso este archivo hace dos cosas: escoge lo mejor que HAYA instalado, y
// cuando solo hay basicas, lo dice y explica como bajar la buena.
//
// Vive aparte porque las dos pantallas que hablan - el escaner de planos y la
// camara de medir - escogian su voz cada una por su lado. Dos asistentes con
// voces distintas en la misma app se oye a aplicacion mal hecha.
enum VozAsistente {

    private static let claveVoz = "vozAsistenteId:v1"

    // Las voces en español instaladas en ESTE telefono, las mejores primero.
    //
    // No hay lista fija de nombres a proposito: lo que hay instalado cambia de
    // telefono a telefono y con lo que cada quien descargue. Se pregunta al
    // sistema y se ordena, en vez de adivinar.
    static func disponibles() -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { v in
                guard v.language.hasPrefix("es") else { return false }
                // Fuera las voces Eloquence (Eddy, Flo, Grandma, Rocko,
                // Shelley...). Son las retro de los años ochenta, a proposito
                // roboticas. En una app que termina en una factura de seguro
                // suenan a juguete.
                return !v.identifier.contains(".eloquence.")
            }
            .sorted { a, b in
                // 1. Calidad primero: es lo que de verdad se oye.
                if a.quality.rawValue != b.quality.rawValue {
                    return a.quality.rawValue > b.quality.rawValue
                }
                // 2. Femenina antes que masculina: es lo que el pidio.
                let fa = a.gender == .female ? 0 : 1
                let fb = b.gender == .female ? 0 : 1
                if fa != fb { return fa < fb }
                // 3. Español de Mexico antes que de España: asi habla su
                //    cuadrilla, y "vosotros" en una casa de Virginia distrae.
                let ma = a.language == "es-MX" ? 0 : 1
                let mb = b.language == "es-MX" ? 0 : 1
                if ma != mb { return ma < mb }
                return a.name < b.name
            }
    }

    // La que se usa: la que el escogio, o la mejor que haya.
    static func preferida() -> AVSpeechSynthesisVoice? {
        if let guardada = UserDefaults.standard.string(forKey: claveVoz),
           let v = AVSpeechSynthesisVoice(identifier: guardada) {
            return v
        }
        return disponibles().first ?? AVSpeechSynthesisVoice(language: "es-MX")
    }

    static func escoger(_ v: AVSpeechSynthesisVoice) {
        UserDefaults.standard.set(v.identifier, forKey: claveVoz)
    }

    static func esLaEscogida(_ v: AVSpeechSynthesisVoice) -> Bool {
        return preferida()?.identifier == v.identifier
    }

    // ¿Solo hay voces basicas en este telefono? Entonces no hay nada que
    // programar: hay que bajar una mejor.
    static func soloBasicas() -> Bool {
        return !disponibles().contains { $0.quality != .default }
    }

    static let comoBajarUnaMejor =
        "Ajustes → Accesibilidad → Contenido hablado → Voces → Español. " +
        "Descargue una que diga Mejorada o Premium: es gratis y suena muchísimo mejor."

    // Como se le dice al tecnico, en su idioma y sin palabras de programador.
    static func descripcion(_ v: AVSpeechSynthesisVoice) -> String {
        let calidad: String
        switch v.quality {
        case .premium:  calidad = "Premium"
        case .enhanced: calidad = "Mejorada"
        default:        calidad = "Básica"
        }
        let pais = v.language == "es-MX" ? "México"
                 : v.language == "es-ES" ? "España"
                 : v.language == "es-AR" ? "Argentina"
                 : v.language == "es-CL" ? "Chile"
                 : v.language == "es-CO" ? "Colombia"
                 : v.language == "es-US" ? "Estados Unidos"
                 : v.language
        return "\(v.name) · \(pais) · \(calidad)"
    }

    // ============ SI Y NO, PARA TODA LA APP ============
    //
    // Las dos pantallas preguntan cosas de si o no. Vivian solo en el escaner;
    // ahora la camara de medir tambien conversa, asi que la respuesta correcta
    // no puede depender de en cual pantalla este parado.
    //
    // Solo palabra COMPLETA. Un hasPrefix("si") pelado tambien pega con
    // "siganme" y "simbolo" - ya mordio una vez en la confirmacion de borrar.
    static func esSi(_ lower: String) -> Bool {
        let yes = ["sí", "si", "sip", "simon", "claro", "correcto", "exacto", "ajá", "aja",
                   "así es", "asi es", "dale", "órale", "orale", "ok", "okay", "okey", "yes"]
        return yes.contains(lower) || yes.contains(where: { lower.hasPrefix($0 + " ") })
    }
    static func esNo(_ lower: String) -> Bool {
        let no = ["no", "nop", "nel", "negativo", "incorrecto", "para nada", "todavía no", "todavia no"]
        return no.contains(lower) || no.contains(where: { lower.hasPrefix($0 + " ") })
    }

    // El ritmo lo ajusta EL, con la voz, ahi parado. Lo que a uno le parece
    // rapido a otro le parece atropellado, y no hay forma de acertarle desde
    // aqui. Se guarda por telefono.
    private static let claveRitmo = "vozAsistenteRitmo:v1"
    static func ritmo() -> Float {
        let g = UserDefaults.standard.float(forKey: claveRitmo)
        return g > 0 ? g : 1.18
    }
    static func ajustarRitmo(_ delta: Float) {
        // Con topes: demasiado lento aburre, demasiado rapido no se entiende.
        let nuevo = min(max(ritmo() + delta, 0.75), 1.6)
        UserDefaults.standard.set(nuevo, forKey: claveRitmo)
    }

    // ============ QUIEN ESTA HABLANDO ============
    //
    // Su pedido: "si alguien más está hablando, tiene que saber y captar la
    // voz del que le está hablando de frente".
    //
    // EL LIMITE HONESTO, dicho claro: el iPhone NO reconoce QUIEN habla. No
    // existe esa funcion en el reconocedor de Apple - no distingue su voz de
    // la de otra persona. Prometerlo seria mentira.
    //
    // Lo que SI se puede medir, y es lo que se usa, es QUE TAN CERCA esta el
    // que habla. El que trae el telefono lo tiene a un palmo de la boca; el
    // que esta al otro lado del cuarto entra mucho mas bajito, y eso la fisica
    // no lo puede fingir. No es reconocer la voz: es reconocer la distancia.
    // Para el caso real - alguien platicando al fondo mientras el trabaja -
    // sirve igual.
    //
    // Callado hasta tener con que comparar: con menos de 5 frases suyas
    // medidas NO filtra nada. Un filtro que adivina el primer dia lo deja sin
    // asistente sin que sepa por que.
    static func vieneDeLejos(nivel: Float, suNivel: Float, muestras: Int) -> Bool {
        guard muestras >= 5, suNivel > 0, nivel > 0 else { return false }
        return nivel < suNivel * 0.33
    }

    private static let claveNivel = "vozNivelPropio:v1"
    static func suNivel() -> Float { UserDefaults.standard.float(forKey: claveNivel) }
    static func muestrasDeNivel() -> Int { UserDefaults.standard.integer(forKey: claveNivel + ":n") }
    // Solo de frases donde hay CERTEZA de que fue el: contestar una pregunta,
    // dar una orden que se ejecuto. Aprender del audio suelto seria aprender
    // tambien de los vecinos, y el filtro se envenenaria hasta no filtrar nada.
    static func aprenderSuNivel(_ nivel: Float) {
        guard nivel > 0, nivel < .greatestFiniteMagnitude else { return }
        let n = muestrasDeNivel(), actual = suNivel()
        let tope = Float(min(n, 30))
        let nuevo = n == 0 ? nivel : (actual * tope + nivel) / (tope + 1)
        UserDefaults.standard.set(nuevo, forKey: claveNivel)
        UserDefaults.standard.set(n + 1, forKey: claveNivel + ":n")
    }

    // TODA frase hablada de la app sale de aqui, para que las dos pantallas
    // suenen igual y para que un cambio de voz o de ritmo se haga en un solo
    // lugar.
    static func frase(_ texto: String) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: texto)
        u.voice = preferida()
        // MAS RAPIDO. Su reporte: "el voice command tiene que ser un poco mas
        // rapido, esta muy lento, habla".
        //
        // Se probo bajarlo un 5% pensando en el ruido de la casa, y fue al
        // reves de lo que hacia falta: el tecnico ya SABE lo que le va a
        // decir, asi que cada palabra de mas es tiempo parado esperando. La
        // claridad en una casa ruidosa se arregla con frases CORTAS, no con
        // hablar despacio - y las frases ya se acortaron.
        u.rate = AVSpeechUtteranceDefaultSpeechRate * ritmo()
        // Sin pausa al final: el de fabrica deja un silencio que, encadenando
        // dos frases, se siente como si la app se hubiera trabado.
        u.postUtteranceDelay = 0
        u.preUtteranceDelay = 0
        u.volume = 1.0
        return u
    }
}
