-- =====================================================================
--  fotos-10-invitaciones.sql  ·  SCANOVA — invitar por enlace (14 oct 2026)
--  Amilcar: "yo con mi empresa tengo que tener la habilidad de mandar invitaciones; con ese link pueden entrar y
--  crear su perfil, y ya poder usar la aplicación, pero solo ven lo de la empresa que le mandó la invitación."
--  El manager crea un enlace (scanova360.com/?invitacion=XXXX). Quien lo abre crea su cuenta y entra DIRECTO a esa
--  empresa, activo (el manager ya lo autorizó al invitarlo). Lo que ve ya lo limita my_company() en todas las tablas.
--  Cada enlace sirve para UNA persona y vence a los 7 días. El código del equipo + aprobación (fotos-02) sigue igual.
--  Nada de Field Reports se toca: una tabla y cuatro funciones con prefijo fotos_.
-- =====================================================================

-- ---------- 1. Las invitaciones ----------
create table if not exists fotos_invitaciones (
  token       text primary key,
  company_id  uuid not null references companies(id) on delete cascade,
  creada_por  uuid references auth.users(id) on delete set null,
  nombre      text,                                   -- para quién (opcional, solo para que el manager se acuerde)
  created_at  timestamptz not null default now(),
  vence_at    timestamptz not null default now() + interval '7 days',
  usada_por   uuid references auth.users(id) on delete set null,
  usada_nombre text,
  usada_at    timestamptz,
  anulada_at  timestamptz
);
create index if not exists fotos_invitaciones_empresa_idx on fotos_invitaciones (company_id, created_at desc);
alter table fotos_invitaciones enable row level security;
revoke all on fotos_invitaciones from anon, public;
grant select on fotos_invitaciones to authenticated;
drop policy if exists "fotos_invitaciones manager lee" on fotos_invitaciones;
create policy "fotos_invitaciones manager lee" on fotos_invitaciones for select to authenticated
  using (company_id = my_company() and my_role() = 'manager');
-- Sin insert/update/delete para la app: solo las funciones de abajo escriben.

-- ---------- 2. Crear una invitación (solo el manager de su empresa) ----------
create or replace function fotos_invitar(p_nombre text default null)
returns json language plpgsql security definer set search_path = public as $$
declare v_token text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if my_role() <> 'manager' or my_company() is null then raise exception 'solo_manager'; end if;
  v_token := replace(gen_random_uuid()::text, '-', '');            -- 122 bits al azar: no se puede adivinar
  insert into fotos_invitaciones (token, company_id, creada_por, nombre)
    values (v_token, my_company(), auth.uid(), nullif(trim(coalesce(p_nombre, '')), ''));
  return (select json_build_object('token', token, 'nombre', nombre, 'vence_at', vence_at) from fotos_invitaciones where token = v_token);
end $$;
revoke all on function fotos_invitar(text) from public, anon;
grant execute on function fotos_invitar(text) to authenticated;

-- ---------- 3. Qué dice un enlace (lo pregunta la pantalla ANTES de crear la cuenta: por eso anon) ----------
-- Solo devuelve el nombre de la empresa y si el enlace sirve. Sin el token (122 bits) no se puede preguntar nada.
create or replace function fotos_invitacion_info(p_token text)
returns json language plpgsql security definer set search_path = public as $$
declare v fotos_invitaciones%rowtype; v_emp text;
begin
  select * into v from fotos_invitaciones where token = lower(trim(coalesce(p_token, '')));
  if v.token is null then return json_build_object('estado', 'no_existe'); end if;
  select name into v_emp from companies where id = v.company_id;
  return json_build_object('empresa', v_emp, 'nombre', v.nombre,
    'estado', case when v.anulada_at is not null then 'anulada' when v.usada_at is not null then 'usada'
                   when v.vence_at < now() then 'vencida' else 'valida' end);
end $$;
revoke all on function fotos_invitacion_info(text) from public;
grant execute on function fotos_invitacion_info(text) to anon, authenticated;

-- ---------- 4. Aceptar: la cuenta queda en la empresa que invitó, ACTIVA ----------
create or replace function fotos_aceptar_invitacion(p_token text, p_name text default null)
returns json language plpgsql security definer set search_path = public as $$
declare v fotos_invitaciones%rowtype; v_prof profiles%rowtype; v_correo text; v_nom text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into v from fotos_invitaciones where token = lower(trim(coalesce(p_token, ''))) for update;
  if v.token is null then raise exception 'invitacion_no_existe'; end if;
  select * into v_prof from profiles where id = auth.uid();
  -- Ya es de ESTA empresa (abrió el enlace otra vez): no gasta nada, solo entra como ya estaba.
  if v_prof.id is not null and v_prof.company_id = v.company_id and (v_prof.role = 'manager' or coalesce(v_prof.status, 'active') = 'active') then
    return json_build_object('company_id', v_prof.company_id, 'status', coalesce(v_prof.status, 'active'), 'role', v_prof.role, 'ya_era', true);
  end if;
  -- Es de OTRA empresa: una cuenta vive en una sola empresa. No se mueve a nadie.
  if v_prof.id is not null and v_prof.company_id is not null and v_prof.company_id <> v.company_id then raise exception 'otra_empresa'; end if;
  if v.anulada_at is not null then raise exception 'invitacion_anulada'; end if;
  if v.usada_at is not null and v.usada_por is distinct from auth.uid() then raise exception 'invitacion_usada'; end if;
  if v.vence_at < now() then raise exception 'invitacion_vencida'; end if;
  select email into v_correo from auth.users where id = auth.uid();
  v_nom := coalesce(nullif(trim(coalesce(p_name, '')), ''), v_prof.full_name, v.nombre);
  insert into profiles (id, company_id, role, full_name, status) values (auth.uid(), v.company_id, 'crew', v_nom, 'active')
    on conflict (id) do update set company_id = v.company_id, full_name = coalesce(v_nom, profiles.full_name), status = 'active'
    where profiles.role <> 'manager';
  update fotos_invitaciones set usada_por = auth.uid(), usada_nombre = v_nom, usada_at = coalesce(usada_at, now()) where token = v.token;
  -- Queda en el historial de Personas como aprobada (si había pedido entrada con el código, ya no espera).
  insert into fotos_solicitudes (user_id, company_id, nombre, correo, estado, decidido_at, decidido_por)
    values (auth.uid(), v.company_id, v_nom, v_correo, 'aprobada', now(), v.creada_por)
    on conflict (user_id) do update set company_id = v.company_id, estado = 'aprobada', decidido_at = now(), decidido_por = v.creada_por;
  return json_build_object('company_id', v.company_id, 'status', 'active', 'role', 'crew');
end $$;
revoke all on function fotos_aceptar_invitacion(text, text) from public, anon;
grant execute on function fotos_aceptar_invitacion(text, text) to authenticated;

-- ---------- 5. Anular un enlace que todavía no se usó (solo el manager de esa empresa) ----------
create or replace function fotos_anular_invitacion(p_token text)
returns json language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if my_role() <> 'manager' then raise exception 'solo_manager'; end if;
  update fotos_invitaciones set anulada_at = now()
    where token = p_token and company_id = my_company() and usada_at is null and anulada_at is null;
  if not found then raise exception 'no_se_puede'; end if;
  return json_build_object('token', p_token, 'estado', 'anulada');
end $$;
revoke all on function fotos_anular_invitacion(text) from public, anon;
grant execute on function fotos_anular_invitacion(text) to authenticated;

notify pgrst, 'reload schema';

-- ---------- COMPROBACION (una fila; lo esperado al lado) ----------
select (select count(*) from information_schema.tables where table_name = 'fotos_invitaciones') as tabla,                    -- 1
       (select count(*) from pg_policies where tablename = 'fotos_invitaciones') as politicas,                                -- 1
       has_table_privilege('anon', 'fotos_invitaciones', 'select') as anon_lee_tabla,                                         -- false
       has_function_privilege('anon', 'fotos_invitar(text)', 'execute') as anon_invita,                                       -- false
       has_function_privilege('anon', 'fotos_invitacion_info(text)', 'execute') as anon_pregunta,                             -- true
       has_function_privilege('anon', 'fotos_aceptar_invitacion(text,text)', 'execute') as anon_acepta,                       -- false
       has_function_privilege('authenticated', 'fotos_aceptar_invitacion(text,text)', 'execute') as equipo_acepta,            -- true
       has_function_privilege('anon', 'fotos_anular_invitacion(text)', 'execute') as anon_anula,                              -- false
       (select bool_and(prosecdef) from pg_proc where proname like 'fotos_%invita%') as todas_definer;                        -- true
