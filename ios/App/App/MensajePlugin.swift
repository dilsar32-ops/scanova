import Foundation
import Capacitor
import MessageUI
import UIKit

// MANDAR EL INVOICE POR MENSAJE, YA DIRIGIDO AL CLIENTE  (7 de octubre de 2026)
//
// Su pedido, con la foto de la conversacion con Susan: "a la hora que se envia
// el invoice deberia enviarse directamente desde la aplicacion, ya que esta el
// numero del cliente en la aplicacion".
//
// POR QUE HIZO FALTA CODIGO NATIVO, y no bastaba lo que ya habia:
//  * La hoja de compartir de iOS (la que usa Share.share) NO deja escoger al
//    destinatario: siempre hay que buscar a la persona a mano.
//  * Un enlace `sms:numero&body=...` si abre Mensajes con el numero puesto,
//    pero NO puede llevar el PDF. Esos dos caminos ya estaban en la app y
//    ninguno hace las dos cosas.
//  * MFMessageComposeViewController si: destinatario + texto + el PDF adjunto,
//    todo servido. El cliente sale ya escrito y solo falta tocar Enviar.
//
// LO QUE ESTE PLUGIN NO HACE, A PROPOSITO:
//  * NO manda nada solo. Abre Mensajes con todo listo y el dedo de Amilcar es
//    el que toca Enviar. iOS no deja mandar un SMS sin que la persona lo vea, y
//    aunque dejara, un mensaje a un cliente no se manda sin que alguien lo lea.
//  * Si el telefono no puede mandar mensajes (un iPad sin linea) o no acepta
//    adjuntos, contesta `disponible: false` y la web se va a la hoja de
//    compartir de siempre. Nunca se queda callado.
@objc(MensajePlugin)
public class MensajePlugin: CAPPlugin, CAPBridgedPlugin, MFMessageComposeViewControllerDelegate {
    public let identifier = "MensajePlugin"
    public let jsName = "Mensaje"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "disponible", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "enviar",     returnType: CAPPluginReturnPromise)
    ]

    private var llamada: CAPPluginCall?

    @objc func disponible(_ call: CAPPluginCall) {
        call.resolve([
            "mensajes": MFMessageComposeViewController.canSendText(),
            "adjuntos": MFMessageComposeViewController.canSendAttachments()
        ])
    }

    @objc func enviar(_ call: CAPPluginCall) {
        guard MFMessageComposeViewController.canSendText() else {
            // Un iPad sin linea, o un telefono con Mensajes apagado.
            call.resolve(["estado": "no-disponible", "porque": "Este telefono no puede mandar mensajes."])
            return
        }

        let numero = (call.getString("telefono") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !numero.isEmpty else {
            call.resolve(["estado": "sin-numero", "porque": "Ese cliente no tiene telefono guardado."])
            return
        }

        // El PDF ya lo escribio la web con Filesystem (carpeta CACHE) y manda su
        // ruta. Se lee aqui; si no se puede leer, se dice y la web se va a la
        // hoja de compartir en vez de abrir Mensajes con el texto pelado.
        var datos: Data?
        var nombre = call.getString("nombre") ?? "invoice.pdf"
        if let ruta = call.getString("archivo"), !ruta.isEmpty {
            let url = URL(string: ruta) ?? URL(fileURLWithPath: ruta)
            datos = try? Data(contentsOf: url)
            if datos == nil, url.isFileURL == false {
                datos = try? Data(contentsOf: URL(fileURLWithPath: url.path))
            }
            if nombre.isEmpty { nombre = url.lastPathComponent }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.llamada == nil else {
                call.resolve(["estado": "ocupado", "porque": "Ya hay un mensaje abierto."])
                return
            }
            let vc = MFMessageComposeViewController()
            vc.messageComposeDelegate = self
            vc.recipients = [numero]
            vc.body = call.getString("texto") ?? ""
            var conAdjunto = false
            if let d = datos, MFMessageComposeViewController.canSendAttachments() {
                conAdjunto = vc.addAttachmentData(d, typeIdentifier: "com.adobe.pdf", filename: nombre)
            }
            // SI EL PDF NO SE PUDO ADJUNTAR, NO SE ABRE NADA. Mandar el texto
            // solo, sin la factura, es peor que no mandar: el cliente recibe un
            // cobro sin con que revisarlo.
            if datos != nil && !conAdjunto {
                call.resolve(["estado": "sin-adjunto", "porque": "Este telefono no pudo adjuntar el PDF."])
                return
            }
            self.llamada = call
            self.bridge?.viewController?.present(vc, animated: true)
        }
    }

    public func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                             didFinishWith result: MessageComposeResult) {
        let call = llamada
        llamada = nil
        controller.dismiss(animated: true) {
            switch result {
            case .sent:      call?.resolve(["estado": "enviado"])
            case .cancelled: call?.resolve(["estado": "cancelado"])
            default:         call?.resolve(["estado": "fallo", "porque": "Mensajes no pudo mandarlo."])
            }
        }
    }
}
