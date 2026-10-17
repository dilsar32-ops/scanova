// La resta de puertas vuelve sola si el tamaño regresa al medido por la cámara (y nunca pisa lo que él tocó a mano).
import { readFileSync } from 'node:fs';
const s = readFileSync(new URL('../docs/medidas.js', import.meta.url), 'utf8');
const f = s.slice(s.indexOf('function revisarResta'), s.indexOf('function pintarResultado'));
const ok = [/ED\.restaMano\) return/.test(f), /!cambio && ED\.restaAuto/.test(f), /ED\.restar = !!ED\.restar0/.test(f), (s.match(/ED\.restaMano = true/g)||[]).length === 2];
if (ok.includes(false)) { console.error('FALLA resta_regreso', ok); process.exit(1); }
console.log('resta_regreso: ok');
