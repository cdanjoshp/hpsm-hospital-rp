-- Prescrição da consulta: uso regular e contexto terapêutico mais completo.
-- Snapshots finalizados permanecem históricos e imutáveis.

with updated_medications as (
  update public.rp_medications medication set
    default_frequency = regexp_replace(medication.default_frequency, ',?[[:space:]]+se[[:space:]]+necess[aá]rio', '', 'gi'),
    default_instructions = case
      when medication.default_instructions ~* '(se|quando|caso)[[:space:]]+necess|conforme[[:space:]]+(a[[:space:]]+)?necessidade|sob[[:space:]]+demanda|(^|[^a-z])prn([^a-z]|$)'
        then 'Administrar na frequência prescrita durante todo o período indicado.'
      else medication.default_instructions
    end,
    default_as_needed = false,
    version = medication.version + 1,
    updated_at = now()
  where medication.default_as_needed
     or medication.default_frequency ~* '(se|quando|caso)[[:space:]]+necess|conforme[[:space:]]+(a[[:space:]]+)?necessidade|sob[[:space:]]+demanda|(^|[^a-z])prn([^a-z]|$)'
     or medication.default_instructions ~* '(se|quando|caso)[[:space:]]+necess|conforme[[:space:]]+(a[[:space:]]+)?necessidade|sob[[:space:]]+demanda|(^|[^a-z])prn([^a-z]|$)'
  returning medication.*
)
insert into public.rp_medication_versions (medication_id, version, snapshot, change_reason)
select medication.id, medication.version,
  to_jsonb(medication) - 'created_at' - 'updated_at',
  'PRESCRICAO_USO_REGULAR_SEM_CONDICIONAL'
from updated_medications medication;

update public.consultation_prescription_items item set
  frequency_snapshot = regexp_replace(item.frequency_snapshot, ',?[[:space:]]+se[[:space:]]+necess[aá]rio', '', 'gi'),
  instructions_snapshot = case
    when item.instructions_snapshot ~* '(se|quando|caso)[[:space:]]+necess|conforme[[:space:]]+(a[[:space:]]+)?necessidade|sob[[:space:]]+demanda|(^|[^a-z])prn([^a-z]|$)'
      then 'Administrar na frequência prescrita durante todo o período indicado.'
    else item.instructions_snapshot
  end,
  updated_at = now()
from public.consultation_prescriptions prescription
where prescription.id = item.prescription_id
  and prescription.status = 'draft'
  and (
    item.frequency_snapshot ~* '(se|quando|caso)[[:space:]]+necess|conforme[[:space:]]+(a[[:space:]]+)?necessidade|sob[[:space:]]+demanda|(^|[^a-z])prn([^a-z]|$)'
    or item.instructions_snapshot ~* '(se|quando|caso)[[:space:]]+necess|conforme[[:space:]]+(a[[:space:]]+)?necessidade|sob[[:space:]]+demanda|(^|[^a-z])prn([^a-z]|$)'
  );

create or replace function private.enforce_required_prescription_use()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.frequency_snapshot ~* '(se|quando|caso)[[:space:]]+necess|conforme[[:space:]]+(a[[:space:]]+)?necessidade|sob[[:space:]]+demanda|(^|[^a-z])prn([^a-z]|$)'
     or new.instructions_snapshot ~* '(se|quando|caso)[[:space:]]+necess|conforme[[:space:]]+(a[[:space:]]+)?necessidade|sob[[:space:]]+demanda|(^|[^a-z])prn([^a-z]|$)' then
    raise exception 'A prescrição deve definir uso regular, sem termos condicionais como “se necessário”.';
  end if;
  return new;
end;
$$;

revoke all on function private.enforce_required_prescription_use()
from public, anon, authenticated, service_role;

drop trigger if exists consultation_prescription_required_use_guard
on public.consultation_prescription_items;
create trigger consultation_prescription_required_use_guard
before insert or update of frequency_snapshot, instructions_snapshot
on public.consultation_prescription_items
for each row execute function private.enforce_required_prescription_use();

create or replace function public.consultation_rollup_reference_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
begin
  if not private.has_permission(v_actor, 'consultations.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'medications', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', medication.id,
        'rp_name', medication.rp_name,
        'reference_name', medication.reference_name,
        'category', medication.category,
        'active', medication.active,
        'controlled', medication.controlled,
        'antibiotic', medication.antibiotic,
        'requires_justification', medication.requires_justification,
        'allowed_body_systems', to_jsonb(medication.allowed_body_systems),
        'allowed_case_tags', to_jsonb(medication.allowed_case_tags),
        'disallowed_case_tags', to_jsonb(medication.disallowed_case_tags),
        'default_dose', medication.default_dose,
        'default_frequency', medication.default_frequency,
        'default_duration', medication.default_duration,
        'default_duration_days', medication.default_duration_days,
        'default_route', medication.default_route,
        'default_instructions', medication.default_instructions,
        'default_doses_per_day', medication.default_doses_per_day,
        'default_as_needed', medication.default_as_needed,
        'version', medication.version
      ) order by lower(medication.rp_name))
      from public.rp_medications medication
      where medication.active
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.consultation_rollup_reference_data()
from public, anon, authenticated, service_role;
grant execute on function public.consultation_rollup_reference_data()
to authenticated;

comment on function private.enforce_required_prescription_use() is
'Bloqueia linguagem de uso condicional em novos itens ou edições de prescrição; todo item prescrito possui frequência regular.';

notify pgrst, 'reload schema';
