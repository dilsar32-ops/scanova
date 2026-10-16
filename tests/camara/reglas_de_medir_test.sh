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
// ---- "underlayment o padding" (16 oct, su prueba): UNA pregunta del nivel para el pad del carpet y el underlayment ----
ok("debajo del carpet va Carpet Pad; del laminate, hardwood y vinyl, Underlayment; tile y lo escrito a mano, nada",
   R.debajoDelPiso("Carpet") == "Carpet Pad" && R.debajoDelPiso("Laminate") == "Underlayment" && R.debajoDelPiso("Hardwood") == "Underlayment"
   && R.debajoDelPiso("Vinyl (LVP)") == "Underlayment" && R.debajoDelPiso("Tile") == nil && R.debajoDelPiso("Cork") == nil)
let c2 = R.piso("Carpet", largo: 12, ancho: 10, underlayment: true)
ok("piso 'sí' + carpet: Carpet 120 SF + Carpet Pad 120 SF (sin preguntar el pad)", c2.material == "Carpet" && c2.unidad == "SF" && igual(c2.cantidad, 120)
   && c2.companero == "Carpet Pad" && c2.unidadCompanero == "SF" && igual(c2.cantidadCompanero, 120))
ok("piso 'no' + carpet: solo Carpet", R.piso("Carpet", largo: 12, ancho: 10, underlayment: false).companero == nil)
ok("alfombra(pad:) da lo mismo que piso(\"Carpet\")", R.alfombra(largo: 12, ancho: 10, pad: true) == c2 && R.alfombra(largo: 12, ancho: 10, pad: false) == R.piso("Carpet", largo: 12, ancho: 10, underlayment: false))
ok("la respuesta del nivel decide el pad: 'si' sí, 'no' no, 'mixto' se pregunta en el cuarto",
   R.underlayment("si", material: "Carpet", respuesta: nil) == true && R.underlayment("no", material: "Carpet", respuesta: nil) == false
   && R.underlayment("mixto", material: "Carpet", respuesta: nil) == nil && R.underlayment("mixto", material: "Carpet", respuesta: false) == false)
ok("tile no lleva ni con 'si' (y nunca se pregunta)", R.underlayment("si", material: "Tile", respuesta: nil) == false && R.piso("Tile", largo: 1, ancho: 1, underlayment: true).companero == nil)
ok("mixto contestado en el cuarto: carpet con Carpet Pad, laminate con Underlayment",
   R.conUnderlayment(R.piso("Carpet", largo: 12, ancho: 10, underlayment: false), true).companero == "Carpet Pad"
   && R.conUnderlayment(R.piso("Carpet", largo: 12, ancho: 10, underlayment: true), false).companero == nil
   && R.conUnderlayment(R.piso("Carpet", largo: 12, ancho: 10, underlayment: false), true).unidadCompanero == "SF")
ok("aviso del carpet con pad que salió solo", R.aviso(c2, parte: "floor") == "✓ Carpet + pad · 120 pies²")
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
// ---- TODA LA PARED (16 oct): las medidas del plano, menos sus puertas y ventanas ----
let ven = R.Abertura(p: SIMD2(6, 0), esVentana: true, ancho: 3, alto: 4), pue = R.Abertura(p: SIMD2(14, 0.3), esVentana: false, ancho: 3, alto: 6.7)
let otraPared = R.Abertura(p: SIMD2(20, 8), esVentana: false, ancho: 3, alto: 6.7), sinTam = R.Abertura(p: SIMD2(10, 0), esVentana: true, ancho: 0, alto: 0)
let enSur = R.aberturasEnLaPared(a: SIMD2(0, 0), b: SIMD2(20, 0), aberturas: [ven, pue, otraPared, sinTam])
ok("en la pared sur caen la ventana y la puerta (no la de la pared de al lado)", enSur.conMedida.count == 2 && enSur.conMedida.contains(ven) && enSur.conMedida.contains(pue))
ok("la ventana sin medida en el plano no se resta: se cuenta aparte", enSur.sinMedida == 1)
ok("la puerta de la pared este cae en la pared este", R.aberturasEnLaPared(a: SIMD2(20, 0), b: SIMD2(20, 12), aberturas: [ven, pue, otraPared]).conMedida == [otraPared])
ok("la misma ventana dos veces cuenta una", R.aberturasEnLaPared(a: SIMD2(0, 0), b: SIMD2(20, 0), aberturas: [ven, R.Abertura(p: SIMD2(6.3, 0.1), esVentana: true, ancho: 3, alto: 4)]).conMedida.count == 1)
let gemela = R.aberturasEnLaPared(a: SIMD2(0, 0), b: SIMD2(20, 0), aberturas: [R.Abertura(p: SIMD2(14, 0), esVentana: false, ancho: 0, alto: 0), R.Abertura(p: SIMD2(14.2, 0.35), esVentana: false, ancho: 3, alto: 6.7)])
ok("la misma puerta de los dos cuartos: cuenta una, la que trae medida", gemela.conMedida.count == 1 && gemela.sinMedida == 0 && igual(gemela.conMedida.first?.ancho, 3))
ok("una abertura a más de 1 pie de la línea no es de esa pared", R.aberturasEnLaPared(a: SIMD2(0, 0), b: SIMD2(20, 0), aberturas: [R.Abertura(p: SIMD2(6, 1.6), esVentana: true, ancho: 3, alto: 4)]).conMedida.isEmpty)
ok("ni una que queda fuera de su largo", R.aberturasEnLaPared(a: SIMD2(0, 0), b: SIMD2(20, 0), aberturas: [R.Abertura(p: SIMD2(21.5, 0), esVentana: false, ancho: 3, alto: 6.7)]).conMedida.isEmpty)
ok("lo que se resta: 3 × 4 + 3 × 6.7 = 32.1 pies²", igual(R.restaDeLaPared(largo: 20, alto: 8.1, aberturas: enSur.conMedida), 32.1))
ok("una abertura más alta que la pared se recorta al alto", igual(R.restaDeLaPared(largo: 20, alto: 6, aberturas: [pue]), 18))
ok("nunca se resta más que la pared", igual(R.restaDeLaPared(largo: 3, alto: 6, aberturas: [pue, R.Abertura(p: SIMD2(1, 0), esVentana: false, ancho: 3, alto: 6.7)]), 18))
let te = R.conLaResta(R.pared("Drywall", largo: 20, alto: 8.1, insulacion: true), aberturas: enSur.conMedida)
ok("toda la pared: 20 × 8.1 − 32.1 = 129.9 pies², y su insulación igual", igual(te.cantidad, 129.9) && igual(te.cantidadCompanero, 129.9) && igual(te.menos, 32.1))
ok("lo restado va en inglés al reporte: '1 door, 1 window'", te.menosQue == "1 door, 1 window" && R.nombreDeAberturas(enSur.conMedida, ingles: false) == "1 puerta y 1 ventana")
ok("el largo y el alto se quedan como son (el reporte dice 20 × 8.1)", igual(te.largo, 20) && igual(te.ancho, 8.1))
ok("la insulación que se pone después conserva la resta", igual(R.conInsulacion(R.conLaResta(R.pared("Drywall", largo: 20, alto: 8.1, insulacion: false), aberturas: enSur.conMedida), true).cantidadCompanero, 129.9))
ok("sin aberturas no se resta nada", R.conLaResta(R.pared("Drywall", largo: 20, alto: 8.1, insulacion: false), aberturas: []).menos == 0)
ok("lo que va por pie lineal no se toca (drywall de 1 pie)", R.conLaResta(R.drywallCorte(largo: 20, insulacion: true), aberturas: enSur.conMedida) == R.drywallCorte(largo: 20, insulacion: true))
ok("aviso de la pared entera, corto: '✓ Drywall · toda la pared · 129.9 pies² · con insulación'", R.aviso(te, parte: "wall") == "✓ Drywall · toda la pared · 129.9 pies² · con insulación")
ok("sin resta el aviso es el de siempre", R.aviso(p1, parte: "wall") == "✓ Drywall · 14 × 4 = 56 pies² · con insulación")
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
# Su prueba (16 oct, 3:31): "no puedo seguir midiendo más de una medida… eso ya lo teníamos arreglado". Medir es como
# siempre: el largo por esquinas sin límite (lo cierra "Listo · el largo"), y el alto o el ancho también por esquinas.
gat = bloque(v, 'fileprivate func gatilloMedir')
ok("el + marca esquinas del largo sin límite (no cierra solo el largo)", 'addTapped()' in gat and 'finishPathTapped' not in gat)
ok("el + también marca el alto o el ancho por esquinas", 'case .measuringWidth, .widthDone:\n            addTapped()' in gat)
tel = bloque(v, 'fileprivate func terminarElLargo')
ok("'Listo · el largo' cierra el largo con la función de siempre y pregunta si mide el alto/ancho", 'finishPathTapped()' in tel and 'abrirPregunta(.segunda)' in tel)
ok("el alto/ancho empieza con la función de siempre (addWidthTapped), sin pegarse a la última esquina", 'addWidthTapped()' in bloque(v, 'fileprivate func empezarAncho') and 'empezarSegunda' not in v)
ok("Deshacer en el alto/ancho quita un punto a la vez (undoTapped de siempre)", 'undoTapped()\n            if stage == .lengthDone { abrirPregunta(.segunda) }' in bloque(v, 'fileprivate func deshacerMedir'))
mm = bloque(v, 'fileprivate func pintarMuelleMedir')
ok("con el largo cerrado el botón dice 'Alto' (pared) o 'Ancho' (piso, techo), como antes", 'titulo = segundaPalabra.capitalized' in mm and 'self?.empezarAncho()' in mm)
ok("el + se queda vivo en el alto/ancho ya medido (un ancho que dobla se sigue)", 'let masVivo = !roomName.isEmpty && stage != .lengthDone' in mm)
# Su prueba del 16 oct (8:00): no le salió la página del nivel, la pared se quería guardar como techo y salía el "Ojo" viejo.
ok("la página de las 3 preguntas sale SIEMPRE al abrir, con lo contestado ya marcado", 'abrirAjuste(volver: false)\n    }' in bloque(v, 'fileprivate func prepararMedirPrimero') and 'entrarAMedir()' not in bloque(v, 'fileprivate func prepararMedirPrimero'))
ok("el aviso viejo 'Ojo: veo la pared, pero esta medida es de techo' no corre en medir primero", 'guard !(medirPrimero && nueva.medirActivo) else { return }' in bloque(v, 'private func updateSurfaceAssistant'))
ok("la mira no se pone 'equivocada' en medir primero", '!(medirPrimero && n.medirActivo), let s = currentSurface()' in v)
lm = bloque(v, 'fileprivate func listoMedir'); rp = bloque(v, 'fileprivate func revisarParteDeLaMedida')
ok("Listo y 'Listo · el largo' revisan la parte por los puntos de la medida (si no la escogió a mano)",
   'revisarParteDeLaMedida("listo")' in lm and 'revisarParteDeLaMedida("largo")' in bloque(v, 'fileprivate func terminarElLargo')
   and 'parteDeEstaMedida()' in rp and 'ponerParteDeLaMedida(p)' in rp and '!n.parteAMano' in rp)
ok("cambiar la parte de la medida no borra sus esquinas ni usa cambiarSeccion", 'cambiarSeccion(' not in bloque(v, 'private func ponerParteDeLaMedida') and 'pathPoints' not in bloque(v, 'private func ponerParteDeLaMedida'))
gm2 = bloque(v, 'fileprivate func gatilloMedir')
ok("la primera esquina toma la parte a la que apunta claro, sin brincarse '¿Ya terminó?' ni su 'Continuar'",
   'n.clasificador.ahoraMismo(ahora: ahora)' in gm2 and '!(section == "wall" && (n.cierreCallado || medidasEnEstaPared() > 0))' in gm2)
ok("la bitácora anota medir primero (cada +, la parte de la medida, cada cambio y cada guardada)", 'anotarMedir("mas"' in gm2
   and 'anotarMedir("guardar"' in bloque(v, 'fileprivate func guardarMedir') and 'anotarMedir("resumen"' in v
   and '(medirPrimero && nueva.medirActivo)' in bloque(v, 'fileprivate func anotarBitacora'))
ok("en medir primero el seguro de la parte es solo una medida a medias o algo abierto", 'if medirPrimero && n.medirActivo {\n            return medidaEnCurso' in bloque(v, 'fileprivate func bloqueoDeParte'))
ok("pared y techo en 1 s; el piso pide 2 s (leer la pantalla no es el piso)", 'estable(por: 1.0, ahora: ahora)' in v and 'estable(por: 2.0, ahora: ahora) != "floor"' in v)
ok("la maqueta 38 recorre su prueba por las funciones de verdad (+, Listo el largo, Alto, Listo)", 'case 38:' in v and 'nueva.puntosDeMaqueta' in bloque(v, '@objc private func addTapped') and v.count('gatilloNuevoTocado(); gatilloNuevoTocado(); terminarElLargo()') == 2)
ok("Terminar y mandar sigue por el camino de siempre", 'self.nueva.terminarDeVerdad = true\n            self.terminarNuevoTocado()' in v)
ok("el corte de 1 pie va en pie lineal también en la cámara", 'if m.contains("1 ft cut") { return .lineal }' in v)
# "underlayment o padding" (16 oct): UNA pregunta del nivel; ya no hay "¿Lleva pad?" aparte.
aj = bloque(v, 'private func pintarAjuste')
ok("la página del nivel: 'Piso · ¿Tiene underlayment o padding?' con Sí / No / Mixto",
   '("piso", "Piso", "¿Tiene underlayment o padding?", [("si", "Sí", "todo el nivel"), ("no", "No", "ningún cuarto"), ("mixto", "Mixto", "en cada cuarto")])' in aj
   and 'el underlayment y el padding salen solos' in aj)
pm = bloque(v, 'fileprivate func armarPanelMedir')
ok("ya no hay pregunta aparte del pad", 'case .pad' not in v and '.pad)' not in v and '¿Lleva pad?' not in v
   and 'fileprivate enum PreguntaMedir: Equatable { case que, otroLineal, shoe, matPared, insulPared, piso, underCuarto, techo, techoCuarto, lineal1, cierre, cuarto, segunda, paredEntera }' in v)
ok("el carpet va por resolverPiso como los demás pisos", 'listaDeMateriales(ReglasDeMedir.materialesPiso, sugerido: nil, sub: "\\(pies(A)) pies²") { s, m in s.resolverPiso(m) }' in pm)
ok("mixto: '¿<cuarto> tiene underlayment o padding?' una vez por cuarto (padding si es carpet)",
   '"¿\\(roomName) tiene underlayment o padding?"' in pm and 'ReglasDeMedir.debajoDelPiso(m) == "Carpet Pad" ? "padding" : "underlayment"' in pm
   and 'case .underCuarto: n.underDeCuarto[n.clavePendiente] = si; guardarMedir(ReglasDeMedir.conUnderlayment(g, si))' in bloque(v, 'private func contestarPendiente'))
tu = bloque(v, 'private func textoUnder')
ok("la ayuda del panel del piso habla de underlayment o padding", 'debajo del carpet, laminate, hardwood o vinyl' in tu and 'Sin underlayment ni padding' in tu and 'tiene underlayment o padding' in tu)
ok("lo contestado con la pregunta vieja no cuenta: la llave del nivel es v2", 'private static let llaveAjuste = "scanova.medirPrimero.ajuste.v2"' in v)
ok("la maqueta 37 guarda el carpet por las reglas de verdad (resolverPiso)", 'resolverPiso("Carpet")' in bloque(v, 'private func maquetaMedirPrimeroPaso') and 'ReglasDeMedir.alfombra(' not in v[:v.index('struct ReglasDeMedir {')])
ok("lo contestado del nivel se guarda por trabajo y nivel", 'Self.llaveAjuste + "|" + trabajoId + "|" + nivelActual' in v and 'arVC.trabajoId = call.getString("trabajo")' in plg)
ok("las maquetas 24-42 no se enciman con las del laboratorio (18-23)", 'arVC.porMovimiento = (24...42).contains(paso)' in plg and '(18...23).contains(paso)' in plg)
# ---- TODA LA PARED (16 oct) ----
rm = bloque(v, 'fileprivate func revisarMedirPrimero')
tp = bloque(v, 'private func tocaPreguntarParedEntera')
ok("'¿Toda la pared o una parte?' se pregunta desde el detector, después de saber qué pared es", 'if let i = tocaPreguntarParedEntera(ahora) { abrirParedEntera(i) }' in rm
   and rm.index('tocaPreguntarParedEntera') > rm.index('// 3. OTRA PARED'))
ok("solo apuntándole a esa pared 1.5 s, con la ubicación firme, una vez, sin medidas en ella ni nada a medias",
   'c.i == i, ahora - c.desde >= 1.5' in tp and 'ubicacionFirme()' in tp and '!n.paredEnteraPreguntada.contains(claveParedEntera(i))' in tp
   and 'medidasEnEstaPared() == 0' in tp and '!medidaEnCurso' in tp and 'n.preguntaMedir == nil' in tp)
ap = bloque(v, 'fileprivate func aceptarParedEntera')
ok("'Toda la pared' es un largo dictado del plano (sin esquinas) y va al material", 'largoDictado = true' in ap and 'pathTotalFeet = d.largo' in ap and 'abrirPregunta(.matPared)' in ap
   and 'pathPoints.isEmpty, widthPoints.isEmpty' in ap)
ok("sin el alto en el plano se marca solo el alto con +", 'empezarAncho()' in ap)
ok("sin el largo dictado no queda pared entera (no se le resta a otra medida)", 'didSet { if !largoDictado { nueva.paredEntera = nil } }' in v)
bm = bloque(v, 'private func bancarMedida')
ok("bancarMedida guarda la resta UNA vez y solo con alto", 'let resta = currentWidthFeet != nil ? restaAlGuardar : nil' in bm and 'restaAlGuardar = nil' in bm
   and 'menos: resta?.menos ?? 0' in bm)
ok("la resta viaja a la página (menos y menosQue)", 'if item.menos > 0 { d["menos"] = item.menos; d["menosQue"] = item.menosQue }' in plg)
ok("guardar y la insulación usan la pared entera", 'let g = conLaParedEntera(g0)' in bloque(v, 'fileprivate func guardarMedir')
   and 'conLaParedEntera(' in bloque(v, 'private func resolverPared'))
ok("la insulación de la pared entera mira la pared completa del plano", 'claseDeLaMedida(tramosFijos: [(indice: pe.indice, t0: 0, t1: pe.largo)])' in bloque(v, 'private func claseParaInsulacion'))
ok("'No era toda la pared' y Deshacer la quitan completa (nunca una guardada)", 'cancelarMedidaEnCurso(hablar: false)' in bloque(v, 'fileprivate func cancelarParedEntera')
   and 'cancelarParedEntera(); return' in bloque(v, 'fileprivate func deshacerMedir'))
ok("los totales de la cámara restan lo de la pared entera", 'max(0, w * largo - menos)' in bloque(v, 'private func cuentaDe') and 'menos: x.menos' in bloque(v, 'private func totalesTexto'))
ok("tocar MEDIDA vuelve a preguntar (si contestó 'Una parte' por error)", 'if let i = paredEnteraAMano() { abrirParedEntera(i)' in bloque(v, '@objc fileprivate func rielMaterialTocado'))
ok("las maquetas 39-42 enseñan la pregunta, el material, la guardada y un plano sin alto", 'case 39, 40, 41, 42:' in v)
ok("las puertas que solo vio el cuarto de al lado también se restan", 'cuartosDelMarco(m).filter { Self.clave($0.nombre) != Self.clave(roomName) }.flatMap { $0.senas }' in bloque(v, 'fileprivate func datosParedEntera'))
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
ok("los nombres que manda la cámara son los de la página: Carpet -> 'Carpet Pad', Laminate/Vinyl -> 'Underlayment', ambos SF en el piso",
   M.ACOMPANANTE['Carpet'] === 'Carpet Pad' && M.ACOMPANANTE['Laminate'] === 'Underlayment' && M.ACOMPANANTE['Vinyl (LVP)'] === 'Underlayment'
   && M.MATERIALES.floor.includes('Carpet Pad') && M.MATERIALES.floor.includes('Underlayment') && M.unidad('Carpet Pad') === 'SF' && M.unidad('Underlayment') === 'SF'
   && !M.ACOMPANANTE['Tile']);
ok("'Drywall (1 ft cut)' no sale en las listas para escoger (solo llega de la cámara)", !Object.values(M.MATERIALES).some(l => l.includes('Drywall (1 ft cut)')));
// ---- TODA LA PARED (16-oct): la página resta lo que dice la cámara ----
const pe = M.filasDeCamara([{ length: 20, width: 8.1, material: 'Drywall', companion: 'Insulation', nivel: 'First Floor', cuarto: 'Living Room', seccion: 'wall', menos: 32.1, menosQue: '1 door, 1 window' },
  { length: 20, material: 'Baseboard', companion: 'Shoe Molding', nivel: 'First Floor', cuarto: 'Living Room', seccion: 'wall', menos: 32.1 }], base);
const neto = (x) => M.calcular(x.material, x.largo, x.ancho, x.menos).sqft;
ok('la pared entera: 20 × 8.1 − 32.1 = 129.9 SF, y su insulación igual', neto(pe[0]) === 129.9 && pe[1].material === 'Insulation' && neto(pe[1]) === 129.9);
ok("y se lee '20 × 8.1 ft − 32.1 sq ft (1 door, 1 window)'", M.medidaTexto(pe[0]) === '20 × 8.1 ft − 32.1 sq ft (1 door, 1 window)');
ok('lo de pie lineal nunca lleva resta (baseboard)', pe[2].menos === undefined && pe[3].menos === undefined && M.calcular('Baseboard', 20, null, 32.1).linear === 20);
ok('sin resta todo es igual que antes', M.calcular('Drywall', 14, 4).sqft === 56 && M.calcular('Drywall', 14, 4, 0).sqft === 56 && filas.every(x => x.menos === undefined));
ok('nunca negativo', M.calcular('Drywall', 3, 2, 50).sqft === 0);
const g = M.agrupar(pe.map((x, i) => ({ ...x, id: 'x' + i, created_at: '' })), [], []);
ok('los totales (y el PDF, que sale de agrupar) restan: Drywall 129.9 SF', g.partidas.find(x => x.material === 'Drywall').sqft === 129.9);
const src = (await import('node:fs')).readFileSync(process.argv[2], 'utf8');
ok('al guardar lo de la cámara, la resta va solo si la trae', src.includes("if(num(n.menos)){ fila.menos = n.menos; fila.menos_que = n.menos_que || null; }"));
ok('en el editor se puede quitar la resta', src.includes('id="medMenos"') && src.includes('fila.menos = null; fila.menos_que = null;'));
ok("la página manda la bandera solo al manager, y de qué trabajo es", src.includes('porMovimiento: esManager(), trabajo: tid'));
console.log(`\n  página: ${p} pasan, ${f} fallan`);
process.exit(f ? 1 : 0);
JSEOF
exit $E
