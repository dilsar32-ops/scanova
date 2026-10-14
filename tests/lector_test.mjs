// Scanova360 · el lector de números de medidor (nuestro, gratis, sin internet): banco de pantallas de PRUEBA.
// Lo que importa más: que NUNCA lea un número equivocado. Si no puede, dice "no pude" y el técnico lo escribe.
import { leerPantalla } from '../docs/lector.js';
import { pantalla, azar, valorAzar } from './_pantallas.mjs';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const lee = (txt, op, sem) => { const R = azar(sem || 7); const p = pantalla(txt, op, R); const r = leerPantalla(p.img, p.guia); return r ? r.texto : null; };
// Los casos de siempre, limpios
for(const t of ['40', '18.5', '12', '9.8', '100', '27.3', '88', '65'])
  ok('pantalla limpia "' + t + '"', lee(t, { pct: true, gap: 0.08 }) === t);
// Una sola cifra NO se da (fotos de verdad, 14-oct: un "7" o un "9" suelto salía de cualquier rayita). Los medidores
// muestran el decimal (7.0); si de veras dice 7, el técnico lo escribe.
for(const t of ['0', '7']) ok('una sola cifra "' + t + '" no se adivina', lee(t, { pct: true, gap: 0.08 }) === null);
// Como en la vida real
ok('cursiva (los medidores escriben inclinado)', lee('18.5', { inclina: 0.18, gap: 0.08 }) === '18.5');
ok('foto un poco chueca (5°)', lee('40', { gira: 5, gap: 0.08, pct: true }) === '40');
ok('borrosa', lee('27.3', { borroso: 2, gap: 0.08 }) === '27.3');
ok('con ruido de cámara', lee('64', { ruido: 50, gap: 0.08 }) === '64');
ok('sombra de un lado', lee('35', { sombra: 0.7, gap: 0.08 }) === '35');
ok('pantalla con luz (números claros sobre oscuro)', lee('22', { invertida: true, gap: 0.08 }) === '22');
ok('la guía no quedó centrada', lee('59', { corre: 25, gap: 0.08 }) === '59');
// Lo que NO debe pasar: inventar un número
ok('sin pantalla (pura pared) no inventa', (() => { const p = pantalla('', {}, azar(3)); return leerPantalla(p.img, { x: 0, y: 0, w: 100, h: 100 }) === null; })());
// El banco grande: 300 pantallas al azar, con todo revuelto
const R = azar(2026);
let bien = 0, mal = 0, nada = 0; const malos = [];
for(let i = 0; i < 300; i++){
  const txt = valorAzar(R);
  const op = { inclina: R() * 0.22, gira: (R() - 0.5) * 8, borroso: Math.floor(R() * 3), ruido: R() * 50, sombra: (R() - 0.5) * 1.2, gap: 0.05 + R() * 0.1, pct: R() < 0.6, grosor: 9 + Math.floor(R() * 5), corre: (R() - 0.5) * 40, invertida: R() < 0.1 };
  const r = leerPantalla(...(p => [p.img, p.guia])(pantalla(txt, op, R)));
  if(!r) nada++; else if(r.texto === txt) bien++; else { mal++; if(malos.length < 8) malos.push(txt + '→' + r.texto); }
}
console.log(`\n  banco de 300: ${bien} bien, ${nada} sin leer (el técnico lo escribe), ${mal} MAL ${malos.join(' ')}`);
ok('el banco: lee bien 9 de cada 10 (>= 88%)', bien >= 264);
ok('el banco: NINGUNA lectura equivocada', mal === 0);
// Un segundo banco que el lector nunca vio (otra semilla), más difícil: más giro, inclinación y la guía más chueca.
{ const R2 = azar(99); let b2 = 0, m2 = 0, n2 = 0;
  for(let i = 0; i < 300; i++){
    const txt = valorAzar(R2);
    const op = { inclina: R2() * 0.25, gira: (R2() - 0.5) * 9, borroso: Math.floor(R2() * 3), ruido: R2() * 55, sombra: (R2() - 0.5) * 1.3, gap: 0.04 + R2() * 0.12, pct: R2() < 0.6, grosor: 8 + Math.floor(R2() * 6), corre: (R2() - 0.5) * 50, invertida: R2() < 0.1, margen: 15 + Math.floor(R2() * 40) };
    const p = pantalla(txt, op, R2); const r = leerPantalla(p.img, p.guia);
    if(!r) n2++; else if(r.texto === txt) b2++; else m2++;
  }
  console.log(`  banco difícil de 300: ${b2} bien, ${n2} sin leer, ${m2} MAL`);
  ok('banco difícil: lee bien 3 de cada 4 (>= 75%)', b2 >= 225);
  ok('banco difícil: casi nunca lee mal (<= 1)', m2 <= 1); }
console.log(`\nlector: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
