// Scanova · empresas nuevas (sql/fotos-11-empresas.sql): solo el dueño de Scanova360 crea el enlace; quien lo usa crea
// SU empresa y queda de manager. Nadie se mueve de empresa y create_company sigue cerrado.
import fs from 'node:fs';
import { enlaceInvitacion, empresaInvHtml } from '../docs/personas.js';
import { tokenDeUrl, mensajeEmpresa, mensajeInvitacion } from '../docs/app.js';
let pass = 0, fail = 0; const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const sql = fs.readFileSync(new URL('../sql/fotos-11-empresas.sql', import.meta.url), 'utf8');
const app = fs.readFileSync(new URL('../docs/app.js', import.meta.url), 'utf8');
const idx = fs.readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8');
const T = 'd'.repeat(32), ahora = Date.parse('2026-10-14T12:00:00Z');

ok('SQL: el dueño es solo la cuenta dilsar32@gmail.com', /insert into fotos_plataforma \(user_id\) select id from auth\.users where lower\(email\) = 'dilsar32@gmail\.com'/.test(sql));
ok('SQL: solo el dueño crea y anula enlaces de empresa', (sql.match(/if not exists\(select 1 from fotos_plataforma where user_id = auth\.uid\(\)\) then raise exception 'solo_dueno'/g) || []).length === 2);
ok('SQL: la empresa nueva sale con su propio código de equipo único', /v_code := upper\(substr\(md5\(random\(\)::text\), 1, 6\)\);\s*exit when not exists \(select 1 from companies where join_code = v_code\)/.test(sql) && /insert into companies \(name, join_code\) values \(v_emp, v_code\)/.test(sql));
ok('SQL: quien usa el enlace queda manager ACTIVO de la empresa nueva', /insert into profiles \(id, company_id, role, full_name, status\) values \(auth\.uid\(\), v_id, 'manager', v_nom, 'active'\)/.test(sql));
ok('SQL: una cuenta que ya tiene perfil nunca se mueve de empresa', /if v_prof\.id is not null then raise exception 'ya_tiene_empresa'/.test(sql));
ok('SQL: el enlace sirve una vez, vence a los 14 días y se puede anular', /interval '14 days'/.test(sql) && /raise exception 'empresa_usada'/.test(sql) && /raise exception 'empresa_vencida'/.test(sql) && /raise exception 'empresa_anulada'/.test(sql));
ok('SQL: pide el nombre de la empresa', /raise exception 'falta_nombre_empresa'/.test(sql));
ok('SQL: anon solo pregunta qué dice el enlace', /grant execute on function fotos_empresa_invitacion_info\(text\) to anon, authenticated/.test(sql)
  && (sql.match(/revoke all on function fotos_(invitar_empresa|crear_empresa|anular_invitacion_empresa|soy_dueno|aceptar_invitacion)\([^)]*\) from public, anon;/g) || []).length === 5);
ok('SQL: la lista de enlaces solo la lee el dueño; la app no escribe en las tablas', /using \(exists\(select 1 from fotos_plataforma d where d\.user_id = auth\.uid\(\)\)\)/.test(sql) && !/on fotos_(invitaciones_empresa|plataforma) for (insert|update|delete)/.test(sql));
ok('SQL: NO abre create_company (lo comprueba al final)', !/grant execute on function create_company/.test(sql) && /create_company_abierto/.test(sql));
ok('SQL: la invitación de equipo dice claro "fuera del equipo" en vez de chocar con el guardia', /raise exception 'cuenta_fuera'/.test(sql));

ok('tokenDeUrl: lee ?empresa= aparte de ?invitacion=', tokenDeUrl('?empresa=' + T, 'empresa') === T && tokenDeUrl('?empresa=' + T) === '' && tokenDeUrl('?invitacion=' + T, 'empresa') === '');
ok('enlaceInvitacion: el de empresa usa ?empresa=', enlaceInvitacion(T, 'https://scanova360.com/', 'empresa') === 'https://scanova360.com/?empresa=' + T);
const hv = empresaInvHtml({ token:T, empresa:'Flood Pros LLC', para:'Carlos', vence_at:'2026-10-28T00:00:00Z' }, ahora);
const hu = empresaInvHtml({ token:T, empresa:'Dry', vence_at:'2026-10-28T00:00:00Z', usada_at:'2026-10-13T00:00:00Z', empresa_creada:'Dry Team Restoration' }, ahora);
ok('empresaInvHtml: la sin usar se manda o anula; la usada dice qué empresa se creó', /data-emp="anular"/.test(hv) && /para Carlos/.test(hv) && /Creó Dry Team Restoration/.test(hu) && !/data-emp/.test(hu));
ok('mensajes: cada caso dice qué hacer', /ya se usó/.test(mensajeEmpresa('empresa_usada')) && /otro correo/.test(mensajeEmpresa('ya_tiene_empresa')) && /activar/.test(mensajeInvitacion('cuenta_fuera')) && mensajeEmpresa('x') === '');
ok('web: Crear cuenta con enlace de empresa pide el nombre de la empresa y crea la empresa', /emp \? await crearEmpresa\(empresaGuardada\(\), emp, nombre\)/.test(app) && /\$\('#crTitulo'\)\.textContent = emp \? 'Registre su empresa'/.test(app));
ok('web: Google y Entrar también llevan a "Registre su empresa"', /if\(empresaGuardada\(\)\)\{ if\(!EMP_INFO\) EMP_INFO = await infoEmpresa\(empresaGuardada\(\)\); pedirEmpresa\(NOMBRE_GOOGLE\)/.test(app) && /necesitaEmpresa/.test(app));
ok('web: el bloque de empresas solo aparece si el servidor dice que es el dueño', /rpc\/fotos_soy_dueno/.test(fs.readFileSync(new URL('../docs/personas.js', import.meta.url), 'utf8')) && /id="bloqueEmpresas" hidden/.test(idx));
ok('pantallas: campo de empresa en Crear cuenta y en "Un paso más"', /id="crEmpresaCampo" hidden/.test(idx) && /id="gcEmpresaCampo" hidden/.test(idx) && /id="crInvEmpresaNueva" hidden/.test(idx));
console.log(`\n${pass} ok, ${fail} fail`); process.exit(fail ? 1 : 0);
