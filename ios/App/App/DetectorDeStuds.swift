import Foundation
import Vision
import CoreML

// EL DETECTOR DE PAREDES DE SOLO STUDS, desde las FOTOS del escaneo.
//
// Su pedido del 12 de septiembre de 2026: que el escáner reconozca una pared a
// la que le quitaron el drywall de las dos caras. RoomPlan no puede (no tiene
// categoría de madera); la cámara sí. El escaneo ya guarda unas 100 fotos por
// casa con la posición de la cámara (ScanKeyframeRecorder). Aquí un modelo
// PROPIO, entrenado en la Mac con Create ML sobre fotos con licencia libre
// (studs a la vista / cuarto terminado / madera que no es pared), mira cada
// foto y le pone una nota de 0 a 1 a "esto es una pared pelada".
//
// LO QUE NUNCA HACE: dibujar la pared ni partir el cuarto. Solo marca fotos.
// La app enseña la foto en Plan review y PREGUNTA; la cuadrilla decide. Es su
// regla: nada que se cobre se escoge solo.
//
// Corre DESPUÉS del escaneo, sobre los JPEG ya guardados, en segundo plano:
// nunca compite con RoomPlan por la GPU mientras ella camina (el teléfono ya
// falló por calor en campo).
enum DetectorDeStuds {

    // El modelo, si viene en el paquete. Sin modelo no hay notas, y nadie se
    // entera de que faltó: el escaneo sigue igual que siempre.
    private static let modelo: VNCoreMLModel? = {
        guard let url = Bundle.main.url(forResource: "StudDetector", withExtension: "mlmodelc") else { return nil }
        // CPU y Neural Engine, nunca la GPU: la GPU es de RoomPlan y ARKit
        // mientras se escanea, y el detector corre durante el escaneo.
        let cfg = MLModelConfiguration()
        cfg.computeUnits = .cpuAndNeuralEngine
        guard let ml = try? MLModel(contentsOf: url, configuration: cfg) else { return nil }
        return try? VNCoreMLModel(for: ml)
    }()
    static var disponible: Bool { modelo != nil }

    // Cargar el modelo cuesta un segundo o dos. Se hace ANTES de que
    // arranque la captura (al abrir la pantalla), en segundo plano, para
    // que nunca caiga dentro del escaneo sobre la primera foto.
    static func precalentar() {
        DispatchQueue.global(qos: .utility).async { _ = disponible }
    }

    // La nota de "studs" de UNA foto, o nil si no se pudo mirar.
    static func nota(archivo: URL) -> Float? {
        guard let modelo = modelo else { return nil }
        let peticion = VNCoreMLRequest(model: modelo)
        peticion.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(url: archivo, options: [:])
        do { try handler.perform([peticion]) } catch { return nil }
        guard let obs = peticion.results as? [VNClassificationObservation] else { return nil }
        return obs.first(where: { $0.identifier == "studs" })?.confidence ?? 0
    }

    // Todas las fotos de un escaneo -> [id: nota]. Se puede cancelar: si el
    // plano ya se entregó, no vale la pena seguir calentando el teléfono.
    static func notas(fotos: [(id: String, archivo: URL)], isCancelled: () -> Bool = { false }) -> [String: Float] {
        guard disponible else { return [:] }
        var salida: [String: Float] = [:]
        for f in fotos {
            if isCancelled() { break }
            if let n = nota(archivo: f.archivo) { salida[f.id] = n }
        }
        return salida
    }
}
