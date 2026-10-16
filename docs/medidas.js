// Scanova360 · pestaña MEASUREMENTS (15 oct 2026). Su pedido: "debes copiar todo lo que ya tenemos en Field Report de la
// carpeta de measurements". Lo que se DEMOLIÓ, cuarto por cuarto, igual que Medidas de Field Reports:
//  · seis partes: Floor, Wall, Ceiling, Kitchen, Bathroom y Materials, con las MISMAS listas de materiales y en el mismo orden;
//  · cada medida es un "corte": largo × ancho = pies cuadrados; solo el largo = pies lineales; lo que se cuenta (un
//    inodoro, una tina) va por pieza (EA). Las tres unidades NUNCA se suman entre sí ("cada line item es diferente");
//  · el acompañante (insulación detrás del drywall, pad debajo de la alfombra, shoe molding con el baseboard) se
//    PREGUNTA, nunca se agrega solo (su regla del 11 de septiembre);
//  · la cámara que mide (la misma de Field Reports, ya viene en el aparato de Scanova) con el nivel escogido UNA vez en
//    pantalla y los cuartos de ese nivel ya propuestos; al terminar, todo se guarda solo y se ve aquí;
//  · la revisión por NIVEL → CUARTO → material, con lo de cada cuarto sumado por material, y con 2 cuartos o más el total
//    del trabajo por partida; las notas; y el PDF "Measurements & Demo" (lo arma Documents).
// Lo que cambia contra Field Reports: aquí el trabajo ya es el proyecto (cliente, dirección y fecha ya están), y los
// niveles y cuartos son los del proyecto (los mismos de Photos y Dry Logs).
import { $, authFetch, esAparato, esManager, preguntar, PERFIL } from './app.js?v=2026-10-16-2';

const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
const IC = (n, cls) => '<svg class="ic' + (cls ? ' ' + cls : '') + '"><use href="#i-' + n + '"/></svg>';

// ---------- lo puro (las listas de Field Reports, en su orden) ----------
export const SECCIONES = [['floor', 'Floor'], ['wall', 'Wall'], ['ceiling', 'Ceiling'], ['kitchen', 'Kitchen'], ['bathroom', 'Bathroom'], ['materiales', 'Materials']];
export const SUPERFICIE = Object.fromEntries(SECCIONES);
export const MATERIALES = {
  floor: ['Laminate', 'Tile', 'Hardwood', 'Vinyl (LVP)', 'Carpet', 'Carpet Pad', 'Underlayment', 'Plywood', 'Subfloor', 'Concrete', 'Tackless Strip'],
  wall: ['Drywall', 'Plaster', 'Stud / Framing', 'Insulation', 'Baseboard', 'Shoe Molding', 'Trim', 'Crown Molding'],
  ceiling: ['Drywall', 'Plaster', 'Insulation', 'Popcorn / Texture'],
  kitchen: ['Countertop', 'Cabinets', 'Stove / Range', 'Refrigerator', 'Sink', 'Backsplash', 'Toe Kick', 'Dishwasher', 'Range Hood / Microwave'],
  // El baño en el orden en que se demuele la pared de la regadera, de adentro hacia afuera (su corrección del 27-sep).
  bathroom: ['Shower Tile', 'Floor Tile', 'Thinset / Mortar Bed', 'Cement Board', 'Greenboard', 'Vapor Barrier', 'Shower Pan', 'Shower Surround', 'Shower Door',
    'Plywood / Underlayment', 'Subfloor', 'Bathtub', 'Vanity', 'Vanity Top', 'Toilet', 'Medicine Cabinet', 'Exhaust Fan', 'Mirror', 'Towel Bar', 'Shower Curb', 'Shower Drain'],
  // Solo el plástico y la protección de piso: los tubos, buckets y zip poles ya van en el equipo (cobrarlos dos veces no).
  materiales: ['Plastic sheeting (cover)', '6 mil containment plastic', 'Floor protection'],
};
// Lo que se CUENTA en vez de medirse (EA). El número viaja en el largo, como en Field Reports.
// (El espejo se mide desde el 15-oct-2026: Xactimate lo cobra por pie cuadrado del vidrio.)
export const POR_PIEZA = new Set(['Toilet', 'Bathtub', 'Shower Pan', 'Shower Surround', 'Shower Door', 'Medicine Cabinet', 'Exhaust Fan', 'Towel Bar', 'Shower Drain',
  'Stove / Range', 'Refrigerator', 'Sink', 'Dishwasher', 'Range Hood / Microwave']);
export const esPorPieza = (m) => POR_PIEZA.has(String(m || '').trim());
// CADA MATERIAL CON SU UNIDAD (15 oct 2026, igual que Field Reports). Su regla: la pared SIEMPRE largo × alto en pies
// cuadrados ("pie lineal siempre va a ser un pie de alto, 1 por 1 da 1": se acabó "2 ft o menos = pie lineal"); pie lineal
// solo lo que no tiene alto que medir y los gabinetes; tile y drywall pie cuadrado; countertop pie cuadrado; vanity top
// pie lineal. Una pared sin alto NO se vuelve pie lineal: queda "missing height" y no se cobra.
export const LINEAL = new Set(['Baseboard', 'Trim / Baseboard', 'Shoe Molding', 'Trim', 'Crown Molding', 'Tackless Strip', 'Toe Kick', 'Cabinets', 'Vanity', 'Vanity Top', 'Shower Curb']);
// 'EA' | 'LF' | 'SF', o null para un material escrito a mano (no se le inventa unidad: con ancho área, sin ancho tramo).
export function unidad(m){
  m = String(m || '').trim(); if(!m) return null;
  if(POR_PIEZA.has(m)) return 'EA';
  if(LINEAL.has(m)) return 'LF';
  if(Object.values(MATERIALES).some(l => l.includes(m))) return 'SF';
  return null;
}
// Lo que va pegado detrás o debajo, en el mismo lugar: se PREGUNTA y copia el mismo tamaño.
export const ACOMPANANTE = { 'Baseboard': 'Shoe Molding', 'Trim / Baseboard': 'Shoe Molding', 'Drywall': 'Insulation', 'Plaster': 'Insulation', 'Popcorn / Texture': 'Insulation',
  'Carpet': 'Carpet Pad', 'Vinyl (LVP)': 'Underlayment', 'Laminate': 'Underlayment', 'Shower Tile': 'Cement Board', 'Floor Tile': 'Thinset / Mortar Bed',
  'Cement Board': 'Vapor Barrier', 'Greenboard': 'Insulation' };
// Lo que la CÁMARA enseña y oye de cada material: las mismas etiquetas de Field Reports (la cuadrilla dice "tablaroca"),
// y en español lo que pregunta del acompañante ("¿lleva Insulación?"). En la pantalla de Scanova sale solo el inglés.
export const ETIQUETA_CAMARA = { 'Laminate': 'Laminate / Laminado', 'Tile': 'Tile / Baldosa', 'Hardwood': 'Hardwood / Madera', 'Vinyl (LVP)': 'Vinyl LVP / Vinilo',
  'Carpet': 'Carpet / Alfombra', 'Carpet Pad': 'Carpet Pad / Almohadilla', 'Underlayment': 'Underlayment / Base', 'Plywood': 'Plywood / Triplay', 'Subfloor': 'Subfloor / Subpiso',
  'Concrete': 'Concrete / Concreto', 'Drywall': 'Drywall / Tablaroca', 'Plaster': 'Plaster / Yeso', 'Stud / Framing': 'Stud / Framing / Armazón', 'Insulation': 'Insulación / Insulation',
  'Baseboard': 'Baseboard / Zócalo', 'Shoe Molding': 'Shoe Molding / Moldura de Zapata', 'Trim': 'Trim / Marco de puerta y ventana', 'Crown Molding': 'Crown Molding / Moldura de Corona',
  'Popcorn / Texture': 'Popcorn Texture / Textura', 'Countertop': 'Countertop / Cubierta', 'Cabinets': 'Cabinets / Gabinetes', 'Stove / Range': 'Stove / Range / Estufa',
  'Refrigerator': 'Refrigerator / Refrigerador', 'Sink': 'Sink / Fregadero', 'Backsplash': 'Backsplash / Salpicadero', 'Toe Kick': 'Toe Kick / Zócalo de Gabinete',
  'Shower Tile': 'Shower Tile / Azulejo de la regadera', 'Floor Tile': 'Floor Tile / Azulejo del piso', 'Thinset / Mortar Bed': 'Thinset / Mortar Bed / Mortero',
  'Cement Board': 'Cement Board (Durock) / Tabla de cemento', 'Greenboard': 'Greenboard / Tablaroca verde (de humedad)', 'Vapor Barrier': 'Vapor Barrier / Barrera de vapor',
  'Shower Pan': 'Shower Pan / Base de la regadera', 'Shower Surround': 'Shower Surround / Cubierta de la regadera', 'Shower Door': 'Shower Door / Puerta de la regadera',
  'Plywood / Underlayment': 'Plywood / Underlayment / Triplay', 'Bathtub': 'Bathtub / Tina', 'Vanity': 'Vanity / Tocador', 'Vanity Top': 'Vanity Top / Cubierta del tocador',
  'Toilet': 'Toilet / Inodoro', 'Medicine Cabinet': 'Medicine Cabinet / Botiquín', 'Exhaust Fan': 'Exhaust Fan / Extractor', 'Mirror': 'Mirror / Espejo', 'Towel Bar': 'Towel Bar / Toallero',
  'Plastic sheeting (cover)': 'Nailo, plástico para cubrir / Plastic sheeting (cover)', '6 mil containment plastic': 'Plástico 6 mil de contención / 6 mil containment plastic',
  'Floor protection': 'Protección de piso / Floor protection',
  'Tackless Strip': 'Tackless Strip / Tira de clavos', 'Dishwasher': 'Dishwasher / Lavaplatos', 'Range Hood / Microwave': 'Range Hood / Microwave / Campana o microondas',
  'Shower Curb': 'Shower Curb / Bordillo de la regadera', 'Shower Drain': 'Shower Drain / Coladera de la regadera' };
export const ACOMPANANTE_ES = { 'Shoe Molding': 'shoe molding', 'Insulation': 'Insulación', 'Carpet Pad': 'Almohadilla de Alfombra', 'Underlayment': 'Base/Underlayment',
  'Cement Board': 'tabla de cemento (Durock)', 'Thinset / Mortar Bed': 'mortero', 'Vapor Barrier': 'barrera de vapor' };
// Los cuartos que ofrece la cámara después de los del proyecto (la lista de Field Reports, en inglés: van al seguro).
export const CUARTOS_CATALOGO = ['Living Room', 'Family Room', 'Kitchen', 'Dining Room', 'Master Bedroom', 'Bedroom', 'Bathroom', 'Master Bathroom', 'Hallway', 'Laundry Room',
  'Garage', 'Basement', 'Attic', 'Office', 'Closet', 'TV Room', 'Storage Room', 'Utility Room', 'Stairs', 'Kids Bedroom', 'Guest Bedroom', 'Guest Bathroom', 'Half Bathroom', 'Gym', 'Pantry'];
export const NIVELES_COMUNES = ['Basement', 'First Floor', 'Second Floor', 'Third Floor', 'Attic'];
const r2 = (v) => Math.round(v * 100) / 100;
const norm = (s) => String(s || '').trim().toLowerCase();
const num = (v) => { const n = parseFloat(v); return isFinite(n) && n > 0 ? n : 0; };
// Lo que vale un corte, según la UNIDAD de su material (15-oct-2026). faltaAlto: es de superficie y solo trae el largo.
export function calcular(material, largo, ancho){
  const a = num(largo), b = num(ancho), u = unidad(material);
  if(u === 'EA') return { sqft: 0, linear: 0, piezas: a ? Math.round(a) : 0, faltaAlto: false };
  if(u === 'LF') return { sqft: 0, linear: a ? r2(a) : 0, piezas: 0, faltaAlto: false };
  if(u === 'SF') return { sqft: a && b ? r2(a * b) : 0, linear: 0, piezas: 0, faltaAlto: !!a && !b };
  if(a && b) return { sqft: r2(a * b), linear: 0, piezas: 0, faltaAlto: false };
  return { sqft: 0, linear: a ? r2(a) : 0, piezas: 0, faltaAlto: false };
}
// "120 sq ft + 40 linear ft": nunca sumados entre sí.
export function totalTexto(sqft, linear, piezas){
  const bits = [];
  if(sqft > 0) bits.push(r2(sqft) + ' sq ft');
  if(linear > 0) bits.push(r2(linear) + ' linear ft');
  if(piezas > 0) bits.push(Math.round(piezas) + ' EA');
  return bits.join(' + ');
}
// Cantidad y unidad por separado, como se lee un estimado (SF / LF / EA). Si un material trae dos unidades, la cantidad
// queda vacía y todo va en la unidad (no se inventa una sola).
export function qtyUnidad(sqft, linear, piezas){
  const cuantas = (sqft > 0 ? 1 : 0) + (linear > 0 ? 1 : 0) + (piezas > 0 ? 1 : 0);
  if(cuantas !== 1) return { qty: '', unidad: totalTexto(sqft, linear, piezas).replace(/ sq ft/g, ' SF').replace(/ linear ft/g, ' LF') };
  if(piezas > 0) return { qty: String(Math.round(piezas)), unidad: 'EA' };
  if(sqft > 0) return { qty: String(r2(sqft)), unidad: 'SF' };
  return { qty: String(r2(linear)), unidad: 'LF' };
}
// Una línea por unidad, como se escribe un estimado: si un material trae SF y LF salen dos renglones (nunca uno partido).
// Con cuartos por unidad (las partidas del trabajo) cada renglón dice en cuántos cuartos va ESA unidad.
export function lineasUnidad(x){
  const out = [], cu = x.cuartosU || null;
  if(x.sqft > 0) out.push({ qty: String(r2(x.sqft)), unidad: 'SF', cuartos: cu ? cu.sf : x.cuartos });
  if(x.linear > 0) out.push({ qty: String(r2(x.linear)), unidad: 'LF', cuartos: cu ? cu.lf : x.cuartos });
  if(x.piezas > 0) out.push({ qty: String(Math.round(x.piezas)), unidad: 'EA', cuartos: cu ? cu.ea : x.cuartos });
  // Lo que le falta su segunda medida no se cobra, pero se DICE (15-oct-2026).
  if(x.faltaAlto > 0) out.push({ qty: '—', unidad: 'missing height', cuartos: cu ? cu.fa : x.cuartos });
  return out;
}
// "12 × 2 ft", "38 ft", "2 each".
export function medidaTexto(f){
  const u = unidad(f.material);
  if(u === 'EA') return Math.round(num(f.largo)) + ' each';
  const a = num(f.largo), b = num(f.ancho);
  if(u === 'LF') return r2(a) + ' ft';
  return a && b ? r2(a) + ' × ' + r2(b) + ' ft' : r2(a) + ' ft' + (u === 'SF' ? ' · missing height' : '');
}
const RANGO_SECCION = { floor: 0, wall: 1, ceiling: 2, kitchen: 3, bathroom: 4, materiales: 5 };
// Las medidas -> niveles -> cuartos -> materiales, ya sumadas. Los niveles en el orden del proyecto; los cuartos y los
// materiales en el orden en que se MIDIERON (el papel sigue el recorrido de la casa, y el acompañante sale junto al suyo).
export function agrupar(filas, niveles, cuartos){
  const nivPorId = new Map((niveles || []).map((n, i) => [n.id, { n, i }]));
  const cuaPorId = new Map((cuartos || []).map(c => [c.id, c]));
  const lista = (filas || []).slice().sort((a, b) => (Number(a.orden) || 0) - (Number(b.orden) || 0) || String(a.created_at || '').localeCompare(String(b.created_at || '')));
  const L = new Map();
  lista.forEach(f => {
    const nv = f.nivel_id && nivPorId.get(f.nivel_id);
    const nivelTit = nv ? nv.n.nombre : String(f.nivel_nombre || '').trim();
    const claveN = nv ? 'id:' + f.nivel_id : 'n:' + nivelTit.toLowerCase();
    let N = L.get(claveN);
    if(!N){ N = { clave: claveN, nivel_id: nv ? f.nivel_id : null, titulo: nivelTit || 'Level not specified', rango: nv ? nv.i : (nivelTit ? 900 : 990), orden: L.size, cuartos: new Map() }; L.set(claveN, N); }
    const cu = f.cuarto_id && cuaPorId.get(f.cuarto_id);
    const cuartoTit = cu ? cu.nombre : String(f.cuarto_nombre || '').trim();
    const claveC = cu ? 'id:' + f.cuarto_id : 'n:' + cuartoTit.toLowerCase();
    let C = N.cuartos.get(claveC);
    if(!C){ C = { clave: claveC, cuarto_id: cu ? f.cuarto_id : null, nivel_id: N.nivel_id, nivel: N.titulo, titulo: cuartoTit || 'Room not specified',
      nivel_nombre: nv ? '' : nivelTit, cuarto_nombre: cu ? '' : cuartoTit, orden: N.cuartos.size, materiales: new Map(), filas: [] }; N.cuartos.set(claveC, C); }
    C.filas.push(f);
    const r = calcular(f.material, f.largo, f.ancho);
    const claveM = f.material + '|' + f.seccion;
    let M = C.materiales.get(claveM);
    if(!M){ M = { material: f.material, seccion: f.seccion, superficie: SUPERFICIE[f.seccion] || f.seccion, orden: C.materiales.size, sqft: 0, linear: 0, piezas: 0, faltaAlto: 0, filas: [] }; C.materiales.set(claveM, M); }
    M.filas.push(f); M.sqft += r.sqft; M.linear += r.linear; M.piezas += r.piezas; if(r.faltaAlto) M.faltaAlto++;
  });
  const porOrden = (x, y) => x.orden - y.orden;
  const nivelesOut = [...L.values()].sort((x, y) => (x.rango - y.rango) || (x.orden - y.orden)).map(N => ({
    clave: N.clave, nivel_id: N.nivel_id, titulo: N.titulo,
    cuartos: [...N.cuartos.values()].sort(porOrden).map(C => ({
      clave: C.clave, cuarto_id: C.cuarto_id, nivel_id: C.nivel_id, nivel: C.nivel, titulo: C.titulo, nivel_nombre: C.nivel_nombre, cuarto_nombre: C.cuarto_nombre, filas: C.filas,
      materiales: [...C.materiales.values()].sort(porOrden).map(M => ({ ...M, sqft: r2(M.sqft), linear: r2(M.linear) })),
    })),
  }));
  // El total del trabajo por partida (material × superficie): con cuántos cuartos lo traen.
  const P = new Map(); let nCuartos = 0;
  nivelesOut.forEach(N => N.cuartos.forEach(C => {
    if(C.materiales.length) nCuartos++;
    C.materiales.forEach(M => {
      const k = M.material + '|' + M.seccion; let p = P.get(k);
      if(!p){ p = { material: M.material, seccion: M.seccion, superficie: M.superficie, orden: P.size, cuartos: 0, cuartosU: { sf: 0, lf: 0, ea: 0, fa: 0 }, sqft: 0, linear: 0, piezas: 0, faltaAlto: 0 }; P.set(k, p); }
      p.cuartos++; p.sqft += M.sqft; p.linear += M.linear; p.piezas += M.piezas; p.faltaAlto += M.faltaAlto;
      if(M.sqft > 0) p.cuartosU.sf++; if(M.linear > 0) p.cuartosU.lf++; if(M.piezas > 0) p.cuartosU.ea++; if(M.faltaAlto > 0) p.cuartosU.fa++;
    });
  }));
  const partidas = [...P.values()].sort((x, y) => ((RANGO_SECCION[x.seccion] ?? 9) - (RANGO_SECCION[y.seccion] ?? 9)) || (x.orden - y.orden))
    .map(p => ({ ...p, sqft: r2(p.sqft), linear: r2(p.linear) }));
  return { niveles: nivelesOut, partidas, nCuartos, total: lista.length };
}
// Lo que trae la cámara -> las filas que se guardan. El acompañante que la persona dijo que sí, con el mismo tamaño.
export function filasDeCamara(medidas, base){
  const out = []; let k = 0;
  (medidas || []).forEach(m => {
    const seccion = SUPERFICIE[m && m.seccion] ? m.seccion : 'floor';
    const material = String(m && m.material || '').trim(); const largo = num(m && m.length);
    if(!material || !largo) return;
    const pieza = esPorPieza(material), ancho = pieza ? null : (num(m.width) || null);
    // Los nombres van a la lista de niveles y cuartos del proyecto, que acepta hasta 60 letras.
    const nivel = String(m.nivel || base.nivel || '').trim().slice(0, 60);
    // El cuarto de donde se empezó solo vale si la medida es de ESE nivel (en "Several levels" la cámara cambia de piso).
    const cuarto = String(m.cuarto || (norm(nivel) === norm(base.nivel) ? base.cuarto : '') || '').trim().slice(0, 60);
    const fila = { nivel, cuarto, seccion, material,
      largo: pieza ? Math.max(1, Math.round(largo)) : r2(largo), ancho: ancho ? r2(ancho) : null, orden: base.orden + (k++) };
    out.push(fila);
    const comp = String(m.companion || '').trim();
    if(comp && !esPorPieza(comp)) out.push({ ...fila, material: comp, orden: base.orden + (k++) });
  });
  return out;
}
// ---------- en la página ----------
let T = null, NIVELES = [], CUARTOS = [], FILAS = [], NOTA = '', NOTA_ED = null, CARGADO = null, CARGANDO = false, FALTA_SQL = false, FALLO = '', AVISO = '', AVISO_OK = false;
// Tres trabajos que pueden ir a la vez sin estorbarse: guardar del editor, guardar lo de la cámara y hacer el PDF.
let ALCANCE = false, GUARDANDO = false, CAMARA = false, HACIENDO_PDF = false, ED = null, AYUDA = {}, ULTIMO = null;
// Lo que se guardó o borró mientras una carga venía en camino: se vuelve a poner encima de lo que llegó (sin repetir ni perder).
let GEN = 0; const CAMBIOS = [];
function anotar(c, trabajo){ GEN++; CAMBIOS.push({ ...c, gen: GEN, trabajo }); if(CAMBIOS.length > 300) CAMBIOS.splice(0, CAMBIOS.length - 300); }
const unir = (lista, nuevas) => { const m = new Map(lista.map(x => [x.id, x])); nuevas.forEach(x => m.set(x.id, x)); return [...m.values()]; };
const msg = (e) => String(e && e.message || e);
// Lo que trajo la cámara se guarda PRIMERO en este aparato: si la señal falla o se abre otro proyecto, no se pierde el
// recorrido ("Try again" lo vuelve a mandar con los mismos ids, así nunca se repite una medida).
const LLAVE_PEND = (id) => 'scanova.medidas.pendientes.' + id;
function pendientes(id){ try{ const v = JSON.parse(localStorage.getItem(LLAVE_PEND(id)) || 'null'); return Array.isArray(v) && v.length ? v : null; }catch{ return null; } }
function guardarPendientes(id, nuevas){ try{ localStorage.setItem(LLAVE_PEND(id), JSON.stringify(nuevas)); return true; }catch{ return false; } }
function soltarPendientes(id){ try{ localStorage.removeItem(LLAVE_PEND(id)); }catch{} }
const nuevoId = () => (window.crypto && crypto.randomUUID) ? crypto.randomUUID()
  : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); });
// Lo que la ficha le presta: escoger o crear nivel y cuarto, releerlos del servidor, y el PDF de Documents.
export function usar(ayuda){ AYUDA = ayuda || {}; }
const caja = () => $('#panel-medidas');
const camaraLista = () => !!(esAparato() && window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.ARMeasure);
export function pintar(t, niveles, cuartos){
  if(!t) return;
  if(!T || T.id !== t.id){ CARGADO = null; FILAS = []; NOTA = ''; NOTA_ED = null; ALCANCE = false; AVISO = ''; AVISO_OK = false; FALLO = ''; cerrarEditor(); }
  T = t; NIVELES = niveles || []; CUARTOS = cuartos || [];
  if(CARGADO !== T.id) cargar();
  pintarAqui();
}
// Al abrir la pestaña: lo más nuevo (otro del equipo pudo medir hace un minuto).
export function entrar(){ CARGADO = null; }
export const filas = () => FILAS.slice();
export const nota = () => NOTA;
async function cargar(){
  if(!T || CARGANDO) return; const id = T.id, g0 = GEN; CARGANDO = true;
  try{
    const [r, n] = await Promise.all([
      authFetch('/rest/v1/fotos_medidas?trabajo_id=eq.' + encodeURIComponent(id) + '&order=orden.asc,created_at.asc&limit=5000'),
      authFetch('/rest/v1/fotos_medidas_notas?trabajo_id=eq.' + encodeURIComponent(id) + '&select=texto'),
    ]);
    if(!T || T.id !== id) return;
    FALTA_SQL = r.status === 404; FALLO = '';
    if(!r.ok && !FALTA_SQL){ FALLO = 'Could not load the measurements (HTTP ' + r.status + ').'; CARGADO = id; return; }
    let lista = r.ok ? await r.json() : [];
    CAMBIOS.filter(c => c.gen > g0 && c.trabajo === id).forEach(c => { lista = c.quita ? lista.filter(x => x.id !== c.quita) : unir(lista, [c.fila]); });
    FILAS = lista;
    if(n.ok){ const ns = await n.json(); NOTA = (ns[0] && ns[0].texto) || ''; }
    CARGADO = id;
  }catch(e){ if(T && T.id === id){ CARGADO = id; FALLO = 'Could not load the measurements. ' + msg(e); } }
  // Si mientras tanto se abrió otro proyecto, se carga ese (si no, se quedaba en "Loading…" para siempre).
  finally{ CARGANDO = false; if(T && T.id !== id && CARGADO !== T.id) cargar(); else pintarAqui(); }
}
const avisoHtml = () => `<p class="aviso${AVISO_OK ? ' ok' : ''}" id="medAviso">${esc(AVISO)}</p>`;
function avisar(t, ok){ AVISO = t || ''; AVISO_OK = !!ok; const a = $('#medAviso'); if(a){ a.textContent = AVISO; a.classList.toggle('ok', AVISO_OK); } }
function pintarAqui(){
  const c = caja(); if(!c || !T) return;
  if(CARGADO !== T.id){ c.innerHTML = '<p class="vacio">Loading measurements…</p>'; return; }
  if(FALTA_SQL){ c.innerHTML = '<div class="card"><h2 class="sec-t">Measurements</h2><p class="aviso">Measurements are not set up on the server yet (falta correr sql/fotos-12-medidas.sql).</p></div>'; return; }
  // No pisar las notas que se están escribiendo.
  const ta = c.querySelector('#medNotaTxt'), enNota = !!(ta && document.activeElement === ta); if(enNota) NOTA_ED = ta.value;
  const g = agrupar(FILAS, NIVELES, CUARTOS), cam = camaraLista(), pend = pendientes(T.id);
  const botones = `${cam ? `<button type="button" class="btn btn-accent" data-med-camara${CAMARA ? ' disabled' : ''}>${IC('regla')}Measure with camera</button>` : ''}
      <button type="button" class="btn ${cam ? 'btn-outline' : 'btn-accent'}" data-med-nuevo>${IC('mas')}Add by hand</button>
      ${g.total ? `<button type="button" class="btn btn-outline" data-med-pdf>${IC('bajar')}PDF</button>` : ''}`;
  const alcance = ALCANCE ? `<div class="card med-alcance"><h3>What are you measuring?</h3>
      <p class="med-nota-chica">Pick the level once; inside the camera you only say the rooms.</p>
      <div class="med-alcance-ops">
        <button type="button" class="btn btn-outline" data-med-alcance="cuarto">${IC('dl-cuarto')}One room</button>
        <button type="button" class="btn btn-outline" data-med-alcance="nivel">${IC('dl-capas')}A whole level</button>
        <button type="button" class="btn btn-outline" data-med-alcance="varios">${IC('cubo')}Several levels</button>
      </div>
      <button type="button" class="btn btn-block med-cancelar" data-med-alcance-no>Cancel</button></div>` : '';
  const pendHtml = pend ? `<div class="card med-pend"><p><b>${pend.length} ${pend.length === 1 ? 'measurement' : 'measurements'} from the camera ${pend.length === 1 ? 'is' : 'are'} not saved yet.</b> They are kept on this device.</p>
      <div class="fila-botones"><button type="button" class="btn btn-outline" data-med-descartar${CAMARA ? ' disabled' : ''}>Discard</button><button type="button" class="btn btn-accent" data-med-reintentar${CAMARA ? ' disabled' : ''}>${CAMARA ? 'Saving…' : 'Try again'}</button></div></div>` : '';
  const falloHtml = FALLO ? `<div class="card med-pend"><p class="aviso">${esc(FALLO)}</p><div class="fila-botones"><button type="button" class="btn btn-outline" data-med-recargar>Try again</button></div></div>` : '';
  const vacio = !g.total && !FALLO && !pend ? `<div class="vacio-tarj">${IC('regla')}<div><b>No measurements yet.</b> ${cam ? 'Measure with the camera, or add them by hand' : 'Add what was removed, room by room'}: floor, walls, ceiling, kitchen, bathroom and the plastic used.</div></div>` : '';
  const filaHtml = (f) => `<button type="button" class="med-fila" data-med-editar="${esc(f.id)}">
      <span class="med-fila-txt"><b>${esc(f.material)}</b><small>${esc(SUPERFICIE[f.seccion] || f.seccion)} · ${esc(medidaTexto(f))}${f.origen === 'camara' ? ' · camera' : ''}</small></span>
      <span class="med-fila-res${calcular(f.material, f.largo, f.ancho).faltaAlto ? ' falta' : ''}">${esc(totalTexto(...Object.values(calcular(f.material, f.largo, f.ancho))) || (calcular(f.material, f.largo, f.ancho).faltaAlto ? 'missing height' : ''))}</span>${IC('chev-der', 'med-chev')}</button>`;
  const cuartoHtml = (C) => {
    // Lo GUARDADO, no lo que se ve: "Level not specified" es un rótulo, nunca un nombre de nivel.
    const donde = { nivel_id: C.nivel_id, cuarto_id: C.cuarto_id, nivel: C.nivel_nombre || '', cuarto: C.cuarto_nombre || '' };
    return `<section class="card med-cuarto">
      <div class="med-cuarto-cab"><h3>${esc(C.titulo)}</h3><small>${esc(C.nivel)}</small></div>
      <div class="med-filas">${C.materiales.map(M => M.filas.map(filaHtml).join('')).join('')}</div>
      ${C.materiales.some(M => M.filas.length > 1) ? `<div class="med-tot"><span>By material</span>${C.materiales.map(M => `<span class="med-tot-i"><b>${esc(M.material)}</b> <small>${esc(M.superficie)}</small> ${esc([totalTexto(M.sqft, M.linear, M.piezas), M.faltaAlto ? M.faltaAlto + ' missing height' : ''].filter(Boolean).join(' + '))}</span>`).join('')}</div>` : ''}
      <div class="med-agregar"><span>Add to this room</span><div class="med-rejilla med-partes">${SECCIONES.map(([k, t]) => `<button type="button" class="chip" data-med-agregar='${esc(JSON.stringify({ ...donde, seccion: k }))}'>+ ${t}</button>`).join('')}</div></div>
    </section>`;
  };
  const niveles = g.niveles.map(N => `<h3 class="med-nivel">${esc(N.titulo)}</h3>${N.cuartos.map(cuartoHtml).join('')}`).join('');
  const partidas = g.nCuartos > 1 && g.partidas.length ? `<section class="card med-partidas"><h3>Job totals by line item</h3>
      <div class="med-tabla-caja"><table class="med-tabla"><thead><tr><th>Material</th><th>Surface</th><th class="der">Qty</th><th>Unit</th><th class="der">Rooms</th></tr></thead><tbody>
      ${g.partidas.map(p => lineasUnidad(p).map(l => `<tr><td><b>${esc(p.material)}</b></td><td>${esc(p.superficie)}</td><td class="der"><b>${esc(l.qty)}</b></td><td>${esc(l.unidad)}</td><td class="der">${l.cuartos}</td></tr>`).join('')).join('')}
      </tbody></table></div></section>` : '';
  const notaTxt = NOTA_ED != null ? NOTA_ED : NOTA;
  const notas = g.total || NOTA ? `<section class="card med-notas"><label for="medNotaTxt"><b>Notes</b></label>
      <textarea id="medNotaTxt" placeholder="Anything the office or the adjuster should know about these measurements…">${esc(notaTxt)}</textarea>
      <div class="fila-botones"><button type="button" class="btn btn-outline" data-med-nota${notaTxt === NOTA ? ' disabled' : ''}>Save notes</button></div></section>` : '';
  c.innerHTML = `<div class="med">
    <div class="med-cab"><div class="med-cab-t"><h2 class="sec-t">Measurements</h2><p>What was removed, room by room. Sq ft, linear ft and pieces are never added together.</p></div>
      <div class="med-acc">${botones}</div></div>
    ${alcance}${avisoHtml()}${pendHtml}${falloHtml}${vacio}${niveles}${partidas}${notas}</div>`;
  if(enNota){ const n = c.querySelector('#medNotaTxt'); if(n){ n.focus(); n.setSelectionRange(n.value.length, n.value.length); } }
}

// ---------- el editor (una hoja que sube) ----------
const hoja = () => $('#hojaMedida');
function abrirEditor(e){
  ED = { id: null, nivel_id: null, cuarto_id: null, nivel: '', cuarto: '', seccion: 'floor', material: '', otro: '', largo: '', ancho: '', acomp: false, ...e };
  const h = hoja(); if(!h) return; pintarEditor(); h.hidden = false;
  setTimeout(() => { const i = h.querySelector(ED && ED.material ? '#medLargo' : '[data-med-mat]'); if(i && !('ontouchstart' in window)) i.focus(); }, 60);
}
function cerrarEditor(){ ED = null; const h = hoja(); if(h){ h.hidden = true; const f = $('#medForma'); if(f) f.innerHTML = ''; } }
const nombreNivel = (id, nombre) => { const n = NIVELES.find(x => x.id === id); return n ? n.nombre : (nombre || ''); };
const nombreCuarto = (id, nombre) => { const c = CUARTOS.find(x => x.id === id); return c ? c.nombre : (nombre || ''); };
function materialDe(e){ return e.material === 'Other' ? String(e.otro || '').trim() : e.material; }
// Lo que cambia la forma del editor (si hay tamaño que escribir, si es por pieza, si tiene acompañante).
const formaDe = (e) => { const m = materialDe(e); return [!!m, esPorPieza(m), !!(!e.id && ACOMPANANTE[m])].join(); };
function pintarEditor(){
  const f = $('#medForma'); if(!f || !ED) return;
  $('#medTitulo').textContent = ED.id ? 'Edit measurement' : 'Add measurement';
  const lista = MATERIALES[ED.seccion] || [], esOtro = ED.material === 'Other' || (ED.material && !lista.includes(ED.material) && ED.id);
  if(esOtro && ED.material !== 'Other'){ ED.otro = ED.material; ED.material = 'Other'; }
  const mat = materialDe(ED), pieza = esPorPieza(mat), comp = !ED.id && ACOMPANANTE[mat];
  const nivel = nombreNivel(ED.nivel_id, ED.nivel), cuarto = nombreCuarto(ED.cuarto_id, ED.cuarto);
  const r = calcular(mat, ED.largo, pieza ? '' : ED.ancho), res = totalTexto(r.sqft, r.linear, r.piezas) || (r.faltaAlto ? (ED.seccion === 'wall' ? 'missing height' : 'missing width') : '');
  const etqAncho = ED.seccion === 'wall' ? 'Height (ft)' : 'Width (ft)', lineal = unidad(mat) === 'LF', sup = unidad(mat) === 'SF';
  // En la compu, 4 columnas solo si la última fila queda igual o más llena que con 3 (Wall: 9 = 3 × 3, sin huecos).
  const nMat = lista.length + 1, hueco = (c) => (c - nMat % c) % c, cuatro = hueco(4) <= hueco(3);
  f.innerHTML = `
    <div class="med-donde">${IC('casa')}<span><b>${esc(cuarto || 'Room not specified')}</b>${nivel ? ' · ' + esc(nivel) : ''}</span><button type="button" class="pdet-link" data-med-cambiar>Change</button></div>
    <p class="med-et">Part</p>
    <div class="med-rejilla med-partes">${SECCIONES.map(([k, t]) => `<button type="button" class="chip${ED.seccion === k ? ' on' : ''}" data-med-sec="${k}">${t}</button>`).join('')}</div>
    <p class="med-et">${ED.seccion === 'kitchen' || ED.seccion === 'bathroom' ? 'Item' : 'Material'}</p>
    <div class="med-rejilla med-mats${cuatro ? ' c4' : ''}">${lista.concat(['Other']).map(m => `<button type="button" class="chip${ED.material === m ? ' on' : ''}" data-med-mat="${esc(m)}">${esc(m)}</button>`).join('')}</div>
    ${ED.material === 'Other' ? `<div class="field med-otro"><label for="medOtro">Material / item name</label><input id="medOtro" type="text" maxlength="80" value="${esc(ED.otro)}" placeholder="e.g. Wainscoting"></div>` : ''}
    ${mat ? (pieza ? `<div class="field med-dims1"><label for="medLargo">How many? <span class="hint">each</span></label><input id="medLargo" type="number" inputmode="numeric" min="1" step="1" value="${esc(ED.largo)}"></div>`
      : lineal ? `<div class="field med-dims1"><label for="medLargo">Length (ft) <span class="hint">linear</span></label><input id="medLargo" type="number" inputmode="decimal" min="0" step="0.01" value="${esc(ED.largo)}" placeholder="L"></div>`
      : `<div class="med-dims"><div class="field"><label for="medLargo">Length (ft)</label><input id="medLargo" type="number" inputmode="decimal" min="0" step="0.01" value="${esc(ED.largo)}" placeholder="L"></div>
          <span class="med-x">×</span>
          <div class="field"><label for="medAncho">${etqAncho}${sup ? '' : ' <span class="hint">optional</span>'}</label><input id="medAncho" type="number" inputmode="decimal" min="0" step="0.01" value="${esc(ED.ancho)}" placeholder="${ED.seccion === 'wall' ? 'H' : 'W'}"></div></div>
         ${ED.seccion === 'wall' && sup ? '<p class="med-nota-chica">Walls are always length × height, in square feet, however tall the cut is.</p>' : ''}`)
      + `<p class="med-res" id="medRes">${res ? '= ' + esc(res) : ''}</p>` : ''}
    ${comp ? `<label class="med-acomp"><input type="checkbox" id="medAcomp"${ED.acomp ? ' checked' : ''}><span>Also add <b>${esc(comp)}</b> with the same size</span></label>` : ''}
    <p class="aviso" id="medEdAviso"></p>
    <div class="fila-botones">${ED.id ? '<button type="button" class="btn btn-outline btn-rojo" data-med-borrar>Delete</button>' : ''}<button type="button" class="btn btn-outline" data-med-cerrar>Cancel</button><button type="button" class="btn btn-accent" data-med-guardar>Save</button></div>
    ${ED.id ? '' : '<button type="button" class="btn btn-block med-otra" data-med-guardar="otra">Save and add another</button>'}`;
}
function pintarResultado(){
  if(!ED) return; const mat = materialDe(ED), r = calcular(mat, ED.largo, esPorPieza(mat) ? '' : ED.ancho), t = totalTexto(r.sqft, r.linear, r.piezas);
  const el = $('#medRes'); if(el) el.textContent = t ? '= ' + t : '';
}
const botonesEditor = (off) => document.querySelectorAll('#hojaMedida [data-med-guardar], #hojaMedida [data-med-borrar]').forEach(b => { b.disabled = off; });
// El aviso del editor si sigue abierto el MISMO; si lo cerraron mientras guardaba, el aviso sale en la pestaña.
function avisoEditor(ed, t){ const av = $('#medEdAviso'); if(ED === ed && av) av.textContent = t; else avisar(t); }
async function guardarEditor(otra){
  if(!ED || !T) return; const ed = ED, tid = T.id;
  if(GUARDANDO){ avisoEditor(ed, 'Still saving…'); return; }
  const mat = materialDe(ed), pieza = esPorPieza(mat), largo = num(ed.largo), ancho = pieza ? 0 : num(ed.ancho);
  if(!mat){ avisoEditor(ed, ed.material === 'Other' ? 'Write the material or item name.' : 'Pick the material.'); return; }
  if(!largo){ avisoEditor(ed, pieza ? 'Write how many.' : 'Write the length in feet.'); return; }
  // Lo de superficie siempre lleva su segunda medida (15-oct-2026): una pared sin alto ya no es pie lineal.
  if(unidad(mat) === 'SF' && !ancho){ avisoEditor(ed, ed.seccion === 'wall' ? 'Write the height: walls are length × height.' : 'Write the width: this is length × width.'); return; }
  const fila = { nivel_id: ed.nivel_id || null, cuarto_id: ed.cuarto_id || null, nivel_nombre: nombreNivel(ed.nivel_id, ed.nivel) || null, cuarto_nombre: nombreCuarto(ed.cuarto_id, ed.cuarto) || null,
    seccion: ed.seccion, material: mat, largo: pieza ? Math.max(1, Math.round(largo)) : r2(largo), ancho: ancho ? r2(ancho) : null };
  // Todo lo que hace falta DESPUÉS se toma ahora: si cierran el editor mientras guarda, ya no existe.
  const edId = ed.id, sig = otra ? { nivel_id: ed.nivel_id, cuarto_id: ed.cuarto_id, nivel: ed.nivel, cuarto: ed.cuarto, seccion: ed.seccion } : null;
  GUARDANDO = true; botonesEditor(true);
  try{
    let out;
    if(edId){
      const r = await authFetch('/rest/v1/fotos_medidas?id=eq.' + encodeURIComponent(edId), { method: 'PATCH', headers: { Prefer: 'return=representation' }, body: JSON.stringify(fila) });
      if(!r.ok) throw new Error('HTTP ' + r.status); out = await r.json();
      if(!out.length) throw new Error('only the manager or who measured it can change it');
    } else {
      const orden = Date.now(); const filas = [{ ...fila, trabajo_id: tid, orden, origen: 'mano' }];
      const comp = ACOMPANANTE[mat]; if(ed.acomp && comp) filas.push({ ...fila, material: comp, largo: esPorPieza(comp) ? 1 : fila.largo, ancho: esPorPieza(comp) ? null : fila.ancho, trabajo_id: tid, orden: orden + 1, origen: 'mano' });
      out = await insertar(filas);
    }
    out.forEach(f => anotar({ fila: f }, tid));
    if(T && T.id === tid){ FILAS = unir(FILAS, out); ULTIMO = { nivel_id: fila.nivel_id, cuarto_id: fila.cuarto_id }; }
    if(ED === ed){ cerrarEditor(); if(sig && T && T.id === tid) abrirEditor(sig); }
    avisar(''); pintarAqui();
  }catch(e){ avisoEditor(ed, 'Could not save. ' + msg(e)); }
  finally{ GUARDANDO = false; botonesEditor(false); }
}
// Guardar varias filas y COMPROBAR en la base que quedaron todas (un 400 no siempre se nota). Cada fila lleva su id desde
// aquí: si se manda otra vez (señal que se cayó a medias), las que ya estaban no se repiten.
async function insertar(filas){
  filas = filas.map(f => f.id ? f : { ...f, id: nuevoId() });
  const r = await authFetch('/rest/v1/fotos_medidas?on_conflict=id', { method: 'POST', headers: { Prefer: 'resolution=ignore-duplicates,return=minimal' }, body: JSON.stringify(filas) });
  if(!r.ok) throw new Error(r.status === 404 ? 'falta correr sql/fotos-12-medidas.sql' : 'HTTP ' + r.status);
  const g = await authFetch('/rest/v1/fotos_medidas?id=in.(' + filas.map(f => f.id).join(',') + ')');
  if(!g.ok) throw new Error('could not check that they were saved (HTTP ' + g.status + ')');
  const out = await g.json();
  if(!Array.isArray(out) || out.length !== filas.length) throw new Error('the database did not save all of them');
  return out;
}
async function borrarEditor(){
  if(!ED || !ED.id || !T) return; const ed = ED, id = ED.id, tid = T.id;
  if(GUARDANDO){ avisoEditor(ed, 'Still saving…'); return; }
  const ok = await preguntar({ titulo: 'Delete this measurement?', texto: materialDe(ed) + ' · ' + medidaTexto({ material: materialDe(ed), largo: ed.largo, ancho: ed.ancho }), si: 'Delete', no: 'Keep it' });
  if(!ok || GUARDANDO) return;
  GUARDANDO = true; botonesEditor(true);
  try{
    const r = await authFetch('/rest/v1/fotos_medidas?id=eq.' + encodeURIComponent(id), { method: 'DELETE', headers: { Prefer: 'return=representation' } });
    if(!r.ok) throw new Error('HTTP ' + r.status); const out = await r.json();
    if(!out.length) throw new Error('only the manager or who measured it can delete it');
    anotar({ quita: id }, tid);
    if(T && T.id === tid) FILAS = FILAS.filter(x => x.id !== id);
    if(ED === ed) cerrarEditor(); pintarAqui();
  }catch(e){ avisoEditor(ed, 'Could not delete. ' + msg(e)); }
  finally{ GUARDANDO = false; botonesEditor(false); }
}
async function guardarNota(){
  const ta = $('#medNotaTxt'); if(!ta || !T) return; const texto = ta.value.trim(), tid = T.id;
  try{
    const r = await authFetch('/rest/v1/fotos_medidas_notas?on_conflict=trabajo_id', { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates,return=representation' }, body: JSON.stringify({ trabajo_id: tid, texto }) });
    if(!r.ok) throw new Error('HTTP ' + r.status); const out = await r.json();
    if(!out.length) throw new Error('the database did not save them');
    if(!T || T.id !== tid) return;
    NOTA = out[0].texto || ''; NOTA_ED = null; avisar('Notes saved.', true); pintarAqui();
  }catch(e){ avisar('Could not save the notes. ' + msg(e)); }
}

// ---------- la cámara que mide (la de Field Reports) ----------
// Con los colores de Scanova (su decisión del 15-oct: "colores de Scanova", la voz sigue en español). La cámara es la
// misma de Field Reports; Field Reports no manda tema y se queda con los suyos. Hex con transparencia al final.
// Sin verde (su corrección del 15-oct: "el color verde no va, no se distingue"): Terminar/Listo van en el azul oscuro de Scanova.
// LA CÁMARA NUEVA (Fase 2, 15 oct 2026): Scanova la pide primero. Un aparato viejo no conoce la bandera y abre la de
// siempre; Field Reports no la manda y sigue con la de siempre hasta que esta se pruebe en obra.
export const EXPERIENCIA_CAMARA = 'nueva';
export const TEMA_CAMARA = { escogido: '#2563EBF2', pastilla: '#0F1A2EBD', tarjeta: '#151E2E', neutro: '#243046', primario: '#2563EBF2', listo: '#1D4ED8F2', fondo: '#0D1420' };
function catalogos(){
  const secciones = {};
  SECCIONES.forEach(([k]) => { secciones[k] = MATERIALES[k].map(v => { const a = ACOMPANANTE[v];
    return { value: v, label: ETIQUETA_CAMARA[v] || v, companion: a ? { value: a, labelEn: a, labelEs: ACOMPANANTE_ES[a] || a } : null, porPieza: esPorPieza(v), unidad: unidad(v) }; }); });
  return secciones;
}
// LA BITÁCORA DEL LABORATORIO (16 oct, su pedido: "que guarde información para que tú aprendas y veas los datos de lo
// que voy haciendo"): mientras se prueba "Probar lo demolido", la cámara manda lotes (un resumen cada 2 s y cada evento)
// y aquí se suben a fotos_lab_bitacora. Si la red falla, el lote espera al siguiente; si la tabla todavía no existe, se tira.
let BITACORA_PENDIENTE = [];
async function subirBitacora(tid, lote){
  const filas = (lote && Array.isArray(lote.filas) ? lote.filas : []).map(f => ({ trabajo_id: tid, sesion: String((lote && lote.sesion) || 'sin-sesion').slice(0, 64),
    t: Number(f && f.t) || 0, tipo: String((f && f.tipo) || 'evento').slice(0, 40), datos: (f && f.datos) || {} }));
  const todas = BITACORA_PENDIENTE.concat(filas).slice(-3000);
  BITACORA_PENDIENTE = [];
  if(!todas.length) return;
  try{
    const r = await authFetch('/rest/v1/fotos_lab_bitacora', { method: 'POST', headers: { Prefer: 'return=minimal' }, body: JSON.stringify(todas) });
    if(!r.ok && r.status !== 400 && r.status !== 404) BITACORA_PENDIENTE = todas;
  }catch(e){ BITACORA_PENDIENTE = todas; }
}
async function lanzarCamara(alcance, d){
  const ARMeasure = window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.ARMeasure;
  if(!camaraLista() || !ARMeasure){ avisar('Measuring with the camera works in the Scanova app on the iPhone.'); return; }
  if(CAMARA){ avisar('Still saving the last measurements from the camera…'); return; }
  if(!T) return; const tid = T.id;
  if(pendientes(tid)){ avisar('First save (Try again) or discard the camera measurements that were not saved.'); return; }
  const nivel = NIVELES.find(n => n.id === d.nivel_id) || null, cuarto = CUARTOS.find(c => c.id === d.cuarto_id) || null;
  const cuartosPorPlanta = {}; NIVELES.forEach(n => { cuartosPorPlanta[n.nombre] = CUARTOS.filter(c => c.nivel_id === n.id).map(c => c.nombre); });
  // Los cuartos de ESE nivel primero (los del proyecto), después los de siempre.
  const propios = nivel ? (cuartosPorPlanta[nivel.nombre] || []) : [];
  const cuartos = propios.concat(CUARTOS_CATALOGO.filter(x => !propios.some(p => norm(p) === norm(x))));
  const niveles = NIVELES.map(n => n.nombre).concat(NIVELES_COMUNES.filter(x => !NIVELES.some(n => norm(n.nombre) === norm(x))));
  const secciones = catalogos();
  let res;
  // Las paredes del plano de este piso (largo y si es de afuera), para que la cámara sugiera lo de la insulación.
  let paredesPorCuarto = {};
  try{ if(AYUDA.paredes) paredesPorCuarto = (await AYUDA.paredes(tid, nivel ? nivel.id : null)) || {}; }catch(e){ paredesPorCuarto = {}; }
  // Y la forma de cada cuarto, para que la cámara se ubique dentro del plano con el LiDAR (15-oct).
  let planoPorCuarto = {};
  try{ if(AYUDA.formas) planoPorCuarto = AYUDA.formas() || {}; }catch(e){ planoPorCuarto = {}; }
  let oyente = null;
  try{ if(esManager() && ARMeasure.addListener) oyente = await ARMeasure.addListener('bitacora', l => { subirBitacora(tid, l); }); }catch(e){ oyente = null; }
  try{
    res = await ARMeasure.measure({ modo: 'recorrido', alcance, nivel: nivel ? nivel.nombre : '', section: 'floor', materials: secciones.floor, secciones, cuartos, niveles,
      areasPorCuarto: {}, cuartosPorPlanta, areasPorPlanta: {}, crewName: String((PERFIL && PERFIL.full_name) || '').split(' ')[0], roomName: cuarto ? cuarto.nombre : '', roomAreaSqFt: 0, tema: TEMA_CAMARA, experiencia: EXPERIENCIA_CAMARA, paredesPorCuarto, planoPorCuarto,
      // "Probar lo demolido" (laboratorio): solo el manager ve el botón dentro de la cámara. Un aparato viejo lo ignora.
      laboratorio: esManager() });
  }catch(e){ avisar('Could not open the measuring camera. ' + msg(e)); return; }
  finally{ try{ if(oyente && oyente.remove) await oyente.remove(); }catch(e){} if(BITACORA_PENDIENTE.length) subirBitacora(tid, null); }
  if(!res || res.cancelled){ if(res && res.error) avisar(res.error); return; }
  const nuevas = filasDeCamara(res.measurements, { nivel: nivel ? nivel.nombre : '', cuarto: cuarto ? cuarto.nombre : '', orden: Date.now() }).map(f => ({ ...f, id: nuevoId() }));
  if(!nuevas.length) return;
  guardarPendientes(tid, nuevas);
  await guardarDeCamara(tid, nuevas);
  // La cámara se cayó a media sesión, pero trajo lo que ya estaba guardado: se dice por qué terminó así.
  if(res.aviso) avisar(String(res.aviso));
}
// Cada medida con su nivel y su cuarto DEL PROYECTO: si la cuadrilla dijo uno que todavía no existe, se crea (así sale
// también en Photos y Dry Logs, como un cuarto agregado a mano). Antes se releen del servidor: otro del equipo pudo
// agregar "Kitchen" hace un minuto, y no se debe crear un segundo "Kitchen".
async function guardarDeCamara(tid, nuevas){
  if(CAMARA) return; CAMARA = true;
  avisar('Saving ' + nuevas.length + (nuevas.length === 1 ? ' measurement…' : ' measurements…'), true); pintarAqui();
  const sigue = () => { if(!T || T.id !== tid) throw new Error('another project was opened. They are kept on this device: open this project again and tap Try again.'); };
  try{
    sigue();
    if(AYUDA.refrescar){ const x = await AYUDA.refrescar(tid); sigue(); NIVELES = x.niveles; CUARTOS = x.cuartos; }
    const filas = [];
    for(const n of nuevas){
      let nivel = n.nivel ? NIVELES.find(x => norm(x.nombre) === norm(n.nivel)) : null;
      if(!nivel && n.nivel && AYUDA.asegurarNivel){ nivel = await AYUDA.asegurarNivel(n.nivel, tid); sigue(); if(nivel && !NIVELES.some(x => x.id === nivel.id)) NIVELES = NIVELES.concat(nivel); }
      let cuarto = null;
      if(n.cuarto && nivel){
        cuarto = CUARTOS.find(c => c.nivel_id === nivel.id && norm(c.nombre) === norm(n.cuarto)) || null;
        if(!cuarto && AYUDA.asegurarCuarto){ cuarto = await AYUDA.asegurarCuarto(nivel.id, n.cuarto, tid); sigue(); if(cuarto && !CUARTOS.some(x => x.id === cuarto.id)) CUARTOS = CUARTOS.concat(cuarto); }
      }
      filas.push({ id: n.id, trabajo_id: tid, nivel_id: nivel ? nivel.id : null, cuarto_id: cuarto ? cuarto.id : null, nivel_nombre: nivel ? nivel.nombre : (n.nivel || null), cuarto_nombre: cuarto ? cuarto.nombre : (n.cuarto || null),
        seccion: n.seccion, material: n.material, largo: n.largo, ancho: n.ancho, origen: 'camara', orden: n.orden });
    }
    const out = await insertar(filas);
    soltarPendientes(tid);
    out.forEach(f => anotar({ fila: f }, tid));
    if(T && T.id === tid){ FILAS = unir(FILAS, out); avisar(out.length + (out.length === 1 ? ' measurement added.' : ' measurements added.') + ' Review them below.', true); }
  }catch(e){ if(T && T.id === tid) avisar('The measurements were NOT saved yet. They are kept on this device: tap Try again. ' + msg(e)); }
  finally{ CAMARA = false; pintarAqui(); }
}

// El PDF "Measurements & Demo" (lo arma Documents, el mismo que sale allá).
async function hacerPdf(b){
  if(!AYUDA.pdf || HACIENDO_PDF) return; HACIENDO_PDF = true; const antes = b.innerHTML; b.disabled = true; b.textContent = 'Making PDF…';
  try{ const x = await AYUDA.pdf(); avisar(x && x.r === 'downloaded' ? 'Downloaded ' + x.nombre : '', true); }
  catch(e){ if(!(e && e.name === 'AbortError')) avisar('Could not make the PDF. ' + msg(e)); }
  finally{ HACIENDO_PDF = false; const b2 = document.querySelector('[data-med-pdf]'); if(b2){ b2.disabled = false; b2.innerHTML = antes; } }
}
// Si hay otra hoja o una pregunta ENCIMA del editor, Escape es de ella, no del editor.
const algoEncima = () => ['#hojaCuarto', '#dlgPregunta'].some(s => { const x = $(s); return x && !x.hidden; });
export function conectar(){
  document.addEventListener('click', (e) => {
    const q = (s) => e.target.closest(s); let el;
    const enHoja = q('#hojaMedida'), enTab = caja() && caja().contains(e.target);
    if(!enHoja && !enTab) return;
    if(enHoja){
      if(!ED) return;
      if(q('[data-med-cerrar]') || e.target === hoja()){ cerrarEditor(); return; }
      if((el = q('[data-med-sec]'))){ if(ED.seccion !== el.dataset.medSec){ ED.seccion = el.dataset.medSec; ED.material = ''; ED.otro = ''; ED.acomp = false; } pintarEditor(); return; }
      if((el = q('[data-med-mat]'))){ ED.material = el.dataset.medMat; ED.acomp = false; pintarEditor(); const i = $('#' + (ED.material === 'Other' ? 'medOtro' : 'medLargo')); if(i && !('ontouchstart' in window)) i.focus(); return; }
      if(q('[data-med-cambiar]')){
        if(AYUDA.escogerCuarto){ const ed = ED; AYUDA.escogerCuarto('Measure which room?', { nivel_id: ED.nivel_id, cuarto_id: ED.cuarto_id }, (d) => { if(ED !== ed) return; ED.nivel_id = d.nivel_id || null; ED.cuarto_id = d.cuarto_id || null; ED.nivel = ''; ED.cuarto = ''; pintarEditor(); }); }
        return; }
      if((el = q('[data-med-guardar]'))){ guardarEditor(el.dataset.medGuardar === 'otra'); return; }
      if(q('[data-med-borrar]')){ borrarEditor(); return; }
      return;
    }
    if(q('[data-med-camara]')){ ALCANCE = !ALCANCE; pintarAqui(); return; }
    if(q('[data-med-alcance-no]')){ ALCANCE = false; pintarAqui(); return; }
    if((el = q('[data-med-alcance]'))){ const alc = el.dataset.medAlcance; ALCANCE = false; pintarAqui();
      if(AYUDA.escogerCuarto) AYUDA.escogerCuarto(alc === 'cuarto' ? 'Measure which room?' : 'Measure which level?', ULTIMO, (d) => lanzarCamara(alc, d));
      return; }
    if(q('[data-med-reintentar]')){ const p = T && pendientes(T.id); if(p) guardarDeCamara(T.id, p); return; }
    if(q('[data-med-descartar]')){ const tid = T && T.id, p = tid && pendientes(tid); if(!p || CAMARA) return;
      preguntar({ titulo: 'Discard these measurements?', texto: p.length + (p.length === 1 ? ' measurement' : ' measurements') + ' from the camera will be lost.', si: 'Discard', no: 'Keep them' })
        .then(ok => { if(ok && !CAMARA){ soltarPendientes(tid); avisar(''); pintarAqui(); } });
      return; }
    if(q('[data-med-recargar]')){ FALLO = ''; CARGADO = null; pintarAqui(); cargar(); return; }
    if(q('[data-med-nuevo]')){ if(AYUDA.escogerCuarto) AYUDA.escogerCuarto('Measure which room?', ULTIMO, (d) => abrirEditor({ nivel_id: d.nivel_id || null, cuarto_id: d.cuarto_id || null })); return; }
    if((el = q('[data-med-agregar]'))){ let d = {}; try{ d = JSON.parse(el.dataset.medAgregar); }catch{}
      abrirEditor({ nivel_id: d.nivel_id || null, cuarto_id: d.cuarto_id || null, nivel: d.nivel || '', cuarto: d.cuarto || '', seccion: d.seccion || 'floor' }); return; }
    if((el = q('[data-med-editar]'))){ const f = FILAS.find(x => x.id === el.dataset.medEditar); if(!f) return;
      abrirEditor({ id: f.id, nivel_id: f.nivel_id, cuarto_id: f.cuarto_id, nivel: f.nivel_nombre || '', cuarto: f.cuarto_nombre || '', seccion: f.seccion, material: f.material, largo: String(f.largo), ancho: f.ancho == null ? '' : String(f.ancho) }); return; }
    if(q('[data-med-nota]')){ guardarNota(); return; }
    if((el = q('[data-med-pdf]'))){ hacerPdf(el); return; }
  });
  document.addEventListener('input', (e) => {
    if(e.target.id === 'medNotaTxt'){ NOTA_ED = e.target.value; const b = document.querySelector('[data-med-nota]'); if(b) b.disabled = e.target.value === NOTA; return; }
    if(!ED) return;
    if(e.target.id === 'medLargo'){ ED.largo = e.target.value; pintarResultado(); }
    else if(e.target.id === 'medAncho'){ ED.ancho = e.target.value; pintarResultado(); }
    else if(e.target.id === 'medOtro'){
      // Al escribir el nombre aparece el largo (y el acompañante, si lo tiene): se vuelve a pintar SIN cerrar el teclado.
      const antes = formaDe(ED); ED.otro = e.target.value;
      if(antes !== formaDe(ED)){ const pos = e.target.selectionStart; pintarEditor(); const i = $('#medOtro'); if(i){ i.focus(); try{ i.setSelectionRange(pos, pos); }catch{} } }
    }
    else if(e.target.id === 'medAcomp'){ ED.acomp = e.target.checked; }
  });
  document.addEventListener('change', (e) => { if(ED && e.target.id === 'medAcomp') ED.acomp = e.target.checked; });
  document.addEventListener('keydown', (e) => { if(e.key === 'Escape' && ED && hoja() && !hoja().hidden && !algoEncima()) cerrarEditor(); if(e.key === 'Enter' && ED && (e.target.id === 'medLargo' || e.target.id === 'medAncho')){ e.preventDefault(); guardarEditor(false); } });
}
