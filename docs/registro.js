// Scanova360 · el REGISTRO DE SECADO (Dry Log) de un proyecto: lo que se anotó día con día.
// Todo es puro (recibe las filas de fotos_drylog_lecturas / fotos_drylog_equipos y devuelve lo que se dibuja), para
// usarlo igual en el teléfono (día 2 en adelante), en la computadora y en los PDF de Documents, y probarlo sin pantalla.
//  · Día del secado: el día 1 es el primer día con algo anotado; cuenta días de calendario (Day 3 = dos días después).
//  · Punto de medida: material + dónde (Drywall · East wall). El día 2 se vuelve a medir el MISMO punto y se compara.
//  · Equipo: lo último que se contó en cada cuarto cada día; los días sin visita siguen con lo último contado.
//  · Días de equipo (para cobrar): cada día de calendario que una unidad estuvo en la casa, desde el día que se
//    anotó hasta el día que se anotó quitada (ese día ya no cuenta). Si sigue en la casa, cuenta hasta hoy.

const pad2 = (n) => String(n).padStart(2, '0');
export const hoyLocal = (d = new Date()) => d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
const aUTC = (dia) => { const [y, m, d] = String(dia || '').split('-').map(Number); return Date.UTC(y, (m || 1) - 1, d || 1); };
export const diasEntre = (a, b) => Math.round((aUTC(b) - aUTC(a)) / 86400000);
export const sumarDias = (dia, n) => { const t = new Date(aUTC(dia) + n * 86400000); return t.getUTCFullYear() + '-' + pad2(t.getUTCMonth() + 1) + '-' + pad2(t.getUTCDate()); };
const MESES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
export const fechaCorta = (dia) => { const p = String(dia || '').split('-'); return p.length === 3 ? MESES[+p[1] - 1] + ' ' + (+p[2]) : String(dia || ''); };
export const fechaLarga = (dia) => { const p = String(dia || '').split('-'); return p.length === 3 ? MESES[+p[1] - 1] + ' ' + (+p[2]) + ', ' + p[0] : String(dia || ''); };
const orden = (filas) => (filas || []).slice().sort((a, b) => String(a.dia).localeCompare(String(b.dia)) || String(a.created_at || '').localeCompare(String(b.created_at || '')));

// ---------- el día ----------
export function primerDia(lecturas, equipos){
  const dias = [...(lecturas || []), ...(equipos || [])].map(f => f.dia).filter(Boolean).sort();
  return dias[0] || null;
}
export function numeroDia(lecturas, equipos, hoy){
  const p = primerDia(lecturas, equipos); return p ? Math.max(1, diasEntre(p, hoy) + 1) : 1;
}
// Todos los días con algo anotado, en orden, con su número de día.
export function diasDelRegistro(lecturas, equipos){
  const p = primerDia(lecturas, equipos); if(!p) return [];
  const dias = [...new Set([...(lecturas || []), ...(equipos || [])].map(f => f.dia).filter(Boolean))].sort();
  return dias.map(d => ({ dia: d, n: diasEntre(p, d) + 1 }));
}

// ---------- los puntos de medida ----------
const norm = (s) => String(s || '').trim().toLowerCase().replace(/\s+/g, ' ');
export const clavePunto = (f) => norm(f.material) + '|' + norm(f.ubicacion);
export const nombrePunto = (f) => [f.material, f.ubicacion].filter(x => String(x || '').trim()).join(' · ') || 'Reading';
// Los puntos de un cuarto, en el orden en que se midieron por primera vez; cada uno con su lectura de cada día
// (si ese día se midió dos veces el mismo punto, vale la última).
export function puntosDeCuarto(lecturas, cuartoId){
  const mapa = new Map();
  orden((lecturas || []).filter(f => f.cuarto_id === cuartoId)).forEach(f => {
    const k = clavePunto(f);
    if(!mapa.has(k)) mapa.set(k, { clave: k, material: f.material || '', ubicacion: f.ubicacion || '', nombre: nombrePunto(f), dias: {} });
    mapa.get(k).dias[f.dia] = { valor: Number(f.valor), foto_id: f.foto_id || null, id: f.id, created_at: f.created_at };
  });
  return [...mapa.values()];
}
// La visita anterior a "hoy" en un cuarto: el último día antes de hoy con lecturas ahí, y sus puntos.
export function visitaAnterior(lecturas, cuartoId, hoy){
  const dias = [...new Set((lecturas || []).filter(f => f.cuarto_id === cuartoId && f.dia < hoy).map(f => f.dia))].sort();
  const dia = dias[dias.length - 1]; if(!dia) return null;
  const puntos = puntosDeCuarto(lecturas, cuartoId).filter(p => p.dias[dia]).map(p => ({ ...p, valor: p.dias[dia].valor }));
  return { dia, puntos };
}
// Los puntos de la visita anterior que todavía no se miden hoy (el día 2 se recorren los mismos puntos).
export function puntosPendientes(lecturas, cuartoId, hoy){
  const v = visitaAnterior(lecturas, cuartoId, hoy); if(!v) return [];
  const hechos = new Set((lecturas || []).filter(f => f.cuarto_id === cuartoId && f.dia === hoy).map(clavePunto));
  return v.puntos.filter(p => !hechos.has(p.clave));
}
// Lo que se midió antes en ese mismo punto (para comparar: 45% → 40%).
export function lecturaAnterior(lecturas, cuartoId, material, ubicacion, hoy){
  const k = clavePunto({ material, ubicacion });
  const l = orden((lecturas || []).filter(f => f.cuarto_id === cuartoId && f.dia < hoy && clavePunto(f) === k));
  const f = l[l.length - 1]; return f ? { dia: f.dia, valor: Number(f.valor) } : null;
}
// Bajó (se está secando), subió o igual. Azul = seca, ámbar = más mojado (en la app no se usa verde).
export function tendencia(antes, ahora){
  if(antes == null || ahora == null || isNaN(antes) || isNaN(ahora)) return null;
  const d = Math.round((ahora - antes) * 10) / 10;
  return { delta: d, tipo: d < 0 ? 'baja' : d > 0 ? 'sube' : 'igual', texto: d === 0 ? 'no change' : (d < 0 ? '▼ ' : '▲ ') + Math.abs(d) };
}
// Lecturas de hoy en un cuarto (la más nueva al final).
export const lecturasDelDia = (lecturas, cuartoId, dia) => orden((lecturas || []).filter(f => f.cuarto_id === cuartoId && f.dia === dia));

// ---------- los cuartos que se recorren ----------
// El día 1 se recorren todos los cuartos del proyecto. Del día 2 en adelante, solo los que ya tienen algo anotado
// (los afectados): un cuarto que el día 1 se brincó no estorba en la vuelta de cada día.
export function cuartosDelRecorrido(niveles, cuartos, lecturas, equipos, hoy){
  const todos = []; (niveles || []).forEach(n => (cuartos || []).filter(c => c.nivel_id === n.id).forEach(c => todos.push(c)));
  const antes = new Set([...(lecturas || []), ...(equipos || [])].filter(f => f.dia < hoy && f.cuarto_id).map(f => f.cuarto_id));
  if(!antes.size) return todos;
  const afectados = todos.filter(c => antes.has(c.id));
  return afectados.length ? afectados : todos;
}

// ---------- el equipo ----------
// Para cada cuarto y cada día, lo contado. Cada vez que se guarda el equipo se escriben todas sus filas juntas (la
// misma hora): de cada cuarto y día vale solo la anotación más nueva completa ("none" = No Equipment = nada).
export function equipoPorDia(equipos){
  const grupos = {};
  (equipos || []).forEach(f => { if(!f.dia) return; const k = (f.cuarto_id || '-') + '|' + f.dia; (grupos[k] = grupos[k] || []).push(f); });
  const out = {};   // cuarto_id -> dia -> { tipo: n }
  Object.entries(grupos).forEach(([k, filas]) => {
    const [c, d] = k.split('|');
    const ultima = filas.map(f => String(f.created_at || '')).sort().pop();
    const cuentas = {};
    filas.filter(f => String(f.created_at || '') === ultima && f.tipo !== 'none').forEach(f => { cuentas[f.tipo] = Math.max(0, Number(f.cantidad) || 0); });
    (out[c] = out[c] || {})[d] = cuentas;
  });
  return out;
}
// Lo que hay en un cuarto un día cualquiera: lo último contado ese día o antes (los días sin visita siguen igual).
export function equipoEnDia(porDia, cuartoId, dia){
  const dias = Object.keys((porDia || {})[cuartoId] || {}).filter(d => d <= dia).sort();
  const d = dias[dias.length - 1]; return d ? { desde: d, cuentas: { ...porDia[cuartoId][d] } } : null;
}
// Días de equipo de un cuarto y un tipo, hasta "hasta" (hoy): cada día de calendario con su cuenta.
export function diasDeEquipo(porDia, cuartoId, tipo, hasta){
  const dias = Object.keys((porDia || {})[cuartoId] || {}).sort(); if(!dias.length || !hasta) return 0;
  let total = 0, cuenta = 0, i = 0;
  for(let d = dias[0]; d <= hasta; d = sumarDias(d, 1)){
    while(i < dias.length && dias[i] <= d){ cuenta = porDia[cuartoId][dias[i]][tipo] || 0; i++; }
    total += cuenta;
  }
  return total;
}
// El resumen del equipo de todo el proyecto, por tipo: cuántas unidades a lo más, días de equipo, cuándo se puso,
// cuándo se quitó (o "on site" si sigue).
export function resumenDeEquipo(equipos, hasta){
  const porDia = equipoPorDia(equipos), tipos = new Map();
  Object.keys(porDia).forEach(c => {
    const dias = Object.keys(porDia[c]).sort();
    const nombres = new Set(); dias.forEach(d => Object.keys(porDia[c][d]).forEach(t => nombres.add(t)));
    nombres.forEach(t => {
      const r = tipos.get(t) || { tipo: t, max: 0, dias: 0, desde: null, hasta: null, enSitio: 0 };
      const cuentas = dias.map(d => [d, porDia[c][d][t] || 0]);
      const primero = cuentas.find(([, n]) => n > 0); if(!primero) return;
      if(!r.desde || primero[0] < r.desde) r.desde = primero[0];
      r.dias += diasDeEquipo(porDia, c, t, hasta);
      const ultimo = cuentas[cuentas.length - 1][1]; r.enSitio += ultimo;
      if(ultimo === 0){ const quit = cuentas.filter(([, n]) => n === 0).pop()[0]; if(!r.hasta || quit > r.hasta) r.hasta = quit; }
      tipos.set(t, r);
    });
  });
  // Lo más que hubo a la vez de cada tipo (sumando cuartos), día por día.
  const todosDias = [...new Set(Object.values(porDia).flatMap(x => Object.keys(x)))].sort();
  tipos.forEach(r => { todosDias.forEach(d => { let s = 0; Object.keys(porDia).forEach(c => { const e = equipoEnDia(porDia, c, d); s += e ? (e.cuentas[r.tipo] || 0) : 0; }); r.max = Math.max(r.max, s); }); if(r.enSitio > 0) r.hasta = null; });
  return [...tipos.values()].sort((a, b) => b.dias - a.dias || a.tipo.localeCompare(b.tipo));
}
// El texto corto del equipo: "2 Fans / Air Movers · 1 Dehumidifiers".
export const textoEquipo = (cuentas) => Object.entries(cuentas || {}).filter(([, n]) => n > 0).map(([t, n]) => n + ' ' + t).join(' · ');
