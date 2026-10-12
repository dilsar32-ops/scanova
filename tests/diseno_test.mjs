// Scanova · el diseño de Amilcar (12 oct 2026): Home con Welcome, Recent Projects, All Projects; barra lateral clara;
// en el teléfono la barra de abajo con la cámara al centro. Lo puro del panel, la ficha, las personas y el armazón.
import fs from 'node:fs';
import * as T from '../docs/trabajos.js';
import * as P from '../docs/panel.js';
import { personaHtml, solicitudHtml } from '../docs/personas.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const idx = fs.readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8');
const css = fs.readFileSync(new URL('../docs/estilo.css', import.meta.url), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');   // sin comentarios
const app = fs.readFileSync(new URL('../docs/app.js', import.meta.url), 'utf8');
const AHORA = Date.parse('2026-10-12T12:00:00Z');
const hace = (seg) => new Date(AHORA - seg * 1000).toISOString();

// ---------- lo de siempre (ficha, fechas, personas) ----------
ok('fechaRelativa: ahora mismo / minutos / horas / ayer / días', T.fechaRelativa(hace(10), AHORA) === 'ahora mismo' && T.fechaRelativa(hace(5 * 60), AHORA) === 'hace 5 min' && T.fechaRelativa(hace(3 * 3600), AHORA) === 'hace 3 h' && T.fechaRelativa(hace(30 * 3600), AHORA) === 'ayer' && T.fechaRelativa(hace(4 * 86400), AHORA) === 'hace 4 días');
ok('iniciales: dos nombres, uno, vacío', T.iniciales('Amilcar Gonzalez') === 'AG' && T.iniciales('Vero') === 'V' && T.iniciales('  ') === '·');
ok('mapsUrl: la dirección va codificada', T.mapsUrl('9 Oak Ln, Vienna VA') === 'https://maps.google.com/?q=9%20Oak%20Ln%2C%20Vienna%20VA');
const t = { id:'x1', cliente:'Lauren <Harris>', direccion:'9 Oak Ln', telefono:'(703) 555-0123', correo:'l@c.com', tipo:'agua', estado:'activo', notas:'Sótano', created_at:hace(86400), updated_at:'2026-10-10T16:00:00Z' };
const PR = await import('../docs/proyecto.js');
const cab = PR.cabeceraHtml({ ...t, cliente_nombre:'Harris <Family>', encargado:'Amilcar', fecha_inicio:'2026-10-10', etapa:'en_curso' }, 'x.jpg', true);
ok('cabeceraHtml: portada, nombre escapado, mapas, etapa, cliente, encargado, fecha, Edit Project y •••', /class="portada"><img src="x.jpg"/.test(cab) && /<h1 class="pcab-t">Lauren &lt;Harris&gt;<\/h1>/.test(cab) && /maps\.google\.com/.test(cab) && !/>Active</.test(cab) && !/>In Progress</.test(cab) && /Client: Harris &lt;Family&gt;/.test(cab) && /Project Manager<\/span><span class="corto">PM<\/span>: Amilcar/.test(cab) && /data-editar-etq/.test(cab) && /data-det-abrir/.test(cab) && /Start Date: Oct 10, 2026/.test(cab) && /id="btnEditar"/.test(cab) && /id="btnFichaMenu"/.test(cab));
ok('cabeceraHtml: sin cliente ni fecha no inventa nada (dice cuándo se creó)', !/Client:/.test(PR.cabeceraHtml(t, '', false)) && /Created: /.test(PR.cabeceraHtml(t, '', false)));
ok('personaHtml y solicitudHtml: avatar, chip y los dos botones', /class="avatar">AG</.test(personaHtml({ full_name:'Amilcar Gonzalez', role:'manager', status:'active' })) && /data-decidir="si"/.test(solicitudHtml({ user_id:'u1', nombre:'Vero' })));

// ---------- el panel nuevo: etapa, avance, fechas ----------
ok('etapaDe: archivado manda; sin columna o raro = In Progress', P.etapaDe({ estado:'archivado', etapa:'planeacion' }) === 'archivado' && P.etapaDe({ estado:'activo' }) === 'en_curso' && P.etapaDe({ estado:'activo', etapa:'zzz' }) === 'en_curso' && P.etapaDe({ estado:'activo', etapa:'completado' }) === 'completado');
ok('pillHtml: Planning / In Progress / Completed / Archived con su clase', /class="pill planeacion">Planning</.test(P.pillHtml({ etapa:'planeacion' })) && /class="pill en_curso">In Progress</.test(P.pillHtml({})) && /class="pill completado">Completed</.test(P.pillHtml({ etapa:'completado' })) && /class="pill archivado">Archived</.test(P.pillHtml({ estado:'archivado' })));
ok('avanceDe: nadie lo puso = null (no se inventa); se recorta a 0-100 y se redondea', P.avanceDe({}) === null && P.avanceDe({ avance:null }) === null && P.avanceDe({ avance:'' }) === null && P.avanceDe({ avance:64.6 }) === 65 && P.avanceDe({ avance:180 }) === 100 && P.avanceDe({ avance:-5 }) === 0 && P.avanceDe({ avance:0 }) === 0);
ok('progresoHtml: sin avance no hay barra; con avance, ancho y % y el color de la etapa', P.progresoHtml({ avance:null }) === '' && /style="width:40%"/.test(P.progresoHtml({ avance:40 })) && /<b>40%<\/b>/.test(P.progresoHtml({ avance:40 })) && /class="planeacion"/.test(P.progresoHtml({ avance:20, etapa:'planeacion' })));
ok('fechaEn y hoyLargo: como en el diseño (Oct 10, 2026 / Monday, Oct 12, 2026)', P.fechaEn('2026-10-10T16:00:00Z') === 'Oct 10, 2026' && P.fechaEn('') === '' && P.hoyLargo(new Date(2026, 9, 12, 9)) === 'Monday, Oct 12, 2026');
ok('primerNombre: "Amilcar Gonzalez" -> Amilcar; vacío -> ""', P.primerNombre('Amilcar Gonzalez') === 'Amilcar' && P.primerNombre('') === '');
const L = [
  { id:'a', cliente:'Harris Residence', direccion:'1234 Maple Ave, Arlington VA', estado:'activo', etapa:'en_curso', updated_at:'2026-10-10T10:00:00Z' },
  { id:'b', cliente:'Shonte Property', direccion:'5678 Cedar Ln, Rockville MD', estado:'activo', etapa:'en_curso', updated_at:'2026-10-08T10:00:00Z' },
  { id:'c', cliente:'Daehn Project', direccion:'1613 D St SE, Washington DC', estado:'activo', etapa:'planeacion', updated_at:'2026-10-05T10:00:00Z' },
  { id:'d', cliente:'Carter Home', direccion:'8942 Oak Dr, Bethesda MD', estado:'activo', etapa:'completado', updated_at:'2026-10-02T10:00:00Z' },
  { id:'e', cliente:'Old Job', direccion:'1 Elm St', estado:'archivado', updated_at:'2026-10-11T10:00:00Z' },
];
ok('recientes: los 3 más recientes sin archivados', P.recientes(L).map(x => x.id).join() === 'a,b,c');
ok('filtrarPanel: todos = sin archivados; Archived = solo archivados; por etapa', P.filtrarPanel(L, 'todos', '').length === 4 && P.filtrarPanel(L, 'archivado', '').map(x => x.id).join() === 'e' && P.filtrarPanel(L, 'planeacion', '').map(x => x.id).join() === 'c');
ok('filtrarPanel: busca en nombre y dirección sin acentos', P.filtrarPanel(L, 'todos', 'cedar').map(x => x.id).join() === 'b' && P.filtrarPanel(L, 'todos', 'CARTER').map(x => x.id).join() === 'd');
ok('ordenar: por nombre ida y vuelta, por fecha la más nueva primero, por etapa', P.ordenar(L, 'nombre', 1)[0].id === 'd' && P.ordenar(L, 'nombre', -1)[0].id === 'b' && P.ordenar(L, 'fecha', -1)[0].id === 'e' && P.ordenar(L.slice(0, 4), 'estado', 1)[0].id === 'c');
const tj = P.tarjetaHtml({ ...L[0], cliente:'A <b>', avance:65 }, 'https://x/y.jpg');
ok('tarjetaHtml: foto, •••, nombre escapado, dirección, fecha, etapa y avance', /<img src="https:\/\/x\/y\.jpg"/.test(tj) && /data-menu="a"/.test(tj) && /A &lt;b&gt;/.test(tj) && /1234 Maple Ave/.test(tj) && /Oct 10, 2026/.test(tj) && /In Progress/.test(tj) && /65%/.test(tj));
ok('tarjetaHtml: sin foto dice "No photos yet"; sin avance no hay barra', /No photos yet/.test(P.tarjetaHtml(L[1], '')) && !/progreso/.test(P.tarjetaHtml(L[1], '')));
const fl = P.filaHtml(L[2]);
ok('filaHtml: abre el proyecto, dirección, fecha, etapa, ••• y la flechita del teléfono', /data-abrir="c"/.test(fl) && /1613 D St SE/.test(fl) && /Oct 5, 2026/.test(fl) && /pill planeacion/.test(fl) && /data-menu="c"/.test(fl) && /chev-movil/.test(fl));
ok('cabTablaHtml: Project Name, Address, Date, Status para ordenar; marca la activa', ['nombre', 'direccion', 'fecha', 'estado'].every(c => new RegExp('data-orden="' + c + '"').test(P.cabTablaHtml({ campo:'fecha' }))) && /tc-orden on" data-orden="fecha"/.test(P.cabTablaHtml({ campo:'fecha' })) && /Project Name/.test(P.cabTablaHtml()));
ok('avanceForma: vacío = null; número recortado 0-100', T.avanceForma('') === null && T.avanceForma(' ') === null && T.avanceForma('35') === 35 && T.avanceForma('150') === 100 && T.avanceForma('-3') === 0 && T.avanceForma('abc') === null);

// ---------- el armazón (página) ----------
const nav = [...idx.matchAll(/class="navitem" data-nav="([a-z]+)"/g)].map(m => m[1]).join(',');
ok('barra lateral: Home, Projects, Capture, Plan, Restore, Reports, Clients, Settings (en ese orden) y Sign Out', nav === 'inicio,proyectos,capture,plan,restore,reports,clients,settings' && /Sign Out/.test(idx) && /class="lat-logo" translate="no">Scanova<span>360<\/span>/.test(idx));
const pie = [...idx.matchAll(/class="tab[^"]*" data-nav="([a-z]+)"/g)].map(m => m[1]).join(',');
ok('barra de abajo (su segunda imagen): Home, Projects, la cámara al centro, Clients, Settings; Gallery en el menú ☰', pie === 'inicio,proyectos,capture,clients,settings' && /class="fab"/.test(idx) && /id="btnMenu"/.test(idx) && /navitem solo-movil" data-nav="galeria"/.test(idx));
ok('arriba: buscar "Search projects, clients, or addresses...", campana y avatar', /placeholder="Search projects, clients, or addresses\.\.\."/.test(idx) && /id="btnCampana"/.test(idx) && /id="avatarBarra"/.test(idx));
ok('Home: Welcome, la frase, Recent Projects con View All, All Projects con All Statuses y buscar', /Welcome, <span id="bienvNombre">/.test(idx) && /Capture\. Plan\. Restore\. All in one place\./.test(idx) && /Recent Projects<\/h2><button type="button" class="ver-todo" data-nav="proyectos">View All/.test(idx) && /<option value="todos">All Statuses<\/option>/.test(idx) && /placeholder="Search projects\.\.\."/.test(idx));
ok('pantallas: Home, Projects, Gallery, More, la de "viene después", Capture (hoja) y el menú •••', ['pInicio', 'pProyectos', 'pGaleria', 'pMas', 'pPronto', 'hojaCaptura', 'menuPop'].every(id => new RegExp('id="' + id + '"').test(idx)));
ok('la forma pide Etapa y Avance', /id="fEtapa"/.test(idx) && /id="fAvance"/.test(idx) && /id="fAvanceBarra"/.test(idx));
ok('ninguna parte dice "Restoration Doctor"', !/Restoration Doctor/.test(idx) && !/Restoration Doctor/.test(app));
ok('css: azul #2563eb, pastillas por etapa, 3 tarjetas en la computadora; sin position:fixed; el que se desplaza es main', /--accent:#2563eb/.test(css) && /\.pill\.planeacion\{/.test(css) && /\.recientes\{ display:grid; grid-template-columns:repeat\(3/.test(css) && !/position:\s*fixed/.test(css) && /main\{[^}]*overflow:auto/.test(css));
ok('app: llega a Home y cada botón va a su lugar (Home, Projects, Gallery, More, Capture, Settings)', /irA\('pInicio'\); panel\.pintar\(\)/.test(app) && /n === 'proyectos'/.test(app) && /n === 'galeria'/.test(app) && /n === 'mas'/.test(app) && /n === 'capture'\) panel\.abrirCaptura\(\)/.test(app) && /n === 'settings'/.test(app));
console.log(`\n${pass} ok, ${fail} fail`); process.exit(fail ? 1 : 0);
