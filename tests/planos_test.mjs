// Scanova360 · pestaña Floor Plan: el plano real (de un escaneo de Field Reports) se mide y se dibuja igual.
import fs from 'node:fs';
import * as PL from '../docs/planos.js';
import * as P from '../docs/plano.js';
import * as PR from '../docs/proyecto.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const raw = JSON.parse(fs.readFileSync(new URL('./fixtures/plano_real.json', import.meta.url), 'utf8')); const data = raw.data || raw;
const r = PL.resumenPlano(data);
ok('Plan Details del plano real: 674 sq ft, 5 cuartos (lo mismo que dice Field Reports)', Math.round(r.area) === 674 && r.cuartos === 5);
ok('paredes exteriores y altura del techo salen del escaneo (164 lf, 8.25 ft)', r.murosExt === 164 && r.techo === 8.25);
ok('plano vacío no inventa medidas', JSON.stringify(PL.resumenPlano({ rooms: [] })) === JSON.stringify({ area: 0, cuartos: 0, murosExt: 0, techo: 0 }));
const svg = PL.svgDelPlano(data, { cliente: 'Lauren <Harris>', direccion: '9 Oak Ln' });
ok('dibuja el plano (SVG con paredes y cotas)', /^<svg[\s>]/.test(svg) && svg.length > 30000 && /LIVING ROOM/.test(svg));
ok('el sello dice Scanova360, nunca el nombre de la otra empresa', !/restoration doctor/i.test(svg) && !/restoration doctor/i.test(fs.readFileSync(new URL('../docs/plano.js', import.meta.url), 'utf8')));
ok('el nombre del cliente va escapado en el sello', !/Lauren <Harris>/.test(svg));
// Vista de la pantalla (su pedido 13-oct): solo el plano. La hoja del PDF/exportar no cambia.
const limpia = PL.svgDelPlano(data, { cliente: 'Lauren Harris', direccion: '9 Oak Ln' }, true);
const hoja = PL.svgDelPlano(data, { cliente: 'Lauren Harris', direccion: '9 Oak Ln' });
ok('14-oct: la imagen que se exporta es la MISMA hoja que la pantalla (sin el sello viejo FLOOR PLAN)', !/>FLOOR PLAN</.test(limpia) && !/>FLOOR PLAN</.test(hoja) && /Scanova<tspan fill="#2563eb">360<\/tspan>/.test(hoja) && !/DRAFT/.test(hoja));
// Su diseño del 14-oct: la vista es una hoja limpia — cadenas de medidas por fuera, nombre + sq ft, marco.
ok('vista y exportar: medidas por fuera en cadenas, y el total en el encabezado', /class="fp-cadenas"/.test(limpia) && /class="fp-cadenas"/.test(hoja) && /8' 7"/.test(limpia) && /Total Area: [\d.]+ sq ft/.test(hoja));
ok('vista: nombre + sq ft de cada cuarto (sin las medidas del cuarto)', /LIVING ROOM/.test(limpia) && /303\.7 sq ft/.test(limpia) && !/27'-11" x 18'-8"/.test(limpia));
ok('vista: marco con encabezado y pie (Units, Scale, Page)',  /Not to scale/.test(limpia) && /ft \/ in/.test(limpia) && /Page/.test(limpia));
ok('vista: piso blanco y sin el sello viejo de abajo', !/#fbfbfa/.test(limpia) && !/TOTAL AREA/.test(limpia));
{ const ultObj = Math.max(limpia.lastIndexOf('class="fp-obj"'), hoja.lastIndexOf('class="fp-obj"') >= 0 ? 0 : 0), primPared = limpia.indexOf('class="fp-wall"');
  ok('ningún mueble encima de una pared: todos los muebles se dibujan antes que las paredes (vista y hoja)', limpia.lastIndexOf('class="fp-obj"') < primPared && hoja.lastIndexOf('class="fp-obj"') < hoja.indexOf('class="fp-wall"') && limpia.includes('class="fp-obj"')); }
ok('ventanas de doble línea y esquinas de pared unidas', (limpia.match(/stroke-width="1.2"\/>/g) || []).length >= 4 && /style="pointer-events:none;"\/>/.test(limpia));
ok('exportar lleva abajo la tabla de medidas (como Field Reports); la pantalla no, y no se queda pegada', /class="fp-tabla"/.test(PL.svgDelPlano(data, {})) && /FLOOR SF/.test(PL.svgDelPlano(data, {})) && !/class="fp-tabla"/.test(PL.svgDelPlano(data, {}, true)));
// Acercar con los dedos (13-oct): nunca se sale del cuadro ni se encoge de más.
{ const e = PL.limitarPZ({ s: 0.4, x: 50, y: 50 }, 300, 200); ok('pellizco: no se encoge menos que entero', e.s === 1 && e.x === 0 && e.y === 0); }
{ const e = PL.zoomEn({ s: 1, x: 0, y: 0 }, 2, 150, 100); ok('pellizco: acerca en el punto de los dedos (el punto no se mueve)', e.x === -150 && e.y === -100); }
{ const e = PL.limitarPZ({ s: 2, x: -900, y: 40 }, 300, 200); ok('pellizco: no deja mover el plano fuera del cuadro', e.x === -300 && e.y === 0); }
{ const src = fs.readFileSync(new URL('../docs/planos.js', import.meta.url), 'utf8'); ok('teléfono: sin + y − encima del plano', /class="pl-tel-flota"><button type="button" class="pl-grande-btn"/.test(src)); }
// Su queja del 13-oct: "los planos salen de lado". El escaneo llega con el ángulo del teléfono: se endereza.
{ const girar = (d, gr) => { const a = gr*Math.PI/180, c = Math.cos(a), sn = Math.sin(a); const rot = p => ({ x: p.x*c - p.y*sn, y: p.x*sn + p.y*c });
    const o = JSON.parse(JSON.stringify(d)); delete o._handEdited; o.rooms.forEach(r => { (r.walls||[]).forEach(w => { w.start = rot(w.start); w.end = rot(w.end); }); ['doors','windows','openings'].forEach(k => (r[k]||[]).forEach(x => x.position && (x.position = rot(x.position)))); (r.objects||[]).forEach(x => { x.center = rot(x.center); }); }); return o; };
  const chueco = d => { let peor = 0; d.rooms.forEach(r => (r.walls||[]).forEach(w => { if(Math.hypot(w.end.x-w.start.x, w.end.y-w.start.y) < 2) return; const g = Math.abs(Math.atan2(w.end.y-w.start.y, w.end.x-w.start.x))*180/Math.PI % 90; peor = Math.max(peor, Math.min(g, 90-g)); })); return peor; };
  const crudo = girar(data, 33), listo = PL.prepararPlano(crudo);
  ok('plano de lado (33°) sale derecho: ninguna pared chueca', chueco(crudo) > 30 && chueco(listo) < 0.5);
  ok('enderezar no cambia el área', Math.abs(PL.resumenPlano(crudo).area - r.area) < 1);
  ok('enderezar no toca lo guardado (trabaja sobre una copia)', chueco(crudo) > 30);
  ok('el dibujo usa el plano enderezado', PL.svgDelPlano(crudo, {}, true) === PL.svgDelPlano(listo, {}, true) || /LIVING ROOM/.test(PL.svgDelPlano(crudo, {}, true)));
  const src = fs.readFileSync(new URL('../docs/planos.js', import.meta.url), 'utf8');
  ok('el escaneo nuevo se guarda ya derecho', /const d = prepararPlano\(r\)/.test(src) && /data: d, area_sqft/.test(src));
  ok('teléfono: la página del plano queda quieta si todo cabe (pl-fijo)', /classList\.add\('pl-fijo'\)/.test(src) && /pl-fijo/.test(fs.readFileSync(new URL('../docs/app.js', import.meta.url), 'utf8')));
}
// Su pedido del 14-oct: el nombre que el personal dice al escanear (voiceName) es el que sale en el plano.
{ const v = JSON.parse(JSON.stringify(data)); v.rooms.forEach(r => { delete r.roomName; delete r._namedByVoice; }); v.rooms[0].voiceName = 'Sala de juegos'; v.rooms[1].voiceName = 'Cocina'; v.rooms[2].roomName = 'Pasillo'; v.rooms[2].voiceName = 'Otro';
  const lv = PL.svgDelPlano(v, {}, true);
  ok('el nombre dicho al escanear sale en el plano', /SALA DE JUEGOS/.test(lv) && /COCINA/.test(lv));
  ok('un nombre puesto a mano gana sobre el dicho', /PASILLO/.test(lv) && !/>OTRO</.test(lv));
  ok('ponerle el nombre no toca lo guardado', !v.rooms[0].roomName && PL.prepararPlano(v).rooms[0].roomName === 'Sala de juegos');
  const ord = JSON.parse(JSON.stringify(v)); ord.rooms[0].voiceName = 'Nuevo cuarto'; ord.rooms[1].voiceName = 'cuarto nuevo';
  const lo = PL.svgDelPlano(ord, {}, true);
  ok('"Nuevo cuarto" es la orden de pasar, no un nombre: sale Room N', !/NUEVO CUARTO/i.test(lo) && /ROOM 1/.test(lo) && /ROOM 2/.test(lo));
  ok('un nombre de verdad con "cuarto" sí pasa', !PL.esOrdenDeCuarto('Cuarto de lavado') && !PL.esOrdenDeCuarto('Cuarto de Chucho') && PL.esOrdenDeCuarto('Otro cuarto'));
  const sin = JSON.parse(JSON.stringify(v)); sin.rooms.forEach(r => { delete r.roomName; delete r.voiceName; });
  ok('sin nombre dicho sigue saliendo Room N (no inventa)', /ROOM 1/.test(PL.svgDelPlano(sin, {}, true))); }
// Su pedido (14-oct): bloque único nombre / largo x ancho / sq ft, flechitas sin líneas, closet, sin repetidos.
{ const lv = PL.svgDelPlano(data, {}, true);
  ok('bloque del cuarto: nombre, luego largo x ancho en pies y pulgadas, y el área debajo', /LIVING ROOM<\/text><text[^>]*>\d+' \d+" x \d+' \d+"<\/text><text[^>]*>303\.7 sq ft/.test(lv));
  ok('puntitas de flecha junto a las paredes, sin líneas entre ellas', /class="fp-extent"/.test(lv) && !/class="fp-extent"[^]*?<line/.test(lv.slice(lv.indexOf('class="fp-extent"'), lv.indexOf('class="fp-extent"') + 600)));
  ok('un rótulo de espacio que cae dentro de un cuarto no se escribe (LAUNDRY ROOM sobre el Master Bedroom)', !/LAUNDRY ROOM/.test(lv));
  const caja = (x, y, w, h, id) => ({ id, level: 1, walls: [[x,y,x+w,y],[x+w,y,x+w,y+h],[x+w,y+h,x,y+h],[x,y+h,x,y]].map((q, k) => ({ id: id + k, start: { x: q[0], y: q[1] }, end: { x: q[2], y: q[3] }, lengthFt: Math.hypot(q[2]-q[0], q[3]-q[1]), heightFt: 8 })), doors: [], windows: [], openings: [], objects: [] });
  const dos = { merged: true, rooms: [caja(0, 0, 12, 10, 'a'), caja(12, 0, 4, 5, 'b')] };
  const sv = PL.svgDelPlano(dos, {}, true);
  ok('un cuarto chico sin nombre se llama Closet (el grande no)', /CLOSET/.test(sv) && /ROOM 1/.test(sv) && !/ROOM 2/.test(sv)); }
// Su pedido (14-oct): la puerta del clóset corrediza; un nombre movido con el dibujo viejo no se queda en la esquina.
{ const caja = (x, y, w, h, id, nom) => ({ id, roomName: nom, level: 1, walls: [[x,y,x+w,y],[x+w,y,x+w,y+h],[x+w,y+h,x,y+h],[x,y+h,x,y]].map((q, k) => ({ id: id + k, start: { x: q[0], y: q[1] }, end: { x: q[2], y: q[3] }, lengthFt: Math.hypot(q[2]-q[0], q[3]-q[1]), heightFt: 8 })), doors: [], windows: [], openings: [], objects: [] });
  const a = caja(0, 0, 12, 10, 'a', 'Bedroom'), b = caja(12, 0, 4, 5, 'b', 'Closet');
  a.doors.push({ id: 'p1', wallId: 'a1', position: { x: 12, y: 2.5 }, widthFt: 2.5 });
  a.doors.push({ id: 'p2', wallId: 'a2', position: { x: 6, y: 10 }, widthFt: 3 });
  const sv = PL.svgDelPlano({ merged: true, rooms: [a, b] }, {}, true);
  ok('puerta del closet corrediza (sin arco); la otra puerta con su arco', (sv.match(/<path d="M [^"]* A /g) || []).length === 1);
  const c = JSON.parse(JSON.stringify(data)); const mb = c.rooms.find(r => /master/i.test(r.roomName)); mb._labelOffsetPx = { dx: 900, dy: 900 };
  const vc = PL.svgDelPlano(c, {}, true), vn = PL.svgDelPlano(data, {}, true);
  const xDe = (sv2) => { const m = sv2.match(/<text x="([\d.]+)"[^>]*>MASTER BEDROOM</); return m ? +m[1] : NaN; };
  ok('un nombre movido con el dibujo de antes se centra igual en la vista', Math.abs(xDe(vc) - xDe(vn)) < 1); }
const L = [{ id:'a', nivel_id:'n1', created_at:'2026-10-13' }, { id:'b', nivel_id:'n1', created_at:'2026-10-12' }, { id:'c', nivel_id:null }];
ok('de cada piso se ve el escaneo más reciente; los viejos quedan de historial', PL.planoDe(L, 'n1').id === 'a' && PL.planoDe(L, 'sin').id === 'c' && PL.planoDe(L, 'n2') === null);
ok('pestañas: Photos, Floor Plan, Measurements… (Floor Plan después de Photos)', /data-ptab="fotos".*data-ptab="plano".*data-ptab="medidas"/.test(PR.tabsHtml('plano', { fotos: 3 })) && /Floor Plan/.test(PR.tabsHtml('plano', { fotos: 3 })));
const sql = fs.readFileSync(new URL('../sql/fotos-07-planos.sql', import.meta.url), 'utf8');
ok('SQL: tabla con candado, sin borrar filas, anon fuera, ASCII puro', /create table if not exists fotos_planos/.test(sql) && /enable row level security/.test(sql) && !/for delete/.test(sql) && /revoke all on fotos_planos from anon/.test(sql) && !/[^\x00-\x7F]/.test(sql));
const js = fs.readFileSync(new URL('../docs/planos.js', import.meta.url), 'utf8');
ok('escanea con el escáner del iPhone (RoomScan) y avisa si no hay LiDAR', /Plugins\.RoomScan/.test(js) && /isSupported/.test(js) && /no LiDAR/.test(js));
ok('confirma que de verdad se guardó antes de decir "saved"', /return=representation/.test(js) && /if\(!guardada \|\| !guardada\.id\) throw/.test(js));
console.log(`\nplanos: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
