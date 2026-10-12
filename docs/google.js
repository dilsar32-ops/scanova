// ---------- CONTINUAR CON GOOGLE, directo desde scanova360.com ----------
// Antes Google regresaba a la dirección de Supabase y su pantalla decía "continuar a ogrvdsawqpiqkkevaewb.supabase.co".
// Ahora Google regresa a scanova360.com/google/, esa página le pasa a Supabase el comprobante de Google (id_token)
// y Supabase da la sesión. Google solo ve scanova360.com. Gratis: no hace falta dominio propio en Supabase.
export const GOOGLE_CLIENT_ID = '320782849765-qm6tcd6dipht6d8tjn8bsa5snsjs94cl.apps.googleusercontent.com';
export const ESQUEMA_APARATO = 'scanova360';
export const CLAVE_GOOGLE = 'scanova.google';

export function aHex(buf){ return Array.from(new Uint8Array(buf), b => b.toString(16).padStart(2, '0')).join(''); }
export function azar(n = 32){ const a = new Uint8Array(n); crypto.getRandomValues(a); return aHex(a); }
// Supabase compara el nonce del comprobante con el SHA-256 (hex) del nonce que le mandamos: a Google va el hash.
export async function sha256hex(t){ return aHex(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(String(t)))); }

// La dirección de esta página tal como está registrada en Google (sin index.html ni ?app=1).
export function dirPagina(origin, pathname){ return origin + String(pathname || '/').replace(/index\.html$/, ''); }
// La entrada empieza en la página google/ que vive junto a la app (en scanova360.com o en la copia de prueba).
export function urlEntrarGoogle(base, app){ return new URL('google/' + (app ? '?app=1' : ''), base).href; }

// El estado lleva si viene de la app del teléfono ('a.') o del navegador ('w.'), para saber a dónde volver
// aunque se haya perdido lo guardado.
export function estadoNuevo(app, r){ return (app ? 'a.' : 'w.') + r; }
export function esDeApp(estado){ return String(estado || '').startsWith('a.'); }

export function urlGoogleDirecto({ clientId, redirectUri, nonceHash, state }){
  const q = new URLSearchParams({ client_id: clientId, redirect_uri: redirectUri, response_type: 'id_token',
    scope: 'openid email profile', nonce: nonceHash, state, prompt: 'select_account' });
  return 'https://accounts.google.com/o/oauth2/v2/auth?' + q.toString();
}
// Pura: lo que Google deja en el fragmento al volver. null si no es una vuelta de Google.
export function leerGoogle(fragmento){
  const q = new URLSearchParams(String(fragmento || '').replace(/^#/, ''));
  if(q.get('id_token')) return { id_token: q.get('id_token'), state: q.get('state') || '' };
  if(q.get('error')) return { error: q.get('error'), state: q.get('state') || '' };
  return null;
}
// Lo que la app ya sabe leer (leerVuelta en app.js): la sesión o el error, en el fragmento.
export function fragmentoSesion(s){
  return '#' + new URLSearchParams({ access_token: s.access_token, refresh_token: s.refresh_token || '',
    expires_in: String(s.expires_in || 3600), token_type: 'bearer' }).toString();
}
export function fragmentoError(msg){ return '#' + new URLSearchParams({ error: 'google', error_description: String(msg || 'No se pudo entrar con Google.') }).toString(); }
export function errorLegible(e){
  if(e === 'access_denied') return 'Se canceló la entrada con Google.';
  return 'Google no dejó entrar (' + e + '). Intente otra vez.';
}
// A dónde volver: a la app del teléfono por scanova360://auth, o a la página principal (un nivel arriba).
export function urlSalida(frag, app, aqui){ return app ? ESQUEMA_APARATO + '://auth' + frag : new URL('../', aqui).href + frag; }
