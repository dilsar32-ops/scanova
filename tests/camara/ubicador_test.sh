#!/bin/bash
# UBICARSE DENTRO DEL PLANO (15 oct 2026): corre el UbicadorEnPlano REAL (sacado de ARMeasureViewController.swift)
# contra cuartos de ejemplo y contra los cuartos de planos REALES (tests/fixtures): lo que vería el LiDAR se arma
# girando y moviendo las paredes del plano, con ruido.
# Uso: bash tests/ubicador_test.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
# Corre desde las pruebas de Field Reports (tests/) o desde el repo de Scanova (tests/camara/, con los planos reales de FR).
if [ -f "$DIR/../ios/App/App/ARMeasureViewController.swift" ]; then SRC="$DIR/../ios/App/App/ARMeasureViewController.swift"; else SRC="$DIR/../../ios/App/App/ARMeasureViewController.swift"; fi
FIX="${FIXTURES:-$DIR/fixtures}"; [ -f "$FIX/real_plan.json" ] || FIX="${FR_DIR:-/Users/amilcargonzalez/Downloads/field-report-ios-app}/tests/fixtures"
OUT="$(mktemp -t ubicador).swift"
python3 - "$SRC" "$OUT" "$FIX" <<'PYEOF'
import io, sys, json, os
s = io.open(sys.argv[1], encoding='utf-8').read()
i = s.index('struct UbicadorEnPlano {'); j = s.index('{', i); d = 0; k = j
while True:
    c = s[k]
    if c == '{': d += 1
    elif c == '}':
        d -= 1
        if d == 0: break
    k += 1
ubicador = s[i:k+1]

# Los cuartos de los planos reales, como literales de Swift (paredes alternadas afuera/adentro: lo que se prueba es
# el acomodo, no la clasificación).
reales = []
plantas = {}
for nombre in ['real_plan.json', 'harold_plano.json', 'hamilton_plano.json']:
    try: dd = json.load(io.open(os.path.join(sys.argv[3], nombre), encoding='utf-8'))
    except Exception: continue
    dd = dd.get('data', dd)
    for r in dd.get('rooms', []) if isinstance(dd, dict) else []:
        ws = [w for w in r.get('walls', []) if w.get('start') and w.get('end') and not w.get('_ajena')]
        if len(ws) < 4: continue
        sw = ', '.join('U.ParedPlano(seg: seg(%.3f, %.3f, %.3f, %.3f), exterior: %s)' % (w['start']['x'], w['start']['y'], w['end']['x'], w['end']['y'], 'true' if n % 2 == 0 else 'false') for n, w in enumerate(ws))
        se = ', '.join('U.SenaPlano(p: SIMD2(%.3f, %.3f), esVentana: %s)' % (x['position']['x'], x['position']['y'], 'true' if kk == 'windows' else 'false') for kk in ['windows', 'doors'] for x in r.get(kk, []) if x.get('position'))
        etiqueta = (nombre.split('.')[0] + ' ' + str(r.get('roomName') or r.get('voiceName') or 'cuarto')).replace('"', '')
        reales.append('("%s", [%s], [%s])' % (etiqueta, sw, se))
        cx = sum(w['start']['x'] + w['end']['x'] for w in ws) / (2 * len(ws)); cy = sum(w['start']['y'] + w['end']['y'] for w in ws) / (2 * len(ws))
        plantas.setdefault(nombre, []).append('("%s", SIMD2(%.3f, %.3f), [%s])' % (etiqueta, cx, cy, sw))
REALES = '[' + ', '.join(reales) + ']'
PLANTAS = '[' + ', '.join('[' + ', '.join(v) + ']' for v in plantas.values()) + ']'

prueba = r'''
typealias U = UbicadorEnPlano
var pasan = 0, fallan = 0
func ok(_ l: String, _ c: Bool, _ d: String = "") { if c { pasan += 1; print("  ok  " + l) } else { fallan += 1; print("  FALLA " + l + " " + d) } }
func seg(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> U.Segmento { U.Segmento(a: SIMD2(ax, ay), b: SIMD2(bx, by)) }
// Un cuarto de 20 x 12 pies: sur y oeste de afuera, norte y este de adentro. Ventana en el sur, puerta en el este.
let cuarto: [U.ParedPlano] = [
    U.ParedPlano(seg: seg(0, 0, 20, 0), exterior: true),
    U.ParedPlano(seg: seg(20, 0, 20, 12), exterior: false),
    U.ParedPlano(seg: seg(20, 12, 0, 12), exterior: false),
    U.ParedPlano(seg: seg(0, 12, 0, 0), exterior: true)
]
let senas = [U.SenaPlano(p: SIMD2(6, 0), esVentana: true), U.SenaPlano(p: SIMD2(20, 8), esVentana: false)]
// La "verdad": de lo que ve la cámara al plano es girar 37 grados y mover (5, -3).
let giroReal = 37.0 * Double.pi / 180, movReal = SIMD2(5.0, -3.0)
func aCamara(_ p: SIMD2<Double>) -> SIMD2<Double> { let q = p - movReal; let c = cos(-giroReal), s = sin(-giroReal); return SIMD2(c*q.x - s*q.y, s*q.x + c*q.y) }
var ruido: UInt64 = 12345
func r(_ m: Double) -> Double { ruido = ruido &* 6364136223846793005 &+ 1442695040888963407; return (Double(ruido >> 33) / Double(1 << 31) - 0.5) * 2 * m }
func visto(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ c: U.Clase = .pared) -> U.Visto {
    U.Visto(seg: U.Segmento(a: aCamara(SIMD2(ax + r(0.15), ay + r(0.15))), b: aCamara(SIMD2(bx + r(0.15), by + r(0.15)))), clase: c)
}
let camara = aCamara(SIMD2(10, 6))
func error(_ ac: U.Acomodo) -> Double { simd_length(ac.aplicar(aCamara(SIMD2(3, 3))) - SIMD2(3, 3)) }

var vistos = [visto(2, 0, 14, 0), visto(0, 2, 0, 9), visto(4.8, 0, 7.2, 0, .ventana)]
if let ac = U.ubicar(paredes: cuarto, senas: senas, vistos: vistos, camara: camara) {
    ok("con dos paredes y la ventana se ubica seguro", ac.seguro, "puntaje \(ac.puntaje) vs \(ac.segundo)")
    ok("y en el lugar correcto (menos de 4 pulgadas de error)", error(ac) < 0.35, "error \(error(ac))")
} else { ok("con dos paredes y la ventana se ubica", false) }

vistos = [visto(2, 0, 14, 0), visto(0, 2, 0, 9)]
let ambiguo = U.ubicar(paredes: cuarto, senas: [], vistos: vistos, camara: camara)
ok("sin ventana ni puerta, un rectángulo es simétrico: NO se dice ubicado", ambiguo == nil || ambiguo!.seguro == false)

ok("con una sola pared vista todavía no se ubica", U.ubicar(paredes: cuarto, senas: senas, vistos: [visto(2, 0, 14, 0)], camara: camara) == nil)

vistos = [visto(3, 0, 16, 0), visto(20, 1, 20, 6), visto(20, 6.8, 20, 9.2, .puerta)]
if let ac = U.ubicar(paredes: cuarto, senas: senas, vistos: vistos, camara: camara) {
    ok("con la puerta también se ubica seguro", ac.seguro, "puntaje \(ac.puntaje) vs \(ac.segundo)")
    ok("y en el lugar correcto", error(ac) < 0.35, "error \(error(ac))")
} else { ok("con la puerta se ubica", false) }

vistos = [visto(2, 0, 14, 0), visto(0, 2, 0, 9), visto(4.8, 0, 7.2, 0, .ventana)]
if let ac = U.ubicar(paredes: cuarto, senas: senas, vistos: vistos, camara: camara) {
    ok("un corte parcial en la pared de AFUERA dice afuera", U.paredMedida(ac, puntos: [aCamara(SIMD2(0.1, 3)), aCamara(SIMD2(0.1, 8))], paredes: cuarto) == true)
    ok("un corte parcial en la pared de ADENTRO dice adentro", U.paredMedida(ac, puntos: [aCamara(SIMD2(5, 11.9)), aCamara(SIMD2(13, 11.9))], paredes: cuarto) == false)
    ok("un corte que dobla la esquina entre dos de afuera dice afuera", U.paredMedida(ac, puntos: [aCamara(SIMD2(0.1, 6)), aCamara(SIMD2(0.1, 0.1)), aCamara(SIMD2(8, 0.1))], paredes: cuarto) == true)
    ok("un corte que pasa de una de adentro a una de afuera NO adivina", U.paredMedida(ac, puntos: [aCamara(SIMD2(19.9, 6)), aCamara(SIMD2(19.9, 0.1)), aCamara(SIMD2(10, 0.1))], paredes: cuarto) == nil)
} else { ok("ubicar para el corte", false) }

vistos = [visto(2, 0, 14, 0), visto(0, 2, 0, 9), visto(4.8, 0, 7.2, 0, .ventana), visto(9, 5, 12, 5)]
if let ac = U.ubicar(paredes: cuarto, senas: senas, vistos: vistos, camara: camara) {
    ok("con un mueble que parece pared, sigue en el lugar correcto", error(ac) < 0.35, "error \(error(ac))")
} else { ok("con un mueble", false) }

vistos = [visto(2, 0, 14, 0), visto(0, 2, 0, 9), visto(4.8, 0, 7.2, 0, .ventana)]
let fuera = U.ubicar(paredes: cuarto, senas: senas, vistos: vistos, camara: aCamara(SIMD2(40, 40)))
ok("si el teléfono no cabe dentro del cuarto escogido, no se ubica", fuera == nil || fuera!.seguro == false)

// Los cuartos de PLANOS REALES: un pedazo de las dos paredes más largas que se cruzan, más la ventana o puerta.
let reales: [(String, [U.ParedPlano], [U.SenaPlano])] = ''' + REALES + r'''
var bien = 0, seguros = 0, mal = 0
for (nombre, paredes, ss) in reales {
    let largas = paredes.filter { $0.seg.largo >= 5 }.sorted { $0.seg.largo > $1.seg.largo }
    guard let p0 = largas.first, let p1 = largas.first(where: { U.difLinea($0.seg.angulo, p0.seg.angulo) > 1.2 }) else { continue }
    func pedazo(_ w: U.ParedPlano) -> U.Visto {
        let a = w.seg.a + (w.seg.b - w.seg.a) * 0.15, b = w.seg.a + (w.seg.b - w.seg.a) * 0.8
        return U.Visto(seg: U.Segmento(a: aCamara(a), b: aCamara(b)), clase: .pared)
    }
    var vs = [pedazo(p0), pedazo(p1)]
    if let sn = ss.first { let dd = SIMD2(1.0, 0.0); vs.append(U.Visto(seg: U.Segmento(a: aCamara(sn.p - dd), b: aCamara(sn.p + dd)), clase: sn.esVentana ? .ventana : .puerta)) }
    let pts = paredes.flatMap { [$0.seg.a, $0.seg.b] }
    let centro = SIMD2(pts.map { $0.x }.reduce(0, +) / Double(pts.count), pts.map { $0.y }.reduce(0, +) / Double(pts.count))
    guard let ac = U.ubicar(paredes: paredes, senas: ss, vistos: vs, camara: aCamara(centro)) else { continue }
    let e = simd_length(ac.aplicar(aCamara(centro)) - centro)
    if ac.seguro { seguros += 1; if e < 0.5 { bien += 1 } else { mal += 1; print("    seguro pero mal en " + nombre + " error \(e)") } }
}
print("    cuartos reales: \(reales.count), seguros \(seguros), bien \(bien), mal \(mal)")
ok("en planos reales, cuando dice 'seguro' siempre está en el lugar correcto", mal == 0)
ok("y se ubica en la mayoría de los cuartos reales con dos paredes y una seña", seguros * 2 >= reales.count, "\(seguros) de \(reales.count)")

// EN QUÉ CUARTO ESTÁ (15 oct, su pedido: al cambiar de cuarto ya debe saber dónde está). En cada planta real, el
// centro de cada cuarto tiene que caer en ESE cuarto (el más chico que lo rodea), y nunca en otro.
let plantas: [[(String, SIMD2<Double>, [U.ParedPlano])]] = ''' + PLANTAS + r'''
var aciertos = 0, errados = 0, sinSaber = 0
for planta in plantas {
    for (nombre, centro, _) in planta {
        let dentro = planta.filter { U.rodea(centro, $0.2) }
        func area(_ w: [U.ParedPlano]) -> Double {
            let xs = w.flatMap { [$0.seg.a.x, $0.seg.b.x] }, ys = w.flatMap { [$0.seg.a.y, $0.seg.b.y] }
            return (xs.max()! - xs.min()!) * (ys.max()! - ys.min()!)
        }
        guard let elegido = dentro.min(by: { area($0.2) < area($1.2) }) else { sinSaber += 1; continue }
        if elegido.0 == nombre { aciertos += 1 } else { errados += 1; print("    \(nombre) salió en \(elegido.0)") }
    }
}
print("    en qué cuarto está: bien \(aciertos), mal \(errados), sin saber \(sinSaber)")
ok("en qué cuarto está: nunca dice otro cuarto", errados == 0)
ok("y lo sabe en la mayoría de los cuartos reales", aciertos * 3 >= (aciertos + sinSaber) * 2, "\(aciertos) de \(aciertos + sinSaber)")
ok("un punto lejos de todo no está en ningún cuarto", !U.rodea(SIMD2(500, 500), cuarto))
ok("el centro del cuarto de ejemplo sí está en él", U.rodea(SIMD2(10, 6), cuarto))

// AFINAR CONTRA LA PLANTA ENTERA (15 oct): ya ubicado, la cámara compara lo que ve con TODOS los cuartos del nivel.
// Con paredes vistas en dos cuartos, cuando dice "seguro" tiene que estar en el lugar correcto (nunca seguro y mal).
var plantaBien = 0, plantaMal = 0
for planta in plantas where planta.count >= 2 {
    let todas = planta.flatMap { $0.2 }
    for i in 0..<planta.count {
        let a = planta[i].2, b = planta[(i + 1) % planta.count].2
        let la = a.filter { $0.seg.largo >= 5 }.sorted { $0.seg.largo > $1.seg.largo }
        guard let p0 = la.first, let p1 = la.first(where: { U.difLinea($0.seg.angulo, p0.seg.angulo) > 1.2 }),
              let q0 = b.filter({ $0.seg.largo >= 4 }).max(by: { $0.seg.largo < $1.seg.largo }) else { continue }
        func pedazo(_ w: U.ParedPlano) -> U.Visto {
            let x = w.seg.a + (w.seg.b - w.seg.a) * 0.15, y = w.seg.a + (w.seg.b - w.seg.a) * 0.8
            return U.Visto(seg: U.Segmento(a: aCamara(x), b: aCamara(y)), clase: .pared)
        }
        let centro = planta[i].1
        guard let ac = U.ubicar(paredes: todas, senas: [], vistos: [pedazo(p0), pedazo(p1), pedazo(q0)], camara: aCamara(centro)) else { continue }
        if ac.seguro { if simd_length(ac.aplicar(aCamara(centro)) - centro) < 0.5 { plantaBien += 1 } else { plantaMal += 1 } }
    }
}
print("    contra la planta entera: seguros bien \(plantaBien), seguros mal \(plantaMal)")
ok("afinando contra la planta entera, nunca 'seguro' en el lugar equivocado", plantaMal == 0)

// AFINAR CON TODAS LAS PAREDES (15 oct, su prueba: "me sacaba hasta afuera"). Paredes vistas con ruido, como las del
// LiDAR (cada una corrida hasta 5 in y torcida hasta 1°): ubicar con dos deja el error de esas dos; afinar lo baja.
var sumaAntes = 0.0, sumaDespues = 0.0, casosAfinar = 0, empeora = 0
for planta in plantas {
    for (_, centro, paredes) in planta where paredes.count >= 4 {
        var vs: [U.Visto] = []
        for w in paredes where w.seg.largo >= 3 {
            let n = SIMD2(-sin(w.seg.angulo), cos(w.seg.angulo))
            let off = n * r(0.4), giro = r(0.017)
            let a = w.seg.a + (w.seg.b - w.seg.a) * 0.15 + off, b = w.seg.a + (w.seg.b - w.seg.a) * 0.85 + off
            let m = (a + b) / 2, c = cos(giro), s = sin(giro)
            func tw(_ p: SIMD2<Double>) -> SIMD2<Double> { let q = p - m; return m + SIMD2(c * q.x - s * q.y, s * q.x + c * q.y) }
            vs.append(U.Visto(seg: U.Segmento(a: aCamara(tw(a)), b: aCamara(tw(b))), clase: .pared))
        }
        guard let ac = U.ubicar(paredes: paredes, senas: [], vistos: vs, camara: aCamara(centro)), ac.seguro else { continue }
        let e0 = simd_length(ac.aplicar(aCamara(centro)) - centro)
        let fino = U.afinar(ac, paredes: paredes, vistos: vs)
        let e1 = simd_length(fino.aplicar(aCamara(centro)) - centro)
        sumaAntes += e0; sumaDespues += e1; casosAfinar += 1
        if e1 > e0 + 0.05 { empeora += 1 }
    }
}
print(String(format: "    afinar: %d cuartos, error promedio antes %.2f ft, después %.2f ft", casosAfinar, casosAfinar > 0 ? sumaAntes / Double(casosAfinar) : 0, casosAfinar > 0 ? sumaDespues / Double(casosAfinar) : 0))
ok("afinar con todas las paredes baja el error promedio", casosAfinar > 0 && sumaDespues < sumaAntes)
ok("afinar nunca empeora una ubicación", empeora == 0)
// DENTRO DE LA CASA: el centro de cada cuarto sí; parado en la pared (una puerta) sí; 6 ft afuera de la casa no.
var dentroBien = 0, dentroTotal = 0, afueraMal = 0
for planta in plantas {
    let cuartos = planta.map { $0.2 }
    for (_, centro, _) in planta { dentroTotal += 1; if U.dentroDeLaCasa(centro, cuartos: cuartos) { dentroBien += 1 } }
    let pts = cuartos.flatMap { $0.flatMap { [$0.seg.a, $0.seg.b] } }
    let minX = pts.map { $0.x }.min()!, maxY = pts.map { $0.y }.max()!
    if U.dentroDeLaCasa(SIMD2(minX - 6, maxY + 6), cuartos: cuartos) { afueraMal += 1 }
}
ok("dentro de la casa: el centro de TODOS los cuartos (\(dentroBien) de \(dentroTotal))", dentroBien == dentroTotal)
ok("6 ft afuera de la casa NO cuenta como ubicado", afueraMal == 0)
ok("parado en la pared (una puerta) sí cuenta", U.dentroDeLaCasa(SIMD2(20, 6), cuartos: [cuarto]))

// ---- INSULACIÓN POR PARED (16 oct): ¿el PEDAZO medido da para afuera o queda entre dos cuartos? ----
// En pies: Living (0,0)-(20,12) [el cuarto de arriba: sur y oeste de afuera], Kitchen (20,0)-(34,12), y una variante
// con la Kitchen de (20,0)-(34,6).
let quieto = U.Acomodo(giro: 0, mov: .zero, puntaje: 20, segundo: 4, seguro: true)
func caja(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [U.ParedPlano] {
    [U.ParedPlano(seg: seg(x0, y0, x1, y0), exterior: true), U.ParedPlano(seg: seg(x1, y0, x1, y1), exterior: true),
     U.ParedPlano(seg: seg(x1, y1, x0, y1), exterior: true), U.ParedPlano(seg: seg(x0, y1, x0, y0), exterior: true)]
}
func centroDe(_ ps: [U.ParedPlano]) -> SIMD2<Double> { let pts = ps.flatMap { [$0.seg.a, $0.seg.b] }; return pts.reduce(SIMD2<Double>(0, 0), +) / Double(pts.count) }
func otrasDe(_ ps: [U.ParedPlano]) -> [(seg: U.Segmento, centro: SIMD2<Double>)] { let c = centroDe(ps); return ps.map { (seg: $0.seg, centro: c) } }
let living = cuarto, kitchen = caja(20, 0, 34, 12), kitchenChica = caja(20, 0, 34, 6)
let pm1 = U.paredesMedidas(quieto, puntos: [SIMD2(2, 0.3), SIMD2(10, 0.3)], paredes: living)
ok("paredesMedidas: un corte en y = 0.3 de x 2 a 10 cae en la pared sur, de 2 a 10",
   pm1 != nil && pm1!.count == 1 && pm1![0].indice == 0 && abs(pm1![0].t0 - 2) < 0.01 && abs(pm1![0].t1 - 10) < 0.01)
ok("paredesMedidas: a 1.2 ft de la pared no es de esa pared (nil)", U.paredesMedidas(quieto, puntos: [SIMD2(2, 1.2), SIMD2(10, 1.2)], paredes: living) == nil)
ok("paredesMedidas: a 15° de la pared no es de esa pared (nil)", U.paredesMedidas(quieto, puntos: [SIMD2(6, -0.45), SIMD2(10, 0.62)], paredes: living) == nil)
let pm2 = U.paredesMedidas(quieto, puntos: [SIMD2(12, 0.3), SIMD2(19.7, 0.3), SIMD2(19.7, 6)], paredes: living)
ok("paredesMedidas: un corte que dobla de la sur a la este da 2 pedazos",
   pm2 != nil && pm2!.count == 2 && pm2![0].indice == 0 && pm2![1].indice == 1 && abs(pm2![1].t0 - 0.3) < 0.01 && abs(pm2![1].t1 - 6) < 0.01)
let girado = U.Acomodo(giro: .pi / 2, mov: SIMD2(20, 0), puntaje: 20, segundo: 4, seguro: true)
let pm3 = U.paredesMedidas(girado, puntos: [SIMD2(2, 19.7), SIMD2(10, 19.7)], paredes: living)
ok("paredesMedidas usa el acomodo (girado 90° y movido: cae en la oeste, de 2 a 10)", pm3 != nil && pm3![0].indice == 3 && abs(pm3![0].t0 - 2) < 0.01 && abs(pm3![0].t1 - 10) < 0.01)
let este = living[1].seg, sur = living[0].seg, propio = centroDe(living)
ok("cobertura: la pared este con la Kitchen entera del otro lado: 1.0", abs(U.cobertura(pared: este, t0: 0, t1: 12, propio: propio, otras: otrasDe(kitchen)) - 1) < 0.01)
ok("cobertura: con la Kitchen de 0-6, el corte 1-5: 1.0", abs(U.cobertura(pared: este, t0: 1, t1: 5, propio: propio, otras: otrasDe(kitchenChica)) - 1) < 0.01)
ok("cobertura: con la Kitchen de 0-6, el corte 7-11: 0.0", U.cobertura(pared: este, t0: 7, t1: 11, propio: propio, otras: otrasDe(kitchenChica)) < 0.01)
ok("cobertura: con la Kitchen de 0-6, el corte 4-10: 0.33", abs(U.cobertura(pared: este, t0: 4, t1: 10, propio: propio, otras: otrasDe(kitchenChica)) - 1.0 / 3) < 0.01)
ok("cobertura: la pared sur (nadie del otro lado): 0", U.cobertura(pared: sur, t0: 0, t1: 20, propio: propio, otras: otrasDe(kitchen)) < 0.01)
ok("cobertura: un closet del MISMO lado no tapa: 0", U.cobertura(pared: este, t0: 0, t1: 4, propio: propio, otras: otrasDe(caja(16, 0, 20, 4))) < 0.01)
ok("cobertura: una pared que no es paralela no tapa: 0", U.cobertura(pared: este, t0: 0, t1: 12, propio: propio, otras: [(seg: seg(20, 6, 30, 6), centro: SIMD2(25, 3))]) < 0.01)
ok("cobertura: dos cuartos que se enciman no cuentan dos veces", abs(U.cobertura(pared: este, t0: 0, t1: 12, propio: propio, otras: otrasDe(kitchenChica) + otrasDe(caja(20, 3, 30, 12))) - 1) < 0.01)
ok("claseDePared: de afuera con cobertura 0: afuera", U.claseDePared(exteriores: [true], coberturaTodas: [0], coberturaHabitables: [0], firme: true, juntado: true, contradice: false) == true)
ok("claseDePared: tapada al 100% y firme: adentro", U.claseDePared(exteriores: [false], coberturaTodas: [1], coberturaHabitables: [1], firme: true, juntado: true, contradice: false) == false)
ok("claseDePared: tapada pero SIN ubicación firme: no se sabe", U.claseDePared(exteriores: [false], coberturaTodas: [1], coberturaHabitables: [1], firme: false, juntado: true, contradice: false) == nil)
ok("claseDePared: tapada pero el plano lo contradice: no se sabe", U.claseDePared(exteriores: [false], coberturaTodas: [1], coberturaHabitables: [1], firme: true, juntado: true, contradice: true) == nil)
ok("claseDePared: plano sin juntar: no se sabe", U.claseDePared(exteriores: [true], coberturaTodas: [0], coberturaHabitables: [0], firme: true, juntado: false, contradice: false) == nil)
ok("claseDePared: un corte en una de afuera y otra de adentro: no se sabe", U.claseDePared(exteriores: [true, false], coberturaTodas: [0, 1], coberturaHabitables: [0, 1], firme: true, juntado: true, contradice: false) == nil)
ok("claseDePared: el garage la tapa (todas 1.0, habitables 0): no se sabe", U.claseDePared(exteriores: [false], coberturaTodas: [1], coberturaHabitables: [0], firme: true, juntado: true, contradice: false) == nil)
ok("claseDePared: tapada a medias (0.33): no se sabe", U.claseDePared(exteriores: [false], coberturaTodas: [0.33], coberturaHabitables: [0.33], firme: true, juntado: true, contradice: false) == nil)
ok("paredMedida da lo mismo que antes (sur afuera, este adentro, la esquina sin saber)",
   U.paredMedida(quieto, puntos: [SIMD2(2, 0.3), SIMD2(10, 0.3)], paredes: living) == true
   && U.paredMedida(quieto, puntos: [SIMD2(19.7, 2), SIMD2(19.7, 9)], paredes: living) == false
   && U.paredMedida(quieto, puntos: [SIMD2(12, 0.3), SIMD2(19.7, 0.3), SIMD2(19.7, 6)], paredes: living) == nil)

print("\n  \(pasan) pasan, \(fallan) fallan")
exit(fallan == 0 ? 0 : 1)
'''
io.open(sys.argv[2], 'w', encoding='utf-8').write('import Foundation\nimport simd\n' + ubicador + '\n' + prueba)
PYEOF
xcrun swiftc -O -o "${OUT%.swift}" "$OUT" 2>&1 | grep -E "error" | head -5 || true
"${OUT%.swift}"
