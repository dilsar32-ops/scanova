// EL NIVEL Y EL NOMBRE QUE SE ESCOGIERON EN LA CÁMARA (14-oct, la casa de Harold).
// - La hoja decía "Level: Floor 1" / "LEVEL 1" en un plano escaneado en "Third Floor".
// - Un cuarto que nadie nombró salía "ROOM 1" aunque el teléfono lo enseñaba como "Dining Room".
// - Un escaneo con dos niveles se dibujaba solo el primero pero el total sumaba los dos.
import fs from 'fs';
const PL = await import('../docs/planos.js');
const plano = await import('../docs/plano.js');
let ok = 0, mal = 0;
const t = (n, c, extra) => { if(c) ok++; else { mal++; console.log('FAIL', n, extra === undefined ? '' : JSON.stringify(extra)); } };
const fx = JSON.parse(fs.readFileSync(new URL('./fixtures/harold_parche_cocina.json', import.meta.url), 'utf8'));
{
  const limpia = PL.svgDelPlano(fx.data, { cliente: 'Cliente de prueba' }, true);
  const hoja = PL.svgDelPlano(fx.data, { cliente: 'Cliente de prueba' });
  t('el marco dice el nivel que se escogió en la cámara (Third Floor)', /Level:<\/tspan> <tspan font-weight="700">Third Floor</.test(hoja) && !/Floor 1</.test(hoja));
  t('la tabla dice THIRD FLOOR, no LEVEL 1', /THIRD FLOOR/.test(hoja) && !/LEVEL 1</.test(hoja));
  t('la vista de la pantalla también', /Third Floor/.test(limpia));
  const d = PL.prepararPlano(fx.data);
  t('el cuarto que nadie nombró ya no sale ROOM 1', !!d.rooms[0].roomName && !/^room\b/i.test(d.rooms[0].roomName), d.rooms[0].roomName);
  t('marcado como sugerido', !!d.rooms[0]._suggestedConfidence);
  t('los nombres dichos no se tocan', d.rooms[1].roomName === 'Kitchen' && !d.rooms[1]._suggestedConfidence);
}
{
  // El nombre que el teléfono enseñaba manda (nombresSugeridos); uno dicho, nunca.
  const crudo = JSON.parse(JSON.stringify(fx.data));
  crudo.inspection = Object.assign({}, crudo.inspection, { nombresSugeridos: { '0': 'Family Room', '1': 'Garage' } });
  const d = PL.prepararPlano(crudo);
  t('usa el nombre que el teléfono enseñaba', d.rooms[0].roomName === 'Family Room', d.rooms[0].roomName);
  t('pero no le quita su nombre a la cocina', d.rooms[1].roomName === 'Kitchen');
}
{
  // Un cuarto cuyo "nombre" era la orden "Nuevo cuarto": se nombra por sus muebles.
  const caja = (x, nom, objs) => ({ voiceName: nom, level: 1, walls: [[x,0,x+12,0],[x+12,0,x+12,10],[x+12,10,x,10],[x,10,x,0]].map((c, k) => ({ id: nom + k + x, start: { x: c[0], y: c[1] }, end: { x: c[2], y: c[3] }, heightFt: 8, confidence: 'high' })), doors: [], windows: [], openings: [], objects: objs });
  const d = PL.prepararPlano({ merged: true, rooms: [caja(0, 'Nuevo cuarto', [{ category: 'bed', center: { x: 6, y: 5 }, widthFt: 5, depthFt: 6 }])] });
  t('"Nuevo cuarto" con cama sale Bedroom', d.rooms[0].roomName === 'Bedroom', d.rooms[0].roomName);
}
{
  // Dos niveles en un escaneo: cada fila se guarda con su nivel (_nivel) y cuenta solo ese.
  const pared = (x1, y1, x2, y2, id) => ({ id, start: { x: x1, y: y1 }, end: { x: x2, y: y2 }, heightFt: 8, confidence: 'high' });
  const cuarto = (nom, lvl, w, h, p) => ({ roomName: nom, level: lvl, walls: [pared(0,0,w,0,p+1), pared(w,0,w,h,p+2), pared(w,h,0,h,p+3), pared(0,h,0,0,p+4)], doors: [], windows: [], openings: [], objects: [] });
  const dos = { merged: true, rooms: [cuarto('Living Room', 1, 12, 10, 'a'), cuarto('Bedroom', 2, 10, 10, 'b')], inspection: { nombresDeNivel: { '1': 'First Floor', '2': 'Second Floor' } } };
  const r1 = PL.resumenPlano(Object.assign({}, dos, { _nivel: 1 })), r2 = PL.resumenPlano(Object.assign({}, dos, { _nivel: 2 }));
  t('nivel 1: solo su cuarto (120 sq ft)', Math.round(r1.area) === 120 && r1.cuartos === 1, r1);
  t('nivel 2: solo su cuarto (100 sq ft)', Math.round(r2.area) === 100 && r2.cuartos === 1, r2);
  const h2 = PL.svgDelPlano(Object.assign({}, dos, { _nivel: 2 }), {});
  t('la hoja del nivel 2 dibuja el nivel 2 y se llama Second Floor', /BEDROOM/.test(h2) && !/LIVING ROOM/.test(h2) && /Second Floor/.test(h2), '');
  t('cada hoja es Page 1 of 1', /Page <tspan font-weight="700">1<\/tspan> of <tspan font-weight="700">1<\/tspan>/.test(h2));
  const viejo = PL.resumenPlano(dos);
  t('una fila vieja de dos niveles cuenta solo el que se dibuja', Math.round(viejo.area) === 120 && viejo.cuartos === 1, viejo);
}
{
  const src = fs.readFileSync(new URL('../docs/planos.js', import.meta.url), 'utf8');
  t('la lista de pisos enseña el área de hoy (no la guardada el día del escaneo)', /fmtPies\(q\.data \? resumenPlano\(q\.data\)\.area/.test(src));
  t('la altura del techo se redondea a la pulgada, como la hoja', /\* 12\) \/ 12/.test(src));
}
console.log('niveles y nombres:', ok, 'ok,', mal, 'fallas');
if(mal) process.exit(1);
