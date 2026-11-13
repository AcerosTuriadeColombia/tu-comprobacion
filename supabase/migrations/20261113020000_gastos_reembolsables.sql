-- Gastos reembolsables: medio 'propio' (dinero de la persona) con motivo.
-- Reemplaza 'efectivo' (no había datos). La liquidación separa tarjeta, anticipo, caja y reembolso.
alter table public.gastos drop constraint gastos_medio_check;
alter table public.gastos add constraint gastos_medio_check check (medio in ('tarjeta','anticipo','caja','propio'));
alter table public.gastos add column motivo_reembolso text not null default ''
  check (motivo_reembolso in ('','no_acepta_tarjeta','cupo_agotado','anticipo_agotado','otro'));
alter table public.gastos add column reembolso_detalle text not null default '';
alter table public.periodos add column reembolso numeric;

create or replace function public.guardar_gasto(d jsonb) returns uuid language plpgsql security definer set search_path = '' as $$
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
  v_motivo text := coalesce(nullif(d->>'motivo_reembolso',''), '');
  v_det text := coalesce(trim(d->>'reembolso_detalle'), '');
  v_tope numeric; existe boolean;
begin
  if coalesce(public.mi_rol(), '') not in ('vendedor','lider','caja') then raise exception 'No autorizado'; end if;
  select * into u from public.perfiles where id = (select auth.uid());
  if v_fecha is null then raise exception 'Ingrese la fecha del ticket'; end if;
  if v_fecha > public.hoy_co() then raise exception 'La fecha no puede ser futura'; end if;
  v_per := public.periodo_de(v_fecha);
  select * into g from public.gastos where id = v_id;
  existe := found;
  if existe then
    if g.user_id <> u.id then raise exception 'No autorizado'; end if;
    if not public.gasto_editable(g) then raise exception 'Este gasto ya no se puede editar'; end if;
    if g.periodo <> v_per then raise exception 'La fecha debe quedar dentro del mismo periodo del gasto'; end if;
  elsif public.estado_periodo(u.id, v_per) <> 'abierto' then
    raise exception 'El periodo % ya fue enviado; no admite gastos nuevos', v_per;
  end if;
  if v_c is null or v_c not in ('desayuno','almuerzo','comida_cliente','cafe_cliente','peaje','combustible','parqueadero','taxi','vuelo','obsequio','hospedaje') then raise exception 'Concepto no válido'; end if;
  if v_valor is null or v_valor <= 0 then raise exception 'Ingrese el valor'; end if;
  if v_cliente and (v_empresa = '' or v_personas = '') then raise exception 'Empresa y nombres de las personas requeridos'; end if;
  if v_c = 'obsequio' and v_empresa = '' then raise exception 'Nombre del cliente requerido'; end if;
  if v_c in ('desayuno','almuerzo') and not v_fuera then raise exception 'Comida individual solo aplica fuera de la ciudad o con pernocta'; end if;
  if not exists (select 1 from public.centros where nombre = d->>'centro') then raise exception 'Centro de costos no válido'; end if;
  if not (v_medio = 'propio' or (case u.pago when 'caja' then v_medio = 'caja' when 'anticipo' then v_medio = 'anticipo' else v_medio = 'tarjeta' end)) then
    raise exception 'Medio de pago no válido'; end if;
  if v_medio = 'propio' then
    if v_motivo not in ('no_acepta_tarjeta','cupo_agotado','anticipo_agotado','otro') then raise exception 'Indique por qué pagó con dinero propio'; end if;
    if v_motivo = 'otro' and v_det = '' then raise exception 'Explique el motivo del reembolso'; end if;
  else
    v_motivo := ''; v_det := '';
  end if;
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
      foto_path = v_foto, motivo_reembolso = v_motivo, reembolso_detalle = v_det, corregido = corregido or estado = 'devuelto', estado = 'borrador'
    where id = v_id;
  else
    insert into public.gastos (id, user_id, periodo, fecha, concepto, valor, centro, medio, empresa, personas, n_personas, cliente, fuera, factura, comentario, foto_path, motivo_reembolso, reembolso_detalle)
    values (v_id, u.id, v_per, v_fecha, v_c, v_valor, d->>'centro', v_medio,
      case when v_cliente or v_c = 'obsequio' then v_empresa else '' end, case when v_cliente then v_personas else '' end,
      case when v_cliente then v_n else 1 end, v_cliente, v_fuera, coalesce((d->>'factura')::boolean, false), v_coment, v_foto, v_motivo, v_det);
  end if;
  return v_id;
end $$;

create or replace function public.finiquitar(p_user uuid, p_periodo text) returns text[] language plpgsql security definer set search_path = '' as $$
declare u public.perfiles; v_total numeric; v_ant numeric; v_reemb numeric; v_dep numeric; fotos text[];
begin
  if public.mi_rol() is distinct from 'contabilidad' then raise exception 'Solo contabilidad'; end if;
  if public.estado_periodo(p_user, p_periodo) <> 'autorizado' then raise exception 'El periodo no está autorizado'; end if;
  select * into u from public.perfiles where id = p_user;
  select coalesce(sum(valor), 0), coalesce(sum(valor) filter (where medio = 'anticipo'), 0), coalesce(sum(valor) filter (where medio = 'propio'), 0),
         array_remove(array_agg(foto_path), null)
    into v_total, v_ant, v_reemb, fotos
    from public.gastos where user_id = p_user and periodo = p_periodo;
  if u.pago = 'anticipo' then
    select coalesce(sum(monto), 0) into v_dep from public.anticipos where user_id = p_user and estado = 'depositado';
    update public.anticipos set estado = 'comprobado', periodo = p_periodo where user_id = p_user and estado = 'depositado';
    -- diferencia > 0: la persona devuelve; < 0: la empresa le deposita el faltante
    update public.periodos set anticipo = v_dep, diferencia = v_dep - v_ant where user_id = p_user and periodo = p_periodo;
  end if;
  update public.gastos set estado = 'pagado', foto_archivada = foto_archivada or foto_path is not null, foto_path = null
    where user_id = p_user and periodo = p_periodo;
  update public.periodos set estado = 'finiquitado', finiquitado = public.hoy_co(), total = v_total, reembolso = v_reemb
    where user_id = p_user and periodo = p_periodo;
  return coalesce(fotos, '{}');
end $$;
