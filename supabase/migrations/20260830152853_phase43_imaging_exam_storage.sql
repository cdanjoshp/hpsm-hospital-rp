-- HPSM · Fase 4.3 · Exames de imagem e Storage privado
-- Os bytes ficam no Storage; o banco preserva metadados, autoria e snapshot clínico.

create or replace function private.default_image_template(p_exam_type_code text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'schema', 'hpsm.image_template.v1',
    'kind', 'imaging',
    'version', 1,
    'region', jsonb_build_object(
      'required', true,
      'options', case p_exam_type_code
        when 'raio_x' then jsonb_build_array('Tórax','Abdome','Coluna cervical','Coluna torácica','Coluna lombar','Pelve','Ombro','Braço','Cotovelo','Antebraço','Punho','Mão','Quadril','Coxa','Joelho','Perna','Tornozelo','Pé','Crânio','Face','Outra região')
        when 'tomografia' then jsonb_build_array('Crânio','Seios da face','Pescoço','Tórax','Abdome','Pelve','Coluna','Membro superior','Membro inferior','Angiotomografia','Outra região')
        when 'ressonancia_magnetica' then jsonb_build_array('Crânio','Coluna cervical','Coluna torácica','Coluna lombar','Ombro','Cotovelo','Punho','Mão','Quadril','Joelho','Tornozelo','Pé','Abdome','Pelve','Outra região')
        when 'ultrassom' then jsonb_build_array('Abdome total','Abdome superior','Pelve','Obstétrico','Rins e vias urinárias','Tireoide','Mama','Partes moles','Musculoesquelético','Doppler vascular','Outra região')
        else jsonb_build_array('Outra região')
      end
    ),
    'supports_laterality', true,
    'supports_contrast', p_exam_type_code in ('tomografia', 'ressonancia_magnetica'),
    'requires_image', true,
    'allows_multiple_images', true
  );
$$;

revoke all on function private.default_image_template(text) from public, anon, authenticated, service_role;

create or replace function private.assert_valid_image_template(p_config jsonb)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_config is null
     or jsonb_typeof(p_config) <> 'object'
     or p_config->>'schema' <> 'hpsm.image_template.v1'
     or p_config->>'kind' <> 'imaging'
     or coalesce((p_config->>'version') ~ '^[1-9][0-9]*$', false) is not true
     or jsonb_typeof(p_config->'region') <> 'object'
     or jsonb_typeof(p_config#>'{region,required}') <> 'boolean'
     or jsonb_typeof(p_config#>'{region,options}') <> 'array'
     or jsonb_array_length(p_config#>'{region,options}') not between 1 and 60
     or jsonb_typeof(p_config->'supports_laterality') <> 'boolean'
     or jsonb_typeof(p_config->'supports_contrast') <> 'boolean'
     or jsonb_typeof(p_config->'requires_image') <> 'boolean'
     or jsonb_typeof(p_config->'allows_multiple_images') <> 'boolean' then
    raise exception 'Template de imagem inválido.';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_config#>'{region,options}') option_value
    where jsonb_typeof(option_value) <> 'string'
       or char_length(btrim(option_value #>> '{}')) not between 2 and 120
  ) or (
    select count(*) <> count(distinct lower(btrim(option_value #>> '{}')))
    from jsonb_array_elements(p_config#>'{region,options}') option_value
  ) then
    raise exception 'Revise as regiões disponíveis no template.';
  end if;
end;
$$;

revoke all on function private.assert_valid_image_template(jsonb) from public, anon, authenticated, service_role;

create or replace function private.build_image_result(p_exam_type_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_code text;
  v_name text;
  v_config jsonb;
  v_snapshot jsonb;
begin
  select exam_type.code, exam_type.name, exam_type.result_config
  into v_code, v_name, v_config
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = p_exam_type_id
    and category.code = 'imagem'
    and exam_type.result_config->>'kind' = 'imaging';

  if v_config is null then return '{}'::jsonb; end if;
  perform private.assert_valid_image_template(v_config);
  v_snapshot := v_config || jsonb_build_object('exam_type_code', v_code, 'exam_type_name', v_name);

  return jsonb_build_object(
    'schema', 'hpsm.image_result.v1',
    'template_version', (v_config->>'version')::integer,
    'template_snapshot', v_snapshot,
    'region', '',
    'other_region', '',
    'laterality', case when (v_config->>'supports_laterality')::boolean then '' else 'not_applicable' end,
    'contrast', case when (v_config->>'supports_contrast')::boolean then '' else 'not_applicable' end,
    'notes', ''
  );
end;
$$;

revoke all on function private.build_image_result(bigint) from public, anon, authenticated, service_role;

create or replace function private.build_clinical_exam_result(p_exam_type_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  v_result := private.build_lab_result(p_exam_type_id);
  if v_result <> '{}'::jsonb then return v_result; end if;
  return private.build_image_result(p_exam_type_id);
end;
$$;

revoke all on function private.build_clinical_exam_result(bigint) from public, anon, authenticated, service_role;

create or replace function private.normalize_image_result(p_existing jsonb, p_candidate jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_snapshot jsonb;
  v_region text;
  v_other_region text;
  v_laterality text;
  v_contrast text;
  v_notes text;
begin
  if p_existing->>'schema' <> 'hpsm.image_result.v1'
     or jsonb_typeof(p_existing->'template_snapshot') <> 'object' then
    raise exception 'O resultado de imagem não possui um snapshot válido.';
  end if;
  if p_candidate is null
     or jsonb_typeof(p_candidate) <> 'object'
     or p_candidate->>'schema' <> 'hpsm.image_result.v1'
     or p_candidate->'template_snapshot' is distinct from p_existing->'template_snapshot'
     or p_candidate->'template_version' is distinct from p_existing->'template_version' then
    raise exception 'O snapshot do template não pode ser alterado.';
  end if;

  v_snapshot := p_existing->'template_snapshot';
  v_region := left(btrim(coalesce(p_candidate->>'region', '')), 120);
  v_other_region := left(btrim(coalesce(p_candidate->>'other_region', '')), 160);
  v_laterality := coalesce(p_candidate->>'laterality', '');
  v_contrast := coalesce(p_candidate->>'contrast', '');
  v_notes := left(coalesce(p_candidate->>'notes', ''), 4000);

  if v_region <> '' and not exists (
    select 1 from jsonb_array_elements_text(v_snapshot#>'{region,options}') option_value
    where option_value = v_region
  ) then raise exception 'Região inválida para este exame.'; end if;
  if v_region = 'Outra região' and v_other_region = '' then
    raise exception 'Informe a outra região examinada.';
  end if;
  if v_region <> 'Outra região' then v_other_region := ''; end if;

  if (v_snapshot->>'supports_laterality')::boolean then
    if v_laterality not in ('', 'left', 'right', 'bilateral', 'not_applicable') then
      raise exception 'Lateralidade inválida.';
    end if;
  else
    v_laterality := 'not_applicable';
  end if;

  if (v_snapshot->>'supports_contrast')::boolean then
    if v_contrast not in ('', 'with', 'without', 'not_applicable') then
      raise exception 'Uso de contraste inválido.';
    end if;
  else
    v_contrast := 'not_applicable';
  end if;

  return jsonb_build_object(
    'schema', 'hpsm.image_result.v1',
    'template_version', p_existing->'template_version',
    'template_snapshot', v_snapshot,
    'region', v_region,
    'other_region', v_other_region,
    'laterality', v_laterality,
    'contrast', v_contrast,
    'notes', v_notes
  );
end;
$$;

revoke all on function private.normalize_image_result(jsonb, jsonb) from public, anon, authenticated, service_role;

update public.exam_types exam_type
set result_config = private.default_image_template(exam_type.code)
from public.exam_categories category
where category.id = exam_type.category_id
  and category.code = 'imagem'
  and exam_type.result_config = '{}'::jsonb;

do $$
declare v_config jsonb;
begin
  for v_config in
    select exam_type.result_config
    from public.exam_types exam_type
    join public.exam_categories category on category.id = exam_type.category_id
    where category.code = 'imagem' and exam_type.result_config->>'kind' = 'imaging'
  loop
    perform private.assert_valid_image_template(v_config);
  end loop;
end;
$$;

create table public.clinical_exam_images (
  id uuid primary key,
  exam_id bigint not null references public.clinical_exams(id) on delete restrict,
  storage_path text not null unique,
  original_filename text not null,
  mime_type text not null,
  file_size bigint not null,
  sort_order integer not null default 0,
  caption text,
  source text not null default 'upload',
  uploaded_by uuid not null references public.profiles(user_id) on delete restrict,
  removed_by uuid references public.profiles(user_id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  removed_at timestamptz,
  constraint clinical_exam_images_path_check check (storage_path ~ '^clinical-exams/[0-9]+/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|png|webp)$'),
  constraint clinical_exam_images_filename_check check (char_length(btrim(original_filename)) between 1 and 240),
  constraint clinical_exam_images_mime_check check (mime_type in ('image/jpeg', 'image/png', 'image/webp')),
  constraint clinical_exam_images_size_check check (file_size between 1 and 10485760),
  constraint clinical_exam_images_sort_check check (sort_order between 0 and 100000),
  constraint clinical_exam_images_caption_check check (caption is null or char_length(btrim(caption)) between 1 and 500),
  constraint clinical_exam_images_source_check check (source in ('upload', 'ai_generated')),
  constraint clinical_exam_images_removal_check check ((removed_at is null and removed_by is null) or (removed_at is not null and removed_by is not null))
);

create index clinical_exam_images_exam_active_idx
  on public.clinical_exam_images (exam_id, sort_order, created_at, id)
  where removed_at is null;
create index clinical_exam_images_uploaded_by_idx on public.clinical_exam_images (uploaded_by, created_at desc);
create index clinical_exam_images_removed_by_idx on public.clinical_exam_images (removed_by, removed_at desc) where removed_by is not null;

drop trigger if exists clinical_exam_images_touch_updated_at on public.clinical_exam_images;
create trigger clinical_exam_images_touch_updated_at
before update on public.clinical_exam_images
for each row execute function private.touch_updated_at();

alter table public.clinical_exam_images enable row level security;
alter table public.clinical_exam_images force row level security;

create policy clinical_exam_images_read_authorized
on public.clinical_exam_images for select to authenticated
using ((select private.has_permission((select auth.uid()), 'exams.view')));

revoke all on public.clinical_exam_images from public, anon, authenticated, service_role;
grant select on public.clinical_exam_images to authenticated, service_role;
grant insert, update on public.clinical_exam_images to service_role;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'clinical-exam-images', 'clinical-exam-images', false, 10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists clinical_exam_images_storage_read on storage.objects;
create policy clinical_exam_images_storage_read
on storage.objects for select to authenticated
using (
  bucket_id = 'clinical-exam-images'
  and exists (
    select 1 from public.clinical_exam_images image
    where image.storage_path = name
      and image.removed_at is null
      and private.has_permission((select auth.uid()), 'exams.view')
  )
);

drop policy if exists clinical_exam_images_storage_insert on storage.objects;
create policy clinical_exam_images_storage_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'clinical-exam-images'
  and (storage.foldername(name))[1] = 'clinical-exams'
  and coalesce((storage.foldername(name))[2] ~ '^[0-9]+$', false)
  and exists (
    select 1 from public.clinical_exams exam
    where exam.id = ((storage.foldername(name))[2])::bigint
      and exam.status = 'in_progress'
      and (
        (exam.responsible_professional_id = (select auth.uid()) and private.has_permission((select auth.uid()), 'exams.perform'))
        or private.has_permission((select auth.uid()), 'exams.review')
      )
  )
);

drop policy if exists clinical_exam_images_storage_delete on storage.objects;
create policy clinical_exam_images_storage_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'clinical-exam-images'
  and (storage.foldername(name))[1] = 'clinical-exams'
  and coalesce((storage.foldername(name))[2] ~ '^[0-9]+$', false)
  and exists (
    select 1 from public.clinical_exams exam
    where exam.id = ((storage.foldername(name))[2])::bigint
      and exam.status = 'in_progress'
      and (
        (exam.responsible_professional_id = (select auth.uid()) and private.has_permission((select auth.uid()), 'exams.perform'))
        or private.has_permission((select auth.uid()), 'exams.review')
      )
  )
);

create or replace function public.clinical_exam_imaging_template_catalog()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_actor uuid := auth.uid();
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.catalog.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', exam_type.id,
      'code', exam_type.code,
      'name', exam_type.name,
      'active', exam_type.active,
      'result_config', exam_type.result_config
    ) order by exam_type.sort_order, exam_type.name)
    from public.exam_types exam_type
    join public.exam_categories category on category.id = exam_type.category_id
    where category.code = 'imagem' and exam_type.result_config->>'kind' = 'imaging'
  ), '[]'::jsonb);
end;
$$;

create or replace function public.manage_exam_imaging_template(
  p_exam_type_id bigint,
  p_expected_version integer,
  p_region_required boolean,
  p_region_options jsonb,
  p_supports_laterality boolean,
  p_supports_contrast boolean,
  p_requires_image boolean,
  p_allows_multiple_images boolean
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_type public.exam_types;
  v_old_config jsonb;
  v_new_config jsonb;
  v_new_version integer;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.catalog.manage') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  select exam_type.* into v_type
  from public.exam_types exam_type
  join public.exam_categories category on category.id = exam_type.category_id
  where exam_type.id = p_exam_type_id and category.code = 'imagem'
  for update of exam_type;
  if v_type.id is null or v_type.result_config->>'kind' <> 'imaging' then
    raise exception 'Template de imagem não localizado.';
  end if;
  if p_expected_version is distinct from (v_type.result_config->>'version')::integer then
    raise exception 'O template foi atualizado por outra pessoa. Reabra-o antes de salvar.';
  end if;
  if jsonb_typeof(p_region_options) <> 'array' then raise exception 'A lista de regiões é inválida.'; end if;

  v_old_config := v_type.result_config;
  v_new_version := p_expected_version + 1;
  v_new_config := jsonb_build_object(
    'schema', 'hpsm.image_template.v1',
    'kind', 'imaging',
    'version', v_new_version,
    'region', jsonb_build_object('required', coalesce(p_region_required, true), 'options', p_region_options),
    'supports_laterality', coalesce(p_supports_laterality, false),
    'supports_contrast', coalesce(p_supports_contrast, false),
    'requires_image', coalesce(p_requires_image, true),
    'allows_multiple_images', coalesce(p_allows_multiple_images, true)
  );
  perform private.assert_valid_image_template(v_new_config);

  update public.exam_types set result_config = v_new_config, updated_by = v_actor
  where id = p_exam_type_id;
  perform private.audit_exam_action(
    v_actor, 'exam_imaging_template.updated', 'exam_types', p_exam_type_id::text,
    jsonb_build_object('result_config', v_old_config), jsonb_build_object('result_config', v_new_config)
  );
  return v_new_version;
end;
$$;

create or replace function public.clinical_exam_image_gallery(p_exam_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_actor uuid := auth.uid();
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.clinical_exams exam where exam.id = p_exam_id) then
    raise exception 'Exame não localizado.';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', image.id,
      'exam_id', image.exam_id,
      'storage_path', image.storage_path,
      'original_filename', image.original_filename,
      'mime_type', image.mime_type,
      'file_size', image.file_size,
      'sort_order', image.sort_order,
      'caption', image.caption,
      'source', image.source,
      'uploaded_by', image.uploaded_by,
      'created_at', image.created_at
    ) order by image.sort_order, image.created_at, image.id)
    from public.clinical_exam_images image
    where image.exam_id = p_exam_id and image.removed_at is null
  ), '[]'::jsonb);
end;
$$;

create or replace function public.clinical_exam_image_upload_context(p_exam_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_exam public.clinical_exams;
  v_count integer;
begin
  select * into v_exam from public.clinical_exams where id = p_exam_id;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_exam.responsible_professional_id) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_exam.status <> 'in_progress' then raise exception 'As imagens só podem ser alteradas enquanto o exame está em andamento.'; end if;
  if v_exam.result_data->>'schema' <> 'hpsm.image_result.v1' then raise exception 'Este exame não utiliza imagens clínicas.'; end if;
  select count(*) into v_count from public.clinical_exam_images image where image.exam_id = p_exam_id and image.removed_at is null;
  return jsonb_build_object(
    'active_image_count', v_count,
    'allows_multiple_images', (v_exam.result_data#>>'{template_snapshot,allows_multiple_images}')::boolean
  );
end;
$$;

create or replace function public.register_clinical_exam_image(
  p_exam_id bigint,
  p_image_id uuid,
  p_storage_path text,
  p_original_filename text,
  p_mime_type text,
  p_file_size bigint,
  p_caption text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_exam public.clinical_exams;
  v_image public.clinical_exam_images;
  v_expected_extension text;
  v_count integer;
begin
  select * into v_exam from public.clinical_exams where id = p_exam_id for update;
  if v_exam.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_exam.responsible_professional_id) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_exam.status <> 'in_progress' then raise exception 'As imagens só podem ser alteradas enquanto o exame está em andamento.'; end if;
  if v_exam.result_data->>'schema' <> 'hpsm.image_result.v1' then raise exception 'Este exame não utiliza imagens clínicas.'; end if;

  select count(*) into v_count from public.clinical_exam_images image where image.exam_id = p_exam_id and image.removed_at is null;
  if not (v_exam.result_data#>>'{template_snapshot,allows_multiple_images}')::boolean and v_count > 0 then
    raise exception 'Este tipo de exame aceita somente uma imagem.';
  end if;
  v_expected_extension := case p_mime_type when 'image/jpeg' then 'jpg' when 'image/png' then 'png' when 'image/webp' then 'webp' else null end;
  if p_image_id is null
     or v_expected_extension is null
     or p_file_size not between 1 and 10485760
     or p_storage_path <> 'clinical-exams/' || p_exam_id::text || '/' || p_image_id::text || '.' || v_expected_extension then
    raise exception 'Metadados da imagem inválidos.';
  end if;

  insert into public.clinical_exam_images (
    id, exam_id, storage_path, original_filename, mime_type, file_size,
    sort_order, caption, source, uploaded_by
  ) values (
    p_image_id, p_exam_id, p_storage_path, left(btrim(p_original_filename), 240), p_mime_type, p_file_size,
    (v_count + 1) * 10, nullif(left(btrim(p_caption), 500), ''), 'upload', v_actor
  ) returning * into v_image;
  update public.clinical_exams set updated_at = now() where id = p_exam_id;
  perform private.audit_exam_action(
    v_actor, 'clinical_exam.image_added', 'clinical_exam_images', v_image.id::text, null,
    jsonb_build_object('exam_id', v_image.exam_id, 'storage_path', v_image.storage_path, 'mime_type', v_image.mime_type, 'file_size', v_image.file_size, 'caption', v_image.caption, 'source', v_image.source)
  );
  return jsonb_build_object('id', v_image.id, 'exam_id', v_image.exam_id, 'storage_path', v_image.storage_path, 'original_filename', v_image.original_filename, 'mime_type', v_image.mime_type, 'file_size', v_image.file_size, 'sort_order', v_image.sort_order, 'caption', v_image.caption, 'source', v_image.source, 'uploaded_by', v_image.uploaded_by, 'created_at', v_image.created_at);
end;
$$;

create or replace function public.remove_clinical_exam_image(p_image_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_exam public.clinical_exams;
  v_image public.clinical_exam_images;
begin
  select image.* into v_image from public.clinical_exam_images image where image.id = p_image_id for update;
  if v_image.id is null or v_image.removed_at is not null then raise exception 'Imagem não localizada.'; end if;
  select * into v_exam from public.clinical_exams where id = v_image.exam_id for update;
  if not private.can_perform_clinical_exam(v_actor, v_exam.responsible_professional_id) then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if v_exam.status <> 'in_progress' then raise exception 'As imagens só podem ser alteradas enquanto o exame está em andamento.'; end if;

  update public.clinical_exam_images set removed_at = now(), removed_by = v_actor where id = p_image_id;
  update public.clinical_exams set updated_at = now() where id = v_image.exam_id;
  perform private.audit_exam_action(
    v_actor, 'clinical_exam.image_removed', 'clinical_exam_images', v_image.id::text,
    jsonb_build_object('exam_id', v_image.exam_id, 'storage_path', v_image.storage_path, 'caption', v_image.caption),
    jsonb_build_object('removed', true)
  );
  return v_image.storage_path;
end;
$$;

create or replace function public.restore_clinical_exam_image(p_image_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_image public.clinical_exam_images;
begin
  select * into v_image from public.clinical_exam_images where id = p_image_id for update;
  if v_image.id is null
     or v_image.removed_by is distinct from v_actor
     or v_image.removed_at is null
     or v_image.removed_at < now() - interval '5 minutes' then
    raise exception 'Não foi possível restaurar o metadado da imagem.';
  end if;
  update public.clinical_exam_images set removed_at = null, removed_by = null where id = p_image_id;
  update public.clinical_exams set updated_at = now() where id = v_image.exam_id;
  perform private.audit_exam_action(v_actor, 'clinical_exam.image_removal_compensated', 'clinical_exam_images', p_image_id::text, jsonb_build_object('removed', true), jsonb_build_object('removed', false));
end;
$$;

create or replace function public.create_clinical_exam(
  p_patient_id bigint,
  p_exam_type_id bigint,
  p_responsible_professional_id uuid,
  p_indication text,
  p_clinical_context text default null,
  p_attendance_id bigint default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_responsible uuid := coalesce(p_responsible_professional_id, v_actor);
  v_exam public.clinical_exams;
  v_result_data jsonb;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.create') or not private.has_permission(v_actor, 'patients.view') then
    raise exception 'Acesso não autorizado.' using errcode = '42501';
  end if;
  if not exists (select 1 from public.patients patient where patient.id = p_patient_id) then raise exception 'Paciente não localizado.'; end if;
  if not exists (
    select 1 from public.exam_types exam_type join public.exam_categories category on category.id = exam_type.category_id
    where exam_type.id = p_exam_type_id and exam_type.active and category.active
  ) then raise exception 'Tipo de exame indisponível.'; end if;
  if not exists (select 1 from public.profiles profile where profile.user_id = v_responsible and profile.status = 'active')
     or not (private.has_permission(v_responsible, 'exams.perform') or private.has_permission(v_responsible, 'exams.review')) then
    raise exception 'Profissional responsável inválido.';
  end if;
  v_result_data := private.build_clinical_exam_result(p_exam_type_id);
  insert into public.clinical_exams (patient_id, exam_type_id, attendance_id, requested_by, responsible_professional_id, indication, clinical_context, result_data)
  values (p_patient_id, p_exam_type_id, p_attendance_id, v_actor, v_responsible, btrim(p_indication), nullif(btrim(p_clinical_context), ''), v_result_data)
  returning * into v_exam;
  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note)
  values (v_exam.id, null, 'requested', v_actor, 'Exame solicitado.');
  perform private.audit_exam_action(v_actor, 'clinical_exam.created', 'clinical_exams', v_exam.id::text, null, to_jsonb(v_exam));
  return v_exam.id;
end;
$$;

create or replace function public.start_clinical_exam(p_exam_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
  v_result_data jsonb;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_old.responsible_professional_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_old.status <> 'requested' then raise exception 'O exame não está disponível para início.'; end if;
  v_result_data := case
    when v_old.result_data->>'schema' in ('hpsm.lab_result.v1', 'hpsm.image_result.v1') then v_old.result_data
    else private.build_clinical_exam_result(v_old.exam_type_id)
  end;
  update public.clinical_exams set status = 'in_progress', started_at = now(), result_data = v_result_data where id = p_exam_id returning * into v_new;
  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note) values (p_exam_id, 'requested', 'in_progress', v_actor, 'Execução iniciada.');
  perform private.audit_exam_action(v_actor, 'clinical_exam.started', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
end;
$$;

create or replace function public.save_clinical_exam_draft(
  p_exam_id bigint,
  p_technique text,
  p_findings text,
  p_conclusion text,
  p_result_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
  v_result_data jsonb;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_old.responsible_professional_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_old.status <> 'in_progress' then raise exception 'O exame não está em andamento.'; end if;
  if p_result_data is null or jsonb_typeof(p_result_data) <> 'object' then raise exception 'Dados adicionais inválidos.'; end if;
  v_result_data := case
    when v_old.result_data->>'schema' = 'hpsm.lab_result.v1' then private.normalize_lab_result(v_old.result_data, p_result_data)
    when v_old.result_data->>'schema' = 'hpsm.image_result.v1' then private.normalize_image_result(v_old.result_data, p_result_data)
    else p_result_data
  end;
  update public.clinical_exams set technique = nullif(btrim(p_technique), ''), findings = nullif(btrim(p_findings), ''), conclusion = nullif(btrim(p_conclusion), ''), result_data = v_result_data
  where id = p_exam_id returning * into v_new;
  if (to_jsonb(v_old) - 'updated_at') is distinct from (to_jsonb(v_new) - 'updated_at') then
    perform private.audit_exam_action(
      v_actor, 'clinical_exam.result_saved', 'clinical_exams', p_exam_id::text,
      jsonb_build_object('technique', v_old.technique, 'findings', v_old.findings, 'conclusion', v_old.conclusion, 'result_data', v_old.result_data),
      jsonb_build_object('technique', v_new.technique, 'findings', v_new.findings, 'conclusion', v_new.conclusion, 'result_data', v_new.result_data)
    );
  end if;
end;
$$;

create or replace function public.submit_clinical_exam_review(p_exam_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.clinical_exams;
  v_new public.clinical_exams;
  v_missing text;
begin
  select * into v_old from public.clinical_exams where id = p_exam_id for update;
  if v_old.id is null then raise exception 'Exame não localizado.'; end if;
  if not private.can_perform_clinical_exam(v_actor, v_old.responsible_professional_id) then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  if v_old.status <> 'in_progress' then raise exception 'O exame não está em andamento.'; end if;
  if v_old.technique is null or v_old.findings is null or v_old.conclusion is null then raise exception 'Preencha técnica, achados e conclusão antes do envio.'; end if;
  if v_old.result_data->>'schema' = 'hpsm.lab_result.v1' then
    select string_agg(snapshot->>'label', ', ' order by (snapshot->>'sort_order')::integer) into v_missing
    from jsonb_array_elements(v_old.result_data#>'{template_snapshot,parameters}') snapshot
    where (snapshot->>'active')::boolean and (snapshot->>'required')::boolean
      and not exists (
        select 1 from jsonb_array_elements(v_old.result_data->'parameters') result_parameter
        where result_parameter->>'key' = snapshot->>'key' and nullif(btrim(result_parameter->>'value'), '') is not null
      );
    if v_missing is not null then raise exception 'Preencha os parâmetros obrigatórios: %.', v_missing; end if;
  elsif v_old.result_data->>'schema' = 'hpsm.image_result.v1' then
    if (v_old.result_data#>>'{template_snapshot,region,required}')::boolean and nullif(btrim(v_old.result_data->>'region'), '') is null then
      raise exception 'Selecione a região examinada.';
    end if;
    if v_old.result_data->>'region' = 'Outra região' and nullif(btrim(v_old.result_data->>'other_region'), '') is null then
      raise exception 'Informe a outra região examinada.';
    end if;
    if (v_old.result_data#>>'{template_snapshot,supports_laterality}')::boolean and nullif(v_old.result_data->>'laterality', '') is null then
      raise exception 'Selecione a lateralidade.';
    end if;
    if (v_old.result_data#>>'{template_snapshot,supports_contrast}')::boolean and nullif(v_old.result_data->>'contrast', '') is null then
      raise exception 'Informe o uso de contraste.';
    end if;
    if (v_old.result_data#>>'{template_snapshot,requires_image}')::boolean and not exists (
      select 1 from public.clinical_exam_images image where image.exam_id = p_exam_id and image.removed_at is null
    ) then raise exception 'Adicione ao menos uma imagem antes do envio.'; end if;
  end if;
  update public.clinical_exams set status = 'awaiting_review', submitted_for_review_at = now() where id = p_exam_id returning * into v_new;
  insert into public.clinical_exam_status_history (exam_id, from_status, to_status, changed_by, note) values (p_exam_id, 'in_progress', 'awaiting_review', v_actor, 'Exame enviado para revisão.');
  perform private.audit_exam_action(v_actor, 'clinical_exam.submitted_for_review', 'clinical_exams', p_exam_id::text, to_jsonb(v_old), to_jsonb(v_new));
end;
$$;

create or replace function public.manage_exam_type(
  p_id bigint,
  p_category_id bigint,
  p_name text,
  p_code text,
  p_description text,
  p_active boolean,
  p_sort_order integer
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_old public.exam_types;
  v_new public.exam_types;
  v_category_active boolean;
  v_category_code text;
  v_result_config jsonb := '{}'::jsonb;
  v_action text;
begin
  if v_actor is null or not private.has_permission(v_actor, 'exams.catalog.manage') then raise exception 'Acesso não autorizado.' using errcode = '42501'; end if;
  select category.active, category.code into v_category_active, v_category_code from public.exam_categories category where category.id = p_category_id;
  if v_category_active is null then raise exception 'Categoria não localizada.'; end if;
  if p_active and not v_category_active then raise exception 'Ative a categoria antes de ativar o tipo de exame.'; end if;
  if v_category_code = 'laboratorial' then
    v_result_config := jsonb_build_object('schema','hpsm.lab_template.v1','kind','laboratory','version',1,'parameters',jsonb_build_array());
  elsif v_category_code = 'imagem' then
    v_result_config := private.default_image_template(btrim(p_code));
  end if;
  if p_id is null then
    insert into public.exam_types (category_id, code, name, description, active, sort_order, result_config, created_by, updated_by)
    values (p_category_id, btrim(p_code), btrim(p_name), nullif(btrim(p_description), ''), coalesce(p_active, true), p_sort_order, v_result_config, v_actor, v_actor)
    returning * into v_new;
    v_action := 'exam_type.created';
  else
    select * into v_old from public.exam_types where id = p_id for update;
    if v_old.id is null then raise exception 'Tipo de exame não localizado.'; end if;
    update public.exam_types set
      category_id = p_category_id,
      name = btrim(p_name),
      description = nullif(btrim(p_description), ''),
      active = p_active,
      sort_order = p_sort_order,
      result_config = case
        when v_category_code = 'laboratorial' and result_config->>'kind' is distinct from 'laboratory' then v_result_config
        when v_category_code = 'imagem' and result_config->>'kind' is distinct from 'imaging' then v_result_config
        else result_config
      end,
      updated_by = v_actor
    where id = p_id returning * into v_new;
    v_action := case when v_old.active is distinct from v_new.active then 'exam_type.status_changed' else 'exam_type.updated' end;
  end if;
  perform private.audit_exam_action(v_actor, v_action, 'exam_types', v_new.id::text, case when v_old.id is null then null else to_jsonb(v_old) end, to_jsonb(v_new));
  return v_new.id;
end;
$$;

-- Inicializa solicitações e exames em andamento de imagem sem tocar resultados concluídos.
update public.clinical_exams exam
set result_data = private.build_image_result(exam.exam_type_id)
from public.exam_types exam_type
join public.exam_categories category on category.id = exam_type.category_id
where exam.exam_type_id = exam_type.id
  and category.code = 'imagem'
  and exam_type.result_config->>'kind' = 'imaging'
  and exam.status in ('requested', 'in_progress')
  and exam.result_data = '{}'::jsonb;

revoke all on function public.clinical_exam_imaging_template_catalog() from public, anon, authenticated;
revoke all on function public.manage_exam_imaging_template(bigint, integer, boolean, jsonb, boolean, boolean, boolean, boolean) from public, anon, authenticated;
revoke all on function public.clinical_exam_image_gallery(bigint) from public, anon, authenticated;
revoke all on function public.clinical_exam_image_upload_context(bigint) from public, anon, authenticated;
revoke all on function public.register_clinical_exam_image(bigint, uuid, text, text, text, bigint, text) from public, anon, authenticated;
revoke all on function public.remove_clinical_exam_image(uuid) from public, anon, authenticated;
revoke all on function public.restore_clinical_exam_image(uuid) from public, anon, authenticated;
grant execute on function public.clinical_exam_imaging_template_catalog() to authenticated;
grant execute on function public.manage_exam_imaging_template(bigint, integer, boolean, jsonb, boolean, boolean, boolean, boolean) to authenticated;
grant execute on function public.clinical_exam_image_gallery(bigint) to authenticated;
grant execute on function public.clinical_exam_image_upload_context(bigint) to authenticated;
grant execute on function public.register_clinical_exam_image(bigint, uuid, text, text, text, bigint, text) to authenticated;
grant execute on function public.remove_clinical_exam_image(uuid) to authenticated;
grant execute on function public.restore_clinical_exam_image(uuid) to authenticated;

comment on table public.clinical_exam_images is 'Metadados protegidos das imagens clínicas; os bytes permanecem no bucket privado clinical-exam-images.';
comment on column public.clinical_exam_images.source is 'Origem da imagem: upload manual nesta fase; ai_generated reservado para evolução futura.';
comment on column public.exam_types.result_config is 'Template configurável e versionado; laboratórios usam hpsm.lab_template.v1 e imagens usam hpsm.image_template.v1.';
comment on column public.clinical_exams.result_data is 'Resultado clínico com snapshot imutável do template para laboratórios e exames de imagem.';

notify pgrst, 'reload schema';
