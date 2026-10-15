// LOS CUARTOS SIN ACCESO, DEDUCIDOS (13-oct, el plano de Harold): el clóset del master y el laundry.
import fs from 'fs';
const PL = await import('../docs/planos.js');
const raw = JSON.parse(fs.readFileSync(new URL('./fixtures/harold_4cuartos.json', import.meta.url), 'utf8'));
let ok = 0, mal = 0;
const t = (n, c) => { if(c) ok++; else { mal++; console.log('FAIL', n); } };
const d = PL.prepararPlano(raw);
const inf = d.rooms.filter(r => r._inferido);
t('se deducen dos cuartos', inf.length === 2);
const lav = inf.find(r => r.roomName === 'Laundry Room'), clo = inf.find(r => r.roomName === 'Closet');
t('el del pasillo junto a la cocina es Laundry Room', !!lav);
t('el que abre desde el master es Closet', !!clo);
const caja = r => { const xs = r.walls.flatMap(w => [w.start.x, w.end.x]), ys = r.walls.flatMap(w => [w.start.y, w.end.y]); return { w: Math.max(...xs) - Math.min(...xs), d: Math.max(...ys) - Math.min(...ys) }; };
t('el clóset mide como la franja (2.4 ft de ancho)', clo && Math.abs(caja(clo).w - 2.36) < 0.2);
t('las paredes deducidas van marcadas', inf.every(r => r.walls.every(w => w._inferido && w._added)));
t('la altura sale de las paredes vecinas, no inventada', inf.every(r => r.walls.every(w => w.heightFt === 8.3)));
t('los cuartos escaneados no se tocan', d.rooms.filter(r => !r._inferido).length === 4);
// otra vez sobre el plano ya completado: no se inventa nada más
const otra = JSON.parse(JSON.stringify(d)); delete otra._autoCompletado;
const plano = await import('../docs/plano.js');
t('segunda pasada no agrega nada', plano.fpAutoCompletarEspacios(otra).length === 0);
// un plano editado a mano no se toca
const hecho = JSON.parse(JSON.stringify(raw)); hecho._handEdited = true;
t('plano editado a mano: nada deducido', PL.prepararPlano(hecho).rooms.every(r => !r._inferido));
// la puerta del master hacia el clóset sale corrediza
const svg = PL.svgDelPlano(raw, { cliente: 'Cliente de prueba' }, true);
t('el dibujo trae los dos nombres', /LAUNDRY ROOM/.test(svg) && /CLOSET/.test(svg));
console.log('autocompletar:', ok, 'ok,', mal, 'fallas');
if(mal) process.exit(1);
