import Foundation

// LO QUE EL ASISTENTE SE ACUERDA DE UN DIA PARA OTRO.
//
// Su pedido: "el comando de voz debe estudiar la app y recordar conversaciones
// y aprender de ellas y la manera que se toman las medidas".
//
// QUE SE GUARDA Y POR QUE CADA COSA:
//
// 1. LA CONVERSACION. Antes vivia dentro de la sesion del modelo, que muere al
//    cerrar la camara. O sea que cada medida empezaba de cero y no habia tal
//    cosa como "acuerdate de lo que te dije". Ahora los turnos se guardan en el
//    telefono y se le vuelven a sembrar al modelo cuando abre.
//
// 2. COMO MIDE EL. Esto es lo que de verdad ahorra tiempo. Un corte de pared
//    casi siempre es de 2 pies; la tablaroca casi siempre lleva insulacion;
//    despues del piso casi siempre sigue la pared. Nada de eso se puede saber
//    de antemano - depende de como trabaja LA CUADRILLA - pero se ve solo
//    despues de unas cuantas medidas.
//
// 3. FRASES QUE NO ENTENDIO y que el corrigio enseguida. Ya existia para los
//    MATERIALES; aqui se extiende a las ordenes, que es donde mas se atoraba.
//
// TRES REGLAS QUE NO SE ROMPEN:
//  - Lo aprendido SUGIERE, nunca decide. Un ancho aprendido se OFRECE en voz
//    alta y el contesta; jamas se anota solo. La app no inventa medidas, y que
//    el numero venga de una costumbre no lo hace menos inventado.
//  - Nada se aprende de una sola vez. Una vez es casualidad; tres veces
//    seguidas es una costumbre. Es la misma regla que ya usa el escaner.
//  - Todo vive en ESTE telefono. No sale a ningun lado.
enum MemoriaAsistente {

    private static let clave = "asistenteMemoria:v1"
    private static let maxTurnos = 60

    // ---------- LO QUE SE GUARDA ----------
    struct Turno: Codable {
        let dijo: String        // lo que dijo el tecnico
        let paso: String        // que acabo pasando ("marcar", "guardar", una respuesta...)
        let cuando: Date
    }

    struct Medida: Codable {
        let seccion: String
        let material: String
        let largo: Double
        let ancho: Double?
        let companero: Bool
        let cuando: Date
    }

    struct Todo: Codable {
        var turnos: [Turno] = []
        var medidas: [Medida] = []
        var ordenesAprendidas: [String: String] = [:]   // frase -> orden
        var saltos: [String: [String: Int]] = [:]       // seccion -> {siguiente: veces}
    }

    private static var cache: Todo?

    private static func leer() -> Todo {
        if let c = cache { return c }
        guard let d = UserDefaults.standard.data(forKey: clave),
              let t = try? JSONDecoder().decode(Todo.self, from: d) else {
            cache = Todo(); return cache!
        }
        cache = t
        return t
    }

    private static func guardar(_ t: Todo) {
        cache = t
        guard let d = try? JSONEncoder().encode(t) else { return }
        UserDefaults.standard.set(d, forKey: clave)
    }

    // ---------- 1. LA CONVERSACION ----------

    static func recordar(dijo: String, paso: String) {
        let frase = dijo.trimmingCharacters(in: .whitespacesAndNewlines)
        // Las palabras sueltas no son conversacion y llenarian la memoria de
        // "marca, marca, marca" hasta tapar lo que si vale la pena.
        guard frase.count >= 6 else { return }
        var t = leer()
        t.turnos.append(Turno(dijo: frase, paso: paso, cuando: Date()))
        if t.turnos.count > maxTurnos { t.turnos.removeFirst(t.turnos.count - maxTurnos) }
        guardar(t)
    }

    // Lo que se le vuelve a sembrar al modelo cuando abre la camara.
    //
    // CORTO A PROPOSITO. El modelo del telefono tiene una ventana chica; si se
    // le vacian sesenta turnos adentro, lo que sobra se cae por el otro lado y
    // ademas cada respuesta tarda mas. Seis intercambios recientes son
    // suficientes para que "lo de ayer" tenga sentido.
    static func conversacionReciente(_ cuantos: Int = 6) -> String {
        let t = leer()
        guard !t.turnos.isEmpty else { return "" }
        let ultimos = t.turnos.suffix(cuantos)
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        f.dateFormat = "d MMM"
        return ultimos.map { "\(f.string(from: $0.cuando)): dijo \"\($0.dijo)\" → \($0.paso)" }
                      .joined(separator: "\n")
    }

    // ---------- 2. COMO MIDE EL ----------

    static func aprenderMedida(seccion: String, material: String,
                               largo: Double, ancho: Double?, companero: Bool) {
        var t = leer()
        t.medidas.append(Medida(seccion: seccion, material: material, largo: largo,
                                ancho: ancho, companero: companero, cuando: Date()))
        // Con las ultimas 300 sobra, y si cambia de costumbre las viejas
        // estorban: lo de hace seis meses no dice como trabaja hoy.
        if t.medidas.count > 300 { t.medidas.removeFirst(t.medidas.count - 300) }
        guardar(t)
    }

    // ¿Este material SIEMPRE lleva el mismo ancho? El caso real: el corte de
    // pared es de 2 pies casi siempre.
    //
    // Devuelve el ancho solo si de verdad es una costumbre: al menos tres
    // medidas y siete de cada diez iguales. Con dos no se sabe nada.
    static func anchoUsual(material: String) -> Double? {
        let suyas = leer().medidas.filter { $0.material == material && $0.ancho != nil }
        guard suyas.count >= 3 else { return nil }
        // Al medio pie, que es como se habla en obra: 2.0 y 2.05 son el mismo ancho.
        var conteo: [Double: Int] = [:]
        for m in suyas { conteo[(m.ancho! * 2).rounded() / 2, default: 0] += 1 }
        guard let (ancho, veces) = conteo.max(by: { $0.value < $1.value }) else { return nil }
        guard veces >= 3, Double(veces) / Double(suyas.count) >= 0.7 else { return nil }
        return ancho
    }

    // ¿Este material siempre lleva lo de abajo (insulacion, almohadilla)?
    static func companeroUsual(material: String) -> Bool? {
        let suyas = leer().medidas.filter { $0.material == material }
        guard suyas.count >= 3 else { return nil }
        let con = suyas.filter { $0.companero }.count
        if Double(con) / Double(suyas.count) >= 0.8 { return true }
        if Double(con) / Double(suyas.count) <= 0.2 { return false }
        return nil   // ni una cosa ni la otra: mejor preguntar
    }

    // Despues de esta seccion, ¿a cual se pasa el? Para ofrecer esa primero en
    // vez de leerle las cuatro cada vez.
    static func recordarSalto(de: String, a: String) {
        guard de != a, !de.isEmpty, !a.isEmpty else { return }
        var t = leer()
        var m = t.saltos[de] ?? [:]
        m[a] = (m[a] ?? 0) + 1
        t.saltos[de] = m
        guardar(t)
    }
    static func seccionDespuesDe(_ seccion: String) -> String? {
        guard let m = leer().saltos[seccion] else { return nil }
        guard let (destino, veces) = m.max(by: { $0.value < $1.value }), veces >= 3 else { return nil }
        return destino
    }

    // ---------- 3. FRASES QUE APRENDIO SOLO ----------

    // Se le dice algo, no lo entiende, y EN SEGUIDA el hace lo que queria - con
    // el dedo o con una orden que si conoce. Esa pareja es la leccion: la frase
    // que no entendio queria decir eso.
    //
    // NO SE APRENDE TODO. "Terminar" manda el reporte y "cancela" tira el
    // trabajo a medias: una frase mal aprendida ahi cuesta caro y no hay como
    // deshacerlo. Solo se aprenden las que se pueden deshacer.
    static let ordenesQueSePuedenAprender: Set<String> = [
        "marcar", "deshacer", "medirAncho", "terminarRecorrido", "guardar",
        "otroCuarto", "cambiarSeccion", "cambiarNivel", "abrirLista",
        "cuantoLlevo", "dondeVoy", "queMaterial", "cambiarMaterial",
        "otraIgual", "ponerCompanero", "quitarCompanero", "esperame", "queComandos"
    ]

    static func aprenderOrden(frase: String, orden: String) {
        let f = frase.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard ordenesQueSePuedenAprender.contains(orden) else { return }
        // Ni muy corta (se confunde con todo) ni una frase entera de platica.
        guard f.count >= 5, f.split(separator: " ").count <= 4 else { return }
        var t = leer()
        guard t.ordenesAprendidas[f] == nil else { return }
        t.ordenesAprendidas[f] = orden
        if t.ordenesAprendidas.count > 80,
           let vieja = t.ordenesAprendidas.keys.first { t.ordenesAprendidas.removeValue(forKey: vieja) }
        guardar(t)
    }

    static func ordenAprendida(_ frase: String) -> String? {
        let f = frase.lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return leer().ordenesAprendidas[f]
    }

    // ---------- LO QUE APRENDIO, EN PALABRAS ----------
    //
    // Para decirselo cuando pregunte "¿qué has aprendido?" y para sembrarselo
    // al modelo. Que sea revisable importa: una app que aprende a escondidas es
    // una app en la que no se puede confiar.
    static func loQueAprendio(materiales: [String]) -> [String] {
        var l: [String] = []
        for m in materiales {
            if let a = anchoUsual(material: m) {
                l.append("\(m): casi siempre \(a == a.rounded() ? String(Int(a)) : String(format: "%.1f", a)) pies de ancho")
            }
            if let c = companeroUsual(material: m), c {
                l.append("\(m): casi siempre lleva lo de abajo")
            }
        }
        for (de, _) in leer().saltos {
            if let a = seccionDespuesDe(de) { l.append("después de \(de) casi siempre sigue \(a)") }
        }
        let n = leer().ordenesAprendidas.count
        if n > 0 { l.append("\(n) \(n == 1 ? "frase suya aprendida" : "frases suyas aprendidas")") }
        return l
    }

    static func cuantosTurnos() -> Int { return leer().turnos.count }
    static func cuantasMedidas() -> Int { return leer().medidas.count }

    // Borrar todo lo aprendido. Tiene que existir: si la app aprendio algo mal
    // y no hay como borrarlo, el error se queda para siempre.
    static func olvidarTodo() {
        cache = Todo()
        UserDefaults.standard.removeObject(forKey: clave)
    }
}
