// Scanova · el panel nuevo (diseño de Amilcar, 12 oct 2026): Home con "Welcome", Recent Projects en tarjetas,
// la tabla All Projects con filtro, búsqueda y orden; Projects; Gallery; el botón de cámara (Capture) y el menú •••.
// Lo puro va arriba (se prueba en Node); lo que toca la página va abajo.
import { $, $$, irA, esManager, PERFIL } from './app.js';
import * as trabajos from './trabajos.js';
import * as fotos from './fotos.js';

// Se piden al usarse (no al cargar): así no importa en qué orden se cargan los módulos.
const esc = (v) => trabajos.esc(v);
const quitarAcentos = (v) => trabajos.quitarAcentos(v);

// ---------- lo puro ----------
// La etapa de un proyecto. Archivado manda; si la base todavía no tiene la columna, cuenta como "In Progress".
export const ETAPAS = { planeacion:'Planning', en_curso:'In Progress', completado:'Completed', archivado:'Archived' };
export function etapaDe(t){
  if(!t) return 'en_curso';
  if(t.estado === 'archivado') return 'archivado';
  return (t.etapa && t.etapa !== 'archivado' && ETAPAS[t.etapa]) ? t.etapa : 'en_curso';
}
export const pillHtml = (t) => { const e = etapaDe(t); return '<span class="pill ' + e + '">' + ETAPAS[e] + '</span>'; };
// El avance (0-100) solo si alguien lo puso. null = no se enseña barra (no se inventa un número).
export function avanceDe(t){
  if(!t || t.avance === null || t.avance === undefined || t.avance === '') return null;
  const n = Number(t.avance); if(!isFinite(n)) return null;
  return Math.max(0, Math.min(100, Math.round(n)));
}
export function progresoHtml(t){
  const a = avanceDe(t); if(a === null) return '';
  return '<div class="progreso"><span class="pbar"><i class="' + etapaDe(t) + '" style="width:' + a + '%"></i></span><b>' + a + '%</b></div>';
}
export const fechaEn = (iso) => { if(!iso) return ''; const d = new Date(iso); return isNaN(d) ? '' : d.toLocaleDateString('en-US', { month:'short', day:'numeric', year:'numeric' }); };
export const hoyLargo = (d) => d.toLocaleDateString('en-US', { weekday:'long', month:'short', day:'numeric', year:'numeric' });
export const primerNombre = (n) => String(n || '').trim().split(/\s+/)[0] || '';
// Los 3 más recientes (por última actividad), sin los archivados.
export function recientes(lista, n = 3){
  return (lista || []).filter(t => t.estado !== 'archivado').slice().sort((a, b) => String(b.updated_at || '').localeCompare(String(a.updated_at || ''))).slice(0, n);
}
// Filtro de la tabla: "todos" = todos los que no están archivados; "archivado" = solo los archivados; o una etapa.
export function filtrarPanel(lista, estado, texto){
  const q = quitarAcentos(texto).trim();
  return (lista || []).filter(t => {
    const e = etapaDe(t);
    if(estado === 'archivado'){ if(e !== 'archivado') return false; }
    else if(e === 'archivado') return false;
    else if(estado && estado !== 'todos' && e !== estado) return false;
    return !q || [t.cliente, t.direccion, t.telefono, t.correo].some(v => quitarAcentos(v).includes(q));
  });
}
const ORDEN_ETAPA = { planeacion:0, en_curso:1, completado:2, archivado:3 };
export function ordenar(lista, campo, dir){
  const d = dir < 0 ? -1 : 1;
  const val = (t) => campo === 'nombre' ? quitarAcentos(t.cliente) : campo === 'direccion' ? quitarAcentos(t.direccion) : campo === 'estado' ? ORDEN_ETAPA[etapaDe(t)] : String(t.updated_at || '');
  return (lista || []).slice().sort((a, b) => { const x = val(a), y = val(b); return (x < y ? -1 : x > y ? 1 : 0) * d; });
}
const IC = (n, cls) => '<svg class="ic' + (cls ? ' ' + cls : '') + '"><use href="#i-' + n + '"/></svg>';
// Una tarjeta de Recent Projects: foto, •••, nombre, dirección, fecha, etapa y avance.
export function tarjetaHtml(t, img){
  const foto = img ? '<img src="' + esc(img) + '" alt="" loading="lazy">' : '<span class="sin-foto">' + IC('camara') + '<small>No photos yet</small></span>';
  return `<article class="tarj" data-abrir="${esc(t.id)}">
    <div class="tarj-foto">${foto}<button type="button" class="mas-btn flot" data-menu="${esc(t.id)}" aria-label="Options">${IC('puntos')}</button></div>
    <div class="tarj-cuerpo">
      <div class="tarj-nom">${esc(t.cliente)}</div>
      <div class="tarj-dir">${esc(t.direccion || 'No address')}</div>
      <div class="tarj-fecha">${esc(fechaEn(t.updated_at))}</div>
      ${pillHtml(t)}${progresoHtml(t)}
    </div>
  </article>`;
}
// Una fila de All Projects. En el teléfono: nombre + fecha, etapa y la flechita; en la computadora, 4 columnas y •••.
export function filaHtml(t){
  return `<div class="tfila" data-abrir="${esc(t.id)}">
    <div class="tc-nom" translate="no"><div class="tn">${esc(t.cliente)}</div><div class="tf-movil">${esc(fechaEn(t.updated_at))}</div></div>
    <div class="tc-dir" translate="no">${esc(t.direccion || '—')}</div>
    <div class="tc-fecha">${esc(fechaEn(t.updated_at))}</div>
    <div class="tc-est">${pillHtml(t)}</div>
    <div class="tc-acc"><button type="button" class="mas-btn" data-menu="${esc(t.id)}" aria-label="Options">${IC('puntos')}</button>${IC('chev-der', 'chev-movil')}</div>
  </div>`;
}
export function cabTablaHtml(orden){
  const col = (campo, txt) => `<button type="button" class="tc-orden${orden && orden.campo === campo ? ' on' : ''}" data-orden="${campo}">${txt}${IC('orden')}</button>`;
  return `<div class="tcab">${col('nombre', 'Project Name')}${col('direccion', 'Address')}${col('fecha', 'Date')}${col('estado', 'Status')}<span></span></div>`;
}

// ---------- la página ----------
const VISTA = { inicio:{ estado:'todos', texto:'' }, proyectos:{ estado:'todos', texto:'' } };
let ORDEN = { campo:'fecha', dir:-1 };
const PORTADAS = {};   // foto_id -> url "web" (más nítida para las tarjetas)
let MENU_ID = null;

function portadaDe(t){
  const d = trabajos.datos(); const id = (d.RECIENTES[t.id] || [])[0];
  return id ? (PORTADAS[id] || d.MINIS[id] || '') : '';
}
function tabla(sel, vista, max){
  const caja = $(sel); if(!caja) return;
  const d = trabajos.datos();
  if(d.cargando){ caja.innerHTML = '<p class="vacio">Loading…</p>'; return; }
  const lista = ordenar(filtrarPanel(d.LISTA, vista.estado, vista.texto), ORDEN.campo, ORDEN.dir);
  const filas = max ? lista.slice(0, max) : lista;
  const vacio = !d.LISTA.length ? 'No projects yet. Tap <b>New Project</b> to create the first one.' : 'No projects match.';
  caja.innerHTML = cabTablaHtml(ORDEN) + (filas.length ? filas.map(filaHtml).join('') : '<p class="vacio">' + vacio + '</p>') +
    (max && lista.length > max ? '<button type="button" class="tabla-mas" data-nav="proyectos">View all ' + lista.length + ' projects</button>' : '');
}
async function cargarPortadas(rec){
  const d = trabajos.datos();
  const ids = rec.map(t => (d.RECIENTES[t.id] || [])[0]).filter(id => id && !PORTADAS[id]);
  if(!ids.length) return;
  try{ const u = await fotos.urlsFirmadas(ids, 'web'); let nuevas = false; Object.entries(u).forEach(([k, v]) => { if(!PORTADAS[k]){ PORTADAS[k] = v; nuevas = true; } }); if(nuevas) pintarRecientes(); }catch{}
}
function pintarRecientes(){
  const caja = $('#recientes'); if(!caja) return;
  const d = trabajos.datos(); const rec = recientes(d.LISTA);
  caja.innerHTML = d.cargando ? '<p class="vacio">Loading…</p>' : rec.length ? rec.map(t => tarjetaHtml(t, portadaDe(t))).join('')
    : '<div class="vacio-tarj">' + IC('carpeta') + '<div><b>No active projects yet.</b><br>Create one in <b>Projects</b> and it will show here with its latest photo.</div></div>';
  return rec;
}
export function pintar(){
  const nom = primerNombre(PERFIL && PERFIL.full_name);
  const bn = $('#bienvNombre'); if(bn) bn.textContent = nom || 'back';
  const bf = $('#bienvFecha'); if(bf) bf.textContent = hoyLargo(new Date());
  const rec = pintarRecientes() || [];
  tabla('#tablaInicio', VISTA.inicio, 8);
  tabla('#tablaProyectos', VISTA.proyectos, 0);
  if(!$('#pGaleria').hidden) pintarGaleria();
  cargarPortadas(rec);
}

// ---------- Gallery: las fotos más nuevas de todos los proyectos ----------
let GAL = {};
export async function pintarGaleria(){
  const caja = $('#galeria'); if(!caja) return;
  const d = trabajos.datos(); const ult = d.ORDEN.slice(0, 60);
  if(!ult.length){ caja.innerHTML = '<div class="vacio-tarj">' + IC('galeria') + '<div><b>No photos yet.</b><br>Tap the camera to take the first one.</div></div>'; return; }
  const nombre = (id) => { const t = d.LISTA.find(x => x.id === id); return t ? t.cliente : ''; };
  const dibujar = () => { caja.innerHTML = '<div class="gal-grid">' + ult.map(f => `<button type="button" class="gal-foto" data-abrir="${esc(f.trabajo_id)}">${GAL[f.id] ? '<img src="' + esc(GAL[f.id]) + '" alt="" loading="lazy">' : '<span class="ffoto-vacia"></span>'}<span class="gal-nom">${esc(nombre(f.trabajo_id))}</span></button>`).join('') + '</div>'; };
  dibujar();
  const faltan = ult.map(f => f.id).filter(id => !GAL[id]);
  if(faltan.length){ try{ Object.assign(GAL, await fotos.urlsFirmadas(faltan, 'mini')); dibujar(); }catch{} }
}

// ---------- el menú ••• (Open / Edit / Archive) ----------
function cerrarMenu(){ const m = $('#menuPop'); if(m){ m.hidden = true; m.innerHTML = ''; } MENU_ID = null; }
function abrirMenuEn(btn, html){
  const m = $('#menuPop'); const app = $('.app');
  m.innerHTML = html; m.hidden = false;
  const r = btn.getBoundingClientRect(), a = app.getBoundingClientRect();
  const ancho = m.offsetWidth || 190;
  m.style.left = Math.max(8, Math.min(a.width - ancho - 8, r.right - a.left - ancho)) + 'px';
  const abajo = r.bottom - a.top + 6, alto = m.offsetHeight || 150;
  m.style.top = (abajo + alto > a.height - 8 ? Math.max(8, r.top - a.top - alto - 6) : abajo) + 'px';
}
function abrirMenu(id, btn){
  const t = trabajos.datos().LISTA.find(x => x.id === id); if(!t) return;
  if(MENU_ID === id){ cerrarMenu(); return; }
  MENU_ID = id;
  const arch = t.estado === 'archivado';
  abrirMenuEn(btn, `<button type="button" data-accion="abrir">${IC('carpeta')}Open project</button>
    ${arch ? '' : `<button type="button" data-accion="fotos">${IC('camara')}Add photos</button>`}
    <button type="button" data-accion="editar">${IC('lapiz')}Edit details</button>
    ${esManager() ? `<button type="button" data-accion="archivar" class="${arch ? '' : 'rojo'}">${IC('archivo')}${arch ? 'Reactivate' : 'Archive'}</button>` : ''}`);
}
function pantallaActual(){ const p = $$('.pantalla').find(x => !x.hidden); return p ? p.id : 'pInicio'; }
function abrirProyecto(id){
  const t = trabajos.datos().LISTA.find(x => x.id === id); if(!t) return;
  trabajos.abrir(t, false, pantallaActual());
}

// ---------- Capture: escoger el proyecto y abrir la cámara (en la computadora, escoger fotos) ----------
export function abrirCaptura(){
  const d = trabajos.datos(); const hoja = $('#hojaCaptura'); const lista = $('#capturaLista');
  const activos = d.LISTA.filter(t => t.estado !== 'archivado').slice().sort((a, b) => String(b.updated_at || '').localeCompare(String(a.updated_at || '')));
  const tactil = (navigator.maxTouchPoints || 0) > 0 || /iPhone|iPad|Android/i.test(navigator.userAgent);
  lista.innerHTML = activos.length ? activos.map(t => `<label class="cap-fila"><span class="cap-foto">${portadaDe(t) ? '<img src="' + esc(portadaDe(t)) + '" alt="">' : IC('camara')}</span>
      <span class="cap-texto"><b>${esc(t.cliente)}</b><small>${esc(t.direccion || '')}</small></span>
      <span class="cap-accion">${IC(tactil ? 'camara' : 'mas')}${tactil ? 'Photo' : 'Upload'}</span>
      <input type="file" accept="image/*" ${tactil ? 'capture="environment"' : 'multiple'} hidden data-capturar="${esc(t.id)}"></label>`).join('')
    : '<p class="vacio">No active projects. Create one in <b>Projects</b> first.</p>';
  $('#capturaTitulo').textContent = tactil ? 'Take a photo for…' : 'Add photos to…';
  hoja.hidden = false;
}
function cerrarCaptura(){ $('#hojaCaptura').hidden = true; }

export function conectar(){
  const filtro = (selSel, inSel, vista) => {
    $(selSel).addEventListener('change', (e) => { vista.estado = e.target.value; pintar(); });
    $(inSel).addEventListener('input', (e) => { vista.texto = e.target.value; pintar(); });
  };
  filtro('#selEstadoI', '#inBuscarI', VISTA.inicio);
  filtro('#selEstadoP', '#inBuscarP', VISTA.proyectos);
  // Buscar de arriba: lleva a Projects con lo escrito.
  $('#inBuscarTodo').addEventListener('input', (e) => {
    VISTA.proyectos.texto = e.target.value; $('#inBuscarP').value = e.target.value;
    if(pantallaActual() !== 'pProyectos') irA('pProyectos');
    pintar();
  });
  $('#btnFiltroI').addEventListener('click', () => $('#herrInicio').classList.toggle('abierto'));
  $('#btnFiltroP').addEventListener('click', () => $('#herrProyectos').classList.toggle('abierto'));
  $('#btnCampana').addEventListener('click', (e) => {
    const n = Number($('#campanaPunto').dataset.n || 0);
    if(esManager() && n){ e.stopPropagation(); cerrarMenu(); document.querySelector('[data-nav="settings"]').click(); return; }
    e.stopPropagation(); MENU_ID = 'campana';
    abrirMenuEn(e.currentTarget, '<div class="menu-nota">No new notifications.</div>');
  });
  document.addEventListener('click', (e) => {
    const ord = e.target.closest('[data-orden]');
    if(ord){ const c = ord.dataset.orden; ORDEN = { campo:c, dir: ORDEN.campo === c ? -ORDEN.dir : (c === 'fecha' ? -1 : 1) }; pintar(); return; }
    const mb = e.target.closest('[data-menu]');
    if(mb){ e.stopPropagation(); abrirMenu(mb.dataset.menu, mb); return; }
    const acc = e.target.closest('#menuPop [data-accion]');
    if(acc){
      const t = trabajos.datos().LISTA.find(x => x.id === MENU_ID); const a = acc.dataset.accion; cerrarMenu(); if(!t) return;
      if(a === 'abrir') abrirProyecto(t.id);
      else if(a === 'editar') trabajos.editar(t, pantallaActual());
      else if(a === 'archivar') trabajos.archivarTrabajo(t);
      else if(a === 'fotos') abrirProyecto(t.id);
      return;
    }
    if(!e.target.closest('#menuPop')) cerrarMenu();
    const ab = e.target.closest('[data-abrir]');
    if(ab && !e.target.closest('label')){ abrirProyecto(ab.dataset.abrir); return; }
    if(e.target.closest('[data-cerrar-hoja]') || e.target.id === 'hojaCaptura'){ cerrarCaptura(); return; }
  });
  // Escogió proyecto y tomó/escogió la foto: se abre el proyecto y la foto entra a su cola de subida.
  document.addEventListener('change', (e) => {
    const inp = e.target.closest && e.target.closest('input[data-capturar]'); if(!inp) return;
    const t = trabajos.datos().LISTA.find(x => x.id === inp.dataset.capturar); const files = Array.from(inp.files || []); inp.value = '';
    cerrarCaptura(); if(!t || !files.length) return;
    trabajos.abrir(t, false, pantallaActual());
    fotos.encolar(files);
  });
  document.addEventListener('keydown', (e) => { if(e.key === 'Escape'){ cerrarMenu(); if(!$('#hojaCaptura').hidden) cerrarCaptura(); } });
  window.addEventListener('resize', cerrarMenu);
  $('#main').addEventListener('scroll', cerrarMenu, { passive:true });
}
