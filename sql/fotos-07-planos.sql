-- =====================================================================
--  fotos-07-planos.sql  -  SCANOVA: planos de cada piso (13 oct 2026)
--  Su diseno: pestana Floor Plan. Cada escaneo con el LiDAR del iPhone se guarda aqui,
--  amarrado al proyecto y al piso (nivel). Un escaneo nuevo NO borra el anterior: se ve
--  el mas reciente de cada piso y los viejos quedan de historial.
--  Solo agrega: nada existente se borra ni cambia. Archivo en ASCII puro.
-- =====================================================================
create table if not exists fotos_planos (
  id           uuid primary key default gen_random_uuid(),
  trabajo_id   uuid not null references fotos_trabajos(id) on delete cascade,
  nivel_id     uuid references fotos_niveles(id) on delete set null,
  company_id   uuid not null default my_company() references companies(id) on delete cascade,
  created_by   uuid not null default auth.uid() references auth.users(id),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  data         jsonb not null,
  area_sqft    numeric,
  cuartos      int,
  muros_ext_ft numeric,
  techo_ft     numeric,
  borrado_at   timestamptz,
  constraint fotos_planos_tamano check (octet_length(data::text) < 3000000)
);
create index if not exists fotos_planos_trabajo_idx on fotos_planos (trabajo_id, nivel_id, created_at desc);

alter table fotos_planos enable row level security;
revoke all on fotos_planos from anon;
grant select, insert, update on fotos_planos to authenticated;

-- Lee y crea cualquiera activo de la empresa; cambia (o marca borrado) el manager o quien lo escaneo. Nadie borra la fila.
drop policy if exists "fotos_planos lee" on fotos_planos;
create policy "fotos_planos lee" on fotos_planos for select to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_planos crea" on fotos_planos;
create policy "fotos_planos crea" on fotos_planos for insert to authenticated
  with check (company_id = my_company() and created_by = auth.uid() and fotos_trabajo_mio(trabajo_id) and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_planos cambia" on fotos_planos;
create policy "fotos_planos cambia" on fotos_planos for update to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')))
  with check (company_id = my_company());

notify pgrst, 'reload schema';

-- ---------- COMPROBACION (lo esperado al lado) ----------
select (select count(*) from information_schema.tables where table_name = 'fotos_planos') as tabla,          -- 1
       (select count(*) from pg_policies where tablename = 'fotos_planos') as politicas,                    -- 3
       (select count(*) from pg_tables where tablename = 'fotos_planos' and rowsecurity) as con_candado,     -- 1
       has_table_privilege('anon', 'fotos_planos', 'select') as anon_lee;                                   -- false
