#!/bin/bash
# (17 oct 2026) Lo guardado en la cámara queda en el teléfono AL MOMENTO (BorradorCamara.swift):
# - el archivo real compilado con swiftc: escribir, deshacer, vaciar, dos sesiones, borrar una, trabajos raros;
# - la estructura: solo con borrador pedido + trabajo + sin maqueta; "Salir" lo borra; mandar y la caída no;
# - el mismo Swift en Field Reports, y la página de Field Reports nunca pide borrador.
# Uso:  bash tests/camara/borrador_camara_test.sh     (FR_DIR para otra ruta)
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$DIR/../ios/App/App/ARMeasureViewController.swift" ]; then RAIZ="$(cd "$DIR/.." && pwd)"; else RAIZ="$(cd "$DIR/../.." && pwd)"; fi
FR="${FR_DIR:-/Users/amilcargonzalez/Downloads/field-report-ios-app}"
E=0
TMP="$(mktemp -d -t borrador)"
cat > "$TMP/main.swift" <<'SWEOF'
import Foundation
var fallas = 0
func ok(_ l: String, _ c: Bool) { print((c ? "  ok  " : "  FAIL ") + l); if !c { fallas += 1 } }
let raiz = URL(fileURLWithPath: CommandLine.arguments[1])
BorradorCamara.base = raiz
let m1: [String: Any] = ["length": 10.0, "material": "Drywall", "id": "a", "idComp": "b", "t": 5.0]
let m2: [String: Any] = ["length": 4.0, "material": "Carpet", "id": "c", "idComp": "d", "t": 6.0]
BorradorCamara.escribir(trabajo: "job-1", sesion: "s1", orden: 100, medidas: [m1, m2])
var l = BorradorCamara.leer(trabajo: "job-1")
ok("dos medidas guardadas: una sesión con dos", l.count == 1 && (l[0]["medidas"] as? [[String: Any]])?.count == 2 && (l[0]["sesion"] as? String) == "s1")
ok("lo leído trae los ids", ((l[0]["medidas"] as? [[String: Any]])?.first?["idComp"] as? String) == "b")
BorradorCamara.escribir(trabajo: "job-1", sesion: "s1", orden: 100, medidas: [m1])
l = BorradorCamara.leer(trabajo: "job-1")
ok("Deshacer deja una", l.count == 1 && (l[0]["medidas"] as? [[String: Any]])?.count == 1)
BorradorCamara.escribir(trabajo: "job-1", sesion: "s1", orden: 100, medidas: [])
let archivo = raiz.appendingPathComponent("borradores-camara/job-1/s1.json")
ok("todo deshecho: el archivo se borra", !FileManager.default.fileExists(atPath: archivo.path) && BorradorCamara.leer(trabajo: "job-1").isEmpty)
BorradorCamara.escribir(trabajo: "job-1", sesion: "s2", orden: 200, medidas: [m2])
BorradorCamara.escribir(trabajo: "job-1", sesion: "s1", orden: 100, medidas: [m1])
l = BorradorCamara.leer(trabajo: "job-1")
ok("dos sesiones: dos archivos, en orden", l.map { $0["sesion"] as? String ?? "" } == ["s1", "s2"])
BorradorCamara.borrar(trabajo: "job-1", sesion: "s1")
l = BorradorCamara.leer(trabajo: "job-1")
ok("borrar una deja la otra", l.map { $0["sesion"] as? String ?? "" } == ["s2"])
ok("otro trabajo no ve nada", BorradorCamara.leer(trabajo: "job-2").isEmpty)
ok("sin trabajo no hay carpeta", BorradorCamara.carpeta("") == nil && BorradorCamara.carpeta("../") == nil)
BorradorCamara.escribir(trabajo: "", sesion: "x", orden: 1, medidas: [m1])
BorradorCamara.escribir(trabajo: "../x", sesion: "x", orden: 1, medidas: [m1])
let c = BorradorCamara.carpeta("../x")
ok("'../x' queda limpio, dentro de la carpeta de prueba", c != nil && c!.path.hasPrefix(raiz.path + "/borradores-camara/") && !c!.path.contains(".."))
ok("nada se escribió afuera", !FileManager.default.fileExists(atPath: raiz.deletingLastPathComponent().appendingPathComponent("x").path))
if let d = try? Data(contentsOf: raiz.appendingPathComponent("borradores-camara/job-1/s2.json")) {
    ok("el archivo es JSON que se vuelve a leer", (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] != nil)
} else { ok("el archivo es JSON que se vuelve a leer", false) }
exit(fallas == 0 ? 0 : 1)
SWEOF
mkdir -p "$TMP/datos"
if swiftc -o "$TMP/prueba" "$RAIZ/ios/App/App/BorradorCamara.swift" "$TMP/main.swift" 2>"$TMP/err"; then
  "$TMP/prueba" "$TMP/datos" || E=1
else echo "  FAIL no compila"; cat "$TMP/err"; E=1; fi
python3 - "$RAIZ" <<'PYEOF' || E=1
import io, sys, re
raiz = sys.argv[1]
rd = lambda p: io.open(p, encoding='utf-8').read()
v = rd(raiz + '/ios/App/App/ARMeasureViewController.swift'); plg = rd(raiz + '/ios/App/App/ARMeasurePlugin.swift')
def bloque(src, firma):
    i = src.index(firma); j = src.index('{', i); d = 0; k = j
    while True:
        c = src[k]
        if c == '{': d += 1
        elif c == '}':
            d -= 1
            if d == 0: break
        k += 1
    return src[i:k+1]
F = 0
def ok(l, c):
    global F
    print(('  ok  ' if c else '  FAIL ') + l)
    if not c: F += 1
ok('items avisa en cada cambio', '= [] { didSet { seguirIdsYBorrador() } }' in v[v.index('private var items: ['):v.index('private var items: [') + 600])
ok('solo con borrador pedido, trabajo y sin maqueta', 'private var guardaBorrador: Bool { borradorPedido && !trabajoId.isEmpty && maqueta == 0 }' in v)
ct = bloque(v, '@objc private func cancelTapped()')
ok('"Salir" borra el borrador antes de cerrar', 'BorradorCamara.borrar' in ct and ct.index('BorradorCamara.borrar') < ct.index('onFinish?(.cancelled)'))
ok('mandar no borra el borrador (lo suelta la página)', 'BorradorCamara.borrar' not in bloque(v, '@objc private func finishTapped()'))
ok('la caída de ARKit no borra el borrador', 'BorradorCamara.borrar' not in bloque(v, 'func session(_ session: ARSession, didFailWithError'))
ok('el plugin lee la bandera', 'getBool("borrador")' in plg)
ok('las dos respuestas con medidas llevan la sesión', plg.count('"measurements": Self.comoDiccionarios(items)') == 2 and len(re.findall(r'"measurements": Self\.comoDiccionarios\(items\)[^\]]*"sesion": sesion\]', plg)) == 2)
i = plg.index('= [', plg.index('pluginMethods')); pm = plg[i:plg.index(']', i + 3)]
ok('pluginMethods trae borrador y soltarBorrador', 'name: "borrador"' in pm and 'name: "soltarBorrador"' in pm)
ed = [l for l in v.split('\n') if re.search(r'\bitems\.(append|remove|insert|swap|sort)|\bitems\[[^\]]*\]\s*=[^=]|\bitems = ', l)]
ok('items solo crece al final y se quita del final (los ids van por posición)', len(ed) > 0 and all(re.search(r'items\.(append\(|removeLast\(\))', l) for l in ed))
sys.exit(1 if F else 0)
PYEOF
if [ -d "$FR" ]; then
  for f in ARMeasureViewController.swift ARMeasurePlugin.swift BorradorCamara.swift; do
    if cmp -s "$RAIZ/ios/App/App/$f" "$FR/ios/App/App/$f"; then echo "  ok  $f identical in Field Reports"; else echo "  FAIL $f identical in Field Reports"; E=1; fi
  done
  if grep -rqE "borrador: *true" "$FR/www" 2>/dev/null; then echo "  FAIL la página de Field Reports pide borrador"; E=1; else echo "  ok  la página de Field Reports nunca pide borrador"; fi
fi
rm -rf "$TMP"
exit $E
