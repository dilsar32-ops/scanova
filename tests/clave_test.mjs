// Scanova360 · "¿Olvidó su contraseña?": el enlace del correo regresa a Scanova360 y ahí se pone la contraseña nueva.
import fs from 'node:fs';
import { leerVuelta, urlVueltaClave, errorDeVuelta } from '../docs/app.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const app = fs.readFileSync(new URL('../docs/app.js', import.meta.url), 'utf8');
const idx = fs.readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8');
ok('la vuelta del correo se reconoce como cambio de contraseña', leerVuelta('#access_token=a&refresh_token=b&type=recovery').tipo === 'recovery');
ok('la vuelta de Google sigue igual (sin tipo recovery)', !leerVuelta('#access_token=a&refresh_token=b').tipo && leerVuelta('#access_token=a').access_token === 'a');
ok('enlace vencido: lo dice claro y cómo pedir otro', /venció/.test(errorDeVuelta(leerVuelta('#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired'))));
ok('otro error: se enseña tal cual', errorDeVuelta({ error:'algo raro', codigo:'' }) === 'No se pudo entrar: algo raro');
ok('regresa a scanova360.com (no a Field Reports)', urlVueltaClave('https://scanova360.com/?cb=3#x') === 'https://scanova360.com/');
ok('en la app (sin http) también regresa a scanova360.com', urlVueltaClave('capacitor://localhost/index.html') === 'https://scanova360.com/');
ok('la copia de prueba regresa a su carpeta', urlVueltaClave('http://localhost:8731/scanova_real/index.html') === 'http://localhost:8731/scanova_real/');
ok('el pedido al correo lleva redirect_to', /\/auth\/v1\/recover\?redirect_to=' \+ encodeURIComponent\(urlVueltaClave\(location\.href\)\)/.test(app));
ok('la contraseña nueva se guarda con PUT /auth/v1/user', /authFetch\('\/auth\/v1\/user', \{ method:'PUT', body: JSON\.stringify\(\{ password: c1 \}\) \}\)/.test(app));
ok('la pantalla Contraseña nueva existe con dos campos y su botón', /id="pClave"/.test(idx) && /id="ncClave"/.test(idx) && /id="ncClave2"/.test(idx) && /id="btnNcGuardar"/.test(idx));
console.log(`\nclave: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
