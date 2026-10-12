import Foundation
import Capacitor

// ACTUALIZAR EL APP SIN CABLE (la parte web).
//
// Su pregunta: "por que no se pueden actualizar como las otras apps, por que
// tengo que insertar el app cada vez en su telefono".
//
// LO QUE SE PUEDE Y LO QUE NO, sin adornos:
//  * La parte WEB (www/index.html: pantallas, reportes, horas, invoices,
//    planos, finanzas) SI se puede bajar. Es lo que hace este archivo.
//  * El codigo NATIVO (camara, escaner LiDAR, AR, voz, ubicacion) NO. iOS solo
//    corre codigo firmado con el certificado del desarrollador y lo verifica al
//    abrir. Ningun app de iPhone puede bajar y correr codigo nativo nuevo.
//    Para eso esta TestFlight, que es otra cosa aparte de este archivo.
//
// COMO FUNCIONA, apoyado en lo que Capacitor 6 ya trae:
//  1. Se baja index.html del sitio y se arma una "copia" completa en
//     Library/NoCloud/ionic_built_snapshots/<version>.
//  2. Se guarda esa ruta en KeyValueStore["serverBasePath"].
//  3. Capacitor la carga SOLA en el siguiente arranque en frio
//     (CAPBridgeViewController.instanceDescriptor lo hace por su cuenta).
//  4. Si se instala un binario nuevo con cable, Capacitor detecta el cambio de
//     version (isNewBinary) y BORRA serverBasePath solo: gana el cable.
//     ESO DEPENDE DE QUE CFBundleVersion CAMBIE EN CADA COMPILACION. Si se
//     queda fijo, una copia bajada vieja taparia una instalacion fresca. Por
//     eso se compila pasando CURRENT_PROJECT_VERSION con la fecha.
//     PERO ESO SOLO AGUANTA EL PRIMER ARRANQUE. Capacitor tira la copia al
//     instalar, y seis segundos despues ESTE archivo se bajaba otra vez la del
//     sitio - que despues de un cable casi siempre es MAS VIEJA. El 7 de
//     octubre de 2026 su telefono estaba sirviendo 2026-10-06-MQ con el binario
//     en NC: probo un cambio dos veces y no lo vio. Por eso ahora hay dos rejas
//     propias, `esMasNueva`: una al arrancar (tira la copia que no le gana al
//     binario) y otra al revisar (no se baja nada mas viejo que lo que corre).
//
// NO se cambia la web a media sesion. Se deja lista y entra al siguiente
// arranque: cambiarla encima de alguien que esta llenando un reporte le
// borraria lo escrito.
enum Actualizador {

    static let sitio = "https://dilsar32-ops.github.io/amg-reportes"

    // LA REJA. Se sube A MANO cada vez que cambia codigo Swift.
    // Un paquete web que pida mas que esto NO se instala solo: necesita cable
    // (o TestFlight). Sin esta reja, una version web nueva llamaria a un metodo
    // nativo que el telefono todavia no tiene y reventaria en el trabajo.
    static let NATIVO = "2026-10-11"   // reconocedor de objetos + traductor (Clasificar, Traducir); publicado por enlace (ios/distribucion)

    // Un index.html de verdad pesa ~2.3 MB. Cualquier cosa por debajo de esto
    // es una pagina de error, un corte a media bajada o un 404 disfrazado.
    private static let MINIMO_BYTES = 400_000

    private static let K_BASE      = "serverBasePath"
    private static let K_EN_PRUEBA = "amgSnapshotEnPrueba"
    private static let K_ESPERA    = "amgEsperandoCable"
    private static let K_ULTIMA    = "amgUltimaRevision"
    // La version que se bajo y NO logro abrir. Sin esto, el telefono la
    // vuelve a bajar en cada arranque: descarta, baja, descarta, baja. Se
    // queda anotada hasta que salga una MAS NUEVA, que es la unica senal de
    // que alla arreglaron lo que estaba mal.
    private static let K_MALA      = "amgVersionMala"

    struct Estado {
        var instalada: String      // la que se esta viendo ahora
        var lista: String?         // bajada y esperando que cierren el app
        var esperandoCable: String? // hay una nueva pero pide nativo mas nuevo
        var revisando: Bool
    }

    private static var revisando = false
    private static let cola = DispatchQueue(label: "amg.actualizador")

    // ---------- rutas ----------
    private static var raizSnapshots: URL? {
        guard let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        else { return nil }
        return lib.appendingPathComponent("NoCloud").appendingPathComponent("ionic_built_snapshots")
    }

    /// La carpeta web que trae el binario firmado. De aqui salen SIEMPRE los
    /// archivos que no se bajan (jspdf, html2canvas, manual, iconos): asi lo
    /// unico que viaja por internet es el index.html.
    private static var carpetaDelBinario: URL? {
        // Igual que lo busca Capacitor. Con el respaldo por si un dia el
        // bundle cambia de forma: sin esta carpeta no se puede armar nada.
        if let u = Bundle.main.url(forResource: "public", withExtension: nil) { return u }
        if let r = Bundle.main.resourceURL {
            let u = r.appendingPathComponent("public", isDirectory: true)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    static func versionDeArchivo(_ html: String) -> String? {
        marca(html, "APP_BUILD")
    }
    static func nativoQuePide(_ html: String) -> String? {
        marca(html, "NATIVE_MIN")
    }
    // ---------- cual sello es mas nuevo ----------
    //
    // ESTO NO SE PUEDE COMPARAR COMO TEXTO A SECAS, y por ahi se colo el
    // problema. Un sello es "2026-10-07-NC": la fecha si se ordena sola en
    // texto, pero la letra NO - despues de la Z viene la AA, y en orden
    // alfabetico "AA" va ANTES que "Z". El 30 de agosto hubo Z, AA y AB el
    // mismo dia.
    // Se compara como las columnas de una hoja de calculo: primero por LARGO
    // de la letra, y con el mismo largo, alfabeticamente.
    private static func partes(_ v: String) -> (fecha: String, letra: String)? {
        let p = v.split(separator: "-", maxSplits: 3, omittingEmptySubsequences: false)
        guard p.count >= 3, p[0].count == 4, p[1].count == 2, p[2].count == 2,
              p[0].allSatisfy({ $0.isNumber }), p[1].allSatisfy({ $0.isNumber }),
              p[2].allSatisfy({ $0.isNumber })
        else { return nil }
        return ("\(p[0])-\(p[1])-\(p[2])", p.count > 3 ? String(p[3]) : "")
    }

    /// true si `a` es mas nueva que `b`.
    /// Si alguno no tiene forma de sello, devuelve true: un formato que
    /// cambie en el futuro NO debe congelar las actualizaciones de toda la
    /// flota en silencio. Queda anotado en el log.
    static func esMasNueva(_ a: String, que b: String) -> Bool {
        guard let A = partes(a), let B = partes(b) else {
            CAPLog.print("[Actualizador] sello sin forma de fecha (\(a) / \(b)): no se puede comparar.")
            return true
        }
        if A.fecha != B.fecha { return A.fecha > B.fecha }
        if A.letra.count != B.letra.count { return A.letra.count > B.letra.count }
        return A.letra > B.letra
    }

    private static func marca(_ html: String, _ nombre: String) -> String? {
        // Busca:  var APP_BUILD = '2026-09-28-X';
        guard let r = html.range(of: "\(nombre)\\s*=\\s*'([^']+)'", options: .regularExpression)
        else { return nil }
        let trozo = String(html[r])
        guard let c = trozo.range(of: "'([^']+)'", options: .regularExpression) else { return nil }
        return String(trozo[c]).replacingOccurrences(of: "'", with: "")
    }

    // ---------- lo que se esta viendo ahora ----------
    static func instalada(raizActual: URL?) -> String {
        guard let raiz = raizActual ?? carpetaDelBinario,
              let html = try? String(contentsOf: raiz.appendingPathComponent("index.html"), encoding: .utf8)
        else { return "?" }
        return versionDeArchivo(html) ?? "?"
    }

    // ---------- la red de seguridad ----------
    // Si el arranque anterior cargo una copia bajada y la web NUNCA confirmo
    // que abrio bien, esa copia se descarta y se vuelve a la del binario. Sin
    // esto, un paquete web malo dejaria el telefono muerto en el trabajo, lejos
    // de la Mac, sin forma de arreglarlo.
    // OJO CON EL ORDEN, que ya me equivoque una vez: la marca "a prueba" se
    // pone cuando la copia SE VA A CARGAR, no cuando se baja. Marcarla al
    // bajarla hacia que el arranque siguiente la viera "sin confirmar" y la
    // tirara antes de estrenarla: la actualizacion no entraba NUNCA.
    static func revisarArranqueAnterior() {
        let st = KeyValueStore.standard

        // 0. EL CABLE GANA. Encontrado el 7 de octubre de 2026, y era real: su
        //    telefono estaba sirviendo la copia bajada 2026-10-06-MQ aunque el
        //    binario recien instalado por cable traia la NC. Probo un cambio
        //    dos veces, no lo vio, y parecia que el cambio no se habia hecho.
        //
        //    Como pasa: se compila e instala por cable (el binario queda
        //    adelante del sitio), y seis segundos despues `revisar` ve que el
        //    sitio dice algo DISTINTO a lo que corre... y se baja lo viejo.
        //    `revisar` solo preguntaba si era distinto, nunca si era mas nuevo.
        //
        //    Aqui se repara el telefono que ya quedo asi: si la copia apuntada
        //    no es mas nueva que la web que trae el binario firmado, se tira.
        //    Tiene que ser ANTES de que Capacitor lea serverBasePath, o sea
        //    aqui dentro, en instanceDescriptor().
        if let base = st[K_BASE, as: String.self], !base.isEmpty {
            let copia   = URL(fileURLWithPath: base).lastPathComponent
            let binario = instalada(raizActual: nil)      // la del binario firmado
            if binario != "?" && !esMasNueva(copia, que: binario) {
                CAPLog.print("[Actualizador] la copia \(copia) no es mas nueva que la del cable (\(binario)). Se tira.")
                st[K_BASE] = nil as String?
                st[K_EN_PRUEBA] = nil as String?
                // No se anota como MALA: no esta rota, solo es vieja. Marcarla
                // la bloquearia para siempre aunque despues fuera la buena.
                if let raiz = raizSnapshots {
                    try? FileManager.default.removeItem(at: raiz.appendingPathComponent(copia))
                }
                return
            }
        }

        // 1. El arranque anterior cargo una copia y la web nunca confirmo que
        //    abrio bien. Se descarta y se vuelve a la del binario.
        if let enPrueba = st[K_EN_PRUEBA, as: String.self], !enPrueba.isEmpty {
            CAPLog.print("[Actualizador] la copia \(enPrueba) nunca confirmo que abrio. Se descarta.")
            st[K_BASE] = nil as String?
            st[K_EN_PRUEBA] = nil as String?
            st[K_MALA] = enPrueba          // y no se vuelve a intentar con esa
            return
        }

        // 2. Hay una copia apuntada y ESTE arranque la va a cargar. Se marca a
        //    prueba: si el app no confirma, el siguiente arranque la tira.
        if let base = st[K_BASE, as: String.self], !base.isEmpty {
            let v = URL(fileURLWithPath: base).lastPathComponent
            st[K_EN_PRUEBA] = v
            CAPLog.print("[Actualizador] estrenando la copia \(v).")
        }
    }

    /// La llama la web cuando ya pinto la primera pantalla.
    static func confirmarQueAbrio() {
        KeyValueStore.standard[K_EN_PRUEBA] = nil as String?
    }

    // ---------- revisar y bajar ----------
    static func revisar(raizActual: URL?, forzado: Bool, listo: @escaping (String) -> Void) {
        cola.async {
            guard !revisando else { listo("ocupado"); return }

            let st = KeyValueStore.standard
            if !forzado, let ult = st[K_ULTIMA, as: Double.self],
               Date().timeIntervalSince1970 - ult < 3600 {
                listo("hace rato"); return
            }

            revisando = true
            defer { revisando = false }
            st[K_ULTIMA] = Date().timeIntervalSince1970

            let aqui = instalada(raizActual: raizActual)
            let cb = String(Int(Date().timeIntervalSince1970))

            guard let vURL = URL(string: "\(sitio)/version.txt?cb=\(cb)"),
                  let alla = bajarTexto(vURL, limite: 200), !alla.isEmpty else {
                listo("sin internet"); return
            }
            if alla == aqui { st[K_ESPERA] = nil as String?; listo("al dia"); return }

            // Y LA OTRA MITAD: nunca bajar una web MAS VIEJA que la que ya
            // corre. Despues de instalar por cable, el telefono va por delante
            // del sitio hasta que se publique; sin esta reja se bajaba solo
            // la version vieja y tapaba la instalacion fresca.
            if !esMasNueva(alla, que: aqui) {
                st[K_ESPERA] = nil as String?
                CAPLog.print("[Actualizador] el sitio tiene \(alla) y este telefono ya trae \(aqui), que es mas nueva. No se baja.")
                listo("el telefono esta mas nuevo"); return
            }

            // Esa version ya se bajo una vez y no abrio. No se vuelve a
            // intentar: el telefono se queda con la del binario, que si
            // funciona, hasta que publiquen una mas nueva.
            if let mala = st[K_MALA, as: String.self], mala == alla {
                CAPLog.print("[Actualizador] \(alla) ya fallo antes. No se reintenta.")
                listo("ya fallo antes"); return
            }

            guard let hURL = URL(string: "\(sitio)/index.html?cb=\(cb)"),
                  let html = bajarTexto(hURL, limite: 40_000_000) else {
                listo("no se pudo bajar"); return
            }

            // ---- que lo bajado sea de verdad lo que dice ser ----
            guard html.utf8.count >= MINIMO_BYTES else { listo("llego cortado"); return }
            guard html.contains("</html>") else { listo("llego incompleto"); return }
            guard let vDentro = versionDeArchivo(html), vDentro == alla else {
                listo("no cuadra la version"); return
            }

            // ---- LA REJA: nunca instalar web que pida nativo mas nuevo ----
            let pide = nativoQuePide(html) ?? "0000-00-00"
            if pide > NATIVO {
                st[K_ESPERA] = alla
                CAPLog.print("[Actualizador] \(alla) pide nativo \(pide) y este app tiene \(NATIVO). Necesita cable.")
                listo("necesita cable"); return
            }

            guard armarCopia(version: alla, html: html) else { listo("no se pudo guardar"); return }

            st[K_ESPERA] = nil as String?
            st[K_MALA] = nil as String?    // llego una nueva: la vieja mala ya no importa
            CAPLog.print("[Actualizador] \(alla) lista. Entra al cerrar y abrir el app.")
            listo("lista")
        }
    }

    private static func bajarTexto(_ u: URL, limite: Int) -> String? {
        var pet = URLRequest(url: u)
        pet.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        pet.timeoutInterval = 40
        var salida: String?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: pet) { d, r, _ in
            defer { sem.signal() }
            guard let d = d, d.count <= limite,
                  (r as? HTTPURLResponse)?.statusCode == 200 else { return }
            salida = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.resume()
        _ = sem.wait(timeout: .now() + 60)
        return salida
    }

    /// Arma la carpeta completa: TODO sale del binario firmado y solo el
    /// index.html viene de internet. Se escribe en una carpeta aparte y se
    /// mueve al final, para que un corte a media copia no deje una carpeta
    /// rota ya apuntada.
    private static func armarCopia(version: String, html: String) -> Bool {
        let fm = FileManager.default
        guard let raiz = raizSnapshots, let origen = carpetaDelBinario else { return false }
        let destino = raiz.appendingPathComponent(version)
        let temporal = raiz.appendingPathComponent("__armando__")
        do {
            try? fm.removeItem(at: temporal)
            try fm.createDirectory(at: raiz, withIntermediateDirectories: true)
            try fm.copyItem(at: origen, to: temporal)
            let idx = temporal.appendingPathComponent("index.html")
            try? fm.removeItem(at: idx)
            try html.write(to: idx, atomically: true, encoding: .utf8)

            try? fm.removeItem(at: destino)
            try fm.moveItem(at: temporal, to: destino)

            // Solo se guarda la ultima. Cada copia pesa ~10 MB.
            if let viejas = try? fm.contentsOfDirectory(atPath: raiz.path) {
                for v in viejas where v != version {
                    try? fm.removeItem(at: raiz.appendingPathComponent(v))
                }
            }
            KeyValueStore.standard[K_BASE] = destino.path
            return true
        } catch {
            CAPLog.print("[Actualizador] no se pudo armar la copia: \(error)")
            try? fm.removeItem(at: temporal)
            return false
        }
    }

    static func estado(raizActual: URL?) -> Estado {
        let st = KeyValueStore.standard
        var lista: String?
        if let base = st[K_BASE, as: String.self], !base.isEmpty {
            let v = URL(fileURLWithPath: base).lastPathComponent
            if v != instalada(raizActual: raizActual) { lista = v }
        }
        return Estado(instalada: instalada(raizActual: raizActual),
                      lista: lista,
                      esperandoCable: st[K_ESPERA, as: String.self],
                      revisando: revisando)
    }
}

// ---------------------------------------------------------------------------

@objc(ActualizadorPlugin)
public class ActualizadorPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "ActualizadorPlugin"
    public let jsName = "Actualizador"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "estado", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "revisar", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "abrioBien", returnType: CAPPluginReturnPromise)
    ]

    private var raizActual: URL? { bridge?.config.appLocation }

    @objc func estado(_ call: CAPPluginCall) {
        let e = Actualizador.estado(raizActual: raizActual)
        call.resolve([
            "instalada": e.instalada,
            "nativo": Actualizador.NATIVO,
            "lista": e.lista as Any,
            "esperandoCable": e.esperandoCable as Any,
            "revisando": e.revisando
        ])
    }

    @objc func revisar(_ call: CAPPluginCall) {
        Actualizador.revisar(raizActual: raizActual,
                             forzado: call.getBool("forzado") ?? false) { r in
            call.resolve(["resultado": r])
        }
    }

    /// La web avisa que pinto bien. Si nunca llega, el arranque siguiente
    /// descarta la copia bajada y vuelve a la del binario.
    @objc func abrioBien(_ call: CAPPluginCall) {
        Actualizador.confirmarQueAbrio()
        call.resolve()
    }
}
