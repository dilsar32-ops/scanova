// Scanova · fotos: subir (cámara o carrete en el teléfono, archivos en la computadora), línea de tiempo
// por día y ver en grande. La página nunca ve las claves de R2: pide URLs firmadas a la función
// fotos-subir, sube DIRECTO a R2 y luego confirma; la fila en fotos_fotos la escribe la función
// solo cuando R2 ya tiene la foto completa (HEAD y tamaño).
import { $, $$, authFetch, PERFIL, esManager } from './app.js?v=2026-10-16-9';
import { esc, iniciales } from './trabajos.js?v=2026-10-16-9';

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
  if(r.enCurso) return 'Uploading ' + (r.listas + r.repetidas + r.fallidas + 1) + ' of ' + r.total + '…';
  const partes = [];
  if(r.listas) partes.push(r.listas === 1 ? '1 photo uploaded' : r.listas + ' photos uploaded');
  if(r.repetidas) partes.push(r.repetidas + ' already there');
  if(r.fallidas) partes.push(r.fallidas + ' could not upload');
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
    img.onerror = () => { URL.revokeObjectURL(url); rej(new Error('could not read the photo')); };
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

// "Load failed" (Safari) o "Failed to fetch": se cayó la señal a media subida, o el teléfono se bloqueó o se
// cambió de app y iOS cortó la conexión (14-oct, una tanda de 8 en 5G con dos "Load failed"). No es la foto.
export const esErrorDeRed = (e) => !!e && (e.name === 'TypeError' || /load failed|failed to fetch|network ?error|internet|offline|timed out|cancelled|abort/i.test(String(e.message || e)));
const esperar = (ms) => new Promise(r => setTimeout(r, ms));
// Si no hay señal, espera a que vuelva (o hasta `max` ms).
function esperarSenal(max){
  if(typeof navigator === 'undefined' || navigator.onLine !== false || typeof window === 'undefined') return Promise.resolve();
  return new Promise(res => { const fin = () => { window.removeEventListener('online', fin); clearTimeout(t); res(); }; const t = setTimeout(fin, max); window.addEventListener('online', fin); });
}
async function putR2(url, blob){
  let ultimo = null;
  for(let i = 0; i < 4; i++){
    if(i){ await esperarSenal(30000); await esperar([0, 1000, 3000, 6000][i]); }
    try{ const r = await fetch(url, { method:'PUT', body: blob, headers:{ 'Content-Type':'image/jpeg' } }); if(r.ok) return; ultimo = new Error('R2 contestó ' + r.status); if(r.status === 403) break; }   // 403 = la firma venció: se vuelve a pedir arriba
    catch(e){ ultimo = e; }
  }
  throw ultimo || new Error('upload failed');
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
// Subiendo, o esperando la señal para volver a intentar (mientras tanto la app no se recarga sola: se perderían).
export const hayFotosSubiendo = () => activos > 0 || TANDA.some(i => (i.estado !== 'lista' && i.estado !== 'fallo' && i.estado !== 'repetida') || (i.estado === 'fallo' && i.red));
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

// Las fotos que son prueba de una lectura del Dry Log: siguen en Photos, pero no son portada (prueba en vivo del 14-oct).
const MEDIDOR = new Set();
export function marcarMedidor(id){ if(id) MEDIDOR.add(id); }
export async function cargar(trabajo){
  // Lo que todavía se está subiendo (de este u otro proyecto) sigue subiendo por detrás; lo ya subido se olvida.
  TRABAJO = trabajo; FOTOS = []; TANDA = TANDA.filter(i => i.estado !== 'lista' && i.estado !== 'repetida');
  const caja = $('#fotosPanel'); if(!caja) return;
  caja.innerHTML = '<p class="vacio">Cargando fotos…</p>';
  const [r] = await Promise.all([
    authFetch('/rest/v1/fotos_fotos?trabajo_id=eq.' + encodeURIComponent(trabajo.id) + '&estado=eq.activa&select=id,trabajo_id,created_by,subida_at,tomada_at,ancho,alto,bytes,nota,nivel_id,cuarto_id&order=subida_at.desc&limit=1000'),
    nombres(),
    authFetch('/rest/v1/fotos_drylog_lecturas?trabajo_id=eq.' + encodeURIComponent(trabajo.id) + '&foto_id=not.is.null&select=foto_id&limit=2000')
      .then(x => x.ok ? x.json() : []).then(m => { (Array.isArray(m) ? m : []).forEach(x => MEDIDOR.add(x.foto_id)); }).catch(() => {}),
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
// La ventana de UNA foto se entera cuando cambia la lista (una foto recién subida entra a su tira sin salir y volver).
let AL_LISTA = null;
export const alCambiarLista = (fn) => { AL_LISTA = fn; };
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
// Lo que se está subiendo NO se enseña con letreros (su pedido del 14-oct: "eso debería pasar detrás, no
// mostrarlo"). Solo aparecen las fotos mismas, en una fila, con una marquita mientras suben; al quedar, pasan a
// su lugar con las demás. Si una de verdad no se pudo (no es la señal: eso se reintenta solo), sale con un "!" y
// tocándola se vuelve a intentar.
export function tandaHtml(){
  const pend = TANDA.filter(i => TRABAJO && i.trabajoId === TRABAJO.id && i.estado !== 'lista' && i.estado !== 'repetida');
  if(!pend.length) return '';
  return '<div class="fsube">' + pend.map(i => `<button type="button" class="fsube-f${i.estado === 'fallo' && !i.red ? ' mal' : ''}" data-tanda-item="${esc(i.clave)}" aria-label="${i.estado === 'fallo' && !i.red ? 'Could not upload: tap to try again' : 'Uploading'}"${i.estado === 'fallo' && i.error ? ' title="' + esc(i.error) + '"' : ''}>${i.vista ? '<img src="' + esc(i.vista) + '" alt="">' : ''}<i></i></button>`).join('') + '</div>';
}
export function pintar(urls){
  if(!TRABAJO) return;
  urls = urls || {}; FOTOS.forEach(f => { const c = URLS.mini[f.id]; if(!urls[f.id] && c && c.vence > Date.now()) urls[f.id] = c.url; });
  const n = $('#fotosConteo'); if(n) n.textContent = '(' + FOTOS.length + ')';
  // La portada de la ficha = la foto más nueva (antes se quedaba vacía si las fotos llegaban después de abrir).
  const masNueva = porDia(FOTOS).flatMap(d => d.fotos).find(f => !MEDIDOR.has(f.id));
  const portada = $('#trabajoFicha .portada');
  if(portada && masNueva && urls[masNueva.id]){ const img = portada.querySelector('img'); if(!img || img.getAttribute('src') !== urls[masNueva.id]) portada.innerHTML = '<img src="' + esc(urls[masNueva.id]) + '" alt="">'; }
  if(AL_PINTAR) AL_PINTAR(urls);
  if(AL_LISTA) AL_LISTA();
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

// ---------- subir una tanda: TRES fotos a la vez (antes una por una: una tanda de 8 en 5G tardaba demasiado) ----------
// Cada foto sigue sola si se cae la señal (espera a que vuelva y lo intenta otra vez). Si se cambia de proyecto,
// sigue subiendo al proyecto donde se tomó.
const A_LA_VEZ = 3;
let activos = 0;
function procesarTanda(){
  while(activos < A_LA_VEZ){
    const item = TANDA.find(i => i.estado === 'cola');
    if(!item) break;
    activos++; item.estado = 'preparando';
    subirItem(item).finally(() => {
      activos--;
      if(TANDA.some(i => i.estado === 'cola')) procesarTanda();
      else if(!activos && TRABAJO) urlsFirmadas(FOTOS.map(f => f.id), 'mini').then(pintar).catch(() => {});
    });
  }
}
async function subirItem(item){
  try{
    let res = null;
    for(let intento = 0; ; intento++){
      try{ res = await subirUna(item.trabajoId, item.file, (e) => { item.estado = e; }); break; }
      catch(e){
        if(!esErrorDeRed(e) || intento >= 3) throw e;
        item.estado = 'reintento';
        await esperarSenal(60000); await esperar([3000, 8000, 20000][intento]);
      }
    }
    const { foto, repetida } = res;
    // La foto queda en el nivel/cuarto escogido (la fila la escribe la función; el cuarto se le pone aquí).
    if(foto && !repetida && item.destino && (item.destino.nivel_id || item.destino.cuarto_id)){
      try{ const r = await authFetch('/rest/v1/fotos_fotos?id=eq.' + encodeURIComponent(foto.id), { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ nivel_id: item.destino.nivel_id || null, cuarto_id: item.destino.cuarto_id || null }) });
        if(r.ok){ const x = (await r.json())[0]; if(x){ foto.nivel_id = x.nivel_id; foto.cuarto_id = x.cuarto_id; } } }catch{}
    }
    item.estado = repetida ? 'repetida' : 'lista';
    // Su miniatura es la foto misma que ya está en el teléfono: pasa a su lugar al instante, sin esperar la descarga.
    if(foto && item.vista) URLS.mini[foto.id] = { url: item.vista, vence: Date.now() + 50 * 60 * 1000 };
    if(!repetida && foto && TRABAJO && foto.trabajo_id === TRABAJO.id && !FOTOS.some(f => f.id === foto.id)) FOTOS.unshift(foto);
  }catch(e){ item.estado = 'fallo'; item.red = esErrorDeRed(e); item.error = item.red ? 'no signal' : String(e && e.message || e); }
  if(TRABAJO && item.trabajoId === TRABAJO.id) pintar();
}
// Subir UNA foto ya hecha (la copia editada) y esperar a que quede: devuelve la foto nueva. La original no se toca.
export async function subirCopia(file, destino, opts){
  if(!TRABAJO) throw new Error('no project open');
  const { foto, repetida } = await subirUna(TRABAJO.id, file, () => {});
  if(foto && opts && opts.medidor) MEDIDOR.add(foto.id);   // la foto del medidor del Dry Log: se marca antes de pintar, así no parpadea de portada
  if(foto && !repetida && destino && (destino.nivel_id || destino.cuarto_id)){
    try{ const r = await authFetch('/rest/v1/fotos_fotos?id=eq.' + encodeURIComponent(foto.id), { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ nivel_id: destino.nivel_id || null, cuarto_id: destino.cuarto_id || null }) });
      if(r.ok){ const x = (await r.json())[0]; if(x){ foto.nivel_id = x.nivel_id; foto.cuarto_id = x.cuarto_id; } } }catch{}
  }
  if(foto && !repetida && !FOTOS.some(f => f.id === foto.id)) FOTOS.unshift(foto);
  const urls = await urlsFirmadas(FOTOS.map(f => f.id), 'mini'); pintar(urls);
  return { foto, repetida };
}
function reintentarSinSenal(){
  if(!TANDA.some(i => i.estado === 'fallo' && i.red)) return;
  TANDA.forEach(i => { if(i.estado === 'fallo' && i.red){ i.estado = 'cola'; i.error = ''; i.red = false; } });
  pintar(); procesarTanda();
}
if(typeof window !== 'undefined'){
  window.addEventListener('online', reintentarSinSenal);
  setInterval(() => { if(!activos) reintentarSinSenal(); }, 30000);   // con señal floja el teléfono a veces no avisa que volvió
  document.addEventListener('visibilitychange', () => { if(!document.hidden) setTimeout(reintentarSinSenal, 1500); });
}
let CLAVES = 0;
export function encolar(files, destino){
  const lista = Array.from(files || []).filter(esImagen);
  if(!lista.length || !TRABAJO) return;
  const d = destino || DESTINO_FN() || {};
  lista.forEach(f => { let vista = ''; try{ vista = URL.createObjectURL(f); }catch{} TANDA.push({ clave: 't' + (++CLAVES), file: f, vista, nombre: f.name || 'foto', trabajoId: TRABAJO.id, estado:'cola', error:'', destino: d }); });
  pintar(); procesarTanda();
}

// ---------- ver una foto ----------
// Tocar una foto abre la VENTANA de la foto (foto.js: detalles, etiquetas, tareas, comentarios). La vista negra de
// antes (#visor) se queda: es la PANTALLA COMPLETA (botón de expandir) y sigue con su papelera y sus flechas.
// Un visor con su propia lista (el Dry Log abre las fotos de UN cuarto ese día): no depende del filtro de Photos.
let VISOR_IDS = null;
const ordenVisor = () => {
  if(VISOR_IDS){ const m = new Map(FOTOS.map(f => [f.id, f])); return VISOR_IDS.map(id => m.get(id)).filter(Boolean); }
  return ORDEN_FN ? ORDEN_FN(FOTOS) : porDia(FOTOS).flatMap(d => d.fotos);
};
let AL_FOTO = null;
export const alAbrirFoto = (fn) => { AL_FOTO = fn; };
export const visorLista = () => ordenVisor();
export const visorIndice = () => VISOR_I;
export const fotoActual = () => ordenVisor()[VISOR_I] || null;
export async function abrirVisor(fotoId, ids){
  const abierto = $('#pFoto') && !$('#pFoto').hidden;
  if(Array.isArray(ids) && ids.length) VISOR_IDS = [...new Set(ids)];
  else if(VISOR_IDS && abierto){ if(!VISOR_IDS.includes(fotoId)) VISOR_IDS.push(fotoId); }   // una copia editada entra a la misma lista
  else VISOR_IDS = null;
  const i = ordenVisor().findIndex(f => f.id === fotoId); if(i < 0) return false;
  VISOR_I = i;
  if(AL_FOTO){ AL_FOTO(true); return true; }
  abrirGrande(); return true;
}
// Al entrar fotos nuevas la lista se corre: la ventana vuelve a buscar SU foto para no saltar a otra.
export function fijarVisor(id){ const i = ordenVisor().findIndex(f => f.id === id); if(i >= 0) VISOR_I = i; return i; }
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
    { const t = e.target.closest('[data-tanda-item]'); if(t){ const it = TANDA.find(i => i.clave === t.dataset.tandaItem); if(it && it.estado === 'fallo'){ it.estado = 'cola'; it.error = ''; it.red = false; pintar(); procesarTanda(); } return; } }
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
