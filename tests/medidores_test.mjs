// Scanova360 · el lector de números con FOTOS DE VERDAD (CompanyCam, medidor GENERAL, 14-oct-2026).
// Las pantallas de prueba (lector_test) son limpias; estas no: reflejos, la foto chueca, la cursiva del medidor, dos
// renglones (la lectura y la temperatura), iconos y una gráfica de barras. Lo que más importa: NUNCA una lectura
// equivocada. Cada foto se lee con la caja guía puesta de 20 formas (más grande, más chica, corrida) como apuntaría
// el técnico de verdad.
import fs from 'fs';
import { leerPantalla } from '../docs/lector.js';
import { leerPng } from './_png.mjs';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const dir = new URL('./fixtures/medidores/', import.meta.url).pathname;
const { casos } = JSON.parse(fs.readFileSync(dir + 'medidores.json', 'utf8'));
let bien = 0, mal = 0, nada = 0, centrado = 0, total = 0; const malos = [];
const leidas = new Set();
for(const c of casos){
  const img = leerPng(dir + c.archivo), b = c.pantalla;
  for(const pad of [0.05, 0.2, 0.4, 0.7]) for(const [dx, dy] of [[0, 0], [0.15, 0], [-0.15, 0], [0, 0.15], [0, -0.15]]){
    const x = Math.max(0, Math.round(b.x - pad * b.w + dx * b.w)), y = Math.max(0, Math.round(b.y - pad * b.h + dy * b.h));
    const g = { x, y, w: Math.min(img.width - x, Math.round(b.w * (1 + 2 * pad))), h: Math.min(img.height - y, Math.round(b.h * (1 + 2 * pad))) };
    const r = leerPantalla(img, g), t = r ? r.texto : null; total++;
    if(c.lee === null){ if(t === null) bien++; else { mal++; malos.push(c.archivo + ' leyó ' + t); } continue; }
    if(t === c.lee){ bien++; leidas.add(c.archivo); if(pad === 0.2 && !dx && !dy) centrado++; }
    else if(t === null) nada++;
    else { mal++; malos.push(c.archivo + ': ' + c.lee + ' → ' + t); }
  }
}
console.log(`\n  ${casos.length} fotos × 20 formas de apuntar = ${total}: ${bien} bien, ${nada} sin leer (el técnico lo escribe), ${mal} MAL ${malos.slice(0, 6).join(' | ')}`);
console.log(`  con la caja bien puesta: ${centrado} fotos leídas; alguna forma leyó ${leidas.size} de ${casos.filter(c => c.lee).length}`);
ok('NINGUNA lectura equivocada en fotos de verdad', mal === 0);
ok('lee al menos 90 de los 540 intentos (hoy 95)', bien >= 90);
ok('con la caja bien puesta lee al menos 5 fotos (hoy 5)', centrado >= 5);
console.log(`\nmedidores: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
