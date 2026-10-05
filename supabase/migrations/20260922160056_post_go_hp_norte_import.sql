-- Pós-GO: importação idempotente e isolada do legado HP Norte.
-- O histórico externo nunca alimenta atendimento, agenda, exame, produção, meta ou relatório atuais.

set lock_timeout = '5s';
set statement_timeout = '120s';

create table public.legacy_import_batches (
  id uuid primary key default gen_random_uuid(),
  source_system text not null,
  source_exported_at timestamptz not null,
  source_file_name text not null,
  source_file_sha256 text not null,
  dry_run_report jsonb not null,
  import_report jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  executed_by uuid references public.profiles(user_id) on delete restrict,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint legacy_import_batches_source_check check (source_system = 'HP_NORTE'),
  constraint legacy_import_batches_hash_check check (source_file_sha256 ~ '^[a-f0-9]{64}$'),
  constraint legacy_import_batches_status_check check (status in ('pending', 'running', 'completed', 'completed_with_conflicts', 'failed')),
  constraint legacy_import_batches_file_unique unique (source_system, source_file_sha256)
);

create table public.patient_external_sources (
  id bigint generated always as identity primary key,
  patient_id bigint not null references public.patients(id) on delete restrict,
  source_system text not null,
  source_record_id text not null,
  source_snapshot jsonb not null,
  imported_batch_id uuid not null references public.legacy_import_batches(id) on delete restrict,
  imported_at timestamptz not null default now(),
  constraint patient_external_sources_source_check check (source_system = 'HP_NORTE'),
  constraint patient_external_sources_record_check check (char_length(btrim(source_record_id)) between 1 and 200),
  constraint patient_external_sources_unique unique (source_system, source_record_id)
);

create table public.legacy_patient_records (
  id bigint generated always as identity primary key,
  patient_id bigint not null references public.patients(id) on delete restrict,
  source_system text not null,
  source_record_id text not null,
  source_original_id text,
  source_patient_record_id text not null,
  record_type text not null,
  occurred_at timestamptz,
  occurred_precision text not null default 'datetime',
  title text not null,
  status text,
  professional_name text,
  professional_registration text,
  summary text,
  details jsonb not null default '{}'::jsonb,
  reference_links jsonb not null default '[]'::jsonb,
  imported_batch_id uuid not null references public.legacy_import_batches(id) on delete restrict,
  imported_at timestamptz not null default now(),
  constraint legacy_patient_records_source_check check (source_system = 'HP_NORTE'),
  constraint legacy_patient_records_type_check check (record_type in ('registration', 'attendance', 'exam', 'vaccine', 'appointment', 'health_plan')),
  constraint legacy_patient_records_precision_check check (occurred_precision in ('date', 'datetime', 'unknown')),
  constraint legacy_patient_records_source_record_check check (char_length(btrim(source_record_id)) between 1 and 300),
  constraint legacy_patient_records_source_patient_check check (char_length(btrim(source_patient_record_id)) between 1 and 200),
  constraint legacy_patient_records_title_check check (char_length(btrim(title)) between 1 and 300),
  constraint legacy_patient_records_details_check check (jsonb_typeof(details) = 'object'),
  constraint legacy_patient_records_links_check check (jsonb_typeof(reference_links) = 'array'),
  constraint legacy_patient_records_unique unique (source_system, source_record_id)
);

create table public.legacy_import_conflicts (
  id bigint generated always as identity primary key,
  source_system text not null,
  source_record_id text not null,
  conflict_type text not null,
  canonical_passport text,
  source_name text,
  existing_patient_id bigint references public.patients(id) on delete restrict,
  details jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  imported_batch_id uuid not null references public.legacy_import_batches(id) on delete restrict,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(user_id) on delete restrict,
  constraint legacy_import_conflicts_source_check check (source_system = 'HP_NORTE'),
  constraint legacy_import_conflicts_status_check check (status in ('pending', 'resolved', 'ignored')),
  constraint legacy_import_conflicts_passport_check check (canonical_passport is null or canonical_passport ~ '^[0-9]{4}$'),
  constraint legacy_import_conflicts_unique unique (source_system, source_record_id, conflict_type)
);

create table public.partnership_external_sources (
  id bigint generated always as identity primary key,
  partnership_id bigint references public.partnerships(id) on delete restrict,
  source_system text not null,
  source_record_id text not null,
  normalized_name text not null,
  source_status text,
  source_snapshot jsonb not null,
  imported_batch_id uuid not null references public.legacy_import_batches(id) on delete restrict,
  imported_at timestamptz not null default now(),
  constraint partnership_external_sources_source_check check (source_system = 'HP_NORTE'),
  constraint partnership_external_sources_record_check check (char_length(btrim(source_record_id)) between 1 and 200),
  constraint partnership_external_sources_name_check check (char_length(btrim(normalized_name)) between 2 and 160),
  constraint partnership_external_sources_unique unique (source_system, source_record_id)
);

create table public.legacy_health_plan_imports (
  id bigint generated always as identity primary key,
  patient_id bigint not null references public.patients(id) on delete restrict,
  health_plan_request_id bigint references public.patient_health_plan_requests(id) on delete restrict,
  source_system text not null,
  source_record_id text not null,
  source_patient_record_id text not null,
  outcome text not null,
  coverage_start timestamptz,
  coverage_end timestamptz,
  imported_batch_id uuid not null references public.legacy_import_batches(id) on delete restrict,
  imported_at timestamptz not null default now(),
  constraint legacy_health_plan_imports_source_check check (source_system = 'HP_NORTE'),
  constraint legacy_health_plan_imports_outcome_check check (outcome in ('activated', 'skipped_hpsm_precedence', 'skipped_invalid_or_expired')),
  constraint legacy_health_plan_imports_request_check check ((outcome = 'activated') = (health_plan_request_id is not null)),
  constraint legacy_health_plan_imports_unique unique (source_system, source_record_id)
);

create index patient_external_sources_patient_idx
  on public.patient_external_sources (patient_id, imported_at desc);
create index patient_external_sources_batch_idx
  on public.patient_external_sources (imported_batch_id);
create index legacy_patient_records_patient_date_idx
  on public.legacy_patient_records (patient_id, occurred_at desc nulls last, id desc);
create index legacy_patient_records_patient_type_date_idx
  on public.legacy_patient_records (patient_id, record_type, occurred_at desc nulls last, id desc);
create index legacy_patient_records_batch_idx
  on public.legacy_patient_records (imported_batch_id);
create index legacy_import_conflicts_pending_idx
  on public.legacy_import_conflicts (created_at, id) where status = 'pending';
create index legacy_import_conflicts_existing_patient_idx
  on public.legacy_import_conflicts (existing_patient_id) where existing_patient_id is not null;
create index legacy_import_conflicts_batch_idx
  on public.legacy_import_conflicts (imported_batch_id);
create index partnership_external_sources_partnership_idx
  on public.partnership_external_sources (partnership_id) where partnership_id is not null;
create index partnership_external_sources_batch_idx
  on public.partnership_external_sources (imported_batch_id);
create index legacy_health_plan_imports_patient_idx
  on public.legacy_health_plan_imports (patient_id, imported_at desc);
create index legacy_health_plan_imports_request_idx
  on public.legacy_health_plan_imports (health_plan_request_id) where health_plan_request_id is not null;
create index legacy_health_plan_imports_batch_idx
  on public.legacy_health_plan_imports (imported_batch_id);

alter table public.legacy_import_batches enable row level security;
alter table public.legacy_import_batches force row level security;
alter table public.patient_external_sources enable row level security;
alter table public.patient_external_sources force row level security;
alter table public.legacy_patient_records enable row level security;
alter table public.legacy_patient_records force row level security;
alter table public.legacy_import_conflicts enable row level security;
alter table public.legacy_import_conflicts force row level security;
alter table public.partnership_external_sources enable row level security;
alter table public.partnership_external_sources force row level security;
alter table public.legacy_health_plan_imports enable row level security;
alter table public.legacy_health_plan_imports force row level security;

revoke all on public.legacy_import_batches from public, anon, authenticated, service_role;
revoke all on public.patient_external_sources from public, anon, authenticated, service_role;
revoke all on public.legacy_patient_records from public, anon, authenticated, service_role;
revoke all on public.legacy_import_conflicts from public, anon, authenticated, service_role;
revoke all on public.partnership_external_sources from public, anon, authenticated, service_role;
revoke all on public.legacy_health_plan_imports from public, anon, authenticated, service_role;

create or replace function private.hp_norte_normalize_name(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select btrim(regexp_replace(
    translate(lower(coalesce(p_value, '')), 'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'),
    '[^a-z0-9]+', ' ', 'g'
  ));
$$;

create or replace function private.hp_norte_import_actor()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_actor uuid;
begin
  select profile.user_id into v_actor
  from public.profiles profile
  where profile.status = 'active'
    and profile.role_code = 'diretor_geral'
  order by profile.created_at, profile.user_id
  limit 1;
  if v_actor is null then
    raise exception 'Diretor Geral ativo não localizado para auditar a importação.' using errcode = '42501';
  end if;
  return v_actor;
end;
$$;

revoke all on function private.hp_norte_normalize_name(text) from public, anon, authenticated, service_role;
revoke all on function private.hp_norte_import_actor() from public, anon, authenticated, service_role;

create or replace function private.import_hp_norte_chunk(p_batch_id uuid, p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
  v_item_type text;
  v_source_record_id text;
  v_source_patient_record_id text;
  v_passport text;
  v_name text;
  v_patient_id bigint;
  v_existing_name text;
  v_partnership_id bigint;
  v_source_status text;
  v_actor uuid := private.hp_norte_import_actor();
  v_plan_request_id bigint;
  v_coverage_start timestamptz;
  v_coverage_end timestamptz;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_skipped integer := 0;
  v_conflicts integer := 0;
  v_errors integer := 0;
begin
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 300 then
    raise exception 'Lote de importação inválido.' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.legacy_import_batches batch
    where batch.id = p_batch_id and batch.source_system = 'HP_NORTE'
      and batch.status in ('pending', 'running')
  ) then
    raise exception 'Lote de importação não localizado ou já encerrado.' using errcode = '22023';
  end if;

  update public.legacy_import_batches
  set status = 'running', started_at = coalesce(started_at, now()), executed_by = coalesce(executed_by, v_actor)
  where id = p_batch_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    begin
      v_patient_id := null;
      v_existing_name := null;
      v_partnership_id := null;
      v_plan_request_id := null;
      v_item_type := btrim(coalesce(v_item ->> 'item_type', ''));
      v_source_record_id := btrim(coalesce(v_item ->> 'source_record_id', ''));
      v_source_patient_record_id := nullif(btrim(coalesce(v_item ->> 'source_patient_record_id', '')), '');
      if v_source_record_id = '' then raise exception 'Registro sem identificador de origem.'; end if;

      if v_item_type = 'patient_conflict' then
        insert into public.legacy_import_conflicts (
          source_system, source_record_id, conflict_type, canonical_passport,
          source_name, details, imported_batch_id
        ) values (
          'HP_NORTE', v_source_record_id, coalesce(nullif(v_item ->> 'conflict_type', ''), 'identity_conflict'),
          nullif(v_item ->> 'canonical_passport', ''), nullif(btrim(v_item ->> 'source_name'), ''),
          coalesce(v_item -> 'details', '{}'::jsonb), p_batch_id
        ) on conflict (source_system, source_record_id, conflict_type) do nothing;
        if found then v_conflicts := v_conflicts + 1; else v_skipped := v_skipped + 1; end if;

      elsif v_item_type = 'patient' then
        if exists (
          select 1 from public.patient_external_sources source
          where source.source_system = 'HP_NORTE' and source.source_record_id = v_source_record_id
        ) then
          v_skipped := v_skipped + 1;
          continue;
        end if;
        v_passport := private.normalize_patient_passport(v_item ->> 'passport');
        v_name := btrim(coalesce(v_item ->> 'name', ''));
        if char_length(v_name) not between 2 and 100 then raise exception 'Nome de paciente inválido.'; end if;

        select patient.id, patient.name into v_patient_id, v_existing_name
        from public.patients patient where patient.passport = v_passport for update;

        if v_patient_id is not null
           and private.hp_norte_normalize_name(v_existing_name) <> private.hp_norte_normalize_name(v_name) then
          insert into public.legacy_import_conflicts (
            source_system, source_record_id, conflict_type, canonical_passport,
            source_name, existing_patient_id, details, imported_batch_id
          ) values (
            'HP_NORTE', v_source_record_id, 'same_passport_divergent_name', v_passport,
            v_name, v_patient_id,
            jsonb_build_object('hpsm_name', v_existing_name), p_batch_id
          ) on conflict (source_system, source_record_id, conflict_type) do nothing;
          if found then v_conflicts := v_conflicts + 1; else v_skipped := v_skipped + 1; end if;
          continue;
        end if;

        if v_patient_id is null then
          insert into public.patients (
            passport, name, phone, emergency_contact_name, emergency_contact_phone,
            birth_date, allergies, created_by, updated_by, created_at, updated_at
          ) values (
            v_passport, v_name,
            case when v_item ->> 'phone' ~ '^\\(055\\) [0-9]{3}-[0-9]{3}$' then v_item ->> 'phone' else null end,
            case
              when v_item ->> 'emergency_phone' ~ '^\\(055\\) [0-9]{3}-[0-9]{3}$'
               and char_length(btrim(coalesce(v_item ->> 'emergency_name', ''))) between 2 and 100
              then btrim(v_item ->> 'emergency_name') else null
            end,
            case when v_item ->> 'emergency_phone' ~ '^\\(055\\) [0-9]{3}-[0-9]{3}$' and char_length(btrim(coalesce(v_item ->> 'emergency_name', ''))) between 2 and 100 then v_item ->> 'emergency_phone' else null end,
            null, nullif(btrim(v_item ->> 'allergies'), ''), null, null,
            coalesce((v_item ->> 'created_at')::timestamptz, now()),
            coalesce((v_item ->> 'created_at')::timestamptz, now())
          ) returning id into v_patient_id;
          v_inserted := v_inserted + 1;
        else
          update public.patients patient set
            phone = case
              when patient.phone is null and v_item ->> 'phone' ~ '^\\(055\\) [0-9]{3}-[0-9]{3}$' then v_item ->> 'phone'
              else patient.phone
            end,
            emergency_contact_name = case
              when patient.emergency_contact_name is null and patient.emergency_contact_phone is null
               and v_item ->> 'emergency_phone' ~ '^\\(055\\) [0-9]{3}-[0-9]{3}$'
               and char_length(btrim(coalesce(v_item ->> 'emergency_name', ''))) between 2 and 100
              then btrim(v_item ->> 'emergency_name') else patient.emergency_contact_name
            end,
            emergency_contact_phone = case
              when patient.emergency_contact_name is null and patient.emergency_contact_phone is null
               and v_item ->> 'emergency_phone' ~ '^\\(055\\) [0-9]{3}-[0-9]{3}$'
               and char_length(btrim(coalesce(v_item ->> 'emergency_name', ''))) between 2 and 100
              then v_item ->> 'emergency_phone' else patient.emergency_contact_phone
            end,
            allergies = case
              when patient.allergies is null then nullif(btrim(v_item ->> 'allergies'), '')
              else patient.allergies
            end,
            updated_at = case
              when (patient.phone is null and v_item ->> 'phone' ~ '^\\(055\\) [0-9]{3}-[0-9]{3}$')
                or (patient.allergies is null and nullif(btrim(v_item ->> 'allergies'), '') is not null)
                or (patient.emergency_contact_name is null and patient.emergency_contact_phone is null
                    and v_item ->> 'emergency_phone' ~ '^\\(055\\) [0-9]{3}-[0-9]{3}$'
                    and char_length(btrim(coalesce(v_item ->> 'emergency_name', ''))) between 2 and 100)
              then now() else patient.updated_at
            end
          where patient.id = v_patient_id;
          v_updated := v_updated + 1;
        end if;

        insert into public.patient_external_sources (
          patient_id, source_system, source_record_id, source_snapshot, imported_batch_id
        ) values (
          v_patient_id, 'HP_NORTE', v_source_record_id,
          coalesce(v_item -> 'source_snapshot', '{}'::jsonb), p_batch_id
        ) on conflict (source_system, source_record_id) do nothing;

        insert into public.legacy_patient_records (
          patient_id, source_system, source_record_id, source_original_id,
          source_patient_record_id, record_type, occurred_at, occurred_precision, title, summary,
          details, reference_links, imported_batch_id
        ) values (
          v_patient_id, 'HP_NORTE', 'registration:' || v_source_record_id, v_source_record_id,
          v_source_record_id, 'registration', (v_item ->> 'created_at')::timestamptz,
          case when v_item ->> 'created_at_precision' in ('date', 'datetime') then v_item ->> 'created_at_precision' else 'unknown' end,
          'Cadastro no HP Norte', 'Identidade vinculada ao histórico legado.',
          coalesce(v_item -> 'profile_details', '{}'::jsonb),
          coalesce(v_item -> 'reference_links', '[]'::jsonb), p_batch_id
        ) on conflict (source_system, source_record_id) do nothing;

      elsif v_item_type = 'legacy_record' then
        select source.patient_id into v_patient_id
        from public.patient_external_sources source
        where source.source_system = 'HP_NORTE'
          and source.source_record_id = v_source_patient_record_id;
        if v_patient_id is null then
          v_skipped := v_skipped + 1;
          continue;
        end if;
        if v_item -> 'details' is not null and (v_item -> 'details')::text ~ '<\\/?[A-Za-z][^>]*>' then
          raise exception 'HTML não sanitizado no registro legado.';
        end if;
        insert into public.legacy_patient_records (
          patient_id, source_system, source_record_id, source_original_id,
          source_patient_record_id, record_type, occurred_at, occurred_precision, title, status,
          professional_name, professional_registration, summary, details,
          reference_links, imported_batch_id
        ) values (
          v_patient_id, 'HP_NORTE', v_source_record_id, nullif(v_item ->> 'source_original_id', ''),
          v_source_patient_record_id, v_item ->> 'record_type',
          nullif(v_item ->> 'occurred_at', '')::timestamptz,
          case when v_item ->> 'occurred_precision' in ('date', 'datetime') then v_item ->> 'occurred_precision' else 'unknown' end,
          left(btrim(v_item ->> 'title'), 300), nullif(left(btrim(v_item ->> 'status'), 100), ''),
          nullif(left(btrim(v_item ->> 'professional_name'), 160), ''),
          nullif(left(btrim(v_item ->> 'professional_registration'), 100), ''),
          nullif(left(btrim(v_item ->> 'summary'), 4000), ''),
          coalesce(v_item -> 'details', '{}'::jsonb),
          coalesce(v_item -> 'reference_links', '[]'::jsonb), p_batch_id
        ) on conflict (source_system, source_record_id) do nothing;
        if found then v_inserted := v_inserted + 1; else v_skipped := v_skipped + 1; end if;

      elsif v_item_type = 'partnership' then
        v_source_status := nullif(v_item ->> 'status', '');
        if v_source_status is null or v_source_status not in ('active', 'inactive') then raise exception 'Status legado de parceria ambíguo.'; end if;
        if exists (
          select 1 from public.partnership_external_sources source
          where source.source_system = 'HP_NORTE' and source.source_record_id = v_source_record_id
        ) then
          v_skipped := v_skipped + 1;
          continue;
        end if;
        select partnership.id into v_partnership_id
        from public.partnerships partnership
        where private.hp_norte_normalize_name(partnership.name) = private.hp_norte_normalize_name(v_item ->> 'name')
        order by partnership.id limit 1;
        if v_partnership_id is null then
          insert into public.partnerships (
            name, status, notes, created_by, updated_by,
            created_at, updated_at, deactivated_at, deactivated_by, deactivation_reason
          ) values (
            btrim(v_item ->> 'name'), v_source_status,
            'Cadastro proveniente da migração HP Norte; limites, preços e descontos antigos não foram importados.',
            v_actor, v_actor, coalesce((v_item ->> 'created_at')::timestamptz, now()), now(),
            case when v_source_status = 'inactive' then now() else null end,
            case when v_source_status = 'inactive' then v_actor else null end,
            case when v_source_status = 'inactive' then 'Parceria já inativa na origem HP Norte.' else null end
          ) returning id into v_partnership_id;
          v_inserted := v_inserted + 1;
        end if;
        insert into public.partnership_external_sources (
          partnership_id, source_system, source_record_id, normalized_name,
          source_status, source_snapshot, imported_batch_id
        ) values (
          v_partnership_id, 'HP_NORTE', v_source_record_id,
          private.hp_norte_normalize_name(v_item ->> 'name'), v_source_status,
          coalesce(v_item -> 'source_snapshot', '{}'::jsonb), p_batch_id
        ) on conflict (source_system, source_record_id) do nothing;

      elsif v_item_type = 'partnership_link' then
        select source.patient_id into v_patient_id
        from public.patient_external_sources source
        where source.source_system = 'HP_NORTE' and source.source_record_id = v_source_patient_record_id;
        select source.partnership_id into v_partnership_id
        from public.partnership_external_sources source
        join public.partnerships partnership on partnership.id = source.partnership_id and partnership.status = 'active'
        where source.source_system = 'HP_NORTE' and source.source_record_id = v_item ->> 'partnership_source_record_id'
          and source.source_status = 'active';
        if v_patient_id is null or v_partnership_id is null then
          v_skipped := v_skipped + 1;
          continue;
        end if;
        if not exists (
          select 1 from public.patient_partnerships link
          where link.patient_id = v_patient_id and link.partnership_id = v_partnership_id and link.status = 'active'
        ) then
          insert into public.patient_partnerships (
            patient_id, partnership_id, status, linked_at, linked_by_type
          ) values (
            v_patient_id, v_partnership_id, 'active',
            coalesce((v_item ->> 'linked_at')::timestamptz, now()), 'system'
          );
          v_inserted := v_inserted + 1;
        else
          v_skipped := v_skipped + 1;
        end if;

      elsif v_item_type = 'legacy_plan_activation' then
        if exists (
          select 1 from public.legacy_health_plan_imports imported
          where imported.source_system = 'HP_NORTE' and imported.source_record_id = v_source_record_id
        ) then
          v_skipped := v_skipped + 1;
          continue;
        end if;
        select source.patient_id into v_patient_id
        from public.patient_external_sources source
        where source.source_system = 'HP_NORTE' and source.source_record_id = v_source_patient_record_id;
        if v_patient_id is null then
          v_skipped := v_skipped + 1;
          continue;
        end if;
        v_coverage_start := nullif(v_item ->> 'coverage_start', '')::timestamptz;
        v_coverage_end := nullif(v_item ->> 'coverage_end', '')::timestamptz;
        if v_coverage_start is null or v_coverage_end is null or v_coverage_end <= greatest(v_coverage_start, now()) then
          insert into public.legacy_health_plan_imports (
            patient_id, source_system, source_record_id, source_patient_record_id,
            outcome, coverage_start, coverage_end, imported_batch_id
          ) values (
            v_patient_id, 'HP_NORTE', v_source_record_id, v_source_patient_record_id,
            'skipped_invalid_or_expired', v_coverage_start, v_coverage_end, p_batch_id
          );
          v_skipped := v_skipped + 1;
          continue;
        end if;
        if exists (select 1 from public.patient_health_plan_requests request where request.patient_id = v_patient_id) then
          insert into public.legacy_health_plan_imports (
            patient_id, source_system, source_record_id, source_patient_record_id,
            outcome, coverage_start, coverage_end, imported_batch_id
          ) values (
            v_patient_id, 'HP_NORTE', v_source_record_id, v_source_patient_record_id,
            'skipped_hpsm_precedence', v_coverage_start, v_coverage_end, p_batch_id
          );
          v_skipped := v_skipped + 1;
          continue;
        end if;
        insert into public.patient_health_plan_requests (
          patient_id, attendance_id, status, requested_at, reviewed_by, reviewed_at,
          coverage_start, coverage_end, origin, administrative_action, created_at, updated_at
        ) values (
          v_patient_id, null, 'approved', v_coverage_start, v_actor, now(),
          v_coverage_start, v_coverage_end, 'administrative', 'grant', now(), now()
        ) returning id into v_plan_request_id;
        insert into public.legacy_health_plan_imports (
          patient_id, health_plan_request_id, source_system, source_record_id,
          source_patient_record_id, outcome, coverage_start, coverage_end, imported_batch_id
        ) values (
          v_patient_id, v_plan_request_id, 'HP_NORTE', v_source_record_id,
          v_source_patient_record_id, 'activated', v_coverage_start, v_coverage_end, p_batch_id
        );
        v_inserted := v_inserted + 1;

      else
        raise exception 'Tipo de item de importação inválido: %', v_item_type;
      end if;
    exception when others then
      insert into public.legacy_import_conflicts (
        source_system, source_record_id, conflict_type, details, imported_batch_id
      ) values (
        'HP_NORTE', coalesce(nullif(v_source_record_id, ''), 'unknown:' || gen_random_uuid()::text),
        'import_error', jsonb_build_object('sqlstate', sqlstate, 'message', sqlerrm, 'item_type', v_item_type), p_batch_id
      ) on conflict (source_system, source_record_id, conflict_type) do nothing;
      v_errors := v_errors + 1;
    end;
  end loop;

  return jsonb_build_object(
    'inserted', v_inserted,
    'updated', v_updated,
    'skipped', v_skipped,
    'conflicts', v_conflicts,
    'errors', v_errors
  );
end;
$$;

create or replace function private.finish_hp_norte_import(p_batch_id uuid, p_import_report jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hp_norte_import_actor();
  v_actor_passport text;
  v_pending_conflicts integer;
  v_status text;
begin
  select count(*) into v_pending_conflicts
  from public.legacy_import_conflicts conflict
  where conflict.imported_batch_id = p_batch_id and conflict.status = 'pending';
  v_status := case when v_pending_conflicts > 0 then 'completed_with_conflicts' else 'completed' end;
  update public.legacy_import_batches batch set
    status = v_status,
    import_report = coalesce(p_import_report, '{}'::jsonb) || jsonb_build_object('pending_conflicts', v_pending_conflicts),
    executed_by = v_actor,
    completed_at = now()
  where batch.id = p_batch_id and batch.source_system = 'HP_NORTE'
    and batch.status in ('pending', 'running');
  if not found then raise exception 'Lote não localizado ou já encerrado.'; end if;

  select profile.passport into v_actor_passport from public.profiles profile where profile.user_id = v_actor;
  insert into public.audit_logs (
    actor_user_id, actor_passport, action, entity_name, entity_id, new_values
  ) values (
    v_actor, v_actor_passport, 'IMPORT', 'legacy_import_batches', p_batch_id::text,
    jsonb_build_object('source_system', 'HP_NORTE', 'status', v_status, 'pending_conflicts', v_pending_conflicts)
  );
  return jsonb_build_object('status', v_status, 'pending_conflicts', v_pending_conflicts);
end;
$$;

revoke all on function private.import_hp_norte_chunk(uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.finish_hp_norte_import(uuid, jsonb) from public, anon, authenticated, service_role;

create or replace function public.patient_legacy_history_page(
  p_patient_id bigint,
  p_record_type text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  if not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then
    raise exception 'Paciente não localizado.' using errcode = '22023';
  end if;
  if p_record_type is not null and p_record_type not in ('registration', 'attendance', 'exam', 'vaccine', 'appointment', 'health_plan') then
    raise exception 'Tipo de histórico legado inválido.' using errcode = '22023';
  end if;

  with filtered as (
    select record.*
    from public.legacy_patient_records record
    where record.patient_id = p_patient_id
      and (p_record_type is null or record.record_type = p_record_type)
  ), page as (
    select record.* from filtered record
    order by record.occurred_at desc nulls last, record.id desc
    limit v_limit offset v_offset
  ), totals as (
    select count(*)::integer as total from filtered
  ), summary as (
    select record.record_type, count(*)::integer as total
    from public.legacy_patient_records record
    where record.patient_id = p_patient_id
    group by record.record_type
  )
  select jsonb_build_object(
    'source', 'HP Norte',
    'total', (select total from totals),
    'sourceProfiles', (select count(*) from public.patient_external_sources source where source.patient_id = p_patient_id and source.source_system = 'HP_NORTE'),
    'summary', coalesce((select jsonb_object_agg(summary.record_type, summary.total) from summary), '{}'::jsonb),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', page.id,
        'record_type', page.record_type,
        'occurred_at', page.occurred_at,
        'occurred_precision', page.occurred_precision,
        'title', page.title,
        'status', page.status,
        'professional_name', page.professional_name,
        'professional_registration', page.professional_registration,
        'summary', page.summary,
        'details', page.details,
        'reference_links', page.reference_links
      ) order by page.occurred_at desc nulls last, page.id desc)
      from page
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function public.patient_legacy_history_page(bigint, text, integer, integer)
from public, anon, authenticated, service_role;
grant execute on function public.patient_legacy_history_page(bigint, text, integer, integer) to authenticated;

comment on table public.legacy_patient_records is
  'Histórico somente leitura importado do HP Norte; não integra domínios operacionais atuais.';
comment on function public.patient_legacy_history_page(bigint, text, integer, integer) is
  'Histórico HP Norte carregado sob demanda exclusivamente no Perfil do Paciente profissional.';
