create or replace function public.actualizar_telefono(p_id bigint, p_tel text) returns text
language plpgsql security definer set search_path = public as $$
declare tel text := regexp_replace(coalesce(p_tel,''), '\D', '', 'g');
begin
  if not es_activo() then raise exception 'No autorizado'; end if;
  if length(tel) <> 10 then raise exception 'Escriba el teléfono con 10 números'; end if;
  if not exists (
    select 1 from seguidores s
    where s.padron_id = p_id
      and (s.coord_id = auth.uid() or es_admin()
           or exists (select 1 from perfiles h where h.id = s.coord_id and h.padre_id = auth.uid()))
  ) then raise exception 'No autorizado'; end if;
  update padron set celular = tel where id = p_id;
  return 'ok';
end $$;
revoke all on function public.actualizar_telefono(bigint, text) from public, anon;
grant execute on function public.actualizar_telefono(bigint, text) to authenticated;
