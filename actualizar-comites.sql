-- =====================================================================
--  COMITÉS: el administrador autoriza a un coordinador a formar comités.
--  Pegar completo en: Supabase > SQL Editor > New query > Run
-- =====================================================================
alter table public.perfiles add column if not exists padre_id uuid references public.perfiles(id);
alter table public.perfiles add column if not exists puede_comites boolean not null default false;
alter table public.perfiles drop constraint if exists perfiles_rol_check;
alter table public.perfiles add constraint perfiles_rol_check check (rol in ('admin','coordinador','jefe'));

-- Una cuenta está activa solo si ella y su coordinador (si tiene) están activos.
create or replace function public.es_activo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from perfiles p
    where p.id = auth.uid() and p.activo
      and (p.padre_id is null or exists (select 1 from perfiles q where q.id = p.padre_id and q.activo))
  )
$$;

-- El coordinador autorizado registra a un jefe de comité (la cuenta de acceso ya fue creada).
create or replace function public.crear_jefe(p_id uuid, p_nombre text, p_zona text, p_telefono text) returns text
language plpgsql security definer set search_path = public, auth as $$
begin
  if not es_activo() then raise exception 'No autorizado'; end if;
  if not exists (select 1 from perfiles where id = auth.uid() and rol = 'coordinador' and puede_comites) then
    raise exception 'No tiene permiso para formar comités';
  end if;
  if length(btrim(coalesce(p_nombre,''))) < 3 then raise exception 'Escriba el nombre'; end if;
  if exists (select 1 from perfiles where id = p_id) then raise exception 'Ese usuario ya existe'; end if;
  if not exists (select 1 from auth.users where id = p_id and created_at > now() - interval '5 minutes') then
    raise exception 'No se pudo verificar la cuenta nueva';
  end if;
  insert into perfiles(id, nombre, zona, telefono, rol, padre_id)
    values (p_id, btrim(p_nombre), coalesce(btrim(p_zona),''), coalesce(p_telefono,''), 'jefe', auth.uid());
  return 'ok';
end $$;

create or replace function public.mis_comites()
returns table (id uuid, nombre text, zona text, telefono text, activo boolean, n bigint)
language sql stable security definer set search_path = public as $$
  select pf.id, pf.nombre, pf.zona, pf.telefono, pf.activo,
         (select count(*) from seguidores s where s.coord_id = pf.id)
  from perfiles pf
  where pf.padre_id = auth.uid() and es_activo()
  order by pf.nombre
$$;

create or replace function public.militantes_de(p_coord uuid)
returns table (id bigint, nombre text, cedula text, estado text, recinto text, colegio text, celular text, creado timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, p.nombre, mask_ced(p.cedula), p.estado, p.recinto, p.colegio, p.celular, s.creado
  from seguidores s join padron p on p.id = s.padron_id
  where s.coord_id = p_coord and es_activo()
    and (p_coord = auth.uid() or es_admin() or exists (select 1 from perfiles h where h.id = p_coord and h.padre_id = auth.uid()))
  order by s.creado desc
$$;

create or replace function public.quitar_de(p_coord uuid, p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not es_activo() then raise exception 'No autorizado'; end if;
  if not (es_admin() or exists (select 1 from perfiles h where h.id = p_coord and h.padre_id = auth.uid())) then
    raise exception 'No autorizado';
  end if;
  delete from seguidores where padron_id = p_id and coord_id = p_coord;
end $$;

create or replace function public.editar_jefe(p_id uuid, p_nombre text, p_zona text, p_telefono text, p_activo boolean) returns text
language plpgsql security definer set search_path = public as $$
begin
  if not es_activo() then raise exception 'No autorizado'; end if;
  if not exists (select 1 from perfiles where id = p_id and rol = 'jefe' and padre_id = auth.uid()) then
    raise exception 'No autorizado';
  end if;
  if length(btrim(coalesce(p_nombre,''))) < 3 then raise exception 'Escriba el nombre'; end if;
  update perfiles set nombre = btrim(p_nombre), zona = coalesce(btrim(p_zona),''), telefono = coalesce(p_telefono,''),
         activo = coalesce(p_activo, activo)
   where id = p_id;
  return 'ok';
end $$;

-- Restablecer clave: el administrador (coordinadores y jefes) o el coordinador (sus jefes).
create or replace function public.admin_reset_clave(p_id uuid, p_clave text) returns text
language plpgsql security definer set search_path = public, auth, extensions as $$
begin
  if not es_activo() then raise exception 'No autorizado'; end if;
  if p_clave is null or length(p_clave) < 6 then raise exception 'La clave debe tener al menos 6 caracteres'; end if;
  if not (
       (es_admin() and exists (select 1 from perfiles where id = p_id and rol in ('coordinador','jefe')))
    or exists (select 1 from perfiles where id = p_id and rol = 'jefe' and padre_id = auth.uid())
  ) then raise exception 'No autorizado'; end if;
  update auth.users set encrypted_password = extensions.crypt(p_clave, extensions.gen_salt('bf')), updated_at = now() where id = p_id;
  return 'ok';
end $$;

-- Resumen del administrador con comités.
create or replace function public.resumen() returns json
language plpgsql stable security definer set search_path = public as $$
declare r json;
begin
  if not es_admin() then raise exception 'No autorizado'; end if;
  select json_build_object(
    'padron',     (select count(*) from padron),
    'seguidores', (select count(*) from seguidores),
    'coordinadores', coalesce((
        select json_agg(json_build_object('id',pf.id,'nombre',pf.nombre,'zona',pf.zona,'telefono',pf.telefono,
                        'activo',pf.activo,'puede_comites',pf.puede_comites,
                        'propios',(select count(*) from seguidores s where s.coord_id = pf.id),
                        'n',(select count(*) from seguidores s where s.coord_id = pf.id
                               or s.coord_id in (select h.id from perfiles h where h.padre_id = pf.id)))
               order by pf.nombre)
        from perfiles pf where pf.rol = 'coordinador'), '[]'::json),
    'jefes', coalesce((
        select json_agg(json_build_object('id',h.id,'nombre',h.nombre,'zona',h.zona,'telefono',h.telefono,
                        'activo',h.activo,'padre_id',h.padre_id,
                        'n',(select count(*) from seguidores s where s.coord_id = h.id))
               order by h.nombre)
        from perfiles h where h.rol = 'jefe'), '[]'::json),
    'recintos', coalesce((
        select json_agg(x) from (
          select json_build_object('recinto', coalesce(nullif(p.recinto,''),'Sin recinto'), 'n', count(*)) x
          from seguidores s join padron p on p.id = s.padron_id
          group by p.recinto order by count(*) desc limit 8) t), '[]'::json),
    'ultimos', coalesce((
        select json_agg(x) from (
          select json_build_object('nombre', p.nombre, 'coord', pf.nombre, 'creado', s.creado) x
          from seguidores s join padron p on p.id = s.padron_id join perfiles pf on pf.id = s.coord_id
          order by s.creado desc limit 6) t), '[]'::json)
  ) into r;
  return r;
end $$;

revoke all on function public.crear_jefe(uuid, text, text, text) from public, anon;
revoke all on function public.mis_comites() from public, anon;
revoke all on function public.militantes_de(uuid) from public, anon;
revoke all on function public.quitar_de(uuid, bigint) from public, anon;
revoke all on function public.editar_jefe(uuid, text, text, text, boolean) from public, anon;
revoke all on function public.admin_reset_clave(uuid, text) from public, anon;
revoke all on function public.resumen() from public, anon;
grant execute on function public.crear_jefe(uuid, text, text, text) to authenticated;
grant execute on function public.mis_comites() to authenticated;
grant execute on function public.militantes_de(uuid) to authenticated;
grant execute on function public.quitar_de(uuid, bigint) to authenticated;
grant execute on function public.editar_jefe(uuid, text, text, text, boolean) to authenticated;
grant execute on function public.admin_reset_clave(uuid, text) to authenticated;
grant execute on function public.resumen() to authenticated;
