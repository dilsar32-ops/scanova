// Scanova · los proyectos más cercanos (para "Taking photos for…").
import * as C from '../docs/cerca.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const yo = { lat:38.9396, lng:-77.1890 };   // McLean
const d = C.distanciaMillas(yo, { lat:38.9012, lng:-77.2653 });   // Vienna
ok('distanciaMillas: McLean a Vienna ~ 4.9 mi; sin punto = null', d > 4.5 && d < 5.3 && C.distanciaMillas(yo, null) === null && C.distanciaMillas(yo, { lat:null, lng:null }) === null);
ok('textoDistancia: aquí mismo, con un decimal, y redondo si está lejos', C.textoDistancia(0.05) === 'Here · < 0.1 mi' && C.textoDistancia(2.345) === '2.3 mi' && C.textoDistancia(27.6) === '28 mi' && C.textoDistancia(null) === '');
const L = [
  { id:'a', cliente:'Vienna', lat:38.9012, lng:-77.2653, updated_at:'2026-10-10' },
  { id:'b', cliente:'Sin punto viejo', updated_at:'2026-10-01' },
  { id:'c', cliente:'Bellview', lat:38.9425, lng:-77.1952, updated_at:'2026-10-02' },
  { id:'d', cliente:'Sin punto nuevo', updated_at:'2026-10-11' },
];
const coords = (t) => t.lat != null ? { lat:t.lat, lng:t.lng } : null;
ok('ordenarCercanos: el más cerca arriba, y los que no tienen punto al final (el más reciente primero)', C.ordenarCercanos(L, yo, coords).map(x => x.t.id).join() === 'c,a,d,b');
ok('ordenarCercanos: sin saber dónde está, todos por lo más reciente', C.ordenarCercanos(L, null, coords).map(x => x.t.id).join() === 'd,a,c,b');
console.log(`\ncerca: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
