-- Pós-GO: partes do mesmo membro reutilizam uma única referência de aplicação.
-- A região clínica detalhada permanece em clinical_casts.body_region; somente a
-- referência do jogo e a detecção de duplicidade usam o grupo braço/perna/costela.

set lock_timeout = '5s';
set statement_timeout = '60s';

create or replace function private.clinical_cast_application_region(p_body_region text)
returns text
language sql
immutable
strict
set search_path = ''
as $$
  select case
    when p_body_region in ('hand', 'wrist', 'forearm', 'elbow', 'arm') then 'arm'
    when p_body_region in ('foot', 'ankle', 'leg', 'knee') then 'leg'
    when p_body_region = 'rib' then 'rib'
    else p_body_region
  end;
$$;

revoke all on function private.clinical_cast_application_region(text)
from public, anon, authenticated, service_role;

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
  v_application_region text;
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

  v_application_region := private.clinical_cast_application_region(p_body_region);

  if not coalesce(p_confirm_duplicate, false) and exists (
    select 1 from public.clinical_casts active_cast
    where active_cast.patient_id = p_patient_id
      and private.clinical_cast_application_region(active_cast.body_region) = v_application_region
      and active_cast.laterality = p_laterality
      and active_cast.status = 'in_use'
  ) then
    raise exception 'O paciente já possui um gesso em uso no mesmo grupo de aplicação e lateralidade.'
      using errcode = '23505', detail = 'HPSM_ACTIVE_CAST_DUPLICATE';
  end if;

  select * into v_reference
  from public.clinical_cast_references reference
  where reference.body_model = p_body_model
    and reference.body_region = v_application_region
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
    p_body_model, v_application_region, p_laterality,
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
      'reference_body_region', v_cast.reference_body_region_snapshot,
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

revoke all on function private.clinical_cast_application_region(text)
from public, anon, authenticated, service_role;
revoke all on function public.create_clinical_cast(bigint, bigint, text, text, text, timestamptz, timestamptz, text, boolean)
from public, anon, authenticated, service_role;
grant execute on function public.create_clinical_cast(bigint, bigint, text, text, text, timestamptz, timestamptz, text, boolean)
to authenticated;

comment on function private.clinical_cast_application_region(text) is
  'Resolve a parte clínica no grupo único de aplicação do jogo: braço, perna, costela ou outro.';
comment on function public.create_clinical_cast(bigint, bigint, text, text, text, timestamptz, timestamptz, text, boolean) is
  'Cria ficha clínica preservando a parte detalhada e congelando a referência compartilhada do grupo anatômico.';
