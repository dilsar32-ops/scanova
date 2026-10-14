// Scanova360 · carpeta Dry Logs, con SU diseño (14-oct):
//  · Sin registros: "No dry logs yet" + botón Start Dry Log.
//  · New Dry Log, Step 1 of 3: "Where are you taking the reading?" — primero el nivel (con cuántos cuartos
//    tiene), después el cuarto de ese nivel. Continue se prende cuando ya escogió los dos.
// Los pasos 2 y 3 (material y punto de medida) esperan su diseño: no se inventan.
// TELÉFONO (su diseño del 14-oct): Dry Logs abre con la cámara prendida. Arriba "Dry Logs" y la barrita de pasos
// (1 of 5), luego Level y Room para escoger dónde, y la cámara llena lo que sobra. El botón azul de cámara de
// abajo (el de siempre) toma la foto directo. Lo que sigue después de la foto espera su siguiente diseño.
import { $, $$, authFetch } from './app.js?v=2026-10-14-11';
import { RESTRICCIONES, errorCamara, puedeCamaraPropia } from './camara.js?v=2026-10-14-11';
import * as fotos from './fotos.js?v=2026-10-14-11';
import { leerPantalla } from './lector.js?v=2026-10-14-11';

const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
const IC = (n, cls) => '<svg class="ic' + (cls ? ' ' + cls : '') + '"><use href="#i-' + n + '"/></svg>';

// ---------- lo puro (para las pruebas) ----------
// El ícono de cada cuarto sale de su nombre o su tipo (Kitchen, Dining Room, East Living Room, Hallway…).
const ICONOS = [
  [/kitchen|cocina/, 'dl-cocina'], [/dining|comedor/, 'dl-comedor'], [/living|family|den\b|sala/, 'dl-sofa'],
  [/bath|toilet|powder|ba[ñn]o/, 'dl-bano'], [/bed|master|guest|nursery|rec[aá]mara|dormitorio/, 'dl-cama'],   // baño primero: "Master Bath" es baño
  [/laundry|utility|lavander/, 'dl-lavar'], [/hall|entry|foyer|stair|closet|pasillo|entrada/, 'dl-puerta'],
];
export function iconoCuarto(c){
  const t = String((c && (c.nombre + ' ' + (c.tipo || ''))) || '').toLowerCase();
  const hit = ICONOS.find(([re]) => re.test(t));
  return hit ? hit[1] : 'dl-cuarto';
}
export const cuartosDeNivel = (cuartos, nivelId) => (cuartos || []).filter(c => c.nivel_id === nivelId);
export const textoCuartos = (n) => n + (n === 1 ? ' room' : ' rooms');
// El nivel que sale escogido al abrir: el primero que tiene cuartos (si ninguno tiene, el primero).
export function nivelInicial(niveles, cuartos){
  const con = (niveles || []).find(n => cuartosDeNivel(cuartos, n.id).length);
  return con ? con.id : ((niveles || [])[0] || {}).id || null;
}

// ---------- estado ----------
let T = null, NIVELES = [], CUARTOS = [], PANTALLA = 'vacio', NIVEL = null, CUARTO = null, VOLVIO = false;
// La web (computadora) y el teléfono van a ser distintos (su pedido del 14-oct); el corte es el mismo de la app.
const esCompu = () => typeof matchMedia === 'function' && matchMedia('(min-width:900px)').matches;
// Su regla para la WEB: si en Photos ya se crearon niveles y cuartos, Dry Logs abre directo en escoger nivel y
// cuarto (su foto 2). Sin cuartos todavía: "No dry logs yet" con solo Start Dry Log.
export const abreEnPaso1 = (web, cuartos, volvio) => !!web && (cuartos || []).length > 0 && !volvio;
// TELÉFONO: con cuartos ya creados, Dry Logs abre directo en la cámara (su diseño); sin cuartos, la portada.
export const abreEnCamara = (web, cuartos) => !web && (cuartos || []).length > 0;
export const PASOS_TEL = 5;
// El cuarto que sale escogido en el teléfono: el que ya tenía (si sigue en ese nivel) o el primero del nivel.
export function cuartoInicial(cuartos, nivelId, actual){
  const l = cuartosDeNivel(cuartos, nivelId);
  return l.some(c => c.id === actual) ? actual : ((l[0] || {}).id || null);
}
const caja = () => $('#panel-secado');

// Al entrar a la pestaña (no en cada repintado): lo de "tocó Back" se olvida y vuelve a abrir como la primera vez.
export function entrar(){ VOLVIO = false; if(PANTALLA === 'vacio'){ NIVEL = null; CUARTO = null; } }
// La ficha la llama cada vez que se pinta la pestaña (y cuando llegan los niveles y cuartos).
export function pintar(t, niveles, cuartos){
  if(!t) return;
  if(!T || T.id !== t.id){ PANTALLA = 'vacio'; NIVEL = null; CUARTO = null; VOLVIO = false; }
  T = t; NIVELES = niveles || []; CUARTOS = cuartos || [];
  if(NIVEL && !NIVELES.some(n => n.id === NIVEL)) NIVEL = null;
  if(CUARTO && !CUARTOS.some(c => c.id === CUARTO && c.nivel_id === NIVEL)) CUARTO = null;
  pintarAqui();
}
function pintarAqui(){
  const c = caja(); if(!c || !T) return;
  const web = esCompu();
  if(PANTALLA === 'vacio' && abreEnPaso1(web, CUARTOS, VOLVIO)) PANTALLA = 'paso1';
  if(PANTALLA === 'vacio' && abreEnCamara(web, CUARTOS)) PANTALLA = 'cam';
  const TEL = ['cam', 'lectura', 'guardado', 'equipo'];
  if(web && TEL.includes(PANTALLA)) PANTALLA = 'paso1';   // si giraron la pantalla o la hicieron ancha
  if(PANTALLA === 'cam' || PANTALLA === 'guardado'){
    if(!NIVEL || !cuartosDeNivel(CUARTOS, NIVEL).length) NIVEL = nivelInicial(NIVELES, CUARTOS);
    CUARTO = cuartoInicial(CUARTOS, NIVEL, CUARTO);
    // La cámara ya está en pantalla: solo se repintan Level y Room (volver a dibujar todo apagaría la imagen).
    if(c.dataset.dlPantalla === PANTALLA && c.querySelector('.dl-tel #dlVideo')){ pintarSelectores(); if(PANTALLA === 'cam') medirTel(); return; }
  }
  // Escribiendo el número (pantalla 2): no se vuelve a dibujar encima de lo que está escribiendo.
  if(PANTALLA === 'lectura' && c.dataset.dlPantalla === 'lectura' && c.querySelector('#dlValor')) return;
  if(PANTALLA !== 'cam' && PANTALLA !== 'guardado') apagarCam();
  c.dataset.dlPantalla = PANTALLA;
  c.innerHTML = PANTALLA === 'paso1' ? paso1Html() : PANTALLA === 'paso2' ? paso2Html() : PANTALLA === 'cam' ? camHtml() : PANTALLA === 'lectura' ? lecturaHtml() : PANTALLA === 'guardado' ? guardadoHtml() : PANTALLA === 'equipo' ? equipoHtml() : vacioHtml();
  if(PANTALLA === 'cam'){ medirTel(); encenderCam(); }
  else if(PANTALLA === 'lectura') medirTel();
  else if(PANTALLA === 'guardado'){
    document.body.classList.remove('dl-fijo'); encenderCam();
    // Como su diseño 3: la tira de la cámara arriba (la página sube hasta el Dry Log; se puede bajar para ver el equipo).
    const m = $('#main'); if(m && !web) m.scrollTop = Math.max(0, c.getBoundingClientRect().top - m.getBoundingClientRect().top + m.scrollTop - 4);
  }
  else document.body.classList.remove('dl-fijo');
  ajustarAlto();
}
// WEB (su pedido del 14-oct, "debe utilizar toda la pantalla"): la tarjeta del paso llega hasta abajo de la
// pantalla y Back / Continue quedan al pie. Se mide dentro de #main (lo que se desplaza en la computadora).
export const altoTarjeta = (altoMain, topEnMain, pieMain) => Math.max(420, Math.round(altoMain - topEnMain - pieMain));
function ajustarAlto(){
  const card = $('#panel-secado .dl-paso'), main = $('#main'); if(!card) return;
  if(!esCompu() || !main){ card.style.minHeight = ''; return; }
  const top = card.getBoundingClientRect().top - main.getBoundingClientRect().top + main.scrollTop;
  const alto = altoTarjeta(main.clientHeight, top, 16);
  card.style.minHeight = alto + 'px';
  // Lo que viene debajo de las pestañas (el renglón de avisos) no debe hacer que la página se mueva.
  const sobra = main.scrollHeight - main.clientHeight;
  if(sobra > 0) card.style.minHeight = Math.max(420, alto - sobra) + 'px';
}

function vacioHtml(){
  return `<div class="dl-vacio">
    <span class="dl-vacio-ic">${IC('dl-hoja')}</span>
    <h2>No dry logs yet</h2>
    <p>Start by scanning the first meter reading for this project.</p>
    <button type="button" class="btn btn-accent dl-empezar" data-dl="paso1">${IC('camara')}Start Dry Log</button>
    <small>You'll choose a level, room, material and measurement point next.</small>
  </div>`;
}

const radio = (on) => `<span class="dl-radio${on ? ' on' : ''}" aria-hidden="true"></span>`;
function paso1Html(){
  if(!NIVEL) NIVEL = nivelInicial(NIVELES, CUARTOS);
  const nivel = NIVELES.find(n => n.id === NIVEL);
  const cuartos = nivel ? cuartosDeNivel(CUARTOS, nivel.id) : [];
  const niveles = NIVELES.length
    ? `<div class="dl-niveles" role="radiogroup" aria-label="Level">${NIVELES.map(n => { const k = cuartosDeNivel(CUARTOS, n.id).length, on = n.id === NIVEL;
        return `<button type="button" class="dl-op dl-nivel${on ? ' on' : ''}" role="radio" aria-checked="${on}" data-dl-nivel="${esc(n.id)}">${IC('casa', 'dl-op-ic')}<span class="dl-op-txt"><b>${esc(n.nombre)}</b><small>${textoCuartos(k)}</small></span>${radio(on)}</button>`; }).join('')}</div>`
    : `<div class="dl-falta"><p>This project has no levels yet.</p><button type="button" class="btn btn-outline btn-chico" data-nuevo-nivel>+ Add level</button></div>`;
  const cuartosHtml = !nivel ? '' : cuartos.length
    ? `<div class="dl-cuartos" role="radiogroup" aria-label="Room">${cuartos.map(c => { const on = c.id === CUARTO;
        return `<button type="button" class="dl-op dl-cuarto${on ? ' on' : ''}" role="radio" aria-checked="${on}" data-dl-cuarto="${esc(c.id)}">${IC(iconoCuarto(c), 'dl-op-ic')}<span class="dl-op-txt"><b>${esc(c.nombre)}</b></span>${radio(on)}</button>`; }).join('')}</div>`
    : `<div class="dl-falta"><p>${esc(nivel.nombre)} has no rooms yet. Add them from the ••• menu of the project (Levels & Rooms).</p></div>`;
  return `<div class="card dl-paso">
    <p class="dl-paso-n">New Dry Log · Step 1 of 3</p>
    <h2 class="dl-paso-t">Where are you taking the reading?</h2>
    <p class="dl-paso-sub">First select a level, then choose a room to take a moisture reading.</p>
    <h3 class="dl-sec">1. Select level</h3>${niveles}
    ${nivel ? `<h3 class="dl-sec">2. Select room <small>(${esc(nivel.nombre)})</small></h3>${cuartosHtml}` : ''}
    <div class="dl-pie"><button type="button" class="dl-atras" data-dl="vacio">${IC('atras')}Back</button><button type="button" class="btn btn-accent dl-seguir" data-dl="paso2"${CUARTO ? '' : ' disabled'}>Continue</button></div>
  </div>`;
}
// Paso 2: todavía sin diseño. Se dice tal cual, con su salida (su regla: toda pantalla con regreso abajo).
function paso2Html(){
  const n = NIVELES.find(x => x.id === NIVEL), c = CUARTOS.find(x => x.id === CUARTO);
  return `<div class="card dl-paso">
    <p class="dl-paso-n">New Dry Log · Step 2 of 3</p>
    <h2 class="dl-paso-t">${esc(c ? c.nombre : '')}${n ? ` <small>${esc(n.nombre)}</small>` : ''}</h2>
    <p class="dl-paso-sub">The next step (material and measurement point) is built from your design.</p>
    <div class="dl-pie"><button type="button" class="dl-atras" data-dl="paso1">${IC('atras')}Back</button></div>
  </div>`;
}

// ---------- TELÉFONO: la cámara del Dry Log ----------
const barrita = (n) => `<div class="dl-prog" role="img" aria-label="Step ${n} of ${PASOS_TEL}">${Array.from({ length: PASOS_TEL }, (_, i) => `<i${i < n ? ' class="on"' : ''}></i>`).join('')}</div><span class="dl-prog-n">${n} of ${PASOS_TEL}</span>`;
function selectoresHtml(){
  const nivel = NIVELES.find(n => n.id === NIVEL), cuarto = CUARTOS.find(c => c.id === CUARTO);
  const cuartos = nivel ? cuartosDeNivel(CUARTOS, nivel.id) : [];
  return `<label class="dl-caja">${IC('dl-capas', 'dl-caja-ic')}<span class="dl-caja-txt"><small>Level</small><b>${esc(nivel ? nivel.nombre : 'Choose')}</b></span>${IC('chev', 'dl-caja-chev')}
      <select data-dl-sel="nivel" aria-label="Level">${NIVELES.map(n => `<option value="${esc(n.id)}"${n.id === NIVEL ? ' selected' : ''}>${esc(n.nombre)}</option>`).join('')}</select></label>
    <label class="dl-caja">${IC(cuarto ? iconoCuarto(cuarto) : 'dl-puerta', 'dl-caja-ic')}<span class="dl-caja-txt"><small>Room</small><b>${esc(cuarto ? cuarto.nombre : 'No rooms')}</b></span>${IC('chev', 'dl-caja-chev')}
      <select data-dl-sel="cuarto" aria-label="Room"${cuartos.length ? '' : ' disabled'}>${cuartos.map(c => `<option value="${esc(c.id)}"${c.id === CUARTO ? ' selected' : ''}>${esc(c.nombre)}</option>`).join('')}</select></label>`;
}
function pintarSelectores(){ const s = $('#panel-secado .dl-tel-sel'); if(s) s.innerHTML = selectoresHtml(); }
function camHtml(){
  return `<div class="dl-tel">
    <div class="dl-tel-cab"><h2>Dry Logs</h2>${barrita(1)}</div>
    <div class="dl-tel-sel">${selectoresHtml()}</div>
    ${AVISO_TEL ? `<p class="dl-tel-aviso">${IC('check')}${esc(AVISO_TEL)}</p>` : ''}
    <div class="dl-visor"><video id="dlVideo" playsinline muted autoplay></video>
      <div class="dl-guia" aria-hidden="true"><i></i><i></i><i></i><i></i></div>
      <div class="dl-visor-aviso" id="dlVisorAviso" hidden><p id="dlVisorTxt"></p><button type="button" class="btn btn-outline btn-chico" data-dl-cam="otra">Try again</button><button type="button" class="btn btn-outline btn-chico" data-dl-cam="telefono">Use the phone camera</button></div>
      <p class="dl-visor-pista">Put the meter screen inside the box, then tap the blue camera button</p></div>
  </div>`;
}
// ---------- TELÉFONO: después de la foto (su diseño 2) y lectura guardada + equipo (su diseño 3) ----------
export const MATERIALES_DL = ['Drywall', 'Baseboard', 'Studs', 'Plaster', 'Cabinet', 'Carpet', 'Carpet pad', 'Wood floor', 'Subfloor', 'Tile', 'Concrete', 'Insulation', 'Other'];
const pad2 = (n) => String(n).padStart(2, '0');
export const hoyLocal = (d = new Date()) => d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
// El cuarto que sigue: en el orden de la app (pisos de arriba abajo, y los cuartos de cada piso en su orden).
export function siguienteCuarto(niveles, cuartos, actual){
  const orden = [];
  (niveles || []).forEach(n => cuartosDeNivel(cuartos, n.id).forEach(c => orden.push(c)));
  const i = orden.findIndex(c => c.id === actual);
  return i >= 0 && i < orden.length - 1 ? orden[i + 1] : null;
}
let FOTO = null;      // { blob, url, nivel, cuarto, lectura: { texto, valor } | null } — la foto recién tomada
let GUARDADA = null;  // la última lectura guardada (para la tarjeta "Saved Reading")
let MATERIAL = 'Drywall', UBIC = '', AVISO_TEL = '', OCUPADO_TEL = false;
const nombreDe = (lista, id) => { const x = lista.find(y => y.id === id); return x ? x.nombre : ''; };
function lecturaHtml(){
  const r = FOTO && FOTO.lectura;
  const valor = r ? r.texto : '';
  return `<div class="dl-tel">
    <div class="dl-visor dl-visor-foto">${FOTO ? `<img src="${FOTO.url}" alt="Meter reading photo">` : ''}</div>
    <div class="dl-leido${r ? '' : ' sin-leer'}">
      <span class="dl-leido-ic">${IC('dl-leer')}</span>
      <div class="dl-leido-txt"><small>${r ? 'Reading detected:' : 'Could not read the number. Type it from the meter:'}</small>
        <label class="dl-num"><input id="dlValor" type="text" inputmode="decimal" autocomplete="off" maxlength="6" value="${esc(valor)}" aria-label="Reading"><span>%</span></label></div>
    </div>
    <div class="dl-mat">
      <label class="dl-mini"><small>Material</small><select id="dlMaterial">${MATERIALES_DL.map(m => `<option${m === MATERIAL ? ' selected' : ''}>${esc(m)}</option>`).join('')}</select></label>
      <label class="dl-mini"><small>Where</small><input id="dlUbic" type="text" maxlength="120" placeholder="East wall" value="${esc(UBIC)}"></label>
    </div>
    <p class="dl-confirma">Confirm the number matches the meter.</p>
    <p class="aviso" id="dlAviso"></p>
    <div class="dl-botones"><button type="button" class="btn btn-outline" data-dl-cam="otra-foto">Retake Photo</button><button type="button" class="btn btn-accent" data-dl-guardar>Save Reading</button></div>
  </div>`;
}
function guardadoHtml(){
  const g = GUARDADA, cuarto = g ? g.cuarto_nombre : '';
  const sig = siguienteCuarto(NIVELES, CUARTOS, g ? g.cuarto_id : CUARTO);
  return `<div class="dl-tel">
    <div class="dl-visor dl-visor-tira"><video id="dlVideo" playsinline muted autoplay></video>
      <div class="dl-visor-aviso" id="dlVisorAviso" hidden><p id="dlVisorTxt"></p></div></div>
    <div class="dl-tel-sel">${selectoresHtml()}</div>
    ${g ? `<div class="dl-listo">${IC('check')}<b>Reading saved for ${esc(cuarto)}</b></div>
    <div class="dl-tarjeta"><small>Saved Reading</small>
      <div class="dl-tarjeta-c"><img src="${g.url}" alt="">
        <div><b>${esc([g.material, g.ubicacion].filter(Boolean).join(' • '))}</b><span class="dl-tarjeta-n">${esc(g.texto)}%</span><small>${IC('calendario')}Today</small></div></div></div>` : ''}
    <div class="dl-equipo">
      <div class="dl-equipo-cab"><span class="dl-equipo-ic">${IC('dl-herramientas')}</span><div><b>Equipment for ${esc(cuarto || nombreDe(CUARTOS, CUARTO))}</b><small>Record equipment before moving to another room.</small></div></div>
      <button type="button" class="btn btn-accent" data-dl-equipo="si">Add Equipment</button>
      <button type="button" class="btn btn-outline" data-dl-equipo="no">No Equipment</button>
      <small class="dl-equipo-nota">No Equipment records zero for ${esc(cuarto || 'this room')}${sig ? `, then advances to ${esc(sig.nombre)}` : ''}.</small>
      <p class="aviso" id="dlAviso"></p>
    </div>
  </div>`;
}
function equipoHtml(){
  return `<div class="dl-tel"><div class="dl-tel-cab"><h2>Dry Logs</h2>${barrita(4)}</div>
    <div class="card dl-paso"><p class="dl-paso-n">Equipment for ${esc(GUARDADA ? GUARDADA.cuarto_nombre : nombreDe(CUARTOS, CUARTO))}</p>
    <p class="dl-paso-sub">This screen is built from your next design.</p>
    <div class="dl-pie"><button type="button" class="dl-atras" data-dl-ir="guardado">${IC('atras')}Back</button></div></div></div>`;
}
// La cámara llena lo que sobra de la pantalla hasta la barra de abajo (como el plano; nada de position:fixed).
function medirTel(){
  const v = $('#panel-secado .dl-visor'), m = $('#main'); if(!v || !m || esCompu()) return;
  document.body.classList.add('dl-fijo');
  // Después de la foto (su diseño 2) la pantalla es solo foto, número y botones: la página sube hasta el Dry Log
  // (la cabecera del proyecto queda arriba, fuera de la vista) y la foto se lleva lo que sobra.
  const sube = PANTALLA === 'lectura' ? Math.max(0, $('#panel-secado').getBoundingClientRect().top - m.getBoundingClientRect().top + m.scrollTop - 4) : 0;
  const arriba = v.getBoundingClientRect().top - (m.getBoundingClientRect().top - m.scrollTop) - sube;
  const panel = $('#panel-secado .dl-tel'), ultimo = panel && panel.lastElementChild;
  const resto = ultimo && ultimo !== v ? ultimo.getBoundingClientRect().bottom - v.getBoundingClientRect().bottom : 0;
  const pie = parseFloat(getComputedStyle(m).paddingBottom) || 0;
  const cabe = Math.floor(m.clientHeight - arriba - resto - pie - 2);
  if(cabe >= 220){ v.style.height = cabe + 'px'; const sobra = m.scrollHeight - m.clientHeight - sube; if(sobra > 0) v.style.height = Math.max(220, cabe - sobra) + 'px'; m.scrollTop = sube; }
  else { document.body.classList.remove('dl-fijo'); v.style.height = '360px'; }
}
let STREAM = null, VIGIA = null, PIDIENDO = false;
const camViva = () => { const v = $('#dlVideo'); return !!(STREAM && v && v.offsetParent && v.videoWidth); };
function apagarCam(){
  if(STREAM){ STREAM.getTracks().forEach(t => t.stop()); STREAM = null; }
  const v = $('#dlVideo'); if(v) v.srcObject = null;
  if(VIGIA){ clearInterval(VIGIA); VIGIA = null; }
}
function avisoCam(txt){ const a = $('#dlVisorAviso'); if(!a) return; $('#dlVisorTxt').textContent = txt || ''; a.hidden = !txt; }
async function encenderCam(){
  const v = $('#dlVideo'); if(!v || PIDIENDO) return;
  if(STREAM){ v.srcObject = STREAM; v.play().catch(() => {}); return; }
  if(!puedeCamaraPropia(navigator)){ avisoCam('This device does not let the page use the camera. Use the phone camera.'); return; }
  PIDIENDO = true; avisoCam('');
  try{
    const s = await navigator.mediaDevices.getUserMedia(RESTRICCIONES);
    const v2 = $('#dlVideo');
    if(!v2 || !v2.offsetParent || (PANTALLA !== 'cam' && PANTALLA !== 'guardado')){ s.getTracks().forEach(t => t.stop()); return; }   // ya se fue de la pantalla
    STREAM = s; v2.srcObject = s; await v2.play().catch(() => {});
    // Si se va de la pestaña o de la pantalla, la cámara se apaga sola (no se queda prendida gastando batería).
    if(!VIGIA) VIGIA = setInterval(() => { const x = $('#dlVideo'); if(!x || !x.offsetParent || document.hidden) apagarCam(); }, 1000);
  }catch(e){ avisoCam(errorCamara(e)); }
  finally{ PIDIENDO = false; }
}
// La parte de la foto que está dentro del cuadro guía (el video se ve "cover": hay que deshacer el recorte).
export function guiaEnVideo(vw, vh, W, H, g){
  const esc2 = Math.max(W / vw, H / vh), ox = (W - vw * esc2) / 2, oy = (H - vh * esc2) / 2;
  const x = Math.max(0, (g.x - ox) / esc2), y = Math.max(0, (g.y - oy) / esc2);
  return { x, y, w: Math.min(vw - x, g.w / esc2), h: Math.min(vh - y, g.h / esc2) };
}
function leerDe(canvas, caja){
  try{
    const ctx = canvas.getContext('2d');
    const x = Math.round(caja.x), y = Math.round(caja.y), w = Math.round(caja.w), h = Math.round(caja.h);
    if(w < 20 || h < 20) return null;
    const d = ctx.getImageData(x, y, w, h);
    return leerPantalla({ data: d.data, width: d.width, height: d.height });
  }catch(e){ console.warn('lector', e); return null; }
}
async function disparar(){
  const v = $('#dlVideo'); if(!camViva() || !CUARTO) return;
  const c = document.createElement('canvas'); c.width = v.videoWidth; c.height = v.videoHeight;
  c.getContext('2d').drawImage(v, 0, 0, c.width, c.height);
  // Lo que está dentro del cuadro guía es lo que se lee.
  const visor = v.parentElement, guia = $('#panel-secado .dl-guia');
  let caja = { x: c.width * 0.15, y: c.height * 0.3, w: c.width * 0.7, h: c.height * 0.4 };
  if(guia && visor){ const R = visor.getBoundingClientRect(), Gr = guia.getBoundingClientRect(); caja = guiaEnVideo(c.width, c.height, R.width, R.height, { x: Gr.left - R.left, y: Gr.top - R.top, w: Gr.width, h: Gr.height }); }
  const blob = await new Promise(r => c.toBlob(r, 'image/jpeg', 0.9));
  const lectura = leerDe(c, caja);
  c.width = c.height = 0;
  if(!blob) return;
  ponerFoto(blob, lectura);
}
function ponerFoto(blob, lectura){
  if(FOTO && FOTO.url) URL.revokeObjectURL(FOTO.url);
  FOTO = { blob, url: URL.createObjectURL(blob), nivel: NIVEL, cuarto: CUARTO, lectura: lectura || null };
  apagarCam(); PANTALLA = 'lectura'; pintarAqui();
  const inp = $('#dlValor'); if(inp){ anchoNumero(inp); if(!FOTO.lectura) inp.focus(); }
}
// Sin cámara dentro de la página: la del teléfono. Sin cuadro guía, se lee el centro de la foto.
function camaraDelTelefono(){
  const inp = document.createElement('input'); inp.type = 'file'; inp.accept = 'image/*'; inp.setAttribute('capture', 'environment'); inp.hidden = true;
  inp.addEventListener('change', async () => {
    const f = inp.files && inp.files[0]; inp.remove(); if(!f) return;
    let lectura = null;
    try{ const bmp = await createImageBitmap(f); const c = document.createElement('canvas'); c.width = bmp.width; c.height = bmp.height; c.getContext('2d').drawImage(bmp, 0, 0);
      lectura = leerDe(c, { x: c.width * 0.15, y: c.height * 0.25, w: c.width * 0.7, h: c.height * 0.5 }); c.width = c.height = 0; }catch{}
    ponerFoto(f, lectura);
  });
  document.body.appendChild(inp); inp.click();
}
async function enviarTel(tabla, fila){
  const r = await authFetch('/rest/v1/' + tabla, { method: 'POST', headers: { Prefer: 'return=representation' }, body: JSON.stringify(fila) });
  if(r.status === 404) throw new Error('This part is not installed on the server yet: sql/fotos-09-drylogs.sql still has to be run.');
  if(!r.ok){ let m = 'HTTP ' + r.status; try{ const d = await r.json(); m = d.message || m; }catch{} throw new Error(m); }
  const filas = await r.json().catch(() => []);
  if(!filas.length) throw new Error('The server did not keep it. Try again.');   // confirmar que de verdad se guardó
  return filas[0];
}
const avisarTel = (t) => { $$('#panel-secado #dlAviso').forEach(a => { a.className = 'aviso'; a.textContent = t; }); };
export function valorDe(txt){ const t = String(txt || '').trim().replace(',', '.'); if(!/^\d{1,3}(\.\d)?$/.test(t)) return null; const n = Number(t); return n <= 1000 ? n : null; }
async function guardarLectura(){
  if(OCUPADO_TEL || !FOTO) return;
  const valor = valorDe($('#dlValor').value);
  if(valor == null){ avisarTel('Type the reading as a number (like 18 or 18.5).'); $('#dlValor').focus(); return; }
  MATERIAL = $('#dlMaterial').value; UBIC = ($('#dlUbic').value || '').trim();
  OCUPADO_TEL = true; const b = $('[data-dl-guardar]'); if(b){ b.disabled = true; b.textContent = 'Saving…'; }
  try{
    // La foto va a Photos, a su piso y cuarto: es la prueba de la lectura.
    const archivo = new File([FOTO.blob], 'dry-log-' + hoyLocal() + '-' + Date.now() + '.jpg', { type: 'image/jpeg', lastModified: Date.now() });
    const { foto } = await fotos.subirCopia(archivo, { nivel_id: FOTO.nivel, cuarto_id: FOTO.cuarto });
    const cuarto_nombre = nombreDe(CUARTOS, FOTO.cuarto) || null;
    const fila = await enviarTel('fotos_drylog_lecturas', { trabajo_id: T.id, dia: hoyLocal(), nivel_id: FOTO.nivel || null, cuarto_id: FOTO.cuarto || null, cuarto_nombre,
      material: MATERIAL, ubicacion: UBIC || null, valor, unidad: '%', foto_id: foto ? foto.id : null,
      leido_texto: FOTO.lectura ? FOTO.lectura.texto : null, leido_por: FOTO.lectura ? 'scanova-lector' : null, corregido: !!(FOTO.lectura && FOTO.lectura.valor !== valor) });
    if(GUARDADA && GUARDADA.url && GUARDADA.url !== FOTO.url) URL.revokeObjectURL(GUARDADA.url);
    GUARDADA = { ...fila, texto: String(valor), url: FOTO.url };
    FOTO = null; PANTALLA = 'guardado'; pintarAqui();
  }catch(e){ avisarTel('Not saved: ' + (e.message || e)); }
  finally{ OCUPADO_TEL = false; const b2 = $('[data-dl-guardar]'); if(b2){ b2.disabled = false; b2.textContent = 'Save Reading'; } }
}
// "No Equipment": se anota cero para el cuarto y se pasa al siguiente (su diseño).
async function sinEquipo(){
  if(OCUPADO_TEL) return;
  const cuarto = GUARDADA ? GUARDADA.cuarto_id : CUARTO, nivel = GUARDADA ? GUARDADA.nivel_id : NIVEL, nombre = nombreDe(CUARTOS, cuarto);
  OCUPADO_TEL = true;
  try{
    await enviarTel('fotos_drylog_equipos', { trabajo_id: T.id, dia: hoyLocal(), nivel_id: nivel || null, cuarto_id: cuarto || null, cuarto_nombre: nombre || null, tipo: 'none', cantidad: 0 });
    const sig = siguienteCuarto(NIVELES, CUARTOS, cuarto);
    if(sig){ NIVEL = sig.nivel_id; CUARTO = sig.id; AVISO_TEL = 'No equipment in ' + nombre + '. Next: ' + sig.nombre + '.'; }
    else AVISO_TEL = 'No equipment in ' + nombre + '. That was the last room.';
    GUARDADA = null; PANTALLA = 'cam'; pintarAqui();
  }catch(e){ avisarTel('Not saved: ' + (e.message || e)); }
  finally{ OCUPADO_TEL = false; }
}
// El cuadro del número mide lo que mide el número (así el % queda pegado, como en su diseño).
let MEDIDOR = null;
const anchoNumero = (inp) => {
  try{ MEDIDOR = MEDIDOR || document.createElement('canvas'); const ctx = MEDIDOR.getContext('2d'); const cs = getComputedStyle(inp);
    ctx.font = cs.fontWeight + ' ' + cs.fontSize + ' ' + cs.fontFamily;
    inp.style.width = Math.max(parseFloat(cs.fontSize) * 0.9, ctx.measureText(inp.value || '0').width + 4) + 'px'; }
  catch{ inp.style.width = Math.max(1.2, String(inp.value || '').length * 0.62) + 'em'; }
};
// La ficha la llama al cambiar a otra pestaña.
export function salir(){ apagarCam(); document.body.classList.remove('dl-fijo'); if(['cam', 'lectura', 'guardado', 'equipo'].includes(PANTALLA)) PANTALLA = 'vacio'; }

// ---------- toques ----------
export function conectar(){
  // El botón azul de cámara de abajo: con la cámara del Dry Log en pantalla, toma la foto aquí (no abre la otra cámara).
  document.addEventListener('click', (e) => {
    if(!e.target.closest || !e.target.closest('[data-nav="capture"]')) return;
    if((PANTALLA !== 'cam' && PANTALLA !== 'guardado') || !$('#dlVideo') || !$('#dlVideo').offsetParent) return;
    e.preventDefault(); e.stopImmediatePropagation();
    if(camViva()) disparar(); else camaraDelTelefono();
  }, true);
  document.addEventListener('change', (e) => {
    const sel = e.target.closest && e.target.closest('[data-dl-sel]'); if(!sel || !caja() || !caja().contains(sel)) return;
    if(sel.dataset.dlSel === 'nivel'){ NIVEL = sel.value; CUARTO = cuartoInicial(CUARTOS, NIVEL, null); } else CUARTO = sel.value;
    const av = $('#panel-secado .dl-tel-aviso'); if(av){ av.remove(); AVISO_TEL = ''; }
    pintarSelectores();
  });
  document.addEventListener('input', (e) => { if(e.target && e.target.id === 'dlValor') anchoNumero(e.target); });
  document.addEventListener('visibilitychange', () => { if(document.hidden) apagarCam(); else if((PANTALLA === 'cam' || PANTALLA === 'guardado') && $('#dlVideo') && $('#dlVideo').offsetParent) encenderCam(); });
  window.addEventListener('resize', () => { if(!caja()) return; if(caja().querySelector('.dl-paso')) ajustarAlto(); if(caja().querySelector('.dl-tel')) pintarAqui(); });
  document.addEventListener('click', (e) => {
    const c = caja(); if(!c || !c.contains(e.target)) return;
    const q = (s) => e.target.closest(s);
    let el;
    if((el = q('[data-dl-cam]'))){ const a = el.dataset.dlCam;
      if(a === 'telefono') camaraDelTelefono(); else if(a === 'otra') encenderCam(); else if(a === 'otra-foto'){ PANTALLA = 'cam'; AVISO_TEL = ''; pintarAqui(); }
      return; }
    if(q('[data-dl-guardar]')){ guardarLectura(); return; }
    if((el = q('[data-dl-equipo]'))){ if(el.dataset.dlEquipo === 'no') sinEquipo(); else { PANTALLA = 'equipo'; pintarAqui(); } return; }
    if((el = q('[data-dl-ir]'))){ PANTALLA = el.dataset.dlIr; pintarAqui(); return; }
    if((el = q('[data-dl-nivel]'))){ if(NIVEL !== el.dataset.dlNivel){ NIVEL = el.dataset.dlNivel; CUARTO = null; } pintarAqui(); return; }
    if((el = q('[data-dl-cuarto]'))){ CUARTO = el.dataset.dlCuarto; pintarAqui(); return; }
    if((el = q('[data-dl]'))){
      const a = el.dataset.dl;
      if(a === 'paso2' && !CUARTO) return;
      if(a === 'vacio'){ NIVEL = null; CUARTO = null; VOLVIO = true; }   // tocó Back: se queda en la portada hasta que toque Start
      if(a === 'paso1') VOLVIO = false;
      PANTALLA = a; pintarAqui();
      if(c.scrollIntoView) c.scrollIntoView({ block: 'nearest' });
    }
  });
}
