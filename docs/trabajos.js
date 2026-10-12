// Scanova · trabajos: la lista, crear, abrir, editar, archivar. Nada de fotos todavía (paso 2).
import { $, $$, authFetch, irA, atras, esManager } from './app.js';

export const TIPOS = { agua:'Agua', moho:'Moho', fuego:'Fuego', contenidos:'Contenidos', mudanza:'Mudanza', otro:'Otro' };
export const tipoTxt = (t) => TIPOS[t] || 'Otro';
export const telDigitos = (v) => String(v || '').replace(/[^\d+]/g, '').slice(0, 20);
export const esc = (s) => String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
export const quitarAcentos = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

// Pura: filtra por estado y por lo escrito (cliente o dirección, sin acentos ni mayúsculas).
export function filtrar(lista, estado, texto){
  const q = quitarAcentos(texto).trim();
  return (lista || []).filter(t => t.estado === estado && (!q || quitarAcentos(t.cliente).includes(q) || quitarAcentos(t.direccion).includes(q)));
}
// Pura: lo que el formulario exige. Devuelve '' si está bien, o el aviso.
export function validar(f){
  if(!String(f.cliente || '').trim()) return 'Escriba el nombre del cliente.';
  if(!String(f.direccion || '').trim()) return 'Escriba la dirección.';
  if(!TIPOS[f.tipo]) return 'Escoja el tipo de trabajo.';
  if(f.correo && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(f.correo)) return 'Ese correo no se ve bien.';
  return '';
}
export const fechaCorta = (iso) => { if(!iso) return ''; const d = new Date(iso); return isNaN(d) ? '' : d.toLocaleDateString('es-US', { month:'short', day:'numeric', year:'numeric' }); };

let LISTA = [];
let estadoVista = 'activo';
let abierto = null;      // el trabajo en pantalla
let editando = null;     // el trabajo que se edita en la forma (null = nuevo)

const SELECT = 'id,cliente,direccion,telefono,correo,tipo,estado,notas,created_at,updated_at,archivado_at';

export async function cargar(){
  const aviso = $('#trabajosAviso'); aviso.textContent = '';
  $('#listaTrabajos').innerHTML = '<p class="vacio">Cargando…</p>';
  const r = await authFetch('/rest/v1/fotos_trabajos?select=' + SELECT + '&order=updated_at.desc&limit=500');
  if(r.status === 404){ LISTA = []; pintar(); aviso.textContent = 'Esta parte todavía no está instalada en el servidor: falta correr sql/fotos-01-base.sql.'; return; }
  if(!r.ok){ LISTA = []; pintar(); aviso.textContent = 'No se pudo leer la lista (' + r.status + '). Revise su internet.'; return; }
  LISTA = await r.json();
  pintar();
}

export function pintar(){
  const caja = $('#listaTrabajos'); if(!caja) return;
  const lista = filtrar(LISTA, estadoVista, $('#inBuscar').value);
  if(!lista.length){
    caja.innerHTML = '<p class="vacio">' + (LISTA.length ? 'Nada que coincida.' : (estadoVista === 'activo' ? 'Todavía no hay trabajos. Toque <b>+ Trabajo nuevo</b> para crear el primero.' : 'No hay trabajos archivados.')) + '</p>';
    return;
  }
  caja.innerHTML = lista.map(t => `<div class="trabajo" data-id="${esc(t.id)}">
    <div><div class="nom">${esc(t.cliente)}</div><div class="dir">${esc(t.direccion || 'Sin dirección')}</div>
      <div class="meta"><span class="chip tipo-${esc(t.tipo)}">${esc(tipoTxt(t.tipo))}</span><span>${esc(fechaCorta(t.updated_at))}</span></div></div>
    <span class="flecha">&#8250;</span></div>`).join('');
}

function leerForma(){
  return { cliente: $('#fCliente').value.trim(), direccion: $('#fDireccion').value.trim(), telefono: $('#fTelefono').value.trim(),
           correo: $('#fCorreo').value.trim(), tipo: $('#fTipo').value, notas: $('#fNotas').value.trim() };
}
function llenarForma(t){
  $('#fCliente').value = t ? (t.cliente || '') : ''; $('#fDireccion').value = t ? (t.direccion || '') : '';
  $('#fTelefono').value = t ? (t.telefono || '') : ''; $('#fCorreo').value = t ? (t.correo || '') : '';
  $('#fTipo').value = t ? (t.tipo || '') : ''; $('#fNotas').value = t ? (t.notas || '') : '';
  $('#formaTitulo').textContent = t ? 'Editar trabajo' : 'Trabajo nuevo';
  $('#formaAviso').textContent = '';
}

async function guardarForma(){
  const f = leerForma(); const aviso = $('#formaAviso');
  const mal = validar(f); if(mal){ aviso.textContent = mal; return; }
  const b = $('#btnFormaGuardar'); b.disabled = true; b.textContent = 'Guardando…';
  try{
    const cuerpo = { cliente: f.cliente, direccion: f.direccion, telefono: f.telefono || null, correo: f.correo || null, tipo: f.tipo, notas: f.notas || null };
    let r;
    if(editando){
      r = await authFetch('/rest/v1/fotos_trabajos?id=eq.' + encodeURIComponent(editando.id), { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ ...cuerpo, updated_at: new Date().toISOString() }) });
    }else{
      r = await authFetch('/rest/v1/fotos_trabajos', { method:'POST', headers:{ Prefer:'return=representation' }, body: JSON.stringify(cuerpo) });
    }
    if(!r.ok) throw new Error('HTTP ' + r.status + ' ' + (await r.text()).slice(0, 200));
    const filas = await r.json();
    if(!Array.isArray(filas) || !filas.length) throw new Error('la base no devolvió la fila');
    const t = filas[0];
    const i = LISTA.findIndex(x => x.id === t.id); if(i >= 0) LISTA[i] = t; else LISTA.unshift(t);
    abrir(t, true);
  }catch(e){ aviso.textContent = 'No se pudo guardar. ' + String(e && e.message || e); }
  b.disabled = false; b.textContent = 'Guardar';
}

export function abrir(t, reemplazar){
  abierto = t;
  const dig = telDigitos(t.telefono);
  $('#trabajoFicha').innerHTML = `<h2>${esc(tipoTxt(t.tipo))} · ${t.estado === 'archivado' ? 'archivado' : 'activo'}</h2>
    <div style="font-size:20px; font-weight:800; margin-bottom:6px;">${esc(t.cliente)}</div>
    <div class="linea"><span>Dirección</span><span>${esc(t.direccion || '—')}</span></div>
    <div class="linea"><span>Teléfono</span><span>${t.telefono ? '<a href="tel:' + esc(dig) + '">' + esc(t.telefono) + '</a>' : '—'}</span></div>
    <div class="linea"><span>Correo</span><span>${t.correo ? '<a href="mailto:' + esc(t.correo) + '">' + esc(t.correo) + '</a>' : '—'}</span></div>
    <div class="linea"><span>Creado</span><span>${esc(fechaCorta(t.created_at))}</span></div>
    ${t.notas ? '<div class="linea"><span>Notas</span><span>' + esc(t.notas) + '</span></div>' : ''}
    <div class="acciones">
      ${dig ? '<a class="btn btn-outline" href="tel:' + esc(dig) + '">Llamar</a><a class="btn btn-outline" href="sms:' + esc(dig) + '">Mensaje</a>' : ''}
      <button type="button" class="btn btn-outline" id="btnEditar">Editar</button>
      ${esManager() ? '<button type="button" class="btn ' + (t.estado === 'archivado' ? 'btn-outline' : 'btn-danger') + '" id="btnArchivar">' + (t.estado === 'archivado' ? 'Reactivar' : 'Archivar') + '</button>' : ''}
    </div>
    <p class="aviso" id="fichaAviso"></p>`;
  $('#btnEditar').addEventListener('click', () => { editando = abierto; llenarForma(abierto); irA('pForma', 'pTrabajo'); });
  const ba = $('#btnArchivar'); if(ba) ba.addEventListener('click', archivar);
  if(reemplazar){ irA('pTrabajo'); } else irA('pTrabajo', 'pTrabajos');
}

async function archivar(){
  const t = abierto; if(!t) return;
  const aArchivar = t.estado !== 'archivado';
  if(aArchivar && !confirm('¿Archivar el trabajo de ' + t.cliente + '? Las fotos se quedan guardadas; solo sale de la lista de activos.')) return;
  const aviso = $('#fichaAviso'); aviso.textContent = '';
  const r = await authFetch('/rest/v1/fotos_trabajos?id=eq.' + encodeURIComponent(t.id), { method:'PATCH', headers:{ Prefer:'return=representation' },
    body: JSON.stringify({ estado: aArchivar ? 'archivado' : 'activo', archivado_at: aArchivar ? new Date().toISOString() : null, updated_at: new Date().toISOString() }) });
  if(!r.ok){ aviso.textContent = 'No se pudo (' + r.status + ').'; return; }
  const filas = await r.json(); if(!filas.length){ aviso.textContent = 'La base no devolvió la fila.'; return; }
  const i = LISTA.findIndex(x => x.id === t.id); if(i >= 0) LISTA[i] = filas[0];
  abrir(filas[0], true);
}

export function conectar(){
  $('#filtroEstado').addEventListener('click', (e) => {
    const b = e.target.closest('[data-estado]'); if(!b) return;
    estadoVista = b.dataset.estado;
    $$('#filtroEstado .pill').forEach(x => x.classList.toggle('on', x === b));
    pintar();
  });
  $('#inBuscar').addEventListener('input', pintar);
  $('#btnNuevo').addEventListener('click', () => { editando = null; llenarForma(null); irA('pForma', 'pTrabajos'); });
  $('#btnFormaCancelar').addEventListener('click', atras);
  $('#btnFormaGuardar').addEventListener('click', guardarForma);
  $('#listaTrabajos').addEventListener('click', (e) => {
    const fila = e.target.closest('[data-id]'); if(!fila) return;
    const t = LISTA.find(x => x.id === fila.dataset.id); if(t) abrir(t);
  });
}
// solo para pruebas
export const _estado = () => ({ LISTA, estadoVista, abierto });
