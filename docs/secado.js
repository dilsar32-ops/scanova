// Scanova360 · pestaña Dry Log (su pedido del 14-oct: "esta aplicación y website es para servir a compañías de
// water damage; después de Photos que vaya Dry Log"). Un registro de secado de verdad, en tres partes:
//  · Moisture: puntos de humedad por cuarto (superficie, material, dónde y la meta de seco), una lectura por día.
//  · Atmosphere: temperatura y humedad relativa por lugar y por día; los GPP los calcula la app.
//  · Equipment: qué equipo, cuántos, en qué cuarto, cuándo se puso y cuándo se quitó (días de equipo).
// "Today's readings" junta todo lo del día en una sola pantalla: la cuadrilla camina con el medidor y escribe.
// Lo que se guarda vive en sql/fotos-08-secado.sql.
import { authFetch } from './app.js?v=2026-10-14-15';
import { coordsDe, miPosicion } from './cerca.js?v=2026-10-14-15';

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
const IC = (n) => '<svg class="ic"><use href="#i-' + n + '"/></svg>';

// ---------- lo puro (para las pruebas) ----------
export const SUPERFICIES = ['Floor', 'Wall', 'Ceiling'];
export const MATERIALES = {
  Floor: ['Carpet', 'Carpet pad', 'Tile', 'Wood floor', 'Laminate', 'Vinyl', 'Plywood / Subfloor', 'Concrete'],
  Wall: ['Drywall', 'Baseboard', 'Studs', 'Plaster', 'Paneling', 'Insulation', 'Cabinet'],
  Ceiling: ['Drywall', 'Plaster', 'Joists', 'Insulation'],
};
// Los mismos equipos de la pestaña Equipment de Field Reports (Fans = Air mover).
export const EQUIPOS = ['Air mover', 'Dehumidifier', 'Air scrubber (HEPA)', 'Drying mat', 'Heater', 'Air duct', 'Ozone machine', 'Generator'];
export const AFUERA = 'Outside', SIN_DANO = 'Unaffected area', SALIDA_DEHU = 'Dehumidifier exhaust';
const pad = (n) => String(n).padStart(2, '0');
// La fecha del teléfono (nunca la de Londres: toISOString da el día de mañana después de las 8 pm).
export const hoyLocal = (d = new Date()) => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
const aFecha = (s) => new Date(String(s).slice(0, 10) + 'T12:00:00');
export const diasEntre = (a, b) => Math.round((aFecha(b) - aFecha(a)) / 86400000);
export const fechaCorta = (s) => { const d = aFecha(s); return isNaN(d) ? '' : d.toLocaleDateString('en-US', { month:'short', day:'numeric' }); };
const vacio = (v) => v == null || String(v).trim() === '';
const num = (v) => vacio(v) ? null : Number(v);
// GPP (granos de agua por libra de aire seco) con la fórmula de Buck, a presión del nivel del mar.
// Contra la tabla de ASHRAE: 70 °F/50 % = 54.5, 80 °F/60 % = 92.1, 90 °F/30 % = 63.0.
export function gpp(tempF, rh){
  const t = num(tempF), h = num(rh);
  if(t == null || h == null || !isFinite(t) || !isFinite(h) || h < 0 || h > 100 || t < -40 || t > 160) return null;
  const c = (t - 32) * 5 / 9;
  const es = 6.1121 * Math.exp((18.678 - c / 234.5) * (c / (257.14 + c)));   // hPa, sobre agua
  const e = es * h / 100;
  const w = 0.62198 * e / (1013.25 - e);                     // kg de agua por kg de aire seco
  return Math.round(w * 7000 * 10) / 10;
}
export const fmtGpp = (g) => (g == null ? '—' : Number(g).toFixed(1));
// El día 1 es el primer día que hay algo anotado: una lectura, un ambiente o un equipo puesto.
export function inicioDe(D){
  const f = [].concat((D.lecturas || []).map(x => x.dia), (D.ambiente || []).map(x => x.dia), (D.equipos || []).map(x => x.puesto)).filter(Boolean).map(s => String(s).slice(0, 10)).sort();
  return f[0] || null;
}
export const numeroDeDia = (inicio, dia) => (inicio ? diasEntre(inicio, dia) + 1 : 1);
export function estadoPunto(p, lecturas){
  const l = (lecturas || []).filter(x => x.punto_id === p.id).sort((a, b) => (a.dia < b.dia ? -1 : a.dia > b.dia ? 1 : 0));
  const ult = l.length ? Number(l[l.length - 1].valor) : null;
  const meta = num(p.meta);
  return { lecturas: l, ultima: ult, meta, seco: ult != null && meta != null && ult <= meta };
}
// Días de equipo: un día por cada día que estuvo puesto (del día que se puso al día que se quitó, o a hoy).
export const diasEquipo = (e, hoy) => Math.max(1, diasEntre(e.puesto, e.quitado || hoy));
export function pluralEquipo(tipo, n){
  if(Number(n) === 1) return tipo;
  const m = String(tipo).match(/^(.*?)(\s*\(.*\))?$/);
  return m[1] + 's' + (m[2] || '');
}
export function resumen(D, hoy){
  const inicio = inicioDe(D);
  const est = (D.puntos || []).map(p => estadoPunto(p, D.lecturas));
  const enSitio = {}, diasEq = {};
  (D.equipos || []).forEach(e => {
    const n = Number(e.cantidad) || 0;
    if(!e.quitado) enSitio[e.tipo] = (enSitio[e.tipo] || 0) + n;
    diasEq[e.tipo] = (diasEq[e.tipo] || 0) + n * diasEquipo(e, hoy);
  });
  return { inicio, dia: inicio ? numeroDeDia(inicio, hoy) : 0, total: est.length, secos: est.filter(x => x.seco).length, sinMeta: est.filter(x => x.meta == null).length, enSitio, diasEq };
}
// Outside (su pedido del 14-oct): la app lo llena sola con el clima de donde está el trabajo. El teléfono no
// tiene termómetro: se toma la ubicación (el punto del proyecto, o el GPS del teléfono) y se le pregunta a
// Open-Meteo (gratis, sin llave). La ubicación va redondeada a ~1 km. Siempre se puede cambiar a mano.
export const urlClima = (lat, lng) => 'https://api.open-meteo.com/v1/forecast?latitude=' + Number(lat).toFixed(2) + '&longitude=' + Number(lng).toFixed(2) + '&current=temperature_2m,relative_humidity_2m&temperature_unit=fahrenheit&timezone=auto';
export function leerClima(j){
  const c = j && j.current; if(!c) return null;
  const t = Number(c.temperature_2m), h = Number(c.relative_humidity_2m);
  if(!isFinite(t) || !isFinite(h) || gpp(t, h) == null) return null;
  const m = String(c.time || '').match(/T(\d{2}):(\d{2})/);
  const hora = m ? ((Number(m[1]) % 12) || 12) + ':' + m[2] + (Number(m[1]) < 12 ? ' AM' : ' PM') : '';
  return { t: Math.round(t), h: Math.round(h), hora };
}
export const listaEquipos = (m) => Object.keys(m).filter(k => m[k] > 0).map(k => m[k] + ' ' + pluralEquipo(k, m[k])).join(' · ');

// ---------- estado ----------
let T = null, NIVELES = [], CUARTOS = [], D = { puntos: [], lecturas: [], ambiente: [], equipos: [] };
let CARGADO = '', CARGANDO = false, FALTA_SQL = false, VISTA = 'humedad', PANTALLA = 'resumen', EDITA = null, DIA = hoyLocal(), AVISO = '', AVISO_OK = false, OCUPADO = false;
const caja = () => $('#panel-secado');
const nombreNivel = (id) => { const n = NIVELES.find(x => x.id === id); return n ? n.nombre : ''; };
function nombreLugar(cuartoId, lugar){ const c = CUARTOS.find(x => x.id === cuartoId); return c ? c.nombre : (lugar || 'No room'); }
// Pisos en el orden de la app (del más alto al más bajo); dentro de cada piso, el orden de sus cuartos.
const ordenCuarto = (c) => { const n = NIVELES.findIndex(x => x.id === c.nivel_id); return (n < 0 ? 99 : n) * 1000 + CUARTOS.indexOf(c); };
function grupoDe(x){ const c = CUARTOS.find(y => y.id === x.cuarto_id); return { clave: c ? c.id : 'L:' + (x.lugar || ''), titulo: c ? c.nombre : (x.lugar || 'No room'), nivel: c ? nombreNivel(c.nivel_id) : '', orden: c ? ordenCuarto(c) : 999999 }; }

async function leer(tabla, orden){
  const r = await authFetch('/rest/v1/' + tabla + '?trabajo_id=eq.' + encodeURIComponent(T.id) + '&select=*&order=' + orden);
  if(r.status === 404){ FALTA_SQL = true; return []; }
  return r.ok ? await r.json() : [];
}
async function cargar(){
  if(!T) return; const id = T.id; CARGANDO = true; FALTA_SQL = false;
  const [p, l, a, e] = await Promise.all([leer('fotos_secado_puntos', 'created_at.asc'), leer('fotos_secado_lecturas', 'dia.asc'), leer('fotos_secado_ambiente', 'dia.asc'), leer('fotos_secado_equipos', 'puesto.asc,created_at.asc')]);
  if(!T || T.id !== id) return;
  D = { puntos: p, lecturas: l, ambiente: a, equipos: e }; CARGADO = id; CARGANDO = false;
  pintarAqui();
}
// La ficha la llama cada vez que se pinta la pestaña (y cuando llegan los cuartos).
export function pintar(t, niveles, cuartos){
  if(!t) return;
  if(!T || T.id !== t.id){ D = { puntos: [], lecturas: [], ambiente: [], equipos: [] }; CARGADO = ''; PANTALLA = 'resumen'; VISTA = 'humedad'; AVISO = ''; EDITA = null; }
  T = t; NIVELES = niveles || []; CUARTOS = cuartos || [];
  if(CARGADO !== t.id && !CARGANDO) cargar();
  // Una pantalla con un formulario a medio llenar no se vuelve a dibujar (perdería lo escrito).
  if(PANTALLA !== 'resumen' && caja() && caja().querySelector('.seco-forma')) return;
  pintarAqui();
}
function pintarAqui(){
  const c = caja(); if(!c || !T) return;
  if(FALTA_SQL){ c.innerHTML = `<div class="pronto pronto-tab"><span class="pronto-ic">${IC('gota')}</span><h2 class="titulo chico">Dry Log</h2><p>This part is not installed on the server yet: sql/fotos-08-secado.sql still has to be run.</p></div>`; return; }
  if(CARGADO !== T.id){ c.innerHTML = '<p class="vacio">Loading the dry log…</p>'; return; }
  c.innerHTML = PANTALLA === 'lecturas' ? lecturasHtml() : PANTALLA === 'punto' ? puntoHtml() : PANTALLA === 'equipo' ? equipoHtml() : resumenHtml();
  if(PANTALLA === 'lecturas') llenarAfuera(false);
}

// ---------- Outside desde el clima ----------
let CLIMA = { para: '', t: 0, dato: null };
async function climaDelTrabajo(){
  if(CLIMA.dato && CLIMA.para === T.id && Date.now() - CLIMA.t < 15 * 60e3) return CLIMA.dato;
  const pos = coordsDe(T) || await miPosicion();
  if(!pos) throw new Error('no location');
  const ctl = typeof AbortController === 'function' ? new AbortController() : null; const reloj = setTimeout(() => ctl && ctl.abort(), 9000);
  try{
    const r = await fetch(urlClima(pos.lat, pos.lng), ctl ? { signal: ctl.signal } : {});
    const d = r.ok ? leerClima(await r.json()) : null; if(!d) throw new Error('no weather');
    CLIMA = { para: T.id, t: Date.now(), dato: d }; return d;
  } finally { clearTimeout(reloj); }
}
async function llenarAfuera(forzar){
  const nota = $('#secClima'), fila = $('[data-amb-lugar="' + AFUERA + '"]'); if(!nota || !fila) return;
  const ti = $('[data-amb="t"]', fila), hi = $('[data-amb="h"]', fila);
  if(DIA !== hoyLocal()){ nota.textContent = ''; return; }   // el clima de ahorita solo sirve para hoy
  if(!forzar && (ti.value || hi.value)){ nota.innerHTML = '<button type="button" class="seco-clima-btn" data-sec-clima>Use the weather now</button>'; return; }
  nota.textContent = 'Getting the outside weather…';
  try{
    const d = await climaDelTrabajo();
    if(!document.body.contains(ti) || DIA !== hoyLocal()) return;
    if(!forzar && (ti.value || hi.value)){ nota.textContent = ''; return; }   // ya escribió algo mientras llegaba
    ti.value = d.t; hi.value = d.h; ti.dispatchEvent(new Event('input', { bubbles: true }));
    nota.innerHTML = 'Filled from the weather at the job' + (d.hora ? ' (' + esc(d.hora) + ')' : '') + '. Change it if your meter reads different. <button type="button" class="seco-clima-btn" data-sec-clima>Refresh</button>';
  }catch{
    if(document.body.contains(nota)) nota.innerHTML = 'Could not get the outside weather (no location or no signal). Type it from your meter. <button type="button" class="seco-clima-btn" data-sec-clima>Try again</button>';
  }
}

// ---------- la vista principal ----------
function resumenHtml(){
  const hoy = hoyLocal(), r = resumen(D, hoy);
  const aviso = AVISO ? `<p class="aviso${AVISO_OK ? ' ok' : ''} seco-aviso">${esc(AVISO)}</p>` : '';
  if(!D.puntos.length && !D.equipos.length && !D.ambiente.length) return aviso + `<div class="card seco-vacio"><span class="seco-vacio-ic">${IC('gota')}</span><h3>Start the dry log</h3>
    <p>Add the moisture points you will check every day (the material, where it is and its dry goal) and the equipment you set. Then use <b>Today's readings</b> once a day.</p>
    <div class="fila-botones"><button type="button" class="btn btn-accent" data-sec="punto">+ Moisture point</button><button type="button" class="btn btn-outline" data-sec="equipo">+ Equipment</button></div></div>`;
  const pct = r.total ? Math.round(r.secos / r.total * 100) : 0;
  const sitio = listaEquipos(r.enSitio);
  const cab = `<div class="card seco-res">
    <div class="seco-dia"><span class="seco-dia-n">Day ${r.dia}</span><span class="seco-dia-t">of drying · started ${esc(fechaCorta(r.inicio))}</span></div>
    ${r.total ? `<div class="seco-barra" role="img" aria-label="${r.secos} of ${r.total} dry"><i style="width:${pct}%"></i></div>` : ''}
    <div class="seco-chips">${r.total ? `<span class="seco-chip${r.secos === r.total ? ' listo' : ''}">${r.secos === r.total ? '✓ All ' + r.total + ' materials dry' : r.secos + ' of ' + r.total + ' materials dry'}</span>` : ''}<span class="seco-chip">${sitio ? 'On site: ' + esc(sitio) : 'No equipment on site'}</span></div>
    <button type="button" class="btn btn-accent seco-hoy" data-sec="lecturas">${IC('gota')}Today's readings</button></div>`;
  const tabs = `<div class="subtabs tres" role="tablist">${[['humedad', 'Moisture'], ['ambiente', 'Atmosphere'], ['equipo', 'Equipment']].map(([k, t]) => `<button type="button" class="subtab${VISTA === k ? ' on' : ''}" data-sec-vista="${k}">${t}</button>`).join('')}</div>`;
  return aviso + cab + tabs + (VISTA === 'ambiente' ? ambienteHtml() : VISTA === 'equipo' ? equiposHtml(r, hoy) : humedadHtml(r));
}
function agrupar(lista){
  const g = new Map();
  lista.forEach(x => { const k = grupoDe(x); if(!g.has(k.clave)) g.set(k.clave, { ...k, items: [] }); g.get(k.clave).items.push(x); });
  return [...g.values()].sort((a, b) => a.orden - b.orden || a.titulo.localeCompare(b.titulo));
}
function humedadHtml(r){
  const cab = `<div class="sec-cab"><h2 class="sec-t">Moisture readings</h2><button type="button" class="btn btn-outline btn-chico" data-sec="punto">+ Moisture point</button></div>`;
  if(!D.puntos.length) return cab + '<p class="vacio">No moisture points yet. Add one for each material you will check every day.</p>';
  return cab + agrupar(D.puntos).map(g => `<section class="seco-grupo"><h4>${esc(g.titulo)}${g.nivel ? ` <small>${esc(g.nivel)}</small>` : ''}</h4>${g.items.map(p => {
    const e = estadoPunto(p, D.lecturas);
    const est = e.ultima == null ? '<span class="seco-est">No reading</span>' : e.meta == null ? '<span class="seco-est">No goal</span>' : e.seco ? '<span class="seco-est seco">✓ Dry</span>' : '<span class="seco-est mojado">Wet</span>';
    const dias = e.lecturas.map(l => { const v = Number(l.valor); const bien = e.meta != null && v <= e.meta; return `<div class="seco-d"><small>Day ${numeroDeDia(r.inicio, l.dia)}</small><small>${esc(fechaCorta(l.dia))}</small><b class="${e.meta == null ? '' : bien ? 'bien' : 'alto'}">${esc(v)}</b></div>`; }).join('');
    return `<button type="button" class="seco-punto" data-sec-punto="${esc(p.id)}"><span class="seco-p-cab"><span><b>${esc(p.material)}</b> · ${esc(p.superficie)}<small>${[p.ubicacion, e.meta != null ? 'Dry goal ' + e.meta : 'No dry goal'].filter(Boolean).map(esc).join(' · ')}</small></span>${est}</span>${dias ? `<span class="seco-dias">${dias}</span>` : ''}</button>`;
  }).join('')}</section>`).join('');
}
function ambienteHtml(){
  const cab = `<div class="sec-cab"><h2 class="sec-t">Atmosphere</h2></div><p class="seco-nota">GPP (grains of water per pound of air) is calculated by the app from the temperature and the relative humidity, at sea-level pressure.</p>`;
  if(!D.ambiente.length) return cab + '<p class="vacio">No atmosphere readings yet. Add them with Today\'s readings.</p>';
  const inicio = inicioDe(D);
  const dias = [...new Set(D.ambiente.map(a => String(a.dia).slice(0, 10)))].sort().reverse();
  return cab + dias.map(d => `<div class="card seco-amb"><h4>Day ${numeroDeDia(inicio, d)} <small>${esc(fechaCorta(d))}</small></h4>
    <div class="seco-amb-fila cab"><span>Place</span><span>Temp</span><span>RH</span><span>GPP</span></div>
    ${ordenarLugares(D.ambiente.filter(a => String(a.dia).slice(0, 10) === d)).map(a => { const g = gpp(a.temp_f, a.rh); return `<div class="seco-amb-fila"><span>${esc(a.lugar)}</span><span>${esc(Number(a.temp_f))}°F</span><span>${esc(Number(a.rh))}%</span><b>${esc(fmtGpp(g))}</b></div>`; }).join('')}</div>`).join('');
}
// Afuera y el área sin daño arriba (son la referencia), los cuartos en medio, la salida del deshumidificador al final.
function ordenarLugares(l){ const p = (x) => (x.lugar === AFUERA ? 0 : x.lugar === SIN_DANO ? 1 : x.lugar === SALIDA_DEHU ? 3 : 2); return l.slice().sort((a, b) => p(a) - p(b) || String(a.lugar).localeCompare(String(b.lugar))); }
function equiposHtml(r, hoy){
  const cab = `<div class="sec-cab"><h2 class="sec-t">Equipment</h2><button type="button" class="btn btn-outline btn-chico" data-sec="equipo">+ Equipment</button></div>`;
  if(!D.equipos.length) return cab + '<p class="vacio">No equipment yet. Add every air mover, dehumidifier and scrubber you set, and remove it here the day you pick it up.</p>';
  const fila = (e) => { const n = Number(e.cantidad) || 0, d = diasEquipo(e, hoy);
    const cuando = e.quitado ? `${fechaCorta(e.puesto)} → ${fechaCorta(e.quitado)} · ${d} ${d === 1 ? 'day' : 'days'}` : `placed ${fechaCorta(e.puesto)} · on site ${d} ${d === 1 ? 'day' : 'days'}`;
    return `<div class="seco-eq${e.quitado ? ' quitado' : ''}"><button type="button" class="seco-eq-dato" data-sec-equipo="${esc(e.id)}"><span class="seco-eq-n">${n}</span><span><b>${esc(pluralEquipo(e.tipo, n))}</b><small>${esc(nombreLugar(e.cuarto_id, e.lugar))} · ${esc(cuando)}</small></span></button>${e.quitado ? '<span class="seco-est">Removed</span>' : `<button type="button" class="btn btn-outline btn-chico" data-sec-quitar="${esc(e.id)}">Remove</button>`}</div>`; };
  const puestos = D.equipos.filter(e => !e.quitado), quitados = D.equipos.filter(e => e.quitado);
  const total = Object.keys(r.diasEq).map(k => `<div class="seco-amb-fila dos"><span>${esc(pluralEquipo(k, 2))}</span><b>${r.diasEq[k]}</b></div>`).join('');
  return cab + (puestos.length ? puestos.map(fila).join('') : '<p class="vacio">All the equipment was removed.</p>') +
    (quitados.length ? `<h4 class="seco-h4">Removed</h4>${quitados.map(fila).join('')}` : '') +
    `<div class="card seco-amb"><h4>Equipment days</h4>${total}<p class="seco-nota">Each unit counts one day for every day on site: from the day it was placed to the day it was removed, or to today if it is still there.</p></div>`;
}

// ---------- Today's readings: todo lo del día en una pantalla ----------
function lugaresDelDia(){
  const usados = new Set();
  const cuartos = [];
  const add = (cid, lugar) => { const n = nombreLugar(cid, lugar); if(n && !usados.has(n)){ usados.add(n); cuartos.push(n); } };
  D.puntos.forEach(p => add(p.cuarto_id, p.lugar));
  D.equipos.filter(e => !e.quitado).forEach(e => add(e.cuarto_id, e.lugar));
  D.ambiente.filter(a => String(a.dia).slice(0, 10) === DIA).forEach(a => { if(![AFUERA, SIN_DANO, SALIDA_DEHU].includes(a.lugar)) add(null, a.lugar); });
  return [AFUERA, SIN_DANO, ...cuartos, SALIDA_DEHU];
}
function lecturasHtml(){
  const hoy = hoyLocal();
  const anterior = (p) => { const l = D.lecturas.filter(x => x.punto_id === p.id && String(x.dia).slice(0, 10) < DIA).sort((a, b) => (a.dia < b.dia ? 1 : -1))[0]; return l ? `last ${Number(l.valor)} (${fechaCorta(l.dia)})` : ''; };
  const deHoy = (p) => { const l = D.lecturas.find(x => x.punto_id === p.id && String(x.dia).slice(0, 10) === DIA); return l ? Number(l.valor) : ''; };
  const humedad = D.puntos.length ? agrupar(D.puntos).map(g => `<h4 class="seco-h4">${esc(g.titulo)}${g.nivel ? ` <small>${esc(g.nivel)}</small>` : ''}</h4>${g.items.map(p => `<label class="seco-in"><span><b>${esc(p.material)}</b> · ${esc(p.superficie)}<small>${[p.ubicacion, p.meta != null && p.meta !== '' ? 'goal ' + Number(p.meta) : '', anterior(p)].filter(Boolean).map(esc).join(' · ')}</small></span><input type="number" inputmode="decimal" min="0" max="1000" step="any" data-lec-punto="${esc(p.id)}" value="${esc(deHoy(p))}" aria-label="${esc(p.material)} reading"></label>`).join('')}`).join('')
    : `<p class="vacio">No moisture points yet.</p><button type="button" class="btn btn-outline btn-chico" data-sec="punto">+ Moisture point</button>`;
  const amb = lugaresDelDia().map(l => { const a = D.ambiente.find(x => x.lugar === l && String(x.dia).slice(0, 10) === DIA) || {}; const g = gpp(a.temp_f, a.rh);
    return `<div class="seco-in amb" data-amb-lugar="${esc(l)}"><span><b>${esc(l)}</b></span><label class="seco-mini"><small>Temp °F</small><input type="number" inputmode="decimal" step="any" data-amb="t" value="${esc(a.temp_f == null ? '' : Number(a.temp_f))}" aria-label="${esc(l)} temperature in °F"></label><label class="seco-mini"><small>RH %</small><input type="number" inputmode="decimal" step="any" data-amb="h" value="${esc(a.rh == null ? '' : Number(a.rh))}" aria-label="${esc(l)} relative humidity"></label><span class="seco-gpp">${esc(fmtGpp(g))} GPP</span>${l === AFUERA ? '<p class="seco-clima" id="secClima"></p>' : ''}</div>`; }).join('');
  return `<div class="seco-forma"><button type="button" class="volver" data-sec="resumen">${IC('atras')}Back to Dry Log</button>
    <h2 class="sec-t">Readings</h2>
    <div class="field"><label for="secDia">Date</label><input type="date" id="secDia" value="${esc(DIA)}" max="${esc(hoy)}"></div>
    <h3 class="seco-h3">Moisture</h3>${humedad}
    <h3 class="seco-h3">Atmosphere</h3><p class="seco-nota">Temperature in °F and relative humidity in %. The app calculates the GPP.</p>${amb}
    <p class="aviso" id="secAviso"></p>
    <div class="fila-botones"><button type="button" class="btn btn-outline" data-sec="resumen">Cancel</button><button type="button" class="btn btn-accent" data-sec-guardar="lecturas">Save readings</button></div></div>`;
}

// ---------- formularios: punto de humedad y equipo ----------
function opcionesCuarto(sel, lugar){
  const porNivel = new Map();
  CUARTOS.slice().sort((a, b) => ordenCuarto(a) - ordenCuarto(b)).forEach(c => { const n = nombreNivel(c.nivel_id) || 'Rooms'; if(!porNivel.has(n)) porNivel.set(n, []); porNivel.get(n).push(c); });
  const otro = !sel && !!lugar;
  return '<option value="">Choose a room</option>' + [...porNivel.entries()].map(([n, l]) => `<optgroup label="${esc(n)}">${l.map(c => `<option value="${esc(c.id)}"${c.id === sel ? ' selected' : ''}>${esc(c.nombre)}</option>`).join('')}</optgroup>`).join('') + `<option value="__otro"${otro ? ' selected' : ''}>Other (type it)</option>`;
}
function campoCuarto(sel, lugar){
  const otro = !sel && !!lugar;
  return `<div class="field"><label for="secCuarto">Room</label><select id="secCuarto">${opcionesCuarto(sel, lugar)}</select></div>
    <div class="field" id="secLugarCaja"${otro || !CUARTOS.length ? '' : ' hidden'}><label for="secLugar">Room name</label><input id="secLugar" maxlength="80" value="${esc(otro ? lugar : '')}" placeholder="e.g. Kitchen"></div>`;
}
const opcionesMaterial = (sup, actual) => { const l = MATERIALES[sup] || []; const otro = actual && !l.includes(actual); return l.map(m => `<option${m === actual ? ' selected' : ''}>${esc(m)}</option>`).join('') + `<option value="__otro"${otro ? ' selected' : ''}>Other (type it)</option>`; };
function puntoHtml(){
  const p = EDITA ? D.puntos.find(x => x.id === EDITA) : null;
  const sup = (p && p.superficie) || 'Wall', mat = p ? p.material : '';
  const otroMat = !!(p && !(MATERIALES[sup] || []).includes(mat));
  const n = p ? D.lecturas.filter(l => l.punto_id === p.id).length : 0;
  return `<div class="seco-forma"><button type="button" class="volver" data-sec="resumen">${IC('atras')}Back to Dry Log</button>
    <h2 class="sec-t">${p ? 'Edit moisture point' : 'New moisture point'}</h2>
    ${campoCuarto(p && p.cuarto_id, p && p.lugar)}
    <div class="field"><label>Surface</label><div class="subtabs tres" id="secSup">${SUPERFICIES.map(s => `<button type="button" class="subtab${s === sup ? ' on' : ''}" data-sec-sup="${s}">${s}</button>`).join('')}</div></div>
    <div class="field"><label for="secMaterial">Material</label><select id="secMaterial">${opcionesMaterial(sup, mat || (MATERIALES[sup] || [])[0])}</select></div>
    <div class="field" id="secMaterialOtroCaja"${otroMat ? '' : ' hidden'}><label for="secMaterialOtro">Material name</label><input id="secMaterialOtro" maxlength="60" value="${esc(otroMat ? mat : '')}"></div>
    <div class="field"><label for="secUbic">Where exactly <span class="hint">(optional)</span></label><input id="secUbic" maxlength="120" value="${esc(p && p.ubicacion || '')}" placeholder="e.g. North wall, 12 in. up"></div>
    <div class="field"><label for="secMeta">Dry goal <span class="hint">the reading of the same material in a dry, unaffected area</span></label><input id="secMeta" type="number" inputmode="decimal" min="0" max="1000" step="any" value="${esc(p && p.meta != null ? Number(p.meta) : '')}" placeholder="e.g. 12"></div>
    <p class="aviso" id="secAviso"></p>
    <div class="fila-botones"><button type="button" class="btn btn-outline" data-sec="resumen">Cancel</button><button type="button" class="btn btn-accent" data-sec-guardar="punto">${p ? 'Save' : 'Add point'}</button></div>
    ${p ? `<button type="button" class="btn btn-outline btn-rojo seco-borrar" data-sec-borrar="punto">${IC('archivo')}Delete this point${n ? ` and its ${n} ${n === 1 ? 'reading' : 'readings'}` : ''}</button>` : ''}</div>`;
}
function equipoHtml(){
  const e = EDITA ? D.equipos.find(x => x.id === EDITA) : null;
  const tipo = e ? e.tipo : EQUIPOS[0];
  return `<div class="seco-forma"><button type="button" class="volver" data-sec="resumen">${IC('atras')}Back to Dry Log</button>
    <h2 class="sec-t">${e ? 'Edit equipment' : 'New equipment'}</h2>
    <div class="field"><label for="secTipo">Equipment</label><select id="secTipo">${EQUIPOS.concat(EQUIPOS.includes(tipo) ? [] : [tipo]).map(t => `<option${t === tipo ? ' selected' : ''}>${esc(t)}</option>`).join('')}</select></div>
    <div class="field"><label for="secCant">How many</label><input id="secCant" type="number" inputmode="numeric" min="1" max="200" step="1" value="${esc(e ? e.cantidad : 1)}"></div>
    ${campoCuarto(e && e.cuarto_id, e && e.lugar)}
    <div class="field"><label for="secPuesto">Placed on</label><input id="secPuesto" type="date" value="${esc(e ? String(e.puesto).slice(0, 10) : hoyLocal())}" max="${esc(hoyLocal())}"></div>
    <div class="field"><label for="secQuitado">Removed on <span class="hint">(leave empty while it is still on site)</span></label><input id="secQuitado" type="date" value="${esc(e && e.quitado ? String(e.quitado).slice(0, 10) : '')}" max="${esc(hoyLocal())}"></div>
    <p class="aviso" id="secAviso"></p>
    <div class="fila-botones"><button type="button" class="btn btn-outline" data-sec="resumen">Cancel</button><button type="button" class="btn btn-accent" data-sec-guardar="equipo">${e ? 'Save' : 'Add equipment'}</button></div>
    ${e ? `<button type="button" class="btn btn-outline btn-rojo seco-borrar" data-sec-borrar="equipo">${IC('archivo')}Delete this equipment</button>` : ''}</div>`;
}

// ---------- guardar ----------
const avisar = (t) => { const a = $('#secAviso'); if(a){ a.className = 'aviso'; a.textContent = t; } };
function ir(pantalla, edita){ PANTALLA = pantalla; EDITA = edita || null; if(pantalla === 'lecturas') DIA = hoyLocal(); if(pantalla !== 'resumen') AVISO = ''; pintarAqui(); const c = caja(); if(c && c.scrollIntoView && pantalla !== 'resumen') c.scrollIntoView({ block: 'start' }); }
function terminar(texto){ AVISO = texto; AVISO_OK = true; PANTALLA = 'resumen'; EDITA = null; CARGADO = ''; cargar(); }
async function enviar(metodo, ruta, cuerpo, prefer){
  const r = await authFetch('/rest/v1/' + ruta, { method: metodo, headers: { Prefer: prefer || 'return=representation' }, body: cuerpo == null ? undefined : JSON.stringify(cuerpo) });
  if(!r.ok){ let m = 'HTTP ' + r.status; try{ const d = await r.json(); m = d.message || m; }catch{} throw new Error(m); }
  return r.status === 204 ? [] : await r.json().catch(() => []);
}
function leerCuarto(){
  const v = ($('#secCuarto') || {}).value || '';
  if(v && v !== '__otro'){ const c = CUARTOS.find(x => x.id === v); return { cuarto_id: v, lugar: c ? c.nombre : null }; }
  const l = (($('#secLugar') || {}).value || '').trim();
  return l ? { cuarto_id: null, lugar: l } : null;
}
async function guardarPunto(){
  const donde = leerCuarto(); if(!donde){ avisar('Choose the room (or type its name).'); return; }
  const supEl = $('#secSup .subtab.on'), sup = supEl ? supEl.dataset.secSup : 'Wall';
  let mat = $('#secMaterial').value; if(mat === '__otro') mat = ($('#secMaterialOtro').value || '').trim();
  if(!mat){ avisar('Type the material.'); return; }
  const metaTxt = $('#secMeta').value.trim(), meta = metaTxt === '' ? null : Number(metaTxt);
  if(meta != null && (!isFinite(meta) || meta < 0 || meta > 1000)){ avisar('The dry goal has to be a number from 0 to 1000.'); return; }
  const fila = { ...donde, superficie: sup, material: mat, ubicacion: ($('#secUbic').value || '').trim() || null, meta };
  const rows = EDITA ? await enviar('PATCH', 'fotos_secado_puntos?id=eq.' + encodeURIComponent(EDITA), fila) : await enviar('POST', 'fotos_secado_puntos', { trabajo_id: T.id, ...fila });
  if(!rows.length) throw new Error('The server did not keep it. Try again.');
  terminar(EDITA ? 'Moisture point saved.' : 'Moisture point added: ' + mat + ' in ' + (donde.lugar || 'the room') + '.');
}
async function guardarEquipo(){
  const donde = leerCuarto(); if(!donde){ avisar('Choose the room (or type its name).'); return; }
  const cant = Number($('#secCant').value); if(!Number.isInteger(cant) || cant < 1 || cant > 200){ avisar('How many: a whole number from 1 to 200.'); return; }
  const puesto = $('#secPuesto').value, quitado = $('#secQuitado').value || null;
  if(!puesto){ avisar('Choose the day it was placed.'); return; }
  if(quitado && quitado < puesto){ avisar('It cannot be removed before the day it was placed.'); return; }
  const fila = { ...donde, tipo: $('#secTipo').value, cantidad: cant, puesto, quitado };
  const rows = EDITA ? await enviar('PATCH', 'fotos_secado_equipos?id=eq.' + encodeURIComponent(EDITA), fila) : await enviar('POST', 'fotos_secado_equipos', { trabajo_id: T.id, ...fila });
  if(!rows.length) throw new Error('The server did not keep it. Try again.');
  terminar(EDITA ? 'Equipment saved.' : 'Added ' + cant + ' ' + pluralEquipo(fila.tipo, cant) + ' in ' + (donde.lugar || 'the room') + '.');
}
async function guardarLecturas(){
  const dia = $('#secDia').value; if(!dia){ avisar('Choose the date.'); return; }
  if(dia > hoyLocal()){ avisar('The date cannot be in the future.'); return; }
  const poner = [], quitar = [], amb = [], quitarAmb = [];
  for(const inp of $$('[data-lec-punto]', caja())){
    const id = inp.dataset.lecPunto, v = inp.value.trim(), ya = D.lecturas.find(x => x.punto_id === id && String(x.dia).slice(0, 10) === dia);
    if(v === ''){ if(ya) quitar.push(ya.id); continue; }
    const n = Number(v); if(!isFinite(n) || n < 0 || n > 1000){ avisar('Each moisture reading has to be a number from 0 to 1000.'); inp.focus(); return; }
    if(!ya || Number(ya.valor) !== n) poner.push({ punto_id: id, trabajo_id: T.id, dia, valor: n });
  }
  for(const fila of $$('[data-amb-lugar]', caja())){
    const lugar = fila.dataset.ambLugar, t = $('[data-amb="t"]', fila).value.trim(), h = $('[data-amb="h"]', fila).value.trim();
    const ya = D.ambiente.find(x => x.lugar === lugar && String(x.dia).slice(0, 10) === dia);
    if(t === '' && h === ''){ if(ya) quitarAmb.push(ya.id); continue; }
    if(t === '' || h === ''){ avisar(lugar + ': type both the temperature and the humidity.'); return; }
    if(gpp(t, h) == null){ avisar(lugar + ': temperature from -40 to 160 °F and humidity from 0 to 100 %.'); return; }
    if(!ya || Number(ya.temp_f) !== Number(t) || Number(ya.rh) !== Number(h)) amb.push({ trabajo_id: T.id, dia, lugar, temp_f: Number(t), rh: Number(h) });
  }
  if(!poner.length && !quitar.length && !amb.length && !quitarAmb.length){ avisar('Nothing changed. Type the readings first.'); return; }
  const junta = 'resolution=merge-duplicates,return=representation';
  if(poner.length){ const r = await enviar('POST', 'fotos_secado_lecturas?on_conflict=punto_id,dia', poner, junta); if(r.length !== poner.length) throw new Error('Only ' + r.length + ' of ' + poner.length + ' moisture readings were kept. Try again.'); }
  if(amb.length){ const r = await enviar('POST', 'fotos_secado_ambiente?on_conflict=trabajo_id,dia,lugar', amb, junta); if(r.length !== amb.length) throw new Error('Only ' + r.length + ' of ' + amb.length + ' atmosphere readings were kept. Try again.'); }
  for(const id of quitar) await enviar('DELETE', 'fotos_secado_lecturas?id=eq.' + encodeURIComponent(id));
  for(const id of quitarAmb) await enviar('DELETE', 'fotos_secado_ambiente?id=eq.' + encodeURIComponent(id));
  const n = poner.length + amb.length;
  terminar((n ? 'Saved ' + n + ' ' + (n === 1 ? 'reading' : 'readings') : 'Readings updated') + ' for ' + fechaCorta(dia) + (quitar.length + quitarAmb.length ? ' (' + (quitar.length + quitarAmb.length) + ' cleared)' : '') + '.');
}
async function borrar(){
  if(PANTALLA === 'punto'){
    const p = D.puntos.find(x => x.id === EDITA); if(!p) return;
    const n = D.lecturas.filter(l => l.punto_id === p.id).length;
    if(!confirm('Delete the ' + p.material + ' point' + (n ? ' and its ' + n + ' ' + (n === 1 ? 'reading' : 'readings') : '') + '? This cannot be undone.')) return;
    const r = await enviar('DELETE', 'fotos_secado_puntos?id=eq.' + encodeURIComponent(p.id));
    if(!r.length) throw new Error('It was not deleted (only a manager or the person who added it can delete it).');
    terminar('Moisture point deleted.');
  } else if(PANTALLA === 'equipo'){
    const e = D.equipos.find(x => x.id === EDITA); if(!e) return;
    if(!confirm('Delete this equipment from the log? If it was picked up, use "Removed on" instead, so its days still count.')) return;
    const r = await enviar('DELETE', 'fotos_secado_equipos?id=eq.' + encodeURIComponent(e.id));
    if(!r.length) throw new Error('It was not deleted (only a manager or the person who added it can delete it).');
    terminar('Equipment deleted.');
  }
}
async function quitarEquipo(id){
  const e = D.equipos.find(x => x.id === id); if(!e) return;
  const hoy = hoyLocal(), n = Number(e.cantidad) || 0;
  if(!confirm('Mark ' + n + ' ' + pluralEquipo(e.tipo, n) + ' (' + nombreLugar(e.cuarto_id, e.lugar) + ') as removed today, ' + fechaCorta(hoy) + '?')) return;
  const r = await enviar('PATCH', 'fotos_secado_equipos?id=eq.' + encodeURIComponent(id), { quitado: hoy < String(e.puesto).slice(0, 10) ? String(e.puesto).slice(0, 10) : hoy });
  if(!r.length) throw new Error('It was not saved. Try again.');
  terminar(n + ' ' + pluralEquipo(e.tipo, n) + ' removed today.');
}
async function conCandado(fn){
  if(OCUPADO) return; OCUPADO = true;
  const b = $$('[data-sec-guardar], [data-sec-borrar]', caja()); b.forEach(x => { x.disabled = true; });
  try{ await fn(); }
  catch(e){ if(PANTALLA === 'resumen'){ AVISO = 'Not saved: ' + (e.message || e); AVISO_OK = false; pintarAqui(); } else avisar('Not saved: ' + (e.message || e)); }
  finally{ OCUPADO = false; b.forEach(x => { x.disabled = false; }); }
}

// ---------- toques ----------
export function conectar(){
  document.addEventListener('click', (e) => {
    const c = caja(); if(!c || !c.contains(e.target)) return;
    const q = (s) => e.target.closest(s);
    let el;
    if(q('[data-sec-clima]')){ CLIMA.dato = null; llenarAfuera(true); return; }
    if((el = q('[data-sec-vista]'))){ VISTA = el.dataset.secVista; AVISO = ''; pintarAqui(); return; }
    if((el = q('[data-sec-sup]'))){ $$('#secSup .subtab').forEach(b => b.classList.toggle('on', b === el)); $('#secMaterial').innerHTML = opcionesMaterial(el.dataset.secSup, (MATERIALES[el.dataset.secSup] || [])[0]); $('#secMaterialOtroCaja').hidden = true; return; }
    if((el = q('[data-sec-punto]'))){ ir('punto', el.dataset.secPunto); return; }
    if((el = q('[data-sec-equipo]'))){ ir('equipo', el.dataset.secEquipo); return; }
    if((el = q('[data-sec-quitar]'))){ conCandado(() => quitarEquipo(el.dataset.secQuitar)); return; }
    if((el = q('[data-sec-guardar]'))){ const k = el.dataset.secGuardar; conCandado(k === 'punto' ? guardarPunto : k === 'equipo' ? guardarEquipo : guardarLecturas); return; }
    if(q('[data-sec-borrar]')){ conCandado(borrar); return; }
    if((el = q('[data-sec]'))){ if(el.dataset.sec === 'resumen'){ AVISO = ''; } ir(el.dataset.sec); return; }
  });
  document.addEventListener('change', (e) => {
    const c = caja(); if(!c || !c.contains(e.target)) return;
    if(e.target.id === 'secCuarto'){ const box = $('#secLugarCaja'); if(box) box.hidden = e.target.value !== '__otro' && !!CUARTOS.length; if(e.target.value === '__otro') $('#secLugar').focus(); }
    if(e.target.id === 'secMaterial'){ $('#secMaterialOtroCaja').hidden = e.target.value !== '__otro'; if(e.target.value === '__otro') $('#secMaterialOtro').focus(); }
    if(e.target.id === 'secDia' && e.target.value){ DIA = e.target.value; pintarAqui(); }
  });
  document.addEventListener('input', (e) => {
    const fila = e.target.closest && e.target.closest('[data-amb-lugar]'); if(!fila || !caja() || !caja().contains(fila)) return;
    const g = gpp($('[data-amb="t"]', fila).value, $('[data-amb="h"]', fila).value);
    $('.seco-gpp', fila).textContent = fmtGpp(g) + ' GPP';
  });
}
