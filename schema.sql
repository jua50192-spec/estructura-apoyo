-- =====================================================================
--  ESTRUCTURA DE APOYO - esquema para Supabase
--  Pegar completo en: Supabase > SQL Editor > New query > Run
--  Se puede ejecutar más de una vez sin dañar nada.
-- =====================================================================

-- ---------- Tablas ----------
create table if not exists public.perfiles (
  id        uuid primary key references auth.users(id) on delete cascade,
  nombre    text not null,
  zona      text not null default '',
  telefono  text not null default '',
  rol       text not null default 'coordinador' check (rol in ('admin','coordinador')),
  activo    boolean not null default true,
  creado    timestamptz not null default now()
);

create table if not exists public.padron (
  id        bigint generated always as identity primary key,
  cedula    text not null unique,
  nombre    text not null,
  estado    text not null default '',
  celular   text not null default '',
  recinto   text not null default '',
  colegio   text not null default ''
);

-- Una persona solo puede tener UN coordinador (la clave primaria lo garantiza).
create table if not exists public.seguidores (
  padron_id bigint primary key references public.padron(id) on delete cascade,
  coord_id  uuid not null references public.perfiles(id),
  creado    timestamptz not null default now()
);
create index if not exists seguidores_coord_idx on public.seguidores(coord_id);

create table if not exists public.config (
  id        int primary key default 1 check (id = 1),
  candidato text not null default '',
  foto      text not null default '',
  logo      text not null default ''
);
insert into public.config(id) values (1) on conflict do nothing;

-- ---------- Funciones de apoyo ----------
create or replace function public.es_activo() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and activo)
$$;

create or replace function public.es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and activo and rol = 'admin')
$$;

create or replace function public.norm(t text) returns text
language sql immutable as $$
  select translate(lower(coalesce(t,'')), 'áéíóúüñàèìòù', 'aeiouunaeiou')
$$;

create or replace function public.mask_ced(c text) returns text
language sql immutable as $$
  select case when length(c) >= 4 then left(c,3) || '-•••••' || right(c,4) else c end
$$;

-- ---------- Permisos por fila (RLS) ----------
alter table public.perfiles   enable row level security;
alter table public.padron     enable row level security;
alter table public.seguidores enable row level security;
alter table public.config     enable row level security;

drop policy if exists perfiles_ver   on public.perfiles;
drop policy if exists perfiles_admin on public.perfiles;
create policy perfiles_ver   on public.perfiles for select to authenticated
  using (id = auth.uid() or public.es_admin());
create policy perfiles_admin on public.perfiles for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- El padrón completo solo lo ve el administrador. Los coordinadores buscan con buscar_padron().
drop policy if exists padron_admin on public.padron;
create policy padron_admin on public.padron for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

drop policy if exists seg_ver   on public.seguidores;
drop policy if exists seg_admin on public.seguidores;
create policy seg_ver   on public.seguidores for select to authenticated
  using (coord_id = auth.uid() or public.es_admin());
create policy seg_admin on public.seguidores for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

drop policy if exists config_ver   on public.config;
drop policy if exists config_admin on public.config;
create policy config_ver   on public.config for select to anon, authenticated using (true);
create policy config_admin on public.config for update to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- ---------- Funciones que usan los coordinadores ----------
create or replace function public.buscar_padron(q text)
returns table (id bigint, nombre text, cedula text, estado text, recinto text, colegio text,
               tomado_por text, mio boolean)
language plpgsql stable security definer set search_path = public as $$
declare qn text := norm(trim(q)); qd text := regexp_replace(q, '\D', '', 'g');
begin
  if not es_activo() then raise exception 'No autorizado'; end if;
  if length(qn) < 3 and length(qd) < 6 then return; end if;
  return query
    select p.id, p.nombre, mask_ced(p.cedula), p.estado, p.recinto, p.colegio,
           pf.nombre, (s.coord_id = auth.uid())
    from padron p
    left join seguidores s on s.padron_id = p.id
    left join perfiles pf on pf.id = s.coord_id
    where (length(qn) >= 3 and norm(p.nombre) like '%' || qn || '%')
       or (length(qd) >= 6 and regexp_replace(p.cedula, '\D', '', 'g') like '%' || qd || '%')
    order by p.nombre
    limit 12;
end $$;

create or replace function public.anadir_seguidor(p_id bigint) returns text
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not es_activo() then raise exception 'No autorizado'; end if;
  insert into seguidores(padron_id, coord_id) values (p_id, auth.uid()) on conflict do nothing;
  get diagnostics n = row_count;
  if n = 1 then return 'ok'; end if;
  if exists (select 1 from seguidores where padron_id = p_id and coord_id = auth.uid()) then return 'ya_suyo'; end if;
  return 'ya_tomado';
end $$;

create or replace function public.quitar_seguidor(p_id bigint) returns void
language sql security definer set search_path = public as $$
  delete from seguidores where padron_id = p_id and coord_id = auth.uid() and es_activo()
$$;

create or replace function public.mis_seguidores()
returns table (id bigint, nombre text, cedula text, estado text, recinto text, colegio text, celular text, creado timestamptz)
language sql stable security definer set search_path = public as $$
  select p.id, p.nombre, mask_ced(p.cedula), p.estado, p.recinto, p.colegio, p.celular, s.creado
  from seguidores s join padron p on p.id = s.padron_id
  where s.coord_id = auth.uid() and es_activo()
  order by s.creado desc
$$;

-- ---------- Resumen para el aspirante / administrador ----------
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
                        'activo',pf.activo,'n',(select count(*) from seguidores s where s.coord_id = pf.id))
               order by pf.nombre)
        from perfiles pf where pf.rol = 'coordinador'), '[]'::json),
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

-- ---------- Quién puede llamar qué ----------
revoke all on function public.buscar_padron(text)   from public, anon;
revoke all on function public.anadir_seguidor(bigint) from public, anon;
revoke all on function public.quitar_seguidor(bigint) from public, anon;
revoke all on function public.mis_seguidores()      from public, anon;
revoke all on function public.resumen()             from public, anon;
grant execute on function public.buscar_padron(text)   to authenticated;
grant execute on function public.anadir_seguidor(bigint) to authenticated;
grant execute on function public.quitar_seguidor(bigint) to authenticated;
grant execute on function public.mis_seguidores()      to authenticated;
grant execute on function public.resumen()             to authenticated;

revoke all on public.perfiles, public.padron, public.seguidores from anon;
grant select on public.config to anon, authenticated;
grant update on public.config to authenticated;
grant select, insert, update, delete on public.perfiles, public.padron, public.seguidores to authenticated;
