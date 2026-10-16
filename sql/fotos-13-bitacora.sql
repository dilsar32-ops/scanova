-- =====================================================================
--  fotos-13-bitacora.sql  -  SCANOVA: la bitacora del laboratorio (16 oct 2026)
--  Su pedido: "ya quiero que empiece a guardar informacion... para que tu aprendas y veas los datos
--  de lo que voy haciendo". Mientras se prueba "Probar lo demolido" en la camara, el telefono manda
--  cada pocos segundos un resumen (en que cuarto esta, que paredes pego la malla al laser, que
--  aberturas vio, lo que va midiendo) y cada evento (fijo una pared, toco una esquina, cambio de
--  cuarto). Sin nombres de clientes ni direcciones: solo el proyecto, los cuartos y numeros.
--    fotos_lab_bitacora   una fila por resumen o evento
--  Correr DESPUES de fotos-12-medidas.sql. Solo agrega: nada existente se borra ni cambia.
--  Archivo en ASCII puro.
-- =====================================================================
create table if not exists fotos_lab_bitacora (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  created_by  uuid not null default auth.uid() references auth.users(id),
  company_id  uuid not null default my_company() references companies(id) on delete cascade,
  trabajo_id  uuid references fotos_trabajos(id) on delete set null,
  sesion      text not null check (length(sesion) between 1 and 64),
  t           double precision,
  tipo        text not null check (length(tipo) between 1 and 40),
  datos       jsonb not null default '{}'::jsonb
);
create index if not exists fotos_lab_bitacora_sesion_idx on fotos_lab_bitacora (sesion, t);
create index if not exists fotos_lab_bitacora_fecha_idx on fotos_lab_bitacora (created_at desc);

alter table fotos_lab_bitacora enable row level security;

-- Cada quien escribe lo suyo, de su empresa; leer: lo suyo (la revision se hace desde el editor SQL).
drop policy if exists fotos_lab_bitacora_insert on fotos_lab_bitacora;
create policy fotos_lab_bitacora_insert on fotos_lab_bitacora for insert to authenticated
  with check (created_by = auth.uid() and company_id = my_company());
drop policy if exists fotos_lab_bitacora_select on fotos_lab_bitacora;
create policy fotos_lab_bitacora_select on fotos_lab_bitacora for select to authenticated
  using (created_by = auth.uid());

revoke all on fotos_lab_bitacora from anon;

-- COMPROBACION (debe salir: rls = true, 2 politicas, anon sin insert)
select relrowsecurity as rls from pg_class where relname = 'fotos_lab_bitacora';
select policyname, cmd from pg_policies where tablename = 'fotos_lab_bitacora' order by policyname;
select has_table_privilege('anon', 'fotos_lab_bitacora', 'insert') as anon_puede_insertar;
