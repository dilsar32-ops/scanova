-- =====================================================================
--  fotos-09-drylogs.sql  -  SCANOVA: lecturas del Dry Log (su diseno del 14 oct 2026)
--  En el telefono: se escoge nivel y cuarto, se toma la foto del medidor, la app lee el
--  numero (lector de Claude, la persona lo confirma) y se guarda. Despues se anota el
--  equipo de ese cuarto ("No Equipment" guarda cero) para no caminar dos veces la casa.
--    fotos_drylog_lecturas  una lectura: cuarto, material, donde, numero, la foto que la prueba,
--                           y lo que leyo la app (para saber si la persona lo corrigio)
--    fotos_drylog_equipos   el equipo de un cuarto un dia (cantidad 0 = "No Equipment")
--  Correr DESPUES de fotos-07-planos.sql. Solo agrega: nada existente se borra ni cambia.
--  (sql/fotos-08-secado.sql es un borrador viejo que NUNCA se corrio; no hace falta.)
--  Archivo en ASCII puro.
-- =====================================================================
create table if not exists fotos_drylog_lecturas (
  id            uuid primary key default gen_random_uuid(),
  trabajo_id    uuid not null references fotos_trabajos(id) on delete cascade,
  company_id    uuid not null default my_company() references companies(id) on delete cascade,
  created_by    uuid not null default auth.uid() references auth.users(id),
  created_at    timestamptz not null default now(),
  dia           date not null,
  nivel_id      uuid references fotos_niveles(id) on delete set null,
  cuarto_id     uuid references fotos_cuartos(id) on delete set null,
  cuarto_nombre text check (cuarto_nombre is null or length(cuarto_nombre) <= 80),
  material      text check (material is null or length(material) <= 60),
  ubicacion     text check (ubicacion is null or length(ubicacion) <= 120),
  valor         numeric not null check (valor >= 0 and valor <= 1000),
  unidad        text not null default '%' check (length(unidad) <= 12),
  foto_id       uuid,
  leido_texto   text check (leido_texto is null or length(leido_texto) <= 40),
  leido_por     text check (leido_por is null or length(leido_por) <= 40),
  corregido     boolean not null default false
);
create index if not exists fotos_drylog_lecturas_trabajo_idx on fotos_drylog_lecturas (trabajo_id, dia, created_at);

create table if not exists fotos_drylog_equipos (
  id            uuid primary key default gen_random_uuid(),
  trabajo_id    uuid not null references fotos_trabajos(id) on delete cascade,
  company_id    uuid not null default my_company() references companies(id) on delete cascade,
  created_by    uuid not null default auth.uid() references auth.users(id),
  created_at    timestamptz not null default now(),
  dia           date not null,
  nivel_id      uuid references fotos_niveles(id) on delete set null,
  cuarto_id     uuid references fotos_cuartos(id) on delete set null,
  cuarto_nombre text check (cuarto_nombre is null or length(cuarto_nombre) <= 80),
  tipo          text not null check (length(trim(tipo)) between 1 and 60),
  cantidad      int not null check (cantidad between 0 and 200)
);
create index if not exists fotos_drylog_equipos_trabajo_idx on fotos_drylog_equipos (trabajo_id, dia, created_at);

alter table fotos_drylog_lecturas enable row level security;
alter table fotos_drylog_equipos  enable row level security;
revoke all on fotos_drylog_lecturas from anon;
revoke all on fotos_drylog_equipos  from anon;
grant select, insert, update, delete on fotos_drylog_lecturas to authenticated;
grant select, insert, update, delete on fotos_drylog_equipos  to authenticated;

-- Lee y anota cualquiera activo de la empresa; corrige o borra el manager o quien lo anoto.
drop policy if exists "fotos_drylog_lecturas lee" on fotos_drylog_lecturas;
create policy "fotos_drylog_lecturas lee" on fotos_drylog_lecturas for select to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_drylog_lecturas crea" on fotos_drylog_lecturas;
create policy "fotos_drylog_lecturas crea" on fotos_drylog_lecturas for insert to authenticated
  with check (company_id = my_company() and created_by = auth.uid() and fotos_trabajo_mio(trabajo_id) and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_drylog_lecturas cambia" on fotos_drylog_lecturas;
create policy "fotos_drylog_lecturas cambia" on fotos_drylog_lecturas for update to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')))
  with check (company_id = my_company() and fotos_trabajo_mio(trabajo_id));
drop policy if exists "fotos_drylog_lecturas borra" on fotos_drylog_lecturas;
create policy "fotos_drylog_lecturas borra" on fotos_drylog_lecturas for delete to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')));

drop policy if exists "fotos_drylog_equipos lee" on fotos_drylog_equipos;
create policy "fotos_drylog_equipos lee" on fotos_drylog_equipos for select to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_drylog_equipos crea" on fotos_drylog_equipos;
create policy "fotos_drylog_equipos crea" on fotos_drylog_equipos for insert to authenticated
  with check (company_id = my_company() and created_by = auth.uid() and fotos_trabajo_mio(trabajo_id) and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_drylog_equipos cambia" on fotos_drylog_equipos;
create policy "fotos_drylog_equipos cambia" on fotos_drylog_equipos for update to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')))
  with check (company_id = my_company() and fotos_trabajo_mio(trabajo_id));
drop policy if exists "fotos_drylog_equipos borra" on fotos_drylog_equipos;
create policy "fotos_drylog_equipos borra" on fotos_drylog_equipos for delete to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')));

notify pgrst, 'reload schema';

-- ---------- COMPROBACION (lo esperado al lado) ----------
select (select count(*) from information_schema.tables where table_name like 'fotos_drylog_%') as tablas,          -- 2
       (select count(*) from pg_policies where tablename like 'fotos_drylog_%') as politicas,                         -- 8
       (select count(*) from pg_tables where tablename like 'fotos_drylog_%' and rowsecurity) as con_candado,          -- 2
       has_table_privilege('anon', 'fotos_drylog_lecturas', 'select') as anon_lee;                                   -- false
