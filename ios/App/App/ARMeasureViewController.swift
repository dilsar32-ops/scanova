import UIKit
import SceneKit
import ARKit
import AVFoundation
import Speech

struct ARMaterialOption {
    let value: String
    let label: String
    // What sits right behind/under this specific material, if anything -
    // drywall has insulation, carpet has pad, tile has nothing. Decided per
    // material, not per section, so this rides along with each option.
    let companionValue: String?
    let companionEn: String?
    let companionEs: String?
    // SE CUENTA, NO SE MIDE (27 sep 2026). Un inodoro, una tina, un extractor:
    // no tienen largo ni ancho, son UNO. Lo decide el lado JS con su tabla
    // MEASURE_POR_PIEZA y viaja con cada opcion, igual que el companero.
    var porPieza: Bool = false
}

// LA CASILLA DE LAS INSTRUCCIONES (13 de septiembre).
//
// Su pedido, con foto marcada: la instruccion de arriba "bajala para abajo y
// agregale una casilla, que se vea perfecto con una casilla, y que despues de
// darle las indicaciones desaparezca automaticamente y vuelva a aparecer en
// esa casilla".
//
// Un UILabel pelado pega el texto al borde de su fondo; esto le da relleno
// para que se lea como una casilla. Y avisa cuando su texto CAMBIA de verdad,
// porque el texto se asigna desde veinte sitios distintos y la pantalla tiene
// que saber cuando hay algo nuevo que mostrar sin tocar esos veinte sitios.
final class CasillaDeInstruccion: UILabel {
    var alCambiar: (() -> Void)?
    var relleno = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
    override var text: String? {
        didSet { if text != oldValue { alCambiar?() } }
    }
    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let dentro = super.textRect(forBounds: bounds.inset(by: relleno), limitedToNumberOfLines: numberOfLines)
        return dentro.inset(by: UIEdgeInsets(top: -relleno.top, left: -relleno.left,
                                             bottom: -relleno.bottom, right: -relleno.right))
    }
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: relleno))
    }
}

struct ARMeasureItem {
    let length: Double
    let width: Double?
    let material: String
    let companion: String?
    // De donde salio. Sin esto, la web no tenia mas remedio que meterlo todo
    // en la tarjeta de la que vino el boton, y por eso habia que salirse de la
    // camara para cada cuarto.
    let nivel: String
    let cuarto: String
    let seccion: String
}

enum ARMeasureOutcome {
    case cancelled
    case measured(items: [ARMeasureItem])
}

// An AR ruler built for a real demo scenario: a crew member cuts several
// different walls (or a wall and a ceiling) in the same room, each a
// different height or a different scenario entirely - a one-foot flood
// cut here, a six-foot removal there, a full wall somewhere else, and not
// all of it the same material (carpet here, tile there). So every
// measurement starts with "what are you measuring?" from that section's
// own material list, then the tap-to-tap distance, then - for a section
// where it applies - "does this include insulation too?" so a second
// identical measurement is never needed. "Guardar y Seguir" banks the
// current measurement and starts the next one right where the crew is,
// with a running tally on screen. "Terminar" ends the session and hands
// every banked measurement back at once, so the app can drop each one
// into its own row automatically.
//
// UI text here is Spanish-only on purpose, unlike the rest of the app -
// this screen gets read in a glance while holding the phone up with both
// hands. PDF exports elsewhere stay English-only, untouched.
// LA BOLITA QUE SE MUEVE CUANDO LE HABLAN.
//
// Su pedido: "en vez de ser solo un micrófono, tiene que ser como una bolita
// que se mueve como Siri a la hora que le hablan".
//
// Y no es adorno. Es la señal que faltaba: hasta ahora, si el no le entendia,
// la app se quedaba callada y el no tenia forma de distinguir tres cosas muy
// distintas - que no lo oyo, que lo oyo y no entendio, o que el microfono se
// cayo. La bolita contesta la primera de un vistazo: si se mueve, lo esta
// oyendo.
//
// Se dibuja con anillos concentricos que crecen con el volumen de VERDAD (el
// mismo RMS que ya se mide en el microfono), no con una animacion inventada
// que se mueve sola.
final class OrbitaVoz: UIView {
    enum Estado { case escuchando, pensando, caido, apagado }
    var estado: Estado = .escuchando { didSet { setNeedsDisplay() } }

    // 0 a 1. Se suaviza al entrar para que no tiemble con cada silaba.
    private var nivel: CGFloat = 0
    private var fase: CGFloat = 0

    func actualizar(nivel n: CGFloat) {
        // Sube rapido y baja despacio: asi se siente viva, como Siri. Bajar
        // igual de rapido la haria parpadear en cada pausa entre palabras.
        let objetivo = min(max(n, 0), 1)
        nivel += (objetivo - nivel) * (objetivo > nivel ? 0.45 : 0.08)
        fase += 0.06
        setNeedsDisplay()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isOpaque = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    private func colores() -> [UIColor] {
        switch estado {
        case .escuchando: return [UIColor.systemBlue, UIColor.systemTeal, UIColor.systemIndigo]
        case .pensando:   return [UIColor.systemPurple, UIColor.systemPink, UIColor.systemIndigo]
        case .caido:      return [UIColor.systemRed, UIColor.systemOrange, UIColor.systemRed]
        case .apagado:    return [UIColor.gray, UIColor.darkGray, UIColor.gray]
        }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let centro = CGPoint(x: rect.midX, y: rect.midY)
        let base = min(rect.width, rect.height) / 2 - 3
        let cols = colores()

        // Tres anillos desfasados: cada uno respira a su propio tiempo, y el
        // volumen los empuja a los tres. De ahi sale el movimiento organico.
        for (i, c) in cols.enumerated() {
            let desfase = fase + CGFloat(i) * 2.1
            let respira = 0.06 * sin(desfase)
            let empuje: CGFloat = (estado == .escuchando || estado == .pensando) ? nivel * 0.38 : 0
            let r = base * (0.56 + respira + empuje - CGFloat(i) * 0.07)
            guard r > 1 else { continue }
            ctx.setFillColor(c.withAlphaComponent(0.38).cgColor)
            ctx.fillEllipse(in: CGRect(x: centro.x - r, y: centro.y - r, width: r*2, height: r*2))
        }
        // El nucleo, siempre visible: aunque este callado, se ve que ahi esta.
        let rn = base * (0.30 + nivel * 0.18)
        ctx.setFillColor(cols[0].withAlphaComponent(0.95).cgColor)
        ctx.fillEllipse(in: CGRect(x: centro.x - rn, y: centro.y - rn, width: rn*2, height: rn*2))

        if estado == .caido || estado == .apagado {
            // Una barra cruzada: sin sonido no hay movimiento, asi que el
            // estado tiene que verse con la bolita quieta.
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(2.5)
            ctx.move(to: CGPoint(x: centro.x - base*0.45, y: centro.y - base*0.45))
            ctx.addLine(to: CGPoint(x: centro.x + base*0.45, y: centro.y + base*0.45))
            ctx.strokePath()
        }
    }
}

class ARMeasureViewController: UIViewController, ARSessionDelegate, UIPickerViewDataSource, UIPickerViewDelegate, AVSpeechSynthesizerDelegate {

    var onFinish: ((ARMeasureOutcome) -> Void)?
    // Set by the plugin before presenting, from the section the crew tapped
    // the camera button from - each option already carries its own
    // companion info (or none), so the "does this include X too?" question
    // is decided by whichever material actually gets picked below, not by
    // the section as a whole.
    var materials: [ARMaterialOption] = []
    // De que tarjeta vino: "floor", "wall", "ceiling", "kitchen". El
    // asistente lo usa para avisar cuando la camara esta viendo una cosa y
    // la medida es de otra - el error mas caro y mas facil de cometer aqui.
    var section: String = ""
    // De quien es la voz que la va a usar, para hablarle por su nombre.
    var crewName: String = ""
    // De que cuarto es esta tarjeta, y cuanto mide ese cuarto en el plano ya
    // escaneado. `roomAreaSqFt == 0` significa "no hay con que comparar" -
    // nunca "el cuarto mide cero".
    var roomName: String = ""
    var roomAreaSqFt: Double = 0

    // ============ EL RECORRIDO: UNA CASA SIN SALIR DE LA CAMARA ============
    //
    // Su reporte despues de un dia midiendo: "es muy complicado que cada vez en
    // cada cuarto nos vuelva a pedir otra vez en que nivel estoy".
    //
    // La causa no era un descuido, era la forma: `section`, `materials`,
    // `roomName` y `roomAreaSqFt` llegaban del formulario y NUNCA se volvian a
    // escribir, asi que para cambiar de cuarto o de seccion no habia mas
    // remedio que cerrar la camara y empezar de cero.
    //
    // Ahora hay DOS modos:
    //   "unaSeccion" - lo de siempre, tal cual. Se abre desde el boton de una
    //                  tarjeta y mide esa seccion de ese cuarto. Intacto a
    //                  proposito: si el recorrido falla en el campo, la
    //                  cuadrilla no se queda sin nada.
    //   "recorrido"  - se abre una vez y no se cierra: nivel, cuarto, seccion,
    //                  material, mide, y vuelta a empezar por donde toque.
    var modo: String = "unaSeccion"
    var esRecorrido: Bool { return modo == "recorrido" }

    // Los catalogos completos, para poder cambiar sin preguntarle al formulario.
    var seccionesDisponibles: [String: [ARMaterialOption]] = [:]
    var cuartosDisponibles: [String] = []
    // LOS CUARTOS Y LAS AREAS DE CADA PLANTA, del plano de esta casa.
    //
    // `cuartosDisponibles` se fijaba UNA sola vez al abrir la camara y nunca se
    // recalculaba. En un recorrido de varios niveles eso significaba que al
    // subir al tercer piso le seguian ofreciendo los cuartos del segundo: los
    // del piso nuevo no aparecian en ninguna posicion, y los del viejo salian
    // en el primer renglon estando parado en otro sitio.
    var cuartosPorPlanta: [String: [String]] = [:]
    var areasPorPlanta: [String: [String: Double]] = [:]
    // Lo que mando la web al abrir, para volver a ello cuando una planta no
    // tenga lista propia.
    private var cuartosDeArranque: [String] = []

    // Cambiar la lista de cuartos a la de ESTA planta. Se llama en cada sitio
    // donde cambia el nivel, que son tres: la pastilla, la voz, y el asistente.
    private func ponerCuartosDeLaPlanta(_ planta: String) {
        if let propios = cuartosPorPlanta[planta], !propios.isEmpty {
            // Los del plano de esa planta primero, y detras lo que vino al
            // abrir: el escaner pudo no ver un closet, y quedarse sin el seria
            // peor que ofrecer uno de mas.
            var lista = propios
            for c in cuartosDeArranque where !lista.contains(c) { lista.append(c) }
            cuartosDisponibles = lista
        } else if !cuartosDeArranque.isEmpty {
            cuartosDisponibles = cuartosDeArranque
        }
        // Y las areas de esa planta, para que el candado de "no cabe" compare
        // contra el cuarto de ESTE piso y no contra su homonimo de otro.
        if let propias = areasPorPlanta[planta] { areasPorCuarto = propias }
    }
    var nivelesDisponibles: [String] = []
    // Cuanto mide cada cuarto en el plano ya escaneado. El telefono no puede
    // calcularlo (eso vive en la web, sobre el plano de LiDAR), asi que llega
    // hecho y aqui solo se consulta al cambiar de cuarto.
    var areasPorCuarto: [String: Double] = [:]
    // El nivel se pregunta UNA vez por recorrido. Eso es todo el punto.
    var nivelActual: String = ""
    // "nivel" = un piso completo, cuarto por cuarto. "cuarto" = solo este.
    var alcance: String = "nivel"
    var esSoloUnCuarto: Bool { return alcance == "cuarto" }

    // ============ EL ASISTENTE QUE HABLA ============
    //
    // Su reporte: "las personas que estan usando la aplicacion no saben como
    // usarla... no saben como medir". Y esta pantalla tenia la explicacion
    // ESCRITA, de ocho pasos, escondida detras de un boton "?" que nunca se
    // abria sola. Alguien que no sabe usar la app no toca un boton de ayuda
    // que no sabe que existe, y si lo toca, esta sosteniendo el telefono con
    // las dos manos apuntando a una pared: no esta para ponerse a leer.
    //
    // Asi que la pantalla ahora HABLA. Cada instruccion que ya aparecia
    // escrita se dice tambien en voz alta, y solo cuando CAMBIA - repetir lo
    // mismo cada segundo enseña a ignorar la voz.
    private let speech = AVSpeechSynthesizer()

    // ============ POR QUE SE REHIZO ESTA CAPA ============
    //
    // Sus dos quejas, y las dos tenian la misma raiz:
    //   "el voice command repite mucho lo mismo"
    //   "el voice command esta atrasado"
    //
    // ATRASADO: AVSpeechSynthesizer ENCOLA. La version anterior soltaba
    // frases desde cinco lugares distintos (cada cambio de instruccion, la
    // superficie que veia la camara, la regla del material, la guia por
    // esquinas, el compañero). Se juntaban en fila y se oian una tras otra,
    // asi que para cuando sonaba la tercera el ya iba dos pasos adelante.
    // AHORA NADA SE ENCOLA: lo nuevo INTERRUMPE a lo viejo. Lo que se oye es
    // siempre lo de este momento, no lo de hace veinte segundos.
    //
    // REPITE: la version anterior narraba instructionLabel en cada
    // updateUI(), y updateUI() corre en cada toque, cada deshacer, cada
    // casilla. El guardia solo evitaba decir lo MISMO dos veces seguidas, asi
    // que ir y venir entre dos estados lo repetia sin fin. AHORA cada cosa
    // tiene una LLAVE y se dice UNA VEZ por medida. Y la narracion continua
    // de "veo que esta midiendo una pared" se elimino entera: era lo mas
    // repetitivo de todo y no le decia nada que no viera con sus ojos. De
    // eso solo sobrevive el aviso de que esta apuntando al lugar equivocado,
    // que si es accionable.
    private enum Prioridad: Int { case guia = 1, aviso = 2 }
    // Lo ya dicho en ESTA medida. Se vacia al empezar una medida nueva.
    private var yaDicho: Set<String> = []
    private var prioridadEnCurso: Prioridad?
    private var llaveEnCurso: String?
    private var ultimoDicho = ""
    private var nivelDeEstaFrase: Float = 0
    private var hizoAlgo = false
    // EL DUEÑO DE LA CASA LE HABLA A MEDIA MEDIDA, y eso pasa en cada trabajo.
    // Antes no habia forma de decirle "espera": o lo callaba con el boton - y
    // entonces tampoco oia - o el asistente seguia preguntando encima de la
    // conversacion. En pausa la app se queda CALLADA pero SIGUE OYENDO, porque
    // si dejara de oir no habria como despertarla sin tocar la pantalla.
    // ============ EL COLOR DE "ESCOGIDO" ============
    //
    // Su reporte del 12 de septiembre: "el anaranjado se ve muy mal, el morado
    // en serio se ve muy mal; ponle otro color que contraste con el azul".
    //
    // Un teal de acero: contrasta con el azul del resto de la app sin pelearse
    // con el, y se lee sobre las pastillas oscuras de la camara. El naranja era
    // ademas confuso - es el color de la MARCA y de los botones que mandan, no
    // el de "aqui esta usted".
    //
    // En UN solo lugar: antes estaba escrito `systemOrange` en seis sitios, y
    // seis copias de un color son seis oportunidades de que uno se quede atras.
    static let colorEscogido = UIColor(red: 0.09, green: 0.64, blue: 0.64, alpha: 0.95)
    static let colorPastilla = UIColor.black.withAlphaComponent(0.62)

    private static let yaSaludoIA = "arMedirSaludoIA:v1"
    // El ancho que se le acaba de ofrecer de memoria, esperando su "sí".
    private var anchoOfrecido: Double?

    // ============ APRENDER SUS FRASES ============
    //
    // El momento en que de verdad se aprende algo es este: le dice algo, la app
    // no entiende, y EN SEGUIDA el hace lo que queria - con el dedo o con una
    // orden que si conoce. Esa pareja es la leccion, y antes se tiraba.
    //
    // Ya existia para los MATERIALES desde hace tiempo y funciona. Esto es lo
    // mismo para las ORDENES, que es donde mas se atora: cada cuadrilla le dice
    // distinto a poner una esquina.
    private var fraseSinEntender: (frase: String, cuando: Date)?
    private var reDespachando = false

    // De vuelta: el nombre de la orden -> como se dice para que la entienda.
    private static let fraseCanonica: [String: String] = [
        "marcar": "marca", "deshacer": "deshacer", "medirAncho": "medir ancho",
        "terminarRecorrido": "terminar recorrido", "guardar": "guardar",
        "otroCuarto": "otro cuarto", "cambiarSeccion": "otra seccion",
        "cambiarNivel": "otro nivel", "abrirLista": "lista",
        "cuantoLlevo": "cuanto llevo", "dondeVoy": "donde voy",
        "queMaterial": "que material", "cambiarMaterial": "otro material",
        "otraIgual": "otra igual", "ponerCompanero": "ponle insulacion",
        "quitarCompanero": "quita la insulacion", "esperame": "esperame",
        "queComandos": "que comandos"
    ]

    // Lo hizo con el dedo despues de que la voz fallo: eso es una correccion.
    private func aprendiDelDedo(_ orden: String) {
        guard let sin = fraseSinEntender, Date().timeIntervalSince(sin.cuando) < 25 else { return }
        MemoriaAsistente.aprenderOrden(frase: sin.frase, orden: orden)
        fraseSinEntender = nil
    }
    private var enPausa = false {
        didSet { if enPausa != oldValue { pausaDesde = Date(); actualizarIndicadorMicro() } }
    }
    private var pausaDesde = Date.distantPast

    // `llave` = se dice una sola vez por medida. Sin llave, se dice siempre
    // (para lo que el pide a proposito, como el boton Asistente).
    private func say(_ text: String, _ prioridad: Prioridad = .guia, llave: String? = nil) {
        // En pausa no habla NI SIQUIERA para avisar: el punto entero es no
        // interrumpir la conversacion que esta teniendo con el cliente.
        guard !enPausa || forzarAunqueMudo else { return }
        // SILENCIAR SILENCIA. Su reporte del 12 de septiembre: "a veces cuando
        // uno lo silencia sigue hablando; asegurate que si uno le pone
        // silenciar, se silencie y no siga hablando".
        //
        // Y tenia razon: este guardia dejaba pasar TODOS los avisos
        // (`prioridad == .aviso`) aunque la voz estuviera apagada - y hay
        // treinta sitios que avisan. O sea que el boton bajaba la guia pero la
        // app seguia hablando, que desde afuera es que el boton no sirve.
        //
        // La pausa ya se comportaba asi (el guardia de arriba no perdona ni los
        // avisos); silenciar ahora hace lo mismo.
        if !asistenteHabla && !forzarAunqueMudo {
            // PERO UN AVISO CALLADO NO SE PIERDE: se ve. Silenciar no puede
            // costarle "esa medida no cabe en el cuarto", que es dinero.
            if prioridad == .aviso { mostrarAvisoMudo(text) }
            return
        }
        if let k = llave, yaDicho.contains(k) { return }
        // Nada de colas. Si ya viene algo sonando y esto es igual o mas
        // urgente, se corta y manda lo nuevo; si es menos urgente, se
        // descarta - hablar tarde es peor que no hablar.
        if speech.isSpeaking {
            if let actual = prioridadEnCurso, prioridad.rawValue < actual.rawValue { return }
            speech.stopSpeaking(at: .immediate)
        }
        // LA LLAVE SE GASTA AQUI, NO ANTES. Estaba arriba, antes del descarte
        // por prioridad, y eso borraba la frase para siempre sin haberla
        // dicho nunca: si un aviso estaba sonando cuando tocaba decir "la
        // tablaroca lleva aislamiento atras", esa frase se marcaba como ya
        // dicha y no volvia a salir en toda la medida - justo la linea que el
        // pidio por su nombre, perdida en silencio. Marcar algo como dicho
        // solo tiene sentido despues de decirlo de verdad.
        if let k = llave { yaDicho.insert(k) }
        llaveEnCurso = llave
        prioridadEnCurso = prioridad
        ultimoDicho = text
        // Una sola fuente para la voz y el ritmo de TODA la app (ver
        // VozAsistente). Antes esta pantalla y el escaner escogian cada una
        // por su lado, y podian sonar distinto.
        speech.speak(VozAsistente.frase(text))
    }
    // Un aviso que no se puede DECIR se VE, en rojo y en la misma barra donde
    // van las instrucciones. Se repinta desde el estado al cabo de unos
    // segundos, igual que `flashNoSurfaceWarning` - el estado es lo unico que
    // sigue siendo cierto despues.
    //
    // Cuatro segundos y medio, no uno y medio: esto es una advertencia de
    // dinero, no un "acerquese mas".
    private func mostrarAvisoMudo(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // El aviso de salir llega aqui en la siguiente vuelta: si ya se
            // desarmo (toco otra cosa), no se vuelve a pintar.
            if text.hasPrefix("Ojo: si cancela"), !self.cancelarPendiente { return }
            self.flashGeneracion += 1
            let mia = self.flashGeneracion
            self.instructionLabel.text = "🔇 " + text
            self.instructionLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
                guard let self = self, self.flashGeneracion == mia else { return }
                self.instructionLabel.backgroundColor = Self.colorPastilla
                self.updateUI()
            }
        }
    }

    // ============ LA CASILLA SE VA SOLA, Y VUELVE CON LO NUEVO ============
    //
    // Su pedido del 13 de septiembre: "que despues de darle las indicaciones,
    // desaparezca automaticamente y vuelva a aparecer en esa casilla". Se
    // queda en pantalla el tiempo de leerla (mas larga, mas tiempo) y se
    // desvanece; cuando llega una instruccion NUEVA, vuelve a aparecer.
    //
    // Lo que NO se va solo, porque es dinero o es lo ultimo antes de mandar:
    // el aviso del ancho que falta, el recibo que se lee antes de mandar, y el
    // aviso en rojo de algo que la voz callada no pudo decir. Esos se quedan
    // mientras sigan siendo ciertos; los demas se van.
    //
    // updateUI corre en cada toque y a veces pone un texto y luego otro
    // encima en la misma pasada. Por eso se revisa en la siguiente vuelta del
    // hilo, con el texto que quedo al final: si es el mismo de antes, no se
    // vuelve a mostrar algo que ya se fue.
    private var casillaUltimoTexto: String?
    private var casillaOcultar: DispatchWorkItem?
    private var casillaRevisionPendiente = false

    private func casillaCambio() {
        guard !casillaRevisionPendiente else { return }
        casillaRevisionPendiente = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.casillaRevisionPendiente = false
            self.revisarCasilla()
        }
    }

    private func casillaDebeQuedarse(_ texto: String) -> Bool {
        let limpio: (String?) -> String = { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        if texto.hasPrefix("🔇") { return true }
        if cancelarPendiente, texto.hasPrefix("⚠︎ Si sale ahora") { return true }
        if resumenPendiente, reciboEnPantalla != nil, texto == limpio(reciboEnPantalla) { return true }
        if avisoEnPantalla != nil, texto == limpio(avisoEnPantalla) { return true }
        return false
    }

    static func segundosEnCasilla(_ texto: String) -> Double {
        return min(9, max(4, 1.5 + Double(texto.count) / 14))
    }

    private func revisarCasilla() {
        let texto = (instructionLabel.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if texto.isEmpty {
            casillaOcultar?.cancel(); casillaOcultar = nil
            casillaUltimoTexto = nil
            UIView.animate(withDuration: 0.25) { self.instructionLabel.alpha = 0 }
            return
        }
        if casillaDebeQuedarse(texto) {
            casillaOcultar?.cancel(); casillaOcultar = nil
            casillaUltimoTexto = texto
            UIView.animate(withDuration: 0.2) { self.instructionLabel.alpha = 1 }
            return
        }
        guard texto != casillaUltimoTexto else { return }
        casillaUltimoTexto = texto
        casillaOcultar?.cancel()
        UIView.animate(withDuration: 0.2) { self.instructionLabel.alpha = 1 }
        let item = DispatchWorkItem { [weak self] in
            guard let self = self,
                  (self.instructionLabel.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == texto,
                  !self.casillaDebeQuedarse(texto) else { return }
            UIView.animate(withDuration: 0.35) { self.instructionLabel.alpha = 0 }
        }
        casillaOcultar = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.segundosEnCasilla(texto), execute: item)
    }

    @objc private func recordatorioTocado() { ocultarRecordatorio() }
    private func ocultarRecordatorio() {
        recordatorioOcultar?.cancel()
        recordatorioOcultar = nil
        guard recordatorioLabel.alpha > 0 else { return }
        UIView.animate(withDuration: 0.2) { self.recordatorioLabel.alpha = 0 }
    }

    // Aparece enfrente, se queda lo que tarda en leerse, y se va solo.
    private func mostrarRecordatorio(_ texto: String) {
        recordatorioLabel.text = texto
        // Encima de la camara y de las filas, pero DEBAJO de la ventana de la
        // lista (y por eso de la ayuda y del Asistente, que ya van sobre ella).
        // Subir la lista al frente taparia el boton del Asistente, que se subio
        // a proposito por encima de ella.
        view.insertSubview(recordatorioLabel, belowSubview: materialOverlay)
        recordatorioOcultar?.cancel()
        recordatorioLabel.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: 0.25) {
            self.recordatorioLabel.alpha = 1
            self.recordatorioLabel.transform = .identity
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            UIView.animate(withDuration: 0.4) { self.recordatorioLabel.alpha = 0 }
        }
        recordatorioOcultar = item
        DispatchQueue.main.asyncAfter(deadline: .now() + min(7, max(4, Double(texto.count) / 16)), execute: item)
    }

    // "Recuerde ver si el piso trae underlayment"; en pared o techo, "recuerde
    // si trae insulación, tambien se agrega". Aparte y sin estado, para probarlo.
    static func textoRecordatorioCompanero(seccion: String, companero: String, pastilla: String) -> String {
        let que = companero.lowercased()
        let primero: String
        switch seccion {
        case "floor":            primero = "Recuerde ver si el piso lleva \(que)."
        case "wall", "ceiling":  primero = "Recuerde: si lleva \(que), también se agrega."
        default:                 primero = "Recuerde ver si lleva \(que)."
        }
        // Espacio que no se parte: "«+" en un renglon y "Underlayment»" en otro
        // no se lee como el nombre de un boton.
        let nombre = pastilla.replacingOccurrences(of: "+ ", with: "+\u{00A0}")
        return primero + "\nSi lo lleva, toque «\(nombre)» abajo."
    }

    // Solo para el boton Asistente y el "?": el pidio oir algo, se le dice
    // aunque tenga el automatico apagado.
    private var forzarAunqueMudo = false
    private func decirPorPeticion(_ text: String) {
        forzarAunqueMudo = true
        say(text, .aviso)
        forzarAunqueMudo = false
    }
    // Si una frase se corta a la mitad, su llave se DEVUELVE. Sin esto, una
    // frase interrumpida quedaba marcada como ya dicha aunque el tecnico solo
    // hubiera oido el principio - y la mitad accionable ("marque la casilla")
    // no volvia a salir en toda la medida.
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        dejoDeHablar = Date()
        if let k = llaveEnCurso { yaDicho.remove(k) }
        llaveEnCurso = nil
        prioridadEnCurso = nil
        // Aunque se haya cortado, la pregunta se abre: si se corto fue porque
        // algo mas urgente hablo encima, no porque el dejara de necesitar
        // contestarla - y dejarla cerrada lo dejaria hablandole a nadie.
        if let p = pasoPorArmar { pasoAbierto = p; pasoPorArmar = nil }
    }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        dejoDeHablar = Date()
        llaveEnCurso = nil
        prioridadEnCurso = nil
        // La pregunta queda abierta justo cuando se acabo de decir.
        if let p = pasoPorArmar { pasoAbierto = p; pasoPorArmar = nil }
    }

    private func medidaNueva() {
        yaDicho.removeAll()
        avisoEnPantalla = nil
    }

    // El automatico: se guarda por telefono. Encendido de fabrica, porque el
    // problema original era justamente que nadie encontraba la ayuda.
    private static let asistenteKey = "arMeasureAsistenteHabla:v1"
    private var asistenteHabla = true {
        didSet {
            UserDefaults.standard.set(asistenteHabla, forKey: Self.asistenteKey)
            muteButton.setImage(UIImage(systemName: asistenteHabla ? "speaker.wave.2.fill" : "speaker.slash.fill"), for: .normal)
            muteButton.backgroundColor = asistenteHabla
                ? Self.colorPastilla
                : UIColor.systemRed.withAlphaComponent(0.75)
        }
    }

    // ============ ESCUCHAR ============
    //
    // Su pedido, repetido de cuatro maneras: que no haya que tocar la
    // pantalla. Sostiene el telefono con las dos manos apuntando a una
    // esquina; soltar una mano para tocar "+" es justo cuando se mueve.
    //
    // DIFERENCIA IMPORTANTE CON EL ESCANER DE PLANOS: alla el microfono
    // escucha texto libre (el nombre del cuarto), y por eso necesito tres
    // defensas contra la platica ajena. Aqui NO. Aqui solo existen ocho
    // ordenes cerradas: nada que no sea una de ellas se ignora sin mas. Una
    // voz ajena no puede inventar una medida, y lo peor que puede pasar -
    // marcar una esquina de mas - se deshace con Deshacer.
    private let reconocedor = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))

    // ============ LOS DOS IDIOMAS A LA VEZ ============
    //
    // Su reporte: "tiene que entender cuando hablo en español o cuando hablo
    // en inglés, porque tablaroca casi no lo usan, usan más drywall... tiene
    // que entender el inglés hispano".
    //
    // Tenia razon y era un techo de raiz: el reconocedor estaba puesto SOLO en
    // es-MX. A un reconocedor español, "drywall" le suena a sonidos españoles y
    // lo escribe como puede - "drai wol", "trigual", "dry gual" - que no casa
    // con nada. No era que la app no conociera la palabra: es que nunca le
    // llegaba la palabra.
    //
    // Ahora corren DOS a la vez sobre el MISMO audio: el de siempre en español
    // y uno en ingles. El español manda - la app habla español y ahi estan las
    // ordenes - y el ingles entra solo cuando el español no entendio nada. Asi
    // no hay forma de que una frase haga dos cosas.
    private let reconocedorIngles = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var tareaIngles: SFSpeechRecognitionTask?
    private var peticionIngles: SFSpeechAudioBufferRecognitionRequest?
    private var ultimoIngles = ""
    private var yaAtendidoIngles = ""
    private var ultimoAtenderHizoAlgo = false
    private var motorAudio: AVAudioEngine?
    private var peticionVoz: SFSpeechAudioBufferRecognitionRequest?
    private var tareaVoz: SFSpeechRecognitionTask?
    private var reinicioVoz: Timer?
    private var escuchando = false
    // Pico de volumen desde la ultima frase atendida (ver el tap del micro).
    private var picoDesdeElUltimo: Float = 0
    // Cuando el telefono TERMINO de hablar. El microfono se ignora un momento
    // despues, no solo mientras habla.
    private var dejoDeHablar = Date.distantPast

    // ¿Esto que entro por el microfono es la app oyendose a si misma?
    //
    // No se adivina por el reloj: se compara con lo que la app ACABA de decir.
    // El eco siempre es un pedazo de su propia frase; lo que el contesta casi
    // nunca lo es.
    private func suenaASuPropioEco(_ oido: String) -> Bool {
        guard !ultimoDicho.isEmpty else { return false }
        func pelar(_ x: String) -> String {
            return x.lowercased()
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        let dicho = pelar(ultimoDicho)
        let oyo = pelar(oido)
        guard !oyo.isEmpty else { return false }
        // Un "sí" o un "no" NUNCA se tiran por eco. Son las respuestas mas
        // comunes que existen y ademas salen dentro de frases que la app dice
        // ("toque sí, mandar"), asi que compararlas daria falsos positivos
        // justo en la palabra que mas se usa. Para esas dos, el unico filtro
        // es el rabito de audio del principio.
        // Y SOLO SI ES CORTO. `esSi` reconoce por principio de frase, asi que
        // el eco de "Ok. Apunte a la primera esquina y diga marca" empieza con
        // "ok" y se colaba por esta puerta como si fuera un "sí" - o sea, la
        // frase entera de la app se libraba del filtro. Una respuesta de si o
        // no son una o dos palabras, nunca nueve.
        if oyo.split(separator: " ").count <= 3,
           VozAsistente.esSi(oido) || VozAsistente.esNo(oido) {
            return Date().timeIntervalSince(dejoDeHablar) < 0.35
        }
        // Palabra por palabra: si casi todo lo que oyo estaba en lo que dijo,
        // es el eco. Una palabra suelta que la app acaba de decir ("marca",
        // "insulacion") tambien cuenta - asi era como se marcaba solo.
        let palabras = oyo.split(separator: " ").map(String.init)
        let suyas = palabras.filter { dicho.contains($0) }.count
        return Double(suyas) >= Double(palabras.count) * 0.8
    }

    private func pedirPermisoYEscuchar() {
        SFSpeechRecognizer.requestAuthorization { [weak self] estado in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard estado == .authorized else { self.sinVoz(); return }
                AVAudioSession.sharedInstance().requestRecordPermission { ok in
                    DispatchQueue.main.async {
                        guard ok else { self.sinVoz(); return }
                        // ============ "SE TRABA AL ABRIR LA CAMARA" ============
                        //
                        // Su reporte. Y al abrir estaban arrancando A LA VEZ, y
                        // todo en el hilo que dibuja: ARKit, la sesion de
                        // audio, el motor de audio, el procesamiento de voz de
                        // Apple (que reconstruye la unidad de entrada entera) y
                        // DOS reconocedores de voz. Cualquiera de esos tarda
                        // decimas; todos juntos y encima del arranque de ARKit
                        // congelan la pantalla.
                        //
                        // Se le da medio segundo a ARKit para que agarre su
                        // primer cuadro y quede dibujando solo. Se pierde medio
                        // segundo de escucha - y en ese medio segundo el
                        // tecnico todavia esta levantando el telefono.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.empezarAEscuchar()
                        }
                    }
                }
            }
        }
    }

    // Sin microfono no hay conversacion, asi que la lista TIENE que salir: de
    // otro modo se quedaria con la camara limpia, sin pregunta y sin lista, o
    // sea sin ninguna forma de escoger el material.
    private func sinVoz() {
        micDot.isHidden = true
        guard stage == .pickingMaterial else { return }
        listaVisible = true
        updateUI()
    }

    // Una fila propia para el audio. Prender el procesamiento de voz y arrancar
    // el motor son operaciones LENTAS - reconstruyen la unidad de entrada del
    // sistema - y hacerlas en el hilo que dibuja es congelar la camara.
    private let filaAudio = DispatchQueue(label: "armedir.audio", qos: .userInitiated)

    private func empezarAEscuchar() {
        guard let rec = reconocedor, rec.isAvailable, motorAudio == nil, !arrancandoAudio else { return }
        arrancandoAudio = true
        filaAudio.async { [weak self] in
            guard let self = self else { return }
            let listo = self.armarMotorDeAudio()
            DispatchQueue.main.async {
                self.arrancandoAudio = false
                guard listo else { return }
                self.terminarDeArrancarLaEscucha()
            }
        }
    }
    private var arrancandoAudio = false
    private var reintentosDeFormato = 0
    private var camaraDesde = Date()

    // Lo pesado, en la fila de audio. Devuelve si quedo andando.
    private func armarMotorDeAudio() -> Bool {
        let motor = AVAudioEngine()
        let entrada = motor.inputNode

        // ============ REDUCCION DE RUIDO DE VERDAD ============
        //
        // Su pedido, repetido: "que haga noise reduction, que se concentre
        // cuando el tecnico habla, evitando los sonidos de alrededor para que
        // no se confunda".
        //
        // `.voiceChat` en la sesion de audio ayuda, pero ESTO es el interruptor
        // que de verdad manda: prende la unidad de procesamiento de voz de
        // Apple SOBRE LA ENTRADA del motor. Es la misma que usa una llamada
        // telefonica: cancela el eco de la bocina y baja el ruido constante de
        // fondo - que en una casa en secado son tres ventiladores y un
        // deshumidificador andando sin parar, justo el tipo de ruido parejo que
        // esto esta hecho para descontar.
        //
        // Va ANTES de leer el formato: prenderlo CAMBIA el formato de entrada,
        // y poner el tap con el formato viejo tira el motor al arrancar.
        //
        // Si el telefono no puede, sigue todo igual que antes - no se cae nada.
        try? entrada.setVoiceProcessingEnabled(true)
        let formato = entrada.outputFormat(forBus: 0)
        // ============ OTRO CIERRE EN SECO, Y ESTE LO ABRI YO ============
        //
        // `installTap` con un formato invalido - cero canales o cero hertz -
        // LANZA UNA EXCEPCION de ObjC, y eso cierra la app en seco. El formato
        // sale invalido cuando la sesion de audio todavia no esta activa: otra
        // app tiene el microfono, una llamada entrando, el telefono acabando de
        // despertar.
        //
        // Antes esto no podia pasar porque `setActive` corria en el MISMO hilo,
        // justo antes. En el build EN lo mandé a una fila de fondo para que la
        // camara no se trabara al abrir - y con eso abri la puerta a que el
        // formato se lea antes de que la sesion este lista.
        //
        // Ahora se revisa y se reintenta. Sin microfono la app sigue viva y con
        // la lista a mano, que es como funcionaba antes de tener voz.
        guard formato.channelCount > 0, formato.sampleRate > 0 else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if self.reintentosDeFormato < 3 {
                    self.reintentosDeFormato += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.empezarAEscuchar() }
                } else {
                    self.sinVoz()
                }
            }
            return false
        }
        entrada.installTap(onBus: 0, bufferSize: 1024, format: formato) { [weak self] buffer, _ in
            guard let self = self else { return }
            // Mientras el telefono habla, el microfono se ignora. Sin esto la
            // app se oye a si misma decir "toque Terminar Recorrido" y lo
            // ejecuta - se daria ordenes sola.
            guard !self.speech.isSpeaking else { return }
            self.peticionVoz?.append(buffer)
            // El MISMO pedacito de audio a los dos reconocedores. Un solo
            // microfono, dos transcripciones - no hay dos grabaciones ni dos
            // tomas, asi que no se pueden desincronizar.
            self.peticionIngles?.append(buffer)
            // Que tan fuerte entro este pedacito. Se guarda el PICO desde la
            // ultima frase atendida: una frase se juzga por su parte mas
            // fuerte, porque el promedio lo hunde el silencio entre palabras.
            guard let ch = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            var suma: Float = 0
            for i in 0..<n { let v = ch[i]; suma += v*v }
            let rms = (suma / Float(n)).squareRoot()
            if rms > self.picoDesdeElUltimo { self.picoDesdeElUltimo = rms }
            self.nivelVivo = rms
        }
        motor.prepare()
        do { try motor.start() } catch { entrada.removeTap(onBus: 0); return false }
        // El motor queda andando; lo que toca pantalla se hace en el hilo
        // principal, en la funcion de abajo.
        DispatchQueue.main.async { self.motorAudio = motor }
        return true
    }

    // Lo ligero, en el hilo principal: estado, reconocedores y pantalla.
    private func terminarDeArrancarLaEscucha() {
        escuchando = true
        ultimaSeñalDeVoz = Date()
        reiniciarTareaVoz()
        arrancarVigilante()
        actualizarIndicadorMicro()
        // Si el telefono PUEDE traer la inteligencia pero esta apagada, se
        // dice una vez. Callarlo lo dejaria creyendo que la app no da para
        // mas, cuando lo que falta es un interruptor de Ajustes.
        if !AsistenteIA.disponible, let porque = AsistenteIA.porQueNo {
            say(porque, .guia, llave: "ia-apagada")
        }
        // Que se entere de que existe. Una funcion que nadie sabe que esta
        // ahi es una funcion que no existe - fue el problema de la ayuda.
        // Con la voz callada no se anuncia al asistente en la casilla (su
        // pedido del 13 de septiembre: "si uno le hace silencio, lo que el
        // asistente de voz dice ya no aparece ahi").
        if asistenteHabla {
            instructionLabel.text = "🎤 Ya me puede hablar — diga \"marca\", \"ancho\", \"guardar\", o \"ayuda\""
        }
        // Una sola frase, con el saludo adentro. Antes eran dos: el saludo
        // arrancaba y medio segundo despues esta lo cortaba a la mitad, asi
        // que el tecnico nunca oia su nombre ni de que cuarto era la tarjeta.
        var frase = ""
        if !crewName.isEmpty { frase += "Listo, \(crewName). " }
        // Solo la PRIMERA vez que abre la camara con la inteligencia prendida:
        // repetirselo en cada medida seria el tipo de frase que termina
        // apagando el asistente.
        if AsistenteIA.disponible, !UserDefaults.standard.bool(forKey: Self.yaSaludoIA) {
            UserDefaults.standard.set(true, forKey: Self.yaSaludoIA)
            frase += "Ya me puede hablar normal, no solo con órdenes: pregúnteme lo que sea. "
        }
        if !roomName.isEmpty { frase += "\(Self.sectionSpokenName(section).capitalized) de \(roomName). " }
        // LA PREGUNTA QUE FALTABA. El codigo para CONTESTARLA ya estaba, pero
        // nada la abria nunca - por eso la lista se quedaba enfrente esperando
        // un dedo, y hablarle solo sacaba "primero cierre lo que tiene
        // abierto". Decir "laminado" es un segundo; buscarlo entre once
        // opciones con guantes puestos es mucho mas.
        // Pintar los botones de seccion desde el arranque: si esperan al primer
        // cambio, no se ven justo cuando mas se necesitan - al empezar.
        actualizarTiraDeEstado()
        if esRecorrido {
            // EL NIVEL YA SE ESCOGIO EN LA PANTALLA, con el dedo, antes de
            // abrir. Preguntarlo aqui hablando era un paso de mas para un dato
            // que no cambia en todo el recorrido - y si no le entendia esa
            // primera respuesta, lo dejaba atorado antes de empezar.
            if !nivelActual.isEmpty { frase += "\(nivelActual). " }
            if !roomName.isEmpty {
                // "Medir un cuarto": tambien trae el cuarto resuelto.
                preguntar(.queSeccion, frase + "\(roomName). ¿Piso, pared, techo, cocina, baño o materiales?")
            } else if nivelActual.isEmpty {
                preguntar(.queNivel, frase + "¿En qué nivel estamos?")
            } else {
                preguntar(.queCuarto, preguntaDeCuarto(frase))
            }
        } else if stage == .pickingMaterial, !materials.isEmpty {
            preguntar(.queMide, frase + "¿Qué va a medir?")
        } else {
            frase += "Ya me puede hablar: diga marca para poner una esquina."
            say(frase, .guia, llave: "escucho")
        }
    }

    // El reconocedor de Apple corta solo despues de un rato, y su
    // transcripcion es ACUMULATIVA: cada frase llega pegada a todo lo dicho
    // antes en esa tarea. Por eso se reinicia cada 40 s y solo se atiende la
    // parte NUEVA - si no, "guardar" seguido de "terminar" llegaria como
    // "guardar terminar" y volveria a disparar lo de antes.
    // El reconocedor de ingles: se alimenta del mismo audio, NO despacha por su
    // cuenta y solo guarda lo ultimo que oyo. Quien decide es el de español.
    //
    // No tiene temporizador de silencio propio a proposito: si los dos
    // despacharan por su lado, una misma frase podria hacer dos cosas - marcar
    // dos esquinas, guardar dos veces. Uno manda y el otro solo aconseja.
    private func arrancarIngles() {
        tareaIngles?.cancel(); tareaIngles = nil
        // EL ORDEN IMPORTA Y CIERRA LA APP SI SE INVIERTE.
        //
        // El tap del microfono corre en el hilo del AUDIO y hace
        // `self.peticionIngles?.append(buffer)` sesenta veces por segundo.
        // Apple LANZA UNA EXCEPCION si se le agrega audio a una peticion a la
        // que ya se le llamo `endAudio()` - y una excepcion de ObjC en el hilo
        // del audio no se puede atrapar: la app se cierra en seco, sin aviso.
        //
        // Yo lo tenia al reves (`endAudio()` y despues `= nil`), y en el
        // hueco entre las dos lineas el tap podia colarse con un buffer. Un
        // hueco de microsegundos, sesenta oportunidades por segundo.
        //
        // Se pone en nil PRIMERO: cuando se llame `endAudio()`, el tap ya no
        // tiene a quien agregarle nada.
        let inglesVieja = peticionIngles
        peticionIngles = nil
        inglesVieja?.endAudio()
        ultimoIngles = ""; yaAtendidoIngles = ""
        guard let ri = reconocedorIngles, ri.isAvailable else { return }
        let p = SFSpeechAudioBufferRecognitionRequest()
        p.shouldReportPartialResults = true
        // En el telefono, igual que el de español: sin señal en una casa
        // inundada, y sin agotar el limite del servidor de Apple.
        p.requiresOnDeviceRecognition = ri.supportsOnDeviceRecognition
        peticionIngles = p
        tareaIngles = ri.recognitionTask(with: p) { [weak self] r, error in
            // Si el de ingles falla NO se hace nada: es el ayudante, no el
            // titular. La app sigue igual de bien que antes de que existiera.
            guard error == nil, let r = r else { return }
            DispatchQueue.main.async { self?.ultimoIngles = r.bestTranscription.formattedString }
        }
    }

    // Lo que oyo el de ingles, cuando el de español no entendio nada.
    private func probarEnIngles() {
        // La primera vez que hace falta, se enciende. De ahi en adelante ya
        // esta corriendo sobre el mismo audio.
        if tareaIngles == nil { arrancarIngles(); return }
        let texto = ultimoIngles
        guard texto != yaAtendidoIngles, !texto.isEmpty else { return }
        let nuevo = texto.hasPrefix(yaAtendidoIngles)
            ? String(texto.dropFirst(yaAtendidoIngles.count))
            : texto
        yaAtendidoIngles = texto
        let limpio = nuevo.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return }
        // El mismo candado del eco: la app tambien se oye a si misma aqui.
        if Date().timeIntervalSince(dejoDeHablar) < 1.2, suenaASuPropioEco(limpio) { return }
        atenderOrden(limpio)
    }

    private func reiniciarTareaVoz() {
        guard let rec = reconocedor, motorAudio != nil else { return }
        tareaVoz?.cancel(); tareaVoz = nil
        // Si el de ingles ya venia andando, se rearma con el nuevo audio; si
        // nunca se necesito, se queda apagado y no cuesta nada.
        let inglesAndaba = tareaIngles != nil
        tareaIngles?.cancel(); tareaIngles = nil
        // EL ORDEN IMPORTA Y CIERRA LA APP SI SE INVIERTE.
        //
        // El tap del microfono corre en el hilo del AUDIO y hace
        // `self.peticionIngles?.append(buffer)` sesenta veces por segundo.
        // Apple LANZA UNA EXCEPCION si se le agrega audio a una peticion a la
        // que ya se le llamo `endAudio()` - y una excepcion de ObjC en el hilo
        // del audio no se puede atrapar: la app se cierra en seco, sin aviso.
        //
        // Yo lo tenia al reves (`endAudio()` y despues `= nil`), y en el
        // hueco entre las dos lineas el tap podia colarse con un buffer. Un
        // hueco de microsegundos, sesenta oportunidades por segundo.
        //
        // Se pone en nil PRIMERO: cuando se llame `endAudio()`, el tap ya no
        // tiene a quien agregarle nada.
        let inglesVieja = peticionIngles
        peticionIngles = nil
        inglesVieja?.endAudio()
        defer { if inglesAndaba { arrancarIngles() } }
        reinicioVoz?.invalidate()
        let peticion = SFSpeechAudioBufferRecognitionRequest()
        peticion.shouldReportPartialResults = true
        // EN EL TELEFONO, NO EN EL SERVIDOR. Esta es la causa mas probable de
        // "se traba y ya no escucha":
        //   - El reconocedor de servidor de Apple tiene LIMITE. Una sesion que
        //     lo reabre cada 40 segundos durante un trabajo entero lo agota, y
        //     cuando lo agota deja de contestar - en silencio.
        //   - Y una casa inundada muchas veces no tiene señal. Sin internet,
        //     el de servidor simplemente no existe.
        // El vocabulario de esta pantalla son nueve ordenes y veinte
        // materiales: el modelo del telefono lo hace de sobra.
        peticion.requiresOnDeviceRecognition = rec.supportsOnDeviceRecognition
        peticionVoz = peticion
        // EL DE INGLES NO ARRANCA AQUI. Montar un segundo reconocedor al mismo
        // tiempo que el primero, encima del arranque de ARKit, era parte de lo
        // que trababa la camara al abrir - y ademas casi nunca hace falta en la
        // primera frase. Se enciende solo cuando el de español no entienda algo
        // (ver `probarEnIngles`), que es exactamente cuando sirve.
        var yaAtendido = ""
        var ultimoTexto = ""
        var esperaSilencio: Timer?
        // ESPERAR A QUE TERMINE LA FRASE, no atender cada pedacito.
        //
        // Sin esto, "terminar recorrido" llegaba primero como "Terminar" a
        // secas - el reconocedor entrega hipotesis palabra por palabra - y esa
        // sola palabra caia en la rama de TERMINAR LA SESION. Toda la defensa
        // de orden ("terminar recorrido" se revisa antes que "terminar") no
        // servia de nada, porque nunca llegaban juntas. Peor: repetir la orden
        // tres veces mandaba una pared sin ancho y cerraba la pantalla.
        //
        // Un segundo de silencio = "eso fue una frase". El escaner de planos
        // ya usaba exactamente esta espera, por exactamente esta razon.
        let despachar: () -> Void = { [weak self] in
            guard let self = self else { return }
            let texto = ultimoTexto
            guard texto != yaAtendido, !texto.isEmpty else { return }
            let nuevo = texto.hasPrefix(yaAtendido)
                ? String(texto.dropFirst(yaAtendido.count))
                : texto
            yaAtendido = texto
            let limpio = nuevo.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let nivel = self.picoDesdeElUltimo
            self.picoDesdeElUltimo = 0
            guard !limpio.isEmpty else { return }
            // ============ "LE HABLO DOS VECES Y NO ENTIENDE" ============
            //
            // Su reporte, y la causa estaba aqui mismo, tres lineas arriba.
            //
            // La app DICE en voz alta "diga marca" y esa palabra, saliendo de
            // su propia bocina, se le vuelve a meter por el microfono. Contra
            // eso habia una compuerta boba: tirar TODO lo que entrara en el
            // primer segundo despues de hablar.
            //
            // Pero la frase ya se habia marcado como atendida ARRIBA. O sea
            // que lo que caia en ese segundo no se posponia: SE PERDIA, y
            // como la transcripcion es acumulativa, no habia segunda
            // oportunidad. Y ese segundo muerto cae justo donde mas duele:
            // LA APP ACABA DE PREGUNTARLE ALGO. El contesta de inmediato -
            // que es lo normal - y su respuesta se la traga la compuerta.
            // Tenia que decir todo dos veces, y no por el ruido de la casa
            // sino por esto.
            //
            // LA COMPUERTA AHORA MIRA QUE SE DIJO, NO CUANDO. La app sabe
            // exactamente lo que acaba de decir: si lo que entra es un pedazo
            // de eso, es su propio eco y se tira. Si es otra cosa, es EL, y
            // pasa aunque hayan pasado dos milisegundos.
            if Date().timeIntervalSince(self.dejoDeHablar) < 1.2, self.suenaASuPropioEco(limpio) { return }
            // ¿Vino de lejos? Entonces no fue el que trae el telefono. No es
            // reconocer la voz - es reconocer la distancia (ver VozAsistente).
            if VozAsistente.vieneDeLejos(nivel: nivel,
                                         suNivel: VozAsistente.suNivel(),
                                         muestras: VozAsistente.muestrasDeNivel()) {
                return
            }
            self.nivelDeEstaFrase = nivel
            self.atenderOrden(limpio)
            // ¿No entendio nada en español? Entonces a ver que oyo el de
            // ingles del MISMO audio. Aqui es donde entra "drywall", "ceiling",
            // "save it", "next room" - como habla la cuadrilla de verdad.
            if !self.ultimoAtenderHizoAlgo { self.probarEnIngles() }
        }
        tareaVoz = rec.recognitionTask(with: peticion) { [weak self] resultado, error in
            // EL ERROR SE ATIENDE. Antes se ignoraba con un "_": si la tarea
            // moria, el microfono se quedaba mudo el resto del trabajo sin que
            // nadie lo supiera. Eso era, literalmente, "se traba y ya no
            // escucha".
            if error != nil {
                DispatchQueue.main.async { self?.reintentarTrasFallo() }
                return
            }
            guard let r = resultado else { return }
            DispatchQueue.main.async {
                self?.ultimaSeñalDeVoz = Date()
                if self?.fallosSeguidos != 0 {
                    self?.fallosSeguidos = 0
                    self?.actualizarIndicadorMicro()
                }
                ultimoTexto = r.bestTranscription.formattedString
                esperaSilencio?.invalidate()
                // ESPERAR SOLO CUANDO HAY DUDA.
                //
                // El segundo completo de espera existia porque "terminar" es
                // el principio de "terminar recorrido": actuar de inmediato
                // cerraba la sesion cuando solo queria cerrar el recorrido.
                // Pero eso solo pasa con UNAS POCAS frases. "Marca", "sí",
                // "laminado" no son el principio de nada, y hacerlo esperar un
                // segundo en cada una es lo que se siente lento.
                //
                // Asi que: si lo dicho todavia podria crecer en otra orden, se
                // espera. Si no, se actua ya.
                let pendiente = ultimoTexto.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let espera = Self.puedeCrecer(pendiente) ? 0.9 : 0.25
                esperaSilencio = Timer.scheduledTimer(withTimeInterval: espera, repeats: false) { _ in
                    despachar()
                }
            }
        }
        reinicioVoz = Timer.scheduledTimer(withTimeInterval: 40, repeats: false) { [weak self] _ in
            self?.reiniciarTareaVoz()
        }
    }

    // Una llamada, Siri o una alarma desactivan la sesion de audio y paran el
    // motor. Sin esto, el microfono se quedaba muerto EL RESTO DEL TRABAJO -
    // en silencio, sin decir nada, mientras el seguia diciendo "marca" en cada
    // esquina y no pasaba nada. Este es un telefono de trabajo: las llamadas
    // entran todo el dia.
    private func observarInterrupciones() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(audioInterrumpido(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance())
        // Conectar unos audifonos, subirse al carro, o que el sistema cambie
        // la ruta de audio PARA el motor sin avisar a nadie. El escaner de
        // planos ya escuchaba esta señal; esta pantalla no, y por eso se
        // quedaba muda sin razon aparente.
        NotificationCenter.default.addObserver(
            self, selector: #selector(cambioDeAudio(_:)),
            name: .AVAudioEngineConfigurationChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(cambioDeAudio(_:)),
            name: AVAudioSession.routeChangeNotification, object: nil)
    }

    @objc private func cambioDeAudio(_ n: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.micApagadoPorElUsuario, self.motorAudio != nil else { return }
            self.dejarDeEscuchar()
            self.empezarAEscuchar()
        }
    }

    @objc private func audioInterrumpido(_ n: Notification) {
        guard let info = n.userInfo,
              let bruto = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let tipo = AVAudioSession.InterruptionType(rawValue: bruto) else { return }
        switch tipo {
        case .began:
            dejarDeEscuchar()
        case .ended:
            // Se vuelve a levantar todo: sesion, motor y tarea. Y se avisa,
            // porque el tecnico no tiene como saber que se habia caido.
            // MODO .voiceChat, NO .default. Su pedido: "el voice assistant tiene que
        // evitar los sonidos exteriores y enfocarse mas en mi voz".
        //
        // Esto prende el procesamiento de voz que iOS ya trae: quita ruido de
        // fondo y cancela el eco de la propia bocina. Es lo mismo que usa una
        // llamada de FaceTime, y esta hecho justo para esto - una persona
        // hablandole al telefono de cerca en un lugar ruidoso. Una casa en
        // secado tiene tres ventiladores y un deshumidificador andando; eso es
        // exactamente el ruido que este modo esta hecho para descontar.
        //
        // Ademas ayuda al otro problema: si el eco de la app se cancela en el
        // audio, llega menos de su propia voz al reconocedor.
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat,
                                                            options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            empezarAEscuchar()
            if escuchando { say("Ya lo vuelvo a escuchar.", .guia) }
        @unknown default:
            break
        }
    }

    // Se cae la tarea: se vuelve a levantar, con espera creciente para no
    // entrar en un ciclo de mil intentos por segundo si el problema es de
    // fondo. Se reinicia el contador en cuanto llega una frase de verdad.
    private var fallosSeguidos = 0
    private var ultimaSeñalDeVoz = Date()
    private func reintentarTrasFallo() {
        guard motorAudio != nil, !micApagadoPorElUsuario else { return }
        fallosSeguidos += 1
        let espera = min(pow(2.0, Double(fallosSeguidos)), 20.0)
        reinicioVoz?.invalidate()
        reinicioVoz = Timer.scheduledTimer(withTimeInterval: espera, repeats: false) { [weak self] _ in
            self?.reiniciarTareaVoz()
        }
        actualizarIndicadorMicro()
    }
    private var micApagadoPorElUsuario = false

    // EL VIGILANTE. Aunque nada avise, si pasaron dos minutos sin una sola
    // palabra mientras el microfono deberia estar vivo, algo se cayo: se
    // levanta todo de nuevo. Es el respaldo de ultimo recurso - lo que atrapa
    // lo que no supimos prever.
    private var vigilante: Timer?
    private func arrancarVigilante() {
        vigilante?.invalidate()
        vigilante = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self = self, !self.micApagadoPorElUsuario else { return }
            guard self.motorAudio != nil else { return }
            if Date().timeIntervalSince(self.ultimaSeñalDeVoz) > 120 {
                self.ultimaSeñalDeVoz = Date()
                self.dejarDeEscuchar()
                self.empezarAEscuchar()
            }
            self.actualizarIndicadorMicro()
        }
    }

    // Verde vivo, rojo caido, gris apagado por el. Se mira de un vistazo sin
    // dejar de apuntar la camara.
    private func actualizarIndicadorMicro() {
        orbita.estado = micApagadoPorElUsuario ? .apagado
            : (motorAudio != nil && fallosSeguidos == 0) ? .escuchando : .caido
        // EN PAUSA SE VE. Una app callada que no dice por que esta callada es
        // igualita al "se traba, ya no habla" que el reporto - y si no se
        // distingue, no sirve de nada haberla arreglado.
        if enPausa {
            micDot.text = "⏸"
            micDot.backgroundColor = Self.colorEscogido
            return
        }
        if micApagadoPorElUsuario {
            micDot.text = "🔇"
            micDot.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        } else if motorAudio != nil, fallosSeguidos == 0 {
            micDot.text = "🎤"
            micDot.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.85)
        } else {
            micDot.text = "🎤"
            micDot.backgroundColor = UIColor.systemRed.withAlphaComponent(0.9)
        }
    }

    private func dejarDeEscuchar() {
        reinicioVoz?.invalidate(); reinicioVoz = nil
        tareaVoz?.cancel(); tareaVoz = nil
        peticionVoz = nil
        motorAudio?.inputNode.removeTap(onBus: 0)
        motorAudio?.stop()
        motorAudio = nil
        escuchando = false
    }

    // LAS ORDENES. Cerradas, cortas, y en el orden que importa: "terminar
    // recorrido" se revisa ANTES que "terminar", porque una contiene a la
    // otra y al reves cerraria la sesion entera cuando solo queria cerrar el
    // recorrido.
    // ============ DECIR EL MATERIAL, NO BUSCARLO EN UNA LISTA ============
    //
    // Su pedido: "al abrir la pantalla que el comando pregunte qué es lo que
    // va a medir, y uno dice laminado o piso, que él mismo lo escoja, para
    // que las cosas sean más rápidas".
    //
    // Las palabras son las que la cuadrilla USA, no las del catalogo: dicen
    // "carpeta" por carpet, "béisbol" por baseboard (asi lo transcribe el
    // telefono), "tablaroca" por drywall, "elevepé" por LVP. Una lista hecha
    // con las palabras del catalogo no le entenderia a nadie.
    // "Piso", "el piso", "floor" = dijo la seccion, no el material.
    static func esSoloLaSeccion(_ t: String, section: String) -> Bool {
        let d = t.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "el ", with: "")
            .replacingOccurrences(of: "la ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let palabras: [String: [String]] = [
            "floor":   ["piso", "floor", "el piso"],
            "wall":    ["pared", "wall", "la pared"],
            "ceiling": ["techo", "ceiling", "cielo", "el techo"],
            "kitchen": ["cocina", "kitchen"],
            "materiales": ["materiales", "material", "materials", "los materiales"]
        ]
        return (palabras[section] ?? []).contains(d)
    }

    // ¿Que SECCION dijo? Se reusa la misma tabla que ya servia para detectar
    // "dijiste la seccion en vez del material" - las palabras son las mismas,
    // lo que cambia es para que se usan.
    static func seccionDicha(_ t: String) -> String? {
        let d = t.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard d.split(separator: " ").count <= 5 else { return nil }
        // El techo primero: "cielo raso" contiene "raso" y nada mas choca, pero
        // el orden se deja explicito para que no dependa de la suerte.
        if d.contains("techo") || d.contains("cielo") || d.contains("ceiling") { return "ceiling" }
        if d.contains("pared") || d.contains("wall") || d.contains("muro") { return "wall" }
        // "Materiales" antes que "cocina": "materiales de la cocina" es la
        // sección de materiales, no la cocina.
        if d.contains("material") || d.contains("nailo") || d.contains("plastico") || d.contains("contencion") { return "materiales" }
        // Cocina y Baño volvieron a ser pastillas (27 sep 2026): decirlas lleva
        // a SU sección, no a Pared. OJO con el orden: van DESPUÉS de "material",
        // porque "materiales del baño" es la sección de materiales.
        if d.contains("cocina") || d.contains("kitchen") { return "kitchen" }
        if d.contains("bano") || d.contains("bath") || d.contains("powder room") { return "bathroom" }
        if d.contains("piso") || d.contains("floor") || d.contains("suelo") { return "floor" }
        return nil
    }

    // COMO LE DICE LA CUADRILLA A CADA CUARTO.
    //
    // La lista de cuartos viaja en INGLES porque asi va a la factura del
    // seguro. Pero el tecnico dice "el baño", no "the bathroom" - y sin esta
    // tabla `cuartoDicho` buscaba la palabra inglesa dentro de una frase en
    // español y no encontraba NADA. Todos los nombres en español fallaban en
    // silencio, y la unica forma de escoger cuarto hablando era decirlo en
    // ingles. Lo encontro la prueba de recorrido completo; frase por frase no
    // se veia, porque los ejemplos que yo habia escrito estaban en ingles.
    private static let sinonimosCuarto: [String: [String]] = [
        "Master Bedroom": ["recamara principal", "cuarto principal", "master", "principal"],
        "Bedroom":        ["recamara", "dormitorio", "habitacion", "alcoba"],
        "Bathroom":       ["baño", "bano", "sanitario", "escusado", "excusado", "regadera"],
        "Kitchen":        ["cocina"],
        "Living Room":    ["sala", "living", "estancia"],
        "Hallway":        ["pasillo", "corredor", "entrada"],
        "Basement":       ["sotano", "basement", "abajo"],
        "Closet":         ["closet", "ropero", "armario"],
        "Laundry Room":   ["lavanderia", "cuarto de lavado", "lavado", "laundry"],
        "Garage":         ["garage", "cochera", "garaje"],
        "Dining Room":    ["comedor"],
        "Office":         ["oficina", "estudio"],
        "Attic":          ["atico", "tapanco"],
        // Como los llaman de verdad, y en los dos idiomas.
        "Kids Bedroom":   ["kids bedroom", "kids room", "cuarto de los niños", "cuarto de los ninos",
                           "recamara de los niños", "recamara de los ninos", "cuarto de niños"],
        "Guest Bedroom":  ["guest bedroom", "guest room", "cuarto de visitas", "cuarto de huespedes"],
        "Guest Bathroom": ["guest bathroom", "baño de visitas", "bano de visitas"],
        "Half Bathroom":  ["half bathroom", "half bath", "medio baño", "medio bano"],
        "Family Room":    ["family room", "cuarto familiar", "sala familiar"],
        "Master Bathroom":["master bathroom", "baño principal", "bano principal"]
    ]

    // ¿Que CUARTO dijo? Contra la lista que manda la web, con la misma tecnica
    // ya probada en materialDicho: sin acentos, sin relleno, la mas larga gana,
    // y si niega gana la de despues. Busca el nombre en ingles Y como lo dice
    // el en español.
    // ============ COMO SE DICE UN NIVEL ============
    //
    // El nivel se resolvia con `cuartoDicho`, o sea con el buscador de CUARTOS,
    // y `sinonimosCuarto` no tiene ninguna forma en español para "1st Floor",
    // "2nd Floor" ni "3rd Floor". Resultado: la propia app pregunta "¿En qué
    // nivel? Primer piso, segundo piso, sótano..." y no entiende las dos
    // primeras. ("sótano" y "ático" casaban de casualidad, porque tambien son
    // nombres de CUARTO y esos si tienen sinonimos.)
    //
    // Es la misma familia del bug de los verbos con Ñ: una frase que no puede
    // casar nunca, y nadie se entera porque no falla - simplemente no pasa nada.
    private static let sinonimosNivel: [String: [String]] = [
        "Basement":  ["sotano", "basement", "el sotano", "abajo", "el de abajo", "bajos"],
        "1st Floor": ["primer piso", "primer nivel", "piso uno", "nivel uno", "primera planta",
                      "planta baja", "primero", "1er piso", "first floor", "ground floor",
                      "el uno", "abajo del todo"],
        "2nd Floor": ["segundo piso", "segundo nivel", "piso dos", "nivel dos", "segunda planta",
                      "segundo", "2do piso", "second floor", "el dos", "arriba"],
        "3rd Floor": ["tercer piso", "tercer nivel", "piso tres", "nivel tres", "tercera planta",
                      "tercero", "3er piso", "third floor", "el tres"],
        "Attic":     ["atico", "tapanco", "attic", "el atico", "lo mas arriba", "hasta arriba"]
    ]
    // El nivel que dijo, o nil. Gana la forma MAS LARGA que case, igual que con
    // los materiales: "segundo piso" tiene que ganarle a "segundo" suelto.
    static func nivelDicho(_ t: String, entre niveles: [String]) -> String? {
        func pelar(_ x: String) -> String {
            return x.lowercased()
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let dicho = pelar(t)
        guard !dicho.isEmpty else { return nil }
        var mejor: (valor: String, largo: Int)? = nil
        for nivel in niveles {
            var formas = [pelar(nivel)]
            formas += (Self.sinonimosNivel[nivel] ?? []).map(pelar)
            for f in formas {
                // Palabra o frase COMPLETA, no un trozo: sin esto "primero"
                // casaria dentro de "primerizo" y "el dos" dentro de "dosis".
                guard !f.isEmpty, Self.tienePalabra(dicho, f) else { continue }
                if mejor == nil || f.count > mejor!.largo { mejor = (nivel, f.count) }
            }
        }
        return mejor?.valor
    }

    static func cuartoDicho(_ t: String, entre cuartos: [String]) -> String? {
        func pelar(_ x: String) -> String {
            return x.lowercased()
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var dicho = pelar(t)
        for relleno in ["vamos a medir ", "vamos a la ", "vamos al ", "ahora el ", "ahora la ",
                        "voy a medir ", "medimos ", "es el ", "es la ", "el ", "la ", "en el ", "en la "] {
            if dicho.hasPrefix(relleno) { dicho = String(dicho.dropFirst(relleno.count)); break }
        }
        dicho = dicho.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dicho.isEmpty, dicho.split(separator: " ").count <= 6 else { return nil }
        var casan: [(valor: String, largo: Int, donde: Int)] = []
        for cuarto in cuartos {
            guard pelar(cuarto) != "other" else { continue }
            // El nombre en ingles y todas las formas en que el lo dice, todas
            // como candidatas: gana la mas larga, igual que con los materiales.
            var formas = [pelar(cuarto)]
            formas += (Self.sinonimosCuarto[cuarto] ?? []).map(pelar)
            for f in formas {
                guard !f.isEmpty, let r = dicho.range(of: f) else { continue }
                casan.append((cuarto, f.count, dicho.distance(from: dicho.startIndex, to: r.lowerBound)))
            }
        }
        guard !casan.isEmpty else { return nil }
        let niega = dicho.hasPrefix("no ") || dicho.contains(" no es ")
        let base = niega && casan.count >= 2
            ? casan.max { $0.donde < $1.donde }?.valor
            : casan.max { $0.largo < $1.largo }?.valor
        guard let ganador = base else { return nil }

        // ¿DIJO UN NUMERO? "Recámara dos", "closet tres", "bedroom 2".
        //
        // Sin esto, "recámara dos" devolvia "Bedroom" a secas y la segunda
        // recamara caia en la MISMA tarjeta que la primera: las dos medidas se
        // sumaban en una sola y el area no cuadraba con el plano. Y no se
        // notaba hasta el final, cuando ya nadie se acuerda de cual cuarto era.
        //
        // El uno NO se escribe: "recámara uno" es "Bedroom", no "Bedroom 1".
        // Asi es como se numeran las cosas hablando.
        let numeros: [String: Int] = ["dos": 2, "tres": 3, "cuatro": 4, "cinco": 5,
                                      "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10,
                                      "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                                      "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8,
                                      "9": 9, "10": 10]
        // Solo se mira lo que viene DESPUES del nombre del cuarto: un numero
        // antes es otra cosa ("dos cuartos", "tres paredes del baño").
        let nombre = pelar(ganador)
        var cola = dicho
        if let r = dicho.range(of: nombre) { cola = String(dicho[r.upperBound...]) }
        else if let sin = Self.sinonimosCuarto[ganador]?.map(pelar)
                          .compactMap({ f in dicho.range(of: f) }).max(by: { $0.upperBound < $1.upperBound }) {
            cola = String(dicho[sin.upperBound...])
        }
        for tk in cola.split(separator: " ").map(String.init) {
            if let n = numeros[tk] { return "\(ganador) \(n)" }
        }
        return ganador
    }

    // ============ DECIR UN NUMERO ============
    //
    // Lo que faltaba y se sentia todos los dias: NO habia forma de DECIR una
    // medida. Un pasillo mide 3 pies y el ya lo sabe; una puerta mide 3 pies y
    // lo sabe. Aun asi tenia que hacer otra pasada entera con la camara para
    // capturar un numero que traia en la cabeza.
    //
    // Esto NO es la app inventando una medida - eso sigue prohibido. Es EL
    // dictandola, igual que si la escribiera en el formulario. Y se repite en
    // voz alta al anotarla, para que un numero mal oido se oiga en el momento
    // y no aparezca en la factura.
    //
    // Devuelve PIES. nil si en la frase no venia ningun numero.
    private static let numeroPalabra: [String: Double] = [
        "cero": 0, "un": 1, "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4,
        "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10,
        "once": 11, "doce": 12, "trece": 13, "catorce": 14, "quince": 15,
        "dieciseis": 16, "diecisiete": 17, "dieciocho": 18, "diecinueve": 19,
        "veinte": 20, "veintiuno": 21, "veintiun": 21, "veintidos": 22,
        "veintitres": 23, "veinticuatro": 24, "veinticinco": 25, "veintiseis": 26,
        "veintisiete": 27, "veintiocho": 28, "veintinueve": 29, "treinta": 30,
        "cuarenta": 40, "cincuenta": 50, "sesenta": 60, "setenta": 70,
        "ochenta": 80, "noventa": 90, "cien": 100, "ciento": 100,
        // Las centenas TIENEN que estar aunque nadie mida 300 pies: sin ellas
        // "cuatrocientos cincuenta" se leia como 50 - la palabra desconocida
        // se tiraba callada y quedaba un numero creible y falso. Con ellas da
        // 450, pasa del tope, y se descarta como lo que es: una frase mal oida.
        "doscientos": 200, "trescientos": 300, "cuatrocientos": 400,
        "quinientos": 500, "seiscientos": 600, "setecientos": 700,
        "ochocientos": 800, "novecientos": 900, "mil": 1000
    ]

    // ============ HABLARLE DE MIL MANERAS ============
    //
    // Su pedido: "amplio entendimiento", "como unas 2,000 conversaciones".
    //
    // Escribir dos mil frases a mano seria imposible de mantener y, peor, seria
    // adivinar cual de las dos mil se le va a ocurrir. Aqui van los PEDAZOS en
    // vez de las frases: un grupo de verbos y un grupo de objetos por orden. La
    // frase entra si trae uno de cada grupo, y de ahi salen todas las
    // combinaciones solas. Doce verbos por quince objetos son ciento ochenta
    // formas de pedir lo mismo, escritas en dos renglones.
    //
    // TODO SIN ACENTOS **NI EÑES** a proposito: la frase se pliega antes de
    // comparar, asi que "quitale" cubre tambien "quítale" y no hay que escribir
    // las dos. OJO CON LA Ñ: el plegado la vuelve n, asi que va "anade", no
    // "añade" - escrita con ñ la palabra queda MUERTA, casa con nada. Asi
    // nacieron muertos veinticuatro verbos de esta tabla hasta que el corpus
    // los delato.
    //
    // ESTO CORRE AL FINAL, despues de las reglas exactas de siempre. Las reglas
    // viejas son precisas y estan probadas; esto es la red ancha que agarra lo
    // que se les escapa. Si algo aqui se equivoca, no rompe nada de lo que ya
    // funcionaba.
    private struct Patron {
        let orden: Orden
        let verbos: [String]
        let objetos: [String]   // vacio = el verbo solo basta
    }

    // Palabras que no dicen nada por si solas: pueden sobrar en una orden sin
    // que deje de ser una orden. Cualquier otra cosa que sobre significa que la
    // frase hablaba de algo mas.
    private static let rellenoNeutro: Set<String> = [
        "el", "la", "los", "las", "un", "una", "unos", "unas", "lo", "le", "les",
        "me", "te", "se", "nos", "de", "del", "al", "a", "en", "con", "por", "para",
        "y", "o", "que", "qué", "ya", "mas", "muy", "bien", "ahi", "aca", "asi",
        "este", "esta", "esto", "ese", "esa", "eso", "mi", "su", "tu", "es", "esta",
        "ahora", "luego", "tambien", "nomas", "solo", "otra", "otro", "vez", "va",
        "vamos", "vas", "voy", "favor", "porfa", "ok", "oye", "mira", "bueno", "pues"
    ]

    private static let patrones: [Patron] = [
        // ---- PONER UNA ESQUINA. Lo que mas se dice en todo el dia. ----
        Patron(orden: .marcar,
               verbos: ["marca", "marcala", "marcalo", "marque", "marcar", "pon", "ponle", "ponme",
                        "pone", "poner", "agrega", "agregale", "agregame", "anade", "anadele",
                        "mete", "metele", "clava", "pica", "senala", "senalame", "dale", "echa",
                        "echale", "tira", "tirale", "anota", "anotame", "coloca", "colocale"],
               objetos: ["marca", "marcas", "punto", "puntos", "esquina", "esquinas", "aqui",
                         "aca", "ahi", "alli", "este lado", "esta esquina", "ese punto",
                         "la esquina", "el punto", "otra", "otro", "una mas", "uno mas"]),

        // ---- QUITAR LO ULTIMO ----
        Patron(orden: .deshacer,
               verbos: ["quita", "quitale", "quitame", "quitalo", "quitala", "quitar",
                        "borra", "borrale", "borralo", "borrala", "borrar", "elimina",
                        "saca", "sacale", "sacalo", "remueve", "retira", "deshaz", "deshacer",
                        "regresa", "regresate", "devuelve", "devuelvete", "corrige", "arregla",
                        "tumba", "tumbale"],
               objetos: ["eso", "ese", "esa", "esta", "este", "marca", "punto", "esquina",
                         "ultima", "ultimo", "anterior", "de atras", "para atras", "atras",
                         "lo que hice", "lo que puse", "lo de antes", "esa medida"]),

        // ---- GUARDAR ESTA MEDIDA Y SEGUIR ----
        Patron(orden: .guardar,
               verbos: ["guarda", "guardala", "guardalo", "guardame", "guardar",
                        "anota", "anotala", "anotalo", "apunta", "apuntala", "apuntalo",
                        "registra", "registrala", "salva", "salvala", "mete", "metela",
                        "agrega", "agregala", "quedo", "quedate", "sirve", "sirvio"],
               objetos: ["medida", "medidas", "esa", "esto", "eso", "esta", "el dato",
                         "el numero", "asi", "asi esta", "ya", "ya quedo", "y sigue",
                         "y seguimos", "y continuamos", "y vamos"]),

        // ---- CERRAR EL RECORRIDO DEL LARGO ----
        Patron(orden: .terminarRecorrido,
               verbos: ["cierra", "cierralo", "cerrar", "termina", "terminar", "acaba",
                        "ya", "listo", "cierre"],
               objetos: ["recorrido", "el recorrido", "el largo", "la linea", "el camino",
                         "la vuelta", "el perimetro", "las esquinas"]),

        // ---- YA ACABAMOS TODO: MANDARLO ----
        Patron(orden: .terminar,
               verbos: ["termina", "terminamos", "termine", "termino", "terminar",
                        "acaba", "acabamos", "acabe", "acabo", "acabar",
                        "manda", "mandalo", "mandala", "mandar", "envia", "envialo",
                        "cierra", "cierralo", "finaliza", "concluye"],
               objetos: ["todo", "ya", "esto", "el reporte", "las medidas", "la medicion",
                         "aqui", "de medir", "con todo", "la casa", "el trabajo", "ya esta"]),

        // ---- PASAR AL ANCHO ----
        Patron(orden: .medirAncho,
               verbos: ["mide", "medir", "mediremos", "midamos", "dame", "pon", "sigue",
                        "vamos", "pasa", "pasemos", "toca", "falta", "ahora", "necesito"],
               objetos: ["ancho", "el ancho", "de ancho", "lo ancho", "el otro lado",
                         "lado a lado", "lo de alto", "el alto", "la altura"]),

        // ---- OTRO CUARTO ----
        Patron(orden: .otroCuarto,
               verbos: ["otro", "otra", "siguiente", "proximo", "proxima", "cambia",
                        "cambiamos", "cambiar", "pasa", "pasamos", "pasemos", "vamos",
                        "vamonos", "nos vamos", "sigue", "seguimos", "brinca", "brincamos"],
               objetos: ["cuarto", "cuartos", "pieza", "recamara", "habitacion", "sala",
                         "bano", "cocina", "closet", "pasillo", "area", "espacio"]),

        // ---- OTRO NIVEL ----
        Patron(orden: .cambiarNivel,
               verbos: ["otro", "otra", "siguiente", "cambia", "cambiamos", "cambiar",
                        "subimos", "sube", "subamos", "bajamos", "baja", "bajemos",
                        "vamos", "vamonos", "nos vamos", "pasamos"],
               objetos: ["nivel", "niveles", "piso de arriba", "piso de abajo", "planta",
                         "arriba", "abajo", "segundo piso", "primer piso", "el sotano",
                         "basement", "atico", "attic"]),

        // ---- OTRA SECCION ----
        Patron(orden: .cambiarSeccion,
               verbos: ["otra", "otro", "cambia", "cambiamos", "cambiar", "pasa", "pasamos",
                        "vamos", "sigue", "seguimos", "ahora"],
               objetos: ["seccion", "secciones", "parte", "categoria", "lista de material",
                         "tipo de medida"]),

        // ---- EL TOTAL, SIN BAJAR LA VISTA ----
        Patron(orden: .cuantoLlevo,
               verbos: ["cuanto", "cuantos", "cuanta", "cuantas", "que tanto", "dime",
                        "dame", "como vamos de", "que hay de"],
               objetos: ["llevo", "llevamos", "va", "vamos", "tengo", "tenemos", "hay",
                         "de total", "el total", "en total", "medido", "medidas",
                         "pies", "de pies", "hecho"]),

        // ---- QUE MATERIAL ES ESTE ----
        Patron(orden: .queMaterial,
               verbos: ["que", "cual", "cuales", "dime", "dime que", "recuerdame"],
               objetos: ["material", "materiales", "escogi", "escogimos", "escogiste",
                         "puse", "pusimos", "pusiste", "estoy midiendo", "estamos midiendo",
                         "seleccione", "seleccionamos"]),

        // ---- ME EQUIVOQUE DE MATERIAL ----
        Patron(orden: .cambiarMaterial,
               // "no es" estaba muerta: el filtro de negacion apaga toda frase
               // con un "no" antes de llegar aqui.
               verbos: ["cambia", "cambiame", "cambiar", "otro", "otra", "corrige",
                        "esta mal", "me equivoque", "equivoque", "escogi mal",
                        "pusimos mal"],
               objetos: ["material", "materiales", "el que escogi", "lo que escogi",
                         "de material", "ese material", "este material"]),

        // ---- ABRIR LA LISTA, QUE ESTA VEZ PREFIERE EL DEDO ----
        Patron(orden: .abrirLista,
               verbos: ["abre", "abreme", "muestra", "muestrame", "ensena", "ensename",
                        "dame", "saca", "sacame", "pon", "ponme", "quiero ver", "ver"],
               objetos: ["lista", "la lista", "las opciones", "opciones", "el menu",
                         "los materiales", "el catalogo"]),

        // ---- DONDE VOY ----
        Patron(orden: .dondeVoy,
               verbos: ["donde", "como", "que", "en que", "dime", "recuerdame", "explicame"],
               objetos: ["voy", "vamos", "estoy", "estamos", "sigue", "sigo", "seguimos",
                         "toca", "falta", "me falta", "nos falta", "hago", "hacemos",
                         "paso voy", "punto voy"]),

        // ---- CALLATE ----
        Patron(orden: .silencio,
               verbos: ["callate", "calla", "callese", "silencio", "shh", "guarda",
                        "ya no", "deja de", "no mas"],
               objetos: ["silencio", "hables", "hablar", "digas", "decir", "la boca",
                         "callado", "callada"]),

        // ---- QUE TE PUEDO DECIR ----
        Patron(orden: .queComandos,
               verbos: ["que", "cuales", "cual", "dime", "dime que", "ensename", "muestrame",
                        "recuerdame"],
               objetos: ["te puedo decir", "puedo decir", "puedo decirte", "comandos",
                         "ordenes", "sabes hacer", "puedes hacer", "entiendes",
                         "palabras", "opciones de voz", "te digo"]),

        // ---- AYUDA ----
        Patron(orden: .ayuda,
               // "no se" y "no entiendo" estaban escritas y muertas: el filtro
               // de negacion apaga toda frase con un "no", asi que nunca
               // llegaban aqui. Y "ensename"/"explicame" se fueron a
               // queComandos, que es lo que de verdad piden.
               verbos: ["ayuda", "ayudame", "ayudeme", "auxilio", "socorro"],
               objetos: []),

        // ---- OTRA IGUAL ----
        Patron(orden: .otraIgual,
               verbos: ["otra", "otro", "repite", "repiteme", "haz", "hazme", "dame",
                        "pon", "ponme", "copia", "copiame", "duplica", "igual", "lo mismo",
                        "la misma", "el mismo"],
               objetos: ["igual", "igualita", "misma", "mismo", "anterior", "como esa",
                         "otra vez", "medida", "asi mismo", "identica", "parecida"]),

        // ---- ESPERAME ----
        Patron(orden: .esperame,
               verbos: ["espera", "esperame", "esperese", "espere", "aguanta", "aguantame",
                        "aguante", "detente", "parale", "pausale", "pausa",
                        "permiteme", "permitame", "tantito"],
               objetos: ["", "tantito", "un momento", "un segundo", "un rato", "chance",
                         "poquito", "un minuto", "ahorita"]),

        // ---- YA ESTOY DE VUELTA ----
        Patron(orden: .yaEstoy,
               verbos: ["ya", "listo", "continuamos", "continuemos", "continua", "sigamos",
                        "seguimos", "sigue", "aqui", "regrese", "volvi", "vamos"],
               objetos: ["estoy", "regrese", "volvi", "aqui", "listo", "podemos seguir",
                         "le seguimos", "de vuelta", "otra vez", "continuamos"]),

        // ---- LA INSULACION, HABLANDO ----
        Patron(orden: .ponerCompanero,
               verbos: ["pon", "ponle", "ponme", "agrega", "agregale", "anade", "anadele",
                        "mete", "metele", "marca", "si lleva", "lleva", "tiene", "incluye",
                        "cuenta", "suma"],
               objetos: ["insulacion", "aislamiento", "insulation", "almohadilla", "padding",
                         "underlayment", "lo de abajo", "la base", "el forro", "la espuma"]),
        Patron(orden: .quitarCompanero,
               verbos: ["quita", "quitale", "saca", "sacale", "borra", "sin", "no lleva",
                        "no tiene", "no le pongas", "quitalo", "no cuentes"],
               objetos: ["insulacion", "aislamiento", "insulation", "almohadilla", "padding",
                         "underlayment", "lo de abajo", "la base", "el forro", "la espuma"]),

        // ---- EL RITMO ----
        Patron(orden: .masDespacio,
               verbos: ["mas", "habla", "hablame", "ve", "vete", "baja", "bajale"],
               objetos: ["despacio", "lento", "lentito", "calmado", "pausado", "la velocidad"]),
        Patron(orden: .masRapido,
               verbos: ["mas", "habla", "hablame", "ve", "vete", "sube", "subele", "apurate"],
               objetos: ["rapido", "rapidito", "aprisa", "veloz", "de volada", "ya"]),

        // ---- REPITE LO QUE DIJISTE ----
        Patron(orden: .repite,
               verbos: ["repite", "repiteme", "repitelo", "otra vez", "que", "como",
                        "no te", "vuelve a"],
               objetos: ["dijiste", "decias", "oi", "escuche", "entendi", "dijo",
                         "eso", "lo que dijiste", "decir"]),

        // ---- ¿ESTAS AHI? ----
        // "esta" y "hay" salen en cualquier frase de la casa: "esta bien mojado
        // aqui" le preguntaba a la app si estaba bien. Solo verbos que de
        // verdad le hablan a ELLA.
        Patron(orden: .comoEstas,
               verbos: ["estas", "sigues", "funcionas", "escuchas", "oyes", "tienes"],
               objetos: ["bien", "ahi", "alli", "escuchando", "escuchas", "oyes", "oyendo",
                         "inteligencia", "vivo", "prendido", "conectado", "trabajando"]),

        // CANCELAR NO ESTA EN ESTA TABLA, y es a proposito: es la unica orden
        // que tira trabajo sin preguntar nada. Las reglas exactas ya la agarran
        // ("cancela", "de nuevo", "borra todo"); una red ancha sobre ella solo
        // agrega la forma de perder el trabajo por una frase mal oida.
    ]

    // La red ancha. Corre DESPUES de las reglas exactas: solo ve lo que a
    // aquellas se les escapo, asi que no puede romper nada que ya funcionaba.
    private static func porPatron(_ t: String) -> Orden? {
        let d = t.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
        // UNA NEGACION APAGA TODO. "No marques todavia" trae "marca" adentro y
        // sin esto pondria justo la esquina que le estaban pidiendo no poner.
        // Las negaciones que SI son ordenes ("no lleva insulacion") ya las
        // agarraron las reglas exactas alla arriba, antes de llegar aqui.
        // Por palabra COMPLETA y en cualquier lugar: " no " con espacios a los
        // dos lados se le escapaba "el cliente dijo que no", donde el "no" es
        // la ultima palabra.
        if tienePalabra(d, "no") || tienePalabra(d, "nunca") || tienePalabra(d, "nada")
            || d.contains("todavia no") || d.contains("ni se") { return nil }
        for p in patrones {
            let candidatos = p.verbos.filter { traeFrase(d, $0) }
            guard !candidatos.isEmpty else { continue }
            if p.objetos.isEmpty { return p.orden }
            // EL OBJETO TIENE QUE SER OTRA PARTE DE LA FRASE, y hay que probar
            // TODOS los verbos que casen, no el primero.
            //
            // Dos trampas distintas, las dos ya mordieron:
            //  - Una palabra que esta en los DOS grupos se casaba consigo
            //    misma: "aqui" era verbo Y objeto de "ya estoy", asi que
            //    "esta bien mojado aqui" despertaba a la app.
            //  - Y al reves: tomando solo el PRIMER verbo, "ponle marca"
            //    gastaba "marca" de verbo y se quedaba sin objeto - salia
            //    muda una de las frases que mas se dicen.
            for verbo in candidatos {
                var resto = d
                if let r = resto.range(of: verbo) { resto.removeSubrange(r) }
                guard let objeto = p.objetos.first(where: { !$0.isEmpty && traeFrase(resto, $0) })
                else { continue }
                if let r = resto.range(of: objeto) { resto.removeSubrange(r) }
                // Lo que queda despues de sacar el verbo y el objeto tiene que
                // ser relleno o mas palabras de esta misma orden. Una palabra
                // ajena - "ventiladores", "cliente", "aseguranza" - quiere
                // decir que estaba hablando de otra cosa.
                let sobra = resto.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
                let esRelleno = sobra.allSatisfy { w in
                    Self.rellenoNeutro.contains(w)
                        || p.verbos.contains(where: { $0.contains(w) })
                        || p.objetos.contains(where: { $0.contains(w) })
                }
                if esRelleno { return p.orden }
            }
            // Un objeto vacio en la lista quiere decir "el verbo solo basta
            // TAMBIEN" - se usa donde el verbo ya es inconfundible ("esperame").
            if p.objetos.contains("") { return p.orden }
        }
        return nil
    }

    // ¿La palabra esta COMPLETA en la frase? Un contains pelado busca dentro
    // de otras palabras, y eso ya mordio: "pad" vive dentro de "empapado".
    static func tienePalabra(_ t: String, _ w: String) -> Bool {
        return t.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .contains { String($0) == w }
    }

    // Lo mismo pero para VARIAS palabras seguidas: "esta esquina", "de abajo".
    // Sin esto, buscar "aca" adentro de "saca esa marca" daba positivo y sacar
    // una marca ponia una esquina nueva - lo contrario de lo que pidio.
    static func traeFrase(_ t: String, _ f: String) -> Bool {
        guard !f.isEmpty else { return false }
        let limpio = " " + t.map { $0.isLetter || $0.isNumber ? $0 : " " }
                            .reduce(into: "") { $0.append($1) } + " "
        return limpio.contains(" " + f + " ")
    }

    // ¿Esta frase es una MEDIDA dicha, o nada mas trae un numero adentro?
    //
    // Esta es la diferencia entre una app que obedece y una que anota basura.
    // `piesDichos` es a proposito generosa - lee cualquier numero que
    // encuentre - y eso esta bien CUANDO YA SE SABE que viene una medida
    // (contestando "¿cuánto mide de ancho?"). Suelta, mordia horrible:
    //
    //   "es una pared"      -> "una" = 1    -> anotaba un ancho de 1 pie
    //   "esta medio mojado" -> "medio" = ½  -> anotaba medio pie
    //   "son dos"           -> 2            -> anotaba 2 pies
    //
    // Y ninguna de esas tres es rara: son frases de todos los dias en una casa
    // inundada. La regla que las apaga sin apagar las de verdad: o la frase
    // TRAE LA UNIDAD ("tres pies", "seis pulgadas"), o la frase es SOLO el
    // numero y nada mas ("doce", "tres y medio") - que es como se contesta una
    // pregunta de cuanto mide.
    static func medidaComoOrden(_ t: String) -> Double? {
        let d = t.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
        let tokens = d.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." }).map(String.init)
        guard !tokens.isEmpty else { return nil }
        let unidades: Set<String> = ["pie", "pies", "feet", "ft", "foot",
                                     "pulgada", "pulgadas", "inch", "inches"]
        let traeUnidad = tokens.contains { unidades.contains($0) }
        // NI SIQUIERA CON LA UNIDAD basta que el numero ande suelto adentro de
        // cualquier frase. "Hay que cortar dos pies" trae numero Y unidad, y
        // NO es una medida dictada: es una instruccion a un compañero. Si eso
        // anotara un ancho, media conversacion de obra se volveria medidas.
        //
        // La regla: TODA palabra de la frase tiene que ser parte de decir un
        // numero. Una sola palabra ajena - "cortar", "pared", "mojado" - y ya
        // no es una medida dictada.
        let deNumero: Set<String> = ["y", "punto", "coma", "medio", "media", "cuarto", "cuartos"]
        // Los rellenos que SI valen alrededor de un numero dictado. "cortar"
        // no esta, y por eso "cortar dos pies" no anota nada.
        let relleno: Set<String> = ["el", "la", "los", "las", "de", "del", "es", "son",
                                    "mide", "miden", "tiene", "da", "queda", "como",
                                    "casi", "ancho", "largo", "alto", "por", "ponle", "pon"]
        let todoCuenta = tokens.allSatisfy { tk in
            numeroPalabra[tk] != nil || deNumero.contains(tk) || unidades.contains(tk)
                || relleno.contains(tk) || (Double(tk) != nil && tk.first?.isNumber == true)
        }
        guard todoCuenta else { return nil }
        // Y sin unidad, ademas, no valen ni los rellenos: "son dos" volveria a
        // pasar. Sin unidad la frase tiene que ser SOLO el numero.
        if !traeUnidad {
            let soloNumero = tokens.allSatisfy { tk in
                numeroPalabra[tk] != nil || deNumero.contains(tk)
                    || (Double(tk) != nil && tk.first?.isNumber == true)
            }
            guard soloNumero else { return nil }
        }
        return piesDichos(t)
    }

    static func piesDichos(_ t: String) -> Double? {
        let d = t.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
            .replacingOccurrences(of: ",", with: ".")
        let tokens = d.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." }).map(String.init)
        guard !tokens.isEmpty else { return nil }

        var pies = 0.0            // lo ya cerrado con su unidad
        var acumulado = 0.0       // el numero que se esta armando
        var hayNumero = false

        for (i, tk) in tokens.enumerated() {
            // Un numero escrito con digitos: el reconocedor devuelve "3" y
            // "3.5" tan seguido como las palabras.
            if let n = Double(tk), tk.first?.isNumber == true {
                acumulado += n; hayNumero = true; continue
            }
            if let n = Self.numeroPalabra[tk] {
                // "treinta y dos" y "ciento veinte" se suman llano: la
                // unidad cae sobre la decena (o la centena) que ya venia.
                acumulado += n
                hayNumero = true
                continue
            }
            switch tk {
            case "medio", "media":
                // Pegado al numero o pegado a la unidad: "tres y medio",
                // "medio pie". Suelto mordia: "esta medio mojado" anotaba
                // medio pie de ancho, y asi se habla aqui todos los dias.
                let prev = i > 0 ? tokens[i-1] : ""
                let sig = i + 1 < tokens.count ? tokens[i+1] : ""
                guard prev == "y" || numeroPalabra[prev] != nil || sig.hasPrefix("pie") else { continue }
                acumulado += 0.5; hayNumero = true
            case "cuarto", "cuartos":
                // OJO: "cuarto" es TAMBIEN el nombre de una habitacion, y en
                // esta app esa palabra manda. Solo vale como ¼ de pie si viene
                // PEGADA al numero: "tres y cuarto", "tres cuartos". Con solo
                // pedir que hubiera un numero antes no alcanzaba - "tres pies
                // del cuarto de lavado" daba 3.25 en vez de 3.
                let previa = i > 0 ? tokens[i-1] : ""
                guard hayNumero, previa == "y" || previa == "tres" else { continue }
                // "tres cuartos" = 0.75, y el 3 que se acumulo era el numerador.
                if previa == "tres", acumulado >= 3 { acumulado -= 3; acumulado += 0.75 }
                else { acumulado += 0.25 }
            case "pie", "pies", "feet", "ft", "foot":
                pies += acumulado; acumulado = 0
            case "pulgada", "pulgadas", "inch", "inches", "in":
                pies += acumulado / 12.0; acumulado = 0
            case "y", "con", "de", "el", "la", "es", "son", "mide", "tiene":
                continue          // relleno entre numeros: no rompe la cuenta
            default:
                continue
            }
        }
        pies += acumulado
        guard hayNumero else { return nil }
        // Un tope con los pies en la tierra: nadie mide un tramo de 400 pies
        // de un tiron, y un numero asi casi siempre es una frase mal oida.
        guard pies > 0, pies <= 400 else { return nil }
        // Al cuarto de pulgada, que es a lo que se mide en obra.
        return (pies * 48).rounded() / 48
    }

    // "Doce por diez", "12 x 10": las dos medidas de un jalon.
    static func porDosDicho(_ t: String) -> (largo: Double, ancho: Double)? {
        let d = t.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
        for sep in [" por ", " x "] {
            guard let r = d.range(of: sep) else { continue }
            let izq = String(d[d.startIndex..<r.lowerBound])
            let der = String(d[r.upperBound...])
            if let a = piesDichos(izq), let b = piesDichos(der) { return (a, b) }
        }
        return nil
    }

    // ============ QUITARLE EL RELLENO A UNA FRASE ============
    //
    // El techo real de la comprension no eran las palabras que faltaban: era
    // que TODA frase de mas de cuatro palabras se tiraba sin siquiera leerla.
    // Y el no habla en palabras sueltas - dice "ok, ahora vamos a medir la
    // pared", "ya terminamos con este cuarto". Seis palabras, a la basura.
    //
    // Esto le quita el arranque conversacional para que abajo quede la orden
    // pelada. Lo que NO se puede es abrir la puerta a la platica de casa, asi
    // que despues de pelarla la frase tiene que seguir siendo corta.
    static func sinRelleno(_ t: String) -> String {
        var d = t
        let arranques = ["ok ", "okey ", "okay ", "oye ", "mira ", "bueno ", "este ",
                         "a ver ", "haber ", "pues ", "entonces ", "ahora si ", "ahora ",
                         "ya mero ", "por favor ", "porfa ", "vamos a ", "vamonos a ",
                         "hay que ", "vamos ", "le vamos a ", "nos vamos a "]
        // OJO CON ESTA LISTA: quitar relleno no puede BORRAR una orden.
        // " va" parecia inofensivo y se comia "cuánto va"; "ahorita " se comia
        // "ahorita no", que es como pide una pausa. Las dos se quitaron.
        var cambio = true
        while cambio {
            cambio = false
            for a in arranques where d.hasPrefix(a) {
                d = String(d.dropFirst(a.count)); cambio = true; break
            }
        }
        for cola in [" por favor", " porfa", " pues", " ok", " okey"] {
            if d.hasSuffix(cola) { d = String(d.dropLast(cola.count)) }
        }
        return d.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // ============ COMO LE DICE LA CUADRILLA A CADA MATERIAL ============
    //
    // Su reporte del 12 de septiembre, viendo los botones: "donde dice
    // tablaroca, la mayoría lo conoce como DRYWALL. El yeso es PLASTER. Poste,
    // no sé qué es poste. La moldura, la mayoría lo conoce como BASEBOARD".
    //
    // Los botones mostraban la mitad ESPAÑOLA de la etiqueta ("Tablaroca /
    // Drywall" -> "Tablaroca"), que es lo correcto para el formulario de la
    // oficina y lo EQUIVOCADO para la camara. En una cuadrilla de restauración
    // en Virginia los materiales de estructura se dicen en inglés y se llevan
    // dichos así todo el día. Un botón con una palabra que nadie usa es un
    // botón que hay que leer dos veces - y peor, "Poste" no le dice nada a
    // nadie.
    //
    // Esto cambia SOLO lo que se ve y se oye. El `value` que viaja a la factura
    // del seguro no se toca: ese ya iba en inglés.
    private static let nombreDeCampo: [String: String] = [
        "Drywall":          "Drywall",
        "Plaster":          "Plaster",
        "Stud / Framing":   "Stud",
        "Baseboard":        "Baseboard",
        "Trim":             "Trim",
        "Crown Molding":    "Crown",
        "Insulation":       "Insulación",   // esta SI la dice en español, y lo pidio explicito
        "Popcorn / Texture": "Popcorn",
        "Carpet Pad":       "Pad",
        "Underlayment":     "Underlayment",
        "Vinyl (LVP)":      "LVP",
        "Subfloor":         "Subfloor",
        "Plywood":          "Plywood"
    ]

    // El nombre para la pantalla y para la voz. Si no esta en la tabla, se usa
    // la mitad que ya se usaba - o sea, nada de lo que ya funcionaba cambia.
    static func nombreDeBoton(_ m: ARMaterialOption) -> String {
        if let n = nombreDeCampo[m.value] { return n }
        return m.label.components(separatedBy: " / ").first ?? m.value
    }
    static func nombreDeBoton(valor: String, etiqueta: String) -> String {
        if let n = nombreDeCampo[valor] { return n }
        return etiqueta.components(separatedBy: " / ").first ?? valor
    }

    // LA OTRA MITAD, la que va flotando en chico debajo de la pastilla.
    //
    // Las etiquetas ya traen los dos idiomas ("Drywall / Tablaroca"), asi que
    // no hay que mandar nada nuevo desde la web: la mitad que la pastilla NO
    // esta diciendo es la traduccion. Y funciona en los dos sentidos - la
    // insulacion dice "Insulación" arriba porque el lo pidio explicito, y
    // entonces abajo le toca "Insulation".
    //
    // Vacio cuando las dos mitades dicen lo mismo (el shoe molding se llama
    // igual en los dos idiomas): repetir la palabra debajo de si misma es ruido.
    static func traduccionDeBoton(valor: String, etiqueta: String) -> String {
        let grande = nombreDeBoton(valor: valor, etiqueta: etiqueta)
        let partes = etiqueta.components(separatedBy: " / ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard partes.count > 1, let ultima = partes.last else { return "" }
        if ultima.caseInsensitiveCompare(grande) != .orderedSame { return ultima }
        return partes[0].caseInsensitiveCompare(grande) == .orderedSame ? "" : partes[0]
    }
    static func traduccionDeBoton(_ m: ARMaterialOption) -> String {
        return traduccionDeBoton(valor: m.value, etiqueta: m.label)
    }

    private static func companionDe(_ m: ARMaterialOption) -> String? {
        guard let es = m.companionEs, !es.isEmpty else { return nil }
        return es
    }

    private static let sinonimosMaterial: [String: [String]] = [
        "Laminate":         ["laminado", "laminate", "flotante"],
        // "style" y "tail" son como el telefono transcribe "tile" cuando se
        // dice en ingles dentro de una frase en español. Sin esto, pedir
        // loseta en ingles no escogia nada.
        "Tile":             ["loseta", "losa", "baldosa", "azulejo", "tile", "style", "tail",
                             "cerámica", "ceramica"],
        "Hardwood":         ["madera", "hardwood", "duela", "parquet", "jardwood", "jarwud", "hard wood"],
        "Vinyl (LVP)":      ["vinil", "vinilo", "vinyl", "lvp", "elevepé", "elevepe", "ele ve pe"],
        "Carpet":           ["alfombra", "carpeta", "carpet", "carpete", "carpec"],
        "Carpet Pad":       ["almohadilla", "pad", "padding", "esponja", "carpet pad"],
        "Underlayment":     ["underlayment", "base", "plástico de abajo", "plastico de abajo",
                             "anderleiment", "anderlaiment", "under layment"],
        "Plywood":          ["triplay", "plywood", "madera prensada", "plaiwud", "plai wood"],
        "Subfloor":         ["subpiso", "subfloor", "piso de abajo", "sub flor", "sabflor"],
        "Concrete":         ["concreto", "cemento", "concrete"],
        "Drywall":          ["tablaroca", "drywall", "sheetrock", "panel de yeso", "panel",
                             // Como lo escribe un reconocedor ESPAÑOL al oir
                             // "drywall": la palabra que mas se dice de todas.
                             "drai wol", "drai gual", "dry wall", "draiwol", "drywol",
                             "trigual", "dragual", "chit rock", "shitrock", "sheet rock"],
        "Plaster":          ["yeso", "plaster", "repello"],
        "Stud / Framing":   ["poste", "postes", "armazón", "armazon", "stud", "studs", "framing", "madera de pared"],
        "Insulation":       ["insulación", "insulacion", "insulation", "aislamiento",
                             "insuleichon", "insuleishon", "insuleiron"],
        // 18 sep 2026: el zocalo y la moldura se separaron en dos materiales.
        // "moldura" A SECAS se queda con el ZOCALO a proposito: es como la
        // cuadrilla llama al rodapie. Para la moldura de puertas y ventanas se
        // dice "trim", que es la palabra que usan para esa.
        "Baseboard":        ["zócalo", "zocalo", "moldura", "baseboard", "béisbol", "beisbol",
                             "rodapié", "rodapie", "beis bor", "base board", "beisbor"],
        "Trim":             ["trim", "marco", "marcos", "moldura de puerta", "moldura de ventana",
                             "trin", "trim de puerta"],
        "Crown Molding":    ["corona", "crown", "crown molding", "moldura de corona",
                             "craun", "craun molding", "moldura del techo"],
        "Popcorn / Texture":["textura", "popcorn", "palomita", "palomitas"],
        "Countertop":       ["cubierta", "countertop", "counter top", "counter", "encimera", "barra", "canter"],
        "Cabinets":         ["gabinetes", "gabinete", "cabinets", "cabinet", "muebles de cocina", "cabinets de cocina"],
        "Stove / Range":    ["estufa", "stove", "range", "parrilla"],
        "Refrigerator":     ["refrigerador", "refri", "nevera", "refrigerator", "fridge"],
        "Sink":             ["fregadero", "lavabo", "sink", "lavaplatos"],
        "Backsplash":       ["backsplash", "salpicadero", "respaldo"]
    ]

    // Cual de los materiales DE ESTA SECCION dijo. Se busca solo entre los
    // que la tarjeta ofrece: decir "alfombra" en la seccion de Pared no debe
    // escoger nada, porque ahi no hay alfombra.
    // Envoltura: la version de verdad recibe el diccionario aprendido en vez
    // de leerlo de UserDefaults, para poder probarla sin telefono.
    static func materialDicho(_ t: String, entre valores: [String]) -> String? {
        return materialDicho(t, entre: valores, aprendidas: palabrasAprendidas())
    }
    static func materialDicho(_ t: String, entre valores: [String], aprendidas: [String: String]) -> String? {
        let crudo = t.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Lo aprendido se busca con la frase COMPLETA, antes de quitarle nada:
        // el quitador de relleno le corta el "la" de adelante, y una frase
        // aprendida como "la tabla esa" quedaba en "tabla esa" y ya no se
        // encontraba nunca. Se aprendio completa, se busca completa.
        if let valor = aprendidas[crudo], valores.contains(valor) { return valor }
        var dicho = crudo
        // La gente no contesta con una palabra suelta: dice "voy a medir
        // laminado" o "es piso de madera". Se quitan los rellenos de adelante
        // para que quede el material.
        for relleno in ["voy a medir ", "vamos a medir ", "quiero medir ", "voy a hacer ",
                        "es de ", "es el ", "es la ", "es ", "el ", "la ", "un ", "una ", "de "] {
            if dicho.hasPrefix(relleno) { dicho = String(dicho.dropFirst(relleno.count)); break }
        }
        dicho = dicho.trimmingCharacters(in: .whitespacesAndNewlines)
        // Hasta seis palabras: "laminate floor", "piso de madera", "voy a
        // medir la tablaroca". Mas largo que eso ya es platica.
        guard !dicho.isEmpty, dicho.split(separator: " ").count <= 6 else { return nil }
        // La palabra MAS LARGA que case gana: "carpet pad" antes que "carpet",
        // si no, pedir la almohadilla escogeria la alfombra.
        // Lo que EL enseño va primero: es su palabra, no la nuestra.
        if let valor = aprendidas[dicho], valores.contains(valor) { return valor }
        // Se juntan TODAS las que casan, con la posicion donde casaron.
        var casan: [(valor: String, largo: Int, donde: Int)] = []
        for valor in valores {
            for palabra in (sinonimosMaterial[valor] ?? []) {
                let p = palabra.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
                guard let r = dicho.range(of: p) else { continue }
                let donde = dicho.distance(from: dicho.startIndex, to: r.lowerBound)
                if let i = casan.firstIndex(where: { $0.valor == valor }) {
                    if p.count > casan[i].largo { casan[i] = (valor, p.count, donde) }
                } else {
                    casan.append((valor, p.count, donde))
                }
            }
        }
        guard !casan.isEmpty else { return nil }
        // "NO es alfombra, es madera": lo que quiere es lo de DESPUES de la
        // negacion. Sin esto ganaba "alfombra" por ser la palabra mas larga, y
        // la app hacia justo lo contrario de lo que le pidieron - que es como
        // se quedaba "bloqueada creyendo que es alfombra".
        let niega = crudo.hasPrefix("no ") || crudo.contains(" no es ") || crudo.contains("no es ")
        if niega, casan.count >= 2 {
            return casan.max { $0.donde < $1.donde }?.valor
        }
        // Si no hay negacion, gana la palabra mas larga: "carpet pad" antes
        // que "carpet".
        return casan.max { $0.largo < $1.largo }?.valor
    }

    // ============ LA CONVERSACION DEL ARRANQUE ============
    //
    // Su pedido, tal cual: que al abrir la pantalla el asistente pregunte que
    // va a medir, que uno diga "laminado" y el solo lo escoja; que pregunte si
    // lleva underlayment y uno conteste si o no; y que al cerrar el largo
    // pregunte si ocupa el ancho. Todo hablado, sin tocar nada.
    //
    // UNA pregunta abierta a la vez. La ventana para contestar se arma cuando
    // la frase TERMINA de sonar, no mientras suena: el microfono se ignora
    // mientras el telefono habla, asi que armarla antes seria darle cero
    // tiempo real para contestar.
    private enum Paso {
        case queMide, llevaCompanero, ocupaAncho, sigueIgual
        // ---- Los pasos del recorrido ----
        case queNivel        // una sola vez por recorrido: ese era el pedido
        case queCuarto       // "¿qué cuarto vamos a medir?"
        case queSeccion      // "¿con qué empezamos: piso, pared o techo?"
        case masOtraSeccion  // "¿cambiamos de sección, o pasamos a otro cuarto?"
    }
    private var pasoAbierto: Paso?

    private func preguntar(_ paso: Paso, _ frase: String) {
        // Si lo que se le va a preguntar es QUE MIDE, la camara mira al mismo
        // tiempo. Si reconoce algo, la pregunta se vuelve un si o un no, que se
        // contesta mucho mas rapido que nombrar un material.
        if paso == .queMide { materialQueVio = nil; mirarPorLaCamara(porqueLoPidio: false) }
        pasoAbierto = nil
        say(frase, .aviso)
        // Se arma cuando termine de hablar (ver speechSynthesizer didFinish).
        pasoPorArmar = paso
    }
    private var pasoPorArmar: Paso?

    // ¿Se muestra la lista de materiales encima de la camara?
    //
    // Su reporte: "no me tiene que aparecer mero enfrente de la pantalla".
    // Tenia razon: la lista se plantaba sola tapando la camara y obligando a
    // escoger con el dedo, que es justo lo que la voz venia a quitar. Ahora la
    // camara arranca LIMPIA, el asistente pregunta, y la lista solo sale si el
    // la pide con el boton - o si el telefono no puede escuchar, donde el dedo
    // es la unica via.
    private var listaVisible = false
    // Que paso esta escogiendo el selector ahorita. `.queMide` = materiales,
    // que es lo de siempre.
    private var pasoDelSelector: Paso = .queMide
    private let listaButton = UIButton(type: .system)

    private enum Orden: Equatable {
        case marcar, terminarRecorrido, medirAncho, guardar, terminar, deshacer, ayuda, dondeVoy, silencio
        // Nuevas, de lo que el pidio y de lo que hace falta estando alla:
        case cancelar        // "cancela" - tirar la medida que va a medias
        case cuantoLlevo     // "¿cuánto llevo?" - el total, sin bajar la vista
        case queMaterial     // "¿qué material?" - confirmar lo que escogio
        case cambiarMaterial // "otro material" - se equivoco al escoger
        case abrirLista      // "lista" - prefiere el dedo esta vez
        case repite          // "¿qué dijiste?" - no oyo por el ruido
        case masDespacio, masRapido
        case comoEstas       // "¿estás bien?" / "¿tienes inteligencia?" - el diagnostico hablado
        // La insulacion, hablando, sin buscar la casilla:
        case ponerCompanero, quitarCompanero
        // ---- El recorrido ----
        case otroCuarto, cambiarSeccion, cambiarNivel
        // ---- Decir la medida en vez de caminarla ----
        case numero(Double)          // "tres pies" - el ancho que ya trae sabido
        case porDos(Double, Double)  // "doce por diez" - las dos de un jalon
        case otraIgual               // "otra igual" - cinco closets identicos
        // ---- Aguantar la interrupcion ----
        case esperame, yaEstoy       // el dueño de la casa le habla a media medida
        case queComandos             // "¿qué te puedo decir?" - la lista, hablada
        case queVes                  // "¿qué ves?" - el ojo de la camara
        case queAprendiste           // "¿qué has aprendido?" - que sea revisable
        case olvidaLoAprendido       // si aprendio mal, tiene que haber como borrarlo
    }

    // Aparte y sin estado para poder probarla. Aqui un error no es cosmetico:
    // si "terminar recorrido" cae en la rama de "terminar", le cierra la
    // sesion de medir cuando solo queria cerrar el recorrido.
    // ¿Lo dicho hasta ahora podria ser el principio de una orden mas larga?
    // Solo estas: todo lo demas se puede atender de inmediato.
    static func puedeCrecer(_ t: String) -> Bool {
        let ultimaPalabra = t.split(separator: " ").last.map(String.init) ?? t
        let principios = ["terminar", "termina", "cerrar", "cierra", "medir", "ya"]
        return principios.contains(ultimaPalabra)
    }

    // LA POLITICA DE LARGO, que era el techo de verdad de la comprension.
    //
    // Antes: `guard palabras <= 4 else { return nil }`. TODA frase de cinco
    // palabras o mas se tiraba sin leerla. Y el no habla en palabras sueltas -
    // dice "ok, ahora vamos a medir la pared", "ya terminamos con este cuarto".
    // Esas iban a la basura y la app parecia sorda.
    //
    // Pero el limite estaba por una razon buena: la platica de la casa no
    // puede dar ordenes. Asi que ahora son DOS niveles:
    //   1. Corta (<=4 tras quitarle el relleno): las reglas de siempre.
    //   2. Larga (<=8): SOLO frases inconfundibles, dichas a la app, y ninguna
    //      que tire trabajo sin preguntar.
    private static func ordenDe(_ t: String) -> Orden? {
        // SE PRUEBAN LAS DOS: la frase pelada y la frase tal como la dijo.
        //
        // Quitar el relleno abre la puerta a frases largas, pero ya mordio TRES
        // veces comiendose una orden de verdad: " va" se tragaba "cuánto va",
        // "ahorita " se tragaba "ahorita no", y "mira " se tragaba "mira esto".
        // Cada vez lo arregle quitando esa palabra de la lista, y cada vez
        // volvio a pasar con otra. Probando las dos formas el problema se acaba
        // de raiz: si una palabra de relleno era parte de la orden, la version
        // sin pelar la agarra.
        let pelada = sinRelleno(t)
        let palabras = pelada.split(separator: " ").count
        let crudas = t.split(separator: " ").count
        if pelada != t {
            if crudas <= 8, let o = reglasLargas(t) { return o }
            if crudas <= 4, let o = reglas(t) { return o }
        }
        // LAS INCONFUNDIBLES PRIMERO, midan lo que midan. Son frases de varias
        // palabras que no salen por accidente, y tienen que ganarle a
        // cualquier regla mas floja de abajo.
        //
        // Esto ya mordio: "espera un momento" son TRES palabras, asi que caia
        // en las reglas cortas, y alla abajo el "un" de adentro la convertia
        // en un ancho de un pie. Una pausa se volvia una medida.
        if palabras <= 8, let o = reglasLargas(pelada) { return o }
        if palabras <= 4, let o = reglas(pelada) { return o }
        // LA RED ANCHA, hasta el final. Lo que las reglas exactas no agarraron
        // todavia puede ser una orden dicha de otra forma.
        //
        // PERO SOLO EN FRASES CORTAS, y esto se aprendio de golpe: con ocho
        // palabras empezo a obedecer la platica de la casa - "vamos mas
        // despacio con el cliente" le hablaba al compañero, no a la app, y
        // "lista de materiales para la oficina" le abria la lista. Una orden de
        // verdad es corta y casi todo en ella es la orden. Lo largo ya lo
        // cubre reglasLargas, que es una lista curada, no una red.
        if palabras <= 4, let o = porPatron(pelada) { return o }
        // Y la frase SIN pelar. "Vamos" y "ahora" son relleno conversacional y
        // TAMBIEN son verbos de la tabla, asi que al pelar la frase se le
        // quitaba justo el verbo: "vamos al ancho" salia muda.
        if t.split(separator: " ").count <= 4, let o = porPatron(t) { return o }
        return nil
    }

    // Las frases largas que SI son una orden. Lista corta y explicita a
    // proposito: aqui no se adivina. Cada una tiene al menos dos palabras que
    // juntas no salen en una platica de casa.
    private static func reglasLargas(_ t: String) -> Orden? {
        // El ingles tambien aqui: metido solo en `reglas` se quedaba con el
        // techo de cuatro palabras, y en ingles se habla mas largo - "how much
        // do we have" son cinco y no llegaba nunca.
        if let o = reglasIngles(t) { return o }
        // Terminar de medir un cuarto, como se dice de verdad.
        if t.contains("terminamos con este cuarto") || t.contains("acabamos con este cuarto")
            || t.contains("terminamos este cuarto") || t.contains("acabamos este cuarto")
            || t.contains("pasamos al siguiente cuarto") || t.contains("vamos al siguiente cuarto")
            || t.contains("pasamos a otro cuarto") || t.contains("nos pasamos a otro") { return .otroCuarto }
        if t.contains("terminamos con este nivel") || t.contains("acabamos con este piso")
            || t.contains("nos vamos para arriba") || t.contains("nos vamos para abajo")
            || t.contains("subimos al siguiente") || t.contains("bajamos al siguiente") { return .cambiarNivel }
        if t.contains("acabamos con todo") || t.contains("terminamos con todo")
            || t.contains("terminamos de medir") || t.contains("acabamos de medir")
            || t.contains("ya esta todo medido") || t.contains("ya esta todo")
            || t.contains("ya quedo todo") || t.contains("eso es todo") { return .terminar }
        if t.contains("guarda esa medida") || t.contains("guarda esta medida")
            || t.contains("guardala asi") || t.contains("ya quedo guardalo")
            || t.contains("apunta esa medida") { return .guardar }
        if t.contains("quita la ultima marca") || t.contains("borra la ultima marca")
            || t.contains("quita el ultimo punto") || t.contains("quitale la ultima")
            || t.contains("esa marca esta mal") || t.contains("ese punto esta mal") { return .deshacer }
        if t.contains("cuanto llevamos") || t.contains("cuanto vamos hasta")
            || t.contains("cuanto tenemos hasta") { return .cuantoLlevo }
        if t.contains("que material escogimos") || t.contains("que material pusimos")
            || t.contains("cual material escogimos") { return .queMaterial }
        if t.contains("me equivoque de material") || t.contains("escogi mal el material")
            || t.contains("ese no es el material") { return .cambiarMaterial }
        // "YA NO QUIERO MEDIR PARED, QUIERO MEDIR OTRA COSA."
        //
        // Su reporte, palabra por palabra: "le repito y le repito que ya no
        // quiero medir pared, quiero medir otra cosa y no me entiende".
        //
        // Y no entendia por DOS razones a la vez: la frase pasa de cuatro
        // palabras, asi que solo la podian agarrar estas reglas largas - que
        // no la tenian - y ademas trae un "no", que apaga la red ancha de
        // patrones entera. Las dos puertas cerradas para la forma mas natural
        // de decirlo.
        if t.contains("ya no quiero medir") || t.contains("no quiero medir")
            || t.contains("ya no quiero esta") || t.contains("ya no quiero este")
            || t.contains("ya no estoy midiendo") || t.contains("ya no es")
            || t.contains("quiero medir otra cosa") || t.contains("quiero medir otro")
            || t.contains("medir algo diferente") || t.contains("medir otra cosa")
            || t.contains("cambiar lo que estoy midiendo")
            || t.contains("cambiame lo que estoy midiendo") {
            // ¿Nombro una seccion? Aunque sea para decir que NO quiere esa, ya
            // se sabe que quiere salirse de donde esta: se le ofrecen las
            // cuatro y escoge. Si no nombro ninguna, es el material lo que
            // quiere cambiar y ahi se le vuelve a preguntar que va a medir.
            // Se buscan las palabras a mano en vez de usar `seccionDicha`:
            // esa corta en cinco palabras - con razon, porque suelta no puede
            // andar leyendo secciones dentro de la platica de la casa - y
            // "ya no quiero medir el techo" son seis. Aqui ya se sabe que la
            // frase le habla a la app, asi que el limite no hace falta.
            let nombraSeccion = ["piso", "pared", "techo", "cocina", "cielo", "muro",
                                 "floor", "wall", "ceiling", "kitchen", "suelo"]
                .contains { tienePalabra(t, $0) }
            return nombraSeccion ? .cambiarSeccion : .cambiarMaterial
        }
        // Que le puedo decir: esto es lo que la cuadrilla nunca sabe.
        if t.contains("que te puedo decir") || t.contains("que comandos") || t.contains("que ordenes")
            || t.contains("que sabes hacer") || t.contains("que puedo decirte")
            || t.contains("cuales son los comandos") { return .queComandos }
        // La interrupcion del dueño de la casa, dicha completa.
        if t.contains("espera un momento") || t.contains("esperame un momento")
            || t.contains("dame un momento")
            || t.contains("ya vuelvo contigo") { return .esperame }
        if t.contains("ya estoy listo") || t.contains("ya podemos seguir")
            || t.contains("ya le seguimos") || t.contains("continuamos") { return .yaEstoy }
        // Una medida dictada completa: "el ancho es de tres pies y medio".
        if let d = porDosDicho(t) { return .porDos(d.largo, d.ancho) }
        if t.contains("ancho") || t.contains("largo") || t.contains("mide"),
           let pies = piesDichos(t) { return .numero(pies) }
        return nil
    }

    // Como le dice la cuadrilla a lo que va DEBAJO del material: insulacion
    // bajo la tablaroca, almohadilla bajo la alfombra, underlayment bajo el
    // laminado. Escrito UNA vez porque lo consultan dos reglas distintas.
    private static func nombraElCompanero(_ t: String) -> Bool {
        if t.contains("insulacion") || t.contains("insulación") || t.contains("insulation")
            || t.contains("aislamiento") || t.contains("almohadilla") || t.contains("padding")
            || t.contains("underlayment") || t.contains("el forro") || t.contains("la espuma")
            || t.contains("lo de abajo") || t.contains("la base") { return true }
        // "Sí, lleva shoe molding" - la respuesta natural a "¿lleva shoe
        // molding?". Sin esto caía en la corrección de material y le cambiaba
        // la medida de zócalo a shoe molding, que es el mismo hueco que ya
        // tuvo la insulación.
        if t.contains("shoe") || t.contains("chu molding") || t.contains("su molding")
            || t.contains("zapata") || t.contains("cuarto rredondo")
            || t.contains("cuarto redondo") || t.contains("molding") { return true }
        return tienePalabra(t, "pad")
    }

    // Las ordenes dichas EN INGLES. Ahora que corre un reconocedor en ingles
    // sobre el mismo audio, estas llegan escritas bien y hay que conocerlas:
    // la cuadrilla brinca de un idioma al otro a media frase todo el dia.
    private static func reglasIngles(_ t: String) -> Orden? {
        // TODO POR FRASE COMPLETA, nunca por pedazo. Las palabras inglesas de
        // mando son cortisimas y viven dentro de palabras españolas de todos
        // los dias: "undo" vive en "seg-UNDO", "here" en "ad-HIERE", "mark" en
        // "MARK-eting", "list" en "LIST-a". Con `contains`, decir "espera un
        // segundo" BORRABA la ultima esquina. Es el mismo error que ya mordio
        // ocho veces en este archivo; esta es la novena y la ultima.
        func d(_ f: String) -> Bool { return traeFrase(t, f) }
        if d("finish path") || d("close the path") || d("done with the path")
            || d("close path") { return .terminarRecorrido }
        if d("measure width") || d("width") || d("the width") { return .medirAncho }
        if d("undo") || d("delete that") || d("remove that")
            || d("take that off") || d("erase that") || d("go back") { return .deshacer }
        if d("save it") || d("save") || d("save this")
            || d("save and continue") { return .guardar }
        if d("all done") || d("we are done") || d("we're done")
            || d("finish") || d("send it") || d("that's it") || d("thats it") { return .terminar }
        if d("next room") || d("another room") || d("other room") || d("new room") { return .otroCuarto }
        if d("next level") || d("another level") || d("upstairs") || d("downstairs") { return .cambiarNivel }
        if d("another section") || d("change section") || d("different section") { return .cambiarSeccion }
        if d("how much") || d("what's the total") || d("whats the total")
            || d("the total") { return .cuantoLlevo }
        if d("what material") || d("which material") { return .queMaterial }
        if d("wrong material") || d("change the material") || d("change material")
            || d("i messed up") { return .cambiarMaterial }
        if d("show the list") || d("the list") { return .abrirLista }
        if d("where am i") || d("what's next") || d("whats next") || d("how am i doing") { return .dondeVoy }
        if d("help me") || d("help") { return .ayuda }
        if d("be quiet") || d("shut up") || d("quiet") || d("stop talking") { return .silencio }
        if d("hold on") || d("wait a second") || d("wait a minute") || d("wait")
            || d("give me a second") || d("one second") { return .esperame }
        if d("i'm back") || d("im back") || d("go ahead") || d("keep going")
            || d("let's go") { return .yaEstoy }
        if d("same as that") || d("another one like") || d("one more like")
            || d("do it again") { return .otraIgual }
        if d("what do you see") || d("what is this") || d("what's this") { return .queVes }
        if d("add insulation") || d("with insulation") || d("put insulation") { return .ponerCompanero }
        if d("no insulation") || d("without insulation") || d("remove insulation") { return .quitarCompanero }
        // "Mark" va de ultimo, igual que "marca": la mas corta y la que mas
        // facil se confunde.
        if d("mark") || d("mark it") || d("here") || d("right here")
            || d("point") || d("corner") || d("mark it here")
            || d("put a mark") || d("add a point") { return .marcar }
        return nil
    }

    private static func reglas(_ t: String) -> Orden? {
        // El ingles primero, y es barato: si la frase venia en ingles, ninguna
        // regla de español la iba a agarrar de todos modos.
        if let o = reglasIngles(t) { return o }

        // EL ORDEN IMPORTA: "terminar recorrido" contiene "terminar", asi que
        // va primero. Al reves, decir "terminar recorrido" cerraria todo.
        // CERRAR EL RECORRIDO, y esto tiene que ganarle a "terminar" pase lo que
        // pase. Se probaban cuatro frases exactas, y bastaba un "el" de mas
        // para romperlo: "TERMINAR EL RECORRIDO" - dicho asi, con el articulo,
        // que es como se dice - no casaba con ninguna y caia en terminar, que
        // cierra la sesion entera. Ahora se busca el verbo y el objeto por
        // separado, y el articulo de en medio ya no importa.
        let cierraVerbo = ["terminar", "termina", "termino", "terminamos", "cerrar", "cierra",
                           "cierro", "cerramos", "acabar", "acaba", "acabamos", "ya"]
        let cierraObjeto = ["recorrido", "el largo", "la linea", "la línea", "el camino",
                            "la vuelta", "el perimetro", "el perímetro", "las esquinas"]
        if cierraObjeto.contains(where: { t.contains($0) }),
           cierraVerbo.contains(where: { tienePalabra(t, $0) }) { return .terminarRecorrido }
        if t.contains("medir ancho") || t == "ancho" || t.hasPrefix("ancho ")
            || t.contains("el ancho") { return .medirAncho }
        // COMO LO DICE DE VERDAD, no como lo diria un manual: "quita esa
        // marca", "desmarca", "borra ese punto". Antes solo entendia
        // "deshacer" pelado y por eso parecia que no hacia caso.
        if t.contains("deshacer") || t.contains("deshaz") || t.contains("borralo")
            || t.contains("bórralo") || t.contains("quita eso") || t.contains("desmarca")
            || t.contains("quita esa marca") || t.contains("quita la marca")
            || t.contains("borra esa marca") || t.contains("borra la marca")
            || t.contains("quita ese punto") || t.contains("borra ese punto")
            || t.contains("devuelvete") || t.contains("devuélvete") || t.contains("regresate")
            || t.contains("regrésate") || t.contains("desmarcalo") || t.contains("desmárcalo")
            || t.contains("quitale") || t.contains("quítale") {
            // ...salvo cuando lo que quiere quitar es el COMPAÑERO. "Quítale la
            // almohadilla" no borra una esquina: destilda la casilla. Sin esta
            // salida, deshacer se lo robaba y borraba una marca buena.
            if !nombraElCompanero(t) { return .deshacer }
        }
        // "Guarda silencio" es callarse, no guardar la medida - y con "guarda"
        // revisado antes que "silencio", pedir silencio BANCABA la medida.
        if t.contains("silencio") || t.contains("callate") || t.contains("cállate")
            || t.contains("callese") || t.contains("cállese") || t.contains("la boca")
            || t.contains("no hables") || t.contains("deja de hablar") { return .silencio }
        if t.contains("guardar") || t.contains("guarda") || t.contains("guardalo")
            || t.contains("guárdalo") { return .guardar }
        if t.contains("terminar") || t.contains("termine") || t.contains("terminé")
            || t.contains("ya acabe") || t.contains("ya acabé") { return .terminar }
        if t.contains("ayuda") || t.contains("ayudame") || t.contains("ayúdame") { return .ayuda }
        if t.contains("donde voy") || t.contains("dónde voy") || t.contains("como voy")
            || t.contains("cómo voy") || t.contains("donde estoy") || t.contains("dónde estoy")
            || t.contains("que sigue") || t.contains("qué sigue") { return .dondeVoy }
        if t.contains("silencio") || t.contains("callate") || t.contains("cállate") { return .silencio }
        // EL RECORRIDO, y va ARRIBA de casi todo: "otro cuarto" contiene
        // "cuarto", y "cambiar de nivel" contiene "cambiar" - si se revisaran
        // despues, caerian en la rama equivocada.
        if t.contains("otro cuarto") || t.contains("siguiente cuarto")
            || t.contains("cambiar de cuarto") || t.contains("cambia de cuarto")
            || t.contains("pasamos a otro") || t.contains("siguiente pieza") { return .otroCuarto }
        if t.contains("otro nivel") || t.contains("cambiar de nivel") || t.contains("cambia de nivel")
            || t.contains("otro piso") || t.contains("subimos") || t.contains("bajamos") { return .cambiarNivel }
        if t.contains("otra seccion") || t.contains("otra sección")
            || t.contains("cambiar de seccion") || t.contains("cambiar de sección")
            || t.contains("cambia de seccion") || t.contains("cambia de sección") { return .cambiarSeccion }

        // Y ANTES DE CANCELAR: "olvídalo" ya quiere decir cancelar la medida,
        // asi que olvidar lo APRENDIDO tiene que pedirse completo o se lo come.
        if t.contains("olvida lo que aprendiste") || t.contains("olvídalo que aprendiste")
            || t.contains("olvida todo lo que aprendiste") || t.contains("borra lo que aprendiste")
            || t.contains("olvida lo aprendido") || t.contains("empieza a aprender de nuevo")
            || t.contains("ya no te acuerdes") { return .olvidaLoAprendido }

        // "Cancela" tiene que ir ANTES que nada que contenga "cancel".
        if t.contains("cancela") || t.contains("cancelar") || t.contains("olvidalo")
            || t.contains("olvídalo") || t.contains("borra todo")
            // "Empezar de nuevo" - se lo dijo y no le hacia caso porque esa
            // frase no existia en ningun lado.
            || t.contains("de nuevo") || t.contains("otra vez desde")
            || t.contains("empezamos de cero") || t.contains("desde el principio") { return .cancelar }
        if t.contains("cuanto llevo") || t.contains("cuánto llevo") || t.contains("cuanto va")
            || t.contains("cuánto va") || t.contains("cuanto tengo") || t.contains("el total") { return .cuantoLlevo }
        if t.contains("otro material") || t.contains("cambiar material") || t.contains("cambia el material")
            || t.contains("me equivoque") || t.contains("me equivoqué") { return .cambiarMaterial }
        if t.contains("que material") || t.contains("qué material") || t.contains("que escogi")
            || t.contains("qué escogí") { return .queMaterial }
        if t == "lista" || t.contains("la lista") || t.contains("ver la lista") { return .abrirLista }
        // "Otra igual" va ANTES que "repite": "repite la medida" trae "repite"
        // adentro y caia en repetir-lo-que-dijiste, asi que la regla de otra
        // igual estaba escrita pero muerta.
        if t.contains("otra igual") || t.contains("otro igual") || t.contains("lo mismo otra vez")
            || t.contains("igual que la anterior") || t.contains("la misma medida")
            || t.contains("otra como esa")
            // "Repite" solo es repetir-lo-que-dijiste si NO viene con algo que
            // hable de la medida anterior.
            || (t.contains("repite") && (t.contains("igual") || t.contains("misma")
                || t.contains("mismo") || t.contains("anterior") || t.contains("medida"))) { return .otraIgual }
        if t.contains("que dijiste") || t.contains("qué dijiste") || t.contains("repite")
            || t.contains("repitelo") || t.contains("repítelo") || t.contains("no te oi")
            || t.contains("no te oí") { return .repite }
        if t.contains("mas despacio") || t.contains("más despacio") || t.contains("mas lento")
            || t.contains("más lento") { return .masDespacio }
        if t.contains("mas rapido") || t.contains("más rápido") { return .masRapido }
        // "Añade insulación", "ponle insulación", "sí lleva insulación".
        // Un solo lugar donde se dice como se le llama a lo que va debajo: lo
        // usan la regla de poner/quitar Y el candado de deshacer, y tenerlo
        // escrito dos veces ya dejo a "quítale el forro" borrando una esquina.
        // "pad" SOLO como palabra completa. Suelta con contains mordia feo:
        // "empapado" la trae adentro ("empa-PAD-o"), y en una app de daños por
        // AGUA esa palabra se dice veinte veces al dia - prendia la insulacion
        // sola cada vez. "Padre" y "padrino" igual.
        if nombraElCompanero(t) {
            // Quitar se dice de muchas formas y solo se conocian cuatro:
            // "saca la insulación" y "retira el padding" la PONIAN, que es lo
            // contrario de lo que pidio - y se va derecho a la factura.
            if t.contains("quita") || t.contains("quítale") || t.contains("sin ")
                || t.contains("no lleva") || t.contains("no tiene") || t.contains("borra")
                || t.contains("saca") || t.contains("sácale") || t.contains("retira")
                || t.contains("elimina") || t.contains("no le pongas")
                || t.contains("no cuentes") { return .quitarCompanero }
            return .ponerCompanero
        }
        if t.contains("estas bien") || t.contains("estás bien") || t.contains("me escuchas")
            || t.contains("me oyes") || t.contains("inteligencia") || t.contains("estas ahi")
            || t.contains("estás ahí") { return .comoEstas }
        // ---- AGUANTAR LA INTERRUPCION ----
        // Pasa en cada casa: el dueño le habla a media medida. Antes no habia
        // forma de decirle a la app "espera" - o se callaba a mano con el
        // boton, o seguia preguntando encima de la conversacion.
        if t == "esperame" || t == "espérame" || t == "espera" || t == "espere"
            || t == "aguanta" || t == "aguantame" || t == "un momento"
            || t == "ahorita no" || t == "al rato" { return .esperame }
        if t == "ya estoy" || t == "ya" || t == "seguimos" || t == "continuemos"
            || t == "listo" || t == "ya regrese" || t == "ya regresé"
            || t == "aqui estoy" || t == "aquí estoy" { return .yaEstoy }

        // ---- LA LISTA DE LO QUE ENTIENDE, HABLADA ----
        // Su problema de siempre: "las personas que estan usando la aplicacion
        // no saben como usarla". La ayuda escrita no sirve con las dos manos
        // ocupadas y el telefono en alto.
        if t.contains("que te puedo decir") || t.contains("qué te puedo decir")
            || t.contains("que comandos") || t.contains("qué comandos")
            || t.contains("que ordenes") || t.contains("qué órdenes")
            || t.contains("que sabes hacer") || t.contains("qué sabes hacer") { return .queComandos }
        // ---- EL OJO ----
        if t.contains("que ves") || t.contains("qué ves") || t.contains("que estas viendo")
            || t.contains("qué estás viendo") || t.contains("que es esto") || t.contains("qué es esto")
            || t.contains("mira esto") || t.contains("checa esto") || t.contains("adivina") { return .queVes }
        // ---- LO QUE HA APRENDIDO, REVISABLE ----
        if t.contains("que aprendiste") || t.contains("qué aprendiste") || t.contains("que has aprendido")
            || t.contains("qué has aprendido") || t.contains("que te acuerdas") || t.contains("qué te acuerdas")
            || t.contains("que sabes de mi") || t.contains("qué sabes de mí") { return .queAprendiste }

        // "Marca" va de ULTIMO: es la orden mas corta y la que mas facil se
        // confunde, asi que solo gana si no era ninguna otra. Y solo como
        // palabra COMPLETA - "marcador" o "ya vamonos" no marcan una esquina.
        // "Ya" SE QUITO a proposito: es tambien el principio de "ya acabé",
        // asi que la app tendria que esperar a ver si crece - y marcar una
        // esquina es justo lo que mas veces se hace y mas rapido tiene que
        // ser. "Marca" y "aquí" no son el principio de nada: salen al
        // instante.
        // "Añade otra marca", "pon otra marca", "agrega un punto": son
        // frases, no palabras sueltas, asi que van con contains.
        if t.contains("otra marca") || t.contains("una marca") || t.contains("otro punto")
            || t.contains("un punto") || t.contains("pon marca") || t.contains("pon la marca")
            || t.contains("agrega marca") || t.contains("añade marca") { return .marcar }
        let sueltas: Set<String> = ["marca", "marque", "marcar", "aqui", "aquí", "punto", "esquina",
                                    "marcala", "márcala", "marcalo", "márcalo",
                                    "marquela", "marquelo", "aca", "acá", "ahi", "ahí"]
        if sueltas.contains(t) { return .marcar }

        // ---- UN NUMERO DICHO, Y VA HASTA EL FINAL ----
        // Tiene que ser lo ULTIMO que se prueba: "una marca" y "un punto"
        // traen un numero adentro, y ahi manda la orden, no el numero.
        if let d = porDosDicho(t) { return .porDos(d.largo, d.ancho) }
        if let pies = medidaComoOrden(t) { return .numero(pies) }
        return nil
    }

    // LA REGLA DE ORO DE LA VOZ: solo puede hacer lo que un dedo podria hacer
    // en ese momento. Si el boton no esta en pantalla, la orden no corre.
    //
    // Sin esta regla la voz se saltaba la pantalla entera: decir "guardar" a
    // media caminata guardaba con el recorrido abierto y dejaba un punto
    // colgando que se volvia un tramo fantasma en la MEDIDA SIGUIENTE; decir
    // "marca" con la lista de materiales encima plantaba una esquina que
    // nadie veia. Un boton escondido esta escondido por una razon.
    private func atenderOrden(_ t: String) {
        // Si la frase de verdad hace algo, es porque fue el: de ahi se aprende
        // su volumen normal. Aprender de todo lo que entra por el microfono
        // seria aprender tambien de quien pasa platicando.
        defer {
            ultimoAtenderHizoAlgo = hizoAlgo
            if hizoAlgo { VozAsistente.aprenderSuNivel(nivelDeEstaFrase); hizoAlgo = false }
        }
        // EN PAUSA: solo se atiende que lo despierten. Todo lo demas es la
        // conversacion con el cliente, y ahi la app no se mete.
        if enPausa {
            guard Self.ordenDe(t) == .yaEstoy else { return }
            enPausa = false
            hizoAlgo = true
            say("Aquí seguimos. " + situacionActual(), .aviso)
            return
        }
        // Contestar una pregunta abierta manda sobre todo lo demas: si le
        // preguntaron "¿lleva insulación?", un "sí" es la respuesta, no una
        // orden suelta.
        // Si hay una pregunta abierta PERO el nombro un material, eso es una
        // correccion, no una respuesta. Sin esto, "no, es madera" mientras la
        // app pregunta "¿lleva insulación?" se leia como un simple "no" y el
        // material nunca cambiaba - otra forma del mismo trabon.
        // PERO no cuando la pregunta abierta es "¿lleva insulación?" y el la
        // NOMBRA: "sí, lleva insulación" es la respuesta. Insulation es material
        // de pared, asi que esa frase caia AQUI y le cambiaba el Drywall por
        // Insulación -- el drywall se cobraba como insulación. contestar() ya
        // sabia leer esa frase; este camino llegaba antes y no la dejaba.
        //
        // Y SOLO si no nombra OTRO material. nombraElCompanero reconoce "molding"
        // suelto, asi que "no, es crown molding" con la pregunta "¿lleva shoe
        // molding?" abierta se leia como un "no" al compañero y el Crown se
        // cobraba como Baseboard. Si nombra un material, tiene que ser el
        // compañero mismo; si nombra otro, es una correccion.
        let contestaElCompanero: Bool = {
            guard let paso = pasoAbierto, case .llevaCompanero = paso, Self.nombraElCompanero(t) else { return false }
            let dicho = Self.materialDicho(t, entre: materials.map { $0.value })
            return dicho == nil || dicho == currentCompanion?.value
        }()
        if let paso = pasoAbierto, !esPreguntaDeMaterial(paso), !contestaElCompanero,
           Self.materialDicho(t, entre: materials.map { $0.value }) != nil,
           corrigioElMaterial(t) { hizoAlgo = true; return }
        if let paso = pasoAbierto, contestar(paso, t) { hizoAlgo = true; return }

        // ¿Esta CORRIGIENDO el material? "no, es madera", "medimos otro piso",
        // o de plano nada mas "madera".
        //
        // Este era el hueco que lo trababa: una vez escogido, decir "no" o
        // decir otro material NO HACIA NADA - la app se quedaba creyendo que
        // era alfombra y no habia como devolverla. El material es solo una
        // ETIQUETA hasta que se guarda, asi que cambiarlo NO pierde las
        // esquinas ya marcadas: se cambia y se sigue.
        if pasoAbierto == nil, corrigioElMaterial(t) { hizoAlgo = true; return }
        // Y si venia de una correccion, la pregunta que estaba abierta ya no
        // aplica: el cambio de material reinicia la conversacion.

        guard let orden = Self.ordenDe(t) else {
            // "AHORA LA PARED", suelto, sin que nadie le pregunte nada. En un
            // recorrido eso es un cambio de seccion y punto. Antes contestaba
            // "no le entendí", o gastaba una pregunta entera ("¿piso, pared,
            // techo o cocina?") para algo que el ya habia dicho.
            //
            // VA AQUI, DESPUES de las ordenes, y no antes. Puesto antes ya
            // mordio: "otro piso" quiere decir OTRO NIVEL, pero trae la
            // palabra "piso" adentro, asi que cambiaba de seccion en vez de
            // subir. Una orden completa siempre le gana a una palabra suelta.
            // Y NUNCA con una negacion adentro. "Ya no quiero medir pared"
            // nombra "pared", y sin este candado el atajo lo cambiaba A pared:
            // exactamente lo contrario de lo que pidio.
            if esRecorrido, pasoAbierto == nil, materialOverlay.isHidden, helpOverlay.isHidden,
               !Self.tienePalabra(t, "no"), !t.contains("tampoco"),
               let sec = Self.seccionDicha(Self.sinRelleno(t)), sec != section,
               seccionesDisponibles[sec] != nil {
                hizoAlgo = true
                if cambiarSeccion(sec) {
                    preguntar(.queMide, "\(Self.sectionSpokenName(sec).capitalized). ¿Qué va a medir?")
                }
                return
            }
            // ¿YA LA APRENDIO ANTES? Una frase suya que se aprendio de una
            // correccion entra aqui, antes que el modelo: es instantanea y no
            // depende de que el telefono traiga la inteligencia.
            if !reDespachando, let nombre = MemoriaAsistente.ordenAprendida(t),
               let canonica = Self.fraseCanonica[nombre] {
                reDespachando = true
                atenderOrden(canonica)
                reDespachando = false
                return
            }
            // Queda anotada por si ahorita hace con el dedo lo que queria: esa
            // pareja - frase que no entendi, cosa que hizo - es la leccion.
            fraseSinEntender = (t, Date())
            // AQUI ES DONDE ENTRA LA INTELIGENCIA, y solo aqui: las ordenes de
            // siempre ya fallaron. Antes esto era el final del camino - la
            // frase se tiraba y el se quedaba parado sin respuesta.
            pedirleALaIA(t)
            return
        }
        hizoAlgo = true
        // LA LECCION. Si hace nada no se entendia una frase y ahora esto SI se
        // entendio, la de antes queria decir esto. La proxima vez entra sola.
        if let sin = fraseSinEntender, Date().timeIntervalSince(sin.cuando) < 25, sin.frase != t {
            MemoriaAsistente.aprenderOrden(frase: sin.frase, orden: String(describing: orden))
            fraseSinEntender = nil
        }
        // Queda escrito de un dia para otro. Antes la conversacion vivia dentro
        // de la sesion del modelo, que muere al cerrar la camara: cada medida
        // empezaba de cero y no habia tal cosa como "acuérdate de lo que te dije".
        MemoriaAsistente.recordar(dijo: t, paso: String(describing: orden))

        // Con una ventana encima (materiales o ayuda) solo se atiende lo que
        // no toca la medida.
        // Solo cuenta como "ventana abierta" si el DE VERDAD la abrio. La
        // lista de materiales ya no se planta sola, asi que hablarle con la
        // camara limpia nunca mas contesta "primero cierre lo que tiene
        // abierto" - que era exactamente lo que le pasaba.
        let hayVentana = (!materialOverlay.isHidden && listaVisible) || !helpOverlay.isHidden
        if hayVentana {
            switch orden {
            case .ayuda:    helpTapped()
            case .silencio: if asistenteHabla { muteTapped() }
            case .dondeVoy: assistantTapped()
            default:        say("Primero cierre lo que tiene abierto en la pantalla.", .guia)
            }
            return
        }

        func siSeVe(_ boton: UIButton, _ accion: () -> Void, _ porque: String) {
            if boton.isHidden { say(porque, .guia) } else { accion() }
        }

        switch orden {
        case .terminarRecorrido:
            siSeVe(finishPathButton, { confirmarOrden("Terminando el recorrido."); finishPathTapped() },
                   "Todavía no. Marque al menos dos esquinas primero.")
        case .medirAncho:
            siSeVe(addWidthButton, { confirmarOrden("Ahora el ancho."); addWidthTapped() },
                   "Primero cierre el recorrido: diga terminar recorrido.")
        case .deshacer:
            siSeVe(undoButton, { undoTapped() }, "No hay nada que deshacer.")
        case .guardar:
            siSeVe(saveContinueButton, { saveContinueTapped() },
                   "Todavía no puedo guardar. Primero cierre el recorrido: diga terminar recorrido.")
        case .terminar:
            siSeVe(finishButton, { finishTapped() }, "Todavía no hay ninguna medida que mandar.")
        case .marcar:
            siSeVe(addButton, { addTapped() }, "Ahorita no toca marcar esquinas.")
        case .ayuda:    helpTapped()
        case .dondeVoy: assistantTapped()
        case .silencio: if asistenteHabla { muteTapped() }

        case .cancelar:
            // Tira lo que va a medias, NO lo ya guardado. Borrar medidas
            // guardadas con una palabra suelta seria demasiado fácil de hacer
            // sin querer; para eso esta "deshacer", que va de una en una.
            // Mira lo MISMO que el candado de cambiar de seccion (medidaEnCurso).
            // Si miraran cosas distintas, uno podia decir "no puede, tiene una
            // medida a medias" y el otro "no hay nada a medias que cancelar":
            // trabado sin salida.
            if !medidaEnCurso && selectedMaterial == nil {
                say("No hay nada a medias que cancelar.", .guia)
            } else {
                cancelarMedidaEnCurso()
            }
        case .cuantoLlevo:
            decirPorPeticion(totalHablado())
        case .queMaterial:
            if let m = selectedMaterial {
                decirPorPeticion("Está midiendo \(Self.nombreDeBoton(m)).")
            } else {
                decirPorPeticion("Todavía no ha escogido material.")
            }
        case .cambiarMaterial:
            cancelarMedidaEnCurso()
            preguntar(.queMide, "Ok. ¿Qué va a medir?")
        case .abrirLista:
            listaTapped()
        case .repite:
            decirPorPeticion(ultimoDicho.isEmpty ? situacionActual() : ultimoDicho)
        case .masDespacio:
            VozAsistente.ajustarRitmo(-0.12)
            decirPorPeticion("Así de despacio.")
        case .masRapido:
            VozAsistente.ajustarRitmo(0.12)
            decirPorPeticion("Así de rápido.")
        case .comoEstas:
            decirPorPeticion(diagnosticoHablado())
        case .otroCuarto:
            guard esRecorrido else { say("Eso es para un recorrido completo.", .guia); return }
            // Lo mismo que la pastilla "Otro cuarto": una medida COMPLETA se guarda
            // primero, en el cuarto donde se tomo. Lo que siga a medias despues de
            // eso NO: se contestaba el cuarto, y el siguiente Guardar mandaba la
            // medida de la sala a la cocina. Mismo candado que la seccion.
            if !saveContinueButton.isHidden { saveContinueTapped() }
            if medidaEnCurso { say("Primero guarde o cancele la medida que lleva.", .aviso); return }
            preguntar(.queCuarto, "¿Cómo se llama el siguiente cuarto?")
        case .cambiarSeccion:
            guard esRecorrido else { say("Eso es para un recorrido completo.", .guia); return }
            preguntar(.queSeccion, "¿Piso, pared, techo, cocina, baño o materiales?")
        case .cambiarNivel:
            guard esRecorrido else { say("Eso es para un recorrido completo.", .guia); return }
            if medidaEnCurso { say("Primero guarde o cancele la medida que lleva.", .aviso); return }
            preguntar(.queNivel, "¿A qué nivel pasamos?")
        case .esperame:
            enPausa = true
            // Esta frase SI sale: es el acuse de que se va a callar, y sin el
            // no hay forma de saber si lo oyo.
            forzarAunqueMudo = true
            say("Ok, aquí espero. Dígame ya estoy cuando siga.", .aviso)
            forzarAunqueMudo = false
        case .yaEstoy:
            // Fuera de pausa "ya estoy" no es una orden: es relleno. Que no
            // haga nada es lo correcto.
            break
        case .queComandos:
            decirPorPeticion(listaDeComandos())
        case .queVes:
            mirarPorLaCamara(porqueLoPidio: true)
        case .olvidaLoAprendido:
            MemoriaAsistente.olvidarTodo()
            decirPorPeticion("Listo, olvidé todo lo que había aprendido. Empiezo de cero.")
        case .queAprendiste:
            let l = MemoriaAsistente.loQueAprendio(materiales: materials.map { $0.value })
            decirPorPeticion(l.isEmpty
                ? "Todavía nada. Después de unas cuantas medidas ya le voy agarrando el modo."
                : "He aprendido que " + l.joined(separator: "; ") + ".")
        case .otraIgual:
            repetirUltimaMedida()
        case .numero(let pies):
            anotarAncho(pies)
        case .porDos(let largo, let ancho):
            anotarLargoYAncho(largo: largo, ancho: ancho)

        case .ponerCompanero, .quitarCompanero:
            guard let c = currentCompanion else {
                say("Este material no lleva nada debajo.", .guia)
                return
            }
            includeCompanion = (orden == .ponerCompanero)
            updateUI()
            say(includeCompanion
                ? "Anotado, con \(c.es.lowercased())."
                : "Ok, sin \(c.es.lowercased()).", .aviso)
        }
    }

    // ============ ANOTAR UNA MEDIDA DICHA ============
    //
    // El ancho es el numero que mas veces ya trae sabido: un pasillo de 3
    // pies, una puerta de 3, un corte de pared de 2. Antes cada uno de esos
    // costaba una pasada entera de camara.
    //
    // SE REPITE EN VOZ ALTA SIEMPRE. Un numero mal oido que entra callado sale
    // en la factura; dicho en voz alta se corrige ahi mismo con "deshacer".
    private func anotarAncho(_ pies: Double) {
        // CONTESTAR LA PREGUNTA CON EL NUMERO. La app pregunta "¿ocupa
        // ancho?" y lo mas natural del mundo es contestar "tres pies" - no
        // "sí" y despues el numero. Antes eso caia en el guard de abajo y lo
        // mandaba a cerrar el recorrido: le preguntaba algo y castigaba la
        // respuesta correcta. Aqui se hace lo mismo que hace el "sí": se
        // cierra el largo solo, y el numero entra.
        if stage == .measuringLength, hasLengthMeasurement {
            pasoAbierto = nil
            finishPathTapped()
        }
        // El candado de siempre: solo donde un dedo podria hacerlo. El ancho
        // solo existe cuando el largo ya esta cerrado.
        guard stage == .lengthDone || stage == .measuringWidth else {
            if stage == .measuringLength {
                say("Primero marque el largo, o dígame las dos: por ejemplo doce por diez.", .guia)
            } else {
                say("Primero escoja el material.", .guia)
            }
            return
        }
        pasoAbierto = nil
        pendingStartNode?.removeFromParentNode()
        if let node = pendingStartNode, let idx = currentMarkers.firstIndex(of: node) {
            currentMarkers.remove(at: idx)
        }
        pendingStart = nil
        pendingStartNode = nil
        lineLayer.path = nil
        // Un ancho DICTADO borra las esquinas caminadas del ancho: no se mezclan
        // las dichas con las caminadas, la misma regla que ya tiene el largo.
        widthPoints = []
        currentWidthFeet = pies
        yaAvisoFaltaAncho = false
        stage = .widthDone
        say("Ancho, \(Self.piesHablados(pies)).", .aviso)
    }

    // "Doce por diez": las dos medidas de un jalon, sin caminar ninguna.
    private func anotarLargoYAncho(largo: Double, ancho: Double) {
        guard selectedMaterial != nil else {
            say("Primero dígame qué va a medir.", .guia)
            return
        }
        // NO SE MEZCLAN las dichas con las caminadas. Si ya hay esquinas
        // puestas, meterle un largo dictado encima dejaria dos verdades sobre
        // la misma medida y `recomputePathTotal` borraria la dictada sin avisar.
        guard pathPoints.isEmpty else {
            say("Ya tiene esquinas marcadas. Diga cancela si quiere dictarla.", .guia)
            return
        }
        pasoAbierto = nil
        pathTotalFeet = largo
        largoDictado = true
        widthPoints = []
        currentWidthFeet = ancho
        yaAvisoFaltaAncho = false
        stage = .widthDone
        say("\(Self.piesHablados(largo)) por \(Self.piesHablados(ancho)).", .aviso)
    }

    // Medio pie no se dice "0.5 pies": se dice "y medio".
    private static func piesHablados(_ ft: Double) -> String {
        let entero = Int(ft)
        let resto = ft - Double(entero)
        let unidad = entero == 1 && resto < 0.01 ? "pie" : "pies"
        if resto < 0.01 { return "\(entero) \(unidad)" }
        if abs(resto - 0.5) < 0.02 { return entero == 0 ? "medio pie" : "\(entero) pies y medio" }
        if abs(resto - 0.25) < 0.02 { return entero == 0 ? "un cuarto de pie" : "\(entero) pies y cuarto" }
        if abs(resto - 0.75) < 0.02 { return "\(entero) pies y tres cuartos" }
        return String(format: "%.1f pies", ft)
    }

    // ============ OTRA IGUAL ============
    //
    // Cinco closets del mismo tamaño, cinco puertas iguales, tres ventanas
    // iguales. Antes habia que volver a escoger material y volver a medir el
    // ancho en cada una, aunque fuera el mismo numero cinco veces.
    private func repetirUltimaMedida() {
        guard let ultima = items.last else {
            say("Todavía no hay ninguna medida que repetir.", .guia)
            return
        }
        // medidaEnCurso, no "sin esquinas y sin ancho": un largo DICTADO ("doce
        // por diez", y luego Deshacer el ancho) pasaba este candado, y "otra
        // igual" le sumaba el largo caminado encima: 12 + 8 = 20 pies cobrados.
        guard !medidaEnCurso else {
            say("Primero termine o cancele la que lleva a medias.", .guia)
            return
        }
        guard let material = materials.first(where: { $0.value == ultima.material }) else {
            say("Esa medida era de otra sección.", .guia)
            return
        }
        selectedMaterial = material
        arrancarConteoSiHaceFalta()
        if let fila = materials.firstIndex(where: { $0.value == material.value }) {
            materialPickerView.selectRow(fila, inComponent: 0, animated: false)
        }
        // "Otra igual" SI copia el compañero, y esta bien: es una copia que el
        // pidio con esas palabras, no una costumbre que la app adivino. Pero
        // TIENE que oirlo - si no, es otra insulacion que aparece sin que el
        // sepa, que es justo de lo que se quejo.
        includeCompanion = (ultima.companion != nil)
        let nombre = Self.nombreDeBoton(material)
        var conQue = ""
        if includeCompanion, let c = currentCompanion { conQue = ", con \(c.es.lowercased())" }
        if let ancho = ultima.width {
            widthPoints = []
            currentWidthFeet = ancho
            yaAvisoFaltaAncho = false
            stage = .measuringLength
            say("Otra igual: \(nombre)\(conQue), \(Self.piesHablados(ancho)) de ancho. Marque las esquinas.", .aviso)
        } else {
            stage = .measuringLength
            say("Otra igual: \(nombre)\(conQue). Marque las esquinas.", .aviso)
        }
        updateUI()
    }

    // ============ EL OJO DE LA CAMARA ============
    //
    // Su pedido: "que puedan ver por la cámara lo que se va a medir".
    //
    // Lo que ve NUNCA escoge: se OFRECE como pregunta de sí o no. Un "no" le
    // cuesta una palabra; un material escogido solo y equivocado le cuesta una
    // linea mal facturada que nadie ve hasta que el ajustador la rebota.
    //
    // Y dice la verdad sobre lo que no puede: laminado, madera y vinil son tres
    // tablas cafes con veta, y ni una persona las distingue segura en una foto.
    private var materialQueVio: String?

    private func mirarPorLaCamara(porqueLoPidio: Bool) {
        // NO mientras la camara apenas arranca. Vision sobre el primer cuadro,
        // encima de ARKit inicializandose, es parte de lo que trababa el
        // arranque - y ademas en ese momento la camara todavia no esta
        // enfocada, asi que lo que vea no vale nada.
        if !porqueLoPidio, Date().timeIntervalSince(camaraDesde) < 2.5 { return }
        guard let cuadro = sceneView.session.currentFrame?.capturedImage else {
            if porqueLoPidio { say("La cámara todavía no arranca bien.", .guia) }
            return
        }
        OjoDeLaCamara.mirar(cuadro, entre: materials.map { $0.value }) { [weak self] v in
            guard let self = self, let v = v else {
                if porqueLoPidio { self?.decirPorPeticion("No alcanzo a reconocer nada desde aquí.") }
                return
            }
            if porqueLoPidio {
                var partes: [String] = []
                if let m = v.material {
                    let nombre = self.materials.first(where: { $0.value == m })
                        .map { Self.nombreDeBoton($0) } ?? m
                    partes.append("Se me hace que es \(nombre.lowercased())")
                }
                if let c = v.cuarto { partes.append("y parece \(c)") }
                if partes.isEmpty, let primera = v.etiquetas.first {
                    partes.append("Veo algo como \(primera.nombre), pero no es de lo que medimos")
                }
                self.decirPorPeticion(partes.joined(separator: ", ") + ".")
                return
            }
            // No lo pidio: se le ofrece SOLO si sigue esperando saber que mide.
            guard self.pasoAbierto == .queMide, v.material != nil,
                  let m = v.material,
                  let opcion = self.materials.first(where: { $0.value == m }) else { return }
            let nombre = Self.nombreDeBoton(opcion)
            self.materialQueVio = m
            self.say("¿Es \(nombre.lowercased())?", .aviso)
            self.pasoPorArmar = .queMide
        }
    }

    // ============ LO QUE LE PUEDE DECIR ============
    //
    // Su queja de siempre: "las personas que estan usando la aplicacion no
    // saben como usarla". La ayuda escrita no sirve con las dos manos ocupadas
    // y el telefono en alto, asi que esta lista se OYE.
    //
    // Se arma con lo que de verdad se puede hacer AHORITA, no con todo el
    // catalogo: leerle veinte ordenes de las cuales tres sirven en este
    // momento es lo mismo que no decirle nada.
    private func listaDeComandos() -> String {
        var puede: [String] = []
        if !addButton.isHidden          { puede.append("marca, para poner una esquina") }
        if !finishPathButton.isHidden   { puede.append("terminar recorrido") }
        if !addWidthButton.isHidden     { puede.append("medir ancho, o dígame el número: tres pies") }
        if !undoButton.isHidden         { puede.append("deshacer") }
        if !saveContinueButton.isHidden { puede.append("guardar") }
        if !finishButton.isHidden       { puede.append("terminar") }
        if selectedMaterial == nil      { puede.append("el material: laminado, tablaroca, alfombra") }
        if !items.isEmpty               { puede.append("otra igual") }
        if esRecorrido                  { puede.append("otro cuarto, otra sección, cambiar de nivel") }
        var frase = puede.isEmpty ? "" : "Ahorita puede decirme: " + puede.joined(separator: "; ") + ". "
        frase += "Cuando quiera: cuánto llevo, qué material, cómo voy, más despacio, "
        frase += "espérate si lo interrumpen, y ya estoy para seguir."
        // Y lo mas util de todo, si el telefono lo trae: que no tiene que
        // aprenderse ninguna lista.
        if AsistenteIA.disponible {
            frase += " Y no tiene que decirlo exacto: hábleme normal y pregúnteme lo que sea."
        }
        return frase
    }

    // Tirar la medida a medias y volver a empezar limpio.
    private func cancelarMedidaEnCurso(hablar: Bool = true) {
        currentMarkers.forEach { $0.removeFromParentNode() }
        currentMarkers = []
        currentLines.forEach { $0.removeFromParentNode() }
        currentLines = []
        pathPoints = []
        pathTotalFeet = 0
        largoDictado = false
        widthPoints = []
        currentWidthFeet = nil
        pendingStart = nil
        pendingStartNode = nil
        lineLayer.path = nil
        includeCompanion = false
        selectedMaterial = nil
        yaAvisoFaltaAncho = false
        medidaNueva()
        if hablar { say("Cancelado.", .aviso) }
        stage = (materials.isEmpty && !esRecorrido) ? .measuringLength : .pickingMaterial
    }

    // EL DIAGNOSTICO, EN VOZ ALTA. Antes, si algo no jalaba, el unico sintoma
    // era el silencio - y del silencio no se puede deducir nada. Ahora se le
    // pregunta a la app y ella dice exactamente que trae y que le falta.
    private func diagnosticoHablado() -> String {
        var p: [String] = []
        p.append(micApagadoPorElUsuario ? "El micrófono está apagado por usted"
                 : (motorAudio != nil ? "Sí lo estoy escuchando" : "El micrófono no está prendido"))
        if AsistenteIA.disponible {
            p.append("y la inteligencia está lista")
        } else if let porque = AsistenteIA.porQueNo {
            p.append("pero la inteligencia no. " + porque)
        } else {
            p.append("pero este teléfono no trae la inteligencia de Apple. Las órdenes de siempre funcionan igual")
        }
        return p.joined(separator: ", ") + "."
    }

    private func totalHablado() -> String {
        guard !items.isEmpty else { return "Todavía no ha guardado ninguna medida." }
        let sqft = items.compactMap { i -> Double? in i.width.map { $0 * i.length } }.reduce(0, +)
        let lineal = items.filter { $0.width == nil }.map { $0.length }.reduce(0, +)
        var t: [String] = []
        if sqft > 0 { t.append(String(format: "%.0f pies cuadrados", sqft)) }
        if lineal > 0 { t.append(String(format: "%.0f pies lineales", lineal)) }
        return "Lleva \(items.count) medida\(items.count == 1 ? "" : "s")" +
               (t.isEmpty ? "." : ": " + t.joined(separator: " y ") + ".")
    }

    // Devuelve true si la frase contesto la pregunta. Si no, se devuelve
    // false y la frase sigue su camino como orden normal - asi puede decir
    // "ayuda" o "deshacer" en medio de una pregunta sin quedarse atorado.
    private func contestar(_ paso: Paso, _ t: String) -> Bool {
        switch paso {
        case .queMide:
            // ¿Le esta diciendo que sí a lo que la camara creyo ver? Eso es un
            // material escogido, no un "sí" suelto.
            if let visto = materialQueVio, VozAsistente.esSi(t),
               let fila = materials.firstIndex(where: { $0.value == visto }) {
                materialQueVio = nil
                pasoAbierto = nil
                materialPickerView.selectRow(fila, inComponent: 0, animated: true)
                materialConfirmTapped()
                return true
            }
            if materialQueVio != nil, VozAsistente.esNo(t) {
                materialQueVio = nil
                say("Ok. ¿Entonces qué va a medir?", .aviso)
                pasoPorArmar = .queMide
                return true
            }
            // Dijo la SECCION, no el material ("piso", "pared"). No es que no
            // se le entendiera: es que falta el dato. Se le leen las opciones
            // en vez de repetir "¿qué va a medir?" y dejarlo adivinando.
            if Self.esSoloLaSeccion(t, section: section) {
                let nombres = materials.prefix(6).map {
                    Self.nombreDeBoton($0).lowercased()
                }
                say("¿De qué es? " + nombres.joined(separator: ", ") + "...", .aviso)
                pasoPorArmar = .queMide
                return true
            }
            guard let valor = Self.materialDicho(t, entre: materials.map { $0.value }),
                  let fila = materials.firstIndex(where: { $0.value == valor }) else {
                // Si fue una ORDEN (ayuda, silencio), que pase de largo. Si
                // fue cualquier otra cosa, se repite la pregunta corta.
                if Self.ordenDe(t) != nil { return false }
                // Se guarda para aprenderla si en seguida escoge un material.
                noEntendido = (t, Date())
                if AsistenteIA.disponible {
                    // Que lo intente el modelo antes de rendirse: "es el piso
                    // de madera del pasillo" no esta en ninguna tabla.
                    pedirleALaIA(t)
                    pasoPorArmar = .queMide
                    return true
                }
                say("No le entendí. ¿Qué va a medir?", .aviso)
                pasoPorArmar = .queMide
                return true
            }
            pasoAbierto = nil
            materialPickerView.selectRow(fila, inComponent: 0, animated: true)
            materialConfirmTapped()
            return true

        case .llevaCompanero:
            // CONTESTAR NOMBRANDO LA COSA. "Sí, lleva insulación" es la
            // respuesta mas natural del mundo a "¿lleva insulación?" - y era un
            // hueco feo: `Insulation` ES un material de pared, asi que esa
            // frase caia en la correccion de material y CAMBIABA lo que estaba
            // midiendo de tablaroca a insulacion. Contestaba bien y la app le
            // cambiaba la medida.
            //
            // Va primero que todo, y la negacion manda: "no lleva insulación"
            // es un no, aunque traiga la palabra.
            // A MEDIA MEDIDA no se dice "apunte a la primera esquina" (21 sep 2026):
            // desde que se puede escoger material a medias, esta pregunta tambien
            // sale a medias, y el siguiente "marca" iba a la medida ABIERTA --
            // le sumaba al ancho o al largo la distancia a esa "primera esquina".
            let sigue = medidaEnCurso ? "Siga midiendo." : "Apunte a la primera esquina y diga marca."
            if Self.nombraElCompanero(t) {
                let niega = Self.tienePalabra(t, "no") || t.contains("sin ")
                    || t.contains("quita") || t.contains("tampoco")
                pasoAbierto = nil
                includeCompanion = !niega
                updateUI()
                say(niega ? "Ok, sin eso. \(sigue)" : "Anotado. \(sigue)", .guia)
                return true
            }
            // Mas formas de decir si y no en este momento exacto, que es donde
            // no contesta con una palabra suelta: "sí lleva", "también",
            // "nomás el piso", "solo eso".
            if t.contains("tambien") || t.contains("también") || t.contains("si lleva")
                || t.contains("sí lleva") || t.contains("obvio") || t.contains("por supuesto") {
                pasoAbierto = nil
                includeCompanion = true
                updateUI()
                say("Anotado. \(sigue)", .guia)
                return true
            }
            if t.contains("nomas") || t.contains("nomás") || t.contains("solo eso")
                || t.contains("solamente") || t.contains("nada mas") || t.contains("nada más") {
                pasoAbierto = nil
                includeCompanion = false
                updateUI()
                say("Ok. \(sigue)", .guia)
                return true
            }
            guard t.split(separator: " ").count <= 3 else { return false }
            if VozAsistente.esSi(t) {
                pasoAbierto = nil
                includeCompanion = true
                updateUI()
                say("Anotado. \(sigue)", .guia)
                return true
            }
            if VozAsistente.esNo(t) {
                pasoAbierto = nil
                includeCompanion = false
                updateUI()
                say("Ok. \(sigue)", .guia)
                return true
            }
            return false

        case .sigueIgual:
            guard t.split(separator: " ").count <= 3 else { return false }
            if VozAsistente.esSi(t) {
                pasoAbierto = nil
                if let valor = materialAnterior,
                   let fila = materials.firstIndex(where: { $0.value == valor }) {
                    materialPickerView.selectRow(fila, inComponent: 0, animated: false)
                    materialConfirmTapped()
                } else {
                    preguntar(.queMide, "¿Qué va a medir?")
                }
                return true
            }
            if VozAsistente.esNo(t) {
                pasoAbierto = nil
                // En un recorrido lo que sigue casi nunca es otro material de
                // la MISMA seccion: es cambiar de seccion o de cuarto. Se
                // pregunta lo que de verdad toca.
                if esRecorrido {
                    // Si ya se le conoce la costumbre, se le ofrece esa en vez
                    // de leerle las cuatro secciones cada vez.
                    if esSoloUnCuarto {
                        // Vino a medir UN cuarto: ofrecerle otro seria mandarlo
                        // a un recorrido que no pidio.
                        preguntar(.masOtraSeccion, "¿Cambiamos de sección, o ya terminamos?")
                    } else if let usual = MemoriaAsistente.seccionDespuesDe(section) {
                        preguntar(.masOtraSeccion,
                                  "¿Seguimos con \(Self.sectionSpokenName(usual)), o pasamos a otro cuarto?")
                    } else {
                        preguntar(.masOtraSeccion, "¿Cambiamos de sección, o pasamos a otro cuarto?")
                    }
                } else {
                    preguntar(.queMide, "¿Qué va a medir?")
                }
                return true
            }
            // Si en vez de si o no dice DIRECTO otro material, se toma: es mas
            // rapido que obligarlo a decir "no" y luego el material.
            if let valor = Self.materialDicho(t, entre: materials.map { $0.value }),
               let fila = materials.firstIndex(where: { $0.value == valor }) {
                pasoAbierto = nil
                materialPickerView.selectRow(fila, inComponent: 0, animated: true)
                materialConfirmTapped()
                return true
            }
            return false

        case .queNivel:
            guard let nivel = Self.nivelDicho(t, entre: nivelesDisponibles) else {
                if Self.ordenDe(t) != nil { return false }
                say("¿En qué nivel? Primer piso, segundo piso, sótano...", .aviso)
                pasoPorArmar = .queNivel
                return true
            }
            pasoAbierto = nil
            nivelActual = nivel
            roomName = ""
            roomAreaSqFt = 0
            ponerCuartosDeLaPlanta(nivel)
            actualizarTiraDeEstado()
            preguntar(.queCuarto, preguntaDeCuarto("\(nivel). "))
            return true

        case .queCuarto:
            // ¿Esta contestando al "no esta en el plano, ¿lo agrego?"? Eso va
            // ANTES de buscar un nombre: un "si" suelto no es un cuarto.
            if let pendiente = cuartoPorConfirmar {
                if VozAsistente.esSi(t) {
                    cuartoPorConfirmar = nil
                    pasoAbierto = nil
                    cambiarCuarto(pendiente)
                    preguntar(.queSeccion, "\(pendiente). ¿Con qué empezamos: piso, pared o techo?")
                    return true
                }
                if VozAsistente.esNo(t) {
                    cuartoPorConfirmar = nil
                    say(preguntaDeCuarto("Ok. "), .aviso)
                    pasoPorArmar = .queCuarto
                    return true
                }
            }
            guard let cuarto = Self.cuartoDicho(t, entre: cuartosDisponibles) else {
                if Self.ordenDe(t) != nil { return false }
                // No esta en la lista: se toma tal cual. La casa del cliente no
                // tiene por que caber en dieciseis nombres.
                let libre = t.trimmingCharacters(in: .whitespacesAndNewlines)
                if libre.count >= 3, libre.split(separator: " ").count <= 4 {
                    let nombre = libre.prefix(1).uppercased() + libre.dropFirst()
                    // Si hay plano de esta planta y el nombre no esta en el,
                    // se PREGUNTA antes de meterlo.
                    if confirmarCuartoFuera(nombre) { return true }
                    pasoAbierto = nil
                    cambiarCuarto(nombre)
                    preguntar(.queSeccion, "\(roomName). ¿Con qué empezamos: piso, pared o techo?")
                    return true
                }
                say(preguntaDeCuarto(), .aviso)
                pasoPorArmar = .queCuarto
                return true
            }
            pasoAbierto = nil
            cambiarCuarto(cuarto)
            preguntar(.queSeccion, "\(cuarto). ¿Con qué empezamos: piso, pared o techo?")
            return true

        case .queSeccion:
            guard let sec = Self.seccionDicha(t) else {
                if Self.ordenDe(t) != nil { return false }
                say("¿Piso, pared, techo, cocina, baño o materiales?", .aviso)
                pasoPorArmar = .queSeccion
                return true
            }
            guard cambiarSeccion(sec) else { return true }
            pasoAbierto = nil
            preguntar(.queMide, "\(Self.sectionSpokenName(sec).capitalized) de \(roomName). ¿Qué va a medir?")
            return true

        case .masOtraSeccion:
            // Se acepta lo que diga: una seccion, un cuarto, o "otro cuarto".
            if let sec = Self.seccionDicha(t) {
                guard cambiarSeccion(sec) else { return true }
                pasoAbierto = nil
                preguntar(.queMide, "\(Self.sectionSpokenName(sec).capitalized) de \(roomName). ¿Qué va a medir?")
                return true
            }
            if t.contains("otro cuarto") || t.contains("siguiente cuarto") || t.contains("cambiar de cuarto") {
                pasoAbierto = nil
                preguntar(.queCuarto, "¿Cómo se llama el siguiente cuarto?")
                return true
            }
            if let cuarto = Self.cuartoDicho(t, entre: cuartosDisponibles) {
                pasoAbierto = nil
                cambiarCuarto(cuarto)
                preguntar(.queSeccion, "\(cuarto). ¿Con qué empezamos?")
                return true
            }
            return false

        case .ocupaAncho:
            guard t.split(separator: " ").count <= 3 else { return false }
            if VozAsistente.esSi(t) {
                pasoAbierto = nil
                finishPathTapped()
                // Si lo que se le ofrecio fue un NUMERO, el "sí" es a ese
                // numero y ya no hay que caminar el ancho.
                if let ofrecido = anchoOfrecido {
                    anchoOfrecido = nil
                    anotarAncho(ofrecido)
                    return true
                }
                addWidthTapped()
                say("Apunte al inicio del ancho y diga marca.", .guia)
                return true
            }
            if VozAsistente.esNo(t) {
                pasoAbierto = nil
                finishPathTapped()
                // Un "no" a un NUMERO ofrecido no quiere decir "sin ancho":
                // quiere decir "ese no, mídelo". Tratarlo como sin ancho
                // guardaria una pared sin pies cuadrados por decir que no.
                if anchoOfrecido != nil {
                    anchoOfrecido = nil
                    addWidthTapped()
                    say("Ok. Apunte al inicio del ancho y diga marca, o dígame el número.", .guia)
                    return true
                }
                say("Ok, sin ancho. Diga guardar cuando quiera guardarlo.", .guia)
                return true
            }
            return false
        }
    }

    // Lo que esta pasando ahorita, en una linea, para que la IA entienda
    // "quítale eso" o "¿me falta algo?". Sin esto, el modelo contestaria en el
    // aire.
    private func estadoParaLaIA() -> String {
        var p: [String] = []
        p.append("sección: \(Self.sectionSpokenName(section))")
        // El nivel faltaba, y sin el la mitad de las preguntas no tienen
        // respuesta: "¿ya acabamos aquí?" depende de en que piso esta parado.
        if !nivelActual.isEmpty { p.append("nivel: \(nivelActual)") }
        if !roomName.isEmpty { p.append("cuarto: \(roomName)") }
        if esRecorrido { p.append("va en un recorrido: puede cambiar de cuarto y de sección sin salir") }
        if let m = selectedMaterial { p.append("material escogido: \(m.value)") } else { p.append("sin material escogido") }
        switch stage {
        case .pickingMaterial: p.append("paso: escogiendo material")
        case .measuringLength: p.append("paso: midiendo el largo, \(pathPoints.count) esquinas puestas")
        case .lengthDone:      p.append("paso: largo cerrado en \(Self.piesTexto(pathTotalFeet))")
        case .measuringWidth:  p.append("paso: midiendo el ancho")
        case .widthDone:       p.append("paso: medida completa, falta guardar")
        }
        if let w = currentWidthFeet { p.append("ancho: \(Self.piesTexto(w))") }
        p.append("medidas ya guardadas: \(items.count)")
        let sqft = items.compactMap { i -> Double? in i.width.map { $0 * i.length } }.reduce(0, +)
        if sqft > 0 { p.append(String(format: "total %.0f pies cuadrados", sqft)) }
        if let paso = pasoAbierto {
            p.append("pregunta abierta: \(paso)")
        }
        return p.joined(separator: "; ")
    }

    private func pedirleALaIA(_ frase: String) {
        guard AsistenteIA.disponible else {
            // Sin modelo, se comporta como siempre: callado. Decir "no le
            // entendí" en cada palabra suelta de una conversacion ajena seria
            // insoportable.
            return
        }
        orbita.estado = .pensando
        AsistenteIA.entender(frase,
                             seccion: Self.sectionSpokenName(section),
                             estado: estadoParaLaIA(),
                             materiales: materials.map { $0.value },
                             cuartos: cuartosDisponibles,
                             niveles: nivelesDisponibles,
                             conversacion: MemoriaAsistente.conversacionReciente(),
                             aprendido: MemoriaAsistente.loQueAprendio(materiales: materials.map { $0.value })) { [weak self] r in
            guard let self = self else { return }
            self.actualizarIndicadorMicro()
            guard let r = r else {
                // La IA no contesto o no entendio. Se DICE, no se traga: el
                // silencio es lo que lo dejaba sin saber si lo habian oido.
                self.say("No entendí eso. Diga ayuda para ver qué puede decir.", .guia, llave: "no-entendi")
                return
            }
            self.aplicarDeLaIA(r)
        }
    }

    // Lo que la IA propone pasa por LOS MISMOS CANDADOS que un dedo. El modelo
    // puede equivocarse; los candados no lo dejan equivocarse caro.
    private func aplicarDeLaIA(_ r: AsistenteIA.Resultado) {
        switch r.intencion {
        case .nada:
            return
        case .responder:
            if let t = r.respuesta, !t.isEmpty { decirPorPeticion(t) }
        case .escogerMaterial:
            guard let v = r.valor,
                  let fila = materials.firstIndex(where: { $0.value == v }) else { return }
            pasoAbierto = nil
            materialPickerView.selectRow(fila, inComponent: 0, animated: true)
            materialConfirmTapped()

        // ---- EL RECORRIDO, hablando ----
        // El modelo propone; los candados de siempre deciden. Un cuarto que no
        // esta en la lista de la casa no se inventa, y una seccion que esta
        // camara no trae no se puede escoger.
        case .escogerCuarto:
            // El asistente tampoco cambia de cuarto con una medida a medias: el
            // puede decidirlo de una frase suelta ("ya estamos en la cocina"),
            // sin que haya ninguna pregunta abierta.
            if medidaEnCurso { say("Primero guarde o cancele la medida que lleva.", .aviso); return }
            // UN NOMBRE QUE NO ESTA EN LA LISTA SE ACEPTA IGUAL.
            //
            // Aqui habia un `guard ... else { return }` que lo DESCARTABA en
            // silencio: si el asistente entendia "gimnasio" y la lista no lo
            // traia, no pasaba nada - ni se escogia el cuarto ni se le decia
            // por que. El camino de voz directo (.queCuarto) si lo aceptaba
            // desde hace tiempo; este se habia quedado fuera.
            //
            // Y ahora importa mucho mas: con la rueda reducida a los cuartos
            // del plano, cualquier cuarto que el escaner no vio cae por aqui.
            guard esRecorrido, let v = r.valor else { return }
            let dicho = cuartosDisponibles.first(where: { $0.caseInsensitiveCompare(v) == .orderedSame })
                ?? Self.cuartoDicho(v, entre: cuartosDisponibles)
            let libre = v.trimmingCharacters(in: .whitespacesAndNewlines)
            // Misma regla que .queCuarto: tres letras y como mucho cuatro
            // palabras. Debajo de eso es ruido, no el nombre de un cuarto.
            guard let cuarto = dicho ?? (libre.count >= 3 && libre.split(separator: " ").count <= 4
                                         ? libre.prefix(1).uppercased() + libre.dropFirst() : nil)
            else { return }
            // Si vino de la lista se mete; si es un nombre suyo y hay plano, se
            // pregunta primero - la misma regla que por voz directa.
            if dicho == nil, confirmarCuartoFuera(String(cuarto)) { return }
            pasoAbierto = nil
            cambiarCuarto(String(cuarto))
            preguntar(.queSeccion, "\(cuarto). ¿Piso, pared, techo, cocina, baño o materiales?")
        case .escogerSeccion:
            guard esRecorrido, let v = r.valor,
                  let sec = Self.seccionDicha(v) ?? (seccionesDisponibles[v] != nil ? v : nil),
                  seccionesDisponibles[sec] != nil else { return }
            guard cambiarSeccion(sec) else { return }
            pasoAbierto = nil
            preguntar(.queMide, "\(Self.sectionSpokenName(sec).capitalized). ¿Qué va a medir?")
        case .escogerNivel:
            if medidaEnCurso { say("Primero guarde o cancele la medida que lleva.", .aviso); return }
            // EL CANDADO QUE AQUI FALTABA. Tenia `?? v`, que deja pasar el
            // valor crudo del modelo aunque no este en el catalogo - y de ahi
            // va a `nivelActual` y se estampa en cada medida, hasta el PDF del
            // seguro. `.escogerCuarto` y `.escogerSeccion` si hacen `return`
            // cuando no casa; este se habia quedado fuera.
            guard esRecorrido, let v = r.valor, !v.isEmpty,
                  let nivel = nivelesDisponibles.first(where: { $0.caseInsensitiveCompare(v) == .orderedSame })
                    ?? Self.nivelDicho(v, entre: nivelesDisponibles) else { return }
            pasoAbierto = nil
            nivelActual = nivel
            roomName = ""
            roomAreaSqFt = 0
            ponerCuartosDeLaPlanta(nivel)
            actualizarTiraDeEstado()
            preguntar(.queCuarto, preguntaDeCuarto("\(nivelActual). "))
        case .otroCuarto:        atenderOrden("otro cuarto")
        case .otraIgual:         atenderOrden("otra igual")
        case .ponerCompanero:    atenderOrden("ponle insulacion")
        case .quitarCompanero:   atenderOrden("quita la insulacion")
        case .esperame:          atenderOrden("esperame")
        case .yaEstoy:           atenderOrden("ya estoy")
        case .queComandos:       atenderOrden("que comandos")
        case .si:
            if let paso = pasoAbierto { _ = contestar(paso, "si") }
        case .no:
            if let paso = pasoAbierto { _ = contestar(paso, "no") }
        // Todo lo demas se despacha por el MISMO camino que una orden hablada,
        // con su revision de boton visible incluida.
        case .marcar:            atenderOrden("marca")
        case .terminarRecorrido: atenderOrden("terminar recorrido")
        case .medirAncho:        atenderOrden("medir ancho")
        case .guardar:           atenderOrden("guardar")
        case .terminar:          atenderOrden("terminar")
        case .deshacer:          atenderOrden("deshacer")
        case .cancelar:          atenderOrden("cancela")
        case .ayuda:             atenderOrden("ayuda")
        case .dondeVoy:          atenderOrden("donde voy")
        case .silencio:          atenderOrden("silencio")
        case .cuantoLlevo:       atenderOrden("cuanto llevo")
        case .queMaterial:       atenderOrden("que material")
        case .cambiarMaterial:   atenderOrden("otro material")
        case .abrirLista:        atenderOrden("lista")
        }
    }

    private func esPreguntaDeMaterial(_ p: Paso) -> Bool {
        if case .queMide = p { return true }
        if case .sigueIgual = p { return true }   // esa ya sabe recibir un material
        return false
    }

    private func corrigioElMaterial(_ t: String) -> Bool {
        // Un "no" pelado, ya con material escogido: quiere cambiarlo.
        if VozAsistente.esNo(t), t.split(separator: " ").count <= 2, selectedMaterial != nil {
            preguntar(.queMide, "Ok. ¿Qué va a medir?")
            return true
        }
        guard let valor = Self.materialDicho(t, entre: materials.map { $0.value }),
              let fila = materials.firstIndex(where: { $0.value == valor }) else { return false }
        // Si es el MISMO que ya tenia, no hay nada que corregir: que siga su
        // camino normal (puede que estuviera contestando otra cosa).
        if selectedMaterial?.value == valor { return false }
        let nombre = Self.nombreDeBoton(materials[fila])
        materialPickerView.selectRow(fila, inComponent: 0, animated: true)
        if selectedMaterial == nil {
            materialConfirmTapped()
        } else {
            // Cambiar sobre la marcha: se conserva TODO lo medido. Solo cambia
            // la etiqueta con la que se va a guardar.
            selectedMaterial = materials[fila]
            arrancarConteoSiHaceFalta()
            // Lo escrito a mano no entra en la cuenta de "el que mas usa", que
            // se guarda en el telefono para siempre (igual que al escogerlo).
            if !esEscrito(valor) { recordarMaterialUsado(valor) }
            includeCompanion = false
            updateUI()
            // medidaEnCurso, no solo esquinas: con un largo DICTADO tampoco se
            // manda a la primera esquina -- el "marca" siguiente borraba el dictado.
            if !medidaEnCurso {
                say("Ok, \(nombre.lowercased()). Apunte a la primera esquina y diga marca.", .aviso)
            } else {
                say("Ok, ahora es \(nombre.lowercased()). Lo que lleva medido se queda.", .aviso)
            }
        }
        return true
    }

    // Un golpecito y una palabra: sabe que se le oyo, sin tener que mirar.
    private func confirmarOrden(_ texto: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        say(texto, .guia)
    }

    // ============ LO QUE LA CAMARA DE VERDAD PUEDE VER ============
    //
    // ARKit clasifica la superficie que tiene enfrente: pared, piso, techo,
    // mesa, puerta, ventana. Eso es REAL y es lo que se usa aqui.
    //
    // LO QUE NO PUEDE, y no se va a fingir: NO distingue alfombra de madera
    // ni de loseta. No existe esa funcion en el telefono. Decir "veo que
    // esta midiendo carpet" seria mentira, y una mentira que termina en una
    // factura de seguro. Lo que si se hace es lo honesto: la camara dice que
    // es PISO, y la pregunta de material - que ya existia - la contesta el.
    // ============ PIE LINEAL O PIE CUADRADO ============
    //
    // Su reporte: "si miden una pared y se demolio tanto, tiene que ser en
    // square foot... y para el baseboard es solo una linear foot".
    //
    // La app dejaba poner ancho o no ponerlo y NUNCA decia cuando hacia
    // falta. Una pared guardada sin ancho llega a la oficina como pie
    // lineal cuando debia ser pie cuadrado, y esa diferencia es dinero que
    // no se factura.
    //
    // DE DONDE SALEN ESTAS REGLAS: no de mi cabeza, sino de las lineas que
    // Flood Doctor YA acepto y pago en la factura Malik reconstruida:
    //   "Tear out baseboard and bag for disposal" ................. LF
    //   "Tear out tackless strip" ................................. LF
    //   "Tear out wet drywall, cleanup, bag, per LF - up to 2' tall" LF
    //   "Tear out wet drywall, cleanup, bag for disposal (ceiling)"  SF
    //   "Tear out wet non-salvageable carpet, cut & bag for disp."   SF
    //   "Tear out wet carpet pad, cut/bag - Category 2 water" ...... SF
    // Es decir: el corte de pared BAJITO (hasta 2 pies) va por pie lineal,
    // y solo cuando pasa de ahi va por pie cuadrado. Ese detalle es de la
    // factura de ellos, no una opinion.
    private enum Unidad { case lineal, cuadrado, depende }
    private func unidad(for material: String) -> Unidad {
        return Self.unidad(material: material, section: seccionDelMaterial(material))
    }
    // Aparte y sin estado para poder probarla: esto decide si una linea se
    // factura por pie lineal o por pie cuadrado. Equivocarse aqui es dinero
    // que no se cobra, o una linea que el seguro rebota.
    private static func unidad(material: String, section: String) -> Unidad {
        let m = material.lowercased()
        // SHOE MOLDING Y TOE KICK SE COBRAN POR PIE LINEAL, igual que el
        // zócalo: son tiras que corren, no superficies. Sin esto, "Shoe
        // Molding" no casaba ninguna palabra de esta línea y caía en pie
        // cuadrado por ser de pared - y entonces la cámara le habría pedido un
        // ancho que no existe.
        if m.contains("baseboard") || m.contains("trim") || m.contains("tackless")
            || m.contains("shoe") || m.contains("molding") || m.contains("toe kick") { return .lineal }
        if section == "kitchen" { return .depende }
        // Los materiales (nailo, 6 mil de contención, protección de piso) se
        // cobran por pie cuadrado: largo por ancho, o largo por alto si es
        // una pared de contención.
        if section == "floor" || section == "ceiling" || section == "wall" || section == "materiales" { return .cuadrado }
        return .depende
    }
    // Lo que se dice al escoger el material. Corto: esta parado con el
    // telefono en alto, no en un salon de clases.
    private func explicacionUnidad(for material: String) -> String {
        switch unidad(for: material) {
        case .lineal:
            return "El zócalo se cobra por pie lineal. Con el largo basta, no necesita ancho."
        case .cuadrado where section == "wall":
            return "La pared se mide largo por alto, para sacar los pies cuadrados. Ojo: si el corte es de dos pies de alto o menos, con el largo basta, porque eso se cobra por pie lineal."
        case .cuadrado where section == "ceiling":
            return "El techo se cobra por pie cuadrado. Necesita el largo y el ancho."
        case .cuadrado where section == "materiales":
            return "El material se cobra por pie cuadrado: largo por ancho, o largo por alto si es una pared de contención."
        case .cuadrado:
            return "El piso se cobra por pie cuadrado: largo por ancho. Necesita las dos medidas."
        case .depende:
            // La cocina no tiene una regla pareja y no me la voy a inventar:
            // una unidad equivocada aqui es una linea que el seguro rebota.
            return "Si no está seguro si va por pie lineal o cuadrado, mida las dos: la oficina puede quitar una medida, pero no puede inventar la que falta."
        }
    }

    // ============ COMO SE MIDE CADA COSA ============
    //
    // Su reporte: "el piso solo se mide de largo y ancho, o sea, solo hay que
    // obtener dos esquinas... a veces el voice command deja que midan otra
    // esquina mas y no se puede. Excepto que esten midiendo drywall, que esos
    // si pueden continuar en todas las cuatro paredes."
    //
    // Y no es solo un consejo: es GEOMETRIA. La app guarda largo x ancho.
    //   - TABLAROCA de pared: el largo es la suma de las paredes y el ancho
    //     es el ALTO del corte. Sumar pared tras pared y multiplicar por el
    //     alto SI da los pies cuadrados correctos - asi se cobra el corte.
    //   - PISO o TECHO: si marca tres esquinas (un cuarto en L), el "largo"
    //     queda siendo la suma de dos tramos perpendiculares, y multiplicar
    //     ESO por un ancho no es el area de nada. El numero sale mal y nadie
    //     se entera.
    // Por eso el aviso, y por eso la app no lo bloquea: un cuarto en L se
    // mide en dos medidas separadas, y eso lo tiene que hacer el.
    private enum Forma {
        case recorrido    // de corrido, esquina tras esquina (paredes)
        case rectangulo   // dos esquinas y ya: largo x ancho
        case libre        // sin regla clara - no se le dice nada
    }
    private func forma(for material: String) -> Forma {
        return Self.forma(section: section)
    }
    private static func forma(section: String) -> Forma {
        switch section {
        case "wall":              return .recorrido   // tablaroca y zocalo dan la vuelta al cuarto
        case "floor", "ceiling":  return .rectangulo
        case "materiales":        return .rectangulo  // un plastico o una proteccion de piso: largo por ancho
        default:                  return .libre       // cocina: una cubierta en L es normal
        }
    }

    // ============ LO QUE LA CAMARA APRENDE DE LA CUADRILLA ============
    //
    // La lista de materiales sale siempre en el mismo orden, y en un trabajo
    // de agua el 80% de lo que se quita es lo mismo una y otra vez. Se lleva
    // la cuenta por seccion y se DEJA PRESELECCIONADO lo que mas usa.
    //
    // No se REORDENA la lista a proposito: una lista que cambia de orden
    // debajo del dedo hace que se equivoquen. Solo se mueve el selector.
    // ============ APRENDER COMO HABLA ============
    //
    // Su pedido: "que vaya aprendiendo constantemente la conversación con el
    // trabajador para que vaya estudiando cómo habla".
    //
    // Como funciona, sin magia: cuando el asistente NO entiende una palabra y
    // en seguida el escoge un material - de la lista o diciendo otra palabra -
    // se guarda que esa palabra que no se entendio significa ESE material. La
    // proxima vez ya entra sola. Es su diccionario, en su telefono.
    //
    // Se guarda solo si viene PEGADA a la correccion (menos de 25 segundos):
    // mas lejos ya no es una correccion, es casualidad.
    private static let clavePalabras = "arMatPalabras:v1"
    private var noEntendido: (palabra: String, cuando: Date)?

    private func aprenderPalabra(_ palabra: String, para valor: String) {
        let p = palabra.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Ni muy corta (se confunde con todo) ni una frase entera.
        guard p.count >= 4, p.split(separator: " ").count <= 3 else { return }
        // Y que no sea ya una orden: aprender "guardar" como material seria
        // dejarlo sin poder guardar.
        guard Self.ordenDe(p) == nil else { return }
        var d = (UserDefaults.standard.dictionary(forKey: Self.clavePalabras) as? [String: String]) ?? [:]
        guard d[p] == nil else { return }
        d[p] = valor
        if d.count > 120 { d.removeValue(forKey: d.keys.first!) }
        UserDefaults.standard.set(d, forKey: Self.clavePalabras)
    }
    static func palabrasAprendidas() -> [String: String] {
        return (UserDefaults.standard.dictionary(forKey: clavePalabras) as? [String: String]) ?? [:]
    }

    // ---- Cambiar de seccion y de cuarto EN CALIENTE ----
    //
    // Todo lo que dependia de la seccion pasa por aqui. Un solo lugar, porque
    // la seccion toca demasiadas cosas: la lista de materiales, las reglas de
    // pie lineal contra pie cuadrado, la forma de medir (la pared va de
    // corrido, el piso no), lo que la camara espera ver enfrente, y las
    // instrucciones de la IA - que se arman UNA vez con la seccion adentro y
    // por eso hay que reconstruirlas.
    // COCINA Y BAÑO TIENEN SU PROPIA PASTILLA (27 sep 2026). Del 13 al 27 de
    // septiembre no la tuvieron: sus artículos salían dentro de PARED cuando el
    // cuarto se llamaba así ("cambia cocina por materiales", su pedido de
    // entonces). El problema de fondo era que dependía del NOMBRE del cuarto:
    // en un "Basement" con una regadera no había forma de llegar a esas piezas.
    // Ahora se escoge como Piso, Pared o Techo. esCocina/esBano se quedan: el
    // asistente las usa para hablarle del cuarto donde está parado.
    static func esCocina(_ nombre: String) -> Bool {
        let d = nombre.lowercased()
        return d.contains("kitchen") || d.contains("cocina")
    }
    // EL BAÑO, IGUAL QUE LA COCINA (27 sep 2026). Su pedido: "en esa sección
    // falta cocina y baño". La cocina ya salía dentro de Pared cuando el cuarto
    // es la cocina (su instrucción del 13 de septiembre); el baño no existía.
    // Se acentúa o no ("bano", "baño"), y "half bath" / "master bath" también
    // son baños. "bathroom" contiene "bath", así que con "bath" alcanza.
    static func esBano(_ nombre: String) -> Bool {
        let d = nombre.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
        return d.contains("bath") || d.contains("bano") || d.contains("powder room")
    }
    private func listaDeMateriales(_ sec: String) -> [ARMaterialOption] {
        // SIN MEZCLA (27 sep 2026). Antes los articulos de cocina y de baño se
        // colaban dentro de PARED cuando el cuarto se llamaba asi. Ahora cada
        // una tiene su pastilla, como Piso, Pared y Techo, y ofrecer lo mismo
        // en dos listas solo confunde: el mismo inodoro en Pared y en Baño.
        let lista0 = seccionesDisponibles[sec] ?? []
        var lista = lista0
        // Lo escrito a mano va ANTES de "Other": en la ruleta queda junto a los
        // de la lista, y "Other" sigue siendo lo ultimo, como en la web.
        let escritos = (materialesEscritos[sec] ?? []).filter { e in !lista.contains(where: { $0.value == e.value }) }
        if !escritos.isEmpty {
            let i = lista.firstIndex(where: { $0.value == "Other" }) ?? lista.count
            lista.insert(contentsOf: escritos, at: i)
        }
        return lista
    }
    // La sección con la que se GUARDA un material. Desde que Cocina y Baño
    // tienen pastilla (27 sep 2026) es, casi siempre, la de la pastilla. Esta
    // red de seguridad se queda para un trabajo guardado ANTES de ese cambio,
    // que trae un artículo de cocina apuntando a "wall": así sigue saliendo
    // como Kitchen en la hoja y no se convierte en pared.
    private func seccionDelMaterial(_ valor: String) -> String {
        guard section == "wall",
              !(seccionesDisponibles["wall"] ?? []).contains(where: { $0.value == valor }) else { return section }
        // El orden importa: "Tile" está en las dos listas (azulejo de baño y
        // baldosa de cocina no, pero Piso sí tiene Tile). Se mira primero la
        // lista del cuarto en el que de verdad está parado.
        if Self.esBano(roomName),
           (seccionesDisponibles["bathroom"] ?? []).contains(where: { $0.value == valor }) { return "bathroom" }
        if (seccionesDisponibles["kitchen"] ?? []).contains(where: { $0.value == valor }) { return "kitchen" }
        if (seccionesDisponibles["bathroom"] ?? []).contains(where: { $0.value == valor }) { return "bathroom" }
        return section
    }

    // ¿Hay una medida a medias? Esquinas puestas, un ancho, o un largo dicho
    // de viva voz. Es lo que no se puede dejar colgado al cambiar de seccion.
    private var medidaEnCurso: Bool {
        !pathPoints.isEmpty || !widthPoints.isEmpty || currentWidthFeet != nil || largoDictado
    }

    // Devuelve si DE VERDAD cambio. Los que la llaman solo preguntan "¿Que va a
    // medir?" cuando si: preguntarlo despues de negarse seria decirle que ya
    // esta en Techo cuando se quedo en Piso.
    @discardableResult
    private func cambiarSeccion(_ nueva: String) -> Bool {
        guard seccionesDisponibles[nueva] != nil else { return false }
        // EL CANDADO DE LA MEDIDA A MEDIAS, AQUI Y NO EN CADA BOTON (21 sep 2026).
        //
        // Solo lo tenia la pastilla de seccion (seccionTapped). La voz ("ahora el
        // techo", dicho a un compañero), el asistente y la pregunta de "¿otra
        // seccion?" cambiaban de seccion con las esquinas puestas. Antes eso
        // guardaba la medida en la seccion equivocada; con el material ya
        // soltado (abajo), Guardar no hacia nada y Terminar cerraba la camara
        // como cancelada: el recorrido perdido, sin una palabra.
        // Aqui lo pasan los cinco caminos.
        if medidaEnCurso {
            say("Primero guarde o cancele la medida que lleva.", .aviso)
            return false
        }
        // Por donde se mueve el: despues del piso, ¿que sigue? Nadie lo puede
        // saber de antemano - depende de como trabaja ESTA cuadrilla.
        MemoriaAsistente.recordarSalto(de: section, a: nueva)
        section = nueva
        materials = listaDeMateriales(nueva)
        materialPickerView.reloadAllComponents()
        // EL MATERIAL DE LA SECCION ANTERIOR NO SE QUEDA ESCOGIDO (21 sep 2026).
        //
        // Salio en su foto: arriba decia "Living Room · Techo · LVP" y abajo
        // ofrecia "+ Underlayment". Habia escogido LVP en Piso y paso a Techo;
        // esto cambiaba la lista pero no soltaba el material. Y bancarMedida
        // guarda con la seccion DE AHORA y el material DE ANTES: el siguiente
        // toque de + habria medido el techo y lo habria mandado al PDF como
        // piso vinilico, con underlayment encima. Se habria cobrado mal.
        //
        // Solo se suelta si NO existe en la seccion nueva: Drywall de Pared a
        // Techo es Drywall en los dos, y ahi no hay nada que corregir.
        if let m = selectedMaterial, !materials.contains(where: { $0.value == m.value }) {
            selectedMaterial = nil
            includeCompanion = false
            // Y la pantalla vuelve a "escoger material", la misma regla que
            // despues de guardar una medida. Si no, el + se quedaba puesto sin
            // material: marcaba esquinas que despues no se podian guardar.
            stage = (materials.isEmpty && !esRecorrido) ? .measuringLength : .pickingMaterial
        }
        // Lo que mas usa EN ESTA seccion queda preseleccionado. Antes esto se
        // leia una sola vez al abrir la pantalla; ahora toca en cada cambio.
        if let usual = materialMasUsado(), let fila = materials.firstIndex(where: { $0.value == usual }) {
            materialPickerView.selectRow(fila, inComponent: 0, animated: false)
        }
        // AQUI YA NO SE TIRA LA SESION DE LA IA, y ese es el punto.
        //
        // Se tiraba porque las instrucciones del modelo traian la seccion
        // escrita adentro. Pero en un recorrido la seccion cambia cada pocos
        // minutos, y con cada cambio se iba la CONVERSACION ENTERA: le
        // preguntaba algo, pasaba a pared, y el modelo ya no se acordaba de
        // nada. Eso no es conversar, es empezar de cero todo el tiempo.
        //
        // Ahora la seccion viaja en el estado, que se manda en cada turno, asi
        // que el modelo siempre sabe donde esta parado Y se acuerda de lo que
        // llevan platicado en toda la casa.
        actualizarTiraDeEstado()
        return true
    }

    // ============ LA BARRITA DE AVANCE: QUE SE MIDE Y CUANTO LLEVA ============
    //
    // Su pedido del 13 de septiembre, marcado en verde: "ya sabemos que estamos
    // en el basement desde el principio, entonces solo nombre de cuarto, que
    // seccion estamos midiendo, que material, y cuanto es la medida que
    // llevamos, cuantos pies cuadrados llevamos". Aqui vive tambien el conteo
    // que antes iba arriba en amarillo.
    //
    // Lo que ya esta hecho de cada seccion no se pierde: sale como una
    // palomita en su pastilla ("Pared ✓").
    private func pintarAvanceDelCuarto() {
        // De las medidas YA guardadas de este cuarto en este nivel. Se lee del
        // mismo sitio de donde sale el reporte: si aqui dice que la pared esta
        // hecha, es porque de verdad hay una medida de pared que se va a
        // imprimir.
        let deAqui = items.filter { $0.cuarto == roomName && $0.nivel == nivelActual }
        let hechas = Set(deAqui.map { $0.seccion })
        // La palomita va en la traduccion chica, no en la palabra grande: en la
        // grande ensanchaba la pastilla y "Materiales" se salia de la orilla.
        // Las SEIS pastillas, cada una con su palomita (27 sep 2026): Cocina y
        // Baño ya no cuelgan de Pared, tienen la suya. Sin esto, escanear el
        // baño entero dejaba su pastilla sin palomita para siempre y parecia
        // que faltaba.
        for (clave, ingles) in [("floor", "Floor"), ("wall", "Wall"), ("ceiling", "Ceiling"),
                                ("kitchen", "Kitchen"), ("bathroom", "Bathroom"),
                                ("materiales", "Materials")] {
            guard let b = botonesSeccion[clave] else { continue }
            let hecha = !roomName.isEmpty && hechas.contains(clave)
            ponerTraduccion(b, hecha ? "\(ingles) ✓" : ingles)
        }

        // Lo que ya lleva, de LO QUE SE ESTA MIDIENDO: mismo material Y misma
        // seccion (el Drywall de la pared no es el del techo).
        let deLaSeccion = deAqui.filter { $0.seccion == section }
        let guardadas: [(largo: Double, ancho: Double?)]
        if let m = selectedMaterial {
            let sec = seccionDelMaterial(m.value)
            guardadas = deAqui.filter { $0.material == m.value && $0.seccion == sec }.map { (largo: $0.length, ancho: $0.width) }
        } else {
            guardadas = (section.isEmpty ? deAqui : deLaSeccion).map { (largo: $0.length, ancho: $0.width) }
        }
        let texto = Self.textoDeAvance(cuarto: roomName,
                                       seccion: Self.sectionSpokenName(section).capitalized,
                                       material: selectedMaterial.map { Self.nombreDeBoton($0) },
                                       largoEnCurso: pathTotalFeet > 0 ? pathTotalFeet : nil,
                                       anchoEnCurso: currentWidthFeet,
                                       guardadas: guardadas,
                                       medidasEnElNivel: items.filter { $0.nivel == nivelActual }.count,
                                       hayAlgoGuardado: !items.isEmpty,
                                       piezasEnCurso: esPorPieza ? piezasContadas : nil)
        guard let texto = texto else { avanceLabel.isHidden = true; return }
        if avanceLabel.text != texto { avanceLabel.text = texto }
        avanceLabel.isHidden = false
    }

    // El texto, aparte y sin estado, para poder probarlo. SIEMPRE tres
    // renglones cuando se muestra (que, midiendo, llevo): si cambiara de dos a
    // tres, "Terminar" y la lista de cuartos, que cuelgan de la columna, se
    // moverian debajo del dedo.
    static func textoDeAvance(cuarto: String, seccion: String, material: String?,
                              largoEnCurso: Double?, anchoEnCurso: Double?,
                              guardadas: [(largo: Double, ancho: Double?)],
                              medidasEnElNivel: Int, hayAlgoGuardado: Bool,
                              // Lo que se CUENTA en vez de medirse (27 sep 2026).
                              // Con valor por omision para no tocar a quien ya
                              // la llama, incluidas las pruebas.
                              piezasEnCurso: Int? = nil) -> String? {
        // Sin cuarto ni material: con algo ya guardado la barrita se queda
        // (para que nada se mueva); en una pantalla nueva, no estorba.
        if cuarto.isEmpty && material == nil {
            guard hayAlgoGuardado else { return nil }
            let n = medidasEnElNivel
            return "Escoja el cuarto\nMidiendo: —\nLlevo \(n) medida" + (n == 1 ? "" : "s") + " en este nivel"
        }
        var arriba: [String] = []
        if !cuarto.isEmpty { arriba.append(cuarto) }
        if !seccion.isEmpty { arriba.append(seccion) }
        arriba.append(material ?? "escoja material")
        var enCurso = "Midiendo: —"
        if let p = piezasEnCurso {
            enCurso = "Cuántos: \(p) " + (p == 1 ? "pieza" : "piezas")
        } else if let l = largoEnCurso, l > 0 {
            if let w = anchoEnCurso, w > 0 {
                enCurso = String(format: "Midiendo %.1f × %.1f pies = %.0f pies²", l, w, l * w)
            } else {
                enCurso = String(format: "Midiendo %.1f pies", l)
            }
        }
        var total = "Llevo 0"
        if !guardadas.isEmpty {
            let area = guardadas.compactMap { g in g.ancho.map { $0 * g.largo } }.reduce(0, +)
            let lineal = guardadas.filter { $0.ancho == nil }.map { $0.largo }.reduce(0, +)
            var partes: [String] = []
            if area > 0 { partes.append(String(format: "%.0f pies²", area)) }
            if lineal > 0 { partes.append(String(format: "%.0f pies lineales", lineal)) }
            let n = guardadas.count
            let cuantas = "\(n) medida" + (n == 1 ? "" : "s")
            total = "Llevo " + (partes.isEmpty ? cuantas : partes.joined(separator: " + ") + " · " + cuantas)
        }
        return arriba.joined(separator: " · ") + "\n" + enCurso + "\n" + total
    }

    // Apagado en vez de escondido: si los botones aparecieran y desaparecieran,
    // la fila se moveria debajo del dedo justo cuando va a tocar.
    private func pintarTiraDeAcciones() {
        let ventana = (!materialOverlay.isHidden && listaVisible) || !helpOverlay.isHidden
        tiraAccionesScroll.isHidden = ventana || (seccionesDisponibles.isEmpty && materials.isEmpty)
        func poner(_ clave: String, _ vivo: Bool, _ prendido: Bool = false) {
            guard let b = botonesAccion[clave] else { return }
            b.isEnabled = vivo
            atenuarPastilla(b, vivo ? 1.0 : 0.38)
            b.backgroundColor = prendido ? Self.colorEscogido
                                         : Self.colorPastilla
        }
        let hayMaterial = selectedMaterial != nil
        // POR PIEZA: no hay largo ni ancho que marcar, hay cuantos. Las dos
        // pastillas de medir se apagan y salen las de contar, con el numero
        // escrito en la del mas para no tener que mirar a otro lado.
        let contando = esPorPieza
        esconderPastilla(botonesAccion["largo"], contando)
        esconderPastilla(botonesAccion["ancho"], contando)
        esconderPastilla(botonesAccion["menos"], !contando)
        esconderPastilla(botonesAccion["mas"], !contando)
        if contando {
            botonesAccion["mas"]?.setTitle("+ 1  (\(piezasContadas))", for: .normal)
            poner("menos", piezasContadas > 1)
            poner("mas", true)
        } else {
            poner("largo", hayMaterial, stage == .measuringLength)
            poner("ancho", hayMaterial && (hasLengthMeasurement || stage == .measuringWidth),
                  stage == .measuringWidth || stage == .widthDone)
        }
        poner("comp", currentCompanion != nil, includeCompanion)
        poner("guardar", !saveContinueButton.isHidden)
        poner("otro", esRecorrido)
        poner("anterior", cuartoAnterior() != nil)
        poner("cancelar", true)
        if cancelarPendiente, let b = botonesAccion["cancelar"] {
            b.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
            // Corto: una pastilla que crece al final de una fila deslizada se
            // sale por la orilla y se lee "¿Salir? To".
            b.setTitle("¿Salir?", for: .normal)
            ponerTraduccion(b, "Tap again")
        } else if let b = botonesAccion["cancelar"] {
            b.setTitle("Cancelar", for: .normal)
            ponerTraduccion(b, "Cancel")
        }
        if let b = botonesAccion["comp"] {
            // Cada acompañante dice SU nombre, con la misma regla que los
            // materiales: arriba la palabra de la obra, abajo la otra.
            //
            // Antes, todo nombre de mas de 11 letras caia a "Insulación": el
            // boton decia "Insulación" y agregaba Almohadilla en la alfombra,
            // Base en el laminado y Moldura en el zocalo. Lo que se toca aqui
            // sale en la factura del seguro, asi que un boton mal rotulado no
            // es un detalle de pantalla. Ya no hace falta cortar: la fila se
            // desliza, asi que un nombre largo ensancha su pastilla.
            // Con "+" delante: la misma palabra ("Insulación", "Underlayment")
            // tambien es un MATERIAL en la fila de arriba, y tocar ese cambia lo
            // que se esta midiendo. El recordatorio y la voz dicen este titulo.
            let grande = currentCompanion.map {
                "+ " + Self.nombreDeBoton(valor: $0.value, etiqueta: $0.en)
            } ?? "+ Insulación"
            let chica = currentCompanion?.en ?? "Insulation"
            b.setTitle(grande, for: .normal)
            ponerTraduccion(b, chica.caseInsensitiveCompare(grande) == .orderedSame ? "" : chica)
        }
    }

    private var pintadoDe = ""
    private func pintarTiraDeMateriales() {
        // Se esconde cuando hay una ventana encima: dejarla asomando debajo de
        // la lista de materiales serian dos formas de escoger lo mismo a la vez.
        // Tambien mientras se lee el recibo antes de mandar o el aviso de salir:
        // un recibo largo baja hasta donde van los materiales y quedaria tapado.
        if (!materialOverlay.isHidden && listaVisible) || !helpOverlay.isHidden
            || (resumenPendiente && reciboEnPantalla != nil) || cancelarPendiente {
            tiraMateriales.isHidden = true
            pintadoDe = ""
            return
        }
        // Solo se rehace si de verdad cambio algo. `updateUI` corre en cada
        // toque y en cada cambio de etapa; reconstruir los botones cada vez
        // parpadearia y se comeria el toque a medio camino.
        let firma = section + "|" + (selectedMaterial?.value ?? "") + "|" + String(materials.count)
        guard firma != pintadoDe else { return }
        pintadoDe = firma
        filaMateriales.arrangedSubviews.forEach { $0.removeFromSuperview() }
        olvidarPastillasMuertas()
        // "Other" no va como una pastilla mas: es la ranura para ESCRIBIR, y va
        // al final con su lapiz (abajo). Antes no se ponia porque "aqui no hay
        // teclado"; ahora abre el teclado, igual que "Escribir el nombre" de
        // los cuartos.
        let opciones = materials.filter { $0.value != "Other" }
        // LA PASTILLA NO DEPENDE DE QUE "Other" VENGA EN LA LISTA (21 sep 2026).
        //
        // La primera version decia `materials.contains("Other")`, y NUNCA salia:
        // las dos llamadas de la web (el recorrido y la camara de una tarjeta)
        // le quitan "Other" a la lista antes de mandarla. A proposito, y se
        // queda asi: un "Other" suelto en la ruleta o en la voz guardaria una
        // medida SIN NOMBRE en el PDF. El nombre solo existe si lo escriben, y
        // para eso esta esta pastilla. Se instalo en cuatro telefonos sin que
        // saliera; lo encontro la revision, no la prueba.
        let hayOtro = !opciones.isEmpty
        guard opciones.count + (hayOtro ? 1 : 0) > 1 else { tiraMateriales.isHidden = true; return }
        _ = tiraMateriales
        // El que mas usa EN ESTA SECCION va primero: en una barra que se
        // desliza, lo que queda fuera de la pantalla es como si no estuviera.
        let usual = materialMasUsado()
        let ordenadas = opciones.sorted { a, b in
            if a.value == usual { return true }
            if b.value == usual { return false }
            return false
        }
        for m in ordenadas {
            let b = UIButton(type: .system)
            let corto = Self.nombreDeBoton(m)
            styledOverlayButton(b, title: corto, bg: Self.colorPastilla, fontSize: 14)
            b.accessibilityIdentifier = m.value
            b.addTarget(self, action: #selector(materialTapped(_:)), for: .touchUpInside)
            if m.value == selectedMaterial?.value {
                b.backgroundColor = Self.colorEscogido
            }
            filaMateriales.addArrangedSubview(pastillaBilingue(b, Self.traduccionDeBoton(m)))
        }
        // LA ULTIMA SIEMPRE: "Otro", para escribir el nombre exacto. Con lapiz,
        // porque una fila mas abajo ya hay un "Otro cuarto" y los dos no pueden
        // parecer el mismo boton.
        if hayOtro {
            let b = UIButton(type: .system)
            styledOverlayButton(b, title: "✏️ Otro", bg: Self.colorPastilla, fontSize: 14)
            b.accessibilityIdentifier = Self.idOtroMaterial
            b.addTarget(self, action: #selector(otroMaterialTapped), for: .touchUpInside)
            filaMateriales.addArrangedSubview(pastillaBilingue(b, "Other"))
        }
        tiraMateriales.isHidden = false
    }

    // Lo que hace cada boton de la fila. Cada uno cae en la MISMA funcion que
    // ya usaban el boton grande de esa etapa y la voz: un solo camino por
    // accion, para que la conversacion y los candados no cambien segun por
    // donde se haya entrado.
    @objc private func accionTapped(_ b: UIButton) {
        guard let que = b.accessibilityIdentifier else { return }
        // Tocar cualquier otra cosa quiere decir que no queria salir.
        if que != "cancelar" { reiniciarCancelar() }
        switch que {
        case "menos":
            guard esPorPieza else { return }
            if piezasContadas > 1 { piezasContadas -= 1 }
            pathTotalFeet = Double(piezasContadas)
            say("\(piezasContadas).", .guia)
            pintarTiraDeAcciones()
        case "mas":
            guard esPorPieza else { return }
            piezasContadas += 1
            pathTotalFeet = Double(piezasContadas)
            say("\(piezasContadas).", .guia)
            pintarTiraDeAcciones()
        case "largo":
            // Volver a medir el largo. Si venia del ancho, se devuelve; si ya
            // estaba midiendo largo, no hace nada y no molesta.
            guard selectedMaterial != nil else { say("Primero escoja el material.", .guia); return }
            if stage == .measuringWidth || stage == .widthDone || stage == .lengthDone {
                // Se empieza el largo de nuevo, DEL MISMO MATERIAL. cancelar suelta
                // el material; sin devolverlo quedaba midiendo sin material: el +
                // marcaba, Guardar no hacia nada y Terminar tiraba el largo.
                let m = selectedMaterial, comp = includeCompanion
                cancelarMedidaEnCurso(hablar: false)
                selectedMaterial = m
                includeCompanion = comp
                stage = .measuringLength
                say("Otra vez el largo. Apunte a la primera esquina y toque más.", .guia)
            }
        case "ancho":
            // Mismo camino que decirlo: si el largo ya esta puesto pero el
            // recorrido sigue abierto, se cierra solo en vez de regañarlo.
            guard selectedMaterial != nil else { say("Primero escoja el material.", .guia); return }
            if stage == .measuringLength, hasLengthMeasurement { finishPathTapped() }
            guard stage == .lengthDone || stage == .measuringWidth else {
                say("Primero marque el largo con dos esquinas.", .guia); return
            }
            addWidthTapped()
        case "comp":
            guard currentCompanion != nil else {
                say("Este material no lleva nada debajo.", .guia); return
            }
            companionToggleTapped()
        case "guardar":
            guard !saveContinueButton.isHidden else {
                say("Todavía no hay una medida completa que guardar.", .guia); return
            }
            saveContinueTapped()
        case "otro":
            pasarAOtroCuarto()
        case "anterior":
            volverAlCuartoAnterior()
        case "cancelar":
            cancelarDesdeLaTira()
        default: break
        }
    }

    // El cuarto donde estaba antes del actual, si hay.
    private func cuartoAnterior() -> (nivel: String, cuarto: String)? {
        return cuartosVisitados.last { $0.cuarto != roomName || $0.nivel != nivelActual }
    }
    private func anotarVisita() {
        guard !roomName.isEmpty else { return }
        if let ultimo = cuartosVisitados.last, ultimo.cuarto == roomName, ultimo.nivel == nivelActual { return }
        cuartosVisitados.append((nivel: nivelActual, cuarto: roomName))
    }
    private func volverAlCuartoAnterior() {
        guard let previo = cuartoAnterior() else {
            say("Todavía no hay un cuarto anterior.", .guia)
            return
        }
        volverACuarto(nivel: previo.nivel, cuarto: previo.cuarto)
    }

    private func cancelarDesdeLaTira() {
        // Sin nada guardado no hay que perder: sale como salia el de arriba.
        guard !items.isEmpty else { onFinish?(.cancelled); return }
        if cancelarPendiente { onFinish?(.cancelled); return }
        cancelarPendiente = true
        let n = items.count
        let medidas = n == 1 ? "la medida" : "las \(n) medidas"
        instructionLabel.text = "⚠︎ Si sale ahora se pierden \(medidas) — toque ¿Salir? otra vez para salir"
        say("Ojo: si cancela, se pierden \(medidas) de esta cámara. Toque el botón rojo otra vez para salir, o Terminar para mandarlas.", .aviso)
        pintarTiraDeAcciones()
        updateUI()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, self.cancelarPendiente else { return }
            self.reiniciarCancelar()
        }
        cancelarReinicio?.cancel()
        cancelarReinicio = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: item)
    }
    private func reiniciarCancelar() {
        guard cancelarPendiente else { return }
        cancelarPendiente = false
        cancelarReinicio?.cancel(); cancelarReinicio = nil
        pintarTiraDeAcciones()
        // El aviso ya no es cierto: se quita. Al escoger material updateUI no
        // reescribe la casilla, asi que se vacia y se desvanece; en los demas
        // pasos updateUI pone la instruccion del paso.
        let t = instructionLabel.text ?? ""
        if t.hasPrefix("⚠︎ Si sale ahora") || t.hasPrefix("🔇 Ojo: si cancela") {
            flashGeneracion += 1
            instructionLabel.backgroundColor = Self.colorPastilla
            instructionLabel.text = nil
        }
        updateUI()
    }

    // "Otro cuarto" con el dedo: guarda lo que este completo y pregunta el
    // nombre del siguiente. Su pedido: "tenemos que tener una opcion en la
    // pantalla seguir a otro cuarto, por si el voice assistant no entiende".
    private func pasarAOtroCuarto() {
        guard esRecorrido else { say("Eso es para un recorrido completo.", .guia); return }
        // Lo que ya esta completo se guarda solo: perder la ultima medida por
        // tocar "otro cuarto" seria el peor momento posible para perderla.
        if !saveContinueButton.isHidden { saveContinueTapped() }
        // Y lo que quedo a medias NO se guarda a la fuerza - seria inventar una
        // medida - pero tampoco se tira callado.
        if medidaEnCurso {
            say("Ojo: dejó una medida a medias sin guardar.", .aviso)
            cancelarMedidaEnCurso()
        }
        abrirSelector(.queCuarto)
        preguntar(.queCuarto, "¿Cómo se llama el siguiente cuarto?")
    }

    // El identificador de la pastilla "Otro". No es un material: es el boton
    // que abre el teclado. No choca con el "otro" de "Otro cuarto", que va a
    // accionTapped y no aqui.
    static let idOtroMaterial = "__otro_material__"

    @objc private func otroMaterialTapped() {
        // pasoAbierto NO se suelta aqui: si estaba preguntando "¿Lleva
        // underlayment?" y el toca Cancelar, la pregunta tiene que seguir viva.
        // Se suelta hasta que de verdad escoge un nombre (usarMaterialEscrito).
        pedirMaterialEscrito()
    }

    // EN INGLES, por la misma razon que los cuartos escritos a mano: el value
    // de un material es lo que viaja al PDF, a la oficina y a Xactimate. Un
    // material escrito en español es una linea que el ajustador rebota.
    private func pedirMaterialEscrito() {
        let donde = Self.sectionSpokenName(section).capitalized
        let a = UIAlertController(title: "¿Qué material es?",
                                  message: "\(donde). Escríbalo EN INGLÉS: este nombre sale tal cual en el reporte del seguro.",
                                  preferredStyle: .alert)
        a.addTextField { t in
            t.placeholder = "Stair treads, Paneling, Wainscoting"
            t.autocapitalizationType = .words
            t.returnKeyType = .done
            t.clearButtonMode = .whileEditing
        }
        // La seccion en la que lo esta escribiendo. Con el teclado abierto la
        // voz sigue escuchando: si un "ahora el techo" de un compañero lo cambia
        // de seccion a medio escribir, "Stair treads" no puede caer en Techo.
        let seccionAlAbrir = section
        a.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        a.addAction(UIAlertAction(title: "Usar este nombre", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let escrito = (a.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !escrito.isEmpty else { return }
            guard self.section == seccionAlAbrir else {
                self.say("Cambió de sección mientras escribía. Vuelva a tocar Otro.", .aviso)
                return
            }
            self.usarMaterialEscrito(escrito)
        })
        present(a, animated: true)
    }

    private func usarMaterialEscrito(_ escrito: String) {
        // ¿Ya esta en la lista con otro nombre? "drywall" escrito a mano ES el
        // Drywall de la lista: se escoge ese, no se inventa uno nuevo que
        // saldria como una partida aparte en el PDF.
        let n = escrito.lowercased()
        let mitades: (ARMaterialOption) -> [String] = { m in
            m.label.lowercased().components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let yaEsta = materials.first { m in
            m.value != "Other"
                && (m.value.lowercased() == n || Self.nombreDeBoton(m).lowercased() == n || mitades(m).contains(n))
        }
        if yaEsta == nil {
            let nuevo = ARMaterialOption(value: escrito, label: escrito,
                                         companionValue: nil, companionEn: nil, companionEs: nil)
            materialesEscritos[section, default: []].append(nuevo)
            if seccionesDisponibles[section] != nil {
                // Recorrido: la lista de la seccion sale del catalogo, y ahi
                // listaDeMateriales ya mete lo escrito.
                materials = listaDeMateriales(section)
            } else if !materials.contains(where: { $0.value == escrito }) {
                // LA CAMARA DE UNA SOLA TARJETA NO TRAE CATALOGO: la lista es
                // la que mando la web en `materials`. Rehacerla con
                // listaDeMateriales la dejaba en [lo escrito] y nada mas: se
                // iban LVP, Carpet y todos los demas por el resto de la sesion.
                // Aqui se AGREGA a la que ya hay.
                materials.append(nuevo)
            }
            materialPickerView.reloadAllComponents()
        }
        let valor = yaEsta?.value ?? escrito
        guard let fila = materials.firstIndex(where: { $0.value == valor }) else { return }
        // Y desde aqui, el MISMO camino que tocar una pastilla de la lista: un
        // solo sitio donde se escoge material.
        pasoAbierto = nil
        materialPickerView.selectRow(fila, inComponent: 0, animated: false)
        materialConfirmTapped()
    }

    @objc private func materialTapped(_ b: UIButton) {
        guard let valor = b.accessibilityIdentifier,
              let fila = materials.firstIndex(where: { $0.value == valor }) else { return }
        // Por el MISMO camino que escogerlo de la lista o decirlo hablando: un
        // solo sitio donde se escoge material, para que la conversacion que
        // sigue (¿lleva insulación?, el ancho de siempre) pase igual.
        pasoAbierto = nil
        materialPickerView.selectRow(fila, inComponent: 0, animated: false)
        materialConfirmTapped()
    }

    // ---- LA BARRA DE NIVELES ----
    private func pintarTiraDeNiveles() {
        // SOLO en "diferentes niveles". En los otros dos alcances el nivel ya
        // se contesto en la pantalla y no cambia: ofrecerlo seria invitarlo a
        // tocar algo que le cambiaria de sitio medidas que ya tomo.
        guard alcance == "varios", nivelesDisponibles.count > 1 else {
            tiraNivelesScroll.isHidden = true
            return
        }
        if botonesNivel.isEmpty {
            for n in nivelesDisponibles {
                let b = UIButton(type: .system)
                styledOverlayButton(b, title: Self.nivelCorto(n), bg: Self.colorPastilla, fontSize: 13)
                b.accessibilityIdentifier = n
                b.addTarget(self, action: #selector(nivelTapped(_:)), for: .touchUpInside)
                botonesNivel[n] = b
                // Debajo va el nombre tal como sale en el reporte del seguro.
                tiraNiveles.addArrangedSubview(pastillaBilingue(b, n))
            }
        }
        for (n, b) in botonesNivel {
            b.backgroundColor = n == nivelActual ? Self.colorEscogido
                                                 : Self.colorPastilla
        }
        tiraNivelesScroll.isHidden = false
    }

    // "1st Floor" no cabe cuatro veces en una barra. Se acorta a lo que se lee
    // de un vistazo, pero el VALOR que viaja al reporte no se toca: ese va en
    // ingles al seguro.
    private static func nivelCorto(_ n: String) -> String {
        switch n {
        case "Basement":  return "Sótano"
        case "1st Floor": return "1er"
        case "2nd Floor": return "2do"
        case "3rd Floor": return "3er"
        case "Attic":     return "Ático"
        default:          return n
        }
    }

    @objc private func nivelTapped(_ b: UIButton) {
        guard let n = b.accessibilityIdentifier, n != nivelActual else { return }
        // Con una medida a medias no se cambia de nivel: se perderia sin avisar.
        if medidaEnCurso {
            say("Primero guarde o cancele la medida que lleva.", .aviso)
            return
        }
        pasoAbierto = nil
        nivelActual = n
        // Cambiar de nivel es empezar de cero en cuartos: el "Bedroom" de
        // arriba no es el "Bedroom" de abajo.
        roomName = ""
        roomAreaSqFt = 0
        ponerCuartosDeLaPlanta(n)
        actualizarTiraDeEstado()
        preguntar(.queCuarto, preguntaDeCuarto("\(n). "))
    }

    // ---- LO QUE YA LLEVA GUARDADO ----
    private var cuartosPintados = ""
    private func pintarTiraDeCuartos() {
        guard esRecorrido else { tiraCuartosScroll.isHidden = true; return }
        // Cada cuarto, con cuantas medidas lleva, en el orden en que los midio.
        var orden: [String] = []
        var cuenta: [String: Int] = [:]
        for it in items {
            let k = (it.nivel.isEmpty ? "" : it.nivel + " · ") + it.cuarto
            guard !it.cuarto.isEmpty else { continue }
            if cuenta[k] == nil { orden.append(k) }
            cuenta[k] = (cuenta[k] ?? 0) + 1
        }
        guard !orden.isEmpty else { tiraCuartosScroll.isHidden = true; cuartosPintados = ""; return }
        let firma = orden.map { "\($0)#\(cuenta[$0] ?? 0)" }.joined(separator: "|") + "@" + roomName
        guard firma != cuartosPintados else { return }
        cuartosPintados = firma
        tiraCuartos.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for k in orden {
            let b = UIButton(type: .system)
            let soloCuarto = k.components(separatedBy: " · ").last ?? k
            let n = cuenta[k] ?? 0
            styledOverlayButton(b, title: "✓ \(soloCuarto) (\(n))",
                                bg: Self.colorPastilla, fontSize: 12)
            b.accessibilityIdentifier = k
            b.addTarget(self, action: #selector(cuartoGuardadoTapped(_:)), for: .touchUpInside)
            if soloCuarto == roomName {
                b.backgroundColor = Self.colorEscogido
            }
            tiraCuartos.addArrangedSubview(b)
        }
        tiraCuartosScroll.isHidden = false
    }

    // Tocar uno de los guardados VUELVE a ese cuarto. Su pedido: "por si
    // queremos regresar a medir algo que se nos haya olvidado".
    @objc private func cuartoGuardadoTapped(_ b: UIButton) {
        guard let k = b.accessibilityIdentifier else { return }
        let partes = k.components(separatedBy: " · ")
        let cuarto = partes.last ?? k
        let nivel = partes.count > 1 ? partes[0] : nivelActual
        volverACuarto(nivel: nivel, cuarto: cuarto)
    }

    // Tocar un cuarto guardado y tocar "Cuarto anterior" van por aqui: los
    // mismos candados, la misma pregunta.
    private func volverACuarto(nivel: String, cuarto: String) {
        guard cuarto != roomName || nivel != nivelActual else { return }
        if medidaEnCurso {
            say("Primero guarde o cancele la medida que lleva.", .aviso)
            return
        }
        pasoAbierto = nil
        if nivel != nivelActual {
            // Igual que al tocar un nivel: la lista de cuartos y las areas de
            // ESE piso, o el candado de "no cabe" compara contra otro cuarto.
            nivelActual = nivel
            ponerCuartosDeLaPlanta(nivel)
        }
        cambiarCuarto(cuarto)
        preguntar(.queSeccion, "De vuelta en \(cuarto). ¿Piso, pared, techo, cocina, baño o materiales?")
    }

    @objc private func seccionTapped(_ b: UIButton) {
        guard let clave = b.accessibilityIdentifier, clave != section,
              seccionesDisponibles[clave] != nil else { return }
        // Lo que va a medias se queda a medias: cambiar de seccion con una
        // medida sin guardar la perderia sin avisar. El candado vive ahora en
        // cambiarSeccion, para que la voz tambien lo tenga.
        guard cambiarSeccion(clave) else { return }
        pasoAbierto = nil
        preguntar(.queMide, "\(Self.sectionSpokenName(clave).capitalized). ¿Qué va a medir?")
    }

    // Lo que dice la tira: nivel, cuarto y seccion, solo lo que ya se sabe.
    private func actualizarTiraDeEstado() {
        // Solo cuando la camara trae varias secciones, o sea en recorrido.
        // Entrando por el boton de UNA tarjeta no se pueden ofrecer: esa
        // medida ya tiene su tarjeta esperandola, y cambiarle la seccion la
        // dejaria guardada en el lugar equivocado.
        let hayVarias = seccionesDisponibles.count > 1
        tiraSecciones.isHidden = !hayVarias
        pintarTiraDeMateriales()
        pintarTiraDeAcciones()
        pintarAvanceDelCuarto()
        pintarTiraDeNiveles()
        pintarTiraDeCuartos()
        for (clave, b) in botonesSeccion {
            let esta = clave == section
            esconderPastilla(b, seccionesDisponibles[clave] == nil)
            b.backgroundColor = esta ? Self.colorEscogido
                                     : Self.colorPastilla
        }
        guard esRecorrido else { tiraEstado.isHidden = true; return }
        var p: [String] = []
        if !nivelActual.isEmpty { p.append(nivelActual) }
        if !roomName.isEmpty { p.append(roomName) }
        if !section.isEmpty { p.append(Self.sectionSpokenName(section).capitalized) }
        tiraEstado.setTitle(p.isEmpty ? "Toque para escoger" : p.joined(separator: "  ·  "), for: .normal)
        tiraEstado.isHidden = false
    }

    // ============ EL ASISTENTE LEE LOS CUARTOS DEL PLANO ============
    //
    // Su pedido del 12 de septiembre: "que el comando de voz diga: en este
    // nivel hay estos cuartos, ¿con cual quieres empezar primero? Que el
    // asistente de voz tambien sugiera y que lea inteligentemente que nombres
    // hay".
    //
    // Va con el telefono en alto y sin poder leer la pantalla, asi que la rueda
    // corta no le sirve de nada si nadie le dice lo que tiene.
    private var cuartosDeEstaPlanta: [String] { cuartosPorPlanta[nivelActual] ?? [] }

    // "En este nivel hay Family Room, Kitchen, Living Room y Hallway. ¿Con cual
    // quiere empezar?" - y si no hay plano de esta planta, la pregunta de
    // siempre, sin inventarse una lista.
    private func preguntaDeCuarto(_ prefijo: String = "") -> String {
        let cs = cuartosDeEstaPlanta
        guard !cs.isEmpty else { return prefijo + "¿Qué cuarto vamos a medir?" }
        // Se leen todos si son pocos. Con mas de seis, los seis primeros y
        // "...y otros N": una lista de dieciseis nombres dicha en voz alta no
        // se recuerda, se aguanta.
        let leidos = cs.count <= 6 ? cs : Array(cs.prefix(6))
        var lista = leidos.joined(separator: ", ")
        if cs.count > 6 { lista += ", y otros \(cs.count - 6)" }
        else if leidos.count >= 2, let ultimo = leidos.last {
            lista = leidos.dropLast().joined(separator: ", ") + " y " + ultimo
        }
        return prefijo + "En este nivel hay \(lista). ¿Con cuál quiere empezar?"
    }

    // Un nombre que NO esta en el plano de esta planta: se pregunta antes de
    // meterlo. Su pedido: "que el comando de voz diga: este cuarto no esta en
    // la lista, lo añado, y uno dice si o no".
    //
    // Solo se pregunta cuando HAY una lista del plano contra la que comparar.
    // Sin plano no hay nada que contradecir, y preguntar por cada nombre seria
    // un estorbo en cada cuarto.
    private var cuartoPorConfirmar: String?

    // ============ "CUARTO ANTERIOR" Y "CANCELAR", EN LA FILA DE ABAJO ============
    //
    // Su pedido del 13 de septiembre, con flecha roja: el Cancelar de arriba
    // pasa a la fila que se desliza, despues de "Otro cuarto", y junto a el un
    // boton para regresar al cuarto anterior. Arriba queda la pantalla libre.
    //
    // Los cuartos por los que ha pasado, en orden. "El anterior" es el ultimo
    // de esta lista que no es donde esta parado ahora.
    private var cuartosVisitados: [(nivel: String, cuarto: String)] = []
    // Cancelar cierra la camara y la web NO recibe nada: las medidas de esta
    // sesion se pierden. Arriba estaba lejos del pulgar; en la fila de abajo
    // queda al lado de "Otro cuarto", donde un toque de mas es facil. Por eso,
    // con medidas guardadas, el primer toque avisa y el segundo sale.
    private var cancelarPendiente = false
    private var cancelarReinicio: DispatchWorkItem?
    // Lo que el escribio con el teclado no se confirma: ya lo confirmo al
    // escribirlo.
    private var saltarConfirmacionDeCuarto = false
    private func confirmarCuartoFuera(_ nombre: String) -> Bool {
        guard !saltarConfirmacionDeCuarto else { return false }
        guard !cuartosDeEstaPlanta.isEmpty else { return false }
        let pelado = nombre.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
        if cuartosDeEstaPlanta.contains(where: {
            $0.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es")) == pelado
        }) { return false }
        cuartoPorConfirmar = nombre
        say("\(nombre) no está en el plano de este nivel. ¿Lo agrego?", .aviso)
        pasoPorArmar = .queCuarto
        return true
    }

    private func cambiarCuarto(_ nuevo: String) {
        cuartoPorConfirmar = nil
        roomName = nuevo
        anotarVisita()
        // El area del plano viaja hecha desde la web; aqui solo se busca.
        roomAreaSqFt = areasPorCuarto[nuevo] ?? 0
        // Entrar (o salir) de la cocina cambia la lista de Pared.
        if !section.isEmpty, seccionesDisponibles[section] != nil {
            materials = listaDeMateriales(section)
            materialPickerView.reloadAllComponents()
        }
        actualizarTiraDeEstado()
    }

    private static func claveUso(_ section: String) -> String { "arMatUso:v1:" + section }
    private func recordarMaterialUsado(_ valor: String) {
        let k = Self.claveUso(section)
        var conteo = (UserDefaults.standard.dictionary(forKey: k) as? [String: Int]) ?? [:]
        conteo[valor] = (conteo[valor] ?? 0) + 1
        UserDefaults.standard.set(conteo, forKey: k)
    }
    private func materialMasUsado() -> String? {
        let conteo = (UserDefaults.standard.dictionary(forKey: Self.claveUso(section)) as? [String: Int]) ?? [:]
        // Dos veces, no una: una es casualidad. Misma regla que el escaner.
        return conteo.filter { $0.value >= 2 }.max { $0.value < $1.value }?.key
    }

    private enum Surface { case wall, floor, ceiling, other }
    private var lastSurfaceSpoken: Surface?
    // Un solo aviso por medida: si insiste en Guardar, se guarda. El sabe si
    // el corte era de dos pies o menos; la app avisa una vez, no discute.
    private var yaAvisoFaltaAncho = false
    // El aviso escrito se lo comia el siguiente updateUI() - y updateUI()
    // corre al marcar la casilla del compañero, y ahora tambien desde el
    // temporizador del aviso rojo. Se guarda aparte y updateUI lo respeta
    // hasta que el estado que lo causo deje de ser cierto.
    private var avisoEnPantalla: String?
    // El recibo hablado ya se dijo y esta esperando el segundo toque.
    private var resumenPendiente = false
    // El recibo escrito, para que updateUI no se lo coma.
    private var reciboEnPantalla: String?
    private var surfaceStableSince: Date?
    private var pendingSurface: Surface?

    private static func surfaceName(_ s: Surface) -> String {
        switch s {
        case .wall: return "una pared"
        case .floor: return "el piso"
        case .ceiling: return "el techo"
        case .other: return "una superficie"
        }
    }

    private let sceneView = ARSCNView()
    private let lineLayer = CAShapeLayer()
    private let instructionLabel = CasillaDeInstruccion()
    private let liveLabel = UILabel()
    private let addButton = UIButton(type: .system)
    private let undoButton = UIButton(type: .system)
    private let addWidthButton = UIButton(type: .system)
    private let saveContinueButton = UIButton(type: .system)
    private let finishPathButton = UIButton(type: .system)
    private let finishButton = UIButton(type: .system)
    // ============ EL RECORDATORIO DEL COMPAÑERO ============
    //
    // Su foto del 13 de septiembre, marcada en rojo: la casilla grande "¿Lleva
    // Base/Underlayment? toque aqui..." quedaba debajo de las filas y del +, y
    // no se leia. Lo pidio como "un pequeño recordatorio enfrente de la
    // pantalla, y despues que desaparezca". Marcar SI lleva sigue siendo suyo:
    // la pastilla del compañero en la fila de abajo (y la voz). Esto solo
    // recuerda; nunca marca nada.
    private let recordatorioLabel = CasillaDeInstruccion()
    private var recordatorioOcultar: DispatchWorkItem?
    // Para QUE compañero ya se mostro en esta medida. Por valor, no un si/no:
    // si corrige de laminado a alfombra, el Pad merece su propio recordatorio.
    private var recordatorioCompaneroPara: String?

    // ============ EL MARGEN DE ABAJO, SEGUN LA PANTALLA DE CADA UNO ============
    //
    // Su pedido del 13 de septiembre, con su foto marcada en rojo: el boton
    // + se quedaba con un pedazo de pantalla vacio abajo, sin usar - "en la
    // parte de abajo tenemos amplio espacio... debes hacer la aplicacion
    // inteligente para darse cuenta de eso cuando abren cada telefono para
    // que los margenes sean los adecuados". La cuadrilla trae tres modelos
    // distintos (17 Pro Max, 16 Pro Max, 17 Pro), cada uno con su propia
    // altura util - un numero fijo que se ve bien en uno deja sobrando en
    // otro.
    //
    // margenControlesConstraints guarda las 4 anclas de fondo que antes
    // eran numeros sueltos (-140 para +, -32 para las otras tres); ahora
    // las cuatro comparten UNA fraccion de lo que YA hay disponible en la
    // pantalla de ESE telefono, recalculada en viewDidLayoutSubviews (la
    // primera pasada, antes de que la vista tenga su tamaño real, usa el
    // valor de siempre como reserva).
    private var margenControlesConstraints: [NSLayoutConstraint] = []
    private func margenInferiorControles() -> CGFloat {
        let alto = view.safeAreaLayoutGuide.layoutFrame.height
        guard alto > 0 else { return 32 }
        return min(56, max(24, alto * 0.035))
    }
    private let torchButton = UIButton(type: .system)
    private var isTorchOn = false
    private let helpButton = UIButton(type: .system)
    // "Creo que tiene que haber un botón al lado que diga asistente, y si
    // pucho asistente ya sale el voice command para ayudarme, y también
    // detecta dónde estoy." Eso es este boton: tocarlo cuenta la situacion
    // completa - que seccion, que material, en que paso va, y que sigue.
    private let assistantButton = UIButton(type: .system)
    // Y el de al lado apaga la voz automatica, sin apagar al asistente: el
    // boton de arriba sigue contestando cuando se le pida.
    private let muteButton = UIButton(type: .system)
    private var vozBotones: [UIButton] = []
    // Un punto que dice si el microfono esta vivo. Su reporte era "ya no
    // escucha" - y lo peor de eso no era que se cayera, sino que NO HABIA
    // MANERA DE SABERLO: le hablaba y no pasaba nada, sin explicacion.
    private let micDot = UILabel()
    private let orbita = OrbitaVoz(frame: .zero)
    // "1er Piso · Master Bedroom · Piso". En un recorrido de casa entera, sin
    // esto uno se pierde: la camara se ve igual en todos los cuartos. Tocarla
    // abre el selector para corregir a mano.
    private let tiraEstado = UIButton(type: .system)

    // ============ CAMBIAR DE SECCION CON EL DEDO ============
    //
    // Su reporte: "estoy midiendo pared, pero en la pantalla... yo me puedo
    // cambiar a medir piso, o si yo quiero cambiar a medir techo, puedo
    // hacerlo en la misma pantalla y seguir midiendo... porque el AI
    // assistant hay cosas que no entiende. Le repito y le repito que ya no
    // quiero medir pared y no me entiende."
    //
    // Tiene toda la razon, y el arreglo de verdad no es enseñarle mas frases
    // al asistente - eso tambien se hizo, pero un asistente SIEMPRE va a
    // tener un dia malo. Lo que no puede pasar es que se quede encerrado en
    // una seccion. Cuatro botones, siempre a la vista, y se acabo.
    //
    // 13 de septiembre: con Materiales, "Materiales" no cabia en una fila de
    // cuatro pastillas del mismo ancho (fillEqually) y salia cortada
    // ("M...ales"). Ella eligio la Opcion B: una franja que CORRE, igual que
    // la de materiales de aqui abajo - cada pastilla mide lo que necesita su
    // palabra, y si un dia se agrega una quinta seccion no hay que rediseñar
    // nada. tiraSecciones sigue siendo lo que todo el resto del archivo ya
    // toca (isHidden, la columna, el alto): ahora es el UIScrollView; la fila
    // de botones de verdad es filaSecciones, adentro.
    private let tiraSecciones = UIScrollView()
    private let filaSecciones = UIStackView()
    private var botonesSeccion: [String: UIButton] = [:]

    // ============ LOS MATERIALES, ABAJO, DE UN TOQUE ============
    //
    // Su pedido: "despues de seleccionar que se va a medir, seria bueno que
    // pongas otra barra abajo... y me ponga los materiales para solo darle
    // clic. Porque a veces yo le digo al voice assistant drywall" - y no le
    // entendia.
    //
    // Va ABAJO, pegada al boton +, porque ahi es donde tiene el pulgar cuando
    // esta midiendo. La lista completa sigue existiendo en el boton de lista;
    // esta barra es para los tres o cuatro que de verdad usa en esta seccion,
    // sin abrir nada encima de la camara.
    private let tiraMateriales = UIScrollView()
    private let filaMateriales = UIStackView()

    // ============ TODO A UN TOQUE, SIN HABLAR ============
    //
    // Su pedido: "abajo de las barritas donde estan los materiales, abajo
    // puedes poner medir ancho o agregar insulacion... y despues podemos darle
    // guardar, o tambien siguiente u otro cuarto, en la misma camara. Clic,
    // clic, clic, guardar, pum, ya pasamos a otro cuarto".
    //
    // Los botones de estas acciones YA EXISTIAN, pero repartidos por la
    // pantalla y cada uno apareciendo solo en su etapa: para llegar a uno habia
    // que estar en el paso correcto, y si la voz no entendia, no habia camino.
    // Esta fila los junta en un solo renglon, SIEMPRE a la vista, y el que no
    // se puede usar ahorita se ve apagado en vez de desaparecer - asi la
    // pantalla no se le mueve debajo del dedo.
    // ============ LA BARRA DE NIVELES ============
    //
    // Su pedido: "en medir diferentes niveles, arriba donde dice piso, tienes
    // que agregarle sótano, primer nivel, segundo nivel, tercer nivel, porque
    // son diferentes niveles... es donde tienes que expandir toda la
    // informacion".
    //
    // SOLO en "diferentes niveles", y eso es el punto: en "un nivel completo"
    // el nivel se escogio una vez en la pantalla y no cambia - poner la barra
    // ahi seria ofrecerle tocar algo que no deberia tocar. En "un cuarto"
    // tampoco. Cada alcance muestra lo que ese alcance necesita.
    // Las cuatro barras de arriba viven en esta columna. Ver el comentario de
    // las restricciones: anclarlas a mano fue lo que las dejo encimadas.
    private let columnaArriba = UIStackView()
    private let tiraNivelesScroll = UIScrollView()
    private let tiraNiveles = UIStackView()
    private var botonesNivel: [String: UIButton] = [:]

    // ============ LO QUE YA LLEVA GUARDADO, AL LADO ============
    //
    // Su pedido: "al lado de la cámara, en una esquina, el nombre del cuarto y
    // guardado... para mostrar cuántos cuartos llevamos, y si se llena la
    // barrita podemos escrolearle, por si queremos regresar a medir algo que se
    // nos haya olvidado".
    //
    // En una casa de ocho cuartos, saber si ya se hizo el baño de arriba
    // obligaba a salir de la camara. Y lo segundo que pidio es lo que de verdad
    // lo salva: TOCAR uno de esos para volver a ese cuarto sin salir.
    private let tiraCuartosScroll = UIScrollView()
    private let tiraCuartos = UIStackView()

    private let tiraAccionesScroll = UIScrollView()
    private let tiraAcciones = UIStackView()
    private var botonesAccion: [String: UIButton] = [:]

    // Lo que YA lleva completo de ESTE cuarto. Su pedido: "en una esquina tiene
    // que aparecer el nombre como master room, completo la pared, cielo, piso".
    //
    // En una casa de ocho cuartos, acordarse de si al baño ya se le midió el
    // techo es imposible - y la unica forma de enterarse era salir de la camara
    // a mirar las tarjetas. Se lee de las medidas ya guardadas, no de una
    // bandera aparte que se podria desincronizar.
    private let avanceLabel = CasillaDeInstruccion()
    // Nivel suavizado del microfono, para mover la bolita. Se escribe en la
    // cola del audio y se lee en el tick: es un solo Float, y leerlo un
    // milisegundo tarde no cambia nada que el ojo note.
    private var nivelVivo: Float = 0
    private let helpOverlay = UIView()
    private let crosshair = UIView()

    private let materialOverlay = UIView()
    private let materialCard = UIView()
    private let materialTitleLabel = UILabel()
    private let materialPickerView = UIPickerView()
    private let materialConfirmButton = UIButton(type: .system)
    private var selectedMaterial: ARMaterialOption?
    // LOS MATERIALES ESCRITOS A MANO, por sección (21 sep 2026). Su pedido, con
    // la fila de materiales marcada en rojo al final: "every section should
    // have another section to say other, so they can type the exact name".
    // Se quedan el resto de la sesión en SU sección: si escribe "Stair treads"
    // en Piso y mide cinco escalones, no lo teclea cinco veces. No viajan a
    // otra sección, ni a la sesión siguiente.
    private var materialesEscritos: [String: [ARMaterialOption]] = [:]
    // Escrito a mano EN ESTA SECCION y que no esta en su catalogo. Mirar todas
    // las secciones fallaba: "Insulation" escrito en Piso (donde no esta en la
    // lista) hacia que el Insulation DE CATALOGO de Pared dejara de contarse.
    private func esEscrito(_ valor: String) -> Bool {
        (materialesEscritos[section] ?? []).contains { $0.value == valor }
            && !(seccionesDisponibles[section] ?? []).contains { $0.value == valor }
    }
    // Convenience: the companion info for whichever material is currently
    // selected, if it has one.
    private var currentCompanion: (value: String, en: String, es: String)? {
        guard let m = selectedMaterial, let v = m.companionValue, let en = m.companionEn, let es = m.companionEs else { return nil }
        return (v, en, es)
    }

    private var pendingStart: simd_float3?
    private var pendingStartNode: SCNNode?

    // The length measurement currently being built, as a corner-to-corner
    // path rather than one straight segment - a plain wall is just a
    // two-point path, and a run that turns a corner (baseboard, crown
    // molding, an L-shaped cut) keeps adding points until "Terminar
    // Recorrido" closes it off. pathTotalFeet is always the sum of every
    // consecutive pair in pathPoints, kept in sync by recomputePathTotal()
    // so Undo can drop just the last corner without redoing the whole walk.
    private var pathPoints: [simd_float3] = []
    private var pathTotalFeet: Double = 0
    // LAS ESQUINAS DEL ANCHO. Su reporte del 12 de septiembre: "al medir el
    // ancho necesitamos que nos de para medir varios puntos, como en el largo,
    // porque a veces el ancho tiene varios puntos, como que gira la pared".
    //
    // Aqui habia un comentario mio que decia "Width stays a single straight
    // segment - it doesn't need to turn corners the way a perimeter run does".
    // Esa suposicion es falsa en una casa de verdad: un cuarto en L, un nicho,
    // una pared que dobla. El ancho se media de dos puntos y punto, asi que lo
    // que giraba habia que partirlo en dos medidas o medirlo de menos.
    //
    // Vacio con `currentWidthFeet` puesto = un ancho DICTADO por voz ("ancho
    // tres pies"). No se mezclan los dichos con los caminados, igual que en el
    // largo.
    private var widthPoints: [simd_float3] = []
    // Un largo DICTADO vale tanto como uno caminado: las dos son medidas que
    // el dio. Sin esta bandera, "doce por diez" anotaba el numero y luego
    // Guardar no hacia nada - `pathPoints` estaba vacio y el guard lo tiraba
    // en silencio, que es la peor forma de fallar.
    private var largoDictado = false
    private var hasLengthMeasurement: Bool { pathPoints.count >= 2 || largoDictado || esPorPieza }
    // ¿El material escogido se cuenta? Entonces no hay esquinas que marcar:
    // el numero vive en `piezasContadas` y se guarda en el mismo campo del
    // largo, igual que en el formulario.
    private var esPorPieza: Bool { selectedMaterial?.porPieza == true }
    private var piezasContadas: Int = 1
    // Al escoger un material que se cuenta, el numero arranca en 1 y se guarda
    // en el MISMO campo del largo, para que todo lo de abajo (guardar, el
    // resumen, lo que viaja al formulario) siga funcionando sin cambios.
    private func arrancarConteoSiHaceFalta() {
        guard esPorPieza else { return }
        say("Eso se cuenta, no se mide. Lleva 1. Toque más 1 si hay otro, y Guardar.", .guia)
        piezasContadas = 1
        pathTotalFeet = 1
        currentWidthFeet = nil
        widthPoints = []
        pathPoints = []
        largoDictado = false
        stage = .lengthDone
    }
    private var currentWidthFeet: Double?
    private var currentMarkers: [SCNNode] = []
    // A solid 3D line for every segment already closed (one per completed
    // corner-to-corner leg, plus one for width if it's used) - anchored in
    // the scene like the markers, not a screen-space overlay, so it stays
    // put and reads correctly from any angle as the crew walks around it.
    private var currentLines: [SCNNode] = []
    // Resets to false for every new measurement - not all walls have
    // insulation behind them, so this is asked fresh each time rather than
    // remembered from the last one.
    private var includeCompanion = false

    // Every banked measurement, each keeping its own markers so Undo can
    // remove them again if the crew backs out of the last one.
    // Cada medida se guarda ETIQUETADA con donde se tomo. Antes era una lista
    // plana sin nivel, cuarto ni seccion - por eso la web no tenia mas remedio
    // que meterlo todo en la tarjeta de la que vino el boton.
    private var items: [(length: Double, width: Double?, material: String, companion: String?,
                         nivel: String, cuarto: String, seccion: String, markers: [SCNNode])] = []

    private var displayLink: CADisplayLink?

    private enum Stage { case pickingMaterial, measuringLength, lengthDone, measuringWidth, widthDone }
    private var stage: Stage = .measuringLength {
        didSet {
            // Cada medida nueva merece que le diga otra vez que esta viendo:
            // entre una y otra el tecnico camino a otra pared.
            if oldValue != stage {
                lastSurfaceSpoken = nil
                pendingSurface = nil
                surfaceStableSince = nil
            }
            updateUI()
        }
    }

    override func viewDidLoad() {
        // Lo que mando la web al abrir, guardado tal cual: es a lo que se
        // vuelve cuando una planta no tiene lista propia en el plano.
        cuartosDeArranque = cuartosDisponibles
        // El cuarto con el que abrio la camara cuenta como el primero visitado.
        anotarVisita()
        if !nivelActual.isEmpty { ponerCuartosDeLaPlanta(nivelActual) }
        super.viewDidLoad()
        view.backgroundColor = .black
        setupScene()
        setupUI()
        setupMaterialPicker()
        setupHelpOverlay()
        // Las capas de material y de ayuda se agregan despues de los botones,
        // asi que quedaban ENCIMA del Asistente - justo cuando alguien esta
        // parado frente a una lista de materiales sin saber cual escoger es
        // cuando mas falta le hace poder preguntar. Se suben al frente.
        view.bringSubviewToFront(assistantButton)
        view.bringSubviewToFront(muteButton)
        // ...pero la ayuda va POR ENCIMA de todo. Subir los botones los dejo
        // tambien encima de la tarjeta de ayuda, tapandole el paso 1 y - peor -
        // robandole los toques: arrastrar para leer los pasos caia en el boton
        // de mudo y apagaba la voz sin querer.
        view.bringSubviewToFront(columnaArriba)
        view.bringSubviewToFront(helpOverlay)
        stage = (materials.isEmpty && !esRecorrido) ? .measuringLength : .pickingMaterial
        // Lo que mas usa en esta seccion, ya seleccionado. Un toque menos por
        // medida, y en un trabajo son veinte medidas.
        if let usual = materialMasUsado(), let fila = materials.firstIndex(where: { $0.value == usual }) {
            materialPickerView.selectRow(fila, inComponent: 0, animated: false)
        }
        updateUI()

        // El sonido: esta pantalla solo habla, no escucha. .playback con
        // .duckOthers para que se oiga por encima de lo que traigan sonando
        // sin apagarselo, y sin pelearse con el microfono del escaner.
        speech.delegate = self
        // .playAndRecord porque ahora tambien ESCUCHA.
        //
        // MODO .voiceChat. Su pedido: "el voice assistant tiene que evitar los
        // sonidos exteriores y enfocarse mas en mi voz". Esto prende el
        // procesamiento de voz que iOS ya trae - quita ruido de fondo y cancela
        // el eco de la propia bocina - y es lo mismo que usa una llamada de
        // FaceTime. Una casa en secado tiene tres ventiladores y un
        // deshumidificador andando: eso es exactamente el ruido que este modo
        // esta hecho para descontar.
        //
        // NUNCA .measurement: el escaner ya se quemo con ese - baja el volumen
        // de salida por diseño y dejo mudas todas las respuestas. .voiceChat es
        // otra cosa (esta hecho para hablar Y oir), y con .defaultToSpeaker la
        // salida se queda en la bocina de altavoz, no en la del oido.
        //
        // Y SI FALLA, se cae a .default: quedarse sin sesion de audio seria
        // quedarse sin voz y sin microfono de un golpe.
        // FUERA DEL HILO QUE DIBUJA. `setActive` puede tardar decimas -
        // negocia con el resto del sistema quien se queda con el audio - y
        // hacerlo aqui, justo cuando ARKit arranca, es congelar la pantalla
        // antes de que aparezca.
        filaAudio.async {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat,
                                                                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            } catch {
                try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default,
                                                                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            }
            try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        }
        observarInterrupciones()
        pedirPermisoYEscuchar()

        // LA PRIMERA VEZ SE ABRE SOLA. Este era el hueco de verdad: los ocho
        // pasos de "Cómo Medir" ya estaban escritos, pero detras de un boton
        // "?" que alguien que no sabe usar la app nunca va a tocar, porque no
        // sabe que existe. Ahora la primera vez que abre la camara, la ayuda
        // se abre sola y ademas se dice en voz alta.
        let d = UserDefaults.standard
        // Si ya conoce la pantalla, NO se dice nada al abrir. Antes saludaba
        // cada vez ("Cámara de medir, toque el signo de interrogación") y esa
        // frase no le servia para nada mas que sonar.
        if !d.bool(forKey: Self.seenHelpKey) {
            d.set(true, forKey: Self.seenHelpKey)
            helpOverlay.isHidden = false
            speakHelpIntro()
        } else if (!crewName.isEmpty || !roomName.isEmpty), reconocedor?.isAvailable != true {
            // Respaldo: solo si el microfono NO va a arrancar. Si arranca, el
            // saludo va dentro de su frase (ver empezarAEscuchar) para que no
            // se corten entre si.
            // Ni un saludo de relleno ni silencio total: se dice lo UNICO que
            // el no puede ver de un vistazo y que confirma que la app entendio
            // bien de que tarjeta vino - su nombre y el cuarto.
            var saludo = crewName.isEmpty ? "Listo" : "Listo, \(crewName)"
            if !roomName.isEmpty {
                saludo += ". \(Self.sectionSpokenName(section).capitalized) de \(roomName)"
            }
            say(saludo + ".", .guia, llave: "saludo")
        }
    }

    // El "asistente" del margen de abajo: en cuanto la vista tiene su tamaño
    // real (view.safeAreaLayoutGuide ya no es un adivinado de arranque),
    // se recalculan las 4 anclas de fondo para ESE telefono. Corre en cada
    // pasada de layout (tambien tras un giro o un cambio de tamaño), asi que
    // nunca hace falta abrir la app dos veces para que se vea bien.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ajustarMargenInferior()
    }
    // Con "Escoger de la lista" a la vista, los controles se paran ENCIMA de
    // ella. Su foto del 13 de septiembre: con el margen nuevo, el + quedaba
    // debajo del boton de la lista.
    private func ajustarMargenInferior() {
        var margen = margenInferiorControles()
        // Solo cuando la lista y el + estan A LA VEZ en pantalla (una pregunta
        // de cuarto/nivel/seccion abierta mientras mide). Al escoger material
        // el + esta escondido y la lista cabe debajo de las filas: si aqui
        // tambien subieran, todo el bloque brincaria ~50 pt en cada medida y
        // el dedo caeria en un material en vez de en "Otro cuarto".
        if !listaButton.isHidden, stage != .pickingMaterial {
            let alto = listaButton.bounds.height > 0 ? listaButton.bounds.height : listaButton.intrinsicContentSize.height
            margen = max(margen, 24 + alto + 10)
        }
        for c in margenControlesConstraints where c.constant != -margen { c.constant = -margen }
    }
    private static let seenHelpKey = "arMeasureSeenHelp:v1"

    // La version hablada de la ayuda: corta a proposito. Los ocho pasos
    // escritos siguen en pantalla para el que quiera leerlos; al oido, tres
    // frases es lo que aguanta alguien parado con el telefono en alto.
    private func speakHelpIntro() {
        // UNA sola frase, no cinco. Cinco llamadas a say() seguidas se
        // encolaban y tardaban casi medio minuto en salir: eso, literalmente,
        // era el asistente "atrasado" desde el primer segundo.
        decirPorPeticion("Párese en una esquina, apunte la cámara y toque el botón de más. Camine a la siguiente esquina y toque más otra vez. Si necesita ayuda en cualquier momento, toque el botón naranja del asistente y le digo dónde va.")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        sceneView.session.delegate = self
        sceneView.session.run(config)
        camaraDesde = Date()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .default)
        displayLink = link
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
        displayLink?.invalidate()
        displayLink = nil
        // Always off on the way out, however the crew leaves this screen -
        // otherwise it stays lit and drains the battery after they've
        // already moved on.
        setTorch(false)
        // Y lo mismo con la voz y el audio. Sin esto la camara seguia hablando
        // encima del formulario despues de cerrarse, y la musica del tecnico
        // se quedaba bajita para siempre porque nadie soltaba la sesion. El
        // escaner de planos ya lo hacia bien; esta pantalla no.
        speech.stopSpeaking(at: .immediate)
        dejarDeEscuchar()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Torch

    // ARSession owns the camera's image capture, but the torch LED can
    // still be driven directly through AVCaptureDevice - that's the
    // standard, ARKit-safe way to do this, as long as nothing here tries
    // to also start its own AVCaptureSession.
    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            isTorchOn = on
            let imageName = isTorchOn ? "bolt.fill" : "bolt.slash.fill"
            torchButton.setImage(UIImage(systemName: imageName), for: .normal)
            torchButton.backgroundColor = isTorchOn
                ? UIColor.systemYellow.withAlphaComponent(0.95)
                : Self.colorPastilla
            torchButton.tintColor = isTorchOn ? .black : .white
        } catch {
            // Not critical to the measuring flow itself - just leave the
            // button as it was.
        }
    }

    @objc private func torchTapped() {
        setTorch(!isTorchOn)
    }

    // "El voice command tiene que saber qué botones ya puché y dónde estoy."
    // Esto es exactamente eso, dicho de corrido: la seccion de la que vino,
    // el material que ya escogio, en que paso va, cuantas esquinas lleva, lo
    // que ya tiene guardado, y - lo unico que de verdad importa - QUE SIGUE.
    // Probar una voz: se guarda y se dice una frase REAL de las que va a oir
    // en el trabajo, no un "hola, uno dos tres". Asi la compara como suena de
    // verdad.
    @objc private func vozTapped(_ sender: UIButton) {
        guard let id = sender.accessibilityIdentifier,
              let voz = AVSpeechSynthesisVoice(identifier: id) else { return }
        VozAsistente.escoger(voz)
        for b in vozBotones {
            b.backgroundColor = (b === sender)
                ? Self.colorEscogido
                : UIColor(white: 0.22, alpha: 1)
        }
        speech.stopSpeaking(at: .immediate)
        decirPorPeticion("Con esta voz le voy a ayudar. La pared se mide largo por alto, para sacar los pies cuadrados.")
    }

    // Abre el selector en el paso que corresponda: si hay una pregunta del
    // recorrido abierta, esa; si no, materiales.
    private func abrirSelector(_ paso: Paso) {
        ocultarRecordatorio()
        pasoDelSelector = paso
        materialTitleLabel.text = {
            switch paso {
            case .queNivel:   return "¿En qué nivel?"
            case .queCuarto:  return "¿Qué cuarto?"
            case .queSeccion: return "¿Qué va a medir: piso, pared, techo o materiales?"
            default:          return "¿Qué está midiendo?"
            }
        }()
        materialPickerView.reloadAllComponents()
        materialPickerView.selectRow(0, inComponent: 0, animated: false)
        listaVisible = true
        speech.stopSpeaking(at: .immediate)
        pasoAbierto = nil
        pasoPorArmar = nil
        materialOverlay.isHidden = false
    }

    @objc private func tiraEstadoTapped() {
        // Toca la tira = corregir donde estoy. Se abre por el dato que falta,
        // y si no falta ninguno, por el cuarto - que es lo que mas cambia.
        if nivelActual.isEmpty { abrirSelector(.queNivel) }
        else if roomName.isEmpty { abrirSelector(.queCuarto) }
        else { abrirSelector(.queCuarto) }
    }

    @objc private func listaTapped() {
        // En el recorrido el boton abre el paso que este abierto, no siempre
        // materiales: si la app pregunto "¿qué cuarto?", la lista tiene que ser
        // de cuartos.
        if let p = pasoAbierto ?? pasoPorArmar,
           p == .queNivel || p == .queCuarto || p == .queSeccion {
            abrirSelector(p)
            return
        }
        listaVisible = true
        speech.stopSpeaking(at: .immediate)
        pasoAbierto = nil
        pasoPorArmar = nil
        updateUI()
    }

    @objc private func assistantTapped() {
        decirPorPeticion(situacionActual())
    }

    @objc private func muteTapped() {
        asistenteHabla.toggle()
        // Apagar la voz apaga tambien el oido: si la app no le va a contestar,
        // tenerla escuchando solo gasta bateria. Y el indicador lo dice.
        micApagadoPorElUsuario = !asistenteHabla
        if micApagadoPorElUsuario { dejarDeEscuchar() } else { empezarAEscuchar() }
        actualizarIndicadorMicro()
        if asistenteHabla {
            decirPorPeticion("Voz encendida. " + situacionActual())
        } else {
            speech.stopSpeaking(at: .immediate)
            // Lo que el asistente estaba anunciando se quita de la casilla en
            // ese momento; vuelve la instruccion del paso, que no es de la voz.
            if (instructionLabel.text ?? "").hasPrefix("🎤") {
                casillaOcultar?.cancel(); casillaOcultar = nil
                UIView.animate(withDuration: 0.2) { self.instructionLabel.alpha = 0 }
                updateUI()
            }
        }
    }

    // EL RECIBO HABLADO, antes de mandar nada.
    //
    // Se dice en el PRIMER toque de Terminar y se manda en el segundo. Dos
    // razones, las dos de peso:
    //   1. Es la ultima oportunidad de oir un disparate ("ciento cuarenta
    //      pies lineales de zocalo" en un baño) mientras todavia esta parado
    //      adentro y lo puede arreglar.
    //   2. Decirlo Y cerrar la pantalla a la vez no funciona: al cerrarse, la
    //      voz se corta a media frase. Con el segundo toque ya lo oyo entero.
    // ¿CABE ESTO EN EL CUARTO? El plano escaneado ya sabe cuanto mide la
    // recamara. Si la medida es MAYOR que el cuarto entero, eso no es una
    // demolicion grande: es un dedo de mas, o una esquina marcada en la casa
    // del vecino.
    //
    // SOLO SE AVISA HACIA ARRIBA, y esa asimetria es a proposito: medir MENOS
    // que el cuarto es lo normal - casi nunca se quita el piso completo, se
    // quita la parte mojada. Avisar de eso seria gritar en cada medida hasta
    // que dejen de hacer caso. Medir MAS que el cuarto es imposible.
    //
    // RECIBE los valores en vez de leerlos de las variables: la primera
    // version los leia DESPUES de que guardar ya las habia puesto en cero, asi
    // que el chequeo entero era codigo muerto y nunca aviso de nada.
    private func avisarSiNoCabe(largo: Double, ancho: Double?) {
        guard roomAreaSqFt > 0, let ancho = ancho,
              section == "floor" || section == "ceiling" else { return }
        let area = largo * ancho
        guard area > roomAreaSqFt * 1.15 else { return }
        say("Ojo: acaba de medir \(Int(area.rounded())) pies cuadrados, pero el plano dice que \(roomName) completo tiene \(Int(roomAreaSqFt.rounded())). No cabe. Revise la medida antes de mandarla.", .aviso)
    }

    private func resumenHablado() -> String {
        var porMaterial: [(String, Double, Double)] = []   // material, sqft, lineal
        for it in items {
            let sq = it.width.map { $0 * it.length } ?? 0
            let li = it.width == nil ? it.length : 0
            if let i = porMaterial.firstIndex(where: { $0.0 == it.material }) {
                porMaterial[i].1 += sq
                porMaterial[i].2 += li
            } else {
                porMaterial.append((it.material, sq, li))
            }
        }
        let partes = porMaterial.map { m -> String in
            let nombre = materials.first(where: { $0.value == m.0 }).map { Self.nombreDeBoton($0) } ?? m.0
            var t: [String] = []
            if m.1 > 0 { t.append(String(format: "%.0f pies cuadrados", m.1)) }
            if m.2 > 0 { t.append(String(format: "%.0f pies lineales", m.2)) }
            return "\(t.joined(separator: " y ")) de \(nombre.lowercased())"
        }
        let conCompanero = items.compactMap { $0.companion }
        var frase = "Va a mandar \(items.count) medida\(items.count == 1 ? "" : "s")"
        if !roomName.isEmpty { frase += " de \(roomName)" }
        frase += ": " + partes.joined(separator: ", ") + "."
        if !conCompanero.isEmpty {
            let unicos = Array(Set(conCompanero)).joined(separator: " y ")
            frase += " Con \(unicos.lowercased())."
        }
        return frase
    }

    private func situacionActual() -> String {
        var partes: [String] = []

        // Donde esta: la seccion de la que toco la camara.
        let sec = Self.sectionSpokenName(section)
        if !sec.isEmpty { partes.append("Está midiendo \(sec)") }

        // Que ya escogio.
        if let m = selectedMaterial {
            partes.append("escogió \(Self.nombreDeBoton(m))")
        }

        // Lo que ya lleva guardado en esta sesion de camara.
        if !items.isEmpty {
            partes.append(items.count == 1 ? "lleva 1 medida guardada" : "lleva \(items.count) medidas guardadas")
        }
        var frase = partes.isEmpty ? "" : partes.joined(separator: ", ") + ". "

        // Un piso con mas de dos esquinas esta mal medido PASE LO QUE PASE
        // despues, asi que se dice antes de mirar la etapa: al tocar Terminar
        // Recorrido el problema no se arregla, solo deja de verse.
        if Self.forma(section: section) == .rectangulo, pathPoints.count > 2,
           stage != .pickingMaterial {
            frase += "Ojo: lleva \(pathPoints.count) esquinas, y un piso o un techo se mide con dos. Así el área sale mal: guarde el cuarto en pedazos. "
        }

        // Con el recibo esperando, lo unico que importa es el recibo. Antes
        // le mandaba a tocar "Guardar y Seguir" - un boton que en ese momento
        // ya no hace lo que dice.
        if resumenPendiente {
            return resumenHablado() + " Toque Sí, mandar para mandarlo, o siga midiendo si falta algo."
        }

        // En que paso va y QUE SIGUE - esto es lo que de verdad necesita.
        switch stage {
        case .pickingMaterial:
            frase += "Escoja de la lista qué material va a medir y toque Confirmar."
        case .measuringLength:
            if pathPoints.isEmpty {
                frase += "Apunte a la primera esquina y toque el botón de más."
            } else if pathPoints.count == 1 {
                frase += "Ya marcó la primera esquina. Camine a la siguiente y toque más otra vez."
            } else {
                frase += "Lleva \(pathPoints.count) esquinas y \(Self.piesTexto(pathTotalFeet)) de largo. "
                if Self.forma(section: section) == .rectangulo {
                    // Con mas de dos esquinas ya NO "tiene el largo": el area
                    // va a salir mal. Decirle que siga adelante seria
                    // contradecir el aviso que la app misma acaba de darle.
                    frase += pathPoints.count > 2
                        ? "Toque Deshacer hasta dejar dos esquinas."
                        : "Ya tiene el largo: toque Terminar Recorrido y luego Medir Ancho."
                } else {
                    frase += "Puede seguir a la siguiente esquina, o tocar Terminar Recorrido."
                }
            }
        case .lengthDone:
            frase += "Tiene \(Self.piesTexto(pathTotalFeet)) de largo. "
            // Tres casos, no dos. El else de antes le decia a TODA medida de
            // cocina que iba por pie lineal - una afirmacion que la app misma
            // se niega a hacer en otro lado, porque no hay regla pareja y una
            // unidad inventada es una linea que el seguro rebota.
            switch selectedMaterial.map({ unidad(for: $0.value) }) ?? .depende {
            case .cuadrado:
                if currentWidthFeet == nil {
                    // En la pared la app NO puede saber todavia si va por pie
                    // cuadrado: eso depende del ALTO del corte, que es justo lo
                    // que falta por medir. Afirmarlo aqui contradiria la regla
                    // de los dos pies que la app misma explica al escoger el
                    // material.
                    frase += section == "wall"
                        ? "Le falta el alto del corte: toque Medir Ancho. Si el corte es de dos pies o menos va por pie lineal, y con el largo basta."
                        : "Le falta el ancho: toque Medir Ancho, porque esto se cobra por pie cuadrado."
                } else {
                    frase += "Ya tiene las dos medidas: toque Guardar y Seguir."
                }
            case .lineal:
                frase += "Esto va por pie lineal, así que con el largo basta: toque Guardar y Seguir."
            case .depende:
                frase += currentWidthFeet == nil
                    ? "Si no está seguro de cómo se cobra esto, mida también el ancho: la oficina puede quitar una medida, pero no inventar la que falta."
                    : "Ya tiene largo y ancho: toque Guardar y Seguir."
            }
        case .measuringWidth:
            frase += pendingStart == nil
                ? "Apunte al inicio del ancho y toque más."
                : "Apunte al final del ancho y toque más."
        case .widthDone:
            frase += "Medida completa. Toque Guardar y Seguir para la próxima, o Terminar."
        }

        // El compañero, si aplica y todavia no lo marco.
        if let c = currentCompanion, !includeCompanion, stage == .lengthDone || stage == .widthDone {
            let pastilla = "+ " + Self.nombreDeBoton(valor: c.value, etiqueta: c.en)
            frase += " Ojo: si también quitó \(c.es.lowercased()), toque más \(pastilla.dropFirst(2)) abajo antes de guardar."
        }
        return frase
    }

    @objc private func helpTapped() {
        ocultarRecordatorio()
        helpOverlay.isHidden = false
        speakHelpIntro()
    }

    @objc private func helpCloseTapped() {
        helpOverlay.isHidden = true
        // Se corta lo que quedaba por decir: cerro la ayuda, ya no la quiere.
        speech.stopSpeaking(at: .immediate)
        // Y en seguida la instruccion de donde se quedo, para no dejarlo
        // parado en silencio sin saber que sigue.
        updateUI()
    }

    // MARK: - Scene / UI setup

    private func setupScene() {
        sceneView.frame = view.bounds
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.automaticallyUpdatesLighting = true
        view.addSubview(sceneView)

        // Drawn in plain 2D screen space (projecting the 3D anchor point
        // onto the screen every frame) rather than as 3D SceneKit geometry -
        // far simpler to get right than orienting a cylinder in 3D, and
        // reads exactly the same to the person holding the phone.
        lineLayer.strokeColor = UIColor.systemYellow.cgColor
        lineLayer.lineWidth = 4
        lineLayer.lineDashPattern = [10, 8]
        lineLayer.lineCap = .round
        lineLayer.fillColor = nil
        view.layer.addSublayer(lineLayer)
    }

    // ============ LA PASTILLA Y SU TRADUCCION ============
    //
    // Su pedido del 12 de septiembre, marcado en rojo sobre una foto de esta
    // pantalla: "todo lo tienes que poner en español, y luego la traducción al
    // inglés... sin casillas, solo las palabras flotantes junto con ese cuadro
    // ... en todas las casillas que todo vaya español, y siempre en inglés,
    // pero en pequeño".
    //
    // Sin casilla detrás, la palabra en inglés va flotando sobre la imagen de
    // la cámara: necesita sombra para leerse igual contra una pared blanca que
    // contra un sótano oscuro.
    //
    // LAS TRES MEDIDAS VIVEN AQUI, JUNTAS, y el alto de la fila se calcula de
    // ellas. Las filas tienen ALTURA FIJA, así que una fila más corta que su
    // pastilla más su traducción corta el texto - y eso es exactamente el error
    // que él ya me marcó en una foto ("la barra de niveles salió encima de la
    // de secciones, ilegible"). Calculado, no se pueden desincronizar.
    static let altoPastilla: CGFloat = 34
    static let altoTraduccion: CGFloat = 11
    static let brechaTraduccion: CGFloat = 1
    static var altoFilaBilingue: CGFloat { altoPastilla + brechaTraduccion + altoTraduccion }

    private var envolturaDePastilla: [UIButton: UIStackView] = [:]
    private var traduccionDePastilla: [UIButton: UILabel] = [:]

    // La pastilla envuelta con su traduccion debajo, lista para meter en una
    // fila. El boton sigue siendo el mismo de siempre: quien le cambiaba el
    // color sigue cambiandoselo igual.
    private func pastillaBilingue(_ b: UIButton, _ traduccion: String) -> UIStackView {
        let t = UILabel()
        t.translatesAutoresizingMaskIntoConstraints = false
        t.text = traduccion
        t.font = .systemFont(ofSize: 9, weight: .semibold)
        t.textColor = .white
        t.textAlignment = .center
        t.numberOfLines = 1
        t.adjustsFontSizeToFitWidth = true
        t.minimumScaleFactor = 0.7
        t.backgroundColor = .clear
        t.layer.shadowColor = UIColor.black.cgColor
        t.layer.shadowOpacity = 0.9
        t.layer.shadowRadius = 2
        t.layer.shadowOffset = .zero
        let col = UIStackView(arrangedSubviews: [b, t])
        col.translatesAutoresizingMaskIntoConstraints = false
        col.axis = .vertical
        col.alignment = .fill
        col.spacing = Self.brechaTraduccion
        NSLayoutConstraint.activate([
            b.heightAnchor.constraint(equalToConstant: Self.altoPastilla),
            t.heightAnchor.constraint(equalToConstant: Self.altoTraduccion)
        ])
        envolturaDePastilla[b] = col
        traduccionDePastilla[b] = t
        return col
    }

    // Esconder o atenuar una pastilla tiene que llevarse su traduccion: si no,
    // la palabra en ingles se queda sola flotando sobre la camara, debajo de un
    // hueco. Por eso nadie le toca `isHidden` ni `alpha` al boton directo.
    private func esconderPastilla(_ b: UIButton?, _ si: Bool) {
        guard let b = b else { return }
        esconderPastilla(b, si)
    }
    private func esconderPastilla(_ b: UIButton, _ si: Bool) {
        (envolturaDePastilla[b] ?? b).isHidden = si
    }
    private func atenuarPastilla(_ b: UIButton, _ a: CGFloat) {
        (envolturaDePastilla[b] ?? b).alpha = a
    }
    private func ponerTraduccion(_ b: UIButton, _ texto: String) {
        traduccionDePastilla[b]?.text = texto
    }
    // La fila de materiales se tira y se rehace en cada cambio de seccion. Sus
    // envolturas se tienen que ir con ella o las dos tablas crecen sin parar.
    private func olvidarPastillasMuertas() {
        envolturaDePastilla = envolturaDePastilla.filter { $0.value.superview != nil }
        let vivas = Set(envolturaDePastilla.keys)
        traduccionDePastilla = traduccionDePastilla.filter { vivas.contains($0.key) }
    }

    private func styledOverlayButton(_ button: UIButton, title: String, bg: UIColor, fontSize: CGFloat = 17) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: fontSize, weight: .bold)
        button.titleLabel?.numberOfLines = 1
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.75
        button.backgroundColor = bg
        button.layer.cornerRadius = 10
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        view.addSubview(button)
    }

    private func setupUI() {
        crosshair.translatesAutoresizingMaskIntoConstraints = false
        crosshair.backgroundColor = .clear
        crosshair.layer.borderColor = UIColor.white.cgColor
        crosshair.layer.borderWidth = 3
        crosshair.layer.cornerRadius = 8
        view.addSubview(crosshair)

        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.textColor = .white
        // 17, no 19: ahora va a media pantalla, cerca del ojo, entre la
        // lectura en vivo y la fila de materiales - ahi no sobra alto.
        instructionLabel.font = .systemFont(ofSize: 17, weight: .bold)
        instructionLabel.textAlignment = .center
        // Una casilla de verdad: borde fino, no solo un fondo oscuro.
        instructionLabel.layer.borderWidth = 1
        instructionLabel.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        instructionLabel.alCambiar = { [weak self] in self?.casillaCambio() }
        // Nace invisible: sin texto no hay casilla. Si no, se veia un marco
        // vacio a media pantalla hasta que llegaba la primera instruccion.
        instructionLabel.alpha = 0
        // Era 2 lineas a 19pt en una franja angosta: las instrucciones mas
        // largas se cortaban con puntos suspensivos en TODOS los iPhone, y
        // justo ahora que la voz ya no las lee completas, la pantalla es lo
        // unico que queda. Se dejan crecer y, si aun asi no caben, encogen.
        instructionLabel.numberOfLines = 0
        instructionLabel.adjustsFontSizeToFitWidth = true
        instructionLabel.minimumScaleFactor = 0.7
        instructionLabel.backgroundColor = Self.colorPastilla
        instructionLabel.layer.cornerRadius = 12
        instructionLabel.clipsToBounds = true
        // Si el texto no cabe en el hueco, que empuje hacia abajo un poco
        // antes que cortarse: una instruccion a medias es peor que una casilla
        // que roza la fila de materiales unos segundos.
        instructionLabel.setContentCompressionResistancePriority(UILayoutPriority(760), for: .vertical)
        view.addSubview(instructionLabel)

        liveLabel.translatesAutoresizingMaskIntoConstraints = false
        liveLabel.textColor = .systemGreen
        liveLabel.font = .monospacedDigitSystemFont(ofSize: 30, weight: .heavy)
        liveLabel.textAlignment = .center
        liveLabel.backgroundColor = Self.colorPastilla
        liveLabel.layer.cornerRadius = 10
        liveLabel.clipsToBounds = true
        liveLabel.isHidden = true
        view.addSubview(liveLabel)

        styledOverlayButton(finishButton, title: "Terminar", bg: UIColor.systemGreen.withAlphaComponent(0.95))
        finishButton.addTarget(self, action: #selector(finishTapped), for: .touchUpInside)

        styledOverlayButton(undoButton, title: "Deshacer", bg: Self.colorPastilla)
        undoButton.addTarget(self, action: #selector(undoTapped), for: .touchUpInside)

        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.setTitle("+", for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: 40, weight: .bold)
        addButton.setTitleColor(.black, for: .normal)
        addButton.backgroundColor = .white
        addButton.layer.cornerRadius = 42
        addButton.layer.shadowColor = UIColor.black.cgColor
        addButton.layer.shadowOpacity = 0.4
        addButton.layer.shadowRadius = 6
        addButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        view.addSubview(addButton)

        styledOverlayButton(addWidthButton, title: "Medir Ancho", bg: UIColor.systemBlue.withAlphaComponent(0.9), fontSize: 16)
        addWidthButton.addTarget(self, action: #selector(addWidthTapped), for: .touchUpInside)

        // MAS CHICO Y A LA IZQUIERDA DEL +. Su foto del 13 de septiembre: salia
        // grande a la derecha, encima de "Deshacer" y rozando el +. Dos
        // renglones cortos en vez de uno largo.
        styledOverlayButton(saveContinueButton, title: "Guardar\ny seguir", bg: UIColor.systemBlue.withAlphaComponent(0.9), fontSize: 15)
        saveContinueButton.titleLabel?.numberOfLines = 2
        saveContinueButton.titleLabel?.textAlignment = .center
        saveContinueButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        saveContinueButton.addTarget(self, action: #selector(saveContinueTapped), for: .touchUpInside)

        // En el mismo lugar que "Guardar y seguir": nunca se ven a la vez. A la
        // derecha se encimaba con "Deshacer".
        styledOverlayButton(finishPathButton, title: "Terminar\nrecorrido", bg: UIColor.systemGreen.withAlphaComponent(0.95), fontSize: 15)
        finishPathButton.titleLabel?.numberOfLines = 2
        finishPathButton.titleLabel?.textAlignment = .center
        finishPathButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        finishPathButton.addTarget(self, action: #selector(finishPathTapped), for: .touchUpInside)

        recordatorioLabel.translatesAutoresizingMaskIntoConstraints = false
        recordatorioLabel.textColor = .white
        recordatorioLabel.font = .systemFont(ofSize: 17, weight: .bold)
        recordatorioLabel.textAlignment = .center
        recordatorioLabel.numberOfLines = 0
        recordatorioLabel.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        recordatorioLabel.layer.cornerRadius = 14
        recordatorioLabel.layer.borderWidth = 2
        recordatorioLabel.layer.borderColor = UIColor.systemYellow.withAlphaComponent(0.85).cgColor
        recordatorioLabel.clipsToBounds = true
        recordatorioLabel.relleno = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        recordatorioLabel.alpha = 0
        // Tocarlo lo quita. Mientras se ve NO deja pasar el toque a lo de
        // debajo (Terminar, la lista de cuartos); ya desvanecido no estorba,
        // porque una vista transparente no recibe toques.
        recordatorioLabel.isUserInteractionEnabled = true
        recordatorioLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(recordatorioTocado)))
        view.addSubview(recordatorioLabel)

        torchButton.translatesAutoresizingMaskIntoConstraints = false
        torchButton.backgroundColor = Self.colorPastilla
        torchButton.layer.cornerRadius = 22
        torchButton.tintColor = .white
        torchButton.setImage(UIImage(systemName: "bolt.slash.fill"), for: .normal)
        torchButton.addTarget(self, action: #selector(torchTapped), for: .touchUpInside)
        torchButton.isHidden = !(AVCaptureDevice.default(for: .video)?.hasTorch ?? false)
        view.addSubview(torchButton)

        helpButton.translatesAutoresizingMaskIntoConstraints = false
        helpButton.backgroundColor = Self.colorPastilla
        helpButton.layer.cornerRadius = 22
        helpButton.tintColor = .white
        helpButton.setImage(UIImage(systemName: "questionmark.circle.fill"), for: .normal)
        helpButton.addTarget(self, action: #selector(helpTapped), for: .touchUpInside)
        view.addSubview(helpButton)

        styledOverlayButton(listaButton, title: "📋  Escoger de la lista", bg: Self.colorPastilla, fontSize: 17)
        listaButton.addTarget(self, action: #selector(listaTapped), for: .touchUpInside)
        listaButton.isHidden = true
        view.addSubview(listaButton)

        micDot.translatesAutoresizingMaskIntoConstraints = false
        micDot.font = .systemFont(ofSize: 15)
        micDot.textAlignment = .center
        micDot.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        micDot.layer.cornerRadius = 13
        micDot.clipsToBounds = true
        micDot.text = "🎤"
        micDot.isHidden = true          // la bolita lo reemplaza
        view.addSubview(micDot)

        orbita.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(orbita)

        styledOverlayButton(tiraEstado, title: "", bg: Self.colorPastilla, fontSize: 15)
        tiraEstado.addTarget(self, action: #selector(tiraEstadoTapped), for: .touchUpInside)
        tiraEstado.isHidden = true
        _ = tiraEstado          // idem

        tiraSecciones.translatesAutoresizingMaskIntoConstraints = false
        tiraSecciones.showsHorizontalScrollIndicator = false
        tiraSecciones.isHidden = true
        filaSecciones.translatesAutoresizingMaskIntoConstraints = false
        filaSecciones.axis = .horizontal
        filaSecciones.distribution = .fill
        filaSecciones.spacing = 6
        tiraSecciones.addSubview(filaSecciones)
        // "COCINA" YA NO ES PASTILLA. Su pedido del 13 de septiembre: "cambia
        // cocina por materiales, que tenga que aparecer en todo... si nos vamos
        // a kitchen, ya sabemos que nos va a tirar todo lo relacionado a
        // cocina". Los artículos de cocina salen solos dentro de PARED cuando
        // el cuarto es la cocina (ver listaDeMateriales), y MATERIALES es lo
        // que se gastó en ese cuarto: nailo, 6 mil de contención, protección
        // de piso.
        //
        // Franja que corre (distribution .fill, no .fillEqually), no cuatro
        // columnas del mismo ancho: cada pastilla mide lo que necesita SU
        // palabra ("Materiales" ya no se corta) y la fila entera se puede
        // correr con el dedo si algun dia se agrega una quinta. La palabra
        // de la obra va grande, en español, en el boton mismo; la traduccion
        // al ingles va chica, debajo, con pastillaBilingue - igual que ya
        // llevaban Piso/Pared/Techo.
        // COCINA Y BAÑO, PASTILLAS PROPIAS (27 sep 2026). Su pedido: "prefiero
        // tener la opcion en la camara de baño y cocina... como esta el piso y
        // pared y techo". Revierte a proposito lo del 13 de septiembre (que los
        // articulos de cocina salieran dentro de Pared cuando el cuarto era la
        // cocina): eso dependia del NOMBRE del cuarto, asi que en un "Basement"
        // con una regadera no habia forma de llegar a esas piezas. La fila
        // corre con el dedo, asi que seis caben.
        for (clave, titulo, ingles) in [("floor", "Piso", "Floor"), ("wall", "Pared", "Wall"),
                                        ("ceiling", "Techo", "Ceiling"),
                                        ("kitchen", "Cocina", "Kitchen"),
                                        ("bathroom", "Baño", "Bathroom"),
                                        ("materiales", "Materiales", "Materials")] {
            let b = UIButton(type: .system)
            styledOverlayButton(b, title: titulo, bg: Self.colorPastilla, fontSize: 14)
            b.accessibilityIdentifier = clave
            b.addTarget(self, action: #selector(seccionTapped(_:)), for: .touchUpInside)
            botonesSeccion[clave] = b
            filaSecciones.addArrangedSubview(pastillaBilingue(b, ingles))
        }
        _ = tiraSecciones       // idem

        tiraMateriales.translatesAutoresizingMaskIntoConstraints = false
        tiraMateriales.showsHorizontalScrollIndicator = false
        tiraMateriales.isHidden = true
        filaMateriales.translatesAutoresizingMaskIntoConstraints = false
        filaMateriales.axis = .horizontal
        filaMateriales.spacing = 6
        tiraMateriales.addSubview(filaMateriales)
        view.addSubview(tiraMateriales)

        // SE DESLIZA, y cada boton mide lo que dice.
        //
        // Estaban repartidos en partes iguales, y en un telefono de 402 puntos
        // eso deja 72 por boton: "Insulación" salia "Ins...ción" y "Otro
        // cuarto" salia "Otr...arto". Un boton que no se puede leer es un boton
        // que no se toca.
        tiraAccionesScroll.translatesAutoresizingMaskIntoConstraints = false
        tiraAccionesScroll.showsHorizontalScrollIndicator = false
        tiraAcciones.translatesAutoresizingMaskIntoConstraints = false
        tiraAcciones.axis = .horizontal
        tiraAcciones.distribution = .fill
        tiraAcciones.spacing = 6
        for (clave, titulo, ingles) in [("largo", "Largo", "Length"), ("ancho", "Ancho", "Width"),
                                        // Para lo que se cuenta (27 sep 2026): un inodoro no tiene
                                        // esquinas. Estas dos solo se prenden con un material por pieza.
                                        ("menos", "\u{2212}", "Less"), ("mas", "+ 1", "More"),
                                        ("comp", "+ Insulación", "Insulation"),
                                        ("guardar", "Guardar", "Save"),
                                        ("otro", "Otro cuarto", "Another room"),
                                        ("anterior", "Cuarto anterior", "Previous room"),
                                        ("cancelar", "Cancelar", "Cancel")] {
            let b = UIButton(type: .system)
            styledOverlayButton(b, title: titulo, bg: Self.colorPastilla, fontSize: 13)
            b.accessibilityIdentifier = clave
            b.addTarget(self, action: #selector(accionTapped(_:)), for: .touchUpInside)
            botonesAccion[clave] = b
            tiraAcciones.addArrangedSubview(pastillaBilingue(b, ingles))
        }
        tiraAccionesScroll.addSubview(tiraAcciones)
        view.addSubview(tiraAccionesScroll)

        tiraNivelesScroll.translatesAutoresizingMaskIntoConstraints = false
        tiraNivelesScroll.showsHorizontalScrollIndicator = false
        tiraNivelesScroll.isHidden = true
        tiraNiveles.translatesAutoresizingMaskIntoConstraints = false
        tiraNiveles.axis = .horizontal
        tiraNiveles.distribution = .fill
        tiraNiveles.spacing = 6
        tiraNivelesScroll.addSubview(tiraNiveles)
        _ = tiraNivelesScroll   // se mete en la columna, no directo a la vista

        tiraCuartosScroll.translatesAutoresizingMaskIntoConstraints = false
        tiraCuartosScroll.showsVerticalScrollIndicator = false
        tiraCuartosScroll.isHidden = true
        tiraCuartos.translatesAutoresizingMaskIntoConstraints = false
        tiraCuartos.axis = .vertical
        tiraCuartos.spacing = 4
        tiraCuartos.alignment = .trailing
        tiraCuartosScroll.addSubview(tiraCuartos)
        view.addSubview(tiraCuartosScroll)

        avanceLabel.translatesAutoresizingMaskIntoConstraints = false
        avanceLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        avanceLabel.textColor = .white
        avanceLabel.textAlignment = .center
        // Tres renglones: QUE se esta midiendo (cuarto, seccion, material),
        // la medida en curso, y lo que ya lleva. Cada total en su renglon: en
        // uno solo se cortaba la cola (los pies lineales), igual que le paso al
        // conteo de antes.
        avanceLabel.numberOfLines = 3
        avanceLabel.adjustsFontSizeToFitWidth = true
        avanceLabel.minimumScaleFactor = 0.75
        avanceLabel.relleno = UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
        avanceLabel.backgroundColor = Self.colorPastilla
        avanceLabel.layer.cornerRadius = 10
        avanceLabel.clipsToBounds = true
        avanceLabel.isHidden = true

        // LA COLUMNA, en el orden en que se lee: donde estoy, el nivel, la
        // seccion, y que llevo hecho. El stack se encarga de repartir el
        // espacio y de SACAR lo escondido.
        columnaArriba.translatesAutoresizingMaskIntoConstraints = false
        columnaArriba.axis = .vertical
        columnaArriba.spacing = 6
        columnaArriba.alignment = .fill
        [tiraEstado, tiraNivelesScroll, tiraSecciones, avanceLabel].forEach {
            columnaArriba.addArrangedSubview($0)
        }
        view.addSubview(columnaArriba)

        assistantButton.translatesAutoresizingMaskIntoConstraints = false
        assistantButton.backgroundColor = Self.colorEscogido
        assistantButton.layer.cornerRadius = 22
        assistantButton.tintColor = .white
        assistantButton.setImage(UIImage(systemName: "bubble.left.and.bubble.right.fill"), for: .normal)
        assistantButton.accessibilityLabel = "Asistente"
        assistantButton.addTarget(self, action: #selector(assistantTapped), for: .touchUpInside)
        view.addSubview(assistantButton)

        muteButton.translatesAutoresizingMaskIntoConstraints = false
        muteButton.layer.cornerRadius = 22
        muteButton.tintColor = .white
        muteButton.addTarget(self, action: #selector(muteTapped), for: .touchUpInside)
        view.addSubview(muteButton)
        // El didSet no corre para el valor inicial, asi que el boton se pinta
        // aqui a mano con lo que quedo guardado la ultima vez.
        asistenteHabla = UserDefaults.standard.object(forKey: Self.asistenteKey) as? Bool ?? true
        muteButton.setImage(UIImage(systemName: asistenteHabla ? "speaker.wave.2.fill" : "speaker.slash.fill"), for: .normal)
        muteButton.backgroundColor = asistenteHabla
            ? Self.colorPastilla
            : UIColor.systemRed.withAlphaComponent(0.75)

        // Las 4 anclas de fondo de esta pantalla, con la reserva de siempre
        // (la fraccion de verdad la pone viewDidLayoutSubviews en cuanto la
        // vista tiene su tamaño real).
        let margenAddButton = addButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -140)
        // Medir Ancho, Guardar y seguir y Terminar recorrido ya no tienen su
        // propio margen: van en el renglon del +, asi que bajan y suben con el.
        margenControlesConstraints = [margenAddButton]

        // La casilla se apoya en la fila de materiales, pero cede antes que
        // cortar su texto (resistencia 760 > 740), y crece a lo ancho de la
        // pantalla sin pasar de 380 en los telefonos grandes.
        let casillaSobreMateriales = instructionLabel.bottomAnchor.constraint(equalTo: tiraMateriales.topAnchor, constant: -8)
        casillaSobreMateriales.priority = UILayoutPriority(740)
        let casillaAnchoIdeal = instructionLabel.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -40)
        casillaAnchoIdeal.priority = UILayoutPriority(750)

        NSLayoutConstraint.activate([
            crosshair.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            crosshair.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            crosshair.widthAnchor.constraint(equalToConstant: 16),
            crosshair.heightAnchor.constraint(equalToConstant: 16),

            // ============ LA CASILLA, A MEDIA PANTALLA ============
            //
            // Su foto del 13 de septiembre, con una flecha: la instruccion
            // estaba arriba, entre "Cancelar" y la luz, y empujaba hacia abajo
            // todo lo demas (el cuarto, las secciones). Ahora va DEBAJO de la
            // lectura en vivo y ENCIMA de la fila de materiales, en su propia
            // casilla - lejos de los botones de las orillas, asi que ya no
            // hay que dejarle 132 pt a "Cancelar" ni 76 a la luz.
            //
            // Nunca tapa la cruz ni la lectura en vivo (>=). Si el texto es
            // largo, prefiere rozar la fila de materiales a cortarse.
            casillaSobreMateriales,
            instructionLabel.topAnchor.constraint(greaterThanOrEqualTo: liveLabel.bottomAnchor, constant: 6),
            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
            casillaAnchoIdeal,

            liveLabel.topAnchor.constraint(equalTo: crosshair.bottomAnchor, constant: 24),
            liveLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            liveLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            liveLabel.heightAnchor.constraint(equalToConstant: 52),

            // Sin el Cancelar de arriba, la columna de botones redondos arranca
            // en el primer renglon.
            helpButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            helpButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            helpButton.widthAnchor.constraint(equalToConstant: 44),
            helpButton.heightAnchor.constraint(equalToConstant: 44),

            micDot.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            micDot.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            micDot.widthAnchor.constraint(equalToConstant: 26),
            micDot.heightAnchor.constraint(equalToConstant: 26),

            // ABAJO DE LA BOCINA, en la columna de la izquierda.
            //
            // Estaba arriba a la derecha, EXACTAMENTE encima del boton de la
            // luz (los dos en trailing, los dos a ~12 del borde): se tapaban
            // uno al otro. Aqui va con los demas controles de voz - ayuda,
            // asistente, bocina, bolita - todos en la misma columna, que es
            // donde el ojo ya los busca.
            orbita.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 7),
            orbita.topAnchor.constraint(equalTo: muteButton.bottomAnchor, constant: 6),
            orbita.widthAnchor.constraint(equalToConstant: 54),
            orbita.heightAnchor.constraint(equalToConstant: 54),

            // ============ UNA COLUMNA, NO CUATRO VISTAS SUELTAS ============
            //
            // Su foto del 12 de septiembre: la barra de niveles salio ENCIMA de
            // la de secciones, ilegible. Y la causa fue exactamente lo que se
            // ve: las dos estaban ancladas AL MISMO punto
            // (tiraEstado.bottomAnchor + 6). Agregue la de niveles y no
            // re-anclé la de secciones debajo.
            //
            // No se arregla moviendo un ancla: se arregla quitando la manera de
            // equivocarse. Estas cuatro cosas son UNA COLUMNA, y una columna es
            // un UIStackView - que ademas SACA DEL LAYOUT lo que esta
            // escondido, asi que cuando la barra de niveles no aplica (en "un
            // nivel completo" y "un cuarto") no deja un hueco ni se encima con
            // nada. Con anclas a mano cada vista nueva es otra oportunidad de
            // que dos caigan en el mismo sitio.
            // Arriba del todo: ya no hay Cancelar ni conteo encima (el conteo
            // vive ahora en la barrita de avance, que dice cuanto lleva).
            columnaArriba.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            columnaArriba.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 70),
            // A la derecha ya no hay nada a esta altura: la luz se fue a la
            // columna de la izquierda (13 de septiembre, "por el flash esta
            // ocupando su espacio"). La columna crece hasta la orilla y
            // "Materiales" cabe entera en mas telefonos.
            columnaArriba.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            tiraSecciones.heightAnchor.constraint(equalToConstant: Self.altoFilaBilingue),
            filaSecciones.leadingAnchor.constraint(equalTo: tiraSecciones.contentLayoutGuide.leadingAnchor),
            filaSecciones.trailingAnchor.constraint(equalTo: tiraSecciones.contentLayoutGuide.trailingAnchor),
            filaSecciones.topAnchor.constraint(equalTo: tiraSecciones.contentLayoutGuide.topAnchor),
            filaSecciones.bottomAnchor.constraint(equalTo: tiraSecciones.contentLayoutGuide.bottomAnchor),
            filaSecciones.heightAnchor.constraint(equalTo: tiraSecciones.frameLayoutGuide.heightAnchor),

            // Justo encima del boton +, que es donde ya trae el pulgar.
            tiraMateriales.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            tiraMateriales.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            tiraMateriales.bottomAnchor.constraint(equalTo: tiraAccionesScroll.topAnchor, constant: -6),
            tiraMateriales.heightAnchor.constraint(equalToConstant: Self.altoFilaBilingue),
            filaMateriales.leadingAnchor.constraint(equalTo: tiraMateriales.contentLayoutGuide.leadingAnchor),
            filaMateriales.trailingAnchor.constraint(equalTo: tiraMateriales.contentLayoutGuide.trailingAnchor),
            filaMateriales.topAnchor.constraint(equalTo: tiraMateriales.contentLayoutGuide.topAnchor),
            filaMateriales.bottomAnchor.constraint(equalTo: tiraMateriales.contentLayoutGuide.bottomAnchor),
            filaMateriales.heightAnchor.constraint(equalTo: tiraMateriales.frameLayoutGuide.heightAnchor),

            tiraAccionesScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            tiraAccionesScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            tiraAccionesScroll.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -6),
            tiraAccionesScroll.heightAnchor.constraint(equalToConstant: Self.altoFilaBilingue),
            tiraAcciones.leadingAnchor.constraint(equalTo: tiraAccionesScroll.contentLayoutGuide.leadingAnchor),
            tiraAcciones.trailingAnchor.constraint(equalTo: tiraAccionesScroll.contentLayoutGuide.trailingAnchor),
            tiraAcciones.topAnchor.constraint(equalTo: tiraAccionesScroll.contentLayoutGuide.topAnchor),
            tiraAcciones.bottomAnchor.constraint(equalTo: tiraAccionesScroll.contentLayoutGuide.bottomAnchor),
            tiraAcciones.heightAnchor.constraint(equalTo: tiraAccionesScroll.frameLayoutGuide.heightAnchor),

            avanceLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 26),

            tiraNivelesScroll.heightAnchor.constraint(equalToConstant: Self.altoFilaBilingue),
            tiraNiveles.leadingAnchor.constraint(equalTo: tiraNivelesScroll.contentLayoutGuide.leadingAnchor),
            tiraNiveles.trailingAnchor.constraint(equalTo: tiraNivelesScroll.contentLayoutGuide.trailingAnchor),
            tiraNiveles.topAnchor.constraint(equalTo: tiraNivelesScroll.contentLayoutGuide.topAnchor),
            tiraNiveles.bottomAnchor.constraint(equalTo: tiraNivelesScroll.contentLayoutGuide.bottomAnchor),
            tiraNiveles.heightAnchor.constraint(equalTo: tiraNivelesScroll.frameLayoutGuide.heightAnchor),

            // Al lado derecho, entre el aviso de avance y los materiales.
            tiraCuartosScroll.topAnchor.constraint(equalTo: finishButton.bottomAnchor, constant: 8),
            tiraCuartosScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            tiraCuartosScroll.widthAnchor.constraint(lessThanOrEqualToConstant: 170),
            // Termina ANTES de la casilla, que ahora vive entre la cruz y la
            // fila de materiales: si llegaba hasta los materiales, la lista de
            // cuartos le pasaba por encima del lado derecho.
            tiraCuartosScroll.bottomAnchor.constraint(lessThanOrEqualTo: instructionLabel.topAnchor, constant: -8),
            tiraCuartos.trailingAnchor.constraint(equalTo: tiraCuartosScroll.contentLayoutGuide.trailingAnchor),
            tiraCuartos.leadingAnchor.constraint(equalTo: tiraCuartosScroll.contentLayoutGuide.leadingAnchor),
            tiraCuartos.topAnchor.constraint(equalTo: tiraCuartosScroll.contentLayoutGuide.topAnchor),
            tiraCuartos.bottomAnchor.constraint(equalTo: tiraCuartosScroll.contentLayoutGuide.bottomAnchor),
            tiraCuartos.widthAnchor.constraint(equalTo: tiraCuartosScroll.frameLayoutGuide.widthAnchor),

            listaButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            listaButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),

            assistantButton.topAnchor.constraint(equalTo: helpButton.bottomAnchor, constant: 10),
            assistantButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            assistantButton.widthAnchor.constraint(equalToConstant: 44),
            assistantButton.heightAnchor.constraint(equalToConstant: 44),

            muteButton.topAnchor.constraint(equalTo: assistantButton.bottomAnchor, constant: 10),
            muteButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            muteButton.widthAnchor.constraint(equalToConstant: 44),
            muteButton.heightAnchor.constraint(equalToConstant: 44),

            // LA LUZ, A LA COLUMNA DE LA IZQUIERDA, debajo de la bocina y la
            // bolita. Su foto del 13 de septiembre, marcada en verde: arriba a
            // la derecha le quitaba espacio a la fila de arriba. Aqui va con
            // los demas botones redondos, donde el ojo ya los busca.
            torchButton.topAnchor.constraint(equalTo: orbita.bottomAnchor, constant: 8),
            torchButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            torchButton.widthAnchor.constraint(equalToConstant: 44),
            torchButton.heightAnchor.constraint(equalToConstant: 44),

            // "Terminar" va DEBAJO de la columna, a la derecha, encima de la
            // lista de cuartos guardados. En la esquina de arriba quedaba
            // encima de la columna, que ahora arranca en el primer renglon y
            // llega a la orilla derecha. Aparece justo cuando hay medidas, que
            // es cuando tambien aparece esa lista: van juntos.
            finishButton.topAnchor.constraint(equalTo: columnaArriba.bottomAnchor, constant: 8),
            finishButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            undoButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            undoButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            addButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            margenAddButton,
            addButton.widthAnchor.constraint(equalToConstant: 84),
            addButton.heightAnchor.constraint(equalToConstant: 84),

            // EL RENGLON DEL +: a la izquierda "Guardar y seguir" (o "Terminar
            // recorrido"), al centro el + (o "Medir Ancho", que sale cuando el
            // + esta escondido), a la derecha "Deshacer".
            addWidthButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            addWidthButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            addWidthButton.widthAnchor.constraint(lessThanOrEqualToConstant: 170),

            saveContinueButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            saveContinueButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            saveContinueButton.trailingAnchor.constraint(lessThanOrEqualTo: addButton.leadingAnchor, constant: -8),

            finishPathButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            finishPathButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            finishPathButton.trailingAnchor.constraint(lessThanOrEqualTo: addButton.leadingAnchor, constant: -8),

            // El recordatorio, enfrente, ENCIMA de la cruz: no tapa a donde se
            // apunta ni la lectura en vivo.
            recordatorioLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordatorioLabel.bottomAnchor.constraint(equalTo: crosshair.topAnchor, constant: -28),
            recordatorioLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48)
        ])
    }

    // A full-screen dimmed overlay with a card holding a native scrolling
    // wheel - the exact same interaction as any <select> elsewhere in the
    // app - so picking "what am I measuring" feels consistent, not bolted on.
    private func setupMaterialPicker() {
        materialOverlay.translatesAutoresizingMaskIntoConstraints = false
        materialOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        materialOverlay.isHidden = true
        view.addSubview(materialOverlay)

        materialCard.translatesAutoresizingMaskIntoConstraints = false
        materialCard.backgroundColor = UIColor(white: 0.12, alpha: 1)
        materialCard.layer.cornerRadius = 14
        materialOverlay.addSubview(materialCard)

        materialTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        materialTitleLabel.text = "¿Qué está midiendo?"
        materialTitleLabel.textColor = .white
        materialTitleLabel.font = .systemFont(ofSize: 19, weight: .bold)
        materialTitleLabel.textAlignment = .center
        materialTitleLabel.numberOfLines = 2
        materialCard.addSubview(materialTitleLabel)

        materialPickerView.translatesAutoresizingMaskIntoConstraints = false
        materialPickerView.dataSource = self
        materialPickerView.delegate = self
        materialCard.addSubview(materialPickerView)

        materialConfirmButton.translatesAutoresizingMaskIntoConstraints = false
        materialConfirmButton.setTitle("Confirmar", for: .normal)
        materialConfirmButton.setTitleColor(.white, for: .normal)
        materialConfirmButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        materialConfirmButton.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.95)
        materialConfirmButton.layer.cornerRadius = 10
        materialConfirmButton.contentEdgeInsets = UIEdgeInsets(top: 13, left: 16, bottom: 13, right: 16)
        materialConfirmButton.addTarget(self, action: #selector(materialConfirmTapped), for: .touchUpInside)
        materialCard.addSubview(materialConfirmButton)

        NSLayoutConstraint.activate([
            materialOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            materialOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            materialOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            materialOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            materialCard.leadingAnchor.constraint(equalTo: materialOverlay.leadingAnchor, constant: 24),
            materialCard.trailingAnchor.constraint(equalTo: materialOverlay.trailingAnchor, constant: -24),
            materialCard.centerYAnchor.constraint(equalTo: materialOverlay.centerYAnchor),

            materialTitleLabel.topAnchor.constraint(equalTo: materialCard.topAnchor, constant: 20),
            materialTitleLabel.leadingAnchor.constraint(equalTo: materialCard.leadingAnchor, constant: 16),
            materialTitleLabel.trailingAnchor.constraint(equalTo: materialCard.trailingAnchor, constant: -16),

            materialPickerView.topAnchor.constraint(equalTo: materialTitleLabel.bottomAnchor, constant: 4),
            materialPickerView.leadingAnchor.constraint(equalTo: materialCard.leadingAnchor),
            materialPickerView.trailingAnchor.constraint(equalTo: materialCard.trailingAnchor),
            materialPickerView.heightAnchor.constraint(equalToConstant: 160),

            materialConfirmButton.topAnchor.constraint(equalTo: materialPickerView.bottomAnchor, constant: 8),
            materialConfirmButton.leadingAnchor.constraint(equalTo: materialCard.leadingAnchor, constant: 16),
            materialConfirmButton.trailingAnchor.constraint(equalTo: materialCard.trailingAnchor, constant: -16),
            materialConfirmButton.bottomAnchor.constraint(equalTo: materialCard.bottomAnchor, constant: -20)
        ])
    }

    // A step-by-step reference for crew who haven't used this before -
    // where to stand, that it's corner to corner, when to tap +. Purely
    // opt-in from the "?" button; it never shows on its own.
    private func setupHelpOverlay() {
        helpOverlay.translatesAutoresizingMaskIntoConstraints = false
        helpOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        helpOverlay.isHidden = true
        view.addSubview(helpOverlay)

        let helpCard = UIView()
        helpCard.translatesAutoresizingMaskIntoConstraints = false
        helpCard.backgroundColor = UIColor(white: 0.12, alpha: 1)
        helpCard.layer.cornerRadius = 14
        helpOverlay.addSubview(helpCard)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Cómo Medir"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 21, weight: .bold)
        titleLabel.textAlignment = .center
        helpCard.addSubview(titleLabel)

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        helpCard.addSubview(scrollView)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        scrollView.addSubview(stack)

        let steps: [(String, String)] = [
            ("mappin.and.ellipse", "Vaya a una esquina de lo que va a medir y apunte la cámara ahí."),
            ("plus.circle.fill", "Toque + para marcar el INICIO."),
            ("figure.walk", "Camine hacia la siguiente esquina, apuntando la cámara todo el tiempo."),
            ("checkmark.circle.fill", "Toque + otra vez para marcar esa esquina. El total aparece solo."),
            ("arrow.triangle.turn.up.right.circle.fill", "¿La medida da la vuelta a otra esquina? Siga caminando y tocando + en cada esquina - no hay límite."),
            ("flag.checkered", "Cuando termine de dar la vuelta, toque \"Terminar Recorrido\"."),
            ("arrow.left.and.right", "¿También necesita el ancho? Toque \"Medir Ancho\" y repita los mismos pasos."),
            ("flag.checkered", "Toque \"Guardar y Seguir\" para la próxima medida, o \"Terminar\" cuando ya termine.")
        ]
        for (index, step) in steps.enumerated() {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 12
            row.alignment = .top

            let numberLabel = UILabel()
            numberLabel.translatesAutoresizingMaskIntoConstraints = false
            numberLabel.text = "\(index + 1)"
            numberLabel.textColor = .black
            numberLabel.font = .systemFont(ofSize: 14, weight: .bold)
            numberLabel.textAlignment = .center
            numberLabel.backgroundColor = .white
            numberLabel.layer.cornerRadius = 12
            numberLabel.clipsToBounds = true
            numberLabel.widthAnchor.constraint(equalToConstant: 24).isActive = true
            numberLabel.heightAnchor.constraint(equalToConstant: 24).isActive = true

            let iconView = UIImageView(image: UIImage(systemName: step.0))
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.tintColor = .systemYellow
            iconView.contentMode = .scaleAspectFit
            iconView.widthAnchor.constraint(equalToConstant: 24).isActive = true
            iconView.heightAnchor.constraint(equalToConstant: 24).isActive = true

            let textLabel = UILabel()
            textLabel.text = step.1
            textLabel.textColor = .white
            textLabel.font = .systemFont(ofSize: 15, weight: .medium)
            textLabel.numberOfLines = 0

            row.addArrangedSubview(numberLabel)
            row.addArrangedSubview(iconView)
            row.addArrangedSubview(textLabel)
            stack.addArrangedSubview(row)
        }

        // ---- LAS ORDENES QUE PUEDE DECIR ----
        let ordTitulo = UILabel()
        ordTitulo.text = "Puede hablarle en vez de tocar"
        ordTitulo.textColor = .white
        ordTitulo.font = .systemFont(ofSize: 17, weight: .bold)
        ordTitulo.numberOfLines = 0
        stack.addArrangedSubview(ordTitulo)

        // Que sepa que YA NO tiene que hablarle como a un robot. Antes toda
        // frase de mas de cuatro palabras se tiraba sin leerla, y la gente
        // aprendia a decir palabras sueltas sin saber por que.
        let ordNota = UILabel()
        ordNota.text = "Háblele normal: \"ok, ya terminamos con este cuarto\" se entiende igual que \"otro cuarto\"."
        ordNota.textColor = UIColor(white: 0.7, alpha: 1)
        ordNota.font = .italicSystemFont(ofSize: 13)
        ordNota.numberOfLines = 0
        stack.addArrangedSubview(ordNota)

        let ordenes: [(String, String)] = [
            ("\"Marca\" · \"Aquí\"", "pone una esquina, igual que el botón +"),
            ("\"Laminado\", \"tablaroca\", \"béisbol\"…", "escoge el material sin buscarlo en la lista"),
            ("\"Sí\" · \"No\"", "contesta lo que el asistente le pregunte"),
            ("\"Terminar recorrido\"", "cierra el recorrido del largo"),
            ("\"Ancho\"", "pasa a medir el ancho"),
            ("\"Guardar\"", "guarda esta medida y sigue con la próxima"),
            ("\"Terminar\"", "le lee lo que va a mandar; dígalo otra vez para mandarlo"),
            ("\"Deshacer\"", "quita lo último"),
            ("\"¿Cómo voy?\"", "le dice dónde va y qué sigue"),
            ("\"Ayuda\"", "abre esta pantalla"),
            ("\"Silencio\"", "apaga la voz"),
            // ---- LO NUEVO. Si no se descubre, es como si no existiera: por
            //      eso va aqui y no solo en el codigo.
            ("\"Tres pies\" · \"Doce por diez\"", "DIGA la medida en vez de caminarla — para lo que ya trae sabido, como un pasillo de 3 pies"),
            ("\"Otra igual\"", "repite el material y el ancho de la anterior — para cinco closets del mismo tamaño"),
            ("\"Espérate\"", "lo deja callado mientras habla con el cliente; \"ya estoy\" lo despierta"),
            ("\"¿Qué te puedo decir?\"", "le dice en voz alta lo que puede pedirle AHORITA"),
            ("\"Añade insulación\"", "prende la pastilla + del compañero, abajo, sin buscarla"),
            ("\"Otro cuarto\" · \"Otra sección\"", "solo en un recorrido: pasa al siguiente sin salir de la cámara"),
            ("\"¿Qué ves?\"", "la cámara mira y le dice qué cree que es — usted confirma o corrige"),
            ("\"¿Qué has aprendido?\"", "le cuenta lo que le fue agarrando: sus anchos de siempre, sus palabras"),
            ("\"Olvida lo que aprendiste\"", "si agarró una maña equivocada, empieza de cero")
        ]
        for (orden, que) in ordenes {
            let fila = UILabel()
            let t = NSMutableAttributedString(
                string: orden + "  ",
                attributes: [.foregroundColor: Self.colorEscogido,
                             .font: UIFont.systemFont(ofSize: 15, weight: .bold)])
            t.append(NSAttributedString(
                string: que,
                attributes: [.foregroundColor: UIColor(white: 0.85, alpha: 1),
                             .font: UIFont.systemFont(ofSize: 14, weight: .regular)]))
            fila.attributedText = t
            fila.numberOfLines = 0
            stack.addArrangedSubview(fila)
        }

        // ---- ESCOGER LA VOZ, OYENDOLA ----
        //
        // "La voz no me gusta" no se arregla adivinando: el gusto es suyo. Se
        // le ponen las voces que SU telefono tiene y cada una se prueba de un
        // toque, diciendo una frase de verdad de las que va a oir trabajando.
        let vozTitulo = UILabel()
        vozTitulo.text = "La voz del asistente"
        vozTitulo.textColor = .white
        vozTitulo.font = .systemFont(ofSize: 17, weight: .bold)
        vozTitulo.numberOfLines = 0
        stack.addArrangedSubview(vozTitulo)

        let vozNota = UILabel()
        vozNota.text = "Toque una para oírla. La que escoja se usa también en el escáner de planos."
        vozNota.textColor = UIColor(white: 0.75, alpha: 1)
        vozNota.font = .systemFont(ofSize: 14, weight: .regular)
        vozNota.numberOfLines = 0
        stack.addArrangedSubview(vozNota)

        for voz in VozAsistente.disponibles().prefix(8) {
            let b = UIButton(type: .system)
            b.setTitle(VozAsistente.descripcion(voz), for: .normal)
            b.setTitleColor(.white, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            b.titleLabel?.numberOfLines = 0
            b.contentHorizontalAlignment = .left
            b.contentEdgeInsets = UIEdgeInsets(top: 11, left: 14, bottom: 11, right: 14)
            b.layer.cornerRadius = 9
            b.backgroundColor = VozAsistente.esLaEscogida(voz)
                ? Self.colorEscogido
                : UIColor(white: 0.22, alpha: 1)
            b.accessibilityIdentifier = voz.identifier
            b.addTarget(self, action: #selector(vozTapped(_:)), for: .touchUpInside)
            vozBotones.append(b)
            stack.addArrangedSubview(b)
        }

        // Y si el telefono SOLO trae voces basicas, ningun boton de aqui la va
        // a hacer sonar bien. Se dice, con el camino exacto, en vez de dejarlo
        // creyendo que la app no da para mas.
        if VozAsistente.soloBasicas() {
            let aviso = UILabel()
            aviso.text = "Todas las voces de este teléfono son Básicas — por eso suenan a robot. "
                + VozAsistente.comoBajarUnaMejor
            aviso.textColor = .white
            aviso.font = .systemFont(ofSize: 14, weight: .semibold)
            aviso.numberOfLines = 0
            aviso.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.28)
            aviso.layer.cornerRadius = 9
            aviso.clipsToBounds = true
            stack.addArrangedSubview(aviso)
        }

        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("Entendido", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        closeButton.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.95)
        closeButton.layer.cornerRadius = 10
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 13, left: 16, bottom: 13, right: 16)
        closeButton.addTarget(self, action: #selector(helpCloseTapped), for: .touchUpInside)
        helpCard.addSubview(closeButton)

        NSLayoutConstraint.activate([
            helpOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            helpOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            helpOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            helpOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            helpCard.leadingAnchor.constraint(equalTo: helpOverlay.leadingAnchor, constant: 20),
            helpCard.trailingAnchor.constraint(equalTo: helpOverlay.trailingAnchor, constant: -20),
            helpCard.topAnchor.constraint(greaterThanOrEqualTo: helpOverlay.safeAreaLayoutGuide.topAnchor, constant: 30),
            helpCard.bottomAnchor.constraint(lessThanOrEqualTo: helpOverlay.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            helpCard.centerYAnchor.constraint(equalTo: helpOverlay.centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: helpCard.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: helpCard.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: helpCard.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: helpCard.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: helpCard.trailingAnchor, constant: -16),
            scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 380),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            closeButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: helpCard.leadingAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: helpCard.trailingAnchor, constant: -16),
            closeButton.bottomAnchor.constraint(equalTo: helpCard.bottomAnchor, constant: -20)
        ])

        // The <=380 cap alone leaves the scroll view's height ambiguous (it has
        // no intrinsic size), so Auto Layout was collapsing it to 0 - this ties
        // it to the actual content height, still capped at 380 by the required
        // constraint above.
        let scrollHeightFit = scrollView.heightAnchor.constraint(equalTo: stack.heightAnchor)
        scrollHeightFit.priority = .defaultHigh
        scrollHeightFit.isActive = true
    }

    // MARK: - UIPickerViewDataSource / Delegate

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return opcionesDelSelector().count
    }

    // EL SELECTOR SIRVE PARA TODOS LOS PASOS, no solo para materiales.
    //
    // El respaldo manual no es un lujo: `siSeVe` impide que la voz haga algo
    // que un dedo no podria hacer en ese instante, asi que un paso sin boton
    // visible seria un paso SIN CANDADO. Y si la voz falla en una casa ruidosa,
    // el dedo tiene que poder terminar el trabajo.
    //
    // Se reusa la misma ventana que ya estaba probada en vez de inventar tres
    // pantallas nuevas: cambia la lista y el titulo, nada mas.
    // ============ LOS NOMBRES DE LOS CUARTOS ============
    //
    // Su pedido: "tiene que haber una opción para escribir los cuartos, porque
    // a veces hay cuarto uno, cuarto dos... como room one, room two, room
    // three, closet one, closet two, closet three".
    //
    // La lista fija no alcanza y no puede alcanzar: una casa tiene tres
    // recamaras y cuatro closets, y la lista trae "Bedroom" y "Closet" una sola
    // vez. Sin numerar, la segunda recamara caia en la misma tarjeta que la
    // primera y las dos medidas se sumaban en una sola - un error que no se ve
    // hasta que el area no cuadra con el plano.
    //
    // Tres cosas aqui:
    //  1. Los cuartos que YA se midieron en este recorrido salen primero, pero
    //     numerados al siguiente libre: si ya hay un Bedroom, se ofrece
    //     "Bedroom 2". Es lo que de verdad va a escoger en seguida.
    //  2. Despues la lista normal.
    //  3. Y arriba del todo, ESCRIBIRLO. Con teclado, que es la unica forma de
    //     poner "Kids Room" o "Office" en una casa que no se parece a ninguna.
    static let escribirCuarto = "__escribir__"

    // Los cuartos de los que una casa tiene VARIOS. Una casa normal trae tres
    // recamaras, dos baños y cuatro closets; "Kitchen" y "Living Room" hay una.
    // Numerar los que no se repiten seria llenar la lista de basura.
    static let cuartosQueSeRepiten: Set<String> = [
        "Bedroom", "Bathroom", "Closet", "Hallway", "Office", "Family Room"
    ]
    // Nombres que se usan de verdad y no estan en la lista de la web. Viajan al
    // campo libre, que ya los acepta. EN INGLES: van al seguro.
    static let cuartosConNombre = ["Kids Bedroom", "Guest Bedroom", "Guest Bathroom", "Half Bathroom"]

    private func opcionesDeCuarto() -> [(valor: String, etiqueta: String)] {
        var ops: [(valor: String, etiqueta: String)] = [(Self.escribirCuarto, "✏️  Escribir el nombre…")]
        func meter(_ v: String) {
            guard !ops.contains(where: { $0.valor == v }) else { return }
            ops.append((v, v))
        }
        // 1. LOS CUARTOS DEL PLANO DE ESTA CASA, primero y sin rellenos.
        //
        // Su reporte del 12 de septiembre, con foto: "seleccione el plano, pero
        // en la barrita de scrollear no me aparecen los nombres de los cuartos
        // sugeridos... en la misma barrita yo deberia seleccionar que cuarto voy
        // a medir, que esos nombres ya vienen del plano".
        //
        // Y tenia razon. La rueda muestra cinco renglones, y el bloque de abajo
        // mete TRES nombres inventados ("Family Room 2, 3, 4") justo detras de
        // cada cuarto repetible. Con el plano de Kate - Family Room, Kitchen,
        // Living Room, Hallway - los cinco renglones visibles se los comian
        // "Family Room" y sus tres copias, y Living Room y Hallway quedaban
        // enterrados. Los nombres del plano son los UNICOS seguros: van arriba,
        // enteros, sin nada intercalado.
        let delPlano = cuartosPorPlanta[nivelActual] ?? []
        if !delPlano.isEmpty {
            for c in delPlano { meter(c) }
            // Y SE ACABA AQUI. Su pedido del 12 de septiembre: "que nos sugiera
            // SOLO los nombres de los cuartos que ya estan en el plano,
            // dependiendo en que nivel seleccionamos, y que solo haya otra
            // barrita de escribir otro nombre, que no sugiera un monton".
            //
            // Antes, detras de estos venia todo lo demas: la lista generica del
            // nivel, tres copias numeradas de cada cuarto repetible, y los
            // cuatro nombres sueltos. Con el plano de Kate eran cuatro nombres
            // ciertos enterrados entre veinte inventados, en una rueda que
            // muestra cinco renglones.
            //
            // La unica otra opcion es "✏️ Escribir el nombre…", que ya va de
            // primera en `ops` - un cuarto que el escaner no vio se teclea.
            return ops
        }

        // ---- SIN PLANO DE ESTA PLANTA: la lista de siempre ----
        // Dejarla con solo "escribir el nombre" seria peor que una lista larga.

        // 2. Los ya usados en ESTE NIVEL, ofrecidos al siguiente numero libre.
        //    Acaba de medir una recamara y lo que sigue es otra.
        //
        //    Por NIVEL y no por todo el recorrido: juntando los de todos los
        //    pisos, el primer cuarto de un piso nuevo se ofrecia ya numerado
        //    ("Bedroom 2") aunque en ese piso no hubiera ningun "Bedroom".
        let usados = Set(items.filter { $0.nivel == nivelActual }.map { $0.cuarto }).filter { !$0.isEmpty }
        for base in cuartosDisponibles where usados.contains(where: { $0 == base || $0.hasPrefix(base + " ") }) {
            meter(Self.siguienteNumero(base: base, entre: usados))
        }
        // 3. El resto de la lista de la zona.
        for c in cuartosDisponibles { meter(c) }
        // 4. Y AL FINAL los repetibles ya numerados.
        //
        // Su pedido original: "tiene que ir como bedroom one, bedroom two,
        // master bedroom, kids bedroom, bathroom, closet one, closet two,
        // closet three" - si queria saltarse al tres tenia que escribirlo a
        // mano. Siguen estando, porque una casa con dos recamaras en un piso es
        // de verdad y el escaner pudo nombrar solo una. Pero DETRAS de todo lo
        // real, no intercalados.
        for c in cuartosDisponibles where Self.cuartosQueSeRepiten.contains(c) {
            for n in 2...4 { meter("\(c) \(n)") }
        }
        // 5. Los que se llaman por su nombre y no estan en la lista de la web.
        for c in Self.cuartosConNombre { meter(c) }
        return ops
    }

    // "Bedroom" ya usado -> "Bedroom 2". Ya usados "Bedroom" y "Bedroom 2" ->
    // "Bedroom 3". Se cuenta lo que HAY, no un contador aparte que se
    // desincronizaria al deshacer una medida.
    static func siguienteNumero(base: String, entre usados: Set<String>) -> String {
        // La base se limpia de un numero que ya traiga: con "Room 3" de entrada
        // esto devolvia "Room 3 2". Los nombres numerados vienen tanto del plano
        // ("Bedroom 2" que el bautizo) como de la lista por nivel.
        var raiz = base
        if let r = base.range(of: " [0-9]+$", options: .regularExpression) {
            raiz = String(base[base.startIndex..<r.lowerBound])
        }
        let base = raiz
        var n = 2
        while usados.contains("\(base) \(n)") { n += 1 }
        return usados.contains(base) ? "\(base) \(n)" : base
    }

    // El teclado, para un nombre que no esta en ninguna lista.
    private func pedirNombreEscrito(_ paso: Paso) {
        // EN INGLES. Su regla, y no es una preferencia: este nombre sale tal
        // cual en el reporte que va al SEGURO. Un cuarto llamado "Cuarto de
        // Juan" en una factura en ingles es una linea que el ajustador no puede
        // leer - y lo que el ajustador no entiende, lo rebota.
        let a = UIAlertController(title: "¿Cómo se llama el cuarto?",
                                  message: "Escríbalo EN INGLÉS: este nombre sale tal cual en el reporte del seguro.",
                                  preferredStyle: .alert)
        a.addTextField { t in
            t.placeholder = "Kids Room, Office, Closet 3, Room 2"
            t.autocapitalizationType = .words
            t.returnKeyType = .done
            // Si ya se sabe de que cuarto viene, se ofrece numerado: casi
            // siempre el siguiente es el mismo tipo de cuarto otra vez.
            let usados = Set(self.items.map { $0.cuarto }).filter { !$0.isEmpty }
            if !self.roomName.isEmpty {
                let base = self.roomName.replacingOccurrences(of: "\\s+\\d+$", with: "",
                                                             options: .regularExpression)
                t.text = Self.siguienteNumero(base: base, entre: usados.union([self.roomName]))
                t.clearButtonMode = .whileEditing
            }
        }
        a.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { [weak self] _ in
            // Cancelar no puede dejarlo sin cuarto y sin pregunta: se le
            // vuelve a preguntar en vez de dejarlo mirando la camara.
            guard let self = self else { return }
            self.preguntar(paso, self.preguntaDeCuarto())
        })
        a.addAction(UIAlertAction(title: "Usar este nombre", style: .default) { [weak self] _ in
            guard let self = self else { return }
            let escrito = (a.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !escrito.isEmpty else {
                self.preguntar(paso, self.preguntaDeCuarto())
                return
            }
            // Entra por el MISMO camino que decirlo o escogerlo de la lista.
            //
            // PERO SIN VOLVER A PREGUNTAR si esta en el plano: acaba de
            // teclearlo y de tocar "Usar este nombre". Preguntarle "¿lo
            // agrego?" por algo que escribio a proposito es hacerle confirmar
            // dos veces lo mismo.
            self.pasoAbierto = paso
            self.saltarConfirmacionDeCuarto = true
            _ = self.contestar(paso, escrito)
            self.saltarConfirmacionDeCuarto = false
            self.updateUI()
        })
        present(a, animated: true)
    }

    private func opcionesDelSelector() -> [(valor: String, etiqueta: String)] {
        switch pasoDelSelector {
        case .queNivel:   return nivelesDisponibles.map { ($0, $0) }
        case .queCuarto:  return opcionesDeCuarto()
        case .queSeccion: return ["floor", "wall", "ceiling", "kitchen", "bathroom", "materiales"]
                                 .filter { seccionesDisponibles[$0] != nil || $0 == section }
                                 .map { ($0, Self.sectionSpokenName($0).capitalized) }
        // La lista grande tambien: "Poste / Armazón / Stud / Framing" no le
        // dice nada a nadie, y ahi es donde busca cuando la barra no le
        // alcanzo. La palabra que usa, y ya.
        default:          return materials.map { ($0.value, Self.nombreDeBoton($0)) }
        }
    }

    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 36 }

    // Explicit white text - the picker's default row color doesn't reliably
    // read against this screen's dark card regardless of system theme.
    func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
        let ops = opcionesDelSelector()
        guard row < ops.count else { return nil }
        return NSAttributedString(string: ops[row].etiqueta, attributes: [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 17, weight: .medium)
        ])
    }

    // Si despues de oir el recibo hace CUALQUIER otra cosa - marcar otra
    // esquina, escoger material, deshacer - es que no queria mandar todavia.
    // El boton vuelve a decir Terminar solo.
    private func cancelarResumen() {
        guard resumenPendiente else { return }
        resumenPendiente = false
        reciboEnPantalla = nil
        finishButton.setTitle("Terminar", for: .normal)
    }

    private func updateUI() {
        // La barra de materiales se mantiene al dia sola: marca el que esta
        // escogido y se rehace cuando cambia la seccion (adentro se compara una
        // firma, asi que la mayoria de las veces no hace nada).
        pintarTiraDeMateriales()
        materialOverlay.isHidden = !(stage == .pickingMaterial && listaVisible)
        // El boton para abrirla a mano: solo mientras toca escoger material y
        // la lista no esta abierta.
        // El respaldo manual tiene que estar EN CADA PASO, no solo al escoger
        // material: si la voz falla a medio recorrido, el dedo tiene que poder
        // seguir. Y de paso es el candado de `siSeVe` para esos pasos.
        let enPasoDelRecorrido = (pasoAbierto ?? pasoPorArmar).map {
            $0 == .queNivel || $0 == .queCuarto || $0 == .queSeccion
        } ?? false
        listaButton.isHidden = listaVisible || !(stage == .pickingMaterial || enPasoDelRecorrido)
        ajustarMargenInferior()
        // Una medida nueva vuelve a merecer su recordatorio.
        if stage == .pickingMaterial || (stage == .measuringLength && pathPoints.isEmpty && !largoDictado) {
            recordatorioCompaneroPara = nil
        }
        // Se quita en cuanto deja de aplicar: ya lo marco, ya guardo o deshizo,
        // o se abrio una ventana encima.
        if includeCompanion || currentCompanion == nil || !(stage == .lengthDone || stage == .widthDone)
            || !helpOverlay.isHidden || !materialOverlay.isHidden {
            ocultarRecordatorio()
        }
        if enPasoDelRecorrido {
            listaButton.setTitle("📋  Escoger de la lista", for: .normal)
        }
        actualizarTiraDeEstado()
        if stage == .pickingMaterial {
            addButton.isHidden = true
            addWidthButton.isHidden = true
            saveContinueButton.isHidden = true
            finishPathButton.isHidden = true
            finishButton.isHidden = items.isEmpty
            undoButton.isHidden = items.isEmpty
            return
        }

        let canFinish = !items.isEmpty || hasLengthMeasurement
        finishButton.isHidden = !canFinish
        let hasInProgressWork = !pathPoints.isEmpty || pendingStart != nil || currentWidthFeet != nil
            || stage == .lengthDone || stage == .widthDone
        undoButton.isHidden = !hasInProgressWork && items.isEmpty

        addButton.isHidden = true
        addWidthButton.isHidden = true
        saveContinueButton.isHidden = true
        finishPathButton.isHidden = true

        // Cada instruccion que ya se escribia, ahora tambien se oye. Se dice
        // al final de updateUI (ver el say de abajo), una sola vez por cambio.
        switch stage {
        case .pickingMaterial:
            break
        case .measuringLength:
            addButton.isHidden = false
            if pathPoints.isEmpty {
                instructionLabel.text = "Apunte a la primera esquina y toque +"
            } else if pathPoints.count == 1 {
                instructionLabel.text = "Camine a la siguiente esquina y toque +"
            } else {
                finishPathButton.isHidden = false
                instructionLabel.text = String(format: "Total del recorrido: %.1f pies. Siga a otra esquina, o toque \"Terminar Recorrido\".", pathTotalFeet)
            }
        case .lengthDone:
            addWidthButton.isHidden = false
            saveContinueButton.isHidden = false
            instructionLabel.text = String(format: "Recorrido de %.1f pies capturado. Agregue un ancho, o guarde y siga.", pathTotalFeet)
        case .measuringWidth:
            addButton.isHidden = false
            instructionLabel.text = pendingStart == nil
                ? "Apunte al INICIO del ancho y toque +"
                : "Apunte al FINAL del ancho y toque +"
        case .widthDone:
            saveContinueButton.isHidden = false
            // EL + SE QUEDA VISIBLE. Estaba escondido aqui, y por eso un ancho
            // que dobla no se podia seguir: con dos puntos quedaba cerrado.
            addButton.isHidden = false
            if let w = currentWidthFeet, widthPoints.count > 2 {
                instructionLabel.text = String(format: "Ancho de %.1f pies en %d tramos. Siga a otra esquina, o guarde y siga.", w, widthPoints.count - 1)
            } else if let w = currentWidthFeet, widthPoints.count == 2 {
                instructionLabel.text = String(format: "Ancho de %.1f pies. Si el ancho dobla, siga a la otra esquina y toque +. Si no, guarde y siga.", w)
            } else {
                instructionLabel.text = "Medida completa. Guarde y siga con la próxima, o termine."
            }
        }

        // La fila se pinto arriba, antes de que este paso decidiera que botones
        // se ven: sin repintarla, "Guardar" se quedaba apagado justo cuando ya
        // se podia guardar.
        pintarTiraDeAcciones()

        // Asked right at the point of saving, for both the length-only and
        // length+width cases - one question, whichever one applies to
        // whatever material was actually picked for this measurement.
        if let companion = currentCompanion, stage == .lengthDone || stage == .widthDone {
            // El nombre de la pastilla de abajo que lo marca, igual que ella lo dice.
            let pastilla = "+ " + Self.nombreDeBoton(valor: companion.value, etiqueta: companion.en)
            // Su pedido textual: "si sabe que pucharon drywall, puede sugerir
            // esto tiene insulacion antes que lo guardes". Se DICE una sola vez
            // por medida, y justo antes de guardar, que es cuando todavia se
            // puede marcar.
            do {
                let m = selectedMaterial?.value ?? ""
                let porque: String
                if m.contains("Drywall") || m.contains("Plaster") {
                    porque = "La tablaroca casi siempre lleva insulación atrás."
                } else if m.contains("Carpet") {
                    porque = "La alfombra casi siempre lleva almohadilla debajo."
                } else if m.contains("Texture") || m.contains("Popcorn") {
                    porque = "El techo casi siempre lleva insulación arriba."
                } else {
                    porque = "Esto casi siempre lleva " + companion.es.lowercased() + " detrás."
                }
                say(porque + " Si también lo quitó, toque más \(pastilla.dropFirst(2)) abajo antes de guardar.", .guia, llave: "companero")
            }
            // Y se VE un momento enfrente, como recordatorio, y se va solo.
            if !includeCompanion, recordatorioCompaneroPara != companion.value, helpOverlay.isHidden, materialOverlay.isHidden {
                recordatorioCompaneroPara = companion.value
                mostrarRecordatorio(Self.textoRecordatorioCompanero(seccion: seccionDelMaterial(selectedMaterial?.value ?? ""),
                                                                    companero: companion.es, pastilla: pastilla))
            }
        }

        // AQUI SE NARRABA CADA INSTRUCCION EN VOZ ALTA, y era la fuente
        // numero uno de "repite mucho lo mismo": updateUI() corre en cada
        // toque, cada Deshacer, cada casilla, y el guardia solo evitaba
        // repetir la MISMA frase dos veces seguidas - ir y venir entre dos
        // estados la repetia sin fin. La pantalla ya dice el texto; la voz
        // ahora solo habla en los momentos que importan (ver guiarPorEsquinas,
        // materialConfirmTapped y los avisos), una sola vez cada uno.

        // El recibo pendiente manda sobre cualquier instruccion: es lo ultimo
        // que le pedimos leer antes de mandar el trabajo.
        if resumenPendiente, let recibo = reciboEnPantalla {
            instructionLabel.text = recibo
        }
        // El aviso del ancho faltante sobrevive a updateUI mientras siga
        // faltando el ancho. Antes lo borraba cualquier repintado - marcar la
        // casilla del compañero lo hacia desaparecer al instante - y la unica
        // huella en pantalla de que algo iba a salir mal se esfumaba.
        if let aviso = avisoEnPantalla {
            if currentWidthFeet == nil, hasLengthMeasurement,
               let m = selectedMaterial, unidad(for: m.value) == .cuadrado {
                instructionLabel.text = aviso
            } else {
                avisoEnPantalla = nil
            }
        }

    }

    // MARK: - Raycasting

    // Que tiene enfrente la camara ahorita mismo.
    //
    // Primero se le pregunta a ARKit su clasificacion, que es la buena. Si
    // el telefono no la trae (o todavia no se decide), se cae a pura
    // geometria: un plano vertical es pared; uno horizontal ARRIBA de la
    // camara es techo; abajo, piso. Esa segunda via no falla nunca y no
    // depende de que Apple haya clasificado el cuarto.
    private func currentSurface() -> Surface? {
        let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        guard let query = sceneView.raycastQuery(from: center, allowing: .existingPlaneGeometry, alignment: .any),
              let hit = sceneView.session.raycast(query).first else { return nil }
        if let plane = hit.anchor as? ARPlaneAnchor {
            switch plane.classification {
            case .wall:    return .wall
            case .floor:   return .floor
            case .ceiling: return .ceiling
            case .table, .seat, .door, .window: return .other
            default: break   // sin clasificar todavia: sigue abajo
            }
            if plane.alignment == .vertical { return .wall }
            // Horizontal: arriba o abajo de la camara.
            let camY = sceneView.session.currentFrame?.camera.transform.columns.3.y
            let planeY = hit.worldTransform.columns.3.y
            if let camY = camY { return planeY > camY ? .ceiling : .floor }
            return .floor
        }
        return nil
    }

    // Como se llama la seccion de la que vino, para poder avisar del choque.
    private func expectedSurface() -> Surface? {
        switch section {
        case "floor":   return .floor
        case "wall":    return .wall
        case "ceiling": return .ceiling
        default:        return nil   // cocina y demas: no hay una sola correcta
        }
    }
    private static func sectionSpokenName(_ s: String) -> String {
        switch s {
        case "floor": return "piso"
        case "wall": return "pared"
        case "ceiling": return "techo"
        case "kitchen": return "cocina"
        case "materiales": return "materiales"
        default: return ""
        }
    }

    // Se dice lo que ve, pero SOLO cuando se asienta. Sin esta espera, un
    // barrido de la camara por el cuarto soltaria "pared, piso, pared,
    // techo" en dos segundos y nadie volveria a hacerle caso.
    private func updateSurfaceAssistant() {
        guard stage == .measuringLength || stage == .measuringWidth else { return }
        guard let s = currentSurface(), s != .other else { return }
        if s != pendingSurface {
            pendingSurface = s
            surfaceStableSince = Date()
            return
        }
        guard let since = surfaceStableSince, Date().timeIntervalSince(since) >= 1.5 else { return }
        guard s != lastSurfaceSpoken else { return }
        lastSurfaceSpoken = s
        // El choque: vino de la tarjeta de Pared y esta apuntando al piso.
        // Es el error que mas caro sale aqui y el mas facil de cometer, asi
        // que se dice primero y se dice claro. No BLOQUEA - el sabra si tiene
        // una razon; la app avisa, no manda.
        if let esperado = expectedSurface(), esperado != s {
            say("Ojo: veo \(Self.surfaceName(s)), pero esta medida es de \(Self.sectionSpokenName(section)).", .aviso, llave: "choque-\(s)")
            return
        }
        // Y si esta apuntando a lo correcto, NO SE DICE NADA. Antes soltaba
        // "veo que esta midiendo una pared" cada vez que la camara cambiaba
        // de superficie: era lo mas repetitivo de todo el asistente y no le
        // decia nada que no estuviera viendo con sus propios ojos. El unico
        // caso que vale la pena abrir la boca es el de arriba, cuando esta
        // apuntando al lugar equivocado.
    }

    private func currentRaycastHit() -> simd_float3? {
        let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        let query = sceneView.raycastQuery(from: center, allowing: .existingPlaneGeometry, alignment: .any)
            ?? sceneView.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .any)
        guard let query = query, let result = sceneView.session.raycast(query).first else { return nil }
        let t = result.worldTransform
        return simd_float3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
    }

    @objc private func tick() {
        // La bolita se mueve con el volumen de VERDAD, no con una animacion
        // inventada. Un RMS de 0.08 ya es hablar de cerca; se escala a 1 para
        // que llegue arriba sin tener que gritar.
        orbita.actualizar(nivel: CGFloat(min(nivelVivo / 0.08, 1.0)))
        // La pausa se despinta sola. Si el se distrae y nunca dice "ya estoy",
        // una app muda para el resto del trabajo es peor que una que
        // interrumpe una vez - y es indistinguible de estar descompuesta.
        if enPausa, Date().timeIntervalSince(pausaDesde) > 300 {
            enPausa = false
            say("Ya pasó un rato. Aquí sigo. " + situacionActual(), .aviso)
        }
        // El asistente se cuelga del tick que ya corria - ni un timer mas.
        updateSurfaceAssistant()
        guard let start = pendingStart else {
            liveLabel.isHidden = true
            lineLayer.path = nil
            return
        }
        guard let hit = currentRaycastHit() else { return }
        let feet = Double(simd_distance(start, hit)) * 3.28084
        liveLabel.isHidden = false
        liveLabel.text = String(format: "%.1f pies", feet)
        updateLiveLine(from: start)
    }

    // Draws a dashed line from the anchor point (projected from its fixed
    // 3D world position onto the screen this frame) to the crosshair, so
    // the crew can see exactly what's being measured while they move the
    // phone toward the far end - not just a number changing.
    private func updateLiveLine(from start: simd_float3) {
        let startVec = SCNVector3(start.x, start.y, start.z)
        let projected = sceneView.projectPoint(startVec)
        // z outside 0...1 means the anchor is behind the camera or past the
        // far clip plane - projecting it anyway would draw a line flying to
        // a meaningless spot on screen, so just hide it instead.
        guard projected.z >= 0, projected.z <= 1 else {
            lineLayer.path = nil
            return
        }
        let startScreen = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
        let endScreen = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)
        let path = UIBezierPath()
        path.move(to: startScreen)
        path.addLine(to: endScreen)
        lineLayer.path = path.cgPath
    }

    // MARK: - Markers

    @discardableResult
    private func addMarker(at position: simd_float3, color: UIColor) -> SCNNode {
        let sphere = SCNSphere(radius: 0.012)
        sphere.firstMaterial?.diffuse.contents = color
        sphere.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(position.x, position.y, position.z)
        sceneView.scene.rootNode.addChildNode(node)
        return node
    }

    // A thin cylinder stretched and rotated to span two 3D points - the
    // standard way to draw a "line" in SceneKit, since there's no simpler
    // built-in primitive that supports width and a flat, unlit color the
    // way this needs. Anchored in the scene, so once a corner is placed the
    // line to it stays visible from any angle, not just the one it was
    // drawn from - that's what turns a row of separate dots into a trail
    // the crew can actually see themselves having walked.
    @discardableResult
    private func addLineSegment(from start: simd_float3, to end: simd_float3, color: UIColor) -> SCNNode {
        let distance = simd_distance(start, end)
        let cylinder = SCNCylinder(radius: 0.006, height: CGFloat(max(distance, 0.001)))
        cylinder.radialSegmentCount = 12
        cylinder.firstMaterial?.diffuse.contents = color
        cylinder.firstMaterial?.lightingModel = .constant
        let node = SCNNode(geometry: cylinder)
        let mid = (start + end) / 2
        node.position = SCNVector3(mid.x, mid.y, mid.z)
        // SCNCylinder's height runs along local +Y by default - this finds
        // the rotation that carries +Y onto the actual start->end direction.
        let direction = simd_normalize(end - start)
        node.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: direction)
        sceneView.scene.rootNode.addChildNode(node)
        return node
    }

    // MARK: - Actions

    @objc private func materialConfirmTapped() {
        cancelarResumen()
        let row = materialPickerView.selectedRow(inComponent: 0)
        // Los pasos del recorrido se contestan por el MISMO camino que la voz,
        // no por uno aparte: asi el dedo y la voz no pueden divergir.
        switch pasoDelSelector {
        case .queNivel, .queCuarto, .queSeccion:
            let ops = opcionesDelSelector()
            guard row >= 0, row < ops.count else { return }
            let paso = pasoDelSelector
            // ¿Escogio "Escribir el nombre"? Entonces sale el teclado, que es
            // la unica forma de poner "Kids Room" o "Cuarto de Juan" en una
            // casa que no se parece a ninguna de la lista.
            if ops[row].valor == Self.escribirCuarto {
                listaVisible = false
                pasoDelSelector = .queMide
                updateUI()
                pedirNombreEscrito(paso)
                return
            }
            listaVisible = false
            pasoDelSelector = .queMide
            pasoAbierto = paso
            _ = contestar(paso, ops[row].valor)
            updateUI()
            return
        default:
            break
        }
        guard row >= 0, row < materials.count else { return }
        // ¿Ya iba midiendo? Entonces escoger material es CAMBIARLE EL NOMBRE a
        // la medida que lleva, no empezar otra (ver abajo).
        let aMedias = medidaEnCurso
        // Un material ESCRITO A MANO no se aprende: ni como la palabra de algo
        // que no se entendio, ni en la cuenta de "el que mas usa". Esa cuenta se
        // guarda en el telefono para siempre, y lo escrito solo existe en esta
        // sesion: "Stair treads" le quitaba el primer lugar al LVP de todos los
        // dias, y la vez siguiente ni siquiera estaba en la fila.
        let escrito = esEscrito(materials[row].value)
        // Si acaba de decir algo que no se entendio y AHORA escoge, esa
        // palabra era este material. Queda aprendida.
        if !escrito, let ne = noEntendido, Date().timeIntervalSince(ne.cuando) < 25 {
            aprenderPalabra(ne.palabra, para: materials[row].value)
        }
        noEntendido = nil
        selectedMaterial = materials[row]
        arrancarConteoSiHaceFalta()
        // Lo de debajo NUNCA se hereda del material anterior: el de ahora se
        // pregunta (abajo) y la casilla no se toca hasta que el conteste. Antes
        // no hacia falta, porque solo se escogia material antes de medir; ahora
        // tambien se puede a medias.
        includeCompanion = false
        listaVisible = false
        if !escrito { recordarMaterialUsado(materials[row].value) }
        medidaNueva()
        // Y la conversacion sigue sola: lo que lleva debajo, y a medir. Se
        // pregunta AHORA, no al guardar - en un trabajo de agua, si lleva
        // insulación se sabe en el momento de arrancarlo, no al final.
        let nombre = Self.nombreDeBoton(materials[row])
        if let comp = Self.companionDe(materials[row]) {
            // SIEMPRE SE PREGUNTA. SIEMPRE.
            //
            // Su reporte del 12 de septiembre: "a veces selecciona
            // automáticamente insulación y no debería hacerlo; tiene que
            // esperar y escuchar si yo le digo que sí o no".
            //
            // Yo lo habia puesto al contrario: si en las ultimas tres medidas
            // de ese material siempre le habia puesto insulacion, se marcaba
            // sola y se lo decia en voz alta. El razonamiento era ahorrarle una
            // pregunta que ya habia contestado tres veces. Estaba mal, y no por
            // un descuido sino por el tipo de decision:
            //
            // MARCAR INSULACION AGREGA UNA LINEA A LA FACTURA DEL SEGURO. Una
            // costumbre no es un permiso. Que la app acierte nueve de diez
            // veces no sirve: la decima es una linea que el no aprobo, en un
            // documento que firma el, y que el ajustador le puede rebotar.
            // Decirlo en voz alta no alcanza - el esta viendo la pantalla con
            // las dos manos ocupadas, no auditando lo que la app decidio.
            //
            // Lo aprendido se queda, pero SOLO para redactar la pregunta: se
            // le dice "como siempre" para que un "sí" le cueste una palabra.
            // La casilla no se toca hasta que el conteste.
            let comoSiempre = MemoriaAsistente.companeroUsual(material: materials[row].value) == true
            preguntar(.llevaCompanero, comoSiempre
                      ? "\(nombre). ¿Lleva \(comp), como siempre?"
                      : "\(nombre). ¿Lleva \(comp)?")
        } else if aMedias {
            say("\(nombre). Siga midiendo.", .guia)
        } else {
            say("\(nombre). Apunte a la primera esquina y diga marca.", .guia)
        }
        yaAvisoFaltaAncho = false
        // ESCOGER MATERIAL A MEDIAS YA NO REGRESA AL LARGO (21 sep 2026).
        //
        // Esto decia `stage = .measuringLength` siempre. medidaNueva() solo
        // limpia lo que se dice, NO las esquinas: con el ancho ya marcado, tocar
        // otro material regresaba al largo con los puntos puestos, y el
        // siguiente "marca" le sumaba al LARGO la distancia desde la ultima
        // esquina del ancho. Guardar mandaba ese largo inflado por el ancho de
        // antes. Ya pasaba con las pastillas de siempre; "Otro" era una puerta
        // mas para caer ahi. A medias, solo cambia el nombre.
        if !aMedias { stage = .measuringLength }
        // Se dice ANTES de que empiece a medir, que es cuando todavia sirve.
        // Se dice UNA vez, al escoger. Si vuelve a escoger el mismo material
        // en otra medida, se dice otra vez - porque medidaNueva() limpia las
        // llaves y esa si es informacion nueva para ESA medida.
        say(explicacionUnidad(for: materials[row].value), .guia, llave: "unidad")
    }

    @objc private func addTapped() {
        aprendiDelDedo("marcar")
        cancelarResumen()
        guard let hit = currentRaycastHit() else {
            flashNoSurfaceWarning()
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if stage == .measuringLength {
            // Every tap places a corner. The first just anchors the start;
            // every one after that closes a segment (added to the running
            // total) and immediately becomes the anchor for the next one -
            // there's no fixed number of corners, so the loop never forces
            // a stage change on its own. Only "Terminar Recorrido" does.
            let marker = addMarker(at: hit, color: pendingStart == nil ? .systemYellow : .systemGreen)
            currentMarkers.append(marker)
            if let start = pendingStart {
                pathTotalFeet += Double(simd_distance(start, hit)) * 3.28084
                currentLines.append(addLineSegment(from: start, to: hit, color: .systemYellow))
            }
            pathPoints.append(hit)
            pendingStart = hit
            pendingStartNode = marker
            lineLayer.path = nil
            updateUI()
            guiarPorEsquinas()
            return
        }

        // EL ANCHO TAMBIEN VA POR ESQUINAS, igual que el largo.
        //
        // Cada toque cierra un tramo y se vuelve el ancla del siguiente, asi que
        // un ancho que dobla se mide caminandolo. El caso de dos puntos se
        // comporta EXACTAMENTE como antes - en cuanto hay dos se pasa a
        // .widthDone y sale "Guardar y seguir" - pero `pendingStart` se queda
        // puesto, asi que otro toque lo sigue alargando en vez de dejarlo
        // encerrado. Nadie tiene que aprender nada nuevo para lo de siempre.
        let marker = addMarker(at: hit, color: pendingStart == nil ? .systemYellow : .systemGreen)
        currentMarkers.append(marker)
        if let start = pendingStart {
            currentLines.append(addLineSegment(from: start, to: hit, color: .systemBlue))
        }
        widthPoints.append(hit)
        recomputeWidthTotal()
        pendingStart = hit
        pendingStartNode = marker
        lineLayer.path = nil
        // Con dos o mas esquinas ya hay un ancho que guardar.
        if widthPoints.count >= 2 { stage = .widthDone } else { updateUI() }
    }

    // Lo que se dice segun cuantas esquinas lleva y QUE escogio. El
    // asistente ya sabe que material toco - esto es usar ese dato.
    private func guiarPorEsquinas() {
        guard let material = selectedMaterial else { return }
        let f = forma(for: material.value)
        switch (f, pathPoints.count) {
        case (.rectangulo, 2):
            // Ya cerro el largo. Aqui es donde se le sugiere el ancho, que es
            // lo que falta para los pies cuadrados.
            let que = section == "ceiling" ? "El techo" : "El piso"
            // Antes lo mandaba a tocar DOS botones. Ahora se le pregunta y
            // con un "sí" la app hace los dos pasos sola.
            // Y si este material siempre lleva el mismo ancho - el corte de
            // pared de dos pies es el caso de todos los dias - se le OFRECE el
            // numero. Ofrecer, no poner: la app no inventa medidas, y que el
            // numero salga de una costumbre no lo haria menos inventado. El
            // contesta "sí" y entonces si.
            if let m = selectedMaterial, let usual = MemoriaAsistente.anchoUsual(material: m.value) {
                anchoOfrecido = usual
                preguntar(.ocupaAncho, "Ya tiene el largo. ¿\(Self.piesHablados(usual)) de ancho, como siempre?")
            } else {
                anchoOfrecido = nil
                preguntar(.ocupaAncho, "Ya tiene el largo. ¿Ocupa el ancho?")
            }
        case (.rectangulo, 3):
            // Tercera esquina en algo que se mide como rectangulo: el numero
            // va a salir mal. Se avisa UNA vez y no se bloquea - el sabe si
            // de veras es un cuarto en L.
            say("Ojo: con tres esquinas el área sale mal. Un cuarto en ele se guarda en dos medidas separadas.", .aviso, llave: "tres-esquinas")
        case (.recorrido, 2):
            // La excepcion que el pidio, dicha en voz alta para que sepan que
            // AQUI si se puede seguir.
            say("La pared se mide de corrido: siga a la siguiente esquina. Al final el ancho es el alto del corte.", .guia, llave: "recorrido")
        default:
            break
        }
    }
    private static func piesTexto(_ ft: Double) -> String {
        return String(format: "%.1f pies", ft)
    }

    // Keeps pathTotalFeet as the sum of every consecutive pair after a
    // corner gets removed - cheap to just redo from scratch given how few
    // corners a real walk ever has.
    private func recomputePathTotal() {
        pathTotalFeet = 0
        guard pathPoints.count >= 2 else { return }
        for i in 1..<pathPoints.count {
            pathTotalFeet += Double(simd_distance(pathPoints[i - 1], pathPoints[i])) * 3.28084
        }
    }

    // Igual que la del largo. Con menos de dos esquinas no hay ancho: se pone
    // en nil, no en 0 - un 0 se guardaria como un ancho de cero pies.
    private func recomputeWidthTotal() {
        guard widthPoints.count >= 2 else { currentWidthFeet = nil; return }
        var t = 0.0
        for i in 1..<widthPoints.count {
            t += Double(simd_distance(widthPoints[i - 1], widthPoints[i])) * 3.28084
        }
        currentWidthFeet = t
    }

    @objc private func undoTapped() {
        cancelarResumen()
        aprendiDelDedo("deshacer")
        // Mid-walk: drop just the last corner placed, not the whole path -
        // one bad tap three corners in shouldn't cost the whole walk.
        if stage == .measuringLength, !pathPoints.isEmpty {
            if let node = currentMarkers.popLast() { node.removeFromParentNode() }
            // A line only exists between two points - removing the first
            // point of a fresh path has none to clean up yet.
            if pathPoints.count >= 2, let line = currentLines.popLast() { line.removeFromParentNode() }
            pathPoints.removeLast()
            recomputePathTotal()
            if let last = pathPoints.last {
                pendingStart = last
                pendingStartNode = currentMarkers.last
            } else {
                pendingStart = nil
                pendingStartNode = nil
            }
            lineLayer.path = nil
            updateUI()
            return
        }
        // Entro a Medir Ancho por error y todavia no marco nada: Deshacer
        // tiene que devolverlo. Antes ninguna rama lo agarraba - Deshacer se
        // veia en pantalla y no hacia absolutamente nada, y Guardar y Seguir
        // esta escondido en esta etapa, asi que quedaba encerrado sin mas
        // salida que marcar dos puntos de ancho que no queria.
        if stage == .measuringWidth, pendingStart == nil {
            stage = .lengthDone
            say("Listo, cancelé el ancho.", .guia)
            return
        }
        // Mid-width segment: just drop the pending start point.
        if stage == .measuringWidth, pendingStart != nil {
            pendingStartNode?.removeFromParentNode()
            if let node = pendingStartNode, let idx = currentMarkers.firstIndex(of: node) {
                currentMarkers.remove(at: idx)
            }
            pendingStart = nil
            pendingStartNode = nil
            // Y EL PUNTO TAMBIEN (21 sep 2026). Se quitaba la bolita de la
            // pantalla pero el punto se quedaba en widthPoints: una esquina
            // fantasma. Estaba dormida hasta que el candado de "medida a
            // medias" empezo a mirar widthPoints -- desde ahi trababa la camara:
            // no dejaba cambiar de seccion, y al escoger material decia "Siga
            // midiendo" sin boton de +. Y si se llegaba a medir, esa esquina
            // vieja era la primera del ancho siguiente.
            // Solo si habia puntos: un ancho DICHO ("otra igual") no tiene
            // esquinas, y recalcular lo borraria.
            if !widthPoints.isEmpty {
                widthPoints.removeLast()
                recomputeWidthTotal()
            }
            lineLayer.path = nil
            updateUI()
            return
        }
        // UN ancho CAMINADO: se quita el ULTIMO tramo, no el ancho entero. Con
        // un ancho de cuatro esquinas, un toque malo en la tercera no puede
        // costar las tres buenas - la misma regla que ya tiene el largo.
        if stage == .widthDone, !widthPoints.isEmpty {
            if let node = currentMarkers.popLast() { node.removeFromParentNode() }
            if widthPoints.count >= 2, let line = currentLines.popLast() { line.removeFromParentNode() }
            widthPoints.removeLast()
            recomputeWidthTotal()
            pendingStart = widthPoints.last
            pendingStartNode = widthPoints.isEmpty ? nil : currentMarkers.last
            lineLayer.path = nil
            if widthPoints.count >= 2 { updateUI(); return }
            // Queda una esquina o ninguna: vuelve a estar midiendo el ancho.
            yaAvisoFaltaAncho = false
            stage = .measuringWidth
            return
        }
        // Un ancho DICTADO por voz no tiene esquinas que quitar: se borra y se
        // vuelve a "largo listo", como antes.
        if stage == .widthDone, currentWidthFeet != nil {
            widthPoints = []
            currentWidthFeet = nil
            // Y se vuelve a armar el aviso del ancho faltante. Sin esto,
            // quitar el ancho dejaba el candado ya gastado, y la pared se
            // guardaba sin ancho y SIN QUE NADIE AVISARA - que es exactamente
            // el dinero que ese aviso existe para no perder.
            yaAvisoFaltaAncho = false
            stage = .lengthDone
            return
        }
        // The corner-walk was already closed off with "Terminar Recorrido",
        // nothing for width yet - discard the whole path and go back to
        // picking a material fresh, same as undoing a single-segment measure.
        if stage == .lengthDone {
            currentMarkers.forEach { $0.removeFromParentNode() }
            currentMarkers = []
            currentLines.forEach { $0.removeFromParentNode() }
            currentLines = []
            pathPoints = []
            pathTotalFeet = 0
            largoDictado = false
            // El ancho se va con el recorrido: era el UNICO de los tres sitios
            // que borran el largo (con cancelarMedidaEnCurso y bancarMedida) que
            // dejaba el ancho vivo, y eso trababa la camara (ver arriba).
            widthPoints = []
            currentWidthFeet = nil
            pendingStart = nil
            pendingStartNode = nil
            lineLayer.path = nil
            yaAvisoFaltaAncho = false
            includeCompanion = false
            selectedMaterial = nil
            // Este Deshacer borra el recorrido ENTERO y el material, un toque
            // despues de que el mismo boton quitaba una sola esquina. Que se
            // le diga: enterarse de que perdio el trabajo es peor si se
            // entera solo, mirando la pantalla vacia.
            say("Borré el recorrido completo. Empiece otra vez escogiendo el material.", .aviso)
            stage = (materials.isEmpty && !esRecorrido) ? .measuringLength : .pickingMaterial
            return
        }
        // UNA MEDIDA EMPEZADA SIN ESQUINAS ("otra igual" con su ancho puesto, o
        // un largo dictado): se cancela ESA. Antes caia en la rama de abajo, que
        // BORRABA LA ULTIMA MEDIDA GUARDADA -- una linea ya cobrada -- y dejaba el
        // ancho de "otra igual" cargado; el segundo toque borraba otra.
        if stage == .measuringLength, pathPoints.isEmpty, medidaEnCurso {
            cancelarMedidaEnCurso()
            updateUI()
            return
        }
        // Nothing in progress - undo the last measurement that was already
        // saved with "Guardar y Seguir", in case that was a mistake.
        //
        // Tambien desde .measuringLength sin esquinas puestas: ahi el boton
        // Deshacer SE VE (updateUI lo muestra porque hay medidas guardadas) y
        // antes ninguna rama lo agarraba, asi que una medida mal tomada se
        // quedaba en el reporte sin manera de quitarla.
        // !medidaEnCurso: con algo a medias, NUNCA se borra una guardada.
        if stage == .pickingMaterial || (stage == .measuringLength && pathPoints.isEmpty), !items.isEmpty, !medidaEnCurso {
            let last = items.removeLast()
            last.markers.forEach { $0.removeFromParentNode() }
            say("Quité la última medida guardada.", .aviso)
            updateUI()
        }
    }

    @objc private func addWidthTapped() {
        cancelarResumen()
        aprendiDelDedo("medirAncho")
        stage = .measuringWidth
    }

    @objc private func finishPathTapped() {
        cancelarResumen()
        aprendiDelDedo("terminarRecorrido")
        guard hasLengthMeasurement else { return }
        pendingStart = nil
        pendingStartNode = nil
        lineLayer.path = nil
        stage = .lengthDone
    }

    @objc private func companionToggleTapped() {
        includeCompanion.toggle()
        updateUI()
        // La casilla grande lo decia con su color y su texto; la pastilla es
        // chica, asi que se confirma de viva voz y en la casilla.
        if let c = currentCompanion {
            let dicho = includeCompanion ? "Sí lleva \(c.es.lowercased())." : "Sin \(c.es.lowercased())."
            instructionLabel.text = (includeCompanion ? "✓ " : "") + dicho
            say(dicho, .guia)
        }
    }

    // GUARDAR UNA MEDIDA. Un solo lugar.
    //
    // Esto estaba escrito DOS veces, palabra por palabra, en Guardar y en
    // Terminar. Y ya costo un bug: el chequeo contra el plano se agrego a una
    // de las dos copias y la otra se quedo sin el, asi que la ultima medida
    // del trabajo - la que casi siempre se guarda con Terminar - se iba sin
    // revisar. Dos copias de la misma regla es una regla que se va a separar.
    private func bancarMedida(_ material: ARMaterialOption) {
        // Una pieza no lleva ancho NUNCA: con ancho el papel la imprimiria
        // como pies cuadrados. Y su numero es entero.
        if material.porPieza {
            currentWidthFeet = nil
            pathTotalFeet = Double(max(1, piezasContadas))
        } else {
            // Un conteo NO son pies: revisarlo contra el plano diria que "2
            // inodoros no caben en el cuarto".
            avisarSiNoCabe(largo: pathTotalFeet, ancho: currentWidthFeet)
        }
        let companion = includeCompanion ? currentCompanion?.value : nil
        // DE AQUI APRENDE COMO MIDE. No de lo que dice: de lo que HACE. Una
        // medida guardada es una decision suya ya tomada, y despues de tres
        // iguales eso deja de ser casualidad y pasa a ser su forma de trabajar.
        let seccionGuardada = seccionDelMaterial(material.value)
        MemoriaAsistente.aprenderMedida(seccion: seccionGuardada, material: material.value,
                                        largo: pathTotalFeet, ancho: currentWidthFeet,
                                        companero: companion != nil)
        items.append((length: pathTotalFeet, width: currentWidthFeet,
                      material: material.value, companion: companion,
                      nivel: nivelActual, cuarto: roomName, seccion: seccionGuardada,
                      markers: currentMarkers + currentLines))
        pathPoints = []
        pathTotalFeet = 0
        largoDictado = false
        widthPoints = []
        currentWidthFeet = nil
        currentMarkers = []
        currentLines = []
        // El punto a medio poner tambien se suelta: sin esto, un "guardar"
        // dicho a media caminata lo dejaba vivo y la medida SIGUIENTE empezaba
        // con un tramo fantasma desde la esquina anterior.
        pendingStart = nil
        pendingStartNode = nil
        lineLayer.path = nil
        includeCompanion = false
        selectedMaterial = nil
        piezasContadas = 1
    }

    @objc private func saveContinueTapped() {
        cancelarResumen()
        guard hasLengthMeasurement, let material = selectedMaterial else { return }
        // EL MOMENTO QUE IMPORTA: va a guardar una superficie que se cobra
        // por pie cuadrado y no le tomo el ancho. Se avisa UNA vez; si
        // vuelve a tocar Guardar, se guarda como el quiere - el sabe si el
        // corte era bajito, y la app avisa, no manda.
        if unidad(for: material.value) == .cuadrado, currentWidthFeet == nil, !yaAvisoFaltaAncho {
            yaAvisoFaltaAncho = true
            let que = section == "wall" ? "la pared" : (section == "ceiling" ? "el techo" : "el piso")
            avisoEnPantalla = "⚠︎ Falta el ancho — sin él esto va como pie lineal"
            say("Ojo: \(que) se cobra por pie cuadrado y solo tiene el largo. Toque Medir Ancho, o Guardar otra vez si va por pie lineal.", .aviso)
            instructionLabel.text = avisoEnPantalla
            return
        }
        yaAvisoFaltaAncho = false
        bancarMedida(material)
        // Confirmar lo que acaba de guardar, corto. El total ya esta escrito
        // en la pantalla, pero el esta mirando una pared con el telefono en
        // alto: oirlo es lo unico que le sirve sin bajar la vista.
        //
        // Va ANTES de medidaNueva() a proposito - despues, la llave estaria
        // limpia y esto no es algo que deba repetirse por medida, es la
        // confirmacion de un toque que el acaba de dar.
        let cuantas = items.count
        let sqft = items.compactMap { i -> Double? in i.width.map { $0 * i.length } }.reduce(0, +)
        let lineal = items.filter { $0.width == nil }.map { $0.length }.reduce(0, +)
        var totales: [String] = []
        if sqft > 0 { totales.append(String(format: "%.0f pies cuadrados", sqft)) }
        if lineal > 0 { totales.append(String(format: "%.0f pies lineales", lineal)) }
        let cola = totales.isEmpty ? "" : ": " + totales.joined(separator: " y ")
        // Y SE SIGUE LA CONVERSACION. Este era el hueco que el reporto: al
        // guardar, la app se quedaba MUDA y el se quedaba parado sin saber que
        // seguia. En un trabajo de agua lo normal es medir varios cortes del
        // MISMO material en el mismo cuarto, asi que la pregunta correcta no
        // es "¿qué va a medir?" otra vez - es "¿sigue con lo mismo?".
        // `material` viene del guard de arriba, ANTES de que se limpiara. La
        // primera version leia `selectedMaterial` aqui abajo - donde ya era
        // nil - asi que la pregunta "¿sigue con lo mismo?" NUNCA se hacia, y
        // la app se quedaba muda justo como el lo reporto.
        let mismo: ARMaterialOption? = material
        medidaNueva()
        stage = (materials.isEmpty && !esRecorrido) ? .measuringLength : .pickingMaterial
        if let m = mismo, !materials.isEmpty {
            materialAnterior = m.value
            let nombre = Self.nombreDeBoton(m)
            preguntar(.sigueIgual,
                      "Guardado. Van \(cuantas) medida\(cuantas == 1 ? "" : "s")\(cola). ¿Sigue con \(nombre.lowercased())?")
        } else {
            say("Guardado. Van \(cuantas) medida\(cuantas == 1 ? "" : "s")\(cola).", .guia)
        }
    }
    // Con que material venia la medida anterior, para poder repetirlo de un
    // "sí" sin volver a preguntar todo.
    private var materialAnterior: String?

    @objc private func finishTapped() {
        // "Terminar" no puede ser la puerta de atras por donde una pared se
        // va sin ancho.
        //
        // Un intento anterior limito este aviso a .lengthDone/.widthDone
        // "porque ahi es donde existe el boton Medir Ancho" - y con eso abrio
        // algo PEOR que el problema original: Terminar tambien se ve en
        // .measuringLength, asi que la pared se guardaba sin ancho y SIN UN
        // SOLO AVISO. Lo correcto no era callar donde el boton no esta, sino
        // decirle el boton que SI esta ahi.
        if hasLengthMeasurement, let material = selectedMaterial,
           unidad(for: material.value) == .cuadrado, currentWidthFeet == nil, !yaAvisoFaltaAncho {
            yaAvisoFaltaAncho = true
            let que = section == "wall" ? "la pared" : (section == "ceiling" ? "el techo" : "el piso")
            let comoSeguir = (stage == .lengthDone || stage == .widthDone)
                ? "Toque Medir Ancho"
                : "Toque Terminar Recorrido y luego Medir Ancho"
            avisoEnPantalla = "⚠︎ Falta el ancho — sin él esto va como pie lineal"
            say("Ojo: \(que) se cobra por pie cuadrado y solo tiene el largo. \(comoSeguir), o Terminar otra vez si va por pie lineal.", .aviso)
            instructionLabel.text = avisoEnPantalla
            return
        }
        if hasLengthMeasurement, let material = selectedMaterial {
            bancarMedida(material)
            // La medida ya esta guardada, asi que la pantalla NO puede seguir
            // en "midiendo": sin esto el recibo quedaba encima de una etapa
            // que ya no existia, y Deshacer decia borrar un recorrido que ya
            // se habia guardado.
            stage = (materials.isEmpty && !esRecorrido) ? .measuringLength : .pickingMaterial
        }
        guard !items.isEmpty else { onFinish?(.cancelled); return }

        // Primer toque: se lee el recibo y se espera. Segundo toque: se manda.
        if !resumenPendiente {
            resumenPendiente = true
            finishButton.setTitle("✓ Sí, mandar", for: .normal)
            let recibo = resumenHablado()
            // updateUI() PRIMERO y el recibo DESPUES. Al reves - que era como
            // estaba - updateUI reescribia la instruccion una linea despues de
            // ponerla, y el recibo solo existia hablado: si no lo oyo bien, no
            // habia forma de leerlo.
            updateUI()
            reciboEnPantalla = recibo
            instructionLabel.text = recibo
            say(recibo + " Toque Sí, mandar.", .aviso)
            return
        }
        onFinish?(.measured(items: items.map {
            ARMeasureItem(length: $0.length, width: $0.width, material: $0.material,
                          companion: $0.companion, nivel: $0.nivel, cuarto: $0.cuarto,
                          seccion: $0.seccion)
        }))
    }

    @objc private func cancelTapped() {
        onFinish?(.cancelled)
    }

    // Un contador de generacion: el restaurador de 1.5 s solo repinta si
    // sigue siendo el aviso mas reciente. Sin esto, un toque fallido y luego
    // dos buenos dejaban la pantalla mostrando la instruccion VIEJA (la de
    // antes del aviso) encima de la nueva - y si el segundo aviso caia justo
    // ahi, la dejaba roja para siempre.
    private var flashGeneracion = 0
    private func flashNoSurfaceWarning() {
        flashGeneracion += 1
        let mia = flashGeneracion
        instructionLabel.text = "No se detectó superficie - acérquese o apunte a una superficie plana."
        instructionLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.flashGeneracion == mia else { return }
            // Se repinta desde el ESTADO, no desde un texto guardado hace un
            // segundo y medio: el estado es lo unico que sigue siendo cierto.
            self.instructionLabel.backgroundColor = Self.colorPastilla
            self.updateUI()
        }
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onFinish?(.cancelled)
        }
    }
}
