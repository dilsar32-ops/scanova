import Foundation
import Capacitor
import UserNotifications
import AlarmKit
import AppIntents
import ActivityKit
import SwiftUI

// Alarma para despertar el dia de la mudanza (AMG Moving), y recordatorio "En 1 hora".
//
// Contrato: scratchpad/spec-asistencia.md, seccion 3. Nombres fijos: jsName "Alarma", metodos estado / pedirPermiso /
// programar / despiertos, recordatorios con identifier "amgcal-" + clave, dias despiertos en UserDefaults "amgcal.despiertos".
//
// Como se comporta:
//  * La web manda SIEMPRE la lista completa. programar() cancela lo que este plugin haya puesto antes y ya no viene
//    (o cambio de hora), deja quieto lo que sigue igual, y pone lo nuevo. Lista vacia = cancelar todo.
//  * La alarma de verdad (suena con el telefono en silencio, pantalla completa) es AlarmKit: solo iOS 26 o mas nuevo.
//    En iOS 16-25, o si el trabajador dijo que no, solo quedan los recordatorios (notificacion local).
//  * El boton de la alarma corre YaMeLevanteIntent: guarda el dia en "amgcal.despiertos" (para que la web lo reporte a
//    la nube) y quita las otras alarmas de ese dia (las de -85, -80, -75 ya no suenan).
//  * Una alarma que esta sonando en este momento NUNCA se cancela desde aqui (aunque la web ya no la mande).
//  * Nunca rechaza por "no soportado": resuelve con soportado:false.
//  * programar() y el boton de la alarma van en FILA (AlarmaCola): la web llama programar() varias veces sin esperar
//    (al arrancar, al llegar un push, al tocar el azulejo, al volver a la app, despues de "Si voy"); si dos se enciman,
//    las dos ven el mapa vacio y ponen las alarmas dos veces, y las copias quedan sin control.
//  * Toda alarma de AlarmKit de esta app es de este plugin: la que esta viva y no esta en el mapa (huerfana) se cancela.
//  * Los recordatorios "amgcal-" se muestran aunque la app este abierta, y al tocarlos le llegan a la web como un
//    pushNotificationActionPerformed con data.abrir = "amgcal" (el mismo camino que los push).

// MARK: - Fila: un trabajo a la vez

/// Cada trabajo empieza cuando termina el anterior. Sirve igual en iOS 16-25 (recordatorios) y en 26+ (alarmas).
enum AlarmaCola {
    private static let lock = NSLock()
    private static var ultima: Task<Void, Never>?

    static func correr<T: Sendable>(_ trabajo: @escaping @Sendable () async -> T) async -> T {
        await encolar(trabajo).value
    }

    /// Sin await adentro: el candado se toma y se suelta sin salir del hilo.
    private static func encolar<T: Sendable>(_ trabajo: @escaping @Sendable () async -> T) -> Task<T, Never> {
        lock.withLock {
            let anterior = ultima
            let t = Task<T, Never> {
                await anterior?.value
                return await trabajo()
            }
            ultima = Task { _ = await t.value }
            return t
        }
    }
}

// MARK: - Lo que se guarda en el telefono

enum AlarmaAlmacen {
    static let llaveAlarmas = "amgcal.alarmas"          // clave -> ["id": UUID, "dia": "YYYY-MM-DD", "fecha": "YYYY-MM-DDTHH:MM", "titulo": ...]
    static let llaveDespiertos = "amgcal.despiertos"    // dias que falta reportar a la nube (despiertos() los borra)
    static let llaveYaDespierto = "amgcal.yaDespierto"  // dias en que ya toco el boton (NO se borra al reportar: evita volver a poner las alarmas de ese dia)
    static let prefijoRecordatorio = "amgcal-"
    /// El boton de la alarma lo avisa dentro de la app: si la web esta abierta, manda el "Ya me levanté" enseguida.
    static let avisoDespierto = Notification.Name("amgcal.despierto")

    private static let lock = NSLock()
    private static var ud: UserDefaults { .standard }

    static func alarmas() -> [String: [String: String]] {
        (ud.dictionary(forKey: llaveAlarmas) as? [String: [String: String]]) ?? [:]
    }
    static func guardarAlarmas(_ m: [String: [String: String]]) {
        ud.set(m, forKey: llaveAlarmas)
    }

    static func yaDespierto() -> Set<String> {
        Set((ud.stringArray(forKey: llaveYaDespierto)) ?? [])
    }

    /// El trabajador toco el boton de la alarma de ese dia.
    static func marcarDespierto(_ dia: String) {
        lock.lock(); defer { lock.unlock() }
        var pend = ud.stringArray(forKey: llaveDespiertos) ?? []
        if !pend.contains(dia) { pend.append(dia) }
        ud.set(pend, forKey: llaveDespiertos)
        var ya = ud.stringArray(forKey: llaveYaDespierto) ?? []
        if !ya.contains(dia) { ya.append(dia) }
        // Solo se guardan los ultimos dias (no crece para siempre).
        let hoy = AlarmaFechas.diaDeHoy()
        ya = ya.filter { $0 >= AlarmaFechas.sumarDias(hoy, -7) }
        ud.set(ya, forKey: llaveYaDespierto)
    }

    /// Devuelve y borra los dias pendientes de reportar.
    static func sacarDespiertos() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let pend = ud.stringArray(forKey: llaveDespiertos) ?? []
        ud.removeObject(forKey: llaveDespiertos)
        return pend
    }
}

enum AlarmaFechas {
    private static func formato(_ f: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.timeZone = TimeZone.current     // hora LOCAL del telefono
        d.calendar = Calendar(identifier: .gregorian)
        d.dateFormat = f
        return d
    }
    /// "YYYY-MM-DDTHH:MM" (o con :SS) en hora local -> Date.
    static func fecha(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        return formato("yyyy-MM-dd'T'HH:mm").date(from: t) ?? formato("yyyy-MM-dd'T'HH:mm:ss").date(from: t)
    }
    static func diaDeHoy() -> String { formato("yyyy-MM-dd").string(from: Date()) }
    static func sumarDias(_ dia: String, _ n: Int) -> String {
        let f = formato("yyyy-MM-dd")
        guard let d = f.date(from: dia),
              let r = Calendar(identifier: .gregorian).date(byAdding: .day, value: n, to: d) else { return dia }
        return f.string(from: r)
    }
    /// Componentes de calendario (sin zona) para UNCalendarNotificationTrigger.
    static func componentes(_ s: String) -> DateComponents? {
        guard let d = fecha(s) else { return nil }
        return Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: d)
    }
}

// MARK: - AlarmKit (iOS 26+)

@available(iOS 26.0, *)
struct AmgAlarmaDatos: AlarmMetadata {
    var dia: String
}

/// El boton de la alarma. Guarda el dia como "ya me levante" y quita las demas alarmas de ese dia.
@available(iOS 26.0, *)
struct YaMeLevanteIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Ya me levanté"
    static let openAppWhenRun: Bool = true
    // Solo lo corre la alarma: que no salga en Atajos ni en Spotlight (si no, cualquiera marca un dia como despierto).
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Día")
    var dia: String

    init() { self.dia = "" }
    init(dia: String) { self.dia = dia }

    func perform() async throws -> some IntentResult {
        let d = dia
        // La alarma es del dia de la mudanza: hoy, o manana si la mudanza empieza pasada la medianoche.
        let hoy = AlarmaFechas.diaDeHoy()
        guard !d.isEmpty, d >= hoy, d <= AlarmaFechas.sumarDias(hoy, 1) else { return .result() }
        AlarmaAlmacen.marcarDespierto(d)                        // enseguida: un programar() que venga despues ya no la pone
        await AlarmaCola.correr { AlarmaAmg.cancelarDia(d) }    // en fila: espera a un programar() que este a medias
        // Con la app ya abierta no hay "volver a la app" (visibilitychange): el plugin se lo dice a la web.
        NotificationCenter.default.post(name: AlarmaAlmacen.avisoDespierto, object: nil, userInfo: ["dia": d])
        return .result()
    }
}

@available(iOS 26.0, *)
enum AlarmaAmg {
    static func estado() -> String {
        switch AlarmManager.shared.authorizationState {
        case .authorized: return "autorizado"
        case .denied: return "negado"
        case .notDetermined: return "sin-preguntar"
        @unknown default: return "sin-preguntar"
        }
    }

    /// Cancela todas las alarmas de ese dia que puso este plugin (menos las que ya no existen).
    /// Correrla dentro de AlarmaCola, para que no se encime con un sincronizar() a medias.
    static func cancelarDia(_ dia: String) {
        var m = AlarmaAlmacen.alarmas()
        for (clave, a) in m where a["dia"] == dia {
            if let s = a["id"], let id = UUID(uuidString: s) { try? AlarmManager.shared.cancel(id: id) }
            m.removeValue(forKey: clave)
        }
        AlarmaAlmacen.guardarAlarmas(m)
    }

    struct Pedida { let clave: String; let fecha: String; let titulo: String; let dia: String; let cuando: Date }

    /// Deja programadas exactamente las alarmas pedidas (futuras). Devuelve cuantas quedan programadas.
    /// Correrla SOLO dentro de AlarmaCola (dos a la vez duplican las alarmas).
    static func sincronizar(_ pedidas: [Pedida], autorizado: Bool) async -> Int {
        let ahora = Date()
        var m = AlarmaAlmacen.alarmas()
        // Si no se pudo leer lo que hay en AlarmKit, no se toca nada: borrar del mapa "porque no esta viva" dejaria
        // alarmas sin control, y ponerlas otra vez las duplicaria.
        guard let lista = try? AlarmManager.shared.alarms else {
            NSLog("[Alarma] no se pudo leer AlarmKit; no se cambia nada")
            return m.count
        }
        var vivas: [UUID: Alarm.State] = [:]
        for a in lista { vivas[a.id] = a.state }

        // 0) Huerfanas: toda alarma de esta app es de este plugin; la que esta viva y no esta en el mapa se cancela
        //    (menos si esta sonando en este momento).
        let conocidas = Set(m.values.compactMap { $0["id"].flatMap { UUID(uuidString: $0) } })
        for a in lista where !conocidas.contains(a.id) && a.state != .alerting {
            do { try AlarmManager.shared.cancel(id: a.id); vivas.removeValue(forKey: a.id) }
            catch { NSLog("[Alarma] no se pudo quitar una huerfana: %@", String(describing: error)) }
        }

        let despiertos = AlarmaAlmacen.yaDespierto()
        var quiero: [String: Pedida] = [:]
        if autorizado {
            for p in pedidas where p.cuando > ahora.addingTimeInterval(5) && !despiertos.contains(p.dia) { quiero[p.clave] = p }
        }

        // 1) Quitar lo que ya no viene, cambio de hora/titulo, o ya no existe.
        for (clave, a) in m {
            let id = a["id"].flatMap { UUID(uuidString: $0) }
            let estado = id.flatMap { vivas[$0] }
            if estado == nil { m.removeValue(forKey: clave); continue }          // ya sono y se fue, o la borraron
            if estado == .alerting { continue }                                    // esta sonando: no se toca
            if let p = quiero[clave], p.fecha == a["fecha"], p.titulo == a["titulo"], p.dia == a["dia"] { continue }
            if let id = id { try? AlarmManager.shared.cancel(id: id) }
            m.removeValue(forKey: clave)
        }

        // 2) Poner lo que falta.
        var n = 0
        for (clave, p) in quiero {
            if let a = m[clave], a["fecha"] == p.fecha { n += 1; continue }        // ya estaba igual
            let boton = AlarmButton(text: "Ya me levanté", textColor: .white, systemImageName: "sun.max.fill")
            let alerta: AlarmPresentation.Alert
            let segundo: (any LiveActivityIntent)?
            if #available(iOS 26.1, *) {
                // Desde 26.1 el sistema ya no usa el texto del stopButton (sale su "Detener"): la palabra que dice la
                // web ("Ya me levanté") va en el segundo boton, que corre el mismo intent. Detener tambien lo corre.
                alerta = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: p.titulo),
                                                 secondaryButton: boton, secondaryButtonBehavior: .custom)
                segundo = YaMeLevanteIntent(dia: p.dia)
            } else {
                alerta = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: p.titulo), stopButton: boton)
                segundo = nil
            }
            let atributos = AlarmAttributes<AmgAlarmaDatos>(
                presentation: AlarmPresentation(alert: alerta),
                metadata: AmgAlarmaDatos(dia: p.dia),
                tintColor: .green)
            let config = AlarmManager.AlarmConfiguration<AmgAlarmaDatos>.alarm(
                schedule: .fixed(p.cuando),
                attributes: atributos,
                stopIntent: YaMeLevanteIntent(dia: p.dia),
                secondaryIntent: segundo,
                sound: .default)
            let id = UUID()
            do {
                _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
                m[clave] = ["id": id.uuidString, "dia": p.dia, "fecha": p.fecha, "titulo": p.titulo]
                n += 1
            } catch {
                NSLog("[Alarma] no se pudo programar %@: %@", clave, String(describing: error))
            }
        }
        AlarmaAlmacen.guardarAlarmas(m)
        return n
    }
}

// MARK: - El plugin

@objc(AlarmaPlugin)
public class AlarmaPlugin: CAPPlugin, CAPBridgedPlugin, NotificationHandlerProtocol {
    public let identifier = "AlarmaPlugin"
    public let jsName = "Alarma"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "estado", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pedirPermiso", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "programar", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "despiertos", returnType: CAPPluginReturnPromise)
    ]

    private var soportado: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    // MARK: Notificaciones locales (el recordatorio "En 1 hora")
    //
    // Capacitor manda al localNotificationHandler toda notificacion que no es push, y en este proyecto nadie lo ocupaba
    // (no hay @capacitor/local-notifications): el recordatorio llegaba callado con la app abierta, y al tocarlo la web
    // no se enteraba. Ahora lo atiende este plugin.

    override public func load() {
        bridge?.notificationRouter.localNotificationHandler = self
        NotificationCenter.default.addObserver(self, selector: #selector(tocoDespierto(_:)),
                                               name: AlarmaAlmacen.avisoDespierto, object: nil)
    }

    /// La web escucha "despierto" y llama despiertos() (que es quien saca el dia de la lista y lo manda a la nube).
    @objc private func tocoDespierto(_ n: Notification) {
        let dia = (n.userInfo?["dia"] as? String) ?? ""
        DispatchQueue.main.async { [weak self] in self?.notifyListeners("despierto", data: ["dia": dia]) }
    }

    public func willPresent(notification: UNNotification) -> UNNotificationPresentationOptions {
        if notification.request.identifier.hasPrefix(AlarmaAlmacen.prefijoRecordatorio) {
            return [.banner, .list, .sound]
        }
        return []
    }

    public func didReceive(response: UNNotificationResponse) {
        // El handler de push arma pushNotificationActionPerformed con notification.data = userInfo ({abrir:'amgcal'}),
        // y lo guarda hasta que la web ponga el listener (app que se abrio al tocar el aviso). La web no cambia.
        bridge?.notificationRouter.pushNotificationHandler?.didReceive(response: response)
    }

    private func estadoAlarma() -> String {
        if #available(iOS 26.0, *) { return AlarmaAmg.estado() }
        return "no-soportado"
    }

    private func estadoNotificaciones() async -> String {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "autorizado"
        case .denied: return "negado"
        case .notDetermined: return "sin-preguntar"
        @unknown default: return "sin-preguntar"
        }
    }

    private func respuestaEstado() async -> [String: Any] {
        return ["soportado": soportado, "alarma": estadoAlarma(), "notificaciones": await estadoNotificaciones()]
    }

    @objc func estado(_ call: CAPPluginCall) {
        Task {
            call.resolve(await respuestaEstado())
        }
    }

    @objc func pedirPermiso(_ call: CAPPluginCall) {
        Task {
            if #available(iOS 26.0, *) {
                if AlarmManager.shared.authorizationState == .notDetermined {
                    do { _ = try await AlarmManager.shared.requestAuthorization() }
                    catch { NSLog("[Alarma] permiso de alarma fallo: %@", String(describing: error)) }
                }
            }
            if await estadoNotificaciones() == "sin-preguntar" {
                // .badge tambien: si este es el primer cuadro que ve, que no le quite los numeritos a los push.
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            }
            call.resolve(await respuestaEstado())
        }
    }

    /// Lo que la web pide, ya leido del JS (texto y fechas: se puede pasar a la fila).
    struct AlarmaPedida: Sendable { let clave: String; let fecha: String; let titulo: String; let dia: String }
    struct RecordatorioPedido: Sendable { let clave: String; let fecha: String; let titulo: String; let cuerpo: String }

    @objc func programar(_ call: CAPPluginCall) {
        let alarmas: [AlarmaPedida] = (call.getArray("alarmas", JSObject.self) ?? []).compactMap { a in
            guard let clave = a["clave"] as? String, !clave.isEmpty, let fecha = a["fecha"] as? String else { return nil }
            return AlarmaPedida(clave: clave, fecha: fecha, titulo: (a["titulo"] as? String) ?? "Mudanza hoy",
                                dia: (a["dia"] as? String) ?? String(fecha.prefix(10)))
        }
        let recordatorios: [RecordatorioPedido] = (call.getArray("recordatorios", JSObject.self) ?? []).compactMap { r in
            guard let clave = r["clave"] as? String, !clave.isEmpty, let fecha = r["fecha"] as? String else { return nil }
            return RecordatorioPedido(clave: clave, fecha: fecha, titulo: (r["titulo"] as? String) ?? "",
                                      cuerpo: (r["cuerpo"] as? String) ?? "")
        }
        let soportado = self.soportado
        Task {
            // En fila: si la web llama dos veces seguidas, la segunda empieza cuando termina la primera.
            let (nAl, nRec) = await AlarmaCola.correr { await AlarmaPlugin.aplicar(alarmas, recordatorios) }
            call.resolve(["alarmas": nAl, "recordatorios": nRec, "soportado": soportado])
        }
    }

    /// El trabajo de programar(). Correrla SOLO dentro de AlarmaCola.
    private static func aplicar(_ alarmas: [AlarmaPedida], _ recordatorios: [RecordatorioPedido]) async -> (Int, Int) {
        let ahora = Date()

        // ---- Recordatorios (notificacion local): se quitan todos los nuestros pendientes y se ponen los que vienen.
        let centro = UNUserNotificationCenter.current()
        let pendientes = await centro.pendingNotificationRequests()
        let viejos = pendientes.map { $0.identifier }.filter { $0.hasPrefix(AlarmaAlmacen.prefijoRecordatorio) }
        if !viejos.isEmpty { centro.removePendingNotificationRequests(withIdentifiers: viejos) }
        var nRec = 0
        for r in recordatorios {
            guard let cuando = AlarmaFechas.fecha(r.fecha), cuando > ahora,
                  let comp = AlarmaFechas.componentes(r.fecha) else { continue }
            let c = UNMutableNotificationContent()
            c.title = r.titulo
            c.body = r.cuerpo
            c.sound = .default
            c.userInfo = ["abrir": "amgcal", "clave": r.clave]   // al tocarla, la web abre el calendario
            if #available(iOS 15.0, *) { c.interruptionLevel = .timeSensitive }
            let trig = UNCalendarNotificationTrigger(dateMatching: comp, repeats: false)
            let req = UNNotificationRequest(identifier: AlarmaAlmacen.prefijoRecordatorio + r.clave, content: c, trigger: trig)
            do { try await centro.add(req); nRec += 1 }
            catch { NSLog("[Alarma] recordatorio %@ fallo: %@", r.clave, String(describing: error)) }
        }

        // ---- Alarmas (AlarmKit, iOS 26+)
        var nAl = 0
        if #available(iOS 26.0, *) {
            let pedidas: [AlarmaAmg.Pedida] = alarmas.compactMap { a in
                guard let cuando = AlarmaFechas.fecha(a.fecha) else { return nil }
                return AlarmaAmg.Pedida(clave: a.clave, fecha: a.fecha, titulo: a.titulo, dia: a.dia, cuando: cuando)
            }
            let autorizado = AlarmManager.shared.authorizationState == .authorized
            nAl = await AlarmaAmg.sincronizar(pedidas, autorizado: autorizado)
        }
        return (nAl, nRec)
    }

    @objc func despiertos(_ call: CAPPluginCall) {
        call.resolve(["dias": AlarmaAlmacen.sacarDespiertos()])
    }
}
