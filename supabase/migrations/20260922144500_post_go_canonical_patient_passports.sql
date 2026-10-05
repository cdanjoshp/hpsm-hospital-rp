-- Pós-GO: identidade canônica de pacientes em quatro dígitos.
-- Não altera passaportes profissionais nem reescreve snapshots clínicos/financeiros.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.normalize_patient_passport(p_value text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_value text := btrim(coalesce(p_value, ''));
begin
  if v_value !~ '^[0-9]{1,4}$' then
    raise exception 'Informe um passaporte válido com 1 a 4 números.' using errcode = '22023';
  end if;
  return lpad(v_value, 4, '0');
end;
$$;

create or replace function private.normalize_patient_search(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_value is null then null
    when btrim(p_value) ~ '^[0-9]{1,4}$' then lpad(btrim(p_value), 4, '0')
    else btrim(p_value)
  end;
$$;

revoke all on function private.normalize_patient_passport(text) from public, anon, authenticated, service_role;
revoke all on function private.normalize_patient_search(text) from public, anon, authenticated, service_role;

create table if not exists public.patient_identity_reconciliations (
  id bigint generated always as identity primary key,
  survivor_patient_id bigint not null references public.patients(id) on delete restrict,
  merged_patient_id bigint not null,
  previous_passport text not null,
  canonical_passport text not null,
  reason text not null,
  merged_snapshot jsonb not null,
  reconciled_at timestamptz not null default now(),
  constraint patient_identity_reconciliations_passport_check
    check (canonical_passport ~ '^[0-9]{4}$')
);

create index if not exists patient_identity_reconciliations_survivor_idx
  on public.patient_identity_reconciliations (survivor_patient_id, reconciled_at desc);

alter table public.patient_identity_reconciliations enable row level security;
alter table public.patient_identity_reconciliations force row level security;
revoke all on public.patient_identity_reconciliations from public, anon, authenticated, service_role;

do $$
declare
  duplicate_row public.patients%rowtype;
  survivor_row public.patients%rowtype;
begin
  for duplicate_row in
    select duplicate.*
    from public.patients duplicate
    join public.patients canonical
      on canonical.passport = private.normalize_patient_passport(duplicate.passport)
     and canonical.id <> duplicate.id
    where duplicate.passport ~ '^[0-9]{1,3}$'
      and lower(regexp_replace(btrim(duplicate.name), '\\s+', ' ', 'g'))
          = lower(regexp_replace(btrim(canonical.name), '\\s+', ' ', 'g'))
      and duplicate.birth_date is not distinct from canonical.birth_date
      and duplicate.phone is not distinct from canonical.phone
      and duplicate.emergency_contact_name is not distinct from canonical.emergency_contact_name
      and duplicate.emergency_contact_phone is not distinct from canonical.emergency_contact_phone
  loop
    select * into strict survivor_row
    from public.patients
    where passport = private.normalize_patient_passport(duplicate_row.passport);

    if exists (select 1 from public.attendances where patient_id = duplicate_row.id)
       or exists (select 1 from public.clinical_casts where patient_id = duplicate_row.id)
       or exists (select 1 from public.clinical_exam_document_shares where created_by_patient_id = duplicate_row.id)
       or exists (select 1 from public.clinical_exam_documents where created_by_patient_id = duplicate_row.id)
       or exists (select 1 from public.clinical_exams where patient_id = duplicate_row.id)
       or exists (select 1 from public.hospitalizations where patient_id = duplicate_row.id)
       or exists (select 1 from public.medical_certificates where patient_id = duplicate_row.id)
       or exists (select 1 from public.partnership_pending_beneficiaries where created_by_patient_id = duplicate_row.id or canceled_by_patient_id = duplicate_row.id or resolved_patient_id = duplicate_row.id)
       or exists (select 1 from public.partnership_responsible_history where responsible_patient_id = duplicate_row.id or previous_patient_id = duplicate_row.id)
       or exists (select 1 from public.partnerships where responsible_patient_id = duplicate_row.id)
       or exists (select 1 from public.patient_health_plan_requests where patient_id = duplicate_row.id)
       or exists (select 1 from public.patient_partnerships where patient_id = duplicate_row.id or linked_by_patient_id = duplicate_row.id or unlinked_by_patient_id = duplicate_row.id)
       or exists (select 1 from public.patient_portal_login_attempts where patient_id = duplicate_row.id)
       or exists (select 1 from public.patient_portal_sessions where patient_id = duplicate_row.id) then
      raise exception 'Conflito de passaporte % possui vínculos e exige conciliação manual.', duplicate_row.passport;
    end if;

    insert into public.patient_identity_reconciliations (
      survivor_patient_id, merged_patient_id, previous_passport, canonical_passport, reason, merged_snapshot
    ) values (
      survivor_row.id,
      duplicate_row.id,
      duplicate_row.passport,
      survivor_row.passport,
      'Duplicata inequívoca sem vínculos; dados de identidade coincidentes.',
      to_jsonb(duplicate_row)
    );

    delete from public.patients where id = duplicate_row.id;
  end loop;

  if exists (
    select 1
    from public.patients patient
    where patient.passport ~ '^[0-9]{1,4}$'
    group by private.normalize_patient_passport(patient.passport)
    having count(*) > 1
  ) then
    raise exception 'Existem colisões de passaporte que exigem revisão manual.';
  end if;

  if exists (select 1 from public.patients where passport !~ '^[0-9]{1,4}$') then
    raise exception 'Existem passaportes inválidos que exigem revisão manual.';
  end if;
end;
$$;

update public.patients
set passport = private.normalize_patient_passport(passport)
where passport !~ '^[0-9]{4}$';

alter table public.patients
  drop constraint if exists patients_passport_check,
  add constraint patients_passport_check check (passport ~ '^[0-9]{4}$');

create or replace function private.canonicalize_patient_passport()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.passport := private.normalize_patient_passport(new.passport);
  return new;
end;
$$;

revoke all on function private.canonicalize_patient_passport() from public, anon, authenticated, service_role;

drop trigger if exists patients_canonicalize_passport on public.patients;
create trigger patients_canonicalize_passport
before insert or update of passport on public.patients
for each row execute function private.canonicalize_patient_passport();

comment on column public.patients.passport is
  'Identificador canônico do paciente: texto com exatamente quatro dígitos, 0000–9999.';

-- Pré-beneficiários também usam a identidade canônica, sem criar pacientes.
update public.partnership_pending_beneficiaries
set passport = private.normalize_patient_passport(passport)
where passport !~ '^[0-9]{4}$';

alter table public.partnership_pending_beneficiaries
  drop constraint if exists partnership_pending_passport_check,
  add constraint partnership_pending_passport_check check (passport ~ '^[0-9]{4}$');

drop trigger if exists partnership_pending_canonicalize_passport on public.partnership_pending_beneficiaries;
create trigger partnership_pending_canonicalize_passport
before insert or update of passport on public.partnership_pending_beneficiaries
for each row execute function private.canonicalize_patient_passport();

-- Normaliza lotes de parcerias antes da resolução por passaporte.
alter function private.partnership_apply_people(bigint, jsonb, text, uuid, bigint, text)
  rename to partnership_apply_people_pre_canonical;

create function private.partnership_apply_people(
  p_partnership_id bigint,
  p_people jsonb,
  p_origin text,
  p_actor_user_id uuid,
  p_actor_patient_id bigint,
  p_source text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_people jsonb;
begin
  if p_people is null or jsonb_typeof(p_people) <> 'array' then
    return private.partnership_apply_people_pre_canonical(
      p_partnership_id, p_people, p_origin, p_actor_user_id, p_actor_patient_id, p_source
    );
  end if;

  select coalesce(jsonb_agg(
    case
      when jsonb_typeof(entry.value) = 'object'
       and btrim(coalesce(entry.value ->> 'passport', '')) ~ '^[0-9]{1,4}$'
      then jsonb_set(
        entry.value,
        '{passport}',
        to_jsonb(private.normalize_patient_passport(entry.value ->> 'passport')),
        true
      )
      else entry.value
    end
    order by entry.ordinality
  ), '[]'::jsonb)
  into v_people
  from jsonb_array_elements(p_people) with ordinality as entry(value, ordinality);

  return private.partnership_apply_people_pre_canonical(
    p_partnership_id, v_people, p_origin, p_actor_user_id, p_actor_patient_id, p_source
  );
end;
$$;

revoke all on function private.partnership_apply_people(bigint, jsonb, text, uuid, bigint, text)
from public, anon, authenticated, service_role;
revoke all on function private.partnership_apply_people_pre_canonical(bigint, jsonb, text, uuid, bigint, text)
from public, anon, authenticated, service_role;

-- Busca rápida: qualquer entrada numérica de 1–4 dígitos vira uma chave exata de quatro dígitos.
alter function public.hpsm_patient_quick_lookup(text, integer)
  rename to hpsm_patient_quick_lookup_pre_canonical;

create function public.hpsm_patient_quick_lookup(p_passport text, p_limit integer default 8)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select public.hpsm_patient_quick_lookup_pre_canonical(
    private.normalize_patient_passport(p_passport),
    p_limit
  );
$$;

revoke all on function public.hpsm_patient_quick_lookup_pre_canonical(text, integer)
from public, anon, authenticated, service_role;
revoke all on function public.hpsm_patient_quick_lookup(text, integer)
from public, anon, authenticated, service_role;
grant execute on function public.hpsm_patient_quick_lookup(text, integer) to authenticated;

-- O Portal aceita 7/40/503/0532, mas sempre autentica pela chave canônica.
alter function public.patient_portal_create_session(text, date, text, text, text)
  rename to patient_portal_create_session_pre_canonical;

create function public.patient_portal_create_session(
  p_passport text,
  p_birth_date date,
  p_token_hash text,
  p_origin_hash text,
  p_client_hash text default null
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select public.patient_portal_create_session_pre_canonical(
    private.normalize_patient_passport(p_passport),
    p_birth_date,
    p_token_hash,
    p_origin_hash,
    p_client_hash
  );
$$;

revoke all on function public.patient_portal_create_session_pre_canonical(text, date, text, text, text)
from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_create_session(text, date, text, text, text)
from public, anon, authenticated, service_role;
grant execute on function public.patient_portal_create_session(text, date, text, text, text) to service_role;

-- Busca de pacientes em parcerias preserva nomes e normaliza apenas consultas inteiramente numéricas.
alter function public.hpsm_partnership_patient_lookup(text, integer)
  rename to hpsm_partnership_patient_lookup_pre_canonical;

create function public.hpsm_partnership_patient_lookup(p_search text, p_limit integer default 8)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select public.hpsm_partnership_patient_lookup_pre_canonical(
    private.normalize_patient_search(p_search),
    p_limit
  );
$$;

revoke all on function public.hpsm_partnership_patient_lookup_pre_canonical(text, integer)
from public, anon, authenticated, service_role;
revoke all on function public.hpsm_partnership_patient_lookup(text, integer)
from public, anon, authenticated, service_role;
grant execute on function public.hpsm_partnership_patient_lookup(text, integer) to authenticated;

-- Wrappers mantêm as regras e permissões atuais dos módulos; apenas ajustam a chave de busca.
alter function public.clinical_cast_page(text, text, integer, integer)
  rename to clinical_cast_page_pre_canonical;
create function public.clinical_cast_page(
  p_search text default null,
  p_status text default 'in_use',
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb language sql stable security definer set search_path = '' as $$
  select public.clinical_cast_page_pre_canonical(private.normalize_patient_search(p_search), p_status, p_limit, p_offset);
$$;
revoke all on function public.clinical_cast_page_pre_canonical(text, text, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.clinical_cast_page(text, text, integer, integer) from public, anon, authenticated, service_role;
grant execute on function public.clinical_cast_page(text, text, integer, integer) to authenticated;

alter function public.clinical_exam_page(text, text, bigint, bigint, text, date, date, integer, integer)
  rename to clinical_exam_page_pre_canonical;
create function public.clinical_exam_page(
  p_search text default null,
  p_passport text default null,
  p_category_id bigint default null,
  p_exam_type_id bigint default null,
  p_status text default null,
  p_date_from date default null,
  p_date_to date default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb language sql stable security definer set search_path = '' as $$
  select public.clinical_exam_page_pre_canonical(
    private.normalize_patient_search(p_search),
    case when nullif(btrim(coalesce(p_passport, '')), '') is null then null else private.normalize_patient_passport(p_passport) end,
    p_category_id, p_exam_type_id, p_status, p_date_from, p_date_to, p_limit, p_offset
  );
$$;
revoke all on function public.clinical_exam_page_pre_canonical(text, text, bigint, bigint, text, date, date, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.clinical_exam_page(text, text, bigint, bigint, text, date, date, integer, integer) from public, anon, authenticated, service_role;
grant execute on function public.clinical_exam_page(text, text, bigint, bigint, text, date, date, integer, integer) to authenticated, service_role;

alter function public.medical_certificate_page(text, text, date, date, uuid, integer, integer)
  rename to medical_certificate_page_pre_canonical;
create function public.medical_certificate_page(
  p_search text default null,
  p_status text default null,
  p_date_from date default null,
  p_date_to date default null,
  p_created_by uuid default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb language sql stable security definer set search_path = '' as $$
  select public.medical_certificate_page_pre_canonical(
    private.normalize_patient_search(p_search), p_status, p_date_from, p_date_to, p_created_by, p_limit, p_offset
  );
$$;
revoke all on function public.medical_certificate_page_pre_canonical(text, text, date, date, uuid, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.medical_certificate_page(text, text, date, date, uuid, integer, integer) from public, anon, authenticated, service_role;
grant execute on function public.medical_certificate_page(text, text, date, date, uuid, integer, integer) to authenticated;

alter function public.hospitalization_history_page(text, text, bigint, text, date, date, integer, integer)
  rename to hospitalization_history_page_pre_canonical;
create function public.hospitalization_history_page(
  p_search text default null,
  p_source text default null,
  p_bed_id bigint default null,
  p_status text default null,
  p_date_from date default null,
  p_date_to date default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb language sql stable security definer set search_path = '' as $$
  select public.hospitalization_history_page_pre_canonical(
    private.normalize_patient_search(p_search), p_source, p_bed_id, p_status, p_date_from, p_date_to, p_limit, p_offset
  );
$$;
revoke all on function public.hospitalization_history_page_pre_canonical(text, text, bigint, text, date, date, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.hospitalization_history_page(text, text, bigint, text, date, date, integer, integer) from public, anon, authenticated, service_role;
grant execute on function public.hospitalization_history_page(text, text, bigint, text, date, date, integer, integer) to authenticated;

alter function public.hpsm_partnership_member_page(bigint, text, text, integer, integer)
  rename to hpsm_partnership_member_page_pre_canonical;
create function public.hpsm_partnership_member_page(
  p_partnership_id bigint,
  p_filter text default 'all',
  p_search text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb language sql stable security definer set search_path = '' as $$
  select public.hpsm_partnership_member_page_pre_canonical(
    p_partnership_id, p_filter, private.normalize_patient_search(p_search), p_limit, p_offset
  );
$$;
revoke all on function public.hpsm_partnership_member_page_pre_canonical(bigint, text, text, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.hpsm_partnership_member_page(bigint, text, text, integer, integer) from public, anon, authenticated, service_role;
grant execute on function public.hpsm_partnership_member_page(bigint, text, text, integer, integer) to authenticated;

alter function public.patient_portal_partnership_member_page(text, bigint, text, text, integer, integer)
  rename to patient_portal_partnership_member_page_pre_canonical;
create function public.patient_portal_partnership_member_page(
  p_token_hash text,
  p_partnership_id bigint,
  p_filter text default 'all',
  p_search text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb language sql stable security definer set search_path = '' as $$
  select public.patient_portal_partnership_member_page_pre_canonical(
    p_token_hash, p_partnership_id, p_filter, private.normalize_patient_search(p_search), p_limit, p_offset
  );
$$;
revoke all on function public.patient_portal_partnership_member_page_pre_canonical(text, bigint, text, text, integer, integer) from public, anon, authenticated, service_role;
revoke all on function public.patient_portal_partnership_member_page(text, bigint, text, text, integer, integer) from public, anon, authenticated, service_role;
grant execute on function public.patient_portal_partnership_member_page(text, bigint, text, text, integer, integer) to service_role;

-- A Busca Global consulta o termo original e, quando numérico, também a forma canônica.
-- Assim pacientes são encontrados sem retirar resultados profissionais que usam o valor legado.
alter function public.hpsm_global_search(text, integer)
  rename to hpsm_global_search_pre_canonical;

create function public.hpsm_global_search(p_query text, p_limit integer default 5)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_query text := btrim(coalesce(p_query, ''));
  v_canonical text;
  v_original jsonb;
  v_canonical_result jsonb;
  v_items jsonb := '[]'::jsonb;
  v_item jsonb;
begin
  v_original := public.hpsm_global_search_pre_canonical(v_query, p_limit);
  if v_query !~ '^[0-9]{1,4}$' then
    return v_original;
  end if;

  v_canonical := private.normalize_patient_passport(v_query);
  if v_canonical = v_query then
    return v_original;
  end if;

  v_canonical_result := public.hpsm_global_search_pre_canonical(v_canonical, p_limit);
  for v_item in
    select canonical_item.item
    from jsonb_array_elements(coalesce(v_canonical_result -> 'items', '[]'::jsonb)) as canonical_item(item)
    union all
    select original_item.item
    from jsonb_array_elements(coalesce(v_original -> 'items', '[]'::jsonb)) as original_item(item)
  loop
    if not exists (
      select 1
      from jsonb_array_elements(v_items) existing
      where existing ->> 'category' = v_item ->> 'category'
        and existing ->> 'id' = v_item ->> 'id'
    ) then
      v_items := v_items || jsonb_build_array(v_item);
    end if;
  end loop;

  return jsonb_build_object('items', v_items);
end;
$$;

revoke all on function public.hpsm_global_search_pre_canonical(text, integer)
from public, anon, authenticated, service_role;
revoke all on function public.hpsm_global_search(text, integer)
from public, anon, authenticated, service_role;
grant execute on function public.hpsm_global_search(text, integer) to authenticated;
