-- =====================================================================
--  FORMULARIO DE COMITÉ AFECTIVO: meta, datos del responsable, apodo y dirección
--  Pegar completo en: Supabase > SQL Editor > New query > Run
--  (Instalar antes el de comités y el de teléfono.)
-- =====================================================================
alter table public.config  add column if not exists meta int not null default 10;
alter table public.config  add column if not exists organizacion text not null default '';
alter table public.perfiles add column if not exists cedula text not null default '';
alter table public.perfiles add column if not exists cargo text not null default '';
alter table public.perfiles add column if not exists provincia text not null default '';
alter table public.perfiles add column if not exists municipio text not null default '';
alter table public.perfiles add column if not exists recinto text not null default '';
alter table public.perfiles add column if not exists meta int;
alter table public.padron   add column if not exists apodo text not null default '';
alter table public.padron   add column if not exists direccion text not null default '';

create or replace function public.ced_vis(c text) returns text
language sql immutable as $$ select case when c like 'MANUAL-%' then '' else coalesce(c,'') end $$;

-- Mis militantes (con apodo, dirección y cédula completa: son los que usted inscribió)
drop function if exists public.mis_seguidores();
create function public.mis_seguidores()
returns table (id bigint, nombre text, cedula text, estado text, recinto text, colegio text, celular text, creado timestamptz, apodo text, direccion text)
language sql stable security definer set search_path = public as $$
  select p.id, p.nombre, ced_vis(p.cedula), p.estado, p.recinto, p.colegio, p.celular, s.creado, p.apodo, p.direccion
  from seguidores s join padron p on p.id = s.padron_id
  where s.coord_id = auth.uid() and es_activo()
  order by s.creado desc
$$;

drop function if exists public.militantes_de(uuid);
create function public.militantes_de(p_coord uuid)
returns table (id bigint, nombre text, cedula text, estado text, recinto text, colegio text, celular text, creado timestamptz, apodo text, direccion text)
language sql stable security definer set search_path = public as $$
  select p.id, p.nombre, ced_vis(p.cedula), p.estado, p.recinto, p.colegio, p.celular, s.creado, p.apodo, p.direccion
  from seguidores s join padron p on p.id = s.padron_id
  where s.coord_id = p_coord and es_activo()
    and (p_coord = auth.uid() or es_admin() or exists (select 1 from perfiles h where h.id = p_coord and h.padre_id = auth.uid()))
  order by s.creado desc
$$;

-- Teléfono, apodo y dirección de un militante
create or replace function public.actualizar_contacto(p_id bigint, p_tel text, p_dir text, p_apodo text) returns text
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
  update padron set celular = tel, direccion = left(btrim(coalesce(p_dir,'')), 200), apodo = left(btrim(coalesce(p_apodo,'')), 60) where id = p_id;
  return 'ok';
end $$;

-- Crear / editar jefe de comité con los datos del formulario
drop function if exists public.crear_jefe(uuid, text, text, text);
create function public.crear_jefe(p_id uuid, p_nombre text, p_zona text, p_telefono text,
    p_cedula text default '', p_cargo text default '', p_provincia text default '', p_municipio text default '', p_recinto text default '') returns text
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
  insert into perfiles(id, nombre, zona, telefono, rol, padre_id, cedula, cargo, provincia, municipio, recinto)
    values (p_id, btrim(p_nombre), coalesce(btrim(p_zona),''), coalesce(p_telefono,''), 'jefe', auth.uid(),
            coalesce(btrim(p_cedula),''), coalesce(btrim(p_cargo),''), coalesce(btrim(p_provincia),''), coalesce(btrim(p_municipio),''), coalesce(btrim(p_recinto),''));
  return 'ok';
end $$;

drop function if exists public.editar_jefe(uuid, text, text, text, boolean);
create function public.editar_jefe(p_id uuid, p_nombre text, p_zona text, p_telefono text, p_activo boolean,
    p_cedula text default '', p_cargo text default '', p_provincia text default '', p_municipio text default '', p_recinto text default '') returns text
language plpgsql security definer set search_path = public as $$
begin
  if not es_activo() then raise exception 'No autorizado'; end if;
  if not exists (select 1 from perfiles where id = p_id and rol = 'jefe' and padre_id = auth.uid()) then
    raise exception 'No autorizado';
  end if;
  if length(btrim(coalesce(p_nombre,''))) < 3 then raise exception 'Escriba el nombre'; end if;
  update perfiles set nombre = btrim(p_nombre), zona = coalesce(btrim(p_zona),''), telefono = coalesce(p_telefono,''),
         activo = coalesce(p_activo, activo), cedula = coalesce(btrim(p_cedula),''), cargo = coalesce(btrim(p_cargo),''),
         provincia = coalesce(btrim(p_provincia),''), municipio = coalesce(btrim(p_municipio),''), recinto = coalesce(btrim(p_recinto),'')
   where id = p_id;
  return 'ok';
end $$;

drop function if exists public.mis_comites();
create function public.mis_comites()
returns table (id uuid, nombre text, zona text, telefono text, activo boolean, n bigint,
               cedula text, cargo text, provincia text, municipio text, recinto text, meta int)
language sql stable security definer set search_path = public as $$
  select pf.id, pf.nombre, pf.zona, pf.telefono, pf.activo,
         (select count(*) from seguidores s where s.coord_id = pf.id),
         pf.cedula, pf.cargo, pf.provincia, pf.municipio, pf.recinto, coalesce(pf.meta, (select c.meta from config c where c.id = 1))
  from perfiles pf
  where pf.padre_id = auth.uid() and es_activo()
  order by pf.nombre
$$;

-- Todo lo que lleva el formulario impreso
create or replace function public.datos_formulario(p_coord uuid) returns json
language plpgsql stable security definer set search_path = public as $$
declare r json;
begin
  if not es_activo() then raise exception 'No autorizado'; end if;
  if not (p_coord = auth.uid() or es_admin() or exists (select 1 from perfiles h where h.id = p_coord and h.padre_id = auth.uid())) then
    raise exception 'No autorizado';
  end if;
  select json_build_object(
    'resp', (select json_build_object('nombre',pf.nombre,'cedula',pf.cedula,'cargo',pf.cargo,'telefono',pf.telefono,
                    'provincia',pf.provincia,'municipio',pf.municipio,'zona',pf.zona,'recinto',pf.recinto)
             from perfiles pf where pf.id = p_coord),
    'meta', coalesce((select pf.meta from perfiles pf where pf.id = p_coord), (select c.meta from config c where c.id = 1), 10),
    'filas', coalesce((
        select json_agg(json_build_object('nombre',p.nombre,'apodo',p.apodo,'cedula',ced_vis(p.cedula),'celular',p.celular,'direccion',p.direccion)
                        order by s.creado)
        from seguidores s join padron p on p.id = s.padron_id where s.coord_id = p_coord), '[]'::json)
  ) into r;
  return r;
end $$;

-- Resumen del administrador (con datos del formulario y meta)
create or replace function public.resumen() returns json
language plpgsql stable security definer set search_path = public as $$
declare r json;
begin
  if not es_admin() then raise exception 'No autorizado'; end if;
  select json_build_object(
    'padron',     (select count(*) from padron),
    'seguidores', (select count(*) from seguidores),
    'meta',       (select c.meta from config c where c.id = 1),
    'coordinadores', coalesce((
        select json_agg(json_build_object('id',pf.id,'nombre',pf.nombre,'zona',pf.zona,'telefono',pf.telefono,
                        'activo',pf.activo,'puede_comites',pf.puede_comites,
                        'cedula',pf.cedula,'cargo',pf.cargo,'provincia',pf.provincia,'municipio',pf.municipio,'recinto',pf.recinto,'meta',pf.meta,
                        'propios',(select count(*) from seguidores s where s.coord_id = pf.id),
                        'n',(select count(*) from seguidores s where s.coord_id = pf.id
                               or s.coord_id in (select h.id from perfiles h where h.padre_id = pf.id)))
               order by pf.nombre)
        from perfiles pf where pf.rol = 'coordinador'), '[]'::json),
    'jefes', coalesce((
        select json_agg(json_build_object('id',h.id,'nombre',h.nombre,'zona',h.zona,'telefono',h.telefono,
                        'activo',h.activo,'padre_id',h.padre_id,
                        'cedula',h.cedula,'cargo',h.cargo,'provincia',h.provincia,'municipio',h.municipio,'recinto',h.recinto,'meta',h.meta,
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

revoke all on function public.ced_vis(text) from public, anon;
revoke all on function public.mis_seguidores() from public, anon;
revoke all on function public.militantes_de(uuid) from public, anon;
revoke all on function public.actualizar_contacto(bigint, text, text, text) from public, anon;
revoke all on function public.crear_jefe(uuid, text, text, text, text, text, text, text, text) from public, anon;
revoke all on function public.editar_jefe(uuid, text, text, text, boolean, text, text, text, text, text) from public, anon;
revoke all on function public.mis_comites() from public, anon;
revoke all on function public.datos_formulario(uuid) from public, anon;
revoke all on function public.resumen() from public, anon;
grant execute on function public.ced_vis(text) to authenticated;
grant execute on function public.mis_seguidores() to authenticated;
grant execute on function public.militantes_de(uuid) to authenticated;
grant execute on function public.actualizar_contacto(bigint, text, text, text) to authenticated;
grant execute on function public.crear_jefe(uuid, text, text, text, text, text, text, text, text) to authenticated;
grant execute on function public.editar_jefe(uuid, text, text, text, boolean, text, text, text, text, text) to authenticated;
grant execute on function public.mis_comites() to authenticated;
grant execute on function public.datos_formulario(uuid) to authenticated;
grant execute on function public.resumen() to authenticated;
