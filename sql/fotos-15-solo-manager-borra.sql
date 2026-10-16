-- =====================================================================
--  fotos-15-solo-manager-borra.sql  -  SCANOVA: borrar planos y medidas, SOLO el manager (16 oct 2026)
--  Su pedido: "solo los managers tienen esas habilidades de borrar planos, borrar medidas".
--  La pantalla ya lo cumplia (commit 33a29c0), pero el servidor todavia dejaba que quien escaneo un plano lo
--  marcara borrado, y que quien anoto una medida la borrara, por fuera de la app. Esto lo cierra en el servidor.
--    fotos_planos  UPDATE: solo el manager. El unico UPDATE de la app es marcar borrado_at (docs/planos.js);
--                  escanear y subir un plano es INSERT y no cambia.
--    fotos_medidas DELETE: solo el manager. EDITAR una medida (UPDATE) sigue igual: el manager o quien la midio.
--  Nada se borra: solo cambian dos reglas. Correr DESPUES de fotos-07 y fotos-12. Archivo en ASCII puro.
-- =====================================================================
drop policy if exists "fotos_planos cambia" on fotos_planos;
create policy "fotos_planos cambia" on fotos_planos for update to authenticated
  using (company_id = my_company() and my_role() = 'manager')
  with check (company_id = my_company());

drop policy if exists "fotos_medidas borra" on fotos_medidas;
create policy "fotos_medidas borra" on fotos_medidas for delete to authenticated
  using (company_id = my_company() and my_role() = 'manager');

notify pgrst, 'reload schema';

-- ---------- COMPROBACION (lo esperado al lado) ----------
select tablename, policyname, cmd,
       (qual like '%manager%') as pide_manager,                -- true
       (qual like '%created_by%') as deja_al_autor             -- false
  from pg_policies
 where (tablename = 'fotos_planos' and cmd = 'UPDATE') or (tablename = 'fotos_medidas' and cmd = 'DELETE')
 order by tablename;
