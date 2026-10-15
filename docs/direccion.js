// Scanova · la dirección al crear o editar un proyecto, como en CompanyCam:
//  - el botón 📍 dentro del campo pone la dirección exacta de donde está parado (GPS + dirección de ese punto);
//  - mientras escribe salen sugerencias: en la app del iPhone, de Apple Maps (las más cercanas primero);
//    en la página web, de las direcciones de sus propios proyectos (no hay un servicio gratis para eso en la web).
// Al escoger una sugerencia o usar el 📍 también se guarda el punto (lat/lng) del proyecto.
import { $ } from './app.js?v=2026-10-15-8';

// ---------- lo puro ----------
const ESTADOS = { Alabama:'AL', Alaska:'AK', Arizona:'AZ', Arkansas:'AR', California:'CA', Colorado:'CO', Connecticut:'CT', Delaware:'DE', 'District of Columbia':'DC', Florida:'FL', Georgia:'GA', Hawaii:'HI', Idaho:'ID', Illinois:'IL', Indiana:'IN', Iowa:'IA', Kansas:'KS', Kentucky:'KY', Louisiana:'LA', Maine:'ME', Maryland:'MD', Massachusetts:'MA', Michigan:'MI', Minnesota:'MN', Mississippi:'MS', Missouri:'MO', Montana:'MT', Nebraska:'NE', Nevada:'NV', 'New Hampshire':'NH', 'New Jersey':'NJ', 'New Mexico':'NM', 'New York':'NY', 'North Carolina':'NC', 'North Dakota':'ND', Ohio:'OH', Oklahoma:'OK', Oregon:'OR', Pennsylvania:'PA', 'Rhode Island':'RI', 'South Carolina':'SC', 'South Dakota':'SD', Tennessee:'TN', Texas:'TX', Utah:'UT', Vermont:'VT', Virginia:'VA', Washington:'WA', 'West Virginia':'WV', Wisconsin:'WI', Wyoming:'WY' };
export const estadoCorto = (s) => ESTADOS[String(s || '').trim()] || String(s || '').trim();
export const sinPais = (s) => String(s || '').replace(/,?\s*(United States|USA|Estados Unidos)\s*$/i, '').replace(/\s{2,}/g, ' ').trim();
// Una sugerencia de Apple ({title, subtitle}) -> "1315 Beverly Rd, McLean, VA 22101".
export function unirSugerencia(s){
  const t = String(s && s.title || '').trim(), sub = sinPais(s && s.subtitle);
  if(!sub || t.toLowerCase().includes(sub.toLowerCase())) return sinPais(t);
  return sinPais(t + ', ' + sub);
}
// La dirección que devuelve el servicio abierto de mapas (web) -> "1241 Providence Terrace, McLean, VA 22101".
export function direccionDeMapa(a){
  if(!a) return '';
  const calle = [a.house_number, a.road].filter(Boolean).join(' ');
  const ciudad = a.city || a.town || a.village || a.hamlet || a.suburb || a.county || '';
  const estado = [estadoCorto(a.state), a.postcode].filter(Boolean).join(' ');
  return [calle, ciudad, estado].filter(Boolean).join(', ');
}
export const notaPrecision = (m) => { const n = Math.round(Number(m)); return isFinite(n) && n > 0 ? 'Located within ±' + n + ' m. Check that it is the right house (GPS sometimes gives the one next door).' : 'Check that it is the right house (GPS sometimes gives the one next door).'; };
// Sugerencias de las direcciones de sus proyectos (sin repetir), las que contienen lo escrito.
export function deSusProyectos(lista, texto, max = 3){
  const q = String(texto || '').trim().toLowerCase(); if(q.length < 2) return [];
  const vistas = new Set(); const out = [];
  for(const t of lista || []){ const d = String(t.direccion || '').trim(); const k = d.toLowerCase(); if(!d || vistas.has(k) || !k.includes(q)) continue; vistas.add(k); out.push({ title: d, subtitle: t.cliente || '', propia: true }); if(out.length >= max) break; }
  return out;
}
export function errorUbicacion(e){
  const c = (e && (e.code || e.message)) || '';
  if(c === 'gps_off') return 'GPS is turned off on this phone.';
  if(c === 'denied' || c === 1) return 'Location permission is off. Turn it on in the phone Settings.';
  if(c === 'timeout' || c === 3) return 'Could not find the location. Try outside the building.';
  if(c === 'busy') return 'Already looking for the location.';
  return 'Could not find the location.';
}

// ---------- el campo ----------
const plugin = () => (window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Location) || null;
const CLAVE_FIX = 'scanova.ultimaUbicacion';
let LISTA_FN = () => [];
let SUG = [], SEL = -1, SEQ = 0, ESPERA = null;
const inp = () => $('#fDireccion'), caja = () => $('#fDireccionSug'), nota = () => $('#fDireccionNota');

function ultimoFix(){ try{ const f = JSON.parse(localStorage.getItem(CLAVE_FIX) || 'null'); return f && Date.now() - f.t < 6 * 3600e3 ? f : null; }catch{ return null; } }
function guardarFix(lat, lng){ try{ localStorage.setItem(CLAVE_FIX, JSON.stringify({ lat, lng, t: Date.now() })); }catch{} }
export function ponerPunto(lat, lng){ $('#fLat').value = lat == null ? '' : String(lat); $('#fLng').value = lng == null ? '' : String(lng); }
export function borrarNota(){ const n = nota(); if(n){ n.textContent = ''; n.classList.remove('error'); } }

function pintarSug(){
  const c = caja(); if(!c) return;
  const filas = SUG.map((s, i) => `<button type="button" class="dir-op${i === SEL ? ' on' : ''}" data-sug="${i}">${s.ubicacion ? '<svg class="ic"><use href="#i-ubicacion"/></svg>' : '<svg class="ic"><use href="#i-pin"/></svg>'}<span><b>${esc(s.title)}</b>${s.subtitle ? '<small>' + esc(s.propia || s.ubicacion ? s.subtitle : sinPais(s.subtitle)) + '</small>' : ''}</span></button>`).join('');
  c.innerHTML = filas; c.hidden = !SUG.length;
}
const esc = (s) => String(s == null ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
function cerrarSug(){ SUG = []; SEL = -1; const c = caja(); if(c){ c.hidden = true; c.innerHTML = ''; } }
const filaUbicacion = { title:'Use my current location', subtitle:'Fills in the address where you are standing', ubicacion:true };

async function buscar(){
  const q = inp().value.trim(); const mio = ++SEQ;
  const propias = deSusProyectos(LISTA_FN(), q, 2);
  if(q.length < 3){ SUG = [filaUbicacion, ...propias]; SEL = -1; pintarSug(); return; }
  let apple = [];
  const P = plugin();
  if(P && P.searchAddress){
    try{ const f = ultimoFix(); const r = await P.searchAddress(f ? { query:q, lat:f.lat, lng:f.lng } : { query:q }); apple = (r && r.results || []).slice(0, 4); }catch{}
  }
  if(mio !== SEQ) return;   // ya escribió otra cosa
  const vistas = new Set(propias.map(s => s.title.toLowerCase()));
  apple = apple.filter(s => !vistas.has(unirSugerencia(s).toLowerCase()));
  SUG = [...propias, ...apple, filaUbicacion].slice(0, 6); SEL = -1; pintarSug();
}

async function escoger(i){
  const s = SUG[i]; if(!s) return;
  if(s.ubicacion){ cerrarSug(); return ubicar(); }
  const texto = s.propia ? s.title : unirSugerencia(s);
  inp().value = texto; cerrarSug(); borrarNota(); ponerPunto(null, null);
  // El punto de esa dirección (solo en la app: Apple la ubica sin costo).
  const P = plugin();
  if(P && P.geocode){ try{ const g = await P.geocode({ address: texto }); if(inp().value === texto && g && isFinite(g.lat)) ponerPunto(g.lat, g.lng); }catch{} }
}

// El 📍: la dirección exacta de donde está parado.
export async function ubicar(){
  const b = $('#btnUbicar'); if(b.classList.contains('busy')) return;
  b.classList.add('busy'); borrarNota(); nota().textContent = 'Finding where you are…';
  try{
    let r;
    const P = plugin();
    if(P && P.suggestAddress){ r = await P.suggestAddress(); }
    else if(navigator.geolocation){
      const pos = await new Promise((res, rej) => navigator.geolocation.getCurrentPosition(res, rej, { enableHighAccuracy:true, timeout:20000, maximumAge:0 }));
      const { latitude:lat, longitude:lng, accuracy } = pos.coords;
      let address = '';
      try{ const resp = await fetch('https://nominatim.openstreetmap.org/reverse?format=jsonv2&addressdetails=1&accept-language=en&lat=' + lat + '&lon=' + lng); const d = await resp.json(); address = direccionDeMapa(d && d.address); }catch{}
      r = { address, lat, lng, accuracyM: accuracy };
    } else throw { code:'nada' };
    if(r && isFinite(r.lat)){ guardarFix(r.lat, r.lng); ponerPunto(r.lat, r.lng); }
    if(r && r.address){ inp().value = sinPais(r.address); nota().textContent = notaPrecision(r.accuracyM); }
    else { nota().textContent = 'The spot was saved, but no address was found for it. Please type it.'; }
  }catch(e){ const n = nota(); n.textContent = errorUbicacion(e); n.classList.add('error'); }
  finally{ b.classList.remove('busy'); }
}

export function conectar(listaFn){
  LISTA_FN = listaFn || LISTA_FN;
  const i = inp(); if(!i) return;
  i.addEventListener('focus', () => buscar());
  i.addEventListener('input', () => { ponerPunto(null, null); borrarNota(); clearTimeout(ESPERA); ESPERA = setTimeout(buscar, 280); });
  i.addEventListener('keydown', (e) => {
    if(caja().hidden) return;
    if(e.key === 'ArrowDown'){ e.preventDefault(); SEL = Math.min(SUG.length - 1, SEL + 1); pintarSug(); }
    else if(e.key === 'ArrowUp'){ e.preventDefault(); SEL = Math.max(0, SEL - 1); pintarSug(); }
    else if(e.key === 'Enter' && SEL >= 0){ e.preventDefault(); escoger(SEL); }
    else if(e.key === 'Escape'){ cerrarSug(); }
  });
  // pointerdown (no click): así escoger no pelea con el blur del campo
  caja().addEventListener('pointerdown', (e) => { const o = e.target.closest('[data-sug]'); if(!o) return; e.preventDefault(); escoger(Number(o.dataset.sug)); });
  i.addEventListener('blur', () => setTimeout(cerrarSug, 150));
  $('#btnUbicar').addEventListener('click', () => { cerrarSug(); ubicar(); });
}
