// Scanova360 · pestaña Floor Plan (su diseño del 13-oct). El plano se escanea con el LiDAR del iPhone
// (el mismo escáner de Field Reports, que ya viene dentro de la app: plugin RoomScan) y se dibuja con el
// mismo código de Field Reports (plano.js, copiado por tools/extraer_plano.py). Un escaneo por piso;
// un escaneo nuevo no borra el anterior (queda de historial), se ve el más reciente.
import * as plano from './plano.js?v=2026-10-15-7';
import { authFetch, esAparato } from './app.js?v=2026-10-15-7';

const $ = (s, r = document) => r.querySelector(s);
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
const IC = (n, cls) => '<svg class="ic' + (cls ? ' ' + cls : '') + '"><use href="#i-' + n + '"/></svg>';
const SIN_NIVEL = 'sin';
const PLANTAS = ['Basement', '1st Floor', '2nd Floor', '3rd Floor', 'Attic'];

let T = null, NIVELES = [], PLANOS = [], NIV_SEL = null, VISTA = '2d', REJILLA = true, ZOOM = 1, CARGADO = '', AVISO = '', AVISO_OK = false, OCUPADO = false, AL_NIVEL = null, MENU = false;
const PZ = { s: 1, x: 0, y: 0 }, PZ_GRANDE = { s: 1, x: 0, y: 0 };   // acercamiento con los dedos (teléfono)

// ---------- puras (para las pruebas) ----------
export const fmtPies = (n) => (Math.round(Number(n) || 0)).toLocaleString('en-US');
// El nivel que se dibuja de este plano: el que trae marcado (un escaneo con dos niveles se guarda partido, una
// fila por nivel) o el primero. El resumen cuenta SOLO ese nivel: antes el dibujo enseñaba el primero y el total
// sumaba todos.
export function nivelDelPlano(data){
  if(data && data._nivel != null) return data._nivel;
  const lv = plano.floorplanLevels(data); return lv && lv.length ? lv[0] : 1;
}
export function resumenPlano(data){
  data = prepararPlano(data);
  const nivel = nivelDelPlano(data), enNivel = r => (r.level || 1) === nivel;
  const rooms = ((data && data.rooms) || []).filter(r => !r.deleted && (r.walls || []).length && enNivel(r));
  if(!rooms.length) return { area: 0, cuartos: 0, murosExt: 0, techo: 0 };
  const m = plano.fpPlanMeasurements(data, enNivel);
  // Paredes exteriores: los tramos que caen en la misma línea se juntan (dos cuartos con copia de la misma pared
  // exterior la contaban dos veces) y las paredes ajenas no cuentan.
  const tramos = [];
  rooms.forEach(r => (r.walls || []).forEach(w => { if(w && w.start && w.end && !w._ajena && plano.floorplanIsExteriorWall(w, r, data.merged === false ? null : rooms)) tramos.push(w); }));
  const ext = data.merged === false ? tramos.reduce((t, w) => t + Math.hypot(w.end.x - w.start.x, w.end.y - w.start.y), 0) : largoSinRepetir(tramos);
  // La altura que más área cubre (no el promedio: una pared bajita no baja todo el piso), a la pulgada, igual que
  // la hoja (antes se redondeaba a cuartos de pie y Plan Details decía otra cosa que la hoja).
  const peso = {}; rooms.forEach(r => { const x = plano.fpRoomMeasurements(r); const h = Math.round((x.wallHeightFt || 0) * 12) / 12; if(h > 0) peso[h] = (peso[h] || 0) + (x.floorSqFt || 1); });
  const techo = Number(Object.keys(peso).sort((a, b) => peso[b] - peso[a])[0] || 0);
  return { area: Math.round((m.floorSqFt || 0) * 10) / 10, cuartos: m.rooms, murosExt: Math.round(ext), techo };
}
// El largo de varias paredes contando una sola vez lo que se repite en la misma línea (0.5 ft de tolerancia).
export function largoSinRepetir(paredes){
  const grupos = [];
  paredes.forEach(w => {
    const dx = w.end.x - w.start.x, dy = w.end.y - w.start.y, L = Math.hypot(dx, dy);
    if(L < 0.05) return;
    const ux = dx / L, uy = dy / L;
    let g = grupos.find(G => Math.abs(G.ux * ux + G.uy * uy) > 0.996 && Math.abs((w.start.x - G.x0) * -G.uy + (w.start.y - G.y0) * G.ux) < 0.5 && Math.abs((w.end.x - G.x0) * -G.uy + (w.end.y - G.y0) * G.ux) < 0.5);
    if(!g){ g = { ux, uy, x0: w.start.x, y0: w.start.y, tr: [] }; grupos.push(g); }
    const t0 = (w.start.x - g.x0) * g.ux + (w.start.y - g.y0) * g.uy, t1 = (w.end.x - g.x0) * g.ux + (w.end.y - g.y0) * g.uy;
    g.tr.push([Math.min(t0, t1), Math.max(t0, t1)]);
  });
  let total = 0;
  grupos.forEach(g => { g.tr.sort((a, b) => a[0] - b[0]); let [a, b] = g.tr[0]; for(let i = 1; i < g.tr.length; i++){ const [c, d] = g.tr[i]; if(c <= b + 0.5) b = Math.max(b, d); else { total += b - a; a = c; b = d; } } total += b - a; });
  return total;
}
// El plano que se ve de cada piso: el más reciente (la lista viene ordenada del más nuevo al más viejo).
export const planoDe = (planos, nivelId) => (planos || []).find(p => (p.nivel_id || SIN_NIVEL) === (nivelId || SIN_NIVEL)) || null;
// El escaneo sale del iPhone con el ángulo con que se sostuvo el teléfono. Field Reports lo endereza al
// recibirlo (sus pasos, en el mismo orden): girarlo a escuadra, escuadrar paredes, juntar las paredes que son
// la misma, cerrar esquinas chicas. Su queja del 13-oct: "los planos salen de lado". Se hace sobre una copia
// (nunca se toca lo guardado) y se recuerda, así no se repite en cada dibujo.
const sinAcento = (t) => String(t || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z ]+/g, ' ').replace(/\s+/g, ' ').trim();
const ORDENES = ['nuevo cuarto', 'cuarto nuevo', 'otro cuarto', 'siguiente cuarto', 'otro nivel', 'es nuevo', 'el siguiente', 'el que sigue', 'new room', 'next room', 'another room'];
export function esOrdenDeCuarto(nombre){ const k = sinAcento(nombre); return ORDENES.some(o => k === o || k.startsWith(o + ' ') || k.endsWith(' ' + o)); }
const LISTOS = new WeakMap();
export function prepararPlano(data){
  if(!data || typeof data !== 'object') return data;
  if(LISTOS.has(data)) return LISTOS.get(data);
  const d = JSON.parse(JSON.stringify(data));
  // El nombre que el personal dijo (o tocó) al escanear cada cuarto viene en voiceName; Field Reports lo
  // copia a roomName al recibir el escaneo y Scanova no lo hacía, por eso salían "ROOM 1/2" (su pedido del
  // 14-oct). Un nombre puesto después a mano (roomName) siempre gana. En el plano sale EN INGLÉS (13-oct):
  // "Sí, en la cocina" -> Kitchen, con la misma tabla de Field Reports.
  // "Nuevo cuarto"/"Otro cuarto" es la orden de pasar al siguiente, no un nombre: el iPhone lo guardaba como
  // nombre (ya arreglado en el aparato) y esos cuartos se quedan como Room N hasta que les pongan uno.
  (d.rooms || []).forEach(r => { const v = String(r && r.voiceName || '').trim(); if(r && !String(r.roomName || '').trim() && v && !esOrdenDeCuarto(v)){ r.roomName = plano.fpNombreDeCuartoEnIngles(v); r._namedByVoice = true; delete r._labelOffsetPx; } });
  // Clósets, baños chicos y lavandería: los nombra fpReconocerClosets (el mismo código de Field Reports), más abajo.
  try{
    plano.floorplanAlignRooms(d);
    // "Completar escaneo" pega al cuarto lo que se escaneó aparte. En la casa de Harold (14-oct) esa captura
    // vio otro espacio y dejó una caja de 13 x 14 ft encima de la cocina: lo que cae fuera de lo que le
    // faltaba al cuarto se aparta (no se borra), antes de enderezar nada. Mismo código que Field Reports.
    if(!d._handEdited){ plano.fpValidarParches(d); plano.floorplanRectifyWalls(d); plano.floorplanRefineGeometry(d); plano.floorplanCloseCorners(d); }
  }catch(e){ console.warn('enderezar plano', e); }
  // Los cuartos sin acceso que las paredes ya dibujan (clóset del master, laundry): la app los deduce sola y
  // los nombra por su puerta (13-oct, el plano de Harold). Mismo código que Field Reports.
  // RoomPlan le da a cada cuarto también las paredes del de al lado que se ven por una abertura: el Hallway de
  // Harold salía con 88 sq ft encima del Living Room (13-oct). Se le devuelven a su dueño ANTES de deducir cuartos.
  try{ if(!d._handEdited) plano.fpResolverParedesAjenas(d); }catch(e){ console.warn('paredes ajenas', e); }
  try{ if(!d._handEdited) plano.fpAutoCompletarEspacios(d); }catch(e){ console.warn('autocompletar', e); }
  // Clósets y rincones (su pedido, 14-oct): la app los reconoce y los nombra igual que Field Reports.
  try{ plano.floorplanDetectSubAreas(d); }catch(e){ console.warn('closets', e); }
  // Un cuarto que sigue sin nombre (nadie lo dijo ni lo tocó, y no es clóset/baño/lavandería por su lugar) no
  // sale "ROOM 1": toma el que el teléfono le enseñaba (nombresSugeridos, por los muebles), o la sugerencia de
  // Field Reports por sus muebles, o lo que RoomPlan dijo que era. Siempre marcado como sugerido; un nombre dicho o
  // escrito nunca se toca. Sin ninguna pista se queda Room N: no se inventa.
  try{ nombrarSinNombre(d); }catch(e){ console.warn('nombres', e); }
  // Cada fila de Scanova es UNA hoja de UN nivel (la que se dibuja).
  if(d._nivel == null){ const lv = plano.floorplanLevels(d); d._nivel = lv && lv.length ? lv[0] : 1; }
  LISTOS.set(data, d); return d;
}
const DEBILES = ['sofa', 'chair', 'table', 'television', 'storage', 'unknown'];
const SECCIONES_EN = { livingRoom: 'Living Room', kitchen: 'Kitchen', bedroom: 'Bedroom', bathroom: 'Bathroom', diningRoom: 'Dining Room' };
export function nombrarSinNombre(d){
  const sug = (d && d.inspection && d.inspection.nombresSugeridos) || {};
  (d.rooms || []).forEach((r, i) => {
    if(!r || r.deleted || String(r.roomName || '').trim()) return;
    const v = String(r.voiceName || '').trim();
    if(v && !esOrdenDeCuarto(v)) return;
    let nombre = String(sug[String(i)] || '').trim(), conf = 'Medium';
    // La sugerencia por muebles solo si hay un mueble que de verdad dice qué es el cuarto (cama, inodoro, estufa,
    // lavadora…) o dos que coinciden. Un sillón solo no hace sala: se ve por una abertura o se mueve (el Hallway
    // de la casa real tiene un sofá y salía "Living Room").
    if(!nombre){
      const s = plano.suggestFloorplanRoomName(r.objects, r);
      const cats = (r.objects || []).filter(o => o && !o._hidden).map(o => o.category);
      const fuerte = cats.some(c => !DEBILES.includes(c));
      if(s && (s.confidence === 'High' || (fuerte && s.name !== 'Closet'))){ nombre = s.name; conf = s.confidence; }
    }
    if(!nombre){ const lab = ((r._apiProbe && r._apiProbe.sectionLabels) || []).find(x => SECCIONES_EN[x]); if(lab){ nombre = SECCIONES_EN[lab]; conf = 'Low'; } }
    if(nombre){ r.roomName = nombre; r._suggestedConfidence = conf; }
  });
}
// limpia = la vista de la pantalla (solo el plano, su pedido del 13-oct); sin limpia = la hoja completa del PDF/exportar.
export function svgDelPlano(data, trabajo, limpia){
  plano.ponerVista(!!limpia);
  plano.ponerTrabajo({ client: trabajo && trabajo.cliente || '', phone: trabajo && trabajo.telefono || '', address: trabajo && trabajo.direccion || '', date: new Date().toLocaleDateString('en-US', { month:'short', day:'numeric', year:'numeric' }) });
  data = prepararPlano(data);
  // El cliente que sale en la hoja es el del PROYECTO (nombre, teléfono, dirección al día), no la copia que se
  // guardó dentro del escaneo el día que se escaneó (esa no trae teléfono y no se entera si lo corrigen).
  if(data && trabajo && (trabajo.cliente || trabajo.direccion)) data.job = Object.assign({}, data.job || {}, { client: trabajo.cliente || '', phone: trabajo.telefono || '', address: trabajo.direccion || '' });
  const nivel = data ? nivelDelPlano(data) : undefined;
  return data && data.merged === false ? plano.buildFloorplanSvgUnmerged(data, nivel) : plano.buildFloorplanSvg(data, nivel);
}
const fechaEn = (iso) => { const d = new Date(iso); return isNaN(d) ? '' : d.toLocaleDateString('en-US', { month:'short', day:'numeric', year:'numeric' }); };
const pies = (n) => (Number(n) || 0) % 1 ? (Math.round(n * 100) / 100) + ' ft' : (n || 0) + ' ft';

// ---------- datos ----------
async function cargar(){
  const id = T.id; CARGADO = 'cargando';
  try{
    const r = await authFetch('/rest/v1/fotos_planos?trabajo_id=eq.' + encodeURIComponent(id) + '&borrado_at=is.null&select=id,nivel_id,created_at,area_sqft,cuartos,muros_ext_ft,techo_ft,data&order=created_at.desc&limit=60');
    if(!T || T.id !== id) return;
    if(r.status === 404){ PLANOS = []; CARGADO = 'falta-sql'; }
    else if(!r.ok){ PLANOS = []; CARGADO = 'error'; }
    else { PLANOS = await r.json(); CARGADO = id; pintarConteo(pisosConPlano(PLANOS)); }
  }catch(e){ PLANOS = []; CARGADO = 'error'; }
  pintar();
}
// Cuántos pisos tienen plano, para la pestaña ("Floor Plan (2)"). Cada piso cuenta una vez aunque se haya guardado
// varias veces; uno sin piso cuenta como uno. Se pinta al abrir el proyecto (consulta chiquita, sin los planos)
// y cada vez que se cargan o se guardan los planos.
export function pisosConPlano(lista){ return new Set((lista || []).map(p => p.nivel_id || '-')).size; }
function pintarConteo(n){ const s = typeof document !== 'undefined' ? document.getElementById('planoConteo') : null; if(s) s.textContent = n == null ? '' : '(' + n + ')'; }
let CONTEO_PARA = '';
export async function contarPlanos(trabajoId){
  CONTEO_PARA = trabajoId;
  if(CARGADO === trabajoId){ pintarConteo(pisosConPlano(PLANOS)); return; }   // ya están cargados
  pintarConteo(null);
  try{
    const r = await authFetch('/rest/v1/fotos_planos?trabajo_id=eq.' + encodeURIComponent(trabajoId) + '&borrado_at=is.null&select=nivel_id&limit=500');
    if(!r.ok) return;
    const filas = await r.json();
    if(CONTEO_PARA === trabajoId && CARGADO !== trabajoId) pintarConteo(pisosConPlano(filas));   // si ya se cargaron los planos, esos mandan
  }catch(e){}
}
function nivelesConPlanos(){
  const l = NIVELES.map(n => ({ id: n.id, nombre: n.nombre }));
  if(PLANOS.some(p => !p.nivel_id) || !l.length) l.push({ id: SIN_NIVEL, nombre: NIVELES.length ? 'No level' : 'Floor Plan' });
  return l;
}
function nivelElegido(){
  const l = nivelesConPlanos();
  if(!l.some(n => n.id === NIV_SEL)) NIV_SEL = (l.find(n => planoDe(PLANOS, n.id)) || l[0]).id;
  return l.find(n => n.id === NIV_SEL);
}

// ---------- dibujar ----------
export function abrir(trabajo, niveles, alNivel){
  if(!T || T.id !== trabajo.id){ PLANOS = []; NIV_SEL = null; ZOOM = 1; VISTA = '2d'; CARGADO = ''; AVISO = ''; }
  T = trabajo; NIVELES = niveles || []; AL_NIVEL = alNivel || null;
  if(CARGADO !== T.id && CARGADO !== 'cargando') cargar(); else pintar();
}
export function pintar(){
  const caja = $('#panel-plano'); if(!caja || !T) return;
  if(CARGADO === 'falta-sql'){ caja.innerHTML = '<p class="aviso">Esta parte todavía no está instalada en el servidor: falta correr sql/fotos-07-planos.sql.</p>'; return; }
  const niv = nivelElegido(); const p = planoDe(PLANOS, niv.id); const res = p ? resumenPlano(p.data) : null;
  const lista = nivelesConPlanos();
  const filasNiv = lista.map(n => { const q = planoDe(PLANOS, n.id);
    return `<button type="button" class="pl-nivel${n.id === niv.id ? ' on' : ''}" data-pl-nivel="${esc(n.id)}"><b>${esc(n.nombre)}</b><small>${q ? fmtPies(q.data ? resumenPlano(q.data).area : (q.area_sqft || 0)) + ' sq ft' : 'No plan'}</small></button>`; }).join('');
  // Teléfono (su pedido, 13-oct): sin la tarjeta de resumen ni la fila de pisos debajo de los botones, para que el
  // plano tenga más espacio. El piso se escoge arriba (la lista); "Add Level" vive en el menú •••.
  const opciones = lista.map(n => `<option value="${esc(n.id)}"${n.id === niv.id ? ' selected' : ''}>${esc(n.nombre)}</option>`).join('');
  let vista;
  if(CARGADO === 'cargando' || CARGADO === '') vista = '<div class="pl-vacio"><p>Loading plans…</p></div>';
  else if(CARGADO === 'error') vista = '<div class="pl-vacio"><p>Could not load the plans. Check your connection.</p></div>';
  else if(!p) vista = `<div class="pl-vacio">${IC('cubo', 'pl-vacio-ic')}<h3>No floor plan for ${esc(niv.nombre)} yet</h3><p>Tap <b>Scan New Plan</b> on an iPhone Pro (with LiDAR) and walk the rooms of this floor.</p></div>`;
  else { let svg = ''; try{ svg = svgDelPlano(p.data, T, true); }catch(e){ svg = '<p class="aviso">Could not draw this plan. ' + esc(e.message) + '</p>'; }
    // Al 100% el plano entra COMPLETO en su cuadro (su pedido: en la web el plano tiene la prioridad); con + se acerca y se puede mover.
    vista = `<div class="pl-lienzo${REJILLA ? ' rejilla' : ''}${ZOOM === 1 ? ' ajustado' : ''}"><div class="pl-zoom"${ZOOM === 1 ? '' : ` style="width:${Math.round(ZOOM * 100)}%"`}>${svg}</div></div>`; }
  const det = (k, v) => `<div class="pl-det"><span>${k}</span><b>${v}</b></div>`;
  const detalles = res ? det('Total Area', fmtPies(res.area) + ' sq ft') + det('Rooms', res.cuartos) + det('Exterior Walls', fmtPies(res.murosExt) + ' lf') + det('Ceiling Height', res.techo ? pies(res.techo) : '—') + det('Units', 'ft / in')
    : '<p class="pl-nada">Scan this floor to see its area, rooms and walls.</p>';
  const herrVista = `<div class="pl-seg"><button type="button" class="${VISTA === '2d' ? 'on' : ''}" data-pl-vista="2d">2D</button><button type="button" class="${VISTA === '3d' ? 'on' : ''}" data-pl-vista="3d">3D</button></div>`;
  const zoom = `<div class="pl-zoomer"><button type="button" data-pl-zoom="-1" aria-label="Zoom out">${IC('menos')}</button><span>${Math.round(ZOOM * 100)}%</span><button type="button" data-pl-zoom="1" aria-label="Zoom in">${IC('mas')}</button></div>`;
  caja.innerHTML = `
  <div class="pl-cab">
    <div class="pl-cab-t"><h2 class="sec-t">Floor Plan</h2><p>View and manage plans by level</p></div>
    <div class="pl-cab-acc">
      <button type="button" class="btn btn-outline" data-pl-escanear>${IC('escanear')}Scan New Plan</button>
      <button type="button" class="btn btn-outline" data-pl-exportar${p ? '' : ' disabled'}>${IC('compartir')}Export</button>
      <button type="button" class="btn btn-accent" data-pl-editar${p ? '' : ' disabled'}>${IC('lapiz')}Edit Floor Plan</button>
    </div>
  </div>
  ${AVISO ? `<p class="aviso${AVISO_OK ? ' ok' : ''}" id="plAviso">${esc(AVISO)}</p>` : ''}
  <div class="pl-tel-barra">
    <label class="sel pl-sel"><select id="plNivelSel" aria-label="Level">${opciones}</select>${IC('chev')}</label>
    ${herrVista}
    <div class="pl-mas-wrap"><button type="button" class="pl-mas-btn" data-pl-menu aria-label="More options" aria-expanded="${MENU ? 'true' : 'false'}">•••</button>
      <div class="pl-menu"${MENU ? '' : ' hidden'}><button type="button" data-pl-mas-nivel>${IC('mas')}Add Level</button><button type="button" data-pl-rejilla>${IC('cuadros')}${REJILLA ? 'Hide grid' : 'Show grid'}</button><button type="button" data-pl-ajustes>${IC('engrane')}Plan Settings</button></div></div>
  </div>
  <div class="pl-cuerpo">
    <aside class="pl-col pl-niveles"><h3>Levels</h3>${filasNiv}<button type="button" class="btn btn-outline btn-block pl-mas-nivel" data-pl-mas-nivel>${IC('mas')}Add Level</button></aside>
    <section class="pl-col pl-visor">
      <div class="pl-visor-cab"><b>${esc(niv.nombre)}</b>${p ? `<span class="pl-fecha">Updated ${esc(fechaEn(p.created_at))}</span>` : ''}
        <span class="pl-esp"></span>${herrVista}
        <button type="button" class="pl-rej${REJILLA ? ' on' : ''}" data-pl-rejilla>${IC('cuadros')}Grid</button>${zoom}
        <button type="button" class="pl-grande-btn" data-pl-grande aria-label="Full screen">${IC('expandir')}</button></div>
      ${vista}
    </section>
    <aside class="pl-col pl-detalles"><h3>Plan Details</h3>${detalles}<button type="button" class="btn btn-outline btn-block" data-pl-ajustes>${IC('engrane')}Plan Settings</button></aside>
  </div>
  <div class="pl-tel-acc">
    <div class="pl-tel-editar"><button type="button" class="btn btn-accent" data-pl-editar${p ? '' : ' disabled'}>Edit Floor Plan</button><button type="button" class="btn btn-outline pl-tel-grande" data-pl-grande aria-label="Full screen">${IC('expandir')}</button></div>
    <div class="pl-tel-dos"><button type="button" class="btn btn-outline" data-pl-escanear>${IC('escanear')}Scan New Plan</button><button type="button" class="btn btn-outline" data-pl-exportar${p ? '' : ' disabled'}>${IC('compartir')}Export</button></div>
  </div>`;
  medir();
  const lz = $('#panel-plano .pl-lienzo.ajustado'); if(lz) pellizco(lz, lz.querySelector('.pl-zoom'), PZ);
}
// Su pedido: en la computadora el plano tiene la prioridad pero SIN esconder las opciones (pestañas, cabecera).
// El cuadro del plano usa lo que queda de pantalla debajo de lo demás y el plano entra completo ahí (se acerca con +).
export function enfocar(){ medir(); }
function medir(){
  const l = $('#panel-plano .pl-lienzo'); const m = $('#main');
  // Solo con la pestaña Floor Plan a la vista: escondida (otra pestaña, otra pantalla) no se mide ni se fija nada.
  if(!l || !l.offsetParent){ if(typeof document !== 'undefined') document.body.classList.remove('pl-fijo'); return; }
  if(window.matchMedia && !window.matchMedia('(min-width: 900px)').matches){
    // Teléfono (su pedido del 13-oct): solo el plano, lo más grande posible. El cuadro toma la forma del
    // plano a todo lo ancho; si el plano es alto, se topa en 62% de la pantalla y el plano queda centrado.
    if(!l.classList.contains('ajustado')){ l.style.height = ''; document.body.classList.remove('pl-fijo'); return; }
    // Su pedido (13-oct): la página del plano NO se mueve para arriba y para abajo, queda como su diseño:
    // cabecera, pestañas, plano y botones en UNA pantalla, y el cuadro del plano se lleva el espacio que sobra.
    // Si de plano no cabe (teléfono acostado, letra muy grande), la página se desplaza como siempre.
    // La clase va ANTES de medir: con ella la pantalla suelta su margen de abajo y el aviso vacío (13-oct),
    // y ese espacio se lo tiene que llevar el plano. Si al final no cabe, se quita abajo.
    document.body.classList.add('pl-fijo');
    const v = l.querySelector('svg'); const vb = v && v.viewBox && v.viewBox.baseVal;
    const ar = vb && vb.width && vb.height ? vb.width / vb.height : 1.4;
    const panel = $('#panel-plano'); const ultimo = panel && panel.lastElementChild;
    const resto = ultimo ? ultimo.getBoundingClientRect().bottom - l.getBoundingClientRect().bottom : 0;   // resumen + botones + pisos
    const visible = m ? m.clientHeight : window.innerHeight;
    const arriba = l.getBoundingClientRect().top - (m ? m.getBoundingClientRect().top - m.scrollTop : 0);
    const pie = m ? parseFloat(getComputedStyle(m).paddingBottom) || 0 : 0;   // el margen de abajo de la pantalla también cuenta
    const cabe = Math.floor(visible - arriba - resto - pie - 2);
    if(cabe >= 160){
      l.style.height = cabe + 'px';
      // Lo que todavía sobresalga (márgenes de más abajo) se le quita al cuadro: así la página ya no se mueve.
      const sobra = m ? m.scrollHeight - m.clientHeight : 0;
      if(sobra > 0) l.style.height = Math.max(160, cabe - sobra) + 'px';
      document.body.classList.add('pl-fijo'); if(m) m.scrollTop = 0;
    } else {
      document.body.classList.remove('pl-fijo');
      l.style.height = Math.max(200, Math.round((l.clientWidth - 16) / ar + 16)) + 'px';
    }
    return;
  }
  const arriba = l.getBoundingClientRect().top + (m ? m.scrollTop : window.scrollY);   // dónde queda el cuadro con la página arriba del todo
  l.style.height = Math.max(380, Math.round(window.innerHeight - arriba - 18)) + 'px';
  // Su pedido (14-oct): en la computadora tampoco se mueve la página. El borde de la tarjeta del plano y el margen de
  // abajo de la pantalla no entraban en la cuenta (sobraban ~65 px): lo que todavía sobresalga se le quita al cuadro.
  const sobra = m ? m.scrollHeight - m.clientHeight : 0;
  if(sobra > 0){ l.style.height = Math.max(380, l.clientHeight - sobra) + 'px'; if(m) m.scrollTop = 0; }
}
if(typeof window !== 'undefined') window.addEventListener('resize', () => medir());
// La foto de la cabecera llega después y cambia el alto: se vuelve a medir para que todo siga cabiendo.
if(typeof document !== 'undefined') document.addEventListener('load', (e) => { if(e.target && e.target.tagName === 'IMG' && e.target.closest && e.target.closest('#pTrabajo') && $('#panel-plano .pl-lienzo')) medir(); }, true);
function avisar(t, ok){ AVISO = t || ''; AVISO_OK = !!ok; pintar(); }

// ---------- acercar con los dedos (su pedido 13-oct: sin + y − encima del plano) ----------
// Dos dedos: abre/cierra y mueve. Un dedo con el plano acercado: lo mueve. Un dedo con el plano entero: la página se
// desplaza como siempre. Dos toques seguidos: acerca ahí, o vuelve a enseñarlo entero.
export function limitarPZ(e, w, h){
  e.s = Math.max(1, Math.min(6, e.s));
  e.x = Math.min(0, Math.max(w - w * e.s, e.x)); e.y = Math.min(0, Math.max(h - h * e.s, e.y));
  if(e.s === 1){ e.x = 0; e.y = 0; }
  return e;
}
export function zoomEn(e, s2, mx, my){ const px = (mx - e.x) / e.s, py = (my - e.y) / e.s; e.s = s2; e.x = mx - px * s2; e.y = my - py * s2; return e; }
function pellizco(caja, obj, e){
  if(!caja || !obj) return;
  obj.style.transformOrigin = '0 0';
  const poner = () => { limitarPZ(e, caja.clientWidth, caja.clientHeight); obj.style.transform = e.s === 1 ? '' : `translate(${e.x}px, ${e.y}px) scale(${e.s})`; caja.classList.toggle('pz-cerca', e.s > 1); };
  poner();
  let ini = null, ultimoToque = 0, movio = false;
  const rel = (t) => { const r = caja.getBoundingClientRect(); return { x: t.clientX - r.left, y: t.clientY - r.top }; };
  caja.addEventListener('touchstart', (ev) => {
    movio = false;
    if(ev.touches.length === 2){ const a = rel(ev.touches[0]), b = rel(ev.touches[1]); ini = { d: Math.hypot(a.x - b.x, a.y - b.y) || 1, s: e.s, mx: (a.x + b.x) / 2, my: (a.y + b.y) / 2, x: e.x, y: e.y }; }
    else if(ev.touches.length === 1){ const a = rel(ev.touches[0]); ini = { uno: true, px: a.x, py: a.y, x: e.x, y: e.y }; }
  }, { passive: true });
  caja.addEventListener('touchmove', (ev) => {
    if(!ini) return;
    if(ev.touches.length === 2 && !ini.uno){
      ev.preventDefault(); movio = true;
      const a = rel(ev.touches[0]), b = rel(ev.touches[1]); const d = Math.hypot(a.x - b.x, a.y - b.y) || 1;
      const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
      e.s = ini.s; e.x = ini.x; e.y = ini.y; zoomEn(e, Math.max(1, Math.min(6, ini.s * d / ini.d)), ini.mx, ini.my);
      e.x += mx - ini.mx; e.y += my - ini.my; poner();
    } else if(ev.touches.length === 2 && ini.uno){ const a = rel(ev.touches[0]), b = rel(ev.touches[1]); ini = { d: Math.hypot(a.x - b.x, a.y - b.y) || 1, s: e.s, mx: (a.x + b.x) / 2, my: (a.y + b.y) / 2, x: e.x, y: e.y }; }
    else if(ev.touches.length === 1 && ini.uno && e.s > 1){
      ev.preventDefault(); const a = rel(ev.touches[0]);
      if(Math.abs(a.x - ini.px) + Math.abs(a.y - ini.py) > 4) movio = true;
      e.x = ini.x + a.x - ini.px; e.y = ini.y + a.y - ini.py; poner();
    } else if(ev.touches.length === 1){ const a = rel(ev.touches[0]); if(Math.abs(a.x - ini.px) + Math.abs(a.y - ini.py) > 4) movio = true; }
  }, { passive: false });
  caja.addEventListener('touchend', (ev) => {
    if(ev.touches.length) return;
    const fue = ini; ini = null;
    if(!fue || !fue.uno || movio) return;
    const ahora = Date.now();
    if(ahora - ultimoToque < 320){
      ultimoToque = 0;
      if(e.s > 1){ e.s = 1; e.x = 0; e.y = 0; } else zoomEn(e, 2.5, fue.px, fue.py);
      poner();
    } else ultimoToque = ahora;
  }, { passive: true });
}

// ---------- escanear ----------
async function escanear(){
  if(OCUPADO) return;
  const RS = window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.RoomScan;
  if(!RS){ avisar('Scanning works in the Scanova360 app on an iPhone Pro (it needs the LiDAR camera). On the computer you can view and export the plans.'); return; }
  try{ const s = await RS.isSupported(); if(s && s.value === false){ avisar('This iPhone has no LiDAR camera, so it cannot scan a floor plan. It works on the iPhone Pro models (12 Pro and newer).'); return; } }catch(e){}
  let niv = nivelElegido(); OCUPADO = true; avisar('');
  try{
    // Los niveles REALES del trabajo viajan a la bandeja de la cámara; el que se escoja ahí es el que manda.
    const r = await RS.scan({ nivelBase: niv && niv.id !== SIN_NIVEL ? niv.nombre : '', niveles: NIVELES.map(n => n.nombre) });
    if(!r || r.cancelled){ OCUPADO = false; if(r && r.error) avisar(r.error); return; }
    if(r.nivelBase){ const m = NIVELES.find(n => n.nombre === r.nivelBase); if(m) niv = m; }
    // La planta estándar que se escogió en la cámara (sótano, 1st Floor…) le da nombre al nivel en la hoja, igual
    // que en Field Reports; los niveles con nombre propio ya vienen en inspection.nombresDeNivel.
    if(r.nivelBase && !r._nivelBase && PLANTAS.includes(r.nivelBase)) r._nivelBase = r.nivelBase;
    r.job = { client: T.cliente || '', address: T.direccion || '', date: new Date().toISOString().slice(0, 10) };
    // UN ESCANEO CON DOS NIVELES ("Otro nivel" a medio escaneo) se guarda partido: una fila por nivel, cada una en
    // SU piso del proyecto. Antes se guardaba todo bajo el primero, se dibujaba solo el primero y el área los sumaba.
    const niveles = plano.floorplanLevels(prepararPlano(r));
    const nombres = (r.inspection && r.inspection.nombresDeNivel) || {};
    const partes = (niveles.length > 1 ? niveles : [null]).map(L => {
      const d = prepararPlano(L == null ? r : Object.assign({}, r, { _nivel: L }));   // se guarda ya derecho
      const nombre = L == null ? '' : String(nombres[String(L)] || (L === niveles[0] ? (r.nivelBase || '') : ''));
      const n = L == null || L === niveles[0] ? (NIVELES.find(x => x.nombre === nombre) || niv) : (NIVELES.find(x => x.nombre === nombre) || null);
      return { d, n, res: resumenPlano(d) };
    }).filter(x => x.res.cuartos);
    if(!partes.length){ OCUPADO = false; avisar('The scan came back without any room. Nothing was saved - try again walking slowly along the walls.'); return; }
    const guardadas = [];
    for(const x of partes){
      const fila = { trabajo_id: T.id, nivel_id: x.n && x.n.id !== SIN_NIVEL ? x.n.id : null, data: x.d, area_sqft: x.res.area, cuartos: x.res.cuartos, muros_ext_ft: x.res.murosExt, techo_ft: x.res.techo || null };
      const g = await authFetch('/rest/v1/fotos_planos', { method:'POST', headers:{ Prefer:'return=representation' }, body: JSON.stringify(fila) });
      const guardada = g.ok ? (await g.json())[0] : null;
      if(!guardada || !guardada.id) throw new Error(g.status === 404 ? 'falta correr sql/fotos-07-planos.sql' : 'HTTP ' + g.status);
      guardadas.push(guardada);
    }
    PLANOS = guardadas.slice().reverse().concat(PLANOS); NIV_SEL = (partes[0].n || niv).id; OCUPADO = false; pintarConteo(pisosConPlano(PLANOS));
    const res = partes[0].res;
    avisar(partes.length > 1
      ? 'Floor plans saved: ' + partes.map(x => (x.n ? x.n.nombre : 'No level') + ' (' + fmtPies(x.res.area) + ' sq ft)').join(', ') + '.'
      : 'Floor plan saved for ' + niv.nombre + ' (' + fmtPies(res.area) + ' sq ft, ' + res.cuartos + ' rooms).', true);
  }catch(e){ OCUPADO = false; avisar('Could not save the floor plan. ' + String(e && e.message || e)); }
}

// ---------- exportar (PNG del plano, como la foto: hoja de compartir en el teléfono) ----------
// La letra de la marca (Plus Jakarta Sans) DENTRO de la imagen que se exporta: un SVG dibujado como imagen no
// puede pedir letras de afuera y el navegador la cambiaba por otra (su pedido del 14-oct: siempre el estilo de
// Scanova). Se baja una vez y se guarda; sin internet, la hoja sale igual con la letra del sistema.
let FUENTE_MARCA = null;
async function fuenteMarca(){
  if(FUENTE_MARCA !== null) return FUENTE_MARCA;
  try{
    const css = await fetch('https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700;800&display=swap').then(r => r.ok ? r.text() : '');
    const caras = [...css.matchAll(/@font-face\s*{([^}]*)}/g)].map(m => m[1]).filter(b => /latin;|U\+0000-00FF/.test(b) || !/unicode-range/.test(b));
    let out = '';
    for(const b of caras){
      const peso = (b.match(/font-weight:\s*(\d+)/) || [])[1] || '400', src = (b.match(/url\((https:[^)]+)\)/) || [])[1];
      if(!src) continue;
      const buf = await fetch(src).then(r => r.arrayBuffer()); let bin = ''; const u8 = new Uint8Array(buf);
      for(let i = 0; i < u8.length; i += 0x8000) bin += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000));
      out += `@font-face{font-family:'Plus Jakarta Sans';font-weight:${peso};src:url(data:font/woff2;base64,${btoa(bin)}) format('woff2');}`;
    }
    FUENTE_MARCA = out;
  }catch(e){ FUENTE_MARCA = ''; }
  return FUENTE_MARCA;
}
// La hoja del plano pintada en un lienzo (la misma del botón exportar; Documents la pone en su PDF).
export async function lienzoDelPlano(data, trabajo, maxLado = 3600){
  let svg = svgDelPlano(data, trabajo);
  const fuente = await fuenteMarca();
  if(fuente) svg = svg.replace(/(<svg[^>]*>)/, `$1<defs><style>${fuente}</style></defs>`);
  const m = svg.match(/viewBox="([\d.\-]+) ([\d.\-]+) ([\d.]+) ([\d.]+)"/); const w = m ? +m[3] : 2000, h = m ? +m[4] : 1400;
  const k = Math.min(2, maxLado / Math.max(w, h)); const c = document.createElement('canvas'); c.width = Math.round(w * k); c.height = Math.round(h * k);
  const ctx = c.getContext('2d'); ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, c.width, c.height);
  const url = URL.createObjectURL(new Blob([svg.includes('xmlns=') ? svg : svg.replace('<svg', '<svg xmlns="http://www.w3.org/2000/svg"')], { type:'image/svg+xml' }));
  try{ const im = await new Promise((ok, no) => { const i = new Image(); i.onload = () => ok(i); i.onerror = () => no(new Error('could not draw the plan')); i.src = url; }); ctx.drawImage(im, 0, 0, c.width, c.height); }
  finally{ URL.revokeObjectURL(url); }
  return c;
}
async function pngDelPlano(p){
  const c = await lienzoDelPlano(p.data, T);
  return new Promise((ok, no) => c.toBlob(b => { c.width = c.height = 0; b ? ok(b) : no(new Error('could not make the image')); }, 'image/png'));
}
async function exportar(){
  const niv = nivelElegido(); const p = planoDe(PLANOS, niv.id); if(!p || OCUPADO) return;
  OCUPADO = true;
  try{
    const blob = await pngDelPlano(p);
    const nombre = ('FloorPlan ' + (T.cliente || 'Project') + ' ' + niv.nombre).replace(/[^\w\- ]+/g, '').trim().replace(/\s+/g, '_') + '.png';
    const archivo = new File([blob], nombre, { type:'image/png' });
    if(!esAparato() && !/iPhone|iPad|Android/i.test(navigator.userAgent)){
      const u = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = u; a.download = nombre; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(u), 4000);
      OCUPADO = false; avisar('Downloaded ' + nombre, true);
    } else if(navigator.canShare && navigator.canShare({ files:[archivo] })){ await navigator.share({ files:[archivo], title: nombre }); OCUPADO = false; }
    else { const u = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = u; a.download = nombre; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(u), 4000); OCUPADO = false; avisar('Downloaded ' + nombre, true); }
  }catch(e){ OCUPADO = false; if(!(e && e.name === 'AbortError')) avisar('Could not export the plan. ' + String(e && e.message || e)); }
}

// ---------- pantalla completa (capa dentro de la app, como la foto grande) ----------
function grande(){
  const niv = nivelElegido(); const p = planoDe(PLANOS, niv.id); if(!p) return;
  let capa = $('#plGrande'); if(!capa){ capa = document.createElement('div'); capa.id = 'plGrande'; capa.className = 'pl-grande'; ($('.app') || document.body).appendChild(capa); }
  capa.innerHTML = `<div class="pl-grande-cab"><b>${esc(T.cliente || '')} · ${esc(niv.nombre)}</b><button type="button" class="pl-grande-x" data-pl-grande-x aria-label="Close">✕</button></div><div class="pl-grande-lienzo">${svgDelPlano(p.data, T, true)}</div>`;
  capa.hidden = false; document.body.classList.add('con-visor');
  PZ_GRANDE.s = 1; PZ_GRANDE.x = 0; PZ_GRANDE.y = 0; const lg = capa.querySelector('.pl-grande-lienzo'); if(lg) pellizco(lg, lg.querySelector('svg'), PZ_GRANDE);
}
function cerrarGrande(){ const c = $('#plGrande'); if(c){ c.hidden = true; c.innerHTML = ''; } document.body.classList.remove('con-visor'); }

export function conectar(){
  document.addEventListener('click', async (e) => {
    const q = (s) => e.target.closest(s); let el;
    if(q('[data-pl-grande-x]')){ cerrarGrande(); return; }
    if(!e.target.closest('#panel-plano')){ if(MENU){ MENU = false; pintar(); } return; }
    if(q('[data-pl-menu]')){ MENU = !MENU; pintar(); return; }
    if(MENU){ MENU = false; if(!q('.pl-menu')) pintar(); }   // tocar cualquier otra cosa cierra el menú
    if((el = q('[data-pl-nivel]'))){ NIV_SEL = el.dataset.plNivel; ZOOM = 1; PZ.s = 1; PZ.x = 0; PZ.y = 0; AVISO = ''; pintar(); return; }
    if((el = q('[data-pl-vista]'))){
      if(el.dataset.plVista === '3d'){
        const RS = window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.RoomScan;
        if(RS && RS.viewModel){ try{ const r = await RS.viewModel(); if(r && r.error) avisar('3D view: ' + r.error + ' The 3D model is available right after a scan on this iPhone.'); }catch(err){ avisar('Could not open the 3D view.'); } }
        else avisar('The 3D view opens in the Scanova360 app on the iPhone, right after scanning a floor.');
        return;
      }
      VISTA = '2d'; pintar(); return;
    }
    if(q('[data-pl-rejilla]')){ REJILLA = !REJILLA; pintar(); return; }
    if((el = q('[data-pl-zoom]'))){ ZOOM = Math.max(0.5, Math.min(3, Math.round((ZOOM + Number(el.dataset.plZoom) * 0.25) * 100) / 100)); pintar(); return; }
    if(q('[data-pl-grande]')){ grande(); return; }
    if(q('[data-pl-escanear]')){ escanear(); return; }
    if(q('[data-pl-exportar]')){ exportar(); return; }
    if(q('[data-pl-mas-nivel]')){ if(AL_NIVEL) AL_NIVEL(); return; }
    if(q('[data-pl-editar]')){ avisar('Editing the plan (move walls, rename rooms, add doors) is the next step being built. For now you can scan, view, zoom and export.'); return; }
    if(q('[data-pl-ajustes]')){ avisar('Plan settings (units, ceiling height) come with the editing step.'); return; }
  });
  document.addEventListener('change', (e) => { if(e.target.id === 'plNivelSel'){ NIV_SEL = e.target.value; ZOOM = 1; AVISO = ''; pintar(); } });
  document.addEventListener('keydown', (e) => { if(e.key === 'Escape') cerrarGrande(); });
}
