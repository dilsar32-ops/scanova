#!/bin/bash
# LA PARTE SALE DEL MOVIMIENTO DEL TELÉFONO (16 oct 2026): los cimientos.
# - el DETECTOR puro (ClasificadorDeParte) sacado del Swift REAL y corrido con swiftc: abajo = piso, arriba = techo,
#   derecho = pared; esquinas, muebles y el teléfono en movimiento nunca ganan;
# - la bandera: Scanova la manda solo para el manager, Field Reports no la manda, y sin ella nada corre;
# - el bloque nuevo todavía NO hace nada en la pantalla: ni escoge parte, ni habla, ni toca medidas ni la insulación
#   (eso llega con el diseño nuevo: "medir primero, el material al final").
# Corre desde las pruebas de Field Reports (tests/) o desde el repo de Scanova (tests/camara/).
# Uso:  bash tests/camara/parte_por_movimiento_test.sh     (SCANOVA_DIR / FR_DIR para otras rutas)
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$DIR/../ios/App/App/ARMeasureViewController.swift" ]; then RAIZ="$(cd "$DIR/.." && pwd)"; else RAIZ="$(cd "$DIR/../.." && pwd)"; fi
FR="${FR_DIR:-/Users/amilcargonzalez/Downloads/field-report-ios-app}"
if [ -n "$SCANOVA_DIR" ]; then SC="$SCANOVA_DIR"; elif [ -f "$RAIZ/docs/medidas.js" ]; then SC="$RAIZ"; else SC="$RAIZ/../scanova"; fi
OUT="$(mktemp -t parte).swift"
E=0
python3 - "$RAIZ" "$SC" "$FR" "$OUT" <<'PYEOF' || E=1
import io, sys, re
raiz, sc, fr, out = sys.argv[1:5]
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
clasificador = bloque(v, 'struct ClasificadorDeParte {')
prueba = r'''
typealias C = ClasificadorDeParte
var pasan = 0, fallan = 0
func ok(_ l: String, _ c: Bool, _ d: String = "") { if c { pasan += 1; print("  ok  " + l) } else { fallan += 1; print("  FALLA " + l + " " + d) } }
// El teléfono a 1.35 m del piso (pisoY = 0), el techo a 2.44 m (8 ft).
func m(_ grados: Double, _ g: C.Golpe?, giro: Double = 0, rastreo: Bool = true, adivinado: Bool = false, techoY: Double? = 2.44) -> C.Muestra {
    C.Muestra(grados: grados, giro: giro, rastreoNormal: rastreo, golpe: g, camY: 1.35, pisoY: 0, pisoAdivinado: adivinado, techoY: techoY)
}
func pared(h: Double, d: Double = 1.2, clase: String = "wall", tope: Double? = nil, plano: Double? = nil) -> C.Golpe {
    C.Golpe(vertical: true, clase: clase, y: h, d: d, tope: tope, aPared: nil, aParedPlano: plano)
}
func plana(y: Double, d: Double = 1.5, clase: String = "", aPared: Double? = nil) -> C.Golpe {
    C.Golpe(vertical: false, clase: clase, y: y, d: d, tope: nil, aPared: aPared, aParedPlano: nil)
}
func voto(_ x: C.Muestra, _ actual: String?) -> C.Voto { C.votar(x, actual: actual) }
// ---- votar ----
ok("pie de pared (h 0.10) apuntando abajo: esquina", voto(m(-45, pared(h: 0.10)), "wall") == .esquina)
ok("corte a 2 ft (h 0.6) a -45° ya en pared: pared", voto(m(-45, pared(h: 0.6)), "wall") == .pared)
ok("el mismo corte viniendo del piso: nada (no se entra a pared tan inclinado)", voto(m(-45, pared(h: 0.6)), "floor") == .nada)
ok("baseboard visto en el piso (a 0.12 m de la pared): esquina", voto(m(-50, plana(y: 0, clase: "floor", aPared: 0.12)), "wall") == .esquina)
ok("piso a 0.5 m de la pared, -60°: piso", voto(m(-60, plana(y: 0.05, aPared: 0.5)), "wall") == .piso)
ok("piso sin pared conocida a -50° estando en pared: nada", voto(m(-50, plana(y: 0.02)), "wall") == .nada)
ok("piso a -60°: piso", voto(m(-60, plana(y: 0.02)), "wall") == .piso)
ok("ya en piso, -47° se queda en piso", voto(m(-47, plana(y: 0.02)), "floor") == .piso)
ok("techo a +40° (0.9 m arriba del teléfono): techo", voto(m(40, plana(y: 2.25), techoY: nil), "wall") == .techo)
ok("techo a +28° estando en pared: nada", voto(m(28, plana(y: 2.25), techoY: nil), "wall") == .nada)
ok("techo a +28° ya en techo: techo", voto(m(28, plana(y: 2.25), techoY: nil), "ceiling") == .techo)
ok("corona (a 0.1 m del techo): esquina", voto(m(30, pared(h: 2.34)), "wall") == .esquina)
ok("sofito 0.5 m arriba a +40°: techo", voto(m(40, plana(y: 1.85), techoY: nil), "wall") == .techo)
ok("cubierta a 0.9 m, -60°: nada", voto(m(-60, plana(y: 0.9), techoY: nil), "floor") == .nada)
ok("frente de gabinete (sin clase, llega a 0.9 m): nada", voto(m(-10, pared(h: 0.5, clase: "", tope: 0.9)), "wall") == .nada)
ok("una puerta (llega a 2 m): pared", voto(m(0, pared(h: 1.0, clase: "door", tope: 2.0)), "wall") == .pared)
ok("mesa: nada", voto(m(-60, plana(y: 0.75, clase: "table")), "floor") == .nada)
ok("sillón o cama: nada", voto(m(-20, pared(h: 0.4, clase: "seat")), "wall") == .nada)
ok("ya ubicado y el golpe a 0.6 m de toda pared del plano (un mueble sin clase): nada", voto(m(0, pared(h: 1.2, clase: "", plano: 0.6)), "wall") == .nada)
ok("ARKit dice que ES pared aunque la ubicación esté corrida 0.6 m: pared (su prueba del 16 oct)", voto(m(0, pared(h: 1.2, plano: 0.6)), "wall") == .pared)
ok("ya ubicado y el golpe sobre la pared del plano: pared", voto(m(0, pared(h: 1.2, plano: 0.1)), "wall") == .pared)
ok("volteando a 80°/s: moviendo", voto(m(-60, plana(y: 0.02), giro: 80), "floor") == .moviendo)
ok("rastreo malo a -80°: nada (nada por pura inclinación)", voto(m(-80, plana(y: 0.02), rastreo: false), "floor") == .nada)
ok("sin golpe a -80°: nada", voto(m(-80, nil), "floor") == .nada)
ok("golpe a 5.5 m: nada", voto(m(0, pared(h: 1.2, d: 5.5)), "wall") == .nada)
ok("golpe a 0.1 m: nada", voto(m(0, pared(h: 1.2, d: 0.1)), "wall") == .nada)
ok("pared a 4.5 m: nada", voto(m(0, pared(h: 1.2, d: 4.5)), "wall") == .nada)
ok("teléfono acostado leyendo a -70° sobre el piso: piso (lo frena quien decide, no el voto)", voto(m(-70, plana(y: 0.02, d: 1.4)), "wall") == .piso)
ok("con el piso adivinado el pie de pared es más alto (0.25 m: esquina)", voto(m(-30, pared(h: 0.25), adivinado: true), "wall") == .esquina)
ok("con el piso visto, 0.25 m ya es pared", voto(m(-30, pared(h: 0.25)), "wall") == .pared)
// ---- la ventana de 1.5 s ----
func serie(_ vs: [C.Voto], desde: Double = 0, paso: Double = 0.1, grados: Double = 0) -> C {
    var c = C(); for (i, x) in vs.enumerated() { c.anotar(x, t: desde + Double(i) * paso, grados: grados) }; return c
}
let ahora = 1.4
ok("15 muestras en 1.5 s, 12 de piso y las 3 últimas de piso: floor", serie(Array(repeating: .nada, count: 3) + Array(repeating: .piso, count: 12)).estable(por: 1.5, ahora: ahora) == "floor")
ok("10 de 15: nada", serie(Array(repeating: .nada, count: 5) + Array(repeating: .piso, count: 10)).estable(por: 1.5, ahora: ahora) == nil)
ok("las 3 últimas distintas: nada", serie(Array(repeating: .piso, count: 12) + [.nada, .esquina, .nada]).estable(por: 1.5, ahora: ahora) == nil)
ok("3 moviendo: nada", serie([C.Voto.moviendo, .moviendo, .moviendo] + Array(repeating: .piso, count: 12)).estable(por: 1.5, ahora: ahora) == nil)
ok("2 moviendo sí se perdonan", serie([C.Voto.moviendo, .moviendo, .nada] + Array(repeating: .piso, count: 12)).estable(por: 1.5, ahora: ahora) == "floor")
ok("mayoría de esquina: nada (la esquina nunca gana)", serie(Array(repeating: .esquina, count: 15)).estable(por: 1.5, ahora: ahora) == nil)
ok("puro nada: nada", serie(Array(repeating: .nada, count: 15)).estable(por: 1.5, ahora: ahora) == nil)
ok("solo 1.0 s de muestras: nada", serie(Array(repeating: .pared, count: 11)).estable(por: 1.5, ahora: 1.0) == nil)
ok("15 de pared: wall", serie(Array(repeating: .pared, count: 15)).estable(por: 1.5, ahora: ahora) == "wall")
ok("15 de techo: ceiling", serie(Array(repeating: .techo, count: 15)).estable(por: 1.5, ahora: ahora) == "ceiling")
var largo = C(); for i in 0..<200 { largo.anotar(.pared, t: Double(i) * 0.1, grados: 0) }
ok("guarda solo los últimos 4 s (\(largo.votos.count) votos)", largo.votos.count <= 41 && largo.votos.first!.t >= 19.9 - 4.0)
// ---- el giro ----
var g1 = C(); g1.anotar(.pared, t: 0, grados: 0); g1.anotar(.nada, t: 1, grados: -15); g1.anotar(.piso, t: 2, grados: -30)
ok("de 0° a -30° en 2 s: giro", g1.huboGiro(ahora: 2))
var g2 = C(); g2.anotar(.pared, t: 0, grados: 0); g2.anotar(.nada, t: 2, grados: -20)
ok("de 0° a -20°: no es giro", !g2.huboGiro(ahora: 2))
var g3 = C(); g3.anotar(.pared, t: 0, grados: 0); g3.anotar(.piso, t: 0.5, grados: -30); for i in 1...10 { g3.anotar(.piso, t: 0.5 + Double(i) * 0.5, grados: -30) }
ok("un giro de hace 5 s ya no cuenta", !g3.huboGiro(ahora: 5.5))
// ---- LA PARTE DE LA MEDIDA POR SUS PUNTOS (su prueba del 16 oct: el techo, luego la pared se guardaba como techo) ----
func P(_ x: Double, _ y: Double, _ z: Double) -> SIMD3<Double> { SIMD3(x, y, z) }
let cam = 1.40
ok("la base de la pared en el piso y el alto que SUBE 4 ft: pared (aunque iba en techo)",
   C.parteDeLaMedida(largo: [P(0, 0.02, 0), P(4.27, 0.02, 0)], segunda: [P(4.27, 0.02, 0), P(4.27, 1.24, 0)], camY: cam, pisoY: 0, actual: "ceiling", zona: nil) == "wall")
ok("el techo: el ancho corre plano arriba del teléfono: techo",
   C.parteDeLaMedida(largo: [P(0, 2.44, 0), P(3.66, 2.44, 0)], segunda: [P(3.66, 2.44, 0), P(3.66, 2.44, 3.05)], camY: cam, pisoY: 0, actual: "wall", zona: nil) == "ceiling")
ok("el piso: el ancho corre plano pegado al piso: piso",
   C.parteDeLaMedida(largo: [P(0, 0.01, 0), P(3.66, 0.01, 0)], segunda: [P(3.66, 0.01, 0), P(3.66, 0.01, 3.05)], camY: cam, pisoY: 0, actual: "ceiling", zona: nil) == "floor")
ok("un ancho plano a media altura (una cubierta): no se sabe, se queda la de antes",
   C.parteDeLaMedida(largo: [P(0, 0.9, 0), P(2, 0.9, 0)], segunda: [P(2, 0.9, 0), P(2, 0.9, 0.6)], camY: cam, pisoY: 0, actual: "wall", zona: nil) == nil)
ok("solo el largo a media pared (la línea del corte a 2 ft): pared",
   C.parteDeLaMedida(largo: [P(0, 0.61, 0), P(4, 0.61, 0)], segunda: [], camY: cam, pisoY: 0, actual: "ceiling", zona: nil) == "wall")
ok("solo el largo pegado al piso con la parte en techo: pared (baseboard), nunca techo",
   C.parteDeLaMedida(largo: [P(0, 0.03, 0), P(4, 0.03, 0)], segunda: [], camY: cam, pisoY: 0, actual: "ceiling", zona: nil) == "wall")
ok("solo el largo pegado al piso, en techo, y el teléfono ya ve el piso: piso (tackless)",
   C.parteDeLaMedida(largo: [P(0, 0.03, 0), P(4, 0.03, 0)], segunda: [], camY: cam, pisoY: 0, actual: "ceiling", zona: "floor") == "floor")
ok("solo el largo pegado al piso con la parte en pared: se queda pared (baseboard)",
   C.parteDeLaMedida(largo: [P(0, 0.03, 0), P(4, 0.03, 0)], segunda: [], camY: cam, pisoY: 0, actual: "wall", zona: nil) == nil)
ok("solo el largo allá arriba (crown, la orilla del techo): techo",
   C.parteDeLaMedida(largo: [P(0, 2.4, 0), P(4, 2.4, 0)], segunda: [], camY: cam, pisoY: 0, actual: "wall", zona: nil) == "ceiling")
ok("sin piso conocido se supone 1.35 m abajo del teléfono",
   C.parteDeLaMedida(largo: [P(0, 0.07, 0), P(4, 0.07, 0)], segunda: [P(4, 0.07, 0), P(4, 1.3, 0)], camY: cam, pisoY: nil, actual: "floor", zona: nil) == "wall")
ok("una sola esquina no decide nada", C.parteDeLaMedida(largo: [P(0, 0.03, 0)], segunda: [], camY: cam, pisoY: 0, actual: "ceiling", zona: nil) == nil)
// ---- AHORA MISMO (la primera esquina): los últimos 3 votos de medio segundo para acá ----
var cA = C(); cA.anotar(.techo, t: 0.0, grados: 40); cA.anotar(.pared, t: 0.8, grados: 2); cA.anotar(.pared, t: 0.9, grados: 1); cA.anotar(.pared, t: 1.0, grados: 0)
ok("acaba de bajar a la pared (3 votos de pared): pared", cA.ahoraMismo(ahora: 1.05) == "wall")
var cB = C(); cB.anotar(.pared, t: 0.8, grados: 0); cB.anotar(.esquina, t: 0.9, grados: -40); cB.anotar(.esquina, t: 1.0, grados: -42)
ok("apuntando al pie de la pared (esquina): no se sabe", cB.ahoraMismo(ahora: 1.05) == nil)
var cD = C(); cD.anotar(.pared, t: 0.1, grados: 0); cD.anotar(.pared, t: 0.2, grados: 0); cD.anotar(.pared, t: 0.3, grados: 0)
ok("votos viejos (de hace más de medio segundo) no cuentan", cD.ahoraMismo(ahora: 1.5) == nil)
print("\n  \(pasan) pasan, \(fallan) fallan")
exit(fallan == 0 ? 0 : 1)
'''
io.open(out, 'w', encoding='utf-8').write('import Foundation\nimport simd\n' + clasificador + '\n' + prueba)

# ---- La estructura (con python) ----
p = f = 0
def ok(l, c):
    global p, f
    if c: p += 1; print("  ok  " + l)
    else: f += 1; print("  FALLA " + l)
ok("el detector no usa ARKit (se compila solo con Foundation y simd)", 'ARKit' not in clasificador and 'ARPlaneAnchor' not in clasificador)
ok("el puente lee la bandera", 'arVC.porMovimiento = call.getBool("porMovimiento") ?? false' in plg)
med = rd(sc + '/docs/medidas.js')
ok("Scanova la manda, primero solo para el manager", 'porMovimiento: esManager()' in med)
try:
    web = rd(fr + '/www/index.html')
    ok("Field Reports NO la manda (su cámara sigue igual)", 'porMovimiento' not in web)
except Exception:
    ok("Field Reports NO la manda (no se encontró su www/index.html en " + fr + ")", False)
ok("por defecto apagada", 'var porMovimiento: Bool = false' in v)
ok("solo con la cámara nueva, la bandera y en un recorrido con varias partes",
   'var parteSolaActiva: Bool { experienciaNueva && porMovimiento && esRecorrido && seccionesDisponibles.count >= 2 }' in v)
tk = bloque(v, 'fileprivate func tickCamaraNueva')
ok("el cuadro por cuadro mira la parte justo antes de ubicarse", 'revisarParteQueApunta()\n        ubicarseEnElPlano()' in tk)
ok("y la fase de ubicarse y el laboratorio siguen igual", 'ubicarseEnElPlano(); pintarMinimapa(); pintarFaseUbicarse()' in tk and 'if lab.activo { tickLaboratorio(); return }' in tk)
rv = bloque(v, 'fileprivate func revisarParteQueApunta')
ok("el detector exige la bandera y no corre en la maqueta", 'guard parteSolaActiva, maqueta == 0 else { return }' in rv)
ok("con el teléfono muy caliente no muestrea (y más despacio si está caliente)", 'thermalState' in rv and '.critical' in rv and '.serious' in rv)
ok("una muestra cada 0.1 s", '0.1' in rv and 'CACurrentMediaTime()' in rv)
bl = bloque(v, 'fileprivate func bloqueoDeParte')
for x in ['medidaEnCurso', 'selectedMaterial', 'stage', 'tarjetaVisible', 'panelForzado', 'cancelarPendiente', 'resumenPendiente', 'enPausa', 'presentedViewController', 'isSpeaking', 'isTracking', 'roomName.isEmpty']:
    ok("LA REGLA MADRE: nada cambia con " + x, x in bl)
mu = bloque(v, 'fileprivate func muestraDeLaCamara')
ok("hacia dónde apunta sale de la columna 2 (nunca eulerAngles)", '-simd_make_float3(t.columns.2)' in mu and '.eulerAngles' not in mu + rv)
ok("un rayo al plano que ya existe, y el estimado a lo mucho cada 0.2 s", '.existingPlaneGeometry' in mu and '.estimatedPlane' in mu and 'n.ultimoEstimado >= 0.2' in mu)
ok("la clase del plano con switch (no con ==)", 'switch a.classification' in bloque(v, 'fileprivate static func claseDelPlano'))
ok("las superficies solo se guardan con la cámara nueva, la bandera y sin maqueta", 'guard experienciaNueva, porMovimiento, maqueta == 0 else { return }' in bloque(v, 'fileprivate func anotarSuperficies'))
ok("el guard de anotarPlanosVistos no se tocó", 'guard experienciaNueva, !planoPorCuarto.isEmpty else { return }' in bloque(v, 'fileprivate func anotarPlanosVistos'))
ok("ARKit las avisa (al agregar y al cambiar) y se borran al quitarse",
   '{ anotarPlanosVistos(anchors); anotarSuperficies(anchors) }' in v and 'nueva.horizontales[a.identifier] = nil; nueva.verticales[a.identifier] = nil' in v)
# ---- la ubicación firme ----
ub = bloque(v, 'fileprivate func ubicarseEnElPlano')
ok("firme al ubicarse en la fase (3 seguidas)", 'n.ubicadoDesde = Date(); n.firme = true; n.ultimaConfirmacion = Date()' in ub)
ok("sin acomodo no hay firme", 'if n.acomodo == nil { n.firme = false }' in ub)
ok("fuera de la fase: 3 respuestas seguras seguidas en el mismo lugar; una dudosa la quita", 'n.confirmacionesFuera >= 3 { n.firme = true' in ub and 'n.firme = false; n.confirmacionesFuera = 0; n.candidatoFuera = nil' in ub)
ok("ya ubicado, cada respuesta aceptada confirma", 'n.ultimaConfirmacion = Date()' in ub)
ok("y lo que ya se probaba sigue igual", 'if ac.seguro || !(n.acomodo?.seguro ?? false)' in ub and 'n.coincidencias >= 3 && n.ubicadoDesde == nil' in ub)
ok("un corte del rastreo quita lo firme", 'nueva.firme = false; nueva.confirmacionesFuera = 0' in bloque(v, 'func sessionWasInterrupted'))
ok("el plano que manda la página es de un nivel", 'nueva.nivelDelPlano = planoPorCuarto.isEmpty ? nil : nivelActual' in bloque(v, 'fileprivate func armarCamaraNueva'))
# ---- qué pared es ----
cm = bloque(v, 'fileprivate func claseDeLaMedida')
ok("qué pared es exige estar ubicado (seguro, firme, este nivel) y el plano juntado (2 cuartos o más)", 'ubicacionBase()' in cm and 'cuartosDelMarco(' in cm and '>= 2' in cm)
ok("'de adentro' exige además la ubicación firme del momento", 'firme: ubicacionFirme()' in cm)
ok("un garage o un porche del otro lado no cuenta como cuarto", '"garage"' in v and '"porch"' in v and 'esNoHabitable' in cm)
ok("en la maqueta nunca dice nada", 'guard maqueta == 0' in cm)
ubb = bloque(v, 'fileprivate func ubicacionBase')
ok("ubicado = seguro + firme + este nivel + el plano de este nivel", all(x in ubb for x in ['n.acomodo?.seguro == true', 'n.firme', 'n.acomodoNivel == nivelActual', 'n.nivelDelPlano']))
uf = bloque(v, 'fileprivate func ubicacionFirme')
ok("firme = confirmado hace 20 s o menos, sin cortes a media medida, y parado en ese cuarto", '<= 20' in uf and 'rastreoMaloEnMedida' in uf and 'cuartoDondeEsta()' in uf)
# ---- todavía no hace nada en la pantalla ----
nuevo = v[v.index('// MARK: - ============ LA PARTE SALE DEL MOVIMIENTO (16 oct 2026)'):v.index('// MARK: - ============ MEDIR PRIMERO, EL MATERIAL AL FINAL')]
for x in ['cambiarSeccion(', 'elegirParteNueva(', 'includeCompanion', '.companion =', 'items.append', 'say(', 'preguntar(', 'sceneDepth', 'meshWithClassification', 'systemGreen']:
    ok("el detector no usa " + x, x not in nuevo)
ok("nada de sceneDepth ni de la malla con clases en la cámara", 'meshWithClassification' not in v)
ok("siguen siendo 5 caminos a cambiarSeccion", len(re.findall(r'cambiarSeccion\((sec|clave)\)', v)) == 5)
ok("nadie le pone el compañero a lo ya guardado", re.search(r'items\[[^\]]+\]\.companion\s*=', v) is None)
prendidas = sorted(re.findall(r'includeCompanion = ([^\n;]+)', v))
# Los 17 de antes y UNO nuevo: medir primero guarda con el compañero que salió de sus respuestas del nivel (guardarMedir).
ok("los sitios que prenden/apagan la insulación: los 17 de antes + el de medir primero", prendidas == sorted(['false'] * 10 + ['(orden == .ponerCompanero)', '(ultima.companion != nil)', '!niega', 'true', 'true', 'true', 'comp', 'g.companero != nil']))
ok("las preguntas de voz siguen como estaban; los paneles, más el de medir primero", 'fileprivate enum PanelCamara: Equatable { case nivel, cuarto, parte, material, voz, sigue, medir }' in v and 'case masOtraSeccion  // "¿cambiamos de sección, o pasamos a otro cuarto?"\n    }' in v)
ok("la voz al entrar a un cuarto sigue igual", 'Apunte el teléfono a lo que va a medir' not in v)
ok("'(p == .sigue ? 0.7 : 0.6)' sigue igual", 'view.bounds.height * (p == .sigue ? 0.7 : 0.6)' in v)
# ---- las dos apps ----
try:
    same = all(rd(fr + '/ios/App/App/' + x) == rd(raiz + '/ios/App/App/' + x) for x in ['ARMeasureViewController.swift', 'ARMeasurePlugin.swift'])
except Exception:
    same = False
ok("el Swift es idéntico en las dos apps", same)
print("\n  estructura: %d pasan, %d fallan" % (p, f))
sys.exit(1 if f else 0)
PYEOF
xcrun swiftc -O -o "${OUT%.swift}" "$OUT" 2>&1 | grep -E "error" | head -5 || true
"${OUT%.swift}" || E=1
exit $E
