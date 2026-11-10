-- TU comprobación · esquema inicial
-- Lectura: RLS por tabla. Escritura: solo mediante funciones (security definer) que aplican las reglas.

-- ============ Tablas ============
create table public.centros (
  nombre text primary key
);
insert into public.centros (nombre) values ('Planta Amagá'), ('Planta Malambo'), ('Comercial');

create table public.topes (
  concepto text primary key,
  valor numeric not null check (valor > 0)
);

create table public.perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  login text not null unique check (login ~ '^[a-z0-9._-]{3,}$'),
  nombre text not null,
  puesto text not null,
  rol text not null check (rol in ('vendedor','lider','autorizador','caja','contabilidad','admin')),
  autoriza uuid references public.perfiles(id) on delete set null,
  pago text check (pago in ('tarjeta','anticipo','caja')),
  centro text references public.centros(nombre) on update cascade,
  credito numeric not null default 0,
  monto_caja numeric not null default 0,
  encargado text not null default '',
  telefono text not null default '',
  activo boolean not null default true,
  bloqueado boolean not null default false,
  intentos int not null default 0,
  cambiar_clave boolean not null default true,
  clave_fecha date not null default current_date,
  creado timestamptz not null default now(),
  check (autoriza is null or autoriza <> id)
);
create index perfiles_autoriza_idx on public.perfiles(autoriza);

create table public.periodos (
  user_id uuid not null references public.perfiles(id) on delete cascade,
  periodo text not null check (periodo ~ '^\d{4}-\d{2}$'),
  estado text not null check (estado in ('enviado','devuelto','autorizado','finiquitado')),
  enviado date,
  envios int not null default 0,
  autorizado date,
  finiquitado date,
  exportado date,
  total numeric,
  anticipo numeric,
  diferencia numeric,
  primary key (user_id, periodo)
);

create table public.gastos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perfiles(id) on delete cascade,
  periodo text not null,
  fecha date not null,
  concepto text not null check (concepto in ('desayuno','almuerzo','comida_cliente','cafe_cliente','peaje','combustible','parqueadero','obsequio','hospedaje')),
  valor numeric not null check (valor > 0),
  centro text not null references public.centros(nombre) on update cascade,
  medio text not null check (medio in ('tarjeta','efectivo','anticipo','caja')),
  empresa text not null default '',
  personas text not null default '',
  n_personas int not null default 1 check (n_personas >= 1),
  cliente boolean not null default false,
  fuera boolean not null default false,
  factura boolean not null default false,
  comentario text not null default '',
  devolucion text not null default '',
  estado text not null default 'borrador' check (estado in ('borrador','enviado','aprobado','devuelto','pagado')),
  corregido boolean not null default false,
  foto_path text,
  foto_archivada boolean not null default false,
  creado timestamptz not null default now(),
  check (periodo = to_char(fecha, 'YYYY-MM'))
);
create index gastos_user_periodo_idx on public.gastos(user_id, periodo);

create table public.anticipos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.perfiles(id) on delete cascade,
  monto numeric not null check (monto > 0),
  motivo text not null,
  estado text not null default 'solicitado' check (estado in ('solicitado','autorizado','rechazado','depositado','comprobado')),
  fecha date not null default current_date,
  autorizado date,
  autorizado_por uuid references public.perfiles(id) on delete set null,
  rechazo text,
  depositado date,
  periodo text
);
create index anticipos_user_idx on public.anticipos(user_id);
create index anticipos_autorizado_por_idx on public.anticipos(autorizado_por);
-- Regla: no se puede pedir otro anticipo mientras el anterior no esté comprobado.
create unique index anticipos_uno_abierto on public.anticipos(user_id) where estado in ('solicitado','autorizado','depositado');

alter table public.centros enable row level security;
alter table public.topes enable row level security;
alter table public.perfiles enable row level security;
alter table public.periodos enable row level security;
alter table public.gastos enable row level security;
alter table public.anticipos enable row level security;

-- ============ Funciones auxiliares ============
create function public.hoy_co() returns date language sql stable set search_path = '' as
$$ select (now() at time zone 'America/Bogota')::date $$;

-- Rol del usuario actual, solo si está activo y no bloqueado (null en otro caso).
create function public.mi_rol() returns text language sql stable security definer set search_path = '' as
$$ select rol from public.perfiles where id = (select auth.uid()) and activo and not bloqueado $$;

create function public.mi_autorizador() returns uuid language sql stable security definer set search_path = '' as
$$ select autoriza from public.perfiles where id = (select auth.uid()) $$;

-- ¿El usuario actual autoriza a p_user?
create function public.autorizo_a(p_user uuid) returns boolean language sql stable security definer set search_path = '' as
$$ select public.mi_rol() is not null and p_user <> (select auth.uid())
     and exists (select 1 from public.perfiles where id = p_user and autoriza = (select auth.uid())) $$;

create function public.estado_periodo(p_user uuid, p_periodo text) returns text language sql stable security definer set search_path = '' as
$$ select coalesce((select estado from public.periodos where user_id = p_user and periodo = p_periodo), 'abierto') $$;

create function public.gasto_editable(g public.gastos) returns boolean language sql stable security definer set search_path = '' as
$$ select case public.estado_periodo(g.user_id, g.periodo)
     when 'abierto' then g.estado = 'borrador'
     when 'devuelto' then g.estado in ('devuelto','borrador')
     else false end $$;

-- ============ Lectura (RLS) ============
create policy centros_leer on public.centros for select to authenticated using (public.mi_rol() is not null);
create policy topes_leer on public.topes for select to authenticated using (public.mi_rol() is not null);

create policy perfiles_leer on public.perfiles for select to authenticated using (
  id = (select auth.uid())
  or (public.mi_rol() is not null and (
        autoriza = (select auth.uid())
     or id = public.mi_autorizador()
     or rol = 'contabilidad'
     or public.mi_rol() in ('contabilidad','admin')))
);
create policy periodos_leer on public.periodos for select to authenticated using (
  (user_id = (select auth.uid()) and public.mi_rol() is not null) or public.autorizo_a(user_id) or public.mi_rol() in ('contabilidad','admin')
);
create policy gastos_leer on public.gastos for select to authenticated using (
  (user_id = (select auth.uid()) and public.mi_rol() is not null) or public.autorizo_a(user_id) or public.mi_rol() in ('contabilidad','admin')
);
create policy anticipos_leer on public.anticipos for select to authenticated using (
  (user_id = (select auth.uid()) and public.mi_rol() is not null) or public.autorizo_a(user_id) or public.mi_rol() in ('contabilidad','admin')
);

-- ============ Fotos de tickets (Storage) ============
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('tickets', 'tickets', false, 3145728, array['image/jpeg']);

-- Ruta: {user_id}/{gasto_id}.jpg. El dueño escribe en su carpeta mientras el gasto sea editable.
create function public.foto_escribible(p_name text) returns boolean language plpgsql stable security definer set search_path = '' as $$
declare gid uuid; g public.gastos;
begin
  if coalesce(public.mi_rol(), '') not in ('vendedor','lider','caja') then return false; end if;
  if (storage.foldername(p_name))[1] is distinct from (select auth.uid())::text then return false; end if;
  begin gid := split_part(storage.filename(p_name), '.', 1)::uuid; exception when others then return false; end;
  select * into g from public.gastos where id = gid;
  if not found then return true; end if;
  return g.user_id = (select auth.uid()) and public.gasto_editable(g);
end $$;

create function public.foto_legible(p_name text) returns boolean language plpgsql stable security definer set search_path = '' as $$
declare dueno uuid;
begin
  if public.mi_rol() is null then return false; end if;
  begin dueno := (storage.foldername(p_name))[1]::uuid; exception when others then return false; end;
  return dueno = (select auth.uid()) or public.autorizo_a(dueno) or public.mi_rol() in ('contabilidad','admin');
end $$;

create policy tickets_leer on storage.objects for select to authenticated using (bucket_id = 'tickets' and public.foto_legible(name));
create policy tickets_subir on storage.objects for insert to authenticated with check (bucket_id = 'tickets' and public.foto_escribible(name));
create policy tickets_reemplazar on storage.objects for update to authenticated using (bucket_id = 'tickets' and public.foto_escribible(name)) with check (bucket_id = 'tickets' and public.foto_escribible(name));
create policy tickets_borrar on storage.objects for delete to authenticated using (bucket_id = 'tickets' and (public.foto_escribible(name) or public.mi_rol() = 'contabilidad'));

-- ============ Acceso ============
-- ¿Ya existe algún usuario? (pantalla de configuración inicial)
create function public.hay_usuarios() returns boolean language sql stable security definer set search_path = '' as
$$ select exists (select 1 from public.perfiles) $$;

-- Intento fallido: a los 5 se bloquea. No revela si el usuario existe.
create function public.login_fallido(p_login text) returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.perfiles set intentos = intentos + 1, bloqueado = (intentos + 1 >= 5)
  where login = lower(trim(p_login)) and activo and not bloqueado;
end $$;

-- Tras autenticarse: verifica estado y reinicia intentos.
create function public.login_ok() returns text language plpgsql security definer set search_path = '' as $$
declare p public.perfiles;
begin
  select * into p from public.perfiles where id = (select auth.uid());
  if not found then return 'sin_perfil'; end if;
  if not p.activo then return 'inactivo'; end if;
  if p.bloqueado then return 'bloqueado'; end if;
  update public.perfiles set intentos = 0 where id = p.id;
  return 'ok';
end $$;

create function public.clave_cambiada() returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.perfiles set cambiar_clave = false, clave_fecha = public.hoy_co() where id = (select auth.uid());
end $$;

-- ============ Usuarios (contabilidad) ============
-- Valida y normaliza los datos de un perfil.
create function public._normalizar_perfil(p_id uuid, d jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_rol text := d->>'rol';
  comprueba boolean := v_rol in ('vendedor','lider','caja');
  v_aut uuid := nullif(d->>'autoriza', '')::uuid;
  v_pago text;
  v_centro text := nullif(d->>'centro', '');
  v_credito numeric := coalesce(nullif(d->>'credito', '')::numeric, 0);
  v_caja numeric := coalesce(nullif(d->>'monto_caja', '')::numeric, 0);
begin
  if coalesce(trim(d->>'nombre'), '') = '' or coalesce(trim(d->>'puesto'), '') = '' then raise exception 'Nombre y puesto son obligatorios'; end if;
  if v_rol is null or v_rol not in ('vendedor','lider','autorizador','caja','contabilidad','admin') then raise exception 'Rol no válido'; end if;
  if v_aut is not null then
    if v_aut = p_id then raise exception 'Nadie puede autorizarse a sí mismo'; end if;
    if not exists (select 1 from public.perfiles where id = v_aut and activo and rol in ('lider','autorizador','admin')) then
      raise exception 'El autorizador debe ser un Líder, Autorizador o Administrador activo'; end if;
  end if;
  if comprueba and v_aut is null then raise exception 'Asigne quién lo autoriza'; end if;
  if comprueba and v_centro is null then raise exception 'Defina el centro de costos'; end if;
  if v_centro is not null and not exists (select 1 from public.centros where nombre = v_centro) then raise exception 'Centro de costos no existe'; end if;
  v_pago := case when v_rol = 'caja' then 'caja' when comprueba then nullif(d->>'pago', '') else null end;
  if comprueba and v_rol <> 'caja' and (v_pago is null or v_pago not in ('tarjeta','anticipo')) then raise exception 'Defina el tipo de pago'; end if;
  if v_pago = 'tarjeta' and v_credito <= 0 then raise exception 'Ingrese el cupo de la tarjeta'; end if;
  if v_rol = 'caja' and v_caja <= 0 then raise exception 'Ingrese el monto fijo de la caja'; end if;
  return jsonb_build_object(
    'nombre', trim(d->>'nombre'), 'puesto', trim(d->>'puesto'), 'telefono', coalesce(trim(d->>'telefono'), ''),
    'rol', v_rol, 'autoriza', v_aut, 'pago', v_pago, 'centro', v_centro,
    'credito', case when v_pago = 'tarjeta' then v_credito else 0 end,
    'monto_caja', case when v_rol = 'caja' then v_caja else 0 end,
    'encargado', case when v_rol = 'caja' then coalesce(trim(d->>'encargado'), '') else '' end);
end $$;

-- Solo la usa la función de servidor admin-usuarios (service_role) al crear el usuario de Auth.
create function public.crear_perfil(p_id uuid, p_login text, d jsonb) returns void language plpgsql security definer set search_path = '' as $$
declare n jsonb := public._normalizar_perfil(p_id, d);
begin
  if p_login !~ '^[a-z0-9._-]{3,}$' then raise exception 'Usuario: mínimo 3 caracteres, sin espacios ni tildes'; end if;
  insert into public.perfiles (id, login, nombre, puesto, telefono, rol, autoriza, pago, centro, credito, monto_caja, encargado, cambiar_clave)
  values (p_id, p_login, n->>'nombre', n->>'puesto', n->>'telefono', n->>'rol', nullif(n->>'autoriza','')::uuid, n->>'pago', n->>'centro',
          (n->>'credito')::numeric, (n->>'monto_caja')::numeric, n->>'encargado', true);
end $$;

create function public.actualizar_usuario(p_id uuid, d jsonb) returns void language plpgsql security definer set search_path = '' as $$
declare n jsonb;
begin
  if public.mi_rol() is distinct from 'contabilidad' then raise exception 'Solo contabilidad administra usuarios'; end if;
  if not exists (select 1 from public.perfiles where id = p_id) then raise exception 'Usuario no existe'; end if;
  n := public._normalizar_perfil(p_id, d);
  if p_id = (select auth.uid()) and n->>'rol' <> 'contabilidad' then raise exception 'No puede quitarse a sí mismo el rol de contabilidad'; end if;
  update public.perfiles set nombre = n->>'nombre', puesto = n->>'puesto', telefono = n->>'telefono', rol = n->>'rol',
    autoriza = nullif(n->>'autoriza','')::uuid, pago = n->>'pago', centro = n->>'centro', credito = (n->>'credito')::numeric,
    monto_caja = (n->>'monto_caja')::numeric, encargado = n->>'encargado'
  where id = p_id;
  if n->>'rol' not in ('lider','autorizador','admin') then
    update public.perfiles set autoriza = null where autoriza = p_id;
  end if;
end $$;

create function public.desbloquear_usuario(p_id uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.mi_rol() is distinct from 'contabilidad' then raise exception 'Solo contabilidad administra usuarios'; end if;
  update public.perfiles set bloqueado = false, intentos = 0 where id = p_id;
end $$;

create function public.activar_usuario(p_id uuid, p_activo boolean) returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.mi_rol() is distinct from 'contabilidad' then raise exception 'Solo contabilidad administra usuarios'; end if;
  if p_id = (select auth.uid()) and not p_activo then raise exception 'No puede desactivarse a sí mismo'; end if;
  update public.perfiles set activo = p_activo where id = p_id;
end $$;

-- ============ Gastos ============
create function public.guardar_gasto(d jsonb) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  u public.perfiles; g public.gastos;
  v_id uuid := coalesce(nullif(d->>'id','')::uuid, gen_random_uuid());
  v_fecha date := nullif(d->>'fecha','')::date;
  v_per text; v_c text := d->>'concepto';
  v_valor numeric := nullif(d->>'valor','')::numeric;
  v_n int := greatest(coalesce(nullif(d->>'n_personas','')::int, 1), 1);
  v_empresa text := coalesce(trim(d->>'empresa'), '');
  v_personas text := coalesce(trim(d->>'personas'), '');
  v_coment text := coalesce(trim(d->>'comentario'), '');
  v_fuera boolean := coalesce((d->>'fuera')::boolean, false);
  v_medio text := d->>'medio';
  v_foto text := nullif(d->>'foto_path','');
  v_cliente boolean := v_c in ('comida_cliente','cafe_cliente');
  v_tope numeric; existe boolean;
begin
  if coalesce(public.mi_rol(), '') not in ('vendedor','lider','caja') then raise exception 'No autorizado'; end if;
  select * into u from public.perfiles where id = (select auth.uid());
  if v_fecha is null then raise exception 'Ingrese la fecha del ticket'; end if;
  if v_fecha > public.hoy_co() then raise exception 'La fecha no puede ser futura'; end if;
  v_per := to_char(v_fecha, 'YYYY-MM');
  select * into g from public.gastos where id = v_id;
  existe := found;
  if existe then
    if g.user_id <> u.id then raise exception 'No autorizado'; end if;
    if not public.gasto_editable(g) then raise exception 'Este gasto ya no se puede editar'; end if;
    if g.periodo <> v_per then raise exception 'La fecha debe quedar en el mismo mes del gasto'; end if;
  elsif public.estado_periodo(u.id, v_per) <> 'abierto' then
    raise exception 'El periodo % ya fue enviado; no admite gastos nuevos', v_per;
  end if;
  if v_c is null or v_c not in ('desayuno','almuerzo','comida_cliente','cafe_cliente','peaje','combustible','parqueadero','obsequio','hospedaje') then raise exception 'Concepto no válido'; end if;
  if v_valor is null or v_valor <= 0 then raise exception 'Ingrese el valor'; end if;
  if v_cliente and (v_empresa = '' or v_personas = '') then raise exception 'Empresa y nombres de las personas requeridos'; end if;
  if v_c = 'obsequio' and v_empresa = '' then raise exception 'Nombre del cliente requerido'; end if;
  if v_c in ('desayuno','almuerzo') and not v_fuera then raise exception 'Comida individual solo aplica fuera de la ciudad o con pernocta'; end if;
  if not exists (select 1 from public.centros where nombre = d->>'centro') then raise exception 'Centro de costos no válido'; end if;
  if not (case u.pago when 'caja' then v_medio = 'caja' when 'anticipo' then v_medio in ('anticipo','tarjeta') else v_medio in ('tarjeta','efectivo') end) then
    raise exception 'Medio de pago no válido'; end if;
  select valor into v_tope from public.topes where concepto = v_c;
  if v_tope is not null and (case when v_cliente then v_valor / v_n else v_valor end) > v_tope and v_coment = '' then
    raise exception 'Escriba el motivo del sobrepresupuesto'; end if;
  if v_foto is null or v_foto <> u.id::text || '/' || v_id::text || '.jpg'
     or not exists (select 1 from storage.objects where bucket_id = 'tickets' and name = v_foto) then
    raise exception 'Adjunte la foto del ticket'; end if;
  if existe then
    update public.gastos set fecha = v_fecha, concepto = v_c, valor = v_valor, centro = d->>'centro', medio = v_medio,
      empresa = case when v_cliente or v_c = 'obsequio' then v_empresa else '' end,
      personas = case when v_cliente then v_personas else '' end, n_personas = case when v_cliente then v_n else 1 end,
      cliente = v_cliente, fuera = v_fuera, factura = coalesce((d->>'factura')::boolean, false), comentario = v_coment,
      foto_path = v_foto, corregido = corregido or estado = 'devuelto', estado = 'borrador'
    where id = v_id;
  else
    insert into public.gastos (id, user_id, periodo, fecha, concepto, valor, centro, medio, empresa, personas, n_personas, cliente, fuera, factura, comentario, foto_path)
    values (v_id, u.id, v_per, v_fecha, v_c, v_valor, d->>'centro', v_medio,
      case when v_cliente or v_c = 'obsequio' then v_empresa else '' end, case when v_cliente then v_personas else '' end,
      case when v_cliente then v_n else 1 end, v_cliente, v_fuera, coalesce((d->>'factura')::boolean, false), v_coment, v_foto);
  end if;
  return v_id;
end $$;

create function public.eliminar_gasto(p_id uuid) returns text language plpgsql security definer set search_path = '' as $$
declare g public.gastos;
begin
  select * into g from public.gastos where id = p_id;
  if not found or g.user_id <> (select auth.uid()) or public.mi_rol() is null then raise exception 'No autorizado'; end if;
  if not public.gasto_editable(g) then raise exception 'Este gasto ya no se puede eliminar'; end if;
  delete from public.gastos where id = p_id;
  return g.foto_path;
end $$;

create function public.enviar_periodo(p_periodo text) returns int language plpgsql security definer set search_path = '' as $$
declare u public.perfiles; ep text; n int;
begin
  if coalesce(public.mi_rol(), '') not in ('vendedor','lider','caja') then raise exception 'No autorizado'; end if;
  select * into u from public.perfiles where id = (select auth.uid());
  if u.autoriza is null or not exists (select 1 from public.perfiles where id = u.autoriza and activo) then
    raise exception 'No tiene autorizador asignado. Pida a contabilidad que lo defina.'; end if;
  ep := public.estado_periodo(u.id, p_periodo);
  if ep not in ('abierto','devuelto') then raise exception 'El periodo ya fue enviado'; end if;
  if exists (select 1 from public.gastos where user_id = u.id and periodo = p_periodo and estado = 'devuelto') then
    raise exception 'Faltan gastos devueltos por corregir o eliminar'; end if;
  update public.gastos set estado = 'enviado' where user_id = u.id and periodo = p_periodo and estado = 'borrador';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'No hay gastos por enviar'; end if;
  insert into public.periodos (user_id, periodo, estado, enviado, envios) values (u.id, p_periodo, 'enviado', public.hoy_co(), 1)
  on conflict (user_id, periodo) do update set estado = 'enviado', enviado = public.hoy_co(), envios = public.periodos.envios + 1;
  return n;
end $$;

-- p_items: [{"id": "...", "comentario": "..."}]
create function public.resolver_gastos(p_user uuid, p_periodo text, p_accion text, p_items jsonb) returns text language plpgsql security definer set search_path = '' as $$
declare it jsonb; g public.gastos; com text;
begin
  if not public.autorizo_a(p_user) then raise exception 'No autorizado'; end if;
  if public.estado_periodo(p_user, p_periodo) <> 'enviado' then raise exception 'El periodo no está en revisión'; end if;
  if p_accion not in ('aprobar','devolver') then raise exception 'Acción no válida'; end if;
  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then raise exception 'Seleccione gastos'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    select * into g from public.gastos where id = (it->>'id')::uuid;
    if not found or g.user_id <> p_user or g.periodo <> p_periodo or g.estado <> 'enviado' then raise exception 'Gasto no válido para revisión'; end if;
    if p_accion = 'aprobar' then
      update public.gastos set estado = 'aprobado' where id = g.id;
    else
      com := coalesce(trim(it->>'comentario'), '');
      if com = '' then raise exception 'Escriba el comentario de cada gasto devuelto'; end if;
      update public.gastos set estado = 'devuelto', devolucion = com where id = g.id;
    end if;
  end loop;
  if exists (select 1 from public.gastos where user_id = p_user and periodo = p_periodo and estado = 'enviado') then return 'parcial'; end if;
  if exists (select 1 from public.gastos where user_id = p_user and periodo = p_periodo and estado = 'devuelto') then
    update public.periodos set estado = 'devuelto' where user_id = p_user and periodo = p_periodo;
    return 'devuelto';
  end if;
  update public.periodos set estado = 'autorizado', autorizado = public.hoy_co() where user_id = p_user and periodo = p_periodo;
  return 'autorizado';
end $$;

-- ============ Anticipos ============
create function public.solicitar_anticipo(p_monto numeric, p_motivo text) returns uuid language plpgsql security definer set search_path = '' as $$
declare u public.perfiles; v_id uuid;
begin
  if coalesce(public.mi_rol(), '') not in ('vendedor','lider') then raise exception 'No autorizado'; end if;
  select * into u from public.perfiles where id = (select auth.uid());
  if u.pago is distinct from 'anticipo' then raise exception 'Su tipo de pago no es anticipo'; end if;
  if u.autoriza is null then raise exception 'No tiene jefe/autorizador asignado'; end if;
  if coalesce(p_monto, 0) <= 0 then raise exception 'Ingrese el monto'; end if;
  if coalesce(trim(p_motivo), '') = '' then raise exception 'Escriba el motivo'; end if;
  if exists (select 1 from public.anticipos where user_id = u.id and estado in ('solicitado','autorizado','depositado')) then
    raise exception 'Tiene un anticipo sin comprobar'; end if;
  insert into public.anticipos (user_id, monto, motivo, fecha) values (u.id, p_monto, trim(p_motivo), public.hoy_co()) returning id into v_id;
  return v_id;
end $$;

create function public.resolver_anticipo(p_id uuid, p_ok boolean, p_motivo text) returns void language plpgsql security definer set search_path = '' as $$
declare a public.anticipos;
begin
  select * into a from public.anticipos where id = p_id;
  if not found or not public.autorizo_a(a.user_id) then raise exception 'No autorizado'; end if;
  if a.estado <> 'solicitado' then raise exception 'El anticipo ya fue resuelto'; end if;
  if p_ok then
    update public.anticipos set estado = 'autorizado', autorizado = public.hoy_co(), autorizado_por = (select auth.uid()) where id = p_id;
  else
    if coalesce(trim(p_motivo), '') = '' then raise exception 'Escriba el motivo del rechazo'; end if;
    update public.anticipos set estado = 'rechazado', rechazo = trim(p_motivo), autorizado_por = (select auth.uid()) where id = p_id;
  end if;
end $$;

create function public.depositar_anticipo(p_id uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.mi_rol() is distinct from 'contabilidad' then raise exception 'Solo contabilidad'; end if;
  update public.anticipos set estado = 'depositado', depositado = public.hoy_co() where id = p_id and estado = 'autorizado';
  if not found then raise exception 'El anticipo no está autorizado'; end if;
end $$;

-- ============ Contabilidad ============
-- Devuelve las rutas de fotos a borrar del Storage (las borra la app tras finiquitar).
create function public.finiquitar(p_user uuid, p_periodo text) returns text[] language plpgsql security definer set search_path = '' as $$
declare u public.perfiles; v_total numeric; v_dep numeric; fotos text[];
begin
  if public.mi_rol() is distinct from 'contabilidad' then raise exception 'Solo contabilidad'; end if;
  if public.estado_periodo(p_user, p_periodo) <> 'autorizado' then raise exception 'El periodo no está autorizado'; end if;
  select * into u from public.perfiles where id = p_user;
  select coalesce(sum(valor), 0), array_remove(array_agg(foto_path), null) into v_total, fotos
    from public.gastos where user_id = p_user and periodo = p_periodo;
  if u.pago = 'anticipo' then
    select coalesce(sum(monto), 0) into v_dep from public.anticipos where user_id = p_user and estado = 'depositado';
    update public.anticipos set estado = 'comprobado', periodo = p_periodo where user_id = p_user and estado = 'depositado';
    update public.periodos set anticipo = v_dep, diferencia = v_dep - v_total where user_id = p_user and periodo = p_periodo;
  end if;
  update public.gastos set estado = 'pagado', foto_archivada = foto_archivada or foto_path is not null, foto_path = null
    where user_id = p_user and periodo = p_periodo;
  update public.periodos set estado = 'finiquitado', finiquitado = public.hoy_co(), total = v_total where user_id = p_user and periodo = p_periodo;
  return coalesce(fotos, '{}');
end $$;

create function public.marcar_exportado(p_periodo text) returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.mi_rol() is distinct from 'contabilidad' then raise exception 'Solo contabilidad'; end if;
  update public.periodos set exportado = public.hoy_co() where periodo = p_periodo and estado = 'autorizado';
end $$;

-- ============ Administración ============
create function public.guardar_topes(d jsonb) returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.mi_rol() is distinct from 'admin' then raise exception 'Solo administración'; end if;
  delete from public.topes where true;
  insert into public.topes (concepto, valor)
    select key, value::numeric from jsonb_each_text(d) where nullif(value, '') is not null and value::numeric > 0;
end $$;

create function public.agregar_centro(p_nombre text) returns void language plpgsql security definer set search_path = '' as $$
begin
  if public.mi_rol() is distinct from 'admin' then raise exception 'Solo administración'; end if;
  if coalesce(trim(p_nombre), '') = '' then raise exception 'Escriba el nombre'; end if;
  insert into public.centros (nombre) values (trim(p_nombre)) on conflict do nothing;
end $$;

-- ============ Permisos de ejecución ============
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prokind = 'f' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
grant execute on function public.hay_usuarios() to anon;
grant execute on function public.login_fallido(text) to anon;
revoke execute on function public.crear_perfil(uuid, text, jsonb) from authenticated;
revoke execute on function public._normalizar_perfil(uuid, jsonb) from authenticated;
grant execute on function public.crear_perfil(uuid, text, jsonb) to service_role;
grant execute on function public._normalizar_perfil(uuid, jsonb) to service_role;

-- Las tablas solo se leen desde la app; toda escritura pasa por las funciones de arriba.
revoke insert, update, delete, truncate on all tables in schema public from anon, authenticated;
revoke all on all tables in schema public from anon;
