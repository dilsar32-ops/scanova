// Scanova · la cámara propia: se queda abierta y toma una foto tras otra (la del teléfono solo deja una por vez).
// Cada foto entra a la cola de subida del proyecto en cuanto se toma, y se sube mientras uno sigue tomando.
// Si el teléfono no deja usar la cámara dentro de la página, cae a la cámara normal del teléfono (una por vez).
import { $ } from './app.js';
import * as fotos from './fotos.js';

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

// ---------- la pantalla ----------
let TRABAJO = null, STREAM = null, N = 0, ULTIMA = '';
const video = () => $('#camVideo');

function pintar(){
  $('#camConteo').textContent = conteoTxt(N);
  const m = $('#camUltima');
  m.innerHTML = ULTIMA ? '<img src="' + ULTIMA + '" alt=""><b>' + N + '</b>' : '';
  m.hidden = !ULTIMA;
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
    if(STREAM) $('#camDisparo').disabled = !v.videoWidth;
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
  const c = document.createElement('canvas'); c.width = v.videoWidth; c.height = v.videoHeight;
  c.getContext('2d').drawImage(v, 0, 0, c.width, c.height);
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
