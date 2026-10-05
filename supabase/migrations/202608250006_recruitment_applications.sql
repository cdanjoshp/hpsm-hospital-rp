-- HPSM - candidaturas do processo seletivo.
-- O envio publico passa exclusivamente pela rota segura do Site; anon nao recebe acesso direto.

create table if not exists public.recruitment_applications (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  passport text collate "C" not null unique,
  birth_day smallint not null,
  birth_month smallint not null,
  city_phone text not null,
  discord_id text not null unique,
  availability text[] not null,
  prior_experience boolean not null,
  experience_summary text,
  interest_area text not null,
  motivation text not null,
  external_calls text not null,
  status text not null default 'submitted',
  review_notes text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint recruitment_full_name_length
    check (char_length(btrim(full_name)) between 2 and 100),
  constraint recruitment_passport_format
    check (passport ~ '^[A-Z0-9.-]{2,32}$' and passport = upper(passport)),
  constraint recruitment_birth_day_valid check (birth_day between 1 and 31),
  constraint recruitment_birth_month_valid check (birth_month between 1 and 12),
  constraint recruitment_phone_format
    check (city_phone ~ '^\([0-9]{3}\) [0-9]{3}-[0-9]{3}$'),
  constraint recruitment_discord_id_format check (discord_id ~ '^[0-9]{17,20}$'),
  constraint recruitment_availability_valid check (
    cardinality(availability) between 1 and 4
    and availability <@ array['morning', 'afternoon', 'evening', 'overnight']::text[]
  ),
  constraint recruitment_experience_summary_length
    check (experience_summary is null or char_length(experience_summary) <= 1000),
  constraint recruitment_interest_area_valid check (
    interest_area in ('clinical_care', 'emergency_rescue', 'nursing', 'health_management', 'undecided')
  ),
  constraint recruitment_motivation_length
    check (char_length(btrim(motivation)) between 30 and 1200),
  constraint recruitment_external_calls_valid
    check (external_calls in ('full', 'partial', 'unavailable')),
  constraint recruitment_status_valid
    check (status in ('submitted', 'under_review', 'interview', 'approved', 'rejected', 'withdrawn')),
  constraint recruitment_review_notes_length
    check (review_notes is null or char_length(review_notes) <= 2000)
);

create index if not exists recruitment_status_created_idx
  on public.recruitment_applications (status, created_at desc);

create index if not exists recruitment_created_at_idx
  on public.recruitment_applications (created_at desc);

drop trigger if exists recruitment_touch_updated_at on public.recruitment_applications;
create trigger recruitment_touch_updated_at
before update on public.recruitment_applications
for each row execute function private.touch_updated_at();

alter table public.recruitment_applications enable row level security;
alter table public.recruitment_applications force row level security;

drop policy if exists recruitment_read_directors on public.recruitment_applications;
create policy recruitment_read_directors
on public.recruitment_applications for select
to authenticated
using ((select private.is_director()));

drop policy if exists recruitment_update_directors on public.recruitment_applications;
create policy recruitment_update_directors
on public.recruitment_applications for update
to authenticated
using ((select private.is_director()))
with check (
  (select private.is_director())
  and (reviewed_by is null or reviewed_by = (select auth.uid()))
);

revoke all on public.recruitment_applications from public, anon, authenticated, service_role;
grant select on public.recruitment_applications to authenticated;
grant update (status, review_notes, reviewed_by, reviewed_at)
  on public.recruitment_applications to authenticated;
grant select, insert, update, delete on public.recruitment_applications to service_role;

comment on table public.recruitment_applications is
  'Candidaturas externas ao corpo clinico. Dados reais ficam limitados ao ID do Discord.';

notify pgrst, 'reload schema';
