// Scanova · la cámara propia: se queda abierta y toma una foto tras otra (la del teléfono solo deja una por vez).
// Cada foto entra a la cola de subida del proyecto en cuanto se toma, y se sube mientras uno sigue tomando.
// Si el teléfono no deja usar la cámara dentro de la página, cae a la cámara normal del teléfono (una por vez).
import { $ } from './app.js?v=2026-10-15-12';
import * as fotos from './fotos.js?v=2026-10-15-12';

// ---------- lo puro ----------
// Lo que se le pide al teléfono: la cámara de atrás y la resolución más alta que dé (4:3, como una foto).
export const RESTRICCIONES = { audio:false, video:{ facingMode:{ ideal:'environment' }, width:{ ideal:4032 }, height:{ ideal:3024 } } };
export const nombreFoto = (n, d) => 'scanova-' + d.getFullYear() + String(d.getMonth() + 1).padStart(2, '0') + String(d.getDate()).padStart(2, '0') + '-' + String(d.getHours()).padStart(2, '0') + String(d.getMinutes()).padStart(2, '0') + String(d.getSeconds()).padStart(2, '0') + '-' + n + '.jpg';
export const conteoTxt = (n) => n === 0 ? 'Tap the button to take photos' : (n === 1 ? '1 photo' : n + ' photos');
export const puedeCamaraPropia = (nav) => !!(nav && nav.mediaDevices && typeof nav.mediaDevices.getUserMedia === 'function');
// Qué decir cuando la cámara no abre.
export function errorCamara(e){
  const n = e && e.name;
  if(n === 'NotAllowedError' || n === 'SecurityError') return 'Camera access is off for Scanova360. Turn it on in the phone Settings, or use the phone camera below.';
  if(n === 'NotFoundError' || n === 'OverconstrainedError') return 'No camera was found on this device.';
  if(n === 'NotReadableError') return 'Another app is using the camera. Close it and try again.';
  return 'The camera could not start. Use the phone camera below.';
}

// Los botones de zoom que caben entre el mínimo y el máximo de esta cámara (como la cámara del iPhone).
export function botonesZoom(min, max){ return [0.5, 1, 2, 3, 5].filter(z => z >= min - 1e-6 && z <= max + 1e-6).slice(0, 4); }
export const zoomTxt = (z) => (Math.round(z * 10) / 10).toString().replace(/^0\./, '.') + '×';
// El recorte del cuadro cuando el zoom es digital (el centro, 1/z del ancho y del alto).
export function recorteZoom(w, h, z){ const zz = Math.max(1, z || 1); const cw = Math.round(w / zz), ch = Math.round(h / zz); return { sx: Math.round((w - cw) / 2), sy: Math.round((h - ch) / 2), w: cw, h: ch }; }

// ---------- la pantalla ----------
let TRABAJO = null, STREAM = null, N = 0, ULTIMA = '';
const video = () => $('#camVideo');

function pintar(){
  $('#camConteo').textContent = conteoTxt(N);
  const m = $('#camUltima');
  m.innerHTML = ULTIMA ? '<img src="' + ULTIMA + '" alt=""><b>' + N + '</b>' : '';
  m.hidden = !ULTIMA;
}
// ---------- zoom: el de la cámara si el teléfono lo da; si no, digital (se recorta el centro al tomar la foto) ----------
let ZOOM = 1, ZMIN = 1, ZMAX = 5, NATIVO = false, ZOOM_PEND = null;
function pista(){ return STREAM && STREAM.getVideoTracks ? STREAM.getVideoTracks()[0] : null; }
function prepararZoom(){
  ZOOM = 1; NATIVO = false; ZMIN = 1; ZMAX = 5;
  const t = pista(); let c = null; try{ c = t && t.getCapabilities ? t.getCapabilities() : null; }catch{}
  if(c && c.zoom && isFinite(c.zoom.max) && c.zoom.max > c.zoom.min){ NATIVO = true; ZMIN = Math.max(0.5, c.zoom.min); ZMAX = Math.min(10, c.zoom.max);
    try{ const st = t.getSettings ? t.getSettings() : {}; if(isFinite(st.zoom)) ZOOM = st.zoom; }catch{} }
  const v = video(); if(v) v.style.transform = '';
  pintarZoom();
}
function pintarZoom(){
  const caja = $('#camZoom'); if(!caja) return;
  const bs = botonesZoom(ZMIN, ZMAX);
  // El botón que se prende es el más cercano por debajo; si el zoom no es exacto, ese botón dice el número real (1.4×).
  let activo = bs[0]; bs.forEach(b => { if(ZOOM >= b - 0.05) activo = b; });
  caja.innerHTML = bs.map(b => `<button type="button" class="cam-z${b === activo ? ' on' : ''}" data-zoom="${b}">${b === activo ? zoomTxt(ZOOM) : zoomTxt(b).replace('×', '')}</button>`).join('');
  caja.hidden = !STREAM;
}
function ponerZoom(z){
  ZOOM = Math.max(ZMIN, Math.min(ZMAX, z)); pintarZoom();
  if(NATIVO){
    if(ZOOM_PEND) return;   // uno a la vez: el pellizco manda muchos
    ZOOM_PEND = setTimeout(() => { ZOOM_PEND = null; const t = pista(); if(t) t.applyConstraints({ advanced:[{ zoom: ZOOM }] }).catch(() => { NATIVO = false; ZMIN = 1; ZMAX = 5; ponerZoom(Math.max(1, ZOOM)); }); }, 40);
  } else { const v = video(); if(v) v.style.transform = ZOOM > 1 ? 'scale(' + ZOOM + ')' : ''; }
}

function apagar(){ if(STREAM){ STREAM.getTracks().forEach(t => t.stop()); STREAM = null; } const v = video(); if(v) v.srcObject = null; }
async function encender(){
  apagar(); $('#camError').hidden = true; $('#camDisparo').disabled = true;
  try{
    STREAM = await navigator.mediaDevices.getUserMedia(RESTRICCIONES);
    if($('#camara').hidden){ apagar(); return; }   // la cerró mientras pedía permiso
    const v = video(); v.srcObject = STREAM; await v.play().catch(() => {});
    // El disparador se prende hasta que la cámara ya da imagen (antes, el primer toque se perdía).
    if(!v.videoWidth) await new Promise(res => { v.addEventListener('loadeddata', res, { once:true }); setTimeout(res, 3000); });
    if(STREAM){ $('#camDisparo').disabled = !v.videoWidth; prepararZoom(); }
  }catch(e){
    apagar();
    $('#camErrorTxt').textContent = errorCamara(e);
    $('#camError').hidden = false;
  }
}
// Abrir la cámara para un proyecto. Devuelve false si este aparato no tiene cámara para la página
// (entonces se usa la del teléfono, una por vez, en el mismo toque).
// A qué nivel/cuarto van las fotos de la cámara. La ficha del proyecto presta la lista (usarCuartos).
let DEST = {}, CUARTOS = null, ESCOGER_PROYECTO = null;
export const usarEscogerProyecto = (fn) => { ESCOGER_PROYECTO = fn; };
export const usarCuartos = (api) => { CUARTOS = api; };
export function pintarCuarto(){
  const b = $('#camCuarto'); if(!b) return;
  // Siempre a la vista (aunque el proyecto todavía no tenga niveles: desde aquí se crean).
  const hay = !!(CUARTOS && TRABAJO && CUARTOS.hay(TRABAJO.id));
  b.hidden = !CUARTOS || !TRABAJO;
  $('#camCuartoTxt').textContent = hay && (DEST.nivel_id || DEST.cuarto_id) ? CUARTOS.nombre(DEST) : 'Level & room';
}
export function abrir(trabajo){
  if(!trabajo) return false;
  if(!puedeCamaraPropia(navigator)){ camaraDelTelefono(); return false; }
  TRABAJO = trabajo; N = 0; if(ULTIMA){ URL.revokeObjectURL(ULTIMA); ULTIMA = ''; }
  DEST = CUARTOS && CUARTOS.hay(trabajo.id) ? CUARTOS.destino() : {}; pintarCuarto();
  $('#camProyecto').textContent = trabajo.cliente || '';
  $('#camara').hidden = false; document.body.classList.add('con-camara');
  pintar(); encender();
  return true;
}
// Cambiar de proyecto sin cerrar la cámara (desde "Taking photos for…").
export function cambiar(trabajo){
  if(!trabajo) return;
  TRABAJO = trabajo; DEST = {};
  $('#camProyecto').textContent = trabajo.cliente || '';
  pintarCuarto(); pintar();
}
export function cerrar(){
  apagar(); $('#camara').hidden = true; document.body.classList.remove('con-camara'); TRABAJO = null;
}
// La cámara normal del teléfono (una foto por vez). Tiene que correr dentro del toque, por eso es síncrona.
export function camaraDelTelefono(){
  const inp = document.createElement('input'); inp.type = 'file'; inp.accept = 'image/*'; inp.setAttribute('capture', 'environment'); inp.hidden = true;
  inp.addEventListener('change', () => { fotos.encolar(inp.files); inp.remove(); });
  document.body.appendChild(inp); inp.click();
}
async function disparar(){
  const v = video(); if(!STREAM || !v || !v.videoWidth || !TRABAJO) return;
  // Con zoom digital se guarda solo el centro (lo que se ve en la pantalla); con el zoom de la cámara, el cuadro entero.
  const r = NATIVO ? { sx:0, sy:0, w:v.videoWidth, h:v.videoHeight } : recorteZoom(v.videoWidth, v.videoHeight, ZOOM);
  const c = document.createElement('canvas'); c.width = r.w; c.height = r.h;
  c.getContext('2d').drawImage(v, r.sx, r.sy, r.w, r.h, 0, 0, r.w, r.h);
  const f = $('#camFlash'); f.classList.remove('on'); void f.offsetWidth; f.classList.add('on');
  const blob = await new Promise(r => c.toBlob(r, 'image/jpeg', 0.92));
  c.width = c.height = 0;
  if(!blob) return;
  N++;
  const archivo = new File([blob], nombreFoto(N, new Date()), { type:'image/jpeg', lastModified: Date.now() });
  if(ULTIMA) URL.revokeObjectURL(ULTIMA); ULTIMA = URL.createObjectURL(blob);
  pintar();
  if(fotos.trabajoActual() && fotos.trabajoActual().id === TRABAJO.id) fotos.encolar([archivo], DEST);
}

export function conectar(){
  $('#camDisparo').addEventListener('click', disparar);
  $('#camListo').addEventListener('click', cerrar);
  $('#camCerrar').addEventListener('click', cerrar);
  $('#camOtraVez').addEventListener('click', encender);
  $('#camTelefono').addEventListener('click', () => { camaraDelTelefono(); });
  $('#camCuarto').addEventListener('click', () => { if(CUARTOS && TRABAJO && CUARTOS.hay(TRABAJO.id)) CUARTOS.escoger('Photos go to…', DEST, (d) => { DEST = d || {}; pintarCuarto(); }); });
  $('#camProyectoBtn').addEventListener('click', () => { if(ESCOGER_PROYECTO) ESCOGER_PROYECTO(); });
  // Zoom: los botones (1× 2× 3×) y pellizcar con dos dedos sobre la imagen.
  $('#camZoom').addEventListener('click', (e) => { const b = e.target.closest('[data-zoom]'); if(b) ponerZoom(Number(b.dataset.zoom)); });
  let pinza = null;
  const dist = (t) => Math.hypot(t[0].clientX - t[1].clientX, t[0].clientY - t[1].clientY);
  const cam = $('#camara');
  cam.addEventListener('touchstart', (e) => { if(e.touches.length === 2 && STREAM){ pinza = { d: dist(e.touches), z: ZOOM }; } }, { passive:true });
  cam.addEventListener('touchmove', (e) => { if(pinza && e.touches.length === 2){ e.preventDefault(); ponerZoom(pinza.z * dist(e.touches) / pinza.d); } }, { passive:false });
  cam.addEventListener('touchend', (e) => { if(e.touches.length < 2) pinza = null; }, { passive:true });
  // "Tomar fotos" de la ficha del proyecto.
  document.addEventListener('click', (e) => {
    if(!e.target.closest('[data-camara]')) return;
    const t = fotos.trabajoActual(); if(t) abrir(t);
  });
  // Si el teléfono se bloquea o se cambia de app, la cámara se apaga; al volver, se vuelve a prender.
  document.addEventListener('visibilitychange', () => {
    if($('#camara').hidden) return;
    if(document.hidden) apagar(); else encender();
  });
  document.addEventListener('keydown', (e) => { if($('#camara').hidden) return; if(e.key === 'Escape') cerrar(); if(e.key === ' ' || e.key === 'Enter'){ e.preventDefault(); disparar(); } });
}
