-- =====================================================================
--  fotos-08-secado.sql  -  SCANOVA: pestana Dry Log de cada proyecto (14 oct 2026)
--  Su pedido: "esta aplicacion es para companias de water damage: necesitamos una
--  seccion de dry logs" (despues de Photos, antes de Floor Plan).
--  Cuatro tablas, como un registro de secado de verdad:
--    fotos_secado_puntos   puntos de humedad (cuarto, superficie, material, donde, meta de seco)
--    fotos_secado_lecturas una lectura por punto por dia
--    fotos_secado_ambiente temperatura y humedad relativa por lugar por dia (los GPP los calcula la app)
--    fotos_secado_equipos  equipo puesto: tipo, cuantos, cuarto, puesto y quitado
--  Correr DESPUES de fotos-07-planos.sql. Solo agrega: nada existente se borra ni cambia.
--  Archivo en ASCII puro.
-- =====================================================================
create table if not exists fotos_secado_puntos (
  id          uuid primary key default gen_random_uuid(),
  trabajo_id  uuid not null references fotos_trabajos(id) on delete cascade,
  company_id  uuid not null default my_company() references companies(id) on delete cascade,
  created_by  uuid not null default auth.uid() references auth.users(id),
  created_at  timestamptz not null default now(),
  cuarto_id   uuid references fotos_cuartos(id) on delete set null,
  lugar       text check (lugar is null or length(lugar) <= 80),
  superficie  text not null check (superficie in ('Floor', 'Wall', 'Ceiling')),
  material    text not null check (length(trim(material)) between 1 and 60),
  ubicacion   text check (ubicacion is null or length(ubicacion) <= 120),
  meta        numeric check (meta is null or (meta >= 0 and meta <= 1000))
);
create index if not exists fotos_secado_puntos_trabajo_idx on fotos_secado_puntos (trabajo_id, created_at);

create table if not exists fotos_secado_lecturas (
  id          uuid primary key default gen_random_uuid(),
  punto_id    uuid not null references fotos_secado_puntos(id) on delete cascade,
  trabajo_id  uuid not null references fotos_trabajos(id) on delete cascade,
  company_id  uuid not null default my_company() references companies(id) on delete cascade,
  created_by  uuid not null default auth.uid() references auth.users(id),
  created_at  timestamptz not null default now(),
  dia         date not null,
  valor       numeric not null check (valor >= 0 and valor <= 1000),
  constraint fotos_secado_lecturas_un_dia unique (punto_id, dia)
);
create index if not exists fotos_secado_lecturas_trabajo_idx on fotos_secado_lecturas (trabajo_id, dia);

create table if not exists fotos_secado_ambiente (
  id          uuid primary key default gen_random_uuid(),
  trabajo_id  uuid not null references fotos_trabajos(id) on delete cascade,
  company_id  uuid not null default my_company() references companies(id) on delete cascade,
  created_by  uuid not null default auth.uid() references auth.users(id),
  created_at  timestamptz not null default now(),
  dia         date not null,
  lugar       text not null check (length(trim(lugar)) between 1 and 80),
  temp_f      numeric not null check (temp_f >= -40 and temp_f <= 160),
  rh          numeric not null check (rh >= 0 and rh <= 100),
  constraint fotos_secado_ambiente_un_dia unique (trabajo_id, dia, lugar)
);
create index if not exists fotos_secado_ambiente_trabajo_idx on fotos_secado_ambiente (trabajo_id, dia);

create table if not exists fotos_secado_equipos (
  id          uuid primary key default gen_random_uuid(),
  trabajo_id  uuid not null references fotos_trabajos(id) on delete cascade,
  company_id  uuid not null default my_company() references companies(id) on delete cascade,
  created_by  uuid not null default auth.uid() references auth.users(id),
  created_at  timestamptz not null default now(),
  cuarto_id   uuid references fotos_cuartos(id) on delete set null,
  lugar       text check (lugar is null or length(lugar) <= 80),
  tipo        text not null check (length(trim(tipo)) between 1 and 60),
  cantidad    int not null check (cantidad between 1 and 200),
  puesto      date not null,
  quitado     date,
  constraint fotos_secado_equipos_fechas check (quitado is null or quitado >= puesto)
);
create index if not exists fotos_secado_equipos_trabajo_idx on fotos_secado_equipos (trabajo_id, puesto);

alter table fotos_secado_puntos   enable row level security;
alter table fotos_secado_lecturas enable row level security;
alter table fotos_secado_ambiente enable row level security;
alter table fotos_secado_equipos  enable row level security;
revoke all on fotos_secado_puntos   from anon;
revoke all on fotos_secado_lecturas from anon;
revoke all on fotos_secado_ambiente from anon;
revoke all on fotos_secado_equipos  from anon;
grant select, insert, update, delete on fotos_secado_puntos   to authenticated;
grant select, insert, update, delete on fotos_secado_lecturas to authenticated;
grant select, insert, update, delete on fotos_secado_ambiente to authenticated;
grant select, insert, update, delete on fotos_secado_equipos  to authenticated;

-- Las cuatro con la misma regla: lee y anota cualquiera activo de la empresa (la cuadrilla toma las
-- lecturas cada dia y corrige un numero mal puesto); borra el manager o quien lo anoto.
drop policy if exists "fotos_secado_puntos lee" on fotos_secado_puntos;
create policy "fotos_secado_puntos lee" on fotos_secado_puntos for select to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_secado_puntos crea" on fotos_secado_puntos;
create policy "fotos_secado_puntos crea" on fotos_secado_puntos for insert to authenticated
  with check (company_id = my_company() and created_by = auth.uid() and fotos_trabajo_mio(trabajo_id) and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_secado_puntos cambia" on fotos_secado_puntos;
create policy "fotos_secado_puntos cambia" on fotos_secado_puntos for update to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'))
  with check (company_id = my_company() and fotos_trabajo_mio(trabajo_id));
drop policy if exists "fotos_secado_puntos borra" on fotos_secado_puntos;
create policy "fotos_secado_puntos borra" on fotos_secado_puntos for delete to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')));

drop policy if exists "fotos_secado_lecturas lee" on fotos_secado_lecturas;
create policy "fotos_secado_lecturas lee" on fotos_secado_lecturas for select to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_secado_lecturas crea" on fotos_secado_lecturas;
create policy "fotos_secado_lecturas crea" on fotos_secado_lecturas for insert to authenticated
  with check (company_id = my_company() and created_by = auth.uid() and fotos_trabajo_mio(trabajo_id) and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_secado_lecturas cambia" on fotos_secado_lecturas;
create policy "fotos_secado_lecturas cambia" on fotos_secado_lecturas for update to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'))
  with check (company_id = my_company() and fotos_trabajo_mio(trabajo_id));
drop policy if exists "fotos_secado_lecturas borra" on fotos_secado_lecturas;
create policy "fotos_secado_lecturas borra" on fotos_secado_lecturas for delete to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'));

drop policy if exists "fotos_secado_ambiente lee" on fotos_secado_ambiente;
create policy "fotos_secado_ambiente lee" on fotos_secado_ambiente for select to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_secado_ambiente crea" on fotos_secado_ambiente;
create policy "fotos_secado_ambiente crea" on fotos_secado_ambiente for insert to authenticated
  with check (company_id = my_company() and created_by = auth.uid() and fotos_trabajo_mio(trabajo_id) and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_secado_ambiente cambia" on fotos_secado_ambiente;
create policy "fotos_secado_ambiente cambia" on fotos_secado_ambiente for update to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'))
  with check (company_id = my_company() and fotos_trabajo_mio(trabajo_id));
drop policy if exists "fotos_secado_ambiente borra" on fotos_secado_ambiente;
create policy "fotos_secado_ambiente borra" on fotos_secado_ambiente for delete to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'));

drop policy if exists "fotos_secado_equipos lee" on fotos_secado_equipos;
create policy "fotos_secado_equipos lee" on fotos_secado_equipos for select to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_secado_equipos crea" on fotos_secado_equipos;
create policy "fotos_secado_equipos crea" on fotos_secado_equipos for insert to authenticated
  with check (company_id = my_company() and created_by = auth.uid() and fotos_trabajo_mio(trabajo_id) and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_secado_equipos cambia" on fotos_secado_equipos;
create policy "fotos_secado_equipos cambia" on fotos_secado_equipos for update to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or my_status() = 'active'))
  with check (company_id = my_company() and fotos_trabajo_mio(trabajo_id));
drop policy if exists "fotos_secado_equipos borra" on fotos_secado_equipos;
create policy "fotos_secado_equipos borra" on fotos_secado_equipos for delete to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')));

notify pgrst, 'reload schema';

-- ---------- COMPROBACION (lo esperado al lado) ----------
select (select count(*) from information_schema.tables where table_name like 'fotos_secado_%') as tablas,                 -- 4
       (select count(*) from pg_policies where tablename like 'fotos_secado_%') as politicas,                                -- 16
       (select count(*) from pg_tables where tablename like 'fotos_secado_%' and rowsecurity) as con_candado,                 -- 4
       has_table_privilege('anon', 'fotos_secado_lecturas', 'select') as anon_lee;                                          -- false
