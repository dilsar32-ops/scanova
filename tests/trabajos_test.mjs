// Scanova · pruebas de lo puro de trabajos.js (filtrar, validar, tipos, teléfono).
import * as T from '../docs/trabajos.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const L = [
  { id:'1', cliente:'Lauren Harris', direccion:'9 Oak Ln, Vienna VA', tipo:'agua', estado:'activo' },
  { id:'2', cliente:'José Pérez', direccion:'1068 Bellview Rd, McLean', tipo:'mudanza', estado:'activo' },
  { id:'3', cliente:'Ava Malani', direccion:'Fairfax', tipo:'moho', estado:'archivado' },
];
ok('filtrar: solo activos sin texto', T.filtrar(L, 'activo', '').map(t=>t.id).join() === '1,2');
ok('filtrar: archivados', T.filtrar(L, 'archivado', '').map(t=>t.id).join() === '3');
ok('filtrar: por cliente sin acentos ni mayúsculas', T.filtrar(L, 'activo', 'jose').map(t=>t.id).join() === '2');
ok('filtrar: por dirección', T.filtrar(L, 'activo', 'vienna').map(t=>t.id).join() === '1');
ok('filtrar: lista vacía o nula no truena', T.filtrar(null, 'activo', 'x').length === 0);
ok('validar: cliente obligatorio', /cliente/.test(T.validar({ cliente:'', direccion:'x', tipo:'agua' })));
ok('validar: dirección obligatoria', /dirección/.test(T.validar({ cliente:'A', direccion:' ', tipo:'agua' })));
ok('validar: tipo obligatorio y de la lista', /tipo/.test(T.validar({ cliente:'A', direccion:'B', tipo:'' })) && /tipo/.test(T.validar({ cliente:'A', direccion:'B', tipo:'xx' })));
ok('validar: correo mal escrito avisa; vacío pasa', /correo/.test(T.validar({ cliente:'A', direccion:'B', tipo:'agua', correo:'nada' })) && T.validar({ cliente:'A', direccion:'B', tipo:'agua', correo:'' }) === '');
ok('validar: todo bien = sin aviso', T.validar({ cliente:'A', direccion:'B', tipo:'moho', correo:'a@b.co' }) === '');
ok('tipoTxt: nombres y respaldo', T.tipoTxt('agua') === 'Agua' && T.tipoTxt('zzz') === 'Otro');
ok('telDigitos: solo dígitos', T.telDigitos('(703) 555-0100') === '7035550100');
ok('esc: escapa html', T.esc('<b>"x"</b>') === '&lt;b&gt;&quot;x&quot;&lt;/b&gt;');
ok('fechaCorta: vacío y fecha', T.fechaCorta('') === '' && /2026/.test(T.fechaCorta('2026-10-12T03:00:00Z')));
console.log(`\n${pass} ok, ${fail} fail`); process.exit(fail ? 1 : 0);
