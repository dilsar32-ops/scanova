// Scanova360 · el registro de secado (docs/registro.js): día 2, puntos, comparar, equipo y días de equipo.
import * as R from '../docs/registro.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const L = (dia, cuarto, material, ubic, valor, t) => ({ id: dia + cuarto + material + ubic + t, dia, cuarto_id: cuarto, material, ubicacion: ubic, valor, created_at: dia + 'T' + (t || '10:00') + ':00Z' });
const E = (dia, cuarto, tipo, n, t) => ({ dia, cuarto_id: cuarto, tipo, cantidad: n, created_at: dia + 'T' + (t || '10:00') + ':00Z' });
const lect = [
  L('2026-10-13', 'k', 'Drywall', 'East wall', 45, '10:00'), L('2026-10-13', 'k', 'Baseboard', 'North', 30, '10:01'),
  L('2026-10-13', 'b', 'Drywall', '', 22, '10:05'),
  L('2026-10-14', 'k', 'Drywall', 'east  wall', 40, '09:00'),
];
ok('el día: el primero con algo anotado es el 1; dos días después es el 3', R.numeroDia(lect, [], '2026-10-15') === 3 && R.numeroDia([], [], '2026-10-15') === 1);
ok('días del registro con su número', JSON.stringify(R.diasDelRegistro(lect, [])) === JSON.stringify([{ dia:'2026-10-13', n:1 }, { dia:'2026-10-14', n:2 }]));
const pts = R.puntosDeCuarto(lect, 'k');
ok('puntos: material + dónde, sin importar mayúsculas ni espacios (East wall = east  wall)', pts.length === 2 && pts[0].dias['2026-10-13'].valor === 45 && pts[0].dias['2026-10-14'].valor === 40);
ok('visita anterior: el último día antes de hoy con lecturas en ese cuarto', R.visitaAnterior(lect, 'k', '2026-10-14').dia === '2026-10-13' && R.visitaAnterior(lect, 'k', '2026-10-13') === null);
const pend = R.puntosPendientes(lect, 'k', '2026-10-14');
ok('día 2: falta medir el Baseboard (el Drywall ya se midió hoy)', pend.length === 1 && pend[0].material === 'Baseboard' && pend[0].valor === 30);
ok('lectura anterior del mismo punto (para comparar)', R.lecturaAnterior(lect, 'k', 'Drywall', 'East wall', '2026-10-14').valor === 45);
ok('tendencia: bajó 5 = se está secando', R.tendencia(45, 40).tipo === 'baja' && R.tendencia(45, 40).texto === '▼ 5' && R.tendencia(30, 32).tipo === 'sube' && R.tendencia(null, 3) === null);
ok('recorrido día 1: todos los cuartos; día 2: solo los que tienen algo anotado', (() => {
  const niv = [{ id:'n1' }], cua = [{ id:'k', nivel_id:'n1' }, { id:'b', nivel_id:'n1' }, { id:'x', nivel_id:'n1' }];
  return R.cuartosDelRecorrido(niv, cua, [], [], '2026-10-13').length === 3 && R.cuartosDelRecorrido(niv, cua, lect, [], '2026-10-14').map(c => c.id).join() === 'k,b';
})());
// Equipo: 2 ventiladores el 13; el 15 se quita 1; el 17 se quitan todos. Hoy 18.
const eq = [E('2026-10-13', 'k', 'Fans', 2), E('2026-10-13', 'k', 'Dehus', 1), E('2026-10-15', 'k', 'Fans', 1), E('2026-10-15', 'k', 'Dehus', 1), E('2026-10-17', 'k', 'none', 0)];
const pd = R.equipoPorDia(eq);
ok('equipo por día y lo que hay un día sin visita (sigue lo último contado)', R.equipoEnDia(pd, 'k', '2026-10-14').cuentas.Fans === 2 && R.equipoEnDia(pd, 'k', '2026-10-16').cuentas.Fans === 1);
ok('días de equipo: Fans 13,14 (2+2) + 15,16 (1+1) = 6; el día que se quita no cuenta', R.diasDeEquipo(pd, 'k', 'Fans', '2026-10-18') === 6);
ok('días de equipo: si sigue en la casa, cuenta hasta hoy', R.diasDeEquipo(R.equipoPorDia([E('2026-10-13', 'k', 'Fans', 2)]), 'k', 'Fans', '2026-10-15') === 6);
const res = R.resumenDeEquipo(eq, '2026-10-18'), fans = res.find(r => r.tipo === 'Fans');
ok('resumen: lo más que hubo, días, cuándo se puso y cuándo se quitó', fans.max === 2 && fans.dias === 6 && fans.desde === '2026-10-13' && fans.hasta === '2026-10-17');
ok('resumen: lo que sigue en la casa no tiene fecha de quitado', R.resumenDeEquipo([E('2026-10-13', 'k', 'Fans', 2)], '2026-10-15')[0].hasta === null);
ok('equipo: de un mismo día vale la anotación más nueva completa (No Equipment después de contar = nada)', (() => {
  const x = R.equipoPorDia([E('2026-10-13', 'k', 'Fans', 2, '10:00'), E('2026-10-13', 'k', 'none', 0, '11:00')]); return JSON.stringify(x.k['2026-10-13']) === '{}'; })());
ok('equipo: sumando cuartos, lo más que hubo a la vez', R.resumenDeEquipo([E('2026-10-13', 'k', 'Fans', 2), E('2026-10-13', 'b', 'Fans', 3)], '2026-10-13')[0].max === 5);
ok('fechas cortas y largas', R.fechaCorta('2026-10-14') === 'Oct 14' && R.fechaLarga('2026-10-14') === 'Oct 14, 2026');
console.log(`\nregistro: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
