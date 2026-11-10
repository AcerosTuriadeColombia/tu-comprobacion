-- Cabeza de la empresa: puede no tener autorizador; sus comprobaciones y anticipos van directo a contabilidad.
alter table public.perfiles add column sin_autorizador boolean not null default false;

create or replace function public._normalizar_perfil(p_id uuid, d jsonb) returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_rol text := d->>'rol';
  comprueba boolean := v_rol in ('vendedor','lider','caja');
  v_directo boolean := comprueba and coalesce((d->>'sin_autorizador')::boolean, false);
  v_aut uuid := case when v_directo then null else nullif(d->>'autoriza', '')::uuid end;
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
  if comprueba and v_aut is null and not v_directo then raise exception 'Asigne quién lo autoriza'; end if;
  if comprueba and v_centro is null then raise exception 'Defina el centro de costos'; end if;
  if v_centro is not null and not exists (select 1 from public.centros where nombre = v_centro) then raise exception 'Centro de costos no existe'; end if;
  v_pago := case when v_rol = 'caja' then 'caja' when comprueba then nullif(d->>'pago', '') else null end;
  if comprueba and v_rol <> 'caja' and (v_pago is null or v_pago not in ('tarjeta','anticipo')) then raise exception 'Defina el tipo de pago'; end if;
  if v_pago = 'tarjeta' and v_credito <= 0 then raise exception 'Ingrese el cupo de la tarjeta'; end if;
  if v_rol = 'caja' and v_caja <= 0 then raise exception 'Ingrese el monto fijo de la caja'; end if;
  return jsonb_build_object(
    'nombre', trim(d->>'nombre'), 'puesto', trim(d->>'puesto'), 'telefono', coalesce(trim(d->>'telefono'), ''),
    'rol', v_rol, 'autoriza', v_aut, 'sin_autorizador', v_directo, 'pago', v_pago, 'centro', v_centro,
    'credito', case when v_pago = 'tarjeta' then v_credito else 0 end,
    'monto_caja', case when v_rol = 'caja' then v_caja else 0 end,
    'encargado', case when v_rol = 'caja' then coalesce(trim(d->>'encargado'), '') else '' end);
end $$;

create or replace function public.crear_perfil(p_id uuid, p_login text, d jsonb) returns void language plpgsql security definer set search_path = '' as $$
declare n jsonb := public._normalizar_perfil(p_id, d);
begin
  if p_login !~ '^[a-z0-9._-]{3,}$' then raise exception 'Usuario: mínimo 3 caracteres, sin espacios ni tildes'; end if;
  insert into public.perfiles (id, login, nombre, puesto, telefono, rol, autoriza, sin_autorizador, pago, centro, credito, monto_caja, encargado, cambiar_clave)
  values (p_id, p_login, n->>'nombre', n->>'puesto', n->>'telefono', n->>'rol', nullif(n->>'autoriza','')::uuid, (n->>'sin_autorizador')::boolean,
          n->>'pago', n->>'centro', (n->>'credito')::numeric, (n->>'monto_caja')::numeric, n->>'encargado', true);
end $$;

create or replace function public.actualizar_usuario(p_id uuid, d jsonb) returns void language plpgsql security definer set search_path = '' as $$
declare n jsonb;
begin
  if public.mi_rol() is distinct from 'contabilidad' then raise exception 'Solo contabilidad administra usuarios'; end if;
  if not exists (select 1 from public.perfiles where id = p_id) then raise exception 'Usuario no existe'; end if;
  n := public._normalizar_perfil(p_id, d);
  if p_id = (select auth.uid()) and n->>'rol' <> 'contabilidad' then raise exception 'No puede quitarse a sí mismo el rol de contabilidad'; end if;
  update public.perfiles set nombre = n->>'nombre', puesto = n->>'puesto', telefono = n->>'telefono', rol = n->>'rol',
    autoriza = nullif(n->>'autoriza','')::uuid, sin_autorizador = (n->>'sin_autorizador')::boolean, pago = n->>'pago', centro = n->>'centro',
    credito = (n->>'credito')::numeric, monto_caja = (n->>'monto_caja')::numeric, encargado = n->>'encargado'
  where id = p_id;
  if n->>'rol' not in ('lider','autorizador','admin') then
    update public.perfiles set autoriza = null where autoriza = p_id;
  end if;
end $$;

-- Devuelve el número de gastos enviados. Sin autorizador: quedan aprobados y el periodo pasa a contabilidad.
create or replace function public.enviar_periodo(p_periodo text) returns int language plpgsql security definer set search_path = '' as $$
declare u public.perfiles; ep text; n int;
begin
  if coalesce(public.mi_rol(), '') not in ('vendedor','lider','caja') then raise exception 'No autorizado'; end if;
  select * into u from public.perfiles where id = (select auth.uid());
  if not u.sin_autorizador and (u.autoriza is null or not exists (select 1 from public.perfiles where id = u.autoriza and activo)) then
    raise exception 'No tiene autorizador asignado. Pida a contabilidad que lo defina.'; end if;
  ep := public.estado_periodo(u.id, p_periodo);
  if ep not in ('abierto','devuelto') then raise exception 'El periodo ya fue enviado'; end if;
  if exists (select 1 from public.gastos where user_id = u.id and periodo = p_periodo and estado = 'devuelto') then
    raise exception 'Faltan gastos devueltos por corregir o eliminar'; end if;
  update public.gastos set estado = case when u.sin_autorizador then 'aprobado' else 'enviado' end
    where user_id = u.id and periodo = p_periodo and estado = 'borrador';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'No hay gastos por enviar'; end if;
  if u.sin_autorizador then
    insert into public.periodos (user_id, periodo, estado, enviado, envios, autorizado) values (u.id, p_periodo, 'autorizado', public.hoy_co(), 1, public.hoy_co())
    on conflict (user_id, periodo) do update set estado = 'autorizado', enviado = public.hoy_co(), autorizado = public.hoy_co(), envios = public.periodos.envios + 1;
  else
    insert into public.periodos (user_id, periodo, estado, enviado, envios) values (u.id, p_periodo, 'enviado', public.hoy_co(), 1)
    on conflict (user_id, periodo) do update set estado = 'enviado', enviado = public.hoy_co(), envios = public.periodos.envios + 1;
  end if;
  return n;
end $$;

create or replace function public.solicitar_anticipo(p_monto numeric, p_motivo text) returns uuid language plpgsql security definer set search_path = '' as $$
declare u public.perfiles; v_id uuid;
begin
  if coalesce(public.mi_rol(), '') not in ('vendedor','lider') then raise exception 'No autorizado'; end if;
  select * into u from public.perfiles where id = (select auth.uid());
  if u.pago is distinct from 'anticipo' then raise exception 'Su tipo de pago no es anticipo'; end if;
  if u.autoriza is null and not u.sin_autorizador then raise exception 'No tiene jefe/autorizador asignado'; end if;
  if coalesce(p_monto, 0) <= 0 then raise exception 'Ingrese el monto'; end if;
  if coalesce(trim(p_motivo), '') = '' then raise exception 'Escriba el motivo'; end if;
  if exists (select 1 from public.anticipos where user_id = u.id and estado in ('solicitado','autorizado','depositado')) then
    raise exception 'Tiene un anticipo sin comprobar'; end if;
  insert into public.anticipos (user_id, monto, motivo, fecha, estado, autorizado)
  values (u.id, p_monto, trim(p_motivo), public.hoy_co(),
          case when u.sin_autorizador then 'autorizado' else 'solicitado' end,
          case when u.sin_autorizador then public.hoy_co() end)
  returning id into v_id;
  return v_id;
end $$;
