// Scanova360 · planos que esperan señal (16-oct, Aroldo en un sótano: "Could not save the floor plan. Load failed" y los
// dos escaneos se perdieron). Ahora el escaneo se guarda primero en el teléfono y se sube solo cuando hay señal.
const mem = {};
globalThis.localStorage = { getItem: k => (k in mem ? mem[k] : null), setItem: (k, v) => { mem[k] = String(v); }, removeItem: k => { delete mem[k]; } };
let modo = 'sin-senal', posts = 0, guardados = {};
globalThis.fetch = async (url, opts = {}) => {
  if(modo === 'sin-senal'){ const e = new TypeError('Load failed'); throw e; }
  if(opts.method === 'POST'){
    posts++;
    const fila = JSON.parse(opts.body);
    if(modo === 'prohibido') return { ok: false, status: 403, json: async () => ({}) };
    if(guardados[fila.id]) return { ok: false, status: 409, json: async () => ({}) };
    guardados[fila.id] = { ...fila, created_at: '2026-10-16T18:00:00Z' };
    if(modo === 'respuesta-perdida'){ modo = 'ok'; const e = new TypeError('Load failed'); throw e; }   // llegó, pero se cayó la respuesta
    return { ok: true, status: 201, json: async () => [guardados[fila.id]] };
  }
  const m = /id=eq\.([0-9a-f-]+)/.exec(url);
  if(m) return { ok: true, status: 200, json: async () => (guardados[m[1]] ? [guardados[m[1]]] : []) };
  return { ok: true, status: 200, json: async () => [] };
};
const PL = await import('../docs/planos.js');
globalThis.document = { querySelector: () => null, getElementById: () => null, addEventListener(){} };   // sin pantalla: solo la lógica
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const LL = 'scanova:planosPendientes:v1';
const fila = (id) => ({ fila: { id, trabajo_id: 't1', nivel_id: null, data: { rooms: [] }, area_sqft: 300, cuartos: 3 }, nivel: 'Basement', guardado: '2026-10-16T17:25:00Z' });

ok('el error de iPhone sin señal ("Load failed") cuenta como falta de señal', PL.esErrorDeRed(new TypeError('Load failed')) && PL.esErrorDeRed(new Error('HTTP 503')));
const e403 = new Error('HTTP 403'); e403.permanente = true;
ok('un "no tiene permiso" NO es falta de señal (no se reintenta solo)', !PL.esErrorDeRed(e403));

mem[LL] = JSON.stringify([fila('aaaaaaaa-0000-4000-8000-000000000001')]);
modo = 'sin-senal';
await PL.subirPendientes(true);
ok('sin señal el plano se queda en el teléfono (no se pierde)', PL.leerPendientes().length === 1 && !PL.leerPendientes()[0].error);

modo = 'ok'; posts = 0;
await PL.subirPendientes();
ok('con señal se sube solo y sale de la lista del teléfono', PL.leerPendientes().length === 0 && posts === 1 && guardados['aaaaaaaa-0000-4000-8000-000000000001']);

// La subida sí llegó al servidor pero la respuesta se perdió: el reintento NO lo duplica (mismo id -> 409 -> lo lee).
mem[LL] = JSON.stringify([fila('aaaaaaaa-0000-4000-8000-000000000002')]);
modo = 'respuesta-perdida'; posts = 0;
await PL.subirPendientes(true);
ok('si llegó y solo se perdió la respuesta, el reintento no lo guarda dos veces', PL.leerPendientes().length === 0 && Object.keys(guardados).filter(k => k.endsWith('0002')).length === 1 && posts === 2);

// Sin permiso (otra cuenta, otro trabajo): se queda en el teléfono CON su razón; no se borra nunca solo.
mem[LL] = JSON.stringify([fila('aaaaaaaa-0000-4000-8000-000000000003')]);
modo = 'prohibido';
await PL.subirPendientes(true);
const p3 = PL.leerPendientes();
ok('un error que no es de señal deja el plano guardado con su razón', p3.length === 1 && /403/.test(p3[0].error || ''));
modo = 'ok'; posts = 0;
await PL.subirPendientes();
ok('solo (sin tocar "Upload now") no reintenta el que falló por otra razón', posts === 0 && PL.leerPendientes().length === 1);
await PL.subirPendientes(true);
ok('"Upload now" sí lo reintenta, y al subir sale de la lista', PL.leerPendientes().length === 0);

const fs = await import('node:fs');
const src = fs.readFileSync(new URL('../docs/planos.js', import.meta.url), 'utf8');
ok('al escanear, el plano va PRIMERO al teléfono y después al servidor', src.indexOf('const enTelefono = escribirPendientes(pend);') < src.indexOf('guardadas.push(await subirFila(fila))') && src.includes('id: crypto.randomUUID(), trabajo_id: T.id'));
ok('se vuelve a intentar al reconectarse, al regresar a la app y al abrir Floor Plan', /addEventListener\('online'/.test(src) && /visibilitychange/.test(src) && /pintar\(\);\n  subirPendientes\(\);\n\}/.test(src));
// 16-oct, su pedido: "solo los managers... borrar planos". Se marca borrado (no se destruye), con sus escaneos anteriores, y se comprueba.
ok('borrar plano: solo el manager lo ve (botón en la compu y en el menú ••• del teléfono)', /esManager\(\) && p \? `<button type="button" class="btn btn-outline btn-rojo" data-pl-borrar>/.test(src) && /esManager\(\) && p \? `<button type="button" class="pl-menu-rojo" data-pl-borrar>/.test(src));
ok('borrar plano: pregunta antes, marca borrado_at (no destruye la fila) a todos los escaneos de ese nivel, y lo comprueba volviendo a leer', /if\(!T \|\| OCUPADO \|\| !esManager\(\)\) return;/.test(src) && /preguntar\(\{ titulo: 'Delete the floor plan of '/.test(src) && /method:'PATCH'[^\n]*borrado_at: new Date\(\)\.toISOString\(\)/.test(src) && /CARGADO = ''; await cargar\(\);\n  const quedan = PLANOS\.filter\(p => ids\.includes\(p\.id\)\)\.length;/.test(src) && !/method:'DELETE'/.test(src));
console.log(`\nplanos pendientes: ${pass} ok, ${fail} fallas`);
process.exit(fail ? 1 : 0);
