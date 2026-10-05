-- HP Sul · Fase 1
-- Execute no SQL Editor de um projeto Supabase vazio.

create extension if not exists pgcrypto;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  passport text collate "C" not null unique,
  display_name text not null,
  role_code text not null default 'funcionario',
  status text not null default 'active',
  must_change_password boolean not null default true,
  password_reset_by uuid references auth.users(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_passport_format check (passport ~ '^[A-Za-z0-9.-]{2,32}$'),
  constraint profiles_display_name_length check (char_length(btrim(display_name)) between 2 and 80),
  constraint profiles_role_valid check (role_code in ('diretor_geral', 'diretoria', 'funcionario')),
  constraint profiles_status_valid check (status in ('active', 'inactive', 'suspended'))
);

create index if not exists profiles_password_reset_by_idx
  on public.profiles (password_reset_by)
  where password_reset_by is not null;

create index if not exists profiles_created_by_idx
  on public.profiles (created_by)
  where created_by is not null;

create index if not exists profiles_updated_by_idx
  on public.profiles (updated_by)
  where updated_by is not null;

create unique index if not exists profiles_single_general_director
  on public.profiles ((role_code))
  where role_code = 'diretor_geral';

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_passport text,
  action text not null,
  entity_name text not null,
  entity_id text,
  old_values jsonb,
  new_values jsonb,
  created_at timestamptz not null default now()
);

create index if not exists audit_logs_created_at_idx
  on public.audit_logs (created_at desc);

create index if not exists audit_logs_actor_user_id_idx
  on public.audit_logs (actor_user_id)
  where actor_user_id is not null;

create table if not exists public.system_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function private.is_director()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where user_id = (select auth.uid())
      and status = 'active'
      and role_code in ('diretor_geral', 'diretoria')
  );
$$;

create or replace function private.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid;
  actor_code text;
  row_id text;
begin
  actor_id := auth.uid();

  if actor_id is null and tg_table_name = 'profiles' then
    if tg_op = 'DELETE' then
      actor_id := coalesce(old.updated_by, old.password_reset_by, old.created_by);
    else
      actor_id := coalesce(new.updated_by, new.password_reset_by, new.created_by);
    end if;
  end if;

  select passport into actor_code
  from public.profiles
  where user_id = actor_id;

  if tg_op = 'DELETE' then
    row_id := coalesce(to_jsonb(old)->>'id', to_jsonb(old)->>'key');
  else
    row_id := coalesce(to_jsonb(new)->>'id', to_jsonb(new)->>'key');
  end if;

  insert into public.audit_logs (
    actor_user_id,
    actor_passport,
    action,
    entity_name,
    entity_id,
    old_values,
    new_values
  ) values (
    actor_id,
    actor_code,
    tg_op,
    tg_table_name,
    row_id,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) else null end
  );

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
before update on public.profiles
for each row execute function private.touch_updated_at();

drop trigger if exists settings_touch_updated_at on public.system_settings;
create trigger settings_touch_updated_at
before update on public.system_settings
for each row execute function private.touch_updated_at();

drop trigger if exists profiles_audit on public.profiles;
create trigger profiles_audit
after insert or update or delete on public.profiles
for each row execute function private.audit_row_change();

drop trigger if exists settings_audit on public.system_settings;
create trigger settings_audit
after insert or update or delete on public.system_settings
for each row execute function private.audit_row_change();

alter table public.profiles enable row level security;
alter table public.profiles force row level security;
alter table public.audit_logs enable row level security;
alter table public.audit_logs force row level security;
alter table public.system_settings enable row level security;
alter table public.system_settings force row level security;

drop policy if exists profiles_read_own_or_director on public.profiles;
create policy profiles_read_own_or_director
on public.profiles for select
to authenticated
using (user_id = (select auth.uid()) or (select private.is_director()));

drop policy if exists audit_read_directors on public.audit_logs;
create policy audit_read_directors
on public.audit_logs for select
to authenticated
using ((select private.is_director()));

drop policy if exists settings_read_directors on public.system_settings;
create policy settings_read_directors
on public.system_settings for select
to authenticated
using ((select private.is_director()));

revoke all on public.profiles from public, anon, authenticated, service_role;
revoke all on public.audit_logs from public, anon, authenticated, service_role;
revoke all on public.system_settings from public, anon, authenticated, service_role;
revoke all on function private.touch_updated_at() from public, anon, authenticated, service_role;
revoke all on function private.audit_row_change() from public, anon, authenticated, service_role;
revoke all on function private.is_director() from public, anon, authenticated, service_role;
grant usage on schema public to authenticated;
grant usage on schema private to authenticated;
grant select on public.profiles to authenticated;
grant select on public.audit_logs to authenticated;
grant select on public.system_settings to authenticated;
grant execute on function private.is_director() to authenticated;
grant select, insert, update, delete on public.profiles to service_role;
grant select on public.audit_logs to service_role;
grant select, insert, update on public.system_settings to service_role;

comment on column public.profiles.passport is
  'Identificador textual. Zeros à esquerda são preservados.';
comment on table public.audit_logs is
  'Histórico somente leitura para usuários; mutações são feitas por gatilhos.';
