// Scanova360 + Field Reports · reconocer clósets (su pedido del 14-oct: "entrena a la aplicación").
// Cada caso es una situación de casa real; el plano lo arma el mismo código de Field Reports (docs/plano.js).
import fs from 'node:fs';
import * as PL from '../docs/planos.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
let n = 0;
const W = (pts) => pts.map((p, i) => { const q = pts[(i + 1) % pts.length]; return { id: 'w' + (++n), start: { x: p[0], y: p[1] }, end: { x: q[0], y: q[1] }, lengthFt: Math.hypot(q[0]-p[0], q[1]-p[1]), heightFt: 8 }; });
const cuarto = (pts, nombre, extra) => Object.assign({ id: 'r' + (++n), roomName: nombre, level: 1, walls: W(pts), doors: [], windows: [], openings: [], objects: [] }, extra || {});
const caja = (x, y, w, h, nombre, extra) => cuarto([[x,y],[x+w,y],[x+w,y+h],[x,y+h]], nombre, extra);
const obj = (cat, x, y) => ({ id: 'o' + (++n), category: cat, center: { x, y }, widthFt: 2, depthFt: 2 });
const prep = (rooms, extra) => PL.prepararPlano(Object.assign({ merged: true, rooms }, extra || {}));
const nombres = (d) => d.rooms.map(r => r.roomName);

// 1. Recámara + cuartito sin nombre al lado -> Closet
{ const d = prep([caja(0, 0, 12, 12, 'Bedroom'), caja(12, 0, 2.5, 6, '')]);
  ok('1. cuartito al lado de la recámara = Closet', nombres(d)[1] === 'Closet'); }
// 2. Pasillo + cuartito al lado -> Closet (closet de pasillo)
{ const d = prep([caja(0, 0, 15, 3.5, 'Hallway'), caja(5, 3.5, 4, 3, 'Room 2')]);
  ok('2. cuartito a un lado del pasillo = Closet', nombres(d)[1] === 'Closet'); }
// 3. Recámara principal + cuarto chico con inodoro -> Master Bath
{ const d = prep([caja(0, 0, 14, 13, 'Master Bedroom'), caja(14, 0, 8, 6, '', { objects: [obj('toilet', 16, 2)] })]);
  ok('3. cuarto con inodoro al lado de la recámara principal = Master Bath', nombres(d)[1] === 'Master Bath'); }
// 4. Cuarto chico con lavadora -> Laundry
{ const d = prep([caja(0, 0, 14, 12, 'Living Room'), caja(14, 0, 6, 5, '', { objects: [obj('washerDryer', 16, 2)] })]);
  ok('4. cuarto con lavadora = Laundry', nombres(d)[1] === 'Laundry'); }
// 5. Un cuarto mediano sin pistas NO se vuelve clóset
{ const d = prep([caja(0, 0, 14, 12, 'Living Room'), caja(14, 0, 10, 9, '')]);
  ok('5. un cuarto de 90 sq ft sin pistas no se llama Closet', nombres(d)[1] !== 'Closet'); }
// 6. Muy chico (25 sq ft) junto a la sala -> Closet (abrigos)
{ const d = prep([caja(0, 0, 14, 12, 'Living Room'), caja(14, 0, 5, 5, '')]);
  ok('6. 25 sq ft junto a la sala = Closet', nombres(d)[1] === 'Closet'); }
// 7. Lo que dijo el personal manda: un "Pantry" chico se queda Pantry
{ const d = prep([caja(0, 0, 12, 12, 'Kitchen'), caja(12, 0, 3, 4, '', { voiceName: 'Pantry' })]);
  ok('7. nombre dicho por voz (Pantry) no se cambia', nombres(d)[1] === 'Pantry'); }
// 8. Espacio con nombre genérico ("Open Space") pegado al pasillo -> Closet
{ const d = prep([caja(0, 0, 15, 3.5, 'Hallway')], { _spaceLabels: [{ x: 7, y: -1.25, w: 8, d: 2.5, level: 1, name: 'Open Space' }] });
  ok('8. "Open Space" pegado al pasillo = Closet', d._spaceLabels[0].name === 'Closet'); }
// 9. Un espacio que alguien nombró de verdad no se toca
{ const d = prep([caja(0, 0, 15, 3.5, 'Hallway')], { _spaceLabels: [{ x: 7, y: -1.25, w: 8, d: 2.5, level: 1, name: 'Office' }] });
  ok('9. un espacio llamado "Office" se queda Office', d._spaceLabels[0].name === 'Office'); }
// 10. Rincón dentro de la recámara con la puerta en la BOCA = clóset con puerta
{ const r = cuarto([[0,0],[12,0],[12,3],[14.3,3],[14.3,9],[12,9],[12,12],[0,12]], 'Master Bedroom');
  r.doors.push({ id: 'd1', wallId: 'x', position: { x: 12, y: 6 }, widthFt: 2.6 });
  const d = prep([r]); const sa = d.rooms[0]._subAreas || [];
  ok('10. rincón con su puerta en la entrada = Closet (no se descarta por la puerta)', sa.length === 1 && sa[0].name === 'Closet'); }
// 11. El mismo rincón con la puerta al FONDO es un vestíbulo (se pasa a otro cuarto): no es clóset
{ const r = cuarto([[0,0],[12,0],[12,3],[14.3,3],[14.3,9],[12,9],[12,12],[0,12]], 'Bathroom');
  r.doors.push({ id: 'd2', wallId: 'x', position: { x: 14.3, y: 6 }, widthFt: 2.6 });
  const d = prep([r]);
  ok('11. rincón con la puerta al fondo (vestíbulo) no es Closet', !(d.rooms[0]._subAreas || []).length); }
// 12. Un cuarto en L sin rincón chico no inventa clósets
{ const d = prep([cuarto([[0,0],[16,0],[16,8],[8,8],[8,14],[0,14]], 'Living Room')]);
  ok('12. una sala en L no inventa un clóset', !(d.rooms[0]._subAreas || []).length); }
// 13. Su plano real: el "Open Space" del pasillo y el rincón del Master Bedroom salen como clósets
{ const raw = JSON.parse(fs.readFileSync(new URL('./fixtures/plano_real.json', import.meta.url), 'utf8'));
  const sv = PL.svgDelPlano(raw.data || raw, {}, true);
  ok('13. plano real: 3 clósets (pasillo, el del medio y el del Master Bedroom), ningún "Open Space"', (sv.match(/>CLOSET</g) || []).length === 3 && !/OPEN SPACE/.test(sv)); }
console.log(`\nclosets: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
