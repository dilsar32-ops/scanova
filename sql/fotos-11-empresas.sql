-- =====================================================================
--  fotos-11-empresas.sql  -  SCANOVA: invitar una EMPRESA nueva (14 oct 2026)
--  Amilcar (opcion 1): "tu, como dueno de Scanova360, creas un enlace para una empresa nueva; el dueno de esa
--  empresa lo abre, escribe el nombre de su compania y crea su cuenta; queda como manager de SU empresa".
--  - Solo el DUENO de la plataforma (tabla fotos_plataforma) crea esos enlaces. Los otros managers no.
--  - El enlace (scanova360.com/?empresa=XXXX) sirve UNA vez y vence a los 14 dias.
--  - Quien lo usa queda manager ACTIVO de una empresa nueva y vacia (su propio codigo de equipo).
--  - Una cuenta que ya es de una empresa nunca se mueve.
--  create_company (de Field Reports) sigue cerrado para todos: esto NO lo abre.
--  De paso: fotos_aceptar_invitacion (fotos-10) dice claro el caso "lo sacaron del equipo" en vez de chocar con el
--  guardia de perfiles (guard_profile_update no deja cambiar status/company desde la cuenta de un crew).
-- =====================================================================

-- ---------- 1. Quien es el dueno de la plataforma ----------
create table if not exists fotos_plataforma (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table fotos_plataforma enable row level security;
revoke all on fotos_plataforma from anon, public;
grant select on fotos_plataforma to authenticated;
drop policy if exists "fotos_plataforma propia" on fotos_plataforma;
create policy "fotos_plataforma propia" on fotos_plataforma for select to authenticated using (user_id = auth.uid());
insert into fotos_plataforma (user_id) select id from auth.users where lower(email) = 'dilsar32@gmail.com' on conflict do nothing;

create or replace function fotos_soy_dueno()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from fotos_plataforma where user_id = auth.uid());
$$;
revoke all on function fotos_soy_dueno() from public, anon;
grant execute on function fotos_soy_dueno() to authenticated;

-- ---------- 2. Las invitaciones de empresa ----------
create table if not exists fotos_invitaciones_empresa (
  token        text primary key,
  creada_por   uuid references auth.users(id) on delete set null,
  empresa      text,                                  -- nombre sugerido (lo puede cambiar quien la crea)
  para         text,                                  -- a quien se le manda (solo para acordarse)
  created_at   timestamptz not null default now(),
  vence_at     timestamptz not null default now() + interval '14 days',
  usada_por    uuid references auth.users(id) on delete set null,
  usada_at     timestamptz,
  company_id   uuid references companies(id) on delete set null,   -- la empresa que se creo con el enlace
  empresa_creada text,
  anulada_at   timestamptz
);
create index if not exists fotos_invitaciones_empresa_fecha_idx on fotos_invitaciones_empresa (created_at desc);
alter table fotos_invitaciones_empresa enable row level security;
revoke all on fotos_invitaciones_empresa from anon, public;
grant select on fotos_invitaciones_empresa to authenticated;
drop policy if exists "fotos_invitaciones_empresa dueno lee" on fotos_invitaciones_empresa;
create policy "fotos_invitaciones_empresa dueno lee" on fotos_invitaciones_empresa for select to authenticated
  using (exists(select 1 from fotos_plataforma d where d.user_id = auth.uid()));
-- Sin insert/update/delete para la app: solo las funciones de abajo escriben.

-- ---------- 3. Crear el enlace (solo el dueno) ----------
create or replace function fotos_invitar_empresa(p_empresa text default null, p_para text default null)
returns json language plpgsql security definer set search_path = public as $$
declare v_token text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not exists(select 1 from fotos_plataforma where user_id = auth.uid()) then raise exception 'solo_dueno'; end if;
  v_token := replace(gen_random_uuid()::text, '-', '');
  insert into fotos_invitaciones_empresa (token, creada_por, empresa, para)
    values (v_token, auth.uid(), nullif(trim(coalesce(p_empresa, '')), ''), nullif(trim(coalesce(p_para, '')), ''));
  return (select json_build_object('token', token, 'empresa', empresa, 'para', para, 'vence_at', vence_at) from fotos_invitaciones_empresa where token = v_token);
end $$;
revoke all on function fotos_invitar_empresa(text, text) from public, anon;
grant execute on function fotos_invitar_empresa(text, text) to authenticated;

-- ---------- 4. Que dice el enlace (antes de crear la cuenta: anon) ----------
create or replace function fotos_empresa_invitacion_info(p_token text)
returns json language plpgsql security definer set search_path = public as $$
declare v fotos_invitaciones_empresa%rowtype;
begin
  select * into v from fotos_invitaciones_empresa where token = lower(trim(coalesce(p_token, '')));
  if v.token is null then return json_build_object('estado', 'no_existe'); end if;
  return json_build_object('empresa', v.empresa, 'para', v.para,
    'estado', case when v.anulada_at is not null then 'anulada' when v.usada_at is not null then 'usada'
                   when v.vence_at < now() then 'vencida' else 'valida' end);
end $$;
revoke all on function fotos_empresa_invitacion_info(text) from public;
grant execute on function fotos_empresa_invitacion_info(text) to anon, authenticated;

-- ---------- 5. Usar el enlace: crea la empresa y la cuenta queda de manager ----------
-- Igual que create_company (codigo de equipo de 6 letras, unico), pero con el enlace de por medio.
create or replace function fotos_crear_empresa(p_token text, p_empresa text, p_nombre text default null)
returns json language plpgsql security definer set search_path = public as $$
declare v fotos_invitaciones_empresa%rowtype; v_prof profiles%rowtype; v_code text; v_id uuid; v_nom text; v_emp text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into v from fotos_invitaciones_empresa where token = lower(trim(coalesce(p_token, ''))) for update;
  if v.token is null then raise exception 'empresa_no_existe'; end if;
  select * into v_prof from profiles where id = auth.uid();
  -- Abrio el enlace otra vez despues de crearla: entra a la que ya creo.
  if v.usada_at is not null and v.usada_por = auth.uid() and v_prof.company_id = v.company_id then
    return json_build_object('company_id', v.company_id, 'role', v_prof.role, 'status', coalesce(v_prof.status, 'active'), 'name', v.empresa_creada, 'ya_era', true);
  end if;
  if v_prof.id is not null then raise exception 'ya_tiene_empresa'; end if;   -- ya es de una empresa: no se mueve
  if v.anulada_at is not null then raise exception 'empresa_anulada'; end if;
  if v.usada_at is not null then raise exception 'empresa_usada'; end if;
  if v.vence_at < now() then raise exception 'empresa_vencida'; end if;
  v_emp := nullif(trim(coalesce(p_empresa, '')), '');
  if v_emp is null or length(v_emp) < 2 then raise exception 'falta_nombre_empresa'; end if;
  v_emp := left(v_emp, 80);
  v_nom := nullif(trim(coalesce(p_nombre, '')), '');
  loop
    v_code := upper(substr(md5(random()::text), 1, 6));
    exit when not exists (select 1 from companies where join_code = v_code);
  end loop;
  insert into companies (name, join_code) values (v_emp, v_code) returning id into v_id;
  -- Cuenta nueva = perfil nuevo (insert). Ninguna cuenta del sistema tiene perfil sin empresa, asi que no se toca el
  -- guardia de perfiles; si algun dia existiera una asi, el guardia frena y no se crea nada (todo es una transaccion).
  insert into profiles (id, company_id, role, full_name, status) values (auth.uid(), v_id, 'manager', v_nom, 'active');
  update fotos_invitaciones_empresa set usada_por = auth.uid(), usada_at = now(), company_id = v_id, empresa_creada = v_emp where token = v.token;
  return json_build_object('company_id', v_id, 'role', 'manager', 'status', 'active', 'name', v_emp, 'join_code', v_code);
end $$;
revoke all on function fotos_crear_empresa(text, text, text) from public, anon;
grant execute on function fotos_crear_empresa(text, text, text) to authenticated;

-- ---------- 6. Anular un enlace sin usar (solo el dueno) ----------
create or replace function fotos_anular_invitacion_empresa(p_token text)
returns json language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not exists(select 1 from fotos_plataforma where user_id = auth.uid()) then raise exception 'solo_dueno'; end if;
  update fotos_invitaciones_empresa set anulada_at = now() where token = p_token and usada_at is null and anulada_at is null;
  if not found then raise exception 'no_se_puede'; end if;
  return json_build_object('token', p_token, 'estado', 'anulada');
end $$;
revoke all on function fotos_anular_invitacion_empresa(text) from public, anon;
grant execute on function fotos_anular_invitacion_empresa(text) to authenticated;

-- ---------- 7. fotos-10: el caso "lo sacaron del equipo" con un mensaje claro ----------
create or replace function fotos_aceptar_invitacion(p_token text, p_name text default null)
returns json language plpgsql security definer set search_path = public as $$
declare v fotos_invitaciones%rowtype; v_prof profiles%rowtype; v_correo text; v_nom text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into v from fotos_invitaciones where token = lower(trim(coalesce(p_token, ''))) for update;
  if v.token is null then raise exception 'invitacion_no_existe'; end if;
  select * into v_prof from profiles where id = auth.uid();
  if v_prof.id is not null and v_prof.company_id = v.company_id and (v_prof.role = 'manager' or coalesce(v_prof.status, 'active') = 'active') then
    return json_build_object('company_id', v_prof.company_id, 'status', coalesce(v_prof.status, 'active'), 'role', v_prof.role, 'ya_era', true);
  end if;
  if v_prof.id is not null and v_prof.company_id is not null and v_prof.company_id <> v.company_id then raise exception 'otra_empresa'; end if;
  -- Era del equipo y lo pausaron o sacaron: eso lo decide el manager (el guardia de perfiles no deja cambiarlo aqui).
  if v_prof.id is not null then raise exception 'cuenta_fuera'; end if;
  if v.anulada_at is not null then raise exception 'invitacion_anulada'; end if;
  if v.usada_at is not null and v.usada_por is distinct from auth.uid() then raise exception 'invitacion_usada'; end if;
  if v.vence_at < now() then raise exception 'invitacion_vencida'; end if;
  select email into v_correo from auth.users where id = auth.uid();
  v_nom := coalesce(nullif(trim(coalesce(p_name, '')), ''), v_prof.full_name, v.nombre);
  insert into profiles (id, company_id, role, full_name, status) values (auth.uid(), v.company_id, 'crew', v_nom, 'active');
  update fotos_invitaciones set usada_por = auth.uid(), usada_nombre = v_nom, usada_at = coalesce(usada_at, now()) where token = v.token;
  insert into fotos_solicitudes (user_id, company_id, nombre, correo, estado, decidido_at, decidido_por)
    values (auth.uid(), v.company_id, v_nom, v_correo, 'aprobada', now(), v.creada_por)
    on conflict (user_id) do update set company_id = v.company_id, estado = 'aprobada', decidido_at = now(), decidido_por = v.creada_por;
  return json_build_object('company_id', v.company_id, 'status', 'active', 'role', 'crew');
end $$;
revoke all on function fotos_aceptar_invitacion(text, text) from public, anon;
grant execute on function fotos_aceptar_invitacion(text, text) to authenticated;

notify pgrst, 'reload schema';

-- ---------- COMPROBACION (una fila; lo esperado al lado) ----------
select (select count(*) from fotos_plataforma) as duenos,                                                                     -- 1
       (select count(*) from pg_policies where tablename in ('fotos_plataforma', 'fotos_invitaciones_empresa')) as politicas,  -- 2
       has_table_privilege('anon', 'fotos_invitaciones_empresa', 'select') as anon_lee,                                       -- false
       has_function_privilege('anon', 'fotos_invitar_empresa(text,text)', 'execute') as anon_invita,                          -- false
       has_function_privilege('anon', 'fotos_empresa_invitacion_info(text)', 'execute') as anon_pregunta,                     -- true
       has_function_privilege('anon', 'fotos_crear_empresa(text,text,text)', 'execute') as anon_crea,                         -- false
       has_function_privilege('authenticated', 'fotos_crear_empresa(text,text,text)', 'execute') as cuenta_crea,              -- true
       has_function_privilege('anon', 'fotos_soy_dueno()', 'execute') as anon_dueno,                                          -- false
       has_function_privilege('authenticated', 'create_company(text)', 'execute') as create_company_abierto,                  -- false
       (select bool_and(prosecdef) from pg_proc where proname in ('fotos_invitar_empresa', 'fotos_empresa_invitacion_info',
          'fotos_crear_empresa', 'fotos_anular_invitacion_empresa', 'fotos_soy_dueno', 'fotos_aceptar_invitacion')) as definer; -- true
