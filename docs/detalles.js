// Scanova · "Project Details" (diseño de Amilcar, 12 oct 2026): el panel de la derecha en la computadora y el cajón
// que entra desde la derecha en el teléfono. Customer, Project Users, Collaborators, Description, Tasks y Project Conversation.
// Lo que se guarda vive en sql/fotos-05-detalles.sql.
import { $, $$, authFetch, esManager, PERFIL } from './app.js?v=2026-10-13-6';
import * as trabajos from './trabajos.js?v=2026-10-13-6';

const esc = (v) => trabajos.esc(v);
const IC = (n) => '<svg class="ic"><use href="#i-' + n + '"/></svg>';

// ---------- lo puro ----------
export const iniciales = (n) => trabajos.iniciales(n);
export function horaCorta(iso, ahora = Date.now()){
  const d = new Date(iso); if(isNaN(d)) return '';
  const hoy = new Date(ahora); const mismoDia = d.toDateString() === hoy.toDateString();
  const hora = d.toLocaleTimeString('en-US', { hour:'numeric', minute:'2-digit' });
  return mismoDia ? 'Today ' + hora : d.toLocaleDateString('en-US', { month:'short', day:'numeric' }) + ' ' + hora;
}
// Las tareas: primero las que faltan (la más vieja arriba), después las hechas.
export const ordenarTareas = (l) => (l || []).slice().sort((a, b) => (a.hecha === b.hecha ? String(a.created_at).localeCompare(String(b.created_at)) : (a.hecha ? 1 : -1)));
export function usuariosHtml(ids, nombreDe){
  if(!ids.length) return '<p class="pdet-vacio">No one assigned yet.</p>';
  return '<div class="pdet-avs">' + ids.map(id => { const n = nombreDe(id) || ''; return `<span class="pdet-av" title="${esc(n)}" translate="no">${esc(iniciales(n))}</span>`; }).join('') + '</div>';
}
export function tareaHtml(t, puedeBorrar){
  return `<div class="pdet-tarea${t.hecha ? ' hecha' : ''}"><label><input type="checkbox" data-tarea-hecha="${esc(t.id)}"${t.hecha ? ' checked' : ''}><span>${esc(t.texto)}</span></label>${puedeBorrar ? `<button type="button" class="pdet-x" data-tarea-borrar="${esc(t.id)}" aria-label="Delete task">✕</button>` : ''}</div>`;
}
export function comentarioHtml(c, nombre, puedeBorrar, ahora){
  return `<div class="pdet-com"><span class="pdet-av chico" translate="no">${esc(iniciales(nombre))}</span><div class="pdet-com-cuerpo"><div class="pdet-com-cab"><b>${esc(nombre)}</b><small>${esc(horaCorta(c.created_at, ahora))}</small>${puedeBorrar ? `<button type="button" class="pdet-x" data-com-borrar="${esc(c.id)}" aria-label="Delete comment">✕</button>` : ''}</div><p>${esc(c.texto)}</p></div></div>`;
}

// ---------- estado ----------
let T = null, MIEMBROS = [], COLAB = [], TAREAS = [], COMS = [], EQUIPO = [], FALTA_SQL = false, EDIT_DESC = false, NUEVA_TAREA = false;
let NOMBRE_FN = () => '', CARGAR_NOMBRES = async () => {}, AL_CAMBIO = () => {};
export const usarNombres = (fn, cargarFn) => { NOMBRE_FN = fn; if(cargarFn) CARGAR_NOMBRES = cargarFn; };
export const alCambiar = (fn) => { AL_CAMBIO = fn; };
export const tareas = () => TAREAS;
export const comentarios = () => COMS;
const yo = () => (PERFIL && PERFIL.id) || '';
const puedeBorrar = (fila) => esManager() || fila.created_by === yo();
const puedeEscogerGente = () => !!T && (esManager() || T.created_by === yo());

async function leer(tabla, extra){
  const r = await authFetch('/rest/v1/' + tabla + '?trabajo_id=eq.' + encodeURIComponent(T.id) + '&select=*' + (extra || ''));
  if(r.status === 404){ FALTA_SQL = true; return []; }
  return r.ok ? await r.json() : [];
}
async function cargar(){
  if(!T) return; const id = T.id; FALTA_SQL = false;
  const [m, c, ta, co] = await Promise.all([leer('fotos_miembros', '&order=created_at.asc'), leer('fotos_colaboradores', '&order=created_at.asc'), leer('fotos_tareas', '&order=created_at.asc'), leer('fotos_conversacion', '&order=created_at.asc&limit=500'), CARGAR_NOMBRES().catch(() => {})]);
  if(!T || T.id !== id) return;
  MIEMBROS = m.map(x => x.user_id); COLAB = c; TAREAS = ta; COMS = co;
  pintar(); AL_CAMBIO();
}

// ---------- dónde se ve: panel (computadora) o cajón (teléfono) ----------
const esCompu = () => typeof matchMedia === 'function' && matchMedia('(min-width:900px)').matches;
function colocar(){
  const c = $('#detContenido'); if(!c) return;
  const destino = esCompu() ? $('#pDetallesSlot') : $('#cajonCaja');
  if(destino && c.parentNode !== destino) destino.appendChild(c);
  if(esCompu()) cerrarCajon();
}
const OCULTO = 'scanova.detallesOculto';
function leerOculto(){ try{ const v = localStorage.getItem(OCULTO); if(v === '1') return true; if(v === '0') return false; }catch{} return (window.innerWidth || 0) < 1280; }
function ponerOculto(v){ document.body.classList.toggle('det-oculto', v); try{ localStorage.setItem(OCULTO, v ? '1' : '0'); }catch{} }
export function abrirPanel(){ if(esCompu()) ponerOculto(false); else { colocar(); $('#cajonDetalles').hidden = false; document.body.classList.add('con-cajon'); } }
function cerrarPanel(){ if(esCompu()) ponerOculto(true); else cerrarCajon(); }
function cerrarCajon(){ const k = $('#cajonDetalles'); if(k && !k.hidden){ k.hidden = true; document.body.classList.remove('con-cajon'); } }

export function abrir(t){
  T = t; MIEMBROS = []; COLAB = []; TAREAS = []; COMS = []; EDIT_DESC = false; NUEVA_TAREA = false;
  document.body.classList.toggle('det-oculto', leerOculto());
  colocar(); pintar(); cargar();
}
export function actualizarTrabajo(t){ if(T && t && T.id === t.id){ T = t; pintar(); } }

// ---------- pintar ----------
export function pintar(){
  const c = $('#detContenido'); if(!c || !T) return;
  const borrador = $('#detComTxt') ? $('#detComTxt').value : '';
  const nom = (id) => NOMBRE_FN(id) || '';
  const ahora = Date.now();
  const tel = trabajos.telDigitos(T.telefono);
  const aviso = FALTA_SQL ? '<p class="parche izq">Users, collaborators, tasks and the conversation are not installed on the server yet (falta correr sql/fotos-05-detalles.sql).</p>' : '';
  const editarIc = (attr, label) => `<button type="button" class="pdet-ed" ${attr} aria-label="${label}">${IC('lapiz')}</button>`;
  const masIc = (attr, label) => `<button type="button" class="pdet-ed" ${attr} aria-label="${label}">${IC('mas-circ')}</button>`;
  c.innerHTML = `<div class="pdet-cab"><h2>Project Details</h2><button type="button" class="pdet-cerrar" data-det-cerrar aria-label="Close">✕</button></div>${aviso}
    <section class="pdet-card"><div class="pdet-t"><h3>Customer</h3>${editarIc('data-det-editar', 'Edit customer')}</div>
      <div class="pdet-cliente"><span class="pdet-persona">${IC('persona')}</span><div><b>${esc(T.cliente)}</b><span>${esc(T.direccion || '')}</span>
      ${tel ? `<a href="tel:${esc(tel)}">${esc(T.telefono)}</a>` : ''}${T.correo ? `<a href="mailto:${esc(T.correo)}">${esc(T.correo)}</a>` : ''}</div></div></section>
    <section class="pdet-card"><div class="pdet-t"><h3>Project Users (${MIEMBROS.length})</h3>${puedeEscogerGente() ? editarIc('data-det-usuarios', 'Choose project users') : ''}</div>${usuariosHtml(MIEMBROS, nom)}</section>
    <section class="pdet-card"><div class="pdet-t"><h3>Collaborators</h3>${masIc('data-det-colab', 'Add collaborator')}</div>
      ${COLAB.map(x => `<div class="pdet-colab"><div><b>${esc(x.nombre)}</b><small>${esc([x.rol, x.empresa].filter(Boolean).join(' · '))}</small>${x.telefono ? `<a href="tel:${esc(trabajos.telDigitos(x.telefono))}">${esc(x.telefono)}</a>` : ''}${x.correo ? `<a href="mailto:${esc(x.correo)}">${esc(x.correo)}</a>` : ''}</div>${puedeBorrar(x) ? `<button type="button" class="pdet-x" data-colab-borrar="${esc(x.id)}" aria-label="Remove collaborator">✕</button>` : ''}</div>`).join('')}
      <button type="button" class="pdet-link" data-det-colab>${IC('persona-mas')}Add Collaborator</button></section>
    <section class="pdet-card"><div class="pdet-t"><h3>Description</h3>${EDIT_DESC ? '' : editarIc('data-det-desc', 'Edit description')}</div>
      ${EDIT_DESC ? `<textarea class="pdet-area" id="detDescTxt" placeholder="Water damage mitigation and restoration project.">${esc(T.descripcion || '')}</textarea><div class="pdet-fila"><button type="button" class="btn btn-outline btn-chico" data-desc-cancelar>Cancel</button><button type="button" class="btn btn-accent btn-chico" data-desc-guardar>Save</button></div>`
        : `<p class="${T.descripcion ? 'pdet-texto' : 'pdet-vacio'}">${esc(T.descripcion || 'Add a short description of the job.')}</p>`}</section>
    <section class="pdet-card"><div class="pdet-t"><h3>Tasks${TAREAS.length ? ' (' + TAREAS.filter(x => !x.hecha).length + ' open)' : ''}</h3>${masIc('data-det-tarea', 'New task')}</div>
      ${ordenarTareas(TAREAS).map(x => tareaHtml(x, puedeBorrar(x))).join('')}
      ${NUEVA_TAREA ? `<div class="pdet-nueva"><input type="text" id="detTareaTxt" maxlength="300" placeholder="What needs to be done?"><button type="button" class="btn btn-accent btn-chico" data-tarea-guardar>Add</button></div>` : `<button type="button" class="pdet-link" data-det-tarea>${IC('mas')}New Task</button>${TAREAS.length ? '' : '<p class="pdet-vacio">Add to-dos to keep your project on track.</p>'}`}</section>
    <section class="pdet-card"><div class="pdet-t"><h3>Project Conversation</h3></div>
      <div class="pdet-coms">${COMS.map(x => comentarioHtml(x, nom(x.created_by) || 'Someone', puedeBorrar(x), ahora)).join('')}</div>
      <div class="pdet-escribir"><input type="text" id="detComTxt" maxlength="2000" placeholder="Add a comment..."><button type="button" class="pdet-arroba" data-com-arroba aria-label="Mention someone">@</button></div>
      <div class="pdet-arroba-lista" id="detArroba" hidden></div>
      <button type="button" class="btn btn-suave btn-chico" data-com-post>Post</button></section>
    <p class="aviso" id="detAviso"></p>`;
  const coms = c.querySelector('.pdet-coms'); if(coms) coms.scrollTop = coms.scrollHeight;
  if(borrador && $('#detComTxt')) $('#detComTxt').value = borrador;
}
function aviso(txt){ const a = $('#detAviso'); if(a) a.textContent = txt || ''; }
async function enviar(ruta, metodo, cuerpo){
  const r = await authFetch('/rest/v1/' + ruta, { method: metodo, headers:{ Prefer:'return=representation' }, body: cuerpo ? JSON.stringify(cuerpo) : undefined });
  if(r.status === 404) throw new Error('falta correr sql/fotos-05-detalles.sql');
  if(!r.ok) throw new Error('HTTP ' + r.status);
  return r.json();
}

// ---------- hojas: escoger gente y agregar colaborador ----------
async function abrirUsuarios(){
  if(!EQUIPO.length){ const r = await authFetch('/rest/v1/profiles?select=id,full_name,role,status&order=full_name.asc'); EQUIPO = r.ok ? (await r.json()).filter(p => p.status === 'active' || p.role === 'manager') : []; }
  $('#detHojaTitulo').textContent = 'Project Users';
  $('#detHojaCuerpo').innerHTML = (EQUIPO.length ? EQUIPO.map(p => `<label class="det-gente"><input type="checkbox" value="${esc(p.id)}"${MIEMBROS.includes(p.id) ? ' checked' : ''}><span class="pdet-av chico" translate="no">${esc(iniciales(p.full_name))}</span><span>${esc(p.full_name || 'No name')}<small>${p.role === 'manager' ? 'Manager' : 'Crew'}</small></span></label>`).join('') : '<p class="vacio">No team members found.</p>') +
    '<button type="button" class="btn btn-accent btn-block" data-usuarios-guardar>Save</button><p class="aviso" id="detHojaAviso"></p>';
  $('#detHoja').hidden = false;
}
function abrirColab(){
  $('#detHojaTitulo').textContent = 'Add Collaborator';
  $('#detHojaCuerpo').innerHTML = `<div class="field"><label for="colNombre">Name</label><input type="text" id="colNombre" autocomplete="off" placeholder="John Smith"></div>
    <div class="field"><label for="colRol">Role <span class="hint">optional</span></label><input type="text" id="colRol" autocomplete="off" placeholder="Adjuster, owner, contractor…"></div>
    <div class="field"><label for="colEmpresa">Company <span class="hint">optional</span></label><input type="text" id="colEmpresa" autocomplete="off"></div>
    <div class="field"><label for="colTel">Phone <span class="hint">optional</span></label><input type="tel" id="colTel" autocomplete="off"></div>
    <div class="field"><label for="colCorreo">Email <span class="hint">optional</span></label><input type="email" id="colCorreo" autocomplete="off"></div>
    <button type="button" class="btn btn-accent btn-block" data-colab-guardar>Add Collaborator</button><p class="aviso" id="detHojaAviso"></p>`;
  $('#detHoja').hidden = false; setTimeout(() => { const n = $('#colNombre'); if(n) n.focus(); }, 50);
}
const cerrarHoja = () => { $('#detHoja').hidden = true; };

async function guardarUsuarios(){
  const elegidos = $$('#detHojaCuerpo input[type=checkbox]').filter(x => x.checked).map(x => x.value);
  const poner = elegidos.filter(id => !MIEMBROS.includes(id)), quitar = MIEMBROS.filter(id => !elegidos.includes(id));
  try{
    if(poner.length) await enviar('fotos_miembros', 'POST', poner.map(user_id => ({ trabajo_id: T.id, user_id })));
    for(const id of quitar) await enviar('fotos_miembros?trabajo_id=eq.' + encodeURIComponent(T.id) + '&user_id=eq.' + encodeURIComponent(id), 'DELETE');
    cerrarHoja(); await cargar();
  }catch(e){ $('#detHojaAviso').textContent = 'Could not save. ' + String(e && e.message || e); }
}
async function guardarColab(){
  const v = (id) => ($('#' + id).value || '').trim(); const nombre = v('colNombre');
  if(!nombre){ $('#detHojaAviso').textContent = 'Write the name.'; return; }
  try{ const f = await enviar('fotos_colaboradores', 'POST', { trabajo_id: T.id, nombre, rol: v('colRol') || null, empresa: v('colEmpresa') || null, telefono: v('colTel') || null, correo: v('colCorreo') || null });
    if(f[0]) COLAB.push(f[0]); cerrarHoja(); pintar(); }
  catch(e){ $('#detHojaAviso').textContent = 'Could not save. ' + String(e && e.message || e); }
}
async function guardarDesc(){
  const txt = ($('#detDescTxt').value || '').trim();
  const r = await authFetch('/rest/v1/fotos_trabajos?id=eq.' + encodeURIComponent(T.id), { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ descripcion: txt || null, updated_at: new Date().toISOString() }) });
  const f = r.ok ? await r.json() : [];
  if(!f.length){ aviso(r.status === 400 ? 'The description is not installed yet (falta correr sql/fotos-05-detalles.sql).' : 'Could not save (only the manager or who created the project can).'); return; }
  T.descripcion = f[0].descripcion; EDIT_DESC = false; trabajos.reemplazar(f[0]); pintar();
}
async function nuevaTarea(){
  const txt = ($('#detTareaTxt').value || '').trim(); if(!txt){ NUEVA_TAREA = false; pintar(); return; }
  try{ const f = await enviar('fotos_tareas', 'POST', { trabajo_id: T.id, texto: txt }); if(f[0]) TAREAS.push(f[0]); NUEVA_TAREA = false; pintar(); AL_CAMBIO(); }
  catch(e){ aviso('Could not add the task. ' + String(e && e.message || e)); }
}
async function marcarTarea(id, hecha){
  try{ const f = await enviar('fotos_tareas?id=eq.' + encodeURIComponent(id), 'PATCH', { hecha, hecha_at: hecha ? new Date().toISOString() : null, hecha_por: hecha ? yo() : null });
    const i = TAREAS.findIndex(x => x.id === id); if(f[0] && i >= 0) TAREAS[i] = f[0]; pintar(); AL_CAMBIO(); }
  catch(e){ aviso('Could not save. ' + String(e && e.message || e)); pintar(); }
}
async function borrar(tabla, lista, id, pregunta){
  if(!confirm(pregunta)) return;
  try{ const f = await enviar(tabla + '?id=eq.' + encodeURIComponent(id), 'DELETE'); if(!f.length) throw new Error('only the manager or who added it can');
    const i = lista.findIndex(x => x.id === id); if(i >= 0) lista.splice(i, 1); pintar(); AL_CAMBIO(); }
  catch(e){ aviso('Could not delete. ' + String(e && e.message || e)); }
}
async function postear(){
  const inp = $('#detComTxt'); const txt = (inp.value || '').trim(); if(!txt) return;
  try{ const f = await enviar('fotos_conversacion', 'POST', { trabajo_id: T.id, texto: txt }); if(f[0]) COMS.push(f[0]); inp.value = ''; pintar(); AL_CAMBIO(); }
  catch(e){ aviso('Could not post. ' + String(e && e.message || e)); }
}
async function arroba(){
  const caja = $('#detArroba'); if(!caja) return;
  if(!caja.hidden){ caja.hidden = true; return; }
  if(!EQUIPO.length){ const r = await authFetch('/rest/v1/profiles?select=id,full_name,role,status&order=full_name.asc'); EQUIPO = r.ok ? (await r.json()).filter(p => p.status === 'active' || p.role === 'manager') : []; }
  caja.innerHTML = EQUIPO.map(p => `<button type="button" data-mencion="${esc(p.full_name || '')}">@${esc(p.full_name || '')}</button>`).join('') || '<small>No team members.</small>';
  caja.hidden = false;
}

export function conectar(){
  if(typeof matchMedia === 'function'){ const mq = matchMedia('(min-width:900px)'); const f = () => colocar(); if(mq.addEventListener) mq.addEventListener('change', f); else if(mq.addListener) mq.addListener(f); }
  document.addEventListener('click', (e) => {
    const q = (s) => e.target.closest(s); let el;
    if(q('[data-det-abrir]')){ abrirPanel(); return; }
    if(q('[data-cerrar-cajon]')){ cerrarCajon(); return; }
    if(q('[data-det-hoja-cerrar]') || e.target.id === 'detHoja'){ cerrarHoja(); return; }
    if(!q('#detContenido') && !q('#detHoja')) return;
    if(!T) return;
    if(q('[data-det-cerrar]')){ cerrarPanel(); return; }
    if(q('[data-det-editar]')){ cerrarCajon(); trabajos.editar(T, 'pTrabajo'); return; }
    if(q('[data-det-usuarios]')){ abrirUsuarios(); return; }
    if(q('[data-usuarios-guardar]')){ guardarUsuarios(); return; }
    if(q('[data-det-colab]')){ abrirColab(); return; }
    if(q('[data-colab-guardar]')){ guardarColab(); return; }
    if((el = q('[data-colab-borrar]'))){ borrar('fotos_colaboradores', COLAB, el.dataset.colabBorrar, 'Remove this collaborator from the project?'); return; }
    if(q('[data-det-desc]')){ EDIT_DESC = true; pintar(); const a = $('#detDescTxt'); if(a) a.focus(); return; }
    if(q('[data-desc-cancelar]')){ EDIT_DESC = false; pintar(); return; }
    if(q('[data-desc-guardar]')){ guardarDesc(); return; }
    if(q('[data-det-tarea]')){ NUEVA_TAREA = true; pintar(); const a = $('#detTareaTxt'); if(a) a.focus(); return; }
    if(q('[data-tarea-guardar]')){ nuevaTarea(); return; }
    if((el = q('[data-tarea-borrar]'))){ borrar('fotos_tareas', TAREAS, el.dataset.tareaBorrar, 'Delete this task?'); return; }
    if((el = q('[data-com-borrar]'))){ borrar('fotos_conversacion', COMS, el.dataset.comBorrar, 'Delete this comment?'); return; }
    if(q('[data-com-arroba]')){ arroba(); return; }
    if((el = q('[data-mencion]'))){ const inp = $('#detComTxt'); inp.value = (inp.value.replace(/@$/, '') + (inp.value && !/\s$/.test(inp.value) ? ' ' : '') + '@' + el.dataset.mencion + ' '); $('#detArroba').hidden = true; inp.focus(); return; }
    if(q('[data-com-post]')){ postear(); return; }
  });
  document.addEventListener('change', (e) => { const el = e.target.closest && e.target.closest('[data-tarea-hecha]'); if(el) marcarTarea(el.dataset.tareaHecha, el.checked); });
  document.addEventListener('keydown', (e) => {
    if(e.key !== 'Enter') return;
    if(e.target.id === 'detComTxt'){ e.preventDefault(); postear(); }
    else if(e.target.id === 'detTareaTxt'){ e.preventDefault(); nuevaTarea(); }
  });
}
