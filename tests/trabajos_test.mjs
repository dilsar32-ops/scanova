// Scanova · pruebas de lo puro de trabajos.js (filtrar, validar, tipos, teléfono).
import * as T from '../docs/trabajos.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const L = [
  { id:'1', cliente:'Ana Prueba', direccion:'9 Fake Ln, Vienna VA', tipo:'agua', estado:'activo' },
  { id:'2', cliente:'José Pérez', direccion:'100 Test Rd, McLean', tipo:'mudanza', estado:'activo' },
  { id:'3', cliente:'Eva Ejemplo', direccion:'Fairfax', tipo:'moho', estado:'archivado' },
];
ok('filtrar: solo activos sin texto', T.filtrar(L, 'activo', '').map(t=>t.id).join() === '1,2');
ok('filtrar: archivados', T.filtrar(L, 'archivado', '').map(t=>t.id).join() === '3');
ok('filtrar: por cliente sin acentos ni mayúsculas', T.filtrar(L, 'activo', 'jose').map(t=>t.id).join() === '2');
ok('filtrar: por dirección', T.filtrar(L, 'activo', 'vienna').map(t=>t.id).join() === '1');
ok('filtrar: lista vacía o nula no truena', T.filtrar(null, 'activo', 'x').length === 0);
ok('validar: cliente obligatorio', /client/.test(T.validar({ cliente:'', direccion:'x', tipo:'agua' })));
ok('validar: dirección obligatoria', /address/.test(T.validar({ cliente:'A', direccion:' ', tipo:'agua' })));
ok('validar: tipo obligatorio y de la lista', /job type/.test(T.validar({ cliente:'A', direccion:'B', tipo:'' })) && /job type/.test(T.validar({ cliente:'A', direccion:'B', tipo:'xx' })));
ok('validar: correo mal escrito avisa; vacío pasa', /email/.test(T.validar({ cliente:'A', direccion:'B', tipo:'agua', correo:'nada' })) && T.validar({ cliente:'A', direccion:'B', tipo:'agua', correo:'' }) === '');
ok('validar: todo bien = sin aviso', T.validar({ cliente:'A', direccion:'B', tipo:'moho', correo:'a@b.co' }) === '');
ok('tipoTxt: nombres y respaldo', T.tipoTxt('agua') === 'Agua' && T.tipoTxt('zzz') === 'Otro');
ok('telDigitos: solo dígitos', T.telDigitos('(703) 555-0100') === '7035550100');
ok('esc: escapa html', T.esc('<b>"x"</b>') === '&lt;b&gt;&quot;x&quot;&lt;/b&gt;');
ok('fechaCorta: vacío y fecha', T.fechaCorta('') === '' && /2026/.test(T.fechaCorta('2026-10-12T03:00:00Z')));
// Las fotos del medidor del Dry Log nunca son portada ni "fotos recientes".
{ const F = [ { id:'m1', trabajo_id:'A' }, { id:'f1', trabajo_id:'A' }, { id:'f2', trabajo_id:'A' }, { id:'m2', trabajo_id:'B' }, { id:'f3', trabajo_id:'B' } ];
  const r = T.portadasSinMedidor(F, new Set(['m1','m2']));
  ok('portadas: brinca las fotos del medidor', r.A.join() === 'f1,f2' && r.B.join() === 'f3');
  ok('portadas: proyecto con solo fotos del medidor queda sin portada', !T.portadasSinMedidor([{ id:'m1', trabajo_id:'C' }], new Set(['m1'])).C);
  ok('portadas: tope de 4 por proyecto, y sin medidor no truena', T.portadasSinMedidor([1,2,3,4,5,6].map(i => ({ id:'x'+i, trabajo_id:'D' })), null).D.length === 4); }
ok('fechaDeHoy: hora local, no UTC (9 PM del 14 sigue siendo el 14)', T.fechaDeHoy(new Date(2026, 9, 14, 21, 30)) === '2026-10-14' && T.fechaDeHoy(new Date(2026, 0, 5, 0, 1)) === '2026-01-05');
console.log(`\n${pass} ok, ${fail} fail`); process.exit(fail ? 1 : 0);
