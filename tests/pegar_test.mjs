// Scanova · PEGAR FOTOS (16-oct, pedido de Nova Construction): lo puro de pegar.js, la hoja con un document de mentira,
// y las reglas de fuente (sin navigator.clipboard, el portapapeles se lee antes de cualquier await, etc.).
import fs from 'node:fs';
import * as P from '../docs/pegar.js';
// El MISMO fotos.js que importa pegar.js (con su ?v=): con otra dirección node lo cargaría dos veces y no compartirían la tanda.
const VER = (fs.readFileSync(new URL('../docs/pegar.js', import.meta.url), 'utf8').match(/from '\.\/fotos\.js(\?v=[^']*)?'/) || [])[1] || '';
const F = await import('../docs/fotos.js' + VER);
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const leer = (f) => fs.readFileSync(new URL('../docs/' + f, import.meta.url), 'utf8');

// ---------- imagenesDePegado ----------
const png = new File([new Uint8Array([1, 2, 3])], 'image.png', { type: 'image/png' });
const png2 = new File([new Uint8Array([4, 5, 6])], 'b.png', { type: 'image/png' });
const txt = new File(['hola'], 'a.txt', { type: 'text/plain' });
const item = (f) => ({ kind: 'file', getAsFile: () => f });
let r = P.imagenesDePegado({ files: [png, txt], items: [] });
ok('files [png, txt]: 1 foto y 1 otro', r.fotos.length === 1 && r.otros === 1);
r = P.imagenesDePegado({ files: [], items: [item(png)] });
ok('files vacío: usa los items de archivo (getAsFile)', r.fotos.length === 1 && r.fotos[0] === png);
r = P.imagenesDePegado({ files: [png], items: [item(png)] });
ok('la misma foto en files y en items: una sola', r.fotos.length === 1);
r = P.imagenesDePegado({ files: [], items: [{ kind: 'string', getAsFile: () => null }] });
ok('solo texto: nada', r.fotos.length === 0 && r.otros === 0);
ok('null o undefined: no truena', P.imagenesDePegado(null).fotos.length === 0 && P.imagenesDePegado(undefined).otros === 0);
r = P.imagenesDePegado({ files: [new File(['<svg/>'], 'a.svg', { type: 'image/svg+xml' }), new File(['x'], 'f.ico', { type: 'image/x-icon' }), new File(['%PDF'], 'a.pdf', { type: 'application/pdf' })] });
ok('svg, ico y pdf no son fotos: 3 otros', r.fotos.length === 0 && r.otros === 3);
r = P.imagenesDePegado({ files: [new File([new Uint8Array([9])], 'IMG_1.JPG', { type: '' })] });
ok('sin tipo pero .JPG: se acepta', r.fotos.length === 1);
r = P.imagenesDePegado({ files: [png, png2] });
ok('dos fotos: en el mismo orden', r.fotos[0] === png && r.fotos[1] === png2);
ok('HEIC se acepta', P.esFotoPegable({ type: 'image/heic', name: 'a.heic' }) && P.esFotoPegable({ type: '', name: 'IMG.HEIC' }));
r = P.imagenesDePegado({ files: [], items: [{ kind: 'file', getAsFile: () => null }, item(png)] });
ok('un getAsFile() nulo se salta', r.fotos.length === 1 && r.otros === 0);

// ---------- esCampoDeTexto ----------
const el = (tagName, extra) => ({ tagName, type: '', id: '', isContentEditable: false, closest: () => null, ...(extra || {}) });
ok('input de texto, search, email, number, password: SÍ son campos', ['text', 'search', 'email', 'number', 'password'].every(t => P.esCampoDeTexto(el('INPUT', { type: t }))));
ok('textarea y contenteditable: SÍ', P.esCampoDeTexto(el('TEXTAREA')) && P.esCampoDeTexto(el('DIV', { isContentEditable: true })));
ok('select, button, checkbox, radio, range, file: NO (escoger el cuarto no apaga ⌘V)', !P.esCampoDeTexto(el('SELECT')) && ['button', 'checkbox', 'radio', 'range', 'file'].every(t => !P.esCampoDeTexto(el('INPUT', { type: t }))));
ok('el recuadro propio y el atrapa: NO', !P.esCampoDeTexto(el('DIV', { id: 'pegarZona', isContentEditable: true })) && !P.esCampoDeTexto(el('DIV', { id: 'pegarAtrapa', isContentEditable: true })) && !P.esCampoDeTexto(null));

// ---------- ruta ----------
const base = { hoja: false, enTexto: false, encima: false, pantalla: 'pTrabajo', tab: 'fotos', trabajoId: 't1', abiertoId: 't1', archivado: false };
ok('en Photos del proyecto abierto: abre la hoja', P.ruta(base) === 'fotos');
ok('otra pestaña (Dry Logs, Measurements, Floor Plan): nada', ['secado', 'medidas', 'plano'].every(t => P.ruta({ ...base, tab: t }) === ''));
ok('otra pantalla (la foto, Home): nada', P.ruta({ ...base, pantalla: 'pFoto' }) === '' && P.ruta({ ...base, pantalla: 'pInicio' }) === '');
ok('archivado, sin proyecto, ids distintos: nada', P.ruta({ ...base, archivado: true }) === '' && P.ruta({ ...base, trabajoId: undefined }) === '' && P.ruta({ ...base, abiertoId: 't2' }) === '');
ok('algo encima o escribiendo: nada', P.ruta({ ...base, encima: true }) === '' && P.ruta({ ...base, enTexto: true }) === '');
ok('con la hoja abierta: a la hoja (aunque haya un campo con foco)', P.ruta({ ...base, hoja: true, enTexto: true }) === 'hoja');

// ---------- textos ----------
ok('textoSubir: 0, 1 y 3', P.textoSubir(0) === 'Upload Photos' && P.textoSubir(1) === 'Upload 1 Photo' && P.textoSubir(3) === 'Upload 3 Photos');
ok('textosZona: teléfono vacío y lleno', JSON.stringify(P.textosZona({ tactil: true, mac: true, llena: false })) === JSON.stringify({ b: 'Touch and hold here, then tap Paste', small: 'Copy photos first in Photos, Messages, WhatsApp or Mail.' })
  && P.textosZona({ tactil: true, mac: false, llena: true }).b === 'Touch and hold here to paste more' && P.textosZona({ tactil: true, llena: true }).small === '');
ok('textosZona: computadora Mac y Windows', P.textosZona({ tactil: false, mac: true, llena: false }).b === 'Press ⌘V to paste' && P.textosZona({ tactil: false, mac: false, llena: false }).b === 'Press Ctrl+V to paste'
  && P.textosZona({ tactil: false, mac: false, llena: false }).small === 'Or right-click here and choose Paste.' && P.textosZona({ tactil: false, mac: true, llena: true }).b === 'Press ⌘V to paste more');
ok('destinoTexto', P.destinoTexto('Lauren Harris', 'First Floor › Kitchen') === 'Lauren Harris › First Floor › Kitchen' && P.destinoTexto('', 'No room') === 'Project › No room');
ok('atajoPegar: ⌘V en Mac/iPhone/iPad, Ctrl+V en Windows', F.atajoPegar('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)') === '⌘V' && F.atajoPegar('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0)') === '⌘V'
  && F.atajoPegar('Mozilla/5.0 (iPad; CPU OS 18_0)') === '⌘V' && F.atajoPegar('Mozilla/5.0 (Windows NT 10.0; Win64; x64)') === 'Ctrl+V');

// ---------- la hoja, con un document de mentira (después de importar: app.js no corre sin window) ----------
const clases = new Set();
globalThis.document = { querySelector: () => null, querySelectorAll: () => [], getElementById: () => null, activeElement: null, contains: () => false,
  body: { classList: { add: (c) => clases.add(c), remove: (c) => clases.delete(c), contains: (c) => clases.has(c), toggle: () => {} } } };
let PROY = { id: 't1', estado: 'activo', cliente: 'Lauren Harris' }, DEST = { nivel_id: 'n1', cuarto_id: 'c1' };
await F.cargar({ id: 't1', estado: 'activo' });
P.usar({ proyecto: () => PROY, tab: () => 'fotos', destino: () => DEST, nombre: () => 'First Floor › Kitchen' });
ok('abrir: sí en el proyecto de Photos', P.abrir() === true && clases.has('con-pegar'));
await P.agregar([png]); await P.agregar([png]);
ok('la misma foto dos veces: una sola en la hoja', P._estado().ITEMS.length === 1);
DEST = { nivel_id: 'n2', cuarto_id: 'c2' };                        // cambian el filtro con la hoja abierta
const antes = F._estado().TANDA.length;
ok('subir: sin error', P.subir() === '');
const nuevos = F._estado().TANDA.slice(antes);
ok('subir: entra UNA a la tanda, del proyecto t1 y al cuarto que se enseñó AL ABRIR', nuevos.length === 1 && nuevos[0].trabajoId === 't1' && nuevos[0].destino.cuarto_id === 'c1' && nuevos[0].destino.nivel_id === 'n1');
ok('subir: la hoja se cierra', !clases.has('con-pegar') && P._estado().ITEMS.length === 0 && P._estado().SNAP === null);
P.abrir(); await P.agregar([png2]);
PROY = { ...PROY, estado: 'archivado' };
const antes2 = F._estado().TANDA.length;
ok('archivado con la hoja abierta: no sube y lo dice', P.subir() === P.T_ARCH && F._estado().TANDA.length === antes2 && P._estado().ITEMS.length === 1);
PROY = { id: 't2', estado: 'activo' };
ok('otro proyecto abierto: no sube y lo dice', P.subir() === P.T_OTRO && F._estado().TANDA.length === antes2);
P.cerrar();
ok('abrir: no en un proyecto archivado ni con ids distintos', (PROY = { id: 't1', estado: 'archivado' }, P.abrir() === false) && (PROY = { id: 't9', estado: 'activo' }, P.abrir() === false));
ok('una foto que no se lee no se reintenta para siempre (no es "sin señal")', F.esErrorDeRed(new Error('could not read the photo')) === false);

// ---------- reglas de fuente ----------
const pg = leer('pegar.js'), pr = leer('proyecto.js'), ix = leer('index.html'), ap = leer('app.js'), fo = leer('fotos.js');
ok('pegar.js: sin navigator.clipboard, sin isTrusted, sin stopPropagation', !/navigator\.clipboard/.test(pg) && !/isTrusted/.test(pg) && !/stopPropagation/.test(pg));
const alPegar = pg.slice(pg.indexOf('function alPegar'), pg.indexOf('let CONECTADO'));
ok('el portapapeles se lee antes de cualquier await', alPegar.includes('imagenesDePegado(dt)') && !/await/.test(alPegar.slice(0, alPegar.indexOf('imagenesDePegado(dt)'))));
ok('escucha paste, beforepaste y keydown, y sube por fotos.encolar con el cuarto de la hoja', /addEventListener\('paste'/.test(pg) && /addEventListener\('beforepaste'/.test(pg) && /addEventListener\('keydown'/.test(pg) && pg.includes('fotos.encolar(listos, { ...SNAP.destino })'));
ok('proyecto.js: Paste Photos va justo después de From Library en el mismo menú, y abre la hoja',
  pr.includes("From Library</button><button type=\"button\" data-p-accion=\"foto-pegar\">${IC('pegar')}<span>Paste Photos<small class=\"menu-sub\">Copied from another app</small></span></button>`") && pr.includes("a === 'foto-pegar') pegar.abrir()"));
ok('index.html: la hoja, el recuadro (contenteditable, sin teclado), el atrapa y el ícono', ix.includes('id="hojaPegar"') && /id="pegarZona" contenteditable="true" inputmode="none"/.test(ix) && ix.includes('id="pegarAtrapa"') && ix.includes('<symbol id="i-pegar"'));
ok('app.js: con la hoja abierta la app no se recarga sola', /ocupado\(\)\{[\s\S]{0,200}con-pegar/.test(ap));
ok('fotos.js: Upload Photos de la computadora sigue igual y con su pista del atajo', fo.includes('Upload Photos<input type="file" accept="image/*" multiple hidden data-subir></label>') && fo.includes('title="Or press \' + atajoPegar(navigator.userAgent) + \' to paste copied photos"'));
ok('fotos.js: el botón del teléfono no cambió', fo.includes(`if(tactil) return '<button type="button" class="btn btn-accent btn-chico subir-btn" data-subir-menu><svg class="ic"><use href="#i-camara"/></svg>Upload Photos</button><input type="file" accept="image/*" multiple hidden data-subir>';`));
ok('fotos.js: fondo blanco antes de dibujar, tope de 16 MP para el original que no es JPEG, la huella va a firmar_subida y la repetida no sube',
  /g\.fillStyle = '#fff'; g\.fillRect\(0, 0, w, h\);\s*g\.drawImage/.test(fo) && fo.includes('achicar(img, 1e9, 0.92, MAX_AREA_ORIGINAL)') && fo.includes("llamar('firmar_subida', { trabajo_id: trabajoId, foto_id, bytes, sha256 })") && fo.includes('if(firma.repetida && firma.foto) return { foto: firma.foto, repetida: true };'));
const fn = fs.readFileSync(new URL('../supabase/functions/fotos-subir/index.ts', import.meta.url), 'utf8');
const fsub = fn.slice(fn.indexOf('async function firmarSubida'), fn.indexOf('async function confirmar'));
ok('servidor: firmar_subida busca la misma huella después de revisar si está archivado y antes de firmar', fsub.indexOf('fotoPorHuella') > fsub.indexOf('archivado') && fsub.indexOf('fotoPorHuella') < fsub.indexOf('firmar("PUT"'));
ok('servidor: el 409 de confirmar busca por la huella y borra lo que sobró en R2 solo si es otra foto', /fotoPorHuella\(trabajo_id, u\.company_id, sha256\)/.test(fn) && /if \(otra\.id !== foto_id\) await borrarVariantes/.test(fn));
ok('servidor: la búsqueda por huella filtra trabajo, empresa y huella', /trabajo_id=eq\." \+ trabajo_id \+ "&company_id=eq\." \+ company_id \+ "&sha256=eq\." \+ sha256/.test(fn));

console.log('\n  ' + pass + ' pasan, ' + fail + ' fallan');
process.exit(fail ? 1 : 0);
