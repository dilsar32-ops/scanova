-- =====================================================================
--  fotos-06-foto.sql  -  SCANOVA: tareas de UNA foto (12 oct 2026)
--  Su diseno de la foto abierta: Tasks con fecha limite (Due) y a quien le toca.
--  Se usan las mismas tareas del proyecto (fotos_tareas) con tres columnas mas:
--  la foto, la fecha limite y la persona. Una tarea de foto tambien sale en el proyecto.
--  Solo agrega. Archivo en ASCII puro. Correr DESPUES de fotos-05-detalles.sql.
-- =====================================================================
alter table fotos_tareas add column if not exists foto_id uuid references fotos_fotos(id) on delete set null;
alter table fotos_tareas add column if not exists vence date;
alter table fotos_tareas add column if not exists asignado uuid references auth.users(id) on delete set null;
create index if not exists fotos_tareas_foto_idx on fotos_tareas (foto_id, created_at);
-- Favoritos (el menu ... del telefono: Add to Favorites). Es de la foto, para todo el equipo.
alter table fotos_fotos add column if not exists favorita boolean not null default false;

notify pgrst, 'reload schema';

-- ---------- COMPROBACION (lo esperado al lado) ----------
select (select count(*) from information_schema.columns where table_name = 'fotos_tareas' and column_name in ('foto_id','vence','asignado')) as columnas,  -- 3
       (select count(*) from pg_policies where tablename = 'fotos_tareas') as politicas,                                                              -- 4
       (select count(*) from information_schema.columns where table_name = 'fotos_fotos' and column_name = 'favorita') as favorita;                  -- 1
