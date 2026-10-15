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
// Su pedido (15-oct): "no hay fondo transparente", "en shapes solo hay dos", "necesito un brush", "ya hay algo
// seleccionado cuando entro" y "poder mover el texto".
ok('Shape: nueve figuras, las dos de antes primero', E.FORMAS.map(f => f[0]).join() === 'circulo,cuadro,redondo,linea,doble,triangulo,estrella,cruz,palomita');
ok('Marker: marcador, pincel (Brush) y resaltador', E.MARCAS.map(f => f[1]).join() === 'Marker,Brush,Highlighter');
ok('Text: con color o transparente', E.FONDOS.map(f => f[0]).join() === 'lleno,ninguno');
{ const W = 1000, H = 1000; const circ = { tipo:'circulo', ancho:5, puntos:[[0.2, 0.2], [0.6, 0.6]] };
  ok('tocar DENTRO de un círculo no lo agarra (se puede poner texto o dibujar adentro)', !E.tocaMarca(circ, 400, 400, 10, W, H));
  ok('...tocar su línea sí lo agarra', E.tocaMarca(circ, 600, 400, 10, W, H) && E.tocaMarca(circ, 400, 203, 10, W, H));
  const caja = { tipo:'cuadro', ancho:5, puntos:[[0.2, 0.2], [0.6, 0.6]] };
  ok('cuadro: el centro libre, el borde se agarra', !E.tocaMarca(caja, 400, 400, 10, W, H) && E.tocaMarca(caja, 200, 400, 10, W, H));
  const raya = { tipo:'lapiz', ancho:5, puntos:[[0.1, 0.1], [0.5, 0.1], [0.5, 0.5]] };
  ok('un trazo se agarra por la línea, no por el hueco de su caja', E.tocaMarca(raya, 300, 105, 10, W, H) && !E.tocaMarca(raya, 200, 400, 10, W, H));
  const pincel = { tipo:'pincel', ancho:5, puntos:[[0.1, 0.5], [0.9, 0.5]] };
  ok('el pincel es ancho: se agarra un poco más lejos que el marcador', E.tocaMarca(pincel, 500, 515, 10, W, H) && !E.tocaMarca({ ...pincel, tipo:'lapiz' }, 500, 515, 10, W, H));
  const area = { tipo:'area', texto:'Wet area', puntos:[[0.1, 0.1], [0.5, 0.1], [0.5, 0.5], [0.1, 0.5]] };
  ok('área mojada: por DENTRO no se agarra (ahí se pone la lectura de humedad); por su orilla y su letrero sí',
    !E.tocaMarca(area, 200, 380, 10, W, H) && E.tocaMarca(area, 100, 300, 10, W, H) && E.tocaMarca(area, 300, 300, 10, W, H));
  const med = { tipo:'medida', texto:'4\' 6"', ancho:5, puntos:[[0.1, 0.5], [0.9, 0.5]] };
  ok('medida: se agarra por su línea y por su letrero', E.tocaMarca(med, 500, 510, 10, W, H) && !E.tocaMarca(med, 500, 600, 10, W, H));
  const texto = { tipo:'texto', texto:'Mold', puntos:[[0.5, 0.5]], escala:1, fondo:'ninguno' };
  ok('el texto (con o sin fondo) se agarra en toda su caja: se puede mover', E.tocaMarca(texto, 500, 500, 10, W, H) && E.tocaMarca({ ...texto, fondo:'lleno' }, 500, 500, 10, W, H));
  const tri = { tipo:'triangulo', ancho:5, puntos:[[0.2, 0.2], [0.6, 0.6]] };
  ok('triángulo: la punta arriba; girado un cuarto (con la foto) la punta queda a la derecha',
    E.tocaMarca(tri, 400, 200, 10, W, H) && !E.tocaMarca({ ...tri, giro:1 }, 400, 200, 10, W, H) && E.tocaMarca({ ...tri, giro:1 }, 600, 400, 10, W, H));
  const est = { tipo:'estrella', ancho:5, puntos:[[0.2, 0.2], [0.6, 0.6]] };
  ok('estrella: la punta de arriba se agarra, el centro no', E.tocaMarca(est, 400, 200, 10, W, H) && !E.tocaMarca(est, 400, 400, 10, W, H)); }
ok('bordeDeTexto: borde oscuro para letra clara, claro para letra casi negra', E.bordeDeTexto('#ffffff').includes('0,0,0') && E.bordeDeTexto('#ffd60a').includes('0,0,0') && E.bordeDeTexto('#1d1d1f').includes('255,255,255'));
{ // Pintar con un lienzo de mentira: el texto transparente NO pinta la pastilla de fondo, solo la letra con su borde.
  const hecho = []; const ctx = new Proxy({}, { get: (o, k) => k in o ? o[k] : (k === 'measureText' ? (t) => ({ width: String(t).length * 9 }) : (...a) => { hecho.push(k); }), set: (o, k, v) => { o[k] = v; return true; } });
  E.dibujar(ctx, 1000, 800, [{ tipo:'texto', texto:'Mold', color:'#ffffff', puntos:[[0.5, 0.5]], escala:1, fondo:'ninguno' }]);
  const suelto = hecho.slice(); hecho.length = 0;
  E.dibujar(ctx, 1000, 800, [{ tipo:'texto', texto:'Mold', color:'#ffffff', puntos:[[0.5, 0.5]], escala:1 }]);
  ok('texto transparente: sin pastilla (sin fill de fondo), con la letra bordeada', !suelto.includes('fill') && !suelto.includes('arcTo') && suelto.includes('strokeText') && suelto.includes('fillText'));
  ok('texto de siempre (sin "fondo" guardado): con su pastilla, como antes', hecho.includes('arcTo') && hecho.includes('fill') && hecho.includes('fillText'));
  hecho.length = 0; E.dibujar(ctx, 1000, 800, [{ tipo:'pincel', color:'#ff3b30', ancho:5, puntos:[[0.1, 0.1], [0.3, 0.2], [0.5, 0.1], [0.7, 0.3]] }]);
  ok('pincel: trazo suavizado en dos pasadas', hecho.filter(x => x === 'stroke').length === 2 && hecho.includes('quadraticCurveTo'));
  const sinPintar = E.FORMAS.filter(([k]) => { hecho.length = 0; E.dibujar(ctx, 1000, 800, [{ tipo:k, color:'#ff3b30', ancho:5, puntos:[[0.2, 0.2], [0.6, 0.5]] }]); return !hecho.includes('stroke'); });
  ok('las nueve figuras se pintan' + (sinPintar.length ? ' (faltan: ' + sinPintar.map(f => f[0]).join() + ')' : ''), !sinPintar.length); }
{ const src = (await import('node:fs')).readFileSync(new URL('../docs/editor.js', import.meta.url), 'utf8');
  ok('al abrir el editor NO hay herramienta escogida', /herr: '', forma: 'circulo'/.test(src));
  ok('sin herramienta, tocar la foto no dibuja nada', /const t0 = herrActual\(\);/.test(src) && /const t = t0; if\(!t\) return;/.test(src));
  ok('tocar otra vez la herramienta escogida la suelta (salvo en Crop del teléfono, donde se veía apagada)', /E\.herr = E\.herr === h && !el\.closest\('#edHoja'\) && !\(enCrop && el\.closest\('#edTel'\)\) \? '' : h;/.test(src));
  ok('la foto de abajo solo se vuelve a pintar cuando cambia (no con cada movimiento del dedo)', /if\(llave !== E\.baseLlave \|\| E\.baseMarco !== E\.marco\)/.test(src));
  ok('el trazo guarda un punto cada 2 px de pantalla, no en cada evento', /acc\.k < 2\) return; m\.puntos\.push\(p\);/.test(src));
  ok('"Original" en Crop usa la foto como se ve (girada)', /pr\[2\] === -1 \? FW\(\) \/ FH\(\) : pr\[2\]/.test(src)); }
ok('brillo + contraste como el CSS: el blanco se corta antes del contraste (la foto guardada ya no sale más clara)', (() => { const f = { mult:2, con:0.5, sat:1 }; return E.ajustarPixel(200, f) === 191 && E.ajustarPixel(255, f) === 191; })());
ok('Sharpness: con paso 2 mira a los vecinos de 2 pixeles (mismo realce relativo en la foto grande)', (() => { const w = 9, h = 5, d = new Uint8ClampedArray(w * h * 4).fill(100); for(let y = 0; y < h; y++) for(let x = 5; x < w; x++){ const i = (y * w + x) * 4; d[i] = d[i + 1] = d[i + 2] = 200; }
  const r1 = E.nitidez(new Uint8ClampedArray(d), w, h, 100, 1), r2 = E.nitidez(new Uint8ClampedArray(d), w, h, 100, 2); const at = (r, x) => r[(2 * w + x) * 4]; return at(r1, 3) === 100 && at(r2, 3) < 100 && at(r2, 4) < 100; })());
ok('las marcas miden lo mismo con la foto acostada o parada (la medida es el lado largo)', (() => { const m = { tipo:'texto', texto:'Mold', puntos:[[0.5, 0.5]], escala:1 }; const a = E.cajaMarca(m, 1600, 1200), b = E.cajaMarca(m, 1200, 1600); return Math.abs(a.w - b.w) < 1e-9 && Math.abs(a.h - b.h) < 1e-9; })());
{ const src = (await import('node:fs')).readFileSync(new URL('../docs/editor.js', import.meta.url), 'utf8');
  ok('un dedo a la vez: el segundo dedo de un pellizco no dibuja ni suelta lo que se arrastra', /if\(acc \|\| ev\.isPrimary === false \|\| ev\.button > 0\) return;/.test(src) && /if\(ev\.pointerId !== acc\.id\) return;/.test(src));
  ok('si iOS interrumpe el toque, se descarta (no se guarda como si hubiera soltado)', /c\.addEventListener\('pointercancel', cancelar\)/.test(src) && !/addEventListener\('pointercancel', fin\)/.test(src));
  ok('tocar afuera de la marca escogida solo la suelta', /if\(E\.sel >= 0\)\{ E\.sel = -1; render\(\); pintarPanel\(\); return; \}/.test(src));
  ok('margen de 6 px para el temblor del dedo antes de mover', /ev\.clientY - acc\.cy\) < 6\) return; acc\.movio = true;/.test(src));
  ok('abrir otra foto mientras la primera carga no pisa al editor nuevo', /if\(E !== yo\)\{ URL\.revokeObjectURL\(url\); return; \}/.test(src) && /if\(E\.lienzo\) return;/.test(src));
  ok('guardar usa SU editor aunque cambie a mitad, con lo que había al tocar Save', /const s = estado\(\); const foto = \{ \.\.\.yo, marcas: s\.marcas/.test(src) && /const archivo = await copiaFinal\(foto\);[^\n]*\n\s*const r = await yo\.guardar\(archivo\);/.test(src));
  ok('el Save de arriba del teléfono se vuelve a prender', /querySelectorAll\('#fvTelGuardar'\)\.forEach\(b => \{ b\.disabled = false; \}\)/.test(src));
  ok('abrir la hoja Markup ya no escoge Moisture solo', !/E\.herr = 'humedad'/.test(src));
  ok('Blur: en la vista se difumina la foto de abajo ya ajustada (como en la guardada)', /pixelar\(bx, E\.ajustada,/.test(src) && /dibujar\(ctx, w, h, blurs, limpio\)/.test(src));
  ok('un WET/DRY escogido a mano vale solo para esa lectura', /E\.estado = ''; E\.estadoFijo = false;   \/\/ un WET\/DRY/.test(src)); }
{ const app = (await import('node:fs')).readFileSync(new URL('../docs/app.js', import.meta.url), 'utf8');
  ok('irse a otra pantalla con cambios en el editor pregunta (Save / Discard)', /if\(!forzar && id !== 'pFoto' && editor\.sinGuardar\(\)\)\{ editor\.salir\(\(\) => irA\(id, desde, true\)\); return; \}/.test(app) && /hayCambios\(\) \|\| editor\.sinGuardar\(\)/.test(app)); }
// Su "sí" (15-oct): Line width junto a las herramientas que lo usan, no en Markup Tools.
ok('cuatro grosores para el teléfono (Thin, Medium, Thick, Extra thick)', E.GROSORES.map(g => g[2]).join() === '2,5,9,14');
ok('qué marcas tienen grosor: flecha, marcadores, figuras y medida; texto, humedad, área y blur no', ['flecha', 'lapiz', 'pincel', 'resalta', 'medida', 'circulo', 'estrella'].every(E.USA_GROSOR) && !['texto', 'humedad', 'area', 'borroso'].some(E.USA_GROSOR));
ok('el botón encendido es el grosor más cercano', E.grosorCercano(5) === 'medio' && E.grosorCercano(1) === 'fino' && E.grosorCercano(12) === 'extra' && E.grosorCercano(7.4) === 'grueso');
{ const src = (await import('node:fs')).readFileSync(new URL('../docs/editor.js', import.meta.url), 'utf8');
  ok('Markup Tools ya no tiene la barra de Line width (un solo lugar: junto a la herramienta)', !/seccion\('markup'[^\n]*Line width/.test(src) && !/<div class="ed-fila"><span>Line width<\/span>/.test(src));
  ok('la barra sale en las opciones de la herramienta y de la marca escogida', /USA_GROSOR\(sel\.tipo\) \? filaGrosor\(sel\.ancho\)/.test(src) && /USA_GROSOR\(herrActual\(\)\) \? filaGrosor\(E\.ancho\)/.test(src));
  ok('en el teléfono, los grosores en la fila de Shape, Marker, Arrow/Measure y de la marca escogida', (src.match(/chipsGrosor\(/g) || []).length >= 4);
  ok('cambiar el grosor con una marca escogida la cambia (con Undo)', /if\(m && USA_GROSOR\(m\.tipo\) && \(m\.ancho \|\| 4\) !== n\)\{ E\.deshacer\.push\(estado\(\)\); E\.rehacer = \[\]; m\.ancho = n;/.test(src));
  ok('el estado de antes del slider es siempre el de ese momento', /\(e\.target\.dataset\.edAj \|\| e\.target\.id === 'edAncho'\)\) E\.ajAntes = estado\(\); \};/.test(src)); }
{ const src = (await import('node:fs')).readFileSync(new URL('../docs/editor.js', import.meta.url), 'utf8');
  // Probado en el iPhone (simulador): tras cerrar el teclado, iOS cancelaba el primer arrastre (pointercancel) y el texto
  // regresaba: "no se puede mover el texto".
  ok('un toque que empieza en la foto nunca mueve la página (iOS ya no cancela el arrastre tras el teclado)', /c\.addEventListener\('touchstart', sinPagina, \{ passive:false \}\); c\.addEventListener\('touchmove', sinPagina, \{ passive:false \}\);/.test(src)); }
// Segunda revisión (15-oct, 54 agentes, cada hallazgo comprobado dos veces): lo que se arregló.
ok('con una herramienta escogida, la flecha vieja se agarra solo justo encima (sin el margen extra)', (() => { const m = { tipo:'flecha', ancho:5, puntos:[[0.1, 0.5], [0.5, 0.5]] };
  return E.tocaMarca(m, 300, 517, 6, 1000, 1000) && !E.tocaMarca(m, 300, 517, 6, 1000, 1000, true) && E.tocaMarca(m, 300, 505, 6, 1000, 1000, true); })());
ok('la caja de la flecha gruesa encierra su punta (antes el clic en el ala no la agarraba)', (() => { const c = E.cajaMarca({ tipo:'flecha', ancho:14, puntos:[[0.1, 0.5], [0.5, 0.5]] }, 1000, 1000); return E.dentro(c, 470, 530) && E.dentro(c, 470, 470); })());
ok('la caja de Measure encierra sus rayitas y su letrero', (() => { const c = E.cajaMarca({ tipo:'medida', ancho:9, texto:"12' 6\" long wall", puntos:[[0.5, 0.2], [0.5, 0.3]] }, 1000, 1000); return E.dentro(c, 500 + 9 * 3, 200) && E.dentro(c, 500 + 60, 250); })());
ok('el rectángulo redondeado se agarra por su esquina redonda (la que se ve)', (() => { const m = { tipo:'redondo', ancho:5, puntos:[[0.2, 0.2], [0.8, 0.8]] }; const r = 720 * 0.18, x = 320 + r - r * Math.SQRT1_2, y = 240 + r - r * Math.SQRT1_2;
  return E.tocaMarca(m, x, y, 4, 1600, 1200, true) && !E.tocaMarca(m, 330, 250, 4, 1600, 1200, true); })());
ok('Blur: el cuadrito crece con el cuadro tapado (un número grande queda en 4 cuadritos y ya no se lee)', Math.abs(E.tamBlur(4032, 3024, 400, 220) - 55) < 1e-9 && Math.abs(E.tamBlur(4032, 3024, 60, 40) - 44.8) < 1e-9);
{ const fs = await import('node:fs'); const src = fs.readFileSync(new URL('../docs/editor.js', import.meta.url), 'utf8');
  const app = fs.readFileSync(new URL('../docs/app.js', import.meta.url), 'utf8'), foto = fs.readFileSync(new URL('../docs/foto.js', import.meta.url), 'utf8'), css = fs.readFileSync(new URL('../docs/estilo.css', import.meta.url), 'utf8');
  ok('con Moisture escogido, un Wet area no se agarra (adentro van las lecturas)', /if\(t0 === 'humedad' && mk\.tipo === 'area'\) continue;/.test(src));
  ok('con herramienta, la marca escogida ya no se agarra por toda su caja (salvo texto, lectura y Blur)', /const porCaja = i === E\.sel && \(!t0 \|\| \['texto', 'humedad', 'borroso'\]\.includes\(mk\.tipo\)\);/.test(src));
  ok('el asa metida en la caja (marca en la esquina) igual cambia el tamaño, y el cursor dice lo mismo', /function enAsa\(cj, a, fx, fy, radio\)\{ return \(dentro\(cj, a\.x, a\.y, 0\) \|\| !dentro\(cj, fx, fy, 0\)\)/.test(src) && (src.match(/enAsa\(cj, a, fx, fy,/g) || []).length === 3);
  ok('mientras guarda no se dibuja, no se cambia nada y el teclado no hace Undo', /if\(!E \|\| E\.cargando \|\| E\.guardando\) return;/.test(src) && /if\(E\.guardando && !q\('\[data-ed="cerrar"\]'\)\) return;/.test(src) && /if\(!E \|\| E\.guardando\) return;/.test(src) && /body\.ed-guardando #edTel/.test(css));
  ok('el aviso (Saving…, Could not save) sale de E.aviso en cada repintado y solo en la parte que se ve', !/\$\('#edAviso'\)/.test(src) && (src.match(/\$\{avisoHtml\(\)\}/g) || []).length === 2 && /zonas\(\)\.forEach\(z => z\.querySelectorAll\('#edAviso'\)/.test(src));
  ok('Apply se queda apagado mientras guarda (también tras un repintado)', /data-ed="aplicar"\$\{E\.guardando \? ' disabled' : ''\}/.test(src));
  ok('al pasar a computadora se vacía la bandeja, y al cerrar se limpia siempre', /if\(!tel\)\{ E\.hoja = ''; E\.bandeja\.innerHTML = '';/.test(src) && /if\(x\.bandeja\)\{ x\.bandeja\.hidden = true; x\.bandeja\.innerHTML = ''; \}/.test(src));
  ok('la hoja de Markup no pone velo, y el toque en la foto la cierra y dibuja', /E\.velo\.hidden = !E\.hoja \|\| E\.hoja === 'markup';/.test(src) && /if\(E\.hoja\)\{ E\.hoja = ''; pintarPanel\(\); \}/.test(src) && /body\.fv-editando \.fv-cab\{ z-index:30; \}/.test(css));
  ok('Crop: se agarra la esquina MÁS CERCANA', /if\(d < mejor\)\{ mejor = d; i = j; \}/.test(src) && !/esq\.findIndex/.test(src));
  ok('Undo solo si cambia: la misma proporción y editar dejando lo mismo no gastan un paso', /Math\.abs\(nuevo\.h - c0\.h\) < 1e-9\)\{ pintarPanel\(\); return; \}/.test(src) && /t\.trim\(\) !== \(m\.texto \|\| ''\)/.test(src) && /t\.trim\(\) !== String\(m\.valor == null \? '' : m\.valor\)/.test(src));
  ok('la proporción regresa con el Undo', /crop: \{ \.\.\.E\.crop \}, prop: E\.prop \}/.test(src) && /E\.prop = s\.prop \|\| 'libre';/.test(src));
  ok('Undo de solo marcas no reacomoda los lienzos', /if\(girado \|\| recorte\) colocar\(\); else render\(\);/.test(src));
  ok('si iOS interrumpe un arrastre, el Redo regresa también', /acc\.rehacerAntes = E\.rehacer;/.test(src) && /E\.rehacer = a\.rehacerAntes \|\| \[\]; volver\(s0\);/.test(src));
  ok('Blur: la foto ajustada se guarda aparte (moverlo no recorre la foto entera en cada cuadro)', /if\(llaveAj !== E\.ajLlave \|\| E\.baseMarco !== E\.marco \|\| !E\.ajustada\)/.test(src));
  ok('Blur: no se sale de la foto (no queda una franja sin tapar en la orilla)', /if\(m\.tipo === 'borroso'\) m\.puntos = m\.puntos\.map\(q => \[Math\.max\(0, Math\.min\(1, q\[0\]\)\)/.test(src) && /const x0 = Math\.max\(0, Math\.round\(x\)\)/.test(src));
  ok('girar o agrandar la ventana acomoda una sola vez por cuadro', /window\.addEventListener\('resize', colocarLuego\)/.test(src) && /window\.removeEventListener\('resize', colocarLuego\)/.test(src) && /if\(c\.width !== W \|\| c\.height !== H\)/.test(src));
  ok('la barra lateral con cambios pregunta ANTES de vaciar la pila', /if\(n !== 'atras' && n !== 'capture' && !TEXTO_PRONTO\[n\] && editor\.sinGuardar\(\)\)\{ editor\.salir\(\(\) => b\.click\(\)\); return; \}/.test(app));
  ok('Sign Out cierra el editor', /export function salir\(\)\{ if\(editor\.activo\(\)\) editor\.cerrar\(true\);/.test(app));
  ok('borrar la foto mientras se edita primero sale del editor', /async function borrar\(\)\{ if\(editor\.activo\(\)\)\{ editor\.salir\(\(\) => borrar\(\)\); return; \}/.test(foto)); }
console.log(`\neditor: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
