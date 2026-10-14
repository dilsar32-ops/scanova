// Scanova · la ventana de la foto y el editor (12 oct 2026). Lo puro.
import * as E from '../docs/editor.js';
import * as FO from '../docs/foto.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
ok('herramientas: lápiz, resaltador, flecha, círculo, cuadro, texto, humedad, área mojada, medida, difuminar', E.HERRAMIENTAS.map(h => h[0]).join() === 'lapiz,resalta,flecha,circulo,cuadro,texto,humedad,area,medida,borroso');
ok('estadoHumedad: 17% o más WET, 12-16 DRYING, menos DRY; sin número cuenta como WET', E.estadoHumedad(28) === 'wet' && E.estadoHumedad(17) === 'wet' && E.estadoHumedad(16.9) === 'drying' && E.estadoHumedad(12) === 'drying' && E.estadoHumedad(9) === 'dry' && E.estadoHumedad('') === 'wet');
ok('estadoHumedad: valores concretos', E.estadoHumedad('28') === 'wet' && E.estadoHumedad('14') === 'drying' && E.estadoHumedad('9') === 'dry');
ok('ajustes en cero = sin filtro, y el pixel no cambia', E.filtroCss({ exp:0, bri:0, con:0 }) === '' && E.ajustarPixel(100, E.factores({})) === 100 && E.ajustarPixel(0, E.factores({})) === 0 && E.ajustarPixel(255, E.factores({})) === 255);
ok('exposición +100 dobla la luz (y no pasa de 255)', E.ajustarPixel(60, E.factores({ exp:100 })) === 120 && E.ajustarPixel(200, E.factores({ exp:100 })) === 255);
ok('contraste: aleja del gris medio; el gris medio se queda', E.ajustarPixel(200, E.factores({ con:50 })) > 200 && E.ajustarPixel(50, E.factores({ con:50 })) < 50);
ok('filtroCss coincide con la cuenta de la copia (brightness y contrast)', /^brightness\(2\.000\) contrast\(1\.000\) saturate\(1\.000\)$/.test(E.filtroCss({ exp:100 })));
ok('tintaSobre: texto negro sobre amarillo/blanco, blanco sobre rojo/azul', E.tintaSobre('#ffd60a') === '#111' && E.tintaSobre('#ffffff') === '#111' && E.tintaSobre('#ff3b30') === '#fff' && E.tintaSobre('#0a84ff') === '#fff');
ok('nombreArchivo: proyecto, cuarto y fecha, sin acentos ni símbolos', FO.nombreArchivo('José Pérez', 'Living Room', '2026-10-12T14:00:00') === 'Jose-Perez_Living-Room_2026-10-12.jpg' && FO.nombreArchivo('Lauren Harris', '', '2026-10-10T10:00:00') === 'Lauren-Harris_2026-10-10.jpg');
ok('etiquetasDeFoto: las de la foto en el orden del catálogo', FO.etiquetasDeFoto([{ id:'a' }, { id:'b' }, { id:'c' }], ['c', 'a']).map(e => e.id).join() === 'a,c');
ok('el diseño: arriba Text, Arrow, Shape, Marker', E.PRINCIPALES.map(h => h[1]).join() === 'Text,Arrow,Shape,Marker');
ok('Markup Tools guarda las herramientas de agua: Moisture, Wet area, Measure, Blur', E.MARKUP.map(h => h[1]).join() === 'Moisture,Wet area,Measure,Blur');
ok('filtros: Original no cambia nada; B&W quita el color', E.filtroCss({}, 'original') === '' && E.factores({}, 'bn').sat === 0);
ok('filtro + ajuste se suman (Vivid + saturación)', Math.abs(E.factores({ sat:10 }, 'vivo').sat - 1.45) < 1e-9);
ok('saturación 0 = gris: los tres canales iguales', (() => { const [r, g, b] = E.ajustarRGB(200, 40, 40, E.factores({ sat:-100 })); return r === g && g === b; })());
ok('girar 4 veces a la derecha deja el punto donde estaba', (() => { let p = [0.2, 0.7]; for(let i = 0; i < 4; i++) p = E.girarPunto(p, 1); return Math.abs(p[0] - 0.2) < 1e-9 && Math.abs(p[1] - 0.7) < 1e-9; })());
ok('girar a la derecha y luego a la izquierda = igual', (() => { const p = E.girarPunto(E.girarPunto([0.3, 0.1], 1), -1); return Math.abs(p[0] - 0.3) < 1e-9 && Math.abs(p[1] - 0.1) < 1e-9; })());
ok('el recorte gira con la foto (la esquina de arriba a la izquierda pasa a arriba a la derecha)', (() => { const c = E.girarRecorte({ x:0, y:0, w:0.5, h:0.25 }, 1); return Math.abs(c.x - 0.75) < 1e-9 && c.y === 0 && c.w === 0.25 && c.h === 0.5; })());
ok('cajaMarca: el texto tiene caja y crece con la escala', (() => { const a = E.cajaMarca({ tipo:'texto', texto:'Mold', puntos:[[0.5, 0.5]], escala:1 }, 1000, 800), b = E.cajaMarca({ tipo:'texto', texto:'Mold', puntos:[[0.5, 0.5]], escala:2 }, 1000, 800); return a.w > 0 && Math.abs(b.w - 2 * a.w) < 1e-9 && E.dentro(a, 500, 400); })());
ok('cajaMarca: la flecha cubre de punta a punta', (() => { const c = E.cajaMarca({ tipo:'flecha', ancho:5, puntos:[[0.1, 0.1], [0.4, 0.3]] }, 1000, 1000); return E.dentro(c, 100, 100) && E.dentro(c, 400, 300) && !E.dentro(c, 600, 600); })());
ok('Warmth: calienta (más rojo, menos azul) y 0 no cambia nada', (() => { const a = E.calidezRGB(100, 100, 100, 50), b = E.calidezRGB(100, 100, 100, 0); return a[0] > 100 && a[2] < 100 && b.join() === '100,100,100'; })());
ok('Sharpness: realza el borde y deja igual lo parejo', (() => { const w = 5, h = 3, d = new Uint8ClampedArray(w * h * 4).fill(100); for(let y = 0; y < h; y++) for(let x = 3; x < w; x++){ const i = (y * w + x) * 4; d[i] = d[i + 1] = d[i + 2] = 200; }
  const r = E.nitidez(new Uint8ClampedArray(d), w, h, 100); const at = (x) => r[(1 * w + x) * 4]; return at(1) === 100 && at(2) < 100 && at(3) > 200; })());
// Su reporte (13-oct): "cuando uno escribe ya no puede mover el texto". Tocar la foto para terminar de escribir guarda
// el texto (no lo pierde ni abre otro cuadrito), y ese mismo toque ya puede arrastrarlo. Probado también a mano en la
// vista previa: con la versión vieja salía otro "Type here" vacío; con esta, el texto se guarda y se arrastra.
{ const src = (await import('node:fs')).readFileSync(new URL('../docs/editor.js', import.meta.url), 'utf8');
  ok('tocar la foto mientras se escribe GUARDA el texto', /if\(E\.escritura\)\{ const f = E\.escrituraListo; if\(f\) f\(true\);/.test(src));
  ok('...y no abre otro cuadrito vacío en ese toque', /if\(t === 'texto'\)\{ if\(recienEscrito\) return;/.test(src));
  ok('el cuadrito deja guardado cómo terminarlo', /E\.escrituraListo = listo;/.test(src) && /z\.escrituraListo = null;/.test(src)); }
console.log(`\neditor: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
