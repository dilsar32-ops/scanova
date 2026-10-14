// Scanova · trabajos: la lista, crear, abrir, editar, archivar. De las fotos solo el conteo por ahora (paso 2).
import { $, $$, authFetch, irA, atras, esManager } from './app.js?v=2026-10-14-6';
import * as fotos from './fotos.js?v=2026-10-14-6';

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
// La ficha del proyecto (encabezado y pestañas) la dibuja proyecto.js; se registra con usarFicha().
let FICHA_FN = null;
export const usarFicha = (fn) => { FICHA_FN = fn; };

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
// Pura: el punto escrito (lat/lng) -> número, o null si está vacío o no es número.
export const numONulo = (v) => { const s = String(v == null ? '' : v).trim(); if(s === '') return null; const n = Number(s); return isFinite(n) ? n : null; };
function leerForma(){
  return { cliente: $('#fCliente').value.trim(), direccion: $('#fDireccion').value.trim(), telefono: $('#fTelefono').value.trim(),
           correo: $('#fCorreo').value.trim(), tipo: $('#fTipo').value, notas: $('#fNotas').value.trim(),
           etapa: ETAPAS_FORMA.includes($('#fEtapa').value) ? $('#fEtapa').value : 'en_curso', avance: avanceForma($('#fAvance').value),
           lat: numONulo($('#fLat').value), lng: numONulo($('#fLng').value),
           cliente_nombre: '',   // el nombre del cliente ES el nombre del proyecto (no hay dos nombres)
           encargado: $('#fEncargado').value.trim(), fecha_inicio: $('#fFechaInicio').value || '' };
}
function llenarForma(t){
  $('#fCliente').value = t ? (t.cliente || '') : ''; $('#fDireccion').value = t ? (t.direccion || '') : '';
  $('#fTelefono').value = t ? (t.telefono || '') : ''; $('#fCorreo').value = t ? (t.correo || '') : '';
  $('#fTipo').value = t ? (t.tipo || '') : ''; $('#fNotas').value = t ? (t.notas || '') : '';
  $('#fClienteNombre').value = t ? (t.cliente_nombre || '') : ''; $('#fEncargado').value = t ? (t.encargado || '') : '';
  $('#fFechaInicio').value = t && t.fecha_inicio ? String(t.fecha_inicio).slice(0, 10) : '';
  $('#fEtapa').value = t && ETAPAS_FORMA.includes(t.etapa) ? t.etapa : 'en_curso';
  $('#fLat').value = t && t.lat != null ? String(t.lat) : ''; $('#fLng').value = t && t.lng != null ? String(t.lng) : '';
  const nd = $('#fDireccionNota'); if(nd){ nd.textContent = ''; nd.classList.remove('error'); }
  $('#fAvance').value = t && t.avance != null ? String(t.avance) : ''; pintarAvanceForma();
  $('#formaTitulo').textContent = t ? 'Edit Project' : 'New Project';
  $('#formaAviso').textContent = '';
}

async function guardarForma(){
  const f = leerForma(); const aviso = $('#formaAviso');
  const mal = validar(f); if(mal){ aviso.textContent = mal; return; }
  const b = $('#btnFormaGuardar'); b.disabled = true; b.textContent = 'Guardando…';
  try{
    const base = { cliente: f.cliente, direccion: f.direccion, telefono: f.telefono || null, correo: f.correo || null, tipo: f.tipo, notas: f.notas || null, lat: f.lat, lng: f.lng };
    const enviar = (cuerpo) => editando
      ? authFetch('/rest/v1/fotos_trabajos?id=eq.' + encodeURIComponent(editando.id), { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ ...cuerpo, updated_at: new Date().toISOString() }) })
      : authFetch('/rest/v1/fotos_trabajos', { method:'POST', headers:{ Prefer:'return=representation' }, body: JSON.stringify(cuerpo) });
    // Se manda todo; si la base todavía no tiene las columnas nuevas, se guarda lo demás y se avisa.
    const nuevas = { cliente_nombre: f.cliente_nombre || null, encargado: f.encargado || null, fecha_inicio: f.fecha_inicio || null };
    const etapa = { etapa: f.etapa, avance: f.avance };
    let cuerpo = { ...base, ...etapa, ...nuevas }; const faltan = [];
    let r = await enviar(cuerpo);
    for(let i = 0; i < 2 && r.status === 400; i++){
      const txt = await r.clone().text();
      if(/cliente_nombre|encargado|fecha_inicio/.test(txt) && !faltan.includes('04')){ faltan.push('04'); cuerpo = { ...base, ...(faltan.includes('03') ? {} : etapa) }; }
      else if(/etapa|avance/.test(txt) && !faltan.includes('03')){ faltan.push('03'); cuerpo = { ...base, ...(faltan.includes('04') ? {} : nuevas) }; }
      else break;
      r = await enviar(cuerpo);
    }
    if(!r.ok) throw new Error('HTTP ' + r.status + ' ' + (await r.text()).slice(0, 200));
    if(faltan.length) setTimeout(() => { const a = $('#fichaAviso'); if(a) a.textContent = 'Guardado. ' + (faltan.includes('04') ? 'Cliente, encargado y fecha todavía no se guardan (falta sql/fotos-04-niveles.sql). ' : '') + (faltan.includes('03') ? 'La etapa y el avance todavía no se guardan (falta sql/fotos-03-etapa.sql).' : ''); }, 50);
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
  if(FICHA_FN) FICHA_FN(t, portada);
  if(reemplazar){ irA('pTrabajo'); } else irA('pTrabajo', desde || 'pProyectos');
  $('#subtitulo').textContent = t.cliente || 'Project';
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
  $$('[data-nuevo-inicio]').forEach(b => b.addEventListener('click', () => { editando = null; llenarForma(null); irA('pForma', 'pInicio'); }));
  $('#btnFormaCancelar').addEventListener('click', atras);
  $('#btnFormaGuardar').addEventListener('click', guardarForma);
  $('#fAvance').addEventListener('input', pintarAvanceForma);
  $('#fAvanceBarra').addEventListener('input', (e) => { $('#fAvance').value = e.target.value; pintarAvanceForma(); });
  $('#btnAvanceQuitar').addEventListener('click', () => { $('#fAvance').value = ''; pintarAvanceForma(); });
}
// Cambió una fila desde otra pantalla (etiquetas, descripción): la lista y el proyecto abierto quedan al día.
export function reemplazar(t){ const i = LISTA.findIndex(x => x.id === t.id); if(i >= 0) LISTA[i] = t; if(abierto && abierto.id === t.id) abierto = t; }
// El proyecto que está en pantalla (para el botón de la cámara).
export const proyectoAbierto = () => abierto;
// solo para pruebas
export const _estado = () => ({ LISTA, abierto });
