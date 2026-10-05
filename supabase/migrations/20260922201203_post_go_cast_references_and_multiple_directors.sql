-- HPSM — Pós-GO: referências de aplicação de gesso e múltiplos Diretores Gerais.
-- Incremental: preserva gessos, identidades profissionais, credenciais e históricos existentes.

-- ---------------------------------------------------------------------------
-- Referências canônicas de aplicação de gesso
-- ---------------------------------------------------------------------------

create table public.clinical_cast_references (
  id bigint generated always as identity primary key,
  body_model text not null,
  body_region text not null,
  laterality text not null,
  game_reference text not null,
  description text not null,
  active boolean not null default true,
  created_by uuid references public.profiles(user_id) on delete set null,
  updated_by uuid references public.profiles(user_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clinical_cast_references_model_check check (body_model in ('male', 'female')),
  constraint clinical_cast_references_region_check check (body_region in ('arm', 'leg', 'rib')),
  constraint clinical_cast_references_laterality_check check (
    (body_region in ('arm', 'leg') and laterality in ('right', 'left'))
    or (body_region = 'rib' and laterality = 'not_applicable')
  ),
  constraint clinical_cast_references_game_reference_check check (
    char_length(btrim(game_reference)) between 1 and 80
  ),
  constraint clinical_cast_references_description_check check (
    char_length(btrim(description)) between 2 and 160
  ),
  constraint clinical_cast_references_combination_key unique (body_model, body_region, laterality)
);

create index clinical_cast_references_created_by_idx
  on public.clinical_cast_references (created_by)
  where created_by is not null;
create index clinical_cast_references_updated_by_idx
  on public.clinical_cast_references (updated_by)
  where updated_by is not null;

create trigger clinical_cast_references_touch_updated_at
before update on public.clinical_cast_references
for each row execute function private.touch_updated_at();

alter table public.clinical_cast_references enable row level security;
alter table public.clinical_cast_references force row level security;

create policy clinical_cast_references_read_authorized
on public.clinical_cast_references for select to authenticated
using (
  (select private.has_permission(private.hpsm_current_actor(), 'casts.view'))
  and (
    active
    or (select private.has_permission(private.hpsm_current_actor(), 'casts.manage'))
  )
);

revoke all on table public.clinical_cast_references from public, anon, authenticated;
grant select on table public.clinical_cast_references to authenticated;

insert into public.clinical_cast_references (
  body_model, body_region, laterality, game_reference, description, created_by, updated_by
)
select seed.body_model, seed.body_region, seed.laterality, seed.game_reference, seed.description,
       actor.user_id, actor.user_id
from (
  values
    ('male',   'leg', 'left',           '245',       'Adesivo 245'),
    ('male',   'arm', 'left',           '223',       'Camiseta 223'),
    ('male',   'leg', 'right',          '246 / 158', 'Adesivo 246 / Sapato 158'),
    ('male',   'rib', 'not_applicable', '659',       'Jaqueta 659'),
    ('male',   'arm', 'right',          '231 / 64',  'Camiseta 231 / Colete 64'),
    ('female', 'leg', 'right',          '262 / 166', 'Adesivo 262 / Sapato 166'),
    ('female', 'leg', 'left',           '262',       'Adesivo 262'),
    ('female', 'arm', 'right',          '303 / 269', 'Camiseta 303 / 269'),
    ('female', 'rib', 'not_applicable', '740',       'Jaqueta 740'),
    ('female', 'arm', 'left',           '64',        'Colete 64')
) as seed(body_model, body_region, laterality, game_reference, description)
left join lateral (
  select profile.user_id
  from public.profiles profile
  where profile.role_code = 'diretor_geral' and profile.status = 'active'
  order by profile.created_at, profile.user_id
  limit 1
) actor on true;

alter table public.clinical_casts
  drop constraint clinical_casts_body_region_check;
alter table public.clinical_casts
  add constraint clinical_casts_body_region_check check (
    body_region in ('hand', 'wrist', 'forearm', 'elbow', 'arm', 'foot', 'ankle', 'leg', 'knee', 'rib', 'other')
  );

alter table public.clinical_casts
  add column body_model_snapshot text,
  add column reference_body_region_snapshot text,
  add column reference_laterality_snapshot text,
  add column game_reference_snapshot text,
  add column reference_description_snapshot text,
  add constraint clinical_casts_reference_snapshot_check check (
    (
      body_model_snapshot is null
      and reference_body_region_snapshot is null
      and reference_laterality_snapshot is null
      and game_reference_snapshot is null
      and reference_description_snapshot is null
    )
    or (
      body_model_snapshot in ('male', 'female')
      and reference_body_region_snapshot is not null
      and reference_laterality_snapshot is not null
      and (
        (game_reference_snapshot is null and reference_description_snapshot is null)
        or (game_reference_snapshot is not null and reference_description_snapshot is not null)
      )
    )
  );

create or replace function public.clinical_cast_reference_catalog(
  p_include_inactive boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_result jsonb;
begin
  v_actor := private.hpsm_current_actor();
  if v_actor is null or not private.has_permission(v_actor, 'casts.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if coalesce(p_include_inactive, false) and not private.has_permission(v_actor, 'casts.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', reference.id,
    'body_model', reference.body_model,
    'body_region', reference.body_region,
    'laterality', reference.laterality,
    'game_reference', reference.game_reference,
    'description', reference.description,
    'active', reference.active,
    'updated_at', reference.updated_at,
    'updated_by_name', updated_by.display_name
  ) order by
    case reference.body_model when 'male' then 1 else 2 end,
    case reference.body_region when 'arm' then 1 when 'leg' then 2 else 3 end,
    reference.laterality), '[]'::jsonb)
  into v_result
  from public.clinical_cast_references reference
  left join public.profiles updated_by on updated_by.user_id = reference.updated_by
  where coalesce(p_include_inactive, false) or reference.active;

  return v_result;
end;
$$;

create or replace function public.upsert_clinical_cast_reference(
  p_reference_id bigint,
  p_body_model text,
  p_body_region text,
  p_laterality text,
  p_game_reference text,
  p_description text,
  p_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_old public.clinical_cast_references;
  v_row public.clinical_cast_references;
  v_game_reference text := btrim(coalesce(p_game_reference, ''));
  v_description text := btrim(coalesce(p_description, ''));
  v_actor_passport text;
begin
  v_actor := private.hpsm_current_actor();
  if v_actor is null or not private.has_permission(v_actor, 'casts.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if p_body_model not in ('male', 'female') then
    raise exception 'Modelo inválido.' using errcode = '22023';
  end if;
  if p_body_region not in ('arm', 'leg', 'rib') then
    raise exception 'Região inválida.' using errcode = '22023';
  end if;
  if (p_body_region in ('arm', 'leg') and p_laterality not in ('right', 'left'))
     or (p_body_region = 'rib' and p_laterality <> 'not_applicable') then
    raise exception 'Lateralidade incompatível com a região.' using errcode = '22023';
  end if;
  if char_length(v_game_reference) not between 1 and 80 then
    raise exception 'Informe uma referência de até 80 caracteres.' using errcode = '22023';
  end if;
  if char_length(v_description) not between 2 and 160 then
    raise exception 'Informe uma descrição entre 2 e 160 caracteres.' using errcode = '22023';
  end if;
  if p_active is null then
    raise exception 'Informe o estado da referência.' using errcode = '22023';
  end if;

  if p_reference_id is null then
    insert into public.clinical_cast_references (
      body_model, body_region, laterality, game_reference, description, active, created_by, updated_by
    ) values (
      p_body_model, p_body_region, p_laterality, v_game_reference, v_description, p_active, v_actor, v_actor
    ) returning * into v_row;
  else
    select * into v_old
    from public.clinical_cast_references
    where id = p_reference_id
    for update;
    if not found then
      raise exception 'Referência de gesso não localizada.' using errcode = 'P0002';
    end if;

    update public.clinical_cast_references
    set body_model = p_body_model,
        body_region = p_body_region,
        laterality = p_laterality,
        game_reference = v_game_reference,
        description = v_description,
        active = p_active,
        updated_by = v_actor
    where id = p_reference_id
    returning * into v_row;
  end if;

  select profile.passport into v_actor_passport
  from public.profiles profile where profile.user_id = v_actor;

  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values
  ) values (
    v_actor,
    v_actor_passport,
    case when p_reference_id is null then 'CAST_REFERENCE_CREATED' else 'CAST_REFERENCE_UPDATED' end,
    'clinical_cast_references',
    v_row.id::text,
    case when p_reference_id is null then null else to_jsonb(v_old) end,
    to_jsonb(v_row)
  );

  return to_jsonb(v_row);
exception
  when unique_violation then
    raise exception 'Já existe uma referência para este modelo, região e lateralidade.' using errcode = '23505';
end;
$$;

-- A assinatura antiga não aceita o modelo e não pode criar registros sem snapshot.
create or replace function public.create_clinical_cast(
  p_patient_id bigint,
  p_attendance_id bigint,
  p_body_region text,
  p_laterality text,
  p_applied_at timestamptz,
  p_expected_removal_at timestamptz,
  p_application_notes text default null,
  p_confirm_duplicate boolean default false
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'Atualize a página e selecione o modelo de aplicação.' using errcode = '22023';
end;
$$;

create or replace function public.create_clinical_cast(
  p_patient_id bigint,
  p_attendance_id bigint,
  p_body_region text,
  p_laterality text,
  p_body_model text,
  p_applied_at timestamptz,
  p_expected_removal_at timestamptz,
  p_application_notes text default null,
  p_confirm_duplicate boolean default false
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_cast public.clinical_casts;
  v_reference public.clinical_cast_references;
  v_notes text := nullif(btrim(coalesce(p_application_notes, '')), '');
begin
  v_actor := private.hpsm_current_actor();
  if v_actor is null
     or not private.has_permission(v_actor, 'casts.create')
     or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles profile where profile.user_id = v_actor and profile.status = 'active') then
    raise exception 'Profissional responsável não localizado.';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.';
  end if;
  if p_body_model not in ('male', 'female') then
    raise exception 'Modelo inválido.';
  end if;
  if p_body_region not in ('hand', 'wrist', 'forearm', 'elbow', 'arm', 'foot', 'ankle', 'leg', 'knee', 'rib', 'other') then
    raise exception 'Região inválida.';
  end if;
  if p_laterality not in ('right', 'left', 'bilateral', 'not_applicable') then
    raise exception 'Lateralidade inválida.';
  end if;
  if p_body_region = 'rib' and p_laterality <> 'not_applicable' then
    raise exception 'Costela não utiliza lateralidade.';
  end if;
  if p_applied_at is null then raise exception 'Informe a data e hora da aplicação.'; end if;
  if p_expected_removal_at is null or p_expected_removal_at <= p_applied_at then
    raise exception 'A previsão de retirada deve ser posterior à aplicação.';
  end if;
  if v_notes is not null and char_length(v_notes) > 1000 then
    raise exception 'A observação deve ter no máximo 1000 caracteres.';
  end if;
  if p_attendance_id is not null and not exists (
    select 1 from public.attendances attendance
    where attendance.id = p_attendance_id
      and attendance.patient_id = p_patient_id
      and attendance.status = 'completed'
  ) then
    raise exception 'O atendimento informado não pertence ao paciente ou não está concluído.';
  end if;
  if not coalesce(p_confirm_duplicate, false) and exists (
    select 1 from public.clinical_casts active_cast
    where active_cast.patient_id = p_patient_id
      and active_cast.body_region = p_body_region
      and active_cast.laterality = p_laterality
      and active_cast.status = 'in_use'
  ) then
    raise exception 'O paciente já possui um gesso em uso na mesma região e lateralidade.'
      using errcode = '23505', detail = 'HPSM_ACTIVE_CAST_DUPLICATE';
  end if;

  select * into v_reference
  from public.clinical_cast_references reference
  where reference.body_model = p_body_model
    and reference.body_region = p_body_region
    and reference.laterality = p_laterality
    and reference.active;

  insert into public.clinical_casts (
    patient_id, attendance_id, body_region, laterality, status,
    applied_at, applied_by, expected_removal_at, application_notes, created_by,
    body_model_snapshot, reference_body_region_snapshot, reference_laterality_snapshot,
    game_reference_snapshot, reference_description_snapshot
  ) values (
    p_patient_id, p_attendance_id, p_body_region, p_laterality, 'in_use',
    p_applied_at, v_actor, p_expected_removal_at, v_notes, v_actor,
    p_body_model, p_body_region, p_laterality,
    v_reference.game_reference, v_reference.description
  ) returning * into v_cast;

  perform private.audit_cast_action(
    v_actor, 'CAST_APPLIED', v_cast.id, null,
    jsonb_build_object(
      'patient_id', v_cast.patient_id,
      'attendance_id', v_cast.attendance_id,
      'body_region', v_cast.body_region,
      'laterality', v_cast.laterality,
      'body_model', v_cast.body_model_snapshot,
      'game_reference', v_cast.game_reference_snapshot,
      'reference_description', v_cast.reference_description_snapshot,
      'applied_at', v_cast.applied_at,
      'expected_removal_at', v_cast.expected_removal_at,
      'status', v_cast.status
    )
  );
  return v_cast.id;
end;
$$;

create or replace function public.clinical_cast_detail(p_cast_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
  v_result jsonb;
begin
  v_actor := private.hpsm_current_actor();
  if v_actor is null or not private.has_permission(v_actor, 'casts.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', cast_record.id,
    'patient_id', cast_record.patient_id,
    'patient_name', patient.name,
    'patient_passport', patient.passport,
    'attendance_id', cast_record.attendance_id,
    'attendance_created_at', attendance.created_at,
    'attendance_total', attendance.total,
    'attendance_summary', case when attendance.id is null then null else coalesce((
      select string_agg(item.service_name || case when item.quantity > 1 then ' ×' || item.quantity::text else '' end, ', ' order by item.id)
      from public.attendance_items item where item.attendance_id = attendance.id
    ), 'Atendimento sem itens') end,
    'body_region', cast_record.body_region,
    'laterality', cast_record.laterality,
    'body_model_snapshot', cast_record.body_model_snapshot,
    'reference_body_region_snapshot', cast_record.reference_body_region_snapshot,
    'reference_laterality_snapshot', cast_record.reference_laterality_snapshot,
    'game_reference_snapshot', cast_record.game_reference_snapshot,
    'reference_description_snapshot', cast_record.reference_description_snapshot,
    'status', cast_record.status,
    'applied_at', cast_record.applied_at,
    'applied_by', cast_record.applied_by,
    'applied_by_name', applied.display_name,
    'applied_by_position', applied_position.name,
    'expected_removal_at', cast_record.expected_removal_at,
    'application_notes', cast_record.application_notes,
    'removed_at', cast_record.removed_at,
    'removed_by', cast_record.removed_by,
    'removed_by_name', removed.display_name,
    'removed_by_position', removed_position.name,
    'removal_notes', cast_record.removal_notes,
    'cancelled_at', cast_record.cancelled_at,
    'cancelled_by', cast_record.cancelled_by,
    'cancelled_by_name', cancelled.display_name,
    'cancelled_by_position', cancelled_position.name,
    'cancellation_reason', cast_record.cancellation_reason,
    'created_at', cast_record.created_at,
    'updated_at', cast_record.updated_at
  ) into v_result
  from public.clinical_casts cast_record
  join public.patients patient on patient.id = cast_record.patient_id
  left join public.attendances attendance on attendance.id = cast_record.attendance_id
  join public.profiles applied on applied.user_id = cast_record.applied_by
  left join public.staff_positions applied_position on applied_position.id = applied.position_id
  left join public.profiles removed on removed.user_id = cast_record.removed_by
  left join public.staff_positions removed_position on removed_position.id = removed.position_id
  left join public.profiles cancelled on cancelled.user_id = cast_record.cancelled_by
  left join public.staff_positions cancelled_position on cancelled_position.id = cancelled.position_id
  where cast_record.id = p_cast_id;

  if v_result is null then raise exception 'Registro de gesso não localizado.'; end if;
  return v_result;
end;
$$;

revoke all on function public.clinical_cast_reference_catalog(boolean) from public, anon, authenticated, service_role;
revoke all on function public.upsert_clinical_cast_reference(bigint, text, text, text, text, text, boolean) from public, anon, authenticated, service_role;
revoke all on function public.create_clinical_cast(bigint, bigint, text, text, timestamptz, timestamptz, text, boolean) from public, anon, authenticated, service_role;
revoke all on function public.create_clinical_cast(bigint, bigint, text, text, text, timestamptz, timestamptz, text, boolean) from public, anon, authenticated, service_role;
revoke all on function public.clinical_cast_detail(bigint) from public, anon, authenticated, service_role;
grant execute on function public.clinical_cast_reference_catalog(boolean) to authenticated;
grant execute on function public.upsert_clinical_cast_reference(bigint, text, text, text, text, text, boolean) to authenticated;
grant execute on function public.create_clinical_cast(bigint, bigint, text, text, text, timestamptz, timestamptz, text, boolean) to authenticated;
grant execute on function public.clinical_cast_detail(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- Diretoria: o cargo de nível 14 deixa de ser singular.
-- ---------------------------------------------------------------------------

drop index if exists public.profiles_single_general_director;

create or replace function public.override_staff_position(
  p_employee_id uuid,
  p_to_position_id bigint,
  p_note text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor public.profiles;
  v_actor_position public.staff_positions;
  v_employee public.profiles;
  v_from public.staff_positions;
  v_to public.staff_positions;
  v_history public.staff_position_history;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  select * into v_actor from public.profiles where user_id = p_actor_id;
  select * into v_actor_position from public.staff_positions where id = v_actor.position_id;
  if not found
     or v_actor.role_code <> 'diretor_geral'
     or v_actor.status <> 'active'
     or v_actor_position.level <> 14 then
    raise exception using errcode = '42501', message = 'Somente o Diretor Geral pode alterar cargos diretamente.';
  end if;
  if p_employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'O Diretor Geral não pode alterar o próprio cargo por este fluxo.';
  end if;
  if v_note is not null and char_length(v_note) not between 2 and 2000 then
    raise exception using errcode = '22023', message = 'A observação deve possuir entre 2 e 2000 caracteres.';
  end if;

  select * into v_employee from public.profiles where user_id = p_employee_id for update;
  if not found or v_employee.status = 'inactive' or v_employee.role_code = 'diretor_geral' then
    raise exception using errcode = '22023', message = 'Colaborador indisponível para alteração direta de cargo.';
  end if;
  select * into v_from from public.staff_positions where id = v_employee.position_id;
  select * into v_to from public.staff_positions where id = p_to_position_id and active;
  if not found then
    raise exception using errcode = '22023', message = 'Cargo de destino inválido.';
  end if;
  if v_employee.position_id = v_to.id then
    raise exception using errcode = '22023', message = 'Selecione um cargo diferente do atual.';
  end if;

  perform set_config('hpsm.position_change_authorized', 'true', true);
  update public.profiles
  set position_id = v_to.id,
      role_code = case when v_to.level = 14 then 'diretor_geral' else role_code end,
      updated_by = p_actor_id,
      updated_at = now()
  where user_id = p_employee_id and position_id is not distinct from v_employee.position_id;
  if not found then
    raise exception using errcode = '40001', message = 'O cargo foi alterado durante a operação. Atualize a página.';
  end if;

  update public.staff_promotion_reviews
  set status = 'cancelled', decided_by = p_actor_id, decided_at = now(),
      decision_note = 'Encerrada por alteração direta de cargo pelo Diretor Geral.', updated_at = now()
  where employee_id = p_employee_id and status in ('pending', 'deferred');

  insert into public.staff_position_history (
    employee_id, from_position_id, to_position_id, event_type, decided_by, note
  ) values (
    p_employee_id, v_employee.position_id, v_to.id, 'override', p_actor_id, v_note
  ) returning * into v_history;

  insert into public.notifications (
    kind, recipient_id, priority, title, body, action_url, created_by
  ) values (
    'personal', p_employee_id, 'important', 'Cargo alterado pela Direção Geral',
    format('Seu cargo foi alterado para %s. Consulte o histórico no Meu RH.', v_to.name),
    '/meu-rh', p_actor_id
  );

  return to_jsonb(v_history);
end;
$$;

create or replace function public.appoint_staff_position(
  p_employee_id uuid,
  p_to_position_id bigint,
  p_note text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_level smallint;
  v_employee public.profiles;
  v_from public.staff_positions;
  v_to public.staff_positions;
  v_history public.staff_position_history;
begin
  v_actor_level := private.current_position_level(p_actor_id);
  select * into v_employee from public.profiles where user_id = p_employee_id for update;
  select * into v_from from public.staff_positions where id = v_employee.position_id;
  select * into v_to from public.staff_positions where id = p_to_position_id and active;
  if not found or v_employee.status = 'inactive' or v_from.level + 1 <> v_to.level or v_to.level < 11 then
    raise exception using errcode = '22023', message = 'A nomeação deve avançar somente um cargo na hierarquia.';
  end if;
  if char_length(btrim(coalesce(p_note, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe a fundamentação da nomeação.';
  end if;
  if v_to.level in (11, 12) and not (
      private.has_permission(p_actor_id, 'appointments.manage') and v_actor_level >= 13
    ) then
    raise exception using errcode = '42501', message = 'Somente os níveis 13 e 14 podem realizar esta nomeação.';
  elsif v_to.level = 13 and not (
      private.has_permission(p_actor_id, 'appointments.manage') and v_actor_level = 14
    ) then
    raise exception using errcode = '42501', message = 'Somente o Diretor Geral pode nomear o Diretor Clínico.';
  elsif v_to.level = 14 and not (
      private.has_permission(p_actor_id, 'succession.manage') and v_actor_level = 14 and p_actor_id <> p_employee_id
    ) then
    raise exception using errcode = '42501', message = 'A nomeação para Diretor Geral exige outro Diretor Geral ativo.';
  end if;

  perform set_config('hpsm.position_change_authorized', 'true', true);
  update public.profiles
  set position_id = v_to.id,
      role_code = case when v_to.level = 14 then 'diretor_geral' else role_code end,
      updated_by = p_actor_id,
      updated_at = now()
  where user_id = p_employee_id;

  insert into public.staff_position_history (
    employee_id, from_position_id, to_position_id, event_type, decided_by, note
  ) values (
    p_employee_id, v_from.id, v_to.id,
    'appointment',
    p_actor_id, btrim(p_note)
  ) returning * into v_history;
  insert into public.notifications (
    kind, recipient_id, priority, title, body, action_url, created_by
  ) values (
    'personal', p_employee_id, 'important', 'Novo cargo registrado',
    format('Sua nomeação para %s foi registrada.', v_to.name), '/meu-rh', p_actor_id
  );
  return to_jsonb(v_history);
end;
$$;

revoke all on function public.override_staff_position(uuid, bigint, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.appoint_staff_position(uuid, bigint, text, uuid) from public, anon, authenticated, service_role;
grant execute on function public.override_staff_position(uuid, bigint, text, uuid) to service_role;
grant execute on function public.appoint_staff_position(uuid, bigint, text, uuid) to service_role;

-- A nomeação individual do HPSM foi omitida da distribuição pública.


comment on table public.clinical_cast_references is
  'Referências editáveis por modelo, região e lateralidade usadas no registro clínico de gesso.';
comment on column public.clinical_casts.body_model_snapshot is
  'Modelo selecionado no momento da aplicação; nulo apenas para registros anteriores ao rollup.';
comment on column public.clinical_casts.game_reference_snapshot is
  'ID no jogo congelado no momento da aplicação; não acompanha edições futuras do catálogo.';
comment on column public.clinical_casts.reference_description_snapshot is
  'Descrição da peça congelada no momento da aplicação; não acompanha edições futuras do catálogo.';
