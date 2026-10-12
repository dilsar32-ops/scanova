import Foundation
import Capacitor
import CoreLocation
import MapKit
import Vision
import CryptoKit

// Turns "where am I standing" into a street address the crew can accept with
// one tap. Uses Apple's own CLGeocoder: no API key, no third-party service,
// and the coordinates never leave Apple's stack.
//
// Honesty notes that shape this whole file:
//  * A reverse geocode is Apple's BEST GUESS for a coordinate. On a street of
//    townhouses it can name the neighbour. So this plugin only ever RETURNS a
//    suggestion - the web side shows it and the tech taps to accept. Nothing
//    here writes into a form by itself.
//  * CLGeocoder needs the network. On a job site with no signal it will fail,
//    and it says so plainly instead of returning something made up.
//  * `accuracyM` is handed back so the UI can warn when the fix is poor.
@objc(LocationPlugin)
public class LocationPlugin: CAPPlugin, CAPBridgedPlugin, CLLocationManagerDelegate, MKLocalSearchCompleterDelegate {
    public let identifier = "LocationPlugin"
    public let jsName = "Location"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "suggestAddress", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "searchAddress", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isAvailable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "geocode", returnType: CAPPluginReturnPromise)
    ]

    // ---- Direcciones mientras escriben: MKLocalSearchCompleter (Apple Maps). Sin llave, sin servicio de terceros.
    // Se sesga a la ubicacion del telefono (la ultima conocida) para que salgan primero las de por aqui.
    // Solo devuelve sugerencias: el que escribe toca una para aceptarla; nada se llena solo.
    private lazy var completer: MKLocalSearchCompleter = {
        let c = MKLocalSearchCompleter()
        c.delegate = self
        c.resultTypes = .address
        c.pointOfInterestFilter = .excludingAll
        return c
    }()
    private var searchCall: CAPPluginCall?
    private var searchTimeout: DispatchWorkItem?

    @objc func searchAddress(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let q = (call.getString("query") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // Una busqueda nueva reemplaza a la anterior: la vieja se cierra vacia y marcada, el JS la ignora.
            if let old = self.searchCall { old.resolve(["results": [], "superseded": true]); self.searchCall = nil }
            self.searchTimeout?.cancel(); self.searchTimeout = nil
            guard q.count >= 3 else { call.resolve(["results": []]); return }
            var center: CLLocationCoordinate2D? = nil
            if let lat = call.getDouble("lat"), let lng = call.getDouble("lng") { center = CLLocationCoordinate2D(latitude: lat, longitude: lng) }
            else if let loc = self.manager.location { center = loc.coordinate }
            if let c = center { self.completer.region = MKCoordinateRegion(center: c, latitudinalMeters: 80_000, longitudinalMeters: 80_000) }
            if self.completer.queryFragment == q && !self.completer.results.isEmpty {
                call.resolve(["results": self.completer.results.prefix(12).map { ["title": $0.title, "subtitle": $0.subtitle] }])
                return
            }
            self.searchCall = call
            self.completer.queryFragment = q
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, let c = self.searchCall else { return }
                self.searchCall = nil
                c.resolve(["results": [], "timeout": true])
            }
            self.searchTimeout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
        }
    }
    public func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        searchTimeout?.cancel(); searchTimeout = nil
        guard let c = searchCall else { return }
        searchCall = nil
        c.resolve(["results": completer.results.prefix(12).map { ["title": $0.title, "subtitle": $0.subtitle] }])
    }
    public func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        searchTimeout?.cancel(); searchTimeout = nil
        guard let c = searchCall else { return }
        searchCall = nil
        c.resolve(["results": [], "error": error.localizedDescription])
    }

    private let manager = CLLocationManager()
    private var pending: CAPPluginCall?
    private var timeoutWork: DispatchWorkItem?

    // ---- De una direccion escrita a su punto en el mapa (Visitas: "los clientes mas cerca primero").
    // Es la misma CLGeocoder de Apple, al reves: no hace falta llave ni servicio de terceros, pero SI
    // necesita senal. Apple limita cuantas se piden seguidas, asi que la web pide de una en una, con
    // pausa, y guarda el resultado: cada direccion se busca UNA vez y despues ya no.
    private let geoCoder = CLGeocoder()
    @objc func geocode(_ call: CAPPluginCall) {
        let direccion = (call.getString("address") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard direccion.count >= 5 else { call.reject("Dirección muy corta.", "corta"); return }
        DispatchQueue.main.async {
            if self.geoCoder.isGeocoding { self.geoCoder.cancelGeocode() }
            self.geoCoder.geocodeAddressString(direccion) { marks, err in
                if let e = err as NSError? {
                    // Sin senal, o Apple pidiendo calma: la web lo reintenta mas tarde, no se inventa nada.
                    let codigo = (e.domain == kCLErrorDomain && e.code == CLError.network.rawValue) ? "red" : "nada"
                    call.reject(e.localizedDescription, codigo)
                    return
                }
                guard let c = marks?.first?.location?.coordinate else {
                    call.reject("No se encontró esa dirección.", "nada")
                    return
                }
                call.resolve(["lat": c.latitude, "lng": c.longitude])
            }
        }
    }

    @objc func isAvailable(_ call: CAPPluginCall) {
        call.resolve(["value": CLLocationManager.locationServicesEnabled()])
    }

    @objc func suggestAddress(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if self.pending != nil {
                call.reject("Ya se está buscando la dirección.", "busy")
                return
            }
            guard CLLocationManager.locationServicesEnabled() else {
                call.reject("El GPS está apagado en este teléfono.", "gps_off")
                return
            }
            self.pending = call
            self.manager.delegate = self
            self.manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters

            // A fix can simply never arrive (indoors, basement, airplane mode).
            // Never leave the JS promise hanging - the button would spin forever.
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, let c = self.pending else { return }
                self.pending = nil
                self.manager.stopUpdatingLocation()
                c.reject("No se pudo encontrar la ubicación. Pruebe afuera del edificio.", "timeout")
            }
            self.timeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)

            let status = self.manager.authorizationStatus
            switch status {
            case .notDetermined:
                self.manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                self.finish(reject: "El permiso de ubicación está apagado. Actívelo en Ajustes.", code: "denied")
            default:
                self.manager.requestLocation()
            }
        }
    }

    private func finish(reject message: String, code: String) {
        timeoutWork?.cancel(); timeoutWork = nil
        manager.stopUpdatingLocation()
        guard let c = pending else { return }
        pending = nil
        c.reject(message, code)
    }

    private func finish(resolve payload: [String: Any]) {
        timeoutWork?.cancel(); timeoutWork = nil
        manager.stopUpdatingLocation()
        guard let c = pending else { return }
        pending = nil
        c.resolve(payload)
    }

    public func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        guard pending != nil else { return }
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: m.requestLocation()
        case .denied, .restricted:
            finish(reject: "El permiso de ubicación está apagado. Actívelo en Ajustes.", code: "denied")
        default: break   // still .notDetermined - the prompt is on screen
        }
    }

    public func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        finish(reject: "No se pudo encontrar la ubicación. Pruebe afuera del edificio.", code: "timeout")
    }

    public func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else {
            finish(reject: "No se pudo encontrar la ubicación.", code: "timeout")
            return
        }
        CLGeocoder().reverseGeocodeLocation(loc) { [weak self] marks, err in
            guard let self = self else { return }
            guard let p = marks?.first else {
                // A coordinate with no address is a real answer, not a crash:
                // hand back the coordinate so the tech at least has something.
                self.finish(resolve: [
                    "address": "",
                    "accuracyM": loc.horizontalAccuracy,
                    "lat": loc.coordinate.latitude,
                    "lng": loc.coordinate.longitude,
                    "note": "No se encontró una dirección para este punto."
                ])
                return
            }
            // "123 Main St, Vienna, VA" - the shape the crew already types.
            let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
            let line = [street.isEmpty ? nil : street, p.locality, p.administrativeArea]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            self.finish(resolve: [
                "address": line,
                "accuracyM": loc.horizontalAccuracy,
                "lat": loc.coordinate.latitude,
                "lng": loc.coordinate.longitude,
                "postal": p.postalCode ?? ""
            ])
        }
    }
}

// ============ LEER EL TEXTO DE UNA FOTO (clientes) ============
//
// Su pedido del 14 de septiembre de 2026, con una captura de CompanyCam:
// escribir el nombre y la direccion del cliente a mano en el plano y en las
// medidas toma tiempo y a veces sale mal. Se sube la captura, se lee el texto
// y la app saca el nombre y la direccion.
//
// Todo en el telefono, con Vision de Apple: la foto no sale del telefono ni se
// guarda; solo se devuelven las lineas de texto con su posicion. Decidir que
// linea es el nombre y cual la direccion lo hace la web (clienteDeLineas), y
// la persona lo revisa antes de guardar.
//
// Va en este archivo (y no en uno nuevo) para no tocar el proyecto de Xcode.

@objc(TextoPlugin)
public class TextoPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "TextoPlugin"
    public let jsName = "Texto"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "reconocer", returnType: CAPPluginReturnPromise)
    ]

    @objc func reconocer(_ call: CAPPluginCall) {
        var b64 = call.getString("base64") ?? ""
        if let coma = b64.firstIndex(of: ","), b64.hasPrefix("data:") { b64 = String(b64[b64.index(after: coma)...]) }
        guard let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
              let imagen = UIImage(data: data), let cg = imagen.cgImage else {
            call.reject("No se pudo abrir la foto.", "foto_invalida")
            return
        }
        let orientacion = TextoPlugin.orientacion(imagen.imageOrientation)
        DispatchQueue.global(qos: .userInitiated).async {
            let pedido = VNRecognizeTextRequest { req, err in
                if let err = err {
                    call.reject("No se pudo leer el texto: " + err.localizedDescription, "vision")
                    return
                }
                let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                let lineas: [[String: Any]] = obs.compactMap { o in
                    guard let c = o.topCandidates(1).first else { return nil }
                    let b = o.boundingBox   // normalizado, con el origen ABAJO a la izquierda
                    return ["texto": c.string, "confianza": c.confidence,
                            "x": b.minX, "y": 1 - b.maxY, "w": b.width, "h": b.height]
                }.sorted { a, b in
                    let ya = a["y"] as? CGFloat ?? 0, yb = b["y"] as? CGFloat ?? 0
                    if abs(ya - yb) > 0.01 { return ya < yb }
                    return (a["x"] as? CGFloat ?? 0) < (b["x"] as? CGFloat ?? 0)
                }
                call.resolve(["lineas": lineas])
            }
            pedido.recognitionLevel = .accurate
            pedido.usesLanguageCorrection = true
            pedido.recognitionLanguages = ["en-US", "es-ES"]
            do {
                try VNImageRequestHandler(cgImage: cg, orientation: orientacion, options: [:]).perform([pedido])
            } catch {
                call.reject("No se pudo leer el texto: " + error.localizedDescription, "vision")
            }
        }
    }

    private static func orientacion(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}


// ENVIAR A COMPANYCAM (15 sep 2026). CompanyCam da un enlace de S3 para subir
// cada foto, con Content-MD5 obligatorio. Desde la web (WKWebView) ese PUT choca
// con CORS y el MD5 no existe en WebCrypto, asi que lo hace el telefono:
//   md5({ path })            -> { md5, bytes }   (path relativo a Documents = DATA)
//   subir({ path, url, headers }) -> { status }  (PUT del archivo tal cual)
// Lee el archivo del disco directo: la foto no cruza el puente dos veces.
@objc(SubirPlugin)
public class SubirPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SubirPlugin"
    public let jsName = "Subir"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "md5", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "subir", returnType: CAPPluginReturnPromise)
    ]

    private func archivo(_ call: CAPPluginCall) -> URL? {
        guard let rel = call.getString("path"), !rel.isEmpty, !rel.contains(".."),
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = docs.appendingPathComponent(rel)
        return url.standardizedFileURL.path.hasPrefix(docs.standardizedFileURL.path) ? url : nil
    }

    @objc func md5(_ call: CAPPluginCall) {
        guard let url = archivo(call) else { call.reject("Ruta invalida", "ruta"); return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = try? Data(contentsOf: url) else { call.reject("No se pudo leer la foto", "leer"); return }
            let hash = Data(Insecure.MD5.hash(data: data)).base64EncodedString()
            call.resolve(["md5": hash, "bytes": data.count])
        }
    }

    @objc func subir(_ call: CAPPluginCall) {
        guard let url = archivo(call) else { call.reject("Ruta invalida", "ruta"); return }
        guard let destinoTexto = call.getString("url"), let destino = URL(string: destinoTexto),
              destino.scheme == "https" else { call.reject("Enlace invalido", "enlace"); return }
        guard let data = try? Data(contentsOf: url) else { call.reject("No se pudo leer la foto", "leer"); return }
        var req = URLRequest(url: destino, timeoutInterval: 120)
        req.httpMethod = "PUT"
        for (k, v) in (call.getObject("headers") ?? [:]) {
            if let texto = v as? String { req.setValue(texto, forHTTPHeaderField: k) }
            else if let numero = v as? NSNumber { req.setValue(numero.stringValue, forHTTPHeaderField: k) }
        }
        URLSession.shared.uploadTask(with: req, from: data) { _, resp, err in
            if let err = err { call.reject("Sin conexion: " + err.localizedDescription, "red"); return }
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            call.resolve(["status": status])
        }.resume()
    }
}
