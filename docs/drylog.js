// Scanova360 · carpeta Dry Logs, con SU diseño (14-oct):
//  · Sin registros: "No dry logs yet" + botón Start Dry Log.
//  · New Dry Log, Step 1 of 3: "Where are you taking the reading?" — primero el nivel (con cuántos cuartos
//    tiene), después el cuarto de ese nivel. Continue se prende cuando ya escogió los dos.
// Los pasos 2 y 3 (material y punto de medida) esperan su diseño: no se inventan.
import { $, $$ } from './app.js?v=2026-10-14-10';

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
  if(PANTALLA === 'vacio' && abreEnPaso1(esCompu(), CUARTOS, VOLVIO)) PANTALLA = 'paso1';
  c.innerHTML = PANTALLA === 'paso1' ? paso1Html() : PANTALLA === 'paso2' ? paso2Html() : vacioHtml();
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

// ---------- toques ----------
export function conectar(){
  window.addEventListener('resize', () => { if(caja() && caja().querySelector('.dl-paso')) ajustarAlto(); });
  document.addEventListener('click', (e) => {
    const c = caja(); if(!c || !c.contains(e.target)) return;
    const q = (s) => e.target.closest(s);
    let el;
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
