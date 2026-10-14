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
ok('textos de sus diseños del teléfono', ['Reading detected', 'Moisture meter value captured successfully.', 'Point the camera at your moisture meter and take a photo.', 'Scan ', 'Retake', 'Save Reading', 'Scan Room', 'Equipment for', 'Record what is in this room before moving on.', 'Add Equipment', 'No Equipment', 'Choosing No Equipment will record zero equipment for', 'Equipment in ', 'Add equipment type', 'Save Equipment &amp; Next Room'].every(t => js.includes(t)));
// Su diseño del 14-oct: Continue enseña la lectura guardada + el equipo; Add Equipment abre la rueda del equipo.
ok('Continue va a la pantalla de la lectura guardada (no directo al equipo)', /else abrirListo\(\);/.test(js) && /PANTALLA = 'guardado'; pintarAqui\(\);/.test(js));
ok('esa pantalla ya no prende la cámara', !/PANTALLA !== 'cam' && PANTALLA !== 'guardado'/.test(js) && /if\(PANTALLA !== 'cam'\) apagarCam\(\);/.test(js));
ok('la lista del equipo sube y baja con su barrita; Add type y Save & next van en la barra de abajo (diseño D)', /class="dl-eq-lista dl-eq-rueda"/.test(js) && /class="dl-eq-barra"/.test(js) && /\$\{EQ\.agregando \? equipoAgregarHtml\(\) : ''\}/.test(js) && /equipo: \[\['mas-circulo', 'Add type', 'tipo'\], \['dl-guardar', 'Save & next', 'guardar-eq'\], \['dl-fin', 'Finish', 'fin'\]\]/.test(js));
ok('las pantallas de Continue y del equipo se miden para quedar quietas (la función existe y se llama)', /function medirQuieta\(\)\{/.test(js) && /requestAnimationFrame\(medirQuieta\)/.test(js));
ok('tocar + rápido cuenta y no hace zoom', /e\.preventDefault\(\); if\(!t\.b\.disabled\) t\.b\.click\(\);/.test(js) && /Math\.abs\(p\.clientY - t\.y\) > 10/.test(js));
ok('Back desde el equipo regresa a la lectura guardada', /PANTALLA = GUARDADA && GUARDADA\.cuarto_id === CUARTO \? 'guardado' : 'cam'/.test(js));
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
  ok('equipo: los 7 de su diseño, en su orden', DL.EQUIPOS_DL.map(x => x[0]).join('|') === 'Fans / Air Movers|Dehumidifiers|Drip Pan|HEPA Air Scrubber|Dry Mat|Air Duct|Heater|Poles|Water Bucket|Desiccant Dehumidifier|Wall Cavity Dryer|Generator|Hydroxyl Generator');
  ok('equipo: sus íconos existen en la app', DL.EQUIPOS_DL.every(([, ic]) => idx.includes('id="i-' + ic + '"')) && idx.includes('id="i-mas-circulo"'));
}
ok('registro: en la computadora abre en el registro si ya hay lecturas o equipo', DL.abreEnRegistro(true, [{}], []) && DL.abreEnRegistro(true, [], [{}]) && !DL.abreEnRegistro(true, [], []) && !DL.abreEnRegistro(false, [{}], [{}]));
ok('registro: "+ New Reading" lleva al paso 1 y Back del paso 1 regresa al registro', /data-dl="paso1">\$\{IC\('mas'\)\}New Reading/.test(js) && /abreEnRegistro\(esCompu\(\), LECT, EQUI\)\)\{ PANTALLA = 'registro'/.test(js));
{ const hoy = [{ material:'Drywall', ubicacion:null }, { material:'Drywall', ubicacion:'#2' }, { material:'Studs', ubicacion:'East wall' }];
  ok('mismo material otra vez hoy: no tapa al anterior, queda #2, #3', DL.ubicLibre([], 'Drywall', '') === '' && DL.ubicLibre(hoy.slice(0,1), 'Drywall', '') === '#2' && DL.ubicLibre(hoy, 'Drywall', '') === '#3');
  ok('mismo material con lugar del día anterior: si ya se leyó, "East wall #2"; otro material sin cambio', DL.ubicLibre(hoy, 'Studs', 'East wall') === 'East wall #2' && DL.ubicLibre(hoy, 'Carpet', '') === ''); }
ok('Take next reading guarda y abre la MISMA barra de Material (sin pantalla nueva); al escoger, la cámara', /ESPERA_MAT = guardarLectura\(true\)/.test(js) && /abrirRueda\(\);\n\}/.test(js) && /ESPERA_MAT = null; PANTALLA = 'cam'; pintarAqui\(\)/.test(js) && !/materialHtml/.test(js));
ok('después de la foto: la barra de Material a lo ancho (sin la palabra); Take next reading = la cámara de abajo, Retake y Continue en la barra (diseño D)', /<button type="button" class="dl-mat-bar" data-dl-mat-abrir/.test(js) && /<select id="dlMaterial" aria-label="Material" hidden>/.test(js) && /if\(PANTALLA === 'lectura'\)\{ if\(RUEDA\) okRueda\(\); else siguienteLectura\(\); \}/.test(js) && /lectura: \[\['girar-der', 'Retake', 'retomar'\], \['flecha-der', 'Continue', 'continuar'\]/.test(js));
// Su diseño D (14-oct): la barra de abajo cambia en cada paso; Finish la quita; los dibujos a color del equipo.
ok('diseño D: la barra solo dentro del Dry Log del teléfono (cam, lectura, guardada, equipo) y se quita al salir o al cambiar de página', /const p = SESION && !esCompu\(\) && c && !c\.closest\('\[hidden\]'\) && BARRA\[PANTALLA\] \? PANTALLA : '';/.test(js) && /classList\.remove\('dl-fijo', 'dl-escribiendo', 'dl-barra'\)/.test(js) && fs.readFileSync(new URL('../docs/app.js', import.meta.url), 'utf8').includes("'dl-fijo', 'dl-barra')"));
ok('diseño D: Finish guarda lo abierto y va al resumen del día', /async function terminar\(\)\{/.test(js) && /PANTALLA = 'dia'; pintarAqui\(\);/.test(js) && /const ok = await guardarEquipo\(true\)/.test(js));
ok('diseño D: Skip room, Retake y los botones grandes ya no están en la pantalla (están en la barra)', !/data-dl-saltar>Skip room/.test(js) && !/class="dl-retomar"/.test(js) && !/data-dl-siguiente>\$\{IC/.test(js) && !/data-dl-equipo="si">/.test(js) && !/class="btn btn-accent dl-eq2-guardar"/.test(js));
ok('lista de Dry Logs (su diseño): el teléfono con algo anotado abre en la lista; sin nada, la cámara; la computadora sigue en el registro', DL.abreEnLista(false, [{}], []) && !DL.abreEnLista(false, [], []) && !DL.abreEnLista(true, [{}], []) && /PANTALLA === 'lista' \? listaHtml\(\)/.test(js));
ok('lista de Dry Logs: días Completed / In progress / Upcoming, Take More Readings y la nota de la fecha', ['Completed', 'In progress', 'Upcoming', 'No readings yet', 'Take readings to see them listed here.', 'Take More Readings', "New readings use today's date automatically."].every(t => js.includes(t)));
ok('lista de Dry Logs: barra Back · Dry Logs · cámara · Rooms · Finish, solo mientras dura la sesión (Finish la quita)', /lista: \[\['doc', 'Dry Logs', 'lista'\], \['dl-capas', 'Rooms', 'rooms'\], \['dl-fin', 'Finish', 'fin'\]\]/.test(js) && /const p = SESION && !esCompu\(\)/.test(js) && /SESION = false; VOLVER = null; PANTALLA = esCompu\(\) \? 'dia' : 'lista'/.test(js));
ok('el equipo se enseña con dibujos a color (todos existen)', DL.EQUIPOS_DL.every(([, ic]) => fs.existsSync(new URL('../docs/img/' + ic + '.svg', import.meta.url))) && fs.existsSync(new URL('../docs/img/eq-otro.svg', import.meta.url)) && /<img class="dl-eq-img" src="img\/\$\{ic\}\.svg\?v=\$\{APP_BUILD\}"/.test(js));
ok('número escrito y teclado cerrado: el aviso naranja se quita', /function estadoDet\(\)/.test(js) && /d\.hidden = listo/.test(js) && /setTimeout\(estadoDet, 0\)/.test(js));
ok('paso 4 (su imagen): Take next reading abre "Material", la rueda de 3 a la vista y el botón OK', /function abrirRueda\(\)/.test(js) && /<p class="dl-rueda-t">Material<\/p>/.test(js) && /data-dl-rueda-ok>OK<\/button>/.test(js) && /\.dl-rueda\{[^}]*height:132px/.test(fs.readFileSync(new URL('../docs/estilo.css', import.meta.url), 'utf8')));
ok('OK de la rueda: el material del centro; con la lectura guardada vuelve la cámara', /function okRueda\(\)/.test(js) && /sel\.value = c\.dataset\.dlRueda/.test(js));
// Revisión de la lista (14-oct, 25 hallazgos confirmados): lo que no debe volver a pasar.
{ const css = fs.readFileSync(new URL('../docs/estilo.css', import.meta.url), 'utf8'), app = fs.readFileSync(new URL('../docs/app.js', import.meta.url), 'utf8'), fjs = fs.readFileSync(new URL('../docs/fotos.js', import.meta.url), 'utf8'), pjs = fs.readFileSync(new URL('../docs/proyecto.js', import.meta.url), 'utf8');
  ok('lista: Upcoming sale de los mismos días que las tarjetas (nunca dos tarjetas con la fecha de hoy)', /const prox = dias\.some\(d => d\.dia === hoy\)/.test(js) && !/const prox = LECT\.some/.test(js));
  ok('lista: un cuarto con equipo trabajando ese día sale en ese día aunque nadie lo leyera', /conEquipo\(c\)\)/.test(js) && /R\.equipoEnDia\(porDia, c\.id, dia\); return !!e && Object\.values\(e\.cuentas\)\.some/.test(js));
  ok('lista: la lectura dice solo la fecha (sin la hora)', /<small>\$\{esc\(R\.fechaLarga\(dia\)\)\}<\/small>/.test(js));
  ok('foto de la lista: abre con las fotos de SU cuarto (no depende del filtro de Photos)', /fotos\.abrirVisor\(el\.dataset\.dlFoto, ids\)/.test(js) && /export async function abrirVisor\(fotoId, ids\)/.test(fjs) && /if\(VISOR_IDS\)\{/.test(fjs));
  ok('foto de la lista: al regresar vuelve la barra del Dry Log y el lugar donde estaba', /alMostrar\(\(id\) => \{/.test(js) && /pintarBarra\(\); if\(v && caja\(\)/.test(js) && /AL_MOSTRAR\.forEach\(fn => \{ try\{ fn\(id\); \}catch\{\} \}\);/.test(app) && app.indexOf('const AL_MOSTRAR = []') < app.indexOf('export function irA('));
  ok('fotos que llegan después: la lista se vuelve a dibujar (solo si cambiaron)', /export function alCambiarFotos\(\)/.test(js) && /if\(firmaFotos\(\) === FIRMA_FOTOS\) return;/.test(js) && /drylog\.alCambiarFotos\(\)/.test(pjs));
  ok('Rooms y el equipo abiertos desde la lista: Back y Save regresan a la lista, donde estaba', /if\(\(PANTALLA === 'equipo' \|\| PANTALLA === 'dia'\) && VOLVER\)\{ volverALista\(\); return true; \}/.test(js) && /if\(VOLVER\)\{ volverALista\(\); return true; \}/.test(js) && /if\(a === 'rooms'\)\{ if\(PANTALLA === 'lista'\) desdeLista\(\);/.test(js) && /\[d\[0\], 'Save', d\[2\]\]/.test(js));
  ok('See all days y el último cuarto abren la lista arriba', /\['dia', 'registro', 'lista'\]\.includes\(PANTALLA\)\) m\.scrollTop = 0/.test(js) && /if\(m && \(PANTALLA === 'dia' \|\| PANTALLA === 'lista'\)\) m\.scrollTop = 0;/.test(js));
  ok('lo abierto/cerrado: solo lo que la persona toca, y se olvida al cambiar de proyecto', /ABIERTO_LI\.clear\(\)/.test(js) && /details\[data-li\] > summary'\); if\(s\) ABIERTO_LI\.set/.test(js) && !/addEventListener\('toggle'/.test(js));
  ok('teléfono tomando lecturas = vuelta abierta (nunca sin la barra que guarda)', /if\(!web && \['cam', 'lectura', 'guardado', 'equipo'\]\.includes\(PANTALLA\)\) SESION = true;/.test(js));
  ok('equipo de la lista: cuántos caben según el ancho, y ningún nombre se sale de su cuadro', /\.dl-li-eq-g\{[^}]*repeat\(auto-fill, minmax\(112px, 1fr\)\)[^}]*overflow:hidden/.test(css) && /\.dl-li-eq-i small\{ display:block; overflow:hidden; text-overflow:ellipsis; \}/.test(css) && !/nth-child\(3n\+1\)/.test(css));
  ok('computadora: un cuarto nunca más ancho que su nivel; los botones a la derecha; la flecha y el número juntos', /minmax\(min\(420px, 100%\), 1fr\)/.test(css) && /#panel-secado \.dl-lista-cab \.dl-lista-t\{ margin-right:auto; \}/.test(css) && /\.dl-tend\{[^}]*white-space:nowrap/.test(css)); }
console.log(`\ndrylog: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
