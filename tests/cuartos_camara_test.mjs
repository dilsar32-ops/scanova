// 17-oct: la pestaña Floor Plan manda a la cámara los cuartos que el personal ya creó, por nivel.
import fs from 'node:fs';
import * as PL from '../docs/planos.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const N = [{ id: 'a', nombre: 'Main Level' }, { id: 'b', nombre: 'Basement' }];
const C = [{ id: 1, nivel_id: 'a', nombre: 'Kitchen' }, { id: 2, nivel_id: 'a', nombre: 'Master Bedroom ' }, { id: 3, nivel_id: 'b', nombre: 'Laundry' }, { id: 4, nivel_id: 'b', nombre: '' }];
const r = PL.cuartosParaLaCamara(N, C, 'Main Level');
ok('cuartos del nivel escogido', JSON.stringify(r.cuartosDelNivel) === '["Kitchen","Master Bedroom"]');
ok('cuartos por cada nivel (para el nivel que se escoja en la cámara)', JSON.stringify(r.cuartosPorNivel) === '{"Main Level":["Kitchen","Master Bedroom"],"Basement":["Laundry"]}');
ok('sin nivel / sin cuartos = listas vacías', PL.cuartosParaLaCamara(N, undefined, '').cuartosDelNivel.length === 0);
const d = PL.cuartosParaLaCamara([{ id: 'x', nombre: '1st Floor' }, { id: 'y', nombre: '1st Floor' }], [{ nivel_id: 'x', nombre: 'Kitchen' }, { nivel_id: 'y', nombre: 'Den' }], '1st Floor');
ok('dos niveles con el mismo nombre juntan sus cuartos', JSON.stringify(d.cuartosDelNivel) === '["Kitchen","Den"]');
const src = fs.readFileSync(new URL('../docs/planos.js', import.meta.url), 'utf8');
// (17-oct) + { trabajo, entrega, nivelId }: el escáner deja el escaneo en el teléfono antes de responder (con el nivel que estaba en pantalla).
ok('RS.scan lleva los cuartos', /RS\.scan\(Object\.assign\(\{ nivelBase: base, niveles: NIVELES\.map\(n => n\.nombre\) \}, cuartosParaLaCamara\(NIVELES, CUARTOS_P, base\), \{ trabajo: tid, entrega, nivelId: niv && niv\.id !== SIN_NIVEL \? niv\.id : '' \}\)\)/.test(src));
ok('proyecto.js le pasa CUARTOS a la pestaña', /planos\.abrir\(T, NIVELES, \(\) => abrirFormaNivel\(null\), CUARTOS, NIVELES_LISTOS\)/.test(fs.readFileSync(new URL('../docs/proyecto.js', import.meta.url), 'utf8')));
const sw = fs.readFileSync(new URL('../ios/App/App/RoomPlanPlugin.swift', import.meta.url), 'utf8');
ok('el plugin lee los dos parámetros nuevos (opcionales)', /getArray\("cuartosDelNivel"/.test(sw) && /getObject\("cuartosPorNivel"\)/.test(sw));
console.log(`\n${pass} pasan, ${fail} fallan`); if(fail) process.exit(1);
