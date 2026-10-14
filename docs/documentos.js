// Scanova360 · pestaña DOCUMENTS (14-oct): la papelería del secado para entregar (seguro, cliente, oficina).
//  · Dry Log Report: cada cuarto, cada punto de medida (material · dónde) y su lectura de cada día, con cuánto bajó;
//    al final las fotos del medidor que prueban cada lectura.
//  · Equipment Report: el equipo de cada cuarto día por día y los DÍAS DE EQUIPO (lo que se cobra), con la regla dicha.
// Cada uno se ve aquí mismo (su propia pantalla, con Back) y se baja en PDF (en el teléfono, la hoja de compartir).
// Los números salen de docs/registro.js (lo mismo que ve el técnico en el teléfono): nada se calcula dos veces.
import { $, authFetch, esAparato } from './app.js?v=2026-10-14-35';
import * as R from './registro.js?v=2026-10-14-35';
import * as fotos from './fotos.js?v=2026-10-14-35';

const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
const IC = (n, cls) => '<svg class="ic' + (cls ? ' ' + cls : '') + '"><use href="#i-' + n + '"/></svg>';
const fmt = (v) => (Math.round(Number(v) * 10) / 10).toString();
const signo = (d) => d > 0 ? '+' + fmt(d) : fmt(d);

// ---------- lo puro: lo que lleva cada reporte ----------
// Los cuartos en el orden de la app (pisos de arriba abajo), solo los que tienen algo anotado.
function cuartosOrdenados(niveles, cuartos, usados){
  const out = [];
  (niveles || []).forEach(n => (cuartos || []).filter(c => c.nivel_id === n.id && usados.has(c.id)).forEach(c => out.push({ ...c, nivel: n.nombre })));
  return out;
}
export function modeloDryLog(niveles, cuartos, lecturas, equipos, hoy){
  const dias = R.diasDelRegistro(lecturas, []);
  const usados = new Set((lecturas || []).map(f => f.cuarto_id));
  const lista = cuartosOrdenados(niveles, cuartos, usados);
  // Lecturas de un cuarto que ya no existe: se siguen viendo con su nombre guardado.
  const sueltos = [...usados].filter(id => !lista.some(c => c.id === id)).map(id => { const f = lecturas.find(x => x.cuarto_id === id); return { id, nombre: (f && f.cuarto_nombre) || 'Room', nivel: '' }; });
  const salas = [...lista, ...sueltos].map(c => ({
    id: c.id, nombre: c.nombre, nivel: c.nivel,
    puntos: R.puntosDeCuarto(lecturas, c.id).map(p => {
      let ant = null;
      const celdas = dias.map(({ dia }) => { const x = p.dias[dia]; if(!x) return null;
        const t = ant == null ? null : R.tendencia(ant, x.valor); ant = x.valor; return { valor: x.valor, tend: t, foto_id: x.foto_id }; });
      const vals = celdas.filter(Boolean).map(c => c.valor), conFoto = celdas.filter(c => c && c.foto_id);
      return { clave: p.clave, nombre: p.nombre, material: p.material, ubicacion: p.ubicacion, celdas, foto_id: conFoto.length ? conFoto[conFoto.length - 1].foto_id : null,
        cambio: vals.length > 1 ? Math.round((vals[vals.length - 1] - vals[0]) * 10) / 10 : null };
    }),
  }));
  // Su estilo (14-oct, "Daily Drying Log"): cada punto lleva su número de foto P-001, P-002… (el mismo en la tabla y
  // en las fotos del final) y las tablas van por nivel.
  let k = 0; salas.forEach(sa => sa.puntos.forEach(pt => { pt.num = 'P-' + String(++k).padStart(3, '0'); }));
  const porNivel = []; salas.forEach(sa => { const g = porNivel[porNivel.length - 1]; if(g && g.nivel === sa.nivel) g.salas.push(sa); else porNivel.push({ nivel: sa.nivel, salas: [sa] }); });
  // La gráfica "Moisture Trend": el primer punto de cada cuarto (hasta 6 líneas, para que se lea).
  const serie = salas.map(sa => sa.puntos.find(pt => pt.celdas.filter(Boolean).length) ).filter(Boolean).slice(0, 6)
    .map(pt => { const sa = salas.find(x => x.puntos.includes(pt)); return { etiqueta: sa.nombre + (pt.material ? ' (' + pt.material.toLowerCase() + ')' : ''), valores: pt.celdas.map(c => c ? c.valor : null) }; });
  // Equipo (promedio por día): días de equipo / días del secado, por tipo.
  const res = equipos && hoy ? R.resumenDeEquipo(equipos, hoy) : [], pd = R.primerDia(lecturas, equipos || []);
  const nDias = pd && hoy ? R.diasEntre(pd, hoy) + 1 : 0;
  const promedio = nDias ? res.map(r => ({ tipo: r.tipo, n: Math.round(r.dias / nDias * 10) / 10 })).filter(r => r.n > 0) : [];
  const fotosLect = (lecturas || []).filter(f => f.foto_id).slice().sort((a, b) => String(a.dia).localeCompare(String(b.dia)) || String(a.created_at || '').localeCompare(String(b.created_at || '')))
    .map(f => { const sa = salas.find(x => x.id === f.cuarto_id), pt = sa && sa.puntos.find(x => x.clave === R.clavePunto(f)); return { ...f, num: pt ? pt.num : '' }; })
    .sort((a, b) => String(a.num).localeCompare(String(b.num)) || String(a.dia).localeCompare(String(b.dia)));   // cada punto con sus fotos juntas (P-001 día 1, 2, 3…)
  return { dias, salas, porNivel, serie, promedio, total: (lecturas || []).length,
    tecnicos: [...new Set((lecturas || []).map(f => f.created_by).filter(Boolean))],
    lecturasFoto: fotosLect };
}
export function modeloEquipo(niveles, cuartos, equipos, hoy){
  const porDia = R.equipoPorDia(equipos), dias = R.diasDelRegistro([], equipos);
  // Los días de equipo cuentan hasta hoy: si hoy no hubo visita, se agrega la columna "Today" (con lo que sigue puesto)
  // para que la cuenta se vea completa (3 + 2 + 2 = 7, no 3 + 2 = 7).
  if(dias.length && hoy > dias[dias.length - 1].dia) dias.push({ dia: hoy, n: R.diasEntre(dias[0].dia, hoy) + 1, hoy: true });
  const usados = new Set(Object.keys(porDia));
  const lista = cuartosOrdenados(niveles, cuartos, usados);
  const salas = lista.map(c => {
    const tipos = [...new Set(Object.values(porDia[c.id] || {}).flatMap(x => Object.keys(x)))];
    return { nombre: c.nombre, nivel: c.nivel,
      tipos: tipos.map(t => ({ tipo: t,
        celdas: dias.map(({ dia }) => { const e = R.equipoEnDia(porDia, c.id, dia); const visto = !!((porDia[c.id] || {})[dia]); return e ? { n: e.cuentas[t] || 0, visto } : null; }),
        dias: R.diasDeEquipo(porDia, c.id, t, hoy) })) };
  });
  return { dias, salas, resumen: R.resumenDeEquipo(equipos, hoy), hoy, total: R.resumenDeEquipo(equipos, hoy).reduce((a, r) => a + r.dias, 0) };
}
export const REGLA_DIAS = 'Equipment days count every calendar day a unit was on site: from the day it was logged until the day it was logged as removed (the removal day is not counted). Days between visits keep the last count. Units still on site are counted through the report date.';

// ---------- estado y datos ----------
let T = null, NIVELES = [], CUARTOS = [], LECT = [], EQUI = [], CARGADO = null, VISTA = 'lista', OCUPADO = false, FRESCO = false, CARGANDO = false;
async function cargar(){
  if(!T || CARGANDO) return; const id = T.id; CARGANDO = true;
  try{ await cargarDe(id); }finally{ CARGANDO = false; }
}
async function cargarDe(id){
  const q = (t) => authFetch('/rest/v1/' + t + '?trabajo_id=eq.' + encodeURIComponent(id) + '&order=dia.asc,created_at.asc&limit=5000').then(r => r.ok ? r.json() : []).catch(() => []);
  const [l, e] = await Promise.all([q('fotos_drylog_lecturas'), q('fotos_drylog_equipos'), fotos.cargarNombres().catch(() => null)]);
  if(!T || T.id !== id) return;
  LECT = Array.isArray(l) ? l : []; EQUI = Array.isArray(e) ? e : []; CARGADO = id; pintarAqui();
}
const caja = () => $('#panel-documentos');
export function pintar(t, niveles, cuartos){
  if(!t) return;
  if(!T || T.id !== t.id){ VISTA = 'lista'; CARGADO = null; LECT = []; EQUI = []; }
  T = t; NIVELES = niveles || []; CUARTOS = cuartos || [];
  if(FRESCO || CARGADO !== T.id){ FRESCO = false; cargar(); }
  pintarAqui();
}
// Al abrir la pestaña: lo más nuevo (el técnico pudo anotar hace un minuto).
export function entrar(){ VISTA = 'lista'; FRESCO = true; }
function periodo(dias){ return dias.length ? (dias.length === 1 ? R.fechaLarga(dias[0].dia) : R.fechaCorta(dias[0].dia) + ' – ' + R.fechaLarga(dias[dias.length - 1].dia)) : ''; }
function pintarAqui(){
  const c = caja(); if(!c || !T) return;
  if(CARGADO !== T.id){ c.innerHTML = '<p class="vacio">Loading documents…</p>'; return; }
  const hoy = R.hoyLocal(), md = modeloDryLog(NIVELES, CUARTOS, LECT, EQUI, hoy), me = modeloEquipo(NIVELES, CUARTOS, EQUI, hoy);
  if(VISTA === 'dry'){ c.innerHTML = vistaHtml('', htmlDryLog(md), 'dry'); ponerFotitos(c); return; }
  if(VISTA === 'equipo'){ c.innerHTML = vistaHtml('Equipment Report', htmlEquipo(me), 'equipo'); return; }
  const fila = (k, ic, titulo, sub, hay) => `<div class="doc-fila">
      <span class="doc-ic">${IC(ic)}</span>
      <div class="doc-txt"><b>${titulo}</b><small>${sub}</small></div>
      <div class="doc-acc"><button type="button" class="btn btn-outline btn-chico" data-doc-ver="${k}"${hay ? '' : ' disabled'}>View</button><button type="button" class="btn btn-accent btn-chico" data-doc-pdf="${k}"${hay ? '' : ' disabled'}>${IC('bajar')}PDF</button></div></div>`;
  c.innerHTML = `<div class="card docs">
    <h2 class="sec-t">Documents</h2>
    <p class="doc-nota">Drying paperwork for this project, ready to send. It updates every time the crew saves a reading or equipment.</p>
    ${fila('dry', 'dl-hoja', 'Dry Log Report', md.total ? `${md.salas.length} room${md.salas.length === 1 ? '' : 's'} · ${md.total} reading${md.total === 1 ? '' : 's'} · ${md.dias.length} day${md.dias.length === 1 ? '' : 's'} (${esc(periodo(md.dias))})` : 'No readings yet. They come from Dry Logs.', md.total > 0)}
    ${fila('equipo', 'dl-herramientas', 'Equipment Report', me.resumen.length ? `${me.salas.length} room${me.salas.length === 1 ? '' : 's'} · ${me.total} equipment day${me.total === 1 ? '' : 's'} so far` : 'No equipment logged yet. It comes from Dry Logs.', me.resumen.length > 0)}
    <p class="aviso" id="docAviso"></p>
  </div>`;
}
function vistaHtml(titulo, cuerpo, k){
  return `<div class="doc-vista">
    <div class="doc-vista-cab"><button type="button" class="volver" data-doc-volver data-atras-pie>${IC('atras')}Documents</button>
      <button type="button" class="btn btn-accent btn-chico" data-doc-pdf="${k}">${IC('bajar')}Download PDF</button></div>
    <div class="doc-hoja">${titulo ? encabezadoHtml(titulo) : ''}${cuerpo}</div>
    <p class="aviso" id="docAviso"></p></div>`;
}
async function ponerFotitos(c){
  const ids = [...new Set([...c.querySelectorAll('img[data-foto]')].map(i => i.dataset.foto))]; if(!ids.length) return;
  let u = {}; try{ u = await fotos.urlsFirmadas(ids, 'mini'); }catch{}
  c.querySelectorAll('img[data-foto]').forEach(i => { if(u[i.dataset.foto]) i.src = u[i.dataset.foto]; });
}
function encabezadoHtml(titulo){
  return `<div class="doc-enc"><div class="doc-marca">Scanova<span>360</span></div><div class="doc-titulo">${esc(titulo)}</div></div>
    <div class="doc-datos"><div><small>Client</small><b>${esc(T.cliente || '')}</b></div><div><small>Address</small><b>${esc(T.direccion || '—')}</b></div>
      <div><small>Project manager</small><b>${esc(T.encargado || '—')}</b></div><div><small>Report date</small><b>${esc(R.fechaLarga(R.hoyLocal()))}</b></div></div>`;
}
// "Material / point" como en su muestra: Baseboard (east wall).
const puntoTxt = (pt) => pt.material ? pt.material + (pt.ubicacion ? ' (' + pt.ubicacion.toLowerCase() + ')' : '') : (pt.ubicacion || 'Reading');
export const COLORES_SERIE = ['#2563eb', '#22c55e', '#7c3aed', '#f59e0b', '#0ea5e9', '#ef4444'];
const tecnicosTxt = (m) => m.tecnicos.map(id => fotos.nombreDe(id)).filter((x, i, a) => x && a.indexOf(x) === i).join(', ') || '—';
const trabajoTxt = (m) => (T.cliente || 'Project') + ' • ' + m.salas.length + ' room' + (m.salas.length === 1 ? '' : 's');
const equipoTxt = (m) => m.promedio.length ? m.promedio.map(r => r.tipo + ': ' + fmt(r.n)).join('  |  ') : 'No equipment logged';
// La gráfica "Moisture Trend" (su estilo): una línea por punto, los días abajo, la leyenda a la derecha.
function graficaSvg(m){
  const W = 520, H = 190, x0 = 46, x1 = 360, y0 = 16, y1 = 150;
  const vals = m.serie.flatMap(s => s.valores.filter(v => v != null)); if(!vals.length) return '';
  const tope = Math.max(10, Math.ceil(Math.max(...vals) / 5) * 5), paso = tope <= 30 ? 5 : tope <= 60 ? 10 : 20;
  const X = (i) => m.dias.length === 1 ? (x0 + x1) / 2 : x0 + 20 + i * (x1 - x0 - 40) / (m.dias.length - 1), Y = (v) => y1 - v / tope * (y1 - y0);
  let g = '';
  for(let v = 0; v <= tope; v += paso) g += `<line x1="${x0}" x2="${x1}" y1="${Y(v)}" y2="${Y(v)}" stroke="#e5ebf3"/><text x="${x0 - 8}" y="${Y(v) + 4}" text-anchor="end" font-size="11" fill="#0f1a2e">${v}</text>`;
  g += `<text transform="translate(12 ${(y0 + y1) / 2}) rotate(-90)" text-anchor="middle" font-size="11" fill="#0f1a2e">Meter reading</text>`;
  m.dias.forEach((d, i) => { g += `<text x="${X(i)}" y="${y1 + 18}" text-anchor="middle" font-size="11" font-weight="700" fill="#0f1a2e">Day ${d.n}</text><text x="${X(i)}" y="${y1 + 31}" text-anchor="middle" font-size="10" fill="#56657c">${esc(R.fechaCorta(d.dia))}</text>`; });
  m.serie.forEach((se, k) => { const c = COLORES_SERIE[k % COLORES_SERIE.length]; const pts = se.valores.map((v, i) => v == null ? null : [X(i), Y(v)]).filter(Boolean);
    if(pts.length > 1) g += `<polyline points="${pts.map(p => p.join(',')).join(' ')}" fill="none" stroke="${c}" stroke-width="2.2"/>`;
    pts.forEach(p => { g += `<circle cx="${p[0]}" cy="${p[1]}" r="4" fill="${c}"/>`; });
    const ly = y0 + 6 + k * 24; g += `<line x1="374" x2="396" y1="${ly}" y2="${ly}" stroke="${c}" stroke-width="2.2"/><circle cx="385" cy="${ly}" r="4" fill="${c}"/><text x="402" y="${ly + 4}" font-size="11" fill="#0f1a2e">${esc(se.etiqueta.length > 24 ? se.etiqueta.slice(0, 23) + '…' : se.etiqueta)}</text>`; });
  return `<svg class="dlr-svg" viewBox="0 0 ${W} ${H}" role="img" aria-label="Moisture trend">${g}</svg>`;
}
function htmlDryLog(m){
  if(!m.total) return '<p class="vacio">No readings yet.</p>';
  const cab = `<tr><th>Photo</th><th>Room</th><th>Material / point</th>${m.dias.map(d => `<th class="n">Day ${d.n}<small>${esc(R.fechaCorta(d.dia))}</small></th>`).join('')}</tr>`;
  const tablas = m.porNivel.map(g => `<div class="dlr-nivel">${esc(g.nivel || 'Other rooms')}</div>
    <div class="doc-tabla"><table class="dlr-tabla">${cab}${g.salas.flatMap(sa => sa.puntos.map(pt => `<tr>
      <td class="dlr-foto">${pt.foto_id ? `<img data-foto="${esc(pt.foto_id)}" alt="">` : '<span class="dlr-sinfoto"></span>'}<small>${pt.num}</small></td>
      <td>${esc(sa.nombre)}</td><td>${esc(puntoTxt(pt))}</td>${pt.celdas.map(c => c ? `<td class="n">${esc(fmt(c.valor))}</td>` : '<td class="n nada">—</td>').join('')}</tr>`)).join('')}</table></div>`).join('');
  return `<div class="dlr">
    <div class="dlr-top"><div class="doc-marca">Scanova<span>360</span></div><div class="dlr-etq">${esc(R.fechaLarga(R.hoyLocal()))}</div></div>
    <h1 class="dlr-t">DAILY DRYING LOG</h1>
    <div class="dlr-info"><div><b>Job:</b><span>${esc(trabajoTxt(m))}</span></div><div><b>Technician:</b><span>${esc(tecnicosTxt(m))}</span></div>
      <div><b>Date range:</b><span>${esc(periodo(m.dias))}</span></div><div><b>Address:</b><span>${esc(T.direccion || '—')}</span></div></div>
    ${m.serie.length ? `<div class="dlr-graf"><h3>Moisture Trend</h3>${graficaSvg(m)}</div>` : ''}
    ${tablas}
    <div class="dlr-pie"><div><b>Equipment status (daily average)</b><p>${esc(equipoTxt(m))}</p></div><div><b>Notes</b><p>${esc(T.notas || '—')}</p></div></div>
    <p class="dlr-nota">Moisture readings in % taken with a moisture meter; each point's photo number (P-001…) matches the photos at the end of the PDF.</p>
  </div>`;
}
function htmlEquipo(m){
  if(!m.resumen.length) return '<p class="vacio">No equipment logged yet.</p>';
  const res = `<h3 class="doc-sala">Equipment summary</h3><div class="doc-tabla"><table><tr><th>Equipment</th><th>Most units at once</th><th>Equipment days</th><th>Placed</th><th>Removed</th></tr>
    ${m.resumen.map(r => `<tr><td>${esc(r.tipo)}</td><td>${r.max}</td><td><b>${r.dias}</b></td><td>${esc(r.desde ? R.fechaCorta(r.desde) : '—')}</td><td>${r.hasta ? esc(R.fechaCorta(r.hasta)) : '<span class="baja">On site</span>'}</td></tr>`).join('')}
    <tr class="total"><td>Total</td><td></td><td><b>${m.total}</b></td><td></td><td></td></tr></table></div>
    <p class="doc-sub">${esc(REGLA_DIAS)}</p>`;
  const cab = `<tr><th>Equipment</th>${m.dias.map(d => `<th>${d.hoy ? 'Today' : 'Day ' + d.n}<small>${esc(R.fechaCorta(d.dia))}</small></th>`).join('')}<th>Days</th></tr>`;
  return res + m.salas.map(s => `<h3 class="doc-sala">${esc(s.nombre)}${s.nivel ? ` <small>${esc(s.nivel)}</small>` : ''}</h3>
    ${s.tipos.length ? `<div class="doc-tabla"><table>${cab}${s.tipos.map(t => `<tr><td>${esc(t.tipo)}</td>${t.celdas.map(c => c ? `<td class="${c.visto ? '' : 'sigue'}">${c.n}</td>` : '<td class="nada">—</td>').join('')}<td><b>${t.dias}</b></td></tr>`).join('')}</table></div>` : '<p class="doc-sub">No equipment in this room.</p>'}`).join('') +
    `<p class="doc-sub">Gray numbers = no visit that day; the last count is carried.</p>`;
}

// ---------- el PDF (jsPDF, en este mismo teléfono o compu; sin servicio de afuera) ----------
let JSPDF = null;
function cargarJsPDF(){
  if(JSPDF) return Promise.resolve(JSPDF);
  if(window.jspdf && window.jspdf.jsPDF){ JSPDF = window.jspdf.jsPDF; return Promise.resolve(JSPDF); }
  return new Promise((ok, no) => { const s = document.createElement('script'); s.src = 'vendor/jspdf.umd.min.js';
    s.onload = () => { JSPDF = window.jspdf && window.jspdf.jsPDF; JSPDF ? ok(JSPDF) : no(new Error('the PDF maker did not load')); };
    s.onerror = () => no(new Error('the PDF maker did not load (no internet?)')); document.head.appendChild(s); });
}
const AZUL = [37, 99, 235], TINTA = [15, 26, 46], SUAVE = [86, 101, 124], LINEA = [211, 220, 232], AMBAR = [183, 121, 31], FONDO = [238, 243, 251];
// Una hoja nueva con el encabezado de Scanova360 y los datos del proyecto; devuelve dónde empezar a escribir.
function hojaPdf(doc, titulo, primera){
  const W = doc.internal.pageSize.getWidth(), M = 36;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(18); doc.setTextColor(...TINTA); doc.text('Scanova', M, 44);
  const w = doc.getTextWidth('Scanova'); doc.setTextColor(...AZUL); doc.text('360', M + w, 44);
  doc.setFontSize(13); doc.setTextColor(...TINTA); doc.text(titulo, W - M, 44, { align: 'right' });
  doc.setDrawColor(...AZUL); doc.setLineWidth(2); doc.line(M, 54, W - M, 54);
  let y = 70;
  if(primera){
    const datos = [['Client', T.cliente || ''], ['Address', T.direccion || '—'], ['Project manager', T.encargado || '—'], ['Report date', R.fechaLarga(R.hoyLocal())]];
    const cw = (W - 2 * M) / 4;
    datos.forEach(([k, v], i) => { doc.setFont('helvetica', 'normal'); doc.setFontSize(8); doc.setTextColor(...SUAVE); doc.text(k.toUpperCase(), M + i * cw, y);
      doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(...TINTA); doc.text(doc.splitTextToSize(String(v), cw - 10).slice(0, 2), M + i * cw, y + 13); });
    y += 40;
  }
  return y;
}
// Una tabla que salta de hoja cuando no cabe (y repite su fila de títulos).
function tablaPdf(doc, y, cols, filas, titulo, cabeceraHoja){
  const H = doc.internal.pageSize.getHeight(), M = 36, rh = 18, fondoMax = H - M - 20;
  const dibCab = () => { doc.setFillColor(...FONDO); doc.rect(M, y, cols.reduce((a, c) => a + c.w, 0), rh + 4, 'F');
    let x = M; doc.setFont('helvetica', 'bold'); doc.setFontSize(8.5); doc.setTextColor(...TINTA);
    cols.forEach(c => { const l = String(c.t).split('\n'); doc.text(l[0], c.der ? x + c.w - 5 : x + 5, y + 10, { align: c.der ? 'right' : 'left' });
      if(l[1]){ doc.setFont('helvetica', 'normal'); doc.setTextColor(...SUAVE); doc.text(l[1], c.der ? x + c.w - 5 : x + 5, y + 19, { align: c.der ? 'right' : 'left' }); doc.setFont('helvetica', 'bold'); doc.setTextColor(...TINTA); }
      x += c.w; }); y += rh + 6; };
  if(y + 28 + rh * Math.min(2, filas.length) > fondoMax){ doc.addPage(); y = cabeceraHoja(); }
  if(titulo){ doc.setFont('helvetica', 'bold'); doc.setFontSize(12); doc.setTextColor(...TINTA); doc.text(titulo[0], M, y + 4);
    if(titulo[1]){ const w = doc.getTextWidth(titulo[0] + '  '); doc.setFont('helvetica', 'normal'); doc.setFontSize(9.5); doc.setTextColor(...SUAVE); doc.text(titulo[1], M + w, y + 4); } y += 12; }
  dibCab();
  filas.forEach((f, i) => {
    if(y + rh > fondoMax){ doc.addPage(); y = cabeceraHoja(); dibCab(); }
    let x = M;
    f.forEach((celda, j) => { const c = cols[j], v = celda && typeof celda === 'object' ? celda : { t: celda };
      doc.setFont('helvetica', v.b ? 'bold' : 'normal'); doc.setFontSize(9); doc.setTextColor(...(v.color || TINTA));
      const txt = doc.splitTextToSize(String(v.t == null ? '' : v.t), c.w - 8)[0] || '';
      doc.text(txt, c.der ? x + c.w - 5 : x + 5, y + 12, { align: c.der ? 'right' : 'left' }); x += c.w; });
    doc.setDrawColor(...LINEA); doc.setLineWidth(0.5); doc.line(M, y + rh, x, y + rh); y += rh;
  });
  return y + 14;
}
function parrafoPdf(doc, y, texto, cabeceraHoja){
  const W = doc.internal.pageSize.getWidth(), H = doc.internal.pageSize.getHeight(), M = 36;
  doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); doc.setTextColor(...SUAVE);
  const l = doc.splitTextToSize(texto, W - 2 * M);
  if(y + l.length * 11 > H - M - 20){ doc.addPage(); y = cabeceraHoja(); }
  doc.text(l, M, y); return y + l.length * 11 + 8;
}
function piePdf(doc, titulo){
  const n = doc.getNumberOfPages(), W = doc.internal.pageSize.getWidth(), H = doc.internal.pageSize.getHeight();
  for(let i = 1; i <= n; i++){ doc.setPage(i); doc.setFont('helvetica', 'normal'); doc.setFontSize(8); doc.setTextColor(...SUAVE);
    doc.text('Scanova360 · ' + titulo + ' · ' + (T.cliente || ''), 36, H - 22); doc.text('Page ' + i + ' of ' + n, W - 36, H - 22, { align: 'right' }); }
}
// Las columnas de días caben de 9 en 9 en la hoja acostada; si hay más días, la tabla sigue en otra con los siguientes.
const TROZO = 9;
const trozos = (dias) => { const out = []; for(let i = 0; i < Math.max(1, dias.length); i += TROZO) out.push([i, Math.min(dias.length, i + TROZO)]); return out; };
const colorTend = (t) => t ? (t.tipo === 'baja' ? AZUL : t.tipo === 'sube' ? AMBAR : TINTA) : TINTA;
async function fotoParaPdf(url){
  const b = await (await fetch(url, { cache: 'no-store' })).blob();
  const im = await createImageBitmap(b); const k = Math.min(1, 520 / Math.max(im.width, im.height));
  const c = document.createElement('canvas'); c.width = Math.round(im.width * k); c.height = Math.round(im.height * k);
  c.getContext('2d').drawImage(im, 0, 0, c.width, c.height); const d = c.toDataURL('image/jpeg', 0.78); c.width = c.height = 0;
  return { d, w: Math.round(im.width * k), h: Math.round(im.height * k) };
}
const hex = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
// Su estilo (14-oct, "Daily Drying Log"): hoja parada; Scanova360 arriba, el título grande, los datos del trabajo, la
// gráfica "Moisture Trend", las tablas por nivel con la foto de cada punto (P-001…), el equipo y las notas abajo; al
// final las fotos grandes con el mismo número.
export async function pdfDryLog(m, conFotos = true){
  const Pdf = await cargarJsPDF(), doc = new Pdf({ unit: 'pt', format: 'letter', orientation: 'portrait' });
  const W = doc.internal.pageSize.getWidth(), H = doc.internal.pageSize.getHeight(), M = 40, A = W - 2 * M, ABAJO = H - M - 24;
  // Las fotos (la chiquita de cada punto y las grandes del final) se bajan una vez.
  const ids = [...new Set([...m.salas.flatMap(sa => sa.puntos.map(p => p.foto_id)), ...m.lecturasFoto.map(f => f.foto_id)].filter(Boolean))];
  let urls = {}; if(ids.length){ try{ urls = await fotos.urlsFirmadas(ids, 'web'); }catch{} }
  const imgs = {}; for(const id of ids.slice(0, 120)){ if(urls[id]){ try{ imgs[id] = await fotoParaPdf(urls[id]); }catch{} } }
  const marca = (y) => { doc.setFont('helvetica', 'bold'); doc.setFontSize(19); doc.setTextColor(...TINTA); doc.text('Scanova', M, y);
    doc.setTextColor(...AZUL); doc.text('360', M + doc.getTextWidth('Scanova'), y);
    doc.setFontSize(12); doc.setTextColor(...SUAVE); doc.text(R.fechaLarga(R.hoyLocal()), W - M, y, { align: 'right' });
    doc.setDrawColor(...LINEA); doc.setLineWidth(1); doc.line(M, y + 10, W - M, y + 10); return y + 22; };
  const hoja = () => { doc.addPage(); return marca(M + 14); };
  let y = marca(M + 14);
  doc.setFont('helvetica', 'bold'); doc.setFontSize(25); doc.setTextColor(...TINTA); doc.text('DAILY DRYING LOG', M, y + 22); y += 40;
  const info = [['Job:', trabajoTxt(m)], ['Technician:', tecnicosTxt(m)], ['Date range:', periodo(m.dias)], ['Address:', T.direccion || '—']];
  info.forEach(([k, v], i) => { const x = M + (i % 2) * (A / 2), yy = y + Math.floor(i / 2) * 16;
    doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(...TINTA); doc.text(k, x, yy);
    doc.setFont('helvetica', 'normal'); doc.text(doc.splitTextToSize(String(v), A / 2 - 78)[0] || '', x + 70, yy); });
  y += 36;
  // La gráfica.
  const vals = m.serie.flatMap(se => se.valores.filter(v => v != null));
  if(vals.length){
    const gx = M, gy = y, gw = A, gh = 170;
    doc.setDrawColor(...LINEA); doc.setLineWidth(0.8); doc.roundedRect(gx, gy, gw, gh, 6, 6);
    doc.setFont('helvetica', 'bold'); doc.setFontSize(12); doc.setTextColor(...TINTA); doc.text('Moisture Trend', gx + 12, gy + 18);
    const px0 = gx + 52, px1 = gx + gw * 0.64, py0 = gy + 30, py1 = gy + gh - 36;
    const tope = Math.max(10, Math.ceil(Math.max(...vals) / 5) * 5), paso = tope <= 30 ? 5 : tope <= 60 ? 10 : 20;
    const X = (i) => m.dias.length === 1 ? (px0 + px1) / 2 : px0 + 18 + i * (px1 - px0 - 36) / (m.dias.length - 1), Y = (v) => py1 - v / tope * (py1 - py0);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5);
    for(let v = 0; v <= tope; v += paso){ doc.setDrawColor(229, 235, 243); doc.setLineWidth(0.6); doc.line(px0, Y(v), px1, Y(v)); doc.setTextColor(...TINTA); doc.text(String(v), px0 - 6, Y(v) + 3, { align: 'right' }); }
    doc.text('Meter reading', gx + 16, (py0 + py1) / 2 + 26, { angle: 90 });
    m.dias.forEach((d, i) => { doc.setFont('helvetica', 'bold'); doc.setFontSize(8.5); doc.setTextColor(...TINTA); doc.text('Day ' + d.n, X(i), py1 + 13, { align: 'center' });
      doc.setFont('helvetica', 'normal'); doc.setFontSize(7.5); doc.setTextColor(...SUAVE); doc.text(R.fechaCorta(d.dia), X(i), py1 + 23, { align: 'center' }); });
    m.serie.forEach((se, k) => { const c = hex(COLORES_SERIE[k % COLORES_SERIE.length]); const pts = se.valores.map((v, i) => v == null ? null : [X(i), Y(v)]).filter(Boolean);
      doc.setDrawColor(...c); doc.setFillColor(...c); doc.setLineWidth(1.6);
      for(let i = 1; i < pts.length; i++) doc.line(pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1]);
      pts.forEach(p => doc.circle(p[0], p[1], 2.8, 'F'));
      const lx = px1 + 22, ly = py0 + 4 + k * 20; doc.line(lx, ly, lx + 18, ly); doc.circle(lx + 9, ly, 2.8, 'F');
      doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); doc.setTextColor(...TINTA); doc.text(doc.splitTextToSize(se.etiqueta, gx + gw - lx - 30).slice(0, 2), lx + 24, ly + 3); });
    y += gh + 14;
  }
  // Las tablas por nivel (los días de 5 en 5 si son muchos: la hoja va parada).
  const POR = 5, wFoto = 50, wCuarto = 104, wDia = 62, wPunto = A - wFoto - wCuarto - wDia * Math.min(POR, Math.max(1, m.dias.length));   // las columnas llenan el ancho, como su muestra
  const filaH = 30;
  for(let a = 0; a < Math.max(1, m.dias.length); a += POR){
    const dias = m.dias.slice(a, a + POR);
    for(const g of m.porNivel){
      const filas = g.salas.flatMap(sa => sa.puntos.map(pt => ({ sa, pt })));
      if(y + 22 + 26 + filaH * Math.min(2, filas.length) > ABAJO) y = hoja();
      const banda = () => { doc.setFillColor(232, 240, 255); doc.roundedRect(M, y, A, 22, 4, 4, 'F'); doc.setFont('helvetica', 'bold'); doc.setFontSize(12); doc.setTextColor(...AZUL);
        doc.text((g.nivel || 'Other rooms') + (a ? '  (days ' + dias[0].n + '–' + dias[dias.length - 1].n + ')' : ''), M + 10, y + 15); y += 24; };
      const cab = () => { doc.setFillColor(247, 249, 252); doc.rect(M, y, A, 24, 'F'); doc.setDrawColor(...LINEA); doc.setLineWidth(0.6); doc.rect(M, y, A, 24);
        doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(...TINTA);
        doc.text('Photo', M + 8, y + 15); doc.text('Room', M + wFoto + 8, y + 15); doc.text('Material / point', M + wFoto + wCuarto + 8, y + 15);
        dias.forEach((d, i) => { const cx = M + wFoto + wCuarto + wPunto + wDia * i + wDia / 2; doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(...TINTA); doc.text('Day ' + d.n, cx, y + 11, { align: 'center' });
          doc.setFont('helvetica', 'normal'); doc.setFontSize(7.5); doc.setTextColor(...SUAVE); doc.text(R.fechaCorta(d.dia), cx, y + 20, { align: 'center' }); });
        y += 24; };
      banda(); cab();
      for(const { sa, pt } of filas){
        if(y + filaH > ABAJO){ y = hoja(); banda(); cab(); }
        const im = pt.foto_id && imgs[pt.foto_id];
        if(im){ const k = Math.min(30 / im.w, 19 / im.h); doc.addImage(im.d, 'JPEG', M + 8, y + 3, im.w * k, im.h * k); }
        doc.setFont('helvetica', 'normal'); doc.setFontSize(6.5); doc.setTextColor(...SUAVE); doc.text(pt.num, M + 8, y + 28);
        doc.setFontSize(9.5); doc.setTextColor(...TINTA);
        doc.text(doc.splitTextToSize(sa.nombre, wCuarto - 10)[0], M + wFoto + 8, y + 17);
        doc.text(doc.splitTextToSize(puntoTxt(pt), wPunto - 10)[0], M + wFoto + wCuarto + 8, y + 17);
        pt.celdas.slice(a, a + POR).forEach((c, i) => { const cx = M + wFoto + wCuarto + wPunto + wDia * i + wDia / 2; doc.setTextColor(...(c ? TINTA : SUAVE)); doc.text(c ? fmt(c.valor) : '—', cx, y + 17, { align: 'center' }); });
        doc.setDrawColor(...LINEA); doc.setLineWidth(0.5); doc.line(M, y + filaH, M + A, y + filaH); y += filaH;
      }
      y += 10;
    }
  }
  // El equipo y las notas.
  if(y + 70 > ABAJO) y = hoja();
  doc.setDrawColor(...LINEA); doc.setLineWidth(0.8); doc.line(M, y, M + A, y); y += 16;
  doc.line(M + A / 2, y - 6, M + A / 2, y + 40);
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.setTextColor(...TINTA); doc.text('Equipment status (daily average)', M, y); doc.text('Notes', M + A / 2 + 14, y);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9.5);
  doc.text(doc.splitTextToSize(equipoTxt(m), A / 2 - 14).slice(0, 3), M, y + 16);
  doc.text(doc.splitTextToSize(T.notas || '—', A / 2 - 14).slice(0, 3), M + A / 2 + 14, y + 16);
  y += 52;
  doc.setFontSize(8); doc.setTextColor(...SUAVE);
  doc.text(doc.splitTextToSize("Moisture readings in % taken with a moisture meter. Each point's photo number (P-001...) matches the reading photos below.", A), M, y);
  // Las fotos grandes del final (cada una con el número de su punto).
  const lista = m.lecturasFoto.filter(f => imgs[f.foto_id]);
  if(conFotos && lista.length){
    y = hoja(); doc.setFont('helvetica', 'bold'); doc.setFontSize(13); doc.setTextColor(...TINTA); doc.text('Reading photos', M, y + 6); y += 18;
    const porFila = 3, gap = 12, cw = (A - gap * (porFila - 1)) / porFila, ch = cw * 0.75;
    lista.forEach((f, i) => {
      if(i % porFila === 0 && i) y += ch + 34;
      if(y + ch + 30 > ABAJO){ y = hoja(); }
      const x = M + (i % porFila) * (cw + gap), im = imgs[f.foto_id], k = Math.min(cw / im.w, ch / im.h);
      doc.addImage(im.d, 'JPEG', x + (cw - im.w * k) / 2, y + (ch - im.h * k) / 2, im.w * k, im.h * k);
      doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(...TINTA); doc.text((f.num ? f.num + '  ' : '') + fmt(f.valor) + '%  ' + (f.cuarto_nombre || ''), x, y + ch + 12);
      doc.setFont('helvetica', 'normal'); doc.setFontSize(8); doc.setTextColor(...SUAVE); doc.text(doc.splitTextToSize(puntoTxt({ material: f.material, ubicacion: f.ubicacion }) + ' · ' + R.fechaCorta(f.dia), cw)[0], x, y + ch + 23);
    });
  }
  piePdf(doc, 'Daily Drying Log');
  return doc.output('blob');
}
export async function pdfEquipo(m){
  const Pdf = await cargarJsPDF(), doc = new Pdf({ unit: 'pt', format: 'letter', orientation: 'landscape' }), TIT = 'Equipment Report';
  const W = doc.internal.pageSize.getWidth(), M = 36, cabH = () => hojaPdf(doc, TIT, false), A = W - 2 * M;
  let y = hojaPdf(doc, TIT, true);
  y = tablaPdf(doc, y, [{ t: 'Equipment', w: A - 4 * 110 }, { t: 'Most units at once', w: 110, der: true }, { t: 'Equipment days', w: 110, der: true }, { t: 'Placed', w: 110, der: true }, { t: 'Removed', w: 110, der: true }],
    [...m.resumen.map(r => [r.tipo, String(r.max), { t: String(r.dias), b: true }, r.desde ? R.fechaCorta(r.desde) : '—', r.hasta ? R.fechaCorta(r.hasta) : { t: 'On site', color: AZUL, b: true }]),
      [{ t: 'Total', b: true }, '', { t: String(m.total), b: true }, '', '']], ['Equipment summary', 'through ' + R.fechaLarga(m.hoy)], cabH);
  y = parrafoPdf(doc, y, REGLA_DIAS, cabH);
  for(const s of m.salas){
    if(!s.tipos.length) continue;
    for(const [a, b] of trozos(m.dias)){
      const dias = m.dias.slice(a, b), ultimo = b === m.dias.length, anchoDia = 58;
      const cols = [{ t: 'Equipment', w: A - anchoDia * dias.length - (ultimo ? 62 : 0) }, ...dias.map(d => ({ t: (d.hoy ? 'Today' : 'Day ' + d.n) + '\n' + R.fechaCorta(d.dia), w: anchoDia, der: true }))];
      if(ultimo) cols.push({ t: 'Days', w: 62, der: true });
      const filas = s.tipos.map(t => [t.tipo, ...t.celdas.slice(a, b).map(c => c ? { t: String(c.n), color: c.visto ? TINTA : SUAVE } : { t: '—', color: SUAVE }), ...(ultimo ? [{ t: String(t.dias), b: true }] : [])]);
      y = tablaPdf(doc, y, cols, filas, [s.nombre + (a ? ' (cont.)' : ''), s.nivel || ''], cabH);
    }
  }
  parrafoPdf(doc, y, 'Gray numbers = no visit that day; the last count is carried.', cabH);
  piePdf(doc, TIT);
  return doc.output('blob');
}
// Bajar / compartir el PDF (como el plano: en el teléfono la hoja de compartir; en la compu, a Descargas).
async function entregar(blob, nombre){
  const archivo = new File([blob], nombre, { type: 'application/pdf' });
  const tel = esAparato() || /iPhone|iPad|Android/i.test(navigator.userAgent);
  if(tel && navigator.canShare && navigator.canShare({ files: [archivo] })){ await navigator.share({ files: [archivo], title: nombre }); return 'shared'; }
  const u = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = u; a.download = nombre; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(u), 4000);
  return 'downloaded';
}
const avisar = (t, bien) => { const a = $('#docAviso'); if(a){ a.className = 'aviso' + (bien ? ' ok' : ''); a.textContent = t; } };
async function hacerPdf(k){
  if(OCUPADO || !T) return; OCUPADO = true;
  const b = document.querySelector('[data-doc-pdf="' + k + '"]'); const antes = b ? b.innerHTML : ''; if(b){ b.disabled = true; b.textContent = 'Making PDF…'; }
  try{
    const hoy = R.hoyLocal();
    const blob = k === 'dry' ? await pdfDryLog(modeloDryLog(NIVELES, CUARTOS, LECT, EQUI, hoy)) : await pdfEquipo(modeloEquipo(NIVELES, CUARTOS, EQUI, hoy));
    const nombre = ((k === 'dry' ? 'DryLog ' : 'Equipment ') + (T.cliente || 'Project') + ' ' + hoy).replace(/[^\w\- ]+/g, '').trim().replace(/\s+/g, '_') + '.pdf';
    const r = await entregar(blob, nombre);
    avisar(r === 'shared' ? '' : 'Downloaded ' + nombre, true);
  }catch(e){ if(!(e && e.name === 'AbortError')) avisar('Could not make the PDF. ' + String(e && e.message || e)); }
  finally{ OCUPADO = false; const b2 = document.querySelector('[data-doc-pdf="' + k + '"]'); if(b2){ b2.disabled = false; b2.innerHTML = antes || 'PDF'; } }
}
export function conectar(){
  document.addEventListener('click', (e) => {
    const c = caja(); if(!c || !c.contains(e.target)) return;
    const q = (s) => e.target.closest(s); let el;
    if((el = q('[data-doc-ver]'))){ VISTA = el.dataset.docVer; pintarAqui(); const m = $('#main'); if(m) m.scrollTop = Math.max(0, c.getBoundingClientRect().top - m.getBoundingClientRect().top + m.scrollTop - 8); return; }
    if(q('[data-doc-volver]')){ VISTA = 'lista'; pintarAqui(); return; }
    if((el = q('[data-doc-pdf]'))){ hacerPdf(el.dataset.docPdf); return; }
  });
}
