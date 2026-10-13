// Scanova · personas: quién pide entrar (aprobar / rechazar) y el equipo. Solo el manager.
import { $, $$, authFetch, esManager } from './app.js?v=2026-10-14-2';
import { esc, fechaCorta, iniciales } from './trabajos.js?v=2026-10-14-2';

let SOLICITUDES = [], EQUIPO = [];
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
  if(rs.status === 404){ aviso.textContent = 'Esta parte todavía no está instalada en el servidor: falta correr sql/fotos-02-aprobacion.sql.'; }
  SOLICITUDES = rs.ok ? await rs.json() : [];
  EQUIPO = re.ok ? await re.json() : [];
  pintar();
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
  // Abrir Personas se hace desde la barra lateral / pestaña de abajo (app.js, data-nav="personas").
  $('#listaSolicitudes').addEventListener('click', (e) => {
    const b = e.target.closest('[data-decidir]'); if(!b) return;
    const fila = e.target.closest('[data-user]'); if(!fila) return;
    decidir(fila.dataset.user, b.dataset.decidir === 'si');
  });
}
