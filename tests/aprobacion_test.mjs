// Scanova · aprobación: el SQL y la web dicen lo mismo (en espera = paused; solo el manager decide).
import fs from 'node:fs';
import { estadoTxt } from '../docs/personas.js';
let pass = 0, fail = 0; const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const sql = fs.readFileSync(new URL('../sql/fotos-02-aprobacion.sql', import.meta.url), 'utf8');
const app = fs.readFileSync(new URL('../docs/app.js', import.meta.url), 'utf8');
const idx = fs.readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8');
ok('SQL: la cuenta nueva nace pausada (en espera), nunca activa', /values \(auth\.uid\(\), v_id, 'crew', p_name, 'paused'\)/.test(sql) && !/'crew', p_name, 'active'/.test(sql));
ok('SQL: un miembro que ya es de la empresa no se toca', /if v_prof\.id is not null and v_prof\.company_id is not null then\s+return/.test(sql));
ok('SQL: decidir exige manager y misma empresa, y nunca toca a un manager', /if my_role\(\) <> 'manager' then raise exception 'solo_manager'/.test(sql) && /v_sol\.company_id <> my_company\(\)/.test(sql) && /and role <> 'manager'/.test(sql));
ok('SQL: anon fuera de las dos funciones; la tabla sin escritura para la app', (sql.match(/revoke all on function fotos_\w+\([^)]*\) from public, anon;/g)||[]).length === 2 && /revoke all on fotos_solicitudes from anon/.test(sql) && !/for insert to authenticated/.test(sql.split('fotos_solicitudes').slice(1).join('')));
ok('web: crear cuenta pide entrada (no join_company) y cae en la sala de espera', /rpc\/fotos_pedir_entrada/.test(app) && !/rpc\/join_company/.test(app) && /irA\('pEspera'\)/.test(app));
ok('web: solo activa o manager entra a trabajos; sacado no entra', /function puedeEntrar\(p\)\{ return !!\(p && p\.company_id && \(p\.role === 'manager' \|\| \(p\.status \|\| 'active'\) === 'active'\)\); \}/.test(app) && /status === 'removed'/.test(app));
ok('web: la pantalla de espera y la del equipo existen; Settings lleva al equipo solo al manager y el conteo es solo del manager', /id="pEspera"/.test(idx) && /id="pPersonas"/.test(idx) && /n === 'settings' \|\| n === 'personas'\)\{ if\(esManager\(\)\)\{[^}]*irA\('pPersonas'/.test(app) && /esManager\(\) \? await contarPendientes\(\) : 0/.test(fs.readFileSync(new URL('../docs/personas.js', import.meta.url), 'utf8')));
ok('estadoTxt: pausado se lee como en espera', /espera/.test(estadoTxt('paused')) && estadoTxt('active') === 'activo' && estadoTxt('removed') === 'sacado');
console.log(`\n${pass} ok, ${fail} fail`); process.exit(fail ? 1 : 0);
