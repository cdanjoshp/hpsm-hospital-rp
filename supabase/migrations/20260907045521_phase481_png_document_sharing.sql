-- HPSM Fase 4.8.1 · PNG canônico e link público revogável
-- O conteúdo clínico continua em clinical_exams.final_report_snapshot.

create table public.clinical_exam_documents (
  id uuid primary key,
  exam_id bigint not null references public.clinical_exams(id) on delete restrict,
  storage_path text not null unique,
  mime_type text not null default 'image/png',
  file_size bigint not null,
  pixel_width integer not null,
  pixel_height integer not null,
  render_version text not null,
  created_by uuid not null references public.profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint clinical_exam_documents_png_mime_check check (mime_type = 'image/png'),
  constraint clinical_exam_documents_size_check check (file_size between 1 and 12582912),
  constraint clinical_exam_documents_width_check check (pixel_width between 900 and 1400),
  constraint clinical_exam_documents_height_check check (pixel_height between 400 and 14000),
  constraint clinical_exam_documents_render_version_check check (render_version = 'exam-document-png-v1'),
  constraint clinical_exam_documents_storage_path_check check (
    storage_path ~ ('^clinical-exams/' || exam_id::text || '/documents/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.png$')
  )
);

create unique index clinical_exam_documents_exam_render_version_uidx
on public.clinical_exam_documents (exam_id, render_version);

create table public.clinical_exam_document_shares (
  id uuid primary key default gen_random_uuid(),
  exam_id bigint not null references public.clinical_exams(id) on delete restrict,
  document_id uuid not null references public.clinical_exam_documents(id) on delete restrict,
  created_by uuid not null references public.profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  revoked_by uuid references public.profiles(user_id) on delete restrict,
  revoked_at timestamptz,
  constraint clinical_exam_document_shares_revocation_pair_check check (
    (revoked_by is null and revoked_at is null) or (revoked_by is not null and revoked_at is not null)
  )
);

create unique index clinical_exam_document_shares_one_active_uidx
on public.clinical_exam_document_shares (exam_id)
where revoked_at is null;

create index clinical_exam_document_shares_exam_history_idx
on public.clinical_exam_document_shares (exam_id, created_at desc);

create index clinical_exam_document_shares_document_idx
on public.clinical_exam_document_shares (document_id);

alter table public.clinical_exam_documents enable row level security;
alter table public.clinical_exam_documents force row level security;
alter table public.clinical_exam_document_shares enable row level security;
alter table public.clinical_exam_document_shares force row level security;

revoke all on public.clinical_exam_documents from public, anon, authenticated, service_role;
revoke all on public.clinical_exam_document_shares from public, anon, authenticated, service_role;
grant select, insert, update, delete on public.clinical_exam_documents to service_role;
grant select, insert, update, delete on public.clinical_exam_document_shares to service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('clinical-exam-documents', 'clinical-exam-documents', false, 12582912, array['image/png']::text[])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Sem policies em storage.objects: somente o backend com service role grava e lê
-- o bucket. O link público passa pela rota revogável do Site.

create or replace function private.clinical_exam_document_state_json(p_exam_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_document public.clinical_exam_documents;
  v_share public.clinical_exam_document_shares;
begin
  select document.* into v_document
  from public.clinical_exam_documents document
  where document.exam_id = p_exam_id
    and document.render_version = 'exam-document-png-v1'
  order by document.created_at desc
  limit 1;

  if v_document.id is not null then
    select share.* into v_share
    from public.clinical_exam_document_shares share
    where share.exam_id = p_exam_id
      and share.document_id = v_document.id
      and share.revoked_at is null
    order by share.created_at desc
    limit 1;
  end if;

  return jsonb_build_object(
    'document', case when v_document.id is null then null else jsonb_build_object(
      'id', v_document.id,
      'created_at', v_document.created_at,
      'file_size', v_document.file_size,
      'pixel_width', v_document.pixel_width,
      'pixel_height', v_document.pixel_height,
      'render_version', v_document.render_version
    ) end,
    'share', case when v_share.id is null then null else jsonb_build_object(
      'id', v_share.id,
      'created_at', v_share.created_at
    ) end
  );
end;
$$;

revoke all on function private.clinical_exam_document_state_json(bigint)
from public, anon, authenticated, service_role;

create or replace function public.clinical_exam_document_state(p_exam_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
begin
  if not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.clinical_exams exam
    where exam.id = p_exam_id
      and exam.status = 'completed'
      and exam.final_report_snapshot is not null
  ) then
    raise exception 'A imagem compartilhável está disponível somente para exames concluídos.';
  end if;

  return private.clinical_exam_document_state_json(p_exam_id);
end;
$$;

create or replace function public.register_clinical_exam_document(
  p_exam_id bigint,
  p_document_id uuid,
  p_storage_path text,
  p_file_size bigint,
  p_pixel_width integer,
  p_pixel_height integer,
  p_render_version text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_exam public.clinical_exams;
  v_document public.clinical_exam_documents;
  v_share public.clinical_exam_document_shares;
  v_inserted_id uuid;
begin
  if not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select exam.* into v_exam
  from public.clinical_exams exam
  where exam.id = p_exam_id
  for update;

  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status <> 'completed' or v_exam.final_report_snapshot is null then
    raise exception 'A imagem compartilhável está disponível somente para exames concluídos.';
  end if;
  if p_document_id is null
     or p_render_version <> 'exam-document-png-v1'
     or p_storage_path <> format('clinical-exams/%s/documents/%s.png', p_exam_id, p_document_id)
     or p_file_size not between 1 and 12582912
     or p_pixel_width not between 900 and 1400
     or p_pixel_height not between 400 and 14000 then
    raise exception 'Metadados inválidos para a imagem do documento.';
  end if;

  insert into public.clinical_exam_documents (
    id, exam_id, storage_path, mime_type, file_size, pixel_width, pixel_height, render_version, created_by
  ) values (
    p_document_id, p_exam_id, p_storage_path, 'image/png', p_file_size, p_pixel_width, p_pixel_height, p_render_version, v_actor
  )
  on conflict (exam_id, render_version) do nothing
  returning id into v_inserted_id;

  select document.* into v_document
  from public.clinical_exam_documents document
  where document.exam_id = p_exam_id
    and document.render_version = p_render_version
  limit 1;

  if v_document.id is null then raise exception 'Não foi possível registrar a imagem do documento.'; end if;

  if v_inserted_id is not null then
    perform private.audit_exam_action(
      v_actor,
      'clinical_exam.document_png_generated',
      'clinical_exam_documents',
      v_document.id::text,
      null,
      jsonb_build_object(
        'exam_id', p_exam_id,
        'render_version', v_document.render_version,
        'file_size', v_document.file_size,
        'pixel_width', v_document.pixel_width,
        'pixel_height', v_document.pixel_height
      )
    );
  end if;

  select share.* into v_share
  from public.clinical_exam_document_shares share
  where share.exam_id = p_exam_id and share.revoked_at is null
  limit 1;

  if v_share.id is null then
    insert into public.clinical_exam_document_shares (exam_id, document_id, created_by)
    values (p_exam_id, v_document.id, v_actor)
    returning * into v_share;

    perform private.audit_exam_action(
      v_actor,
      'clinical_exam.document_link_created',
      'clinical_exam_document_shares',
      v_share.id::text,
      null,
      jsonb_build_object('exam_id', p_exam_id, 'document_id', v_document.id)
    );
  end if;

  return private.clinical_exam_document_state_json(p_exam_id);
end;
$$;

create or replace function public.create_clinical_exam_document_share(p_exam_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_exam public.clinical_exams;
  v_document public.clinical_exam_documents;
  v_share public.clinical_exam_document_shares;
begin
  if not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select exam.* into v_exam
  from public.clinical_exams exam
  where exam.id = p_exam_id
  for update;

  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status <> 'completed' or v_exam.final_report_snapshot is null then
    raise exception 'O link está disponível somente para exames concluídos.';
  end if;

  select document.* into v_document
  from public.clinical_exam_documents document
  where document.exam_id = p_exam_id
    and document.render_version = 'exam-document-png-v1'
  limit 1;
  if v_document.id is null then raise exception 'Gere a imagem compartilhável antes de criar o link.'; end if;

  select share.* into v_share
  from public.clinical_exam_document_shares share
  where share.exam_id = p_exam_id and share.revoked_at is null
  limit 1;

  if v_share.id is null then
    insert into public.clinical_exam_document_shares (exam_id, document_id, created_by)
    values (p_exam_id, v_document.id, v_actor)
    returning * into v_share;

    perform private.audit_exam_action(
      v_actor,
      'clinical_exam.document_link_created',
      'clinical_exam_document_shares',
      v_share.id::text,
      null,
      jsonb_build_object('exam_id', p_exam_id, 'document_id', v_document.id)
    );
  end if;

  return private.clinical_exam_document_state_json(p_exam_id);
end;
$$;

create or replace function public.revoke_clinical_exam_document_share(p_exam_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := private.hpsm_current_actor();
  v_exam public.clinical_exams;
  v_share public.clinical_exam_document_shares;
begin
  if not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;

  select exam.* into v_exam
  from public.clinical_exams exam
  where exam.id = p_exam_id
  for update;

  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if v_exam.status <> 'completed' or v_exam.final_report_snapshot is null then
    raise exception 'O link está disponível somente para exames concluídos.';
  end if;

  select share.* into v_share
  from public.clinical_exam_document_shares share
  where share.exam_id = p_exam_id and share.revoked_at is null
  for update;

  if v_share.id is not null then
    update public.clinical_exam_document_shares
    set revoked_by = v_actor, revoked_at = now()
    where id = v_share.id;

    perform private.audit_exam_action(
      v_actor,
      'clinical_exam.document_link_revoked',
      'clinical_exam_document_shares',
      v_share.id::text,
      jsonb_build_object('active', true, 'exam_id', p_exam_id),
      jsonb_build_object('active', false, 'exam_id', p_exam_id)
    );
  end if;

  return private.clinical_exam_document_state_json(p_exam_id);
end;
$$;

create or replace function public.resolve_clinical_exam_document_share(p_share_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'exam_id', document.exam_id,
    'document_id', document.id,
    'storage_path', document.storage_path,
    'mime_type', document.mime_type,
    'file_size', document.file_size,
    'pixel_width', document.pixel_width,
    'pixel_height', document.pixel_height,
    'render_version', document.render_version
  )
  from public.clinical_exam_document_shares share
  join public.clinical_exam_documents document on document.id = share.document_id
  join public.clinical_exams exam on exam.id = share.exam_id
  where share.id = p_share_id
    and share.revoked_at is null
    and exam.status = 'completed'
    and exam.final_report_snapshot is not null
    and document.render_version = 'exam-document-png-v1'
  limit 1;
$$;

revoke all on function public.clinical_exam_document_state(bigint)
from public, anon, authenticated, service_role;
revoke all on function public.register_clinical_exam_document(bigint, uuid, text, bigint, integer, integer, text)
from public, anon, authenticated, service_role;
revoke all on function public.create_clinical_exam_document_share(bigint)
from public, anon, authenticated, service_role;
revoke all on function public.revoke_clinical_exam_document_share(bigint)
from public, anon, authenticated, service_role;
revoke all on function public.resolve_clinical_exam_document_share(uuid)
from public, anon, authenticated, service_role;

grant execute on function public.clinical_exam_document_state(bigint) to authenticated;
grant execute on function public.register_clinical_exam_document(bigint, uuid, text, bigint, integer, integer, text) to authenticated;
grant execute on function public.create_clinical_exam_document_share(bigint) to authenticated;
grant execute on function public.revoke_clinical_exam_document_share(bigint) to authenticated;
grant execute on function public.resolve_clinical_exam_document_share(uuid) to service_role;

comment on table public.clinical_exam_documents is
  'Metadados do PNG canônico imutável gerado a partir do snapshot final aprovado.';
comment on table public.clinical_exam_document_shares is
  'Tokens públicos aleatórios e revogáveis para o PNG canônico do exame concluído.';
comment on function public.resolve_clinical_exam_document_share(uuid) is
  'Resolve somente para service_role um token ativo de PNG concluído; não expõe conteúdo clínico pelo Data API.';

notify pgrst, 'reload schema';
