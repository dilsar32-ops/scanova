-- =====================================================================
--  fotos-02-aprobacion.sql  ·  SCANOVA — entrar con aprobación del manager (12 oct 2026)
--  Amilcar: "solo van a poder entrar quien yo autorice" → "con aprobación".
--  Quien crea cuenta con el código del equipo queda EN ESPERA (profiles.status = 'paused', el
--  mismo estado que Field Reports usa para "Pausado": sin ver nada). El manager aprueba o rechaza
--  desde Scanova. Nada de Field Reports se toca: solo una tabla y dos funciones con prefijo fotos_.
-- =====================================================================

-- ---------- 1. La solicitud (para que el manager vea nombre y correo, y quede historial) ----------
create table if not exists fotos_solicitudes (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  company_id   uuid not null references companies(id) on delete cascade,
  nombre       text,
  correo       text,
  estado       text not null default 'pendiente' check (estado in ('pendiente','aprobada','rechazada')),
  created_at   timestamptz not null default now(),
  decidido_at  timestamptz,
  decidido_por uuid references auth.users(id)
);
alter table fotos_solicitudes enable row level security;
revoke all on fotos_solicitudes from anon;
grant select on fotos_solicitudes to authenticated;
drop policy if exists "fotos_solicitudes manager lee" on fotos_solicitudes;
create policy "fotos_solicitudes manager lee" on fotos_solicitudes for select to authenticated
  using (company_id = my_company() and my_role() = 'manager');
drop policy if exists "fotos_solicitudes propia" on fotos_solicitudes;
create policy "fotos_solicitudes propia" on fotos_solicitudes for select to authenticated
  using (user_id = auth.uid());
-- Sin insert/update/delete para la app: solo las funciones de abajo escriben.

-- ---------- 2. Pedir entrada: como join_company, pero la cuenta nace EN ESPERA ----------
create or replace function fotos_pedir_entrada(p_code text, p_name text default null)
returns json language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_name text; v_prof profiles%rowtype; v_correo text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into v_prof from profiles where id = auth.uid();
  -- Ya es de una empresa (manager o crew activo/pausado): no se toca nada, solo se informa.
  if v_prof.id is not null and v_prof.company_id is not null then
    return json_build_object('company_id', v_prof.company_id, 'status', coalesce(v_prof.status,'active'), 'role', v_prof.role,
      'pendiente', exists(select 1 from fotos_solicitudes s where s.user_id = auth.uid() and s.estado = 'pendiente'));
  end if;
  select id, name into v_id, v_name from companies where join_code = upper(regexp_replace(coalesce(p_code,''), '\s', '', 'g'));
  if v_id is null then raise exception 'codigo_invalido'; end if;
  select email into v_correo from auth.users where id = auth.uid();
  insert into profiles (id, company_id, role, full_name, status) values (auth.uid(), v_id, 'crew', p_name, 'paused')
    on conflict (id) do update set company_id = v_id, full_name = coalesce(excluded.full_name, profiles.full_name), status = 'paused';
  insert into fotos_solicitudes (user_id, company_id, nombre, correo) values (auth.uid(), v_id, p_name, v_correo)
    on conflict (user_id) do update set company_id = v_id, nombre = coalesce(excluded.nombre, fotos_solicitudes.nombre), correo = excluded.correo,
      estado = 'pendiente', created_at = now(), decidido_at = null, decidido_por = null;
  return json_build_object('company_id', v_id, 'status', 'paused', 'role', 'crew', 'pendiente', true, 'empresa', v_name);
end $$;
revoke all on function fotos_pedir_entrada(text, text) from public, anon;
grant execute on function fotos_pedir_entrada(text, text) to authenticated;

-- ---------- 3. Decidir: solo el manager de esa empresa. Aprobar = activo; rechazar = sacado ----------
create or replace function fotos_decidir_entrada(p_user uuid, p_aprobar boolean)
returns json language plpgsql security definer set search_path = public as $$
declare v_sol fotos_solicitudes%rowtype;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if my_role() <> 'manager' then raise exception 'solo_manager'; end if;
  select * into v_sol from fotos_solicitudes where user_id = p_user;
  if v_sol.user_id is null or v_sol.company_id <> my_company() then raise exception 'solicitud_no_encontrada'; end if;
  update profiles set status = case when p_aprobar then 'active' else 'removed' end
    where id = p_user and company_id = my_company() and role <> 'manager';
  update fotos_solicitudes set estado = case when p_aprobar then 'aprobada' else 'rechazada' end, decidido_at = now(), decidido_por = auth.uid()
    where user_id = p_user;
  return json_build_object('user_id', p_user, 'estado', case when p_aprobar then 'aprobada' else 'rechazada' end);
end $$;
revoke all on function fotos_decidir_entrada(uuid, boolean) from public, anon;
grant execute on function fotos_decidir_entrada(uuid, boolean) to authenticated;

notify pgrst, 'reload schema';

-- ---------- COMPROBACION (una fila; lo esperado al lado) ----------
select (select count(*) from information_schema.tables where table_name = 'fotos_solicitudes') as tabla,                       -- 1
       (select count(*) from pg_policies where tablename = 'fotos_solicitudes') as politicas,                                   -- 2
       has_function_privilege('anon', 'fotos_pedir_entrada(text,text)', 'execute') as anon_pide,                                -- false
       has_function_privilege('authenticated', 'fotos_pedir_entrada(text,text)', 'execute') as equipo_pide,                     -- true
       has_function_privilege('anon', 'fotos_decidir_entrada(uuid,boolean)', 'execute') as anon_decide,                         -- false
       (select prosecdef from pg_proc where proname = 'fotos_decidir_entrada') as decide_definer;                                -- true
