-- =====================================================================
--  fotos-04-niveles.sql  -  SCANOVA: niveles y cuartos de cada proyecto (12 oct 2026)
--  Su diseno: cada proyecto tiene niveles (Basement, First Floor...) y dentro cuartos
--  (Kitchen, Living Room...). Cada foto puede quedar en un nivel y en un cuarto.
--  Tambien: cliente (persona), encargado (Project Manager) y fecha de inicio del proyecto.
--  Solo agrega: nada existente se borra ni cambia de valor. Archivo en ASCII puro.
-- =====================================================================
create table if not exists fotos_niveles (
  id          uuid primary key default gen_random_uuid(),
  trabajo_id  uuid not null references fotos_trabajos(id) on delete cascade,
  company_id  uuid not null default my_company() references companies(id) on delete cascade,
  created_by  uuid not null default auth.uid() references auth.users(id),
  created_at  timestamptz not null default now(),
  nombre      text not null check (length(trim(nombre)) between 1 and 60),
  descripcion text,
  orden       int not null default 0
);
create index if not exists fotos_niveles_trabajo_idx on fotos_niveles (trabajo_id, orden, created_at);

create table if not exists fotos_cuartos (
  id          uuid primary key default gen_random_uuid(),
  trabajo_id  uuid not null references fotos_trabajos(id) on delete cascade,
  nivel_id    uuid not null references fotos_niveles(id) on delete cascade,
  company_id  uuid not null default my_company() references companies(id) on delete cascade,
  created_by  uuid not null default auth.uid() references auth.users(id),
  created_at  timestamptz not null default now(),
  nombre      text not null check (length(trim(nombre)) between 1 and 60),
  tipo        text,
  notas       text,
  orden       int not null default 0
);
create index if not exists fotos_cuartos_nivel_idx on fotos_cuartos (nivel_id, orden, created_at);

-- La foto puede quedar en un nivel y en un cuarto. Si se borra el cuarto o el nivel, la foto se queda (sin cuarto).
alter table fotos_fotos add column if not exists nivel_id uuid references fotos_niveles(id) on delete set null;
alter table fotos_fotos add column if not exists cuarto_id uuid references fotos_cuartos(id) on delete set null;
create index if not exists fotos_fotos_cuarto_idx on fotos_fotos (cuarto_id);

-- Datos del proyecto que ensena el diseno.
alter table fotos_trabajos add column if not exists cliente_nombre text;
alter table fotos_trabajos add column if not exists encargado text;
alter table fotos_trabajos add column if not exists fecha_inicio date;

-- El proyecto tiene que ser de la misma empresa (nadie cuelga niveles en un proyecto ajeno).
create or replace function fotos_trabajo_mio(p uuid) returns boolean
  language sql stable security definer set search_path = public as
  $$ select exists (select 1 from fotos_trabajos t where t.id = p and t.company_id = my_company()) $$;
revoke all on function fotos_trabajo_mio(uuid) from public, anon;
grant execute on function fotos_trabajo_mio(uuid) to authenticated;

-- Candados: lee y crea cualquiera activo de la empresa; cambia y borra el manager o quien lo creo.
alter table fotos_niveles enable row level security;
alter table fotos_cuartos enable row level security;
revoke all on fotos_niveles from anon;
revoke all on fotos_cuartos from anon;
grant select, insert, update, delete on fotos_niveles to authenticated;
grant select, insert, update, delete on fotos_cuartos to authenticated;

drop policy if exists "fotos_niveles lee" on fotos_niveles;
create policy "fotos_niveles lee" on fotos_niveles for select to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_niveles crea" on fotos_niveles;
create policy "fotos_niveles crea" on fotos_niveles for insert to authenticated
  with check (company_id = my_company() and created_by = auth.uid() and fotos_trabajo_mio(trabajo_id) and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_niveles cambia" on fotos_niveles;
create policy "fotos_niveles cambia" on fotos_niveles for update to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')))
  with check (company_id = my_company());
drop policy if exists "fotos_niveles borra" on fotos_niveles;
create policy "fotos_niveles borra" on fotos_niveles for delete to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')));

drop policy if exists "fotos_cuartos lee" on fotos_cuartos;
create policy "fotos_cuartos lee" on fotos_cuartos for select to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_cuartos crea" on fotos_cuartos;
create policy "fotos_cuartos crea" on fotos_cuartos for insert to authenticated
  with check (company_id = my_company() and created_by = auth.uid() and fotos_trabajo_mio(trabajo_id) and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_cuartos cambia" on fotos_cuartos;
create policy "fotos_cuartos cambia" on fotos_cuartos for update to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')))
  with check (company_id = my_company());
drop policy if exists "fotos_cuartos borra" on fotos_cuartos;
create policy "fotos_cuartos borra" on fotos_cuartos for delete to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')));

notify pgrst, 'reload schema';

-- ---------- COMPROBACION (lo esperado al lado) ----------
select (select count(*) from information_schema.tables where table_name in ('fotos_niveles','fotos_cuartos')) as tablas,                        -- 2
       (select count(*) from pg_policies where tablename in ('fotos_niveles','fotos_cuartos')) as politicas,                                    -- 8
       (select count(*) from pg_tables where tablename in ('fotos_niveles','fotos_cuartos') and rowsecurity) as con_candado,                     -- 2
       (select count(*) from information_schema.columns where table_name = 'fotos_fotos' and column_name in ('nivel_id','cuarto_id')) as foto_cols, -- 2
       (select count(*) from information_schema.columns where table_name = 'fotos_trabajos' and column_name in ('cliente_nombre','encargado','fecha_inicio')) as trabajo_cols, -- 3
       has_table_privilege('anon', 'fotos_cuartos', 'select') as anon_lee;                                                                     -- false
