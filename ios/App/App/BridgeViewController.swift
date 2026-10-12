import UIKit
import Capacitor
import AuthenticationServices

// The stock CAPBridgeViewController only auto-registers plugins that ship
// as separate npm/CocoaPods packages - it reads their class names out of
// capacitor.config.json's packageClassList, which `npx cap sync` builds by
// scanning node_modules. ARMeasurePlugin lives directly in this app target
// instead (there was no need for a whole separate package for one
// feature), so nothing ever adds it to that list - it has to be
// registered here by hand, in the one hook Capacitor gives local plugins.
class BridgeViewController: CAPBridgeViewController {
    // LA RED DE SEGURIDAD, y tiene que correr AQUI.
    // instanceDescriptor() es lo primero que lee serverBasePath para decidir
    // de que carpeta carga la web. Si el arranque anterior uso una copia
    // bajada y la web nunca confirmo que abrio bien, hay que descartarla
    // ANTES de que Capacitor la lea. En el AppDelegate seria tarde.
    override open func instanceDescriptor() -> InstanceDescriptor {
        // Scanova360: la web se carga en vivo desde scanova360.com (server.url); no hay copias bajadas.
        return super.instanceDescriptor()
    }

    // LA PANTALLA COMPLETA, HASTA LAS ESQUINAS REDONDAS (8 oct 2026).
    //
    // Su foto: "aun no se llena bien en el telefono; el shape del telefono es
    // curveado y la franja sale recta; la app debe ajustarse al estilo de la
    // pantalla". Sin viewport-fit=cover iOS encierra la vista web DENTRO del
    // area segura: la pagina no puede pintar la franja del indicador de abajo
    // ni meterse bajo las esquinas, y ahi se ve el fondo de la vista nativa,
    // con bordes rectos contra una pantalla curva.
    //
    // Esto YA SE INTENTO una vez y se dio marcha atras: "destapa una franja
    // blanca abajo, de la vista NATIVA, que no se puede tapar desde el CSS".
    // Era cierto, y la nota tenia razon en no despacharlo a ciegas. Lo que
    // faltaba estaba de ESTE lado: la vista web y su scroll nacen BLANCOS.
    // Aqui se pintan de negro -- el mismo #000 que usa la app entera, asi que
    // aunque asomara un pixel no habria costura que ver -- y se le quita al
    // scroll su ajuste automatico, porque con viewport-fit=cover los margenes
    // los pone el CSS con env(safe-area-inset-*) y si no se contarian dos
    // veces.
    override open func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0x19/255.0, green: 0x2d/255.0, blue: 0x43/255.0, alpha: 1)
        webView?.backgroundColor = UIColor(red: 0x19/255.0, green: 0x2d/255.0, blue: 0x43/255.0, alpha: 1)
        webView?.isOpaque = true
        webView?.scrollView.backgroundColor = UIColor(red: 0x19/255.0, green: 0x2d/255.0, blue: 0x43/255.0, alpha: 1)
        webView?.scrollView.contentInsetAdjustmentBehavior = .never
    }

    override open func capacitorDidLoad() {
        super.capacitorDidLoad()
        bridge?.registerPluginInstance(ARMeasurePlugin())
        bridge?.registerPluginInstance(RoomPlanPlugin())
        bridge?.registerPluginInstance(LocationPlugin())
        bridge?.registerPluginInstance(ClasificarPlugin())
        bridge?.registerPluginInstance(TraducirPlugin())    // traducir al ingles un nombre escrito a mano (Contenidos), con el traductor del iPhone  // nombres de objetos con el reconocedor del iPhone (Contenidos), gratis y sin internet
        bridge?.registerPluginInstance(TextoPlugin())   // leer nombre y direccion de una foto (Clientes)
        bridge?.registerPluginInstance(SubirPlugin())   // subir fotos a CompanyCam (md5 + PUT)
        bridge?.registerPluginInstance(AlarmaPlugin())  // alarma para despertar el dia de la mudanza (AMG)
        bridge?.registerPluginInstance(AsistenteVozPlugin())  // microfono + nivel para el asistente global
        bridge?.registerPluginInstance(CerebroVozPlugin())    // el modelo del telefono que interpreta lo que oye
        bridge?.registerPluginInstance(MensajePlugin())      // mandar el invoice por Mensajes, ya dirigido al cliente
        bridge?.registerPluginInstance(EntrarWebPlugin())    // Scanova360: Continuar con Google en la hoja segura de iOS

        // Scanova360: sin actualizador (la web vive en el sitio).
    }
}

// CONTINUAR CON GOOGLE en el aparato (Scanova360, 12 oct 2026).
// Google no deja iniciar sesion dentro de una vista web metida en una app (error "disallowed_useragent").
// La salida que Apple da para esto es ASWebAuthenticationSession: una hoja segura de Safari que comparte
// las cuentas de Google del telefono y regresa a la app por scanova360://auth con la sesion en el fragmento.
@objc(EntrarWebPlugin)
public class EntrarWebPlugin: CAPPlugin, CAPBridgedPlugin, ASWebAuthenticationPresentationContextProviding {
    public let identifier = "EntrarWebPlugin"
    public let jsName = "EntrarWeb"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "abrir", returnType: CAPPluginReturnPromise)
    ]
    private var sesion: ASWebAuthenticationSession?

    @objc func abrir(_ call: CAPPluginCall) {
        guard let texto = call.getString("url"), let url = URL(string: texto),
              let esquema = call.getString("esquema"), !esquema.isEmpty else {
            call.reject("falta la url o el esquema"); return
        }
        DispatchQueue.main.async {
            let ses = ASWebAuthenticationSession(url: url, callbackURLScheme: esquema) { [weak self] vuelta, error in
                self?.sesion = nil
                if let vuelta = vuelta { call.resolve(["url": vuelta.absoluteString]); return }
                if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { call.resolve(["cancelado": true]); return }
                call.reject(error?.localizedDescription ?? "no se pudo entrar")
            }
            ses.presentationContextProvider = self
            ses.prefersEphemeralWebBrowserSession = false
            self.sesion = ses
            if !ses.start() { self.sesion = nil; call.reject("no se pudo abrir la hoja de Google") }
        }
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return bridge?.viewController?.view.window ?? ASPresentationAnchor()
    }
}
