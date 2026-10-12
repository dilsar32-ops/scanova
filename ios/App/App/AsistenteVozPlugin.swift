import Foundation
import Capacitor
import AVFoundation
import Speech

// EL MICROFONO DEL ASISTENTE GLOBAL.
//
// ---- LO QUE PASO EN EL TELEFONO, Y QUE ENSENO ----
// Prueba real del 6 oct 2026. El dijo, mas o menos:
//   "estoy en la cocina, instalamos un dehumidifier, dos fans y una HEPA, y un
//    drip pan debajo... en el master bedroom un dehumidifier, cinco fans..."
// y el dictado escribio:
//   "instalamos un de Fire dos Fence y un jefa y un Three pan ... un Dino Fire
//    cinco Fence ... cuatro digan Fires una jefa cinco Fence"
//
// Y ADEMAS DIJO QUE ESTABA SEGURO DE TODAS LAS PALABRAS.
//
// De ahi salen las tres cosas que importan:
//  1. `confidence` NO SIRVE sola. Entrego basura con confianza alta y la lista
//     de dudosas salio vacia. Una estrategia que dependa de que el reconocedor
//     avise cuando duda, no avisa nunca.
//  2. `contextualStrings` NO ALCANZA. Se le estaban mandando "Fans",
//     "Dehumidifiers", "HEPAs" y aun asi salio "Fence", "de Fire", "jefa". Es
//     una sugerencia debil, no cambia el vocabulario del reconocedor.
//  3. LA RAIZ: el son palabras INGLESAS dichas dentro de una frase en espanol.
//     El reconocedor es-MX no las tiene en su lexico, asi que las mapea a lo
//     mas parecido en espanol: fans -> "Fence", HEPA -> "jefa", dehumidifier
//     -> "de Fire". No esta oyendo mal: no conoce la palabra.
//
// ---- LO QUE SE HACE AHORA, Y POR QUE ----
// A. DOS OIDOS A LA VEZ, es-MX y en-US, sobre EL MISMO audio. Es como oye una
//    persona bilingue: el oido espanol arma la frase, el oido ingles clava
//    "five fans", "three HEPAs", "dehumidifier". Las dos lecturas se mandan
//    arriba y el modelo las junta. Esto no es parchar palabras: funciona para
//    cualquier termino del oficio, dicho en cualquiera de los dos idiomas.
// B. UN MODELO DE LENGUAJE CONSTRUIDO DEL CATALOGO REAL
//    (`SFCustomLanguageModelData`, iOS 17+). Esto no es una sugerencia como
//    contextualStrings: mete los terminos AL VOCABULARIO del reconocedor y le
//    sube el peso a las frases que de verdad dice la cuadrilla. Las frases se
//    GENERAN del catalogo que la app ya tiene, no se escriben a mano, y el
//    peso va al maximo porque aqui solo se habla de esto.
// C. Lo que el reconocedor no pueda resolver, se MANDA con su duda. Arriba se
//    pregunta. Nunca se inventa.
//
// ---- LO QUE SIGUE SIENDO CIERTO ----
// UN solo AVAudioEngine con UN solo tap. De ese mismo pedacito de audio salen
// el nivel (RMS) y lo que oyen los dos reconocedores. Dos taps serian dos
// motores peleandose la entrada, que en iOS deja a uno callado.

// ---------------------------------------------------------------------------
// UN OIDO: un reconocedor, su tarea, su relevo y su texto.
// Hay uno por idioma y los dos comen del mismo tap.
// ---------------------------------------------------------------------------
final class OidoVoz {
    let idioma: String
    private let rec: SFSpeechRecognizer
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var relevo: DispatchWorkItem?
    private var acumulado = ""
    private var fallos = 0
    private var vivo = false
    var vocabulario: [String] = []
    // Se arma aparte y tarda; cuando llega, la entra en el siguiente relevo.
    var modeloPropio: Any?            // SFSpeechLanguageModel.Configuration
    var soloEnElTelefono = false

    /// Se llama en cada resultado: (texto completo del oido, dudosos, otras lecturas)
    var alOir: ((String, [[String: Any]], [String]) -> Void)?
    /// Solo cuando ya fallo varias veces seguidas.
    var alMorir: ((String) -> Void)?
    /// Avisos que no son errores (por ejemplo, que se solto el modelo propio).
    var alAviso: ((String) -> Void)?
    /// Este oido ya se rindio. El otro puede seguir oyendo.
    private(set) var muerto = false
    // ---- LA VIGILANCIA DE LA MUDEZ ----
    // No puedo probar el modelo del catalogo desde la Mac: solo se ve en el
    // telefono. Asi que la app se revisa sola - si hay VOZ entrando y el
    // reconocedor no suelta ni una palabra, el modelo es el sospechoso y se
    // suelta. Vale mas un asistente que oye regular que uno mudo.
    private var abiertaEn = Date()
    private var textoEn: Date?
    private(set) var conModelo = false
    /// Hasta que no salga UNA palabra, no se arriesga nada.
    private var yaSalioTexto = false
    private static let SEGUNDOS_MUDO = 6.0

    init?(idioma: String) {
        guard let r = SFSpeechRecognizer(locale: Locale(identifier: idioma)), r.isAvailable else { return nil }
        self.idioma = idioma
        self.rec = r
        self.soloEnElTelefono = r.supportsOnDeviceRecognition
    }

    var texto: String {
        let viva = task != nil ? ultimoParcial : ""
        return OidoVoz.juntar(acumulado, viva)
    }
    private var ultimoParcial = ""

    func empezar() {
        vivo = true; muerto = false
        acumulado = ""; ultimoParcial = ""; fallos = 0; yaSalioTexto = false
        abrirTarea()
    }

    func parar() {
        vivo = false
        relevo?.cancel(); relevo = nil
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
    }

    func tragar(_ buffer: AVAudioPCMBuffer) { request?.append(buffer) }

    // ---- UNA TAREA, Y SU RELEVO ----
    // iOS le pone tope de ~1 min a CADA tarea de reconocimiento. El motor de
    // audio no tiene ese tope: se releva la tarea antes y el que habla no nota
    // nada.
    private func abrirTarea() {
        guard vivo else { return }
        request?.endAudio()
        task?.cancel()
        ultimoParcial = ""

        let pedido = SFSpeechAudioBufferRecognitionRequest()
        pedido.shouldReportPartialResults = true
        pedido.taskHint = .dictation
        if #available(iOS 16.0, *) { pedido.addsPunctuation = false }  // la puntuacion estorba al interpretar
        // La sugerencia debil. Se deja porque no cuesta, pero la prueba del
        // telefono demostro que por si sola no alcanza: lo que de verdad pesa
        // es el modelo de abajo.
        if !vocabulario.isEmpty { pedido.contextualStrings = Array(vocabulario.prefix(100)) }
        // EL MODELO HECHO DEL CATALOGO. Apple exige reconocimiento DENTRO del
        // telefono para usarlo, lo cual ademas le conviene: la cuadrilla
        // trabaja en sotanos sin senal.
        // EL MODELO DEL CATALOGO. Apple exige reconocimiento DENTRO del
        // telefono para usarlo. Si este telefono no lo tiene listo para este
        // idioma, poner la bandera deja al reconocedor sin a quien preguntarle
        // y NO DEVUELVE NADA - ni texto ni error. Eso es exactamente lo que
        // paso: "escuchando" sin una sola palabra. Se mira antes.
        // SOLO DESPUES DE QUE YA SALIO TEXTO. Nunca se arriesga lo que ya
        // funciona: si todavia no se ha oido ni una palabra en esta sesion, se
        // trabaja sin el modelo. Una vez que se comprobo que el camino sirve,
        // el modelo entra en el siguiente relevo - y si entonces enmudece, el
        // vigilante lo suelta. Asi nunca puede ser el que impide las PRIMERAS
        // palabras, que es la falla que costo tres pruebas.
        if #available(iOS 17.0, *), soloEnElTelefono, yaSalioTexto,
           let cfg = modeloPropio as? SFSpeechLanguageModel.Configuration {
            pedido.customizedLanguageModel = cfg
            pedido.requiresOnDeviceRecognition = true
            conModelo = true
        } else {
            conModelo = false
        }
        abiertaEn = Date()
        textoEn = nil
        request = pedido

        NSLog("[Voz] tarea abierta %@ · modelo:%@ · sinRed:%@", idioma,
              conModelo ? "si" : "no", soloEnElTelefono ? "si" : "no")
        task = rec.recognitionTask(with: pedido) { [weak self] resultado, error in
            guard let self = self, self.vivo else { return }
            if let r = resultado {
                self.fallos = 0
                let t = r.bestTranscription.formattedString
                if !t.trimmingCharacters(in: .whitespaces).isEmpty {
                    if self.textoEn == nil { self.textoEn = Date() }
                    if !self.yaSalioTexto {
                        self.yaSalioTexto = true
                        // El camino sirve. Ahora si vale la pena probar el
                        // modelo del catalogo, en el siguiente relevo.
                        NSLog("[Voz] primera palabra oida en %@", self.idioma)
                    }
                }
                self.ultimoParcial = t
                self.reportar(r)
                if r.isFinal {
                    let t = r.bestTranscription.formattedString.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { self.acumulado = OidoVoz.juntar(self.acumulado, t) }
                    self.ultimoParcial = ""
                    DispatchQueue.main.async { self.abrirTarea() }
                }
            }
            if let e = error {
                // NO TODO "ERROR" ES UNA FALLA.
                //
                // Prueba del 6 oct: la pantalla se puso en ERROR con
                // "No speech detected" mientras el microfono SI estaba oyendo.
                // Ese aviso (1110) no quiere decir que algo se rompio: quiere
                // decir que todavia nadie ha hablado, que es el estado normal
                // de un asistente esperando. Contarlo como falla hacia que a
                // los pocos segundos de silencio se llegara a 4 y se matara la
                // sesion. Lo mismo con el aviso que suelta la tarea que
                // nosotros mismos cancelamos en cada relevo.
                //
                // Asi que lo normal se reabre calladito y NO cuenta.
                let ne = e as NSError
                NSLog("[Voz] error %@ %ld: %@", ne.domain, ne.code, ne.localizedDescription)
                if OidoVoz.esSilencioONuestro(ne) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                        guard let self = self, self.vivo else { return }
                        self.abrirTarea()
                    }
                    return
                }
                self.fallos += 1
                // SI FALLA DE VERDAD CON EL MODELO PROPIO PUESTO, el modelo es
                // el primer sospechoso: obliga a reconocer dentro del telefono
                // y eso pide que el idioma este descargado. Se suelta y se
                // vuelve a intentar sin el, antes que quedarse sin oir.
                if self.fallos >= 2 && self.modeloPropio != nil {
                    self.modeloPropio = nil
                    self.alAviso?("modelo_soltado")
                }
                if self.fallos >= 5 { self.muerto = true; self.alMorir?(e.localizedDescription); return }
                let espera = min(3.0, 0.5 * Double(self.fallos))
                DispatchQueue.main.asyncAfter(deadline: .now() + espera) { [weak self] in
                    guard let self = self, self.vivo else { return }
                    self.abrirTarea()
                }
            }
        }

        relevo?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self = self, self.vivo else { return }
            self.request?.endAudio()   // entrega el final; el bloque de arriba reabre
        }
        relevo = w
        DispatchQueue.main.asyncAfter(deadline: .now() + OidoVoz.SEGUNDOS_ANTES_DE_RELEVAR, execute: w)
    }

    // LA DUDA SE MANDA, NO SE ESCONDE. Pero despues de la prueba del telefono
    // ya sabemos que `confidence` miente hacia arriba: dijo estar seguro de
    // "Fence" y de "jefa". Asi que el umbral se subio y, sobre todo, lo que de
    // verdad resuelve es tener la lectura del OTRO idioma. Esto es una ayuda
    // mas, no la defensa principal.
    private func reportar(_ r: SFSpeechRecognitionResult) {
        let mejor = r.bestTranscription
        let otras = r.transcriptions.dropFirst().prefix(2).map { $0.formattedString }
        var dudosos: [[String: Any]] = []
        for seg in mejor.segments where seg.confidence > 0 && seg.confidence < 0.80 {
            var d: [String: Any] = ["palabra": seg.substring, "confianza": Double(seg.confidence)]
            if !seg.alternativeSubstrings.isEmpty { d["parecidas"] = Array(seg.alternativeSubstrings.prefix(3)) }
            dudosos.append(d)
        }
        alOir?(texto, dudosos, Array(otras))
    }

    // Lo que NO es una falla:
    //  1110 = nadie hablo todavia. Es el estado normal esperando.
    //  216 / 301 = la tarea se cancelo. La cancelamos NOSOTROS en cada relevo.
    //  203 = reintento del servicio.
    //  1101 / 1107 = tropiezos del servicio de dictado, pasajeros.
    /// Lo llama el plugin cada par de segundos. `huboVoz` = el microfono
    /// midio voz de verdad hace poco.
    /// Devuelve true si solto el modelo (hay que avisar).
    func revisarMudez(huboVoz: Bool) -> Bool {
        guard vivo, conModelo, huboVoz, textoEn == nil else { return false }
        guard Date().timeIntervalSince(abiertaEn) > OidoVoz.SEGUNDOS_MUDO else { return false }
        // Entro voz, paso el tiempo y no salio ni una palabra. El modelo del
        // catalogo es lo unico raro aqui: se suelta y se vuelve a abrir sin el.
        NSLog("[Voz] mudo con voz entrando: suelto el modelo del catalogo")
        modeloPropio = nil
        abrirTarea()
        return true
    }

    static func esSilencioONuestro(_ e: NSError) -> Bool {
        if e.domain == "kAFAssistantErrorDomain" {
            return [1110, 216, 301, 203, 1101, 1107].contains(e.code)
        }
        // El dominio de Speech usa otros numeros segun la version de iOS; un
        // "cancelado" nunca es una falla, venga de donde venga.
        if e.localizedDescription.lowercased().contains("cancel") { return true }
        if e.localizedDescription.lowercased().contains("no speech") { return true }
        return false
    }

    static func juntar(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }
    static let SEGUNDOS_ANTES_DE_RELEVAR = 45.0
}

@objc(AsistenteVozPlugin)
public class AsistenteVozPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "AsistenteVozPlugin"
    public let jsName = "AsistenteVoz"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "disponible", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "empezar", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "parar", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "hablar", returnType: CAPPluginReturnPromise)
    ]

    private var engine: AVAudioEngine?
    private var oidos: [OidoVoz] = []
    private var ultimoNivelEnviado = Date.distantPast
    private var escuchando = false
    private var vocabulario: [String] = []
    private var modeloListo: [String: Any] = [:]     // idioma -> Configuration
    private var huboVozEn = Date.distantPast
    private var vigilante: Timer?

    // ---- QUE CONTESTE HABLANDO ----
    // Su pedido del 6 oct: "deberia de tener sonido, como cuando me esta
    // escuchando". Tiene razon y es lo que hace util una conversacion en el
    // campo: con las manos sucias y el telefono en el bolsillo, una pregunta
    // escrita en la pantalla no sirve de nada.
    //
    // Mientras habla, el microfono deja de MANDARLE audio al reconocedor. Si
    // no, se oiria a si mismo y se transcribiria su propia pregunta como si
    // el tecnico la hubiera dicho. El motor de audio no se apaga - solo se
    // deja de alimentar al reconocedor - para no tener que levantarlo otra
    // vez, que es lento y a veces falla.
    private let voz = AVSpeechSynthesizer()
    private var hablando = false

    // UN SOLO OIDO. Y aqui va la leccion, porque me costo tres pruebas suyas:
    //
    // La idea de oir con dos reconocedores a la vez (es-MX y en-US) sobre el
    // mismo audio era buena en papel - asi oye una persona bilingue - pero EN
    // EL TELEFONO dejo de salir texto. La cronologia no deja lugar a dudas:
    // con un oido escribia (mal, pero escribia); con dos, primero errores y
    // despues nada. iOS no sostiene dos tareas de reconocimiento a la vez de
    // forma confiable; la segunda ahoga a la primera.
    //
    // Me pase tres rondas culpando al modelo del catalogo cuando lo unico que
    // de verdad habia cambiado era esto. Vuelve a uno.
    //
    // Lo bilingue NO se pierde: se consigue por el otro lado, metiendo los
    // terminos en ingles al modelo de lenguaje de este reconocedor, que es
    // justo para lo que sirve ese mecanismo.
    private static let IDIOMAS = ["es-MX"]

    @objc func disponible(_ call: CAPPluginCall) {
        call.resolve([
            "ok": SFSpeechRecognizer(locale: Locale(identifier: "es-MX")) != nil,
            "permisoVoz": SFSpeechRecognizer.authorizationStatus() == .authorized,
            "permisoMic": AVAudioSession.sharedInstance().recordPermission == .granted
        ])
    }

    @objc func empezar(_ call: CAPPluginCall) {
        // El vocabulario REAL: el catalogo de equipo de la app y los cuartos
        // del plano abierto. No hay ni una palabra escrita a mano aqui.
        self.vocabulario = (call.getArray("vocabulario") as? [String]) ?? []
        let frases = (call.getArray("frases") as? [String]) ?? []
        // COMO SUENA CADA PALABRA DEL CATALOGO, leida por un hispanohablante.
        // Esta es la pieza que faltaba: el reconocedor de espanol no CONOCIA
        // "fans" ni "HEPA", por eso escribia "Fence" y "jefa". Aqui se le
        // ensena. Los sonidos se generan arriba del propio catalogo y se
        // probaron contra los 49 que el idioma admite ANTES de mandarlos: un
        // sonido inventado hace que Apple rechace el modelo entero.
        let pronunciaciones = (call.getArray("pronunciaciones") as? [[String: Any]]) ?? []

        SFSpeechRecognizer.requestAuthorization { [weak self] estado in
            guard let self = self else { return }
            guard estado == .authorized else {
                DispatchQueue.main.async { call.reject("Falta el permiso de reconocimiento de voz.", "permiso_voz") }
                return
            }
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                guard ok else {
                    DispatchQueue.main.async { call.reject("Falta el permiso del microfono.", "permiso_mic") }
                    return
                }
                DispatchQueue.main.async { self.arrancar(call: call, frases: frases, pron: pronunciaciones) }
            }
        }
    }

    private func arrancar(call: CAPPluginCall, frases: [String], pron: [[String: Any]]) {
        pararTodo()

        // Un oido por idioma. Si alguno no esta listo en este telefono se
        // sigue con el que si: oir a medias es mejor que no oir.
        oidos = AsistenteVozPlugin.IDIOMAS.compactMap { OidoVoz(idioma: $0) }
        guard !oidos.isEmpty else {
            call.reject("El telefono no tiene listo el reconocimiento de voz.", "sin_reconocedor"); return
        }
        for o in oidos {
            o.vocabulario = vocabulario
            o.modeloPropio = modeloListo[o.idioma]
            o.alOir = { [weak self] _, dudosos, otras in self?.mandarTexto(dudosos: dudosos, otras: otras) }
            o.alMorir = { [weak self] msg in
                // Un oido caido no mata la sesion: solo se avisa si se cayeron
                // TODOS, porque con uno solo todavia se oye.
                //
                // Antes esto miraba si el oido TENIA TEXTO, y al empezar
                // ninguno tiene: por eso la pantalla se ponia en ERROR apenas
                // habia un tropiezo, aunque el microfono estuviera oyendo.
                // Ahora se mira si de verdad se rindio.
                guard let self = self else { return }
                if self.oidos.allSatisfy({ $0.muerto }) {
                    self.notifyListeners("error", data: ["mensaje": msg])
                } else {
                    self.notifyListeners("aviso", data: ["aviso": "oido_caido", "idioma": o.idioma])
                }
            }
            o.alAviso = { [weak self] a in
                self?.notifyListeners("aviso", data: ["aviso": a, "idioma": o.idioma])
            }
        }

        let sesion = AVAudioSession.sharedInstance()
        do {
            // .default y no .measurement: con .measurement iOS baja el volumen
            // de SALIDA, y esta pantalla va a hablar. Esa leccion ya costo una
            // ronda entera en el escaner de planos.
            try sesion.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP, .allowBluetooth])
            try sesion.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            call.reject("No se pudo abrir el audio: \(error.localizedDescription)", "audio"); return
        }

        let motor = AVAudioEngine()
        let entrada = motor.inputNode
        let formato = entrada.outputFormat(forBus: 0)
        entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { [weak self] buffer, _ in
            guard let self = self else { return }
            // EL MISMO pedacito de audio a los oidos - salvo mientras el
            // asistente esta hablando, para que no se oiga a si mismo.
            if !self.hablando { for o in self.oidos { o.tragar(buffer) } }
            // Y de ese mismo pedacito, el nivel. RMS, que es lo que se parece
            // a "que tan fuerte hablo"; el pico inflaria la esfera con un
            // golpe en la mesa.
            guard let ch = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength); guard n > 0 else { return }
            var suma: Float = 0
            for i in 0..<n { let v = ch[i]; suma += v*v }
            let rms = (suma / Float(n)).squareRoot()
            let db = 20 * log10(max(rms, 0.000_001))
            let nivel = max(0, min(1, (db + 50) / 40))
            let ahora = Date()
            // VOZ DE VERDAD, no ruido de fondo. Sirve para saber si el
            // reconocedor se quedo mudo teniendo con que trabajar.
            if nivel > 0.25 { self.huboVozEn = ahora }
            guard ahora.timeIntervalSince(self.ultimoNivelEnviado) > 0.066 else { return }   // ~15/s
            self.ultimoNivelEnviado = ahora
            self.notifyListeners("nivel", data: ["nivel": Double(nivel)])
        }

        motor.prepare()
        do { try motor.start() }
        catch {
            entrada.removeTap(onBus: 0)
            call.reject("No se pudo encender el microfono: \(error.localizedDescription)", "motor"); return
        }

        engine = motor
        escuchando = true
        for o in oidos { o.empezar() }

        // LA REVISION. Cada 2 s pregunta si algun oido se quedo mudo teniendo
        // voz entrando. Es barato y es lo unico que puede atrapar en el campo
        // un problema que no se puede reproducir en la computadora.
        vigilante?.invalidate()
        vigilante = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, self.escuchando else { return }
            let huboVoz = Date().timeIntervalSince(self.huboVozEn) < 5.0
            for o in self.oidos where o.revisarMudez(huboVoz: huboVoz) {
                self.notifyListeners("aviso", data: ["aviso": "modelo_soltado", "idioma": o.idioma])
            }
        }

        // EL MODELO DEL CATALOGO se arma APARTE y tarda unos segundos. El
        // microfono no lo espera: arranca ya, y cuando el modelo este listo
        // entra solo en el siguiente relevo de tarea. Asi nadie se queda
        // mirando una pantalla muerta mientras se compila.
        prepararModelos(frases: frases, pron: pron)

        call.resolve(["ok": true, "idiomas": oidos.map { $0.idioma }])
    }

    // ---- LO QUE SE MANDA ARRIBA ----
    // Las DOS lecturas, separadas y sin mezclar. Juntarlas aqui seria decidir
    // con menos informacion de la que tiene el modelo de arriba, que ademas se
    // acuerda de toda la conversacion.
    private func mandarTexto(dudosos: [[String: Any]], otras: [String]) {
        var porIdioma: [String: String] = [:]
        for o in oidos { porIdioma[o.idioma] = o.texto }
        // El de espanol manda para la pantalla porque arma mejor la frase; el
        // de ingles va completo igual para que el interprete lo use.
        let principal = porIdioma["es-MX"] ?? porIdioma.values.first ?? ""
        var otrasTodas = otras
        if let en = porIdioma["en-US"], !en.isEmpty, en != principal { otrasTodas.insert(en, at: 0) }
        notifyListeners("texto", data: [
            "texto": principal,
            "porIdioma": porIdioma,
            "otras": otrasTodas,
            "dudosos": dudosos
        ])
    }

    // -----------------------------------------------------------------------
    // EL MODELO DE LENGUAJE HECHO DEL CATALOGO REAL
    //
    // Esto es lo que el pidio: "usando el catalogo real de equipos como
    // contexto FUERTE". `contextualStrings` es una sugerencia; esto mete los
    // terminos al vocabulario del reconocedor y le sube el peso a las frases
    // que de verdad se dicen en el trabajo.
    //
    // Las frases NO se escriben a mano: se generan arriba, en la web, del
    // mismo catalogo de equipo y de los cuartos del plano abierto. El dia que
    // cambie el catalogo, cambia esto solo.
    // -----------------------------------------------------------------------
    private func prepararModelos(frases: [String], pron: [[String: Any]]) {
        guard #available(iOS 17.0, *) else { return }
        guard !frases.isEmpty || !vocabulario.isEmpty else { return }
        let terminos = vocabulario
        // La huella incluye las pronunciaciones: si el aprende una nueva, el
        // modelo se vuelve a armar solo. Ahi esta el aprendizaje de verdad.
        let huella = AsistenteVozPlugin.huella(terminos + frases + pron.map { "\($0["palabra"] ?? "")=\($0["sonidos"] ?? "")" })

        for idioma in AsistenteVozPlugin.IDIOMAS {
            if modeloListo[idioma] != nil { continue }
            Task.detached(priority: .utility) { [weak self] in
                guard let cfg = await AsistenteVozPlugin.construirModelo(idioma: idioma, terminos: terminos,
                                                                        frases: frases, pron: pron,
                                                                        huella: huella) else { return }
                await MainActor.run {
                    guard let self = self else { return }
                    self.modeloListo[idioma] = cfg
                    // Entra en el siguiente relevo, sin cortar lo que se esta
                    // diciendo ahorita.
                    for o in self.oidos where o.idioma == idioma { o.modeloPropio = cfg }
                    self.notifyListeners("modelo", data: ["idioma": idioma, "listo": true])
                }
            }
        }
    }

    @available(iOS 17.0, *)
    private static func construirModelo(idioma: String, terminos: [String], frases: [String],
                                        pron: [[String: Any]], huella: String) async -> SFSpeechLanguageModel.Configuration? {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true) else { return nil }
        let carpeta = base.appendingPathComponent("vozmodelo", isDirectory: true)
        try? fm.createDirectory(at: carpeta, withIntermediateDirectories: true)
        // LA RECETA tiene su propia version. La huella sale del catalogo, asi
        // que si el catalogo no cambia la huella tampoco - y el telefono se
        // quedaria usando el modelo COMPILADO MAL de la version anterior.
        // Subir esto obliga a rehacerlo. Hay que subirlo cada vez que cambie
        // COMO se construye el modelo, no solo que cambie el catalogo.
        let receta = "r3"
        let ident = "amg.voz.\(receta).\(idioma).\(huella)"
        let datos = carpeta.appendingPathComponent("\(ident).bin")
        let compilado = carpeta.appendingPathComponent("\(ident).lm")
        let vocab = carpeta.appendingPathComponent("\(ident).voc")

        // Si ya se armo con el MISMO catalogo, no se vuelve a compilar: tarda
        // segundos y seria regalarle bateria a algo que no cambio.
        // Las DOS tienen que estar. Antes solo se miraba el modelo, y un
        // vocabulario faltante da justo el sintoma de "oye y no escribe".
        if !fm.fileExists(atPath: compilado.path) || !fm.fileExists(atPath: vocab.path) {
            let data = SFCustomLanguageModelData(locale: Locale(identifier: idioma),
                                                 identifier: ident, version: "1")
            // LOS FONEMAS QUE ADMITE ESTE IDIOMA. El siguiente escalon para las
            // palabras CORTAS en ingles dichas en espanol ("fans") es ensenarle
            // como suenan, y para eso hay que saber con que fonemas se puede
            // escribir. Esto los deja en la consola del telefono para poder
            // hacerlo con el dato real y no a ojo.
            if let fon = try? await SFCustomLanguageModelData.supportedPhonemes(locale: Locale(identifier: idioma)) {
                NSLog("[Voz] fonemas de %@ (%d): %@", idioma, fon.count, fon.joined(separator: " "))
            }
            // LAS FRASES CON PESO ALTO. Esto es lo que mete los terminos al
            // vocabulario del reconocedor: una frase del modelo define las
            // palabras que la forman. "HEPA" y "dehumidifier" no estaban en el
            // lexico del reconocedor de espanol - por eso salian "jefa" y
            // "de Fire" - y entran por aqui.
            //
            // (`insert(term:)` existe pero pide la PRONUNCIACION fonetica de
            // cada palabra, no la palabra. Eso es el siguiente escalon si con
            // esto no basta, y hay que sacar los fonemas que admite cada
            // idioma del propio telefono: `supportedPhonemes(locale:)`.)
            for f in frases { data.insert(phraseCount: SFCustomLanguageModelData.PhraseCount(phrase: f, count: 60)) }
            // Y cada termino suelto, por si lo dice sin frase alrededor.
            for t in terminos { data.insert(phraseCount: SFCustomLanguageModelData.PhraseCount(phrase: t, count: 40)) }
            // COMO SE PRONUNCIA CADA UNA. Aqui es donde el reconocedor deja de
            // escribir "Fence" por "fans": se le dice que esa palabra suena
            // /fans/, con los sonidos del espanol.
            for p in pron {
                guard let g = p["palabra"] as? String, let son = p["sonidos"] as? String else { continue }
                let fonemas = son.split(separator: " ").map(String.init)
                guard !g.isEmpty, !fonemas.isEmpty else { continue }
                data.insert(term: SFCustomLanguageModelData.CustomPronunciation(grapheme: g, phonemes: fonemas))
            }
            NSLog("[Voz] modelo con %d frases y %d pronunciaciones", frases.count, pron.count)
            do { try await data.export(to: datos) } catch { return nil }
            // LAS DOS RUTAS. El encabezado de Apple lo dice claro: la
            // configuracion lista "las URLs donde este metodo debe CREAR el
            // modelo y el vocabulario compilado". Yo mandaba el vocabulario en
            // nil, asi que quedaba a medias - y un modelo a medias es
            // exactamente un reconocedor que oye y no escribe nada.
            let cfg = SFSpeechLanguageModel.Configuration(languageModel: compilado, vocabulary: vocab)
            do {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                    if #available(iOS 26.0, *) {
                        SFSpeechLanguageModel.prepareCustomLanguageModel(for: datos, configuration: cfg) { err in
                            if let e = err { c.resume(throwing: e) } else { c.resume() }
                        }
                    } else {
                        SFSpeechLanguageModel.prepareCustomLanguageModel(
                            for: datos,
                            clientIdentifier: Bundle.main.bundleIdentifier ?? "amg.fieldreports",
                            configuration: cfg
                        ) { err in
                            if let e = err { c.resume(throwing: e) } else { c.resume() }
                        }
                    }
                }
            } catch { return nil }
            try? fm.removeItem(at: datos)
            AsistenteVozPlugin.limpiarViejos(carpeta: carpeta, menos: ident)
        }
        // EL PESO. Antes estaba en 1.0 "porque aqui solo se habla del
        // trabajo", y eso fue un error: peso 1 desplaza del todo al modelo
        // base, y entonces el reconocedor no puede armar NI las palabras que
        // van entre medio - no sale nada. El tecnico habla frases completas,
        // no nombres sueltos. Se inclina hacia el catalogo, no se reemplaza.
        if #available(iOS 26.0, *) {
            return SFSpeechLanguageModel.Configuration(languageModel: compilado, vocabulary: vocab, weight: 0.35)
        }
        return SFSpeechLanguageModel.Configuration(languageModel: compilado, vocabulary: vocab)
    }

    // El catalogo cambia (un cuarto nuevo en el plano) y se compila otro
    // modelo. Los de antes ya no sirven y no tienen por que ocupar el telefono.
    private static func limpiarViejos(carpeta: URL, menos ident: String) {
        let fm = FileManager.default
        guard let hijos = try? fm.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: nil) else { return }
        for h in hijos where !h.lastPathComponent.hasPrefix(ident) {
            if h.lastPathComponent.hasPrefix("amg.voz.") { try? fm.removeItem(at: h) }
        }
    }

    private static func huella(_ partes: [String]) -> String {
        var h: UInt64 = 1469598103934665603
        for p in partes.sorted() {
            for b in p.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        }
        return String(h, radix: 36)
    }

    @objc func hablar(_ call: CAPPluginCall) {
        let texto = call.getString("texto") ?? ""
        guard !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            call.resolve(["ok": false]); return
        }
        DispatchQueue.main.async {
            // Si ya estaba diciendo algo, lo nuevo manda: una pregunta vieja
            // encima de la nueva confunde mas que ayudar.
            if self.voz.isSpeaking { self.voz.stopSpeaking(at: .immediate) }
            let u = AVSpeechUtterance(string: texto)
            u.voice = AVSpeechSynthesisVoice(language: call.getString("idioma") ?? "es-MX")
            u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
            // Volumen al tope a proposito: en un sotano con los equipos
            // prendidos, lo normal no se oye.
            u.volume = 1.0
            self.hablando = true
            self.voz.speak(u)
            // Se calcula cuanto va a durar y se vuelve a abrir el oido al
            // terminar. (El delegado seria mas fino, pero obliga a heredar de
            // NSObject con mas piezas; esto es predecible y no deja el
            // microfono sordo si algo falla.)
            let segundos = max(1.2, Double(texto.count) * 0.062) + 0.35
            DispatchQueue.main.asyncAfter(deadline: .now() + segundos) { [weak self] in
                self?.hablando = false
            }
            call.resolve(["ok": true, "segundos": segundos])
        }
    }

    @objc func parar(_ call: CAPPluginCall) {
        pararTodo()
        call.resolve(["ok": true])
    }

    private func pararTodo() {
        if voz.isSpeaking { voz.stopSpeaking(at: .immediate) }
        hablando = false
        vigilante?.invalidate(); vigilante = nil
        for o in oidos { o.parar() }
        oidos = []
        if let m = engine {
            m.inputNode.removeTap(onBus: 0)
            if m.isRunning { m.stop() }
        }
        engine = nil
        escuchando = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    deinit { pararTodo() }
}
