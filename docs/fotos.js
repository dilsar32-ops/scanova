// Scanova · fotos: subir (cámara o carrete en el teléfono, archivos en la computadora), línea de tiempo
// por día y ver en grande. La página nunca ve las claves de R2: pide URLs firmadas a la función
// fotos-subir, sube DIRECTO a R2 y luego confirma; la fila en fotos_fotos la escribe la función
// solo cuando R2 ya tiene la foto completa (HEAD y tamaño).
import { $, $$, authFetch, PERFIL, esManager } from './app.js?v=2026-10-13-7';
import { esc, iniciales } from './trabajos.js?v=2026-10-13-7';

const FUNCION = '/functions/v1/fotos-subir';
export const MAX_WEB = 1600, MAX_MINI = 320;
const VARIANTES = ['original', 'web', 'mini'];

// ---------- puro ----------
export const esImagen = (f) => !!f && (/^image\//i.test(f.type || '') || /\.(jpe?g|png|heic|heif|webp|gif)$/i.test(f.name || ''));
export const hexDe = (buf) => Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('');
// Fecha de la foto: lo que dijo la cámara (tomada_at) y si no, cuándo llegó al servidor.
export const fechaFoto = (f) => f.tomada_at || f.subida_at || '';
export const claveDia = (iso) => { const d = new Date(iso); if(isNaN(d)) return 'sin-fecha'; return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'); };
export const diaTxt = (iso) => { const d = new Date(iso); if(isNaN(d)) return 'Sin fecha'; const s = d.toLocaleDateString('es-US', { weekday:'long', day:'numeric', month:'long', year:'numeric' }); return s.charAt(0).toUpperCase() + s.slice(1); };
export const horaTxt = (iso) => { const d = new Date(iso); return isNaN(d) ? '' : d.toLocaleTimeString('es-US', { hour:'numeric', minute:'2-digit' }); };
// Pura: agrupa por día, el día más reciente primero y dentro del día la foto más reciente primero.
export function porDia(fotos){
  const m = new Map();
  (fotos || []).slice().sort((a, b) => String(fechaFoto(b)).localeCompare(String(fechaFoto(a)))).forEach(f => {
    const k = claveDia(fechaFoto(f)); if(!m.has(k)) m.set(k, { clave:k, titulo: diaTxt(fechaFoto(f)), fotos:[] }); m.get(k).fotos.push(f);
  });
  return Array.from(m.values());
}
// Pura: cómo se cuenta el avance de una tanda. { total, listas, fallidas, repetidas, enCurso }
export function resumenTanda(items){
  const r = { total: items.length, listas:0, fallidas:0, repetidas:0, enCurso:0 };
  items.forEach(i => { if(i.estado === 'lista') r.listas++; else if(i.estado === 'fallo') r.fallidas++; else if(i.estado === 'repetida') r.repetidas++; else r.enCurso++; });
  return r;
}
export function textoAvance(r){
  if(!r.total) return '';
  if(r.enCurso) return 'Subiendo ' + (r.listas + r.repetidas + r.fallidas + 1) + ' de ' + r.total + '…';
  const partes = [];
  if(r.listas) partes.push(r.listas === 1 ? '1 foto subida' : r.listas + ' fotos subidas');
  if(r.repetidas) partes.push(r.repetidas + (r.repetidas === 1 ? ' ya estaba' : ' ya estaban'));
  if(r.fallidas) partes.push(r.fallidas + (r.fallidas === 1 ? ' no se pudo' : ' no se pudieron'));
  return partes.join(' · ');
}
// Pura: la foto de un día en la rejilla.
export function fotoHtml(f, url, nombre){
  return `<button type="button" class="ffoto" data-foto="${esc(f.id)}" aria-label="Ver foto">
    ${url ? '<img src="' + esc(url) + '" alt="" loading="lazy">' : '<span class="ffoto-vacia"></span>'}
    <span class="fquien" title="${esc(nombre || '')}">${esc(iniciales(nombre || '') === '·' ? '' : iniciales(nombre || ''))}</span>
  </button>`;
}

// ---------- la función ----------
export async function llamar(accion, cuerpo){
  const r = await authFetch(FUNCION, { method:'POST', body: JSON.stringify({ accion, ...(cuerpo || {}) }) });
  const t = await r.text(); let d = null; try{ d = JSON.parse(t); }catch{}
  if(r.status === 404 && !d) throw new Error('La función fotos-subir no está desplegada.');
  if(!r.ok || !d || !d.ok) throw new Error((d && d.error) ? (d.error + (d.faltas ? ' (' + d.faltas.join('; ') + ')' : '')) : ('HTTP ' + r.status));
  return d;
}

// ---------- preparar la foto en el navegador: original + 1600 + 320, y su huella ----------
function leerImagen(file){
  return new Promise((res, rej) => {
    const img = new Image(); const url = URL.createObjectURL(file);
    img.onload = () => res({ img, url });
    img.onerror = () => { URL.revokeObjectURL(url); rej(new Error('no se pudo leer la foto')); };
    img.src = url;
  });
}
function achicar(img, max, calidad){
  return new Promise((res, rej) => {
    const W = img.naturalWidth || img.width, H = img.naturalHeight || img.height;
    const s = Math.min(1, max / Math.max(W, H)); const w = Math.max(1, Math.round(W * s)), h = Math.max(1, Math.round(H * s));
    const c = document.createElement('canvas'); c.width = w; c.height = h;
    c.getContext('2d').drawImage(img, 0, 0, w, h);
    c.toBlob(b => b ? res({ blob: b, w, h }) : rej(new Error('sin imagen')), 'image/jpeg', calidad);
  });
}
export async function preparar(file){
  const { img, url } = await leerImagen(file);
  try{
    const web = await achicar(img, MAX_WEB, 0.82);
    const mini = await achicar(img, MAX_MINI, 0.75);
    // El original va tal cual si ya es JPEG; si no (PNG, HEIC, WebP), una copia JPEG a tamaño completo.
    const original = /^image\/jpe?g$/i.test(file.type || '') ? file : (await achicar(img, 1e9, 0.92)).blob;
    return { original, web: web.blob, mini: mini.blob, ancho: img.naturalWidth || img.width, alto: img.naturalHeight || img.height };
  } finally { URL.revokeObjectURL(url); }
}
export async function sha256Hex(blob){ return hexDe(await crypto.subtle.digest('SHA-256', await blob.arrayBuffer())); }

async function putR2(url, blob){
  let ultimo = null;
  for(let i = 0; i < 3; i++){
    try{ const r = await fetch(url, { method:'PUT', body: blob, headers:{ 'Content-Type':'image/jpeg' } }); if(r.ok) return; ultimo = new Error('R2 contestó ' + r.status); }
    catch(e){ ultimo = e; }
    await new Promise(r => setTimeout(r, 700 * (i + 1)));
  }
  throw ultimo || new Error('no se pudo subir a R2');
}
// Una foto, de principio a fin. `avance(etapa)` para la pantalla.
export async function subirUna(trabajoId, file, avance){
  const paso = (e) => { try{ avance && avance(e); }catch{} };
  paso('preparando');
  const foto_id = crypto.randomUUID();
  const p = await preparar(file);
  const sha256 = await sha256Hex(p.original);
  const bytes = { original: p.original.size, web: p.web.size, mini: p.mini.size };
  const tomada_at = new Date(file.lastModified || Date.now()).toISOString();
  const firma = await llamar('firmar_subida', { trabajo_id: trabajoId, foto_id, bytes });
  paso('subiendo');
  await Promise.all(VARIANTES.map(v => putR2(firma.urls[v], p[v])));
  paso('anotando');
  const c = await llamar('confirmar', { trabajo_id: trabajoId, foto_id, sha256, bytes, tomada_at, ancho: p.ancho, alto: p.alto });
  return { foto: c.foto, repetida: !!c.repetida };
}

// ---------- estado de pantalla ----------
let TRABAJO = null;            // el trabajo abierto
let FOTOS = [];                // sus fotos (activas)
let NOMBRES = {};              // user_id -> nombre (lo que la cuenta alcanza a ver)
const URLS = { mini:{}, web:{} };   // foto_id -> { url, vence }
let TANDA = [];                // lo que se está subiendo ahora
let VISOR_I = -1;

async function nombres(){
  if(Object.keys(NOMBRES).length) return NOMBRES;
  const r = await authFetch('/rest/v1/profiles?select=id,full_name');
  if(r.ok){ const f = await r.json(); if(Array.isArray(f)) f.forEach(p => { NOMBRES[p.id] = p.full_name || ''; }); }
  if(PERFIL && PERFIL.id && !NOMBRES[PERFIL.id]) NOMBRES[PERFIL.id] = PERFIL.full_name || '';
  return NOMBRES;
}
export const cargarNombres = () => nombres();
export const nombreDe = (userId) => NOMBRES[userId] || (PERFIL && userId === PERFIL.id ? (PERFIL.full_name || 'Usted') : 'Equipo');

// URLs firmadas por lotes (1 h); se cachean 50 min.
export async function urlsFirmadas(ids, variante){
  const ahora = Date.now(); const caja = URLS[variante] || (URLS[variante] = {});
  const faltan = ids.filter(id => !(caja[id] && caja[id].vence > ahora));
  for(let i = 0; i < faltan.length; i += 150){
    const lote = faltan.slice(i, i + 150);
    try{ const d = await llamar('firmar_lectura', { foto_ids: lote, variante }); Object.entries(d.urls || {}).forEach(([id, url]) => { caja[id] = { url, vence: ahora + 50 * 60 * 1000 }; }); }
    catch(e){ console.warn('firmar_lectura', e); }
  }
  const out = {}; ids.forEach(id => { if(caja[id]) out[id] = caja[id].url; }); return out;
}

export async function cargar(trabajo){
  TRABAJO = trabajo; FOTOS = []; TANDA = [];
  const caja = $('#fotosPanel'); if(!caja) return;
  caja.innerHTML = '<p class="vacio">Cargando fotos…</p>';
  const [r] = await Promise.all([
    authFetch('/rest/v1/fotos_fotos?trabajo_id=eq.' + encodeURIComponent(trabajo.id) + '&estado=eq.activa&select=id,trabajo_id,created_by,subida_at,tomada_at,ancho,alto,bytes,nota,nivel_id,cuarto_id&order=subida_at.desc&limit=1000'),
    nombres(),
  ]);
  if(r.status === 404){ FOTOS = []; pintar(); $('#fotosAviso').textContent = 'Esta parte todavía no está instalada en el servidor: falta correr sql/fotos-01-base.sql.'; return; }
  if(!r.ok){ FOTOS = []; pintar(); $('#fotosAviso').textContent = 'No se pudieron leer las fotos (' + r.status + ').'; return; }
  FOTOS = await r.json();
  if(TRABAJO !== trabajo) return;    // abrió otro trabajo mientras cargaba
  pintar();
  const urls = await urlsFirmadas(FOTOS.map(f => f.id), 'mini');
  if(TRABAJO !== trabajo) return;
  pintar(urls);
}

// La cuadrícula, los filtros por nivel/cuarto y la selección los dibuja la ficha del proyecto (proyecto.js).
// Aquí quedan los botones de subir, el avance de la tanda y las URLs; la ficha se registra con alPintar().
let AL_PINTAR = null, DESTINO_FN = () => ({}), AL_CLIC_FN = null, ORDEN_FN = null, ETIQUETA_FN = null;
export const alPintar = (fn) => { AL_PINTAR = fn; };
export const usarDestino = (fn) => { DESTINO_FN = fn; };
export const alClicFoto = (fn) => { AL_CLIC_FN = fn; };
export const usarOrdenVisor = (fn) => { ORDEN_FN = fn; };
export const usarEtiqueta = (fn) => { ETIQUETA_FN = fn; };
export const lista = () => FOTOS;
export const urlsMini = () => { const u = {}; FOTOS.forEach(f => { const c = URLS.mini[f.id]; if(c && c.vence > Date.now()) u[f.id] = c.url; }); return u; };
// "Upload Photos". En el teléfono abre dos opciones: la cámara de Scanova (muchas fotos seguidas, con el
// nivel y el cuarto escogidos arriba) o el carrete. En la computadora abre el selector de archivos.
export function botonesSubir(){
  if(TRABAJO && TRABAJO.estado === 'archivado') return '';
  const tactil = (navigator.maxTouchPoints || 0) > 0 || /iPhone|iPad|Android/i.test(navigator.userAgent);
  if(tactil) return '<button type="button" class="btn btn-accent btn-chico subir-btn" data-subir-menu><svg class="ic"><use href="#i-camara"/></svg>Upload Photos</button><input type="file" accept="image/*" multiple hidden data-subir>';
  return '<label class="btn btn-accent btn-chico subir-btn"><svg class="ic"><use href="#i-camara"/></svg>Upload Photos<input type="file" accept="image/*" multiple hidden data-subir></label>';
}
export function tandaHtml(){
  if(!TANDA.length) return '';
  const r = resumenTanda(TANDA);
  const filas = TANDA.filter(i => i.estado !== 'lista' && i.estado !== 'repetida').map(i => `<div class="ftanda-fila ${esc(i.estado)}"><span>${esc(i.nombre)}</span><span>${i.estado === 'fallo' ? '✕ ' + esc(i.error || 'no se pudo') : (i.estado === 'cola' ? 'en espera' : i.estado + '…')}</span></div>`).join('');
  return `<div class="ftanda"><div class="ftanda-cab"><b>${esc(textoAvance(r))}</b>${r.enCurso ? '' : '<button type="button" class="enlace-editar" data-tanda-cerrar>Cerrar</button>'}</div>${filas}${(!r.enCurso && r.fallidas) ? '<div class="ftanda-pie"><button type="button" class="btn btn-outline" data-tanda-reintentar>Reintentar las que fallaron</button></div>' : ''}</div>`;
}
export function pintar(urls){
  if(!TRABAJO) return;
  urls = urls || {}; FOTOS.forEach(f => { const c = URLS.mini[f.id]; if(!urls[f.id] && c && c.vence > Date.now()) urls[f.id] = c.url; });
  const n = $('#fotosConteo'); if(n) n.textContent = '(' + FOTOS.length + ')';
  // La portada de la ficha = la foto más nueva (antes se quedaba vacía si las fotos llegaban después de abrir).
  const masNueva = porDia(FOTOS).flatMap(d => d.fotos)[0];
  const portada = $('#trabajoFicha .portada');
  if(portada && masNueva && urls[masNueva.id]){ const img = portada.querySelector('img'); if(!img || img.getAttribute('src') !== urls[masNueva.id]) portada.innerHTML = '<img src="' + esc(urls[masNueva.id]) + '" alt="">'; }
  if(AL_PINTAR) AL_PINTAR(urls);
}
// Mover fotos a un nivel/cuarto (o sacarlas: null). Devuelve cuántas se movieron de verdad (las de otros solo las mueve el manager).
export async function moverFotos(ids, destino){
  if(!ids.length) return 0;
  const cuerpo = { nivel_id: destino && destino.nivel_id || null, cuarto_id: destino && destino.cuarto_id || null };
  const r = await authFetch('/rest/v1/fotos_fotos?id=in.(' + ids.map(encodeURIComponent).join(',') + ')', { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify(cuerpo) });
  if(!r.ok) throw new Error('HTTP ' + r.status);
  const filas = await r.json();
  (filas || []).forEach(x => { const f = FOTOS.find(y => y.id === x.id); if(f){ f.nivel_id = x.nivel_id; f.cuarto_id = x.cuarto_id; } });
  pintar();
  return (filas || []).length;
}
// Mandar varias fotos a la papelera (manager o quien las subió). Devuelve cuántas.
export async function papeleraFotos(ids){
  if(!ids.length) return 0;
  const r = await authFetch('/rest/v1/fotos_fotos?id=in.(' + ids.map(encodeURIComponent).join(',') + ')', { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ estado:'papelera', eliminada_at: new Date().toISOString(), eliminada_por: PERFIL ? PERFIL.id : null }) });
  if(!r.ok) throw new Error('HTTP ' + r.status);
  const filas = await r.json(); const fuera = new Set((filas || []).map(x => x.id));
  FOTOS = FOTOS.filter(f => !fuera.has(f.id)); pintar();
  return fuera.size;
}

// ---------- subir una tanda (una a la vez: así una foto pesada no tumba a las demás) ----------
let subiendo = false;
async function procesarTanda(){
  if(subiendo) return; subiendo = true;
  try{
    for(const item of TANDA){
      if(item.estado !== 'cola') continue;
      if(!TRABAJO || item.trabajoId !== TRABAJO.id) { item.estado = 'fallo'; item.error = 'cambió de trabajo'; continue; }
      try{
        const { foto, repetida } = await subirUna(item.trabajoId, item.file, (e) => { item.estado = e; pintar(); });
        // La foto queda en el nivel/cuarto escogido (la fila la escribe la función; el cuarto se le pone aquí).
        if(foto && !repetida && item.destino && (item.destino.nivel_id || item.destino.cuarto_id)){
          try{ const r = await authFetch('/rest/v1/fotos_fotos?id=eq.' + encodeURIComponent(foto.id), { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ nivel_id: item.destino.nivel_id || null, cuarto_id: item.destino.cuarto_id || null }) });
            if(r.ok){ const x = (await r.json())[0]; if(x){ foto.nivel_id = x.nivel_id; foto.cuarto_id = x.cuarto_id; } } }catch{}
        }
        item.estado = repetida ? 'repetida' : 'lista';
        if(!repetida && foto && TRABAJO && foto.trabajo_id === TRABAJO.id && !FOTOS.some(f => f.id === foto.id)) FOTOS.unshift(foto);
      }catch(e){ item.estado = 'fallo'; item.error = String(e && e.message || e); }
      pintar();
    }
    // Las miniaturas nuevas: una sola llamada para todas las que faltan.
    const urls = await urlsFirmadas(FOTOS.map(f => f.id), 'mini'); pintar(urls);
  } finally { subiendo = false; }
}
// Subir UNA foto ya hecha (la copia editada) y esperar a que quede: devuelve la foto nueva. La original no se toca.
export async function subirCopia(file, destino){
  if(!TRABAJO) throw new Error('no project open');
  const { foto, repetida } = await subirUna(TRABAJO.id, file, () => {});
  if(foto && !repetida && destino && (destino.nivel_id || destino.cuarto_id)){
    try{ const r = await authFetch('/rest/v1/fotos_fotos?id=eq.' + encodeURIComponent(foto.id), { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ nivel_id: destino.nivel_id || null, cuarto_id: destino.cuarto_id || null }) });
      if(r.ok){ const x = (await r.json())[0]; if(x){ foto.nivel_id = x.nivel_id; foto.cuarto_id = x.cuarto_id; } } }catch{}
  }
  if(foto && !repetida && !FOTOS.some(f => f.id === foto.id)) FOTOS.unshift(foto);
  const urls = await urlsFirmadas(FOTOS.map(f => f.id), 'mini'); pintar(urls);
  return { foto, repetida };
}
export function encolar(files, destino){
  const lista = Array.from(files || []).filter(esImagen);
  if(!lista.length || !TRABAJO) return;
  const d = destino || DESTINO_FN() || {};
  lista.forEach(f => TANDA.push({ file: f, nombre: f.name || 'foto', trabajoId: TRABAJO.id, estado:'cola', error:'', destino: d }));
  pintar(); procesarTanda();
}

// ---------- ver una foto ----------
// Tocar una foto abre la VENTANA de la foto (foto.js: detalles, etiquetas, tareas, comentarios). La vista negra de
// antes (#visor) se queda: es la PANTALLA COMPLETA (botón de expandir) y sigue con su papelera y sus flechas.
const ordenVisor = () => ORDEN_FN ? ORDEN_FN(FOTOS) : porDia(FOTOS).flatMap(d => d.fotos);
let AL_FOTO = null;
export const alAbrirFoto = (fn) => { AL_FOTO = fn; };
export const visorLista = () => ordenVisor();
export const visorIndice = () => VISOR_I;
export const fotoActual = () => ordenVisor()[VISOR_I] || null;
export async function abrirVisor(fotoId){
  const i = ordenVisor().findIndex(f => f.id === fotoId); if(i < 0) return;
  VISOR_I = i;
  if(AL_FOTO){ AL_FOTO(true); return; }
  abrirGrande();
}
export function irFoto(i){ const n = ordenVisor().length; if(!n) return; VISOR_I = ((i % n) + n) % n; if(AL_FOTO) AL_FOTO(false); }
// La pantalla completa (la vista negra de siempre).
export async function abrirGrande(){ if(VISOR_I < 0) return; $('#visor').hidden = false; document.body.classList.add('con-visor'); await pintarVisor(); }
const grandeAbierta = () => !$('#visor').hidden;
async function pintarVisor(){
  const lista = ordenVisor(); const f = lista[VISOR_I]; if(!f) return cerrarVisor();
  $('#visorImg').src = ''; $('#visorPie').textContent = '';
  $('#visorQuien').textContent = (ETIQUETA_FN ? ETIQUETA_FN(f) + ' · ' : '') + nombreDe(f.created_by) + ' · ' + diaTxt(fechaFoto(f)) + ' ' + horaTxt(fechaFoto(f));
  $('#visorN').textContent = (VISOR_I + 1) + ' / ' + lista.length;
  $('#visorBorrar').hidden = !(esManager() || (PERFIL && f.created_by === PERFIL.id));
  const urls = await urlsFirmadas([f.id], 'web');
  if(ordenVisor()[VISOR_I] !== f) return;
  $('#visorImg').src = urls[f.id] || (URLS.mini[f.id] ? URLS.mini[f.id].url : '');
  $('#visorPie').textContent = f.nota || '';
}
// Cerrar la pantalla completa: si la ventana de la foto está detrás, se queda en la misma foto.
export function cerrarVisor(){
  $('#visor').hidden = true; document.body.classList.remove('con-visor');
  if(AL_FOTO && $('#pFoto') && !$('#pFoto').hidden) AL_FOTO(false); else VISOR_I = -1;
}
function visorMover(d){ if(VISOR_I < 0) return; const n = ordenVisor().length; if(!n) return cerrarVisor(); VISOR_I = (VISOR_I + d + n) % n; pintarVisor(); }
// Mandar la foto abierta a la papelera (la usan la pantalla completa y el ••• de la ventana). Devuelve '' o el error.
export async function borrarFotoActual(){
  const f = ordenVisor()[VISOR_I]; if(!f) return 'No photo.';
  if(!confirm('Move this photo to the trash? The manager can recover it later.')) return null;
  const r = await authFetch('/rest/v1/fotos_fotos?id=eq.' + encodeURIComponent(f.id), { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ estado:'papelera', eliminada_at: new Date().toISOString(), eliminada_por: PERFIL ? PERFIL.id : null }) });
  const filas = r.ok ? await r.json() : [];
  if(!r.ok || !filas.length) return 'Could not delete it (' + r.status + '). Only the manager or who took it can.';
  FOTOS = FOTOS.filter(x => x.id !== f.id);
  const quedan = ordenVisor().length; VISOR_I = quedan ? Math.min(VISOR_I, quedan - 1) : -1;
  pintar();
  return '';
}
async function borrarFoto(){
  const err = await borrarFotoActual(); if(err === null) return;
  if(err){ $('#visorPie').textContent = err; return; }
  if(VISOR_I < 0){ cerrarVisor(); if(AL_FOTO) AL_FOTO(false); } else pintarVisor();
}
// Guardar la nota (descripción) de una foto: manager o quien la tomó.
export async function guardarNota(fotoId, nota){
  const r = await authFetch('/rest/v1/fotos_fotos?id=eq.' + encodeURIComponent(fotoId), { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ nota: nota || null }) });
  const filas = r.ok ? await r.json() : [];
  if(!filas.length) return false;
  const f = FOTOS.find(x => x.id === fotoId); if(f) f.nota = filas[0].nota;
  return true;
}

export function conectar(){
  document.addEventListener('change', (e) => {
    const inp = e.target.closest && e.target.closest('input[data-subir]'); if(!inp) return;
    encolar(inp.files); inp.value = '';
  });
  document.addEventListener('click', (e) => {
    const foto = e.target.closest('[data-foto]'); if(foto){ if(AL_CLIC_FN && AL_CLIC_FN(foto.dataset.foto)) return; abrirVisor(foto.dataset.foto); return; }
    if(e.target.closest('[data-tanda-cerrar]')){ TANDA = TANDA.filter(i => i.estado !== 'lista' && i.estado !== 'repetida' && i.estado !== 'fallo'); pintar(); return; }
    if(e.target.closest('[data-tanda-reintentar]')){ TANDA.forEach(i => { if(i.estado === 'fallo'){ i.estado = 'cola'; i.error = ''; } }); pintar(); procesarTanda(); return; }
  });
  $('#visorCerrar').addEventListener('click', cerrarVisor);
  $('#visorAnt').addEventListener('click', () => visorMover(-1));
  $('#visorSig').addEventListener('click', () => visorMover(1));
  $('#visorBorrar').addEventListener('click', borrarFoto);
  document.addEventListener('keydown', (e) => {
    if(grandeAbierta()){ if(e.key === 'Escape') cerrarVisor(); if(e.key === 'ArrowLeft') visorMover(-1); if(e.key === 'ArrowRight') visorMover(1); return; }
    if($('#pFoto') && !$('#pFoto').hidden && !document.body.classList.contains('fv-editando') && !/INPUT|TEXTAREA|SELECT/.test((document.activeElement || {}).tagName || '')){ if(e.key === 'ArrowLeft') irFoto(VISOR_I - 1); if(e.key === 'ArrowRight') irFoto(VISOR_I + 1); }
  });
}
// El proyecto abierto (para la cámara y el botón del centro).
export const trabajoActual = () => TRABAJO;
// solo para pruebas
export const _estado = () => ({ TRABAJO, FOTOS, TANDA });
