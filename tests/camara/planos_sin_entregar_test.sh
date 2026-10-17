#!/bin/bash
# (17 oct 2026) El escaneo del plano queda en el teléfono ANTES de responder a la página (PlanosSinEntregar, en RoomPlanPlugin.swift):
# - el código real (sacado del Swift) compilado con swiftc: nombres de archivo, ids raros, NaN/infinito/fechas, leer, soltar,
#   el orden, el resumen para Home, lo que recibe la página (limpio, igual al archivo) y cuándo se borra (180 días después de
#   escaneado, leído o no: leer no marca nada; nunca al escribir);
# - la estructura: solo con trabajo + entrega, se escribe antes de call.resolve y se avisa a la página (escaneoEnTelefono),
#   cancelar no escribe, los métodos registrados, el 3D de otro escaneo no se enseña;
# - el mismo Swift en Field Reports, y la página de Field Reports nunca manda entrega.
# Uso:  bash tests/camara/planos_sin_entregar_test.sh     (FR_DIR para otra ruta)
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$DIR/../ios/App/App/RoomPlanPlugin.swift" ]; then RAIZ="$(cd "$DIR/.." && pwd)"; else RAIZ="$(cd "$DIR/../.." && pwd)"; fi
FR="${FR_DIR:-/Users/amilcargonzalez/Downloads/field-report-ios-app}"
E=0
TMP="$(mktemp -d -t planos)"
python3 - "$RAIZ/ios/App/App/RoomPlanPlugin.swift" "$TMP/enum.swift" <<'PYEOF'
import io, sys
src = io.open(sys.argv[1], encoding='utf-8').read()
i = src.index('enum PlanosSinEntregar {'); j = src.index('{', i); d = 0; k = j
while True:
    c = src[k]
    if c == '{': d += 1
    elif c == '}':
        d -= 1
        if d == 0: break
    k += 1
io.open(sys.argv[2], 'w', encoding='utf-8').write('import Foundation\n' + src[i:k+1] + '\n')
PYEOF
cat > "$TMP/main.swift" <<'SWEOF'
import Foundation
var fallas = 0
func ok(_ l: String, _ c: Bool) { print((c ? "  ok  " : "  FAIL ") + l); if !c { fallas += 1 } }
let raiz = URL(fileURLWithPath: CommandLine.arguments[1])
PlanosSinEntregar.base = raiz
let fm = FileManager.default
struct Raro {}
let e1 = "0F8FAD5B-D9CB-469F-A165-70867728950E"
let escaneo: [String: Any] = ["_entrega": e1, "rooms": [["walls": [["heightFt": Double.nan, "x": 1.5]], "area": Double.infinity, "ok": true, "level": 1]],
                              "inspection": ["incompleteRooms": [0], "raro": Raro()], "lista": [1.0, Double.nan, Raro(), "a"], "cuando": Date(timeIntervalSince1970: 0)]
ok("con NaN, infinito, una fecha y un tipo raro se escribe igual (no se cae)", PlanosSinEntregar.escribir(trabajo: "job-1", entrega: e1, escaneo: escaneo))
let archivo = raiz.appendingPathComponent("planos-sin-entregar/job-1/0f8fad5b-d9cb-469f-a165-70867728950e.json")
ok("planos-sin-entregar/<trabajo>/<entrega>.json (en minúsculas)", fm.fileExists(atPath: archivo.path))
var l = PlanosSinEntregar.leer(trabajo: "job-1")
ok("se lee de vuelta, con su entrega", l.count == 1 && (l[0]["_entrega"] as? String) == e1)
let room = ((l.first?["rooms"] as? [[String: Any]])?.first) ?? [:]
let pared = ((room["walls"] as? [[String: Any]])?.first) ?? [:]
ok("NaN e infinito -> null; lo demás igual", pared["heightFt"] is NSNull && (pared["x"] as? Double) == 1.5 && room["area"] is NSNull)
ok("true sigue siendo true (no 1)", (room["ok"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue } == true)
let lista = (l.first?["lista"] as? [Any]) ?? []
ok("en una lista lo que no se puede escribir queda null (no se corren los índices)", lista.count == 4 && (lista[0] as? Double) == 1.0 && lista[1] is NSNull && lista[2] is NSNull && (lista[3] as? String) == "a")
ok("en un diccionario el tipo raro se quita; lo demás queda", ((l.first?["inspection"] as? [String: Any])?["raro"]) == nil && ((l.first?["inspection"] as? [String: Any])?["incompleteRooms"] as? [Int]) == [0])
ok("la fecha va como texto", (l.first?["cuando"] as? String) == "1970-01-01T00:00:00Z")
ok("otro trabajo no ve nada", PlanosSinEntregar.leer(trabajo: "job-2").isEmpty)
ok("sin trabajo o sin entrega no se escribe nada", !PlanosSinEntregar.escribir(trabajo: "", entrega: e1, escaneo: escaneo) && !PlanosSinEntregar.escribir(trabajo: "job-1", entrega: "", escaneo: escaneo) && !PlanosSinEntregar.escribir(trabajo: "../", entrega: "x", escaneo: escaneo))
let c = PlanosSinEntregar.archivo(trabajo: "../../x", entrega: "../y/z")
ok("'../../x' y '../y/z' quedan limpios, dentro de la carpeta", c != nil && c!.path.hasPrefix(raiz.path + "/planos-sin-entregar/") && !c!.path.contains("..") && c!.lastPathComponent == "yz.json")
// Dos escaneos: del más viejo al más nuevo.
let e2 = "5e1c2b9a-7d3f-4a8e-9b6c-0123456789ab"
PlanosSinEntregar.escribir(trabajo: "job-1", entrega: e2, escaneo: ["_entrega": e2, "rooms": []])
try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: raiz.appendingPathComponent("planos-sin-entregar/job-1/\(e2).json").path)
l = PlanosSinEntregar.leer(trabajo: "job-1")
ok("dos escaneos: el más viejo primero", l.map { $0["_entrega"] as? String ?? "" } == [e2, e1])
// Un archivo sin entrega o roto no se entrega.
try? "{roto".data(using: .utf8)!.write(to: raiz.appendingPathComponent("planos-sin-entregar/job-1/roto.json"))
try? JSONSerialization.data(withJSONObject: ["rooms": []]).write(to: raiz.appendingPathComponent("planos-sin-entregar/job-1/sin.json"))
ok("un archivo roto o sin entrega no se entrega", PlanosSinEntregar.leer(trabajo: "job-1").count == 2)
try? fm.removeItem(at: raiz.appendingPathComponent("planos-sin-entregar/job-1/roto.json")); try? fm.removeItem(at: raiz.appendingPathComponent("planos-sin-entregar/job-1/sin.json"))
// Soltar: con el mismo id que la página recibió (aunque venga en mayúsculas).
PlanosSinEntregar.borrar(trabajo: "job-1", entrega: e1)
ok("soltar quita ese escaneo y deja el otro", PlanosSinEntregar.leer(trabajo: "job-1").map { $0["_entrega"] as? String ?? "" } == [e2])
PlanosSinEntregar.borrar(trabajo: "job-1", entrega: e2)
ok("soltar el último quita también la carpeta del trabajo", !fm.fileExists(atPath: raiz.appendingPathComponent("planos-sin-entregar/job-1").path))
// (revisión 17-oct, 2a) Un archivo que sigue aquí es un escaneo que no está guardado en ningún lado: leerlo NO empieza ningún
// reloj (antes, leído una vez, se borraba a los 30 días aunque nunca se hubiera podido guardar). Solo se va 180 días después
// de escaneado, leído o no. Y nunca al escribir un escaneo nuevo.
let viejo = "7a7a7a7a-1b1b-4c2c-8d3d-e4e4e4e4e4e4", nuevo = "8b8b8b8b-2c2c-4d3d-9e4e-f5f5f5f5f5f5"
let sinLeer = "9c9c9c9c-3d3d-4e4e-8f5f-a6a6a6a6a6a6", olvidado = "0d0d0d0d-4e4e-4f5f-9a6a-b7b7b7b7b7b7"
func ruta(_ t: String, _ e: String, _ ext: String = "json") -> String { raiz.appendingPathComponent("planos-sin-entregar/\(t)/\(e).\(ext)").path }
func atrasar(_ path: String, dias: Double) { try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(-dias * 86400)], ofItemAtPath: path) }
PlanosSinEntregar.escribir(trabajo: "job-3", entrega: viejo, escaneo: ["_entrega": viejo])
PlanosSinEntregar.escribir(trabajo: "job-4", entrega: nuevo, escaneo: ["_entrega": nuevo])
PlanosSinEntregar.escribir(trabajo: "job-5", entrega: sinLeer, escaneo: ["_entrega": sinLeer])
PlanosSinEntregar.escribir(trabajo: "job-6", entrega: olvidado, escaneo: ["_entrega": olvidado])
let res = PlanosSinEntregar.resumen()
ok("resumen: cada trabajo con cuántos tiene", res.count == 4 && res.contains { ($0["trabajo"] as? String) == "job-3" && ($0["n"] as? Int) == 1 && ($0["desde"] as? String) != nil })
_ = PlanosSinEntregar.leer(trabajo: "job-3"); _ = PlanosSinEntregar.leer(trabajo: "job-4")
ok("leer no deja ninguna marca (ni .visto)", ((try? fm.contentsOfDirectory(atPath: raiz.appendingPathComponent("planos-sin-entregar/job-3").path)) ?? []) == ["\(viejo).json"])
// Una marca .visto que dejó una prueba anterior se quita sola.
fm.createFile(atPath: ruta("job-4", nuevo, "visto"), contents: Data())
atrasar(ruta("job-3", viejo), dias: 100); atrasar(ruta("job-4", nuevo), dias: 179); atrasar(ruta("job-5", sinLeer), dias: 100)
atrasar(ruta("job-6", olvidado), dias: 181)
// Un escaneo nuevo no barre nada.
PlanosSinEntregar.escribir(trabajo: "job-7", entrega: e1, escaneo: ["_entrega": e1])
ok("escribir un escaneo nuevo no borra ninguno viejo", fm.fileExists(atPath: ruta("job-3", viejo)) && fm.fileExists(atPath: ruta("job-6", olvidado)))
_ = PlanosSinEntregar.resumen()
ok("leído y sin soltar (no se pudo guardar), 100 días: se queda", PlanosSinEntregar.leer(trabajo: "job-3").count == 1)
ok("leído y sin soltar, 179 días: se queda", PlanosSinEntregar.leer(trabajo: "job-4").count == 1)
ok("la marca .visto vieja se quitó", !fm.fileExists(atPath: ruta("job-4", nuevo, "visto")))
ok("nunca leído, 100 días: se queda (Home lo sigue diciendo)", fm.fileExists(atPath: ruta("job-5", sinLeer)))
ok("más de 180 días desde que se escaneó: se borra, con su carpeta", !fm.fileExists(atPath: raiz.appendingPathComponent("planos-sin-entregar/job-6").path))
atrasar(ruta("job-3", viejo), dias: 181)
_ = PlanosSinEntregar.leer(trabajo: "job-9")
ok("leído alguna vez y ya con más de 180 días: se borra igual", !fm.fileExists(atPath: raiz.appendingPathComponent("planos-sin-entregar/job-3").path))
PlanosSinEntregar.borrar(trabajo: "job-4", entrega: nuevo)
ok("soltar el último quita la carpeta", !fm.fileExists(atPath: raiz.appendingPathComponent("planos-sin-entregar/job-4").path))
// (revisión 17-oct) La página recibe el MISMO escaneo limpio que queda en el archivo (con un NaN, Capacitor no puede mandar
// la respuesta cruda: PluginCallResult pide JSONSerialization.isValidJSONObject y si no, la página recibe {}).
let crudo: [String: Any] = ["rooms": [["walls": [["heightFt": Double.nan, "x": 2.0]], "level": 1]], "nivelBase": "Garage"]
ok("el crudo con NaN no es JSON válido (lo que le pasaba a Capacitor)", !JSONSerialization.isValidJSONObject(crudo))
let e9 = "1e1e1e1e-5f5f-4a6a-8b7b-c8c8c8c8c8c8"
let ahora = Date(timeIntervalSince1970: 1_792_000_000)
let entregado = PlanosSinEntregar.entregar(trabajo: "job-8", entrega: e9, nivelPedido: "nivel-2", escaneo: crudo, ahora: ahora)
ok("lo que recibe la página es JSON válido, con sus cuartos", JSONSerialization.isValidJSONObject(entregado) && ((entregado["rooms"] as? [[String: Any]])?.count ?? 0) == 1)
ok("lleva su entrega, la hora del escaneo y el nivel pedido", (entregado["_entrega"] as? String) == e9 && (entregado["_escaneado"] as? String) == ISO8601DateFormatter().string(from: ahora) && (entregado["_nivelPedido"] as? String) == "nivel-2" && (entregado["nivelBase"] as? String) == "Garage")
let enArchivo = PlanosSinEntregar.leer(trabajo: "job-8").first ?? [:]
ok("y es lo mismo que quedó en el archivo", NSDictionary(dictionary: enArchivo).isEqual(to: entregado))
ok("sin nivel pedido no se pone", PlanosSinEntregar.entregar(trabajo: "job-8", entrega: e9, nivelPedido: "", escaneo: [:])["_nivelPedido"] == nil)
exit(fallas == 0 ? 0 : 1)
SWEOF
mkdir -p "$TMP/datos"
if swiftc -o "$TMP/prueba" "$TMP/enum.swift" "$TMP/main.swift" 2>"$TMP/err"; then
  "$TMP/prueba" "$TMP/datos" || E=1
else echo "  FAIL no compila"; cat "$TMP/err"; E=1; fi
python3 - "$RAIZ" <<'PYEOF' || E=1
import io, sys, re
raiz = sys.argv[1]
plg = io.open(raiz + '/ios/App/App/RoomPlanPlugin.swift', encoding='utf-8').read()
F = 0
def ok(l, c):
    global F
    print(('  ok  ' if c else '  FAIL ') + l)
    if not c: F += 1
i = plg.index('= [', plg.index('pluginMethods')); pm = plg[i:plg.index(']', i + 3)]
ok('pluginMethods trae pendientes y soltar', 'name: "pendientes"' in pm and 'name: "soltar"' in pm)
fin = plg[plg.index('case .finished('):plg.index('presenter.present(vc, animated: true)')]
ok('el escaneo se escribe en el teléfono ANTES de call.resolve(dict), y la página recibe ese mismo (limpio)', 0 < fin.index('PlanosSinEntregar.entregar(') < fin.index('call.resolve(dict)'))
ok('solo cuando la página mandó trabajo y entrega (Field Reports y páginas viejas: como siempre)', re.search(r'if !trabajo\.isEmpty && !entrega\.isEmpty \{\s*(//[^\n]*\n\s*)*dict = PlanosSinEntregar\.entregar\(trabajo: trabajo, entrega: entrega, nivelPedido: nivelPedido, escaneo: dict\)\s*(//[^\n]*\n\s*)*self\?\.notifyListeners\("escaneoEnTelefono", data: \["trabajo": trabajo, "entrega": entrega\], retainUntilConsumed: true\)\s*\}\s*call\.resolve\(dict\)', fin) is not None)
ok('el aviso escaneoEnTelefono sale DESPUÉS de escribir el archivo y antes de responder (una página recargada lo oye)', fin.index('PlanosSinEntregar.entregar(') < fin.index('notifyListeners("escaneoEnTelefono"') < fin.index('call.resolve(dict)'))
ok('leer() no escribe nada en el teléfono (ninguna marca)', 'createFile' not in plg[plg.index('static func leer('):plg.index('static func resumen(')])
ok('el nivel que la página tenía en pantalla (nivelId) se lee antes de abrir el escáner', 'let nivelPedido = call.getString("nivelId") ?? ""' in plg)
pe = plg[plg.index('@objc func pendientes('):plg.index('@objc func soltar(')]
ok('pendientes() sin trabajo: el resumen de todos (para Home)', 'PlanosSinEntregar.resumen()' in pe and 'PlanosSinEntregar.leer(trabajo: t)' in pe)
ok('escribir() no barre los viejos (solo leer y resumen)', 'limpiarViejos()' not in plg[plg.index('static func escribir('):plg.index('static func leer(')])
can = plg[plg.index('case .cancelled:'):plg.index('case .finished(')]
ok('cancelar no escribe nada', 'PlanosSinEntregar' not in can)
ok('la página manda trabajo y entrega como opciones', 'call.getString("trabajo")' in plg and 'call.getString("entrega")' in plg)
vm = plg[plg.index('@objc func viewModel('):plg.index('public func numberOfPreviewItems')]
ok('Ver en 3D: con una entrega que no es la del último escaneo, no se enseña otro', 'lastEntrega' in vm and vm.index('lastEntrega') < vm.index('structure.export'))
ok('la presentación del escáner sigue .fullScreen (no se probó .overFullScreen con RoomPlan)', 'vc.modalPresentationStyle = .fullScreen' in plg)
sys.exit(1 if F else 0)
PYEOF
if [ -d "$FR" ]; then
  for f in RoomPlanPlugin.swift RoomScanViewController.swift; do
    if cmp -s "$RAIZ/ios/App/App/$f" "$FR/ios/App/App/$f"; then echo "  ok  $f identical in Field Reports"; else echo "  FAIL $f identical in Field Reports"; E=1; fi
  done
  if grep -rqE "RoomScan\.scan\([^)]*entrega" "$FR/www" 2>/dev/null; then echo "  FAIL la página de Field Reports manda entrega"; E=1; else echo "  ok  la página de Field Reports nunca manda entrega (sin archivo, como siempre)"; fi
fi
rm -rf "$TMP"
exit $E
