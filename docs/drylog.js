// Scanova360 · carpeta Dry Logs, con SU diseño (14-oct):
//  · Sin registros: "No dry logs yet" + botón Start Dry Log.
//  · New Dry Log, Step 1 of 3: "Where are you taking the reading?" — primero el nivel (con cuántos cuartos
//    tiene), después el cuarto de ese nivel. Continue se prende cuando ya escogió los dos.
// Los pasos 2 y 3 (material y punto de medida) esperan su diseño: no se inventan.
// TELÉFONO (su diseño del 14-oct): Dry Logs abre con la cámara prendida. Arriba "Dry Logs" y en qué cuarto va
// (Room 1 of 4), luego Level y Room para escoger dónde, y la cámara llena lo que sobra. El botón azul de cámara de
// abajo (el de siempre) toma la foto directo. Lo que sigue después de la foto espera su siguiente diseño.
import { $, $$, authFetch, registrarAtras } from './app.js?v=2026-10-14-14';
import { RESTRICCIONES, errorCamara, puedeCamaraPropia } from './camara.js?v=2026-10-14-14';
import * as fotos from './fotos.js?v=2026-10-14-14';
import { leerPantalla } from './lector.js?v=2026-10-14-14';
import * as R from './registro.js?v=2026-10-14-14';

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

// ---------- el registro del proyecto (lo anotado todos los días): se carga una vez y se va sumando lo que se guarda ----------
let LECT = [], EQUI = [], REG_DE = null, REG_CARGANDO = false, AUTO = false;   // AUTO: el cuarto lo escogió la app (no la persona)
export const registro = () => ({ lecturas: LECT, equipos: EQUI });
async function cargarRegistro(forzar){
  if(!T || REG_CARGANDO || (REG_DE === T.id && !forzar)) return;
  const id = T.id; REG_CARGANDO = true;
  try{
    const q = (t) => authFetch('/rest/v1/' + t + '?trabajo_id=eq.' + encodeURIComponent(id) + '&order=dia.asc,created_at.asc&limit=5000').then(r => r.ok ? r.json() : []).catch(() => []);
    const [l, e] = await Promise.all([q('fotos_drylog_lecturas'), q('fotos_drylog_equipos')]);
    if(!T || T.id !== id) return;
    LECT = Array.isArray(l) ? l : []; EQUI = Array.isArray(e) ? e : []; REG_DE = id;
  }finally{ REG_CARGANDO = false; }
  if(T && T.id === id){ if(AUTO && PANTALLA === 'cam'){ CUARTO = null; } pintarAqui(); }
}
const HOY = () => hoyLocal();
const recorrido = () => R.cuartosDelRecorrido(NIVELES, CUARTOS, LECT, EQUI, HOY());
const diaNum = () => R.numeroDia(LECT, EQUI, HOY());

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
export function entrar(){ VOLVIO = false; AVISO_TEL = ''; if(PANTALLA === 'vacio'){ NIVEL = null; CUARTO = null; } if(T) cargarRegistro(true); }   // lo que anotaron otros, al día
// La ficha la llama cada vez que se pinta la pestaña (y cuando llegan los niveles y cuartos).
export function pintar(t, niveles, cuartos){
  if(!t) return;
  if(!T || T.id !== t.id){ PANTALLA = 'vacio'; NIVEL = null; CUARTO = null; VOLVIO = false; LECT = []; EQUI = []; REG_DE = null; }
  T = t; NIVELES = niveles || []; CUARTOS = cuartos || [];
  cargarRegistro();
  if(NIVEL && !NIVELES.some(n => n.id === NIVEL)) NIVEL = null;
  if(CUARTO && !CUARTOS.some(c => c.id === CUARTO && c.nivel_id === NIVEL)) CUARTO = null;
  pintarAqui();
}
function pintarAqui(){
  const c = caja(); if(!c || !T) return;
  const web = esCompu();
  if(PANTALLA === 'vacio' && abreEnPaso1(web, CUARTOS, VOLVIO)) PANTALLA = 'paso1';
  if(PANTALLA === 'vacio' && abreEnCamara(web, CUARTOS)) PANTALLA = 'cam';
  const TEL = ['cam', 'lectura', 'guardado', 'equipo', 'dia'];
  if(web && TEL.includes(PANTALLA) && PANTALLA !== 'dia') PANTALLA = 'paso1';   // si giraron la pantalla o la hicieron ancha
  if(!web && ['paso1', 'paso2', 'paso3'].includes(PANTALLA) && abreEnCamara(web, CUARTOS)) PANTALLA = 'cam';   // y de regreso a lo angosto: la cámara
  if(PANTALLA === 'cam' && !CUARTO){
    // Al abrir: el primer cuarto del recorrido que todavía no se lee hoy (el día 2, solo los cuartos afectados).
    const r = recorrido(), c = r.find(x => !R.lecturasDelDia(LECT, x.id, HOY()).length) || r[0];
    if(c){ NIVEL = c.nivel_id; CUARTO = c.id; AUTO = true; }
  }
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
  c.innerHTML = PANTALLA === 'paso1' ? paso1Html() : PANTALLA === 'paso2' ? paso2Html() : PANTALLA === 'paso3' ? paso3Html() : PANTALLA === 'cam' ? camHtml() : PANTALLA === 'lectura' ? lecturaHtml() : PANTALLA === 'guardado' ? guardadoHtml() : PANTALLA === 'equipo' ? equipoHtml() : PANTALLA === 'dia' ? diaHtml() : vacioHtml();
  if(PANTALLA === 'cam'){ medirTel(); encenderCam(); }
  else if(PANTALLA === 'lectura') medirTel();
  else if(PANTALLA === 'guardado'){
    document.body.classList.remove('dl-fijo'); encenderCam();
    // La cabecera del cliente se queda a la vista (su pedido del 14-oct); se baja con el dedo para ver el equipo.
    const m = $('#main'); if(m && !web) m.scrollTop = 0;
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
        const hoyN = R.lecturasDelDia(LECT, c.id, HOY()).length;
        return `<button type="button" class="dl-op dl-cuarto${on ? ' on' : ''}" role="radio" aria-checked="${on}" data-dl-cuarto="${esc(c.id)}">${IC(iconoCuarto(c), 'dl-op-ic')}<span class="dl-op-txt"><b>${esc(c.nombre)}</b>${hoyN ? `<small class="dl-leido-hoy">${IC('check')}Read today</small>` : ''}</span>${radio(on)}</button>`; }).join('')}</div>`
    : `<div class="dl-falta"><p>${esc(nivel.nombre)} has no rooms yet. Add them from the ••• menu of the project (Levels & Rooms).</p></div>`;
  return `<div class="card dl-paso">
    <p class="dl-paso-n">${diaNum() > 1 ? 'Day ' + diaNum() + ' · ' + esc(R.fechaLarga(HOY())) + ' · ' : 'New Dry Log · '}Step 1 of 3</p>
    ${AVISO_TEL ? `<p class="dl-tel-aviso">${IC('check')}${esc(AVISO_TEL)}</p>` : ''}
    <h2 class="dl-paso-t">Where are you taking the reading?</h2>
    <p class="dl-paso-sub">First select a level, then choose a room to take a moisture reading.</p>
    <h3 class="dl-sec">1. Select level</h3>${niveles}
    ${nivel ? `<h3 class="dl-sec">2. Select room <small>(${esc(nivel.nombre)})</small></h3>${cuartosHtml}` : ''}
    <div class="dl-pie"><button type="button" class="dl-atras" data-dl="vacio">${IC('atras')}Back</button><button type="button" class="btn btn-accent dl-seguir" data-dl="paso2"${CUARTO ? '' : ' disabled'}>Continue</button></div>
  </div>`;
}
// COMPUTADORA, paso 2 de 3 (la lectura): material, dónde y el número del medidor; la foto del medidor si se tiene.
// Del día 2 en adelante sale el punto que toca y se compara con la visita anterior, igual que en el teléfono.
function paso2Html(){
  const n = NIVELES.find(x => x.id === NIVEL), c = CUARTOS.find(x => x.id === CUARTO);
  const hoyL = R.lecturasDelDia(LECT, CUARTO, HOY());
  return `<div class="card dl-paso dl-web">
    <p class="dl-paso-n">${diaNum() > 1 ? 'Day ' + diaNum() + ' · ' : 'New Dry Log · '}Step 2 of 3</p>
    <h2 class="dl-paso-t">${esc(c ? c.nombre : '')}${n ? ` <small>${esc(n.nombre)}</small>` : ''}</h2>
    <p class="dl-paso-sub">Type the reading from the meter. Add the meter photo as proof if you have it.</p>
    ${antesHtml()}
    ${hoyL.length ? `<div class="dl-web-hoy"><small>Today in ${esc(c ? c.nombre : 'this room')}</small>${hoyL.map(f => `<div class="dl-dia-l"><span class="dl-dia-p">${esc(R.nombrePunto(f))}</span><b>${esc(fmtValor(f.valor))}%</b><button type="button" class="dl-dia-x" data-dl-borrar="${esc(f.id)}" aria-label="Delete this reading">✕</button></div>`).join('')}</div>` : ''}
    <div class="dl-web-forma">
      <label class="dl-mini"><small>Material</small><select id="dlMaterial">${(MATERIALES_DL.includes(MATERIAL) ? MATERIALES_DL : [MATERIAL, ...MATERIALES_DL]).map(m => `<option${m === MATERIAL ? ' selected' : ''}>${esc(m)}</option>`).join('')}</select></label>
      <label class="dl-mini"><small>Where</small><input id="dlUbic" type="text" maxlength="120" placeholder="East wall" value="${esc(UBIC)}"></label>
      <label class="dl-mini dl-mini-n"><small>Reading</small><span class="dl-web-n"><input id="dlValor" type="text" inputmode="decimal" autocomplete="off" maxlength="6" placeholder="0"><span>%</span></span></label>
      <label class="dl-mini dl-web-foto"><small>Meter photo <i>(optional)</i></small><input id="dlWebFoto" type="file" accept="image/*"></label>
    </div>
    ${compararHtml('')}
    <p class="aviso" id="dlAviso"></p>
    <div class="dl-pie"><button type="button" class="dl-atras" data-dl="paso1">${IC('atras')}Back</button>
      <span class="dl-pie-der"><button type="button" class="btn btn-outline" data-dl-web-guardar>Save Reading</button><button type="button" class="btn btn-accent dl-seguir" data-dl="paso3">Continue</button></span></div>
  </div>`;
}
// COMPUTADORA, paso 3 de 3: el equipo del cuarto (las mismas filas del teléfono) y al siguiente cuarto.
function paso3Html(){
  const n = NIVELES.find(x => x.id === NIVEL), c = CUARTOS.find(x => x.id === CUARTO);
  return `<div class="card dl-paso dl-web">
    <p class="dl-paso-n">${diaNum() > 1 ? 'Day ' + diaNum() + ' · ' : 'New Dry Log · '}Step 3 of 3</p>
    <h2 class="dl-paso-t">Equipment in ${esc(c ? c.nombre : '')}${n ? ` <small>${esc(n.nombre)}</small>` : ''}</h2>
    ${EQ.previo && EQ.previo < HOY() ? `<p class="dl-paso-sub">On site since the last visit (${esc(R.fechaCorta(EQ.previo))}). Change only what moved.</p>` : '<p class="dl-paso-sub">Count the equipment running in this room.</p>'}
    <div class="dl-eq-lista dl-web-eq">${equipoFilasHtml()}</div>
    <p class="aviso" id="dlAviso"></p>
    <div class="dl-pie"><button type="button" class="dl-atras" data-dl="paso2">${IC('atras')}Back</button><button type="button" class="btn btn-accent dl-seguir" data-eq-guardar>Save Equipment &amp; Next Room</button></div>
  </div>`;
}
async function guardarWeb(){
  if(OCUPADO_TEL || !CUARTO) return;
  const valor = valorDe(($('#dlValor') || {}).value);
  if(valor == null){ avisarTel('Type the reading as a number (like 18 or 18.5).'); const i = $('#dlValor'); if(i) i.focus(); return; }
  MATERIAL = $('#dlMaterial').value; UBIC = ($('#dlUbic').value || '').trim();
  const archivo = ($('#dlWebFoto') && $('#dlWebFoto').files[0]) || null;
  OCUPADO_TEL = true; const b = $('[data-dl-web-guardar]'); if(b){ b.disabled = true; b.textContent = 'Saving…'; }
  try{
    let foto = null; if(archivo) ({ foto } = await fotos.subirCopia(archivo, { nivel_id: NIVEL, cuarto_id: CUARTO }));
    const fila = await enviarTel('fotos_drylog_lecturas', { trabajo_id: T.id, dia: hoyLocal(), nivel_id: NIVEL || null, cuarto_id: CUARTO, cuarto_nombre: nombreDe(CUARTOS, CUARTO) || null,
      material: MATERIAL, ubicacion: UBIC || null, valor, unidad: '%', foto_id: foto ? foto.id : null, leido_texto: null, leido_por: null, corregido: false });
    LECT.push(fila);
    const pend = R.puntosPendientes(LECT, CUARTO, HOY())[0];   // el que sigue, ya escrito
    if(pend){ MATERIAL = pend.material || MATERIAL; UBIC = pend.ubicacion || ''; } else UBIC = '';
    pintarAqui(); avisarTel(''); const a = $('#dlAviso'); if(a){ a.className = 'aviso ok'; a.textContent = 'Saved ' + fmtValor(valor) + '% · ' + R.nombrePunto(fila) + '.'; }
  }catch(e){ avisarTel('Not saved: ' + (e.message || e)); }
  finally{ OCUPADO_TEL = false; const b2 = $('[data-dl-web-guardar]'); if(b2){ b2.disabled = false; b2.textContent = 'Save Reading'; } }
}

// ---------- TELÉFONO: la cámara del Dry Log ----------
function selectoresHtml(){
  const nivel = NIVELES.find(n => n.id === NIVEL), cuarto = CUARTOS.find(c => c.id === CUARTO);
  const cuartos = nivel ? cuartosDeNivel(CUARTOS, nivel.id) : [];
  return `<label class="dl-caja">${IC('dl-capas', 'dl-caja-ic')}<span class="dl-caja-txt"><small>Level</small><b>${esc(nivel ? nivel.nombre : 'Choose')}</b></span>${IC('chev', 'dl-caja-chev')}
      <select data-dl-sel="nivel" aria-label="Level">${NIVELES.map(n => `<option value="${esc(n.id)}"${n.id === NIVEL ? ' selected' : ''}>${esc(n.nombre)}</option>`).join('')}</select></label>
    <label class="dl-caja">${IC(cuarto ? iconoCuarto(cuarto) : 'dl-puerta', 'dl-caja-ic')}<span class="dl-caja-txt"><small>Room</small><b>${esc(cuarto ? cuarto.nombre : 'No rooms')}</b></span>${IC('chev', 'dl-caja-chev')}
      <select data-dl-sel="cuarto" aria-label="Room"${cuartos.length ? '' : ' disabled'}>${cuartos.map(c => `<option value="${esc(c.id)}"${c.id === CUARTO ? ' selected' : ''}>${esc(c.nombre)}</option>`).join('')}</select></label>`;
}
function pintarSelectores(){
  const s = $('#panel-secado .dl-tel-sel'); if(s) s.innerHTML = selectoresHtml();
  // "Room X of N" sigue al cuarto escogido.
  const cab = $('#panel-secado .dl-tel-cab'); if(cab){ cab.querySelectorAll('.dl-prog-btn').forEach(x => x.remove()); cab.insertAdjacentHTML('beforeend', barritaCuartos()); }
  const pista = $('#panel-secado .dl-antes'); if(pista) pista.outerHTML = antesHtml();
  // El aviso de arriba también (si no, decía lo del cuarto anterior al brincar uno).
  if(PANTALLA !== 'cam') return;
  const av = $('#panel-secado .dl-tel > .dl-tel-aviso');
  if(av && !AVISO_TEL) av.remove();
  else if(av) av.lastChild.textContent = AVISO_TEL;
  else if(AVISO_TEL && s) s.insertAdjacentHTML('afterend', `<p class="dl-tel-aviso">${IC('check')}${esc(AVISO_TEL)}</p>`);
}
function camHtml(){
  return `<div class="dl-tel">
    <div class="dl-tel-cab"><h2>Dry Logs</h2>${barritaCuartos()}</div>
    <div class="dl-tel-sel">${selectoresHtml()}</div>
    ${AVISO_TEL ? `<p class="dl-tel-aviso">${IC('check')}${esc(AVISO_TEL)}</p>` : ''}
    ${antesHtml()}
    <div class="dl-visor"><video id="dlVideo" playsinline muted autoplay></video>
      <div class="dl-guia" aria-hidden="true"><i></i><i></i><i></i><i></i></div>
      <button type="button" class="dl-saltar" data-dl-saltar>Skip room${IC('chev-der')}</button>
      <div class="dl-visor-aviso" id="dlVisorAviso" hidden><p id="dlVisorTxt"></p><button type="button" class="btn btn-outline btn-chico" data-dl-cam="otra">Try again</button><button type="button" class="btn btn-outline btn-chico" data-dl-cam="telefono">Use the phone camera</button></div>
      <p class="dl-visor-pista">Put the meter screen inside the box, then tap the blue camera button</p></div>
  </div>`;
}
// Del día 2 en adelante: qué punto toca medir (el de la visita anterior) y cuánto marcó, para medir en el mismo lugar.
function antesHtml(){
  if(!CUARTO) return '<p class="dl-antes" hidden></p>';
  const hoy = HOY(), pend = R.puntosPendientes(LECT, CUARTO, hoy), hechos = R.lecturasDelDia(LECT, CUARTO, hoy).length;
  if(pend.length){ const p = pend[0], v = R.visitaAnterior(LECT, CUARTO, hoy);
    return `<p class="dl-antes">${IC('dl-leer')}<span>Measure <b>${esc(p.nombre)}</b> · ${esc(fmtValor(p.valor))}% on ${esc(R.fechaCorta(v.dia))}${pend.length > 1 ? ` <small>+${pend.length - 1} more</small>` : ''}</span></p>`; }
  if(hechos) return `<p class="dl-antes listo">${IC('check')}<span>${hechos} reading${hechos === 1 ? '' : 's'} taken here today</span></p>`;
  return '<p class="dl-antes" hidden></p>';
}
const fmtValor = (v) => (Math.round(Number(v) * 10) / 10).toString();
// ---------- TELÉFONO: después de la foto (su diseño 2) y lectura guardada + equipo (su diseño 3) ----------
export const MATERIALES_DL = ['Drywall', 'Baseboard', 'Studs', 'Plaster', 'Cabinet', 'Carpet', 'Carpet pad', 'Wood floor', 'Subfloor', 'Tile', 'Concrete', 'Insulation', 'Other'];
const pad2 = (n) => String(n).padStart(2, '0');
export const hoyLocal = (d = new Date()) => d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
// El cuarto que sigue: en el orden de la app (pisos de arriba abajo, y los cuartos de cada piso en su orden).
export function siguienteCuarto(niveles, cuartos, actual, lista){
  const orden = lista ? lista.slice() : [];
  if(!lista) (niveles || []).forEach(n => cuartosDeNivel(cuartos, n.id).forEach(c => orden.push(c)));
  const i = orden.findIndex(c => c.id === actual);
  if(i < 0){ // un cuarto fuera del recorrido (lo escogió a mano): sigue el primero del recorrido que viene después en la app
    const todos = []; (niveles || []).forEach(n => cuartosDeNivel(cuartos, n.id).forEach(c => todos.push(c)));
    const j = todos.findIndex(c => c.id === actual); return todos.slice(j + 1).find(c => orden.some(o => o.id === c.id)) || null;
  }
  return i < orden.length - 1 ? orden[i + 1] : null;
}
let FOTO = null;      // { blob, url, nivel, cuarto, lectura: { texto, valor } | null } — la foto recién tomada
let GUARDADA = null;  // la última lectura guardada (para la tarjeta "Saved Reading")
let MATERIAL = 'Drywall', UBIC = '', AVISO_TEL = '', OCUPADO_TEL = false;
const nombreDe = (lista, id) => { const x = lista.find(y => y.id === id); return x ? x.nombre : ''; };
// Su diseño (14-oct): "Scan <cuarto>", la foto, la caja "Reading detected" con el número grande, Retake / Save Reading.
// Material y dónde (los necesita el reporte y el día 2) van en una línea; el día 1 sale abierta para escribirlos.
let PUNTO_ABIERTO = false;
function lecturaHtml(){
  const r = FOTO && FOTO.lectura, valor = r ? r.texto : '';
  const cuarto = nombreDe(CUARTOS, FOTO ? FOTO.cuarto : CUARTO);
  return `<div class="dl-tel">
    <div class="dl-tel-cab"><h2>Dry Logs</h2>${barritaCuartos()}</div>
    <div class="card dl-lec">
      <div class="dl-tel-sel">${selectoresHtml()}</div>
      <h3 class="dl-lec-t">Scan ${esc(cuarto || 'this room')}</h3>
      <p class="dl-lec-sub">Point the camera at your moisture meter and take a photo.</p>
      <div class="dl-visor dl-visor-foto">${FOTO ? `<img src="${FOTO.url}" alt="Meter reading photo">` : ''}<button type="button" class="dl-retomar" data-dl-cam="otra-foto">${IC('girar-der')}Retake</button></div>
      <div class="dl-det${r ? '' : ' sin'}">
        <span class="dl-det-ic">${r ? IC('check') : '!'}</span>
        <div class="dl-det-txt"><b>${r ? 'Reading detected' : 'Type the reading'}</b>${compararHtml(valor) || ''}<small class="dl-det-sub">${r ? 'Moisture meter value captured successfully.' : 'Could not read the meter. Type the number you see.'}</small></div>
        <label class="dl-num dl-det-n"><input id="dlValor" type="text" inputmode="decimal" autocomplete="off" maxlength="6" value="${esc(valor)}" aria-label="Reading"><span>%</span></label>
      </div>
      <div class="dl-lec-acc">${accionesLecturaHtml()}</div>
    </div>
  </div>`;
}
// Lo de abajo de la lectura (su pedido del 14-oct): "Continue" (guarda y va al equipo) y "+ Add another reading".
// Material y dónde solo salen cuando hacen falta: al tocar "Add another reading", cuando ya hay otra lectura de hoy en
// el cuarto (para distinguir los puntos) o, del día 2, ya escritos en una línea con el punto de la visita anterior.
const campoPunto = () => {
  const cuarto = FOTO ? FOTO.cuarto : CUARTO, otroHoy = R.lecturasDelDia(LECT, cuarto, HOY()).length > 0;
  return { campos: PUNTO_ABIERTO || otroHoy, linea: !PUNTO_ABIERTO && !otroHoy && !!(FOTO && FOTO.prellenado) };
};
function accionesLecturaHtml(){
  const { campos, linea } = campoPunto(), cuarto = FOTO ? FOTO.cuarto : CUARTO;
  const quedan = R.puntosPendientes(LECT, cuarto, HOY()).filter(p => p.clave !== R.clavePunto({ material: MATERIAL, ubicacion: UBIC }));
  const otro = campos || linea
    ? `<button type="button" class="btn btn-outline" data-dl-siguiente>${IC('camara')}${quedan.length ? 'Next point' : 'Take next reading'}</button>`
    : `<button type="button" class="btn btn-outline" data-dl-otra>${IC('mas')}Add another reading</button>`;
  return `${campos ? `<div class="dl-mat">
      <label class="dl-mini"><small>Material</small><select id="dlMaterial">${(MATERIALES_DL.includes(MATERIAL) ? MATERIALES_DL : [MATERIAL, ...MATERIALES_DL]).map(m => `<option${m === MATERIAL ? ' selected' : ''}>${esc(m)}</option>`).join('')}</select></label>
      <label class="dl-mini"><small>Where</small><input id="dlUbic" type="text" maxlength="120" placeholder="East wall" value="${esc(UBIC)}"></label>
    </div>` : linea ? `<button type="button" class="dl-punto" data-dl-otra>${IC('dl-leer')}<span>${esc(R.nombrePunto({ material: MATERIAL, ubicacion: UBIC }))}</span><b>${IC('lapiz')}Edit</b></button>` : ''}
    <p class="aviso" id="dlAviso"></p>
    <div class="dl-botones">${otro}<button type="button" class="btn btn-accent" data-dl-guardar>Continue</button></div>`;
}
function pintarAcciones(){ const a = $('#panel-secado .dl-lec-acc'); if(a){ a.innerHTML = accionesLecturaHtml(); medirTel(); } }
// Lo que marcó la vez pasada este mismo punto (material + dónde): "Last: 45% on Oct 13 ▼ 5".
function compararHtml(valorTxt){
  const cuarto = FOTO ? FOTO.cuarto : CUARTO, ant = cuarto && R.lecturaAnterior(LECT, cuarto, MATERIAL, UBIC, HOY()); if(!ant) return '<span class="dl-compara" hidden></span>';
  const v = valorDe(valorTxt), t = v == null ? null : R.tendencia(ant.valor, v);
  return `<span class="dl-compara${t ? ' ' + t.tipo : ''}" title="Last reading: ${esc(fmtValor(ant.valor))}% on ${esc(R.fechaCorta(ant.dia))}">Last: ${esc(fmtValor(ant.valor))}%${t ? ' · ' + esc(t.texto) : ' on ' + esc(R.fechaCorta(ant.dia))}</span>`;
}
function repintarComparar(){ const c = $('#panel-secado .dl-compara'); const i = $('#dlValor'); if(c && i){ if($('#dlMaterial')) MATERIAL = $('#dlMaterial').value; if($('#dlUbic')) UBIC = ($('#dlUbic').value || '').trim(); c.outerHTML = compararHtml(i.value); } }
function tendGuardada(g){
  const ant = R.lecturaAnterior(LECT, g.cuarto_id, g.material, g.ubicacion, HOY()), t = ant && R.tendencia(ant.valor, Number(g.texto));
  return t ? ` <span class="dl-tend ${t.tipo}">${esc(t.texto)} from ${esc(R.fechaCorta(ant.dia))}</span>` : '';
}
// Otro punto en el mismo cuarto: el que falta de la visita anterior, o uno nuevo.
function otroPuntoHtml(g){
  const cuarto = g ? g.cuarto_id : CUARTO, pend = R.puntosPendientes(LECT, cuarto, HOY());
  return pend.length
    ? `<button type="button" class="dl-otro dl-otro-pend" data-dl-otro>${IC('camara')}<span>Next point: <b>${esc(pend[0].nombre)}</b><small>${esc(fmtValor(pend[0].valor))}% last time${pend.length > 1 ? ' · ' + (pend.length - 1) + ' more' : ''}</small></span>${IC('chev-der')}</button>`
    : `<button type="button" class="dl-otro" data-dl-otro>${IC('mas-circulo')}<span>Take another reading here</span>${IC('chev-der')}</button>`;
}
function guardadoHtml(){
  const g = GUARDADA, cuarto = g ? g.cuarto_nombre : '';
  const sig = siguienteCuarto(NIVELES, CUARTOS, g ? g.cuarto_id : CUARTO, recorrido());
  return `<div class="dl-tel">
    <div class="dl-visor dl-visor-tira"><video id="dlVideo" playsinline muted autoplay></video>
      <div class="dl-visor-aviso" id="dlVisorAviso" hidden><p id="dlVisorTxt"></p></div></div>
    <div class="dl-tel-sel">${selectoresHtml()}</div>
    ${g ? `<div class="dl-listo">${IC('check')}<b>Reading saved for ${esc(cuarto)}</b></div>
    <div class="dl-tarjeta"><small>Saved Reading</small>
      <div class="dl-tarjeta-c"><img src="${g.url}" alt="">
        <div><b>${esc([g.material, g.ubicacion].filter(Boolean).join(' • '))}</b><span class="dl-tarjeta-n">${esc(g.texto)}%</span><small>${IC('calendario')}Today${tendGuardada(g)}</small></div></div></div>` : ''}
    ${otroPuntoHtml(g)}
    <div class="dl-equipo">
      <div class="dl-equipo-cab"><span class="dl-equipo-ic">${IC('dl-herramientas')}</span><div><b>Equipment for ${esc(cuarto || nombreDe(CUARTOS, CUARTO))}</b><small>Record equipment before moving to another room.</small></div></div>
      <button type="button" class="btn btn-accent" data-dl-equipo="si">Add Equipment</button>
      <button type="button" class="btn btn-outline" data-dl-equipo="no">No Equipment</button>
      <small class="dl-equipo-nota">No Equipment records zero for ${esc(cuarto || 'this room')}${sig ? `, then advances to ${esc(sig.nombre)}` : ''}.</small>
      <p class="aviso" id="dlAviso"></p>
    </div>
  </div>`;
}
// ---------- TELÉFONO: el equipo del cuarto (su diseño del 14-oct, paso 4 de 5) ----------
// Una fila por equipo con − y +. Los números salen con lo último que se anotó en ese cuarto (el equipo casi siempre
// se queda de un día a otro: solo se cambia lo que se movió). "Add equipment type" agrega otro tipo y se recuerda
// en este teléfono. "Save Equipment & Next Room" guarda y pasa al siguiente cuarto con la cámara.
export const EQUIPOS_DL = [['Fans / Air Movers', 'eq-ventilador'], ['Dehumidifiers', 'eq-deshum'], ['HEPA Air Scrubber', 'eq-hepa'],
  ['Dry Mat', 'eq-tapete'], ['Air Duct', 'eq-ducto'], ['Heater', 'eq-calentador'], ['Poles', 'eq-postes']];
const CLAVE_TIPOS = 'scanova.dl.tiposEquipo';
const tiposPropios = () => { try{ const a = JSON.parse(localStorage.getItem(CLAVE_TIPOS) || '[]'); return Array.isArray(a) ? a.filter(x => typeof x === 'string' && x.trim()) : []; }catch{ return []; } };
// Lo último que se anotó en un cuarto: el día más reciente, y de ese día la anotación más nueva de cada equipo.
// "none" (No Equipment) deja todo en cero.
export function ultimoEquipo(filas){
  const l = (filas || []).slice().sort((a, b) => String(b.created_at || '').localeCompare(String(a.created_at || '')));
  if(!l.length) return null;
  const dia = l[0].dia, cuentas = {};
  for(const f of l){ if(f.dia !== dia || f.tipo === 'none' || f.tipo in cuentas) continue; cuentas[f.tipo] = Math.max(0, Math.min(200, Number(f.cantidad) || 0)); }
  return { dia, cuentas };
}
// Lo que se manda al guardar: solo lo que tiene cantidad; si todo está en cero, una fila "none" (igual que No Equipment).
export function filasEquipo(cuentas){
  const f = Object.entries(cuentas || {}).filter(([t, n]) => String(t).trim() && n > 0).map(([tipo, cantidad]) => ({ tipo: String(tipo).trim().slice(0, 60), cantidad: Math.min(200, Math.round(cantidad)) }));
  return f.length ? f : [{ tipo: 'none', cantidad: 0 }];
}
export const resumenEquipo = (cuentas) => Object.entries(cuentas || {}).filter(([, n]) => n > 0).map(([t, n]) => n + ' ' + t).join(', ');
let EQ = { cuarto: null, cuentas: {}, previo: null, cargando: false, agregando: false };
const tiposEq = () => { const base = EQUIPOS_DL.map(x => x[0]); const extra = [...tiposPropios(), ...Object.keys(EQ.cuentas)].filter((t, i, a) => !base.includes(t) && a.indexOf(t) === i); return [...EQUIPOS_DL, ...extra.map(t => [t, 'eq-otro'])]; };
// En qué cuarto va de todos los del proyecto (en el orden de la app): "Room 1 of 4".
export function posicionCuarto(niveles, cuartos, actual, lista){
  const orden = lista ? lista.slice() : []; if(!lista) (niveles || []).forEach(n => cuartosDeNivel(cuartos, n.id).forEach(c => orden.push(c)));
  const i = orden.findIndex(c => c.id === actual);
  return { n: i + 1, de: orden.length };
}
// "Room 1 of 4" (y del día 2 en adelante "Day 2 · Room 1 of 4"). Al tocarlo se ve el resumen del día.
function barritaCuartos(){
  const { n, de } = posicionCuarto(NIVELES, CUARTOS, CUARTO, recorrido());
  if(!de) return '';
  const d = diaNum(), cuarto = n > 0 ? 'Room ' + n + ' of ' + de : 'Extra room';
  return `<button type="button" class="dl-prog-btn" data-dl-ir="dia" aria-label="Day ${d} summary"><span class="dl-prog dl-prog-cuartos${de > 8 ? ' muchos' : de > 4 ? ' medio' : ''}" role="img" aria-label="${cuarto}">${Array.from({ length: de }, (_, i) => `<i${i < n ? ' class="on"' : ''}></i>`).join('')}</span><span class="dl-prog-n">${d > 1 ? 'Day ' + d + ' · ' : ''}${cuarto}</span></button>`;
}
// Las filas del equipo (teléfono y computadora): − cantidad +, y al final "Add equipment type".
function equipoFilasHtml(){
  return tiposEq().map(([t, ic], i) => { const n = EQ.cuentas[t] || 0;
    return `<div class="dl-eq-fila${n ? ' con' : ''}">${IC(ic, 'dl-eq-ic')}<span class="dl-eq-n">${esc(t)}</span>
      <button type="button" class="dl-eq-b dl-eq-menos" data-eq-menos="${i}" aria-label="One less ${esc(t)}"${n ? '' : ' disabled'}>${IC('menos')}</button>
      <b class="dl-eq-c" data-eq-c="${i}">${n}</b>
      <button type="button" class="dl-eq-b dl-eq-mas" data-eq-mas="${i}" aria-label="One more ${esc(t)}">${IC('mas')}</button></div>`; }).join('') +
    (EQ.agregando
      ? `<div class="dl-eq-fila dl-eq-nuevo">${IC('eq-otro', 'dl-eq-ic')}<input id="dlEqNuevo" type="text" maxlength="60" placeholder="Equipment name" autocomplete="off"><button type="button" class="btn btn-accent btn-chico" data-eq-nuevo="si">Add</button><button type="button" class="btn btn-outline btn-chico" data-eq-nuevo="no">Cancel</button></div>`
      : `<button type="button" class="dl-eq-fila dl-eq-agregar" data-eq-agregar>${IC('mas-circulo', 'dl-eq-ic')}<span class="dl-eq-n">Add equipment type</span>${IC('chev-der', 'dl-eq-chev')}</button>`);
}
function equipoHtml(){
  const cuarto = nombreDe(CUARTOS, CUARTO);
  // Su diseño (14-oct): arriba "Room 1 of 4" (una rayita por cuarto) y el título es solo "Equipment" con su raya azul;
  // el cuarto ya lo dice la caja Room.
  // Su pedido (14-oct): arriba, donde dice "Dry Logs", aquí dice "Equipment" (no dos títulos). Al guardar vuelve a "Dry Logs".
  return `<div class="dl-tel"><div class="dl-tel-cab"><h2 aria-label="Equipment in ${esc(cuarto || 'this room')}">Equipment</h2>${barritaCuartos()}</div>
    <div class="card dl-eq">
      <div class="dl-tel-sel">${selectoresHtml()}</div>
      ${GUARDADA && GUARDADA.cuarto_id === CUARTO ? (() => { const pend = R.puntosPendientes(LECT, CUARTO, HOY());
        return `<div class="dl-eq-ok">${IC('check')}<span>Saved <b>${esc(GUARDADA.texto)}%</b> · ${esc(R.nombrePunto(GUARDADA))}${tendGuardada(GUARDADA)}</span>${pend.length ? '<button type="button" class="dl-eq-otro pend" data-dl-otro>Next point</button>' : ''}</div>${pend.length ? `<p class="dl-eq-nota">Still to measure here: ${esc(pend.map(p => p.nombre).join(', '))}</p>` : ''}`; })() : ''}
      ${EQ.previo && EQ.previo < HOY() ? `<p class="dl-eq-nota">On site since the last visit (${esc(R.fechaCorta(EQ.previo))}). Change only what moved.</p>` : ''}
      <div class="dl-eq-lista">${equipoFilasHtml()}</div>
      <p class="aviso" id="dlAviso"></p>
      <button type="button" class="btn btn-accent btn-block dl-eq-guardar" data-eq-guardar>Save Equipment &amp; Next Room</button>
    </div></div>`;
}
// Lo que hay en el cuarto: lo último contado (hoy, o la visita anterior: el equipo se queda de un día a otro).
function cargarEquipo(){
  const e = R.equipoEnDia(R.equipoPorDia(EQUI), CUARTO, HOY());
  EQ = { cuarto: CUARTO, cuentas: e ? e.cuentas : {}, previo: e ? e.desde : null, cargando: false, agregando: false };
  if(PANTALLA === 'equipo' || PANTALLA === 'paso3') pintarAqui();
}
function abrirEquipo(){
  if(GUARDADA){ NIVEL = GUARDADA.nivel_id || NIVEL; CUARTO = GUARDADA.cuarto_id || CUARTO; }
  PANTALLA = 'equipo'; cargarEquipo();
  const m = $('#main'); if(m && !esCompu()) m.scrollTop = 0;
}
// Después de anotar el equipo (o No Equipment): al siguiente cuarto, con la cámara lista.
function avanzar(nombre, hecho){
  const sig = siguienteCuarto(NIVELES, CUARTOS, CUARTO, recorrido());
  GUARDADA = null;
  if(sig){ NIVEL = sig.nivel_id; CUARTO = sig.id; AVISO_TEL = hecho + ' Next: ' + sig.nombre + '.'; PANTALLA = 'cam'; }
  else { AVISO_TEL = hecho; PANTALLA = 'dia'; }   // era el último cuarto: el resumen del día
  pintarAqui();
  const m = $('#main'); if(m && PANTALLA === 'dia') m.scrollTop = 0;
}
async function guardarEquipo(){
  if(OCUPADO_TEL || EQ.cargando || !CUARTO) return;
  const nombre = nombreDe(CUARTOS, CUARTO), cuentas = { ...EQ.cuentas };
  OCUPADO_TEL = true; const b = $('[data-eq-guardar]'); if(b){ b.disabled = true; b.textContent = 'Saving…'; }
  try{
    const base = { trabajo_id: T.id, dia: hoyLocal(), nivel_id: NIVEL || null, cuarto_id: CUARTO, cuarto_nombre: nombre || null };
    const filas = filasEquipo(cuentas).map(f => ({ ...base, ...f }));
    const r = await authFetch('/rest/v1/fotos_drylog_equipos', { method: 'POST', headers: { Prefer: 'return=representation' }, body: JSON.stringify(filas) });
    if(r.status === 404) throw new Error('This part is not installed on the server yet: sql/fotos-09-drylogs.sql still has to be run.');
    if(!r.ok){ let m = 'HTTP ' + r.status; try{ const d = await r.json(); m = d.message || m; }catch{} throw new Error(m); }
    const vuelta = await r.json().catch(() => []);
    if(!Array.isArray(vuelta) || vuelta.length !== filas.length) throw new Error('The server did not keep it. Try again.');   // confirmar que de verdad se guardó
    // Ya guardado: si se había contado antes hoy en este cuarto, lo de antes se quita (no se suma dos veces). Se
    // borra DESPUÉS de guardar lo nuevo: si se cae la señal a medias, no se pierde el conteo.
    const desde = vuelta.map(f => f.created_at).filter(Boolean).sort()[0];
    if(desde) await authFetch('/rest/v1/fotos_drylog_equipos?trabajo_id=eq.' + encodeURIComponent(T.id) + '&cuarto_id=eq.' + encodeURIComponent(CUARTO) + '&dia=eq.' + base.dia + '&created_at=lt.' + encodeURIComponent(desde), { method: 'DELETE' }).catch(() => null);
    EQUI = EQUI.filter(f => !(f.cuarto_id === CUARTO && f.dia === base.dia)).concat(vuelta);
    const txt = resumenEquipo(cuentas);
    avanzar(nombre, txt ? 'Equipment saved for ' + nombre + ': ' + txt + '.' : 'No equipment in ' + nombre + '.');
  }catch(e){ avisarTel('Not saved: ' + (e.message || e)); }
  finally{ OCUPADO_TEL = false; const b2 = $('[data-eq-guardar]'); if(b2){ b2.disabled = false; b2.innerHTML = 'Save Equipment &amp; Next Room'; } }
}
function cambiarEq(i, d){
  const t = (tiposEq()[i] || [])[0]; if(!t) return;
  const n = Math.max(0, Math.min(200, (EQ.cuentas[t] || 0) + d)); EQ.cuentas[t] = n;
  const c = $('#panel-secado [data-eq-c="' + i + '"]'); if(!c){ pintarAqui(); return; }
  c.textContent = n; const fila = c.closest('.dl-eq-fila'); fila.classList.toggle('con', n > 0);
  const menos = fila.querySelector('[data-eq-menos]'); if(menos) menos.disabled = !n;
}
function agregarTipo(){
  const inp = $('#dlEqNuevo'), t = (inp ? inp.value : '').trim().replace(/\s+/g, ' ').slice(0, 60);
  if(!t){ if(inp) inp.focus(); return; }
  const ya = tiposEq().find(([x]) => x.toLowerCase() === t.toLowerCase());
  if(!ya){ const l = tiposPropios(); l.push(t); try{ localStorage.setItem(CLAVE_TIPOS, JSON.stringify(l.slice(-20))); }catch{} }
  const nombre = ya ? ya[0] : t; EQ.cuentas[nombre] = Math.max(1, EQ.cuentas[nombre] || 0);
  EQ.agregando = false; pintarAqui();
}
// El Back de la barra de abajo (su pedido del 14-oct): dentro del Dry Log del teléfono regresa un paso.
function atrasTel(){
  const c = caja(); if(!c || c.closest('[hidden]') || esCompu()) return false;
  if(PANTALLA === 'lectura'){ PANTALLA = 'cam'; AVISO_TEL = ''; pintarAqui(); return true; }
  if(PANTALLA === 'guardado'){ PANTALLA = 'cam'; pintarAqui(); return true; }
  if(PANTALLA === 'equipo'){ PANTALLA = 'cam'; AVISO_TEL = ''; pintarAqui(); return true; }
  if(PANTALLA === 'dia'){ PANTALLA = 'cam'; AVISO_TEL = ''; pintarAqui(); return true; }
  return false;
}
// ---------- TELÉFONO: el resumen del día (al terminar el último cuarto, o tocando "Room X of N") ----------
// Cada cuarto del recorrido con lo que se leyó hoy (y cuánto bajó), el equipo que tiene y lo que falta. Una lectura
// equivocada se borra aquí (la foto se queda en Photos).
function diaHtml(){
  const hoy = HOY(), d = diaNum(), lista = recorrido(), porDia = R.equipoPorDia(EQUI);
  const hechos = lista.filter(c => R.lecturasDelDia(LECT, c.id, hoy).length).length;
  const completos = lista.filter(c => R.lecturasDelDia(LECT, c.id, hoy).length && !R.puntosPendientes(LECT, c.id, hoy).length).length;
  const filas = lista.map(c => {
    const ls = R.lecturasDelDia(LECT, c.id, hoy), e = R.equipoEnDia(porDia, c.id, hoy), hoyEq = ((porDia[c.id] || {})[hoy]);
    const nivel = nombreDe(NIVELES, c.nivel_id);
    const lect = ls.length ? ls.map(f => { const ant = R.lecturaAnterior(LECT, c.id, f.material, f.ubicacion, hoy), t = ant && R.tendencia(ant.valor, Number(f.valor));
        return `<div class="dl-dia-l"><span class="dl-dia-p">${esc(R.nombrePunto(f))}</span><b>${esc(fmtValor(f.valor))}%</b>${t ? `<em class="dl-tend ${t.tipo}">${esc(t.texto)}</em>` : ''}<button type="button" class="dl-dia-x" data-dl-borrar="${esc(f.id)}" aria-label="Delete this reading">✕</button></div>`; }).join('')
      : `<p class="dl-dia-falta">No reading today</p>`;
    const pend = ls.length ? R.puntosPendientes(LECT, c.id, hoy) : [];
    const faltan = pend.length ? `<p class="dl-dia-falta">Not measured: ${esc(pend.map(p => p.nombre).join(', '))}</p>` : '';
    const eqTxt = e ? (R.textoEquipo(e.cuentas) || 'No equipment') : 'Equipment not counted yet';
    return `<div class="dl-dia-c${ls.length && !pend.length ? '' : ' falta'}">
      <button type="button" class="dl-dia-cab" data-dl-ir-cuarto="${esc(c.id)}">${IC(iconoCuarto(c), 'dl-dia-ic')}<span><b>${esc(c.nombre)}</b><small>${esc(nivel)}</small></span>${IC('chev-der', 'dl-dia-chev')}</button>
      ${lect}${faltan}<p class="dl-dia-eq">${IC('dl-herramientas')}<span>${esc(eqTxt)}${e && !hoyEq ? ` <small>(from ${esc(R.fechaCorta(e.desde))})</small>` : ''}</span></p></div>`;
  }).join('');
  const listo = lista.length && completos === lista.length;
  return `<div class="dl-tel"><div class="dl-tel-cab"><h2>Day ${d}${listo ? ' complete' : ''}</h2><span class="dl-prog-n">${esc(R.fechaLarga(hoy))}</span></div>
    ${AVISO_TEL ? `<p class="dl-tel-aviso">${IC('check')}${esc(AVISO_TEL)}</p>` : ''}
    <div class="card dl-dia"><p class="dl-dia-res">${hechos} of ${lista.length} room${lista.length === 1 ? '' : 's'} read today</p>${filas || '<p class="vacio">No rooms yet.</p>'}</div>
    <p class="aviso" id="dlAviso"></p>
    <div class="dl-botones"><button type="button" class="btn btn-outline" data-dl-ir="cam">${esCompu() ? 'Back to rooms' : 'Back to camera'}</button><button type="button" class="btn btn-accent" data-dl-reporte>${IC('doc')}Dry Log Report</button></div>
  </div>`;
}
async function borrarLectura(id){
  const f = LECT.find(x => x.id === id); if(!f || OCUPADO_TEL) return;
  if(!confirm('Delete the ' + fmtValor(f.valor) + '% reading of ' + R.nombrePunto(f) + ' (' + (f.cuarto_nombre || 'room') + ')? The photo stays in Photos.')) return;
  OCUPADO_TEL = true;
  try{
    const r = await authFetch('/rest/v1/fotos_drylog_lecturas?id=eq.' + encodeURIComponent(id), { method: 'DELETE', headers: { Prefer: 'return=representation' } });
    const out = r.ok ? await r.json().catch(() => []) : [];
    if(!r.ok || !out.length) throw new Error(r.ok ? 'Only the person who took it or a manager can delete it.' : 'HTTP ' + r.status);   // confirmar que de verdad se borró
    LECT = LECT.filter(x => x.id !== id); AVISO_TEL = ''; pintarAqui();
  }catch(e){ avisarTel('Not deleted: ' + (e.message || e)); }
  finally{ OCUPADO_TEL = false; }
}
// La cámara llena lo que sobra de la pantalla hasta la barra de abajo (como el plano; nada de position:fixed).
function medirTel(){
  const v = $('#panel-secado .dl-visor'), m = $('#main'); if(!v || !m || esCompu()) return;
  document.body.classList.add('dl-fijo');
  // Su pedido (14-oct): la información del cliente siempre se ve arriba; la página ya no sube sola, la foto se acomoda
  // en lo que queda.
  const sube = 0;
  const arriba = v.getBoundingClientRect().top - (m.getBoundingClientRect().top - m.scrollTop) - sube;
  const panel = $('#panel-secado .dl-tel'), ultimo = panel && panel.lastElementChild;
  const resto = ultimo && ultimo !== v ? ultimo.getBoundingClientRect().bottom - v.getBoundingClientRect().bottom : 0;
  const pie = parseFloat(getComputedStyle(m).paddingBottom) || 0;
  const cabe = Math.floor(m.clientHeight - arriba - resto - pie - 2);
  const minimo = PANTALLA === 'lectura' ? 140 : 220;   // en la lectura (su diseño) la foto cede espacio a la caja del número y los botones
  if(cabe >= minimo){ v.style.height = cabe + 'px'; const sobra = m.scrollHeight - m.clientHeight - sube; if(sobra > 0) v.style.height = Math.max(minimo, cabe - sobra) + 'px'; m.scrollTop = sube; }
  else { document.body.classList.remove('dl-fijo'); v.style.height = (PANTALLA === 'lectura' ? minimo : 360) + 'px'; m.scrollTop = 0; }
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
  PUNTO_ABIERTO = false;
  // Día 2 en adelante: el punto que toca (el de la visita anterior) ya viene escrito; se puede cambiar.
  const pend = R.puntosPendientes(LECT, CUARTO, HOY())[0];
  if(pend){ MATERIAL = pend.material || MATERIAL; UBIC = pend.ubicacion || ''; }
  else UBIC = '';   // un punto nuevo: el "dónde" se escribe (no se arrastra el del cuarto o el punto anterior)
  if(FOTO && FOTO.url) URL.revokeObjectURL(FOTO.url);
  FOTO = { blob, url: URL.createObjectURL(blob), nivel: NIVEL, cuarto: CUARTO, lectura: lectura || null, prellenado: !!pend };
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
async function guardarLectura(siguiente){
  if(OCUPADO_TEL || !FOTO) return;
  const valor = valorDe($('#dlValor').value);
  if(valor == null){ avisarTel('Type the reading as a number (like 18 or 18.5).'); $('#dlValor').focus(); return; }
  if($('#dlMaterial')) MATERIAL = $('#dlMaterial').value; if($('#dlUbic')) UBIC = ($('#dlUbic').value || '').trim();
  // Material y dónde solo si se vieron (si no, la lectura queda como "Reading": no se inventa un material).
  const { campos, linea } = campoPunto(), conPunto = campos || linea;
  const mat = conPunto ? MATERIAL : null, ubi = conPunto ? (UBIC || null) : null;
  // Dos lecturas de hoy en el mismo punto: la segunda taparía la primera en el reporte. Se pide decir dónde.
  if(R.lecturasDelDia(LECT, FOTO.cuarto, HOY()).some(f => R.clavePunto(f) === R.clavePunto({ material: mat, ubicacion: ubi }))){
    if(!campos){ PUNTO_ABIERTO = true; pintarAcciones(); }
    avisarTel('This room already has a reading here today. Write where this one is (like North wall).'); const u = $('#dlUbic'); if(u) u.focus(); return;
  }
  OCUPADO_TEL = true; const bot = siguiente ? '[data-dl-siguiente]' : '[data-dl-guardar]', b = $(bot), antes = b ? b.innerHTML : ''; if(b){ b.disabled = true; b.textContent = 'Saving…'; }
  try{
    // La foto va a Photos, a su piso y cuarto: es la prueba de la lectura.
    const archivo = new File([FOTO.blob], 'dry-log-' + hoyLocal() + '-' + Date.now() + '.jpg', { type: 'image/jpeg', lastModified: Date.now() });
    const { foto } = await fotos.subirCopia(archivo, { nivel_id: FOTO.nivel, cuarto_id: FOTO.cuarto });
    const cuarto_nombre = nombreDe(CUARTOS, FOTO.cuarto) || null;
    const fila = await enviarTel('fotos_drylog_lecturas', { trabajo_id: T.id, dia: hoyLocal(), nivel_id: FOTO.nivel || null, cuarto_id: FOTO.cuarto || null, cuarto_nombre,
      material: mat, ubicacion: ubi, valor, unidad: '%', foto_id: foto ? foto.id : null,
      leido_texto: FOTO.lectura ? FOTO.lectura.texto : null, leido_por: FOTO.lectura ? 'scanova-lector' : null, corregido: !!(FOTO.lectura && FOTO.lectura.valor !== valor) });
    if(GUARDADA && GUARDADA.url && GUARDADA.url !== FOTO.url) URL.revokeObjectURL(GUARDADA.url);
    LECT.push(fila);
    GUARDADA = { ...fila, texto: String(valor), url: FOTO.url };
    FOTO = null;
    if(siguiente){ AVISO_TEL = 'Saved ' + fmtValor(valor) + '% · ' + R.nombrePunto(fila) + '. Take the next reading in ' + (cuarto_nombre || 'this room') + '.'; PANTALLA = 'cam'; pintarAqui(); }
    else abrirEquipo();   // su pedido (14-oct): "Continue" va directo al equipo, sin pantalla de en medio
  }catch(e){ avisarTel('Not saved: ' + (e.message || e)); }
  finally{ OCUPADO_TEL = false; const b2 = $(bot); if(b2){ b2.disabled = false; b2.innerHTML = antes; } }
}
// "No Equipment": se anota cero para el cuarto y se pasa al siguiente (su diseño).
async function sinEquipo(){
  if(OCUPADO_TEL) return;
  const cuarto = GUARDADA ? GUARDADA.cuarto_id : CUARTO, nivel = GUARDADA ? GUARDADA.nivel_id : NIVEL, nombre = nombreDe(CUARTOS, cuarto);
  OCUPADO_TEL = true;
  try{
    const f = await enviarTel('fotos_drylog_equipos', { trabajo_id: T.id, dia: hoyLocal(), nivel_id: nivel || null, cuarto_id: cuarto || null, cuarto_nombre: nombre || null, tipo: 'none', cantidad: 0 });
    EQUI.push(f);
    CUARTO = cuarto; NIVEL = nivel || NIVEL; avanzar(nombre, 'No equipment in ' + nombre + '.');
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
export function salir(){ apagarCam(); document.body.classList.remove('dl-fijo'); if(['cam', 'lectura', 'guardado', 'equipo', 'dia'].includes(PANTALLA)) PANTALLA = 'vacio'; }

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
    AUTO = false;
    if(sel.dataset.dlSel === 'nivel'){ NIVEL = sel.value; CUARTO = cuartoInicial(CUARTOS, NIVEL, null); } else CUARTO = sel.value;
    const av = $('#panel-secado .dl-tel-aviso'); if(av){ av.remove(); AVISO_TEL = ''; }
    if(PANTALLA === 'equipo'){ pintarAqui(); cargarEquipo(); return; }
    if(PANTALLA === 'lectura' && FOTO){ FOTO.nivel = NIVEL; FOTO.cuarto = CUARTO; const t = $('#panel-secado .dl-lec-t'); if(t) t.textContent = 'Scan ' + (nombreDe(CUARTOS, CUARTO) || 'this room'); repintarComparar(); }
    pintarSelectores();
    if(PANTALLA === 'cam') medirTel();   // sin el aviso, la cámara vuelve a llenar lo que sobra
  });
  document.addEventListener('keydown', (e) => { if(e.key === 'Enter' && e.target && e.target.id === 'dlEqNuevo'){ e.preventDefault(); agregarTipo(); } });
  registrarAtras(atrasTel);
  document.addEventListener('input', (e) => { if(e.target && e.target.id === 'dlValor'){ if(e.target.closest('.dl-num')) anchoNumero(e.target); repintarComparar(); } if(e.target && e.target.id === 'dlUbic') repintarComparar(); });
  document.addEventListener('change', (e) => { if(e.target && e.target.id === 'dlMaterial') repintarComparar(); });
  document.addEventListener('visibilitychange', () => { if(document.hidden) apagarCam(); else if((PANTALLA === 'cam' || PANTALLA === 'guardado') && $('#dlVideo') && $('#dlVideo').offsetParent) encenderCam(); });
  // Al girar el teléfono (en los grandes, de lado ya es "computadora") se vuelve a escoger la pantalla que toca.
  let ancho = esCompu();
  window.addEventListener('resize', () => { if(!caja()) return; const ahora = esCompu(), cambio = ahora !== ancho; ancho = ahora;
    if(cambio && T){ pintarAqui(); return; }
    if(caja().querySelector('.dl-paso')) ajustarAlto(); if(caja().querySelector('.dl-tel')) pintarAqui(); });
  document.addEventListener('click', (e) => {
    const c = caja(); if(!c || !c.contains(e.target)) return;
    const q = (s) => e.target.closest(s);
    let el;
    if((el = q('[data-dl-cam]'))){ const a = el.dataset.dlCam;
      if(a === 'telefono') camaraDelTelefono(); else if(a === 'otra') encenderCam(); else if(a === 'otra-foto'){ PANTALLA = 'cam'; AVISO_TEL = ''; pintarAqui(); }
      return; }
    if(q('[data-dl-guardar]')){ guardarLectura(false); return; }
    if(q('[data-dl-siguiente]')){ guardarLectura(true); return; }
    if(q('[data-dl-otra]')){ PUNTO_ABIERTO = true; pintarAcciones(); const u = $('#dlUbic'); if(u) u.focus(); return; }
    if(q('[data-dl-web-guardar]')){ guardarWeb(); return; }
    if((el = q('[data-dl-equipo]'))){ if(el.dataset.dlEquipo === 'no') sinEquipo(); else abrirEquipo(); return; }
    if((el = q('[data-eq-mas]'))){ cambiarEq(+el.dataset.eqMas, 1); return; }
    if((el = q('[data-eq-menos]'))){ cambiarEq(+el.dataset.eqMenos, -1); return; }
    if(q('[data-eq-agregar]')){ EQ.agregando = true; pintarAqui(); const i = $('#dlEqNuevo'); if(i) i.focus(); return; }
    if((el = q('[data-eq-nuevo]'))){ if(el.dataset.eqNuevo === 'si') agregarTipo(); else { EQ.agregando = false; pintarAqui(); } return; }
    if(q('[data-eq-guardar]')){ guardarEquipo(); return; }
    if((el = q('[data-dl-ir]'))){ PANTALLA = el.dataset.dlIr; if(PANTALLA === 'cam') AVISO_TEL = ''; pintarAqui(); const m = $('#main'); if(m && PANTALLA === 'dia') m.scrollTop = 0; return; }
    if((el = q('[data-dl-ir-cuarto]'))){ const k = CUARTOS.find(x => x.id === el.dataset.dlIrCuarto); if(k){ NIVEL = k.nivel_id; CUARTO = k.id; AUTO = false; } AVISO_TEL = ''; GUARDADA = null; PANTALLA = 'cam'; pintarAqui(); return; }
    if(q('[data-dl-saltar]')){ const n = nombreDe(CUARTOS, CUARTO); AUTO = false; avanzar(n, 'Skipped ' + n + '.'); return; }
    if(q('[data-dl-otro]')){ GUARDADA = null; AVISO_TEL = ''; PANTALLA = 'cam'; pintarAqui(); return; }
    if((el = q('[data-dl-borrar]'))){ borrarLectura(el.dataset.dlBorrar); return; }
    if(q('[data-dl-reporte]')){ const b = document.querySelector('#pTrabajo [data-ptab="documentos"]'); if(b) b.click(); return; }
    if((el = q('[data-dl-nivel]'))){ if(NIVEL !== el.dataset.dlNivel){ NIVEL = el.dataset.dlNivel; CUARTO = null; } pintarAqui(); return; }
    if((el = q('[data-dl-cuarto]'))){ CUARTO = el.dataset.dlCuarto; pintarAqui(); return; }
    if((el = q('[data-dl]'))){
      const a = el.dataset.dl;
      if(a === 'paso2' && !CUARTO) return;
      if(a === 'vacio'){ NIVEL = null; CUARTO = null; VOLVIO = true; }   // tocó Back: se queda en la portada hasta que toque Start
      if(a === 'paso1') VOLVIO = false;
      if(a === 'paso2'){ const p = R.puntosPendientes(LECT, CUARTO, HOY())[0]; if(p){ MATERIAL = p.material || MATERIAL; UBIC = p.ubicacion || ''; } }
      if(a === 'paso3'){ PANTALLA = 'paso3'; cargarEquipo(); }
      PANTALLA = a; pintarAqui();
      if(c.scrollIntoView) c.scrollIntoView({ block: 'nearest' });
    }
  });
}
