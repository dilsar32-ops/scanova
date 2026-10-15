-- =====================================================================
--  fotos-12-medidas.sql  -  SCANOVA: la pestana Measurements (15 oct 2026)
--  Su pedido: "debes copiar todo lo que ya tenemos en Field Report de la carpeta de measurements".
--  Lo que se DEMOLIO, cuarto por cuarto, como en Field Reports: una fila por medida (un "corte"):
--    fotos_medidas         una medida: nivel y cuarto del proyecto, la parte (floor, wall, ceiling,
--                          kitchen, bathroom, materiales), el material, largo y ancho en pies
--                          (sin ancho = pies lineales; un material "por pieza" guarda la cantidad
--                          en el largo, igual que Field Reports), y si vino de la camara o a mano
--    fotos_medidas_notas   las notas de las medidas de un proyecto (una por proyecto)
--  Correr DESPUES de fotos-09-drylogs.sql. Solo agrega: nada existente se borra ni cambia.
--  Archivo en ASCII puro.
-- =====================================================================
create table if not exists fotos_medidas (
  id            uuid primary key default gen_random_uuid(),
  trabajo_id    uuid not null references fotos_trabajos(id) on delete cascade,
  company_id    uuid not null default my_company() references companies(id) on delete cascade,
  created_by    uuid not null default auth.uid() references auth.users(id),
  created_at    timestamptz not null default now(),
  nivel_id      uuid references fotos_niveles(id) on delete set null,
  cuarto_id     uuid references fotos_cuartos(id) on delete set null,
  nivel_nombre  text check (nivel_nombre is null or length(nivel_nombre) <= 80),
  cuarto_nombre text check (cuarto_nombre is null or length(cuarto_nombre) <= 80),
  seccion       text not null check (seccion in ('floor', 'wall', 'ceiling', 'kitchen', 'bathroom', 'materiales')),
  material      text not null check (length(trim(material)) between 1 and 80),
  largo         numeric not null check (largo > 0 and largo <= 10000),
  ancho         numeric check (ancho is null or (ancho > 0 and ancho <= 10000)),
  origen        text not null default 'mano' check (origen in ('mano', 'camara')),
  orden         bigint not null default 0
);
create index if not exists fotos_medidas_trabajo_idx on fotos_medidas (trabajo_id, orden, created_at);

create table if not exists fotos_medidas_notas (
  trabajo_id    uuid primary key references fotos_trabajos(id) on delete cascade,
  company_id    uuid not null default my_company() references companies(id) on delete cascade,
  created_by    uuid not null default auth.uid() references auth.users(id),
  updated_at    timestamptz not null default now(),
  texto         text not null default '' check (length(texto) <= 4000)
);

alter table fotos_medidas       enable row level security;
alter table fotos_medidas_notas enable row level security;
revoke all on fotos_medidas       from anon;
revoke all on fotos_medidas_notas from anon;
grant select, insert, update, delete on fotos_medidas       to authenticated;
grant select, insert, update, delete on fotos_medidas_notas to authenticated;

-- Lee y anota cualquiera activo de la empresa; corrige o borra el manager o quien la anoto (como el Dry Log).
drop policy if exists "fotos_medidas lee" on fotos_medidas;
create policy "fotos_medidas lee" on fotos_medidas for select to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_medidas crea" on fotos_medidas;
create policy "fotos_medidas crea" on fotos_medidas for insert to authenticated
  with check (company_id = my_company() and created_by = auth.uid() and fotos_trabajo_mio(trabajo_id) and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_medidas cambia" on fotos_medidas;
create policy "fotos_medidas cambia" on fotos_medidas for update to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')))
  -- Quien la anoto no puede pasarsela a otro (created_by): solo el manager la reasigna.
  with check (company_id = my_company() and fotos_trabajo_mio(trabajo_id) and (my_role() = 'manager' or created_by = auth.uid()));
drop policy if exists "fotos_medidas borra" on fotos_medidas;
create policy "fotos_medidas borra" on fotos_medidas for delete to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')));

-- Las notas son del proyecto: cualquiera activo de la empresa las escribe (una sola por proyecto).
drop policy if exists "fotos_medidas_notas lee" on fotos_medidas_notas;
create policy "fotos_medidas_notas lee" on fotos_medidas_notas for select to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_medidas_notas crea" on fotos_medidas_notas;
create policy "fotos_medidas_notas crea" on fotos_medidas_notas for insert to authenticated
  with check (company_id = my_company() and fotos_trabajo_mio(trabajo_id) and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_medidas_notas cambia" on fotos_medidas_notas;
create policy "fotos_medidas_notas cambia" on fotos_medidas_notas for update to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'))
  with check (company_id = my_company() and fotos_trabajo_mio(trabajo_id));

notify pgrst, 'reload schema';

-- ---------- COMPROBACION (lo esperado al lado) ----------
select (select count(*) from information_schema.tables where table_name in ('fotos_medidas', 'fotos_medidas_notas')) as tablas,   -- 2
       (select count(*) from pg_policies where tablename in ('fotos_medidas', 'fotos_medidas_notas')) as politicas,                -- 7
       (select count(*) from pg_tables where tablename in ('fotos_medidas', 'fotos_medidas_notas') and rowsecurity) as con_candado, -- 2
       has_table_privilege('anon', 'fotos_medidas', 'select') as anon_lee;                                                         -- false
