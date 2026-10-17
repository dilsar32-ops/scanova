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
// La revisión del 16 oct: una ventana arriba de un corte bajo no se resta (antes se restaba 2 ft × su ancho).
let ventanaAlta = R.Abertura(p: SIMD2(6, 0), esVentana: true, ancho: 3, alto: 4, abajo: 3)
ok("ventana a 3 ft del piso en un corte de 2 ft: no se resta nada", igual(R.restaDeLaPared(largo: 20, alto: 2, aberturas: [ventanaAlta]), 0))
ok("la misma ventana en la pared entera de 8 ft: 3 × 4 = 12", igual(R.restaDeLaPared(largo: 20, alto: 8, aberturas: [ventanaAlta]), 12))
ok("ventana que empieza a 1.5 ft en un corte de 2 ft: solo el medio pie que cae adentro (3 × 0.5)", igual(R.restaDeLaPared(largo: 20, alto: 2, aberturas: [R.Abertura(p: SIMD2(6, 0), esVentana: true, ancho: 3, alto: 4, abajo: 1.5)]), 1.5))
ok("ventana sin altura del piso en un corte bajo: no se resta (no se sabe)", igual(R.restaDeLaPared(largo: 20, alto: 2, aberturas: [ven]), 0))
ok("puerta sin altura del piso en un corte de 2 ft: empieza en el piso (3 × 2)", igual(R.restaDeLaPared(largo: 20, alto: 2, aberturas: [pue]), 6))
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
// ---- PISO / TECHO COMPLETO (16 oct): la caja menos lo que sobra = el área de verdad del cuarto ----
let enL = R.conLaFormaDelCuarto(R.piso("Laminate", largo: 20, ancho: 12, underlayment: true), area: 200)
ok("piso en L: 20 × 12 − 40 = 200 pies², y su underlayment igual", igual(enL.cantidad, 200) && igual(enL.cantidadCompanero, 200) && igual(enL.menos, 40) && enL.menosQue == "room shape")
ok("cuarto rectángulo: no se resta nada", R.conLaFormaDelCuarto(R.techo("Drywall", largo: 20, ancho: 12, insulacion: true), area: 240).menos == 0)
ok("medio pie² o menos es ruido: no se resta", R.conLaFormaDelCuarto(R.piso("Tile", largo: 10, ancho: 10, underlayment: false), area: 99.6).menos == 0)
ok("nunca más que la caja", igual(R.conLaFormaDelCuarto(R.piso("Tile", largo: 10, ancho: 10, underlayment: false), area: 0.0001).cantidad, 0.0001))
// ---- (16 oct, idea 1) EL CORTE PARCIAL: sus puertas y arcos, desde dónde arranca, y su baseboard ----
let puertaSur = R.Abertura(p: SIMD2(14, 0), esVentana: false, ancho: 3, alto: 6.7, abajo: 0)
let ventanaSur = R.Abertura(p: SIMD2(6, 0), esVentana: true, ancho: 3, alto: 4, abajo: 3)
let arco = R.Abertura(p: SIMD2(10, 12), esVentana: false, ancho: 4, alto: 7, abajo: 0, esPaso: true)
let tramo = R.aberturasEnElTramo(a: SIMD2(0, 0), b: SIMD2(20, 0), t0: 8, t1: 20, aberturas: [puertaSur, ventanaSur])
ok("de x=8 a x=20 entra la puerta (su centro) y no la ventana", tramo.conMedida.count == 1 && igual(tramo.conMedida.first?.ancho, 3) && !(tramo.conMedida.first?.esVentana ?? true))
ok("una puerta con el centro fuera de las esquinas no cuenta", R.aberturasEnElTramo(a: SIMD2(0, 0), b: SIMD2(20, 0), t0: 0, t1: 13.5, aberturas: [puertaSur]).conMedida.isEmpty)
ok("una esquina a media puerta recorta su ancho (2.5)", igual(R.aberturasEnElTramo(a: SIMD2(0, 0), b: SIMD2(20, 0), t0: 13, t1: 20, aberturas: [puertaSur]).conMedida.first?.ancho, 2.5))
ok("con la pared al revés también la encuentra", igual(R.aberturasEnElTramo(a: SIMD2(20, 0), b: SIMD2(0, 0), t0: 0, t1: 12, aberturas: [puertaSur]).conMedida.first?.ancho, 3))
ok("un arco sin medida se cuenta aparte", R.aberturasEnElTramo(a: SIMD2(0, 12), b: SIMD2(20, 12), t0: 0, t1: 20, aberturas: [R.Abertura(p: SIMD2(10, 12), esVentana: false, ancho: 0, alto: 0, esPaso: true)]).sinMedida == 1)
// ---- (revisión 3) LOS TRAMOS JUNTADOS: un + a media puerta no parte la puerta ----
let puerta14 = R.Abertura(p: SIMD2(6.5, 0), esVentana: false, ancho: 3, alto: 6.7, abajo: 0)
func puertasDe(_ trs: [(indice: Int, t0: Double, t1: Double)]) -> [R.Abertura] {
    R.tramosUnidos(trs).flatMap { R.aberturasEnElTramo(a: SIMD2(0, 0), b: SIMD2(14, 0), t0: $0.t0, t1: $0.t1, aberturas: [puerta14]).conMedida }
}
let dosMas = puertasDe([(indice: 1, t0: 0, t1: 14)]), tresMas = puertasDe([(indice: 1, t0: 0, t1: 6), (indice: 1, t0: 6, t1: 14)])
ok("(revisión 3) tres + y el de en medio a media puerta (0, 6, 14): la puerta entera, 6 pies² del corte de 2 ft y baseboard 11, igual que dos +",
   tresMas.count == 1 && igual(tresMas.first?.ancho, 3) && igual(R.restaDeLaPared(largo: 14, alto: 2, aberturas: tresMas), 6)
   && igual(R.baseboardDeLaPared(largo: 14, aberturas: tresMas), 11) && igual(R.restaDeLaPared(largo: 14, alto: 2, aberturas: dosMas), 6))
let enCentro = puertasDe([(indice: 1, t0: 0, t1: 6.5), (indice: 1, t0: 6.5, t1: 14)])
ok("(revisión 3) el + justo en el centro de la puerta: la cuenta una vez, entera", enCentro.count == 1 && igual(enCentro.first?.ancho, 3))
let saltado = puertasDe([(indice: 1, t0: 0, t1: 6), (indice: 1, t0: 6.4, t1: 14)])
ok("(revisión 3) el pedacito de menos de 1 ft que no se cuenta (+ en 0, 6, 6.4, 14): la puerta entera", saltado.count == 1 && igual(saltado.first?.ancho, 3))
let vuelta = R.tramosUnidos([(indice: 0, t0: 6, t1: 14), (indice: 1, t0: 0, t1: 12), (indice: 2, t0: 0, t1: 14), (indice: 3, t0: 0, t1: 12), (indice: 0, t0: 0, t1: 6)])
ok("(revisión 3) empezar a media pared y darle la vuelta al cuarto: la pared 1 queda en un solo tramo de 0 a 14",
   vuelta.count == 4 && vuelta[0].indice == 0 && igual(vuelta[0].t0, 0) && igual(vuelta[0].t1, 14) && vuelta.map { $0.indice } == [0, 1, 2, 3])
let hueco = R.tramosUnidos([(indice: 0, t0: 0, t1: 4), (indice: 0, t0: 9, t1: 14)])
ok("(revisión 3) un hueco de verdad (más de 1 ft sin caminar) no se junta", hueco.count == 2 && igual(hueco[0].t1, 4) && igual(hueco[1].t0, 9))
let cr = R.conLaRestaDelCorte(R.pared("Drywall", largo: 12, alto: 2, insulacion: true), aberturas: tramo.conMedida, desde: 0)
ok("corte de 2 ft con la puerta: 24 − 6 = 18, la insulación igual, '1 door'", igual(cr.cantidad, 18) && igual(cr.cantidadCompanero, 18) && cr.menosQue == "1 door")
ok("el baseboard del corte: 12 − 3 = 9; con un arco de 4 ft: 8", igual(R.baseboardDeLaPared(largo: 12, aberturas: tramo.conMedida), 9) && igual(R.baseboardDeLaPared(largo: 12, aberturas: [arco]), 8))
ok("parche de 4 a 6 ft sobre la puerta: 6; de 7 a 8: 0; desde el piso, lo de siempre (32.1)",
   igual(R.restaDeLaPared(largo: 12, alto: 2, aberturas: [puertaSur], desde: 4), 6) && igual(R.restaDeLaPared(largo: 12, alto: 1, aberturas: [puertaSur], desde: 7), 0)
   && igual(R.restaDeLaPared(largo: 20, alto: 8.1, aberturas: enSur.conMedida, desde: 0), 32.1))
ok("una ventana arriba del corte no se nombra", R.conLaRestaDelCorte(R.pared("Drywall", largo: 20, alto: 2, insulacion: false), aberturas: [puertaSur, ventanaSur], desde: 0).menosQue == "1 door")
ok("sin aberturas y en pie lineal, igual que antes", R.conLaRestaDelCorte(R.pared("Drywall", largo: 12, alto: 2, insulacion: false), aberturas: [], desde: 0) == R.pared("Drywall", largo: 12, alto: 2, insulacion: false)
   && R.conLaRestaDelCorte(R.drywallCorte(largo: 12, insulacion: true), aberturas: [puertaSur], desde: 0) == R.drywallCorte(largo: 12, insulacion: true))
ok("los arcos en el reporte y en la cámara", R.nombreDeAberturas([puertaSur, arco, ventanaSur], ingles: true) == "1 door, 1 opening, 1 window"
   && R.nombreDeAberturas([puertaSur, arco, ventanaSur], ingles: false) == "1 puerta, 1 arco y 1 ventana" && R.nombreDeAberturas([puertaSur, ventanaSur], ingles: false) == "1 puerta y 1 ventana")
ok("lo restado: 'la puerta', 'el arco', '1 puerta y 1 arco'", R.loRestado([puertaSur]) == "la puerta" && R.loRestado([arco]) == "el arco" && R.loRestado([puertaSur, arco]) == "1 puerta y 1 arco")
ok("cocina, baño y lavandería no tienen atajos", R.cuartoSinAtajos("Kitchen") && R.cuartoSinAtajos("Master Bathroom") && R.cuartoSinAtajos("Baño") && R.cuartoSinAtajos("Laundry Room") && R.cuartoSinAtajos("Cocina") && !R.cuartoSinAtajos("Bedroom 2") && !R.cuartoSinAtajos("Living Room"))
ok("arranca en el piso: medio pie o menos", R.arranqueDelPiso == 0.5)
ok("el renglón de la resta", R.textoDeLaResta(largo: 14, alto: 2, restan: [puertaSur], porque: nil, sinMedida: 0) == "14 ft × 2 ft − la puerta"
   && R.textoDeLaResta(largo: 12, alto: 2, restan: [], porque: "falta ubicarse", sinMedida: 0) == "12 ft × 2 ft · sin restar puertas: falta ubicarse")
ok("el renglón del baseboard", R.textoDelBaseboard(arranque: 0, largo: 12, aberturas: [], incluye: (true, true)) == "Baseboard + shoe · 12 ft"
   && R.textoDelBaseboard(arranque: 0, largo: 14, aberturas: [puertaSur], incluye: (true, true)) == "Baseboard + shoe · 11 ft (sin la puerta)"
   && R.textoDelBaseboard(arranque: 0, largo: 12, aberturas: [puertaSur], incluye: nil) == "Baseboard 9 ft (sin la puerta) · se pregunta en Listo"
   && R.textoDelBaseboard(arranque: nil, largo: 12, aberturas: [], incluye: (true, true)) == "Sin baseboard: no veo el piso"
   && R.textoDelBaseboard(arranque: 4, largo: 12, aberturas: [], incluye: (true, true)) == "Sin baseboard: el corte no llega al piso"
   && R.textoDelBaseboard(arranque: 0, largo: 12, aberturas: [], incluye: (false, false)) == "Sin baseboard (así contestó)")
// ---- (16 oct, ideas 3 y 5) EL ALTO CON UN +, LA BANDA Y EL MATERIAL PUESTO ----
let esq = [SIMD3<Double>(0, 0.02, 0), SIMD3<Double>(3.6576, 0.02, 0)]
ok("Otro alto: un + a 0.61 m del piso = 2 ft", igual(R.altoDeUnPunto(punto: SIMD3(1.8, 0.6096, 0.03), piso: 0, esquinas: esq).pies, 2.0))
ok("un + a 0.5 m de la pared: no vale", R.altoDeUnPunto(punto: SIMD3(1.8, 0.6, 0.5), piso: 0, esquinas: esq).porque == "lejos")
ok("un + en el piso: no vale", R.altoDeUnPunto(punto: SIMD3(1.8, 0.05, 0), piso: 0, esquinas: esq).porque == "bajo")
ok("un + a 4 m: no vale", R.altoDeUnPunto(punto: SIMD3(1.8, 4.0, 0), piso: 0, esquinas: esq).porque == "alto")
ok("con una esquina no hay alto", R.altoDeUnPunto(punto: SIMD3(1.8, 0.6, 0), piso: 0, esquinas: [esq[0]]).pies == nil)
ok("el alto se cuenta desde el piso visto (piso a -1.40 m)", igual(R.altoDeUnPunto(punto: SIMD3(1.8, -0.7904, 0), piso: -1.4, esquinas: [SIMD3(0, -1.38, 0), SIMD3(3.6576, -1.38, 0)]).pies, 2.0))
ok("el piso: el más alto debajo de las esquinas, no el más grande", R.pisoBajoLasEsquinas([(y: -1.40, area: 8), (y: -1.58, area: 20)], esquinasY: [-1.38, -1.39]) == -1.40)
ok("un pedacito de piso (0.2 m²) no es el piso", R.pisoBajoLasEsquinas([(y: -1.40, area: 0.2)], esquinasY: [-1.38]) == nil)
ok("esquinas en la línea del corte: el piso de abajo vale", R.pisoBajoLasEsquinas([(y: -1.40, area: 8)], esquinasY: [-0.79]) == -1.40)
ok("un piso arriba de las esquinas no es el suyo", R.pisoBajoLasEsquinas([(y: -0.90, area: 8)], esquinasY: [-1.40]) == nil)
ok("sin esquinas: el piso más grande", R.pisoBajoLasEsquinas([(y: -1.40, area: 8), (y: -1.58, area: 20)], esquinasY: []) == -1.58)
ok("(revisión 4) esquinas en la línea de un corte de 4 ft (1.22 m): el piso vale", R.pisoBajoLasEsquinas([(y: 0, area: 8)], esquinasY: [1.22]) == 0 && R.pisoBajoLasEsquinas([(y: -1.40, area: 8)], esquinasY: [-0.18]) == -1.40)
ok("(revisión 4) con el piso de abajo visto por la escalera gana el de este piso; 3 m abajo no es piso", R.pisoBajoLasEsquinas([(y: 0, area: 8), (y: -2.8, area: 30)], esquinasY: [1.6]) == 0 && R.pisoBajoLasEsquinas([(y: -3.0, area: 8)], esquinasY: [0]) == nil)
ok("(revisión 4) el subfloor es otra capa del piso; Carpet, Tile o lo escrito sin esas palabras no", R.esOtraCapaDelPiso("Subfloor") && R.esOtraCapaDelPiso("Plywood subfloor") && R.esOtraCapaDelPiso("OSB") && !R.esOtraCapaDelPiso("Carpet") && !R.esOtraCapaDelPiso("Tile") && !R.esOtraCapaDelPiso("Marble"))
ok("(revisión 4) clóset por su nombre", R.esNombreDeCloset("Closet") && R.esNombreDeCloset("clóset del master") && R.esNombreDeCloset("Pantry") && R.esNombreDeCloset("Walk-in") && !R.esNombreDeCloset("Bedroom 2") && !R.esNombreDeCloset("Hallway"))
ok("dos + desde el piso son el alto del nivel; un parche alto o sin piso no", R.arrancaEnElPiso([0.03, 0.62], piso: 0) && !R.arrancaEnElPiso([0.5, 1.1], piso: 0) && !R.arrancaEnElPiso([0.03, 0.6], piso: nil))
ok("(revisión) el alto del nivel y el baseboard del corte usan el MISMO medio pie", R.arrancaEnElPiso([0.152, 1], piso: 0) && !R.arrancaEnElPiso([0.153, 1], piso: 0) && abs(R.arranqueDelPiso / 3.28084 - 0.1524) < 1e-4)
let cb = R.cuadroDeBanda(SIMD3(0, 0.02, 0), SIMD3(3, 0.02, 1), piso: 0, alto: 0.61)
ok("la banda va del piso al alto en la línea de las esquinas", cb.count == 4 && cb[0] == SIMD3(0, 0, 0) && cb[1] == SIMD3(3, 0, 1) && cb[2] == SIMD3(3, 0.61, 1) && cb[3] == SIMD3(0, 0.61, 0))
let ry = R.rayas(largo: 1.0)
ok("la orilla punteada: rayas de 10 cm con 7 de hueco, sin pasarse", ry.count == 6 && abs(ry[1].0 - 0.17) < 1e-9 && ry.last!.1 <= 1.0 && R.rayas(largo: 0).isEmpty)
let th = R.tramosSinHuecos(largo: 4, huecos: [(centro: 2, ancho: 1)])
ok("la banda deja el hueco de la puerta", th.count == 2 && abs(th[0].0) < 1e-9 && abs(th[0].1 - 1.5) < 1e-9 && abs(th[1].0 - 2.5) < 1e-9 && abs(th[1].1 - 4) < 1e-9
   && R.tramosSinHuecos(largo: 4, huecos: []).count == 1 && R.tramosSinHuecos(largo: 4, huecos: [(centro: 0.2, ancho: 1)]).first.map { abs($0.0 - 0.7) < 1e-9 } == true)
ok("la ficha del corte (P04)", R.fichaDelCorte(material: "Drywall", alto: 2, largo: 12, menos: 0, resta: "12 ft × 2 ft", insulacion: true, pared: 1, base: "Baseboard + shoe · 12 ft")
   == R.FichaDelCorte(titulo: "Drywall 2 ft · Pared 1", area: "24", detalle: "12 ft × 2 ft · + insulación", base: "Baseboard + shoe · 12 ft"))
let fp = R.fichaDelCorte(material: "Drywall", alto: 2, largo: 14, menos: 6, resta: "14 ft × 2 ft − la puerta", insulacion: true, pared: 2, base: "Baseboard + shoe · 11 ft (sin la puerta)")
ok("con la puerta (P07): 22 pies² y '− la puerta · + insulación'", fp.area == "22" && fp.detalle == "14 ft × 2 ft − la puerta · + insulación" && fp.titulo == "Drywall 2 ft · Pared 2")
ok("sin saber la insulación lo dice", R.fichaDelCorte(material: "Drywall", alto: 2, largo: 12, menos: 0, resta: "12 ft × 2 ft", insulacion: nil, pared: nil, base: nil).detalle == "12 ft × 2 ft · insulación: le pregunto")
let fpl = R.fichaDelCorte(material: "Plaster", alto: 4, largo: 10, menos: 0, resta: "10 ft × 4 ft", insulacion: false, pared: nil, base: nil)
ok("sin baseboard no hay 4o renglón; sin pared dice 'Pared'", fpl.base == nil && fpl.titulo == "Plaster 4 ft · Pared" && fpl.detalle == "10 ft × 4 ft · sin insulación")
ok("lo escrito a mano no habla de insulación", R.fichaDelCorte(material: "Wainscoting", alto: 3, largo: 10, menos: 0, resta: "10 ft × 3 ft", insulacion: false, pared: 1, base: nil).detalle == "10 ft × 3 ft")
ok("pie lineal en la pared: baseboard, 1 pie, trim, crown", R.esDePieLineal("Baseboard") && R.esDePieLineal(R.drywallDeUnPie) && R.esDePieLineal("Trim") && R.esDePieLineal("Crown Molding") && !R.esDePieLineal("Drywall") && R.nombreEnLaCamara(R.drywallDeUnPie) == "Drywall de 1 pie")
typealias FilaPiso = (cuarto: String, nivel: String, seccion: String, material: String, ancho: Double?)
let filas: [FilaPiso] = [("Kitchen", "1st", "floor", "Carpet", 10), ("Kitchen", "1st", "wall", "Drywall", 4), ("Hallway", "1st", "floor", "Tackless Strip", nil), ("Bedroom", "2nd", "floor", "Laminate", 10)]
ok("el piso puesto: el último piso de ESTE nivel (no tackless, no otro nivel)", R.pisoAnterior(filas, nivel: "1st")?.material == "Carpet" && R.pisoAnterior(filas, nivel: "1st")?.de == "Kitchen" && R.pisoAnterior(filas, nivel: "2nd")?.material == "Laminate" && R.pisoAnterior(filas, nivel: "Basement") == nil)
let fc: [FilaPiso] = [("Bedroom 2", "1st", "floor", "Carpet", 10), ("Hallway", "1st", "floor", "Laminate", 10)]
ok("(revisión) el piso puesto es el de ESTE cuarto si ya tiene; si no, el último del nivel",
   R.pisoAnterior(fc, nivel: "1st", cuarto: "bedroom 2 ")?.material == "Carpet" && R.pisoAnterior(fc, nivel: "1st", cuarto: "Bedroom 2")?.de == "Bedroom 2"
   && R.pisoAnterior(fc, nivel: "1st", cuarto: "Office")?.material == "Laminate" && R.pisoAnterior(fc, nivel: "1st", cuarto: "Office")?.de == "Hallway"
   && R.pisoAnterior(fc, nivel: "1st")?.material == "Laminate")
// (revisión 2) Un piso escrito a mano en ESTE cuarto: se pregunta, nunca el del cuarto de antes; lo lineal de este cuarto no cuenta.
let fe: [FilaPiso] = [("Hallway", "1st", "floor", "Laminate", 10), ("Bedroom 2", "1st", "floor", "Cork", 8)]
ok("(revisión 2) Cork escrito en Bedroom 2: el siguiente parche pregunta (no Laminate de Hallway)", R.pisoAnterior(fe, nivel: "1st", cuarto: "Bedroom 2") == nil
   && R.pisoAnterior(fe, nivel: "1st", cuarto: "Office")?.material == "Laminate" && R.pisoAnterior(fe, nivel: "1st", cuarto: "Office")?.de == "Hallway")
let fl: [FilaPiso] = [("Bedroom 2", "1st", "floor", "Carpet", 10), ("Bedroom 2", "1st", "floor", "Transition Strip", nil), ("Bedroom 2", "1st", "floor", "Tackless Strip", nil), ("Bedroom 2", "1st", "floor", "Carpet Pad", 10)]
ok("(revisión 2) lo lineal (tackless, lo escrito sin ancho) y el pad de este cuarto no tapan su piso", R.pisoAnterior(fl, nivel: "1st", cuarto: "Bedroom 2")?.material == "Carpet")
ok("el nombre del piso puesto", R.nombreDelPiso("Carpet", debajo: true) == "Carpet + pad" && R.nombreDelPiso("Laminate", debajo: true) == "Laminate + underlayment" && R.nombreDelPiso("Tile", debajo: nil) == "Tile" && R.nombreDelPiso("Carpet", debajo: nil) == "Carpet · le pregunto el pad" && R.nombreDelPiso("Carpet", debajo: false) == "Carpet")
// ---- (13 pasos) "FALTA UNA PARED" ----
let fq1 = R.paredesQueFaltan(largos: [12, 14, 12, 14], deCadaMedida: [[0], [1], [2]], noSeCorto: [])
ok("falta la pared 4 (índice 3), y es seguro", fq1.faltan == [3] && fq1.seguro)
ok("una medida sin saber de qué pared: no es seguro", !R.paredesQueFaltan(largos: [12, 14, 12, 14], deCadaMedida: [[0], []], noSeCorto: []).seguro)
ok("'No se cortó' ya no falta", R.paredesQueFaltan(largos: [12, 14, 12, 14], deCadaMedida: [[0], [1], [2]], noSeCorto: [3]).faltan.isEmpty)
ok("un pedacito de pared (menos de 2 ft) no cuenta", R.paredesQueFaltan(largos: [12, 1.5, 12, 14], deCadaMedida: [[0], [2], [3]], noSeCorto: []).faltan.isEmpty)
ok("sin medidas de pared en el cuarto no falta nada", R.paredesQueFaltan(largos: [12, 14], deCadaMedida: [], noSeCorto: []).faltan.isEmpty)
ok("una medida en dos paredes cuenta para las dos", R.paredesQueFaltan(largos: [12, 14, 12], deCadaMedida: [[0, 1], [2]], noSeCorto: []).faltan.isEmpty)
ok("la pared 4 / las paredes 2 y 4 / las paredes 1, 2 y 4", R.textoParedes([3]) == "la pared 4" && R.textoParedes([3, 1]) == "las paredes 2 y 4" && R.textoParedes([0, 1, 3]) == "las paredes 1, 2 y 4")
// ---- LA SEGUNDA REVISIÓN DEL 16 OCT ----
let arcoAlto = R.Abertura(p: SIMD2(6, 0), esVentana: false, ancho: 4, alto: 3, abajo: 3.5, esPaso: true)
ok("(revisión) un arco que empieza a 3.5 ft (arriba del mostrador) no corta el baseboard: 12 ft, sin '(sin el arco)'",
   igual(R.baseboardDeLaPared(largo: 12, aberturas: [arcoAlto]), 12) && R.textoDelBaseboard(arranque: 0, largo: 12, aberturas: [arcoAlto], incluye: (true, true)) == "Baseboard + shoe · 12 ft")
ok("(revisión) el arco bajo (0.8 o 1 ft: ruido del piso, escalones) o sin altura (-1) corta como siempre: 8",
   igual(R.baseboardDeLaPared(largo: 12, aberturas: [R.Abertura(p: SIMD2(6, 0), esVentana: false, ancho: 4, alto: 7, abajo: 0.8, esPaso: true)]), 8)
   && igual(R.baseboardDeLaPared(largo: 12, aberturas: [R.Abertura(p: SIMD2(6, 0), esVentana: false, ancho: 4, alto: 7, abajo: 1.0, esPaso: true)]), 8)
   && igual(R.baseboardDeLaPared(largo: 12, aberturas: [R.Abertura(p: SIMD2(6, 0), esVentana: false, ancho: 4, alto: 7, esPaso: true)]), 8))
ok("(revisión) la puerta siempre corta, aunque el plano diga que empieza a 3 ft: 8",
   igual(R.baseboardDeLaPared(largo: 12, aberturas: [R.Abertura(p: SIMD2(6, 0), esVentana: false, ancho: 4, alto: 6.7, abajo: 3)]), 8) && R.pasoElevado == 2.5)
ok("(revisión) baseboard repetido: 11 de la pared + 14 medidos en una de 11 sí; 6 de un corte + 5 en una de 11 no; sin plano sí",
   R.baseboardDeMas(ya: 11, nuevo: 14, cabe: 11) && !R.baseboardDeMas(ya: 6, nuevo: 5, cabe: 11) && !R.baseboardDeMas(ya: 6, nuevo: 5.4, cabe: 11)
   && R.baseboardDeMas(ya: 6, nuevo: 6, cabe: 11) && R.baseboardDeMas(ya: 1, nuevo: 1, cabe: nil)
   && !R.baseboardDeMas(ya: 10, nuevo: 10.6, cabe: 20) && R.baseboardDeMas(ya: 10, nuevo: 20, cabe: 20))
ok("(revisión) dos + desde el piso: la línea de arriba sobre el piso (0.61 m = 2 ft)", igual(R.altoSobreElPiso([0.0, 0.6096], piso: 0), 2.0) && R.altoSobreElPiso([0.5, 1.1], piso: 0) == nil && R.altoSobreElPiso([0.0, 0.6], piso: nil) == nil)
ok("(revisión) el + de abajo 0.4 ft arriba del piso (marcado 1.6, la línea a 2.0): no es el alto del nivel; parejo sí",
   R.altoDelNivelDeDosPuntos([0.1219, 0.6096], piso: 0, marcado: 1.6) == nil && igual(R.altoDelNivelDeDosPuntos([0.01, 0.6096], piso: 0, marcado: 1.97), 1.97)
   && R.altoDelNivelDeDosPuntos([0.5, 1.1], piso: 0, marcado: 2) == nil)
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
# 16 oct: no pregunta si la pared ya está completa, y "Continuar" vale 20 s (antes congelaba parte, pared y cuarto hasta guardar).
ok("(13 pasos) ya no se pregunta si terminó con la pared: entre una medida y otra cambia solo", 'private func pedirCambio(_ d: CambioDeLugar) { aplicarCambio(d) }' in v and 'abrirPregunta(.cierre)' not in v and 'cierreCallado' not in v and 'cuartoCallado' not in v and 'cambioPendiente' not in v and '"¿Ya terminó con esta pared?", nil)' not in v)
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
ok("el + se queda vivo en el alto/ancho ya medido; en 'Otro alto' marca la línea; con el alto de la banda puesto, no", 'let masVivo = !roomName.isEmpty && (stage != .lengthDone || n.otroAlto) && !altoDeLaBandaPuesto' in mm)
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
ok("la primera esquina toma la parte a la que apunta (sin el freno de la pregunta vieja) y el cuarto donde está", 'n.clasificador.ahoraMismo(ahora: ahora)' in gm2 and 'medidasEnEstaPared() > 0' not in gm2 and 'anotarMedir("cambio", ["de_cuarto": roomName, "a_cuarto": aqui, "por": "primera-esquina"])' in gm2 and 'aplicarCambio(.cuarto(aqui))' in gm2)
ok("la bitácora anota medir primero (cada +, la parte de la medida, cada cambio y cada guardada)", 'anotarMedir("mas"' in gm2
   and 'anotarMedir("guardar"' in bloque(v, 'fileprivate func guardarMedir') and 'anotarMedir("resumen"' in v
   and '(medirPrimero && nueva.medirActivo)' in bloque(v, 'fileprivate func anotarBitacora'))
ok("en medir primero el seguro de la parte es solo una medida a medias o algo abierto", 'return medidaEnCurso || (n.preguntaMedir != nil && !(n.preguntaMedir == .parteEntera && n.eleccionAuto)) || n.ajusteAbierto' in bloque(v, 'fileprivate func bloqueoDeParte'))
# 16 oct: EL LECTOR DE LA PARTE (rayo contra el plano + clase de ARKit + estimado del láser + inclinación) con su puerta de cambio.
rpa = bloque(v, 'fileprivate func revisarParteQueApunta')
ok("la parte sale del LectorDeParte y cambia por su puerta (0.4 s; el piso quieto pide más)", 'let v = LectorDeParte.votar(e)' in rpa and 'n.puerta.meter(v, t: ahora, grados: m.grados, quieto: quieto)' in rpa and 'estable(por:' not in rpa)
ok("CUÁL pared, solo con el plano confirmado por el láser; sin plano confiable no hay pared", 'if !confiable { n.puertaPared.soltar(); n.paredVista = nil; n.paredCandidata = nil }' in rpa)
ok("si el plano casi no calza con el láser 3 s, se reubica sola (la misma rueda)", 'empezarAReubicar("rayo-no-calza")' in rpa and 'frac < 0.3' in rpa)
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
   and 'fileprivate enum PreguntaMedir: Equatable { case que, otroLineal, shoe, matPared, insulPared, piso, underCuarto, techo, techoCuarto, lineal1, cierre, cuarto, segunda, parteEntera, incluye, materialPuesto, sobreCompleta }' in v)
ok("el carpet va por resolverPiso como los demás pisos", 'listaDeMateriales(ReglasDeMedir.materialesPiso, sugerido: nil, sub: "\\(pies(A)) pies²") { s, m in s.resolverPiso(m) }' in pm)
ok("mixto: '¿<cuarto> tiene underlayment o padding?' una vez por cuarto (padding si es carpet)",
   '"¿\\(roomName) tiene underlayment o padding?"' in pm and 'ReglasDeMedir.debajoDelPiso(m) == "Carpet Pad" ? "padding" : "underlayment"' in pm
   and 'case .underCuarto: n.underDeCuarto[n.clavePendiente] = si; guardarMedir(ReglasDeMedir.conUnderlayment(g, si))' in bloque(v, 'private func contestarPendiente'))
tu = bloque(v, 'private func textoUnder')
ok("la ayuda del panel del piso habla de underlayment o padding", 'debajo del carpet, laminate, hardwood o vinyl' in tu and 'Sin underlayment ni padding' in tu and 'tiene underlayment o padding' in tu)
ok("lo contestado con la pregunta vieja no cuenta: la llave del nivel es v2", 'private static let llaveAjuste = "scanova.medirPrimero.ajuste.v2"' in v)
ok("la maqueta 37 guarda el carpet por las reglas de verdad (resolverPiso)", 'resolverPiso("Carpet")' in bloque(v, 'private func maquetaMedirPrimeroPaso') and 'ReglasDeMedir.alfombra(' not in v[:v.index('struct ReglasDeMedir {')])
ok("lo contestado del nivel se guarda por trabajo y nivel", 'Self.llaveAjuste + "|" + trabajoId + "|" + nivelActual' in v and 'arVC.trabajoId = call.getString("trabajo")' in plg)
ok("las maquetas 24-110 no se enciman con las del laboratorio (18-23)", 'arVC.porMovimiento = (24...110).contains(paso)' in plg and '(18...23).contains(paso)' in plg)
# ---- LA VENTANA "¿COMPLETO O PARCIAL?" SALE SOLA (16 oct, su pedido: "que ya no pregunte fijar; mira la pared y le da las
# opciones, mira arriba techo completo o parcial, abajo piso; al escoger, engancha") ----
rm = bloque(v, 'fileprivate func revisarMedirPrimero')
ok("ya no sale la pregunta vieja ni hay botón Fijar", 'tocaPreguntarParedEntera' not in v and 'paredEnteraAMano' not in v and 'fijarParte' not in v and 'sePuedeFijar' not in v)
ok("cada 0.1 s se revisa la ventana (antes de lo que frena la parte)", 'revisarEleccion()\n        guard !bloqueoDeParte()' in rm)
et = bloque(v, 'fileprivate func eleccionToca')
ok("sale sola sin nada a medias, sin otra cosa abierta, con cuarto y sin una parte ya enganchada",
   '!medidaEnCurso, !n.enganchada' in et and 'stage == .pickingMaterial || (stage == .measuringLength && pathPoints.isEmpty)' in et
   and '!medidaEnCurso, !n.enganchada, n.preguntaMedir == nil else { return false }' in et and 'n.panelForzado == nil' in et and '!n.ajusteAbierto' in et)
ok("cocina, baño o materiales escogidos a mano se miden como siempre (sin la ventana)", 'if n.parteAMano && !["wall", "floor", "ceiling"].contains(section) { return false }' in et)
re2 = bloque(v, 'fileprivate func revisarEleccion')
ok("(13 pasos) la franja sigue a donde apunta: se esconde al momento, cambia a lo mucho cada 0.3 s y nunca bajo el dedo",
   'if !f.isEmpty, tocando || ahora - n.ventanaCambioEn < 0.3 { return }' in re2 and 'pintarFranja()' in re2
   and 'if c == nil, eleccionToca(), let x = n.franjaContenido, x.cuarto == aqui.cuarto, x.nivel == aqui.nivel, ahora - n.franjaVistaEn < 0.8 { c = x }' in re2
   and 'abrirEleccion' not in v and 'abrirPregunta(.parteEntera)' not in v)
ok("la ventana que sale sola NO frena el cuarto ni la parte (siguen al teléfono)", '!(n.preguntaMedir == .parteEntera && n.eleccionAuto)' in bloque(v, 'fileprivate func bloqueoDeParte'))
ok("al cambiar lo que ve el teléfono se revisa la ventana en el momento", 'if medirPrimero && n.medirActivo { revisarEleccion() }' in v)
en = bloque(v, 'fileprivate func engancharParte')
# 16 oct: lo de la ventana ya NO es "a mano" (eso trabó la parte 2 minutos); lo protegen el largo del plano o enganchada.
ok("al escoger, la parte se ENGANCHA (sin quedar 'a mano') con la pared QUE ENSEÑÓ la tarjeta (otra pared = empieza otra)",
   'n.parteAMano = true' not in en and 'elegirParteNueva(p)' in en and 'if section == "wall", let i = pared {' in en and 'if i != n.paredActual { empezarPared() }' in en)
pa = bloque(v, 'private func paredApuntada')
# 16 oct: la que dice el rayo contra el plano confirmado por el láser (0.5 s), y solo mientras le sigue apuntando (0.6 s).
ok("la pared a la que apunta es la de AHORA: ubicado y el plano lo dice ahorita (nunca la última que vio)",
   'guard ubicacionReciente(), CACurrentMediaTime() - n.ultimoPDeLaPared <= 0.6 else { return nil }' in pa)
ok("completo de una pared sin la pared vista no se acepta", 'if p == "wall", pared == nil { revisarEleccion(); return }' in bloque(v, 'fileprivate func escogerCompleta'))
ok("al cambiar de cuarto se olvida la pared vista (era de otro cuarto)", 'n.paredVista = nil; n.paredCandidata = nil' in bloque(v, 'fileprivate func arreglarMedirPrimero'))
ok("el piso/techo completo solo con el plano de este nivel", 'nueva.nivelDelPlano == nivelActual || maqueta > 0' in bloque(v, 'fileprivate func datosPisoEntero'))
ok("el número grande y el de Listo ya con la resta (el mismo que se guarda)", 'restaEnCurso(pathTotalFeet, currentWidthFeet ?? 0)' in bloque(v, 'fileprivate func pintarMuelleMedir')
   and 'let menos = medirPrimero ? restaEnCurso(pathTotalFeet, w) : 0' in v)
ok("las ventanas se restan según su altura del piso (y los arcos van con su marca)", 'abajo: $0.abajo, esPaso: $0.esPaso)' in bloque(v, 'private func aberturasDelPlano'))
ok("completo -> las medidas del plano; parcial -> enganchada y a medir con +", 'aceptarParteEntera()' in bloque(v, 'fileprivate func escogerCompleta')
   and 'nueva.enganchada = true' in bloque(v, 'fileprivate func escogerParcial') and 'cerrarPregunta()' in bloque(v, 'fileprivate func escogerParcial'))
dm = bloque(v, 'fileprivate func deshacerMedir')
ok("enganchada sin esquinas: Deshacer vuelve a la ventana (nunca borra una guardada)", 'if nueva.enganchada, pathPoints.isEmpty, widthPoints.isEmpty, !medidaEnCurso {' in dm
   and 'nueva.enganchada = false; nueva.parteAMano = false' in dm)
ok("y lo dice abajo: 'Deshacer · volver a escoger'", 'if pathPoints.isEmpty, n.enganchada { leyenda = "volver a escoger"; puedeDeshacer = true }' in bloque(v, 'fileprivate func pintarMuelleMedir'))
ok("al guardar o cambiar de cuarto se suelta lo enganchado (la ventana vuelve a salir)", 'n.enganchada = false' in bloque(v, 'fileprivate func guardarMedir')
   and 'n.enganchada = false' in bloque(v, 'fileprivate func arreglarMedirPrimero'))
mm = bloque(v, 'fileprivate func pintarMuelleMedir')
ok("el muelle: Listo como antes y MEDIDA con el material puesto (se toca para cambiarlo)", 'n.derecho.isEnabled = listo' in mm and 'riel(n.rielMaterial, "MEDIDA", medida.valor, medida.sub, activo: medida.tocable)' in mm
   and '@objc fileprivate func rielMaterialTocado() { if medirPrimero && nueva.medirActivo { abrirMaterialPuesto(); return }' in v)
ap = bloque(v, 'fileprivate func aceptarParteEntera')
sp = bloque(v, 'fileprivate func seguirConLaParteEntera')
ok("'Completa' es un largo dictado del plano (sin esquinas) y va al material de esa parte", 'largoDictado = true' in ap and 'pathTotalFeet = d.largo' in ap
   and 'abrirPregunta(Self.preguntaDelMaterial(pe.seccion))' in sp and 'seguirConLaParteEntera()' in ap and 'pathPoints.isEmpty, widthPoints.isEmpty' in ap)
ok("una pared sin el alto en el plano: se marca solo el alto con +", 'empezarAncho()' in sp)
# "Pared completa" (16 oct, su pedido): primero pregunta qué incluye, y el baseboard se calcula solo.
ok("la pared completa pregunta qué incluye una vez por cuarto (la siguiente ya trae la respuesta)", 'if let r = incluyeDelCuarto() { contestarIncluye(base: r.base, shoe: r.shoe, reusada: true); return }' in ap and 'abrirPregunta(.incluye); return' in ap)
ci = bloque(v, 'fileprivate func contestarIncluye')
ok("'¿qué incluye?' guarda baseboard y shoe molding en la parte", 'pe.conBaseboard = base; pe.conShoe = base && shoe' in ci and 'seguirConLaParteEntera()' in ci)
gm = bloque(v, 'fileprivate func guardarMedir')
ok("al guardar la pared completa con baseboard, el baseboard sale solo (largo menos las puertas)", 'ReglasDeMedir.baseboardDeLaPared(largo: pe.largo, aberturas: pe.aberturas)' in gm)
cf = bloque(v, 'fileprivate func contenidoDeLaFranja')
ok("una parte que ya tiene medida (amarilla o verde) no vuelve a ofrecer 'completa' (revisión 2: salvo trim, crown o tackless solos)",
   'guard !tapaLoCompleto(pared: i, parte: "wall"), let d = datosParedEntera(i) else { return nil }' in cf and 'guard !tapaLoCompleto(pared: nil, parte: parte), let d = datosPisoEntero(parte)' in cf
   and 'private static let noTapanLoCompleto: Set<String> = ["Trim", "Crown Molding", "Tackless Strip"]' in v
   and '&& !(it.width == nil && Self.noTapanLoCompleto.contains(it.material))' in bloque(v, 'fileprivate func tapaLoCompleto'))
# ---- (revisión 4) ----
ok("(revisión 4) sin la ubicación (pared adivinada) no se pregunta '¿Es la pared N? Ya lleva baseboard': se guarda sin pared",
   'if baseboardSinSaberLaPared(donde, que: "corte-base") { return false }' in v and 'if baseboardSinSaberLaPared(donde, que: "baseboard") { return false }' in v
   and 'nueva.paredSinSaber = true' in bloque(v, 'private func baseboardSinSaberLaPared') and 'guard donde.adivinada else { return false }' in bloque(v, 'private func baseboardSinSaberLaPared'))
ok("(revisión 4) al perder la ubicación (reinicio, corte del rastreo) la pared de antes se suelta",
   'if medirPrimero, !medidaEnCurso { empezarPared() }' in bloque(v, 'private func reiniciarElRastreo') and 'if medirPrimero { n.paredCandidata = nil; n.paredVista = nil; if !medidaEnCurso { empezarPared() } }' in bloque(v, 'func sessionWasInterrupted'))
ok("(revisión 4) un parche de subfloor no es 'El piso ya está completo' ni esconde 'Piso completo'; 'Guardar igual' guarda lo de MEDIDA",
   'ReglasDeMedir.esOtraCapaDelPiso(p.material) { return false }' in bloque(v, 'fileprivate func preguntarSiYaCompleta')
   and 'ReglasDeMedir.esOtraCapaDelPiso(it.material)' in bloque(v, 'fileprivate func tapaLoCompleto')
   and 'if let p = materialPuestoVigente(), p.parte == "floor" { resolverPiso(p.material) } else { abrirPregunta(.piso) }' in bloque(v, 'fileprivate func guardarSobreLoCompleto'))
ok("(revisión 4) entrar al clóset del cuarto no dispara 'faltan N paredes': espera a un tercer cuarto; sin plano nunca es clóset",
   'n.salidaPendiente = (antes, nivelActual)' in bloque(v, 'fileprivate func salioDelCuarto') and 'esClosetDe(c, de: antes)' in bloque(v, 'fileprivate func salioDelCuarto')
   and 'guard !planoPorCuarto.isEmpty, ReglasDeMedir.esNombreDeCloset(c) else { return false }' in bloque(v, 'fileprivate func esClosetDe'))
nq = bloque(v, 'fileprivate func noGuardarSobreLoCompleto')
ok("(revisión 4) 'No guardar · medirla aparte' deja el material de MEDIDA para medirla otra vez (los otros 'No guardar' no)",
   'let aparte = !(n.sobreCompleta?.otras.isEmpty ?? true)' in nq and nq.index('if aparte { n.materialPuesto = mat;') > nq.index('cancelarMedidaEnCurso(hablar: false)'))
ok("(revisión 4) 'Es otra pared': nunca la insulación ni el afuera/adentro de la pared que tenía enfrente",
   'let sinSaber = n.paredSinSaber && clase.paredes.isEmpty' in bloque(v, 'private func resolverPared') and 'respuesta: sinSaber ? nil : n.insulDePared[clave]' in bloque(v, 'private func resolverPared')
   and 'guard !nueva.paredSinSaber,' in bloque(v, 'private func paredDeAfueraEnElPlano'))
ok("(revisión 4) lo completo de otra sesión (partesGuardadas) cuenta como completo; sin la llave nada cambia",
   'completaDeAntes(parte: "wall", pared: i)' in bloque(v, 'fileprivate func estadoDeLaPared') and 'completaDeAntes(parte: parte, pared: nil)' in bloque(v, 'fileprivate func estadoDeLaParte')
   and 'guard maqueta == 0, !partesGuardadas.isEmpty else { return false }' in bloque(v, 'fileprivate func completaDeAntes') and 'call.getArray("partesGuardadas")' in plg)
ok("(revisión 4) Deshacer el renglón del alto lo olvida en el momento; el alto del teléfono sin filas guardadas se borra",
   'olvidarAltoSiSeDeshizo()' in bloque(v, '@objc private func undoTapped') and 'UserDefaults.standard.removeObject(forKey: llaveDelAlto())' in bloque(v, 'fileprivate func altoRecordado'))
ok("(revisión 4) 'falta una pared' de otra captura: sin línea roja en otro marco y 'Volver' cambia el cuarto",
   'mismoMarco(r.cuarto, roomName)' in v and 'elegirCuartoNuevo(f.cuarto)' in bloque(v, 'private func contestarFalta'))
# El mapita (16 oct): transparente; verde la pared completa, amarillo la parcial, negro sin tocar; el piso igual; el techo sin color.
ok("el mapita es transparente", 'backgroundColor = .clear' in bloque(v, 'fileprivate final class MinimapaCamara'))
mc = bloque(v, 'fileprivate final class MinimapaCamara')
ok("el mapita va sobre un vidrio que desenfoca, solo hasta donde llega el mapa (y 'Ubicado' en otro vidrio)",
   mc.count('UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight))') == 2
   and 'g.dibujo.insetBy(dx: -Self.orillaVidrio, dy: -Self.orillaVidrio)' in mc and 'dueno?.dibujar(bounds)' in v)
ok("el plano grande de la fase de ubicarse no lleva vidrio (ya va sobre su tarjeta)", 'n.mapaGrande.conVidrio = false' in v)
# Su pregunta del 16 oct: el letrero "✓ ... guardado" de arriba se metía debajo del mapa.
ok("medir primero no pone letrero de guardado (el mapa se pinta verde/amarillo)", 'mostrarAvisoNuevo(ReglasDeMedir.aviso(g' not in bloque(v, 'fileprivate func guardarMedir')
   and 'items.count > n.itemsVistos, !(medirPrimero && n.medirActivo), let u = items.last' in v)
ok("los avisos de arriba nunca van debajo del mapa", 'n.columna.trailingAnchor.constraint(lessThanOrEqualTo: m.leadingAnchor, constant: -8)' in v
   and 'centroColumna.priority = .defaultHigh' in v and 'n.aviso.numberOfLines = 0' in v)
# Su corrección del 16 oct: el aviso no es una franja amarilla arriba; es una tarjeta de vidrio enfrente que se va sola.
ma = bloque(v, 'fileprivate func mostrarAvisoNuevo')
ok("el aviso va en una tarjeta de vidrio enfrente (esquina 10 de Scanova), con ícono, título y explicación",
   'let vidrioAviso = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight))' in v and 'vidrioAviso.layer.cornerRadius = 10' in v
   and 'caja.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -150)' in v and 'Self.partesDelAviso(' in ma and 'UIColor(red: 1.0, green: 0.95, blue: 0.82' not in ma)
ok("el aviso entra suave y se desvanece solo al pasar sus segundos", 'caja.alpha = 1; caja.transform = .identity' in ma
   and 'caja.alpha = 0; caja.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)' in bloque(v, 'fileprivate func pintarAviso') and v.count('pintarAviso()') >= 2)
ok("ya no hay franja de aviso en la columna de arriba", 'for v in [n.ficha, n.pista] { n.columna.addArrangedSubview(v) }' in v)
ok("verde = completa, amarillo = parcial", 'static let verde' in v and 'static let amarillo' in v and 'colorPared' in v and 'colorPiso' in v)
ok("el piso y el techo completos salen del área del cuarto en el plano (piso: área, largo, ancho, aprox)",
   'pisoPorCuarto.first(where: { Self.clave($0.key) == clave })' in bloque(v, 'fileprivate func datosPisoEntero')
   and 'pisos[cuarto] = (a, l, w, pz.count >= 4 ? (num(pz[3]) ?? 0) > 0.5 : false)' in plg)
ok("sin el largo dictado no queda nada completo (no se le resta a otra medida)", 'didSet { if !largoDictado { nueva.parteEntera = nil } }' in v)
bm = bloque(v, 'private func bancarMedida')
ok("bancarMedida guarda la resta UNA vez y solo con alto", 'let resta = currentWidthFeet != nil ? restaAlGuardar : nil' in bm and 'restaAlGuardar = nil' in bm
   and 'menos: resta?.menos ?? 0' in bm)
ok("la resta viaja a la página (menos y menosQue)", 'if item.menos > 0 { d["menos"] = item.menos; d["menosQue"] = item.menosQue }' in plg)
ok("guardar, la insulación, el underlayment y el techo usan lo completo", 'let g = conLaParteEntera(g0)' in bloque(v, 'fileprivate func guardarMedir')
   and 'conLaParteEntera(' in bloque(v, 'private func resolverPared') and 'conLaParteEntera(' in bloque(v, 'private func resolverPiso')
   and 'conLaParteEntera(' in bloque(v, 'private func resolverTecho'))
cp = bloque(v, 'fileprivate func conLaParteEntera')
ok("la pared resta sus puertas y ventanas; el piso/techo lo que sobra de la caja", 'ReglasDeMedir.conLaResta(g, aberturas: pe.aberturas)' in cp
   and 'ReglasDeMedir.conLaFormaDelCuarto(g, area: pe.area)' in cp and 'section == pe.seccion' in cp)
ok("la insulación de la pared completa mira la pared completa del plano", 'claseDeLaMedida(tramosFijos: [(indice: $0, t0: 0, t1: pe.largo)])' in bloque(v, 'private func claseParaInsulacion'))
ok("'No era completo' y Deshacer lo quitan completo (nunca una guardada)", 'cancelarMedidaEnCurso(hablar: false)' in bloque(v, 'fileprivate func cancelarParteEntera')
   and 'cancelarParteEntera(aParcial: false); revisarEleccion(); pintarCamaraNueva(); return' in bloque(v, 'fileprivate func deshacerMedir'))
cpe = bloque(v, 'fileprivate func cancelarParteEntera')
ok("'No era completa · medir con +' deja el + listo en PARCIAL de esa parte y pared (la ventana no vuelve a taparlo)", 'n.parteAMano = false; n.enganchada = aParcial' in cpe and 'n.eleccionAuto = false' in cpe)
ok("lo escogido se suelta solo con la REGLA (sin nada marcado, la parte nueva cuadra con la inclinación y hubo giro)",
   'struct ReglaDeSoltar {' in v and 'if let porque = r.suelta { soltarLoEscogido(porque); revisarEleccion() }' in bloque(v, 'fileprivate func revisarMedirPrimero'))
ok("la ventana respeta la parte escogida a mano en el panel", 'if n.parteAMano, partes.contains(section) { return section }' in bloque(v, 'fileprivate func parteParaFijar'))
ok("Reubicar: tocar 'Ubicado' vuelve a buscar con la rueda, rápido, y para al ser firme o a los 12 s", 'm.alTocarEstado = { [weak self] in self?.reubicarAMano() }' in v and 'n.minimapa.ubicando = true' in v and 'dura > 12' in v and 'ponerEstado("Ubicando…"' in v)
ok("los totales de la cámara restan lo completo", 'max(0, w * largo - menos)' in bloque(v, 'private func cuentaDe') and 'menos: x.menos' in bloque(v, 'private func totalesTexto'))
ok("las maquetas 39-45: pared (sale sola, material, guardada, sin alto), techo, piso en L y parcial enganchada", 'case 39, 40, 41, 42:' in v and 'case 43, 44, 45:' in v)
# ---- 16 oct, la revisión con la bitácora 388DF319: lo escogido manda, la pared completa solo con la ubicación confirmada ----
rm = bloque(v, 'fileprivate func revisarMedirPrimero')
ok("lo escogido manda (a mano o 'Área parcial'): el paso 2 y la primera esquina no lo cambian",
   'fileprivate var parteFija: Bool { nueva.parteAMano || nueva.enganchada }' in v
   and 'if !parteFija, let z = n.zonaVista, z != section, seccionesDisponibles[z] != nil { pedirCambio(.parte(z)); return }' in rm
   and 'pathPoints.isEmpty, !parteFija,' in bloque(v, 'fileprivate func gatilloMedir') and '!n.parteAMano' in bloque(v, 'fileprivate func revisarParteDeLaMedida'))
ok("Deshacer ya no suelta lo escogido (su Techo a mano se queda)", 'soltarLoEscogido("deshacer")' not in v)
ok("enganchada en un parcial de pared adopta una pared, nunca la cambia", 'else if !n.enganchada, let pa = n.paredActual, pv != pa { pedirCambio(.pared(pv)); return }' in rm)
ok("el cuarto por el mapa solo con la ubicación confirmada hace poco", 'if ubicacionReciente(), let aqui = cuartoDondeEsta(), Self.clave(aqui) != Self.clave(roomName),' in rm)
cpe2 = bloque(v, 'fileprivate func cancelarParteEntera')
ok("'No era completa' no hereda la pared equivocada", 'if parte == "wall" { n.paredActual = paredApuntada() }' in cpe2 and 'if parte == "wall", let i = pared { n.paredActual = i }' not in cpe2)
pc = bloque(v, 'private func pedirCambio')
ok("la franja no se rehace bajo el dedo y el toque de los primeros 0.6 s no cuenta",
   '\\(n.preguntaMedir == .parteEntera ? n.firmaEleccion : "")' in bloque(v, 'private func pintarPanelNuevo') and 'firmaDeLaEleccion' not in v
   and 'guard CACurrentMediaTime() - n.ventanaCambioEn >= 0.6 else { anotarMedir("ventana", ["que": "toque-ignorado"]); return }' in bloque(v, 'fileprivate func tocarFranja')
   and 'ventanaParteEn' not in v)
ok("'Pared completa' solo con la ubicación confirmada y apuntándole todavía a esa pared (documento del seguro)",
   'if p == "wall", maqueta == 0, !(ubicacionReciente() && paredApuntada() == pared) {' in bloque(v, 'fileprivate func escogerCompleta')
   and 'anotarMedir("completa-rechazada"' in v and 'let iPared = esPared && ubicacionReciente() ? paredApuntada() : nil' in v
   and '"Sin confirmar la ubicación · toque arriba para reubicar"' in v)
ok("prender 'a mano' en el panel se anota", 'anotarMedir("a-mano", ["prende": "panel", "parte": section])' in bloque(v, 'fileprivate func arreglarMedirPrimero'))
ok("las maquetas 49-54 (lo escogido, la ventana, sin confirmar, reubicar, ¿ya terminó?)", 'case 49:' in v and 'case 54:' in v)
rpa = bloque(v, 'fileprivate func revisarParteQueApunta')
ok("el detector: pared por láser fuerte, sin muebles, la inclinación sola no decide, y 'calza' asimétrica",
   'let confiable = ubicacionReciente() && (n.calzas.count < 5 || frac >= 0.6)' in rpa
   and 'planoFuerte: n.calzas.count >= 5 && frac >= 0.6 && !m.pisoAdivinado' in rpa and 'if !paredDeVerdad { vp.pared = nil }' in rpa
   and 'if v.fuente == "I" { viejo = .nada }' in rpa and 'else if g.d > dPlano + tol { n.calzas.append(false) }' in rpa
   and 'n.paredVista = i; n.paredVistaDesde = ahora' in rpa)
pm2 = bloque(v, 'fileprivate func armarPanelMedir')
ok("(13 pasos, idea 6) sin la ventana grande: la franja chica arriba de la tarjeta de abajo, solo lo completo y sus números del plano",
   'etiqueta("¿Qué extensión se retiró?"' not in v and 'titulo: "Área parcial"' not in v and 'class TarjetaParedEntera' not in v and 'class DibujoParedEntera' not in v
   and 'f.bottomAnchor.constraint(equalTo: n.muelle.topAnchor, constant: -10)' in bloque(v, 'fileprivate func armarFranja')
   and 'titulo: "Pared completa"' in cf and 'ft · del plano' in cf and '"Piso completo" : "Techo completo"' in cf
   and 'escogerCompleta(c.parte, pared: c.pared)' in bloque(v, 'fileprivate func tocarFranja'))
ok("la franja va con la tarjeta de abajo (nunca con un panel) y el + se ve siempre", 'n.franja.isHidden = !(medirPrimero && n.medirActivo) || n.muelle.isHidden || n.franjaContenido == nil' in bloque(v, 'fileprivate func pintarCamaraNueva'))
ok("(idea 5) el piso del cuarto de antes viene puesto en la franja y tocarla lo guarda; 'Otro piso' escoge de la lista",
   'nombreDelPisoPuesto(pre.material) + (de.isEmpty ? "" : " · " + de)\n                                   + " · del plano · toque para guardar"' in cf and 'BotonFranja(icono: nil, titulo: "Otro piso"' in bloque(v, 'fileprivate func pintarFranja') and 'if que == "otro-piso" { n.sinPisoPuesto = true }' in bloque(v, 'fileprivate func tocarFranja')
   and 'if pe.seccion == "floor", let pre = pisoPuesto()' in bloque(v, 'fileprivate func seguirConLaParteEntera'))
ok("cada pantalla del material dice el número con su resta", 'let menosCurso = restaEnCurso(L, S), A = max(0, L * S - menosCurso)' in pm2 and pm2.count('cuenta(), "¿Qu') == 3)
ok("las puertas que solo vio el cuarto de al lado también se restan", 'cuartosDelMarco(m).filter { Self.clave($0.nombre) != Self.clave(roomName) }.flatMap { $0.senas }' in bloque(v, 'private func aberturasDelPlano') and 'aberturasDelPlano(forma)' in bloque(v, 'fileprivate func datosParedEntera'))
# ---- LA UBICACIÓN (su segunda prueba: "me sacó del mapa"; la bitácora: se perdió a los 25 s y no volvió) ----
rp = bloque(v, 'fileprivate func revisarParteQueApunta')
ok("el salto de la cámara a media medida solo cuenta para ESA medida (antes nunca se borraba)", 'if !medidaEnCurso { n.rastreoMaloEnMedida = false }' in rp)
ok("pegado a una pared del cuarto (fuera de todos) sigue en ese cuarto", 'forma.paredes.contains(where: { Self.distanciaASegmento(p, $0.seg) <= 2.0 }) { return roomName }' in bloque(v, 'fileprivate func cuartoDondeEsta'))
ok("el puntito del mapa no se sale del cuarto (solo el dibujo)", 'let tel = telefonoEnElCuarto(' in v and 'enLaPared + hacia / l * 0.5' in bloque(v, 'fileprivate func telefonoEnElCuarto'))
ok("la bitácora anota cuándo y por qué se pierde o vuelve la ubicación, y dónde está en el plano", 'anotarMedir("ubicacion", ["firme": n.firme' in rp
   and '"tel": telefonoEnPlano()' in rp and 'n.porqueFirme = "buscar-dudosa"' in v and 'n.porqueFirme = "interrumpida"' in v)
# LOS CORTES DEL RASTREO (16 oct, su prueba: cada captura cortaba la cámara; una vez el teléfono brincó 15 ft y se congeló).
vr = bloque(v, 'fileprivate func vigilarElRastreo')
ok("ARKit trata de volver al mismo mundo tras un corte (solo la cámara nueva)", 'return experienciaNueva && maqueta == 0' in bloque(v, 'func sessionShouldAttemptRelocalization'))
ok("si el rastreo no vuelve en 10 s tras el corte, la cámara arranca limpia", 'reiniciarElRastreo("no-volvio")' in vr and '> 10' in vr)
ok("un brinco de más de 1.5 m en un corte corto = el mundo cambió: arranca limpia", 'if salto > 1.5 && duro < 15 { reiniciarElRastreo("salto"); return }' in vr)
ok("la imagen congelada o el corte que no acaba: primero se vuelve a correr sin borrar", 'relanzarLaCamara("congelada")' in vr and 'relanzarLaCamara("corte-sin-fin")' in vr)
rr = bloque(v, 'private func reiniciarElRastreo')
ok("el reinicio limpio tira la medida a medias, no las guardadas, y nunca va en ciclo", 'cancelarMedidaEnCurso(hablar: false)' in rr and 'n.reinicios < 6' in rr and '.resetTracking, .removeExistingAnchors' in rr and 'items.removeAll' not in rr)
ub = bloque(v, 'fileprivate func ubicarseEnElPlano')
ok("sin lo firme 5 s, una respuesta lejana que se repite 3 veces reemplaza a la vieja", 'n.lejanoSeguidas >= 3' in ub and 'n.porqueFirme = "reubicada"' in ub and 'dentroDeLaCasa(ac.aplicar(c)' in ub)
ok("cada captura de pantalla y cada cambio del rastreo van a la bitácora", 'userDidTakeScreenshotNotification' in v and 'anotarMedir("rastreo", ["estado": estado])' in vr)
try:
    web = rd(fr + '/www/index.html')
    ok("Field Reports no manda la bandera", 'porMovimiento' not in web)
except Exception:
    ok("Field Reports no manda la bandera (no se encontró " + fr + ")", False)
# ---- (13 pasos, 16 oct) ÁREA A: la franja, sin la pregunta de cerrar la pared, "Revisar y mandar" y "falta una pared" ----
pb = bloque(v, 'fileprivate func pintarBotonTerminarCuarto')
ok("arriba 'Revisar y mandar' con el número de TODAS las medidas; ya no hay 'Terminar cuarto'", 'n.terminar.setTitle("Revisar y mandar", for: .normal)' in pb and 'n.terminarCuenta.text = " \\(items.count) "' in pb
   and 'setTitle("Terminar cuarto"' not in v and 'titulo: "Terminar cuarto"' not in v and 'func terminarCuarto' not in v and 'cuartosTerminados' not in v and 'func siguienteCuarto' not in v)
ok("la hoja dice lo que falta y sigue mandando por el camino de siempre", 'let falta = loQueFalta()' in bloque(v, 'private func armarHojaDelCuarto') and 'self.nueva.terminarDeVerdad = true\n            self.terminarNuevoTocado()' in v and '"Sin medida: "' in bloque(v, '@objc fileprivate func terminarNuevoTocado'))
rf = bloque(v, 'private func revisarParedQueFalta')
ok("(idea 4) 'falta una pared' solo unos segundos fuera y ya en el cuarto nuevo, después de la regla madre", 'guard ahora - s.desde >= Self.esperaParaFalta, ahora - n.cuartoDesde >= Self.esperaEnElCuarto' in rf and 'static let esperaParaFalta: Double = 6' in v and rm.index('guard !bloqueoDeParte()') < rm.index('revisarParedQueFalta(ahora)'))
ok("'falta una pared' solo si es seguro cuál falta, y nunca crea una medida", 'guard p.seguro else' in rf and 'items.append' not in bloque(v, 'private func contestarFalta')
   and 'boton("No se cortó", azul: false) { $0.contestarFalta(volver: false) }' in bloque(v, 'fileprivate func armarFaltaPared')
   and 'boton("Volver", azul: true) { $0.contestarFalta(volver: true) }' in bloque(v, 'fileprivate func armarFaltaPared') and 'anotarMedir("falta-pared", ["que": "no-se-corto"' in v)
ac = bloque(v, 'private func aplicarCambio')
ok("el cuarto cambia solo con su aviso de vidrio y vibra; la pared y la parte con un toquecito, sin aviso", 'vibrar(.cuarto)' in ac and 'mostrarAvisoNuevo("Ahora: \\(c)", segundos: 2.5, sub: "Por el mapa", icono: "mappin.and.ellipse")' in ac and 'vibrar(.cambio)' in ac and 'por el teléfono", segundos: 2.5)' not in v)
ok("el aviso de vidrio acepta título y explicación ya partidos (y su ícono)", 'sub: String? = nil, icono: String? = nil)' in v and 'Self.partesDelAviso(' in bloque(v, 'fileprivate func mostrarAvisoNuevo'))
ok("el mapita marca a dónde apunta (azul) y lo que falta (rojo punteado)", 'if i == apuntada { ctx.setStrokeColor(Claro.azul.cgColor)' in v and 'ctx.setLineDash(phase: 0, lengths: [5, 4])' in v and 'm.apuntada = section == "wall"' in v)
mp = bloque(v, 'private func maquetaMedirPrimeroPaso')
casos = set(int(x) for c in re.findall(r'\n\s*case ([0-9, ]+):', mp) for x in c.split(',') if x.strip())
ok("las maquetas de los 13 pasos (55-90) y de las revisiones (91-110), cada una con su caso", set(range(55, 111)) <= casos and 'guard (24...110).contains(maqueta), medirPrimero' in v and 'case 24...110:' in v)
# ---- "AQUÍ ESTOY" (17 oct): el toque en el mapa es solo pista; vibra suave buscando y fuerte al ubicarse ----
cuerpo = bloque
def tramo_cercano(src):
    u = bloque(src, 'fileprivate func ubicarseEnElPlano')
    i = u.index('if let actual = n.acomodo, actual.seguro'); j = u.index('} else if !n.firme || sinConfirmar > 6 {', i)
    return u[i:j]
ok("el toque en el mapa es solo pista: ubicar no recibe pista", 'pista' not in bloque(v, 'static func ubicar('))
ok("pistaContradice nunca pone firme/acomodo/seguro", all(x not in cuerpo(v,'func pistaContradice') for x in ['firme =','acomodo =','.seguro =','ultimaConfirmacion =']))
ok("pistaTocada y pistaVigente tampoco ubican", all(x not in cuerpo(v,'func pistaTocada') + cuerpo(v,'func pistaVigente') for x in ['firme =','acomodo =','.seguro =','ultimaConfirmacion =','ubicadoDesde =']))
ok("el mapa solo toma toques con aceptaPista (nunca midiendo)", 'aceptaPista, alTocarMapa != nil' in v and '!medidaEnCurso && pathPoints.isEmpty && widthPoints.isEmpty' in v)
ok("la pista se olvida al cambiar nivel/cuarto, al ubicarse y al rendirse", v.count('olvidarPista()') >= 6)
ok("3 respuestas seguras fuera del círculo descartan la pista", 'n.pistaDescartadas >= 3, ac.puntaje >= 8' in v)
ok("la confirmación cercana y 'contradicha' no usan la pista", 'pistaContradice' not in tramo_cercano(v))
ok("vibra suave buscando y fuerte al ubicarse", 'case .buscando: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.35)' in v and v.count('vibrar(.ubicado)') >= 2)
ok("alReubicarse ya no llama .success directo", 'notificationOccurred(.success)' not in cuerpo(v,'func alReubicarse'))
ok("el tic respeta medida en curso, calor y 20 s", 'lleva < 21.5' in v and 'thermalState' in cuerpo(v,'func ticDeBuscando'))
ok("Field Reports: sin planoPorCuarto no hay pista ni tic", '!planoPorCuarto.isEmpty' in cuerpo(v,'func pistaTocada') and '!planoPorCuarto.isEmpty' in cuerpo(v,'func ticDeBuscando'))
# ---- ÁREA B (idea 1 y los arcos) ----
dc = bloque(v, 'fileprivate func datosDelCorte')
ok("el corte pasa sus esquinas al plano solo con la ubicación confirmada en cada esquina y sin cortes del rastreo",
   'let ubicadas = esquinasUbicadas() ?? ubicacionReciente()' in dc and 'guard ubicadas, ubicacionBase(), !n.rastreoMaloEnMedida' in dc
   and 'UbicadorEnPlano.paredesMedidas(ac, puntos: puntosMedidosEnPies(), paredes: forma.paredes)' in dc
   and all(('c.porque = "%s"' % x) in dc for x in ['no veo el piso', 'falta ubicarse', 'no calza con el plano']) and 'aberturasDelPlano(forma)' in dc)
ok("el alto de la banda (o un +) cuenta desde el piso; con dos +, el punto más bajo", 'if widthPoints.isEmpty { c.arranque = 0 }' in dc and 'guard let piso = pisoConocido() else { c.porque = "no veo el piso"; return c }' in dc)
gat2 = bloque(v, 'fileprivate func gatilloMedir')
ok("cada esquina anota si la ubicación estaba confirmada; de la pared al piso no se cambia en la primera esquina",
   'let antes = pathPoints.count, ub = ubicacionReciente()' in gat2 and 'if pathPoints.isEmpty { n.zonaAlPrimerPunto = n.zonaVista; n.incluyeDelCorte = nil; n.altoParaRecordar = nil }' in gat2
   and 'if stage == .measuringLength, pathPoints.count > antes { n.ubicadaEnEsquina = Array(n.ubicadaEnEsquina.prefix(antes)) + [ub] }' in gat2 and '"frenado": true' in gat2)
eu = bloque(v, 'fileprivate func esquinasUbicadas')
ok("(revisión) Deshacer quita la bandera de su esquina: el corte vuelve a estar ubicado al marcarla otra vez ya ubicado",
   'guard !pathPoints.isEmpty, f.count >= pathPoints.count else { return nil }' in eu and 'return f.prefix(pathPoints.count).allSatisfy { $0 }' in eu
   and 'esquinasUbicadas' not in bloque(v, 'fileprivate final class CamaraNueva') and 'nueva.ubicadaEnEsquina = []' in bloque(v, 'private func cancelarMedidaEnCurso')
   and 'n.ubicadaEnEsquina = []' in bloque(v, 'fileprivate func guardarMedir') and 'esquinasUbicadas() ?? ubicacionReciente()' in bloque(v, 'private func paredesDeLasEsquinas'))
gc = bloque(v, 'fileprivate func guardarCorte')
ok("todo corte con alto congela lo del corte y pregunta '¿El corte incluye…?' una vez por cuarto, solo si arranca en el piso",
   'n.corte = datosDelCorte()' in gc and 'if let r = incluyeDelCuarto() { n.incluyeDelCorte = r } else { abrirPregunta(.incluye); return }' in gc and 'c.desdePiso' in gc and 'seguirConElCorte()' in gc)
ok("Kitchen, Bath y Laundry preguntan en cada pared", 'guard !ReglasDeMedir.cuartoSinAtajos(roomName) else { return nil }' in bloque(v, 'fileprivate func incluyeDelCuarto'))
ci2 = bloque(v, 'fileprivate func contestarIncluye')
ok("la respuesta vale para el cuarto y para esta medida", 'n.incluyeDeCuarto[claveDelIncluye()] = (base, base && shoe)' in ci2 and 'n.incluyeDelCorte = (base, base && shoe)' in ci2)
ok("el corte resta lo congelado (sus puertas y arcos)", 'return ReglasDeMedir.conLaRestaDelCorte(g, aberturas: c.aberturas, desde: c.desde)' in bloque(v, 'fileprivate func conLaParteEntera'))
gm4 = bloque(v, 'fileprivate func guardarMedir'); dm2 = bloque(v, 'fileprivate func deshacerMedir'); mm2 = bloque(v, 'fileprivate func pintarMuelleMedir')
ok("el corte que arranca en el piso guarda su baseboard pegado (lo marcado menos sus puertas y arcos)",
   'conBase = (ReglasDeMedir.baseboardDeLaPared(largo: largoMarcado, aberturas: c.aberturas), inc.shoe, "corte")' in gm4
   and 'let c = corte, c.desdePiso, g.unidad == "SF", g.ancho != nil, let inc = n.incluyeDelCorte, inc.base' in gm4
   and 'marcaAlGuardar = (paredes, pe != nil)' in gm4 and 'marcaAlGuardar = (paredes, true)' not in gm4
   and 'n.pegadaALaAnterior.insert(items.count - 1)' in gm4 and '"pegada": true' in gm4)
ok("un solo Deshacer quita los dos renglones", 'nueva.pegadaALaAnterior.remove(items.count - 1)' in bloque(v, 'private func bancarMedida')
   and 'nueva.pegadaALaAnterior.contains(ult)' in dm2 and 'undoTapped(); undoTapped()' in dm2 and 'anotarMedir("deshacer", ["quito": 2' in dm2 and '"las 2 de "' in mm2)
ok("la ficha enseña lo que se resta y el baseboard, y se toca para cambiarlo", 'renglonesDelCorte(L: pathTotalFeet, S: currentWidthFeet ?? 0)' in bloque(v, 'private func pintarCentroNuevo') and '#selector(fichaTocada)' in v)
ok("los arcos llegan del plano, se restan como puertas y no son seña de puerta para ubicarse",
   'esPaso: $0.esPaso' in bloque(v, 'private func aberturasDelPlano') and 'esPaso: !ventana && x.count >= 7 && (num(x[6]) ?? 0) > 0.5' in plg
   and '$0.esPaso ? 1 : 0' in bloque(v, 'private func planoParaBitacora') and 'senas.filter { $0.esVentana == quiere && !$0.esPaso }' in v)
# ---- ÁREA C (ideas 3 y 5, las vibraciones) ----
lca = bloque(v, 'fileprivate func listoConElAlto(_ h: Double, fuente: String)')
ok("Listo · 2 ft guarda por guardarCorte con el alto dicho", 'guardarCorte()' in lca and 'currentWidthFeet = h; stage = .widthDone' in lca)
ok("solo un alto MEDIDO aquí se vuelve el del nivel", 'n.altoParaRecordar = fuente == "recordado" ? nil : h' in lca)
ok("el alto del nivel se recuerda al guardar, una vez; vibra doble; la banda se quita", 'recordarAlto(h, item: indicePared)' in gm4 and 'altoRecordado() == nil' in gm4 and 'vibrar(.guardado)' in gm4 and 'quitarBanda()' in gm4)
ok("el alto nunca sale de la memoria de otras casas", 'MemoriaAsistente' not in medir)
mo = bloque(v, 'fileprivate func marcarOtroAlto')
ok("Otro alto: un + validado contra la pared marcada y el piso visto", 'ReglasDeMedir.altoDeUnPunto(' in mo and 'pisoConocido()' in mo and 'vibrar(.fallo)' in mo)
pc2 = bloque(v, 'fileprivate func pisoConocido')
ok("el piso para medir: solo planos 'floor' (nunca el adivinado ni una mesa)", '$0.clase == "floor"' in pc2 and 'ReglasDeMedir.pisoBajoLasEsquinas(' in pc2 and '1.35' not in pc2)
bc = bloque(v, 'fileprivate func botonDelCorte')
ok("sin piso: dos +; con piso y alto del nivel: Listo · 2 ft; la pared nunca vuelve a '¿Mide el alto?'", bc.index('guard pisoConocido() != nil else') < bc.index('if let a = altoRecordado()') and 'altoConDosPuntos(desde: "sin-piso")' in bc and 'terminarElLargo' not in bc)
ok("el alto vivo nunca va a la ficha ni a Listo", 'if let h = n.altoDeUnPunto { return (h, false) }' in bloque(v, 'fileprivate func altoDeLaBanda') and 'n.altoVivo' not in bloque(v, 'fileprivate func fichaDelCorte') and 'n.altoVivo' not in bc)
ok("MEDIDA cambia el material sin guardar", 'guardarMedir' not in bloque(v, 'fileprivate func ponerMaterial'))
lm2 = bloque(v, 'fileprivate func listoMedir')
ok("Listo de la pared con alto ya no pregunta el material", 'guardarCorte()' in lm2 and '.matPared' not in lm2)
sp2 = bloque(v, 'fileprivate func seguirConLaParteEntera')
ok("pared y piso completos con el material puesto; el techo pregunta", 'if pe.seccion == "floor", let pre = pisoPuesto()' in sp2 and 'abrirPregunta(Self.preguntaDelMaterial(pe.seccion))' in sp2)
ok("cocina, baño y lavandería: el piso se pregunta", 'guard !ReglasDeMedir.cuartoSinAtajos(roomName) else { return nil }' in bloque(v, 'fileprivate func pisoPuesto'))
ok("vibra distinto: ligero por esquina, doble al guardar, largo si no se pudo", 'import CoreHaptics' in v and 'fileprivate func vibrar(_ v: Vibra)' in v
   and 'if medirPrimero && nueva.medirActivo { vibrar(.esquina) } else { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }' in bloque(v, '@objc private func addTapped')
   and '.hapticContinuous' in v and 'guard medirPrimero, maqueta == 0 else { return }' in bloque(v, 'fileprivate func vibrar'))
ok("el cambio solo de pared o parte se siente fuerte (su prueba del 17 oct); el cuarto con dos golpes", 'case .cambio: UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)' in bloque(v, 'fileprivate func vibrar') and 'g.impactOccurred(intensity: 1.0) }' in bloque(v, 'fileprivate func vibrar'))
ok("la banda es de SceneKit, deja el hueco de la puerta y se quita con una pregunta abierta", 'SCNGeometrySource(vertices:' in v and 'mat.isDoubleSided = true' in v
   and 'ReglasDeMedir.tramosSinHuecos(largo: largo, huecos: huecos)' in v
   and 'guard !hayPanel, !lab.activo, let a = altoDeLaBanda(), let piso = pisoConocido() else { quitarBanda(); return }' in bloque(v, 'fileprivate func pintarBanda'))
ok("con el alto de la banda puesto el + no marca y Deshacer vuelve a las esquinas", 'if altoDeLaBandaPuesto { return }' in gat2 and 'if altoDeLaBandaPuesto {' in dm2)
# ---- LA REVISIÓN DEL 16 OCT (los defectos que encontraron los revisores) ----
gc3 = bloque(v, 'fileprivate func guardarCorte'); psc = bloque(v, 'fileprivate func preguntarSiYaCompleta')
ok("(revisión) un corte sobre una pared ya COMPLETA no se guarda en silencio: se pregunta antes de '¿El corte incluye…?'",
   'if preguntarSiYaCompleta("corte") { return }' in gc3 and gc3.index('preguntarSiYaCompleta("corte")') < gc3.index('abrirPregunta(.incluye)')
   and 'estadoDeLaPared($0) == "completa"' in psc and 'estadoDeLaParte(que) == "completa"' in psc and 'abrirPregunta(.sobreCompleta)' in psc
   and 'paredesDeLoQueSeGuarda()' in psc and 'guard medirPrimero' in psc)
ok("(revisión) el piso, el techo y el corte de 1 pie también preguntan", 'if conSegunda, preguntarSiYaCompleta("floor") { return }' in bloque(v, 'fileprivate func listoMedir')
   and 'if conSegunda, preguntarSiYaCompleta("ceiling") { return }' in bloque(v, 'fileprivate func listoMedir')
   and 'if !preguntarSiYaCompleta("un-pie") { resolverPared(m) }' in bloque(v, 'fileprivate func listoLineal') and 'if !s.preguntarSiYaCompleta("un-pie")' in pm2)
gsc = bloque(v, 'fileprivate func guardarSobreLoCompleto')
ok("(revisión) 'Guardar igual' guarda el corte SIN baseboard; 'No guardar' tira la medida; dos losetas parejas y la salida abajo",
   'else { n.incluyeDelCorte = (false, false); seguirConElCorte() }' in gsc and 'cancelarMedidaEnCurso(hablar: false)' in bloque(v, 'fileprivate func noGuardarSobreLoCompleto')
   and 'poner(rejilla([loseta("Guardar igual", otra)' in pm2 and 'loseta("No guardar", "deshacer la medida")' in pm2 and 'case .sobreCompleta:' in pm2)
ok("(revisión) un parche alto con dos + arranca en su + más bajo, no en las esquinas al pie de la pared",
   'else if let bajo = widthPoints.map({ Double($0.y) }).min() { c.arranque = max(0, (bajo - Double(piso)) * 3.28084) }' in dc and '(pathPoints + widthPoints)' not in dc
   and 'return abajo - p <= arranqueDelPiso / 3.28084' in v)
ok("(revisión) el piso puesto mira primero el de este cuarto", 'nivel: nivelActual, cuarto: roomName)' in bloque(v, 'fileprivate func pisoPuesto'))
ok("(revisión) el material de MEDIDA no se borra si el cambio es al cuarto donde estaba al tocarlo",
   'n.materialPuestoDonde = (ubicacionReciente() ? cuartoDondeEsta() : nil) ?? roomName' in bloque(v, 'fileprivate func ponerMaterial')
   and 'n.materialPuestoCuarto = roomName' in bloque(v, 'fileprivate func ponerMaterial'))
ec = bloque(v, 'fileprivate func escogerCompleta')
ok("(revisión) la franja rechazada no se queda pegada (firmaEleccion se queda para que revisarEleccion la esconda)", 'nueva.firmaEleccion = ""' not in ec and 'nueva.firmaPanel = ""' in ec)
ok("(revisión) el laboratorio quita la franja y 'falta una pared'", 'quitarFranjaYFalta()' in bloque(v, 'fileprivate func entrarLaboratorio')
   and '["que": "laboratorio"' in bloque(v, 'fileprivate func entrarLaboratorio'))
ok("(revisión) cambiar el cuarto a mano también arma 'falta una pared' (un solo lugar: salioDelCuarto)",
   'salioDelCuarto(antes, a: c)' in ac and 'salioDelCuarto(antes, a: roomName)' in bloque(v, 'private func elegirCuartoNuevo')
   and 'n.salidaDe = (antes, nivelActual, CACurrentMediaTime())' in bloque(v, 'fileprivate func salioDelCuarto') and v.count('n.salidaDe = (antes, nivelActual') == 1)
ok("(revisión) el + con 'falta una pared' a la vista solo la quita (la tarjeta tapa la mira)",
   'n.paredesEnRojo = nil; cerrarFalta(); pintarCamaraNueva(); return' in gat2)
ok("(revisión) de dónde viene el piso se lee entero: en la franja y en MEDIDA (se corta en medio, nunca el cuarto)",
   'let de = deDondeElPiso(pre.de)' in cf and 'l.lineBreakMode = .byTruncatingMiddle' in mm2 and '"toque para cambiar"' not in v)
# ---- LA SEGUNDA REVISIÓN DEL 16 OCT ----
acn = bloque(v, 'fileprivate func armarCamaraNueva')
ok("(revisión) la franja, la tarjeta de 'falta una pared' y la banda están conectadas, y la tarjeta se va sola en cada cuadro",
   '        armarFranja()\n' in acn and '        armarFaltaPared()\n' in acn
   and 'if medirPrimero && n.medirActivo { pintarBanda() }' in bloque(v, 'fileprivate func pintarCamaraNueva')
   and 'if medirPrimero { revisarFaltaQueVence() }' in bloque(v, 'fileprivate func tickCamaraNueva'))
ok("(revisión) el arco alto no corta el baseboard en NINGÚN lado: el número, la ficha y '¿Qué incluye?'",
   'aberturas.filter(cortaElBaseboard).reduce(0.0)' in reglas and 'let cortan = aberturas.filter(cortaElBaseboard)' in reglas
   and 'let cortan = ab.filter(ReglasDeMedir.cortaElBaseboard)' in pm2 and 'filter { !$0.esVentana }.reduce' not in reglas)
pdg = bloque(v, 'private func paredesDeLoQueSeGuarda')
ok("(revisión) 'ya está completa' mira las MISMAS paredes donde se guarda (sin las esquinas: la clase o la pared de enfrente)",
   'paredes = d.paredes.isEmpty ? paredesAlGuardar(clase: clase, corte: corte) : d.paredes' in gm4
   and 'let clase = maqueta == 0 ? claseDeLaMedida().paredes : ""' in pdg and 'let r = paredesAlGuardar(clase: clase, corte: nueva.corte)' in pdg
   and 'let ps = paredesDeLasEsquinas()' in pdg and 'let donde = paredesDeLoQueSeGuarda()' in psc
   and 'if !s.seguras, n.corte?.desdePiso == true { n.incluyeDelCorte = nil; n.incluyeSoloEsta = true; abrirPregunta(.incluye) }' in gsc
   and 'if !reusada && !n.incluyeSoloEsta { n.incluyeDeCuarto[claveDelIncluye()] = (base, base && shoe) }' in ci2)
ok("(revisión) el corte caminado sobre una completa Y otras paredes: sin 'Guardar igual', se miden aparte",
   'otras = donde.paredes.filter { !llenas.contains($0) }' in psc and 'if !sc.otras.isEmpty {' in pm2
   and 'poner(rejilla([loseta("No guardar", una ? "medirla aparte" : "medirlas aparte") { s in s.noGuardarSobreLoCompleto() }], columnas: 1), 4)' in pm2
   and 's.otras.isEmpty else { cerrarPregunta(); return }' in gsc)
sec = bloque(v, 'fileprivate func seguirConElCorte')
ok("(revisión) el baseboard que ya lleva la pared no se guarda otra vez en silencio: MEDIDA → Baseboard, la loseta, y el corte al revés",
   'case "Baseboard": if !preguntarSiYaLlevaBaseboard() { abrirPregunta(.shoe) }' in bloque(v, 'fileprivate func listoLineal')
   and 'if !s.preguntarSiYaLlevaBaseboard() { s.abrirPregunta(.shoe) }' in pm2
   and sec.index('if preguntarSiElCorteRepiteBaseboard() { return }') < sec.index('resolverPared(m)')
   and 'case "baseboard": abrirPregunta(.shoe)' in gsc and 'case "corte-base":' in gsc and gsc.count('else { n.incluyeDelCorte = (false, false); seguirConElCorte() }') == 2
   and 'ReglasDeMedir.baseboardDeMas(ya:' in bloque(v, 'private func baseboardRepetido') and 'if ya.contains(where: { items[$0].completa }) { return ya }' in bloque(v, 'private func baseboardRepetido'))
ok("(revisión) la franja dice el baseboard que se guarda solo con la pared", 'sub += r.shoe ? " · + baseboard y shoe" : " · + baseboard"' in cf)
pdq = bloque(v, 'fileprivate func paredesDe(')
ok("(revisión) 'falta una pared' no cuenta como sin medida lo que ya está guardado de otra sesión (ni sin saberlo)",
   'guard let ya = cuartosConParedes else { return ([], false, mias.count) }' in pdq and 'if delNivel.contains(where: { Self.clave($0) == k }) { return ([], false, mias.count) }' in pdq
   and pdq.index('let forma = planoPorCuarto') < pdq.index('cuartosConParedes') and 'if let ya = call.getObject("cuartosConParedes")' in plg)
lqf = bloque(v, 'fileprivate func loQueFalta')
ok("(revisión) al mandar se revisa el nivel del PLANO aunque esté en otro nivel", 'let nivelPlano = nueva.nivelDelPlano ?? nivelActual' in lqf and 'paredesDe(c, nivel: nivelPlano)' in lqf
   and '(fuera ? nivelPlano + " · " : "")' in lqf)
ok("(revisión) el alto de dos + se recuerda solo si cuenta desde el piso, y otro alto lo borra",
   'if widthPoints.count >= 2 {' in lm2 and 'n.altoParaRecordar = desdePiso ? ReglasDeMedir.altoDelNivelDeDosPuntos(ys, piso: pisoY, marcado: currentWidthFeet ?? 0) : nil' in lm2
   and 'if desdePiso { n.altoParaRecordar = currentWidthFeet }' not in v)
fdc = bloque(v, 'fileprivate func fichaDelCorte')
ok("(revisión) la ficha del corte se rehace si cambia lo que sale del corte (sus puertas en el tramo), el cuarto o el nivel",
   '|\\(deCorte)|\\(Self.clave(roomName))|\\(nivelActual)"' in fdc and 'renglonesDelCorte(L: L, S: alto, corte: c)' in fdc and 'restaEnCurso(L, alto, corte: c)' in fdc
   and 'nueva.fichaCorteFirma = ""; nueva.fichaCorte = nil' in bloque(v, 'private func cancelarMedidaEnCurso'))
# ---- LA TERCERA REVISIÓN DEL 16 OCT ----
pbr = bloque(v, 'private func preguntarBaseboardRepetido')
ok("(revisión 2) el corte caminado de una pared con baseboard a otra sin él: 'mídala aparte', nunca le quita el suyo a la otra",
   'let otras = donde.paredes.filter { !llenas.contains($0) }' in pbr and 'n.sobreCompleta = (que, llenas, otras, donde.seguras, donde.adivinada)' in pbr
   and 'n.sobreCompleta = (que, llenas, [], donde.seguras' not in v
   and 'case "corte", "corte-base": otra = !sc.seguras && (n.corte?.desdePiso ?? false) ? "preguntar el baseboard" : "sin baseboard"' in pm2
   and gsc.count('if !s.seguras, n.corte?.desdePiso == true { n.incluyeDelCorte = nil; n.incluyeSoloEsta = true; abrirPregunta(.incluye) }') == 2)
cpe3 = bloque(v, 'fileprivate func cancelarParteEntera')
ok("(revisión 2) 'No era completa · medir con +' guarda lo puesto (Plaster, 'Otro piso') para el parcial; Deshacer y reubicar lo quitan",
   'let mat = n.materialPuesto, matDonde = n.materialPuestoDonde, matCuarto = n.materialPuestoCuarto, sinPiso = n.sinPisoPuesto' in cpe3
   and 'if aParcial { n.materialPuesto = mat; n.materialPuestoDonde = matDonde; n.materialPuestoCuarto = matCuarto; n.sinPisoPuesto = sinPiso; n.materialPuestoNivel = matNivel }' in cpe3
   and cpe3.index('cancelarMedidaEnCurso(hablar: false)') < cpe3.index('if aParcial { n.materialPuesto = mat')
   and 'nueva.materialPuesto = nil; nueva.sinPisoPuesto = false\n        nueva.materialPuestoDonde = ""; nueva.materialPuestoCuarto = ""' in bloque(v, 'private func cancelarMedidaEnCurso'))
ok("(revisión 2) el piso puesto ve el ancho de cada renglón (lo lineal no es el piso del cuarto)", 'ancho: $0.width) }, nivel: nivelActual, cuarto: roomName)' in bloque(v, 'fileprivate func pisoPuesto'))
tf2 = bloque(v, 'fileprivate func tocarFranja'); ec2 = bloque(v, 'fileprivate func escogerCompleta')
ok("(revisión 2) la franja es de su cuarto y nivel: se quita al cambiar el cuarto, no se queda los 0.8 s y su toque no guarda en el cuarto nuevo",
   'var firma: String { "\\(parte)|\\(pared ?? -1)|\\(titulo)|\\(sub)|\\(habilitada)|\\(preset ?? "")|\\(cuarto)|\\(nivel)" }' in v
   and 'y.cuarto = aqui.cuarto; y.nivel = aqui.nivel' in re2
   and 'n.franjaContenido = nil; n.firmaEleccion = ""; pintarFranja()' in bloque(v, 'fileprivate func arreglarMedirPrimero')
   and 'guard c.cuarto == Self.clave(roomName), c.nivel == nivelActual else {' in tf2 and tf2.index('guard c.cuarto ==') < tf2.index('escogerCompleta(c.parte')
   and 'if medirPrimero, tapaLoCompleto(pared: pared, parte: p) {' in ec2 and ec2.index('tapaLoCompleto(pared: pared, parte: p)') < ec2.index('engancharParte(p, pared: pared)')
   and 'nueva.firmaEleccion = ""' not in ec2)
ok("(revisión 2) el material de MEDIDA aguanta asomarse a otro cuarto: no se borra al cambiar, vale solo en su cuarto",
   'if n.materialPuesto != nil, Self.clave(roomName) != Self.clave(n.materialPuestoDonde) { n.materialPuesto = nil }' not in v
   and 'if let p = materialPuestoVigente(), p.parte == "wall" { return p.material }' in bloque(v, 'fileprivate func materialDeLaPared')
   and 'if let p = materialPuestoVigente(), p.parte == "floor" { return (p.material, "") }' in bloque(v, 'fileprivate func pisoPuesto')
   and 'return k == Self.clave(n.materialPuestoDonde) || k == Self.clave(n.materialPuestoCuarto) ? p : nil' in bloque(v, 'fileprivate func materialPuestoVigente')
   and 'if let p = nueva.materialPuesto' not in v and 'if let p = n.materialPuesto' not in v
   and 'n.materialPuesto = nil; n.materialPuestoDonde = ""; n.materialPuestoCuarto = ""' in gm4)
ft = bloque(v, '@objc private func finishTapped'); ga = bloque(v, 'fileprivate func guardarAltosEnElTelefono')
ok("(revisión 2) el alto del nivel va al teléfono solo al mandar (o si la cámara se cae con medidas), nunca al guardar ni al salir sin mandar",
   'UserDefaults.standard.set(' not in bloque(v, 'fileprivate func recordarAlto') and 'removeObject' not in bloque(v, 'fileprivate func olvidarAlto')
   and 'UserDefaults.standard.set(["pies": a.pies, "cuarto": a.cuarto], forKey: llaveDelAlto(nivel))' in ga
   and 'where a.item < items.count && items[a.item].nivel == nivel' in ga and 'guard maqueta == 0, !trabajoId.isEmpty else { return }' in ga
   and v.count('guardarAltosEnElTelefono()') == 3 and ft.index('guardarAltosEnElTelefono()') < ft.index('onFinish?(.measured(')
   and 'if !guardadas.isEmpty { self.guardarAltosEnElTelefono() }' in v and 'guardarAltosEnElTelefono' not in bloque(v, '@objc private func cancelTapped')
   and 'altoFuente' not in v and v.count('UserDefaults.standard.set(["pies"') == 1
   and 'if let f = n.altosDeLaSesion[nivelActual], items.count <= f.item { olvidarAlto("deshacer") }' in bloque(v, 'fileprivate func altoRecordado'))
ok("(revisión 2) 'falta una pared': el mismo nombre en otro nivel no es 'regresó'",
   'if Self.clave(s.nombre) == Self.clave(roomName), s.nivel == nivelActual { n.salidaDe = nil; return }' in rf
   and 'else if let s = n.salidaDe, Self.clave(s.nombre) == Self.clave(c), s.nivel == nivelActual { n.salidaDe = nil }' in bloque(v, 'fileprivate func salioDelCuarto'))
# ---- LA REVISIÓN 3 DEL 16 OCT ----
psc3 = bloque(v, 'fileprivate func preguntarSiYaCompleta'); pdg3 = bloque(v, 'private func paredesDeLoQueSeGuarda'); pag3 = bloque(v, 'private func paredesAlGuardar')
geo3 = bloque(v, 'fileprivate func guardarEnOtraPared'); pac3 = bloque(v, 'private func paredActualConfirmada')
ok("(revisión 3) sin las esquinas en el plano ni la clase, la pared de enfrente sin confirmar es una suposición: '¿Es la pared N?', nunca afirmada",
   'return (r, false, !r.isEmpty && !porLoMedido && !paredActualConfirmada())' in pdg3 and 'if !ps.isEmpty { return (ps, true, false) }' in pdg3
   and 'if esquinasUbicadas() == nil { return ubicacionReciente() && paredApuntada() == pa }' in pac3 and 'return n.paredAlPrimerPunto == pa' in pac3
   and 'if pathPoints.isEmpty { n.paredAlPrimerPunto = ub ? paredApuntada() : nil; n.paredSinSaber = false }' in gat2
   and 'seguras = donde.seguras; adivinada = donde.adivinada' in psc3 and 'n.sobreCompleta = (que, llenas, otras, seguras, adivinada)' in psc3
   and 'if sc.adivinada, let i = sc.paredes.first {' in pm2 and '"¿Es la pared \\(i + 1)? " + (deBase ? "Ya lleva baseboard" : "Ya está completa")' in pm2
   and 'poner(rejilla([loseta("Es otra pared", "guardar") { s in s.guardarEnOtraPared() },' in pm2
   and 'loseta("Es la pared \\(i + 1)", "no guardar") { s in s.noGuardarSobreLoCompleto() }], columnas: 2), 4)' in pm2
   and pm2.index('if sc.adivinada, let i = sc.paredes.first {') < pm2.index('poner(rejilla([loseta("Guardar igual", otra)'))
ok("(revisión 3) 'Es otra pared · guardar' guarda sin pared (nunca en la completa) y sigue como si no hubiera salido la pregunta",
   'if r.isEmpty, !nueva.paredSinSaber, let i = nueva.paredActual { r = [i] }' in pag3
   and 'n.paredSinSaber = true' in geo3 and 's.adivinada, s.otras.isEmpty else { cerrarPregunta(); return }' in geo3
   and 'case "corte-base": seguirConElCorte()' in geo3 and 'case "baseboard": abrirPregunta(.shoe)' in geo3 and 'case "un-pie": resolverPared(ReglasDeMedir.drywallDeUnPie)' in geo3
   and '"que": "otra-pared"' in geo3 and v.count('n.paredAlPrimerPunto = nil; n.paredSinSaber = false') == 1 and v.count('nueva.paredAlPrimerPunto = nil; nueva.paredSinSaber = false') == 1
   and 'nueva.paredSinSaber = false' in bloque(v, 'private func cerrarPregunta'))
ok("(revisión 3) guardarMedir pone las MISMAS paredes que revisó la pregunta (las esquinas en el plano antes que la pared de enfrente)",
   'let d = paredesDeLoQueSeGuarda()\n                paredes = d.paredes.isEmpty ? paredesAlGuardar(clase: clase, corte: corte) : d.paredes' in gm4
   and gm4.index('let d = paredesDeLoQueSeGuarda()') < gm4.index('bancarMedida(opcion)'))
bm3 = bloque(v, 'private func bancarMedida')
ok("(revisión 3) cada renglón lleva la parte de la cámara: Greenboard o Backsplash (sección bathroom/kitchen) cuentan en su pared",
   'paredes: [Int], completa: Bool, parte: String)] = []' in v and 'completa: marca?.completa ?? false, parte: section))' in bm3
   and '$0.parte == "wall" && $0.paredes.contains(i) }' in bloque(v, 'fileprivate func estadoDeLaPared')
   and '$0.parte == parte }' in bloque(v, 'fileprivate func estadoDeLaParte')
   and 'it.parte == parte\n            && (parte != "wall" || it.paredes.contains(i ?? -1))' in bloque(v, 'fileprivate func tapaLoCompleto')
   and '(nivel.isEmpty || $0.nivel == nivel) && $0.parte == "wall" }' in pdq and 'it.nivel == nivelActual) && it.parte == section' in pm2
   and 'let seccionGuardada = seccionDelMaterial(material.value)' in bm3 and 'seccion: seccionGuardada' in bm3)
dc3 = bloque(v, 'fileprivate func datosDelCorte')
ok("(revisión 3) las puertas del corte se buscan en los tramos JUNTADOS de cada pared (un + a media puerta no la parte)",
   'for tr in ReglasDeMedir.tramosUnidos(tramos) {' in dc3 and 'c.tramos = tramos' in dc3 and 'for tr in tramos {' not in dc3)
ok("(revisión 3) la franja de la pared dice 'sin baseboard' cuando el cuarto contestó 'Nada más'",
   'if r.base { sub += r.shoe ? " · + baseboard y shoe" : " · + baseboard" }\n                else { sub += " · sin baseboard" }' in cf
   and 'if let r = incluyeDelCuarto(), ReglasDeMedir.baseboardDeLaPared(largo: d.largo, aberturas: d.aberturas) > 0.5 {' in cf)
mpv3 = bloque(v, 'fileprivate func materialPuestoVigente'); pm3 = bloque(v, 'fileprivate func ponerMaterial')
ok("(revisión 3) el material de MEDIDA vale en su nivel (el Bathroom de arriba no es el de abajo); al regresar vuelve",
   'if !n.materialPuestoNivel.isEmpty && n.materialPuestoNivel != nivelActual { return nil }' in mpv3
   and mpv3.index('if n.materialPuestoDonde.isEmpty && n.materialPuestoCuarto.isEmpty { return p }') < mpv3.index('n.materialPuestoNivel != nivelActual')
   and 'n.materialPuestoNivel = nivelActual' in pm3 and 'n.materialPuestoNivel = ""' in gm4 and 'nueva.materialPuestoNivel = ""' in bloque(v, 'private func cancelarMedidaEnCurso')
   and 'matNivel = n.materialPuestoNivel' in cpe3)
ok("(revisión 3) un piso escogido en MEDIDA después de 'Otro piso' sí cuenta (riel, palomita y Listo)",
   'if section == "floor" { n.sinPisoPuesto = false }' in pm3 and pm3.index('n.materialPuesto = (section, m)') < pm3.index('if section == "floor" { n.sinPisoPuesto = false }')
   and 'if n.sinPisoPuesto { return nil }' in bloque(v, 'fileprivate func pisoPuesto'))
ok("la bitácora de los 13 pasos", all(('anotarMedir("' + x + '"') in v for x in ['alto', 'alto-recordado', 'alto-olvidado', 'otro-alto', 'banda', 'material-puesto', 'piso-puesto', 'franja', 'falta-pared', 'revisar', 'corte']))
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
// Su prueba del 16-oct: la pared completa (con resta) + el techo (sin resta) en la MISMA tanda -> 400 "All object keys must match".
const tanda = M.filasDeCamara([{ length: 20, width: 8.1, material: 'Drywall', companion: 'Insulation', nivel: 'First Floor', cuarto: 'Living Room', seccion: 'wall', menos: 32.1, menosQue: '1 door, 1 window' },
  { length: 1.3, width: 0.8, material: 'Drywall', nivel: 'First Floor', cuarto: 'Living Room', seccion: 'ceiling' }], base).map((x, i) => M.filaParaGuardar({ ...x, id: 'id' + i }, 'T', null, null));
const llaves = tanda.map(x => Object.keys(x).sort().join(','));
ok('al guardar lo de la cámara, TODAS las filas de una tanda llevan los mismos campos (con y sin resta)', tanda.length === 3 && new Set(llaves).size === 1);
ok('la que no tiene resta va con menos y menos_que en null', tanda[2].menos === null && tanda[2].menos_que === null && tanda[0].menos === 32.1 && tanda[0].menos_que === '1 door, 1 window');
ok('guardarDeCamara usa esa fila', src.includes('filas.push(filaParaGuardar(n, tid, nivel, cuarto));'));
const pl = (await import('node:fs')).readFileSync(process.argv[2].replace('medidas.js', 'planos.js'), 'utf8');
ok('la página manda el piso completo de cada cuarto: área, largo, ancho y si es aproximado (solo con el contorno bueno)',
   pl.includes('forma.piso = [r2(mm.floorSqFt), r2(Math.max(a, b)), r2(Math.min(a, b)), (mm.guessedFt || 0) > 1 ? 1 : 0];') && pl.includes('mm.outlineOk && mm.floorSqFt > 1'));
ok('en el editor se puede quitar la resta', src.includes('id="medMenos"') && src.includes('fila.menos = null; fila.menos_que = null;'));
ok("la página manda la bandera solo al manager, y de qué trabajo es", src.includes('porMovimiento: esManager(), trabajo: tid'));
// ---- (16-oct, idea 1) el corte con su puerta restada y su baseboard llegan como dos medidas (4 líneas) ----
const cp = M.filasDeCamara([{ length: 12, width: 2, material: 'Drywall', companion: 'Insulation', nivel: 'First Floor', cuarto: 'Living Room', seccion: 'wall', menos: 6, menosQue: '1 door' },
  { length: 9, material: 'Baseboard', companion: 'Shoe Molding', nivel: 'First Floor', cuarto: 'Living Room', seccion: 'wall' }], base);
ok('el corte con la puerta: Drywall 18 SF + Insulation 18 SF, Baseboard 9 LF + Shoe Molding 9 LF', cp.length === 4 && neto(cp[0]) === 18 && cp[1].material === 'Insulation' && neto(cp[1]) === 18
   && M.calcular(cp[2].material, cp[2].largo, cp[2].ancho).linear === 9 && cp[3].material === 'Shoe Molding');
ok("y se lee '12 × 2 ft − 6 sq ft (1 door)'", M.medidaTexto(cp[0]) === '12 × 2 ft − 6 sq ft (1 door)');
// ---- (16-oct, segunda revisión) lo ya guardado de otra sesión y la resta de Paneling y lo escrito a mano ----
const cc = M.cuartosConParedes([{ seccion: 'wall', nivel: '2nd Floor', cuarto: 'Bedroom 2' }, { seccion: 'wall', nivel: '2nd Floor', cuarto: 'bedroom 2 ' },
  { seccion: 'floor', nivel: '2nd Floor', cuarto: 'Kitchen' }, { seccion: 'wall', nivel: '', cuarto: 'Hallway' }, { seccion: 'wall', nivel: '2nd Floor', cuarto: '' }]);
ok('los cuartos con paredes ya guardadas, por nivel (sin repetir; el piso no cuenta)', JSON.stringify(cc) === JSON.stringify({ '2nd Floor': ['Bedroom 2'], '': ['Hallway'] }));
ok('la página los manda a la cámara solo con las medidas cargadas', src.includes('const yaGuardadas = CARGADO === tid && !FALLO ? cuartosConParedes(') && src.includes('...(yaGuardadas ? { cuartosConParedes: yaGuardadas } : {})'));
// ---- (revisión 4) ----
const cb = M.cuartosConParedes([{ seccion: 'bathroom', material: 'Shower Tile', nivel: '1st Floor', cuarto: 'Bathroom' }, { seccion: 'bathroom', material: 'Greenboard', nivel: '1st Floor', cuarto: 'Laundry Room' },
  { seccion: 'kitchen', material: 'Backsplash', nivel: '1st Floor', cuarto: 'Kitchen' }, { seccion: 'bathroom', material: 'Toilet', nivel: '1st Floor', cuarto: 'Half Bathroom' },
  { seccion: 'bathroom', material: 'Floor Tile', nivel: '1st Floor', cuarto: 'Half Bathroom' }, { seccion: 'kitchen', material: 'Cabinets', nivel: '1st Floor', cuarto: 'Pantry' }]);
ok('(revisión 4) Shower Tile, Greenboard y Backsplash cuentan como paredes; Toilet, Floor Tile y Cabinets no', JSON.stringify(cb) === JSON.stringify({ '1st Floor': ['Bathroom', 'Laundry Room', 'Kitchen'] }));
ok('(revisión 4) la página manda el material para eso', src.includes('cuartosConParedes(FILAS.map(f => ({ seccion: f.seccion, material: f.material,'));
const pg = M.partesYaGuardadas([{ seccion: 'wall', material: 'Drywall', largo: 12, ancho: 8.1, nivel: '2nd', cuarto: 'Bedroom 2' }, { seccion: 'wall', material: 'Baseboard', largo: 9, ancho: null, nivel: '2nd', cuarto: 'Bedroom 2' },
  { seccion: 'floor', material: 'Carpet', largo: 14, ancho: 10, nivel: '2nd', cuarto: 'Bedroom 2' }, { seccion: 'kitchen', material: 'Cabinets', largo: 10, ancho: 2, nivel: '2nd', cuarto: 'Kitchen' }]);
ok('(revisión 4) lo de pies² ya guardado va a la cámara (pared y piso; nunca el baseboard ni la cocina)', pg.length === 2 && pg[0].parte === 'wall' && pg[0].alto === 8.1 && pg[1].parte === 'floor'
   && src.includes('...(partesGuardadas ? { partesGuardadas } : {})'));
ok('(revisión 4) el editor desmarca la resta solo si cambió el tamaño', src.includes('const tamanoCambiado = (e) =>') && src.includes("ED.restaAuto = true; ED.restar0 = ED.restar; ED.restar = false;") && src.includes("largo0: String(f.largo)"));
console.log(`\n  página: ${p} pasan, ${f} fallan`);
process.exit(f ? 1 : 0);
JSEOF
exit $E
