-- =====================================================================
--  fotos-01-base.sql  ·  SCANOVA — tablas base (12 oct 2026)
--  Plataforma propia de fotos de trabajos. TODO con prefijo fotos_ : no toca ninguna tabla de
--  Field Reports. Se apoya en lo que ya existe en este mismo proyecto de Supabase:
--  companies, profiles, auth.users, my_company(), my_role(), my_status().
--  Las fotos NO viven aquí (van en Cloudflare R2); aquí va la ficha de cada foto: dónde está,
--  cuándo se tomó, quién la subió, su huella y sus notas.
--  Reglas: todo por empresa; crew activo lee y sube; solo el manager borra, archiva y comparte.
-- =====================================================================

-- ---------- 1. Trabajos (un trabajo = un perfil, como en CompanyCam) ----------
create table if not exists fotos_trabajos (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null default my_company() references companies(id) on delete cascade,
  created_by    uuid not null default auth.uid() references auth.users(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  cliente       text not null,
  direccion     text,
  telefono      text,
  correo        text,
  tipo          text not null default 'otro' check (tipo in ('agua','moho','fuego','mudanza','contenidos','otro')),
  estado        text not null default 'activo' check (estado in ('activo','archivado')),
  archivado_at  timestamptz,
  notas         text,
  lat           double precision,
  lng           double precision,
  cc_project_id text                      -- si vino importado de CompanyCam
);
create index if not exists fotos_trabajos_empresa_idx on fotos_trabajos (company_id, estado, updated_at desc);

-- ---------- 2. Fotos (la ficha de cada foto; el archivo vive en R2) ----------
create table if not exists fotos_fotos (
  id            uuid primary key,                       -- lo genera el teléfono (nace sin señal)
  trabajo_id    uuid not null references fotos_trabajos(id) on delete restrict,
  company_id    uuid not null default my_company() references companies(id) on delete cascade,
  created_by    uuid not null default auth.uid() references auth.users(id),
  subida_at     timestamptz not null default now(),    -- la pone el servidor
  tomada_at     timestamptz,                            -- del EXIF o del teléfono
  lat           double precision,
  lng           double precision,
  r2_original   text not null,                          -- rutas en el bucket
  r2_web        text,                                   -- 1600 px
  r2_mini       text,                                   -- 320 px
  bytes         int,
  ancho         int,
  alto          int,
  sha256        text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  nota          text,
  estado        text not null default 'activa' check (estado in ('activa','papelera')),
  eliminada_at  timestamptz,
  eliminada_por uuid references auth.users(id),
  cc_photo_id   text,                                   -- si vino importada de CompanyCam
  unique (trabajo_id, sha256)                           -- la misma foto dos veces al mismo trabajo = una
);
create index if not exists fotos_fotos_trabajo_idx on fotos_fotos (trabajo_id, estado, tomada_at desc);

-- ---------- 3. Etiquetas (Antes / Después / Daño / Equipo…) ----------
create table if not exists fotos_etiquetas (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null default my_company() references companies(id) on delete cascade,
  nombre      text not null,
  color       text,
  orden       int not null default 0,
  unique (company_id, nombre)
);
create table if not exists fotos_foto_etiquetas (
  foto_id     uuid not null references fotos_fotos(id) on delete cascade,
  etiqueta_id uuid not null references fotos_etiquetas(id) on delete cascade,
  company_id  uuid not null default my_company() references companies(id) on delete cascade,
  puesta_por  uuid not null default auth.uid() references auth.users(id),
  puesta_at   timestamptz not null default now(),
  primary key (foto_id, etiqueta_id)
);

-- ---------- 4. Comentarios por foto ----------
create table if not exists fotos_comentarios (
  id          uuid primary key default gen_random_uuid(),
  foto_id     uuid not null references fotos_fotos(id) on delete cascade,
  company_id  uuid not null default my_company() references companies(id) on delete cascade,
  created_by  uuid not null default auth.uid() references auth.users(id),
  created_at  timestamptz not null default now(),
  texto       text not null check (length(texto) between 1 and 2000)
);
create index if not exists fotos_comentarios_foto_idx on fotos_comentarios (foto_id, created_at);

-- ---------- 5. Enlaces para el cliente (solo lectura, con caducidad) ----------
create table if not exists fotos_enlaces (
  id          uuid primary key default gen_random_uuid(),
  trabajo_id  uuid not null references fotos_trabajos(id) on delete cascade,
  company_id  uuid not null default my_company() references companies(id) on delete cascade,
  created_by  uuid not null default auth.uid() references auth.users(id),
  created_at  timestamptz not null default now(),
  token       text not null unique default encode(gen_random_bytes(24), 'hex'),
  caduca_at   timestamptz not null default now() + interval '30 days',
  activo      boolean not null default true,
  visto_veces int not null default 0,
  visto_at    timestamptz
);

-- ---------- 6. Documentos del trabajo (PDF, estimados) — el archivo vive en R2 ----------
create table if not exists fotos_documentos (
  id          uuid primary key default gen_random_uuid(),
  trabajo_id  uuid not null references fotos_trabajos(id) on delete restrict,
  company_id  uuid not null default my_company() references companies(id) on delete cascade,
  created_by  uuid not null default auth.uid() references auth.users(id),
  created_at  timestamptz not null default now(),
  nombre      text not null,
  r2_key      text not null,
  bytes       int,
  tipo_mime   text
);

-- ---------- 7. Candados: solo gente activa de la empresa; borrar y compartir, el manager ----------
-- Lee: cualquiera de la empresa que esté activo (o el manager). Escribe: activo, y la fila es suya.
do $$
declare t text;
begin
  foreach t in array array['fotos_trabajos','fotos_fotos','fotos_etiquetas','fotos_foto_etiquetas','fotos_comentarios','fotos_enlaces','fotos_documentos'] loop
    execute format('alter table %I enable row level security', t);
    execute format('revoke all on %I from anon', t);
    execute format('grant select, insert, update, delete on %I to authenticated', t);
    execute format('drop policy if exists "%s lee" on %I', t, t);
    execute format('create policy "%s lee" on %I for select to authenticated using (company_id = my_company() and (my_role() = ''manager'' or my_status() = ''active''))', t, t);
  end loop;
end $$;

-- Trabajos: crea cualquiera activo; cambia el manager o quien lo creó; archivar/borrar solo el manager (en la app no se borra: se archiva).
drop policy if exists "fotos_trabajos crea" on fotos_trabajos;
create policy "fotos_trabajos crea" on fotos_trabajos for insert to authenticated
  with check (company_id = my_company() and created_by = auth.uid() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_trabajos cambia" on fotos_trabajos;
create policy "fotos_trabajos cambia" on fotos_trabajos for update to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')))
  with check (company_id = my_company());
drop policy if exists "fotos_trabajos borra" on fotos_trabajos;
create policy "fotos_trabajos borra" on fotos_trabajos for delete to authenticated
  using (company_id = my_company() and my_role() = 'manager');

-- Fotos: la fila la escribe SOLO la función de subida (llave de servicio) después de comprobar
-- que el archivo está en R2; la app no inserta fotos a mano. Cambiar nota/estado: manager o quien la subió.
drop policy if exists "fotos_fotos cambia" on fotos_fotos;
create policy "fotos_fotos cambia" on fotos_fotos for update to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or (created_by = auth.uid() and my_status() = 'active')))
  with check (company_id = my_company());
-- (sin política de insert ni delete para la app: eso lo hace la función)

-- Etiquetas del catálogo: solo el manager. Ponerlas/quitarlas en una foto: cualquiera activo.
drop policy if exists "fotos_etiquetas manager" on fotos_etiquetas;
create policy "fotos_etiquetas manager" on fotos_etiquetas for all to authenticated
  using (company_id = my_company() and my_role() = 'manager') with check (company_id = my_company() and my_role() = 'manager');
drop policy if exists "fotos_foto_etiquetas pone" on fotos_foto_etiquetas;
create policy "fotos_foto_etiquetas pone" on fotos_foto_etiquetas for insert to authenticated
  with check (company_id = my_company() and puesta_por = auth.uid() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_foto_etiquetas quita" on fotos_foto_etiquetas;
create policy "fotos_foto_etiquetas quita" on fotos_foto_etiquetas for delete to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or puesta_por = auth.uid()));

-- Comentarios: escribe cualquiera activo; borra el manager o el autor.
drop policy if exists "fotos_comentarios escribe" on fotos_comentarios;
create policy "fotos_comentarios escribe" on fotos_comentarios for insert to authenticated
  with check (company_id = my_company() and created_by = auth.uid() and (my_role() = 'manager' or my_status() = 'active'));
drop policy if exists "fotos_comentarios borra" on fotos_comentarios;
create policy "fotos_comentarios borra" on fotos_comentarios for delete to authenticated
  using (company_id = my_company() and (my_role() = 'manager' or created_by = auth.uid()));

-- Enlaces para el cliente y documentos: solo el manager los crea/cambia/borra.
drop policy if exists "fotos_enlaces manager" on fotos_enlaces;
create policy "fotos_enlaces manager" on fotos_enlaces for all to authenticated
  using (company_id = my_company() and my_role() = 'manager') with check (company_id = my_company() and my_role() = 'manager');
drop policy if exists "fotos_documentos manager" on fotos_documentos;
create policy "fotos_documentos manager" on fotos_documentos for all to authenticated
  using (company_id = my_company() and my_role() = 'manager') with check (company_id = my_company() and my_role() = 'manager');

notify pgrst, 'reload schema';

-- ---------- COMPROBACION (una fila; lo esperado al lado) ----------
select (select count(*) from information_schema.tables where table_schema = 'public' and table_name like 'fotos\_%') as tablas,          -- 7
       (select count(*) from pg_policies where tablename like 'fotos\_%') as politicas,                                                   -- 18
       (select count(*) from pg_tables where schemaname = 'public' and tablename like 'fotos\_%' and rowsecurity) as con_candado,          -- 7
       has_table_privilege('anon', 'fotos_fotos', 'select') as anon_lee,                                                                 -- false
       has_table_privilege('authenticated', 'fotos_trabajos', 'insert') as equipo_crea;                                                  -- true
