import Foundation
import CoreGraphics
var ok = 0, mal = 0
func t(_ n: String, _ c: Bool) { if c { ok += 1 } else { mal += 1; print("FAIL", n) } }
typealias F = FloorPlanEncoder
func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
// 1) ajusteRigido recupera un giro + movimiento conocido
let r0 = F.Rigido2D(th: 0.7, tx: 3.2, ty: -1.4)
let walls: [(CGPoint, CGPoint)] = [(P(0,0),P(4,0)), (P(4,0),P(4,3)), (P(4,3),P(0,3)), (P(0,3),P(0,0))]
var pares = walls.map { (a0: $0.0, b0: $0.1, a1: r0.aplicar($0.0), b1: r0.aplicar($0.1), peso: 1.0) }
if let r = F.ajusteRigido(pares) {
  t("giro", abs(r.th - 0.7) < 1e-6); t("tx", abs(r.tx - 3.2) < 1e-6); t("ty", abs(r.ty + 1.4) < 1e-6)
} else { t("ajuste existe", false) }
// una pared que vuelve al revés no confunde el giro
pares[1] = (a0: walls[1].0, b0: walls[1].1, a1: r0.aplicar(walls[1].1), b1: r0.aplicar(walls[1].0), peso: 1.0)
if let r = F.ajusteRigido(pares) { t("pared al revés", abs(r.th - 0.7) < 1e-6 && abs(r.tx - 3.2) < 1e-6) } else { t("pared al revés existe", false) }
// giro de 180 (eje igual, sentido opuesto) se distingue por los puntos medios
let r180 = F.Rigido2D(th: Double.pi, tx: 1, ty: 2)
let p180 = walls.map { (a0: $0.0, b0: $0.1, a1: r180.aplicar($0.0), b1: r180.aplicar($0.1), peso: 1.0) }
if let r = F.ajusteRigido(p180) { let q = r.aplicar(P(4,3)), e = r180.aplicar(P(4,3)); t("180 grados", hypot(q.x-e.x, q.y-e.y) < 1e-6) } else { t("180 existe", false) }
// una sola pared: no se adivina
t("una pared = nil", F.ajusteRigido(Array(pares.prefix(1))) == nil)
// paredes que no cuadran entre sí: nil
var malos = pares; malos[2] = (a0: walls[2].0, b0: walls[2].1, a1: P(40,40), b1: P(44,40), peso: 1.0)
t("no cuadran = nil", F.ajusteRigido(malos) == nil)
// identidad, inverso y luego
let id = F.Rigido2D.identidad.aplicar(P(2,3)); t("identidad", id == P(2,3))
let q = r0.inverso.aplicar(r0.aplicar(P(5,-2))); t("inverso", hypot(q.x-5, q.y+2) < 1e-9)
let r1 = F.Rigido2D(th: -0.3, tx: 0.5, ty: 7)
let a = r1.aplicar(r0.aplicar(P(1,2))), b = r0.luego(r1).aplicar(P(1,2)); t("luego", hypot(a.x-b.x, a.y-b.y) < 1e-9)
let pf = r0.aplicarPies(P(3.28084*2, 0), f: 3.28084), pm = r0.aplicar(P(2,0)); t("pies", hypot(pf.x - pm.x*3.28084, pf.y - pm.y*3.28084) < 1e-6)
// 2) piezasDeParche: el pedazo justo en el hueco se queda
let sala: [(CGPoint, CGPoint)] = [(P(0,0),P(12,0)), (P(12,0),P(12,3)), (P(12,7),P(12,10)), (P(12,10),P(0,10)), (P(0,10),P(0,0))]
let cocina: [(CGPoint, CGPoint)] = [(P(12,0),P(20,0)), (P(20,0),P(20,10)), (P(20,10),P(12,10))]
let poliCocina = [P(12,0),P(20,0),P(20,10),P(12,10)]
var pz = F.piezasDeParche(parcheFt: [(P(12,3),P(12,7))], propiasFt: sala, otrasFt: cocina, otrosContornos: [poliCocina])
t("hueco cerrado: 1 pieza", pz.count == 1)
// el parche que trae de más (de 12,1 a 12,9) solo deja lo del hueco
pz = F.piezasDeParche(parcheFt: [(P(12,1),P(12,9))], propiasFt: sala, otrasFt: cocina, otrosContornos: [poliCocina])
t("solo lo que falta", pz.count == 1 && abs(hypot(pz[0].1.x-pz[0].0.x, pz[0].1.y-pz[0].0.y) - 4) < 0.05)
// el parche en medio de la cocina no agrega nada
pz = F.piezasDeParche(parcheFt: [(P(16,-2),P(16,12))], propiasFt: sala, otrasFt: cocina, otrosContornos: [poliCocina])
t("en la cocina: nada", pz.isEmpty)
// cruzando el piso del propio cuarto: nada
pz = F.piezasDeParche(parcheFt: [(P(6,1),P(6,9))], propiasFt: sala, otrasFt: cocina, otrosContornos: [poliCocina])
t("en su propio piso: nada", pz.isEmpty)
// cuarto cerrado: nada que agregar
let cerrada: [(CGPoint, CGPoint)] = sala + [(P(12,3),P(12,7))]
pz = F.piezasDeParche(parcheFt: [(P(12,3),P(12,7)), (P(3,3),P(5,3))], propiasFt: cerrada, otrasFt: cocina, otrosContornos: [poliCocina])
t("cuarto cerrado: nada", pz.isEmpty)
// 3) El parche REAL de Harold, sin alinear (en su propio marco): no cae en ningún hueco
struct H: Decodable { let propias: [[Double]]; let parche: [[Double]]; let otras: [[[Double]]] }
let h = try! JSONDecoder().decode(H.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
func seg(_ v: [Double]) -> (CGPoint, CGPoint) { (P(v[0],v[1]), P(v[2],v[3])) }
let otras = h.otras.flatMap { $0.map(seg) }
let contornos = h.otras.map { F.contornoYHuecos(wallsFt: $0.map(seg)).poly }
let real = F.piezasDeParche(parcheFt: h.parche.map(seg), propiasFt: h.propias.map(seg), otrasFt: otras, otrosContornos: contornos)
print("Harold: piezas aceptadas", real.count, real.map { String(format: "%.1f", hypot($0.1.x-$0.0.x, $0.1.y-$0.0.y)) })
let huecos = F.outlineGaps(wallsFt: h.propias.map(seg)).filter { !F.gapCoveredByWalls($0, walls: h.propias.map(seg)) }
print("Harold: huecos de la sala", huecos.map { String(format: "%.1f", $0.ft) })
t("Harold: la caja encima de la cocina no entra", real.allSatisfy { p in !contornos.contains { F.enPoligono(CGPoint(x: (p.0.x+p.1.x)/2, y: (p.0.y+p.1.y)/2), $0) } })

// 4) Apple alarga o recorta paredes al juntar: el movimiento sale igual
var estiradas = walls.map { (a0: $0.0, b0: $0.1, a1: r0.aplicar($0.0), b1: r0.aplicar($0.1), peso: 1.0) }
for k in estiradas.indices {
  let (a, b) = (estiradas[k].a1, estiradas[k].b1)
  let dx = b.x - a.x, dy = b.y - a.y, L = hypot(dx, dy)
  let ext = [0.6, 0.0, 1.1, 0.3][k]
  estiradas[k].b1 = CGPoint(x: b.x + dx / L * ext, y: b.y + dy / L * ext)
}
if let r = F.ajusteRigido(estiradas) { t("estiradas: giro", abs(r.th - 0.7) < 1e-6); let q = r.aplicar(P(4,3)), e = r0.aplicar(P(4,3)); t("estiradas: lugar", hypot(q.x-e.x, q.y-e.y) < 0.01) } else { t("estiradas existe", false) }
// todas paralelas: no alcanza
let paralelas: [(CGPoint, CGPoint)] = [(P(0,0),P(4,0)), (P(0,3),P(4,3)), (P(1,6),P(3,6))]
t("paralelas = nil", F.ajusteRigido(paralelas.map { (a0: $0.0, b0: $0.1, a1: r0.aplicar($0.0), b1: r0.aplicar($0.1), peso: 1.0) }) == nil)
// largoCubierto
let lc = F.largoCubierto([(P(12,1),P(12,9)), (P(5,0.2),P(9,0.2))], por: sala)
t("cubierto", abs(lc.cubierto - 8.0) < 0.05 && abs(lc.total - 12.0) < 0.01)

// 5) Paredes ajenas en la casa real de Harold (plano entregado, sin el parche)
struct HW: Decodable { let id: String; let s: [Double] }
struct HR: Decodable { let name: String; let walls: [HW] }
let hr = try! JSONDecoder().decode([HR].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
func huecosDe(_ k: Int, quitar: Bool) -> [Double] {
  let propias = hr[k].walls.map { seg($0.s) }
  let otras = hr.indices.filter { $0 != k }.flatMap { j in hr[j].walls.map { seg($0.s) } }
  let aj = quitar ? F.paredesAjenas(propias: propias, otras: otras) : []
  let w = propias.enumerated().filter { !aj.contains($0.offset) }.map { $0.element }
  return F.outlineGaps(wallsFt: w).filter { $0.ft > F.outlineGapWarnFt && !F.gapCoveredByWalls($0, walls: w) && !F.gapCoveredByWalls($0, walls: otras) }.map { $0.ft }
}
for k in hr.indices {
  let propias = hr[k].walls.map { seg($0.s) }
  let otras = hr.indices.filter { $0 != k }.flatMap { j in hr[j].walls.map { seg($0.s) } }
  let aj = F.paredesAjenas(propias: propias, otras: otras).sorted().map { String(hr[k].walls[$0].id.prefix(8)) }
  print("cuarto", k, hr[k].name, "ajenas:", aj, "huecos antes:", huecosDe(k, quitar: false).map { String(format: "%.1f", $0) }, "después:", huecosDe(k, quitar: true).map { String(format: "%.1f", $0) })
}
t("Harold: la sala ya no avisa", huecosDe(0, quitar: true).isEmpty)
t("Harold: la cocina ya no avisa", huecosDe(1, quitar: true).isEmpty)
t("Harold: la pared del Hallway en la sala es ajena", F.paredesAjenas(propias: hr[0].walls.map { seg($0.s) }, otras: hr[1...].flatMap { $0.walls.map { seg($0.s) } }).contains { hr[0].walls[$0].id.hasPrefix("EFE25C88") })
// una partición de verdad (amarrada por las dos puntas) no es ajena
let caja: [(CGPoint, CGPoint)] = [(P(0,0),P(10,0)), (P(10,0),P(10,8)), (P(10,8),P(0,8)), (P(0,8),P(0,0))]
let vecina: [(CGPoint, CGPoint)] = [(P(10,0),P(18,0)), (P(18,0),P(18,8)), (P(18,8),P(10,8)), (P(10,8),P(10,0))]
t("partición amarrada no es ajena", F.paredesAjenas(propias: caja, otras: vecina).isEmpty)
// una pared del vecino colgando dentro del cuarto sí
let conPuerta: [(CGPoint, CGPoint)] = [(P(0,0),P(10,0)), (P(10,0),P(10,2.5)), (P(10,5.5),P(10,8)), (P(10,8),P(0,8)), (P(0,8),P(0,0)), (P(10,5.5),P(16,5.5))]
let vecino2: [(CGPoint, CGPoint)] = [(P(10,5.5),P(16,5.5)), (P(16,5.5),P(16,12)), (P(16,12),P(10,12)), (P(10,12),P(10,8))]
let aj2 = F.paredesAjenas(propias: conPuerta, otras: vecino2)
t("pared del vecino colgando se ignora (y la puerta no se avisa)", aj2 == [5])

// 6) (revisión) una pared compartida en la misma línea que un hueco real NO es ajena: el hueco se sigue avisando
do {
  let rec: [(CGPoint, CGPoint)] = [(P(0,0),P(12,0)), (P(12,0),P(12,14)), (P(12,20),P(0,20)), (P(0,20),P(0,0))]
  let bano: [(CGPoint, CGPoint)] = [(P(12,0),P(20,0)), (P(20,0),P(20,14)), (P(20,14),P(12,14)), (P(12,14),P(12,0))]
  let aj = F.paredesAjenas(propias: rec, otras: bano)
  let w = rec.enumerated().filter { !aj.contains($0.offset) }.map { $0.element }
  let avisos = F.outlineGaps(wallsFt: w).filter { $0.ft > F.outlineGapWarnFt && !F.gapCoveredByWalls($0, walls: w) && !F.gapCoveredByWalls($0, walls: bano) }
  t("pared compartida en línea con un hueco real: no es ajena", aj.isEmpty)
  t("y el hueco de 6 ft se sigue avisando", avisos.count == 1 && abs(avisos[0].ft - 6) < 0.05)
}
// 7) (revisión) el parche bueno sí cierra el hueco aunque RoomPlan haya metido una pared ajena
do {
  let sala: [(CGPoint, CGPoint)] = [(P(0,7),P(0,10)), (P(0,10),P(12,10)), (P(12,10),P(12,0)), (P(12,0),P(0,0)), (P(12,1.5),P(9,1.5))]
  let closet: [(CGPoint, CGPoint)] = [(P(12,1.5),P(9,1.5)), (P(9,1.5),P(9,-3)), (P(9,-3),P(12,-3)), (P(12,-3),P(12,1.5))]
  let pz = F.piezasDeParche(parcheFt: [(P(0,0),P(0,10))], propiasFt: sala, otrasFt: closet, otrosContornos: [])
  t("el parche bueno cierra el hueco (0,0)-(0,7) con la pared ajena adentro", pz.count == 1 && abs(hypot(pz[0].1.x-pz[0].0.x, pz[0].1.y-pz[0].0.y) - 7) < 0.1)
}
// 8) (revisión) puras paredes paralelas: el respaldo da un movimiento
do {
  let par: [(CGPoint, CGPoint)] = [(P(0,0),P(10,0)), (P(0,4),P(10,4))]
  let pp = par.map { (a0: $0.0, b0: $0.1, a1: r0.aplicar($0.0), b1: r0.aplicar($0.1), peso: 1.0) }
  t("sin respaldo: nil", F.ajusteRigido(pp) == nil)
  if let r = F.ajusteRigido(pp, errorMaximo: 0.35, tambienLargo: true) { t("respaldo: gira bien", abs(r.th - 0.7) < 1e-6) } else { t("respaldo existe", false) }
}

// 9) (revisión 2) la pared de arriba no llega a la esquina (0.9 ft): la compartida sigue siendo del cuarto
do {
  let rec: [(CGPoint, CGPoint)] = [(P(0,0),P(12,0)), (P(12,0),P(12,22)), (P(11.1,30),P(0,30)), (P(0,30),P(0,0))]
  let vec: [(CGPoint, CGPoint)] = [(P(12,0),P(20,0)), (P(20,0),P(20,22)), (P(20,22),P(12,22)), (P(12,22),P(12,0))]
  let aj = F.paredesAjenas(propias: rec, otras: vec)
  let w = rec.enumerated().filter { !aj.contains($0.offset) }.map { $0.element }
  let avisos = F.outlineGaps(wallsFt: w).filter { $0.ft > F.outlineGapWarnFt && !F.gapCoveredByWalls($0, walls: w) && !F.gapCoveredByWalls($0, walls: vec) }
  t("esquina sin escanear: la pared compartida no es ajena", aj.isEmpty)
  t("y el hueco de ~8 ft se avisa", avisos.count == 1 && avisos[0].ft > 7.5)
}

// 10) (revisión 3) pasillo de puras paredes paralelas que Apple estiró 1 m: el respaldo da el marco (con las puertas)
do {
  let antes: [(CGPoint, CGPoint)] = [(P(0,0),P(6,0)), (P(0,2),P(6,2)), (P(1.55,0),P(2.45,0)), (P(3.55,2),P(4.45,2))]
  var pp = antes.map { (a0: $0.0, b0: $0.1, a1: r0.aplicar($0.0), b1: r0.aplicar($0.1), peso: Double(hypot($0.1.x-$0.0.x, $0.1.y-$0.0.y))) }
  for k in 0..<2 { pp[k].b1 = r0.aplicar(P(7, antes[k].1.y)) }   // las dos paredes, 1 m más largas
  let r = F.ajusteRigido(pp, errorMaximo: 0.35, tambienLargo: true, pesosLargo: [0.02, 0.02, 1, 1])
  if let r = r { let q = r.aplicar(P(3,1)), e = r0.aplicar(P(3,1)); t("pasillo estirado: marco bueno", hypot(q.x-e.x, q.y-e.y) < 0.1) } else { t("pasillo estirado: hay marco", false) }
}
print("marcos:", ok, "ok,", mal, "fallas")
exit(mal == 0 ? 0 : 1)
