import Foundation
import Capacitor
import SwiftUI
import Translation

// TRADUCIR (11 oct 2026): el traductor del propio iPhone (Translation, iOS 18 o mas),
// gratis y sin internet una vez bajado el idioma. Traduce al ingles el NOMBRE que la
// cuadrilla escribio a mano (la hoja del inventario va en ingles). Si el telefono no lo
// tiene, contesta "no-disponible" y la app sigue con su diccionario.
//
//   texto({ texto, de: 'es', a: 'en' }) -> { texto, motor: 'iphone' }
//   disponible()                        -> { ok, estado: installed | supported | unsupported | ios-viejo }
@objc(TraducirPlugin)
public class TraducirPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "TraducirPlugin"
    public let jsName = "Traducir"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "texto", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "disponible", returnType: CAPPluginReturnPromise)
    ]

    @objc func disponible(_ call: CAPPluginCall) {
        if #available(iOS 18.0, *) {
            Task { let st = await TraductorMotor.compartido.estado(); call.resolve(["ok": st != "unsupported", "estado": st, "motor": "iphone"]) }
        } else {
            call.resolve(["ok": false, "estado": "ios-viejo"])
        }
    }

    @objc func texto(_ call: CAPPluginCall) {
        guard let texto = call.getString("texto")?.trimmingCharacters(in: .whitespacesAndNewlines), !texto.isEmpty, texto.count <= 200 else {
            call.reject("Falta el texto", "texto"); return
        }
        if #available(iOS 18.0, *) {
            DispatchQueue.main.async { [weak self] in
                TraductorMotor.compartido.montar(en: self?.bridge?.viewController)
                TraductorMotor.compartido.traducir(texto) { r in
                    switch r {
                    case .success(let s): call.resolve(["texto": s, "motor": "iphone"])
                    case .failure(let e): call.reject("No se pudo traducir: " + e.localizedDescription, "traduccion")
                    }
                }
            }
        } else {
            call.reject("Este iPhone no trae el traductor (necesita iOS 18)", "no-disponible")
        }
    }
}

// La sesion del traductor vive dentro de una vista de SwiftUI (asi lo pide Apple): se
// monta UNA vez, invisible, sobre la pantalla de la app, y atiende los pedidos en fila.
@available(iOS 18.0, *)
final class TraductorMotor: ObservableObject {
    static let compartido = TraductorMotor()
    struct Pedido { let texto: String; let listo: (Result<String, Error>) -> Void }
    @Published var config: TranslationSession.Configuration? = nil
    private var host: UIHostingController<TraductorVista>?
    private var continuacion: AsyncStream<Pedido>.Continuation?
    let stream: AsyncStream<Pedido>

    init() {
        var cont: AsyncStream<Pedido>.Continuation?
        stream = AsyncStream { c in cont = c }
        continuacion = cont
    }

    func estado() async -> String {
        let st = await LanguageAvailability().status(from: Locale.Language(identifier: "es"), to: Locale.Language(identifier: "en"))
        switch st {
        case .installed: return "installed"
        case .supported: return "supported"
        default: return "unsupported"
        }
    }

    func montar(en vc: UIViewController?) {
        guard host == nil, let vc = vc else { return }
        let h = UIHostingController(rootView: TraductorVista(motor: self))
        h.view.backgroundColor = .clear
        h.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        h.view.alpha = 0.02
        h.view.isUserInteractionEnabled = false
        vc.addChild(h)
        vc.view.addSubview(h.view)
        h.didMove(toParent: vc)
        host = h
        if config == nil {
            config = TranslationSession.Configuration(source: Locale.Language(identifier: "es"), target: Locale.Language(identifier: "en"))
        }
    }

    func traducir(_ texto: String, _ listo: @escaping (Result<String, Error>) -> Void) {
        continuacion?.yield(Pedido(texto: texto, listo: listo))
    }
}

@available(iOS 18.0, *)
struct TraductorVista: View {
    @ObservedObject var motor: TraductorMotor
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(motor.config) { session in
                // Si el idioma no esta bajado, iOS lo ofrece aqui (una vez).
                do { try await session.prepareTranslation() } catch { }
                for await pedido in motor.stream {
                    do {
                        let r = try await session.translate(pedido.texto)
                        pedido.listo(.success(r.targetText))
                    } catch {
                        pedido.listo(.failure(error))
                    }
                }
            }
    }
}
