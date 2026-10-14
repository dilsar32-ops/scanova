// Scanova · la ficha del proyecto con niveles y cuartos (diseño de Amilcar, 12 oct 2026). Lo puro de proyecto.js.
import * as P from '../docs/proyecto.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };

const NV = [{ id:'n1', nombre:'Basement' }, { id:'n2', nombre:'First Floor' }];
const CU = [{ id:'c1', nivel_id:'n2', nombre:'Kitchen' }, { id:'c2', nivel_id:'n2', nombre:'Living Room' }, { id:'c3', nivel_id:'n1', nombre:'Laundry' }];
const F = [
  { id:'f1', nivel_id:'n2', cuarto_id:'c1', created_by:'u1', subida_at:'2026-10-12T14:00:00Z' },
  { id:'f2', nivel_id:'n2', cuarto_id:'c2', created_by:'u1', subida_at:'2026-10-12T14:20:00Z' },
  { id:'f3', nivel_id:'n1', cuarto_id:null, created_by:'u2', subida_at:'2026-10-11T09:00:00Z' },
  { id:'f4', nivel_id:null, cuarto_id:null, created_by:'u1', subida_at:'2026-10-10T09:00:00Z', tomada_at:'2026-10-10T08:00:00Z' },
];

ok('los niveles rápidos y los tipos de cuarto son los del diseño', P.NIVELES_RAPIDOS.join() === 'Basement,First Floor,Second Floor,Third Floor,Attic,Other' && P.TIPOS_CUARTO.join() === 'Living Room,Kitchen,Bedroom,Bathroom,Hallway,Other');
ok('las pestañas (su orden del 14-oct): Rooms (por •••), Photos, Dry Logs, Floor Plan, Measurements, Notes, Documents, Activity', P.TABS.map(x => x[1]).join() === 'Rooms,Photos,Dry Logs,Floor Plan,Measurements,Notes,Documents,Activity');
const c = P.contar(F);
ok('contar: total, por nivel, sin nivel y por cuarto', c.total === 4 && c.nivel.n2 === 2 && c.nivel.n1 === 1 && c.sinNivel === 1 && c.cuarto.c1 === 1 && !c.cuarto.c3);
ok('filtrarFotos: All / un nivel / sin nivel / un cuarto', P.filtrarFotos(F, { nivel:'todos', cuarto:'todos' }).length === 4 && P.filtrarFotos(F, { nivel:'n2', cuarto:'todos' }).map(f => f.id).join() === 'f1,f2' && P.filtrarFotos(F, { nivel:'sin', cuarto:'todos' }).map(f => f.id).join() === 'f4' && P.filtrarFotos(F, { nivel:'n2', cuarto:'c2' }).map(f => f.id).join() === 'f2');
ok('ordenarFotos: Newest primero / Oldest primero; usa la hora en que se tomó si la hay', P.ordenarFotos(F, 'nuevas').map(f => f.id).join() === 'f2,f1,f3,f4' && P.ordenarFotos(F, 'viejas').map(f => f.id).join() === 'f4,f3,f1,f2');
ok('etiquetaFoto: el cuarto; si no, el nivel; si no, "No room"', P.etiquetaFoto(F[0], CU, NV) === 'Kitchen' && P.etiquetaFoto(F[2], CU, NV) === 'Basement' && P.etiquetaFoto(F[3], CU, NV) === 'No room');
const g = P.agruparPorCuarto(P.ordenarFotos(F, 'nuevas'), CU);
ok('agruparPorCuarto (View by Room): en el orden de los cuartos y al final las sin cuarto', g.map(x => x.titulo + ':' + x.fotos.length).join() === 'Kitchen:1,Living Room:1,No room:2');
const act = P.actividad(F, { created_at:'2026-10-09T10:00:00Z' }, (u) => ({ u1:'Vero', u2:'Aroldo' })[u], CU, NV);
ok('actividad: junta las subidas seguidas de una persona y dice a qué cuartos', act[0].texto === 'Vero added 2 photos to 2 rooms' && act.some(x => x.texto === 'Aroldo added 1 photo to Basement') && act[act.length - 1].texto === 'Project created');
ok('actividad: de más nuevo a más viejo', act.every((x, i) => i === 0 || act[i - 1].cuando >= x.cuando));
ok('fechaHora: Oct 12, 2026 y la hora', /^Oct 12, 2026 \d{1,2}:\d{2} (AM|PM)$/.test(P.fechaHora('2026-10-12T14:00:00Z')) && P.fechaHora('') === '');
ok('fechaCortaEn: una fecha sola (sin hora) no se corre un día', P.fechaCortaEn('2026-10-10') === 'Oct 10, 2026' && P.fechaCortaEn(null) === '');
const card = P.fotoCardHtml({ id:'f<1', subida_at:'2026-10-12T14:00:00Z' }, 'u.jpg', 'Kitchen <A>', true);
ok('fotoCardHtml: abre la foto, nombre del cuarto escapado, fecha, ••• y marcada si está escogida', /data-foto="f&lt;1"/.test(card) && /Kitchen &lt;A&gt;/.test(card) && /data-foto-menu=/.test(card) && /class="pfoto sel"/.test(card) && /src="u\.jpg"/.test(card));
ok('tabsHtml: Photos con su conteo y la activa marcada', /data-ptab="fotos">Photos <span class="n" id="fotosConteo">\(142\)<\/span>/.test(P.tabsHtml('fotos', { fotos:142 })) && /class="ptab on" data-ptab="notas"/.test(P.tabsHtml('notas', { fotos:0 })));
ok('tabsHtml: su diseño del 13-oct, sin pestaña Rooms; Photos va primero', !/data-ptab="cuartos"/.test(P.tabsHtml('fotos', { fotos:0 })) && P.tabsHtml('fotos', { fotos:0 }).indexOf('data-ptab="fotos"') < P.tabsHtml('fotos', { fotos:0 }).indexOf('data-ptab="medidas"'));
{ const NV = [{ id:'n1', nombre:'First Floor' }, { id:'n2', nombre:'Basement' }];
  const L = [{ id:'a', nivel_id:'n2' }, { id:'b', nivel_id:null }, { id:'c', nivel_id:'n1' }, { id:'d', nivel_id:'n2' }];
  const g = P.agruparPorNivel(L, NV);
  ok('View by Level: grupos en el orden de los niveles y al final No Level', g.map(x => x.titulo + ':' + x.fotos.map(f => f.id).join('')).join(' ') === 'First Floor:c Basement:ad No Level:b');
  ok('View by Level: un nivel sin fotos no sale', P.agruparPorNivel([{ id:'x', nivel_id:'n1' }], NV).length === 1);
  const D = [{ id:'1', tomada_at:'2026-10-13T15:00:00Z' }, { id:'2', tomada_at:'2026-10-13T14:00:00Z' }, { id:'3', tomada_at:'2026-10-12T14:00:00Z' }];
  const gd = P.agruparPorDia(D);
  ok('View by Date: un grupo por día, respetando el orden en que vienen', gd.length === 2 && gd[0].fotos.length === 2 && gd[1].fotos[0].id === '3' && /Oct 1[23], 2026/.test(gd[0].titulo));
  const m = P.menuVerPorHtml('cuarto', 'viejas');
  ok('menú View by: Level/Room/Date, Date order Newest/Oldest First, con la marca en lo escogido', /View by Level/.test(m) && /View by Room/.test(m) && /View by Date/.test(m) && /Newest First/.test(m) && /Oldest First/.test(m) && /data-ver-por="cuarto" class="on"/.test(m) && /data-orden-fotos="viejas" class="on"/.test(m) && !/data-ver-por="nivel" class="on"/.test(m) && (m.match(/menu-ok/g) || []).length === 2); }
ok('nombreDestino: nivel › cuarto, solo nivel, o No room', typeof P.nombreDestino === 'function' && P.nombreDestino({}) === 'No room');

// ---------- su segunda imagen: etiquetas, Project Details ----------
const D = await import('../docs/detalles.js');
ok('etiquetasDe: limpia, quita repetidas (sin importar mayúsculas) y pone gris si el color es raro', JSON.stringify(P.etiquetasDe({ etiquetas:[{ t:' Google Drive ', c:'gris' }, { t:'google drive', c:'verde' }, { t:'Flood Doctor Contract', c:'zzz' }, { t:'' }] })) === JSON.stringify([{ t:'Google Drive', c:'gris' }, { t:'Flood Doctor Contract', c:'gris' }]) && P.etiquetasDe({}).length === 0);
const eh = P.etiquetasHtml({ estado:'activo', etapa:'en_curso', etiquetas:[{ t:'active', c:'verde' }, { t:'Flood <Doctor>', c:'amarillo' }] });
ok('etiquetasHtml: solo las suyas (escapadas), sin Active ni la etapa puestas solas', eh === '<span class="etq-c c-verde">active</span><span class="etq-c c-amarillo">Flood &lt;Doctor&gt;</span>' && P.etiquetasHtml({ estado:'activo', etapa:'en_curso' }) === '');
ok('etiquetasHtml: archivado sí avisa con Archived en gris', /^<span class="etq-c c-gris">Archived<\/span>/.test(P.etiquetasHtml({ estado:'archivado', etapa:'en_curso', etiquetas:[{ t:'x', c:'azul' }] })));
ok('sugerenciasEtq: las de otros proyectos, sin las que ya tiene ni repetidas', P.sugerenciasEtq([{ etiquetas:[{ t:'Google Drive', c:'gris' }, { t:'Xactimate', c:'azul' }] }, { etiquetas:[{ t:'xactimate', c:'rojo' }] }], [{ t:'google drive', c:'gris' }]).map(x => x.t).join() === 'Xactimate');
const ad = P.actividadDetalles([{ texto:'Pull baseboards', created_by:'u1', created_at:'2026-10-12T10:00:00Z', hecha:true, hecha_por:'u2', hecha_at:'2026-10-12T12:00:00Z' }], [{ texto:'Adjuster comes Monday', created_by:'u2', created_at:'2026-10-12T11:00:00Z' }], (u) => ({ u1:'Vero', u2:'Aroldo' })[u]);
ok('actividadDetalles: tarea nueva, comentario y tarea hecha (con quién)', ad.length === 3 && ad.some(x => x.texto === 'Vero added the task "Pull baseboards"') && ad.some(x => x.texto === 'Aroldo commented: "Adjuster comes Monday"') && ad.some(x => x.texto === 'Aroldo completed "Pull baseboards"'));
ok('ordenarTareas: las que faltan primero (la más vieja arriba) y las hechas al final', D.ordenarTareas([{ id:'a', hecha:true, created_at:'1' }, { id:'b', hecha:false, created_at:'3' }, { id:'c', hecha:false, created_at:'2' }]).map(x => x.id).join() === 'c,b,a');
ok('usuariosHtml: iniciales con el nombre al pasar el dedo; vacío lo dice', /title="Amilcar Gonzalez" translate="no">AG</.test(D.usuariosHtml(['u1'], () => 'Amilcar Gonzalez')) && /No one assigned yet/.test(D.usuariosHtml([], () => '')));
ok('tareaHtml y comentarioHtml: escapan el texto; el ✕ solo si puede borrar', /Pull &lt;b&gt;/.test(D.tareaHtml({ id:'t1', texto:'Pull <b>', hecha:false }, false)) && !/data-tarea-borrar/.test(D.tareaHtml({ id:'t1', texto:'x' }, false)) && /data-com-borrar="c1"/.test(D.comentarioHtml({ id:'c1', texto:'<i>hola</i>', created_at:'2026-10-12T10:00:00Z' }, 'Vero', true)) && /&lt;i&gt;hola/.test(D.comentarioHtml({ id:'c1', texto:'<i>hola</i>', created_at:'2026-10-12T10:00:00Z' }, 'Vero', false)));
ok('horaCorta: hoy dice "Today" y otro día la fecha', /^Today \d/.test(D.horaCorta('2026-10-12T15:00:00Z', Date.parse('2026-10-12T16:00:00Z'))) && /^Oct 1\d /.test(D.horaCorta('2026-10-10T15:00:00Z', Date.parse('2026-10-12T16:00:00Z'))));

ok('nombreLibre: si ya hay Bedroom en el nivel, el siguiente es Bedroom 2 (y luego 3)', P.nombreLibre('Bedroom', ['Kitchen']) === 'Bedroom' && P.nombreLibre('Bedroom', ['bedroom']) === 'Bedroom 2' && P.nombreLibre('Bedroom', ['Bedroom', 'Bedroom 2']) === 'Bedroom 3');
import fs from 'node:fs';
const idx = fs.readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8');
const pc = idx.slice(idx.indexOf('id="pCuarto"'), idx.indexOf('</section>', idx.indexOf('id="pCuarto"')));
ok('Add Room: primero el Level, luego Room Name, Room Type y Notes; Save Room y Done', pc.indexOf('id="cNivel"') < pc.indexOf('id="cNombre"') && pc.indexOf('id="cNombre"') < pc.indexOf('id="cTipos"') && pc.indexOf('id="cTipos"') < pc.indexOf('id="cNotas"') && /id="btnCuartoListo"/.test(pc) && /id="cHechos"/.test(pc));
const app = fs.readFileSync(new URL('../docs/app.js', import.meta.url), 'utf8');
const irA = app.slice(app.indexOf('export function irA('), app.indexOf('export function atras('));
ok('cambiar de pantalla cierra Edit Labels / datos del cliente / escoger cuarto', /#detHoja/.test(irA) && /#hojaCuarto/.test(irA) && /\.hidden = true/.test(irA));
{ const pj = fs.readFileSync(new URL('../docs/proyecto.js', import.meta.url), 'utf8');
  ok('teléfono: flechita junto al título cuando hay un nivel escogido, y regresa un paso', /ptitulo-atras solo-movil" data-filtro-atras/.test(pj) && /FILTRO\.nivel !== 'todos' \? `<button type="button" class="ptitulo-atras/.test(pj) && /if\(FILTRO\.cuarto !== 'todos'\) FILTRO\.cuarto = 'todos'; else FILTRO = \{ nivel:'todos', cuarto:'todos' \}/.test(pj)); }
{ const nom = (l) => P.ordenarNiveles(l.map((n, i) => ({ id:'n' + i, nombre:n }))).map(x => x.nombre).join(' / ');
  ok('niveles del más alto al más bajo aunque se creen desordenados (su proyecto Harold)', nom(['First Floor', 'Second Floor', 'Basement', 'Third Floor']) === 'Third Floor / Second Floor / First Floor / Basement');
  ok('niveles en español y con ático, techo y otros al final', nom(['Ático', 'Segundo piso', 'Garage', 'Sótano', 'Primer piso', 'Techo']) === 'Techo / Ático / Segundo piso / Primer piso / Sótano / Garage');
  ok('niveles con número y Main / Crawl Space', nom(['Level 2', 'Crawl Space', 'Main Level', 'Floor 3']) === 'Floor 3 / Level 2 / Main Level / Crawl Space');
  ok('nombres que no son pisos se quedan en el orden en que se crearon', nom(['Exterior', 'Garage', 'Shed']) === 'Exterior / Garage / Shed');
  ok('"Living Room" o "cuarto" no se confunden con un piso', P.rangoNivel('Cuarto de lavado') === 100 && P.rangoNivel('Living Room') === 100); }
// 13-oct: la pestaña Floor Plan dice cuántos pisos tienen plano; "Select" va junto a cada grupo de fotos.
{ const src = (await import('node:fs')).readFileSync(new URL('../docs/proyecto.js', import.meta.url), 'utf8');
  ok('la pestaña Floor Plan trae su contador', /id="planoConteo"/.test(P.tabsHtml('fotos', { fotos: 3 })));
  ok('Select ya no está arriba en la barra de herramientas', !/class="btn btn-outline btn-chico psel-btn/.test(src));
  ok('cada grupo (piso, cuarto o fecha) trae su Select', /<div class="pgrupo-cab"><h4>[\s\S]{0,120}selGrupo\(g\.fotos\.map/.test(src) && /data-sel-grupo/.test(src));
  ok('con la selección abierta hay Cancel en la barra', /<div class="psel-barra"><button type="button" class="btn btn-outline btn-chico" id="btnSeleccionar">Cancel/.test(src)); }
{ const PL = await import('../docs/planos.js');
  ok('pisos con plano: cada piso cuenta una vez', PL.pisosConPlano([{ nivel_id: 'a' }, { nivel_id: 'a' }, { nivel_id: 'b' }, { nivel_id: null }]) === 3 && PL.pisosConPlano([]) === 0); }
console.log(`\nproyecto: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
