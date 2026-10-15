// Scanova · pestaña Measurements (15 oct 2026): copiada de Medidas de Field Reports. Lo puro.
import * as M from '../docs/medidas.js';
import fs from 'node:fs';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };

// Las listas son las de Field Reports, en su orden (sin "Other", que va aparte).
const RUTA_FR = new URL('../../field-report-ios-app/www/index.html', import.meta.url);
if(!fs.existsSync(RUTA_FR)) console.log('  (sin la carpeta de Field Reports al lado: no se comparan las listas)');
else { const fr = fs.readFileSync(RUTA_FR, 'utf8');
  const i = fr.indexOf('const MEASURE_SECTIONS = {'), f = fr.indexOf('const MATERIAL_COMPANION', i);
  const bloque = fr.slice(i, f);
  for(const [sec] of M.SECCIONES){
    const j = bloque.indexOf('    ' + sec + ': {'); const k = bloque.indexOf(']}', j);
    const vals = [...bloque.slice(j, k).matchAll(/\{value:'([^']+)'/g)].map(x => x[1]).filter(v => v !== 'Other');
    ok('las de ' + sec + ' son las de Field Reports, en su orden', JSON.stringify(vals) === JSON.stringify(M.MATERIALES[sec]));
  }
  const pp = fr.slice(fr.indexOf('const MEASURE_POR_PIEZA = new Set(['), fr.indexOf(']);', fr.indexOf('const MEASURE_POR_PIEZA')));
  const piezas = [...pp.matchAll(/'([^']+)'/g)].map(x => x[1]);
  ok('lo que se cuenta por pieza es lo mismo de Field Reports', piezas.length === M.POR_PIEZA.size && piezas.every(p => M.POR_PIEZA.has(p)));
  const ac = fr.slice(fr.indexOf('const MATERIAL_COMPANION = {'), fr.indexOf('};', fr.indexOf('const MATERIAL_COMPANION = {')));
  const pares = [...ac.matchAll(/'([^']+)': \{ value:'([^']+)'/g)].map(x => [x[1], x[2]]);
  ok('los acompañantes son los de Field Reports', pares.length === Object.keys(M.ACOMPANANTE).length && pares.every(([a, b]) => M.ACOMPANANTE[a] === b)); }

ok('largo × alto = pies cuadrados', JSON.stringify(M.calcular('Drywall', 12, 4)) === JSON.stringify({ sqft: 48, linear: 0, piezas: 0, faltaAlto: false }));
// Su regla del 15-oct-2026: la pared SIEMPRE largo × alto ("pie lineal siempre va a ser un pie de alto, 1 por 1 da 1").
ok('un corte de 2 ft de alto: 24 × 2 = 48 pies cuadrados, nunca 24 pies lineales', M.calcular('Drywall', 24, 2).sqft === 48 && M.calcular('Drywall', 24, 2).linear === 0);
ok('una pared sin alto NO es pie lineal: queda "missing height" y no se cobra', JSON.stringify(M.calcular('Drywall', 24, '')) === JSON.stringify({ sqft: 0, linear: 0, piezas: 0, faltaAlto: true }));
ok('el zócalo es el largo (pie lineal), aunque le escriban un número de más', JSON.stringify(M.calcular('Baseboard', 38, 4)) === JSON.stringify({ sqft: 0, linear: 38, piezas: 0, faltaAlto: false }));
ok('un inodoro es una pieza, no pies', JSON.stringify(M.calcular('Toilet', 2, 9)) === JSON.stringify({ sqft: 0, linear: 0, piezas: 2, faltaAlto: false }));
ok('un largo vacío o negativo no suma nada (ni NaN)', JSON.stringify(M.calcular('Carpet', '', 5)) === JSON.stringify({ sqft: 0, linear: 0, piezas: 0, faltaAlto: false }) && M.calcular('Carpet', -3, 4).sqft === 0);
ok('unidades: gabinetes, vanity, vanity top, zócalo, tackless y curb en pie lineal', ['Cabinets', 'Vanity', 'Vanity Top', 'Baseboard', 'Tackless Strip', 'Shower Curb', 'Toe Kick'].every(m => M.unidad(m) === 'LF'));
ok('unidades: tile, drywall, countertop, backsplash, espejo en pie cuadrado', ['Shower Tile', 'Floor Tile', 'Drywall', 'Countertop', 'Backsplash', 'Mirror', 'Insulation'].every(m => M.unidad(m) === 'SF'));
ok('unidades: inodoro, lavaplatos, campana, coladera por pieza', ['Toilet', 'Dishwasher', 'Range Hood / Microwave', 'Shower Drain', 'Sink'].every(m => M.unidad(m) === 'EA'));
ok('lo escrito a mano no recibe una unidad inventada', M.unidad('Wainscoting') === null && M.calcular('Wainscoting', 10, '').linear === 10);
ok('redondeo a centésimas', M.calcular('Tile', 3.333, 3).sqft === 10);
ok('las unidades nunca se suman: lado a lado', M.totalTexto(80, 24, 2) === '80 sq ft + 24 linear ft + 2 EA' && M.totalTexto(0, 0, 0) === '');
ok('cantidad y unidad separadas (SF / LF / EA)', JSON.stringify(M.qtyUnidad(120, 0, 0)) === JSON.stringify({ qty: '120', unidad: 'SF' }) && JSON.stringify(M.qtyUnidad(0, 0, 3)) === JSON.stringify({ qty: '3', unidad: 'EA' }));
ok('con dos unidades la cantidad queda vacía (no se inventa una)', JSON.stringify(M.qtyUnidad(80, 24, 0)) === JSON.stringify({ qty: '', unidad: '80 SF + 24 LF' }));
ok('el texto de la medida: 12 × 4 ft, 38 ft, 2 each', M.medidaTexto({ material: 'Drywall', largo: 12, ancho: 4 }) === '12 × 4 ft' && M.medidaTexto({ material: 'Baseboard', largo: 38 }) === '38 ft' && M.medidaTexto({ material: 'Sink', largo: 2 }) === '2 each');

{ const niveles = [{ id: 'n2', nombre: 'Second Floor' }, { id: 'n1', nombre: 'First Floor' }];
  const cuartos = [{ id: 'c1', nivel_id: 'n1', nombre: 'Kitchen' }, { id: 'c2', nivel_id: 'n1', nombre: 'Living Room' }, { id: 'c3', nivel_id: 'n2', nombre: 'Bedroom' }];
  const f = (id, n, c, sec, mat, a, b, o) => ({ id, nivel_id: n, cuarto_id: c, seccion: sec, material: mat, largo: a, ancho: b, orden: o });
  const g = M.agrupar([
    f('a', 'n1', 'c2', 'floor', 'Carpet', 15, 18, 1), f('b', 'n1', 'c2', 'wall', 'Drywall', 20, 4, 2), f('c', 'n1', 'c1', 'wall', 'Drywall', 24, null, 3),
    f('d', 'n1', 'c2', 'wall', 'Drywall', 10, 4, 4), f('e', 'n2', 'c3', 'ceiling', 'Drywall', 12, 12, 5), f('g', 'n1', 'c1', 'kitchen', 'Sink', 1, null, 6),
    { id: 'h', nivel_id: null, cuarto_id: null, nivel_nombre: 'Attic', cuarto_nombre: 'Storage', seccion: 'floor', material: 'Plywood', largo: 8, ancho: 4, orden: 7 },
  ], niveles, cuartos);
  ok('niveles en el orden del proyecto; uno que no es del proyecto, al final', g.niveles.map(n => n.titulo).join() === 'Second Floor,First Floor,Attic');
  const primer = g.niveles[1];
  ok('los cuartos en el orden en que se midieron', primer.cuartos.map(c => c.titulo).join() === 'Living Room,Kitchen');
  const sala = primer.cuartos[0];
  ok('el mismo material del cuarto se suma (80 + 40 = 120 sq ft) y no se mezcla con otro cuarto', sala.materiales.find(m => m.material === 'Drywall').sqft === 120);
  ok('el drywall de pared y el de techo son partidas distintas', g.partidas.filter(p => p.material === 'Drywall').map(p => p.superficie).join() === 'Wall,Ceiling');
  const pared = g.partidas.find(p => p.material === 'Drywall' && p.seccion === 'wall');
  ok('total del trabajo: drywall de pared en 2 cuartos, 120 sq ft + 1 sin alto (que no se cobra como pie lineal)', pared.cuartos === 2 && pared.sqft === 120 && pared.linear === 0 && pared.faltaAlto === 1);
  ok('las partidas van por parte: Floor, Wall, Ceiling, Kitchen', g.partidas.map(p => p.seccion).join() === 'floor,floor,wall,ceiling,kitchen');
  ok('una medida de un cuarto que ya no existe sale con su nombre guardado', g.niveles[2].cuartos[0].titulo === 'Storage');
  ok('cuenta cuartos y medidas', g.nCuartos === 4 && g.total === 7); }

{ const filas = M.filasDeCamara([
    { length: 9.5, width: 7, material: 'Vinyl (LVP)', companion: 'Underlayment', nivel: 'First Floor', cuarto: 'Laundry Room', seccion: 'floor' },
    { length: 2.4, material: 'Toilet', nivel: 'First Floor', cuarto: 'Bathroom', seccion: 'bathroom' },
    { length: 0, material: 'Drywall', seccion: 'wall' },
    { length: 5, material: '', seccion: 'wall' },
    { length: 6, material: 'Carpet', seccion: 'rara' } ], { nivel: 'First Floor', cuarto: '', orden: 100 });
  ok('la cámara: el acompañante que dijo que sí entra con el mismo tamaño', filas[1].material === 'Underlayment' && filas[1].largo === 9.5 && filas[1].ancho === 7);
  ok('la cámara: un inodoro se guarda como piezas enteras', filas[2].material === 'Toilet' && filas[2].largo === 2 && filas[2].ancho === null);
  ok('la cámara: sin largo o sin material no se guarda', filas.length === 4);
  ok('la cámara: una parte desconocida cae en Floor', filas[3].seccion === 'floor');
  ok('la cámara: el orden sigue el recorrido', filas.map(f => f.orden).join() === '100,101,102,103'); }

// Revisión del 15-oct: lo que encontró y quedó arreglado.
ok('una línea por unidad: SF y LF en dos renglones, nunca uno cortado', JSON.stringify(M.lineasUnidad({ sqft: 35.5, linear: 12.25, piezas: 0, cuartos: 1 }).map(l => l.qty + ' ' + l.unidad)) === '["35.5 SF","12.25 LF"]');
{ const g = M.agrupar([
    { id: 'a', nivel_id: 'n1', cuarto_id: 'c1', seccion: 'wall', material: 'Drywall', largo: 10, ancho: 4, orden: 1 },
    { id: 'b', nivel_id: 'n1', cuarto_id: 'c2', seccion: 'wall', material: 'Drywall', largo: 24, ancho: null, orden: 2 },
    { id: 'c', nivel_id: 'n1', cuarto_id: 'c2', seccion: 'wall', material: 'Drywall', largo: 5, ancho: 4, orden: 3 },
    { id: 'd', nivel_id: null, cuarto_id: null, nivel_nombre: null, cuarto_nombre: 'Porch', seccion: 'floor', material: 'Tile', largo: 3, ancho: 3, orden: 4 } ],
    [{ id: 'n1', nombre: 'First Floor' }], [{ id: 'c1', nivel_id: 'n1', nombre: 'Kitchen' }, { id: 'c2', nivel_id: 'n1', nombre: 'Hall' }]);
  const dw = g.partidas.find(p => p.material === 'Drywall'), ls = M.lineasUnidad(dw);
  ok('total del trabajo: cada unidad dice en cuántos cuartos va (SF en 2, LF en 1)', ls.length === 2 && ls[0].cuartos === 2 && ls[1].cuartos === 1);
  const sin = g.niveles.find(n => n.titulo === 'Level not specified').cuartos[0];
  ok('"Level not specified" es un rótulo: el nombre guardado queda vacío', sin.nivel_nombre === '' && sin.cuarto_nombre === 'Porch');
  ok('un cuarto del proyecto no repite su nombre como texto suelto', g.niveles[0].cuartos[0].cuarto_nombre === ''); }
{ const f = M.filasDeCamara([{ length: 4, width: 3, material: 'Tile', nivel: 'Second Floor', cuarto: '', seccion: 'floor' },
    { length: 4, width: 3, material: 'Tile', nivel: 'First Floor', cuarto: '', seccion: 'floor' },
    { length: 4, material: 'Baseboard', nivel: 'x'.repeat(90), cuarto: 'y'.repeat(90), seccion: 'wall' }], { nivel: 'First Floor', cuarto: 'Kitchen', orden: 1 });
  ok('la cámara: en otro nivel, el cuarto de donde se empezó NO se arrastra', f[0].cuarto === '' && f[1].cuarto === 'Kitchen');
  ok('la cámara: nombres hasta 60 letras (lo que acepta la lista del proyecto)', f[2].nivel.length === 60 && f[2].cuarto.length === 60); }

{ const src = fs.readFileSync(new URL('../docs/medidas.js', import.meta.url), 'utf8');
  const doc = fs.readFileSync(new URL('../docs/documentos.js', import.meta.url), 'utf8');
  const pro = fs.readFileSync(new URL('../docs/proyecto.js', import.meta.url), 'utf8');
  const sql = fs.readFileSync(new URL('../sql/fotos-12-medidas.sql', import.meta.url), 'utf8');
  ok('la cámara recibe el nivel escogido UNA vez (modo recorrido)', /modo: 'recorrido', alcance, nivel: nivel \? nivel\.nombre : ''/.test(src));
  ok('el acompañante se PREGUNTA (casilla apagada), nunca se agrega solo', /acomp: false/.test(src) && /if\(ed\.acomp && comp\)/.test(src));
  ok('guardar comprueba que la base devolvió todas las filas', /out\.length !== filas\.length/.test(src));
  ok('borrar pregunta antes', /titulo: 'Delete this measurement\?'/.test(src));
  ok('Documents tiene el reporte Measurements & Demo con su PDF', /fila\('medidas'/.test(doc) && /export async function pdfMedidas/.test(doc));
  ok('la pestaña ya no es "pronto"', !/Room measurements will live here/.test(pro) && /medidas\.pintar\(T, NIVELES, CUARTOS\)/.test(pro));
  const css = fs.readFileSync(new URL('../docs/estilo.css', import.meta.url), 'utf8');
  ok('el editor queda DEBAJO de la pregunta de borrar (78 < 80)', /\.hoja\.hoja-medida\{ z-index:78; \}/.test(css) && /\.fv-dialogo\{[^}]*z-index:80/.test(css));
  ok('lo de la cámara se guarda primero en el aparato, con sus ids (no se repite al reintentar)', /guardarPendientes\(tid, nuevas\)/.test(src) && /resolution=ignore-duplicates/.test(src) && /id=in\.\(/.test(src));
  ok('antes de crear niveles o cuartos se releen del servidor', /AYUDA\.refrescar\(tid\)/.test(src) && /refrescar: refrescarCuartos/.test(pro));
  ok('el PDF escribe una línea por unidad y no parte un cuarto', /MD\.lineasUnidad\(x\)/.test(doc) && /cabe\(alto\(f\.length\)\)/.test(doc));
  ok('SQL: quien la anotó no se la pasa a otro', /created_by = auth\.uid\(\)\)\);\s*drop policy if exists "fotos_medidas borra"/.test(sql));
  ok('la cámara se abre con los colores de Scanova (la voz sigue en español)', /tema: TEMA_CAMARA/.test(src) && /escogido: '#2563EB/.test(src));
  { const swV = fs.readFileSync(new URL('../ios/App/App/ARMeasureViewController.swift', import.meta.url), 'utf8'), swP = fs.readFileSync(new URL('../ios/App/App/ARMeasurePlugin.swift', import.meta.url), 'utf8');
    ok('la cámara toma el tema de quien la abre (sin tema, los colores de siempre)', /struct TemaCamara/.test(swV) && /ARMeasureViewController\.tema = TemaCamara\(call\.getObject\("tema"\)\)/.test(swP) && !/UIColor\(white: 0\.22, alpha: 1\)\s*$/m.test(swV.split('struct TemaCamara')[1].split('static var tema')[1] || ''));
    const FRV = new URL('../../field-report-ios-app/ios/App/App/ARMeasureViewController.swift', import.meta.url), FRP = new URL('../../field-report-ios-app/ios/App/App/ARMeasurePlugin.swift', import.meta.url);
    if(fs.existsSync(FRV)) ok('la cámara es IDÉNTICA en Field Reports y en Scanova', fs.readFileSync(FRV, 'utf8') === swV && fs.readFileSync(FRP, 'utf8') === swP); }
  ok('SQL: candado (RLS), anon fuera, solo agrega', /enable row level security/.test(sql) && /revoke all on fotos_medidas\s+from anon/.test(sql) && !/drop table/i.test(sql)); }

console.log(`\nmedidas: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
