-- =====================================================================
--  fotos-03-etapa.sql  -  SCANOVA: etapa y avance de cada proyecto (12 oct 2026)
--  El diseno nuevo (Home) ensena en cada proyecto su etapa (Planning / In Progress / Completed)
--  y una barra de avance con %. Esos datos NO existian: aqui se agregan como columnas que el
--  manager llena al editar el proyecto. Nada se inventa: un proyecto sin avance no ensena barra.
--  Solo agrega columnas con valor por defecto: la app vieja no se entera (pide sus columnas por nombre).
--  Archivo en ASCII puro: el editor de Supabase rompe los acentos al pegar.
-- =====================================================================
alter table fotos_trabajos add column if not exists etapa text not null default 'en_curso';
alter table fotos_trabajos add column if not exists avance smallint;
alter table fotos_trabajos drop constraint if exists fotos_trabajos_etapa_chk;
alter table fotos_trabajos add constraint fotos_trabajos_etapa_chk check (etapa in ('planeacion','en_curso','completado'));
alter table fotos_trabajos drop constraint if exists fotos_trabajos_avance_chk;
alter table fotos_trabajos add constraint fotos_trabajos_avance_chk check (avance is null or (avance between 0 and 100));
notify pgrst, 'reload schema';

-- ---------- COMPROBACION (lo esperado al lado) ----------
select (select count(*) from information_schema.columns where table_name = 'fotos_trabajos' and column_name in ('etapa','avance')) as columnas,   -- 2
       (select count(*) from fotos_trabajos where etapa is null) as sin_etapa,                                                                    -- 0
       (select count(*) from pg_constraint where conname in ('fotos_trabajos_etapa_chk','fotos_trabajos_avance_chk')) as candados;               -- 2
