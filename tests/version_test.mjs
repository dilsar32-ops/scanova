// Scanova360 · Versión nueva: el teléfono guardaba la página vieja 10 minutos; la app pregunta y recarga sola.
import fs from 'node:fs';
import { debeRecargar } from '../docs/app.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const app = fs.readFileSync(new URL('../docs/app.js', import.meta.url), 'utf8');
ok('hay versión nueva -> recarga', debeRecargar('2026-10-13-9', '2026-10-13-8', '') === true);
ok('misma versión -> no recarga', debeRecargar('2026-10-13-8\n', '2026-10-13-8', '') === false);
ok('ya se intentó con esa versión -> no da vueltas', debeRecargar('2026-10-13-9', '2026-10-13-8', '2026-10-13-9') === false);
ok('respuesta rara (página de error, vacío) -> no recarga', debeRecargar('<!doctype html>', '2026-10-13-8', '') === false && debeRecargar('', '2026-10-13-8', '') === false);
ok('pregunta sin caché y recarga con ?v= (dirección nueva = página fresca)', /fetch\('version\.txt\?cb=' \+ Date\.now\(\), \{ cache:'no-store' \}\)/.test(app) && /location\.replace\(location\.pathname \+ '\?v=' \+ encodeURIComponent\(v\)/.test(app));
ok('pregunta al abrir y al volver a la pantalla', /addEventListener\('load'/.test(app) && /visibilitychange/.test(app));
ok('no recarga con la cámara, el editor, fotos subiendo o escribiendo', /con-camara/.test(app) && /fv-editando/.test(app) && /fotos\.hayFotosSubiendo\(\)/.test(app) && /TEXTAREA/.test(app));
console.log(`\nversion: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
