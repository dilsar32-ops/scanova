#!/bin/bash
# MEDIR PRIMERO, EL MATERIAL AL FINAL (16 oct 2026): qué líneas y en qué unidad salen de cada respuesta.
# - las reglas REALES (struct ReglasDeMedir, sacada del Swift) corridas con swiftc;
# - y lo que hace la página con eso (docs/medidas.js de Scanova, con node): el corte de drywall de 1 pie en pies lineales y
#   su insulación largo × 1 en pies cuadrados, cada compañero como su propia línea;
# - y la estructura: la voz apagada en este modo, todo detrás de la bandera, guardar por el bancarMedida de siempre.
# Corre desde las pruebas de Field Reports (tests/) o desde el repo de Scanova (tests/camara/).
# Uso:  bash tests/camara/reglas_de_medir_test.sh     (SCANOVA_DIR / FR_DIR para otras rutas)
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$DIR/../ios/App/App/ARMeasureViewController.swift" ]; then RAIZ="$(cd "$DIR/.." && pwd)"; else RAIZ="$(cd "$DIR/../.." && pwd)"; fi
FR="${FR_DIR:-/Users/amilcargonzalez/Downloads/field-report-ios-app}"
if [ -n "$SCANOVA_DIR" ]; then SC="$SCANOVA_DIR"; elif [ -f "$RAIZ/docs/medidas.js" ]; then SC="$RAIZ"; else SC="$RAIZ/../scanova"; fi
OUT="$(mktemp -t reglas).swift"
E=0
python3 - "$RAIZ" "$FR" "$OUT" <<'PYEOF' || E=1
import io, sys, re
raiz, fr, out = sys.argv[1:4]
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
reglas = bloque(v, 'struct ReglasDeMedir {')
prueba = r'''
typealias R = ReglasDeMedir
var pasan = 0, fallan = 0
func ok(_ l: String, _ c: Bool, _ d: String = "") { if c { pasan += 1; print("  ok  " + l) } else { fallan += 1; print("  FALLA " + l + " " + d) } }
func igual(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 0.001 } ?? false }
// ---- la pared, solo el largo ----
let b1 = R.baseboard(largo: 14, shoe: true)
ok("baseboard con shoe molding: Baseboard 14 LF + Shoe Molding 14 LF", b1.material == "Baseboard" && b1.unidad == "LF" && igual(b1.cantidad, 14) && b1.ancho == nil
   && b1.companero == "Shoe Molding" && b1.unidadCompanero == "LF" && igual(b1.cantidadCompanero, 14))
let b2 = R.baseboard(largo: 14, shoe: false)
ok("baseboard sin shoe molding: solo Baseboard 14 LF", b2.companero == nil && b2.unidad == "LF")
let d1 = R.drywallCorte(largo: 14, insulacion: true)
ok("drywall de 1 pie: 'Drywall (1 ft cut)' 14 LF, con ancho 1", d1.material == "Drywall (1 ft cut)" && d1.unidad == "LF" && igual(d1.cantidad, 14) && d1.ancho == 1)
ok("y su insulación: 14 × 1 = 14 SF", d1.companero == "Insulation" && d1.unidadCompanero == "SF" && igual(d1.cantidadCompanero, 14))
ok("drywall de 1 pie sin insulación: sin compañero", R.drywallCorte(largo: 14, insulacion: false).companero == nil)
ok("trim y crown molding: pie lineal", R.lineal("Trim", largo: 9).unidad == "LF" && R.lineal("Crown Molding", largo: 9).unidad == "LF" && igual(R.lineal("Trim", largo: 9).cantidad, 9))
// ---- la pared, largo × alto: SIEMPRE pie cuadrado ----
let p1 = R.pared("Drywall", largo: 14, alto: 4, insulacion: true)
ok("drywall 14 × 4 de una pared con insulación: 56 SF + Insulation 56 SF", p1.unidad == "SF" && igual(p1.cantidad, 56) && p1.companero == "Insulation" && igual(p1.cantidadCompanero, 56))
ok("sin insulación: solo 56 SF", R.pared("Drywall", largo: 14, alto: 4, insulacion: false).companero == nil)
ok("plaster y paneling también llevan la insulación de la pared", R.pared("Plaster", largo: 10, alto: 2, insulacion: true).companero == "Insulation" && R.pared("Paneling", largo: 10, alto: 2, insulacion: true).companero == "Insulation")
ok("otra cosa escrita a mano no lleva insulación sola", R.pared("Wainscoting", largo: 10, alto: 3, insulacion: true).companero == nil)
ok("lo escrito a mano con alto va en SF; sin alto, en LF", R.otro("Wainscoting", largo: 10, ancho: 3).unidad == "SF" && R.otro("Chair rail", largo: 10, ancho: nil).unidad == "LF")
// ---- la insulación de la pared, según lo que contestó al empezar ----
ok("'solo las de afuera' + pared de afuera: sí", R.insulacionDePared("afuera", afuera: true, respuesta: nil) == true)
ok("'solo las de afuera' + pared de adentro: no", R.insulacionDePared("afuera", afuera: false, respuesta: nil) == false)
ok("'solo las de afuera' + no se sabe qué pared: se pregunta (nil)", R.insulacionDePared("afuera", afuera: nil, respuesta: nil) == nil)
ok("'solo las de afuera' + no se sabe + ya contestó esa pared: su respuesta", R.insulacionDePared("afuera", afuera: nil, respuesta: false) == false)
ok("'todas': sí, de afuera y de adentro", R.insulacionDePared("todas", afuera: false, respuesta: nil) == true && R.insulacionDePared("todas", afuera: nil, respuesta: nil) == true)
ok("'mixto': se pregunta una vez en cada pared", R.insulacionDePared("mixto", afuera: true, respuesta: nil) == nil)
ok("'mixto' y ya contestó esa pared: su respuesta (aunque el plano diga otra cosa)", R.insulacionDePared("mixto", afuera: true, respuesta: false) == false)
ok("sin contestar el nivel: se pregunta", R.insulacionDePared(nil, afuera: true, respuesta: nil) == nil)
// ---- el piso ----
let f1 = R.piso("Laminate", largo: 12, ancho: 10, underlayment: true)
ok("laminate 12 × 10 con underlayment: 120 SF + Underlayment 120 SF", f1.unidad == "SF" && igual(f1.cantidad, 120) && f1.companero == "Underlayment" && igual(f1.cantidadCompanero, 120))
ok("hardwood y vinyl también llevan underlayment", R.piso("Hardwood", largo: 1, ancho: 1, underlayment: true).companero == "Underlayment" && R.piso("Vinyl (LVP)", largo: 1, ancho: 1, underlayment: true).companero == "Underlayment")
ok("tile nunca lleva underlayment", R.piso("Tile", largo: 12, ancho: 10, underlayment: true).companero == nil)
ok("underlayment 'sí' en el nivel: sale solo", R.underlayment("si", material: "Laminate", respuesta: nil) == true)
ok("underlayment 'no': no", R.underlayment("no", material: "Laminate", respuesta: nil) == false)
ok("underlayment 'mixto': se pregunta una vez en cada cuarto", R.underlayment("mixto", material: "Laminate", respuesta: nil) == nil)
ok("underlayment 'mixto' ya contestado en ese cuarto: su respuesta", R.underlayment("mixto", material: "Hardwood", respuesta: true) == true)
ok("tile con 'mixto': no se pregunta (no lleva)", R.underlayment("mixto", material: "Tile", respuesta: nil) == false)
let c1 = R.alfombra(largo: 12, ancho: 10, pad: true)
ok("carpet con pad: Carpet 120 SF + Carpet Pad 120 SF", c1.material == "Carpet" && c1.companero == "Carpet Pad" && c1.unidadCompanero == "SF" && igual(c1.cantidadCompanero, 120))
ok("carpet sin pad: solo Carpet", R.alfombra(largo: 12, ancho: 10, pad: false).companero == nil)
ok("tackless strip (piso, solo el largo): LF", R.lineal("Tackless Strip", largo: 40).unidad == "LF")
// ---- el techo ----
ok("techo de drywall con insulación: 120 SF + Insulation 120 SF", R.techo("Drywall", largo: 12, ancho: 10, insulacion: true).companero == "Insulation"
   && igual(R.techo("Drywall", largo: 12, ancho: 10, insulacion: true).cantidadCompanero, 120))
ok("popcorn y plaster también", R.techo("Popcorn / Texture", largo: 1, ancho: 1, insulacion: true).companero == "Insulation" && R.techo("Plaster", largo: 1, ancho: 1, insulacion: true).companero == "Insulation")
ok("insulación del techo 'sí'/'no' sale sola; 'mixto' se pregunta una vez en cada cuarto",
   R.insulacionDeTecho("si", respuesta: nil) == true && R.insulacionDeTecho("no", respuesta: nil) == false && R.insulacionDeTecho("mixto", respuesta: nil) == nil
   && R.insulacionDeTecho("mixto", respuesta: true) == true)
ok("crown molding del techo (solo el largo): LF", R.lineal("Crown Molding", largo: 44).unidad == "LF")
// ---- lo que se contesta después (mixto) ----
ok("con la respuesta de la pared se agrega o se quita la insulación", R.conInsulacion(R.pared("Drywall", largo: 14, alto: 4, insulacion: false), true).companero == "Insulation"
   && R.conInsulacion(R.pared("Drywall", largo: 14, alto: 4, insulacion: true), false).companero == nil)
ok("y el underlayment del cuarto (nunca en tile)", R.conUnderlayment(R.piso("Laminate", largo: 1, ancho: 1, underlayment: false), true).companero == "Underlayment"
   && R.conUnderlayment(R.piso("Tile", largo: 1, ancho: 1, underlayment: false), true).companero == nil)
// ---- la página del nivel ----
ok("la página pide las 3 respuestas", R.Ajuste().faltan == 3 && !R.Ajuste(paredes: "afuera", techo: "si", piso: nil).completo && R.Ajuste(paredes: "afuera", techo: "mixto", piso: "no").completo)
// ---- el aviso ----
ok("aviso de la pared: '✓ Drywall · 14 × 4 = 56 pies² · con insulación'", R.aviso(p1, parte: "wall") == "✓ Drywall · 14 × 4 = 56 pies² · con insulación")
ok("aviso del drywall de 1 pie", R.aviso(d1, parte: "wall") == "✓ Drywall de 1 pie · 14 pies lineales · con insulación")
ok("aviso del zoclo", R.aviso(b1, parte: "wall") == "✓ Baseboard + shoe molding · 14 pies lineales")
ok("aviso del piso", R.aviso(f1, parte: "floor") == "✓ Laminate + underlayment · 120 pies²" && R.aviso(c1, parte: "floor") == "✓ Carpet + pad · 120 pies²")
ok("aviso del techo", R.aviso(R.techo("Drywall", largo: 12, ancho: 10, insulacion: false), parte: "ceiling") == "✓ Drywall de techo · 120 pies² · sin insulación")
print("\n  \(pasan) pasan, \(fallan) fallan")
exit(fallan == 0 ? 0 : 1)
'''
io.open(out, 'w', encoding='utf-8').write('import Foundation\n' + reglas + '\n' + prueba)

# ---- la estructura ----
p = f = 0
def ok(l, c):
    global p, f
    if c: p += 1; print("  ok  " + l)
    else: f += 1; print("  FALLA " + l)
ok("las reglas no usan nada del teléfono (se compilan solas)", 'UIKit' not in reglas and 'ARKit' not in reglas and 'UIColor' not in reglas and 'UIView' not in reglas)
medir = v[v.index('// MARK: - ============ MEDIR PRIMERO, EL MATERIAL AL FINAL'):v.index('// MARK: - ============ UBICARSE DENTRO DEL PLANO')]
ok("medir primero = la cámara nueva + la bandera + un recorrido", 'var medirPrimero: Bool { parteSolaActiva }' in v
   and 'var parteSolaActiva: Bool { experienciaNueva && porMovimiento && esRecorrido && seccionesDisponibles.count >= 2 }' in v)
# La voz apagada en este modo (su pedido: "por ahora cancela al asistente de voz").
ok("la voz no habla en este modo (los avisos se VEN)", 'if medirPrimero && !forzarAunqueMudo {\n            if prioridad == .aviso { mostrarAvisoMudo(text) }\n            return\n        }' in bloque(v, 'private func say(_ text: String'))
ok("no se pide el micrófono ni se escucha", 'if medirPrimero { return }' in bloque(v, 'private func pedirPermisoYEscuchar') and 'if medirPrimero { return }' in bloque(v, 'private func empezarAEscuchar'))
ok("no se pregunta nada hablando", 'if medirPrimero { return }' in bloque(v, 'private func preguntar(_ paso: Paso'))
ok("la bolita (el micrófono) no se ve y la Luz se recorre", 'n.botonOrbita.isHidden = true' in bloque(v, 'fileprivate func ponerBarraSinVoz'))
ok("medir primero no agrega ni una pregunta de voz", 'case masOtraSeccion  // "¿cambiamos de sección, o pasamos a otro cuarto?"\n    }' in v and 'say(' not in medir and 'preguntar(' not in medir and 'preguntarAunqueMudo' not in v)
# Detrás de la bandera.
for firma, marca in [('fileprivate func pintarCamaraNueva', 'if medirPrimero, n.medirActivo, arreglarMedirPrimero('),
                     ('private func panelQueToca', 'if medirPrimero, nueva.preguntaMedir != nil { return .medir }'),
                     ('private func pintarMuelleNuevo', 'if medirPrimero && nueva.medirActivo { pintarMuelleMedir(); return }'),
                     ('@objc fileprivate func gatilloNuevoTocado', 'if medirPrimero && nueva.medirActivo { gatilloMedir(); pintarCamaraNueva(); return }'),
                     ('@objc fileprivate func deshacerNuevoTocado', 'if medirPrimero && nueva.medirActivo { deshacerMedir(); pintarCamaraNueva(); return }'),
                     ('@objc fileprivate func terminarNuevoTocado', 'if medirPrimero && nueva.medirActivo && !nueva.terminarDeVerdad { abrirHojaDelCuarto(); return }'),
                     ('fileprivate func armarCamaraNueva', 'if medirPrimero && maqueta == 0 { prepararMedirPrimero() }')]:
    ok("detrás de la bandera: " + firma.split('func ')[1], marca in bloque(v, firma))
ok("la página del nivel solo se arma con la bandera", 'guard medirPrimero else { return }' in bloque(v, 'fileprivate func armarAjuste'))
# Guardar por el camino de siempre.
gm = bloque(v, 'fileprivate func guardarMedir')
ok("guardar va por el bancarMedida de siempre, con el material y su compañero", 'bancarMedida(opcion)' in gm and 'includeCompanion = g.companero != nil' in gm and 'companionValue: g.companero' in gm)
ok("nadie le pone el compañero a lo ya guardado", re.search(r'items\[[^\]]+\]\.companion\s*=', v) is None)
ok("medir primero no llama a cambiarSeccion: la parte va por elegirParteNueva -> contestar(.queSeccion)", 'cambiarSeccion(' not in medir and 'elegirParteNueva(' in medir)
ok("siguen siendo 5 caminos a cambiarSeccion", len(re.findall(r'cambiarSeccion\((sec|clave)\)', v)) == 5)
ok("la parte y el cuarto solo cambian entre una medida y otra (la regla madre)", 'guard !bloqueoDeParte() else' in bloque(v, 'fileprivate func revisarMedirPrimero')
   and 'medidaEnCurso' in bloque(v, 'fileprivate func bloqueoDeParte') and 'n.preguntaMedir != nil' in bloque(v, 'fileprivate func bloqueoDeParte'))
ok("'¿Ya terminó con esta pared?' desde 1 medida en esa pared, y 'Continuar' la calla", 'medidasEnEstaPared() > 0' in bloque(v, 'private func pedirCambio') and 'if n.cierreCallado { return }' in bloque(v, 'private func pedirCambio'))
ok("Terminar y mandar sigue por el camino de siempre", 'self.nueva.terminarDeVerdad = true\n            self.terminarNuevoTocado()' in v)
ok("el corte de 1 pie va en pie lineal también en la cámara", 'if m.contains("1 ft cut") { return .lineal }' in v)
ok("lo contestado del nivel se guarda por trabajo y nivel", 'Self.llaveAjuste + "|" + trabajoId + "|" + nivelActual' in v and 'arVC.trabajoId = call.getString("trabajo")' in plg)
ok("las maquetas 24-37 no se enciman con las del laboratorio (18-23)", 'arVC.porMovimiento = (24...37).contains(paso)' in plg and '(18...23).contains(paso)' in plg)
try:
    web = rd(fr + '/www/index.html')
    ok("Field Reports no manda la bandera", 'porMovimiento' not in web)
except Exception:
    ok("Field Reports no manda la bandera (no se encontró " + fr + ")", False)
print("\n  estructura: %d pasan, %d fallan" % (p, f))
sys.exit(1 if f else 0)
PYEOF
xcrun swiftc -O -o "${OUT%.swift}" "$OUT" 2>&1 | grep -E "error" | head -5 || true
"${OUT%.swift}" || E=1
# ---- la página (Scanova): lo que llega de la cámara -> las líneas de Measurements ----
node --input-type=module - "$SC/docs/medidas.js" <<'JSEOF' || E=1
const M = await import(process.argv[2]);
let p = 0, f = 0;
const ok = (l, c) => { if (c) { p++; console.log('  ok  ' + l); } else { f++; console.log('  FALLA ' + l); } };
ok("la página cobra 'Drywall (1 ft cut)' por pie lineal", M.unidad('Drywall (1 ft cut)') === 'LF');
const c = M.calcular('Drywall (1 ft cut)', 14, 1);
ok('14 ft con ancho 1: 14 LF (el ancho no lo vuelve SF)', c.linear === 14 && c.sqft === 0 && !c.faltaAlto);
ok("y se lee '14 ft'", M.medidaTexto({ material: 'Drywall (1 ft cut)', largo: 14, ancho: 1 }) === '14 ft');
const base = { nivel: 'First Floor', cuarto: 'Living Room', orden: 1000 };
const filas = M.filasDeCamara([
  { length: 14, width: 1, material: 'Drywall (1 ft cut)', companion: 'Insulation', nivel: 'First Floor', cuarto: 'Living Room', seccion: 'wall' },
  { length: 14, width: 4, material: 'Drywall', companion: 'Insulation', nivel: 'First Floor', cuarto: 'Living Room', seccion: 'wall' },
  { length: 14, material: 'Baseboard', companion: 'Shoe Molding', nivel: 'First Floor', cuarto: 'Living Room', seccion: 'wall' },
  { length: 12, width: 10, material: 'Carpet', companion: 'Carpet Pad', nivel: 'First Floor', cuarto: 'Living Room', seccion: 'floor' },
  { length: 12, width: 10, material: 'Hardwood', companion: 'Underlayment', nivel: 'First Floor', cuarto: 'Living Room', seccion: 'floor' },
  { length: 12, width: 10, material: 'Drywall', companion: 'Insulation', nivel: 'First Floor', cuarto: 'Living Room', seccion: 'ceiling' },
], base);
const linea = (m, s) => filas.filter(x => x.material === m && x.seccion === s).map(x => M.calcular(x.material, x.largo, x.ancho));
ok('cada compañero es su propia línea (6 medidas -> 12 líneas)', filas.length === 12);
ok('la insulación del corte de 1 pie: 14 × 1 = 14 SF', linea('Insulation', 'wall')[0].sqft === 14);
ok('la del drywall 14 × 4: 56 SF', linea('Insulation', 'wall')[1].sqft === 56 && linea('Drywall', 'wall')[0].sqft === 56);
ok('baseboard y shoe molding: 14 LF cada uno', linea('Baseboard', 'wall')[0].linear === 14 && linea('Shoe Molding', 'wall')[0].linear === 14);
ok('carpet y pad: 120 SF cada uno', linea('Carpet', 'floor')[0].sqft === 120 && linea('Carpet Pad', 'floor')[0].sqft === 120);
ok('hardwood y underlayment: 120 SF cada uno', linea('Hardwood', 'floor')[0].sqft === 120 && linea('Underlayment', 'floor')[0].sqft === 120);
ok('la insulación del techo va en el techo: 120 SF', linea('Insulation', 'ceiling')[0].sqft === 120);
ok("'Drywall (1 ft cut)' no sale en las listas para escoger (solo llega de la cámara)", !Object.values(M.MATERIALES).some(l => l.includes('Drywall (1 ft cut)')));
const src = (await import('node:fs')).readFileSync(process.argv[2], 'utf8');
ok("la página manda la bandera solo al manager, y de qué trabajo es", src.includes('porMovimiento: esManager(), trabajo: tid'));
console.log(`\n  página: ${p} pasan, ${f} fallan`);
process.exit(f ? 1 : 0);
JSEOF
exit $E
