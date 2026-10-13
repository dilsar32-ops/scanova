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
ok('vista limpia: sin sello FLOOR PLAN, la hoja sí lo tiene', !/>FLOOR PLAN</.test(limpia) && />FLOOR PLAN</.test(hoja));
ok('vista limpia: sin cotas de pared (la hoja sí)', (limpia.match(/<text/g) || []).length < (hoja.match(/<text/g) || []).length / 2);
ok('vista limpia: conserva nombre y medida de cada cuarto', /LIVING ROOM/.test(limpia) && /27'-11" x 18'-8"/.test(limpia));
ok('la hoja después de la vista limpia sigue completa (el modo no se queda pegado)', PL.svgDelPlano(data, {}) .includes('>FLOOR PLAN<'));
// Acercar con los dedos (13-oct): nunca se sale del cuadro ni se encoge de más.
{ const e = PL.limitarPZ({ s: 0.4, x: 50, y: 50 }, 300, 200); ok('pellizco: no se encoge menos que entero', e.s === 1 && e.x === 0 && e.y === 0); }
{ const e = PL.zoomEn({ s: 1, x: 0, y: 0 }, 2, 150, 100); ok('pellizco: acerca en el punto de los dedos (el punto no se mueve)', e.x === -150 && e.y === -100); }
{ const e = PL.limitarPZ({ s: 2, x: -900, y: 40 }, 300, 200); ok('pellizco: no deja mover el plano fuera del cuadro', e.x === -300 && e.y === 0); }
{ const src = fs.readFileSync(new URL('../docs/planos.js', import.meta.url), 'utf8'); ok('teléfono: sin + y − encima del plano', /class="pl-tel-flota"><button type="button" class="pl-grande-btn"/.test(src)); }
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
