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
  let p = await cargarPerfil();
  if(!p || !p.company_id){
    // Cuenta recien confirmada por correo: el codigo del equipo quedo guardado al crearla.
    let pend = null; try{ pend = JSON.parse(localStorage.getItem('scanova.codigoPendiente') || 'null'); }catch{}
    if(pend && pend.codigo){ try{ p = await unirseAlEquipo(pend.codigo, pend.nombre); }catch{} }
  }
  if(!p || !p.company_id){ guardarSes(null); throw new Error('Esa cuenta no está en ningún equipo todavía. Pídale al manager el código del equipo y cree la cuenta con él.'); }
  if(p.role !== 'manager' && p.status && p.status !== 'active'){ guardarSes(null); throw new Error('Esa cuenta está pausada o fuera del equipo.'); }
  return p;
}
// Mismo RPC que usa Field Reports para meter a alguien a la empresa con el codigo del equipo.
export async function unirseAlEquipo(codigo, nombre){
  const r = await authFetch('/rest/v1/rpc/join_company', { method:'POST', body: JSON.stringify({ p_code: codigo, p_name: nombre || null }) });
  const t = await r.text();
  if(!r.ok) throw new Error(/codigo_invalido/.test(t) ? 'codigo_invalido' : ('No se pudo entrar al equipo (' + r.status + ')'));
  const p = await cargarPerfil();
  if(!p || !p.company_id) throw new Error('La cuenta quedó creada pero sin equipo. Pídale al manager el código y vuelva a intentarlo.');
  try{ localStorage.removeItem('scanova.codigoPendiente'); }catch{}
  return p;
}
export function salir(){ guardarSes(null); PERFIL = null; pila.length = 0; irA('pEntrar'); }

// ---------- navegación: una pantalla a la vez, con su salida al pie ----------
const pila = [];
export function irA(id, desde){
  if(desde) pila.push(desde);
  $$('.pantalla').forEach(p => { p.hidden = p.id !== id; });
  document.body.classList.toggle('modo-entrar', id === 'pEntrar' || id === 'pCrear');
  $('#pie').hidden = (id === 'pEntrar' || id === 'pCrear');
  $('#btnAtras').hidden = !pila.length;
  $('#subtitulo').textContent = { pEntrar:'Fotos de trabajos', pCrear:'Crear cuenta', pTrabajos:'Trabajos', pForma:'Trabajo', pTrabajo:'Trabajo' }[id] || 'Fotos de trabajos';
  window.scrollTo(0, 0);
}
export function atras(){ const a = pila.pop(); if(a) irA(a); else irA('pTrabajos'); if(a === 'pTrabajos' || !a) trabajos.pintar(); }

// ---------- arranque ----------
function pintarQuien(){ $('#quien').textContent = PERFIL ? (PERFIL.full_name || '') + (esManager() ? ' · manager' : '') : ''; }
async function arrancar(){
  $('#entrarVersion').textContent = 'v ' + APP_BUILD;
  const ojo = (btnSel, inpSel) => $(btnSel).addEventListener('click', () => { const i = $(inpSel); const ver = i.type === 'password'; i.type = ver ? 'text' : 'password'; $(btnSel).textContent = ver ? 'Ocultar' : 'Ver'; });
  ojo('#btnOjo', '#inClave'); ojo('#btnOjo2', '#crClave');
  $('#lnkCrear').addEventListener('click', (e) => { e.preventDefault(); $('#crearAviso').textContent = ''; irA('pCrear'); });
  $('#lnkVolverEntrar').addEventListener('click', (e) => { e.preventDefault(); irA('pEntrar'); });
  // Recuperar: Supabase manda el correo con el enlace; aqui solo se pide.
  $('#lnkOlvide').addEventListener('click', async (e) => {
    e.preventDefault();
    const correo = ($('#inCorreo').value || '').trim(); const aviso = $('#entrarAviso');
    if(!correo) return aviso.textContent = 'Escriba su correo arriba y vuelva a tocar aquí.';
    try{ await authPost('/auth/v1/recover', { email: correo }); aviso.classList.add('ok'); aviso.textContent = 'Le mandamos un correo para cambiar la contraseña. Revise también la carpeta de correo no deseado.'; }
    catch(err){ aviso.classList.remove('ok'); aviso.textContent = 'No se pudo mandar el correo. ' + String(err && err.message || ''); }
  });
  async function entrar(){
    const aviso = $('#entrarAviso'); aviso.classList.remove('ok'); aviso.textContent = '';
    const correo = ($('#inCorreo').value || '').trim(), clave = $('#inClave').value || '';
    if(!correo || !clave) return aviso.textContent = 'Escriba su correo y su contraseña.';
    const b = $('#btnEntrar'); b.disabled = true; b.textContent = 'Entrando…';
    try{
      await entrarCon(correo, clave);
      pintarQuien(); $('#inClave').value = '';
      irA('pTrabajos'); await trabajos.cargar();
    }catch(e){
      const m = String(e && e.message || '');
      aviso.textContent = /Invalid login/i.test(m) ? 'Correo o contraseña incorrectos.'
        : /not confirmed/i.test(m) ? 'Falta confirmar la cuenta: revise su correo y toque el enlace.'
        : /rate limit|too many/i.test(m) ? 'Demasiados intentos. Espere un minuto.' : (m || 'No se pudo entrar. Revise su internet.');
    }
    b.disabled = false; b.textContent = 'Entrar';
  }
  $('#btnEntrar').addEventListener('click', entrar);
  $('#inClave').addEventListener('keydown', (e) => { if(e.key === 'Enter') entrar(); });
  // Crear cuenta: correo + contraseña en Supabase, y con el codigo del equipo queda en la empresa.
  async function crearCuenta(){
    const aviso = $('#crearAviso'); aviso.classList.remove('ok'); aviso.textContent = '';
    const nombre = ($('#crNombre').value || '').trim(), correo = ($('#crCorreo').value || '').trim(), clave = $('#crClave').value || '', codigo = ($('#crCodigo').value || '').trim().toUpperCase();
    if(!nombre) return aviso.textContent = 'Escriba su nombre.';
    if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(correo)) return aviso.textContent = 'Ese correo no se ve bien.';
    if(clave.length < 6) return aviso.textContent = 'La contraseña necesita 6 letras o más.';
    if(!codigo) return aviso.textContent = 'Escriba el código del equipo (pídaselo al manager).';
    const b = $('#btnCrear'); b.disabled = true; b.textContent = 'Creando…';
    try{
      const d = await authPost('/auth/v1/signup', { email: correo, password: clave, data: { full_name: nombre } });
      if(!d || !d.access_token){
        aviso.classList.add('ok'); aviso.textContent = 'Casi listo: le mandamos un correo. Toque el enlace que viene ahí y luego entre con su correo y contraseña.';
        try{ localStorage.setItem('scanova.codigoPendiente', JSON.stringify({ codigo, nombre, correo })); }catch{}
      }else{
        guardarSes({ access_token: d.access_token, refresh_token: d.refresh_token, user_id: d.user && d.user.id });
        await unirseAlEquipo(codigo, nombre);
        pintarQuien(); irA('pTrabajos'); await trabajos.cargar();
      }
    }catch(e){
      const m = String(e && e.message || '');
      aviso.textContent = /already registered|already been registered/i.test(m) ? 'Ese correo ya tiene cuenta. Vuelva a Entrar.'
        : /codigo_invalido/i.test(m) ? 'Ese código del equipo no existe. Pídaselo al manager.'
        : /signups? not allowed|disabled/i.test(m) ? 'Las cuentas nuevas están apagadas. Hable con el manager.'
        : /rate limit|too many/i.test(m) ? 'Demasiados intentos. Espere un minuto.' : (m || 'No se pudo crear la cuenta. Revise su internet.');
    }
    b.disabled = false; b.textContent = 'Crear cuenta';
  }
  $('#btnCrear').addEventListener('click', crearCuenta);
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
