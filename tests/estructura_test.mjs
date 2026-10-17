// Scanova · candado de lo que ya existe (12 oct 2026, él: "no quites ni muevas nada de lo que ya tenemos sin avisarme").
// La foto de todo lo que hay está en tests/estructura_base.json. Si algo de esa lista desaparece, esta prueba falla:
// antes de quitar o renombrar cualquier cosa hay que AVISARLE y, si dice que sí, actualizar la base a propósito.
import fs from 'node:fs';
const base = JSON.parse(fs.readFileSync(new URL('./estructura_base.json', import.meta.url), 'utf8'));
const idx = fs.readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8');
const js = ['proyecto.js', 'detalles.js', 'fotos.js', 'camara.js', 'panel.js', 'trabajos.js', 'pegar.js'].map(f => fs.readFileSync(new URL('../docs/' + f, import.meta.url), 'utf8')).join('\n');
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; } else { fail++; console.log('  FAIL ' + l); } };
base.ids.forEach(id => ok('sigue el elemento #' + id, idx.includes('id="' + id + '"')));
base.navs.forEach(n => ok('sigue el botón de navegación ' + n, idx.includes('data-nav="' + n + '"')));
base.datas.forEach(d => ok('sigue la acción data-' + d, js.includes('data-' + d + '=')));
// (17-oct) Lo de la cámara guardado en el teléfono: primero se recupera, y cada copia se suelta solo cuando ya existe la siguiente.
{ const med = fs.readFileSync(new URL('../docs/medidas.js', import.meta.url), 'utf8');
  const i = med.indexOf('async function lanzarCamara('), f = med.indexOf('\n}\n', i), lc = med.slice(i, f);
  const at = (t, d = 0) => lc.indexOf(t, d);
  ok('(17-oct) lanzarCamara recupera el borrador antes de mirar pendientes', at('await recogerBorrador(tid)') > 0 && at('await recogerBorrador(tid)') < at('if(pendientes(tid))'));
  const r = at('const todas = unir(');
  ok('(17-oct) guardarPendientes antes de soltarBorradorNativo, y ese antes de guardarDeCamara', r > 0 && at('guardarPendientes(tid, todas)', r) < at('soltarBorradorNativo(tid, [res.sesion])', r) && at('soltarBorradorNativo(tid, [res.sesion])', r) < at('await guardarDeCamara(tid, todas)', r));
  ok('(17-oct) la página pide el borrador y exporta filasDeBorrador', lc.includes('trabajo: tid, borrador: true,') && med.includes('export function filasDeBorrador(')); }
console.log(`\nestructura: ${pass} ok, ${fail} fallas (base: ${base.ids.length} elementos, ${base.navs.length} botones de navegación, ${base.datas.length} acciones)`);
if(fail) process.exit(1);
