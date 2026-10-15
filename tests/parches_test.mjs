// EL PARCHE QUE NO CAE DONDE FALTABA (14-oct, la casa de Harold: "puso un cuarto encima de la cocina").
// "Completar escaneo" le pega al cuarto paredes `_parche`; las que atraviesan otro cuarto (o el piso del
// mismo) se apartan, sin borrarse. Probado con el plano REAL de Harold y con casos chicos.
import fs from 'fs';
const PL = await import('../docs/planos.js');
const plano = await import('../docs/plano.js');
let ok = 0, mal = 0;
const t = (n, c) => { if(c) ok++; else { mal++; console.log('FAIL', n); } };
const fx = JSON.parse(fs.readFileSync(new URL('./fixtures/harold_parche_cocina.json', import.meta.url), 'utf8'));

// Cuánto piso comparten dos cuartos (rejilla de 0.25 ft).
function encimado(a, b){
  const pa = plano.fpOrderedRoomPolygon(a), pb = plano.fpOrderedRoomPolygon(b);
  if(pa.length < 3 || pb.length < 3) return 0;
  const xs = pa.map(p => p.x), ys = pa.map(p => p.y), dentro = (p, poly) => { let c = false; for(let i = 0, j = poly.length - 1; i < poly.length; j = i++){ const xi = poly[i].x, yi = poly[i].y, xj = poly[j].x, yj = poly[j].y; if(((yi > p.y) !== (yj > p.y)) && (p.x < (xj - xi) * (p.y - yi) / (yj - yi) + xi)) c = !c; } return c; };
  let n = 0; for(let x = Math.min(...xs); x <= Math.max(...xs); x += 0.25) for(let y = Math.min(...ys); y <= Math.max(...ys); y += 0.25){ const p = { x, y }; if(dentro(p, pa) && dentro(p, pb)) n++; }
  return n * 0.0625;
}

// 1) El plano real de Harold.
{
  const crudo = fx.data;
  t('Harold crudo: la sala trae 4 paredes de parche', crudo.rooms[0].walls.filter(w => w._parche).length === 4);
  const d = PL.prepararPlano(crudo);
  const sala = d.rooms[0], cocina = d.rooms[1], closet = d.rooms[3];
  t('las 4 paredes del parche se apartan (la caja encima de la cocina ya no se dibuja)', sala.walls.every(w => !w._parche) && sala._parcheApartado && sala._parcheApartado.walls.length === 4);
  t('su puerta y su ventana se van con ellas', sala._parcheApartado.doors.length === 1 && sala._parcheApartado.windows.length === 1 && !(sala.windows || []).some(o => o._parche) && !(sala.doors || []).some(o => o._parche));
  t('las paredes escaneadas de la sala se quedan todas (8)', sala.walls.length === 8);
  t('la sala ya no se encima con la cocina', encimado(sala, cocina) < 3);
  t('ni con el clóset', encimado(sala, closet) < 3);
  const a = plano.fpRoomDisplayAreaSqFt(cocina);
  t('la cocina mide lo suyo (8 x 8 ft, no el pedazo que dejaba la caja)', a > 60 && a < 75);
  t('lo guardado no se toca (se trabaja sobre una copia)', crudo.rooms[0].walls.filter(w => w._parche).length === 4);
  const svg = PL.svgDelPlano(crudo, { cliente: 'Cliente de prueba' }, true);
  t('el dibujo sale sin NaN', svg.length > 1000 && !/NaN|undefined/.test(svg));
}

// 2) Casos chicos.
const pared = (x1, y1, x2, y2, extra) => Object.assign({ id: 'w' + [x1, y1, x2, y2].join('_'), start: { x: x1, y: y1 }, end: { x: x2, y: y2 }, heightFt: 8, lengthFt: Math.hypot(x2 - x1, y2 - y1), confidence: 'high' }, extra || {});
const cuarto = (nombre, walls, extra) => Object.assign({ roomName: nombre, level: 1, walls, doors: [], windows: [], openings: [], objects: [] }, extra || {});
const plan = (rooms) => ({ merged: true, rooms });
{
  // Sala de 12 x 10 a la que le faltó un tramo de 4 ft en la pared de la derecha; el parche lo trae justo ahí.
  const sala = cuarto('Living Room', [pared(0, 0, 12, 0), pared(12, 0, 12, 3), pared(12, 7, 12, 10), pared(12, 10, 0, 10), pared(0, 10, 0, 0), pared(12, 3, 12, 7, { _parche: true, id: 'p0' })]);
  const vecino = cuarto('Kitchen', [pared(12, 0, 20, 0), pared(20, 0, 20, 10), pared(20, 10, 12, 10), pared(12, 10, 12, 0)]);
  const d = plan([sala, vecino]);
  const r = plano.fpValidarParches(d);
  t('el parche que trae justo el pedazo que faltaba se queda', r.length === 0 && d.rooms[0].walls.some(w => w.id === 'p0') && !d.rooms[0]._parcheApartado);
}
{
  // El parche que atraviesa el cuarto de al lado se aparta; el resto del cuarto no se toca.
  const sala = cuarto('Living Room', [pared(0, 0, 12, 0), pared(12, 0, 12, 10), pared(12, 10, 0, 10), pared(0, 10, 0, 0), pared(16, -2, 16, 12, { _parche: true, id: 'p0' })], { windows: [{ id: 'v1', wallId: 'p0', _parche: true, widthFt: 3, position: { x: 16, y: 5 } }] });
  const vecino = cuarto('Kitchen', [pared(12, 0, 20, 0), pared(20, 0, 20, 10), pared(20, 10, 12, 10), pared(12, 10, 12, 0)]);
  const d = plan([sala, vecino]);
  const r = plano.fpValidarParches(d);
  t('el parche que pasa por en medio de la cocina se aparta', r.length === 1 && !d.rooms[0].walls.some(w => w._parche) && d.rooms[0]._parcheApartado.walls.length === 1);
  t('con su ventana', d.rooms[0].windows.length === 0 && d.rooms[0]._parcheApartado.windows.length === 1);
  t('las 4 paredes escaneadas siguen', d.rooms[0].walls.length === 4 && d.rooms[1].walls.length === 4);
  t('el plano lleva la cuenta de lo apartado', d._parchesApartados === 1);
}
{
  // El parche que cruza el piso del mismo cuarto (no cierra ningún hueco) también se aparta.
  const sala = cuarto('Living Room', [pared(0, 0, 12, 0), pared(12, 0, 12, 10), pared(12, 10, 0, 10), pared(0, 10, 0, 0), pared(6, 1, 6, 9, { _parche: true, id: 'p0' })]);
  const d = plan([sala]);
  t('el parche que cruza el piso de su propio cuarto se aparta', plano.fpValidarParches(d).length === 1 && d.rooms[0].walls.length === 4);
}
{
  // Un plano editado a mano no se toca: lo que dejó la persona manda.
  const crudo = JSON.parse(JSON.stringify(fx.data)); crudo._handEdited = true;
  const d = PL.prepararPlano(crudo);
  t('plano editado a mano: el parche se queda como lo dejó la persona', d.rooms[0].walls.filter(w => w._parche).length === 4 && !d.rooms[0]._parcheApartado);
}
{
  // Sin parches no pasa nada.
  const sala = cuarto('Living Room', [pared(0, 0, 12, 0), pared(12, 0, 12, 10), pared(12, 10, 0, 10), pared(0, 10, 0, 0)]);
  const d = plan([sala]);
  t('sin parches no se mueve nada', plano.fpValidarParches(d).length === 0 && !('_parchesApartados' in d));
}
{
  // 14-oct: una sola pared del parche que cae FUERA de todo cuarto (F5FCA58A, 6 ft al sur de la cocina). Muestrear
  // la pared no la veía; el contorno de la sala daba la vuelta hasta ella por encima de los vecinos.
  for(const ids of [['F5FCA58A'], ['F5FCA58A', '108E2655']]){
    const crudo = JSON.parse(JSON.stringify(fx.data));
    crudo.rooms[0].walls = crudo.rooms[0].walls.filter(w => !w._parche || ids.some(k => String(w.id).startsWith(k)));
    const r = plano.fpValidarParches(crudo);
    t('la pared del parche que cae fuera de todo cuarto se aparta (' + ids.join('+') + ')', !crudo.rooms[0].walls.some(w => w._parche && String(w.id).startsWith('F5FCA58A')));
  }
}
{
  // Sin merge (falló el merge de Apple): el parche que cruza el piso de su propio cuarto se aparta igual.
  const sala = cuarto('Living Room', [pared(0, 0, 12, 0), pared(12, 0, 12, 10), pared(12, 10, 0, 10), pared(0, 10, 0, 0), pared(6, 1, 6, 9, { _parche: true, id: 'p0' })]);
  const d = { merged: false, rooms: [sala] };
  t('sin merge: el parche que cruza su propio piso también se aparta', plano.fpValidarParches(d).length === 1 && d.rooms[0].walls.length === 4);
}
console.log('parches:', ok, 'ok,', mal, 'fallas');
if(mal) process.exit(1);
