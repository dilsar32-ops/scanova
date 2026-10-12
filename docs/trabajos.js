// Scanova · trabajos: la lista, crear, abrir, editar, archivar. De las fotos solo el conteo por ahora (paso 2).
import { $, $$, authFetch, irA, atras, esManager } from './app.js';
import * as fotos from './fotos.js';

export const TIPOS = { agua:'Agua', moho:'Moho', fuego:'Fuego', contenidos:'Contenidos', mudanza:'Mudanza', otro:'Otro' };
export const tipoTxt = (t) => TIPOS[t] || 'Otro';
export const telDigitos = (v) => String(v || '').replace(/[^\d+]/g, '').slice(0, 20);
export const esc = (s) => String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
export const quitarAcentos = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
// Pura: "Amilcar Gonzalez" -> "AG"; "Vero" -> "V"; vacío -> "·" (el circulito del avatar).
export const iniciales = (nombre) => { const p = String(nombre || '').trim().split(/\s+/).filter(Boolean); if(!p.length) return '·'; return (p[0][0] + (p.length > 1 ? p[p.length - 1][0] : '')).toUpperCase(); };
export const mapsUrl = (dir) => 'https://maps.google.com/?q=' + encodeURIComponent(String(dir || ''));

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
// Pura: "ahora mismo", "hace 5 min", "hace 3 h", "ayer", "hace 4 días", o la fecha corta. `ahora` se pasa en las pruebas.
export function fechaRelativa(iso, ahora = Date.now()){
  if(!iso) return '';
  const d = new Date(iso); if(isNaN(d)) return '';
  const s = Math.round((ahora - d.getTime()) / 1000);
  if(s < 45) return 'ahora mismo';
  if(s < 3600) return 'hace ' + Math.max(1, Math.round(s / 60)) + ' min';
  if(s < 86400) return 'hace ' + Math.max(1, Math.round(s / 3600)) + ' h';
  if(s < 172800) return 'ayer';
  if(s < 7 * 86400) return 'hace ' + Math.round(s / 86400) + ' días';
  return fechaCorta(iso);
}
const ICONO = (n) => '<svg class="ic"><use href="#i-' + n + '"/></svg>';
// Pura: las etiquetas de color de un trabajo (tipo + estado), como las "labels" de CompanyCam.
export function etiquetas(t){
  const arch = t.estado === 'archivado';
  return '<span class="etq tipo-' + esc(TIPOS[t.tipo] ? t.tipo : 'otro') + '">' + esc(tipoTxt(t.tipo)) + '</span>' +
         '<span class="etq ' + (arch ? 'archivado' : 'activo') + '">' + (arch ? 'Archivado' : 'Activo') + '</span>';
}
// Pura: una fila de la lista. En el teléfono se ven miniatura + texto; en la computadora, las 4 columnas.
export function filaHtml(t, nFotos, ahora){
  const n = nFotos || 0; const cuando = esc(fechaRelativa(t.updated_at, ahora));
  const rec = (RECIENTES[t.id] || []).map(id => MINIS[id]).filter(Boolean);
  const portada = rec[0] ? '<img src="' + esc(rec[0]) + '" alt="" loading="lazy">' : ICONO('camara');
  const huecos = rec.map(u => '<span class="foto-vacia"><img src="' + esc(u) + '" alt="" loading="lazy"></span>').join('') + '<span class="foto-vacia"></span>'.repeat(Math.max(0, 4 - rec.length));
  return `<div class="fila-trabajo" data-id="${esc(t.id)}">
    <div class="col-nom"><div class="miniatura">${portada}</div><div class="col-texto">
      <div class="nom">${esc(t.cliente)}</div><div class="dir">${esc(t.direccion || 'Sin dirección')}</div>
      <div class="etqs">${etiquetas(t)}</div><div class="meta-movil">${cuando}</div></div></div>
    <div class="col-act">${cuando}</div>
    <div class="col-res"><b>${n}</b> ${n === 1 ? 'foto' : 'fotos'}</div>
    <div class="col-fotos">${huecos}</div>
  </div>`;
}
// Pura: la ficha de un trabajo (portada, título, dirección, etiquetas, acciones y pestañas Fotos / Datos).
export function fichaHtml(t, nFotos, manager){
  const dig = telDigitos(t.telefono); const arch = t.estado === 'archivado';
  return `<div class="ficha-cab">
    <div class="portada">${ICONO('camara')}</div>
    <div class="ficha-datos">
      <h1 class="titulo">${esc(t.cliente)}</h1>
      <a class="direccion" href="${esc(mapsUrl(t.direccion))}" target="_blank" rel="noopener">${esc(t.direccion || 'Sin dirección')}</a>
      <div class="etqs">${etiquetas(t)}<button type="button" class="enlace-editar" id="btnEditar">${ICONO('lapiz')}Editar</button></div>
    </div></div>
    <div class="acciones">
      ${dig ? '<a class="btn btn-outline" href="tel:' + esc(dig) + '">' + ICONO('tel') + 'Llamar</a><a class="btn btn-outline" href="sms:' + esc(dig) + '">' + ICONO('msj') + 'Mensaje</a>' : ''}
      ${manager ? '<button type="button" class="btn btn-outline' + (arch ? '' : ' btn-rojo') + '" id="btnArchivar">' + ICONO('archivo') + (arch ? 'Reactivar' : 'Archivar') + '</button>' : ''}
    </div>
    <div class="tabs" id="fichaTabs"><button type="button" class="tab-f on" data-tab="fotos">Fotos <span class="n" id="fotosConteo">(${nFotos || 0})</span></button><button type="button" class="tab-f" data-tab="datos">Datos</button></div>
    <div class="tab-panel" data-panel="fotos">
      <div id="fotosPanel"><p class="vacio">Cargando fotos…</p></div>
      <p class="aviso" id="fotosAviso"></p>
    </div>
    <div class="tab-panel" data-panel="datos" hidden>
      <div class="linea"><span>Teléfono</span><span>${t.telefono ? '<a href="tel:' + esc(dig) + '">' + esc(t.telefono) + '</a>' : '—'}</span></div>
      <div class="linea"><span>Correo</span><span>${t.correo ? '<a href="mailto:' + esc(t.correo) + '">' + esc(t.correo) + '</a>' : '—'}</span></div>
      <div class="linea"><span>Tipo</span><span>${esc(tipoTxt(t.tipo))}</span></div>
      <div class="linea"><span>Creado</span><span>${esc(fechaCorta(t.created_at))}</span></div>
      <div class="linea"><span>Última actividad</span><span>${esc(fechaCorta(t.updated_at))}</span></div>
      ${t.notas ? '<div class="linea"><span>Notas</span><span>' + esc(t.notas) + '</span></div>' : ''}
    </div>
    <p class="aviso" id="fichaAviso"></p>`;
}

let LISTA = [];
let FOTOS = {};          // trabajo_id -> cuántas fotos
let RECIENTES = {};      // trabajo_id -> [foto_id...] las 4 más nuevas
let MINIS = {};          // foto_id -> url firmada (mini)
let estadoVista = 'activo';
let abierto = null;      // el trabajo en pantalla
let editando = null;     // el trabajo que se edita en la forma (null = nuevo)

const SELECT = 'id,cliente,direccion,telefono,correo,tipo,estado,notas,created_at,updated_at,archivado_at';

export async function cargar(){
  const aviso = $('#trabajosAviso'); aviso.textContent = '';
  $('#listaTrabajos').innerHTML = '<p class="vacio">Cargando…</p>';
  const [r, rf] = await Promise.all([
    authFetch('/rest/v1/fotos_trabajos?select=' + SELECT + '&order=updated_at.desc&limit=500'),
    authFetch('/rest/v1/fotos_fotos?select=id,trabajo_id&estado=eq.activa&order=subida_at.desc&limit=5000'),
  ]);
  if(r.status === 404){ LISTA = []; pintar(); aviso.textContent = 'Esta parte todavía no está instalada en el servidor: falta correr sql/fotos-01-base.sql.'; return; }
  if(!r.ok){ LISTA = []; pintar(); aviso.textContent = 'No se pudo leer la lista (' + r.status + '). Revise su internet.'; return; }
  LISTA = await r.json();
  FOTOS = {}; RECIENTES = {};
  if(rf && rf.ok){ try{ const f = await rf.json(); if(Array.isArray(f)) f.forEach(x => { FOTOS[x.trabajo_id] = (FOTOS[x.trabajo_id] || 0) + 1; (RECIENTES[x.trabajo_id] = RECIENTES[x.trabajo_id] || []).length < 4 && RECIENTES[x.trabajo_id].push(x.id); }); }catch{} }
  pintar();
  // Miniaturas de verdad en "Fotos recientes" y en la portada de cada fila: una sola llamada firmada.
  const ids = Object.values(RECIENTES).flat();
  if(ids.length){ try{ MINIS = await fotos.urlsFirmadas(ids, 'mini'); pintar(); }catch{} }
}

export function pintar(){
  const caja = $('#listaTrabajos'); if(!caja) return;
  const lista = filtrar(LISTA, estadoVista, $('#inBuscar').value);
  if(!lista.length){
    caja.innerHTML = '<p class="vacio">' + (LISTA.length ? 'Nada que coincida.' : (estadoVista === 'activo' ? 'Todavía no hay trabajos. Toque <b>Crear trabajo</b> para abrir el primero.' : 'No hay trabajos archivados.')) + '</p>';
    return;
  }
  const ahora = Date.now();
  caja.innerHTML = lista.map(t => filaHtml(t, FOTOS[t.id], ahora)).join('');
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
  $('#trabajoFicha').innerHTML = fichaHtml(t, FOTOS[t.id], esManager());
  $('#btnEditar').addEventListener('click', () => { editando = abierto; llenarForma(abierto); irA('pForma', 'pTrabajo'); });
  const ba = $('#btnArchivar'); if(ba) ba.addEventListener('click', archivar);
  $('#fichaTabs').addEventListener('click', (e) => {
    const b = e.target.closest('[data-tab]'); if(!b) return;
    $$('#fichaTabs .tab-f').forEach(x => x.classList.toggle('on', x === b));
    $$('#trabajoFicha .tab-panel').forEach(p => { p.hidden = p.dataset.panel !== b.dataset.tab; });
  });
  if(reemplazar){ irA('pTrabajo'); } else irA('pTrabajo', 'pTrabajos');
  $('#subtitulo').textContent = t.cliente || 'Trabajo';
  fotos.cargar(t);
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
    $$('#filtroEstado .seg').forEach(x => x.classList.toggle('on', x === b));
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
