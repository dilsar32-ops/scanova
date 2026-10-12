// Scanova · diseño "como CompanyCam": lo puro de las filas, la ficha y las personas, y que la página tenga el armazón.
import fs from 'node:fs';
import * as T from '../docs/trabajos.js';
import { personaHtml, solicitudHtml } from '../docs/personas.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const idx = fs.readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8');
const css = fs.readFileSync(new URL('../docs/estilo.css', import.meta.url), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');   // sin comentarios
const app = fs.readFileSync(new URL('../docs/app.js', import.meta.url), 'utf8');
const AHORA = Date.parse('2026-10-12T12:00:00Z');
const hace = (seg) => new Date(AHORA - seg * 1000).toISOString();

ok('fechaRelativa: ahora mismo / minutos / horas', T.fechaRelativa(hace(10), AHORA) === 'ahora mismo' && T.fechaRelativa(hace(5 * 60), AHORA) === 'hace 5 min' && T.fechaRelativa(hace(3 * 3600), AHORA) === 'hace 3 h');
ok('fechaRelativa: ayer / días / y luego la fecha', T.fechaRelativa(hace(30 * 3600), AHORA) === 'ayer' && T.fechaRelativa(hace(4 * 86400), AHORA) === 'hace 4 días' && /2026/.test(T.fechaRelativa(hace(30 * 86400), AHORA)));
ok('fechaRelativa: vacío o basura no truena', T.fechaRelativa('', AHORA) === '' && T.fechaRelativa('nada', AHORA) === '');
ok('iniciales: dos nombres, uno, vacío', T.iniciales('Amilcar Gonzalez') === 'AG' && T.iniciales('Vero') === 'V' && T.iniciales('  ') === '·' && T.iniciales('miguel ángel galeas') === 'MG');
ok('mapsUrl: la dirección va codificada', T.mapsUrl('9 Oak Ln, Vienna VA') === 'https://maps.google.com/?q=9%20Oak%20Ln%2C%20Vienna%20VA');
const t = { id:'x1', cliente:'Lauren <Harris>', direccion:'9 Oak Ln', telefono:'(703) 555-0123', correo:'l@c.com', tipo:'agua', estado:'activo', notas:'Sótano', created_at:hace(86400), updated_at:hace(600) };
const etq = T.etiquetas(t);
ok('etiquetas: tipo y estado con su color; un tipo raro cae en "otro"', /class="etq tipo-agua">Agua</.test(etq) && /class="etq activo">Activo</.test(etq) && /tipo-otro/.test(T.etiquetas({ tipo:'zzz', estado:'archivado' })) && /archivado">Archivado/.test(T.etiquetas({ tipo:'zzz', estado:'archivado' })));
const fila = T.filaHtml(t, 3, AHORA);
ok('filaHtml: miniatura, nombre escapado, dirección, etiquetas, cuándo, conteo y 4 huecos de fotos', /class="miniatura"/.test(fila) && /Lauren &lt;Harris&gt;/.test(fila) && /9 Oak Ln/.test(fila) && /tipo-agua/.test(fila) && /hace 10 min/.test(fila) && /<b>3<\/b> fotos/.test(fila) && (fila.match(/foto-vacia/g) || []).length === 4);
ok('filaHtml: 1 foto en singular, sin fotos = 0', /<b>1<\/b> foto</.test(T.filaHtml(t, 1, AHORA)) && /<b>0<\/b> fotos/.test(T.filaHtml(t, undefined, AHORA)));
const ficha = T.fichaHtml(t, 0, true);
ok('fichaHtml: portada, título, dirección a mapas, Editar, Llamar/Mensaje con dígitos, Archivar solo manager', /class="portada"/.test(ficha) && /<h1 class="titulo">Lauren &lt;Harris&gt;<\/h1>/.test(ficha) && /maps\.google\.com\/\?q=9%20Oak%20Ln/.test(ficha) && /id="btnEditar"/.test(ficha) && /href="tel:7035550123"/.test(ficha) && /href="sms:7035550123"/.test(ficha) && /id="btnArchivar"/.test(ficha) && !/id="btnArchivar"/.test(T.fichaHtml(t, 0, false)));
ok('fichaHtml: pestañas Fotos (n) y Datos; Datos trae teléfono, correo, tipo y notas', /Fotos <span class="n">\(0\)<\/span>/.test(ficha) && /data-tab="datos"/.test(ficha) && /data-panel="datos" hidden/.test(ficha) && /l@c\.com/.test(ficha) && /Sótano/.test(ficha));
ok('fichaHtml: sin teléfono no salen Llamar ni Mensaje; archivado dice Reactivar', !/Llamar/.test(T.fichaHtml({ ...t, telefono:null }, 0, true)) && /Reactivar/.test(T.fichaHtml({ ...t, estado:'archivado' }, 0, true)));
ok('personaHtml: avatar con iniciales y el chip de estado (manager / activo / en espera)', /class="avatar">AG</.test(personaHtml({ full_name:'Amilcar Gonzalez', role:'manager', status:'active' })) && />manager</.test(personaHtml({ full_name:'A', role:'manager' })) && /estado-chip pausado/.test(personaHtml({ full_name:'R', role:'crew', status:'paused' })));
ok('solicitudHtml: nombre, correo, fecha y los dos botones con data-decidir', /data-user="u1"/.test(solicitudHtml({ user_id:'u1', nombre:'Vero', correo:'v@c.com', created_at:hace(60) })) && /data-decidir="si"/.test(solicitudHtml({ user_id:'u1', nombre:'Vero' })) && /data-decidir="no"/.test(solicitudHtml({ user_id:'u1', nombre:'Vero' })));
ok('index: barra lateral, barra de arriba y pestañas de abajo comparten data-nav; Personas sale escondida', /class="lateral"/.test(idx) && /class="barra"/.test(idx) && /class="pie"/.test(idx) && (idx.match(/data-nav="trabajos"/g) || []).length === 2 && (idx.match(/data-nav="personas"/g) || []).length === 2 && /data-nav="personas" id="btnPersonas" hidden/.test(idx));
ok('index: iconos de línea definidos y usados; letra Plus Jakarta Sans', /<symbol id="i-pin"/.test(idx) && /<use href="#i-camara"/.test(idx) === false && /fonts\.googleapis\.com\/css2\?family=Plus\+Jakarta\+Sans/.test(idx));
ok('css: colores de CompanyCam (lateral #192d43, azul #0967d2); sin position:fixed (falla en su iPhone); el que se desplaza es main', /--nav:#192d43/.test(css) && /--accent:#0967d2/.test(css) && !/position:\s*fixed/.test(css) && /main\{[^}]*overflow:auto/.test(css));
ok('css: etiquetas de color por tipo y estado; rejilla de 4 columnas solo en computadora', /\.etq\.tipo-agua\{ background:#0967d2; \}/.test(css) && /\.etq\.archivado\{ background:#2e3a4a; \}/.test(css) && /@media \(min-width:900px\)\{[\s\S]*\.tabla-cab, \.fila-trabajo\{ display:grid; grid-template-columns:minmax\(300px,1\.6fr\) 170px 150px/.test(css));
ok('app: una sola navegación por data-nav (atrás, trabajos, personas, salir) y las iniciales en los dos avatares', /closest\('\[data-nav\]'\)/.test(app) && /n === 'atras'/.test(app) && /n === 'personas'/.test(app) && /n === 'salir'/.test(app) && /#avatarLateral/.test(app) && /#avatarBarra/.test(app));
console.log(`\n${pass} ok, ${fail} fail`); process.exit(fail ? 1 : 0);
