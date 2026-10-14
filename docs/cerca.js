// Scanova · los proyectos más cercanos a donde está parado (para "Taking photos for…").
// La posición sale del GPS del teléfono (en la app, el de Apple; en el navegador, el del navegador).
// Los proyectos sin punto guardado se ubican una vez con Apple (solo en la app) y se recuerdan en el teléfono.
import { authFetch } from './app.js?v=2026-10-14-35';

// ---------- lo puro ----------
export function distanciaMillas(a, b){
  const v = (x) => x != null && x !== '' && isFinite(x);   // isFinite(null) es true: un punto vacío no es (0,0)
  if(!a || !b || !v(a.lat) || !v(a.lng) || !v(b.lat) || !v(b.lng)) return null;
  const R = 3958.8, rad = (x) => x * Math.PI / 180;
  const dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}
export function textoDistancia(mi){
  if(mi == null || !isFinite(mi)) return '';
  if(mi < 0.1) return 'Here · < 0.1 mi';
  if(mi < 10) return mi.toFixed(1) + ' mi';
  return Math.round(mi) + ' mi';
}
// Los que tienen distancia primero (el más cerca arriba); los demás, el más reciente arriba.
export function ordenarCercanos(lista, pos, coordsDe){
  const con = [], sin = [];
  (lista || []).forEach(t => { const d = pos ? distanciaMillas(pos, coordsDe(t)) : null; (d == null ? sin : con).push({ t, d }); });
  con.sort((a, b) => a.d - b.d);
  sin.sort((a, b) => String(b.t.updated_at || '').localeCompare(String(a.t.updated_at || '')));
  return con.concat(sin);
}

// ---------- dónde está parado ----------
const CLAVE_FIX = 'scanova.ultimaUbicacion';
const plugin = () => (window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Location) || null;
function fixGuardado(maxMs){ try{ const f = JSON.parse(localStorage.getItem(CLAVE_FIX) || 'null'); return f && Date.now() - f.t < maxMs ? { lat:f.lat, lng:f.lng } : null; }catch{ return null; } }
function guardarFix(lat, lng){ try{ localStorage.setItem(CLAVE_FIX, JSON.stringify({ lat, lng, t: Date.now() })); }catch{} }
let PIDIENDO = null;
export function miPosicion(){
  const reciente = fixGuardado(5 * 60e3); if(reciente) return Promise.resolve(reciente);
  if(PIDIENDO) return PIDIENDO;
  PIDIENDO = (async () => {
    try{
      if(navigator.geolocation){
        const p = await new Promise((res, rej) => navigator.geolocation.getCurrentPosition(res, rej, { enableHighAccuracy:false, timeout:9000, maximumAge:120000 }));
        guardarFix(p.coords.latitude, p.coords.longitude); return { lat:p.coords.latitude, lng:p.coords.longitude };
      }
    }catch{}
    try{ const P = plugin(); if(P && P.suggestAddress){ const r = await P.suggestAddress(); if(r && isFinite(r.lat)){ guardarFix(r.lat, r.lng); return { lat:r.lat, lng:r.lng }; } } }catch{}
    return fixGuardado(24 * 3600e3);   // lo último que se supo (hoy), mejor que nada
  })().finally(() => { setTimeout(() => { PIDIENDO = null; }, 0); });
  return PIDIENDO;
}

// ---------- dónde está cada proyecto ----------
const CLAVE_GEO = 'scanova.geoProyectos';
function geoCache(){ try{ return JSON.parse(localStorage.getItem(CLAVE_GEO) || '{}') || {}; }catch{ return {}; } }
export function coordsDe(t){
  if(t && isFinite(t.lat) && isFinite(t.lng) && t.lat != null && t.lng != null) return { lat:Number(t.lat), lng:Number(t.lng) };
  const c = geoCache()[t && t.id]; return c && c.dir === (t.direccion || '') ? { lat:c.lat, lng:c.lng } : null;
}
// Ubica (una vez) los proyectos que tienen dirección pero no punto. Solo en la app: Apple lo hace sin costo.
export async function ubicarProyectos(lista){
  const P = plugin(); if(!P || !P.geocode) return 0;
  const cache = geoCache(); let n = 0;
  for(const t of (lista || []).filter(t => t.direccion && !coordsDe(t)).slice(0, 15)){
    try{
      const g = await P.geocode({ address: t.direccion });
      if(g && isFinite(g.lat)){
        cache[t.id] = { lat:g.lat, lng:g.lng, dir:t.direccion }; n++;
        // Se guarda también en el proyecto (si esta persona puede editarlo; si no, se queda en el teléfono).
        authFetch('/rest/v1/fotos_trabajos?id=eq.' + encodeURIComponent(t.id) + '&lat=is.null', { method:'PATCH', body: JSON.stringify({ lat:g.lat, lng:g.lng }) }).catch(() => {});
      }
    }catch{}
  }
  try{ localStorage.setItem(CLAVE_GEO, JSON.stringify(cache)); }catch{}
  return n;
}
