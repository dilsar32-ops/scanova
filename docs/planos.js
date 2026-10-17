// Scanova360 · pestaña Floor Plan (su diseño del 13-oct). El plano se escanea con el LiDAR del iPhone
// (el mismo escáner de Field Reports, que ya viene dentro de la app: plugin RoomScan) y se dibuja con el
// mismo código de Field Reports (plano.js, copiado por tools/extraer_plano.py). Un escaneo por piso;
// un escaneo nuevo no borra el anterior (queda de historial), se ve el más reciente.
import * as plano from './plano.js?v=2026-10-17-5';
import { authFetch, esAparato, esManager, preguntar, desfaseDelReloj } from './app.js?v=2026-10-17-5';

const $ = (s, r = document) => r.querySelector(s);
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
const IC = (n, cls) => '<svg class="ic' + (cls ? ' ' + cls : '') + '"><use href="#i-' + n + '"/></svg>';
const SIN_NIVEL = 'sin';
const PLANTAS = ['Basement', '1st Floor', '2nd Floor', '3rd Floor', 'Attic'];

let PL_CERRADO = false;   // teléfono: todos los niveles cerrados (se ven solo sus tarjetas)
let T = null, CUARTOS_P = [], NIVELES = [], PLANOS = [], NIV_SEL = null, VISTA = '2d', REJILLA = true, ZOOM = 1, CARGADO = '', AVISO = '', AVISO_OK = false, OCUPADO = false, AL_NIVEL = null, MENU = false;
const PZ = { s: 1, x: 0, y: 0 }, PZ_GRANDE = { s: 1, x: 0, y: 0 };   // acercamiento con los dedos (teléfono)

// ---------- puras (para las pruebas) ----------
export const fmtPies = (n) => (Math.round(Number(n) || 0)).toLocaleString('en-US');
// El nivel que se dibuja de este plano: el que trae marcado (un escaneo con dos niveles se guarda partido, una
// fila por nivel) o el primero. El resumen cuenta SOLO ese nivel: antes el dibujo enseñaba el primero y el total
// sumaba todos.
export function nivelDelPlano(data){
  if(data && data._nivel != null) return data._nivel;
  const lv = plano.floorplanLevels(data); return lv && lv.length ? lv[0] : 1;
}
export function resumenPlano(data){
  data = prepararPlano(data);
  const nivel = nivelDelPlano(data), enNivel = r => (r.level || 1) === nivel;
  const rooms = ((data && data.rooms) || []).filter(r => !r.deleted && (r.walls || []).length && enNivel(r));
  if(!rooms.length) return { area: 0, cuartos: 0, murosExt: 0, techo: 0 };
  const m = plano.fpPlanMeasurements(data, enNivel);
  // Paredes exteriores: los tramos que caen en la misma línea se juntan (dos cuartos con copia de la misma pared
  // exterior la contaban dos veces) y las paredes ajenas no cuentan.
  const tramos = [];
  rooms.forEach(r => (r.walls || []).forEach(w => { if(w && w.start && w.end && !w._ajena && plano.floorplanIsExteriorWall(w, r, data.merged === false ? null : rooms)) tramos.push(w); }));
  const ext = data.merged === false ? tramos.reduce((t, w) => t + Math.hypot(w.end.x - w.start.x, w.end.y - w.start.y), 0) : largoSinRepetir(tramos);
  // La altura que más área cubre (no el promedio: una pared bajita no baja todo el piso), a la pulgada, igual que
  // la hoja (antes se redondeaba a cuartos de pie y Plan Details decía otra cosa que la hoja).
  const peso = {}; rooms.forEach(r => { const x = plano.fpRoomMeasurements(r); const h = Math.round((x.wallHeightFt || 0) * 12) / 12; if(h > 0) peso[h] = (peso[h] || 0) + (x.floorSqFt || 1); });
  const techo = Number(Object.keys(peso).sort((a, b) => peso[b] - peso[a])[0] || 0);
  return { area: Math.round((m.floorSqFt || 0) * 10) / 10, cuartos: m.rooms, murosExt: Math.round(ext), techo };
}
// El largo de varias paredes contando una sola vez lo que se repite en la misma línea (0.5 ft de tolerancia).
export function largoSinRepetir(paredes){
  const grupos = [];
  paredes.forEach(w => {
    const dx = w.end.x - w.start.x, dy = w.end.y - w.start.y, L = Math.hypot(dx, dy);
    if(L < 0.05) return;
    const ux = dx / L, uy = dy / L;
    let g = grupos.find(G => Math.abs(G.ux * ux + G.uy * uy) > 0.996 && Math.abs((w.start.x - G.x0) * -G.uy + (w.start.y - G.y0) * G.ux) < 0.5 && Math.abs((w.end.x - G.x0) * -G.uy + (w.end.y - G.y0) * G.ux) < 0.5);
    if(!g){ g = { ux, uy, x0: w.start.x, y0: w.start.y, tr: [] }; grupos.push(g); }
    const t0 = (w.start.x - g.x0) * g.ux + (w.start.y - g.y0) * g.uy, t1 = (w.end.x - g.x0) * g.ux + (w.end.y - g.y0) * g.uy;
    g.tr.push([Math.min(t0, t1), Math.max(t0, t1)]);
  });
  let total = 0;
  grupos.forEach(g => { g.tr.sort((a, b) => a[0] - b[0]); let [a, b] = g.tr[0]; for(let i = 1; i < g.tr.length; i++){ const [c, d] = g.tr[i]; if(c <= b + 0.5) b = Math.max(b, d); else { total += b - a; a = c; b = d; } } total += b - a; });
  return total;
}
// LAS PAREDES DE CADA CUARTO PARA LA CÁMARA DE MEDIR (su pedido del 15-oct: "si estamos en paredes interiores ya sabe
// que no llevan insulación"). El GPS del teléfono no alcanza para saber junto a qué pared está; el plano sí sabe qué
// paredes son de afuera y cuánto mide cada una. La cámara compara lo medido contra esto y SUGIERE (nunca marca sola).
// Una puerta, ventana o paso del plano como lo lee la cámara de medir: [x, y, ventana (1/0), ancho, abajo (-1 = no se sabe), alto].
// Un PASO SIN PUERTA (arco, 16-oct) lleva un 7o número 1: los aparatos viejos lo leen como puerta (se resta igual), los nuevos lo
// nombran "opening". Un paso que en el plano se corrigió a puerta o ventana (_kindOverride) va como lo que se dijo, igual que el
// PDF (fpRoomMeasurements). Uno quitado (_removed) no va.
export function senaParaCamara(x, k){
  if(!x || !x.position || x._removed) return null;
  const tipo = k === 'openings' ? (x._kindOverride || 'opening') : (k === 'windows' ? 'window' : 'door');
  const r2 = v => Math.round(v * 100) / 100;
  const an = Number(x._widthOverrideFt || x.widthFt) || 0, al = Number(x._heightOverrideFt || x.heightFt) || 0, ab = x.bottomFt == null ? -1 : Number(x.bottomFt);
  const s = [r2(x.position.x), r2(x.position.y), tipo === 'window' ? 1 : 0, r2(an), r2(ab), r2(al)];
  if(tipo === 'opening') s.push(1);
  return s;
}
export async function paredesParaCamara(trabajoId, nivelId){
  FORMAS = {};   // nunca la forma de otro proyecto o de otro piso
  try{
    const r = await authFetch('/rest/v1/fotos_planos?trabajo_id=eq.' + encodeURIComponent(trabajoId) + '&borrado_at=is.null&select=id,nivel_id,created_at,data&order=created_at.desc&limit=60');
    if(!r.ok) return {};
    const lista = await r.json();
    const p = planoDe(lista, nivelId) || (nivelId ? null : lista[0]);
    if(!p || !p.data) return {};
    const d = prepararPlano(p.data);
    const nivel = nivelDelPlano(d);
    const rooms = (d.rooms || []).filter(x => !x.deleted && (x.walls || []).length && (x.level || 1) === nivel);
    const out = {};
    rooms.forEach(room => {
      const nombre = String(room.roomName || '').trim(); if(!nombre) return;
      const paredes = (room.walls || []).filter(w => w && w.start && w.end && !w._ajena)
        .map(w => ({ largo: Math.round(Math.hypot(w.end.x - w.start.x, w.end.y - w.start.y) * 100) / 100,
                     exterior: !!plano.floorplanIsExteriorWall(w, room, d.merged === false ? null : rooms) }))
        .filter(x => x.largo >= 1);
      if(paredes.length) out[nombre] = (out[nombre] || []).concat(paredes);
      // Y la forma del cuarto (15-oct): cada pared con sus dos puntas, y las ventanas y puertas. Con esto la cámara
      // se UBICA dentro del plano con lo que ve el LiDAR, y sabe en qué pared cae un corte aunque sea parcial.
      // `marco`: en qué dibujo está el cuarto. Un plano juntado (lo normal) tiene TODOS sus cuartos en las mismas
      // coordenadas (marco 0): ubicada una vez, la cámara sabe dónde está en toda la planta aunque cambie de cuarto
      // (su pedido del 15-oct). Si los cuartos no se pudieron juntar, cada uno va en su propio dibujo.
      const forma = { paredes: [], senas: [], marco: d.merged === false ? (d.rooms || []).indexOf(room) : 0 };
      (room.walls || []).forEach(w => {
        if(!w || !w.start || !w.end || w._ajena) return;
        if(Math.hypot(w.end.x - w.start.x, w.end.y - w.start.y) < 1) return;
        const r2 = v => Math.round(v * 100) / 100;
        // El 6o número es el alto de la pared (pies, 15-oct): con él la cámara pone la malla de la casa del piso al techo.
        forma.paredes.push([r2(w.start.x), r2(w.start.y), r2(w.end.x), r2(w.end.y), plano.floorplanIsExteriorWall(w, room, d.merged === false ? null : rooms) ? 1 : 0, r2(Number(w.heightFt) || 0)]);
      });
      // El 4o número es el ancho (pies, 16-oct): con él la cámara sabe dónde no hay drywall (puerta) y hasta dónde
      // medir bajo una ventana. Los aparatos viejos leen solo los 3 primeros.
      // 5o y 6o (15-oct): a qué altura del piso empieza (-1 = el escaneo es viejo y no lo guardó) y su alto, para que la
      // malla de la casa deje el hueco de la puerta o la ventana en su lugar.
      // (16-oct) Y los PASOS SIN PUERTA (arcos): antes no se mandaban y "Pared completa" cobraba drywall y baseboard a lo ancho del arco.
      ['windows', 'doors', 'openings'].forEach(k => (room[k] || []).forEach(x => { const s = senaParaCamara(x, k); if(s) forma.senas.push(s); }));
      // El piso (y el techo) completo del cuarto (16-oct, su pedido "todo el piso o corte parcial"): el área de verdad del
      // contorno, y su largo × ancho (la caja; el plano ya está enderezado). Con el contorno roto no se manda: la cámara
      // dice que lo mida. El 4o número = 1 si la app cerró sola un tramo del borde (el área es aproximada).
      try{
        const mm = plano.fpRoomMeasurements(room), poly = plano.fpOrderedRoomPolygon(room) || [];
        if(mm && mm.outlineOk && mm.floorSqFt > 1 && poly.length >= 3){
          const xs = poly.map(q => q.x), ys = poly.map(q => q.y);
          const a = Math.max(...xs) - Math.min(...xs), b = Math.max(...ys) - Math.min(...ys);
          const r2 = v => Math.round(v * 100) / 100;
          forma.piso = [r2(mm.floorSqFt), r2(Math.max(a, b)), r2(Math.min(a, b)), (mm.guessedFt || 0) > 1 ? 1 : 0];
          // Y su contorno, para pintar el piso en el mapita de la cámara (verde completo, amarillo parcial).
          forma.contorno = poly.map(q => [r2(q.x), r2(q.y)]);
        }
      }catch(e){}
      if(forma.paredes.length >= 3) FORMAS[nombre] = forma;
    });
    return out;
  }catch(e){ return {}; }
}
// La forma de cada cuarto del último plano pedido (la llena paredesParaCamara, para no pedir el plano dos veces).
let FORMAS = {};
export function formasParaCamara(){ return FORMAS; }
// LOS NIVELES Y CUARTOS DEL PLANO PARA LA HOJA "Photos go to…" (17-oct, su pedido: "que vengan del plano y sin detector").
// Solo lee lo guardado: el plano más reciente de cada piso, sus cuartos con nombre (nunca "Room N" sin nombre ni la orden
// "nuevo cuarto"). Nada se crea aquí: la hoja los ENSEÑA, y solo el que la persona toca se agrega al proyecto.
// Sale [{ nivel_id, nombre, cuartos: [nombres] }]; nivel_id = el piso del proyecto donde se guardó el plano (o null), nombre =
// el nombre del nivel que dice el escaneo ('' si no dice ninguno; nunca se inventa la planta).
const PLANTA_A_NIVEL = { 'Basement': 'Basement', '1st Floor': 'First Floor', '2nd Floor': 'Second Floor', '3rd Floor': 'Third Floor', 'Attic': 'Attic' };
export function nombreDeNivelDelPlano(d){
  if(!d) return '';
  const L = nivelDelPlano(d), nom = d.inspection && d.inspection.nombresDeNivel;
  let n = nom && nom[String(L)] ? String(nom[String(L)]).trim() : '';
  if(!n && d._nivelBase){ const i0 = PLANTAS.indexOf(d._nivelBase); if(i0 >= 0 && PLANTAS[i0 + (Math.max(1, +L || 1) - 1)]) n = PLANTAS[i0 + (Math.max(1, +L || 1) - 1)]; }
  return PLANTA_A_NIVEL[n] || n;
}
const claveNombre = (s) => String(s || '').trim().toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, ' ');
export function nivelesDePlanos(lista){
  const out = [], vistos = new Set();
  (lista || []).forEach(p => {
    if(!p || !p.data) return;
    let d; try{ d = prepararPlano(p.data); }catch(e){ return; }
    if(!d) return;
    const nombre = nombreDeNivelDelPlano(d);
    // Un piso = su nivel del proyecto; los planos sin nivel se separan por el nombre que dice el escaneo.
    const llave = p.nivel_id ? 'n:' + p.nivel_id : 's:' + claveNombre(nombre);
    if(vistos.has(llave)) return;   // la lista viene del más nuevo al más viejo: manda el más reciente
    vistos.add(llave);
    const L = nivelDelPlano(d), ya = new Set(), cuartos = [];
    (d.rooms || []).forEach(r => {
      if(!r || r.deleted || !(r.walls || []).length || (r.level || 1) !== L) return;
      const n = String(r.roomName || '').trim();
      if(!n || esOrdenDeCuarto(n) || ya.has(claveNombre(n))) return;
      ya.add(claveNombre(n)); cuartos.push(n);
    });
    out.push({ nivel_id: p.nivel_id || null, nombre, cuartos });   // aunque quede vacío: así el más nuevo tapa a los viejos de ese piso
  });
  return out;
}
// Los planos del proyecto para esa hoja: los ya cargados por Floor Plan, o se piden; y los que esperan señal en el teléfono
// (un sótano sin señal) van primero porque son los más nuevos. Si no se pueden leer: [] (la hoja queda como siempre).
export async function nivelesDelPlanoDe(trabajoId){
  if(!trabajoId) return [];
  let lista = null;
  if(CARGADO === trabajoId && T && T.id === trabajoId) lista = PLANOS;
  else {
    try{
      const r = await authFetch('/rest/v1/fotos_planos?trabajo_id=eq.' + encodeURIComponent(trabajoId) + '&borrado_at=is.null&select=id,nivel_id,created_at,data&order=created_at.desc&limit=60');
      lista = r.ok ? await r.json() : [];
    }catch(e){ lista = []; }
  }
  // (17-oct) Por la hora del escaneo, junto con los del servidor: un escaneo viejo recogido después no tapa a uno más nuevo.
  return nivelesDePlanos(conPendientes(lista || [], trabajoId));
}
// El plano que se ve de cada piso: el más reciente (la lista viene ordenada del más nuevo al más viejo).
export const planoDe = (planos, nivelId) => (planos || []).find(p => (p.nivel_id || SIN_NIVEL) === (nivelId || SIN_NIVEL)) || null;
// (17-oct) LA HORA DEL ESCANEO. Un plano que se sube al terminar el escaneo no manda hora: la pone el servidor (como antes).
// Uno que se sube TARDE (recogido porque la respuesta del escáner se perdió, o que esperó señal) lleva la hora en que se
// escaneó, para que quede en el historial detrás de un plano más nuevo de su nivel en vez de taparlo. Esa hora sale del reloj
// del teléfono: se pasa a la hora del servidor con el desfase que se midió en las respuestas (app.js, encabezado Date), así un
// teléfono con la fecha mal puesta no lo adelanta; y nunca después de ahora (del servidor). Sin desfase medido todavía, la del
// teléfono tal cual; el servidor de todos modos no acepta una del futuro (sql/fotos-17-planos-hora.sql).
export function horaDelEscaneo(iso, ahora = Date.now(), desfase = desfaseDelReloj()){
  const t = msDe(iso); if(!t) return null;
  return new Date(Math.min(t, ahora) + (Number(desfase) || 0)).toISOString();
}
// La hora (del teléfono) de la parte i de un escaneo con dos niveles: cada parte 1 ms después de la anterior, como cuando el
// servidor ponía la suya al subirlas una tras otra. Así dos partes nunca empatan (con el mismo nivel, cuál se veía era al azar).
export function horaDeParte(iso, i){ const t = msDe(iso); return t ? new Date(t + (i || 0)).toISOString() : null; }
// La fila como se sube tarde: con la hora del escaneo (`escaneado`; las que apuntó la versión anterior solo traen `guardado`,
// cuándo se apuntaron). Así el orden del servidor es el mismo que el del teléfono mientras esperaba (conPendientes).
export function filaConHora(x){
  if(!x || !x.fila || x.fila.created_at) return x && x.fila;
  const h = horaDelEscaneo(x.escaneado || x.guardado);
  return h ? Object.assign({}, x.fila, { created_at: h }) : x.fila;
}
// Una hora como número. Postgres manda microsegundos ("…:00.123456+00:00"): se quedan los milisegundos.
function msDe(s){
  if(!s) return 0;
  let t = Date.parse(s); if(isFinite(t)) return t;
  const m = /^(.*?\.\d{3})\d+(.*)$/.exec(String(s)); t = m ? Date.parse(m[1] + m[2]) : NaN;
  return isFinite(t) ? t : 0;
}
// Del más nuevo al más viejo por su hora (los que no tienen, al final, en el orden en que venían).
export function ordenarPlanos(lista){
  return (lista || []).map((p, i) => ({ p, i, t: msDe(p && p.created_at) })).sort((a, b) => (b.t - a.t) || (a.i - b.i)).map(x => x.p);
}
// Los planos de un trabajo junto con los que esperan señal en este teléfono (su hora: la misma con que se van a subir).
function conPendientes(lista, trabajoId){
  const pend = leerPendientes().filter(x => x && x.fila && x.fila.trabajo_id === trabajoId && !(lista || []).some(p => p.id === x.fila.id))
    .map(x => Object.assign({ created_at: x.guardado }, filaConHora(x), { _pendiente: true }));
  return ordenarPlanos(pend.reverse().concat(lista || []));
}
// El escaneo sale del iPhone con el ángulo con que se sostuvo el teléfono. Field Reports lo endereza al
// recibirlo (sus pasos, en el mismo orden): girarlo a escuadra, escuadrar paredes, juntar las paredes que son
// la misma, cerrar esquinas chicas. Su queja del 13-oct: "los planos salen de lado". Se hace sobre una copia
// (nunca se toca lo guardado) y se recuerda, así no se repite en cada dibujo.
const sinAcento = (t) => String(t || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z ]+/g, ' ').replace(/\s+/g, ' ').trim();
const ORDENES = ['nuevo cuarto', 'cuarto nuevo', 'otro cuarto', 'siguiente cuarto', 'otro nivel', 'es nuevo', 'el siguiente', 'el que sigue', 'new room', 'next room', 'another room'];
export function esOrdenDeCuarto(nombre){ const k = sinAcento(nombre); return ORDENES.some(o => k === o || k.startsWith(o + ' ') || k.endsWith(' ' + o)); }
const LISTOS = new WeakMap();
export function prepararPlano(data){
  if(!data || typeof data !== 'object') return data;
  if(LISTOS.has(data)) return LISTOS.get(data);
  const d = JSON.parse(JSON.stringify(data));
  // El nombre que el personal dijo (o tocó) al escanear cada cuarto viene en voiceName; Field Reports lo
  // copia a roomName al recibir el escaneo y Scanova no lo hacía, por eso salían "ROOM 1/2" (su pedido del
  // 14-oct). Un nombre puesto después a mano (roomName) siempre gana. En el plano sale EN INGLÉS (13-oct):
  // "Sí, en la cocina" -> Kitchen, con la misma tabla de Field Reports.
  // "Nuevo cuarto"/"Otro cuarto" es la orden de pasar al siguiente, no un nombre: el iPhone lo guardaba como
  // nombre (ya arreglado en el aparato) y esos cuartos se quedan como Room N hasta que les pongan uno.
  (d.rooms || []).forEach(r => { const v = String(r && r.voiceName || '').trim(); if(r && !String(r.roomName || '').trim() && v && !esOrdenDeCuarto(v)){ r.roomName = plano.fpNombreDeCuartoEnIngles(v); r._namedByVoice = true; delete r._labelOffsetPx; } });
  // Clósets, baños chicos y lavandería: los nombra fpReconocerClosets (el mismo código de Field Reports), más abajo.
  try{
    plano.floorplanAlignRooms(d);
    // "Completar escaneo" pega al cuarto lo que se escaneó aparte. En la casa de Harold (14-oct) esa captura
    // vio otro espacio y dejó una caja de 13 x 14 ft encima de la cocina: lo que cae fuera de lo que le
    // faltaba al cuarto se aparta (no se borra), antes de enderezar nada. Mismo código que Field Reports.
    if(!d._handEdited){ plano.fpValidarParches(d); plano.floorplanRectifyWalls(d); plano.floorplanRefineGeometry(d); plano.floorplanCloseCorners(d); }
  }catch(e){ console.warn('enderezar plano', e); }
  // Los cuartos sin acceso que las paredes ya dibujan (clóset del master, laundry): la app los deduce sola y
  // los nombra por su puerta (13-oct, el plano de Harold). Mismo código que Field Reports.
  // RoomPlan le da a cada cuarto también las paredes del de al lado que se ven por una abertura: el Hallway de
  // Harold salía con 88 sq ft encima del Living Room (13-oct). Se le devuelven a su dueño ANTES de deducir cuartos.
  try{ if(!d._handEdited) plano.fpResolverParedesAjenas(d); }catch(e){ console.warn('paredes ajenas', e); }
  try{ if(!d._handEdited) plano.fpAutoCompletarEspacios(d); }catch(e){ console.warn('autocompletar', e); }
  // Clósets y rincones (su pedido, 14-oct): la app los reconoce y los nombra igual que Field Reports.
  try{ plano.floorplanDetectSubAreas(d); }catch(e){ console.warn('closets', e); }
  // Un cuarto que sigue sin nombre (nadie lo dijo ni lo tocó, y no es clóset/baño/lavandería por su lugar) no
  // sale "ROOM 1": toma el que el teléfono le enseñaba (nombresSugeridos, por los muebles), o la sugerencia de
  // Field Reports por sus muebles, o lo que RoomPlan dijo que era. Siempre marcado como sugerido; un nombre dicho o
  // escrito nunca se toca. Sin ninguna pista se queda Room N: no se inventa.
  try{ nombrarSinNombre(d); }catch(e){ console.warn('nombres', e); }
  // Cada fila de Scanova es UNA hoja de UN nivel (la que se dibuja).
  if(d._nivel == null){ const lv = plano.floorplanLevels(d); d._nivel = lv && lv.length ? lv[0] : 1; }
  LISTOS.set(data, d); return d;
}
const DEBILES = ['sofa', 'chair', 'table', 'television', 'storage', 'unknown'];
const SECCIONES_EN = { livingRoom: 'Living Room', kitchen: 'Kitchen', bedroom: 'Bedroom', bathroom: 'Bathroom', diningRoom: 'Dining Room' };
export function nombrarSinNombre(d){
  const sug = (d && d.inspection && d.inspection.nombresSugeridos) || {};
  (d.rooms || []).forEach((r, i) => {
    if(!r || r.deleted || String(r.roomName || '').trim()) return;
    const v = String(r.voiceName || '').trim();
    if(v && !esOrdenDeCuarto(v)) return;
    let nombre = String(sug[String(i)] || '').trim(), conf = 'Medium';
    // La sugerencia por muebles solo si hay un mueble que de verdad dice qué es el cuarto (cama, inodoro, estufa,
    // lavadora…) o dos que coinciden. Un sillón solo no hace sala: se ve por una abertura o se mueve (el Hallway
    // de la casa real tiene un sofá y salía "Living Room").
    if(!nombre){
      const s = plano.suggestFloorplanRoomName(r.objects, r);
      const cats = (r.objects || []).filter(o => o && !o._hidden).map(o => o.category);
      const fuerte = cats.some(c => !DEBILES.includes(c));
      if(s && (s.confidence === 'High' || (fuerte && s.name !== 'Closet'))){ nombre = s.name; conf = s.confidence; }
    }
    if(!nombre){ const lab = ((r._apiProbe && r._apiProbe.sectionLabels) || []).find(x => SECCIONES_EN[x]); if(lab){ nombre = SECCIONES_EN[lab]; conf = 'Low'; } }
    if(nombre){ r.roomName = nombre; r._suggestedConfidence = conf; }
  });
}
// limpia = la vista de la pantalla (solo el plano, su pedido del 13-oct); sin limpia = la hoja completa del PDF/exportar.
export function svgDelPlano(data, trabajo, limpia){
  plano.ponerVista(!!limpia);
  plano.ponerTrabajo({ client: trabajo && trabajo.cliente || '', phone: trabajo && trabajo.telefono || '', address: trabajo && trabajo.direccion || '', date: new Date().toLocaleDateString('en-US', { month:'short', day:'numeric', year:'numeric' }) });
  data = prepararPlano(data);
  // El cliente que sale en la hoja es el del PROYECTO (nombre, teléfono, dirección al día), no la copia que se
  // guardó dentro del escaneo el día que se escaneó (esa no trae teléfono y no se entera si lo corrigen).
  if(data && trabajo && (trabajo.cliente || trabajo.direccion)) data.job = Object.assign({}, data.job || {}, { client: trabajo.cliente || '', phone: trabajo.telefono || '', address: trabajo.direccion || '' });
  const nivel = data ? nivelDelPlano(data) : undefined;
  return data && data.merged === false ? plano.buildFloorplanSvgUnmerged(data, nivel) : plano.buildFloorplanSvg(data, nivel);
}
const fechaEn = (iso) => { const d = new Date(iso); return isNaN(d) ? '' : d.toLocaleDateString('en-US', { month:'short', day:'numeric', year:'numeric' }); };
const pies = (n) => (Number(n) || 0) % 1 ? (Math.round(n * 100) / 100) + ' ft' : (n || 0) + ' ft';

// ---------- datos ----------
async function cargar(){
  const id = T.id; CARGADO = 'cargando';
  try{
    const r = await authFetch('/rest/v1/fotos_planos?trabajo_id=eq.' + encodeURIComponent(id) + '&borrado_at=is.null&select=id,nivel_id,created_at,area_sqft,cuartos,muros_ext_ft,techo_ft,data&order=created_at.desc&limit=60');
    if(!T || T.id !== id) return;
    if(r.status === 404){ PLANOS = []; CARGADO = 'falta-sql'; }
    else if(!r.ok){ PLANOS = []; CARGADO = 'error'; }
    else { PLANOS = await r.json(); CARGADO = id; pintarConteo(pisosConPlano(PLANOS)); }
  }catch(e){ PLANOS = []; CARGADO = 'error'; }
  pintar();
  subirPendientes();
  recogerEscaneos(id);
}
// Cuántos pisos tienen plano, para la pestaña ("Floor Plan (2)"). Cada piso cuenta una vez aunque se haya guardado
// varias veces; uno sin piso cuenta como uno. Se pinta al abrir el proyecto (consulta chiquita, sin los planos)
// y cada vez que se cargan o se guardan los planos.
export function pisosConPlano(lista){ return new Set((lista || []).map(p => p.nivel_id || '-')).size; }
function pintarConteo(n){ const s = typeof document !== 'undefined' ? document.getElementById('planoConteo') : null; if(s) s.textContent = n == null ? '' : '(' + n + ')'; }
let CONTEO_PARA = '';
export async function contarPlanos(trabajoId){
  CONTEO_PARA = trabajoId;
  if(CARGADO === trabajoId){ pintarConteo(pisosConPlano(PLANOS)); return; }   // ya están cargados
  pintarConteo(null);
  try{
    const r = await authFetch('/rest/v1/fotos_planos?trabajo_id=eq.' + encodeURIComponent(trabajoId) + '&borrado_at=is.null&select=nivel_id&limit=500');
    if(!r.ok) return;
    const filas = await r.json();
    if(CONTEO_PARA === trabajoId && CARGADO !== trabajoId) pintarConteo(pisosConPlano(filas));   // si ya se cargaron los planos, esos mandan
  }catch(e){}
}
function nivelesConPlanos(){
  const l = NIVELES.map(n => ({ id: n.id, nombre: n.nombre }));
  if(PLANOS.some(p => !p.nivel_id) || !l.length) l.push({ id: SIN_NIVEL, nombre: NIVELES.length ? 'No level' : 'Floor Plan' });
  return l;
}
// El plano de un nivel para el 3D: el del servidor o el que espera señal en este teléfono, el más nuevo.
function plano3d(nivelId){ return T ? planoDe(conPendientes(PLANOS, T.id), nivelId) : null; }
function nivelElegido(){
  const l = nivelesConPlanos();
  if(!l.some(n => n.id === NIV_SEL)) NIV_SEL = (l.find(n => planoDe(PLANOS, n.id)) || l[0]).id;
  return l.find(n => n.id === NIV_SEL);
}

// ---------- dibujar ----------
// Los cuartos que el personal ya creó a mano en Photos, por nivel, para los botones de la cámara (17-oct).
export function cuartosParaLaCamara(niveles, cuartos, nivelBase){
  const por = {};
  (niveles || []).forEach(n => { por[n.nombre] = (por[n.nombre] || []).concat((cuartos || []).filter(c => c.nivel_id === n.id).map(c => String(c.nombre || '').trim()).filter(Boolean)); });
  return { cuartosPorNivel: por, cuartosDelNivel: por[nivelBase] || [] };
}
// `nivelesListos` (17-oct): false mientras el proyecto todavía no trae sus niveles (un escaneo recogido espera a que lleguen).
export function abrir(trabajo, niveles, alNivel, cuartos, nivelesListos){
  CUARTOS_P = cuartos || [];
  if(!T || T.id !== trabajo.id){ PLANOS = []; NIV_SEL = null; PL_CERRADO = false; ZOOM = 1; VISTA = '2d'; CARGADO = ''; AVISO = ''; RECOGER_DESPUES = ''; }
  T = trabajo; NIVELES = niveles || []; AL_NIVEL = alNivel || null; NIV_LISTOS = nivelesListos !== false;
  if(CARGADO !== T.id && CARGADO !== 'cargando') cargar(); else pintar();
  if(NIV_LISTOS && RECOGER_DESPUES === T.id && CARGADO !== 'cargando'){ RECOGER_DESPUES = ''; recogerEscaneos(T.id); }
}
export function pintar(){
  const caja = $('#panel-plano'); if(!caja || !T) return;
  if(CARGADO === 'falta-sql'){ caja.innerHTML = '<p class="aviso">Esta parte todavía no está instalada en el servidor: falta correr sql/fotos-07-planos.sql.</p>'; return; }
  const niv = nivelElegido(); const p = planoDe(PLANOS, niv.id); const res = p ? resumenPlano(p.data) : null;
  const lista = nivelesConPlanos();
  const filasNiv = lista.map(n => { const q = planoDe(PLANOS, n.id);
    return `<button type="button" class="pl-nivel${n.id === niv.id ? ' on' : ''}" data-pl-nivel="${esc(n.id)}"><b>${esc(n.nombre)}</b><small>${q ? fmtPies(q.data ? resumenPlano(q.data).area : (q.area_sqft || 0)) + ' sq ft' : 'No plan'}</small></button>`; }).join('');
  // Teléfono (su pedido, 13-oct): sin la tarjeta de resumen ni la fila de pisos debajo de los botones, para que el
  // plano tenga más espacio. El piso se escoge arriba (la lista); "Add Level" vive en el menú •••.
  // Teléfono (16-oct, su pedido "como en Dry Logs: abrir y encoger, ir rápido a cierto nivel"): cada nivel es una tarjeta;
  // la abierta enseña su plano (como siempre, quieto y lo más grande posible) y las demás quedan arriba y abajo. Tocar la
  // abierta la cierra (se ven todos los niveles); tocar otra la abre.
  const tarjetaNiv = (n) => { const q = planoDe(PLANOS, n.id), abierta = n.id === niv.id && !PL_CERRADO;
    return `<button type="button" class="pl-tel-niv${abierta ? ' on' : ''}" data-pl-tel-niv="${esc(n.id)}" aria-expanded="${abierta ? 'true' : 'false'}"><span class="pl-tel-niv-t"><b>${esc(n.nombre)}</b><small>${q ? fmtPies(q.data ? resumenPlano(q.data).area : (q.area_sqft || 0)) + ' sq ft' : 'No plan'}</small></span>${IC('chev', 'pl-tel-niv-flecha')}</button>`; };
  const iNiv = Math.max(0, lista.findIndex(n => n.id === niv.id));
  const nivArriba = lista.slice(0, iNiv + 1).map(tarjetaNiv).join(''), nivAbajo = lista.slice(iNiv + 1).map(tarjetaNiv).join('');
  let vista;
  if(CARGADO === 'cargando' || CARGADO === '') vista = '<div class="pl-vacio"><p>Loading plans…</p></div>';
  else if(CARGADO === 'error') vista = '<div class="pl-vacio"><p>Could not load the plans. Check your connection.</p></div>';
  else if(!p) vista = `<div class="pl-vacio">${IC('cubo', 'pl-vacio-ic')}<h3>No floor plan for ${esc(niv.nombre)} yet</h3><p>Tap <b>Scan New Plan</b> on an iPhone Pro (with LiDAR) and walk the rooms of this floor.</p></div>`;
  else { let svg = ''; try{ svg = svgDelPlano(p.data, T, true); }catch(e){ svg = '<p class="aviso">Could not draw this plan. ' + esc(e.message) + '</p>'; }
    // Al 100% el plano entra COMPLETO en su cuadro (su pedido: en la web el plano tiene la prioridad); con + se acerca y se puede mover.
    vista = `<div class="pl-lienzo${REJILLA ? ' rejilla' : ''}${ZOOM === 1 ? ' ajustado' : ''}"><div class="pl-zoom"${ZOOM === 1 ? '' : ` style="width:${Math.round(ZOOM * 100)}%"`}>${svg}</div></div>`; }
  const det = (k, v) => `<div class="pl-det"><span>${k}</span><b>${v}</b></div>`;
  const detalles = res ? det('Total Area', fmtPies(res.area) + ' sq ft') + det('Rooms', res.cuartos) + det('Exterior Walls', fmtPies(res.murosExt) + ' lf') + det('Ceiling Height', res.techo ? pies(res.techo) : '—') + det('Units', 'ft / in')
    : '<p class="pl-nada">Scan this floor to see its area, rooms and walls.</p>';
  // 3D: solo con un plano en este nivel (también uno que espera señal en este teléfono: recién escaneado en un sótano).
  const p3 = plano3d(niv.id);
  const herrVista = `<div class="pl-seg"><button type="button" class="${VISTA === '2d' ? 'on' : ''}" data-pl-vista="2d">2D</button><button type="button" class="${VISTA === '3d' ? 'on' : ''}" data-pl-vista="3d"${p3 ? (p3._pendiente ? ' title="Last scan on this phone (not uploaded yet)"' : '') : ' disabled'}>3D</button></div>`;
  const zoom = `<div class="pl-zoomer"><button type="button" data-pl-zoom="-1" aria-label="Zoom out">${IC('menos')}</button><span>${Math.round(ZOOM * 100)}%</span><button type="button" data-pl-zoom="1" aria-label="Zoom in">${IC('mas')}</button></div>`;
  caja.classList.toggle('pl-cerrado', PL_CERRADO);
  caja.innerHTML = `
  <div class="pl-cab">
    <div class="pl-cab-t"><h2 class="sec-t">Floor Plan</h2><p>View and manage plans by level</p></div>
    <div class="pl-cab-acc">
      <button type="button" class="btn btn-outline" data-pl-escanear>${IC('escanear')}Scan New Plan</button>
      <button type="button" class="btn btn-outline" data-pl-exportar${p ? '' : ' disabled'}>${IC('compartir')}Export</button>
      <button type="button" class="btn btn-accent" data-pl-editar${p ? '' : ' disabled'}>${IC('lapiz')}Edit Floor Plan</button>
      ${esManager() && p ? `<button type="button" class="btn btn-outline btn-rojo" data-pl-borrar>${IC('basura')}Delete Plan</button>` : ''}
    </div>
  </div>
  ${AVISO ? `<p class="aviso${AVISO_OK ? ' ok' : ''}" id="plAviso">${esc(AVISO)}</p>` : ''}
  ${bandaPendientes()}
  <div class="pl-tel-barra">
    <span class="pl-sel"></span>
    ${herrVista}
    <div class="pl-mas-wrap"><button type="button" class="pl-mas-btn" data-pl-menu aria-label="More options" aria-expanded="${MENU ? 'true' : 'false'}">•••</button>
      <div class="pl-menu"${MENU ? '' : ' hidden'}><button type="button" data-pl-mas-nivel>${IC('mas')}Add Level</button><button type="button" data-pl-rejilla>${IC('cuadros')}${REJILLA ? 'Hide grid' : 'Show grid'}</button><button type="button" data-pl-ajustes>${IC('engrane')}Plan Settings</button>${esManager() && p ? `<button type="button" class="pl-menu-rojo" data-pl-borrar>${IC('basura')}Delete floor plan</button>` : ''}</div></div>
  </div>
  <div class="pl-tel-niveles">${nivArriba}</div>
  <div class="pl-cuerpo">
    <aside class="pl-col pl-niveles"><h3>Levels</h3>${filasNiv}<button type="button" class="btn btn-outline btn-block pl-mas-nivel" data-pl-mas-nivel>${IC('mas')}Add Level</button></aside>
    <section class="pl-col pl-visor">
      <div class="pl-visor-cab"><b>${esc(niv.nombre)}</b>${p ? `<span class="pl-fecha">Updated ${esc(fechaEn(p.created_at))}</span>` : ''}
        <span class="pl-esp"></span>${herrVista}
        <button type="button" class="pl-rej${REJILLA ? ' on' : ''}" data-pl-rejilla>${IC('cuadros')}Grid</button>${zoom}
        <button type="button" class="pl-grande-btn" data-pl-grande aria-label="Full screen">${IC('expandir')}</button></div>
      ${vista}
    </section>
    <aside class="pl-col pl-detalles"><h3>Plan Details</h3>${detalles}<button type="button" class="btn btn-outline btn-block" data-pl-ajustes>${IC('engrane')}Plan Settings</button></aside>
  </div>
  ${nivAbajo ? `<div class="pl-tel-niveles">${nivAbajo}</div>` : ''}
  <div class="pl-tel-acc">
    <div class="pl-tel-editar"><button type="button" class="btn btn-accent" data-pl-editar${p ? '' : ' disabled'}>Edit Floor Plan</button><button type="button" class="btn btn-outline pl-tel-grande" data-pl-grande aria-label="Full screen">${IC('expandir')}</button></div>
    <div class="pl-tel-dos"><button type="button" class="btn btn-outline" data-pl-escanear>${IC('escanear')}Scan New Plan</button><button type="button" class="btn btn-outline" data-pl-exportar${p ? '' : ' disabled'}>${IC('compartir')}Export</button></div>
  </div>`;
  medir();
  const lz = $('#panel-plano .pl-lienzo.ajustado'); if(lz) pellizco(lz, lz.querySelector('.pl-zoom'), PZ);
}
// Su pedido: en la computadora el plano tiene la prioridad pero SIN esconder las opciones (pestañas, cabecera).
// El cuadro del plano usa lo que queda de pantalla debajo de lo demás y el plano entra completo ahí (se acerca con +).
// (17-oct) Al entrar a Floor Plan con los planos ya cargados (el mismo proyecto otra vez, o "Open it" de Home), las copias del
// escáner se vuelven a mirar: cargar() solo lo hace la primera vez, y una que no se pudo guardar se quedaba sin reintentar.
export function enfocar(){ medir(); if(T && CARGADO === T.id) recogerEscaneos(T.id); }
function medir(){
  const l = $('#panel-plano .pl-lienzo'); const m = $('#main');
  // Solo con la pestaña Floor Plan a la vista: escondida (otra pestaña, otra pantalla) no se mide ni se fija nada.
  if(!l || !l.offsetParent){ if(typeof document !== 'undefined') document.body.classList.remove('pl-fijo'); return; }
  if(window.matchMedia && !window.matchMedia('(min-width: 900px)').matches){
    // Teléfono (su pedido del 13-oct): solo el plano, lo más grande posible. El cuadro toma la forma del
    // plano a todo lo ancho; si el plano es alto, se topa en 62% de la pantalla y el plano queda centrado.
    if(!l.classList.contains('ajustado')){ l.style.height = ''; document.body.classList.remove('pl-fijo'); return; }
    // Su pedido (13-oct): la página del plano NO se mueve para arriba y para abajo, queda como su diseño:
    // cabecera, pestañas, plano y botones en UNA pantalla, y el cuadro del plano se lleva el espacio que sobra.
    // Si de plano no cabe (teléfono acostado, letra muy grande), la página se desplaza como siempre.
    // La clase va ANTES de medir: con ella la pantalla suelta su margen de abajo y el aviso vacío (13-oct),
    // y ese espacio se lo tiene que llevar el plano. Si al final no cabe, se quita abajo.
    document.body.classList.add('pl-fijo');
    const v = l.querySelector('svg'); const vb = v && v.viewBox && v.viewBox.baseVal;
    const ar = vb && vb.width && vb.height ? vb.width / vb.height : 1.4;
    const panel = $('#panel-plano'); const ultimo = panel && panel.lastElementChild;
    const resto = ultimo ? ultimo.getBoundingClientRect().bottom - l.getBoundingClientRect().bottom : 0;   // resumen + botones + pisos
    const visible = m ? m.clientHeight : window.innerHeight;
    const arriba = l.getBoundingClientRect().top - (m ? m.getBoundingClientRect().top - m.scrollTop : 0);
    const pie = m ? parseFloat(getComputedStyle(m).paddingBottom) || 0 : 0;   // el margen de abajo de la pantalla también cuenta
    const cabe = Math.floor(visible - arriba - resto - pie - 2);
    if(cabe >= 160){
      l.style.height = cabe + 'px';
      // Lo que todavía sobresalga (márgenes de más abajo) se le quita al cuadro: así la página ya no se mueve.
      const sobra = m ? m.scrollHeight - m.clientHeight : 0;
      if(sobra > 0) l.style.height = Math.max(160, cabe - sobra) + 'px';
      document.body.classList.add('pl-fijo'); if(m) m.scrollTop = 0;
    } else {
      document.body.classList.remove('pl-fijo');
      l.style.height = Math.max(200, Math.round((l.clientWidth - 16) / ar + 16)) + 'px';
    }
    return;
  }
  const arriba = l.getBoundingClientRect().top + (m ? m.scrollTop : window.scrollY);   // dónde queda el cuadro con la página arriba del todo
  l.style.height = Math.max(380, Math.round(window.innerHeight - arriba - 18)) + 'px';
  // Su pedido (14-oct): en la computadora tampoco se mueve la página. El borde de la tarjeta del plano y el margen de
  // abajo de la pantalla no entraban en la cuenta (sobraban ~65 px): lo que todavía sobresalga se le quita al cuadro.
  const sobra = m ? m.scrollHeight - m.clientHeight : 0;
  if(sobra > 0){ l.style.height = Math.max(380, l.clientHeight - sobra) + 'px'; if(m) m.scrollTop = 0; }
}
if(typeof window !== 'undefined') window.addEventListener('resize', () => medir());
// La foto de la cabecera llega después y cambia el alto: se vuelve a medir para que todo siga cabiendo.
if(typeof document !== 'undefined') document.addEventListener('load', (e) => { if(e.target && e.target.tagName === 'IMG' && e.target.closest && e.target.closest('#pTrabajo') && $('#panel-plano .pl-lienzo')) medir(); }, true);
function avisar(t, ok){ AVISO = t || ''; AVISO_OK = !!ok; pintar(); }
// Los planos de ESTE trabajo que esperan señal: una franja con "Upload now".
function bandaPendientes(){
  const mios = T ? leerPendientes().filter(x => x && x.fila && x.fila.trabajo_id === T.id) : [];
  if(!mios.length) return '';
  const niveles = [...new Set(mios.map(x => x.nivel || 'No level'))].join(', ');
  const err = mios.find(x => x.error);
  return `<div class="pl-pend" id="plPend">${IC('reloj')}<span><b>${mios.length === 1 ? '1 floor plan' : mios.length + ' floor plans'} waiting for signal</b> · ${esc(niveles)}${err ? ' · ' + esc(err.error) : ''}<br><small>Saved on this phone. It uploads by itself when there is signal.</small></span><button type="button" class="btn btn-outline" data-pl-subir${SUBIENDO ? ' disabled' : ''}>${SUBIENDO ? 'Uploading…' : 'Upload now'}</button></div>`;
}

// ---------- acercar con los dedos (su pedido 13-oct: sin + y − encima del plano) ----------
// Dos dedos: abre/cierra y mueve. Un dedo con el plano acercado: lo mueve. Un dedo con el plano entero: la página se
// desplaza como siempre. Dos toques seguidos: acerca ahí, o vuelve a enseñarlo entero.
export function limitarPZ(e, w, h){
  e.s = Math.max(1, Math.min(6, e.s));
  e.x = Math.min(0, Math.max(w - w * e.s, e.x)); e.y = Math.min(0, Math.max(h - h * e.s, e.y));
  if(e.s === 1){ e.x = 0; e.y = 0; }
  return e;
}
export function zoomEn(e, s2, mx, my){ const px = (mx - e.x) / e.s, py = (my - e.y) / e.s; e.s = s2; e.x = mx - px * s2; e.y = my - py * s2; return e; }
function pellizco(caja, obj, e){
  if(!caja || !obj) return;
  obj.style.transformOrigin = '0 0';
  const poner = () => { limitarPZ(e, caja.clientWidth, caja.clientHeight); obj.style.transform = e.s === 1 ? '' : `translate(${e.x}px, ${e.y}px) scale(${e.s})`; caja.classList.toggle('pz-cerca', e.s > 1); };
  poner();
  let ini = null, ultimoToque = 0, movio = false;
  const rel = (t) => { const r = caja.getBoundingClientRect(); return { x: t.clientX - r.left, y: t.clientY - r.top }; };
  caja.addEventListener('touchstart', (ev) => {
    movio = false;
    if(ev.touches.length === 2){ const a = rel(ev.touches[0]), b = rel(ev.touches[1]); ini = { d: Math.hypot(a.x - b.x, a.y - b.y) || 1, s: e.s, mx: (a.x + b.x) / 2, my: (a.y + b.y) / 2, x: e.x, y: e.y }; }
    else if(ev.touches.length === 1){ const a = rel(ev.touches[0]); ini = { uno: true, px: a.x, py: a.y, x: e.x, y: e.y }; }
  }, { passive: true });
  caja.addEventListener('touchmove', (ev) => {
    if(!ini) return;
    if(ev.touches.length === 2 && !ini.uno){
      ev.preventDefault(); movio = true;
      const a = rel(ev.touches[0]), b = rel(ev.touches[1]); const d = Math.hypot(a.x - b.x, a.y - b.y) || 1;
      const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
      e.s = ini.s; e.x = ini.x; e.y = ini.y; zoomEn(e, Math.max(1, Math.min(6, ini.s * d / ini.d)), ini.mx, ini.my);
      e.x += mx - ini.mx; e.y += my - ini.my; poner();
    } else if(ev.touches.length === 2 && ini.uno){ const a = rel(ev.touches[0]), b = rel(ev.touches[1]); ini = { d: Math.hypot(a.x - b.x, a.y - b.y) || 1, s: e.s, mx: (a.x + b.x) / 2, my: (a.y + b.y) / 2, x: e.x, y: e.y }; }
    else if(ev.touches.length === 1 && ini.uno && e.s > 1){
      ev.preventDefault(); const a = rel(ev.touches[0]);
      if(Math.abs(a.x - ini.px) + Math.abs(a.y - ini.py) > 4) movio = true;
      e.x = ini.x + a.x - ini.px; e.y = ini.y + a.y - ini.py; poner();
    } else if(ev.touches.length === 1){ const a = rel(ev.touches[0]); if(Math.abs(a.x - ini.px) + Math.abs(a.y - ini.py) > 4) movio = true; }
  }, { passive: false });
  caja.addEventListener('touchend', (ev) => {
    if(ev.touches.length) return;
    const fue = ini; ini = null;
    if(!fue || !fue.uno || movio) return;
    const ahora = Date.now();
    if(ahora - ultimoToque < 320){
      ultimoToque = 0;
      if(e.s > 1){ e.s = 1; e.x = 0; e.y = 0; } else zoomEn(e, 2.5, fue.px, fue.py);
      poner();
    } else ultimoToque = ahora;
  }, { passive: true });
}

// ---------- borrar el plano de un nivel (16-oct, su pedido: "solo los managers... borrar planos, en este momento de los testeos") ----------
// Solo el manager. Se marca borrado (borrado_at; la fila no se destruye) el plano del nivel escogido Y sus escaneos anteriores
// (si no, al borrar el último aparecería el de antes). Las medidas no se tocan. Se COMPRUEBA volviendo a leer.
async function borrarPlano(){
  if(!T || OCUPADO || !esManager()) return;
  const tid = T.id, niv = nivelElegido();
  const mios = PLANOS.filter(p => (p.nivel_id || SIN_NIVEL) === (niv.id || SIN_NIVEL));
  if(!mios.length) return;
  const ok = await preguntar({ titulo: 'Delete the floor plan of ' + niv.nombre + '?',
    texto: (mios.length === 1 ? 'The floor plan' : 'The floor plan and its ' + (mios.length - 1) + (mios.length === 2 ? ' earlier scan' : ' earlier scans')) + ' of ' + niv.nombre + ' will be removed from this project. Measurements are not touched.',
    si: 'Delete plan', no: 'Keep it' });
  if(!ok || !T || T.id !== tid) return;
  const ids = mios.map(p => p.id);
  OCUPADO = true; avisar('Deleting the floor plan…', true);
  let fallo = '';
  try{
    const r = await authFetch('/rest/v1/fotos_planos?id=in.(' + ids.join(',') + ')&borrado_at=is.null', { method:'PATCH', headers:{ Prefer:'return=representation' }, body: JSON.stringify({ borrado_at: new Date().toISOString() }) });
    if(!r.ok) fallo = 'HTTP ' + r.status;
  }catch(e){ fallo = String(e && e.message || e); }
  OCUPADO = false;
  if(!T || T.id !== tid) return;
  CARGADO = ''; await cargar();
  const quedan = PLANOS.filter(p => ids.includes(p.id)).length;
  if(!quedan) avisar('Floor plan of ' + niv.nombre + ' deleted.', true);
  else avisar('Could not delete the floor plan' + (fallo ? ' (' + fallo + ')' : '') + '. Only the manager can delete plans.');
}

// ---------- planos esperando señal (16-oct, Aroldo en un sótano: "Load failed" y los dos escaneos se perdieron) ----------
// El escaneo se guarda PRIMERO en el teléfono y después se sube. Sin señal se queda ahí y se sube solo al volver la señal
// (al abrir Floor Plan, al regresar a la app, al reconectarse, o con "Upload now"). Cada plano lleva su id desde el
// teléfono: si la primera subida sí llegó y solo se perdió la respuesta, el reintento no lo duplica.
const PEND_LLAVE = 'scanova:planosPendientes:v1';
export function leerPendientes(){ try{ const v = JSON.parse(localStorage.getItem(PEND_LLAVE) || '[]'); return Array.isArray(v) ? v : []; }catch(e){ return []; } }
function escribirPendientes(l){ try{ localStorage.setItem(PEND_LLAVE, JSON.stringify(l)); return true; }catch(e){ return false; } }
function quitarPendiente(id){ escribirPendientes(leerPendientes().filter(x => x.fila && x.fila.id !== id)); }
export const esErrorDeRed = (e) => !!e && !e.permanente && (e.name === 'TypeError' || /load failed|failed to fetch|network ?error|internet|offline|timed out|cancelled|abort|HTTP 5\d\d/i.test(String(e.message || e)));
const COLS_PLANO = 'id,nivel_id,created_at,area_sqft,cuartos,muros_ext_ft,techo_ft,data';
async function subirFila(fila, intentos = 3){
  let ultimo = null;
  for(let i = 0; i < intentos; i++){
    if(i) await new Promise(r => setTimeout(r, [0, 2000, 6000][i] || 6000));
    try{
      const g = await authFetch('/rest/v1/fotos_planos', { method:'POST', headers:{ Prefer:'return=representation' }, body: JSON.stringify(fila) });
      if(g.ok){ const x = (await g.json())[0]; if(x && x.id) return x; }
      if(g.status === 409){   // ya estaba: la vez anterior sí llegó
        const r = await authFetch('/rest/v1/fotos_planos?id=eq.' + encodeURIComponent(fila.id) + '&select=' + COLS_PLANO);
        if(r.ok){ const x = (await r.json())[0]; if(x) return x; }
      }
      const err = new Error(g.status === 404 ? 'falta correr sql/fotos-07-planos.sql' : 'HTTP ' + g.status);
      err.permanente = g.status >= 400 && g.status < 500 && g.status !== 408 && g.status !== 429;
      throw err;
    }catch(e){ ultimo = e; if(!esErrorDeRed(e)) throw e; }
  }
  throw ultimo || new Error('Load failed');
}
let SUBIENDO = false;
// Sube lo que quedó en el teléfono. `aMano` = tocó "Upload now" (también reintenta los que fallaron por otra razón).
export async function subirPendientes(aMano){
  if(SUBIENDO) return; const lista = leerPendientes(); if(!lista.length) return;
  if(typeof navigator !== 'undefined' && navigator.onLine === false && !aMano) return;
  SUBIENDO = true; let subidas = 0, falla = '';
  try{
    for(const x of lista){
      if(!x || !x.fila) continue;
      if(x.error && !aMano) continue;
      try{
        // Con la hora en que se escaneó (17-oct): sin ella el servidor le ponía la de la subida y un escaneo de ayer tapaba
        // al plano que otro subió hoy de ese nivel. Las que apuntó la versión anterior: la hora en que se apuntaron.
        const g = await subirFila(filaConHora(x), aMano ? 3 : 1);
        quitarPendiente(x.fila.id); subidas++;
        if(T && g.trabajo_id ? g.trabajo_id === T.id : (T && x.fila.trabajo_id === T.id)){
          if(!PLANOS.some(p => p.id === g.id)) PLANOS = ordenarPlanos([g].concat(PLANOS));   // por la hora del escaneo (17-oct)
          pintarConteo(pisosConPlano(PLANOS));
        }
      }catch(e){
        if(!esErrorDeRed(e)){ const l = leerPendientes(); const y = l.find(z => z.fila && z.fila.id === x.fila.id); if(y){ y.error = String(e && e.message || e); escribirPendientes(l); } falla = String(e && e.message || e); }
        else { falla = 'red'; break; }
      }
    }
  } finally { SUBIENDO = false; }
  if(subidas) avisar(subidas === 1 ? 'The floor plan that was waiting for signal is uploaded.' : 'The ' + subidas + ' floor plans that were waiting for signal are uploaded.', true);
  else if(aMano && falla) avisar(falla === 'red' ? 'Still no signal. The floor plan stays safe on this phone; it uploads by itself when there is signal.' : 'Could not upload the floor plan: ' + falla + '. It stays saved on this phone.');
  else pintar();
}
if(typeof window !== 'undefined'){
  // (17-oct) Y después, las copias que el escáner dejó en el teléfono (una que no cupo en la lista del teléfono se reintenta
  // sola al volver la señal). Al regresar a la app, un segundo después: el escáner cierra con una animación y su copia se
  // escribe al final de ella.
  window.addEventListener('online', () => { subirPendientes().catch(() => {}).then(revisarTelefono); });
  document.addEventListener('visibilitychange', () => { if(document.visibilityState === 'visible') subirPendientes().catch(() => {}).then(() => setTimeout(revisarTelefono, 1000)); });
}

// ---------- escanear ----------
const rs = () => (typeof window !== 'undefined' && window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.RoomScan) || null;
const nuevoId = () => (typeof crypto !== 'undefined' && crypto.randomUUID) ? crypto.randomUUID()
  : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); });
// (17-oct) El id de cada fila sale de la ENTREGA del escaneo: la primera fila es la entrega misma y las demás (un escaneo
// con dos niveles) se sacan de ella. Si el mismo escaneo llega dos veces (la respuesta del escáner y la copia que dejó en
// el teléfono) trae los mismos ids: el servidor dice 409 y no se repite nada.
const ES_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export function idDeParte(entrega, i){
  const e = String(entrega || '').toLowerCase();
  if(!ES_UUID.test(e)) return nuevoId();
  if(!i) return e;
  const s = e + ':' + i; let a = 0x811c9dc5, b = 0x9e3779b9;
  for(let k = 0; k < s.length; k++){ const c = s.charCodeAt(k); a = Math.imul(a ^ c, 16777619) >>> 0; b = Math.imul(b ^ c, 2246822519) >>> 0; }
  return e.slice(0, 24) + (a.toString(16).padStart(8, '0') + b.toString(16).padStart(8, '0')).slice(0, 12);
}
// (17-oct) Con el escáner abierto la app no se recarga sola por una versión nueva (app.js, ocupado()).
function marcarEscaner(on){ if(typeof document !== 'undefined' && document.body && document.body.classList) document.body.classList.toggle('con-escaner', !!on); }
// La copia que el escáner dejó en el teléfono se suelta SOLO cuando el plano ya está a salvo. Aparato viejo: no existe.
function soltarEscaneos(tid, ids){
  const RS = rs(); ids = (ids || []).filter(Boolean);
  if(!ids.length || !RS || !RS.soltar) return;
  try{ const x = RS.soltar({ trabajo: tid, ids }); if(x && x.catch) x.catch(() => {}); }catch(e){}
}
// Lo que trajo el escáner, listo para guardar. UN ESCANEO CON DOS NIVELES ("Otro nivel" a medio escaneo) se guarda
// partido: una fila por nivel, cada una en SU piso del proyecto. Antes se guardaba todo bajo el primero, se dibujaba solo
// el primero y el área los sumaba.
function partesDelEscaneo(r, niv){
  // Los niveles REALES del trabajo viajan a la bandeja de la cámara; el que se escoja ahí es el que manda.
  if(r.nivelBase){ const m = NIVELES.find(n => n.nombre === r.nivelBase); if(m) niv = m; }
  // La planta estándar que se escogió en la cámara (sótano, 1st Floor…) le da nombre al nivel en la hoja, igual
  // que en Field Reports; los niveles con nombre propio ya vienen en inspection.nombresDeNivel.
  if(r.nivelBase && !r._nivelBase && PLANTAS.includes(r.nivelBase)) r._nivelBase = r.nivelBase;
  r.job = { client: T.cliente || '', address: T.direccion || '', date: String(r._escaneado || new Date().toISOString()).slice(0, 10) };
  const niveles = plano.floorplanLevels(prepararPlano(r));
  const nombres = (r.inspection && r.inspection.nombresDeNivel) || {};
  const partes = (niveles.length > 1 ? niveles : [null]).map(L => {
    const d = prepararPlano(L == null ? r : Object.assign({}, r, { _nivel: L }));   // se guarda ya derecho
    const nombre = L == null ? '' : String(nombres[String(L)] || (L === niveles[0] ? (r.nivelBase || '') : ''));
    const n = L == null || L === niveles[0] ? (NIVELES.find(x => x.nombre === nombre) || niv) : (NIVELES.find(x => x.nombre === nombre) || null);
    return { d, n, res: resumenPlano(d) };
  }).filter(x => x.res.cuartos);
  // La fila no lleva hora: la del escaneo (el aparato la pone en _escaneado) solo se manda si se sube tarde (filaConHora).
  const filas = partes.map((x, i) => ({ id: idDeParte(r._entrega, i), trabajo_id: T.id, nivel_id: x.n && x.n.id !== SIN_NIVEL ? x.n.id : null, data: x.d, area_sqft: x.res.area, cuartos: x.res.cuartos, muros_ext_ft: x.res.murosExt, techo_ft: x.res.techo || null }));
  return { niv, partes, filas };
}
// (17-oct) El nivel de un escaneo recogido: el que estaba en pantalla al empezar a escanear (el aparato lo guardó en
// _nivelPedido), como si la respuesta hubiera llegado. Si ese nivel ya no existe: 'No level'.
function nivelPedidoDe(e){
  return NIVELES.find(n => n.id === e._nivelPedido) || { id: SIN_NIVEL, nombre: NIVELES.length ? 'No level' : 'Floor Plan' };
}
// GUARDAR UN ESCANEO, en dos pasos. 1) El teléfono (al instante, sin red): las filas a la lista del teléfono; si cupieron,
// la copia del escáner se suelta ya (el plano está a salvo). 2) El servidor. Si la lista no cupo, la copia del escáner se
// suelta solo cuando el servidor lo confirmó.
function apuntarEscaneo(r, prep){
  const { partes, filas } = prep, ids = new Set(filas.map(f => f.id));
  // La misma entrega no se apunta dos veces.
  const pend = leerPendientes().filter(x => !(x && x.fila && ids.has(x.fila.id)));
  // Cada parte con la hora en que se escaneó (la suya, 1 ms después de la anterior): con esa se sube si espera señal.
  const ahora = Date.now();
  filas.forEach((f, i) => pend.push({ fila: f, nivel: partes[i].n ? partes[i].n.nombre : 'No level', guardado: new Date(ahora + i).toISOString(), escaneado: horaDeParte(r._escaneado, i) }));
  const enTelefono = escribirPendientes(pend);
  if(enTelefono) soltarEscaneos(filas[0].trabajo_id, [r._entrega]);
  return enTelefono;
}
// `recuperado` = vino de la copia del escáner (la respuesta se perdió): un solo intento, la lista del teléfono sigue sola.
async function subirEscaneo(r, prep, recuperado, enTelefono){
  const { niv, partes, filas } = prep, tid = filas[0].trabajo_id, ids = new Set(filas.map(f => f.id));
  const antes = recuperado ? 'Recovered a floor plan scan that was not saved. ' : '';
  const intentos = recuperado && enTelefono ? 1 : 3, guardadas = [];
  let sinSenal = 0;
  for(const [i, fila] of filas.entries()){
    // Recogido: con la hora en que se escaneó. Recién escaneado: sin hora, la pone el servidor (un reloj mal puesto no decide).
    const f = recuperado ? filaConHora({ fila, escaneado: horaDeParte(r._escaneado, i) }) : fila;
    try{ guardadas.push(await subirFila(f, intentos)); quitarPendiente(fila.id); }
    catch(e){
      if(enTelefono && esErrorDeRed(e)){ sinSenal++; continue; }
      // Otro error (no la señal): el escaneo se QUEDA en el teléfono con su razón; "Upload now" lo vuelve a intentar.
      if(enTelefono){ const l = leerPendientes(); const y = l.find(z => z.fila && z.fila.id === fila.id); if(y){ y.error = String(e && e.message || e); escribirPendientes(l); } }
      throw e;
    }
  }
  if(!enTelefono) soltarEscaneos(tid, [r._entrega]);   // la lista del teléfono no cupo: se suelta ya confirmado por el servidor
  if(!T || T.id !== tid) return;
  if(guardadas.length) PLANOS = ordenarPlanos(guardadas.concat(PLANOS.filter(p => !ids.has(p.id))));
  pintarConteo(pisosConPlano(PLANOS));
  // Más viejo que el plano que ya tiene su nivel (recogido días después, o el reloj de otro teléfono): queda de historial, el
  // nivel en pantalla no cambia y no se dice que es el plano de ese nivel.
  const n0 = partes[0].n || niv, actual = planoDe(conPendientes(PLANOS, tid), n0.id);
  if(actual && !ids.has(actual.id)){
    avisar((recuperado ? 'Recovered an earlier scan of ' + n0.nombre + ' that was not saved. It is kept as history; ' : 'The scan of ' + n0.nombre + ' is saved as history: ')
      + 'the newer plan of ' + n0.nombre + ' stays.' + (sinSenal ? ' It is saved on this phone and uploads by itself when there is signal.' : ''), true);
    return;
  }
  NIV_SEL = n0.id;
  if(sinSenal){
    avisar(antes + (sinSenal === filas.length ? 'No signal here. ' : 'Part of the scan could not upload (no signal). ')
      + 'The floor plan is saved on this phone and uploads by itself when there is signal. You do not need to scan again.', true);
    return;
  }
  const res = partes[0].res;
  avisar(antes + (partes.length > 1
    ? 'Floor plans saved: ' + partes.map(x => (x.n ? x.n.nombre : 'No level') + ' (' + fmtPies(x.res.area) + ' sq ft)').join(', ') + '.'
    : 'Floor plan saved for ' + niv.nombre + ' (' + fmtPies(res.area) + ' sq ft, ' + res.cuartos + ' rooms).'), true);
}
// Guarda el escaneo que acaba de llegar del escáner: primero el teléfono, después el servidor.
async function guardarEscaneo(r, prep){
  if(!prep.partes.length){ soltarEscaneos(T.id, [r._entrega]); avisar('The scan came back without any room. Nothing was saved - try again walking slowly along the walls.'); return; }
  const enTelefono = apuntarEscaneo(r, prep);
  await subirEscaneo(r, prep, false, enTelefono);
}
// (17-oct) LO QUE EL ESCÁNER GUARDÓ Y LA PÁGINA NUNCA RECIBIÓ: con el escáner abierto iOS mató el motor web, la página se
// recargó y el escaneo se perdió sin aviso (su escaneo 2 del 17-oct). Ahora el escáner deja cada escaneo en el teléfono
// antes de responder, y aquí se guarda como cualquier escaneo. Lo que ya está en Floor Plan o en la lista del teléfono
// solo se suelta. Solo el paso del teléfono se espera (al instante); la subida sigue sola, sin detener Scan New Plan ni
// Delete plan. `propio` = lo llama escanear() (ya tiene OCUPADO). Una a la vez: la que llega espera a la que va. Devuelve
// cuántos escaneos se recogieron. Aparato viejo (sin pendientes): nada.
let RECOGIENDO = null, NIV_LISTOS = true, RECOGER_DESPUES = ''; const NO_SE_PUDO = new Set(), EN_CAMINO = new Set();
function recogerEscaneos(tid, propio){
  if(RECOGIENDO) return RECOGIENDO.then(() => recogerEscaneos(tid, propio));
  RECOGIENDO = recoger(tid, propio).catch(e => { console.warn('recoger escaneos', e); return 0; }).finally(() => { RECOGIENDO = null; });
  return RECOGIENDO;
}
async function recoger(tid, propio){
  const RS = rs();
  if(!RS || !RS.pendientes || !T || T.id !== tid || CARGADO === 'falta-sql' || (!propio && OCUPADO)) return 0;
  // Sin los niveles del proyecto todavía (recién abierto, o no llegaron) se espera a que lleguen: si no, caería en 'No level'.
  // También desde Scan New Plan: la copia se queda en el teléfono y se guarda cuando abrir() trae los niveles.
  if(!NIV_LISTOS){ RECOGER_DESPUES = tid; return 0; }
  let r; try{ r = await RS.pendientes({ trabajo: tid }); }catch(e){ return 0; }
  const lista = ((r && r.escaneos) || []).filter(e => e && typeof e === 'object' && ES_UUID.test(String(e._entrega || '').toLowerCase()) && !NO_SE_PUDO.has(e._entrega) && !EN_CAMINO.has(e._entrega));
  if(!lista.length || !T || T.id !== tid) return 0;
  let n = 0;
  for(const e of lista){
    if(!T || T.id !== tid) break;
    let prep;
    try{ prep = partesDelEscaneo(e, nivelPedidoDe(e)); }
    catch(err){ NO_SE_PUDO.add(e._entrega); console.warn('escaneo sin entregar', err); continue; }
    const ya = new Set((CARGADO === tid ? PLANOS : []).map(p => p.id).concat(leerPendientes().map(x => x && x.fila && x.fila.id)));
    if(prep.filas.every(f => ya.has(f.id))){ soltarEscaneos(tid, [e._entrega]); continue; }   // ya estaba a salvo (o no trae ningún cuarto)
    n++;
    const enTelefono = apuntarEscaneo(e, prep);
    avisar('Recovered a floor plan scan that was not saved. Saving it…', true);
    EN_CAMINO.add(e._entrega);
    subirEscaneo(e, prep, true, enTelefono).catch(err => {
      const enLista = leerPendientes().some(x => x && x.fila && prep.filas.some(f => f.id === x.fila.id));
      if(T && T.id === tid) avisar('Recovered a floor plan scan that was not saved, but it could not be uploaded. ' + String(err && err.message || err) + (enLista ? ' It stays saved on this phone.'
        : esErrorDeRed(err) ? ' It stays on this phone and is saved by itself when there is signal.' : ' It stays on this phone: open Floor Plan again to retry.'));
    }).finally(() => EN_CAMINO.delete(e._entrega));
  }
  return n;
}
// (17-oct) Los proyectos con un escaneo que el escáner dejó en este teléfono y ninguna página guardó (de cualquier proyecto):
// [{ trabajo, n, desde }]. Para el aviso de Home y para abrir ese proyecto directo en Floor Plan. Aparato viejo: [].
export async function trabajosConEscaneoSinGuardar(){
  const RS = rs(); if(!RS || !RS.pendientes) return [];
  try{ const r = await RS.pendientes({}); return ((r && r.trabajos) || []).filter(x => x && x.trabajo && Number(x.n) > 0).map(x => ({ trabajo: String(x.trabajo).toLowerCase(), n: Number(x.n), desde: x.desde || '' })); }
  catch(e){ return []; }
}
// (17-oct) VOLVER A MIRAR las copias del escáner: cuando el aparato avisa que dejó una (una página recargada con el escáner
// abierto no recibe la respuesta de scan(), pero sí este aviso), al volver la señal y al regresar a la app. Las del último
// proyecto abierto en Floor Plan se guardan; Home dice cuáles quedan. Con un escaneo en curso en esta página, nada: su
// respuesta llega por scan().
let LISTA_INICIO = null;
export function usarListaDeInicio(f){ LISTA_INICIO = f; }
async function revisarTelefono(){
  if(OCUPADO) return;
  try{
    if(T && CARGADO === T.id) await recogerEscaneos(T.id);
    if(LISTA_INICIO) await pintarAvisoDeInicio(LISTA_INICIO());
  }catch(e){}
}
// El aviso de Home: uno por proyecto (solo los de la lista de esta cuenta), con "Open it". Se quita solo cuando ya se guardó.
let SEQ_INICIO = 0;
export async function pintarAvisoDeInicio(proyectos){
  const caja = typeof document !== 'undefined' && document.getElementById ? document.getElementById('inicioPlanos') : null; if(!caja) return;
  const seq = ++SEQ_INICIO, l = await trabajosConEscaneoSinGuardar();
  if(seq !== SEQ_INICIO) return;
  const filas = l.map(x => ({ x, t: (proyectos || []).find(p => p && String(p.id).toLowerCase() === x.trabajo) })).filter(y => y.t);
  caja.hidden = !filas.length;
  caja.innerHTML = filas.map(({ x, t }) => `<div class="ini-plano">${IC('escanear')}<span><b>${x.n === 1 ? 'A floor plan scan' : x.n + ' floor plan scans'} of ${esc(t.cliente || t.direccion || 'a project')} ${x.n === 1 ? 'was' : 'were'} not saved yet.</b><br><small>${x.n === 1 ? 'It is' : 'They are'} safe on this phone. Open the project to save ${x.n === 1 ? 'it' : 'them'}.</small></span><button type="button" class="btn btn-outline" data-abrir="${esc(t.id)}">Open it</button></div>`).join('');
}
async function escanear(){
  if(OCUPADO) return;
  const RS = rs();
  if(!RS){ avisar('Scanning works in the Scanova360 app on an iPhone Pro (it needs the LiDAR camera). On the computer you can view and export the plans.'); return; }
  try{ const s = await RS.isSupported(); if(s && s.value === false){ avisar('This iPhone has no LiDAR camera, so it cannot scan a floor plan. It works on the iPhone Pro models (12 Pro and newer).'); return; } }catch(e){}
  const niv = nivelElegido(), tid = T.id; OCUPADO = true; avisar('');
  let copia = false;
  try{
    // Lo que el escáner dejó en el teléfono sin entregar se apunta primero (solo el paso del teléfono: la subida sigue sola).
    await recogerEscaneos(tid, true);
    if(!T || T.id !== tid) return;
    const entrega = nuevoId();
    const base = niv && niv.id !== SIN_NIVEL ? niv.nombre : '';
    // Los cuartos ya creados del proyecto: la cámara los enseña primero y empareja lo dicho con ellos.
    // `trabajo` + `entrega` + `nivelId` (17-oct): el escáner deja el escaneo en el teléfono antes de responder (aparato viejo: lo ignora).
    let r;
    marcarEscaner(true);
    try{ r = await RS.scan(Object.assign({ nivelBase: base, niveles: NIVELES.map(n => n.nombre) }, cuartosParaLaCamara(NIVELES, CUARTOS_P, base), { trabajo: tid, entrega, nivelId: niv && niv.id !== SIN_NIVEL ? niv.id : '' })); }
    finally{ marcarEscaner(false); }
    // Cancelado sin error: se dice (antes no salía nada y parecía guardado).
    if(!r || r.cancelled){ avisar(r && r.error ? r.error : 'Scan cancelled. No floor plan was saved.'); return; }
    // Llegó vacía o dañada (un aparato que sí deja la copia siempre manda su entrega): la copia del teléfono manda.
    if(!r._entrega && RS.pendientes && !(Array.isArray(r.rooms) && r.rooms.length)){
      // Sin los niveles del proyecto todavía, la copia espera en el teléfono (recoger no la toca): no es "sin cuartos".
      if(!NIV_LISTOS){ RECOGER_DESPUES = tid; avisar('The scan is safe on this phone. It is saved as soon as the levels of this project load (open the project again if this stays).', true); return; }
      if(!(await recogerEscaneos(tid, true))) avisar('The scan came back without any room. Nothing was saved - try again walking slowly along the walls.');
      return;
    }
    const delAparato = !!r._entrega;
    if(!r._entrega) r._entrega = entrega;   // aparato viejo: no la devuelve
    const prep = partesDelEscaneo(r, niv);
    copia = delAparato && !!RS.pendientes;   // el aparato dejó su copia: se suelta solo cuando el plano está a salvo
    await guardarEscaneo(r, prep);
  }catch(e){
    const enLista = T && leerPendientes().some(x => x.fila && x.fila.trabajo_id === T.id);
    // La lista del teléfono no cupo y la subida falló: la copia del escáner sigue en el teléfono (Floor Plan la reintenta).
    const quedaCopia = copia && !enLista;
    avisar('Could not save the floor plan. ' + String(e && e.message || e) + (enLista ? ' The scan stays saved on this phone.'
      : quedaCopia ? (esErrorDeRed(e) ? ' The scan stays on this phone and is saved by itself when there is signal. You do not need to scan again.' : ' The scan stays on this phone: open Floor Plan again to retry.') : ''));
  }
  finally{ OCUPADO = false; }
}

// ---------- exportar (PNG del plano, como la foto: hoja de compartir en el teléfono) ----------
// La letra de la marca (Plus Jakarta Sans) DENTRO de la imagen que se exporta: un SVG dibujado como imagen no
// puede pedir letras de afuera y el navegador la cambiaba por otra (su pedido del 14-oct: siempre el estilo de
// Scanova). Se baja una vez y se guarda; sin internet, la hoja sale igual con la letra del sistema.
let FUENTE_MARCA = null;
async function fuenteMarca(){
  if(FUENTE_MARCA !== null) return FUENTE_MARCA;
  try{
    const css = await fetch('https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;600;700;800&display=swap').then(r => r.ok ? r.text() : '');
    const caras = [...css.matchAll(/@font-face\s*{([^}]*)}/g)].map(m => m[1]).filter(b => /latin;|U\+0000-00FF/.test(b) || !/unicode-range/.test(b));
    let out = '';
    for(const b of caras){
      const peso = (b.match(/font-weight:\s*(\d+)/) || [])[1] || '400', src = (b.match(/url\((https:[^)]+)\)/) || [])[1];
      if(!src) continue;
      const buf = await fetch(src).then(r => r.arrayBuffer()); let bin = ''; const u8 = new Uint8Array(buf);
      for(let i = 0; i < u8.length; i += 0x8000) bin += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000));
      out += `@font-face{font-family:'Plus Jakarta Sans';font-weight:${peso};src:url(data:font/woff2;base64,${btoa(bin)}) format('woff2');}`;
    }
    FUENTE_MARCA = out;
  }catch(e){ FUENTE_MARCA = ''; }
  return FUENTE_MARCA;
}
// La hoja del plano pintada en un lienzo (la misma del botón exportar; Documents la pone en su PDF).
export async function lienzoDelPlano(data, trabajo, maxLado = 3600){
  let svg = svgDelPlano(data, trabajo);
  const fuente = await fuenteMarca();
  if(fuente) svg = svg.replace(/(<svg[^>]*>)/, `$1<defs><style>${fuente}</style></defs>`);
  const m = svg.match(/viewBox="([\d.\-]+) ([\d.\-]+) ([\d.]+) ([\d.]+)"/); const w = m ? +m[3] : 2000, h = m ? +m[4] : 1400;
  const k = Math.min(2, maxLado / Math.max(w, h)); const c = document.createElement('canvas'); c.width = Math.round(w * k); c.height = Math.round(h * k);
  const ctx = c.getContext('2d'); ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, c.width, c.height);
  const url = URL.createObjectURL(new Blob([svg.includes('xmlns=') ? svg : svg.replace('<svg', '<svg xmlns="http://www.w3.org/2000/svg"')], { type:'image/svg+xml' }));
  try{ const im = await new Promise((ok, no) => { const i = new Image(); i.onload = () => ok(i); i.onerror = () => no(new Error('could not draw the plan')); i.src = url; }); ctx.drawImage(im, 0, 0, c.width, c.height); }
  finally{ URL.revokeObjectURL(url); }
  return c;
}
async function pngDelPlano(p){
  const c = await lienzoDelPlano(p.data, T);
  return new Promise((ok, no) => c.toBlob(b => { c.width = c.height = 0; b ? ok(b) : no(new Error('could not make the image')); }, 'image/png'));
}
async function exportar(){
  const niv = nivelElegido(); const p = planoDe(PLANOS, niv.id); if(!p || OCUPADO) return;
  OCUPADO = true;
  try{
    const blob = await pngDelPlano(p);
    const nombre = ('FloorPlan ' + (T.cliente || 'Project') + ' ' + niv.nombre).replace(/[^\w\- ]+/g, '').trim().replace(/\s+/g, '_') + '.png';
    const archivo = new File([blob], nombre, { type:'image/png' });
    if(!esAparato() && !/iPhone|iPad|Android/i.test(navigator.userAgent)){
      const u = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = u; a.download = nombre; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(u), 4000);
      OCUPADO = false; avisar('Downloaded ' + nombre, true);
    } else if(navigator.canShare && navigator.canShare({ files:[archivo] })){ await navigator.share({ files:[archivo], title: nombre }); OCUPADO = false; }
    else { const u = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = u; a.download = nombre; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(u), 4000); OCUPADO = false; avisar('Downloaded ' + nombre, true); }
  }catch(e){ OCUPADO = false; if(!(e && e.name === 'AbortError')) avisar('Could not export the plan. ' + String(e && e.message || e)); }
}

// ---------- pantalla completa (capa dentro de la app, como la foto grande) ----------
function grande(){
  const niv = nivelElegido(); const p = planoDe(PLANOS, niv.id); if(!p) return;
  let capa = $('#plGrande'); if(!capa){ capa = document.createElement('div'); capa.id = 'plGrande'; capa.className = 'pl-grande'; ($('.app') || document.body).appendChild(capa); }
  capa.innerHTML = `<div class="pl-grande-cab"><b>${esc(T.cliente || '')} · ${esc(niv.nombre)}</b><button type="button" class="pl-grande-x" data-pl-grande-x aria-label="Close">✕</button></div><div class="pl-grande-lienzo">${svgDelPlano(p.data, T, true)}</div>`;
  capa.hidden = false; document.body.classList.add('con-visor');
  PZ_GRANDE.s = 1; PZ_GRANDE.x = 0; PZ_GRANDE.y = 0; const lg = capa.querySelector('.pl-grande-lienzo'); if(lg) pellizco(lg, lg.querySelector('svg'), PZ_GRANDE);
}
function cerrarGrande(){ const c = $('#plGrande'); if(c){ c.hidden = true; c.innerHTML = ''; } document.body.classList.remove('con-visor'); }

export function conectar(){
  // (17-oct) El aparato avisa cada vez que deja un escaneo en el teléfono (RoomPlanPlugin, "escaneoEnTelefono").
  const RS = rs();
  if(RS && RS.addListener){ try{ const x = RS.addListener('escaneoEnTelefono', () => { revisarTelefono(); }); if(x && x.catch) x.catch(() => {}); }catch(e){} }
  document.addEventListener('click', async (e) => {
    const q = (s) => e.target.closest(s); let el;
    if(q('[data-pl-grande-x]')){ cerrarGrande(); return; }
    if(!e.target.closest('#panel-plano')){ if(MENU){ MENU = false; pintar(); } return; }
    if(q('[data-pl-menu]')){ MENU = !MENU; pintar(); return; }
    if(MENU){ MENU = false; if(!q('.pl-menu')) pintar(); }   // tocar cualquier otra cosa cierra el menú
    if((el = q('[data-pl-nivel]'))){ NIV_SEL = el.dataset.plNivel; PL_CERRADO = false; ZOOM = 1; PZ.s = 1; PZ.x = 0; PZ.y = 0; AVISO = ''; pintar(); return; }
    if((el = q('[data-pl-tel-niv]'))){
      const id = el.dataset.plTelNiv;
      if(id === nivelElegido().id && !PL_CERRADO) PL_CERRADO = true;
      else { NIV_SEL = id; PL_CERRADO = false; ZOOM = 1; PZ.s = 1; PZ.x = 0; PZ.y = 0; AVISO = ''; }
      pintar(); if(!PL_CERRADO){ const m = $('#main'); if(m) m.scrollTop = 0; } return; }
    if((el = q('[data-pl-vista]'))){
      if(el.dataset.plVista === '3d'){
        // (17-oct) Solo con un plano guardado en este nivel, y solo el escaneo de ESE plano: antes salía en AR el último
        // escaneo del teléfono aunque nunca se hubiera guardado, y parecía que sí estaba guardado. Cuenta también el que
        // espera señal en este teléfono (es el más nuevo de su nivel).
        const p = plano3d(nivelElegido().id); if(!p) return;
        const RS = rs();
        if(RS && RS.viewModel){ try{ const r = await RS.viewModel({ entrega: (p.data && p.data._entrega) || '-' }); if(r && r.error) avisar('3D view: ' + r.error + ' The 3D model opens only on the iPhone that made the scan, for its last scan, until the app is closed.'); }catch(err){ avisar('Could not open the 3D view.'); } }
        else avisar('The 3D view opens in the Scanova360 app on the iPhone, right after scanning a floor.');
        return;
      }
      VISTA = '2d'; pintar(); return;
    }
    if(q('[data-pl-rejilla]')){ REJILLA = !REJILLA; pintar(); return; }
    if((el = q('[data-pl-zoom]'))){ ZOOM = Math.max(0.5, Math.min(3, Math.round((ZOOM + Number(el.dataset.plZoom) * 0.25) * 100) / 100)); pintar(); return; }
    if(q('[data-pl-grande]')){ grande(); return; }
    if(q('[data-pl-escanear]')){ escanear(); return; }
    if(q('[data-pl-borrar]')){ borrarPlano(); return; }
    if(q('[data-pl-subir]')){ const b = q('[data-pl-subir]'); b.disabled = true; b.textContent = 'Uploading…'; subirPendientes(true); return; }
    if(q('[data-pl-exportar]')){ exportar(); return; }
    if(q('[data-pl-mas-nivel]')){ if(AL_NIVEL) AL_NIVEL(); return; }
    if(q('[data-pl-editar]')){ avisar('Editing the plan (move walls, rename rooms, add doors) is the next step being built. For now you can scan, view, zoom and export.'); return; }
    if(q('[data-pl-ajustes]')){ avisar('Plan settings (units, ceiling height) come with the editing step.'); return; }
  });
  document.addEventListener('change', (e) => { if(e.target.id === 'plNivelSel'){ NIV_SEL = e.target.value; ZOOM = 1; AVISO = ''; pintar(); } });
  document.addEventListener('keydown', (e) => { if(e.key === 'Escape') cerrarGrande(); });
}
