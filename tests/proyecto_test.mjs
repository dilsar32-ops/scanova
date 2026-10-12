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
ok('las pestañas: Rooms, Photos, Measurements, Notes, Documents, Activity', P.TABS.map(x => x[1]).join() === 'Rooms,Photos,Measurements,Notes,Documents,Activity');
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
ok('tabsHtml: Photos con su conteo y la activa marcada', /data-ptab="fotos">Photos <span class="n" id="fotosConteo">\(142\)<\/span>/.test(P.tabsHtml('fotos', { fotos:142 })) && /class="ptab on" data-ptab="cuartos"/.test(P.tabsHtml('cuartos', { fotos:0 })));
ok('nombreDestino: nivel › cuarto, solo nivel, o No room', typeof P.nombreDestino === 'function' && P.nombreDestino({}) === 'No room');

// ---------- su segunda imagen: etiquetas, Project Details ----------
const D = await import('../docs/detalles.js');
ok('etiquetasDe: limpia, quita repetidas (sin importar mayúsculas) y pone gris si el color es raro', JSON.stringify(P.etiquetasDe({ etiquetas:[{ t:' Google Drive ', c:'gris' }, { t:'google drive', c:'verde' }, { t:'Flood Doctor Contract', c:'zzz' }, { t:'' }] })) === JSON.stringify([{ t:'Google Drive', c:'gris' }, { t:'Flood Doctor Contract', c:'gris' }]) && P.etiquetasDe({}).length === 0);
const eh = P.etiquetasHtml({ estado:'activo', etapa:'en_curso', etiquetas:[{ t:'Flood <Doctor>', c:'verde' }] });
ok('etiquetasHtml: Active verde, las suyas (escapadas) y la etapa al final en amarillo', /^<span class="etq-c c-verde">Active<\/span><span class="etq-c c-verde">Flood &lt;Doctor&gt;<\/span><span class="etq-c c-amarillo">In Progress<\/span>$/.test(eh));
ok('etiquetasHtml: archivado dice Archived y no enseña la etapa', /c-gris">Archived</.test(P.etiquetasHtml({ estado:'archivado', etapa:'en_curso' })) && !/In Progress/.test(P.etiquetasHtml({ estado:'archivado', etapa:'en_curso' })));
ok('sugerenciasEtq: las de otros proyectos, sin las que ya tiene ni repetidas', P.sugerenciasEtq([{ etiquetas:[{ t:'Google Drive', c:'gris' }, { t:'Xactimate', c:'azul' }] }, { etiquetas:[{ t:'xactimate', c:'rojo' }] }], [{ t:'google drive', c:'gris' }]).map(x => x.t).join() === 'Xactimate');
const ad = P.actividadDetalles([{ texto:'Pull baseboards', created_by:'u1', created_at:'2026-10-12T10:00:00Z', hecha:true, hecha_por:'u2', hecha_at:'2026-10-12T12:00:00Z' }], [{ texto:'Adjuster comes Monday', created_by:'u2', created_at:'2026-10-12T11:00:00Z' }], (u) => ({ u1:'Vero', u2:'Aroldo' })[u]);
ok('actividadDetalles: tarea nueva, comentario y tarea hecha (con quién)', ad.length === 3 && ad.some(x => x.texto === 'Vero added the task "Pull baseboards"') && ad.some(x => x.texto === 'Aroldo commented: "Adjuster comes Monday"') && ad.some(x => x.texto === 'Aroldo completed "Pull baseboards"'));
ok('ordenarTareas: las que faltan primero (la más vieja arriba) y las hechas al final', D.ordenarTareas([{ id:'a', hecha:true, created_at:'1' }, { id:'b', hecha:false, created_at:'3' }, { id:'c', hecha:false, created_at:'2' }]).map(x => x.id).join() === 'c,b,a');
ok('usuariosHtml: iniciales con el nombre al pasar el dedo; vacío lo dice', /title="Amilcar Gonzalez" translate="no">AG</.test(D.usuariosHtml(['u1'], () => 'Amilcar Gonzalez')) && /No one assigned yet/.test(D.usuariosHtml([], () => '')));
ok('tareaHtml y comentarioHtml: escapan el texto; el ✕ solo si puede borrar', /Pull &lt;b&gt;/.test(D.tareaHtml({ id:'t1', texto:'Pull <b>', hecha:false }, false)) && !/data-tarea-borrar/.test(D.tareaHtml({ id:'t1', texto:'x' }, false)) && /data-com-borrar="c1"/.test(D.comentarioHtml({ id:'c1', texto:'<i>hola</i>', created_at:'2026-10-12T10:00:00Z' }, 'Vero', true)) && /&lt;i&gt;hola/.test(D.comentarioHtml({ id:'c1', texto:'<i>hola</i>', created_at:'2026-10-12T10:00:00Z' }, 'Vero', false)));
ok('horaCorta: hoy dice "Today" y otro día la fecha', /^Today \d/.test(D.horaCorta('2026-10-12T15:00:00Z', Date.parse('2026-10-12T16:00:00Z'))) && /^Oct 1\d /.test(D.horaCorta('2026-10-10T15:00:00Z', Date.parse('2026-10-12T16:00:00Z'))));

console.log(`\nproyecto: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
