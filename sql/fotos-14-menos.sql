-- =====================================================================
--  fotos-14-menos.sql  -  SCANOVA: lo que se le resta a una medida (16 oct 2026)
--  Su pedido: "cuando le senalamos a la pared, puede preguntar: es toda la pared o un area parcial?
--  Si es toda la pared, las medidas salen del plano" y "restala" (las puertas y ventanas).
--    fotos_medidas.menos      pies cuadrados que se restan (las puertas y ventanas de esa pared);
--                             null = nada (todas las medidas de antes)
--    fotos_medidas.menos_que  que se resto, en ingles (va al reporte): "1 door, 1 window"
--  Correr DESPUES de fotos-12-medidas.sql. Solo agrega: nada existente se borra ni cambia.
--  Los permisos son de la tabla entera: las columnas nuevas quedan con el mismo candado.
--  Archivo en ASCII puro.
-- =====================================================================
alter table fotos_medidas add column if not exists menos numeric;
alter table fotos_medidas add column if not exists menos_que text;
alter table fotos_medidas drop constraint if exists fotos_medidas_menos_ck;
alter table fotos_medidas add constraint fotos_medidas_menos_ck check (menos is null or (menos >= 0 and menos <= 100000));
alter table fotos_medidas drop constraint if exists fotos_medidas_menos_que_ck;
alter table fotos_medidas add constraint fotos_medidas_menos_que_ck check (menos_que is null or length(menos_que) <= 120);

notify pgrst, 'reload schema';

-- ---------- COMPROBACION (lo esperado al lado) ----------
select (select count(*) from information_schema.columns where table_name = 'fotos_medidas' and column_name in ('menos', 'menos_que')) as columnas,  -- 2
       (select count(*) from pg_constraint where conname in ('fotos_medidas_menos_ck', 'fotos_medidas_menos_que_ck')) as reglas,               -- 2
       (select count(*) from fotos_medidas where menos is not null) as con_resta,                                                              -- 0
       has_table_privilege('anon', 'fotos_medidas', 'select') as anon_lee;                                                                     -- false
