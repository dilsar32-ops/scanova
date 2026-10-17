// Scanova360 · pestaña DOCUMENTS (14-oct): la papelería del secado para entregar (seguro, cliente, oficina).
//  · Dry Log Report: cada cuarto, cada punto de medida (material · dónde) y su lectura de cada día, con cuánto bajó;
//    al final las fotos del medidor que prueban cada lectura.
//  · Equipment Report: el equipo de cada cuarto día por día y los DÍAS DE EQUIPO (lo que se cobra), con la regla dicha.
//  · Measurements & Demo (15-oct): lo que se demolió por nivel y cuarto, sumado por material (Material · Surface · Qty ·
//    Unit, como Field Reports), el total del trabajo por partida y las notas. Los números salen de docs/medidas.js.
// Cada uno se ve aquí mismo (su propia pantalla, con Back) y se baja en PDF (en el teléfono, la hoja de compartir).
// Los números salen de docs/registro.js (lo mismo que ve el técnico en el teléfono): nada se calcula dos veces.
import { $, authFetch, esAparato } from './app.js?v=2026-10-16-13';
import * as R from './registro.js?v=2026-10-16-13';
import * as fotos from './fotos.js?v=2026-10-16-13';
import * as MD from './medidas.js?v=2026-10-16-13';
import * as planos from './planos.js?v=2026-10-16-13';

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
// Photo Report (15-oct, su pedido: "en los documentos tenemos que tener secciones de fotos, del floor plan y de los
// measurements"): las fotos del proyecto cuarto por cuarto, en el orden de los niveles y cuartos del proyecto y, dentro
// de cada cuarto, en el orden en que se tomaron. Cada una con su número (#1, #2…), la fecha y hora, quién la tomó y su
// nota; la foto que prueba una lectura del Dry Log dice cuál lectura es.
export function modeloFotos(niveles, cuartos, lista, lecturas){
  const lect = new Map(); (lecturas || []).forEach(l => { if(l.foto_id && !lect.has(l.foto_id)) lect.set(l.foto_id, l); });
  const grupos = new Map();
  const grupo = (clave, nivel, cuarto) => { let g = grupos.get(clave); if(!g){ g = { clave, nivel, cuarto, fotos: [] }; grupos.set(clave, g); } return g; };
  (niveles || []).forEach(n => { (cuartos || []).filter(c => c.nivel_id === n.id).forEach(c => grupo('c:' + c.id, n.nombre, c.nombre)); grupo('n:' + n.id, n.nombre, ''); });
  const cuaPorId = new Map((cuartos || []).map(c => [c.id, c])), nivPorId = new Map((niveles || []).map(n => [n.id, n]));
  const cuando = (f) => f.tomada_at || f.subida_at || '';
  (lista || []).slice().sort((a, b) => String(cuando(a)).localeCompare(String(cuando(b)))).forEach(f => {
    const c = f.cuarto_id && cuaPorId.get(f.cuarto_id), n = (f.nivel_id && nivPorId.get(f.nivel_id)) || (c && nivPorId.get(c.nivel_id));
    const g = (c && grupos.get('c:' + c.id)) || (n && grupos.get('n:' + n.id)) || grupo('sin', '', '');
    g.fotos.push({ ...f, cuando: cuando(f), lectura: lect.get(f.id) || null });
  });
  const out = [...grupos.values()].filter(g => g.fotos.length); let k = 0;
  out.forEach(g => g.fotos.forEach(f => { f.num = ++k; }));
  return { grupos: out, total: k };
}
export const tituloGrupo = (g) => g.cuarto || (g.nivel ? 'Whole ' + g.nivel : 'No room');
// Floor Plan: la hoja más nueva de cada nivel, en el orden de los niveles del proyecto (la misma que se ve en Floor Plan).
export function modeloPlanos(niveles, lista){
  const ultimo = (nid) => (lista || []).filter(p => (p.nivel_id || null) === nid).sort((a, b) => String(b.created_at || '').localeCompare(String(a.created_at || '')))[0];
  const out = [];
  (niveles || []).forEach(n => { const p = ultimo(n.id); if(p) out.push({ nivel: n.nombre, plano: p }); });
  const suelto = ultimo(null); if(suelto) out.push({ nivel: (niveles || []).length ? 'No level' : 'Floor Plan', plano: suelto });
  return out;
}
export const REGLA_DIAS = 'Equipment days count every calendar day a unit was on site: from the day it was logged until the day it was logged as removed (the removal day is not counted). Days between visits keep the last count. Units still on site are counted through the report date.';

// ---------- estado y datos ----------
let MEDS = [], MNOTA = '', FOTS = [], PLANS = [], ELEGIDOS = null, LISTOS = null;
let T = null, NIVELES = [], CUARTOS = [], LECT = [], EQUI = [], CARGADO = null, VISTA = 'lista', OCUPADO = false, FRESCO = false, CARGANDO = false;
async function cargar(){
  if(!T || CARGANDO) return; const id = T.id; CARGANDO = true;
  try{ await cargarDe(id); }finally{ CARGANDO = false; }
}
async function cargarDe(id){
  const q = (t) => authFetch('/rest/v1/' + t + '?trabajo_id=eq.' + encodeURIComponent(id) + '&order=dia.asc,created_at.asc&limit=5000').then(r => r.ok ? r.json() : []).catch(() => []);
  const qm = (t, x) => authFetch('/rest/v1/' + t + '?trabajo_id=eq.' + encodeURIComponent(id) + x).then(r => r.ok ? r.json() : []).catch(() => []);
  const [l, e, md, mn, fo, pl] = await Promise.all([q('fotos_drylog_lecturas'), q('fotos_drylog_equipos'), qm('fotos_medidas', '&order=orden.asc,created_at.asc&limit=5000'), qm('fotos_medidas_notas', '&select=texto'),
    qm('fotos_fotos', '&estado=eq.activa&select=id,created_by,subida_at,tomada_at,ancho,alto,nota,nivel_id,cuarto_id&order=subida_at.asc&limit=2000'),
    qm('fotos_planos', '&borrado_at=is.null&select=id,nivel_id,created_at,data&order=created_at.desc&limit=60'), fotos.cargarNombres().catch(() => null)]);
  if(!T || T.id !== id) return;
  LECT = Array.isArray(l) ? l : []; EQUI = Array.isArray(e) ? e : []; MEDS = Array.isArray(md) ? md : []; MNOTA = (Array.isArray(mn) && mn[0] && mn[0].texto) || '';
  FOTS = Array.isArray(fo) ? fo : []; PLANS = Array.isArray(pl) ? pl : []; CARGADO = id; pintarAqui();
}
const caja = () => $('#panel-documentos');
export function pintar(t, niveles, cuartos){
  if(!t) return;
  if(!T || T.id !== t.id){ VISTA = 'lista'; CARGADO = null; LECT = []; EQUI = []; MEDS = []; MNOTA = ''; FOTS = []; PLANS = []; ELEGIDOS = null; LISTOS = null; }
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
  const mm = MD.agrupar(MEDS, NIVELES, CUARTOS), mf = modeloFotos(NIVELES, CUARTOS, FOTS, LECT), mp = modeloPlanos(NIVELES, PLANS);
  if(VISTA === 'medidas'){ c.innerHTML = vistaHtml('Measurements & Demo', htmlMedidas(mm, MNOTA), 'medidas'); return; }
  if(VISTA === 'fotos'){ c.innerHTML = vistaHtml('Photo Report', htmlFotos(mf), 'fotos'); ponerFotitos(c); return; }
  if(VISTA === 'plano'){ c.innerHTML = vistaHtml('', htmlPlano(mp), 'plano'); return; }
  const fila = (k, ic, titulo, sub, hay) => `<div class="doc-fila">
      <span class="doc-ic">${IC(ic)}</span>
      <div class="doc-txt"><b>${titulo}</b><small>${sub}</small></div>
      <div class="doc-acc"><button type="button" class="btn btn-outline btn-chico" data-doc-ver="${k}"${hay ? '' : ' disabled'}>View</button><button type="button" class="btn btn-accent btn-chico" data-doc-pdf="${k}"${hay ? '' : ' disabled'}>${IC('bajar')}PDF</button></div></div>`;
  const ps = partes(md, me, mm, mf, mp);
  if(!ELEGIDOS) ELEGIDOS = new Set(ps.filter(x => x.hay).map(x => x.k));
  const elegidas = ps.filter(x => x.hay && ELEGIDOS.has(x.k));
  const enviar = ps.some(x => x.hay) ? `<div class="doc-enviar">
      <h3>Send documents</h3>
      <p class="doc-nota">Pick what goes. <b>One PDF</b> puts them together with a cover page and contents; <b>Separate PDFs</b> makes one file for each.</p>
      <div class="doc-checks">${ps.map(x => `<label class="doc-check${x.hay ? '' : ' off'}"><input type="checkbox" data-doc-sel="${x.k}"${x.hay && ELEGIDOS.has(x.k) ? ' checked' : ''}${x.hay ? '' : ' disabled'}><span><b>${esc(x.titulo)}</b><small>${esc(x.hay ? x.sub : x.vacio)}</small></span></label>`).join('')}</div>
      <div class="doc-enviar-acc"><button type="button" class="btn btn-accent" data-doc-todo="uno"${elegidas.length ? '' : ' disabled'}>${IC('bajar')}One PDF</button><button type="button" class="btn btn-outline" data-doc-todo="varios"${elegidas.length ? '' : ' disabled'}>${IC('bajar')}Separate PDFs</button></div>
    </div>` : '';
  c.innerHTML = `<div class="card docs">
    <h2 class="sec-t">Documents</h2>
    <p class="doc-nota">Paperwork for this project, ready to send. It updates every time the crew adds a photo, a reading, equipment, a floor plan or a measurement.</p>
    ${fila('fotos', 'camara', 'Photo Report', mf.total ? `${mf.total} photo${mf.total === 1 ? '' : 's'} · ${mf.grupos.length} room${mf.grupos.length === 1 ? '' : 's'}` : 'No photos yet. They come from Photos.', mf.total > 0)}
    ${fila('plano', 'escanear', 'Floor Plan', mp.length ? mp.map(x => x.nivel).join(' · ') : 'No floor plan yet. It comes from Floor Plan.', mp.length > 0)}
    ${fila('dry', 'dl-hoja', 'Dry Log Report', md.total ? `${md.salas.length} room${md.salas.length === 1 ? '' : 's'} · ${md.total} reading${md.total === 1 ? '' : 's'} · ${md.dias.length} day${md.dias.length === 1 ? '' : 's'} (${esc(periodo(md.dias))})` : 'No readings yet. They come from Dry Logs.', md.total > 0)}
    ${fila('equipo', 'dl-herramientas', 'Equipment Report', me.resumen.length ? `${me.salas.length} room${me.salas.length === 1 ? '' : 's'} · ${me.total} equipment day${me.total === 1 ? '' : 's'} so far` : 'No equipment logged yet. It comes from Dry Logs.', me.resumen.length > 0)}
    ${fila('medidas', 'regla', 'Measurements &amp; Demo', mm.total ? `${mm.nCuartos} room${mm.nCuartos === 1 ? '' : 's'} · ${mm.total} measurement${mm.total === 1 ? '' : 's'}` : 'No measurements yet. They come from Measurements.', mm.total)}
    ${enviar}
    <p class="aviso" id="docAviso"></p>${listosHtml()}
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
// Lo que trae cada documento: su nombre, qué cuenta, si hay algo, cómo se llama el archivo y cómo se hace el PDF (solo o
// dentro del de todo junto). El orden es el de la lista y el del PDF de todo junto.
function partes(md, me, mm, mf, mp){
  const s = (n, una, varias) => n + ' ' + (n === 1 ? una : varias);
  return [
    { k: 'fotos', titulo: 'Photo Report', sub: s(mf.total, 'photo', 'photos'), vacio: 'No photos yet', hay: mf.total > 0, archivo: 'Photos', hacer: (o) => pdfFotos(mf, o) },
    { k: 'plano', titulo: 'Floor Plan', sub: mp.map(x => x.nivel).join(' · '), vacio: 'No floor plan yet', hay: mp.length > 0, archivo: 'FloorPlan', hacer: (o) => pdfPlano(mp, o) },
    { k: 'dry', titulo: 'Dry Log Report', sub: s(md.total, 'reading', 'readings'), vacio: 'No readings yet', hay: md.total > 0, archivo: 'DryLog', hacer: (o) => pdfDryLog(md, o) },
    { k: 'equipo', titulo: 'Equipment Report', sub: s(me.total, 'equipment day', 'equipment days'), vacio: 'No equipment yet', hay: me.resumen.length > 0, archivo: 'Equipment', hacer: (o) => pdfEquipo(me, o) },
    { k: 'medidas', titulo: 'Measurements & Demo', sub: s(mm.total, 'measurement', 'measurements'), vacio: 'No measurements yet', hay: mm.total > 0, archivo: 'Measurements', hacer: (o) => pdfMedidas(mm, MNOTA, o) },
  ];
}
function partesAhora(){
  const hoy = R.hoyLocal();
  return partes(modeloDryLog(NIVELES, CUARTOS, LECT, EQUI, hoy), modeloEquipo(NIVELES, CUARTOS, EQUI, hoy), MD.agrupar(MEDS, NIVELES, CUARTOS), modeloFotos(NIVELES, CUARTOS, FOTS, LECT), modeloPlanos(NIVELES, PLANS));
}
const fechaHoraEn = (iso) => { const d = new Date(iso); return isNaN(d) ? '' : d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) + ' ' + d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }); };
// Quién la tomó: el nombre de la persona (nunca el "Equipo" o "Usted" de la pantalla en español).
const quienFoto = (id) => { const n = fotos.nombreDe(id); return n === 'Equipo' || n === 'Usted' ? '' : n; };
const pieFoto = (f) => [quienFoto(f.created_by), f.lectura ? 'Moisture reading ' + fmt(f.lectura.valor) + '% · ' + puntoTxt(f.lectura) : '', f.nota || ''].filter(Boolean).join(' · ');
function htmlFotos(m){
  if(!m.total) return '<p class="vacio">No photos yet.</p>';
  return m.grupos.map(g => `<h3 class="doc-sala">${esc(tituloGrupo(g))}${g.nivel && g.cuarto ? ` <small>${esc(g.nivel)}</small>` : ''} <small>· ${g.fotos.length} photo${g.fotos.length === 1 ? '' : 's'}</small></h3>
    <div class="doc-fotos">${g.fotos.map(f => `<figure><img data-foto="${esc(f.id)}" alt=""><figcaption><b>#${f.num}</b> ${esc(fechaHoraEn(f.cuando))}${pieFoto(f) ? `<small>${esc(pieFoto(f))}</small>` : ''}</figcaption></figure>`).join('')}</div>`).join('')
    + '<p class="doc-sub">Room by room, in the order they were taken. The PDF has them larger.</p>';
}
function htmlPlano(lista){
  if(!lista.length) return '<p class="vacio">No floor plan yet.</p>';
  return lista.map(x => { let svg = ''; try{ svg = planos.svgDelPlano(x.plano.data, T); }catch(e){ svg = '<p class="aviso">Could not draw this plan. ' + esc(e && e.message || e) + '</p>'; }
    return `<h3 class="doc-sala">${esc(x.nivel)}</h3><div class="doc-plano">${svg}</div>`; }).join('');
}
// Si el teléfono ya no deja abrir la hoja de compartir sola (el PDF tardó y el toque "venció"), un botón para abrirla.
function listosHtml(){ return LISTOS ? `<div class="doc-listos"><span>${LISTOS.length === 1 ? 'The PDF is ready.' : LISTOS.length + ' PDFs are ready.'}</span><button type="button" class="btn btn-accent" data-doc-compartir>${IC('compartir')}Share</button></div>` : ''; }
// Measurements & Demo: por nivel y cuarto, una fila por material ya sumado (como el papel de Field Reports).
function htmlMedidas(g, nota){
  if(!g.total) return '<p class="vacio">No measurements yet.</p>';
  // Una línea por unidad: un drywall con SF y LF sale en dos renglones (como dos partidas de un estimado).
  const tabla = (filas, rooms) => `<div class="doc-tabla"><table><tr><th>Material</th><th>Surface</th><th>Qty</th><th>Unit</th>${rooms ? '<th>Rooms</th>' : ''}</tr>${filas.map(x => MD.lineasUnidad(x).map(l =>
    `<tr><td><b>${esc(x.material)}</b></td><td>${esc(x.superficie)}</td><td><b>${esc(l.qty)}</b></td><td>${esc(l.unidad)}</td>${rooms ? `<td>${l.cuartos}</td>` : ''}</tr>`).join('')).join('')}</table></div>`;
  return g.niveles.map(N => `<div class="dlr-nivel">${esc(N.titulo)}</div>${N.cuartos.map(C => `<h3 class="doc-sala">${esc(C.titulo)}</h3>${tabla(C.materiales)}`).join('')}`).join('')
    + (g.nCuartos > 1 && g.partidas.length ? `<h3 class="doc-sala">Job totals by line item</h3>${tabla(g.partidas, true)}` : '')
    + (nota ? `<h3 class="doc-sala">Notes</h3><p class="doc-sub doc-nota">${esc(nota)}</p>` : '')
    + '<p class="doc-sub">SF = square feet, LF = linear feet, EA = each. Different units are never added together.</p>';
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
function tablaPdf(doc, y, cols, filas, titulo, cabeceraHoja, opc){
  const H = doc.internal.pageSize.getHeight(), M = 36, rh = 18, fondoMax = H - M - 20;
  const dibCab = () => { doc.setFillColor(...FONDO); doc.rect(M, y, cols.reduce((a, c) => a + c.w, 0), rh + 4, 'F');
    let x = M; doc.setFont('helvetica', 'bold'); doc.setFontSize(8.5); doc.setTextColor(...TINTA);
    cols.forEach(c => { const l = String(c.t).split('\n'); doc.text(l[0], c.der ? x + c.w - 5 : x + 5, y + 10, { align: c.der ? 'right' : 'left' });
      if(l[1]){ doc.setFont('helvetica', 'normal'); doc.setTextColor(...SUAVE); doc.text(l[1], c.der ? x + c.w - 5 : x + 5, y + 19, { align: c.der ? 'right' : 'left' }); doc.setFont('helvetica', 'bold'); doc.setTextColor(...TINTA); }
      x += c.w; }); y += rh + 6; };
  if(y + 28 + rh * Math.min(2, filas.length) > fondoMax){ hojaNueva(doc); y = cabeceraHoja(); }
  if(titulo){ doc.setFont('helvetica', 'bold'); doc.setFontSize(12); doc.setTextColor(...TINTA); doc.text(titulo[0], M, y + 4);
    if(titulo[1]){ const w = doc.getTextWidth(titulo[0] + '  '); doc.setFont('helvetica', 'normal'); doc.setFontSize(9.5); doc.setTextColor(...SUAVE); doc.text(titulo[1], M + w, y + 4); } y += 12; }
  dibCab();
  filas.forEach((f, i) => {
    if(y + rh > fondoMax){ hojaNueva(doc); y = cabeceraHoja();
      if(opc && opc.cont && titulo){ doc.setFont('helvetica', 'bold'); doc.setFontSize(12); doc.setTextColor(...TINTA); doc.text(titulo[0] + ' (cont.)', M, y + 4); y += 12; }
      dibCab(); }
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
  if(y + l.length * 11 > H - M - 20){ hojaNueva(doc); y = cabeceraHoja(); }
  doc.text(l, M, y); return y + l.length * 11 + 8;
}
// Abrir el reporte: su propio PDF, o la parte que le toca dentro del PDF con todo junto (opc.doc).
async function abrirDoc(opc, orient){
  if(opc && opc.doc){ const d = opc.doc; d.__orient = orient; d.addPage('letter', orient); return d; }
  const Pdf = await cargarJsPDF(), d = new Pdf({ unit: 'pt', format: 'letter', orientation: orient }); d.__orient = orient; return d;
}
// jsPDF, sin decirle nada, hace la hoja nueva como la PRIMERA del documento: hay que decirle la de este reporte.
function hojaNueva(doc){ doc.addPage('letter', doc.__orient || 'portrait'); }
// Cerrar el reporte: si va solo, su pie y el archivo; si va dentro del de todo junto, el pie lo pone el de todo junto.
const cerrarDoc = (doc, opc, titulo) => { if(opc && opc.doc) return doc; piePdf(doc, titulo); return doc.output('blob'); };
// La letra del PDF (Helvetica) solo trae las letras del español y el inglés: un emoji o un símbolo raro salía como basura.
const pdfTxt = (s) => String(s == null ? '' : s).replace(/[\u2018\u2019]/g, "'").replace(/[\u201C\u201D]/g, '"').replace(/[\u2013\u2014]/g, '-').replace(/\u2026/g, '...').replace(/[^\x09\x0A\x0D\x20-\x7E\xA0-\xFF]/g, '');
function piePdf(doc, titulo){
  const n = doc.getNumberOfPages(), W = doc.internal.pageSize.getWidth(), H = doc.internal.pageSize.getHeight();
  for(let i = 1; i <= n; i++){ doc.setPage(i); doc.setFont('helvetica', 'normal'); doc.setFontSize(8); doc.setTextColor(...SUAVE);
    doc.text('Scanova360 · ' + titulo + ' · ' + (T.cliente || ''), 36, H - 22); doc.text('Page ' + i + ' of ' + n, W - 36, H - 22, { align: 'right' }); }
}
// Las columnas de días caben de 9 en 9 en la hoja acostada; si hay más días, la tabla sigue en otra con los siguientes.
const TROZO = 9;
const trozos = (dias) => { const out = []; for(let i = 0; i < Math.max(1, dias.length); i += TROZO) out.push([i, Math.min(dias.length, i + TROZO)]); return out; };
const colorTend = (t) => t ? (t.tipo === 'baja' ? AZUL : t.tipo === 'sube' ? AMBAR : TINTA) : TINTA;
// Una foto achicada para el PDF (JPEG). Si el navegador no la sabe abrir como ImageBitmap, se abre como imagen normal.
async function fotoParaPdf(url, lado = 520){
  const b = await (await fetch(url, { cache: 'no-store' })).blob();
  let im, cerrar = () => {};
  try{ im = await createImageBitmap(b); cerrar = () => { if(im.close) im.close(); }; }
  catch{ const u = URL.createObjectURL(b); cerrar = () => URL.revokeObjectURL(u);
    try{ im = await new Promise((ok, no) => { const i = new Image(); i.onload = () => ok(i); i.onerror = () => no(new Error('could not open the photo')); i.src = u; }); }catch(e){ cerrar(); throw e; } }
  const iw = im.width || im.naturalWidth, ih = im.height || im.naturalHeight;
  if(!iw || !ih){ cerrar(); throw new Error('empty photo'); }
  const k = Math.min(1, lado / Math.max(iw, ih)), w = Math.max(1, Math.round(iw * k)), h = Math.max(1, Math.round(ih * k));
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  const g = c.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, w, h); g.drawImage(im, 0, 0, w, h);
  const d = c.toDataURL('image/jpeg', 0.78); c.width = c.height = 0; cerrar();
  return { d, w, h };
}
const hex = (h) => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
// Su estilo (14-oct, "Daily Drying Log"): hoja parada; Scanova360 arriba, el título grande, los datos del trabajo, la
// gráfica "Moisture Trend", las tablas por nivel con la foto de cada punto (P-001…), el equipo y las notas abajo; al
// final las fotos grandes con el mismo número.
export async function pdfDryLog(m, opc = {}){
  if(typeof opc === 'boolean') opc = { conFotos: opc };
  const conFotos = opc.conFotos !== false, doc = await abrirDoc(opc, 'portrait');
  const W = doc.internal.pageSize.getWidth(), H = doc.internal.pageSize.getHeight(), M = 40, A = W - 2 * M, ABAJO = H - M - 24;
  // Las fotos (la chiquita de cada punto y las grandes del final) se bajan una vez.
  const ids = [...new Set([...m.salas.flatMap(sa => sa.puntos.map(p => p.foto_id)), ...m.lecturasFoto.map(f => f.foto_id)].filter(Boolean))];
  let urls = {}; if(ids.length){ try{ urls = await fotos.urlsFirmadas(ids, 'web'); }catch{} }
  const imgs = {}; for(const id of ids.slice(0, 120)){ if(urls[id]){ try{ imgs[id] = await fotoParaPdf(urls[id]); }catch{} } }
  const marca = (y) => { doc.setFont('helvetica', 'bold'); doc.setFontSize(19); doc.setTextColor(...TINTA); doc.text('Scanova', M, y);
    doc.setTextColor(...AZUL); doc.text('360', M + doc.getTextWidth('Scanova'), y);
    doc.setFontSize(12); doc.setTextColor(...SUAVE); doc.text(R.fechaLarga(R.hoyLocal()), W - M, y, { align: 'right' });
    doc.setDrawColor(...LINEA); doc.setLineWidth(1); doc.line(M, y + 10, W - M, y + 10); return y + 22; };
  const hoja = () => { hojaNueva(doc); return marca(M + 14); };
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
  return cerrarDoc(doc, opc, 'Daily Drying Log');
}
export async function pdfEquipo(m, opc = {}){
  const doc = await abrirDoc(opc, 'landscape'), TIT = 'Equipment Report';
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
  return cerrarDoc(doc, opc, TIT);
}
// Measurements & Demo: hoja parada, un bloque por cuarto (Material · Surface · Qty · Unit), el total por partida y las notas.
export async function pdfMedidas(g, nota, opc = {}){
  const doc = await abrirDoc(opc, 'portrait'), TIT = 'Measurements & Demo';
  const W = doc.internal.pageSize.getWidth(), M = 36, A = W - 2 * M, cabH = () => hojaPdf(doc, TIT, false);
  let y = hojaPdf(doc, TIT, true);
  const cols = (rooms) => [{ t: 'Material', w: A - 90 - 70 - 70 - (rooms ? 60 : 0) }, { t: 'Surface', w: 90 }, { t: 'Qty', w: 70, der: true }, { t: 'Unit', w: 70 }, ...(rooms ? [{ t: 'Rooms', w: 60, der: true }] : [])];
  // Una línea por unidad (SF, LF, EA): nunca "35.5 SF +" cortado con el LF perdido.
  const filas = (lista, rooms) => lista.flatMap(x => MD.lineasUnidad(x).map(l => [{ t: x.material, b: true }, { t: x.superficie, color: SUAVE }, { t: l.qty, b: true }, l.unidad, ...(rooms ? [String(l.cuartos)] : [])]));
  // Como en Field Reports: un cuarto no se parte entre hojas, y el título de un nivel no se queda solo al pie.
  // Lo que mide un cuarto en el papel (título, cabecera, renglones y su aire) y lo que cabe en una hoja limpia (debajo
  // del encabezado de hojaPdf, que en las hojas que siguen termina en y = 70).
  const H = doc.internal.pageSize.getHeight(), fondo = H - M - 20, alto = (n) => 12 + 24 + 18 * n + 14, libre = fondo - 70;
  const cabe = (necesita) => { if(y + necesita > fondo && necesita <= libre){ hojaNueva(doc); y = cabH(); } };
  for(const N of g.niveles){
    const primero = N.cuartos[0] ? alto(filas(N.cuartos[0].materiales, false).length) : 0;
    cabe(26 + primero);
    doc.setFont('helvetica', 'bold'); doc.setFontSize(13); doc.setTextColor(...AZUL); doc.text(String(N.titulo).toUpperCase(), M, y + 6);
    doc.setDrawColor(...LINEA); doc.setLineWidth(1); doc.line(M, y + 12, W - M, y + 12); y += 26;
    for(const C of N.cuartos){ const f = filas(C.materiales, false); cabe(alto(f.length)); y = tablaPdf(doc, y, cols(false), f, [C.titulo, ''], cabH, { cont: true }); }
  }
  if(g.nCuartos > 1 && g.partidas.length){ const f = filas(g.partidas, true); cabe(6 + alto(Math.min(f.length, 6))); y = tablaPdf(doc, y + 6, cols(true), f, ['Job totals by line item', 'all rooms'], cabH, { cont: true }); }
  if(nota){
    doc.setFont('helvetica', 'normal'); doc.setFontSize(9.5);
    const lineas = doc.splitTextToSize(pdfTxt(nota), A); cabe(18 + 12 * Math.min(lineas.length, 4));
    doc.setFont('helvetica', 'bold'); doc.setFontSize(12); doc.setTextColor(...TINTA); doc.text('Notes', M, y + 4); y += 18;
    // Renglón por renglón: unas notas largas siguen en la hoja siguiente en vez de salirse del papel.
    doc.setFont('helvetica', 'normal'); doc.setFontSize(9.5); doc.setTextColor(...TINTA);
    for(const l of lineas){ if(y + 12 > fondo){ hojaNueva(doc); y = cabH(); doc.setFont('helvetica', 'normal'); doc.setFontSize(9.5); doc.setTextColor(...TINTA); } doc.text(l, M, y); y += 12; }
    y += 8;
  }
  parrafoPdf(doc, y + 4, 'SF = square feet, LF = linear feet, EA = each. Different units are never added together.', cabH);
  return cerrarDoc(doc, opc, TIT);
}
// Photo Report: hoja parada, dos fotos por renglón y tres renglones por hoja, cuarto por cuarto. Debajo de cada foto su
// número, fecha y hora, quién la tomó y su nota. Las fotos se bajan una por una (en el teléfono no caben todas a la vez).
export async function pdfFotos(m, opc = {}){
  const doc = await abrirDoc(opc, 'portrait'), TIT = 'Photo Report';
  const W = doc.internal.pageSize.getWidth(), H = doc.internal.pageSize.getHeight(), M = 36, A = W - 2 * M, fondo = H - M - 20, cabH = () => hojaPdf(doc, TIT, false);
  const todas = m.grupos.flatMap(g => g.fotos);
  let urls = {}; if(todas.length){ try{ urls = await fotos.urlsFirmadas(todas.map(f => f.id), 'web'); }catch{} }
  const GAP = 14, cw = (A - GAP) / 2, ch = Math.round(cw * 0.68), filaH = ch + 40;
  let y = hojaPdf(doc, TIT, true), hechas = 0, faltan = 0;
  for(const g of m.grupos){
    if(y + 24 + filaH > fondo){ hojaNueva(doc); y = cabH(); }
    const tit = pdfTxt(tituloGrupo(g));
    doc.setFont('helvetica', 'bold'); doc.setFontSize(12); doc.setTextColor(...TINTA); doc.text(tit, M, y + 4); const wt = doc.getTextWidth(tit);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(9.5); doc.setTextColor(...SUAVE);
    doc.text((g.nivel && g.cuarto ? pdfTxt(g.nivel) + ' · ' : '') + g.fotos.length + (g.fotos.length === 1 ? ' photo' : ' photos'), M + wt + 10, y + 4);
    doc.setDrawColor(...LINEA); doc.setLineWidth(0.8); doc.line(M, y + 10, W - M, y + 10); y += 22;
    for(let i = 0; i < g.fotos.length; i++){
      const f = g.fotos[i], col = i % 2;
      if(col === 0 && i) y += filaH;
      if(col === 0 && y + filaH > fondo){ hojaNueva(doc); y = cabH(); }
      const x = M + col * (cw + GAP);
      if(opc.avance) opc.avance(++hechas, todas.length);
      let im = null; if(urls[f.id]){ try{ im = await fotoParaPdf(urls[f.id], 1100); }catch{} }
      doc.setFillColor(...FONDO); doc.rect(x, y, cw, ch, 'F');
      if(im){ const k = Math.min(cw / im.w, ch / im.h); doc.addImage(im.d, 'JPEG', x + (cw - im.w * k) / 2, y + (ch - im.h * k) / 2, im.w * k, im.h * k); }
      else { faltan++; doc.setFont('helvetica', 'normal'); doc.setFontSize(9); doc.setTextColor(...SUAVE); doc.text('Photo not available', x + cw / 2, y + ch / 2, { align: 'center' }); }
      doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(...TINTA); doc.text('#' + f.num, x, y + ch + 12);
      const wn = doc.getTextWidth('#' + f.num + '  ');
      doc.setFont('helvetica', 'normal'); doc.setTextColor(...SUAVE); doc.text(fechaHoraEn(f.cuando), x + wn, y + ch + 12);
      const pie = pdfTxt(pieFoto(f));
      if(pie){ doc.setFontSize(8.5); doc.setTextColor(...TINTA); doc.text(doc.splitTextToSize(pie, cw).slice(0, 2), x, y + ch + 24); }
    }
    y += filaH + 8;
  }
  if(faltan) parrafoPdf(doc, y, faltan + (faltan === 1 ? ' photo' : ' photos') + ' could not be downloaded (no internet?). Make the PDF again to include ' + (faltan === 1 ? 'it' : 'them') + '.', cabH);
  return cerrarDoc(doc, opc, TIT);
}
// Floor Plan: una hoja por nivel, la misma hoja que exporta la pestaña Floor Plan (con su encabezado y su tabla de
// medidas), acostada o parada según el dibujo.
export async function pdfPlano(lista, opc = {}){
  if(!lista.length) throw new Error('there is no floor plan yet');
  let doc = null, i = 0;
  for(const x of lista){
    if(opc.avance) opc.avance(++i, lista.length);
    const c = await planos.lienzoDelPlano(x.plano.data, T, 2600), w = c.width, h = c.height, orient = w >= h ? 'landscape' : 'portrait';
    if(!doc) doc = await abrirDoc(opc, orient); else { doc.__orient = orient; hojaNueva(doc); }
    const W = doc.internal.pageSize.getWidth(), H = doc.internal.pageSize.getHeight(), M = 28, k = Math.min((W - 2 * M) / w, (H - M - 40) / h);
    const d = c.toDataURL('image/jpeg', 0.95); c.width = c.height = 0;
    doc.addImage(d, 'JPEG', (W - w * k) / 2, M, w * k, h * k);
  }
  return cerrarDoc(doc, opc, 'Floor Plan');
}
// TODO JUNTO (su pedido: "si cualquier compañía quisiera tener todos sus documentos juntos"): una portada con el
// proyecto y el índice (cada documento con la hoja donde empieza), y después cada documento con su propio encabezado.
// El pie de cada hoja dice de qué documento es y "Page N of M" del archivo entero.
export async function pdfTodo(lista, opc = {}){
  const doc = await abrirDoc({}, 'portrait'), secciones = [];
  for(const p of lista){
    const desde = doc.getNumberOfPages() + 1;
    await p.hacer({ doc, avance: opc.avance ? (i, n) => opc.avance(p.titulo, i, n) : null });
    secciones.push({ titulo: p.titulo, sub: p.sub, desde, hasta: doc.getNumberOfPages() });
  }
  doc.setPage(1); portadaPdf(doc, secciones);
  const n = doc.getNumberOfPages();
  for(let i = 1; i <= n; i++){
    doc.setPage(i); const W = doc.internal.pageSize.getWidth(), H = doc.internal.pageSize.getHeight(), sec = secciones.find(x => i >= x.desde && i <= x.hasta);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8); doc.setTextColor(...SUAVE);
    doc.text(pdfTxt('Scanova360 · ' + (sec ? sec.titulo : 'Project Documents') + ' · ' + (T.cliente || '')), 36, H - 22); doc.text('Page ' + i + ' of ' + n, W - 36, H - 22, { align: 'right' });
  }
  return doc.output('blob');
}
function portadaPdf(doc, secciones){
  const W = doc.internal.pageSize.getWidth(), M = 48, A = W - 2 * M;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(30); doc.setTextColor(...TINTA); doc.text('Scanova', M, 92);
  doc.setTextColor(...AZUL); doc.text('360', M + doc.getTextWidth('Scanova'), 92);
  doc.setDrawColor(...AZUL); doc.setLineWidth(2.5); doc.line(M, 108, W - M, 108);
  doc.setFontSize(12); doc.setTextColor(...SUAVE); doc.text('PROJECT DOCUMENTS', M, 150);
  doc.setFontSize(28); doc.setTextColor(...TINTA); doc.text(doc.splitTextToSize(pdfTxt(T.cliente || 'Project'), A).slice(0, 2), M, 184);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(13); doc.setTextColor(...TINTA); doc.text(doc.splitTextToSize(pdfTxt(T.direccion || ''), A).slice(0, 2), M, 214);
  const datos = [['Project manager', T.encargado || '—'], ['Report date', R.fechaLarga(R.hoyLocal())], ['Documents', String(secciones.length)]];
  datos.forEach(([k, v], i) => { const x = M + i * (A / 3);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); doc.setTextColor(...SUAVE); doc.text(k.toUpperCase(), x, 262);
    doc.setFont('helvetica', 'bold'); doc.setFontSize(12); doc.setTextColor(...TINTA); doc.text(pdfTxt(v), x, 279); });
  let y = 330;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(14); doc.setTextColor(...TINTA); doc.text('Contents', M, y); y += 14;
  secciones.forEach((sx, i) => {
    doc.setDrawColor(...LINEA); doc.setLineWidth(0.6); doc.line(M, y, W - M, y); y += 22;
    doc.setFont('helvetica', 'bold'); doc.setFontSize(11); doc.setTextColor(...AZUL); doc.text(String(i + 1), M, y);
    doc.setTextColor(...TINTA); doc.text(pdfTxt(sx.titulo), M + 22, y);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(9.5); doc.setTextColor(...SUAVE); doc.text(pdfTxt(sx.sub || ''), M + 22, y + 13);
    doc.setFont('helvetica', 'bold'); doc.setFontSize(11); doc.setTextColor(...TINTA); doc.text('Page ' + sx.desde, W - M, y, { align: 'right' });
    y += 24;
  });
  doc.setDrawColor(...LINEA); doc.line(M, y, W - M, y);
}
// El botón PDF de la pestaña Measurements: lo mismo que Documents, con lo que esa pestaña ya tiene cargado.
export async function pdfDeMedidas(t, niveles, cuartos, filas, nota){
  if(OCUPADO) throw new Error('another PDF is being made'); OCUPADO = true;
  try{
    T = t; NIVELES = niveles || []; CUARTOS = cuartos || [];
    const blob = await pdfMedidas(MD.agrupar(filas, NIVELES, CUARTOS), nota);
    const nombre = ('Measurements ' + (T.cliente || 'Project') + ' ' + R.hoyLocal()).replace(/[^\w\- ]+/g, '').trim().replace(/\s+/g, '_') + '.pdf';
    return { r: await entregar(blob, nombre), nombre };
  }finally{ OCUPADO = false; }
}
// Bajar / compartir el PDF (como el plano: en el teléfono la hoja de compartir; en la compu, a Descargas).
async function entregar(blob, nombre){
  const archivo = new File([blob], nombre, { type: 'application/pdf' });
  const tel = esAparato() || /iPhone|iPad|Android/i.test(navigator.userAgent);
  if(tel && navigator.canShare && navigator.canShare({ files: [archivo] })){ await navigator.share({ files: [archivo], title: nombre }); return 'shared'; }
  const u = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = u; a.download = nombre; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(u), 4000);
  return 'downloaded';
}
// Varios archivos de una vez: en el teléfono, UNA hoja de compartir con todos; en la compu, a Descargas uno tras otro.
async function entregarArchivos(lista){
  const files = lista.map(a => new File([a.blob], a.nombre, { type: 'application/pdf' }));
  const tel = esAparato() || /iPhone|iPad|Android/i.test(navigator.userAgent);
  if(tel && navigator.canShare && navigator.canShare({ files })){
    try{ await navigator.share({ files, title: files.length === 1 ? files[0].name : 'Project documents' }); return 'shared'; }
    // Si el PDF tardó, el teléfono ya no deja abrir la hoja sola: queda un botón "Share" para tocarlo.
    catch(e){ if(e && e.name === 'NotAllowedError'){ LISTOS = files; return 'tocar'; } throw e; }
  }
  for(const a of lista){ const u = URL.createObjectURL(a.blob); const x = document.createElement('a'); x.href = u; x.download = a.nombre; document.body.appendChild(x); x.click(); x.remove(); setTimeout(() => URL.revokeObjectURL(u), 4000); await new Promise(r => setTimeout(r, 450)); }
  return 'downloaded';
}
const nombreArchivo = (base) => (base + ' ' + (T.cliente || 'Project') + ' ' + R.hoyLocal()).replace(/[^\w\- ]+/g, '').trim().replace(/\s+/g, '_') + '.pdf';
const avisar = (t, bien) => { const a = $('#docAviso'); if(a){ a.className = 'aviso' + (bien ? ' ok' : ''); a.textContent = t; } };
async function hacerPdf(k){
  if(OCUPADO || !T) return; OCUPADO = true;
  const b = document.querySelector('[data-doc-pdf="' + k + '"]'); const antes = b ? b.innerHTML : ''; if(b){ b.disabled = true; b.textContent = 'Making PDF…'; }
  try{
    const p = partesAhora().find(x => x.k === k); if(!p) return;
    const blob = await p.hacer({ avance: (i, n) => { if(n > 1) avisar('Making the ' + p.titulo + '… ' + i + ' of ' + n, true); } });
    const nombre = nombreArchivo(p.archivo);
    const r = await entregarArchivos([{ blob, nombre }]);
    avisar(r === 'downloaded' ? 'Downloaded ' + nombre : '', true); if(r === 'tocar') pintarAqui();
  }catch(e){ if(!(e && e.name === 'AbortError')) avisar('Could not make the PDF. ' + String(e && e.message || e)); }
  finally{ OCUPADO = false; const b2 = document.querySelector('[data-doc-pdf="' + k + '"]'); if(b2){ b2.disabled = false; b2.innerHTML = antes || 'PDF'; } }
}
// Mandar lo escogido: todo en un PDF (con portada) o un PDF por documento.
async function enviarTodo(modo){
  if(OCUPADO || !T) return;
  const lista = partesAhora().filter(x => x.hay && ELEGIDOS && ELEGIDOS.has(x.k)); if(!lista.length) return;
  OCUPADO = true; LISTOS = null; document.querySelectorAll('[data-doc-todo]').forEach(b => { b.disabled = true; });
  const avance = (tit, i, n) => avisar('Making the ' + tit + '…' + (n > 1 ? ' ' + i + ' of ' + n : ''), true);
  try{
    let archivos;
    if(modo === 'uno' && lista.length > 1){ avisar('Making one PDF with ' + lista.length + ' documents…', true); archivos = [{ blob: await pdfTodo(lista, { avance }), nombre: nombreArchivo('Documents') }]; }
    else { archivos = []; for(const p of lista){ avance(p.titulo, 0, 0); archivos.push({ blob: await p.hacer({ avance: (i, n) => avance(p.titulo, i, n) }), nombre: nombreArchivo(p.archivo) }); } }
    const r = await entregarArchivos(archivos);
    avisar(r === 'downloaded' ? 'Downloaded ' + archivos.map(a => a.nombre).join(', ') : '', true);
    if(r === 'tocar') pintarAqui();
  }catch(e){ if(!(e && e.name === 'AbortError')) avisar('Could not make the PDF. ' + String(e && e.message || e)); }
  finally{ OCUPADO = false; document.querySelectorAll('[data-doc-todo]').forEach(b => { b.disabled = !(ELEGIDOS && ELEGIDOS.size); }); }
}
export function conectar(){
  document.addEventListener('change', (e) => {
    const el = e.target.closest && e.target.closest('[data-doc-sel]'); if(!el || !ELEGIDOS) return;
    if(el.checked) ELEGIDOS.add(el.dataset.docSel); else ELEGIDOS.delete(el.dataset.docSel);
    document.querySelectorAll('[data-doc-todo]').forEach(b => { b.disabled = OCUPADO || !ELEGIDOS.size; });
  });
  document.addEventListener('click', (e) => {
    const c = caja(); if(!c || !c.contains(e.target)) return;
    const q = (s) => e.target.closest(s); let el;
    if((el = q('[data-doc-todo]'))){ enviarTodo(el.dataset.docTodo); return; }
    if(q('[data-doc-compartir]')){ const files = LISTOS; if(!files) return;
      navigator.share({ files, title: files.length === 1 ? files[0].name : 'Project documents' }).then(() => { LISTOS = null; pintarAqui(); }).catch(err => { if(!(err && err.name === 'AbortError')) avisar('Could not open the share sheet. ' + String(err && err.message || err)); });
      return; }
    if((el = q('[data-doc-ver]'))){ VISTA = el.dataset.docVer; pintarAqui(); const m = $('#main'); if(m) m.scrollTop = Math.max(0, c.getBoundingClientRect().top - m.getBoundingClientRect().top + m.scrollTop - 8); return; }
    if(q('[data-doc-volver]')){ VISTA = 'lista'; pintarAqui(); return; }
    if((el = q('[data-doc-pdf]'))){ hacerPdf(el.dataset.docPdf); return; }
  });
}
