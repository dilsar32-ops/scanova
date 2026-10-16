// Scanova · la ventana de UNA foto (diseño de Amilcar, 12 oct 2026): la foto grande con sus flechas, la tira de fotos,
// y a la derecha "Photo Details" (quién/cuándo/dónde, nivel y cuarto, descripción), Tags, Tasks y Comments.
// Arriba: Download, Share, •••, Edit Photo y Save a Copy. El panel se esconde y se vuelve a sacar con la flechita.
// Datos: la nota de la foto (fotos_fotos.nota), sus etiquetas (fotos_etiquetas + fotos_foto_etiquetas) y sus comentarios
// (fotos_comentarios) ya existían desde fotos-01; las tareas de la foto usan fotos_tareas (sql/fotos-06-foto.sql).
import { $, $$, authFetch, irA, atras, esManager, PERFIL, esAparato } from './app.js?v=2026-10-16-10';
import * as trabajos from './trabajos.js?v=2026-10-16-10';
import * as fotos from './fotos.js?v=2026-10-16-10';
import * as proyecto from './proyecto.js?v=2026-10-16-10';
import * as panel from './panel.js?v=2026-10-16-10';
import * as editor from './editor.js?v=2026-10-16-10';

const esc = (v) => trabajos.esc(v);
const IC = (n) => '<svg class="ic"><use href="#i-' + n + '"/></svg>';

// ---------- lo puro ----------
export const fechaLarga = (iso) => { const d = new Date(iso); return isNaN(d) ? '' : d.toLocaleDateString('en-US', { month:'short', day:'numeric', year:'numeric' }); };
export const horaLarga = (iso) => { const d = new Date(iso); return isNaN(d) ? '' : d.toLocaleTimeString('en-US', { hour:'numeric', minute:'2-digit' }); };
export const fechaCorta = (s) => { if(!s) return ''; const d = new Date(String(s).length === 10 ? s + 'T12:00:00' : s); return isNaN(d) ? '' : d.toLocaleDateString('en-US', { month:'short', day:'numeric', year:'numeric' }); };
// Nombre del archivo al bajar o compartir: proyecto, cuarto y fecha (sin caracteres raros).
export function nombreArchivo(proyectoNombre, lugar, iso){
  const d = new Date(iso); const f = isNaN(d) ? '' : d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  const limpio = (x) => String(x || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^A-Za-z0-9]+/g, '-').replace(/^-|-$/g, '');
  return [limpio(proyectoNombre), limpio(lugar), f].filter(Boolean).join('_') + '.jpg';
}
// Las etiquetas de la foto, en el orden del catálogo.
export function etiquetasDeFoto(catalogo, ids){ const s = new Set(ids || []); return (catalogo || []).filter(e => s.has(e.id)); }
const COLOR = (c) => proyecto.ETQ_COLORES[c] ? c : 'gris';

// ---------- estado ----------
let F = null, CAT = [], ETQ = [], TAREAS = [], COMS = [], EQUIPO = [], FALTA_TAREAS = false;
let EDIT_NOTA = false, ABRIR_ETQ = false, ABRIR_TAREA = false, ETQ_COLOR = 'azul';
const yo = () => (PERFIL && PERFIL.id) || '';
const puedeEditar = (f) => esManager() || (f && f.created_by === yo());
const OCULTO = 'scanova.fotoPanelOculto';
function aviso(t, ok){ const a = $('#fvAviso'); if(a){ a.textContent = t || ''; a.classList.toggle('ok', !!ok); } }

// ---------- abrir / pintar ----------
async function abrir(nueva){
  const lista = fotos.visorLista(); const f = lista[fotos.visorIndice()];
  if(!f){ if(!$('#pFoto').hidden) atras(); return; }
  const cambio = !F || F.id !== f.id; F = f;
  if(nueva && $('#pFoto').hidden) irA('pFoto', pantallaActual());
  try{ document.body.classList.toggle('fv-oculto', localStorage.getItem(OCULTO) === '1'); }catch{}
  if(cambio){ EDIT_NOTA = false; ABRIR_ETQ = false; ABRIR_TAREA = false; ETQ = []; TAREAS = []; COMS = []; aviso(''); }
  pintarCabeza(); pintarFoto(); pintarTira(); pintarPanel();
  if(cambio) cargar(f);
}
function pantallaActual(){ const p = $$('.pantalla').find(x => !x.hidden); return p ? p.id : 'pTrabajo'; }
function lugarDe(f){
  const n = f.nivel_id && proyecto.niveles().find(x => x.id === f.nivel_id);
  const c = f.cuarto_id && proyecto.cuartos().find(x => x.id === f.cuarto_id);
  return { nivel: n ? n.nombre : '', cuarto: c ? c.nombre : '' };
}
function pintarCabeza(){
  const T = trabajos.proyectoAbierto() || {}; const l = lugarDe(F);
  $('#fvTitulo').textContent = l.cuarto || l.nivel || T.cliente || 'Photo';
  $('#fvRuta').innerHTML = l.nivel ? esc(l.nivel) + (l.cuarto ? ' ' + IC('chev-der') + ' ' + esc(l.cuarto) : '') : esc(l.cuarto ? '' : 'No room yet');
}
async function pintarFoto(){
  const lista = fotos.visorLista(); const i = fotos.visorIndice(); const f = F;
  $('#fvN').textContent = (i + 1) + ' / ' + lista.length;
  const img = $('#fvImg'); const mini = fotos.urlsMini()[f.id];
  if(img.dataset.id !== f.id){ img.src = mini || ''; img.dataset.id = f.id; }
  $('#fvFav').hidden = !f.favorita;
  // Rapidez: se firman TODAS las fotos de la lista en una sola llamada (antes una por foto, medio segundo cada vez)
  // y se adelantan la anterior y la siguiente, así las flechas cambian al instante.
  const ids = lista.map(x => x.id);
  const u = await fotos.urlsFirmadas(ids, 'web');
  if(F === f && u[f.id]) img.src = u[f.id];
  [i - 1, i + 1].forEach(k => { const g = lista[(k + lista.length) % lista.length]; if(g && u[g.id] && !PRECARGA.has(u[g.id])){ PRECARGA.add(u[g.id]); const pi = new Image(); pi.decoding = 'async'; pi.src = u[g.id]; } });
}
const PRECARGA = new Set();
let TIRA_CLAVE = '';
function pintarTira(){
  const lista = fotos.visorLista(); const urls = fotos.urlsMini(); const i = fotos.visorIndice();
  const t = $('#fvTira');
  TIRA_CLAVE = lista.map(f => f.id + (urls[f.id] ? '+' : '')).join(',') + '|' + i;
  t.innerHTML = lista.map((f, k) => `<button type="button" class="fv-mini${k === i ? ' on' : ''}" data-fv-ir="${k}" aria-label="Photo ${k + 1}">${urls[f.id] ? '<img src="' + esc(urls[f.id]) + '" alt="" loading="lazy">' : ''}</button>`).join('');
  const on = t.querySelector('.fv-mini.on'); if(on && on.scrollIntoView) on.scrollIntoView({ block:'nearest', inline:'center' });
}

// ---------- datos de la foto ----------
async function cargar(f){
  const id = encodeURIComponent(f.id);
  const [rc, re, rt, rm] = await Promise.all([
    CAT.length ? null : authFetch('/rest/v1/fotos_etiquetas?select=*&order=orden.asc,nombre.asc'),
    authFetch('/rest/v1/fotos_foto_etiquetas?foto_id=eq.' + id + '&select=etiqueta_id'),
    authFetch('/rest/v1/fotos_tareas?foto_id=eq.' + id + '&select=*&order=created_at.asc'),
    authFetch('/rest/v1/fotos_comentarios?foto_id=eq.' + id + '&select=*&order=created_at.asc'),
    fotos.cargarNombres().catch(() => {}),
  ]);
  if(F !== f) return;
  // Favorita: aparte, para que la galería no se caiga si todavía no se corre sql/fotos-06-foto.sql.
  authFetch('/rest/v1/fotos_fotos?id=eq.' + id + '&select=favorita').then(r => r.ok ? r.json() : []).then(x => { if(x[0]){ f.favorita = !!x[0].favorita; if(F === f) $('#fvFav').hidden = !f.favorita; } }).catch(() => {});
  if(rc && rc.ok) CAT = await rc.json();
  ETQ = re.ok ? (await re.json()).map(x => x.etiqueta_id) : [];
  FALTA_TAREAS = !rt.ok; TAREAS = rt.ok ? await rt.json() : [];
  COMS = rm.ok ? await rm.json() : [];
  pintarPanel();
}

function fila(icono, html, extra){ return `<div class="fv-fila">${IC(icono)}<div class="fv-fila-t">${html}</div>${extra || ''}</div>`; }
function pintarPanel(){
  if(editor.activo()) return;   // mientras se edita, el panel es del editor
  const p = $('#fvPanel'); if(!p || !F) return;
  const T = trabajos.proyectoAbierto() || {}; const l = lugarDe(F); const cuando = F.tomada_at || F.subida_at;
  const borrador = $('#fvComTxt') ? $('#fvComTxt').value : '';
  const tags = etiquetasDeFoto(CAT, ETQ);
  const sinUsar = CAT.filter(e => !ETQ.includes(e.id));
  const nom = (u) => fotos.nombreDe(u) || '';
  p.innerHTML = `<div class="fv-h-fila"><h2 class="fv-h">Photo Details</h2><button type="button" class="fv-cerrar-tel" data-fv-cerrar-detalles aria-label="Close">✕</button></div>
    <div class="fv-grupo">
      <div class="fv-doble">${fila('persona', esc(T.cliente || ''))}${fila('calendario', esc(fechaLarga(cuando)) + '<br>' + esc(horaLarga(cuando)) + '<small>by ' + esc(nom(F.created_by) || 'Team') + '</small>')}</div>
      ${fila('pin', esc(T.direccion || 'No address'))}
    </div>
    <button type="button" class="fv-grupo fv-lugar" data-fv-mover>${fila('casa', l.nivel ? esc(l.nivel) + (l.cuarto ? ' ' + IC('chev-der') + ' ' + esc(l.cuarto) : '') : '<span class="fv-gris">Choose level &amp; room</span>', IC('chev'))}</button>
    <div class="fv-grupo">
      ${EDIT_NOTA ? `<div class="fv-fila">${IC('doc')}<div class="fv-fila-t"><textarea class="pdet-area" id="fvNotaTxt" placeholder="What does this photo show?">${esc(F.nota || '')}</textarea><div class="pdet-fila"><button type="button" class="btn btn-outline btn-chico" data-fv-nota-no>Cancel</button><button type="button" class="btn btn-accent btn-chico" data-fv-nota-si>Save</button></div></div></div>`
        : fila('doc', F.nota ? esc(F.nota) : '<span class="fv-gris">Add a description</span>', puedeEditar(F) ? `<button type="button" class="pdet-ed" data-fv-nota aria-label="Edit description">${IC('lapiz')}</button>` : '')}
    </div>
    <section class="fv-sec">
      <div class="fv-sec-t">${IC('etiqueta')}<h3>Tags</h3><button type="button" class="fv-agregar" data-fv-etq>${IC('mas')}Add Tag</button></div>
      <div class="fv-tags">${tags.length ? tags.map(e => `<span class="etq-s c-${esc(COLOR(e.color))}">${esc(e.nombre)}<button type="button" data-fv-etq-quitar="${esc(e.id)}" aria-label="Remove ${esc(e.nombre)}">✕</button></span>`).join('') : '<span class="fv-gris">No tags yet.</span>'}</div>
      ${ABRIR_ETQ ? `<div class="fv-caja">${sinUsar.length ? '<div class="fv-tags">' + sinUsar.map(e => `<button type="button" class="etq-s c-${esc(COLOR(e.color))} fv-etq-op" data-fv-etq-poner="${esc(e.id)}">+ ${esc(e.nombre)}</button>`).join('') + '</div>' : '<p class="fv-gris">' + (CAT.length ? 'All tags are on this photo.' : 'There are no tags yet.') + '</p>'}
        ${esManager() ? `<div class="etq-nueva"><input type="text" id="fvEtqTxt" maxlength="40" placeholder="New tag, e.g. Water Damage"><button type="button" class="btn btn-outline btn-chico" data-fv-etq-crear>Create</button></div>
        <div class="etq-colores">${Object.keys(proyecto.ETQ_COLORES).map(k => `<button type="button" class="etq-color c-${k}${ETQ_COLOR === k ? ' on' : ''}" data-fv-etq-color="${k}" aria-label="${k}"></button>`).join('')}</div>` : '<p class="fv-gris">Only the manager can create new tags.</p>'}</div>` : ''}
    </section>
    <section class="fv-sec">
      <div class="fv-sec-t">${IC('tareas')}<h3>Tasks</h3><button type="button" class="fv-agregar" data-fv-tarea>${IC('mas')}Add Task</button></div>
      ${FALTA_TAREAS ? '<p class="fv-gris">Photo tasks are not installed on the server yet (falta sql/fotos-06-foto.sql).</p>' : ''}
      ${TAREAS.map(t => `<div class="fv-tarea${t.hecha ? ' hecha' : ''}"><button type="button" class="fv-circ" data-fv-tarea-hecha="${esc(t.id)}" aria-label="${t.hecha ? 'Mark as not done' : 'Mark as done'}">${t.hecha ? IC('check') : ''}</button>
        <div class="fv-tarea-t"><b>${esc(t.texto)}</b>${t.vence ? '<small>Due: ' + esc(fechaCorta(t.vence)) + '</small>' : ''}</div>
        ${t.asignado ? `<span class="fv-av" title="${esc(nom(t.asignado))}" translate="no">${esc(trabajos.iniciales(nom(t.asignado)))}</span>` : ''}
        ${esManager() || t.created_by === yo() ? `<button type="button" class="fv-puntos" data-fv-tarea-menu="${esc(t.id)}" aria-label="Task options">${IC('puntos')}</button>` : ''}</div>`).join('')}
      ${ABRIR_TAREA ? `<div class="fv-caja"><input type="text" class="fv-in" id="fvTareaTxt" maxlength="300" placeholder="What needs to be done?">
        <div class="fv-in-fila"><label>Due<input type="date" class="fv-in" id="fvTareaVence"></label><label>Assign to<select class="fv-in" id="fvTareaQuien"><option value="">Nobody</option>${EQUIPO.map(u => `<option value="${esc(u.id)}">${esc(u.full_name || '')}</option>`).join('')}</select></label></div>
        <div class="pdet-fila"><button type="button" class="btn btn-outline btn-chico" data-fv-tarea-no>Cancel</button><button type="button" class="btn btn-accent btn-chico" data-fv-tarea-si>Add Task</button></div></div>`
        : (TAREAS.length || FALTA_TAREAS ? '' : '<p class="fv-gris">No tasks for this photo.</p>')}
    </section>
    <section class="fv-sec">
      <div class="fv-sec-t">${IC('comentario')}<h3>Comments</h3><button type="button" class="fv-agregar" data-fv-com-foco>${IC('mas')}Add Comment</button></div>
      ${COMS.map(c => `<div class="fv-com"><span class="fv-av" translate="no">${esc(trabajos.iniciales(nom(c.created_by)))}</span><div class="fv-com-t"><b>${esc(nom(c.created_by) || 'Someone')}</b><small>${esc(fechaLarga(c.created_at))} &nbsp;${esc(horaLarga(c.created_at))}</small><p>${esc(c.texto)}</p></div>
        ${esManager() || c.created_by === yo() ? `<button type="button" class="fv-puntos" data-fv-com-menu="${esc(c.id)}" aria-label="Comment options">${IC('puntos')}</button>` : ''}</div>`).join('')}
      <div class="fv-escribir"><input type="text" id="fvComTxt" maxlength="2000" placeholder="Add a comment..."><button type="button" class="fv-enviar" data-fv-com-enviar aria-label="Send comment">${IC('enviar')}</button></div>
    </section>`;
  if(borrador && $('#fvComTxt')) $('#fvComTxt').value = borrador;
}

// ---------- acciones ----------
async function enviar(ruta, metodo, cuerpo){
  const r = await authFetch('/rest/v1/' + ruta, { method: metodo, headers:{ Prefer:'return=representation' }, body: cuerpo ? JSON.stringify(cuerpo) : undefined });
  if(!r.ok) throw new Error(r.status === 400 && /foto_id|vence|asignado/.test(await r.clone().text()) ? 'falta correr sql/fotos-06-foto.sql' : 'HTTP ' + r.status);
  return r.json();
}
async function equipo(){ if(!EQUIPO.length){ const r = await authFetch('/rest/v1/profiles?select=id,full_name,role,status&order=full_name.asc'); EQUIPO = r.ok ? (await r.json()).filter(p => p.status === 'active' || p.role === 'manager') : []; } return EQUIPO; }
async function blobDe(f){
  const u = (await fotos.urlsFirmadas([f.id], 'original'))[f.id] || (await fotos.urlsFirmadas([f.id], 'web'))[f.id];
  if(!u) throw new Error('no link for this photo');
  const r = await editor.bajar(u); if(!r.ok) throw new Error('HTTP ' + r.status);   // sin la copia guardada del navegador (CORS)
  return r.blob();
}
function nombreDeFoto(f){ const T = trabajos.proyectoAbierto() || {}; const l = lugarDe(f); return nombreArchivo(T.cliente, l.cuarto || l.nivel, f.tomada_at || f.subida_at); }
async function compartir(soloGuardar){
  const f = F; const b = soloGuardar ? $('#fvBajar') : $('#fvCompartir'); b.disabled = true; aviso('');
  try{
    const blob = await blobDe(f); const nombre = nombreDeFoto(f);
    const archivo = new File([blob], nombre, { type: blob.type || 'image/jpeg' });
    // En la computadora "Download" baja el archivo; en el teléfono abre la hoja de iOS (ahí está "Save Image").
    if(soloGuardar && !esAparato() && !/iPhone|iPad|Android/i.test(navigator.userAgent)){
      const u = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = u; a.download = nombre; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(u), 4000);
      aviso('Downloaded ' + nombre, true);
    } else if(navigator.canShare && navigator.canShare({ files:[archivo] })){
      await navigator.share({ files:[archivo], title: nombre });
    } else {
      const u = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = u; a.download = nombre; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(u), 4000);
      aviso('This browser cannot share files; the photo was downloaded instead.', true);
    }
  }catch(e){ if(!(e && e.name === 'AbortError')) aviso('Could not ' + (soloGuardar ? 'download' : 'share') + ' the photo. ' + String(e && e.message || e)); }
  b.disabled = false;
}
function ponerOculto(v){ document.body.classList.toggle('fv-oculto', v); try{ localStorage.setItem(OCULTO, v ? '1' : '0'); }catch{} }

export function conectar(){
  fotos.alAbrirFoto(abrir);
  // Una foto recién subida (o su miniatura que llega después) entra a la tira y al contador sin salir y volver.
  fotos.alCambiarLista(() => {
    if(!F || $('#pFoto').hidden || fotos.fijarVisor(F.id) < 0) return;
    const lista = fotos.visorLista(); const urls = fotos.urlsMini(); const i = fotos.visorIndice();
    if(lista.map(f => f.id + (urls[f.id] ? '+' : '')).join(',') + '|' + i === TIRA_CLAVE) return;
    $('#fvN').textContent = (i + 1) + ' / ' + lista.length; pintarTira();
  });
  $('#fvAtras').addEventListener('click', () => editor.salir(volverAGaleria));
  $('#fvAnt').addEventListener('click', () => otraFoto(-1));
  $('#fvSig').addEventListener('click', () => otraFoto(1));
  $('#fvTelCancelar').addEventListener('click', () => editor.salir());
  $('#fvTelGuardar').addEventListener('click', () => editor.guardarCopia(true));
  $('#fvMasTel').addEventListener('click', (e) => { e.stopPropagation();
    panel.abrirMenuEn(e.currentTarget, `<button type="button" data-fv-accion="detalles">${IC('info')}Photo Details</button><button type="button" data-fv-accion="favorita">${IC('corazon')}${F && F.favorita ? 'Remove from Favorites' : 'Add to Favorites'}</button><button type="button" data-fv-accion="mover">${IC('carpeta')}Move to Room</button>${puedeEditar(F) ? `<button type="button" class="rojo" data-fv-accion="papelera">${IC('basura')}Delete Photo</button>` : ''}`); });
  $('#fvGrande').addEventListener('click', () => fotos.abrirGrande());
  $('#fvAsa').addEventListener('click', () => ponerOculto(!document.body.classList.contains('fv-oculto')));
  $('#fvBajar').addEventListener('click', () => compartir(true));
  $('#fvCompartir').addEventListener('click', () => compartir(false));
  $('#fvEditar').addEventListener('click', () => { if(editor.activo()) editor.salir(); else editar(); });
  $('#fvCopia').addEventListener('click', () => { if(!editor.activo()) aviso('Tap "Edit Photo" first: "Save a Copy" saves the edited photo as a new one and keeps the original.'); });
  editor.conectar();
  $('#fvMas').addEventListener('click', (e) => { e.stopPropagation();
    panel.abrirMenuEn(e.currentTarget, `<button type="button" data-fv-accion="mover">${IC('carpeta')}Move to room</button><button type="button" data-fv-accion="grande">${IC('expandir')}Full screen</button>${puedeEditar(F) ? `<button type="button" class="rojo" data-fv-accion="papelera">${IC('archivo')}Delete photo</button>` : ''}`); });
  // Deslizar la foto con el dedo: anterior / siguiente.
  let x0 = null;
  $('#fvImg').addEventListener('touchstart', (e) => { x0 = e.touches.length === 1 ? e.touches[0].clientX : null; }, { passive:true });
  $('#fvImg').addEventListener('touchend', (e) => { if(x0 == null) return; const dx = e.changedTouches[0].clientX - x0; x0 = null; if(Math.abs(dx) > 50) fotos.irFoto(fotos.visorIndice() + (dx < 0 ? 1 : -1)); }, { passive:true });

  document.addEventListener('click', async (e) => {
    if(!$('#pFoto') || $('#pFoto').hidden || !F) return;
    const q = (s) => e.target.closest(s); let el;
    if((el = q('[data-fv-ir]'))){ fotos.irFoto(Number(el.dataset.fvIr)); return; }
    if((el = q('[data-fv-tel]'))){ const a = el.dataset.fvTel;
      if(a === 'compartir') compartir(false); else if(a === 'bajar') compartir(true); else if(a === 'editar') editar(); else if(a === 'borrar') borrar();
      return; }
    if(!editor.activo() && (q('#fvVelo') || q('[data-fv-cerrar-detalles]'))){ detalles(false); return; }
    if((el = q('[data-fv-accion]'))){ panel.cerrarMenu(); const a = el.dataset.fvAccion;
      if(a === 'grande') fotos.abrirGrande();
      else if(a === 'mover') moverFoto();
      else if(a === 'detalles') detalles(true);
      else if(a === 'favorita') favorita();
      else if(a === 'papelera') borrar();
      return; }
    if(q('[data-fv-mover]')){ moverFoto(); return; }
    if(q('[data-fv-nota]')){ EDIT_NOTA = true; pintarPanel(); const t = $('#fvNotaTxt'); if(t) t.focus(); return; }
    if(q('[data-fv-nota-no]')){ EDIT_NOTA = false; pintarPanel(); return; }
    if(q('[data-fv-nota-si]')){ const ok = await fotos.guardarNota(F.id, ($('#fvNotaTxt').value || '').trim()); if(!ok){ aviso('Could not save the description (only the manager or who took the photo can).'); return; } F = fotos.fotoActual() || F; EDIT_NOTA = false; pintarPanel(); return; }
    if(q('[data-fv-etq]')){ ABRIR_ETQ = !ABRIR_ETQ; pintarPanel(); return; }
    if((el = q('[data-fv-etq-color]'))){ ETQ_COLOR = el.dataset.fvEtqColor; const v = $('#fvEtqTxt') ? $('#fvEtqTxt').value : ''; pintarPanel(); if($('#fvEtqTxt')) $('#fvEtqTxt').value = v; return; }
    if((el = q('[data-fv-etq-poner]'))){ try{ await enviar('fotos_foto_etiquetas', 'POST', { foto_id: F.id, etiqueta_id: el.dataset.fvEtqPoner }); ETQ.push(el.dataset.fvEtqPoner); pintarPanel(); }catch(err){ aviso('Could not add the tag. ' + err.message); } return; }
    if((el = q('[data-fv-etq-quitar]'))){ try{ const f = await enviar('fotos_foto_etiquetas?foto_id=eq.' + encodeURIComponent(F.id) + '&etiqueta_id=eq.' + encodeURIComponent(el.dataset.fvEtqQuitar), 'DELETE'); if(!f.length) throw new Error('only the manager or who put it can remove it'); ETQ = ETQ.filter(x => x !== el.dataset.fvEtqQuitar); pintarPanel(); }catch(err){ aviso('Could not remove the tag. ' + err.message); } return; }
    if(q('[data-fv-etq-crear]')){ const nombre = ($('#fvEtqTxt').value || '').trim().slice(0, 40); if(!nombre) return;
      try{ let e2 = CAT.find(x => x.nombre.toLowerCase() === nombre.toLowerCase());
        if(!e2){ e2 = (await enviar('fotos_etiquetas', 'POST', { nombre, color: ETQ_COLOR, orden: CAT.length }))[0]; CAT.push(e2); }
        if(!ETQ.includes(e2.id)){ await enviar('fotos_foto_etiquetas', 'POST', { foto_id: F.id, etiqueta_id: e2.id }); ETQ.push(e2.id); }
        pintarPanel(); }catch(err){ aviso('Could not create the tag. ' + err.message); } return; }
    if(q('[data-fv-tarea]')){ ABRIR_TAREA = !ABRIR_TAREA; if(ABRIR_TAREA) await equipo(); pintarPanel(); const t = $('#fvTareaTxt'); if(t) t.focus(); return; }
    if(q('[data-fv-tarea-no]')){ ABRIR_TAREA = false; pintarPanel(); return; }
    if(q('[data-fv-tarea-si]')){ const texto = ($('#fvTareaTxt').value || '').trim(); if(!texto) return;
      const T = trabajos.proyectoAbierto(); if(!T) return;
      try{ const f = await enviar('fotos_tareas', 'POST', { trabajo_id: T.id, foto_id: F.id, texto, vence: $('#fvTareaVence').value || null, asignado: $('#fvTareaQuien').value || null });
        if(f[0]) TAREAS.push(f[0]); ABRIR_TAREA = false; pintarPanel(); }catch(err){ aviso('Could not add the task. ' + err.message); } return; }
    if((el = q('[data-fv-tarea-hecha]'))){ const t = TAREAS.find(x => x.id === el.dataset.fvTareaHecha); if(!t) return; const hecha = !t.hecha;
      try{ const f = await enviar('fotos_tareas?id=eq.' + encodeURIComponent(t.id), 'PATCH', { hecha, hecha_at: hecha ? new Date().toISOString() : null, hecha_por: hecha ? yo() : null }); if(f[0]) Object.assign(t, f[0]); pintarPanel(); }catch(err){ aviso('Could not save. ' + err.message); } return; }
    if((el = q('[data-fv-tarea-menu]'))){ e.stopPropagation(); panel.abrirMenuEn(el, `<button type="button" class="rojo" data-fv-borrar-tarea="${esc(el.dataset.fvTareaMenu)}">${IC('archivo')}Delete task</button>`); return; }
    if((el = q('[data-fv-borrar-tarea]'))){ panel.cerrarMenu(); if(!confirm('Delete this task?')) return; try{ const f = await enviar('fotos_tareas?id=eq.' + encodeURIComponent(el.dataset.fvBorrarTarea), 'DELETE'); if(!f.length) throw new Error('only the manager or who created it can'); TAREAS = TAREAS.filter(x => x.id !== el.dataset.fvBorrarTarea); pintarPanel(); }catch(err){ aviso('Could not delete. ' + err.message); } return; }
    if(q('[data-fv-com-foco]')){ const t = $('#fvComTxt'); if(t){ t.scrollIntoView({ block:'center' }); t.focus(); } return; }
    if(q('[data-fv-com-enviar]')){ comentar(); return; }
    if((el = q('[data-fv-com-menu]'))){ e.stopPropagation(); panel.abrirMenuEn(el, `<button type="button" class="rojo" data-fv-borrar-com="${esc(el.dataset.fvComMenu)}">${IC('archivo')}Delete comment</button>`); return; }
    if((el = q('[data-fv-borrar-com]'))){ panel.cerrarMenu(); if(!confirm('Delete this comment?')) return; try{ const f = await enviar('fotos_comentarios?id=eq.' + encodeURIComponent(el.dataset.fvBorrarCom), 'DELETE'); if(!f.length) throw new Error('only the manager or who wrote it can'); COMS = COMS.filter(x => x.id !== el.dataset.fvBorrarCom); pintarPanel(); }catch(err){ aviso('Could not delete. ' + err.message); } return; }
  });
  document.addEventListener('keydown', (e) => { if(e.key === 'Enter' && e.target.id === 'fvComTxt'){ e.preventDefault(); comentar(); } });
}
async function comentar(){
  const inp = $('#fvComTxt'); const texto = (inp.value || '').trim(); if(!texto) return;
  try{ const f = await enviar('fotos_comentarios', 'POST', { foto_id: F.id, texto }); if(f[0]) COMS.push(f[0]); inp.value = ''; pintarPanel(); }
  catch(err){ aviso('Could not post the comment. ' + err.message); }
}
// Editar: las herramientas salen donde estaba "Photo Details"; "Save a Copy" sube la foto editada como una nueva.
// La de 1600 px ya viene firmada (la ventana firma toda la lista), así que el editor abre al instante;
// la ORIGINAL solo hace falta al guardar y se firma ahí (firmarOriginal).
let ABRIENDO = false;
async function editar(){
  const f = F; if(!f || ABRIENDO) return; aviso('');
  ABRIENDO = true; $('#fvEditar').classList.add('on');
  let w = {};
  try{ w = await fotos.urlsFirmadas([f.id], 'web'); } finally { ABRIENDO = false; }
  if(F !== f){ $('#fvEditar').classList.remove('on'); return; }
  if(!w[f.id]){ $('#fvEditar').classList.remove('on'); aviso('Could not open the photo to edit. Check your connection and try again.'); return; }
  document.body.classList.remove('fv-oculto'); detalles(false);
  editor.abrir({ foto: f, tel: esTelefono(), bandeja: $('#edTel'), cajaHoja: $('#edHoja'), velo: $('#fvVelo'), img: $('#fvImg'), panel: $('#fvPanel'), urlWeb: w[f.id],
    firmarOriginal: async () => (await fotos.urlsFirmadas([f.id], 'original'))[f.id] || null,
    guardar: (archivo) => fotos.subirCopia(archivo, { nivel_id: f.nivel_id, cuarto_id: f.cuarto_id }),
    alGuardar: (nueva) => { if(nueva && nueva.id) fotos.abrirVisor(nueva.id); },
    alSalir: () => { $('#fvEditar').classList.remove('on'); const img = $('#fvImg'); img.dataset.id = ''; if(F) { pintarFoto(); pintarTira(); pintarPanel(); } } });
}
export const editando = () => editor.activo();
// ---------- el teléfono (su diseño) ----------
const esTelefono = () => window.matchMedia('(max-width: 899px)').matches;
// Photo Details en el teléfono: una hoja que sube encima de la foto (la foto se sigue viendo detrás).
function detalles(si){ document.body.classList.toggle('fv-detalles', !!si); const v = $('#fvVelo'); if(v && !editor.activo()) v.hidden = !si; if(si){ const p = $('#fvPanel'); if(p) p.scrollTop = 0; } }
// Otra foto con las flechas: si se está editando, pregunta por los cambios y sigue editando la otra foto.
function otraFoto(d){
  const ir = () => fotos.irFoto(fotos.visorIndice() + d);
  if(!editor.activo()){ ir(); return; }
  editor.salir(() => { ir(); if(esTelefono()) editar(); });
}
// Back: a la galería, con la última foto vista a la vista y marcada.
function volverAGaleria(){
  const id = F && F.id; detalles(false); atras();
  if(!id) return;
  requestAnimationFrame(() => {
    $$('.pfoto.fv-ultima').forEach(x => x.classList.remove('fv-ultima'));
    const b = $$('[data-foto="' + CSS.escape(id) + '"]').find(x => x.offsetParent); if(!b) return;
    const card = b.closest('.pfoto') || b; card.classList.add('fv-ultima'); b.scrollIntoView({ block:'center' });
  });
}
// Borrar mientras se edita: primero se sale del editor (si no, se quedaba abierto encima de la siguiente foto y Apply
// guardaba una copia de la que se acababa de mandar a la papelera).
async function borrar(){ if(editor.activo()){ editor.salir(() => borrar()); return; } const err = await fotos.borrarFotoActual(); if(err === null) return; if(err) aviso(err); else { F = null; detalles(false); abrir(false); } }
async function favorita(){
  const f = F; if(!f) return;
  try{ const r = await authFetch('/rest/v1/fotos_fotos?id=eq.' + encodeURIComponent(f.id), { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ favorita: !f.favorita }) });
    if(!r.ok) throw new Error(r.status === 400 ? 'falta correr sql/fotos-06-foto.sql' : 'HTTP ' + r.status);
    const fila = (await r.json())[0]; if(!fila) throw new Error('only the manager or who took it can');
    f.favorita = !!fila.favorita; if(F === f){ $('#fvFav').hidden = !f.favorita; aviso(f.favorita ? 'Added to Favorites.' : 'Removed from Favorites.', true); } }
  catch(err){ aviso('Could not change Favorites. ' + String(err && err.message || err)); }
}
function moverFoto(){
  const f = F; if(!f) return;
  proyecto.escogerCuarto('Move photo to…', { nivel_id: f.nivel_id, cuarto_id: f.cuarto_id }, async (d) => {
    try{ await fotos.moverFotos([f.id], d); F = fotos.fotoActual() || f; pintarCabeza(); pintarPanel(); }
    catch(err){ aviso('Could not move it. ' + String(err && err.message || err)); }
  });
}
