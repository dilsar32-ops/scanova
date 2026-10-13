// Scanova · la ficha de un proyecto (diseño de Amilcar, 12 oct 2026): portada, nombre, dirección, etapa, cliente,
// encargado y fecha; pestañas Rooms · Photos · Measurements · Notes · Documents · Activity.
// Rooms = niveles (Basement, First Floor…) y sus cuartos (Kitchen…). Photos = las fotos por nivel y por cuarto.
import { $, $$, authFetch, irA, atras, esManager, PERFIL } from './app.js?v=2026-10-13-6';
import * as trabajos from './trabajos.js?v=2026-10-13-6';
import * as fotos from './fotos.js?v=2026-10-13-6';
import * as panel from './panel.js?v=2026-10-13-6';
import * as camara from './camara.js?v=2026-10-13-6';
import * as detalles from './detalles.js?v=2026-10-13-6';

const esc = (v) => trabajos.esc(v);
const IC = (n, cls) => '<svg class="ic' + (cls ? ' ' + cls : '') + '"><use href="#i-' + n + '"/></svg>';

// ---------- lo puro ----------
export const NIVELES_RAPIDOS = ['Basement', 'First Floor', 'Second Floor', 'Third Floor', 'Attic', 'Other'];
export const TIPOS_CUARTO = ['Living Room', 'Kitchen', 'Bedroom', 'Bathroom', 'Hallway', 'Other'];
export const TABS = [['cuartos', 'Rooms'], ['fotos', 'Photos'], ['medidas', 'Measurements'], ['notas', 'Notes'], ['documentos', 'Documents'], ['actividad', 'Activity']];
const fechaF = (f) => f.tomada_at || f.subida_at || '';
export const fechaHora = (iso) => { const d = new Date(iso); return isNaN(d) ? '' : d.toLocaleDateString('en-US', { month:'short', day:'numeric', year:'numeric' }) + ' ' + d.toLocaleTimeString('en-US', { hour:'numeric', minute:'2-digit' }); };
export const fechaCortaEn = (iso) => { if(!iso) return ''; const d = new Date(String(iso).length === 10 ? iso + 'T12:00:00' : iso); return isNaN(d) ? '' : d.toLocaleDateString('en-US', { month:'short', day:'numeric', year:'numeric' }); };
// Cuántas fotos hay en total, por nivel, sin nivel y por cuarto.
export function contar(lista){
  const c = { total:0, sinNivel:0, nivel:{}, cuarto:{} };
  (lista || []).forEach(f => { c.total++; if(f.nivel_id) c.nivel[f.nivel_id] = (c.nivel[f.nivel_id] || 0) + 1; else c.sinNivel++; if(f.cuarto_id) c.cuarto[f.cuarto_id] = (c.cuarto[f.cuarto_id] || 0) + 1; });
  return c;
}
// filtro.nivel: 'todos' | 'sin' | id; filtro.cuarto: 'todos' | id
export function filtrarFotos(lista, filtro){
  const n = filtro && filtro.nivel || 'todos', q = filtro && filtro.cuarto || 'todos';
  return (lista || []).filter(f => (n === 'todos' || (n === 'sin' ? !f.nivel_id : f.nivel_id === n)) && (q === 'todos' || f.cuarto_id === q));
}
export function ordenarFotos(lista, orden){
  const d = orden === 'viejas' ? 1 : -1;
  return (lista || []).slice().sort((a, b) => String(fechaF(a)).localeCompare(String(fechaF(b))) * d);
}
// Lo que dice debajo de cada foto: el cuarto, o el nivel, o "No room".
export function etiquetaFoto(f, cuartos, niveles){
  const c = f.cuarto_id && (cuartos || []).find(x => x.id === f.cuarto_id); if(c) return c.nombre;
  const n = f.nivel_id && (niveles || []).find(x => x.id === f.nivel_id); if(n) return n.nombre;
  return 'No room';
}
// Agrupar por cuarto (View by Room): en el orden de los cuartos, y al final las que no tienen cuarto.
export function agruparPorCuarto(lista, cuartos){
  const grupos = []; const usados = new Set();
  (cuartos || []).forEach(c => { const fs = lista.filter(f => f.cuarto_id === c.id); if(fs.length){ grupos.push({ titulo: c.nombre, fotos: fs }); fs.forEach(f => usados.add(f.id)); } });
  const resto = lista.filter(f => !usados.has(f.id)); if(resto.length) grupos.push({ titulo: 'No room', fotos: resto });
  return grupos;
}
// Activity: subidas seguidas de la misma persona (menos de 2 h entre una y otra) se cuentan juntas.
export function actividad(lista, trabajo, nombreDe, cuartos, niveles){
  const fs = ordenarFotos(lista, 'viejas'); const out = []; let g = null;
  fs.forEach(f => {
    const t = new Date(f.subida_at || fechaF(f)).getTime();
    if(g && g.quien === f.created_by && t - g.fin < 2 * 3600e3){ g.n++; g.fin = t; g.lugares.add(etiquetaFoto(f, cuartos, niveles)); }
    else { g = { quien: f.created_by, n:1, ini:t, fin:t, lugares: new Set([etiquetaFoto(f, cuartos, niveles)]) }; out.push(g); }
  });
  const items = out.map(x => { const l = [...x.lugares].filter(s => s !== 'No room'); return { cuando: x.fin, texto: (nombreDe(x.quien) || 'Someone') + ' added ' + x.n + (x.n === 1 ? ' photo' : ' photos') + (l.length === 1 ? ' to ' + l[0] : l.length > 1 ? ' to ' + l.length + ' rooms' : '') }; });
  if(trabajo && trabajo.created_at) items.push({ cuando: new Date(trabajo.created_at).getTime(), texto:'Project created' });
  return items.sort((a, b) => b.cuando - a.cuando);
}
// Etiquetas de color del proyecto (Edit Labels), como CompanyCam. Se guardan en fotos_trabajos.etiquetas.
export const ETQ_COLORES = { verde:'#16a34a', azul:'#2563eb', amarillo:'#facc15', naranja:'#ea580c', rojo:'#dc2626', morado:'#7c3aed', gris:'#6b7280' };
export function etiquetasDe(t){
  const l = Array.isArray(t && t.etiquetas) ? t.etiquetas : [];
  const vistas = new Set();
  return l.map(x => ({ t: String(x && x.t || '').trim().slice(0, 40), c: ETQ_COLORES[x && x.c] ? x.c : 'gris' })).filter(x => x.t && !vistas.has(x.t.toLowerCase()) && vistas.add(x.t.toLowerCase()));
}
// Solo las etiquetas que él pone (ya no se agregan solas Active ni la etapa: él puso las suyas).
// La única que sale sola es "Archived", para que nunca se le pase que el proyecto está archivado.
export const chipEtq = (txt, color) => `<span class="etq-c c-${esc(color)}">${esc(txt)}</span>`;
export function etiquetasHtml(t){
  return (t.estado === 'archivado' ? chipEtq('Archived', 'gris') : '') + etiquetasDe(t).map(x => chipEtq(x.t, x.c)).join('');
}
// Etiquetas usadas en otros proyectos: para escogerlas con un toque.
export function sugerenciasEtq(lista, actuales){
  const ya = new Set(actuales.map(x => x.t.toLowerCase())); const out = []; const vistas = new Set();
  (lista || []).forEach(t => etiquetasDe(t).forEach(x => { const k = x.t.toLowerCase(); if(!ya.has(k) && !vistas.has(k)){ vistas.add(k); out.push(x); } }));
  return out.slice(0, 12);
}
// Lo de Project Details que va a Activity: comentarios, tareas nuevas y tareas hechas.
export function actividadDetalles(tareas, coms, nombreDe){
  const n = (id) => nombreDe(id) || 'Someone'; const corto = (s) => { s = String(s || ''); return s.length > 60 ? s.slice(0, 57) + '…' : s; };
  const out = [];
  (coms || []).forEach(c => out.push({ cuando: new Date(c.created_at).getTime(), texto: n(c.created_by) + ' commented: "' + corto(c.texto) + '"' }));
  (tareas || []).forEach(t => { out.push({ cuando: new Date(t.created_at).getTime(), texto: n(t.created_by) + ' added the task "' + corto(t.texto) + '"' });
    if(t.hecha && t.hecha_at) out.push({ cuando: new Date(t.hecha_at).getTime(), texto: n(t.hecha_por) + ' completed "' + corto(t.texto) + '"' }); });
  return out.filter(x => !isNaN(x.cuando));
}
export function cabeceraHtml(t, portada, manager){
  // Su diseño: nombre; dirección; "PM · Created" en una línea; y abajo las etiquetas. La foto mide lo mismo que el texto.
  const pm = t.encargado ? 'PM: ' + esc(t.encargado) : '';
  const fecha = 'Created: ' + esc(fechaCortaEn(t.created_at));   // su pedido: junto a PM, la fecha en que se creó el proyecto
  // El cliente ya sale en Project Details (Customer); aquí se repetía junto al nombre del proyecto.
  const meta = [pm, fecha].filter(Boolean).map(x => '<span class="pm-i">' + x + '</span>').join('<span class="sep">|</span>');
  return `<div class="pcab">
    <div class="portada">${portada ? '<img src="' + esc(portada) + '" alt="">' : IC('camara')}</div>
    <div class="pcab-datos">
      <h1 class="pcab-t">${esc(t.cliente)}</h1>
      <a class="pcab-dir" href="${esc(trabajos.mapsUrl(t.direccion))}" target="_blank" rel="noopener">${esc(t.direccion || 'No address')}</a>
      <div class="pcab-meta">${meta}</div>
      <div class="pcab-etqs">${etiquetasHtml(t)}<button type="button" class="enlace-editar solo-compu" data-editar-etq>${IC('lapiz')}Edit Labels</button></div>
      <button type="button" class="enlace-editar solo-movil-i" data-editar-etq>${IC('lapiz')}Edit Labels</button>
    </div>
    <div class="pcab-acc">
      <button type="button" class="btn btn-outline solo-compu" id="btnEditar">Edit Project</button>
      <button type="button" class="icono-btn mas-cab" id="btnFichaMenu" aria-label="Options">${IC('puntos')}</button>
      <button type="button" class="pdet-mostrar" data-det-abrir>${IC('chev-izq')}Show Sidebar</button>
    </div>
  </div>`;
}
export function tabsHtml(activa, conteos){
  return '<div class="ptabs" id="fichaTabs" role="tablist">' + TABS.map(([k, txt]) => `<button type="button" class="ptab${k === activa ? ' on' : ''}" data-ptab="${k}">${txt}${k === 'fotos' ? ' <span class="n" id="fotosConteo">(' + (conteos.fotos || 0) + ')</span>' : ''}</button>`).join('') + '</div>';
}
export function fotoCardHtml(f, url, etiqueta, sel){
  return `<div class="pfoto${sel ? ' sel' : ''}">
    <button type="button" class="ffoto" data-foto="${esc(f.id)}" aria-label="Open photo">${url ? '<img src="' + esc(url) + '" alt="" loading="lazy">' : '<span class="ffoto-vacia"></span>'}<span class="pfoto-check">${IC('check')}</span></button>
    <div class="pfoto-pie"><span class="pfoto-txt"><b>${esc(etiqueta)}</b><small>${esc(fechaHora(fechaF(f)))}</small></span><button type="button" class="mas-btn" data-foto-menu="${esc(f.id)}" aria-label="Photo options">${IC('puntos')}</button></div>
  </div>`;
}

// ---------- estado ----------
let T = null, NIVELES = [], CUARTOS = [], TAB = 'fotos', SUBTAB = 'niveles', NIVEL_CUARTOS = '';
let FILTRO = { nivel:'todos', cuarto:'todos' }, VISTA = 'grid', ORDEN = 'nuevas', POR_CUARTO = false;
let MODO_SEL = false; const SEL = new Set(); let URLS = {}; let EDIT_NIVEL = null, EDIT_CUARTO = null;
export const niveles = () => NIVELES;
export const cuartos = () => CUARTOS;
const cuartosDe = (nivelId) => CUARTOS.filter(c => c.nivel_id === nivelId);
const nombreNivel = (id) => (NIVELES.find(n => n.id === id) || {}).nombre || '';
const nombreCuarto = (id) => (CUARTOS.find(c => c.id === id) || {}).nombre || '';
// A dónde van las fotos nuevas: lo que está escogido en el filtro de Photos.
export function destinoActual(){
  const d = {};
  if(FILTRO.cuarto !== 'todos'){ const c = CUARTOS.find(x => x.id === FILTRO.cuarto); if(c){ d.cuarto_id = c.id; d.nivel_id = c.nivel_id; } }
  else if(FILTRO.nivel !== 'todos' && FILTRO.nivel !== 'sin') d.nivel_id = FILTRO.nivel;
  return d;
}
export const nombreDestino = (d) => d && d.cuarto_id ? nombreNivel(d.nivel_id) + ' › ' + nombreCuarto(d.cuarto_id) : d && d.nivel_id ? nombreNivel(d.nivel_id) : 'No room';

async function cargarCuartos(){
  if(!T) return;
  const id = T.id;
  const [rn, rc] = await Promise.all([
    authFetch('/rest/v1/fotos_niveles?trabajo_id=eq.' + encodeURIComponent(id) + '&select=*&order=orden.asc,created_at.asc'),
    authFetch('/rest/v1/fotos_cuartos?trabajo_id=eq.' + encodeURIComponent(id) + '&select=*&order=orden.asc,created_at.asc'),
  ]);
  if(!T || T.id !== id) return;
  NIVELES = rn.ok ? await rn.json() : []; CUARTOS = rc.ok ? await rc.json() : [];
  if(rn.status === 404) aviso('Esta parte todavía no está instalada en el servidor: falta correr sql/fotos-04-niveles.sql.');
  pintarTodo();
}
function aviso(txt){ const a = $('#fichaAviso'); if(a) a.textContent = txt || ''; }

// ---------- abrir la ficha ----------
export function abrir(t, portada){
  T = t; NIVELES = []; CUARTOS = []; TAB = 'fotos'; SUBTAB = 'niveles'; NIVEL_CUARTOS = '';
  FILTRO = { nivel:'todos', cuarto:'todos' }; POR_CUARTO = false; MODO_SEL = false; SEL.clear(); URLS = {};
  $('#trabajoFicha').innerHTML = cabeceraHtml(t, portada, esManager()) + tabsHtml(TAB, { fotos: 0 }) +
    TABS.map(([k]) => `<div class="tab-panel" data-panel="${k}"${k === TAB ? '' : ' hidden'}>${k === 'fotos' ? '<div id="fotosPanel"></div><p class="aviso" id="fotosAviso"></p>' : '<div id="panel-' + k + '"></div>'}</div>`).join('') +
    '<p class="aviso" id="fichaAviso"></p>';
  detalles.abrir(t);
  cargarCuartos();
}
export const tabActual = () => TAB;
function irTab(k){
  TAB = k; MODO_SEL = false; SEL.clear();
  $$('#fichaTabs .ptab').forEach(b => b.classList.toggle('on', b.dataset.ptab === k));
  $$('#trabajoFicha .tab-panel').forEach(p => { p.hidden = p.dataset.panel !== k; });
  const b = $('#fichaTabs .ptab.on'); if(b && b.scrollIntoView) b.scrollIntoView({ block:'nearest', inline:'center' });
  pintarTodo();
}
function pintarTodo(){ pintarCuartos(); pintarFotos(); pintarNotas(); pintarActividad(); pintarPronto(); camara.pintarCuarto(); }

// ---------- Rooms ----------
function miniDe(lista){ const f = ordenarFotos(lista, 'nuevas')[0]; return f ? (URLS[f.id] || '') : ''; }
function pintarCuartos(){
  const caja = $('#panel-cuartos'); if(!caja) return;
  const fs = fotos.lista();
  const sub = `<div class="subtabs"><button type="button" class="subtab${SUBTAB === 'niveles' ? ' on' : ''}" data-subtab="niveles">Levels</button><button type="button" class="subtab${SUBTAB === 'cuartos' ? ' on' : ''}" data-subtab="cuartos">Rooms</button></div>`;
  if(!NIVELES.length){
    caja.innerHTML = `<div class="sin-cuartos">${IC('casa')}<h3>No rooms yet</h3><p>Add levels and rooms to start capturing photos, measurements and notes.</p>
      <button type="button" class="btn btn-accent btn-block" data-nuevo-nivel>${IC('mas')}Add Level</button>
      <button type="button" class="btn btn-outline btn-block" data-nav="plan">${IC('cubo')}Import Floor Plan</button></div>`;
    return;
  }
  if(SUBTAB === 'niveles'){
    caja.innerHTML = sub + '<div class="plista">' + NIVELES.map(n => { const cs = cuartosDe(n.id); const fn = fs.filter(f => f.nivel_id === n.id); const m = miniDe(fn);
      return `<div class="pfila" data-ver-nivel="${esc(n.id)}"><span class="pfila-mini">${m ? '<img src="' + esc(m) + '" alt="">' : IC('cubo')}</span>
        <span class="pfila-txt"><b>${esc(n.nombre)}</b><small>${cs.length} ${cs.length === 1 ? 'room' : 'rooms'} · ${fn.length} ${fn.length === 1 ? 'photo' : 'photos'}</small></span>
        <button type="button" class="mas-btn" data-nivel-menu="${esc(n.id)}" aria-label="Level options">${IC('puntos')}</button></div>`; }).join('') + '</div>' +
      `<button type="button" class="btn btn-suave btn-block" data-nuevo-nivel>${IC('mas')}Add Level</button>`;
  } else {
    if(!NIVEL_CUARTOS || !NIVELES.some(n => n.id === NIVEL_CUARTOS)) NIVEL_CUARTOS = NIVELES[0].id;
    const cs = cuartosDe(NIVEL_CUARTOS);
    caja.innerHTML = sub + `<label class="sel psel"><select id="selNivelCuartos">${NIVELES.map(n => `<option value="${esc(n.id)}"${n.id === NIVEL_CUARTOS ? ' selected' : ''}>${esc(n.nombre)}</option>`).join('')}</select>${IC('chev')}</label>` +
      (cs.length ? '<div class="plista">' + cs.map(c => { const fc = fs.filter(f => f.cuarto_id === c.id); const m = miniDe(fc);
        return `<div class="pfila" data-ver-cuarto="${esc(c.id)}"><span class="pfila-mini">${m ? '<img src="' + esc(m) + '" alt="">' : IC('casa')}</span>
          <span class="pfila-txt"><b>${esc(c.nombre)}</b><small>${fc.length} ${fc.length === 1 ? 'photo' : 'photos'}${c.tipo && c.tipo !== c.nombre ? ' · ' + esc(c.tipo) : ''}</small></span>
          <button type="button" class="mas-btn" data-cuarto-menu="${esc(c.id)}" aria-label="Room options">${IC('puntos')}</button></div>`; }).join('') + '</div>'
        : '<p class="vacio">No rooms in this level yet.</p>') +
      `<button type="button" class="btn btn-accent btn-block" data-nuevo-cuarto>${IC('mas')}Add Room</button>`;
  }
}

// ---------- Photos ----------
function ordenVisible(lista){ const fs = ordenarFotos(filtrarFotos(lista, FILTRO), ORDEN); return POR_CUARTO ? agruparPorCuarto(fs, CUARTOS.filter(c => FILTRO.nivel === 'todos' || c.nivel_id === FILTRO.nivel)).flatMap(g => g.fotos) : fs; }
export function pintarFotos(urls){
  if(urls) URLS = Object.assign({}, URLS, urls);
  const caja = $('#fotosPanel'); if(!caja || !T) return;
  const todas = fotos.lista(); const c = contar(todas);
  const n = $('#fotosConteo'); if(n) n.textContent = '(' + c.total + ')';
  const chips = [`<button type="button" class="chip${FILTRO.nivel === 'todos' ? ' on' : ''}" data-filtro-nivel="todos">All Photos (${c.total})</button>`]
    .concat(NIVELES.map(nv => `<button type="button" class="chip${FILTRO.nivel === nv.id ? ' on' : ''}" data-filtro-nivel="${esc(nv.id)}">${esc(nv.nombre)} (${c.nivel[nv.id] || 0})</button>`))
    .concat(c.sinNivel && NIVELES.length ? [`<button type="button" class="chip${FILTRO.nivel === 'sin' ? ' on' : ''}" data-filtro-nivel="sin">No level (${c.sinNivel})</button>`] : []);
  const cs = FILTRO.nivel !== 'todos' && FILTRO.nivel !== 'sin' ? cuartosDe(FILTRO.nivel) : [];
  const selCuarto = cs.length ? `<label class="sel psel-cuarto"><select id="selCuartoFotos"><option value="todos">All rooms</option>${cs.map(x => `<option value="${esc(x.id)}"${FILTRO.cuarto === x.id ? ' selected' : ''}>${esc(x.nombre)} (${c.cuarto[x.id] || 0})</option>`).join('')}</select>${IC('chev')}</label>` : '';
  // El selector de nivel del teléfono (en la computadora son botones).
  const opNivel = [`<option value="todos"${FILTRO.nivel === 'todos' ? ' selected' : ''}>All Photos (${c.total})</option>`]
    .concat(NIVELES.map(nv => `<option value="${esc(nv.id)}"${FILTRO.nivel === nv.id ? ' selected' : ''}>${esc(nv.nombre)} (${c.nivel[nv.id] || 0})</option>`))
    .concat(c.sinNivel && NIVELES.length ? [`<option value="sin"${FILTRO.nivel === 'sin' ? ' selected' : ''}>No level (${c.sinNivel})</option>`] : []);
  const herr = `<div class="pherr">
      <div class="chips pchips">${chips.join('')}</div>
      <label class="sel psel-nivel"><select id="selNivelFotos" aria-label="Level">${opNivel.join('')}</select>${IC('chev')}</label>
      <div class="vistas"><button type="button" class="vista${VISTA === 'grid' ? ' on' : ''}" data-vista="grid" aria-label="Grid">${IC('cuadros')}</button><button type="button" class="vista${VISTA === 'lista' ? ' on' : ''}" data-vista="lista" aria-label="List">${IC('lista')}</button></div>
      <label class="sel psel-orden"><select id="selOrdenFotos" aria-label="Order"><option value="nuevas"${ORDEN === 'nuevas' ? ' selected' : ''}>Newest</option><option value="viejas"${ORDEN === 'viejas' ? ' selected' : ''}>Oldest</option></select>${IC('chev')}</label>
      <span class="pherr-salto"></span>
      ${selCuarto}
      <button type="button" class="btn btn-outline btn-chico psel-btn${MODO_SEL ? ' on' : ''}" id="btnSeleccionar">${MODO_SEL ? 'Cancel' : 'Select'}</button>
      ${fotos.botonesSubir()}
    </div>`;
  const porNivel = (FILTRO.nivel === 'todos' && NIVELES.length) ? '<h3 class="psub solo-movil">By Level</h3><div class="plista solo-movil">' + NIVELES.map(nv => { const m = miniDe(todas.filter(f => f.nivel_id === nv.id));
      return `<div class="pfila" data-filtro-nivel="${esc(nv.id)}"><span class="pfila-mini">${m ? '<img src="' + esc(m) + '" alt="">' : IC('cubo')}</span><span class="pfila-txt"><b>${esc(nv.nombre)}</b><small>${c.nivel[nv.id] || 0} photos</small></span>${IC('chev-der', 'chev-der')}</div>`; }).join('') + '</div>' : '';
  const titulo = (FILTRO.cuarto !== 'todos' ? nombreCuarto(FILTRO.cuarto) : FILTRO.nivel === 'todos' ? 'All' : FILTRO.nivel === 'sin' ? 'No level' : nombreNivel(FILTRO.nivel)) + ' Photos';
  const fs = ordenarFotos(filtrarFotos(todas, FILTRO), ORDEN);
  const d = destinoActual();
  const destino = (T.estado === 'archivado' ? '' : `<p class="pdestino">${IC('pin')}New photos go to: <b>${esc(nombreDestino(d))}</b></p>`);
  const tarjeta = (f) => fotoCardHtml(f, URLS[f.id], etiquetaFoto(f, CUARTOS, NIVELES), SEL.has(f.id));
  let cuerpo;
  if(!todas.length) cuerpo = '<div class="vacio-fotos">' + IC('camara') + '<div><b>No photos in this project yet.</b><br>Tap Upload Photos, or the blue camera button to take several in a row.</div></div>';
  else if(!fs.length) cuerpo = '<p class="vacio">No photos here yet.</p>';
  else if(POR_CUARTO) cuerpo = agruparPorCuarto(fs, CUARTOS.filter(x => FILTRO.nivel === 'todos' || x.nivel_id === FILTRO.nivel)).map(g => `<section class="pgrupo"><h4>${esc(g.titulo)} <span class="n">${g.fotos.length}</span></h4><div class="pgrid ${VISTA}">${g.fotos.map(tarjeta).join('')}</div></section>`).join('');
  else cuerpo = `<div class="pgrid ${VISTA}">${fs.map(tarjeta).join('')}</div>`;
  const barraSel = MODO_SEL ? `<div class="psel-barra"><b>${SEL.size} selected</b><button type="button" class="btn btn-outline btn-chico" data-sel-accion="mover"${SEL.size ? '' : ' disabled'}>${IC('carpeta')}Move to room</button><button type="button" class="btn btn-outline btn-chico btn-rojo" data-sel-accion="papelera"${SEL.size ? '' : ' disabled'}>${IC('archivo')}Delete</button></div>` : '';
  caja.classList.toggle('pmodo-sel', MODO_SEL);
  caja.innerHTML = destino + fotos.tandaHtml() + herr + porNivel + barraSel +
    `<div class="sec-cab ptitulo"><h2 class="sec-t">${esc(titulo)} (${fs.length})</h2>${fs.length ? `<button type="button" class="ver-cuarto" id="btnPorCuarto">${POR_CUARTO ? 'View by Date' : 'View by Room'}${IC('chev-der')}</button>` : ''}</div>` + cuerpo;
  if(TAB === 'cuartos') pintarCuartos();
}

// ---------- Notes, Activity, y las que vienen después ----------
function pintarNotas(){
  const caja = $('#panel-notas'); if(!caja || !T) return;
  if(caja.dataset.para === T.id && caja.querySelector('textarea')) return;   // no pisar lo que está escribiendo
  caja.dataset.para = T.id;
  caja.innerHTML = `<div class="card pnotas"><label for="pNotasTxt"><b>Project notes</b></label><textarea id="pNotasTxt" placeholder="Anything the team should know about this project…">${esc(T.notas || '')}</textarea>
    <div class="fila-botones"><button type="button" class="btn btn-accent" id="btnNotasGuardar">Save notes</button></div><p class="aviso" id="notasAviso"></p></div>`;
}
function pintarActividad(){
  const caja = $('#panel-actividad'); if(!caja || !T) return;
  const items = actividad(fotos.lista(), T, fotos.nombreDe, CUARTOS, NIVELES).concat(actividadDetalles(detalles.tareas(), detalles.comentarios(), fotos.nombreDe)).sort((a, b) => b.cuando - a.cuando);
  caja.innerHTML = items.length ? '<div class="pact">' + items.map(x => `<div class="pact-fila"><span class="pact-punto"></span><div><b>${esc(x.texto)}</b><small>${esc(fechaHora(new Date(x.cuando).toISOString()))}</small></div></div>`).join('') + '</div>' : '<p class="vacio">No activity yet.</p>';
}
function pintarPronto(){
  [['medidas', 'Measurements', 'Room measurements will live here. This tab is built next, from your design.'], ['documentos', 'Documents', 'Estimates, reports and PDFs for this project will live here. This tab is built next, from your design.']].forEach(([k, t, x]) => {
    const caja = $('#panel-' + k); if(caja && !caja.innerHTML) caja.innerHTML = `<div class="pronto pronto-tab"><span class="pronto-ic">${IC(k === 'medidas' ? 'cubo' : 'doc')}</span><h2 class="titulo chico">${t}</h2><p>${x}</p></div>`;
  });
}

// ---------- escoger un cuarto (mover fotos o la cámara) ----------
let AL_ESCOGER = null;
// Escoger nivel/cuarto (mover fotos o la cámara). Aquí mismo se crean el nivel y el cuarto si todavía no existen.
let ESC_TITULO = '', ESC_ACTUAL = null, ESC_ABRIR = '';
export function escogerCuarto(titulo, actual, fn){
  AL_ESCOGER = fn; ESC_TITULO = titulo; ESC_ACTUAL = actual || null; ESC_ABRIR = '';
  pintarEscoger();
  $('#hojaCuarto').hidden = false;
}
function pintarEscoger(){
  $('#cuartoTitulo').textContent = ESC_TITULO;
  const actual = ESC_ACTUAL;
  const marca = (d) => (actual && (actual.cuarto_id || null) === (d.cuarto_id || null) && (actual.nivel_id || null) === (d.nivel_id || null)) ? ' on' : '';
  const op = (d, txt, sub, ic) => `<button type="button" class="cap-fila cuarto-op${marca(d)}" data-escoger='${esc(JSON.stringify(d))}'><span class="cap-foto">${IC(ic)}</span><span class="cap-texto"><b>${esc(txt)}</b>${sub ? '<small>' + esc(sub) + '</small>' : ''}</span></button>`;
  const tipos = (nid) => '<div class="chips envolver cuarto-nuevo">' + TIPOS_CUARTO.map(r => `<button type="button" class="chip" data-crear-cuarto="${esc(nid)}" data-tipo="${esc(r)}">${esc(r)}</button>`).join('') + '</div>';
  const usados = new Set(NIVELES.map(x => x.nombre));
  const rapidos = '<div class="chips envolver cuarto-nuevo">' + NIVELES_RAPIDOS.filter(r => !usados.has(r) || r === 'Other').map(r => `<button type="button" class="chip" data-crear-nivel="${esc(r)}">${esc(r)}</button>`).join('') + '</div>';
  const niveles = NIVELES.map(n => '<h4 class="cuarto-nivel">' + esc(n.nombre) + '</h4>' + cuartosDe(n.id).map(c => op({ nivel_id:n.id, cuarto_id:c.id }, c.nombre, n.nombre, 'casa')).join('') + op({ nivel_id:n.id }, 'Whole ' + n.nombre, 'No specific room', 'cubo') +
      (ESC_ABRIR === n.id ? '<p class="cuarto-ayuda">Pick the new room:</p>' + tipos(n.id) : `<button type="button" class="pdet-link cuarto-agregar" data-abrir-tipos="${esc(n.id)}">${IC('mas')}Add room to ${esc(n.nombre)}</button>`)).join('');
  $('#cuartoLista').innerHTML = (NIVELES.length ? niveles : '<p class="cuarto-ayuda">This project has no levels yet. Tap one to add it:</p>' + rapidos) +
    (NIVELES.length ? (ESC_ABRIR === '+nivel' ? '<h4 class="cuarto-nivel">New level</h4>' + rapidos : `<button type="button" class="pdet-link cuarto-agregar cuarto-nivel-nuevo" data-abrir-tipos="+nivel">${IC('mas')}Add level</button>`) : '') +
    '<h4 class="cuarto-nivel">Other</h4>' + op({}, 'No room', 'Keep it without a room', 'archivo') + '<p class="aviso" id="cuartoHojaAviso"></p>';
}
async function crearNivel(nombre){
  const r = await authFetch('/rest/v1/fotos_niveles', { method:'POST', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ trabajo_id: T.id, nombre, orden: NIVELES.length }) });
  if(!r.ok) throw new Error(r.status === 404 ? 'falta correr sql/fotos-04-niveles.sql' : 'HTTP ' + r.status);
  const fila = (await r.json())[0]; if(!fila) throw new Error('the database did not return the level');
  NIVELES.push(fila); pintarTodo(); return fila;
}
async function crearCuarto(nivel_id, nombre, tipo){
  const r = await authFetch('/rest/v1/fotos_cuartos', { method:'POST', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ trabajo_id: T.id, nivel_id, nombre, tipo: tipo || null, orden: cuartosDe(nivel_id).length }) });
  if(!r.ok) throw new Error(r.status === 404 ? 'falta correr sql/fotos-04-niveles.sql' : 'HTTP ' + r.status);
  const fila = (await r.json())[0]; if(!fila) throw new Error('the database did not return the room');
  CUARTOS.push(fila); pintarTodo(); return fila;
}
function cerrarEscoger(){ $('#hojaCuarto').hidden = true; AL_ESCOGER = null; }

// ---------- formas: nivel y cuarto ----------
function abrirFormaNivel(n){
  EDIT_NIVEL = n || null;
  $('#nivelTitulo').textContent = n ? 'Edit Level' : 'Add Level';
  $('#nNombre').value = n ? n.nombre : ''; $('#nDesc').value = n ? (n.descripcion || '') : ''; $('#nivelAviso').textContent = '';
  const usados = new Set(NIVELES.map(x => x.nombre));
  $('#nRapidos').innerHTML = NIVELES_RAPIDOS.map(r => `<button type="button" class="chip${n && n.nombre === r ? ' on' : ''}${!n && usados.has(r) ? ' usado' : ''}" data-rapido="${esc(r)}">${esc(r)}</button>`).join('');
  irA('pNivel', 'pTrabajo');
}
function abrirFormaCuarto(c, nivelId){
  EDIT_CUARTO = c || null;
  $('#cuartoFormaTitulo').textContent = c ? 'Edit Room' : 'Add Room';
  $('#cNombre').value = c ? c.nombre : ''; $('#cNotas').value = c ? (c.notas || '') : ''; $('#cuartoAviso').textContent = '';
  $('#cNivel').innerHTML = NIVELES.map(n => `<option value="${esc(n.id)}">${esc(n.nombre)}</option>`).join('');
  $('#cNivel').value = c ? c.nivel_id : (nivelId || NIVEL_CUARTOS || (NIVELES[0] || {}).id || '');
  $('#cTipos').innerHTML = TIPOS_CUARTO.map(r => `<button type="button" class="chip${c && c.tipo === r ? ' on' : ''}" data-tipo-cuarto="${esc(r)}">${esc(r)}</button>`).join('');
  $('#cuartoAviso').classList.remove('ok');
  $('#btnCuartoListo').hidden = !!c;
  pintarHechos();
  irA('pCuarto', 'pTrabajo');
  if(!c) setTimeout(() => { const n = $('#cNombre'); if(n) n.focus(); }, 60);
}
// Los cuartos que ya tiene el nivel escogido (para ver lo que se lleva agregado sin salir de la página).
function pintarHechos(){
  const caja = $('#cHechos'); if(!caja) return;
  const cs = cuartosDe($('#cNivel').value).filter(x => !EDIT_CUARTO || x.id !== EDIT_CUARTO.id);
  caja.innerHTML = cs.length ? '<small>Already in this level:</small>' + cs.map(x => `<span class="c-hecho">${IC('check')}${esc(x.nombre)}</span>`).join('') : '<small>No rooms in this level yet.</small>';
}
// "Bedroom" ya existe en el nivel -> "Bedroom 2".
export function nombreLibre(base, existentes){
  const usados = new Set((existentes || []).map(x => String(x).trim().toLowerCase()));
  if(!usados.has(base.toLowerCase())) return base;
  for(let i = 2; i < 100; i++){ const n = base + ' ' + i; if(!usados.has(n.toLowerCase())) return n; }
  return base;
}
async function guardarNivel(){
  const nombre = $('#nNombre').value.trim(), desc = $('#nDesc').value.trim(); const av = $('#nivelAviso');
  if(!nombre){ av.textContent = 'Write the level name or pick one.'; return; }
  const b = $('#btnNivelGuardar'); b.disabled = true;
  try{
    const r = EDIT_NIVEL
      ? await authFetch('/rest/v1/fotos_niveles?id=eq.' + encodeURIComponent(EDIT_NIVEL.id), { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ nombre, descripcion: desc || null }) })
      : await authFetch('/rest/v1/fotos_niveles', { method:'POST', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ trabajo_id: T.id, nombre, descripcion: desc || null, orden: NIVELES.length }) });
    if(!r.ok) throw new Error(r.status === 404 ? 'falta correr sql/fotos-04-niveles.sql' : 'HTTP ' + r.status + ' ' + (await r.text()).slice(0, 160));
    const fila = (await r.json())[0]; if(!fila) throw new Error('the database did not return the level');
    if(EDIT_NIVEL){ const i = NIVELES.findIndex(x => x.id === fila.id); if(i >= 0) NIVELES[i] = fila; } else NIVELES.push(fila);
    SUBTAB = 'niveles'; atras(); irTab('cuartos');
  }catch(e){ av.textContent = 'Could not save. ' + String(e && e.message || e); }
  b.disabled = false;
}
async function guardarCuarto(){
  const nombre = $('#cNombre').value.trim(), nivel_id = $('#cNivel').value, notas = $('#cNotas').value.trim(); const av = $('#cuartoAviso');
  const chipOn = $('#cTipos .chip.on'); const tipo = chipOn ? chipOn.dataset.tipoCuarto : null;
  if(!nombre){ av.textContent = 'Write the room name or pick a type.'; return; }
  if(!nivel_id){ av.textContent = 'Add a level first.'; return; }
  av.classList.remove('ok');
  const b = $('#btnCuartoGuardar'); b.disabled = true;
  try{
    const cuerpo = { nombre, nivel_id, tipo: tipo || null, notas: notas || null };
    const r = EDIT_CUARTO
      ? await authFetch('/rest/v1/fotos_cuartos?id=eq.' + encodeURIComponent(EDIT_CUARTO.id), { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify(cuerpo) })
      : await authFetch('/rest/v1/fotos_cuartos', { method:'POST', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ ...cuerpo, trabajo_id: T.id, orden: cuartosDe(nivel_id).length }) });
    if(!r.ok) throw new Error(r.status === 404 ? 'falta correr sql/fotos-04-niveles.sql' : 'HTTP ' + r.status + ' ' + (await r.text()).slice(0, 160));
    const fila = (await r.json())[0]; if(!fila) throw new Error('the database did not return the room');
    if(EDIT_CUARTO){ const i = CUARTOS.findIndex(x => x.id === fila.id); if(i >= 0) CUARTOS[i] = fila; } else CUARTOS.push(fila);
    NIVEL_CUARTOS = fila.nivel_id; SUBTAB = 'cuartos';
    if(EDIT_CUARTO){ atras(); irTab('cuartos'); }
    else {
      // Se queda en la página: mismo nivel, campos limpios, para agregar el siguiente cuarto.
      pintarTodo();
      $('#cNombre').value = ''; $('#cNotas').value = ''; $$('#cTipos .chip').forEach(x => x.classList.remove('on'));
      av.classList.add('ok'); av.textContent = '✓ ' + fila.nombre + ' added to ' + nombreNivel(fila.nivel_id) + '. Add another room, or tap Done.';
      pintarHechos(); $('#cNombre').focus();
    }
  }catch(e){ av.textContent = 'Could not save. ' + String(e && e.message || e); }
  b.disabled = false;
}
async function borrarNivel(n){
  const cs = cuartosDe(n.id);
  if(!confirm('Delete ' + n.nombre + (cs.length ? ' and its ' + cs.length + (cs.length === 1 ? ' room' : ' rooms') : '') + '? Photos stay in the project, without a room.')) return;
  const r = await authFetch('/rest/v1/fotos_niveles?id=eq.' + encodeURIComponent(n.id), { method:'DELETE', headers:{ Prefer:'return=representation' } });
  const filas = r.ok ? await r.json() : [];
  if(!filas.length){ aviso('Could not delete it (only the manager or who created it can).'); return; }
  NIVELES = NIVELES.filter(x => x.id !== n.id); CUARTOS = CUARTOS.filter(x => x.nivel_id !== n.id);
  fotos.lista().forEach(f => { if(f.nivel_id === n.id){ f.nivel_id = null; f.cuarto_id = null; } });
  if(FILTRO.nivel === n.id) FILTRO = { nivel:'todos', cuarto:'todos' };
  pintarTodo();
}
async function borrarCuarto(c){
  if(!confirm('Delete ' + c.nombre + '? Its photos stay in the project, in the level.')) return;
  const r = await authFetch('/rest/v1/fotos_cuartos?id=eq.' + encodeURIComponent(c.id), { method:'DELETE', headers:{ Prefer:'return=representation' } });
  const filas = r.ok ? await r.json() : [];
  if(!filas.length){ aviso('Could not delete it (only the manager or who created it can).'); return; }
  CUARTOS = CUARTOS.filter(x => x.id !== c.id);
  fotos.lista().forEach(f => { if(f.cuarto_id === c.id) f.cuarto_id = null; });
  if(FILTRO.cuarto === c.id) FILTRO.cuarto = 'todos';
  pintarTodo();
}
async function mover(ids){
  escogerCuarto(ids.length === 1 ? 'Move photo to…' : 'Move ' + ids.length + ' photos to…', null, async (d) => {
    try{ const n = await fotos.moverFotos(ids, d); aviso(n < ids.length ? 'Moved ' + n + ' of ' + ids.length + '. Only the manager can move photos someone else took.' : ''); }
    catch(e){ aviso('Could not move them. ' + String(e && e.message || e)); }
    MODO_SEL = false; SEL.clear(); pintarFotos();
  });
}
async function papelera(ids){
  if(!confirm('Move ' + (ids.length === 1 ? 'this photo' : ids.length + ' photos') + ' to the trash? The manager can recover them.')) return;
  try{ const n = await fotos.papeleraFotos(ids); aviso(n < ids.length ? 'Deleted ' + n + ' of ' + ids.length + '. Only the manager can delete photos someone else took.' : ''); }
  catch(e){ aviso('Could not delete them. ' + String(e && e.message || e)); }
  MODO_SEL = false; SEL.clear(); pintarFotos();
}
function bajarFoto(id){ fotos.urlsFirmadas([id], 'web').then(u => { if(u[id]) window.open(u[id], '_blank', 'noopener'); }); }

// ---------- Edit Labels (hoja) ----------
let ETQ_EDIT = [], ETQ_COLOR = 'verde';
function abrirEtiquetas(){
  if(!T) return; ETQ_EDIT = etiquetasDe(T).map(x => ({ ...x })); ETQ_COLOR = 'verde';
  $('#detHojaTitulo').textContent = 'Edit Labels';
  pintarEtiquetas(); $('#detHoja').hidden = false;
}
function pintarEtiquetas(guardarTexto){
  const txt = guardarTexto && $('#etqTxt') ? $('#etqTxt').value : '';
  const sug = sugerenciasEtq(trabajos.datos().LISTA, ETQ_EDIT);
  $('#detHojaCuerpo').innerHTML = `<div class="etq-lista">${ETQ_EDIT.length ? ETQ_EDIT.map((x, i) => `<span class="etq-c c-${esc(x.c)}">${esc(x.t)}<button type="button" data-etq-quitar="${i}" aria-label="Remove ${esc(x.t)}">✕</button></span>`).join('') : '<span class="pdet-vacio">No labels yet.</span>'}</div>
    ${sug.length ? '<h4 class="etq-sub">Used in other projects</h4><div class="etq-lista">' + sug.map(x => `<button type="button" class="etq-c c-${esc(x.c)} etq-sug" data-etq-sug='${esc(JSON.stringify(x))}'>+ ${esc(x.t)}</button>`).join('') + '</div>' : ''}
    <h4 class="etq-sub">New label</h4>
    <div class="etq-nueva"><input type="text" id="etqTxt" maxlength="40" placeholder="Flood Doctor Contract" value="${esc(txt)}"><button type="button" class="btn btn-outline btn-chico" data-etq-agregar>Add</button></div>
    <div class="etq-colores">${Object.keys(ETQ_COLORES).map(k => `<button type="button" class="etq-color c-${k}${ETQ_COLOR === k ? ' on' : ''}" data-etq-color="${k}" aria-label="${k}"></button>`).join('')}</div>
    <button type="button" class="btn btn-accent btn-block" data-etq-guardar>Save Labels</button><p class="aviso" id="detHojaAviso"></p>`;
}
function agregarEtiqueta(){
  const v = ($('#etqTxt').value || '').trim().slice(0, 40); if(!v) return;
  if(ETQ_EDIT.some(x => x.t.toLowerCase() === v.toLowerCase())){ $('#detHojaAviso').textContent = 'That label is already on the project.'; return; }
  ETQ_EDIT.push({ t: v, c: ETQ_COLOR }); pintarEtiquetas(); const i = $('#etqTxt'); if(i) i.focus();
}
async function guardarEtiquetas(){
  const pend = ($('#etqTxt') && $('#etqTxt').value || '').trim(); if(pend) agregarEtiqueta();
  const b = $('[data-etq-guardar]'); if(b) b.disabled = true;
  const r = await authFetch('/rest/v1/fotos_trabajos?id=eq.' + encodeURIComponent(T.id), { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ etiquetas: ETQ_EDIT, updated_at: new Date().toISOString() }) });
  const f = r.ok ? await r.json() : [];
  if(!f.length){ const av = $('#detHojaAviso'); if(av) av.textContent = r.status === 400 ? 'Labels are not installed on the server yet (falta correr sql/fotos-05-detalles.sql).' : 'Could not save (only the manager or who created the project can).'; if(b) b.disabled = false; return; }
  T = f[0]; trabajos.reemplazar(T); detalles.actualizarTrabajo(T);
  const e = $('#trabajoFicha .pcab-etqs'); if(e) e.innerHTML = etiquetasHtml(T) + `<button type="button" class="enlace-editar solo-compu" data-editar-etq>${IC('lapiz')}Edit Labels</button>`;
  $('#detHoja').hidden = true;
}

export function conectar(){
  trabajos.usarFicha(abrir);
  detalles.usarNombres(fotos.nombreDe, fotos.cargarNombres);
  detalles.alCambiar(() => { if(T) pintarActividad(); });
  detalles.conectar();
  camara.usarCuartos({ hay: (id) => !!(T && T.id === id), destino: destinoActual, nombre: nombreDestino, escoger: escogerCuarto });
  fotos.alPintar(pintarFotos);
  fotos.usarDestino(destinoActual);
  fotos.usarOrdenVisor(ordenVisible);
  fotos.usarEtiqueta((f) => etiquetaFoto(f, CUARTOS, NIVELES));
  fotos.alClicFoto((id) => { if(!MODO_SEL) return false; if(SEL.has(id)) SEL.delete(id); else SEL.add(id); pintarFotos(); return true; });
  document.addEventListener('click', (e) => {
    if(!$('#pTrabajo') || ($('#pTrabajo').hidden && $('#hojaCuarto').hidden && $('#detHoja').hidden)) return;
    const q = (s) => e.target.closest(s);
    let el;
    if((el = q('[data-ptab]'))){ irTab(el.dataset.ptab); return; }
    if((el = q('[data-subtab]'))){ SUBTAB = el.dataset.subtab; pintarCuartos(); return; }
    if(q('[data-nuevo-nivel]')){ abrirFormaNivel(null); return; }
    if(q('[data-nuevo-cuarto]')){ abrirFormaCuarto(null, NIVEL_CUARTOS); return; }
    if((el = q('[data-nivel-menu]'))){ e.stopPropagation(); const n = NIVELES.find(x => x.id === el.dataset.nivelMenu); if(!n) return;
      panel.abrirMenuEn(el, `<button type="button" data-p-accion="nivel-cuartos" data-id="${esc(n.id)}">${IC('casa')}See rooms</button><button type="button" data-p-accion="nivel-editar" data-id="${esc(n.id)}">${IC('lapiz')}Edit level</button><button type="button" class="rojo" data-p-accion="nivel-borrar" data-id="${esc(n.id)}">${IC('archivo')}Delete level</button>`); return; }
    if((el = q('[data-cuarto-menu]'))){ e.stopPropagation(); const c = CUARTOS.find(x => x.id === el.dataset.cuartoMenu); if(!c) return;
      panel.abrirMenuEn(el, `<button type="button" data-p-accion="cuarto-fotos" data-id="${esc(c.id)}">${IC('galeria')}See photos</button><button type="button" data-p-accion="cuarto-editar" data-id="${esc(c.id)}">${IC('lapiz')}Edit room</button><button type="button" class="rojo" data-p-accion="cuarto-borrar" data-id="${esc(c.id)}">${IC('archivo')}Delete room</button>`); return; }
    if((el = q('[data-foto-menu]'))){ e.stopPropagation(); const id = el.dataset.fotoMenu;
      panel.abrirMenuEn(el, `<button type="button" data-p-accion="foto-mover" data-id="${esc(id)}">${IC('carpeta')}Move to room</button><button type="button" data-p-accion="foto-bajar" data-id="${esc(id)}">${IC('galeria')}Open full size</button><button type="button" class="rojo" data-p-accion="foto-papelera" data-id="${esc(id)}">${IC('archivo')}Delete</button>`); return; }
    if(q('#btnFichaMenu')){ e.stopPropagation(); const t = T; const dig = trabajos.telDigitos(t.telefono);
      panel.abrirMenuEn(q('#btnFichaMenu'), `<button type="button" data-p-accion="detalles">${IC('doc')}Project details</button><button type="button" data-p-accion="etiquetas">${IC('etiqueta')}Edit labels</button><button type="button" data-p-accion="editar">${IC('lapiz')}Edit project</button>${dig ? `<button type="button" data-p-accion="llamar">${IC('tel')}Call</button><button type="button" data-p-accion="mensaje">${IC('msj')}Message</button>` : ''}<button type="button" data-p-accion="mapa">${IC('pin')}Open in Maps</button>${esManager() ? `<button type="button" data-p-accion="archivar" class="${t.estado === 'archivado' ? '' : 'rojo'}">${IC('archivo')}${t.estado === 'archivado' ? 'Reactivate' : 'Archive'}</button>` : ''}`); return; }
    if((el = q('[data-p-accion]'))){
      const a = el.dataset.pAccion, id = el.dataset.id; panel.cerrarMenu();
      if(a === 'nivel-cuartos'){ NIVEL_CUARTOS = id; SUBTAB = 'cuartos'; pintarCuartos(); }
      else if(a === 'nivel-editar') abrirFormaNivel(NIVELES.find(x => x.id === id));
      else if(a === 'nivel-borrar') borrarNivel(NIVELES.find(x => x.id === id));
      else if(a === 'cuarto-fotos'){ const c = CUARTOS.find(x => x.id === id); if(c){ FILTRO = { nivel:c.nivel_id, cuarto:c.id }; irTab('fotos'); } }
      else if(a === 'cuarto-editar') abrirFormaCuarto(CUARTOS.find(x => x.id === id));
      else if(a === 'cuarto-borrar') borrarCuarto(CUARTOS.find(x => x.id === id));
      else if(a === 'foto-camara') camara.abrir(T);
      else if(a === 'foto-carrete'){ const inp = $('#fotosPanel input[data-subir]'); if(inp) inp.click(); }
      else if(a === 'foto-mover') mover([id]);
      else if(a === 'foto-bajar') bajarFoto(id);
      else if(a === 'foto-papelera') papelera([id]);
      else if(a === 'editar') trabajos.editar(T, 'pTrabajo');
      else if(a === 'detalles') detalles.abrirPanel();
      else if(a === 'etiquetas') abrirEtiquetas();
      else if(a === 'llamar') location.href = 'tel:' + trabajos.telDigitos(T.telefono);
      else if(a === 'mensaje') location.href = 'sms:' + trabajos.telDigitos(T.telefono);
      else if(a === 'mapa') window.open(trabajos.mapsUrl(T.direccion), '_blank', 'noopener');
      else if(a === 'archivar') trabajos.archivarTrabajo(T, true);
      return;
    }
    if((el = q('[data-subir-menu]'))){ e.stopPropagation();
      panel.abrirMenuEn(el, `<button type="button" data-p-accion="foto-camara">${IC('camara')}<span>Take Photos<small class="menu-sub">Choose level & room · many in a row</small></span></button><button type="button" data-p-accion="foto-carrete">${IC('galeria')}From Library</button>`); return; }
    if(q('#btnEditar')){ trabajos.editar(T, 'pTrabajo'); return; }
    if(q('[data-editar-etq]')){ abrirEtiquetas(); return; }
    if((el = q('[data-etq-quitar]'))){ ETQ_EDIT.splice(Number(el.dataset.etqQuitar), 1); pintarEtiquetas(); return; }
    if((el = q('[data-etq-sug]'))){ const x = JSON.parse(el.dataset.etqSug); ETQ_EDIT.push(x); pintarEtiquetas(); return; }
    if((el = q('[data-etq-color]'))){ ETQ_COLOR = el.dataset.etqColor; pintarEtiquetas(true); return; }
    if(q('[data-etq-agregar]')){ agregarEtiqueta(); return; }
    if(q('[data-etq-guardar]')){ guardarEtiquetas(); return; }
    if((el = q('[data-ver-nivel]')) && !q('.mas-btn')){ NIVEL_CUARTOS = el.dataset.verNivel; SUBTAB = 'cuartos'; pintarCuartos(); return; }
    if((el = q('[data-ver-cuarto]')) && !q('.mas-btn')){ const c = CUARTOS.find(x => x.id === el.dataset.verCuarto); if(c){ FILTRO = { nivel:c.nivel_id, cuarto:c.id }; irTab('fotos'); } return; }
    if((el = q('[data-filtro-nivel]'))){ FILTRO = { nivel: el.dataset.filtroNivel, cuarto:'todos' }; pintarFotos(); return; }
    if((el = q('[data-vista]'))){ VISTA = el.dataset.vista; pintarFotos(); return; }
    if(q('#btnPorCuarto')){ POR_CUARTO = !POR_CUARTO; pintarFotos(); return; }
    if(q('#btnSeleccionar')){ MODO_SEL = !MODO_SEL; SEL.clear(); pintarFotos(); return; }
    if((el = q('[data-sel-accion]'))){ const ids = [...SEL]; if(el.dataset.selAccion === 'mover') mover(ids); else papelera(ids); return; }
    if((el = q('[data-abrir-tipos]'))){ ESC_ABRIR = ESC_ABRIR === el.dataset.abrirTipos ? '' : el.dataset.abrirTipos; pintarEscoger(); return; }
    if((el = q('[data-crear-nivel]'))){ let nombre = el.dataset.crearNivel;
      if(nombre === 'Other'){ nombre = (prompt('Level name') || '').trim(); if(!nombre) return; }
      el.disabled = true;
      crearNivel(nombre).then(n => { ESC_ABRIR = n.id; pintarEscoger(); }).catch(err => { el.disabled = false; const a = $('#cuartoHojaAviso'); if(a) a.textContent = 'Could not add the level. ' + String(err && err.message || err); });
      return; }
    if((el = q('[data-crear-cuarto]'))){ const nid = el.dataset.crearCuarto, tipo = el.dataset.tipo;
      let nombre = tipo === 'Other' ? (prompt('Room name') || '').trim() : nombreLibre(tipo, cuartosDe(nid).map(x => x.nombre));
      if(!nombre) return;
      el.disabled = true;
      crearCuarto(nid, nombre, tipo).then(c => { const fn = AL_ESCOGER; cerrarEscoger(); if(fn) fn({ nivel_id: c.nivel_id, cuarto_id: c.id }); })
        .catch(err => { el.disabled = false; const a = $('#cuartoHojaAviso'); if(a) a.textContent = 'Could not add the room. ' + String(err && err.message || err); });
      return; }
    if((el = q('[data-escoger]'))){ const d = JSON.parse(el.dataset.escoger); const fn = AL_ESCOGER; cerrarEscoger(); if(fn) fn(d); return; }
    if(q('[data-cerrar-cuarto]') || e.target.id === 'hojaCuarto'){ cerrarEscoger(); return; }
  });
  document.addEventListener('change', (e) => {
    if(e.target.id === 'selCuartoFotos'){ FILTRO.cuarto = e.target.value; pintarFotos(); }
    else if(e.target.id === 'selNivelFotos'){ FILTRO = { nivel: e.target.value, cuarto:'todos' }; pintarFotos(); }
    else if(e.target.id === 'selOrdenFotos'){ ORDEN = e.target.value; pintarFotos(); }
    else if(e.target.id === 'selNivelCuartos'){ NIVEL_CUARTOS = e.target.value; pintarCuartos(); }
  });
  // formas
  $('#btnNivelGuardar').addEventListener('click', guardarNivel);
  $('#btnCuartoGuardar').addEventListener('click', guardarCuarto);
  $('#nRapidos').addEventListener('click', (e) => { const b = e.target.closest('[data-rapido]'); if(!b) return; $('#nNombre').value = b.dataset.rapido; $$('#nRapidos .chip').forEach(x => x.classList.toggle('on', x === b)); });
  $('#cTipos').addEventListener('click', (e) => { const b = e.target.closest('[data-tipo-cuarto]'); if(!b) return; const ya = b.classList.contains('on'); $$('#cTipos .chip').forEach(x => x.classList.remove('on')); if(!ya){ b.classList.add('on'); const n = $('#cNombre'); const tipos = new Set(TIPOS_CUARTO); if(!n.value.trim() || tipos.has(n.value.trim()) || /^(.+) \d+$/.test(n.value.trim()) && tipos.has(n.value.trim().replace(/ \d+$/, ''))) n.value = b.dataset.tipoCuarto === 'Other' ? '' : nombreLibre(b.dataset.tipoCuarto, cuartosDe($('#cNivel').value).filter(x => !EDIT_CUARTO || x.id !== EDIT_CUARTO.id).map(x => x.nombre)); } });
  $('#cNivel').addEventListener('change', () => { pintarHechos(); $('#cuartoAviso').textContent = ''; });
  $('#btnCuartoListo').addEventListener('click', () => { atras(); irTab('cuartos'); });
  document.addEventListener('click', async (e) => {
    if(!e.target.closest('#btnNotasGuardar') || !T) return;
    const txt = $('#pNotasTxt').value.trim(); const av = $('#notasAviso'); av.classList.remove('ok'); av.textContent = '';
    const r = await authFetch('/rest/v1/fotos_trabajos?id=eq.' + encodeURIComponent(T.id), { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ notas: txt || null, updated_at: new Date().toISOString() }) });
    const filas = r.ok ? await r.json() : [];
    if(filas.length){ T.notas = filas[0].notas; av.classList.add('ok'); av.textContent = 'Saved.'; } else av.textContent = 'Could not save (only the manager or who created the project can).';
  });
}
