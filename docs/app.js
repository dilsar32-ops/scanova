// Scanova · arranque, sesión y navegación. Las pantallas viven en index.html; lo de trabajos en trabajos.js.
import { SUPABASE_URL, ANON_KEY, APP_BUILD } from './config.js?v=2026-10-13-7';
import { ESQUEMA_APARATO, urlEntrarGoogle } from './google.js?v=2026-10-13-7';
import * as trabajos from './trabajos.js?v=2026-10-13-7';
import * as personas from './personas.js?v=2026-10-13-7';
import * as fotos from './fotos.js?v=2026-10-13-7';
import * as panel from './panel.js?v=2026-10-13-7';
import * as camara from './camara.js?v=2026-10-13-7';
import * as direccion from './direccion.js?v=2026-10-13-7';
import * as proyecto from './proyecto.js?v=2026-10-13-7';
import * as foto from './foto.js?v=2026-10-13-7';
import * as editor from './editor.js?v=2026-10-13-7';

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
    if(pend && pend.codigo){ try{ p = await pedirEntrada(pend.codigo, pend.nombre); }catch{} }
  }
  if(!p || !p.company_id){ guardarSes(null); throw new Error('Esa cuenta no está en ningún equipo todavía. Pídale al manager el código del equipo y cree la cuenta con él.'); }
  if(p.role !== 'manager' && p.status === 'removed'){ guardarSes(null); throw new Error('Esa cuenta no está autorizada en este equipo. Hable con el manager.'); }
  return p;
}
// Pedir entrada con el codigo del equipo: la cuenta queda EN ESPERA hasta que el manager la apruebe.
export async function pedirEntrada(codigo, nombre){
  const r = await authFetch('/rest/v1/rpc/fotos_pedir_entrada', { method:'POST', body: JSON.stringify({ p_code: codigo, p_name: nombre || null }) });
  const t = await r.text();
  if(r.status === 404) throw new Error('Esta parte todavía no está instalada en el servidor: falta correr sql/fotos-02-aprobacion.sql.');
  if(!r.ok) throw new Error(/codigo_invalido/.test(t) ? 'codigo_invalido' : ('No se pudo pedir la entrada (' + r.status + ')'));
  try{ localStorage.removeItem('scanova.codigoPendiente'); }catch{}
  return await cargarPerfil();
}
// Que pantalla le toca a esta cuenta: trabajos si esta activa (o es manager), espera si esta pausada.
export function puedeEntrar(p){ return !!(p && p.company_id && (p.role === 'manager' || (p.status || 'active') === 'active')); }
// ---------- CONTINUAR CON GOOGLE ----------
// La página google/ (junto a la app) habla con Google y regresa con la sesión en el fragmento (#access_token=...).
// Google solo ve scanova360.com (ver google.js). En el aparato nativo Google no deja entrar desde una vista web
// metida en una app, así que se abre la hoja segura de iOS (plugin EntrarWeb) y vuelve por scanova360://auth.
export { ESQUEMA_APARATO, urlEntrarGoogle };
// Pura: lee lo que Supabase deja en el fragmento. null si no es una vuelta de inicio de sesión.
export function leerVuelta(fragmento){
  const f = String(fragmento || '').replace(/^#/, ''); if(!f) return null;
  const q = new URLSearchParams(f);
  if(q.get('access_token')) return { access_token: q.get('access_token'), refresh_token: q.get('refresh_token') || '', ...(q.get('type') ? { tipo: q.get('type') } : {}) };
  if(q.get('error') || q.get('error_description')) return { error: (q.get('error_description') || q.get('error') || '').replace(/\+/g, ' '), codigo: q.get('error_code') || '' };
  return null;
}
// A dónde regresa el enlace del correo de "¿Olvidó su contraseña?": a Scanova360 (no a la página de Field Reports, que es
// la dirección principal del proyecto en Supabase). En la app o fuera de http, siempre a scanova360.com.
export function urlVueltaClave(href){
  try{ const u = new URL(href); if(u.protocol === 'https:' || u.protocol === 'http:') return u.origin + u.pathname.replace(/[^/]*$/, ''); }catch{}
  return 'https://scanova360.com/';
}
// Pura: el mensaje cuando el enlace del correo falla.
export function errorDeVuelta(v){
  if(!v || !v.error) return '';
  if(v.codigo === 'otp_expired' || /expired|invalid/i.test(v.error)) return 'Ese enlace ya venció o ya se usó. Pida otro con "¿Olvidó su contraseña?".';
  return 'No se pudo entrar: ' + v.error;
}
async function googleActivo(){
  try{ const r = await fetch(SUPABASE_URL + '/auth/v1/settings', { headers:{ apikey: ANON_KEY } }); const d = await r.json(); return !!(d && d.external && d.external.google); }catch{ return false; }
}
let NOMBRE_GOOGLE = '', CORREO_GOOGLE = '';
async function entrarConGoogle(aviso){
  aviso.classList.remove('ok'); aviso.textContent = '';
  const nativo = window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform();
  if(!nativo){ window.location.assign(urlEntrarGoogle(location.href, false)); return; }
  const P = window.Capacitor.Plugins && window.Capacitor.Plugins.EntrarWeb;
  if(!P){ aviso.textContent = 'Esta versión de la app todavía no tiene Google. Entre con su correo, o actualice la app.'; return; }
  try{
    const r = await P.abrir({ url: urlEntrarGoogle(location.href, true), esquema: ESQUEMA_APARATO });
    if(!r || r.cancelado) return;
    const u = String(r.url || ''); await procesarVuelta(leerVuelta(u.includes('#') ? u.slice(u.indexOf('#')) : ''), aviso);
  }catch(e){ aviso.textContent = 'No se pudo entrar con Google. ' + String(e && e.message || ''); }
}
// Con la vuelta en la mano: guardar la sesión, saber quién es, y llevarlo a donde le toca.
async function procesarVuelta(v, aviso){
  if(!v) return false;
  if(v.error){ abrirEntrar('pEntrar'); $('#entrarAviso').textContent = errorDeVuelta(v); return true; }
  guardarSes({ access_token: v.access_token, refresh_token: v.refresh_token, user_id: null });
  const r = await authFetch('/auth/v1/user'); const u = r.ok ? await r.json() : null;
  if(!u || !u.id){ guardarSes(null); abrirEntrar('pEntrar'); $('#entrarAviso').textContent = 'No se pudo entrar con Google. Intente otra vez.'; return true; }
  guardarSes({ ...SES, user_id: u.id });
  const m = u.user_metadata || {}; NOMBRE_GOOGLE = m.full_name || m.name || ''; CORREO_GOOGLE = u.email || '';
  const p = await cargarPerfil();
  if(p && p.company_id){
    if(p.role !== 'manager' && p.status === 'removed'){ guardarSes(null); abrirEntrar('pEntrar'); $('#entrarAviso').textContent = 'Esa cuenta no está autorizada en este equipo. Hable con el manager.'; return true; }
    pintarQuien(); await llegar(p); return true;
  }
  pedirCodigo(); return true;
}
// Vino del enlace del correo: con esa sesión de un rato se pone la contraseña nueva, y luego entra como siempre.
async function pedirClaveNueva(v){
  guardarSes({ access_token: v.access_token, refresh_token: v.refresh_token, user_id: null });
  $('#ncClave').value = ''; $('#ncClave2').value = ''; $('#ncAviso').textContent = '';
  abrirEntrar('pClave');
  try{ const r = await authFetch('/auth/v1/user'); const u = r.ok ? await r.json() : null; if(u && u.id){ guardarSes({ ...SES, user_id: u.id }); if(u.email) $('#ncCorreo').textContent = 'Para ' + u.email + '. Escriba su contraseña nueva.'; } }catch{}
}
async function guardarClaveNueva(){
  const aviso = $('#ncAviso'); aviso.classList.remove('ok');
  const c1 = $('#ncClave').value || '', c2 = $('#ncClave2').value || '';
  if(c1.length < 6) return aviso.textContent = 'La contraseña necesita 6 letras o más.';
  if(c1 !== c2) return aviso.textContent = 'Las dos contraseñas no son iguales.';
  const b = $('#btnNcGuardar'); b.disabled = true; b.textContent = 'Guardando…';
  try{
    const r = await authFetch('/auth/v1/user', { method:'PUT', body: JSON.stringify({ password: c1 }) });
    const t = await r.text(); let d = null; try{ d = JSON.parse(t); }catch{}
    if(!r.ok){ const m = (d && (d.msg || d.message || d.error_description)) || ('HTTP ' + r.status);
      throw new Error(/different from the old/i.test(m) ? 'La contraseña nueva tiene que ser distinta a la anterior.' : r.status === 401 ? 'El enlace ya venció. Pida otro con "¿Olvidó su contraseña?".' : m); }
    if(d && d.id) guardarSes({ ...SES, user_id: d.id });
    aviso.classList.add('ok'); aviso.textContent = 'Listo: su contraseña quedó cambiada.';
    const p = await cargarPerfil();
    if(p && p.company_id){ pintarQuien(); await llegar(p); }
    else { guardarSes(null); abrirEntrar('pEntrar'); $('#entrarAviso').classList.add('ok'); $('#entrarAviso').textContent = 'Contraseña cambiada. Ya puede entrar con su correo y la contraseña nueva.'; }
  }catch(e){ aviso.textContent = 'No se pudo cambiar. ' + String(e && e.message || ''); }
  b.disabled = false; b.textContent = 'Guardar y entrar';
}
// Entró con Google pero no es del equipo todavía: pedir el código (queda en espera hasta que el manager apruebe).
function pedirCodigo(){
  $('#gcNombre').value = NOMBRE_GOOGLE; $('#gcCodigo').value = ''; $('#gcAviso').textContent = '';
  $('#gcCorreo').textContent = 'Entró con Google' + (CORREO_GOOGLE ? ' (' + CORREO_GOOGLE + ')' : '') + '. Falta el código del equipo.';
  abrirEntrar('pCodigo');
}
export function salir(){ guardarSes(null); PERFIL = null; pila.length = 0; if(esAparato()) irA('pEntrar'); else cerrarEntrar(); }

// ---------- la bienvenida (la imagen aprobada): se ve solo sin sesión y solo en el navegador ----------
// En el aparato nativo o en la app guardada en la pantalla de inicio se va derecho a Entrar.
export const esAparato = () => !!(window.Capacitor && window.Capacitor.isNativePlatform && window.Capacitor.isNativePlatform()) || navigator.standalone === true;
export function mostrarInicio(){
  const i = $('#inicio'); if(!i) return;
  $$('.pantalla').forEach(p => { p.hidden = true; });
  document.body.classList.add('modo-entrar'); $('#pie').hidden = true;
  i.hidden = false; document.body.classList.add('en-inicio');
  if(window.inicioAjustar) window.inicioAjustar();
}
export function ocultarInicio(){ const i = $('#inicio'); if(i){ i.hidden = true; } document.body.classList.remove('en-inicio'); }

// ---------- la entrada como VENTANA EMERGENTE en el centro, con la bienvenida detrás ----------
// Sign In y Access Workspace la abren; Crear cuenta y la sala de espera siguen dentro de la misma ventana.
// Se cierra con la X, tocando fuera de la tarjeta o con Escape, y se vuelve a la bienvenida.
let MODAL = false;
export function abrirEntrar(cual){
  if(esAparato()){ irA(cual || 'pEntrar'); return; }   // en la app no hay bienvenida detrás: pantalla normal
  MODAL = true; document.body.classList.add('modal-entrar');
  irA(cual || 'pEntrar');
  const ai = (window.matchMedia && window.matchMedia('(pointer: coarse)').matches);   // en el teléfono no se abre el teclado solo
  if(!ai) setTimeout(() => { const c = $('#inCorreo'); if(c && !$('#pEntrar').hidden) c.focus(); }, 280);
}
export function cerrarEntrar(){ MODAL = false; document.body.classList.remove('modal-entrar'); mostrarInicio(); }

// ---------- navegación: una pantalla a la vez, con su salida al pie ----------
const pila = [];
export function irA(id, desde){
  const enVentana = MODAL && (id === 'pEntrar' || id === 'pCrear' || id === 'pEspera' || id === 'pCodigo' || id === 'pClave');
  if(!enVentana){ MODAL = false; document.body.classList.remove('modal-entrar'); ocultarInicio(); }
  if(desde) pila.push(desde);
  document.body.classList.remove('menu-abierto');
  if(id !== 'pFoto' && editor.activo()) editor.cerrar(true);
  if(id !== 'pTrabajo'){ const k = $('#cajonDetalles'); if(k){ k.hidden = true; document.body.classList.remove('con-cajon'); } }
  // Las hojas del proyecto (Edit Labels, datos del cliente, escoger cuarto) no se quedan encima de otra pantalla.
  ['#detHoja', '#hojaCuarto'].forEach(s => { const h = $(s); if(h) h.hidden = true; });
  $$('.pantalla').forEach(p => { p.hidden = p.id !== id; });
  const solo = (id === 'pEntrar' || id === 'pCrear' || id === 'pEspera' || id === 'pCodigo' || id === 'pClave');
  document.body.classList.toggle('modo-entrar', solo);
  $('#pie').hidden = solo;
  // La barra lateral y la de abajo marcan en qué parte está (Projects abarca la forma y la ficha).
  const seccion = { pInicio:'inicio', pProyectos:'proyectos', pForma:'proyectos', pTrabajo:'proyectos', pNivel:'proyectos', pCuarto:'proyectos', pFoto:'proyectos', pPersonas:'settings', pGaleria:'galeria', pMas:'mas', pPronto: PRONTO }[id] || '';
  $$('[data-nav]').forEach(b => b.classList.toggle('on', !!seccion && b.dataset.nav === seccion));
  $('#subtitulo').textContent = { pEntrar:'Scanova360', pClave:'Contraseña nueva', pCrear:'Crear cuenta', pEspera:'Cuenta en espera', pInicio:'Home', pProyectos:'Projects', pPersonas:'Team', pForma:'Project', pTrabajo:'Project', pNivel:'Level', pCuarto:'Room', pFoto:'Photo', pGaleria:'Gallery', pMas:'More' }[id] || 'Scanova360';
  const m = $('#main'); if(m) m.scrollTo(0, 0); window.scrollTo(0, 0);
}
export function atras(){ const a = pila.pop(); if(a) irA(a); else irA('pInicio'); if(!a || a === 'pInicio' || a === 'pProyectos'){ trabajos.pintar(); trabajos.cargar(); } }
// Una sección que todavía no tiene diseño: pantalla que lo dice (no finge que funciona).
let PRONTO = '';
const TEXTO_PRONTO = {
  plan:['Plan', 'Floor plans and scans will live here. This section is built next, from your design.'],
  restore:['Restore', 'Drying, equipment and restoration tracking will live here. This section is built next, from your design.'],
  reports:['Reports', 'Project reports will live here. This section is built next, from your design.'],
  clients:['Clients', 'Your clients and their contact info will live here. This section is built next, from your design.'],
  settings:['Settings', 'Your account and company settings will live here. This section is built next, from your design.'],
};
function pronto(cual){
  const [t, x] = TEXTO_PRONTO[cual] || ['Coming next', 'This section is built next, from your design.'];
  PRONTO = cual; $('#prontoTitulo').textContent = t; $('#prontoTexto').textContent = x;
  pila.length = 0; irA('pPronto', 'pInicio');
}

// ---------- arranque ----------
// A donde llega una cuenta ya identificada: trabajos (activa o manager) o la sala de espera.
async function llegar(p){
  if(puedeEntrar(p)){ irA('pInicio'); panel.pintar(); await Promise.all([trabajos.cargar(), personas.pintarConteo()]); }
  else { document.body.classList.add('modo-entrar'); irA('pEspera'); }
}
function pintarQuien(){
  const nom = PERFIL ? (PERFIL.full_name || '') : '';
  const rol = PERFIL ? (esManager() ? 'Manager' : 'Team') : '';
  $('#quien').textContent = nom; $('#masNombre').textContent = nom;
  $('#quienRol').textContent = rol; $('#masRol').textContent = rol;
  const ini = trabajos.iniciales(nom);
  $('#avatarLateral').textContent = ini; $('#avatarBarra').textContent = ini; $('#avatarMas').textContent = ini;
}
async function arrancar(){
  $('#entrarVersion').textContent = 'v ' + APP_BUILD;
  const ojo = (btnSel, inpSel) => $(btnSel).addEventListener('click', () => { const i = $(inpSel); const ver = i.type === 'password'; i.type = ver ? 'text' : 'password'; $(btnSel).textContent = ver ? 'Ocultar' : 'Ver'; });
  ojo('#btnOjo', '#inClave'); ojo('#btnOjo2', '#crClave');
  $('#lnkCrear').addEventListener('click', (e) => { e.preventDefault(); $('#crearAviso').textContent = ''; irA('pCrear'); });
  $('#lnkVolverEntrar').addEventListener('click', (e) => { e.preventDefault(); irA('pEntrar'); });
  $('#btnGoogle').addEventListener('click', () => entrarConGoogle($('#entrarAviso')));
  $('#btnGoogle2').addEventListener('click', () => entrarConGoogle($('#crearAviso')));
  $('#lnkGcOtra').addEventListener('click', (e) => { e.preventDefault(); salir(); });
  $('#btnGcPedir').addEventListener('click', async () => {
    const aviso = $('#gcAviso'); aviso.textContent = '';
    const nombre = ($('#gcNombre').value || '').trim(), codigo = ($('#gcCodigo').value || '').trim().toUpperCase();
    if(!nombre) return aviso.textContent = 'Escriba su nombre.';
    if(!codigo) return aviso.textContent = 'Escriba el código del equipo (pídaselo al manager).';
    const b = $('#btnGcPedir'); b.disabled = true; b.textContent = 'Pidiendo…';
    try{ const p = await pedirEntrada(codigo, nombre); pintarQuien(); await llegar(p); }
    catch(e){ const m = String(e && e.message || ''); aviso.textContent = /codigo_invalido/.test(m) ? 'Ese código del equipo no existe. Pídaselo al manager.' : (m || 'No se pudo. Revise su internet.'); }
    b.disabled = false; b.textContent = 'Pedir entrada';
  });
  googleActivo().then(si => { $$('.g-solo').forEach(x => { x.hidden = !si; }); });
  // Recuperar: Supabase manda el correo con el enlace; aqui solo se pide.
  $('#btnNcGuardar').addEventListener('click', guardarClaveNueva);
  $('#ncClave2').addEventListener('keydown', (e) => { if(e.key === 'Enter') guardarClaveNueva(); });
  $('#lnkOlvide').addEventListener('click', async (e) => {
    e.preventDefault();
    const correo = ($('#inCorreo').value || '').trim(); const aviso = $('#entrarAviso');
    if(!correo) return aviso.textContent = 'Escriba su correo arriba y vuelva a tocar aquí.';
    try{ await authPost('/auth/v1/recover?redirect_to=' + encodeURIComponent(urlVueltaClave(location.href)), { email: correo }); aviso.classList.add('ok'); aviso.textContent = 'Le mandamos un correo para cambiar la contraseña. Revise también la carpeta de correo no deseado.'; }
    catch(err){ aviso.classList.remove('ok'); aviso.textContent = 'No se pudo mandar el correo. ' + String(err && err.message || ''); }
  });
  async function entrar(){
    const aviso = $('#entrarAviso'); aviso.classList.remove('ok'); aviso.textContent = '';
    const correo = ($('#inCorreo').value || '').trim(), clave = $('#inClave').value || '';
    if(!correo || !clave) return aviso.textContent = 'Escriba su correo y su contraseña.';
    const b = $('#btnEntrar'); b.disabled = true; b.textContent = 'Entrando…';
    try{
      const p = await entrarCon(correo, clave);
      pintarQuien(); $('#inClave').value = '';
      await llegar(p);
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
        const p = await pedirEntrada(codigo, nombre);
        pintarQuien(); await llegar(p);
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
  $('#btnEsperaRevisar').addEventListener('click', async () => {
    const b = $('#btnEsperaRevisar'); b.disabled = true; b.textContent = 'Revisando…'; $('#esperaAviso').textContent = '';
    const p = await cargarPerfil();
    if(puedeEntrar(p)){ pintarQuien(); await llegar(p); } else $('#esperaAviso').textContent = 'Todavía no está aprobada. Avísele al manager.';
    b.disabled = false; b.textContent = 'Revisar';
  });
  $('#lnkEsperaSalir').addEventListener('click', (e) => { e.preventDefault(); salir(); });
  // Navegación: barra lateral (computadora) y pestañas de abajo (teléfono) comparten data-nav.
  document.addEventListener('click', (e) => {
    const bi = e.target.closest('[data-inicio]');
    if(bi){ e.preventDefault(); if(bi.dataset.inicio === 'entrar') abrirEntrar('pEntrar'); return; }
    if(MODAL && (e.target.closest('[data-cerrar-modal]') || (e.target.classList && e.target.classList.contains('entrar')))){ e.preventDefault(); cerrarEntrar(); return; }
    if(e.target.closest('#btnMenu')){ document.body.classList.toggle('menu-abierto'); return; }
    if(e.target.closest('[data-cerrar-menu]')){ document.body.classList.remove('menu-abierto'); return; }
    const b = e.target.closest('[data-nav]'); if(!b) return;
    document.body.classList.remove('menu-abierto');
    const n = b.dataset.nav;
    if(n === 'atras') atras();
    else if(n === 'inicio' || n === 'trabajos'){ pila.length = 0; irA('pInicio'); panel.pintar(); trabajos.cargar(); }
    else if(n === 'proyectos'){ pila.length = 0; irA('pProyectos'); panel.pintar(); trabajos.cargar(); }
    else if(n === 'galeria'){ pila.length = 0; irA('pGaleria'); panel.pintarGaleria(); trabajos.cargar(); }
    else if(n === 'mas'){ pila.length = 0; irA('pMas'); }
    else if(n === 'capture') panel.abrirCaptura();
    else if(n === 'settings' || n === 'personas'){ if(esManager()){ pila.length = 0; irA('pPersonas', 'pInicio'); personas.cargar(); } else pronto('settings'); }
    else if(TEXTO_PRONTO[n]) pronto(n);
    else if(n === 'salir'){ if(confirm('Sign out of Scanova360 on this device?')) salir(); }
  });
  document.addEventListener('keydown', (e) => { if(e.key === 'Escape' && MODAL) cerrarEntrar(); });
  trabajos.conectar();
  trabajos.alCambiar(panel.pintar);
  panel.conectar();
  camara.conectar();
  proyecto.conectar();
  foto.conectar();
  direccion.conectar(() => trabajos.datos().LISTA);
  personas.conectar();
  fotos.conectar();

  // ¿Viene de vuelta de Google? (#access_token=... o #error=...): se limpia la dirección y se entra.
  const vuelta = leerVuelta(location.hash);
  if(vuelta){ history.replaceState(null, '', location.pathname + location.search); if(!esAparato()) mostrarInicio();
    if(vuelta.tipo === 'recovery'){ await pedirClaveNueva(vuelta); return; }   // vino del correo de "¿Olvidó su contraseña?"
    if(await procesarVuelta(vuelta)) return; }
  SES = leerSes();
  if(SES && SES.access_token){
    const p = await cargarPerfil();
    if(p && p.company_id){ pintarQuien(); await llegar(p); return; }
    if(p && !p.company_id || (!p && SES.user_id)){ const r = await authFetch('/auth/v1/user'); const u = r.ok ? await r.json() : null; if(u && u.app_metadata && u.app_metadata.provider === 'google'){ const m = u.user_metadata || {}; NOMBRE_GOOGLE = m.full_name || m.name || ''; CORREO_GOOGLE = u.email || ''; if(!esAparato()) mostrarInicio(); pedirCodigo(); return; } }
    guardarSes(null);
  }
  if(esAparato()) irA('pEntrar'); else mostrarInicio();
}
if(typeof document !== 'undefined'){ document.addEventListener('DOMContentLoaded', arrancar); console.info('Scanova360', APP_BUILD); }
