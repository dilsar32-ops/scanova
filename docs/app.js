// Scanova · arranque, sesión y navegación. Las pantallas viven en index.html; lo de trabajos en trabajos.js.
import { SUPABASE_URL, ANON_KEY, APP_BUILD } from './config.js';
import * as trabajos from './trabajos.js';

export const $ = (s, r = document) => r.querySelector(s);
export const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
const CLAVE_SES = 'scanova.ses';

// ---------- sesión ----------
export let SES = null;
export let PERFIL = null;   // { id, full_name, role, company_id, status }
function leerSes(){ try{ return JSON.parse(localStorage.getItem(CLAVE_SES) || 'null'); }catch{ return null; } }
function guardarSes(s){ SES = s; try{ if(s) localStorage.setItem(CLAVE_SES, JSON.stringify(s)); else localStorage.removeItem(CLAVE_SES); }catch{} }
export const codeEmail = (code) => 'crew.' + String(code || '').trim().toLowerCase() + '@fieldreports.local';
export const esManager = () => !!(PERFIL && PERFIL.role === 'manager');

async function authPost(path, body, token){
  const r = await fetch(SUPABASE_URL + path, { method:'POST', headers:{ 'Content-Type':'application/json', apikey: ANON_KEY, ...(token ? { Authorization:'Bearer ' + token } : {}) }, body: JSON.stringify(body || {}) });
  const t = await r.text(); let d = null; try{ d = JSON.parse(t); }catch{}
  if(!r.ok) throw new Error((d && (d.msg || d.message || d.error_description || d.error)) || ('HTTP ' + r.status));
  return d;
}
async function refrescar(){
  if(!SES || !SES.refresh_token) return false;
  try{
    const d = await authPost('/auth/v1/token?grant_type=refresh_token', { refresh_token: SES.refresh_token });
    if(!d || !d.access_token) return false;
    guardarSes({ ...SES, access_token: d.access_token, refresh_token: d.refresh_token || SES.refresh_token });
    return true;
  }catch{ return false; }
}
// fetch con la sesión; si la sesión venció, la renueva UNA vez y repite.
export async function authFetch(path, opts = {}){
  const hacer = () => fetch(SUPABASE_URL + path, { ...opts, headers:{ 'Content-Type':'application/json', apikey: ANON_KEY, Authorization:'Bearer ' + (SES ? SES.access_token : ''), ...(opts.headers || {}) } });
  let r = await hacer();
  if(r.status === 401 && await refrescar()) r = await hacer();
  return r;
}
export async function cargarPerfil(){
  if(!SES || !SES.user_id) return null;
  const r = await authFetch('/rest/v1/profiles?id=eq.' + encodeURIComponent(SES.user_id) + '&select=id,full_name,role,company_id,status&limit=1');
  if(!r.ok) return null;
  const f = await r.json();
  PERFIL = f[0] || null;
  return PERFIL;
}
async function entrarCon(email, password){
  const d = await authPost('/auth/v1/token?grant_type=password', { email, password });
  if(!d || !d.access_token) throw new Error('Sin sesión');
  guardarSes({ access_token: d.access_token, refresh_token: d.refresh_token, user_id: d.user && d.user.id });
  const p = await cargarPerfil();
  if(!p || !p.company_id){ guardarSes(null); throw new Error('Esa cuenta no está en ningún equipo todavía. Entre primero a Field Reports.'); }
  if(p.role !== 'manager' && p.status && p.status !== 'active'){ guardarSes(null); throw new Error('Esa cuenta está pausada o fuera del equipo.'); }
  return p;
}
export function salir(){ guardarSes(null); PERFIL = null; pila.length = 0; irA('pEntrar'); }

// ---------- navegación: una pantalla a la vez, con su salida al pie ----------
const pila = [];
export function irA(id, desde){
  if(desde) pila.push(desde);
  $$('.pantalla').forEach(p => { p.hidden = p.id !== id; });
  $('#pie').hidden = (id === 'pEntrar');
  $('#btnAtras').hidden = !pila.length;
  $('#subtitulo').textContent = { pEntrar:'Fotos de trabajos', pTrabajos:'Trabajos', pForma:'Trabajo', pTrabajo:'Trabajo' }[id] || 'Fotos de trabajos';
  window.scrollTo(0, 0);
}
export function atras(){ const a = pila.pop(); if(a) irA(a); else irA('pTrabajos'); if(a === 'pTrabajos' || !a) trabajos.pintar(); }

// ---------- arranque ----------
function pintarQuien(){ $('#quien').textContent = PERFIL ? (PERFIL.full_name || '') + (esManager() ? ' · manager' : '') : ''; }
async function arrancar(){
  $('#entrarModo').addEventListener('click', (e) => {
    const b = e.target.closest('[data-modo]'); if(!b) return;
    $$('#entrarModo .pill').forEach(x => x.classList.toggle('on', x === b));
    $('#entrarCodigo').hidden = b.dataset.modo !== 'codigo';
    $('#entrarCorreo').hidden = b.dataset.modo !== 'correo';
    $('#entrarAviso').textContent = '';
  });
  $('#btnEntrar').addEventListener('click', async () => {
    const aviso = $('#entrarAviso'); aviso.textContent = '';
    const porCodigo = !$('#entrarCodigo').hidden;
    const codigo = ($('#inCodigo').value || '').trim().toUpperCase();
    const correo = ($('#inCorreo').value || '').trim(), clave = $('#inClave').value || '';
    if(porCodigo && codigo.length < 6) return aviso.textContent = 'Escriba su código personal (8 letras).';
    if(!porCodigo && (!correo || !clave)) return aviso.textContent = 'Escriba correo y contraseña.';
    const b = $('#btnEntrar'); b.disabled = true; b.textContent = 'Entrando…';
    try{
      await entrarCon(porCodigo ? codeEmail(codigo) : correo, porCodigo ? codigo : clave);
      pintarQuien();
      $('#inClave').value = ''; $('#inCodigo').value = '';
      irA('pTrabajos'); await trabajos.cargar();
    }catch(e){
      const m = String(e && e.message || '');
      aviso.textContent = /Invalid login/i.test(m) ? (porCodigo ? 'Ese código no es de nadie. Revíselo letra por letra.' : 'Correo o contraseña incorrectos.')
        : /rate limit|too many/i.test(m) ? 'Demasiados intentos. Espere un minuto.' : (m || 'No se pudo entrar. Revise su internet.');
    }
    b.disabled = false; b.textContent = 'Entrar';
  });
  $('#inCodigo').addEventListener('keydown', (e) => { if(e.key === 'Enter') $('#btnEntrar').click(); });
  $('#inClave').addEventListener('keydown', (e) => { if(e.key === 'Enter') $('#btnEntrar').click(); });
  $('#btnAtras').addEventListener('click', atras);
  $('#btnSalir').addEventListener('click', () => { if(confirm('¿Salir de Scanova en este aparato?')) salir(); });
  trabajos.conectar();

  SES = leerSes();
  if(SES && SES.access_token){
    const p = await cargarPerfil();
    if(p && p.company_id){ pintarQuien(); irA('pTrabajos'); await trabajos.cargar(); return; }
    guardarSes(null);
  }
  irA('pEntrar');
}
if(typeof document !== 'undefined'){ document.addEventListener('DOMContentLoaded', arrancar); console.info('Scanova', APP_BUILD); }
