// Scanova · invitar por enlace (sql/fotos-10-invitaciones.sql): el manager manda un enlace; quien lo abre crea su cuenta
// y entra DIRECTO, activo, a la empresa que lo invitó. Una persona por enlace, vence en 7 días, nunca mueve a nadie de empresa.
import fs from 'node:fs';
import { enlaceInvitacion, estadoInvitacion, invitacionHtml } from '../docs/personas.js';
import { tokenDeUrl, mensajeInvitacion } from '../docs/app.js';
let pass = 0, fail = 0; const ok = (l, c) => { if(c){ pass++; console.log('  ok  ' + l); } else { fail++; console.log('  FAIL ' + l); } };
const sql = fs.readFileSync(new URL('../sql/fotos-10-invitaciones.sql', import.meta.url), 'utf8');
const app = fs.readFileSync(new URL('../docs/app.js', import.meta.url), 'utf8');
const idx = fs.readFileSync(new URL('../docs/index.html', import.meta.url), 'utf8');
const T = 'a'.repeat(32);

// SQL
ok('SQL: solo el manager invita, y a SU empresa', /if my_role\(\) <> 'manager' or my_company\(\) is null then raise exception 'solo_manager'/.test(sql) && /values \(v_token, my_company\(\), auth\.uid\(\)/.test(sql));
ok('SQL: el token sale al azar (no se puede adivinar)', /v_token := replace\(gen_random_uuid\(\)::text, '-', ''\)/.test(sql));
ok('SQL: vence a los 7 días', /vence_at\s+timestamptz not null default now\(\) \+ interval '7 days'/.test(sql));
ok('SQL: la cuenta entra ACTIVA a la empresa del enlace', /values \(auth\.uid\(\), v\.company_id, 'crew', v_nom, 'active'\)/.test(sql));
ok('SQL: nunca mueve a alguien de OTRA empresa', /v_prof\.company_id <> v\.company_id then raise exception 'otra_empresa'/.test(sql));
ok('SQL: un enlace usado, vencido o anulado no sirve', /invitacion_usada/.test(sql) && /v\.vence_at < now\(\) then raise exception 'invitacion_vencida'/.test(sql) && /invitacion_anulada/.test(sql));
ok('SQL: nunca convierte a un manager en crew', /where profiles\.role <> 'manager'/.test(sql));
ok('SQL: anon solo puede PREGUNTAR qué dice un enlace (no invitar, aceptar ni anular)', /grant execute on function fotos_invitacion_info\(text\) to anon, authenticated/.test(sql)
  && (sql.match(/revoke all on function fotos_(invitar|aceptar_invitacion|anular_invitacion)\([^)]*\) from public, anon;/g) || []).length === 3);
ok('SQL: la tabla la lee solo el manager de esa empresa y la app no escribe en ella', /revoke all on fotos_invitaciones from anon, public/.test(sql) && /using \(company_id = my_company\(\) and my_role\(\) = 'manager'\)/.test(sql) && !/on fotos_invitaciones for (insert|update|delete)/.test(sql));
ok('SQL: las cuatro funciones son security definer', (sql.match(/create or replace function fotos_\w+[\s\S]*?security definer set search_path = public/g) || []).length === 4);
ok('SQL: anular solo un enlace sin usar de su empresa', /where token = p_token and company_id = my_company\(\) and usada_at is null and anulada_at is null/.test(sql));

// web
ok('tokenDeUrl: lee ?invitacion= de 32 letras y nada más', tokenDeUrl('?invitacion=' + T.toUpperCase()) === T && tokenDeUrl('?invitacion=abc') === '' && tokenDeUrl('?v=1') === '' && tokenDeUrl('') === '');
ok('enlaceInvitacion: en el navegador usa la misma página; en el aparato, scanova360.com',
  enlaceInvitacion(T, 'https://scanova360.com/?v=2026') === 'https://scanova360.com/?invitacion=' + T
  && enlaceInvitacion(T, 'capacitor://localhost/index.html') === 'https://scanova360.com/?invitacion=' + T);
const ahora = Date.parse('2026-10-14T12:00:00Z');
ok('estadoInvitacion: sin usar / usada / vencida / anulada',
  estadoInvitacion({ vence_at:'2026-10-20T00:00:00Z' }, ahora) === 'valida' && estadoInvitacion({ vence_at:'2026-10-20T00:00:00Z', usada_at:'x' }, ahora) === 'usada'
  && estadoInvitacion({ vence_at:'2026-10-10T00:00:00Z' }, ahora) === 'vencida' && estadoInvitacion({ vence_at:'2026-10-20T00:00:00Z', anulada_at:'x' }, ahora) === 'anulada');
const hv = invitacionHtml({ token:T, nombre:'Vero', vence_at:'2026-10-20T00:00:00Z', created_at:'2026-10-13T00:00:00Z' }, ahora);
const hu = invitacionHtml({ token:T, nombre:'Harold', vence_at:'2026-10-20T00:00:00Z', usada_at:'2026-10-13T00:00:00Z', usada_nombre:'Harold Gomez' }, ahora);
ok('invitacionHtml: la sin usar se puede mandar o anular; la usada dice quién entró y no tiene botones', /data-inv="anular"/.test(hv) && /data-inv="mandar"/.test(hv) && /Entró Harold Gomez/.test(hu) && !/data-inv/.test(hu));
ok('invitacionHtml: escapa el nombre', !/<b>x<\/b>/.test(invitacionHtml({ token:T, nombre:'<b>x</b>', vence_at:'2026-10-20T00:00:00Z' }, ahora)));
ok('mensajeInvitacion: cada caso dice qué hacer', /ya se usó/.test(mensajeInvitacion('invitacion_usada', 'RD')) && /venció/.test(mensajeInvitacion('invitacion_vencida')) && /otra empresa/.test(mensajeInvitacion('otra_empresa')) && mensajeInvitacion('x') === '');
ok('web: el enlace se guarda antes de que la página se recargue (sobrevive al correo y a Google)', /\(function guardarInvitacionDeUrl\(\)\{/.test(app) && /localStorage\.setItem\(CLAVE_INV, t\)/.test(app));
ok('web: con invitación, Crear cuenta no pide el código y usa el enlace', /if\(!codigo && !inv\)/.test(app) && /inv \? await aceptarInvitacion\(inv, nombre\) : await pedirEntrada\(codigo, nombre\)/.test(app));
ok('web: Entrar y Google también usan el enlace si la cuenta no tiene empresa', /if\(\(!p \|\| !p\.company_id\) && inv\)\{ try\{ p = await aceptarInvitacion/.test(app) && /if\(invitacionGuardada\(\)\)\{\s*try\{ const p2 = await aceptarInvitacion/.test(app));
ok('pantallas: aviso de quién invita en Crear cuenta y bloque Invitar en Personas', /id="crInvitacion"/.test(idx) && /id="crCodigoCampo"/.test(idx) && /id="btnInvitar"/.test(idx) && /id="listaInvitaciones"/.test(idx));
console.log(`\n${pass} ok, ${fail} fail`); process.exit(fail ? 1 : 0);
