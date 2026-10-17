// Scanova · 17-oct, su pedido: en la hoja "Photos go to…" de la cámara salen solos los niveles y cuartos del PLANO del
// proyecto (sin detector, sin LiDAR), aunque nadie los haya creado a mano. Solo el que se toca se agrega al proyecto.
import fs from 'node:fs';
import * as PL from '../docs/planos.js';
import * as PR from '../docs/proyecto.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const raw = JSON.parse(fs.readFileSync(new URL('./fixtures/plano_real.json', import.meta.url), 'utf8')); const data = raw.data || raw;
const copia = (o) => JSON.parse(JSON.stringify(o));

// ---------- lo que dice el plano ----------
{ const l = PL.nivelesDePlanos([{ id: 'p1', nivel_id: 'N1', data }]);
  ok('el plano real da sus 5 cuartos con nombre, en su nivel del proyecto', l.length === 1 && l[0].nivel_id === 'N1' && l[0].cuartos.join('|') === 'Living Room|Kitchen|Hallway|Master Bedroom|Bathroom');
  ok('sin nombre de nivel en el escaneo no se inventa la planta', l[0].nombre === ''); }
{ const viejo = copia(data); viejo.rooms.forEach(r => { r.roomName = 'Viejo ' + (r.roomName || ''); });
  const l = PL.nivelesDePlanos([{ id: 'nuevo', nivel_id: 'N1', data }, { id: 'viejo', nivel_id: 'N1', data: viejo }]);
  ok('de cada piso manda el plano más reciente (no se mezclan escaneos viejos)', l.length === 1 && !l[0].cuartos.some(c => /^Viejo/.test(c))); }
{ const d = copia(data); d.rooms[0].roomName = 'Nuevo cuarto'; d.rooms[1].deleted = true; d.rooms[2].roomName = ''; d.rooms[2].voiceName = ''; d._handEdited = true;
  const l = PL.nivelesDePlanos([{ id: 'x', nivel_id: null, data: d }]);
  const cs = l.length ? l[0].cuartos : [];
  ok('no salen: la orden "nuevo cuarto", los cuartos borrados del plano', !cs.some(c => /nuevo cuarto/i.test(c)) && !cs.includes('Kitchen')); }
{ const d = copia(data); d.inspection = Object.assign({}, d.inspection || {}, { nombresDeNivel: { '1': 'Basement' } });
  const l = PL.nivelesDePlanos([{ id: 'x', nivel_id: null, data: d }]);
  ok('un plano guardado sin nivel trae el nombre del nivel que escogieron al escanear', l.length === 1 && l[0].nivel_id === null && l[0].nombre === 'Basement'); }
{ const d = copia(data); delete d.inspection; d._nivelBase = '2nd Floor';
  ok('la planta estándar del escaneo sale como los niveles del proyecto (2nd Floor -> Second Floor)', PL.nombreDeNivelDelPlano(PL.prepararPlano(d)) === 'Second Floor'); }
ok('sin planos: nada (la hoja queda como hoy)', PL.nivelesDePlanos([]).length === 0 && PL.nivelesDePlanos(null).length === 0 && PR.sugerenciasDelPlano([], [], []).length === 0);
ok('un plano sin datos o roto no tumba la hoja', PL.nivelesDePlanos([{ id: 'a', nivel_id: 'N1', data: null }, { id: 'b', nivel_id: 'N2' }]).length === 0);

// ---------- cómo se cruza con el proyecto ----------
const NIV = [{ id: 'N1', nombre: 'First Floor' }, { id: 'N2', nombre: 'Basement' }];
const CU = [{ id: 'c1', nivel_id: 'N1', nombre: 'kitchen' }, { id: 'c2', nivel_id: 'N2', nombre: 'Living Room' }];
{ const s = PR.sugerenciasDelPlano([{ nivel_id: 'N1', nombre: '', cuartos: ['Living Room', 'Kitchen', 'Bathroom'] }], NIV, CU);
  ok('va al nivel del proyecto donde se guardó el plano', s.length === 1 && s[0].nivel && s[0].nivel.id === 'N1' && s[0].nombre === 'First Floor');
  ok('un cuarto que ya existe en ese nivel no se repite (sin importar mayúsculas)', s[0].cuartos.join('|') === 'Living Room|Bathroom'); }
{ const s = PR.sugerenciasDelPlano([{ nivel_id: null, nombre: '1st Floor', cuartos: ['Kitchen', 'Bedroom'] }], NIV, CU);
  ok('un plano sin nivel cae en el nivel del mismo nombre (1st Floor = First Floor)', s.length === 1 && s[0].nivel && s[0].nivel.id === 'N1' && s[0].cuartos.join('|') === 'Bedroom'); }
{ const s = PR.sugerenciasDelPlano([{ nivel_id: null, nombre: 'Attic', cuartos: ['Storage'] }], NIV, CU);
  ok('un nivel del plano que no está en el proyecto sale como nivel nuevo (todavía sin crear)', s.length === 1 && s[0].nivel === null && s[0].nombre === 'Attic' && s[0].cuartos[0] === 'Storage'); }
{ const s = PR.sugerenciasDelPlano([{ nivel_id: null, nombre: '', cuartos: ['Kitchen'] }], [], []);
  ok('proyecto sin niveles y plano sin nombre de nivel: "Level 1", nunca una planta inventada', s.length === 1 && s[0].nombre === 'Level 1' && !/floor|basement/i.test(s[0].nombre)); }
{ const s = PR.sugerenciasDelPlano([{ nivel_id: 'BORRADO', nombre: '', cuartos: ['Kitchen'] }], NIV, CU);
  ok('el plano de un nivel que ya no está y sin nombre: no se adivina dónde va', s.length === 0); }
{ const s = PR.sugerenciasDelPlano([{ nivel_id: 'N1', nombre: '', cuartos: ['Kitchen'] }], NIV, CU);
  ok('si ya están todos en el proyecto no sale nada extra', s.length === 0); }
ok('nombres iguales sin acentos ni espacios de más', PR.claveNombre('  Baño   Principal ') === PR.claveNombre('bano principal'));

// ---------- en la hoja (código) ----------
const src = fs.readFileSync(new URL('../docs/proyecto.js', import.meta.url), 'utf8');
const cuerpo = (nombre) => { const i = src.indexOf(nombre); return src.slice(i, src.indexOf('\n}\n', i)); };
const pe = cuerpo('function pintarEscoger('), ec = cuerpo('export function escogerCuarto('), dp = cuerpo('async function escogerDelPlano(');
ok('abrir o pintar la hoja nunca crea niveles ni cuartos', !/crearNivel|crearCuarto|asegurar/.test(pe) && !/crearNivel|crearCuarto|asegurar/.test(ec));
ok('la hoja lee el plano guardado (nada nativo, sin detector)', /planos\.nivelesDelPlanoDe\(tid\)/.test(ec) && !/Capacitor|RoomScan|detect/i.test(ec + pe + dp));
ok('lo del plano va con su propia acción (data-escoger-plano), con la misma fila de siempre', /data-escoger-plano=/.test(pe) && /class="cap-fila cuarto-op" data-escoger-plano/.test(pe) && /From floor plan/.test(pe));
ok('al tocarlo: primero se releen niveles y cuartos, luego se busca por nombre, y solo entonces se crea', dp.indexOf('await refrescarCuartos(tid)') > 0 && dp.indexOf('await refrescarCuartos(tid)') < dp.indexOf('crearNivel(') && dp.indexOf('claveNombre(c.nombre) === claveNombre(p.cuarto)') < dp.indexOf('crearCuarto(') && dp.indexOf('claveNombre(c.nombre)') > 0);
ok('las fotos van al cuarto tocado, y solo si la hoja sigue abierta para lo mismo', /escogerDelPlano\(p\)\.then\(d => \{ if\(AL_ESCOGER !== fn\) return; cerrarEscoger\(\); if\(fn\) fn\(d\); \}\)/.test(src));
ok('sin plano la hoja sigue igual (No levels yet + rápidos, Add level, No room)', /This project has no levels yet\. Tap one to add it:/.test(pe) && /Add level/.test(pe) && /'No room', 'Keep it without a room'/.test(pe));


// ---------- 17-oct revisión: nombres con apóstrofo y planos viejos del mismo piso ----------
{ const linea = src.split('\n').find(l => l.includes('const opPlano = ')); const expr = linea.slice(linea.indexOf('(g, cuarto) =>'), linea.lastIndexOf(';'));
  const { esc } = await import('../docs/trabajos.js');
  const opPlano = new Function('esc', 'IC', 'return ' + expr)(esc, () => '');
  const html = opPlano({ nivel: null, nombre: "Mom's Floor" }, "Kid's Room");
  const m = html.match(/data-escoger-plano=(["'])([\s\S]*?)\1/);
  const dec = (v) => v.replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
  let p = null; try{ p = JSON.parse(dec(m[2])); }catch(e){}
  ok('un cuarto o nivel con apóstrofo ("Kid\'s Room") se puede tocar: el atributo se lee completo', p && p.cuarto === "Kid's Room" && p.nivel === "Mom's Floor"); }
{ const s = PR.sugerenciasDelPlano([
    { nivel_id: 'N1', nombre: 'First Floor', cuartos: ['Living Room', 'Study'] },          // el más nuevo, con su nivel
    { nivel_id: null, nombre: 'First Floor', cuartos: ['Living Rom', 'Office', 'Study'] }  // uno viejo sin nivel, mismo piso
  ], NIV, CU);
  ok('un plano viejo del mismo piso no mezcla sus cuartos con el más nuevo', s.length === 1 && s[0].cuartos.join('|') === 'Living Room|Study'); }
{ const s = PR.sugerenciasDelPlano([{ nivel_id: 'N1', nombre: '', cuartos: [] }, { nivel_id: null, nombre: 'First Floor', cuartos: ['Office'] }], NIV, CU);
  ok('si el plano más nuevo del piso ya no tiene un cuarto, uno viejo no lo revive', s.length === 0); }
{ const d = copia(data); d.rooms.forEach(r => { r.deleted = true; }); const viejo = copia(data);
  const l = PL.nivelesDePlanos([{ id: 'nuevo', nivel_id: 'N1', data: d }, { id: 'viejo', nivel_id: 'N1', data: viejo }]);
  ok('el plano más nuevo sin cuartos con nombre igual tapa al viejo de ese piso', l.length === 1 && l[0].cuartos.length === 0 && PR.sugerenciasDelPlano(l, NIV, CU).length === 0); }

console.log(`\ncuartos del plano: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
