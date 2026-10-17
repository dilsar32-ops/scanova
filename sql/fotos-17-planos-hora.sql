-- =====================================================================
--  fotos-17-planos-hora.sql  -  SCANOVA: la hora de un plano nunca es del futuro (17 oct 2026)
--  Un plano que se sube TARDE (el escaneo que la pagina no recibio porque se recargo con el escaner abierto, o uno
--  que espero senal en un sotano) lleva la hora en que se escaneo, para quedar de historial detras de un plano mas
--  nuevo de su piso en vez de taparlo. Esa hora la manda el telefono: si su fecha esta adelantada, ese plano
--  quedaria como "el mas nuevo" del piso (en Floor Plan, la camara de medir y el PDF) hasta que se borrara el piso.
--  Aqui el servidor la corrige al guardar: nunca despues de ahora. Y una de hace mas de 190 dias (un reloj muy
--  atrasado; el telefono no guarda copias de mas de 180) queda en ahora.
--  Sin hora (el escaneo normal, que se sube al terminar), now() como siempre.
--  Solo agrega una funcion de trigger y su trigger: nada existente se borra ni cambia. No es security definer y una
--  funcion de trigger no se puede llamar sola (ni por la API). Correr DESPUES de fotos-07. Archivo en ASCII puro.
-- =====================================================================
create or replace function fotos_planos_hora() returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.created_at := least(coalesce(new.created_at, now()), now());
  if new.created_at < now() - interval '190 days' then new.created_at := now(); end if;
  return new;
end
$$;

drop trigger if exists fotos_planos_hora on fotos_planos;
create trigger fotos_planos_hora before insert on fotos_planos
  for each row execute function fotos_planos_hora();

-- ---------- COMPROBACION (lo esperado al lado) ----------
select (select count(*) from pg_trigger where tgname = 'fotos_planos_hora' and tgrelid = 'fotos_planos'::regclass and not tgisinternal) as trigger_puesto,  -- 1
       (select prosecdef from pg_proc where proname = 'fotos_planos_hora') as security_definer;                                                         -- false
