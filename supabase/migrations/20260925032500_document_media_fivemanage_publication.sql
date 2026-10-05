-- HPSM: publicação centralizada de documentos finais em imagem no FiveManage.

create table public.document_media_publications (
  id uuid primary key default gen_random_uuid(),
  document_type text not null check (document_type in ('EXAM', 'MEDICAL_CERTIFICATE', 'PRESCRIPTION', 'CONSULTATION_RECORD')),
  document_id bigint not null check (document_id > 0),
  provider text not null default 'fivemanage' check (provider = 'fivemanage'),
  external_asset_id text,
  cdn_url text,
  mime_type text not null default 'image/png' check (mime_type = 'image/png'),
  render_version text not null,
  publication_status text not null default 'PENDING' check (publication_status in ('PENDING', 'PUBLISHING', 'PUBLISHED', 'FAILED')),
  attempt_token uuid,
  attempt_started_at timestamptz,
  uploaded_at timestamptz,
  uploaded_by uuid references auth.users(id) on delete set null,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (document_type, document_id),
  check ((publication_status = 'PUBLISHED') = (external_asset_id is not null and cdn_url is not null and uploaded_at is not null))
);

create index document_media_publications_uploaded_by_idx
  on public.document_media_publications (uploaded_by)
  where uploaded_by is not null;

alter table public.document_media_publications enable row level security;
alter table public.document_media_publications force row level security;

revoke all on table public.document_media_publications from public, anon, authenticated;
grant select, insert, update, delete on table public.document_media_publications to service_role;

create trigger document_media_publications_touch_updated_at
before update on public.document_media_publications
for each row execute function private.touch_updated_at();

create or replace function private.document_media_publication_json(p_row public.document_media_publications)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_row.id,
    'document_type', p_row.document_type,
    'document_id', p_row.document_id,
    'provider', p_row.provider,
    'external_asset_id', p_row.external_asset_id,
    'cdn_url', p_row.cdn_url,
    'mime_type', p_row.mime_type,
    'render_version', p_row.render_version,
    'publication_status', p_row.publication_status,
    'uploaded_at', p_row.uploaded_at,
    'last_error', p_row.last_error,
    'created_at', p_row.created_at,
    'updated_at', p_row.updated_at
  );
$$;

create or replace function public.document_image_publication_state(
  p_document_type text,
  p_document_id bigint
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row public.document_media_publications;
begin
  select * into v_row
  from public.document_media_publications
  where document_type = p_document_type and document_id = p_document_id;
  if v_row.id is null then return null; end if;
  return private.document_media_publication_json(v_row);
end;
$$;

create or replace function public.begin_document_image_publication(
  p_document_type text,
  p_document_id bigint,
  p_render_version text,
  p_uploaded_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.document_media_publications;
  v_token uuid := gen_random_uuid();
  v_passport text;
begin
  if p_document_type not in ('EXAM', 'MEDICAL_CERTIFICATE', 'PRESCRIPTION', 'CONSULTATION_RECORD')
     or p_document_id is null or p_document_id <= 0
     or nullif(btrim(p_render_version), '') is null then
    raise exception 'Metadados de publicação inválidos.';
  end if;
  if p_uploaded_by is not null and not exists (
    select 1 from public.profiles where user_id = p_uploaded_by and status = 'active'
  ) then
    raise exception 'Profissional responsável inválido.';
  end if;

  insert into public.document_media_publications (document_type, document_id, render_version, uploaded_by)
  values (p_document_type, p_document_id, p_render_version, p_uploaded_by)
  on conflict (document_type, document_id) do nothing;

  select * into v_row
  from public.document_media_publications
  where document_type = p_document_type and document_id = p_document_id
  for update;

  if v_row.publication_status = 'PUBLISHED' and v_row.render_version = p_render_version then
    return jsonb_build_object('should_upload', false, 'in_progress', false, 'attempt_token', null,
      'publication', private.document_media_publication_json(v_row));
  end if;
  if v_row.publication_status = 'PUBLISHING'
     and v_row.attempt_started_at > now() - interval '2 minutes' then
    return jsonb_build_object('should_upload', false, 'in_progress', true, 'attempt_token', null,
      'publication', private.document_media_publication_json(v_row));
  end if;

  update public.document_media_publications set
    render_version = p_render_version,
    publication_status = 'PUBLISHING',
    attempt_token = v_token,
    attempt_started_at = now(),
    uploaded_by = p_uploaded_by,
    external_asset_id = null,
    cdn_url = null,
    uploaded_at = null,
    last_error = null
  where id = v_row.id
  returning * into v_row;

  select passport into v_passport from public.profiles where user_id = p_uploaded_by;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  values (p_uploaded_by, v_passport, 'DOCUMENT_IMAGE_PUBLISH_STARTED', 'document_media_publications',
    p_document_type || ':' || p_document_id::text, null,
    jsonb_build_object('provider', 'fivemanage', 'render_version', p_render_version));

  return jsonb_build_object('should_upload', true, 'in_progress', false, 'attempt_token', v_token,
    'publication', private.document_media_publication_json(v_row));
end;
$$;

create or replace function public.complete_document_image_publication(
  p_document_type text,
  p_document_id bigint,
  p_attempt_token uuid,
  p_external_asset_id text,
  p_cdn_url text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.document_media_publications;
  v_passport text;
begin
  if nullif(btrim(p_external_asset_id), '') is null
     or p_cdn_url !~ '^https://([a-z0-9-]+[.])*fivemanage[.]com/' then
    raise exception 'Resposta de publicação inválida.';
  end if;
  select * into v_row from public.document_media_publications
  where document_type = p_document_type and document_id = p_document_id for update;
  if v_row.id is null or v_row.publication_status <> 'PUBLISHING' or v_row.attempt_token <> p_attempt_token then
    raise exception 'Tentativa de publicação expirada.';
  end if;

  update public.document_media_publications set
    publication_status = 'PUBLISHED',
    external_asset_id = left(btrim(p_external_asset_id), 500),
    cdn_url = left(btrim(p_cdn_url), 2000),
    uploaded_at = now(),
    attempt_token = null,
    attempt_started_at = null,
    last_error = null
  where id = v_row.id
  returning * into v_row;

  select passport into v_passport from public.profiles where user_id = v_row.uploaded_by;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  values (v_row.uploaded_by, v_passport, 'DOCUMENT_IMAGE_PUBLISHED', 'document_media_publications',
    p_document_type || ':' || p_document_id::text, null,
    jsonb_build_object('provider', 'fivemanage', 'external_asset_id', v_row.external_asset_id));
  return private.document_media_publication_json(v_row);
end;
$$;

create or replace function public.fail_document_image_publication(
  p_document_type text,
  p_document_id bigint,
  p_attempt_token uuid,
  p_error_code text,
  p_error_message text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.document_media_publications;
  v_passport text;
begin
  select * into v_row from public.document_media_publications
  where document_type = p_document_type and document_id = p_document_id for update;
  if v_row.id is null then return null; end if;
  if v_row.publication_status <> 'PUBLISHING' or v_row.attempt_token <> p_attempt_token then
    return private.document_media_publication_json(v_row);
  end if;

  update public.document_media_publications set
    publication_status = 'FAILED',
    attempt_token = null,
    attempt_started_at = null,
    external_asset_id = null,
    cdn_url = null,
    uploaded_at = null,
    last_error = left(coalesce(nullif(btrim(p_error_message), ''), 'Não foi possível publicar a imagem. Tente novamente.'), 500)
  where id = v_row.id
  returning * into v_row;

  select passport into v_passport from public.profiles where user_id = v_row.uploaded_by;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  values (v_row.uploaded_by, v_passport, 'DOCUMENT_IMAGE_PUBLISH_FAILED', 'document_media_publications',
    p_document_type || ':' || p_document_id::text, null,
    jsonb_build_object('provider', 'fivemanage', 'error_code', left(coalesce(p_error_code, 'UNKNOWN'), 60)));
  return private.document_media_publication_json(v_row);
end;
$$;

create or replace function public.record_document_image_event(
  p_document_type text,
  p_document_id bigint,
  p_actor_user_id uuid,
  p_action text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_passport text;
begin
  if p_action not in ('DOCUMENT_IMAGE_RENDERED', 'DOCUMENT_IMAGE_DOWNLOAD', 'DOCUMENT_IMAGE_LINK_COPIED') then
    raise exception 'Evento de documento inválido.';
  end if;
  if not exists (
    select 1 from public.document_media_publications
    where document_type = p_document_type and document_id = p_document_id
  ) then return; end if;
  select passport into v_passport from public.profiles where user_id = p_actor_user_id;
  insert into public.audit_logs (actor_user_id, actor_passport, action, entity_name, entity_id, old_values, new_values)
  values (p_actor_user_id, v_passport, p_action, 'document_media_publications',
    p_document_type || ':' || p_document_id::text, null, jsonb_build_object('provider', 'fivemanage'));
end;
$$;

revoke all on function private.document_media_publication_json(public.document_media_publications) from public, anon, authenticated;
revoke all on function public.document_image_publication_state(text, bigint) from public, anon, authenticated;
revoke all on function public.begin_document_image_publication(text, bigint, text, uuid) from public, anon, authenticated;
revoke all on function public.complete_document_image_publication(text, bigint, uuid, text, text) from public, anon, authenticated;
revoke all on function public.fail_document_image_publication(text, bigint, uuid, text, text) from public, anon, authenticated;
revoke all on function public.record_document_image_event(text, bigint, uuid, text) from public, anon, authenticated;

grant execute on function public.document_image_publication_state(text, bigint) to service_role;
grant execute on function public.begin_document_image_publication(text, bigint, text, uuid) to service_role;
grant execute on function public.complete_document_image_publication(text, bigint, uuid, text, text) to service_role;
grant execute on function public.fail_document_image_publication(text, bigint, uuid, text, text) to service_role;
grant execute on function public.record_document_image_event(text, bigint, uuid, text) to service_role;

