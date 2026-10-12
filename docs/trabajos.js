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
// Pura: la ficha de un trabajo (portada, título, dirección, etiquetas, acciones y pestañas Fotos / Datos).
export function fichaHtml(t, nFotos, manager, portadaUrl){
  const dig = telDigitos(t.telefono); const arch = t.estado === 'archivado';
  return `<div class="ficha-cab">
    <div class="portada">${portadaUrl ? '<img src="' + esc(portadaUrl) + '" alt="">' : ICONO('camara')}</div>
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
let CARGANDO = true;     // hasta que llega la primera lista
let ORDEN = [];          // todas las fotos activas {id, trabajo_id}, la más nueva primero (para Gallery)
let FOTOS = {};          // trabajo_id -> cuántas fotos
let RECIENTES = {};      // trabajo_id -> [foto_id...] las 4 más nuevas
let MINIS = {};          // foto_id -> url firmada (mini)
let abierto = null;      // el trabajo en pantalla
let editando = null;     // el trabajo que se edita en la forma (null = nuevo)

// select=*: así llegan etapa y avance cuando la base ya los tiene (sql/fotos-03-etapa.sql), sin romper si todavía no.
const SELECT = '*';
// Lo que el panel necesita leer (Home, Projects, Gallery, Capture).
export const datos = () => ({ LISTA, FOTOS, RECIENTES, MINIS, ORDEN, cargando: CARGANDO });
let AL_CAMBIAR = () => {};
export const alCambiar = (fn) => { AL_CAMBIAR = fn; };

export async function cargar(){
  const aviso = $('#trabajosAviso'); aviso.textContent = '';
  CARGANDO = !LISTA.length; pintar();
  const [r, rf] = await Promise.all([
    authFetch('/rest/v1/fotos_trabajos?select=' + SELECT + '&order=updated_at.desc&limit=500'),
    authFetch('/rest/v1/fotos_fotos?select=id,trabajo_id&estado=eq.activa&order=subida_at.desc&limit=5000'),
  ]);
  CARGANDO = false;
  if(r.status === 404){ LISTA = []; pintar(); aviso.textContent = 'Esta parte todavía no está instalada en el servidor: falta correr sql/fotos-01-base.sql.'; return; }
  if(!r.ok){ LISTA = []; pintar(); aviso.textContent = 'No se pudo leer la lista (' + r.status + '). Revise su internet.'; return; }
  LISTA = await r.json();
  FOTOS = {}; RECIENTES = {}; ORDEN = [];
  if(rf && rf.ok){ try{ const f = await rf.json(); if(Array.isArray(f)){ ORDEN = f; } if(Array.isArray(f)) f.forEach(x => { FOTOS[x.trabajo_id] = (FOTOS[x.trabajo_id] || 0) + 1; (RECIENTES[x.trabajo_id] = RECIENTES[x.trabajo_id] || []).length < 4 && RECIENTES[x.trabajo_id].push(x.id); }); }catch{} }
  pintar();
  // Miniaturas de verdad en "Fotos recientes" y en la portada de cada fila: una sola llamada firmada.
  const ids = Object.values(RECIENTES).flat();
  if(ids.length){ try{ MINIS = await fotos.urlsFirmadas(ids, 'mini'); pintar(); }catch{} }
}

// La lista ya no se pinta aquí: avisa al panel (Home / Projects / Gallery) que los datos cambiaron.
export function pintar(){ AL_CAMBIAR(); }

// Pura: el avance escrito en la forma -> número 0-100, o null si se dejó vacío.
export function avanceForma(v){ const s = String(v == null ? '' : v).trim(); if(s === '') return null; const n = Number(s); return isFinite(n) ? Math.max(0, Math.min(100, Math.round(n))) : null; }
export const ETAPAS_FORMA = ['planeacion', 'en_curso', 'completado'];
function leerForma(){
  return { cliente: $('#fCliente').value.trim(), direccion: $('#fDireccion').value.trim(), telefono: $('#fTelefono').value.trim(),
           correo: $('#fCorreo').value.trim(), tipo: $('#fTipo').value, notas: $('#fNotas').value.trim(),
           etapa: ETAPAS_FORMA.includes($('#fEtapa').value) ? $('#fEtapa').value : 'en_curso', avance: avanceForma($('#fAvance').value) };
}
function llenarForma(t){
  $('#fCliente').value = t ? (t.cliente || '') : ''; $('#fDireccion').value = t ? (t.direccion || '') : '';
  $('#fTelefono').value = t ? (t.telefono || '') : ''; $('#fCorreo').value = t ? (t.correo || '') : '';
  $('#fTipo').value = t ? (t.tipo || '') : ''; $('#fNotas').value = t ? (t.notas || '') : '';
  $('#fEtapa').value = t && ETAPAS_FORMA.includes(t.etapa) ? t.etapa : 'en_curso';
  $('#fAvance').value = t && t.avance != null ? String(t.avance) : ''; pintarAvanceForma();
  $('#formaTitulo').textContent = t ? 'Editar trabajo' : 'Trabajo nuevo';
  $('#formaAviso').textContent = '';
}

async function guardarForma(){
  const f = leerForma(); const aviso = $('#formaAviso');
  const mal = validar(f); if(mal){ aviso.textContent = mal; return; }
  const b = $('#btnFormaGuardar'); b.disabled = true; b.textContent = 'Guardando…';
  try{
    const base = { cliente: f.cliente, direccion: f.direccion, telefono: f.telefono || null, correo: f.correo || null, tipo: f.tipo, notas: f.notas || null };
    const enviar = (cuerpo) => editando
      ? authFetch('/rest/v1/fotos_trabajos?id=eq.' + encodeURIComponent(editando.id), { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ ...cuerpo, updated_at: new Date().toISOString() }) })
      : authFetch('/rest/v1/fotos_trabajos', { method:'POST', headers:{ Prefer:'return=representation' }, body: JSON.stringify(cuerpo) });
    let r = await enviar({ ...base, etapa: f.etapa, avance: f.avance });
    // La base todavía sin las columnas nuevas (sql/fotos-03-etapa.sql): se guarda lo demás y se avisa.
    let sinEtapa = false;
    if(r.status === 400){ const txt = await r.clone().text(); if(/etapa|avance/.test(txt)){ sinEtapa = true; r = await enviar(base); } }
    if(!r.ok) throw new Error('HTTP ' + r.status + ' ' + (await r.text()).slice(0, 200));
    if(sinEtapa) setTimeout(() => { const a = $('#fichaAviso'); if(a) a.textContent = 'Guardado. La etapa y el avance todavía no se guardan: falta correr sql/fotos-03-etapa.sql.'; }, 50);
    const filas = await r.json();
    if(!Array.isArray(filas) || !filas.length) throw new Error('la base no devolvió la fila');
    const t = filas[0];
    const i = LISTA.findIndex(x => x.id === t.id); if(i >= 0) LISTA[i] = t; else LISTA.unshift(t);
    abrir(t, true);
  }catch(e){ aviso.textContent = 'No se pudo guardar. ' + String(e && e.message || e); }
  b.disabled = false; b.textContent = 'Guardar';
}

// Abrir la forma para editar un proyecto (desde la ficha o desde el menú •••).
export function editar(t, desde){ editando = t; llenarForma(t); irA('pForma', desde || 'pTrabajo'); }
export function abrir(t, reemplazar, desde){
  abierto = t;
  const portada = (RECIENTES[t.id] || []).map(id => MINIS[id]).find(Boolean) || '';
  $('#trabajoFicha').innerHTML = fichaHtml(t, FOTOS[t.id], esManager(), portada);
  $('#btnEditar').addEventListener('click', () => editar(abierto, 'pTrabajo'));
  const ba = $('#btnArchivar'); if(ba) ba.addEventListener('click', () => archivarTrabajo(abierto, true));
  $('#fichaTabs').addEventListener('click', (e) => {
    const b = e.target.closest('[data-tab]'); if(!b) return;
    $$('#fichaTabs .tab-f').forEach(x => x.classList.toggle('on', x === b));
    $$('#trabajoFicha .tab-panel').forEach(p => { p.hidden = p.dataset.panel !== b.dataset.tab; });
  });
  if(reemplazar){ irA('pTrabajo'); } else irA('pTrabajo', desde || 'pProyectos');
  $('#subtitulo').textContent = t.cliente || 'Trabajo';
  fotos.cargar(t);
}

// Archivar / reactivar. Desde la ficha (enFicha) vuelve a pintar la ficha; desde el menú ••• solo la lista.
export async function archivarTrabajo(t, enFicha){
  if(!t) return;
  const aArchivar = t.estado !== 'archivado';
  if(aArchivar && !confirm('Archive ' + t.cliente + '? Photos stay saved; it only leaves the active list.')) return;
  const aviso = enFicha ? $('#fichaAviso') : $('#trabajosAviso'); if(aviso) aviso.textContent = '';
  const r = await authFetch('/rest/v1/fotos_trabajos?id=eq.' + encodeURIComponent(t.id), { method:'PATCH', headers:{ Prefer:'return=representation' },
    body: JSON.stringify({ estado: aArchivar ? 'archivado' : 'activo', archivado_at: aArchivar ? new Date().toISOString() : null, updated_at: new Date().toISOString() }) });
  if(!r.ok){ if(aviso) aviso.textContent = 'Could not save (' + r.status + ').'; return; }
  const filas = await r.json(); if(!filas.length){ if(aviso) aviso.textContent = 'The database did not return the row.'; return; }
  const i = LISTA.findIndex(x => x.id === t.id); if(i >= 0) LISTA[i] = filas[0];
  if(enFicha) abrir(filas[0], true); else pintar();
}
function pintarAvanceForma(){ const v = avanceForma($('#fAvance').value); $('#fAvanceTxt').textContent = v === null ? 'Not set' : v + '%'; $('#fAvanceBarra').value = v === null ? 0 : v; }

export function conectar(){
  $('#btnNuevo').addEventListener('click', () => { editando = null; llenarForma(null); irA('pForma', 'pProyectos'); });
  $('#btnFormaCancelar').addEventListener('click', atras);
  $('#btnFormaGuardar').addEventListener('click', guardarForma);
  $('#fAvance').addEventListener('input', pintarAvanceForma);
  $('#fAvanceBarra').addEventListener('input', (e) => { $('#fAvance').value = e.target.value; pintarAvanceForma(); });
  $('#btnAvanceQuitar').addEventListener('click', () => { $('#fAvance').value = ''; pintarAvanceForma(); });
}
// solo para pruebas
export const _estado = () => ({ LISTA, abierto });
