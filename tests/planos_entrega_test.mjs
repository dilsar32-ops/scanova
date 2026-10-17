// Scanova360 · el escaneo que la página nunca recibió (17-oct, su escaneo 2: con el escáner abierto iOS mató el motor web,
// la página se recargó y el plano se perdió sin aviso; el botón 3D enseñaba ese escaneo como si estuviera guardado).
// Ahora el escáner deja cada escaneo en el teléfono ANTES de responder (RoomPlanPlugin.swift, PlanosSinEntregar) y la página:
//  - lo recoge al abrir Floor Plan y lo guarda como cualquier escaneo, sin repetirlo;
//  - suelta la copia del teléfono SOLO cuando el plano ya está a salvo (su lista del teléfono o el servidor);
//  - el 3D solo con plano en el nivel, y del escaneo de ESE plano;
//  - "cancelado" sin error se dice; la app no se recarga sola con el escáner o la cámara de medir abiertos.
import fs from 'node:fs';
const mem = {}; let llenoElTelefono = false;
globalThis.localStorage = { getItem: k => (k in mem ? mem[k] : null), setItem: (k, v) => { if(llenoElTelefono) throw new Error('QuotaExceededError'); mem[k] = String(v); }, removeItem: k => { delete mem[k]; } };
// ---------- el servidor ----------
let red = true, posts = 0, seq = 0, colgar = false; const servidor = {}, colgadas = [], cuerpos = [];
// relojServidor: null = la respuesta no trae Date; un número = la hora del servidor menos la del teléfono (ms).
let relojServidor = null;
const resp = (status, body) => ({ ok: status >= 200 && status < 300, status, json: async () => body,
  headers: { get: k => (relojServidor != null && String(k).toLowerCase() === 'date' ? new Date(Date.now() + relojServidor).toUTCString() : null) } });
globalThis.fetch = async (url, opts = {}) => {
  if(!red) throw new TypeError('Load failed');
  // Señal débil: la subida se queda colgada hasta que la prueba la suelta.
  if(colgar && opts.method === 'POST') return new Promise(ok => colgadas.push(() => ok(globalThis.fetch(url, opts))));
  if(opts.method === 'POST' && /\/rest\/v1\/fotos_planos$/.test(url)){
    posts++;
    const f = JSON.parse(opts.body); cuerpos.push(f);
    if(servidor[f.id]) return resp(409, {});
    servidor[f.id] = { ...f, created_at: f.created_at || new Date(Date.UTC(2026, 9, 17, 20, 0, seq++)).toISOString() };   // como Postgres: la hora que manda la página, o now()
    return resp(201, [servidor[f.id]]);
  }
  let m = /fotos_planos\?id=eq\.([0-9a-f-]+)/.exec(url);
  if(m) return resp(200, servidor[m[1]] ? [servidor[m[1]]] : []);
  m = /fotos_planos\?trabajo_id=eq\.([0-9a-f-]+)/.exec(url);
  if(m) return resp(200, Object.values(servidor).filter(f => f.trabajo_id === m[1] && !f.borrado_at).sort((a, b) => b.created_at.localeCompare(a.created_at)));
  return resp(200, []);
};
const PL = await import('../docs/planos.js');
const { ocupado } = await import('../docs/app.js');
// ---------- la pantalla (solo lo que planos.js toca) ----------
const clases = new Set();
const body = { classList: { add: c => clases.add(c), remove: c => clases.delete(c), contains: c => clases.has(c), toggle: (c, on) => { if(on === undefined) on = !clases.has(c); on ? clases.add(c) : clases.delete(c); return on; } } };
const caja = { innerHTML: '', classList: { toggle(){} }, lastElementChild: null };
let alClic = null;
const inicio = { innerHTML: '', hidden: true };
globalThis.document = { body, querySelector: s => (s === '#panel-plano' ? caja : null), querySelectorAll: () => [], getElementById: id => (id === 'inicioPlanos' ? inicio : null), activeElement: null,
  addEventListener: (t, f) => { if(t === 'click') alClic = f; } };
// ---------- el aparato (RoomPlanPlugin) ----------
const archivos = {};   // trabajo -> { entrega -> escaneo } (planos-sin-entregar/<trabajo>/<entrega>.json)
const sueltos = [], vistas = [], pedidos = [];
let alEscanear = null, soltarRoto = false;
const RS = {
  isSupported: async () => ({ value: true }),
  scan: async (o) => { pedidos.push({ ...o, escaner: clases.has('con-escaner') }); return alEscanear(o); },
  pendientes: async ({ trabajo } = {}) => (trabajo ? { escaneos: Object.values(archivos[trabajo] || {}).map(x => JSON.parse(JSON.stringify(x))) }
    : { escaneos: [], trabajos: Object.entries(archivos).filter(([, v]) => Object.keys(v).length).map(([t, v]) => ({ trabajo: t, n: Object.keys(v).length, desde: '2026-10-17T19:49:00Z' })) }),
  soltar: async ({ trabajo, ids }) => {
    // En el momento de soltar, cada escaneo tiene que estar YA a salvo: en la lista del teléfono o en el servidor.
    ids.forEach(id => sueltos.push({ id, aSalvo: PL.leerPendientes().some(x => x.fila && x.fila.id === id) || !!servidor[id] }));
    if(soltarRoto) return;
    ids.forEach(id => { if(archivos[trabajo]) delete archivos[trabajo][id]; });
  },
  viewModel: async (o) => { vistas.push(o || {}); return {}; },
  addListener: async (ev, cb) => { oyentes[ev] = cb; return { remove(){} }; },
};
const oyentes = {};
globalThis.window = { Capacitor: { Plugins: { RoomScan: RS } }, addEventListener(){} };
PL.conectar();
let pass = 0, fail = 0;
const ok = (l, c, x) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l + (x !== undefined ? '  ' + JSON.stringify(x) : '')); } };
const esperar = async (cond, ms = 3000) => { const t0 = Date.now(); while(!cond() && Date.now() - t0 < ms) await new Promise(r => setTimeout(r, 5)); return cond(); };
const tranquilo = () => new Promise(r => setTimeout(r, 40));
const clic = (sel, datos = {}) => alClic({ target: { closest: s => (s === '#panel-plano' ? caja : s === sel ? { dataset: datos, disabled: false, textContent: '' } : null) } });
const raw = JSON.parse(fs.readFileSync(new URL('./fixtures/plano_real.json', import.meta.url), 'utf8'));
const escaneo = (extra) => Object.assign(JSON.parse(JSON.stringify(raw.data || raw)), { nivelBase: 'Main Level' }, extra || {});
const N1 = { id: 'aaaaaaaa-1111-4111-8111-000000000001', nombre: 'Main Level' };
const T1 = { id: '11111111-1111-4111-8111-111111111111', cliente: 'Test Client', direccion: '1 Test St' };
const T2 = { id: '22222222-2222-4222-8222-222222222222', cliente: 'Test Client 2', direccion: '' };
const T3 = { id: '33333333-3333-4333-8333-333333333333', cliente: 'Test Client 3', direccion: '' };
const delTrabajo = (t) => Object.values(servidor).filter(f => f.trabajo_id === t.id);
const abrir = async (t) => { PL.abrir(t, [N1], null, []); await tranquilo(); await esperar(() => !/Loading plans/.test(caja.innerHTML)); await tranquilo(); };
const salirYVolver = async (t) => { PL.abrir({ id: '99999999-9999-4999-8999-999999999999' }, [], null, []); await tranquilo(); await abrir(t); };

// ---------- ids que salen de la entrega ----------
{ const e = '0f8fad5b-d9cb-469f-a165-70867728950e', e1 = PL.idDeParte(e, 1);
  ok('la primera fila lleva la entrega misma como id', PL.idDeParte(e, 0) === e && PL.idDeParte(e.toUpperCase(), 0) === e);
  ok('las demás partes (otro nivel) salen de la entrega: siempre el mismo id, con forma de uuid y distinto', e1 === PL.idDeParte(e, 1) && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(e1) && e1 !== e && PL.idDeParte(e, 2) !== e1);
  ok('sin entrega de verdad: un id nuevo (como antes)', /^[0-9a-f-]{36}$/.test(PL.idDeParte('', 0)) && PL.idDeParte('', 0) !== PL.idDeParte('', 0)); }

// ---------- 1. escaneo normal: llega la respuesta ----------
await abrir(T1);
ok('sin plano en el nivel, el botón 3D sale apagado', /data-pl-vista="3d" disabled/.test(caja.innerHTML));
await clic('[data-pl-vista]', { plVista: '3d' }); await tranquilo();
ok('y tocarlo no abre ningún 3D (antes enseñaba el último escaneo del teléfono aunque no se guardó)', vistas.length === 0);
alEscanear = (o) => { const d = escaneo({ _entrega: o.entrega, _escaneado: '2026-10-17T19:49:30Z' }); (archivos[o.trabajo] = archivos[o.trabajo] || {})[o.entrega] = d; return d; };
await clic('[data-pl-escanear]');
await esperar(() => delTrabajo(T1).length === 1 && sueltos.length === 1); await tranquilo();
const p1 = pedidos[0];
ok('la página manda su trabajo y una entrega nueva al escáner', p1 && p1.trabajo === T1.id && /^[0-9a-f-]{36}$/.test(p1.entrega || ''));
ok('con el escáner abierto el cuerpo dice con-escaner, y al cerrar se quita', p1 && p1.escaner === true && !clases.has('con-escaner'));
ok('el plano se guarda UNA vez con la entrega como id', delTrabajo(T1).length === 1 && delTrabajo(T1)[0].id === p1.entrega && delTrabajo(T1)[0].data._entrega === p1.entrega);
ok('la copia del teléfono se suelta una vez, ya a salvo', sueltos.length === 1 && sueltos[0].id === p1.entrega && sueltos[0].aSalvo && !Object.keys(archivos[T1.id]).length);
ok('la fecha del plano es la del escaneo', delTrabajo(T1)[0].data.job && delTrabajo(T1)[0].data.job.date === '2026-10-17');
ok('recién escaneado y subido al instante: no manda hora (la pone el servidor; el reloj del teléfono no decide)', cuerpos.filter(c => c.id === p1.entrega).length >= 1 && cuerpos.filter(c => c.id === p1.entrega).every(c => !('created_at' in c)));
ok('dice que se guardó, sin "Recovered"', /Floor plan saved for Main Level/.test(caja.innerHTML) && !/Recovered/.test(caja.innerHTML));
ok('con plano en el nivel el 3D se prende', /data-pl-vista="3d">3D/.test(caja.innerHTML));
await clic('[data-pl-vista]', { plVista: '3d' }); await tranquilo();
ok('el 3D pide el escaneo de ESE plano', vistas.length === 1 && vistas[0].entrega === p1.entrega);

// ---------- 2. la página se recargó a medio escaneo: la respuesta nunca llegó ----------
const perdida = '5e1c2b9a-7d3f-4a8e-9b6c-0123456789ab';
(archivos[T2.id] = {})[perdida] = escaneo({ _entrega: perdida, _escaneado: '2026-10-17T19:50:11Z' });
posts = 0;
await abrir(T2);
await esperar(() => delTrabajo(T2).length === 1 && sueltos.some(s => s.id === perdida)); await tranquilo();
ok('al abrir Floor Plan se recoge y se guarda el escaneo que no llegó', delTrabajo(T2).length === 1 && delTrabajo(T2)[0].id === perdida && posts === 1);
ok('se dice que se recuperó', /Recovered a floor plan scan that was not saved\. Floor plan saved for Main Level/.test(caja.innerHTML));
ok('la copia del teléfono se suelta solo ya a salvo', sueltos.filter(s => s.id === perdida).every(s => s.aSalvo) && !archivos[T2.id][perdida]);
ok('y su 3D se puede ver (es el mismo escaneo)', /data-pl-vista="3d">3D/.test(caja.innerHTML));

// ---------- 3. llega dos veces: nunca se repite ----------
soltarRoto = true;   // la copia no se pudo borrar: vuelve a salir en pendientes
(archivos[T2.id])[perdida] = escaneo({ _entrega: perdida });
posts = 0;
await salirYVolver(T2); await tranquilo();
ok('ya está en Floor Plan: no se vuelve a mandar, solo se suelta', posts === 0 && delTrabajo(T2).length === 1 && sueltos.filter(s => s.id === perdida).length >= 2);
// El plano ya está en el servidor pero la lista no se pudo leer y el teléfono no lo tiene apuntado: el 409 lo resuelve.
soltarRoto = false;
(archivos[T2.id])[perdida] = escaneo({ _entrega: perdida });
const listar = globalThis.fetch; let sinLista = true;
globalThis.fetch = async (url, opts) => (sinLista && /trabajo_id=eq\./.test(url) && !(opts && opts.method) ? resp(500, {}) : listar(url, opts));
posts = 0;
await salirYVolver(T2);
await esperar(() => !archivos[T2.id][perdida]); await tranquilo();
ok('sin la lista del servidor: se manda, el servidor dice 409 y no hay dos', posts === 1 && delTrabajo(T2).length === 1 && PL.leerPendientes().length === 0);
sinLista = false; globalThis.fetch = listar;

// ---------- 4. soltar SOLO cuando ya está a salvo ----------
const dura = '7a7a7a7a-1b1b-4c2c-8d3d-e4e4e4e4e4e4';
(archivos[T3.id] = {})[dura] = escaneo({ _entrega: dura });
llenoElTelefono = true; red = false; const antes = sueltos.length;
await abrir(T3); await tranquilo(); await tranquilo();
ok('sin lugar en el teléfono y sin señal: la copia del escáner NO se suelta', sueltos.length === antes && !!archivos[T3.id][dura] && delTrabajo(T3).length === 0);
// (subirFila lo intenta 3 veces: 0, 2 y 6 segundos)
ok('y se dice que sigue en el teléfono', await esperar(() => /could not be uploaded[\s\S]*It stays on this phone/.test(caja.innerHTML), 12000));
llenoElTelefono = false; red = true;
await salirYVolver(T3);
await esperar(() => !archivos[T3.id][dura]); await tranquilo();
ok('con señal otra vez se guarda, y se suelta solo después de que el servidor lo confirmó', delTrabajo(T3).length === 1 && sueltos.slice(antes).length === 1 && sueltos[antes].aSalvo && !!servidor[dura]);
// Sin señal pero con lugar en el teléfono: pasa a la lista del teléfono (se sube sola) y la copia se suelta.
const sotano = '8b8b8b8b-2c2c-4d3d-9e4e-f5f5f5f5f5f5';
archivos[T3.id][sotano] = escaneo({ _entrega: sotano });
red = false;
await salirYVolver(T3);
await esperar(() => !archivos[T3.id][sotano]); await tranquilo();
ok('sin señal: queda en la lista del teléfono y recién entonces se suelta la copia', PL.leerPendientes().some(x => x.fila.id === sotano) && sueltos[sueltos.length - 1].id === sotano && sueltos[sueltos.length - 1].aSalvo);
red = true; await PL.subirPendientes(); await tranquilo();
ok('al volver la señal se sube una vez', !!servidor[sotano] && PL.leerPendientes().length === 0 && delTrabajo(T3).length === 2);

// ---------- 5. un escaneo con dos niveles: dos filas, y recogido otra vez no se repite ----------
{ const dos = '9c9c9c9c-3d3d-4e4e-8f5f-a6a6a6a6a6a6', d = escaneo({ _entrega: dos });
  d.rooms.forEach((r, i) => { if(i >= 3) r.level = 2; }); d.inspection = Object.assign({}, d.inspection, { nombresDeNivel: { '2': 'Upper Level' } });
  const T4 = { id: '44444444-4444-4444-8444-444444444444', cliente: 'Test 4', direccion: '' };
  (archivos[T4.id] = {})[dos] = d;
  await abrir(T4); await esperar(() => !archivos[T4.id][dos]); await tranquilo();
  const ids = delTrabajo(T4).map(f => f.id).sort();
  ok('dos niveles = dos filas con los ids de la entrega', ids.length === 2 && ids.includes(dos) && ids.includes(PL.idDeParte(dos, 1)));
  archivos[T4.id][dos] = JSON.parse(JSON.stringify(d)); posts = 0;
  await salirYVolver(T4); await tranquilo();
  ok('recogido otra vez: nada nuevo', posts === 0 && delTrabajo(T4).length === 2 && !archivos[T4.id][dos]); }

// ---------- 6. cancelado sin error ----------
await abrir(T1);
alEscanear = () => ({ cancelled: true });
await clic('[data-pl-escanear]'); await esperar(() => /Scan cancelled/.test(caja.innerHTML));
ok('cancelado sin error: se dice que no se guardó nada', /Scan cancelled\. No floor plan was saved\./.test(caja.innerHTML) && !clases.has('con-escaner'));
alEscanear = () => ({ cancelled: true, error: 'Este teléfono no tiene LiDAR' });
await clic('[data-pl-escanear]'); await esperar(() => /Este teléfono no tiene LiDAR/.test(caja.innerHTML));
ok('cancelado con error: el error, como antes', /Este teléfono no tiene LiDAR/.test(caja.innerHTML));

// ---------- 6b. la hora del escaneo (revisión 17-oct): uno recogido después NO tapa al plano más nuevo de su nivel ----------
{ ok('horaDelEscaneo: la del escaneo; del futuro queda en ahora; sin hora o rota: null', PL.horaDelEscaneo('2026-10-17T14:00:00Z') === '2026-10-17T14:00:00.000Z'
    && PL.horaDelEscaneo('2030-01-01T00:00:00Z', Date.UTC(2026, 9, 17)) === new Date(Date.UTC(2026, 9, 17)).toISOString() && PL.horaDelEscaneo('') === null && PL.horaDelEscaneo('ayer') === null);
  ok('ordenarPlanos: del más nuevo al más viejo, también con los microsegundos de Postgres', PL.ordenarPlanos([{ id: 'a', created_at: '2026-10-17T14:00:00.123456+00:00' }, { id: 'b', created_at: '2026-10-17T14:20:00Z' }, { id: 'c' }, { id: 'd', created_at: '2026-10-16T09:00:00.5+00:00' }]).map(x => x.id).join() === 'b,a,d,c'); }
{ const T6 = { id: '66666666-6666-4666-8666-666666666666', cliente: 'Test 6', direccion: '' };
  const nuevo = 'a1a1a1a1-0000-4000-8000-000000000006', viejo = 'b2b2b2b2-0000-4000-8000-000000000006';
  // 10:20: el teléfono Y guardó Main Level. 10:00: el teléfono X lo había escaneado y la respuesta se perdió.
  servidor[nuevo] = { id: nuevo, trabajo_id: T6.id, nivel_id: N1.id, created_at: '2026-10-17T14:20:00.000Z', data: escaneo({ _entrega: nuevo }), cuartos: 5 };
  (archivos[T6.id] = {})[viejo] = escaneo({ _entrega: viejo, _escaneado: '2026-10-17T14:00:00Z' });
  await abrir(T6); await esperar(() => !!servidor[viejo]); await tranquilo();
  ok('el recogido se guarda con la hora en que se escaneó', servidor[viejo] && servidor[viejo].created_at === '2026-10-17T14:00:00.000Z');
  const orden = Object.values(servidor).filter(f => f.trabajo_id === T6.id).sort((a, b) => b.created_at.localeCompare(a.created_at)).map(f => f.id);
  ok('en el servidor el plano de Main Level sigue siendo el más nuevo (el recogido queda de historial)', orden[0] === nuevo && orden[1] === viejo);
  ok('y en pantalla también (no se pone arriba por ser el último que se subió)', /Recovered an earlier scan of Main Level that was not saved\. It is kept as history; the newer plan of Main Level stays\./.test(caja.innerHTML));
  await clic('[data-pl-vista]', { plVista: '3d' }); await tranquilo();
  ok('el 3D pide el escaneo del plano que se ve (el más nuevo)', vistas[vistas.length - 1].entrega === nuevo);
  const sinHora = await PL.nivelesDelPlanoDe(T6.id);
  ok('Photos go to… / Measurements siguen el plano más nuevo del nivel', sinHora.length === 1); }

// ---------- 6c. el nivel que estaba en pantalla al empezar (revisión 17-oct) ----------
{ const N2 = { id: 'aaaaaaaa-1111-4111-8111-000000000002', nombre: 'Basement' };
  const T7 = { id: '77777777-7777-4777-8777-777777777777', cliente: 'Test 7', direccion: '' };
  const e7 = 'c3c3c3c3-0000-4000-8000-000000000007', e8 = 'd4d4d4d4-0000-4000-8000-000000000007';
  // En la bandeja se escribió un nivel que no es del proyecto ("Garage"); en la web estaba Basement.
  (archivos[T7.id] = {})[e7] = escaneo({ _entrega: e7, nivelBase: 'Garage', _nivelPedido: N2.id });
  // Recién abierto el proyecto todavía sin sus niveles: se espera.
  posts = 0; PL.abrir(T7, [], null, [], false); await tranquilo(); await esperar(() => !/Loading plans/.test(caja.innerHTML)); await tranquilo();
  ok('sin los niveles del proyecto todavía, el escaneo recogido espera (no cae en "No level")', posts === 0 && !!archivos[T7.id][e7]);
  PL.abrir(T7, [N1, N2], null, [], true); await esperar(() => !!servidor[e7]); await tranquilo();
  ok('llegaron los niveles: se guarda en el nivel que estaba en pantalla al escanear', servidor[e7] && servidor[e7].nivel_id === N2.id);
  archivos[T7.id][e8] = escaneo({ _entrega: e8, nivelBase: 'Garage', _nivelPedido: 'aaaaaaaa-9999-4999-8999-000000000000' });
  await salirYVolver(T7); await esperar(() => !!servidor[e8]); await tranquilo();
  ok('si ese nivel ya no existe: "No level"', servidor[e8] && servidor[e8].nivel_id === null); }

// ---------- 6d. respuesta {} (un NaN rompía la respuesta) con la copia buena en el teléfono (revisión 17-oct) ----------
{ const T8 = { id: '88888888-8888-4888-8888-888888888888', cliente: 'Test 8', direccion: '' };
  await abrir(T8);
  const antesS = sueltos.length;
  alEscanear = (o) => { (archivos[o.trabajo] = archivos[o.trabajo] || {})[o.entrega] = escaneo({ _entrega: o.entrega, _escaneado: '2026-10-17T19:49:30Z', _nivelPedido: o.nivelId }); return {}; };
  await clic('[data-pl-escanear]'); await esperar(() => delTrabajo(T8).length === 1); await tranquilo();
  const p8 = pedidos[pedidos.length - 1];
  ok('la página manda el nivel en pantalla (nivelId)', p8.nivelId === N1.id);
  ok('respuesta {}: no se suelta la copia sin guardarla; se guarda UNA vez desde la copia', delTrabajo(T8).length === 1 && delTrabajo(T8)[0].id === p8.entrega && sueltos.slice(antesS).every(x => x.aSalvo) && !Object.keys(archivos[T8.id]).length);
  ok('y no dice "without any room"', !/without any room/.test(caja.innerHTML));
  alEscanear = (o) => { (archivos[o.trabajo] = archivos[o.trabajo] || {})[o.entrega] = { _entrega: o.entrega, rooms: [] }; return {}; };
  await clic('[data-pl-escanear]'); await esperar(() => /without any room/.test(caja.innerHTML));
  ok('respuesta {} y la copia sin cuartos: "without any room", nada guardado', /without any room/.test(caja.innerHTML) && delTrabajo(T8).length === 1); }

// ---------- 6e. recoger no detiene Scan New Plan (revisión 17-oct) ----------
{ const T9 = { id: '99999999-0000-4000-8000-000000000009', cliente: 'Test 9', direccion: '' };
  const e9 = 'e5e5e5e5-0000-4000-8000-000000000009';
  (archivos[T9.id] = {})[e9] = escaneo({ _entrega: e9, _escaneado: '2026-10-17T19:00:00Z' });
  colgar = true;
  await abrir(T9); await esperar(() => !archivos[T9.id][e9]);
  ok('señal débil: el escaneo recogido queda en la lista del teléfono y la copia se suelta, sin esperar la subida', PL.leerPendientes().some(x => x.fila.id === e9) && !archivos[T9.id][e9] && /Saving it/.test(caja.innerHTML));
  const n0 = pedidos.length, t0 = Date.now();
  alEscanear = () => ({ cancelled: true });
  await clic('[data-pl-escanear]'); await esperar(() => pedidos.length > n0, 2000);
  ok('Scan New Plan abre el escáner al instante (la subida sigue sola)', pedidos.length === n0 + 1 && Date.now() - t0 < 1000, Date.now() - t0);
  colgar = false; colgadas.splice(0).forEach(f => f());
  await esperar(() => !!servidor[e9] && !PL.leerPendientes().some(x => x.fila.id === e9)); await tranquilo();
  ok('al soltar la señal se sube una vez', !!servidor[e9] && delTrabajo(T9).length === 1); }
{ const T10 = { id: '10101010-0000-4000-8000-000000000010', cliente: 'Test 10', direccion: '' };
  const e10 = 'f6f6f6f6-0000-4000-8000-000000000010';
  (archivos[T10.id] = {})[e10] = escaneo({ _entrega: e10 });
  red = false;
  const n0 = pedidos.length, t0 = Date.now();
  await abrir(T10);
  alEscanear = () => ({ cancelled: true });
  await clic('[data-pl-escanear]'); await esperar(() => pedidos.length > n0, 3000);
  ok('sin señal: del toque al escáner, sin los 8 s de reintentos', pedidos.length === n0 + 1 && Date.now() - t0 < 1500, Date.now() - t0);
  red = true; await PL.subirPendientes(); await tranquilo(); }

// ---------- 6f. el 3D de un escaneo que solo está en el teléfono (sin señal) (revisión 17-oct) ----------
{ const T11 = { id: '11111111-0000-4000-8000-000000000011', cliente: 'Test 11', direccion: '' };
  await abrir(T11);
  red = false;
  alEscanear = (o) => { const d = escaneo({ _entrega: o.entrega, _escaneado: '2026-10-17T21:00:00Z' }); (archivos[o.trabajo] = archivos[o.trabajo] || {})[o.entrega] = d; return d; };
  await clic('[data-pl-escanear]'); await esperar(() => /No signal here/.test(caja.innerHTML), 12000);
  const p11 = pedidos[pedidos.length - 1];
  ok('sin señal, recién escaneado: el 3D se prende (dice que es el de este teléfono)', /data-pl-vista="3d" title="Last scan on this phone \(not uploaded yet\)">3D/.test(caja.innerHTML));
  await clic('[data-pl-vista]', { plVista: '3d' }); await tranquilo();
  ok('y pide ESE escaneo', vistas[vistas.length - 1].entrega === p11.entrega);
  red = true; await PL.subirPendientes(); await tranquilo();
  ok('al volver la señal sube con la hora en que se escaneó (no la de la subida)', servidor[p11.entrega] && servidor[p11.entrega].created_at === '2026-10-17T21:00:00.000Z'); }

// ---------- 6g. Home dice qué proyecto tiene un escaneo sin guardar (revisión 17-oct) ----------
{ const T12 = { id: '12121212-0000-4000-8000-000000000012', cliente: 'Casa <Prueba>', direccion: '' };
  const e12 = 'a7a7a7a7-0000-4000-8000-000000000012';
  (archivos[T12.id] = {})[e12] = escaneo({ _entrega: e12 });
  const l = await PL.trabajosConEscaneoSinGuardar();
  ok('el aparato dice qué proyectos tienen escaneos sin guardar', l.some(x => x.trabajo === T12.id && x.n === 1));
  await PL.pintarAvisoDeInicio([T12, T1]);
  ok('Home: el aviso nombra el proyecto (escapado) y abre ESE proyecto', !inicio.hidden && /A floor plan scan of Casa &lt;Prueba&gt; was not saved yet\./.test(inicio.innerHTML) && inicio.innerHTML.includes('data-abrir="' + T12.id + '"'));
  await PL.pintarAvisoDeInicio([T1]);
  ok('Home: un proyecto que no es de esta cuenta no sale', inicio.hidden && !inicio.innerHTML);
  delete archivos[T12.id][e12];
  await PL.pintarAvisoDeInicio([T12, T1]);
  ok('Home: ya guardado, el aviso se quita', inicio.hidden && !inicio.innerHTML);
  const pr = fs.readFileSync(new URL('../docs/proyecto.js', import.meta.url), 'utf8');
  ok('al abrir el proyecto (con sus niveles), si tiene un escaneo sin guardar va directo a Floor Plan', /cargarCuartos\(\)\.then\(async \(\) => \{[\s\S]{0,200}const l = await planos\.trabajosConEscaneoSinGuardar\(\);[\s\S]{0,200}irTab\('plano'\);/.test(pr));
  const pa = fs.readFileSync(new URL('../docs/panel.js', import.meta.url), 'utf8');
  ok('Home lo pinta cada vez que se pinta la lista', /planos\.pintarAvisoDeInicio\(trabajos\.datos\(\)\.LISTA\)/.test(pa) && fs.readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8').includes('id="inicioPlanos"')); }

// ---------- 6h. segunda revisión (17-oct) ----------
const N2b = { id: 'aaaaaaaa-1111-4111-8111-000000000002', nombre: 'Basement' };
// Un plano con hora del futuro (un teléfono adelantado, antes del trigger del servidor) no deja decir "saved" de uno que no se ve.
{ const T13 = { id: '13131313-0000-4000-8000-000000000013', cliente: 'Test 13', direccion: '' };
  const fut = 'b8b8b8b8-0000-4000-8000-000000000013';
  servidor[fut] = { id: fut, trabajo_id: T13.id, nivel_id: N1.id, created_at: '2030-01-01T00:00:00.000Z', data: escaneo({ _entrega: fut }), cuartos: 5 };
  await abrir(T13);
  alEscanear = (o) => { const d = escaneo({ _entrega: o.entrega, _escaneado: new Date().toISOString() }); (archivos[o.trabajo] = archivos[o.trabajo] || {})[o.entrega] = d; return d; };
  await clic('[data-pl-escanear]'); await esperar(() => delTrabajo(T13).length === 2); await tranquilo();
  ok('recién escaneado pero otro plano del nivel tiene hora más nueva: no dice "Floor plan saved for", dice que queda de historial', !/Floor plan saved for/.test(caja.innerHTML) && /The scan of Main Level is saved as history: the newer plan of Main Level stays\./.test(caja.innerHTML)); }
// Lo que la versión anterior dejó esperando señal (sin escaneado ni created_at): sube con la hora en que se apuntó.
{ const T14 = { id: '14141414-0000-4000-8000-000000000014', cliente: 'Test 14', direccion: '' };
  const hoy = 'c9c9c9c9-0000-4000-8000-000000000014', ayer = 'd0d0d0d0-0000-4000-8000-000000000014', nueva = 'e1e1e1e1-0000-4000-8000-000000000014';
  servidor[hoy] = { id: hoy, trabajo_id: T14.id, nivel_id: N1.id, created_at: '2026-10-17T14:00:00.000Z', data: escaneo({ _entrega: hoy }), cuartos: 5 };
  const LL = 'scanova:planosPendientes:v1', l = PL.leerPendientes();
  l.push({ fila: { id: ayer, trabajo_id: T14.id, nivel_id: N1.id, data: { rooms: [] }, area_sqft: 1, cuartos: 1 }, nivel: 'Main Level', guardado: '2026-10-16T17:25:00.000Z' });
  l.push({ fila: { id: nueva, trabajo_id: T14.id, nivel_id: null, data: { rooms: [] }, area_sqft: 1, cuartos: 1 }, nivel: 'No level', guardado: '2026-10-17T15:00:05.000Z', escaneado: '2026-10-17T15:00:00.000Z' });
  mem[LL] = JSON.stringify(l);
  await PL.subirPendientes(); await tranquilo();
  ok('fila vieja de la lista del teléfono: el POST lleva created_at = cuándo se apuntó (ayer)', cuerpos.filter(c => c.id === ayer).pop()?.created_at === '2026-10-16T17:25:00.000Z' && servidor[ayer].created_at === '2026-10-16T17:25:00.000Z');
  ok('fila nueva de la lista: el POST lleva la hora del escaneo', servidor[nueva] && servidor[nueva].created_at === '2026-10-17T15:00:00.000Z');
  const orden = PL.ordenarPlanos(Object.values(servidor).filter(f => f.trabajo_id === T14.id));
  ok('y el plano de hoy sigue siendo el de su nivel', PL.planoDe(orden, N1.id).id === hoy); }
// Scan New Plan antes de que lleguen los niveles: el escaneo recogido espera (no cae en "No level").
{ const T15 = { id: '15151515-0000-4000-8000-000000000015', cliente: 'Test 15', direccion: '' };
  const e15 = 'f2f2f2f2-0000-4000-8000-000000000015';
  (archivos[T15.id] = {})[e15] = escaneo({ _entrega: e15, nivelBase: 'Basement', _nivelPedido: N2b.id, _escaneado: '2026-10-17T16:00:00Z' });
  PL.abrir(T15, [], null, [], false); await tranquilo(); await esperar(() => !/Loading plans/.test(caja.innerHTML)); await tranquilo();
  posts = 0; alEscanear = () => ({ cancelled: true });
  await clic('[data-pl-escanear]'); await esperar(() => /Scan cancelled/.test(caja.innerHTML)); await tranquilo();
  ok('Scan New Plan sin los niveles: el escaneo recogido no se guarda todavía y la copia sigue en el teléfono', posts === 0 && !!archivos[T15.id][e15] && !PL.leerPendientes().some(x => x.fila.id === e15));
  alEscanear = (o) => { (archivos[o.trabajo] = archivos[o.trabajo] || {})[o.entrega] = escaneo({ _entrega: o.entrega, _escaneado: '2026-10-17T16:30:00Z' }); return {}; };
  await clic('[data-pl-escanear]'); await esperar(() => /safe on this phone/.test(caja.innerHTML)); await tranquilo();
  ok('respuesta {} sin los niveles: no dice "without any room", dice que está a salvo en el teléfono', !/without any room/.test(caja.innerHTML) && /The scan is safe on this phone\./.test(caja.innerHTML) && posts === 0);
  const nuevo15 = pedidos[pedidos.length - 1].entrega;
  PL.abrir(T15, [N1, N2b], null, [], true); await esperar(() => !!servidor[e15] && !!servidor[nuevo15]); await tranquilo();
  ok('llegaron los niveles: se guarda en el nivel que estaba en pantalla al escanear (Basement)', servidor[e15] && servidor[e15].nivel_id === N2b.id);
  ok('y con su hora de escaneo', servidor[e15] && servidor[e15].created_at === '2026-10-17T16:00:00.000Z'); }
// Dos partes del mismo escaneo, con el mismo nivel (proyecto sin niveles): nunca la misma hora; la última parte, la más nueva.
{ const T16 = { id: '16161616-0000-4000-8000-000000000016', cliente: 'Test 16', direccion: '' };
  const e16 = 'a3a3a3a3-0000-4000-8000-000000000016', d = escaneo({ _entrega: e16, nivelBase: '', _escaneado: '2026-10-17T18:00:00Z' });
  d.rooms.forEach((r, i) => { if(i >= 3) r.level = 2; }); d.inspection = Object.assign({}, d.inspection, { nombresDeNivel: { '2': 'Upper Level' } });
  (archivos[T16.id] = {})[e16] = d;
  PL.abrir(T16, [], null, [], true); await esperar(() => delTrabajo(T16).length === 2); await tranquilo();
  const a = servidor[e16], b = servidor[PL.idDeParte(e16, 1)];
  ok('dos partes sin nivel: horas distintas, la segunda 1 ms después', a && b && a.nivel_id === null && b.nivel_id === null && a.created_at === '2026-10-17T18:00:00.000Z' && b.created_at === '2026-10-17T18:00:00.001Z'); }
// La lista del teléfono llena y sin señal: la copia del escáner se queda, se dice, y se guarda al volver a entrar a Floor Plan.
{ const T17 = { id: '17171717-0000-4000-8000-000000000017', cliente: 'Test 17', direccion: '' };
  await abrir(T17);
  llenoElTelefono = true; red = false;
  alEscanear = (o) => { const d = escaneo({ _entrega: o.entrega, _escaneado: new Date().toISOString() }); (archivos[o.trabajo] = archivos[o.trabajo] || {})[o.entrega] = d; return d; };
  await clic('[data-pl-escanear]'); await esperar(() => /Could not save the floor plan/.test(caja.innerHTML), 12000);
  const e17 = pedidos[pedidos.length - 1].entrega;
  ok('lista llena y sin señal: dice que el escaneo sigue en este teléfono', /The scan stays on this phone and is saved by itself when there is signal\./.test(caja.innerHTML) && !!archivos[T17.id][e17]);
  red = true;
  PL.abrir(T17, [N1], null, [], true); PL.enfocar(); await esperar(() => !!servidor[e17] && !archivos[T17.id][e17], 12000); await tranquilo();
  ok('volver a entrar a Floor Plan del mismo proyecto (ya cargado) lo reintenta: guardado y la copia suelta', !!servidor[e17] && !archivos[T17.id][e17]);
  llenoElTelefono = false; }
// El aparato avisa que dejó un escaneo (la página se recargó con el escáner abierto): Floor Plan lo guarda y Home lo dice.
{ ok('la página oye el aviso del aparato (escaneoEnTelefono)', typeof oyentes.escaneoEnTelefono === 'function');
  const T18 = { id: '18181818-0000-4000-8000-000000000018', cliente: 'Test 18', direccion: '' };
  const T19 = { id: '19191919-0000-4000-8000-000000000019', cliente: 'Casa Diecinueve', direccion: '' };
  await abrir(T18);
  PL.usarListaDeInicio(() => [T18, T19]);
  await PL.pintarAvisoDeInicio([T18, T19]);
  ok('Home sin escaneos en el teléfono: sin aviso', inicio.hidden);
  const e18 = 'b4b4b4b4-0000-4000-8000-000000000018', e19 = 'c5c5c5c5-0000-4000-8000-000000000019';
  (archivos[T18.id] = {})[e18] = escaneo({ _entrega: e18, _escaneado: '2026-10-17T19:00:00Z' });
  (archivos[T19.id] = {})[e19] = escaneo({ _entrega: e19, _escaneado: '2026-10-17T19:05:00Z' });
  oyentes.escaneoEnTelefono({ trabajo: T19.id, entrega: e19 });
  await esperar(() => !!servidor[e18] && !inicio.hidden); await tranquilo();
  ok('con el aviso: el del proyecto abierto en Floor Plan se guarda', !!servidor[e18] && !archivos[T18.id][e18]);
  ok('y Home dice el del otro proyecto (antes no se volvía a mirar)', !inicio.hidden && /Casa Diecinueve/.test(inicio.innerHTML) && !/Test 18/.test(inicio.innerHTML));
  delete archivos[T19.id][e19]; }
{ const src = fs.readFileSync(new URL('../docs/planos.js', import.meta.url), 'utf8');
  ok('al volver la señal y al regresar a la app también se miran las copias del escáner', /addEventListener\('online', \(\) => \{ subirPendientes\(\)\.catch\(\(\) => \{\}\)\.then\(revisarTelefono\); \}\)/.test(src) && /visibilitychange[^\n]*setTimeout\(revisarTelefono, 1000\)/.test(src));
  ok('Home le pasa su lista de proyectos a Floor Plan', /planos\.usarListaDeInicio\(\(\) => trabajos\.datos\(\)\.LISTA\)/.test(fs.readFileSync(new URL('../docs/panel.js', import.meta.url), 'utf8'))); }
// La hora del servidor: un teléfono con la fecha un día adelantada no pone su escaneo delante (al final: deja medido el desfase).
{ const dia = 86400000, ahora = Date.UTC(2026, 9, 18, 15);
  ok('horaDelEscaneo con desfase: la hora del escaneo en la hora del servidor', PL.horaDelEscaneo('2026-10-18T14:00:00Z', ahora, -dia) === '2026-10-17T14:00:00.000Z');
  ok('horaDelEscaneo con desfase: nunca después de ahora del servidor', PL.horaDelEscaneo('2026-10-18T16:00:00Z', ahora, -dia) === '2026-10-17T15:00:00.000Z');
  const T20 = { id: '20202020-0000-4000-8000-000000000020', cliente: 'Test 20', direccion: '' };
  const e20 = 'd6d6d6d6-0000-4000-8000-000000000020', escaneado = new Date(Date.now() - 3600000).toISOString();   // hace 1 h en el reloj del teléfono
  relojServidor = -dia;   // el teléfono va un día adelantado
  (archivos[T20.id] = {})[e20] = escaneo({ _entrega: e20, _escaneado: escaneado });
  await abrir(T20); await esperar(() => !!servidor[e20]); await tranquilo();
  const dif = Date.parse(escaneado) - dia - Date.parse(servidor[e20].created_at);
  ok('recogido en un teléfono un día adelantado: se guarda con la hora del servidor (un día menos)', Math.abs(dif) < 3000, dif);
  relojServidor = null; }

// ---------- 7. aparato viejo (sin pendientes ni soltar): igual que antes ----------
delete RS.pendientes; delete RS.soltar;
const T5 = { id: '55555555-5555-4555-8555-555555555555', cliente: 'Test 5', direccion: '' };
await abrir(T5);
alEscanear = () => escaneo();   // no devuelve _entrega
await clic('[data-pl-escanear]');
await esperar(() => delTrabajo(T5).length === 1); await tranquilo();
const viejo = pedidos[pedidos.length - 1];
ok('aparato viejo: se guarda igual, con la entrega de la página como id', delTrabajo(T5).length === 1 && delTrabajo(T5)[0].id === viejo.entrega && /Floor plan saved/.test(caja.innerHTML));

// ---------- 8. la app no se recarga sola con el escáner o la cámara abiertos ----------
clases.clear();
ok('nada abierto: se puede recargar', ocupado() === false);
clases.add('con-escaner'); ok('escáner del plano abierto: ocupado', ocupado() === true); clases.clear();
clases.add('con-medir'); ok('cámara de medir abierta: ocupado', ocupado() === true); clases.clear();
const med = fs.readFileSync(new URL('../docs/medidas.js', import.meta.url), 'utf8');
{ const i = med.indexOf('async function lanzarCamara('), lc = med.slice(i, med.indexOf('\n}\n', i));
  ok('medidas: con-medir se pone antes de abrir la cámara y se quita en el finally', lc.indexOf("document.body.classList.add('con-medir')") > 0 && lc.indexOf("document.body.classList.add('con-medir')") < lc.indexOf('await ARMeasure.measure(') && /finally\{ CAMARA_ABIERTA = false; document\.body\.classList\.remove\('con-medir'\);/.test(lc)); }
const src = fs.readFileSync(new URL('../docs/planos.js', import.meta.url), 'utf8');
ok('planos: la copia se suelta después de escribir la lista del teléfono (o del servidor si no cupo)', (() => {
  const trozo = (f) => src.slice(src.indexOf(f), src.indexOf('\n}\n', src.indexOf(f)));
  const a = trozo('function apuntarEscaneo('), s = trozo('async function subirEscaneo(');
  return a.indexOf('const enTelefono = escribirPendientes(pend);') > 0 && a.indexOf('const enTelefono = escribirPendientes(pend);') < a.indexOf('if(enTelefono) soltarEscaneos(')
    && s.indexOf('guardadas.push(await subirFila(f, intentos))') > 0 && s.indexOf('guardadas.push(await subirFila(f, intentos))') < s.indexOf('if(!enTelefono) soltarEscaneos('); })());
console.log(`\nplanos entrega: ${pass} ok, ${fail} fallas`);
process.exit(fail ? 1 : 0);
