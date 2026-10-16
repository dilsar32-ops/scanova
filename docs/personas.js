// Scanova · personas: quién pide entrar (aprobar / rechazar) y el equipo. Solo el manager.
import { $, $$, authFetch, esManager } from './app.js?v=2026-10-16-12';
import { esc, fechaCorta, iniciales } from './trabajos.js?v=2026-10-16-12';

let SOLICITUDES = [], EQUIPO = [], INVITACIONES = [], INV_LISTA = true, EMPRESAS = [], DUENO = false;
export const estadoTxt = (st) => ({ active:'activo', paused:'en espera / pausado', removed:'sacado' }[st] || st || 'activo');

export async function contarPendientes(){
  if(!esManager()) return 0;
  const r = await authFetch('/rest/v1/fotos_solicitudes?select=user_id&estado=eq.pendiente');
  if(!r.ok) return 0;
  const f = await r.json(); return Array.isArray(f) ? f.length : 0;
}
// Quién pide entrar (solo el manager): el número rojo en Settings y en More, y el puntito de la campana.
export async function pintarConteo(){
  const n = esManager() ? await contarPendientes() : 0;
  ['#ajustesConteo', '#masConteo', '#pieConteo'].forEach(sel => { const c = $(sel); if(c){ c.textContent = String(n); c.hidden = !n; } });
  const p = $('#campanaPunto'); if(p){ p.hidden = !n; p.dataset.n = String(n); }
}
export async function cargar(){
  const aviso = $('#personasAviso'); aviso.textContent = '';
  $('#listaSolicitudes').innerHTML = '<p class="vacio">Cargando…</p>'; $('#listaEquipo').innerHTML = '';
  const [rs, re] = await Promise.all([
    authFetch('/rest/v1/fotos_solicitudes?select=user_id,nombre,correo,estado,created_at&estado=eq.pendiente&order=created_at.asc'),
    authFetch('/rest/v1/profiles?select=id,full_name,role,status&order=full_name.asc'),
  ]);
  cargarInvitaciones(); cargarEmpresas();
  if(rs.status === 404){ aviso.textContent = 'Esta parte todavía no está instalada en el servidor: falta correr sql/fotos-02-aprobacion.sql.'; }
  SOLICITUDES = rs.ok ? await rs.json() : [];
  EQUIPO = re.ok ? await re.json() : [];
  pintar();
}
// ---------- invitar por enlace (sql/fotos-10-invitaciones.sql) ----------
// Pura: el enlace que se manda. Siempre a scanova360.com (en el aparato la página no vive en https).
export function enlaceInvitacion(token, href, param = 'invitacion'){
  let base = 'https://scanova360.com/';
  try{ const u = new URL(href); if(u.protocol === 'https:' || u.protocol === 'http:') base = u.origin + u.pathname.replace(/[^/]*$/, ''); }catch{}
  return base + '?' + param + '=' + encodeURIComponent(token);
}
// Pura: en qué quedó una invitación.
export function estadoInvitacion(v, ahora = Date.now()){
  if(v.anulada_at) return 'anulada';
  if(v.usada_at) return 'usada';
  return Date.parse(v.vence_at) < ahora ? 'vencida' : 'valida';
}
// Pura: una invitación en la lista (las sin usar se pueden anular).
export function invitacionHtml(v, ahora = Date.now()){
  const st = estadoInvitacion(v, ahora);
  const sub = st === 'usada' ? 'Entró ' + esc(v.usada_nombre || '') + ' · ' + esc(fechaCorta(v.usada_at))
    : st === 'valida' ? 'Sin usar · vence ' + esc(fechaCorta(v.vence_at))
    : st === 'vencida' ? 'Venció ' + esc(fechaCorta(v.vence_at)) : 'Anulada';
  const chip = { valida:'esperando', usada:'usada', vencida:'vencida', anulada:'anulada' }[st];
  return `<div class="persona invitacion" data-token="${esc(v.token)}"><span class="avatar">${esc(iniciales(v.usada_nombre || v.nombre || '?'))}</span>
    <div><div class="nom">${esc(v.nombre || v.usada_nombre || 'Invitación')}<span class="estado-chip inv-${st}">${chip}</span></div><div class="sub">${sub}</div></div>
    ${st === 'valida' ? `<div class="persona-acciones"><button type="button" class="btn btn-outline" data-inv="mandar">Mandar</button><button type="button" class="btn btn-outline btn-rojo" data-inv="anular">Anular</button></div>` : ''}</div>`;
}
async function cargarInvitaciones(){
  const l = $('#listaInvitaciones'); if(!l) return;
  const r = await authFetch('/rest/v1/fotos_invitaciones?select=token,nombre,created_at,vence_at,usada_nombre,usada_at,anulada_at&order=created_at.desc&limit=30');
  INV_LISTA = r.status !== 404;
  INVITACIONES = r.ok ? await r.json() : [];
  pintarInvitaciones();
}
function pintarInvitaciones(){
  const l = $('#listaInvitaciones'); if(!l) return;
  l.innerHTML = !INV_LISTA ? '<p class="vacio">Para invitar falta correr sql/fotos-10-invitaciones.sql en el servidor.</p>'
    : INVITACIONES.length ? INVITACIONES.map(v => invitacionHtml(v)).join('') : '';
}
async function mandarEnlace(enlace, nombre, texto0){
  const texto = texto0 || ((nombre ? nombre + ', l' : 'L') + 'o invito a Scanova360. Toque este enlace, cree su cuenta y ya entra:');
  try{ if(navigator.share){ await navigator.share({ title:'Scanova360', text: texto, url: enlace }); return 'ok'; } }catch(e){ if(e && e.name === 'AbortError') return 'cancelo'; }
  return copiar(enlace) ? 'copiado' : 'no';
}
function copiar(t, sel = '#invEnlace'){
  try{ if(navigator.clipboard && navigator.clipboard.writeText){ navigator.clipboard.writeText(t); return true; } }catch{}
  const i = $(sel); if(i){ i.value = t; i.select(); try{ return document.execCommand('copy'); }catch{} } return false;
}
async function crearInvitacion(){
  const aviso = $('#personasAviso'); aviso.classList.remove('ok'); aviso.textContent = '';
  const nombre = ($('#invNombre').value || '').trim();
  const b = $('#btnInvitar'); b.disabled = true;
  try{
    const r = await authFetch('/rest/v1/rpc/fotos_invitar', { method:'POST', body: JSON.stringify({ p_nombre: nombre || null }) });
    const t = await r.text();
    if(r.status === 404) throw new Error('Para invitar falta correr sql/fotos-10-invitaciones.sql en el servidor.');
    if(!r.ok) throw new Error(/solo_manager/.test(t) ? 'Solo el manager puede invitar.' : 'No se pudo crear el enlace (' + r.status + ').');
    const d = JSON.parse(t);
    const enlace = enlaceInvitacion(d.token, location.href);
    $('#invEnlace').value = enlace; $('#invHechoT').textContent = nombre ? 'Enlace para ' + nombre : 'Enlace listo';
    $('#invHecho').hidden = false; $('#invHecho').dataset.nombre = nombre; $('#invNombre').value = '';
    await cargarInvitaciones();
  }catch(e){ aviso.textContent = String(e && e.message || e); }
  finally{ b.disabled = false; }
}
// ---------- empresas nuevas (sql/fotos-11-empresas.sql): solo el dueño de Scanova360 ----------
// Pura: una invitación de empresa en la lista (la usada dice qué empresa se creó).
export function empresaInvHtml(v, ahora = Date.now()){
  const st = estadoInvitacion(v, ahora);
  const sub = st === 'usada' ? 'Creó ' + esc(v.empresa_creada || 'su empresa') + ' · ' + esc(fechaCorta(v.usada_at))
    : st === 'valida' ? 'Sin usar · vence ' + esc(fechaCorta(v.vence_at)) + (v.para ? ' · para ' + esc(v.para) : '')
    : st === 'vencida' ? 'Venció ' + esc(fechaCorta(v.vence_at)) : 'Anulada';
  const chip = { valida:'esperando', usada:'registrada', vencida:'vencida', anulada:'anulada' }[st];
  const titulo = v.empresa_creada || v.empresa || 'Empresa nueva';
  return `<div class="persona invitacion" data-token="${esc(v.token)}"><span class="avatar">${esc(iniciales(titulo))}</span>
    <div><div class="nom">${esc(titulo)}<span class="estado-chip inv-${st}">${chip}</span></div><div class="sub">${sub}</div></div>
    ${st === 'valida' ? `<div class="persona-acciones"><button type="button" class="btn btn-outline" data-emp="mandar">Mandar</button><button type="button" class="btn btn-outline btn-rojo" data-emp="anular">Anular</button></div>` : ''}</div>`;
}
const textoEmpresa = (v) => (v && v.para ? v.para + ', l' : 'L') + 'o invito a registrar ' + (v && v.empresa ? v.empresa : 'su empresa') + ' en Scanova360. Toque este enlace, cree su cuenta y queda como manager:';
async function cargarEmpresas(){
  const b = $('#bloqueEmpresas'); if(!b) return;
  const r = await authFetch('/rest/v1/rpc/fotos_soy_dueno', { method:'POST', body:'{}' });
  DUENO = r.ok ? (await r.json()) === true : false;
  b.hidden = !DUENO; if(!DUENO) return;
  const l = await authFetch('/rest/v1/fotos_invitaciones_empresa?select=token,empresa,para,created_at,vence_at,usada_at,empresa_creada,anulada_at&order=created_at.desc&limit=30');
  EMPRESAS = l.ok ? await l.json() : [];
  $('#listaEmpresas').innerHTML = EMPRESAS.map(v => empresaInvHtml(v)).join('');
}
async function crearInvEmpresa(){
  const aviso = $('#empAviso'); aviso.classList.remove('ok'); aviso.textContent = '';
  const empresa = ($('#empNombre').value || '').trim(), para = ($('#empPara').value || '').trim();
  const b = $('#btnEmpInvitar'); b.disabled = true;
  try{
    const r = await authFetch('/rest/v1/rpc/fotos_invitar_empresa', { method:'POST', body: JSON.stringify({ p_empresa: empresa || null, p_para: para || null }) });
    const t = await r.text();
    if(r.status === 404) throw new Error('Falta correr sql/fotos-11-empresas.sql en el servidor.');
    if(!r.ok) throw new Error(/solo_dueno/.test(t) ? 'Solo el dueño de Scanova360 puede invitar empresas.' : 'No se pudo crear el enlace (' + r.status + ').');
    const d = JSON.parse(t);
    $('#empEnlace').value = enlaceInvitacion(d.token, location.href, 'empresa');
    $('#empHechoT').textContent = 'Enlace para ' + (empresa || para || 'la empresa nueva');
    $('#empHecho').hidden = false; $('#empHecho').dataset.empresa = empresa; $('#empHecho').dataset.para = para;
    $('#empNombre').value = ''; $('#empPara').value = '';
    await cargarEmpresas();
  }catch(e){ aviso.textContent = String(e && e.message || e); }
  finally{ b.disabled = false; }
}
// Pura: una persona del equipo (avatar con iniciales, nombre y su estado).
export function personaHtml(p){
  const chip = p.role === 'manager' ? 'manager' : esc(estadoTxt(p.status));
  return `<div class="persona"><span class="avatar">${esc(iniciales(p.full_name))}</span>
    <div><div class="nom">${esc(p.full_name || 'Sin nombre')}<span class="estado-chip ${p.status === 'paused' ? 'pausado' : ''}">${chip}</span></div></div></div>`;
}
// Pura: quien pide entrar, con Aprobar / Rechazar.
export function solicitudHtml(s){
  return `<div class="persona" data-user="${esc(s.user_id)}"><span class="avatar">${esc(iniciales(s.nombre))}</span>
    <div><div class="nom">${esc(s.nombre || 'Sin nombre')}</div><div class="sub">${esc(s.correo || '')} · pidió entrar ${esc(fechaCorta(s.created_at))}</div></div>
    <div class="persona-acciones"><button type="button" class="btn btn-accent" data-decidir="si">Aprobar</button><button type="button" class="btn btn-outline btn-rojo" data-decidir="no">Rechazar</button></div></div>`;
}
export function pintar(){
  const ls = $('#listaSolicitudes'), le = $('#listaEquipo'); if(!ls) return;
  ls.innerHTML = SOLICITUDES.length ? SOLICITUDES.map(solicitudHtml).join('') : '<p class="vacio">Nadie está esperando.</p>';
  const equipo = EQUIPO.filter(p => p.status !== 'removed');
  le.innerHTML = equipo.length ? equipo.map(personaHtml).join('') : '<p class="vacio">Todavía no hay nadie en el equipo.</p>';
}
async function decidir(userId, aprobar){
  const aviso = $('#personasAviso'); aviso.textContent = '';
  const s = SOLICITUDES.find(x => x.user_id === userId); if(!s) return;
  if(!aprobar && !confirm('¿Rechazar a ' + (s.nombre || s.correo || 'esta persona') + '? No podrá entrar a Scanova360.')) return;
  const r = await authFetch('/rest/v1/rpc/fotos_decidir_entrada', { method:'POST', body: JSON.stringify({ p_user: userId, p_aprobar: !!aprobar }) });
  const t = await r.text();
  if(!r.ok){ aviso.textContent = 'No se pudo. ' + (/solo_manager/.test(t) ? 'Solo el manager puede aprobar.' : ('(' + r.status + ')')); return; }
  await cargar(); await pintarConteo();
}
export function conectar(){
  $('#btnEmpInvitar').addEventListener('click', crearInvEmpresa);
  const avisoEmp = (r) => { const a = $('#empAviso'); a.classList.toggle('ok', r === 'copiado'); a.textContent = r === 'copiado' ? 'Enlace copiado. Péguelo en un mensaje.' : r === 'no' ? 'Copie el enlace de arriba y péguelo en un mensaje.' : ''; };
  $('#btnEmpCompartir').addEventListener('click', async () => { const h = $('#empHecho'); avisoEmp(await mandarEnlace($('#empEnlace').value, '', textoEmpresa({ empresa: h.dataset.empresa, para: h.dataset.para }))); });
  $('#btnEmpCopiar').addEventListener('click', () => { const ok = copiar($('#empEnlace').value, '#empEnlace'); avisoEmp(ok ? 'copiado' : 'no'); });
  $('#listaEmpresas').addEventListener('click', async (e) => {
    const b = e.target.closest('[data-emp]'); const fila = e.target.closest('[data-token]'); if(!b || !fila) return;
    const v = EMPRESAS.find(x => x.token === fila.dataset.token); if(!v) return;
    if(b.dataset.emp === 'mandar'){ avisoEmp(await mandarEnlace(enlaceInvitacion(v.token, location.href, 'empresa'), '', textoEmpresa(v))); return; }
    if(!confirm('¿Anular el enlace' + (v.empresa ? ' de ' + v.empresa : '') + '? Ya no servirá para registrar la empresa.')) return;
    const r = await authFetch('/rest/v1/rpc/fotos_anular_invitacion_empresa', { method:'POST', body: JSON.stringify({ p_token: v.token }) });
    if(!r.ok){ const a = $('#empAviso'); a.classList.remove('ok'); a.textContent = 'No se pudo anular (' + r.status + ').'; return; }
    await cargarEmpresas();
  });
  $('#btnInvitar').addEventListener('click', crearInvitacion);
  $('#invNombre').addEventListener('keydown', (e) => { if(e.key === 'Enter') crearInvitacion(); });
  $('#btnInvCompartir').addEventListener('click', async () => {
    const r = await mandarEnlace($('#invEnlace').value, $('#invHecho').dataset.nombre || '');
    const a = $('#personasAviso'); a.classList.toggle('ok', r === 'copiado'); a.textContent = r === 'copiado' ? 'Enlace copiado. Péguelo en un mensaje.' : r === 'no' ? 'Copie el enlace de arriba y péguelo en un mensaje.' : '';
  });
  $('#btnInvCopiar').addEventListener('click', () => { const ok = copiar($('#invEnlace').value); const a = $('#personasAviso'); a.classList.toggle('ok', ok); a.textContent = ok ? 'Enlace copiado. Péguelo en un mensaje.' : 'Toque el enlace, selecciónelo y cópielo.'; });
  $('#listaInvitaciones').addEventListener('click', async (e) => {
    const b = e.target.closest('[data-inv]'); const fila = e.target.closest('[data-token]'); if(!b || !fila) return;
    const v = INVITACIONES.find(x => x.token === fila.dataset.token); if(!v) return;
    const a = $('#personasAviso'); a.classList.remove('ok'); a.textContent = '';
    if(b.dataset.inv === 'mandar'){ const r = await mandarEnlace(enlaceInvitacion(v.token, location.href), v.nombre || ''); if(r === 'copiado'){ a.classList.add('ok'); a.textContent = 'Enlace copiado. Péguelo en un mensaje.'; } return; }
    if(!confirm('¿Anular la invitación' + (v.nombre ? ' de ' + v.nombre : '') + '? Ese enlace ya no servirá.')) return;
    const r = await authFetch('/rest/v1/rpc/fotos_anular_invitacion', { method:'POST', body: JSON.stringify({ p_token: v.token }) });
    if(!r.ok){ a.textContent = 'No se pudo anular (' + r.status + ').'; return; }
    await cargarInvitaciones();
  });
  // Abrir Personas se hace desde la barra lateral / pestaña de abajo (app.js, data-nav="personas").
  $('#listaSolicitudes').addEventListener('click', (e) => {
    const b = e.target.closest('[data-decidir]'); if(!b) return;
    const fila = e.target.closest('[data-user]'); if(!fila) return;
    decidir(fila.dataset.user, b.dataset.decidir === 'si');
  });
}
