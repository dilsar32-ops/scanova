#!/bin/bash
# EL LECTOR DE LA PARTE (16 oct 2026, su segunda prueba: "el láser ya sabe qué es pared y qué es techo... tiene que ser más rápido").
# Corre el LectorDeParte REAL (sacado de ARMeasureViewController.swift, junto con UbicadorEnPlano) con swiftc:
#  - el rayo contra el plano: en un cuarto de 12 x 12 ft con el teléfono en medio, abajo piso, en medio pared (y CUÁL), arriba
#    techo, y las uniones neutras; por una puerta no vota;
#  - los votos: el plano confirmado por el láser (P), la clase de ARKit (A), el plano estimado (E) y la inclinación (I);
#  - la puerta de cambio: pared -> techo en 0.4 s, sin parpadear, el piso con el teléfono quieto pide más;
#  - los casos de su bitácora 388DF319 (techo a 28-30° que salía "esquina", piso a -35..-50° que salía nada).
# Uso:  bash tests/camara/lector_de_parte_test.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$DIR/../ios/App/App/ARMeasureViewController.swift" ]; then RAIZ="$(cd "$DIR/.." && pwd)"; else RAIZ="$(cd "$DIR/../.." && pwd)"; fi
OUT="$(mktemp -t lector).swift"
python3 - "$RAIZ" "$OUT" <<'PYEOF'
import io, sys
raiz, out = sys.argv[1:3]
s = io.open(raiz + '/ios/App/App/ARMeasureViewController.swift', encoding='utf-8').read()
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
ubicador = bloque(s, 'struct UbicadorEnPlano {')
lector = bloque(s, 'struct LectorDeParte {') + '\n' + bloque(s, 'struct ReglaDeSoltar {')
prueba = r'''
typealias L = LectorDeParte
typealias U = UbicadorEnPlano
var pasan = 0, fallan = 0
func ok(_ l: String, _ c: Bool, _ d: String = "") { if c { pasan += 1; print("  ok  " + l) } else { fallan += 1; print("  FALLA " + l + " " + d) } }
func seg(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> U.Segmento { U.Segmento(a: SIMD2(ax, ay), b: SIMD2(bx, by)) }
// El cuarto: 12 x 12 ft, alto 8.1 ft. Pared 0 = sur (y=0), 1 = este (x=12), 2 = norte (y=12), 3 = oeste (x=0).
let cuarto = [U.ParedPlano(seg: seg(0, 0, 12, 0), exterior: true, alto: 8.1), U.ParedPlano(seg: seg(12, 0, 12, 12), exterior: true, alto: 8.1),
              U.ParedPlano(seg: seg(12, 12, 0, 12), exterior: true, alto: 8.1), U.ParedPlano(seg: seg(0, 12, 0, 0), exterior: true, alto: 8.1)]
let indices: [Int?] = [0, 1, 2, 3]
let centro = SIMD2<Double>(6, 6), h = 4.6          // el teléfono a 1.40 m
func rayo(_ grados: Double, dir: SIMD2<Double> = SIMD2(1, 0), o: SIMD2<Double> = centro, puertas: [U.SenaPlano] = [], paredes: [U.ParedPlano] = cuarto, idx: [Int?] = indices) -> L.Rayo? {
    L.rayoEnPlano(o: o, dir: dir, tanP: tan(grados * .pi / 180), h: h, paredes: paredes, indiceEnCuarto: idx, puertas: puertas, altoRespaldo: 8)
}
// ---- EL RAYO CONTRA EL PLANO ----
// Mirando al este (pared 1 a 6 ft): la unión con el piso a atan(4.6/6) = -37.5°, con el techo a atan(3.5/6) = +30.3°.
ok("mirando derecho: pared 1", rayo(0)?.parte == .wall && rayo(0)?.pared == 1)
ok("a -20°: pared 1", rayo(-20)?.parte == .wall && rayo(-20)?.pared == 1)
ok("a +20°: pared 1", rayo(20)?.parte == .wall)
ok("a -50°: piso", rayo(-50)?.parte == .floor)
ok("a +40°: techo (antes a 25-40° salía 'esquina' o nada)", rayo(40)?.parte == .ceiling)
ok("a +32°: techo", rayo(32)?.parte == .ceiling)
ok("a -37°: en la unión con el piso, el margen es chico (< 2.5°)", (rayo(-37)?.margen ?? 99) < 2.5)
ok("a +30°: en la unión con el techo, el margen es chico", (rayo(30)?.margen ?? 99) < 2.5)
ok("la distancia a la pared mirando derecho: 6 ft", abs((rayo(0)?.dist ?? 0) - 6) < 0.01)
ok("la distancia al piso a -60°: h / sin(60°)", abs((rayo(-60)?.dist ?? 0) - h / sin(60 * .pi / 180)) < 0.01)
ok("mirando al norte: pared 2", rayo(0, dir: SIMD2(0, 1))?.pared == 2)
ok("mirando al sur: pared 0", rayo(0, dir: SIMD2(0, -1))?.pared == 0)
ok("mirando en diagonal a la esquina NE: pared, pero sin número (puede caer en la de al lado)", rayo(0, dir: SIMD2(1, 1.001))?.parte == .wall && rayo(0, dir: SIMD2(1, 1.001))?.pared == nil)
func dirG(_ g: Double) -> SIMD2<Double> { SIMD2(cos(g * .pi / 180), sin(g * .pi / 180)) }
ok("a 43° (2° de la esquina NE): sin número", rayo(0, dir: dirG(43))?.parte == .wall && rayo(0, dir: dirG(43))?.pared == nil)
ok("a 38° (lejos de la esquina): pared 1", rayo(0, dir: dirG(38))?.pared == 1)
let copia119 = cuarto + [U.ParedPlano(seg: seg(11.9, 0, 11.9, 12), exterior: false, alto: 8.1)]
ok("la misma pared copiada por otro cuarto 0.1 ft adelante (compartida): gana la del cuarto", rayo(0, paredes: copia119, idx: indices + [nil])?.pared == 1)
let copia115 = cuarto + [U.ParedPlano(seg: seg(11.5, 0, 11.5, 12), exterior: false, alto: 8.1)]
ok("otra pared de otro cuarto 0.5 ft adelante: esa manda (sin número)", rayo(0, paredes: copia115, idx: indices + [nil])?.pared == nil)
let puerta = U.SenaPlano(p: SIMD2(12, 6), esVentana: false, ancho: 3, abajo: 0, alto: 6.7)
ok("mirando por una puerta del plano: no vota (porPuerta)", rayo(-10, puertas: [puerta])?.porPuerta == true)
ok("arriba de la puerta (dintel): pared, no puerta", rayo(25, puertas: [puerta])?.porPuerta == false)
let ventana = U.SenaPlano(p: SIMD2(12, 6), esVentana: true, ancho: 3, abajo: 3, alto: 4)
ok("una ventana no es puerta: sigue siendo pared", rayo(0, puertas: [ventana])?.porPuerta == false)
// La pared de otro cuarto (sin índice): es pared, pero sin número.
let otro = [U.ParedPlano(seg: seg(9, 2, 9, 10), exterior: false, alto: 8.1)] + cuarto
ok("una pared de otro cuarto más cerca: pared sin índice", rayo(0, paredes: otro, idx: [nil] + indices)?.pared == nil && rayo(0, paredes: otro, idx: [nil] + indices)?.parte == .wall)
ok("sin altura razonable del teléfono: nada", L.rayoEnPlano(o: centro, dir: SIMD2(1, 0), tanP: 0, h: 0.2, paredes: cuarto, indiceEnCuarto: indices, puertas: [], altoRespaldo: 8) == nil)
ok("pared sin alto en el plano: se usa el alto de respaldo", L.rayoEnPlano(o: centro, dir: SIMD2(1, 0), tanP: tan(40 * .pi / 180), h: h,
   paredes: cuarto.map { var w = $0; w.alto = 0; return w }, indiceEnCuarto: indices, puertas: [], altoRespaldo: 8)?.parte == .ceiling)

// ---- LOS VOTOS ----
func entrada(_ grados: Double, d: Double? = nil, y: Double? = nil, clase: String = "", vertical: Bool? = nil, aParedClasif: Double? = nil,
             rayo r: L.Rayo? = nil, confiable: Bool = false, fuerte: Bool = true, giro: Double = 0) -> L.Entrada {
    L.Entrada(grados: grados, giro: giro, rastreoNormal: true, d: d, golpeY: y, clase: clase, vertical: vertical, tope: nil,
              aParedClasif: aParedClasif, camY: 1.40, pisoY: 0, techoY: 2.47, rayo: r, planoConfiable: confiable, planoFuerte: fuerte)
}
let r0 = rayo(0)!
ok("P: el plano dice pared 1 y el láser mide lo mismo (1.83 m): pared, peso 1, pared 1",
   { let v = L.votar(entrada(0, d: 1.83, y: 1.4, clase: "wall", vertical: true, rayo: r0, confiable: true)); return v.parte == .wall && v.peso == 1 && v.pared == 1 && v.fuente == "P" }())
ok("P: sin golpe del láser, el plano solo: pared con peso 0.5 y SIN número (nunca cuál pared con el plano solo)",
   { let v = L.votar(entrada(0, rayo: r0, confiable: true)); return v.parte == .wall && v.peso == 0.5 && v.pared == nil && v.fuente == "P" }())
ok("P: el láser calza pero el plano todavía no es fuerte: peso 0.8 y sin número",
   { let v = L.votar(entrada(0, d: 1.83, y: 1.4, clase: "wall", vertical: true, rayo: r0, confiable: true, fuerte: false)); return v.parte == .wall && v.peso == 0.8 && v.pared == nil }())
ok("un mueble 1 m antes de la pared (sin clase): no vota",
   L.votar(entrada(0, d: 0.8, y: 1.0, clase: "", vertical: true, rayo: r0, confiable: true)).parte == nil)
ok("el láser y el plano no calzan pero ARKit dice pared: pared por la clase (A), sin número",
   { let v = L.votar(entrada(0, d: 1.2, y: 1.4, clase: "wall", vertical: true, rayo: r0, confiable: true)); return v.parte == .wall && v.fuente == "A" && v.pared == nil }())
ok("P en la unión pared-techo: neutro (esquina)", L.votar(entrada(30, rayo: rayo(30)!, confiable: true)).fuente == "e")
ok("P por una puerta: neutro", L.votar(entrada(-10, rayo: rayo(-10, puertas: [puerta])!, confiable: true)).parte == nil)
ok("sin plano confiable no se usa el rayo", L.votar(entrada(0, rayo: r0, confiable: false)).fuente != "P")
// ---- SU BITÁCORA 388DF319 ----
ok("115.5 s: 29.6° arriba, ARKit dice techo a 30 cm de la pared: TECHO (antes 'esquina' siempre)",
   L.votar(entrada(29.6, d: 2.2, y: 2.47, clase: "ceiling", vertical: false, aParedClasif: 0.3)).parte == .ceiling)
ok("pegado a la pared clasificada (5 cm): sigue siendo la corona (neutro)",
   L.votar(entrada(29.6, d: 2.2, y: 2.47, clase: "ceiling", vertical: false, aParedClasif: 0.05)).fuente == "e")
ok("64.2 s: -35° abajo, ARKit dice piso a 20 cm de la pared: PISO (antes 'esquina')",
   L.votar(entrada(-35.3, d: 2.4, y: 0.0, clase: "floor", vertical: false, aParedClasif: 0.2)).parte == .floor)
ok("82.7 s: -48° abajo, piso sin clase (estimado del láser): PISO (antes nada)",
   L.votar(entrada(-48.5, d: 1.9, y: 0.0, clase: "", vertical: false)).parte == .floor)
ok("8.5 s: -18° a una pared sin clase todavía (estimado): PARED (antes '.')",
   L.votar(entrada(-18, d: 2.0, y: 0.8, clase: "", vertical: true)).parte == .wall)
ok("la cama o la mesa: no vota", L.votar(entrada(-30, d: 1.5, y: 0.5, clase: "table", vertical: false)).parte == nil)
ok("sin golpe y a 50° arriba: techo por la inclinación (peso 0.5)", { let v = L.votar(entrada(50)); return v.parte == .ceiling && v.peso == 0.5 }())
ok("sin golpe y a -30°: no se sabe (neutro)", L.votar(entrada(-30)).parte == nil)
ok("volteando muy rápido: neutro", L.votar(entrada(0, d: 1.83, y: 1.4, clase: "wall", vertical: true, giro: 150)).fuente == "~")

// ---- LA PUERTA DE CAMBIO ----
let A = { (p: L.Parte) in L.Voto(parte: p, peso: 1, pared: nil, fuente: "A") }
let neutro = L.Voto.neutro("e")
var pc = L.PuertaDeCambio()
var cambio = 0.0
for i in 0..<10 { let t = Double(i) * 0.1; if pc.meter(A(.wall), t: t, grados: 0, quieto: false) { cambio = t; break } }
ok("al empezar: pared con 3 votos (0.2 s)", pc.actual == .wall && abs(cambio - 0.2) < 1e-9)
var t = 1.0, alTecho = -1.0
for i in 0..<20 { t = 1.0 + Double(i) * 0.1; if pc.meter(A(.ceiling), t: t, grados: 30, quieto: false) { alTecho = t - 1.0; break } }
ok("de pared a techo: 0.4 s (4 votos), antes 1.2-1.5 s o nunca", pc.actual == .ceiling && abs(alTecho - 0.3) < 1e-9, "\(alTecho)")
var pp = L.PuertaDeCambio(); for i in 0..<5 { _ = pp.meter(A(.wall), t: Double(i) * 0.1, grados: 0, quieto: false) }
var cambios = 0
for i in 0..<40 { let tt = 1.0 + Double(i) * 0.1; if pp.meter(A(i % 2 == 0 ? .ceiling : .wall), t: tt, grados: 0, quieto: false) { cambios += 1 } }
ok("pared/techo alternado (parpadeo): nunca cambia", cambios == 0 && pp.actual == .wall)
var pn = L.PuertaDeCambio(); for i in 0..<5 { _ = pn.meter(A(.wall), t: Double(i) * 0.1, grados: 0, quieto: false) }
_ = pn.meter(A(.ceiling), t: 1.0, grados: 30, quieto: false); _ = pn.meter(neutro, t: 1.1, grados: 30, quieto: false)
_ = pn.meter(A(.ceiling), t: 1.2, grados: 30, quieto: false); _ = pn.meter(neutro, t: 1.3, grados: 30, quieto: false)
_ = pn.meter(A(.ceiling), t: 1.4, grados: 30, quieto: false); let cambio4 = pn.meter(A(.ceiling), t: 1.5, grados: 30, quieto: false)
ok("las esquinas en medio no borran al candidato: techo al 4o voto", cambio4 && pn.actual == .ceiling)
var pq = L.PuertaDeCambio(); for i in 0..<5 { _ = pq.meter(A(.wall), t: Double(i) * 0.1, grados: 0, quieto: false) }
var votosPiso = 0
for i in 0..<30 { votosPiso += 1; if pq.meter(A(.floor), t: 1.0 + Double(i) * 0.1, grados: -50, quieto: true) { break } }
ok("el piso con el teléfono QUIETO (leyendo la pantalla): pide 9 votos", pq.actual == .floor && votosPiso == 9, "\(votosPiso)")
var pg = L.PuertaDeCambio(); for i in 0..<5 { _ = pg.meter(A(.wall), t: Double(i) * 0.1, grados: 0, quieto: false) }
var votosG = 0
for i in 0..<30 { votosG += 1; if pg.meter(A(.floor), t: 1.0 + Double(i) * 0.1, grados: -50, quieto: false) { break } }
ok("el piso apuntando de verdad (volteó el teléfono): 4 votos", pg.actual == .floor && votosG == 4, "\(votosG)")
var pr = L.PuertaDeCambio(); for i in 0..<3 { _ = pr.meter(A(.wall), t: Double(i) * 0.1, grados: 0, quieto: false) }
var rapido = false
for i in 0..<4 { if pr.meter(A(.ceiling), t: 0.3 + Double(i) * 0.05, grados: 30, quieto: false) { rapido = true } }
ok("dos cambios en menos de 0.6 s: no pasa el segundo", !rapido && pr.actual == .wall)
// ---- CUÁL PARED ----
let P = { (i: Int) in L.Voto(parte: .wall, peso: 1, pared: i, fuente: "P") }
var pw = L.PuertaDePared()
var en = -1
for i in 0..<10 { if pw.meter(P(1), t: Double(i) * 0.1) { en = i; break } }
ok("la pared 1 con 5 votos del plano (0.4 s)", pw.actual == 1 && en == 4)
var pw2 = pw; var paso2 = -1
for i in 0..<10 { if pw2.meter(P(2), t: 2.0 + Double(i) * 0.1) { paso2 = i; break } }
ok("a la pared 2: otros 5 votos", pw2.actual == 2 && paso2 == 4)
var pw3 = pw; for i in 0..<10 { _ = pw3.meter(L.Voto(parte: .wall, peso: 1, pared: nil, fuente: "A"), t: 2.0 + Double(i) * 0.1) }
ok("votos sin plano (A) no cambian la pared", pw3.actual == 1)
var pw4 = pw; for i in 0..<10 { _ = pw4.meter(P(i % 2 == 0 ? 2 : 3), t: 2.0 + Double(i) * 0.1) }
ok("2 y 3 alternados (la esquina): no cambia", pw4.actual == 1)
ok("calza: 1.83 m contra 6 ft", L.calza(r0, d: 1.83) && !L.calza(r0, d: 1.3))
// ---- CUÁNDO SE SUELTA LO ESCOGIDO (ReglaDeSoltar, 16 oct) ----
typealias R = ReglaDeSoltar
func corre(aMano: Bool = false, enganchada: Bool = false, sinNada: Bool = true, seccion: String, zona: String?, grados: Double,
           fuerte: Bool = false, giro: Bool, otraPared: Bool = false, hasta: Double, paso: Double = 0.1) -> (suelta: String?, en: Double) {
    var d: Double? = nil, t = 0.0
    while t <= hasta + 1e-9 {
        let r = R.revisar(aMano: aMano, enganchada: enganchada, sinNada: sinNada, seccion: seccion, zona: zona, zonaDisponible: true,
                          grados: grados, fuerte: fuerte, huboGiro: giro, otraPared: otraPared, desde: d, ahora: t)
        if let s = r.suelta { return (s, t) }
        d = r.desde; t += paso
    }
    return (nil, -1)
}
ok("(a) parcial de pared, mira el piso a -55° SIN giro (leyendo la pantalla): nunca se suelta",
   { var d: Double? = nil; for i in 0..<20 { let r = R.revisar(aMano: false, enganchada: true, sinNada: true, seccion: "wall", zona: "floor", zonaDisponible: true, grados: -55, fuerte: false, huboGiro: false, otraPared: false, desde: d, ahora: Double(i) * 0.1); if r.desde != nil || r.suelta != nil { return false }; d = r.desde }; return true }())
ok("(b) lo mismo CON giro: se suelta 've-floor' a los 1.5 s (no a los 1.4)",
   R.revisar(aMano: false, enganchada: true, sinNada: true, seccion: "wall", zona: "floor", zonaDisponible: true, grados: -55, fuerte: false, huboGiro: true, otraPared: false, desde: 0, ahora: 1.4).suelta == nil
   && R.revisar(aMano: false, enganchada: true, sinNada: true, seccion: "wall", zona: "floor", zonaDisponible: true, grados: -55, fuerte: false, huboGiro: true, otraPared: false, desde: 0, ahora: 1.5).suelta == "ve-floor")
ok("(c) Techo a mano, ve pared a +25° (la parte alta de la pared), fuerte: nunca", corre(aMano: true, seccion: "ceiling", zona: "wall", grados: 25, fuerte: true, giro: true, hasta: 10).suelta == nil)
ok("(d) Techo a mano, ve pared a +5°, fuerte y con giro: a los 3.0 s (no a los 2.9)",
   R.revisar(aMano: true, enganchada: false, sinNada: true, seccion: "ceiling", zona: "wall", zonaDisponible: true, grados: 5, fuerte: true, huboGiro: true, otraPared: false, desde: 0, ahora: 2.9).suelta == nil
   && R.revisar(aMano: true, enganchada: false, sinNada: true, seccion: "ceiling", zona: "wall", zonaDisponible: true, grados: 5, fuerte: true, huboGiro: true, otraPared: false, desde: 0, ahora: 3.0).suelta == "ve-wall")
ok("(e) a mano sin fuente fuerte: nunca", corre(aMano: true, seccion: "ceiling", zona: "wall", grados: 5, fuerte: false, giro: true, hasta: 10).suelta == nil)
ok("(f) con algo marcado: nunca, y la cuenta vuelve a cero",
   { let r = R.revisar(aMano: false, enganchada: true, sinNada: false, seccion: "wall", zona: "floor", zonaDisponible: true, grados: -55, fuerte: true, huboGiro: true, otraPared: false, desde: 1.0, ahora: 5); return r.suelta == nil && r.desde == nil }())
ok("(g) cocina escogida: nunca", corre(aMano: true, seccion: "kitchen", zona: "wall", grados: 0, fuerte: true, giro: true, hasta: 10).suelta == nil)
ok("(h) otra pared en un parcial de pared, sin giro: 'otra-pared' a los 1.5 s",
   { let x = corre(enganchada: true, seccion: "wall", zona: "wall", grados: 0, giro: false, otraPared: true, hasta: 3); return x.suelta == "otra-pared" && abs(x.en - 1.5) < 0.051 }())
ok("(i) sin zona: nunca", corre(enganchada: true, seccion: "wall", zona: nil, grados: -55, fuerte: true, giro: true, hasta: 10).suelta == nil)

print("\n  \(pasan) pasan, \(fallan) fallan")
exit(fallan == 0 ? 0 : 1)
'''
io.open(out, 'w', encoding='utf-8').write('import Foundation\nimport simd\n' + ubicador + '\n' + lector + '\n' + prueba)
PYEOF
xcrun swiftc -O -o "${OUT%.swift}" "$OUT" 2>&1 | grep -E "error" | head -5 || true
"${OUT%.swift}"
