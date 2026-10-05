-- Amplia a venda avulsa somente para Tratamento e itens de Deslocamento.
-- Atendimento com paciente, preços, descontos e snapshots permanecem inalterados.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.walk_in_service_allowed(
  p_service_code text,
  p_category text
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $$
  select lower(btrim(coalesce(p_category, ''))) in ('insumos', 'medicamentos', 'deslocamento')
    or lower(btrim(coalesce(p_service_code, ''))) in ('tratamento', 'desloc_norte', 'desloc_sul');
$$;

revoke all on function private.walk_in_service_allowed(text, text)
from public, anon, authenticated, service_role;
grant execute on function private.walk_in_service_allowed(text, text) to service_role;

create or replace function private.create_attendance(
  p_patient_id bigint,
  p_items jsonb,
  p_notes text default null,
  p_benefit_code text default null,
  p_partnership_id bigint default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attendance_id bigint;
  v_discount numeric(18, 2);
  v_input_count integer;
  v_limit integer;
  v_limited_item_name text;
  v_patient_name text;
  v_patient_passport text;
  v_plan_code text;
  v_plan_name text;
  v_partnership_name text;
  v_subtotal numeric(18, 2);
  v_valid_count integer;
  v_priced_items jsonb;
begin
  perform private.hpsm_current_actor();
  if not private.has_permission((select auth.uid()), 'attendances.create') then
    raise exception 'Você não possui permissão para registrar atendimentos.';
  end if;

  if p_patient_id is null then
    v_patient_name := 'Venda avulsa';
    v_patient_passport := '—';
  else
    select patient.name, patient.passport into v_patient_name, v_patient_passport
    from public.patients patient where patient.id = p_patient_id;
    if not found then raise exception 'Paciente não localizado.'; end if;
  end if;

  v_plan_code := nullif(btrim(coalesce(p_benefit_code, '')), '');
  if v_plan_code is not null then
    select plan.name into v_plan_name from public.benefit_plans plan where plan.code = v_plan_code;
    if not found then raise exception 'Benefício inválido ou indisponível.'; end if;
  end if;

  if v_plan_code = 'parceiros_hp' then
    if p_patient_id is null or p_partnership_id is null then
      raise exception 'Selecione a parceria responsável por este benefício.' using errcode = '22023';
    end if;
    select partnership.name into v_partnership_name
    from public.partnerships partnership
    join public.patient_partnerships membership
      on membership.partnership_id = partnership.id
     and membership.patient_id = p_patient_id
     and membership.status = 'active'
    where partnership.id = p_partnership_id and partnership.status = 'active';
    if not found then
      raise exception 'O paciente não possui vínculo ativo com a parceria selecionada.' using errcode = '22023';
    end if;
  elsif p_partnership_id is not null then
    raise exception 'A parceria só pode ser informada com o benefício Parceiro do HP.' using errcode = '22023';
  end if;

  if p_notes is not null and char_length(p_notes) > 1000 then raise exception 'Observação muito longa.'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'Inclua ao menos um item.'; end if;
  v_input_count := jsonb_array_length(p_items);
  if v_input_count < 1 or v_input_count > 50 then raise exception 'Quantidade de itens inválida.'; end if;
  if exists (select 1 from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer) group by service_id having count(*) <> 1) then
    raise exception 'Cada item deve aparecer apenas uma vez.';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer)
    join public.service_catalog catalog on catalog.id = item.service_id
    where catalog.code = 'plano_saude_convenio' and item.quantity <> 1
  ) then raise exception 'O plano de saúde pode aparecer somente uma vez no atendimento.'; end if;
  if p_patient_id is null and exists (
    select 1 from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer)
    join public.service_catalog catalog on catalog.id = item.service_id
    where not private.walk_in_service_allowed(catalog.code, catalog.category)
  ) then raise exception 'Venda avulsa aceita somente insumos, medicamentos, tratamento e deslocamentos.'; end if;
  if not private.has_permission((select auth.uid()), 'catalog.view')
     or (p_patient_id is not null and not private.has_permission((select auth.uid()), 'patients.view')) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  perform 1 from public.service_catalog where id in (
    select service_id from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer)
  ) for share;
  perform 1 from public.plan_discounts where plan_code = v_plan_code and service_id in (
    select service_id from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer)
  ) for share;

  select catalog.name, private.attendance_item_limit(catalog.code, v_plan_code)
  into v_limited_item_name, v_limit
  from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer)
  join public.service_catalog catalog on catalog.id = item.service_id
  where private.attendance_item_limit(catalog.code, v_plan_code) is not null
    and item.quantity > private.attendance_item_limit(catalog.code, v_plan_code)
  order by catalog.id
  limit 1;
  if found then
    raise exception 'Quantidade de % acima do limite permitido para este atendimento.', v_limited_item_name
      using errcode = '22023', hint = format('O máximo permitido é %s.', v_limit);
  end if;

  with input_items as (
    select service_id, quantity from jsonb_to_recordset(p_items) item(service_id bigint, quantity integer)
  )
  select count(*), coalesce(sum(catalog.unit_price * input_items.quantity), 0),
    coalesce(sum(round(catalog.unit_price * input_items.quantity * coalesce(discount.discount_percent, 0) / 100, 2)), 0),
    coalesce(jsonb_agg(jsonb_build_object(
      'service_id', catalog.id, 'service_name', catalog.name, 'unit_price', catalog.unit_price,
      'quantity', input_items.quantity, 'discount_percent', coalesce(discount.discount_percent, 0)
    )), '[]'::jsonb)
  into v_valid_count, v_subtotal, v_discount, v_priced_items
  from input_items
  join public.service_catalog catalog on catalog.id = input_items.service_id and catalog.active
  left join public.plan_discounts discount on discount.service_id = catalog.id and discount.plan_code = v_plan_code
  where input_items.quantity between 1 and 99;
  if v_valid_count <> v_input_count then raise exception 'Um dos itens não está disponível.'; end if;

  insert into public.attendances (
    patient_id, patient_name, patient_passport, plan_code, plan_name, partnership_id, partnership_name,
    subtotal, discount, notes, performed_by
  ) values (
    p_patient_id, v_patient_name, v_patient_passport, v_plan_code, v_plan_name, p_partnership_id, v_partnership_name,
    v_subtotal, v_discount, nullif(btrim(coalesce(p_notes, '')), ''), (select auth.uid())
  ) returning id into v_attendance_id;

  insert into public.attendance_items (attendance_id, service_id, service_name, unit_price, quantity, discount_percent)
  select v_attendance_id, priced.service_id, priced.service_name, priced.unit_price, priced.quantity, priced.discount_percent
  from jsonb_to_recordset(v_priced_items) priced(
    service_id bigint, service_name text, unit_price numeric, quantity smallint, discount_percent numeric
  );
  return v_attendance_id;
end;
$$;

revoke all on function private.create_attendance(bigint, jsonb, text, text, bigint)
from public, anon, authenticated, service_role;
grant execute on function private.create_attendance(bigint, jsonb, text, text, bigint)
to authenticated, service_role;

comment on function private.walk_in_service_allowed(text, text) is
  'Regra canônica dos itens aceitos em venda avulsa sem paciente.';
