begin;

create temporary table post1_pricing_context as
with active_sessions as (
  select
    profile.user_id,
    session.id as session_id,
    private.has_permission(profile.user_id, 'catalog.manage') as can_manage
  from public.profiles profile
  join lateral (
    select active_session.id
    from auth.sessions active_session
    where active_session.user_id = profile.user_id
      and (active_session.not_after is null or active_session.not_after > now())
    order by active_session.created_at desc
    limit 1
  ) session on true
  where profile.status = 'active'
    and not profile.must_change_password
), manager as (
  select user_id, session_id from active_sessions where can_manage limit 1
), limited as (
  select user_id, session_id from active_sessions where not can_manage limit 1
), service as (
  select id, unit_price from public.service_catalog order by sort_order, id limit 1
), history as (
  select md5(coalesce(jsonb_agg(jsonb_build_array(id, unit_price, discount_percent, line_total) order by id)::text, '[]')) as checksum
  from public.attendance_items
)
select
  manager.user_id as manager_id,
  manager.session_id as manager_session_id,
  limited.user_id as limited_id,
  limited.session_id as limited_session_id,
  service.id as service_id,
  service.unit_price as original_price,
  history.checksum as history_checksum
from manager, limited, service, history;

do $$
begin
  if (select count(*) from post1_pricing_context) <> 1 then
    raise exception 'O teste requer sessões válidas com e sem catalog.manage.';
  end if;
end;
$$;

grant select on post1_pricing_context to authenticated;
set local role authenticated;

do $$
declare
  v_actor uuid := (select manager_id from post1_pricing_context);
  v_session uuid := (select manager_session_id from post1_pricing_context);
  v_service bigint := (select service_id from post1_pricing_context);
  v_original numeric := (select original_price from post1_pricing_context);
  v_result jsonb;
  v_history_checksum text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_actor,
    'role', 'authenticated',
    'session_id', v_session
  )::text, true);

  v_result := public.update_catalog_unit_price(v_service, v_original + 1.23);
  if (v_result ->> 'service_id')::bigint <> v_service
     or (v_result ->> 'unit_price')::numeric <> round(v_original + 1.23, 2)
     or (select unit_price from public.service_catalog where id = v_service) <> round(v_original + 1.23, 2) then
    raise exception 'A alteração rápida não gravou somente o novo preço esperado.';
  end if;

  v_result := public.update_catalog_discounts_bulk(jsonb_build_array(
    jsonb_build_object('plan_code', 'plano_saude', 'discount_percent', 15),
    jsonb_build_object('plan_code', 'parceiros_hp', 'discount_percent', 25),
    jsonb_build_object('plan_code', 'policiais_arcanjos', 'discount_percent', 20)
  ));

  if (v_result ->> 'service_count')::integer <> (select count(*) from public.service_catalog) then
    raise exception 'A operação em massa não confirmou todos os itens.';
  end if;
  if exists (
    select 1
    from public.plan_discounts
    where discount_percent <> case plan_code
      when 'plano_saude' then 15
      when 'parceiros_hp' then 25
      when 'policiais_arcanjos' then 20
    end
  ) then
    raise exception 'Nem todos os descontos receberam o percentual informado.';
  end if;

  select md5(coalesce(jsonb_agg(jsonb_build_array(id, unit_price, discount_percent, line_total) order by id)::text, '[]'))
  into v_history_checksum
  from public.attendance_items;
  if v_history_checksum is distinct from (select history_checksum from post1_pricing_context) then
    raise exception 'O histórico financeiro foi alterado pela atualização do catálogo.';
  end if;

  begin
    perform public.update_catalog_discounts_bulk('[{"plan_code":"plano_saude","discount_percent":15}]'::jsonb);
    raise exception 'Operação em massa incompleta foi aceita.';
  exception when invalid_parameter_value then null;
  end;
end;
$$;

do $$
declare
  v_actor uuid := (select limited_id from post1_pricing_context);
  v_session uuid := (select limited_session_id from post1_pricing_context);
  v_service bigint := (select service_id from post1_pricing_context);
begin
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', v_actor,
    'role', 'authenticated',
    'session_id', v_session
  )::text, true);
  begin
    perform public.update_catalog_unit_price(v_service, 1);
    raise exception 'Usuário sem catalog.manage alterou o preço.';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.update_catalog_discounts_bulk(jsonb_build_array(
      jsonb_build_object('plan_code', 'plano_saude', 'discount_percent', 15),
      jsonb_build_object('plan_code', 'parceiros_hp', 'discount_percent', 25),
      jsonb_build_object('plan_code', 'policiais_arcanjos', 'discount_percent', 20)
    ));
    raise exception 'Usuário sem catalog.manage alterou os descontos.';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
rollback;

select jsonb_build_object(
  'phase', 'post1_catalog_quick_pricing',
  'status', 'ok',
  'quick_price', true,
  'bulk_discounts', true,
  'history_preserved', true,
  'permission_enforced', true,
  'residue', false
) as result;
