// Scanova360 · carpeta Dry Logs con SU diseño (14-oct): vacío -> Start Dry Log -> paso 1 (nivel y cuarto).
import fs from 'node:fs';
import * as DL from '../docs/drylog.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const NIV = [{ id:'n1', nombre:'Level 1' }, { id:'n2', nombre:'Level 2' }, { id:'n3', nombre:'Attic' }];
const CUA = [{ id:'a', nivel_id:'n1', nombre:'Kitchen' }, { id:'b', nivel_id:'n1', nombre:'Dining Room' }, { id:'c', nivel_id:'n1', nombre:'East Living Room' }, { id:'d', nivel_id:'n1', nombre:'Hallway' }, { id:'e', nivel_id:'n2', nombre:'Master Bedroom' }];
ok('cuántos cuartos tiene cada nivel (4 rooms / 1 room / 0 rooms)', DL.textoCuartos(DL.cuartosDeNivel(CUA, 'n1').length) === '4 rooms' && DL.textoCuartos(DL.cuartosDeNivel(CUA, 'n2').length) === '1 room' && DL.textoCuartos(0) === '0 rooms');
ok('el nivel que sale escogido: el primero con cuartos', DL.nivelInicial(NIV, CUA) === 'n1' && DL.nivelInicial([{ id:'x' }, { id:'n2' }], CUA) === 'n2' && DL.nivelInicial([{ id:'x' }], []) === 'x' && DL.nivelInicial([], []) === null);
ok('íconos de su diseño: Kitchen, Dining Room, East Living Room, Hallway', DL.iconoCuarto(CUA[0]) === 'dl-cocina' && DL.iconoCuarto(CUA[1]) === 'dl-comedor' && DL.iconoCuarto(CUA[2]) === 'dl-sofa' && DL.iconoCuarto(CUA[3]) === 'dl-puerta');
ok('íconos: recámara, baño, lavandería, y uno general para lo demás', DL.iconoCuarto({ nombre:'Master Bedroom' }) === 'dl-cama' && DL.iconoCuarto({ nombre:'Guest Bath' }) === 'dl-bano' && DL.iconoCuarto({ nombre:'Laundry Room' }) === 'dl-lavar' && DL.iconoCuarto({ nombre:'Garage' }) === 'dl-cuarto' && DL.iconoCuarto({ nombre:'Room 3', tipo:'Kitchen' }) === 'dl-cocina');
ok('WEB: con cuartos creados en Photos abre directo en el paso 1; sin cuartos, la portada "No dry logs yet"', DL.abreEnPaso1(true, CUA, false) === true && DL.abreEnPaso1(true, [], false) === false);
ok('TELÉFONO: por ahora sigue igual (portada y Start), su diseño del teléfono viene aparte', DL.abreEnPaso1(false, CUA, false) === false);
ok('si toca Back en la web, se queda en la portada (no lo regresa solo al paso 1)', DL.abreEnPaso1(true, CUA, true) === false);
ok('WEB: la tarjeta llega al fondo de la pantalla (alto de la pantalla menos donde empieza), nunca más chica que 420', DL.altoTarjeta(786, 230, 16) === 540 && DL.altoTarjeta(500, 400, 16) === 420);
// TELÉFONO (sus 3 diseños): cámara -> lectura detectada -> guardada + equipo
ok('TELÉFONO: con cuartos abre directo en la cámara; sin cuartos, la portada', DL.abreEnCamara(false, CUA) === true && DL.abreEnCamara(false, []) === false && DL.abreEnCamara(true, CUA) === false);
ok('el cuarto que sigue: en el orden de los pisos y de sus cuartos; el último no tiene siguiente', DL.siguienteCuarto(NIV, CUA, 'a').id === 'b' && DL.siguienteCuarto(NIV, CUA, 'd').id === 'e' && DL.siguienteCuarto(NIV, CUA, 'e') === null);
ok('el número escrito: 18, 18.5, "18,5"; nada raro (letras, dos decimales, más de 3 cifras)', DL.valorDe('18') === 18 && DL.valorDe('18.5') === 18.5 && DL.valorDe('18,5') === 18.5 && DL.valorDe('abc') === null && DL.valorDe('1.25') === null && DL.valorDe('1234') === null && DL.valorDe('') === null);
{ const g = DL.guiaEnVideo(1920, 1080, 400, 400, { x: 56, y: 113, w: 288, h: 170 });   // video ancho en un cuadro cuadrado ("cover")
  ok('el cuadro guía se pasa bien a la foto (el video se ve recortado)', Math.abs(g.x - 571.2) < 1 && Math.abs(g.w - 777.6) < 1 && Math.abs(g.y - 305.1) < 1); }
const js = fs.readFileSync(new URL('../docs/drylog.js', import.meta.url), 'utf8');
ok('textos de su diseño: No dry logs yet / Start Dry Log / Step 1 of 3 / Where are you taking the reading?', ['No dry logs yet', 'Start by scanning the first meter reading for this project.', 'Start Dry Log', "You'll choose a level, room, material and measurement point next.", 'New Dry Log · ', 'Step 1 of 3', 'Where are you taking the reading?', 'First select a level, then choose a room to take a moisture reading.', '1. Select level', '2. Select room'].every(t => js.includes(t)));
ok('Continue apagado hasta escoger el cuarto; cambiar de nivel borra el cuarto escogido', /data-dl="paso2"\$\{CUARTO \? '' : ' disabled'\}/.test(js) && /if\(NIVEL !== el\.dataset\.dlNivel\)\{ NIVEL = el\.dataset\.dlNivel; CUARTO = null; \}/.test(js));
ok('textos de sus diseños del teléfono', ['Reading detected', 'Moisture meter value captured successfully.', 'Point the camera at your moisture meter and take a photo.', 'Scan ', 'Retake', 'Save Reading', 'Reading saved for', 'Saved Reading', 'Equipment for', 'Record equipment before moving to another room.', 'Add Equipment', 'No Equipment', 'records zero for'].every(t => js.includes(t)));
ok('el número lo lee NUESTRO lector (gratis, en el teléfono) y la persona lo puede corregir antes de guardar', /import \{ leerPantalla \} from '\.\/lector\.js/.test(js) && /id="dlValor"/.test(js) && /corregido: !!\(FOTO\.lectura && FOTO\.lectura\.valor !== valor\)/.test(js));
ok('la foto de la lectura se guarda en Photos, marcada como del medidor (nunca portada)', /medidor: true/.test(js));
ok('la foto de la lectura se guarda en Photos, en su piso y cuarto (es la prueba)', /fotos\.subirCopia\(archivo, \{ nivel_id: FOTO\.nivel, cuarto_id: FOTO\.cuarto \}, \{ medidor: true \}\)/.test(js) && /foto_id: foto \? foto\.id : null/.test(js));
ok('se comprueba que el servidor de verdad guardó', /if\(!filas\.length\) throw new Error/.test(js));
ok('el botón azul de abajo toma la foto en el Dry Log (no abre la otra cámara)', /closest\('\[data-nav="capture"\]'\)/.test(js) && /e\.stopImmediatePropagation\(\)/.test(js));
ok('cada paso tiene Back abajo', (js.match(/class="dl-atras"/g) || []).length >= 2);
const idx = fs.readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8');
ok('los íconos de los cuartos existen en la app', ['dl-hoja', 'dl-cocina', 'dl-comedor', 'dl-sofa', 'dl-puerta', 'dl-cama', 'dl-bano', 'dl-lavar', 'dl-cuarto'].every(n => idx.includes('id="i-' + n + '"')));
const css = fs.readFileSync(new URL('../docs/estilo.css', import.meta.url), 'utf8').split('===== Dry Logs (14-oct')[1] || 'x';
ok('el CSS de Dry Logs no usa position:fixed', !/position:\s*fixed/.test(css));
// Su regla era "nada verde"; su diseño del 14-oct de la lectura pone verde SOLO en la caja "Reading detected" (.dl-det).
ok('verde solo en "Reading detected" (su diseño), en ningún otro lado del Dry Log', !css.split('\n').filter(l => !/^\.dl-det/.test(l.trim())).some(l => /#16a34a|green|var\(--ok\)|#22a35a|#15803d|#ecf8f0/.test(l)));
// Equipo del cuarto (su diseño del 14-oct, 4 of 5)
{ const filas = [
    { tipo:'Fans / Air Movers', cantidad:3, dia:'2026-10-14', created_at:'2026-10-14T15:00:00Z' },
    { tipo:'Fans / Air Movers', cantidad:2, dia:'2026-10-14', created_at:'2026-10-14T12:00:00Z' },
    { tipo:'Dehumidifiers', cantidad:1, dia:'2026-10-14', created_at:'2026-10-14T15:00:00Z' },
    { tipo:'Heater', cantidad:4, dia:'2026-10-13', created_at:'2026-10-13T15:00:00Z' } ];
  const u = DL.ultimoEquipo(filas);
  ok('equipo: sale lo del día más reciente, la anotación más nueva de cada uno', u.dia === '2026-10-14' && u.cuentas['Fans / Air Movers'] === 3 && u.cuentas['Dehumidifiers'] === 1 && !('Heater' in u.cuentas));
  ok('equipo: "No Equipment" deja todo en cero', JSON.stringify(DL.ultimoEquipo([{ tipo:'none', cantidad:0, dia:'2026-10-14', created_at:'x' }]).cuentas) === '{}');
  ok('equipo: sin nada anotado, no inventa', DL.ultimoEquipo([]) === null);
  const f = DL.filasEquipo({ 'Fans / Air Movers':2, 'Dry Mat':0, 'Ozone Machine':1 });
  ok('equipo: se guarda solo lo que tiene cantidad', f.length === 2 && f.every(x => x.cantidad > 0));
  ok('equipo: todo en cero se guarda como "none" (igual que No Equipment)', JSON.stringify(DL.filasEquipo({ 'Heater':0 })) === '[{"tipo":"none","cantidad":0}]');
  { const niv = [{ id:'n1' }, { id:'n2' }], cua = [{ id:'a', nivel_id:'n1' }, { id:'b', nivel_id:'n1' }, { id:'c', nivel_id:'n2' }, { id:'d', nivel_id:'n2' }];
    const p = DL.posicionCuarto(niv, cua, 'c');
    ok('equipo: "Room 3 of 4" cuenta los cuartos de todo el proyecto, en el orden de la app', p.n === 3 && p.de === 4); }
  ok('equipo: los 7 de su diseño, en su orden', DL.EQUIPOS_DL.map(x => x[0]).join('|') === 'Fans / Air Movers|Dehumidifiers|HEPA Air Scrubber|Dry Mat|Air Duct|Heater|Poles');
  ok('equipo: sus íconos existen en la app', DL.EQUIPOS_DL.every(([, ic]) => idx.includes('id="i-' + ic + '"')) && idx.includes('id="i-mas-circulo"'));
}
ok('registro: en la computadora abre en el registro si ya hay lecturas o equipo', DL.abreEnRegistro(true, [{}], []) && DL.abreEnRegistro(true, [], [{}]) && !DL.abreEnRegistro(true, [], []) && !DL.abreEnRegistro(false, [{}], [{}]));
ok('registro: "+ New Reading" lleva al paso 1 y Back del paso 1 regresa al registro', /data-dl="paso1">\$\{IC\('mas'\)\}New Reading/.test(js) && /abreEnRegistro\(esCompu\(\), LECT, EQUI\)\)\{ PANTALLA = 'registro'/.test(js));
{ const hoy = [{ material:'Drywall', ubicacion:null }, { material:'Drywall', ubicacion:'#2' }, { material:'Studs', ubicacion:'East wall' }];
  ok('mismo material otra vez hoy: no tapa al anterior, queda #2, #3', DL.ubicLibre([], 'Drywall', '') === '' && DL.ubicLibre(hoy.slice(0,1), 'Drywall', '') === '#2' && DL.ubicLibre(hoy, 'Drywall', '') === '#3');
  ok('mismo material con lugar del día anterior: si ya se leyó, "East wall #2"; otro material sin cambio', DL.ubicLibre(hoy, 'Studs', 'East wall') === 'East wall #2' && DL.ubicLibre(hoy, 'Carpet', '') === ''); }
ok('Take next reading guarda y abre la MISMA barra de Material (sin pantalla nueva); al escoger, la cámara', /ESPERA_MAT = guardarLectura\(true\)/.test(js) && /abrirRueda\(\);\n\}/.test(js) && /ESPERA_MAT = null; PANTALLA = 'cam'; pintarAqui\(\)/.test(js) && !/materialHtml/.test(js));
ok('después de la foto: la barra de Material a lo ancho (sin la palabra) + Take next reading + Continue', /<button type="button" class="dl-mat-bar" data-dl-mat-abrir/.test(js) && /<select id="dlMaterial" aria-label="Material" hidden>/.test(js) && /data-dl-siguiente>\$\{IC\('camara'\)\}Take next reading/.test(js));
ok('número escrito y teclado cerrado: el aviso naranja se quita', /function estadoDet\(\)/.test(js) && /d\.hidden = listo/.test(js) && /setTimeout\(estadoDet, 0\)/.test(js));
ok('paso 4 (su imagen): Take next reading abre "Material", la rueda de 3 a la vista y el botón OK', /function abrirRueda\(\)/.test(js) && /<p class="dl-rueda-t">Material<\/p>/.test(js) && /data-dl-rueda-ok>OK<\/button>/.test(js) && /\.dl-rueda\{[^}]*height:132px/.test(fs.readFileSync(new URL('../docs/estilo.css', import.meta.url), 'utf8')));
ok('OK de la rueda: el material del centro; con la lectura guardada vuelve la cámara', /function okRueda\(\)/.test(js) && /sel\.value = c\.dataset\.dlRueda/.test(js));
console.log(`\ndrylog: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
