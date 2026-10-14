// Scanova360 · pestaña Dry Log (14-oct): GPP, días de secado, puntos secos, días de equipo, y la base de datos.
import fs from 'node:fs';
import * as S from '../docs/secado.js';
let pass = 0, fail = 0;
const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
// GPP contra la tabla de ASHRAE (nivel del mar): 70 °F/50 % = 54.5; 80 °F/60 % = 92.1; 90 °F/30 % = 63.0.
ok('GPP 70 °F y 50 % = 54.5 (ASHRAE)', Math.abs(S.gpp(70, 50) - 54.5) <= 0.2);
ok('GPP 80 °F y 60 % = 92.1 (ASHRAE)', Math.abs(S.gpp(80, 60) - 92.1) <= 0.3);
ok('GPP 90 °F y 30 % = 63.0 (ASHRAE)', Math.abs(S.gpp(90, 30) - 63.0) <= 0.3);
ok('GPP no inventa: sin un dato, o fuera de rango, no hay número', S.gpp('', 50) === null && S.gpp(70, '') === null && S.gpp(70, 120) === null && S.gpp(200, 40) === null && S.gpp(null, null) === null);
ok('GPP se muestra con un decimal (44 sale 44.0) y sin dato sale una raya', S.fmtGpp(44) === '44.0' && S.fmtGpp(null) === '—');
ok('la fecha de hoy es la del teléfono, no la de Londres', S.hoyLocal(new Date(2026, 9, 14, 23, 30)) === '2026-10-14');
ok('días entre fechas sin brincos por el horario de verano', S.diasEntre('2026-11-01', '2026-11-03') === 2 && S.diasEntre('2026-10-10', '2026-10-14') === 4);
const D = {
  puntos: [{ id:'a', meta:12, material:'Drywall' }, { id:'b', meta:14 }, { id:'c', meta:null }],
  lecturas: [{ punto_id:'a', dia:'2026-10-11', valor:30 }, { punto_id:'a', dia:'2026-10-13', valor:11 }, { punto_id:'a', dia:'2026-10-12', valor:19 }, { punto_id:'b', dia:'2026-10-13', valor:15 }, { punto_id:'c', dia:'2026-10-13', valor:3 }],
  ambiente: [{ dia:'2026-10-12', lugar:'Outside', temp_f:70, rh:50 }],
  equipos: [{ tipo:'Air mover', cantidad:4, puesto:'2026-10-10', quitado:null }, { tipo:'Air mover', cantidad:3, puesto:'2026-10-10', quitado:'2026-10-13' }, { tipo:'Dehumidifier', cantidad:1, puesto:'2026-10-14', quitado:null }],
};
ok('el día 1 es el primer día con algo anotado (aquí el equipo del 10)', S.inicioDe(D) === '2026-10-10' && S.numeroDeDia('2026-10-10', '2026-10-14') === 5);
const ea = S.estadoPunto(D.puntos[0], D.lecturas);
ok('un punto: lecturas en orden de fecha y la última manda (11 ≤ 12 = seco)', ea.lecturas.map(l => l.valor).join() === '30,19,11' && ea.ultima === 11 && ea.seco === true);
ok('15 contra una meta de 14 sigue mojado; sin meta nunca se da por seco', S.estadoPunto(D.puntos[1], D.lecturas).seco === false && S.estadoPunto(D.puntos[2], D.lecturas).seco === false);
ok('un punto sin lecturas no está seco', S.estadoPunto({ id:'z', meta:10 }, D.lecturas).seco === false && S.estadoPunto({ id:'z', meta:10 }, D.lecturas).ultima === null);
const r = S.resumen(D, '2026-10-14');
ok('resumen: día 5, 1 de 3 materiales secos, 1 sin meta', r.dia === 5 && r.total === 3 && r.secos === 1 && r.sinMeta === 1);
ok('en el sitio solo cuenta lo que no se ha quitado', r.enSitio['Air mover'] === 4 && r.enSitio['Dehumidifier'] === 1 && S.listaEquipos(r.enSitio) === '4 Air movers · 1 Dehumidifier');
ok('días de equipo: 4×4 + 3×3 = 25 air movers; uno puesto hoy cuenta 1', r.diasEq['Air mover'] === 25 && r.diasEq['Dehumidifier'] === 1);
ok('plurales del equipo', S.pluralEquipo('Air scrubber (HEPA)', 2) === 'Air scrubbers (HEPA)' && S.pluralEquipo('Dehumidifier', 1) === 'Dehumidifier' && S.pluralEquipo('Ozone machine', 3) === 'Ozone machines');
ok('sin nada anotado: día 0 y nada en el sitio', S.resumen({ puntos:[], lecturas:[], ambiente:[], equipos:[] }, '2026-10-14').dia === 0 && S.listaEquipos({}) === '');
ok('los mismos equipos de Field Reports y materiales por superficie', S.EQUIPOS.includes('Air mover') && S.EQUIPOS.includes('Dehumidifier') && S.MATERIALES.Wall.includes('Drywall') && S.MATERIALES.Floor.includes('Carpet pad') && S.SUPERFICIES.join() === 'Floor,Wall,Ceiling');
// Outside desde el clima (su pedido del 14-oct)
ok('clima: pide °F y humedad de ahora, con la ubicación redondeada a ~1 km', S.urlClima(38.901234, -77.265311) === 'https://api.open-meteo.com/v1/forecast?latitude=38.90&longitude=-77.27&current=temperature_2m,relative_humidity_2m&temperature_unit=fahrenheit&timezone=auto');
ok('clima: lee la respuesta (69.9 °F, 75 %, 00:15 → 70, 75, 12:15 AM)', JSON.stringify(S.leerClima({ current:{ time:'2026-10-14T00:15', temperature_2m:69.9, relative_humidity_2m:75 } })) === JSON.stringify({ t:70, h:75, hora:'12:15 AM' }) && S.leerClima({ current:{ time:'2026-10-14T14:05', temperature_2m:81, relative_humidity_2m:40 } }).hora === '2:05 PM');
ok('clima: una respuesta rara no llena nada', S.leerClima(null) === null && S.leerClima({}) === null && S.leerClima({ current:{ temperature_2m:'x', relative_humidity_2m:50 } }) === null && S.leerClima({ current:{ temperature_2m:70, relative_humidity_2m:140 } }) === null);
{ const sj0 = fs.readFileSync(new URL('../docs/secado.js', import.meta.url), 'utf8');
  ok('clima: solo para hoy, nunca pisa lo que ya escribieron, y siempre se puede cambiar', /if\(DIA !== hoyLocal\(\)\)\{ nota\.textContent = ''; return; \}/.test(sj0) && /if\(!forzar && \(ti\.value \|\| hi\.value\)\)/.test(sj0) && /Change it if your meter reads different/.test(sj0));
  ok('clima: usa el punto del trabajo y, si no hay, el GPS del teléfono', /coordsDe\(T\) \|\| await miPosicion\(\)/.test(sj0)); }
// La pestaña en la ficha
const pr = fs.readFileSync(new URL('../docs/proyecto.js', import.meta.url), 'utf8');
ok('por ahora (14-oct, él arma el diseño): la pestaña Dry Log existe y adentro dice que viene; el módulo no está conectado', /\['secado', 'Dry Log'\]/.test(pr) && /\['secado', 'Dry Log', 'Moisture readings/.test(pr) && !/from '\.\/secado\.js/.test(pr));
const sj = fs.readFileSync(new URL('../docs/secado.js', import.meta.url), 'utf8');
ok('las lecturas del día se guardan sin duplicar (una por punto por día; una por lugar por día)', /fotos_secado_lecturas\?on_conflict=punto_id,dia/.test(sj) && /fotos_secado_ambiente\?on_conflict=trabajo_id,dia,lugar/.test(sj) && /resolution=merge-duplicates/.test(sj));
ok('comprueba que el servidor de verdad guardó (cuenta lo que regresa)', /r\.length !== poner\.length/.test(sj) && /r\.length !== amb\.length/.test(sj));
ok('el CSS del Dry Log no usa verde', !/#16a34a|green|var\(--ok\)/.test(fs.readFileSync(new URL('../docs/estilo.css', import.meta.url), 'utf8').split('===== Dry Log')[1] || 'x'));
// La base de datos
const sql = fs.readFileSync(new URL('../sql/fotos-08-secado.sql', import.meta.url), 'utf8');
ok('SQL en ASCII puro (el editor de Supabase rompe los acentos)', /^[\x00-\x7F]*$/.test(sql));
ok('SQL: cuatro tablas, todas con candado y sin acceso anónimo', ['puntos', 'lecturas', 'ambiente', 'equipos'].every(t => sql.includes('create table if not exists fotos_secado_' + t) && sql.includes('alter table fotos_secado_' + t) && new RegExp('revoke all on fotos_secado_' + t + '\\s+from anon').test(sql)));
ok('SQL: 16 políticas, una lectura por punto por día y un ambiente por lugar por día', (sql.match(/create policy/g) || []).length === 16 && /unique \(punto_id, dia\)/.test(sql) && /unique \(trabajo_id, dia, lugar\)/.test(sql));
ok('SQL: solo agrega (nada se borra ni cambia de lo que ya existe)', !/\bdrop table\b|\balter table fotos_trabajos\b|\bdelete from\b|\btruncate\b/i.test(sql));
console.log(`\nsecado: ${pass} ok, ${fail} fallas`);
if(fail) process.exit(1);
