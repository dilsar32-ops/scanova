-- =====================================================================
--  fotos-05-detalles.sql  -  SCANOVA: "Project Details" de cada proyecto (12 oct 2026)
--  Su diseno: etiquetas de color (Edit Labels), descripcion, quienes trabajan en el
--  proyecto (Project Users), colaboradores de afuera, tareas y la conversacion.
--  Correr DESPUES de fotos-04-niveles.sql. Solo agrega. Archivo en ASCII puro.
-- =====================================================================
alter table fotos_trabajos add column if not exists etiquetas jsonb not null default '[]'::jsonb;
alter table fotos_trabajos add column if not exists descripcion text;

-- Quienes del equipo trabajan en el proyecto.
create table if not exists fotos_miembros (
  trabajo_id  uuid not null references fotos_trabajos(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  company_id  uuid not null default my_company() references companies(id) on delete cascade,
  created_by  uuid not null default auth.uid() references auth.users(id),
  created_at  timestamptz not null default now(),
  primary key (trabajo_id, user_id)
);

-- Gente de afuera: ajustador, duenio, contratista...
create table if not exists fotos_colaboradores (
  id          uuid primary key default gen_random_uuid(),
  trabajo_id  uuid not null references fotos_trabajos(id) on delete cascade,
  company_id  uuid not null default my_company() references companies(id) on delete cascade,
  created_by  uuid not null default auth.uid() references auth.users(id),
  created_at  timestamptz not null default now(),
  nombre      text not null check (length(trim(nombre)) between 1 and 80),
  empresa     text,
  rol         text,
  telefono    text,
  correo      text
);
create index if not exists fotos_colaboradores_trabajo_idx on fotos_colaboradores (trabajo_id, created_at);

create table if not exists fotos_tareas (
  id          uuid primary key default gen_random_uuid(),
  trabajo_id  uuid not null references fotos_trabajos(id) on delete cascade,
  company_id  uuid not null default my_company() references companies(id) on delete cascade,
  created_by  uuid not null default auth.uid() references auth.users(id),
  created_at  timestamptz not null default now(),
  texto       text not null check (length(trim(texto)) between 1 and 300),
  hecha       boolean not null default false,
  hecha_at    timestamptz,
  hecha_por   uuid references auth.users(id)
);
create index if not exists fotos_tareas_trabajo_idx on fotos_tareas (trabajo_id, created_at);

create table if not exists fotos_conversacion (
  id          uuid primary key default gen_random_uuid(),
  trabajo_id  uuid not null references fotos_trabajos(id) on delete cascade,
  company_id  uuid not null default my_company() references companies(id) on delete cascade,
  created_by  uuid not null default auth.uid() references auth.users(id),
  created_at  timestamptz not null default now(),
  texto       text not null check (length(trim(texto)) between 1 and 2000)
);
create index if not exists fotos_conversacion_trabajo_idx on fotos_conversacion (trabajo_id, created_at);

-- El proyecto tiene que ser de la misma empresa (nadie cuelga cosas en un proyecto ajeno).
create or replace function fotos_trabajo_mio(p uuid) returns boolean
  language sql stable security definer set search_path = public as
  $$ select exists (select 1 from fotos_trabajos t where t.id = p and t.company_id = my_company()) $$;
revoke all on function fotos_trabajo_mio(uuid) from public, anon;
grant execute on function fotos_trabajo_mio(uuid) to authenticated;
-- Quien creo el proyecto (para dejarle escoger a la gente del proyecto aunque no sea manager).
create or replace function fotos_trabajo_creador(p uuid) returns boolean
  language sql stable security definer set search_path = public as
  $$ select exists (select 1 from fotos_trabajos t where t.id = p and t.created_by = auth.uid()) $$;
revoke all on function fotos_trabajo_creador(uuid) from public, anon;
grant execute on function fotos_trabajo_creador(uuid) to authenticated;

alter table fotos_miembros enable row level security;
alter table fotos_colaboradores enable row level security;
alter table fotos_tareas enable row level security;
alter table fotos_conversacion enable row level security;
revoke all on fotos_miembros from anon;
revoke all on fotos_colaboradores from anon;
revoke all on fotos_tareas from anon;
revoke all on fotos_conversacion from anon;
grant select, insert, delete on fotos_miembros to authenticated;
grant select, insert, update, delete on fotos_colaboradores to authenticated;
grant select, insert, update, delete on fotos_tareas to authenticated;
grant select, insert, delete on fotos_conversacion to authenticated;

-- Project Users: lo ve el equipo; lo escoge el manager o quien creo el proyecto.
drop policy if exists "fotos_miembros lee" on fotos_miembros;
create policy "fotos_miembros lee" on fotos_miembros for select to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_miembros pone" on fotos_miembros;
create policy "fotos_miembros pone" on fotos_miembros for insert to authenticated
  with check (company_id = my_company() and created_by = auth.uid() and fotos_trabajo_mio(trabajo_id)
              and (my_role() = 'manager' or (my_status() = 'active' and fotos_trabajo_creador(trabajo_id))));
drop policy if exists "fotos_miembros quita" on fotos_miembros;
create policy "fotos_miembros quita" on fotos_miembros for delete to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (my_status() = 'active' and fotos_trabajo_creador(trabajo_id))));

-- Colaboradores: cualquiera activo los agrega; cambia/borra el manager o quien lo agrego.
drop policy if exists "fotos_colaboradores lee" on fotos_colaboradores;
create policy "fotos_colaboradores lee" on fotos_colaboradores for select to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_colaboradores crea" on fotos_colaboradores;
create policy "fotos_colaboradores crea" on fotos_colaboradores for insert to authenticated
  with check (company_id = my_company() and created_by = auth.uid() and fotos_trabajo_mio(trabajo_id) and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_colaboradores cambia" on fotos_colaboradores;
create policy "fotos_colaboradores cambia" on fotos_colaboradores for update to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')))
  with check (company_id = my_company());
drop policy if exists "fotos_colaboradores borra" on fotos_colaboradores;
create policy "fotos_colaboradores borra" on fotos_colaboradores for delete to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')));

-- Tareas: cualquiera activo las crea y las marca hechas; borra el manager o quien la creo.
drop policy if exists "fotos_tareas lee" on fotos_tareas;
create policy "fotos_tareas lee" on fotos_tareas for select to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_tareas crea" on fotos_tareas;
create policy "fotos_tareas crea" on fotos_tareas for insert to authenticated
  with check (company_id = my_company() and created_by = auth.uid() and fotos_trabajo_mio(trabajo_id) and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_tareas cambia" on fotos_tareas;
create policy "fotos_tareas cambia" on fotos_tareas for update to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'))
  with check (company_id = my_company());
drop policy if exists "fotos_tareas borra" on fotos_tareas;
create policy "fotos_tareas borra" on fotos_tareas for delete to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')));

-- Conversacion: cualquiera activo escribe; borra el manager o quien lo escribio. No se editan.
drop policy if exists "fotos_conversacion lee" on fotos_conversacion;
create policy "fotos_conversacion lee" on fotos_conversacion for select to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_conversacion crea" on fotos_conversacion;
create policy "fotos_conversacion crea" on fotos_conversacion for insert to authenticated
  with check (company_id = my_company() and created_by = auth.uid() and fotos_trabajo_mio(trabajo_id) and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_conversacion borra" on fotos_conversacion;
create policy "fotos_conversacion borra" on fotos_conversacion for delete to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')));

notify pgrst, 'reload schema';

-- ---------- COMPROBACION (lo esperado al lado) ----------
select (select count(*) from information_schema.tables where table_name in ('fotos_miembros','fotos_colaboradores','fotos_tareas','fotos_conversacion')) as tablas, -- 4
       (select count(*) from pg_policies where tablename in ('fotos_miembros','fotos_colaboradores','fotos_tareas','fotos_conversacion')) as politicas,              -- 14
       (select count(*) from pg_tables where tablename in ('fotos_miembros','fotos_colaboradores','fotos_tareas','fotos_conversacion') and rowsecurity) as con_candado, -- 4
       (select count(*) from information_schema.columns where table_name = 'fotos_trabajos' and column_name in ('etiquetas','descripcion')) as trabajo_cols,   -- 2
       has_table_privilege('anon', 'fotos_conversacion', 'select') as anon_lee,                                                                             -- false
       has_function_privilege('anon', 'fotos_trabajo_mio(uuid)', 'execute') as anon_funcion;                                                               -- false
