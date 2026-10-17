// Scanova · PEGAR FOTOS (16-oct, pedido de Nova Construction: "copiar una foto de otro lugar y pegarla, sin bajarla y subirla").
// Computadora: ⌘V / Ctrl+V en la pestaña Photos abre la hoja "Paste Photos" con las fotos para revisar antes de subir.
// Teléfono (la app de iPhone carga esta misma web): Upload Photos > Paste Photos abre la hoja; se deja el dedo en el recuadro y
// "Pegar". Las fotos entran por la MISMA tanda de Upload Photos (fotos.encolar), al cuarto que dice "New photos go to".
// Nunca la lectura asíncrona del portapapeles: en el iPhone solo entrega PNG y en Chrome pide permiso. El evento 'paste'
// entrega las fotos completas en todos lados.
// Al cargar no toca la página (app.js importa proyecto.js, que importa este, que importa app.js).
import { $, registrarAtras } from './app.js?v=2026-10-17-4';
import * as fotos from './fotos.js?v=2026-10-17-4';
import * as trabajos from './trabajos.js?v=2026-10-17-4';
import * as panel from './panel.js?v=2026-10-17-4';

// ---------- puro (para las pruebas) ----------
export const T_NADA = 'No photo found. Copy a photo, then paste it here.';
export const T_OTROS = 'Only photos can be pasted here.';
export const T_ARCH = 'This project was archived. Nothing was uploaded.';
export const T_OTRO = 'This project is no longer open. Nothing was uploaded.';
const TIPOS = /^image\/(jpeg|pjpeg|png|webp|gif|bmp|heic|heif|tiff)$/i;
export function esFotoPegable(f){
  if(!f) return false;
  if(f.type) return TIPOS.test(f.type);
  return /\.(jpe?g|png|webp|gif|heic|heif)$/i.test(f.name || '');
}
// Lo que trae el portapapeles (o lo que se soltó). Primero dt.files; solo si viene vacío, los items de archivo. Nunca los dos
// juntos (así no se repite la foto, ni entra el ícono PNG que algunos navegadores ponen al copiar un archivo en Finder).
export function imagenesDePegado(dt){
  const out = { fotos: [], otros: 0 };
  if(!dt) return out;
  let lista = Array.from(dt.files || []);
  if(!lista.length) lista = Array.from(dt.items || []).filter(i => i && i.kind === 'file').map(i => { try{ return i.getAsFile(); }catch{ return null; } }).filter(Boolean);
  lista.forEach(f => { if(esFotoPegable(f)) out.fotos.push(f); else out.otros++; });
  return out;
}
const NO_TEXTO = /^(button|checkbox|radio|range|file|submit|reset|color|image|hidden)$/i;
// ¿Está escribiendo? Ahí ⌘V pega TEXTO como siempre. Un <select> no cuenta (escoger el cuarto no apaga ⌘V), ni el recuadro propio.
export function esCampoDeTexto(el){
  if(!el || !el.tagName) return false;
  if(el.id === 'pegarZona' || el.id === 'pegarAtrapa' || (el.closest && el.closest('#pegarZona, #pegarAtrapa'))) return false;
  if(el.tagName === 'TEXTAREA') return true;
  if(el.isContentEditable) return true;
  if(el.tagName === 'INPUT') return !NO_TEXTO.test(el.type || 'text');
  return false;
}
// A dónde va lo pegado: 'hoja' (la hoja abierta), 'fotos' (abrir la hoja) o '' (no se toca: el navegador hace lo de siempre).
export function ruta(s){
  if(!s) return '';
  if(s.hoja) return 'hoja';
  if(s.enTexto || s.encima) return '';
  if(s.pantalla !== 'pTrabajo' || s.tab !== 'fotos') return '';
  if(!s.trabajoId || s.trabajoId !== s.abiertoId) return '';
  if(s.archivado) return '';
  return 'fotos';
}
export const textoSubir = (n) => n === 1 ? 'Upload 1 Photo' : n > 1 ? 'Upload ' + n + ' Photos' : 'Upload Photos';
export function textosZona({ tactil, mac, llena }){
  const atajo = mac ? '⌘V' : 'Ctrl+V';
  if(tactil) return llena ? { b: 'Touch and hold here to paste more', small: '' }
    : { b: 'Touch and hold here, then tap Paste', small: 'Copy photos first in Photos, Messages, WhatsApp or Mail.' };
  return llena ? { b: 'Press ' + atajo + ' to paste more', small: '' } : { b: 'Press ' + atajo + ' to paste', small: 'Or right-click here and choose Paste.' };
}
export const destinoTexto = (cliente, lugar) => (cliente || 'Project') + ' › ' + lugar;

// ---------- en vivo ----------
let API = { proyecto: () => null, tab: () => '', destino: () => ({}), nombre: () => 'No room' };
export function usar(api){ API = { ...API, ...(api || {}) }; }
let SNAP = null;            // { trabajoId, destino, cliente } al abrir: lo pegado va a ESE proyecto y ESE cuarto
let ITEMS = [];             // [{ clave, file, url, huella, mal }]
let GEN = 0, CLAVES = 0;
let COLA = Promise.resolve();
let ATRAPA = null;          // { prev, t }: el foco antes del ⌘V
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
const tactil = () => typeof navigator !== 'undefined' && ((navigator.maxTouchPoints || 0) > 0 || /iPhone|iPad|Android/i.test(navigator.userAgent || ''));
const mac = () => typeof navigator !== 'undefined' && fotos.atajoPegar(navigator.userAgent) === '⌘V';
export const abierta = () => !!$('#hojaPegar') && !$('#hojaPegar').hidden;
const visible = (sel) => { const el = $(sel); return !!el && !el.hidden; };
const archivado = (t) => !!t && t.estado === 'archivado';
function estadoPantalla(target){
  const b = document.body.classList;
  const encima = ['#camara', '#visor', '#hojaCaptura', '#hojaCuarto', '#hojaMedida', '#detHoja', '#cajonDetalles', '#dlgPregunta', '#fvDialogo'].some(visible)
    || ['con-camara', 'con-visor', 'fv-editando', 'con-cajon', 'modal-entrar', 'menu-abierto'].some(c => b.contains(c));
  const p = [...document.querySelectorAll('.pantalla')].find(x => !x.hidden);
  const f = fotos.trabajoActual(), a = trabajos.proyectoAbierto();
  return { hoja: abierta(), enTexto: esCampoDeTexto(target) || esCampoDeTexto(document.activeElement), encima,
    pantalla: p ? p.id : '', tab: API.tab(), trabajoId: f && f.id, abiertoId: a && a.id, archivado: archivado(a) };
}
function decodifica(url){
  if(typeof Image === 'undefined') return Promise.resolve(true);
  return new Promise(res => { const img = new Image(); img.onload = () => res(true); img.onerror = () => res(false); img.src = url;
    if(img.decode) img.decode().then(() => res(true), () => {}); });
}
function aviso(t){ const el = $('#pegarAviso'); if(el) el.textContent = t || ''; }
function pintar(){
  const caja = $('#pegarFotos'); if(!caja) return;
  caja.innerHTML = ITEMS.map(i => `<div class="pegar-f${i.mal ? ' mal' : ''}"><img src="${esc(i.url)}" alt=""><button type="button" class="pegar-quitar" data-pegar-quitar="${esc(i.clave)}" aria-label="Remove">✕</button>${i.mal ? '<span class="pegar-mal">Can\'t read</span>' : ''}</div>`).join('');
  const buenas = ITEMS.filter(i => !i.mal).length;
  const b = $('#pegarSubir'); if(b){ b.textContent = textoSubir(buenas); b.disabled = !buenas; }
  const c = $('#pegarCaja'); if(c) c.classList.toggle('llena', ITEMS.length > 0);
  const z = textosZona({ tactil: tactil(), mac: mac(), llena: ITEMS.length > 0 });
  const pb = $('#pegarPistaB'), ps = $('#pegarPistaS'); if(pb) pb.textContent = z.b; if(ps){ ps.textContent = z.small; ps.hidden = !z.small; }
}
export function abrir(){
  const t = API.proyecto(), f = fotos.trabajoActual();
  if(!t || !f || t.id !== f.id || archivado(t)) return false;
  if(!abierta()){
    SNAP = { trabajoId: t.id, destino: { ...(API.destino() || {}) }, cliente: t.cliente || 'Project' };
    ITEMS = [];
  }
  const d = $('#pegarDestino');
  if(d) d.innerHTML = '<svg class="ic"><use href="#i-pin"/></svg>New photos go to: <b>' + esc(destinoTexto(SNAP.cliente, API.nombre(SNAP.destino))) + '</b>';
  aviso(''); pintar();
  const h = $('#hojaPegar'); if(h) h.hidden = false;
  document.body.classList.add('con-pegar');
  const z = $('#pegarZona');
  if(z){ if(tactil()){ const a = document.activeElement; if(a && a.blur) a.blur(); } else { try{ z.focus({ preventScroll: true }); }catch{ z.focus(); } } }
  return true;
}
// Una por una (por la huella se sabe si ya estaba). Lo que llega después de cerrar se tira.
export function agregar(files){
  const gen = GEN;
  const lista = Array.from(files || []);
  COLA = COLA.then(async () => {
    let n = 0;
    for(const file of lista){
      if(gen !== GEN || !SNAP) break;
      let huella = '';
      try{ huella = await fotos.sha256Hex(file); }catch{}
      if(gen !== GEN || !SNAP) break;
      if(huella && ITEMS.some(i => i.huella === huella)) continue;
      let url = ''; try{ url = URL.createObjectURL(file); }catch{}
      const mal = !(url && await decodifica(url));
      if(gen !== GEN || !SNAP){ try{ url && URL.revokeObjectURL(url); }catch{} break; }
      ITEMS.push({ clave: 'p' + (++CLAVES), file, url, huella, mal }); n++;
      if(!mal) aviso('');
      pintar();
    }
    return n;
  }).catch(() => 0);
  return COLA;
}
export function quitar(clave){
  const i = ITEMS.findIndex(x => x.clave === clave); if(i < 0) return;
  try{ ITEMS[i].url && URL.revokeObjectURL(ITEMS[i].url); }catch{}
  ITEMS.splice(i, 1); pintar();
}
export function subir(){
  if(!SNAP) return '';
  const t = API.proyecto(), f = fotos.trabajoActual();
  if(!t || !f || t.id !== SNAP.trabajoId || f.id !== SNAP.trabajoId){ aviso(T_OTRO); return T_OTRO; }
  if(archivado(t) || archivado(trabajos.proyectoAbierto())){ aviso(T_ARCH); return T_ARCH; }
  const listos = ITEMS.filter(i => !i.mal).map(i => i.file);
  if(!listos.length) return '';
  fotos.encolar(listos, { ...SNAP.destino });      // el cuarto que se enseñó al abrir; {} = No room
  // La tanda usa sus propias miniaturas: los object URL de la hoja se sueltan al cerrar.
  cerrar();
  const s = $('#fotosPanel .fsube'); if(s && s.scrollIntoView) s.scrollIntoView({ block: 'nearest' });
  return '';
}
export function cerrar(){
  ITEMS.forEach(i => { try{ i.url && URL.revokeObjectURL(i.url); }catch{} });
  ITEMS = []; SNAP = null; GEN++;
  const z = $('#pegarZona'); if(z){ z.textContent = ''; if(z.blur) z.blur(); }
  const h = $('#hojaPegar'); if(h) h.hidden = true;
  document.body.classList.remove('con-pegar');
  aviso('');
  pintar();
}
function devolverFoco(){
  const a = ATRAPA; ATRAPA = null; if(!a) return;
  clearTimeout(a.t);
  const z = $('#pegarAtrapa'); if(z) z.textContent = '';
  if(z && document.activeElement === z){
    if(a.prev && a.prev !== document.body && a.prev.focus && document.contains(a.prev)){ try{ a.prev.focus({ preventScroll: true }); }catch{} }
    if(document.activeElement === z && z.blur) z.blur();      // nada a dónde volver (body): se suelta, nunca se queda escribiendo ahí
  }
}
function esAtajoPegar(e){
  const v = e.code === 'KeyV' || String(e.key || '').toLowerCase() === 'v';
  return v && (mac() ? e.metaKey : e.ctrlKey) && !e.altKey && !e.shiftKey && !e.repeat;
}
function alPegar(e, dt, enAtrapa){
  const r = ruta(estadoPantalla(e.target));
  if(!r){ if(enAtrapa){ e.preventDefault(); devolverFoco(); } return; }
  // Primero que nada (sin esperar): Chrome vacía el portapapeles del evento al terminar.
  const { fotos: fs, otros } = imagenesDePegado(dt);
  if(r === 'hoja'){
    e.preventDefault();
    const z = $('#pegarZona'); if(z) z.textContent = '';
    if(fs.length) agregar(fs); else aviso(otros ? T_OTROS : T_NADA);
    return;
  }
  if(enAtrapa) devolverFoco();
  if(!fs.length && !otros){ if(enAtrapa) e.preventDefault(); return; }   // solo texto: como siempre
  e.preventDefault();
  panel.cerrarMenu();
  if(!abrir()) return;
  if(fs.length) agregar(fs); else aviso(T_OTROS);
}
let CONECTADO = false;
export function conectar(){
  if(CONECTADO || typeof document === 'undefined') return; CONECTADO = true;
  document.addEventListener('keydown', (e) => {
    if(abierta()){
      if(e.key === 'Escape'){ cerrar(); return; }
      if(e.key === 'Enter' && !e.isComposing && !e.metaKey && !e.ctrlKey && !e.altKey && !e.shiftKey && !(document.activeElement && document.activeElement.tagName === 'BUTTON')){ e.preventDefault(); subir(); return; }
    }
    if(!esAtajoPegar(e)) return;
    if(abierta()){ const z = $('#pegarZona'); if(z && document.activeElement !== z){ try{ z.focus({ preventScroll: true }); }catch{ z.focus(); } } return; }
    if(ruta(estadoPantalla(document.activeElement)) !== 'fotos') return;
    // Nada que se pueda escribir tiene el foco: el navegador no manda 'paste'. Un recuadro escondido lo recibe un momento.
    const z = $('#pegarAtrapa'); if(!z) return;
    if(ATRAPA) clearTimeout(ATRAPA.t);
    ATRAPA = { prev: document.activeElement, t: setTimeout(devolverFoco, 400) };
    try{ z.focus({ preventScroll: true }); }catch{ z.focus(); }
  });
  document.addEventListener('beforepaste', (e) => { if(ruta(estadoPantalla(e.target))) e.preventDefault(); });
  document.addEventListener('paste', (e) => {
    const enAtrapa = !!(e.target && e.target.closest && e.target.closest('#pegarAtrapa'));
    alPegar(e, e.clipboardData, enAtrapa);
  });
  document.addEventListener('click', (e) => {
    if(!e.target || !e.target.closest) return;
    if(e.target.closest('[data-pegar-cerrar]')){ cerrar(); return; }
    const q = e.target.closest('[data-pegar-quitar]'); if(q){ quitar(q.dataset.pegarQuitar); return; }
    if(e.target.closest('#pegarSubir')){ subir(); return; }
    if(e.target.id === 'hojaPegar' && !ITEMS.length) cerrar();
  });
  const z = $('#pegarZona');
  if(z){
    z.addEventListener('beforeinput', (e) => e.preventDefault());
    z.addEventListener('input', () => { z.textContent = ''; });
    z.addEventListener('dragover', (e) => e.preventDefault());
    z.addEventListener('drop', (e) => { e.preventDefault(); if(!abierta()) return; const { fotos: fs, otros } = imagenesDePegado(e.dataTransfer); if(fs.length) agregar(fs); else aviso(otros ? T_OTROS : T_NADA); });
  }
  registrarAtras(() => abierta() ? (cerrar(), true) : false);
}
// solo para pruebas
export const _estado = () => ({ SNAP, ITEMS });
