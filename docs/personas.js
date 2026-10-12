// Scanova · personas: quién pide entrar (aprobar / rechazar) y el equipo. Solo el manager.
import { $, authFetch, irA, esManager } from './app.js';
import { esc, fechaCorta } from './trabajos.js';

let SOLICITUDES = [], EQUIPO = [];
export const estadoTxt = (st) => ({ active:'activo', paused:'en espera / pausado', removed:'sacado' }[st] || st || 'activo');

export async function contarPendientes(){
  if(!esManager()) return 0;
  const r = await authFetch('/rest/v1/fotos_solicitudes?select=user_id&estado=eq.pendiente');
  if(!r.ok) return 0;
  const f = await r.json(); return Array.isArray(f) ? f.length : 0;
}
export async function pintarConteo(){
  const b = $('#btnPersonas'), c = $('#personasConteo'); if(!b) return;
  b.hidden = !esManager(); if(b.hidden) return;
  const n = await contarPendientes();
  c.textContent = String(n); c.hidden = !n;
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
export function pintar(){
  const ls = $('#listaSolicitudes'), le = $('#listaEquipo'); if(!ls) return;
  ls.innerHTML = SOLICITUDES.length ? SOLICITUDES.map(s => `<div class="persona" data-user="${esc(s.user_id)}">
      <div class="nom">${esc(s.nombre || 'Sin nombre')}</div>
      <div class="sub">${esc(s.correo || '')} · pidió entrar ${esc(fechaCorta(s.created_at))}</div>
      <div class="acciones"><button type="button" class="btn btn-accent" data-decidir="si">Aprobar</button><button type="button" class="btn btn-danger" data-decidir="no">Rechazar</button></div>
    </div>`).join('') : '<p class="vacio">Nadie está esperando.</p>';
  const equipo = EQUIPO.filter(p => p.status !== 'removed');
  le.innerHTML = equipo.length ? equipo.map(p => `<div class="persona">
      <div class="nom">${esc(p.full_name || 'Sin nombre')}<span class="estado-chip ${p.status === 'paused' ? 'pausado' : ''}">${p.role === 'manager' ? 'manager' : esc(estadoTxt(p.status))}</span></div>
    </div>`).join('') : '<p class="vacio">Todavía no hay nadie en el equipo.</p>';
}
async function decidir(userId, aprobar){
  const aviso = $('#personasAviso'); aviso.textContent = '';
  const s = SOLICITUDES.find(x => x.user_id === userId); if(!s) return;
  if(!aprobar && !confirm('¿Rechazar a ' + (s.nombre || s.correo || 'esta persona') + '? No podrá entrar a Scanova.')) return;
  const r = await authFetch('/rest/v1/rpc/fotos_decidir_entrada', { method:'POST', body: JSON.stringify({ p_user: userId, p_aprobar: !!aprobar }) });
  const t = await r.text();
  if(!r.ok){ aviso.textContent = 'No se pudo. ' + (/solo_manager/.test(t) ? 'Solo el manager puede aprobar.' : ('(' + r.status + ')')); return; }
  await cargar(); await pintarConteo();
}
export function conectar(){
  $('#btnPersonas').addEventListener('click', () => { irA('pPersonas', 'pTrabajos'); cargar(); });
  $('#listaSolicitudes').addEventListener('click', (e) => {
    const b = e.target.closest('[data-decidir]'); if(!b) return;
    const fila = e.target.closest('[data-user]'); if(!fila) return;
    decidir(fila.dataset.user, b.dataset.decidir === 'si');
  });
}
