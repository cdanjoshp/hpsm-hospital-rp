-- Laudos e imagens clínicas não podem expor o contexto externo do sistema.
-- Identificadores históricos de prompt permanecem válidos apenas para auditoria.

alter table public.exam_ai_generations drop constraint exam_ai_generations_prompt_check;
alter table public.exam_ai_generations add constraint exam_ai_generations_prompt_check check (
  (generation_type = 'generate_image' and prompt_version in ('exam-image-rp-v1', 'exam-image-rp-v2', 'exam-image-clinical-v3'))
  or (generation_type = 'generate_exam' and prompt_version in ('exam-rp-luna-v4', 'exam-clinical-exam-v5'))
  or (generation_type = 'generate_report' and prompt_version in ('exam-rp-luna-v1', 'exam-rp-luna-v2', 'exam-rp-luna-v3', 'exam-clinical-report-v4'))
  or (generation_type = 'generate_lab_results' and prompt_version in ('exam-rp-luna-v1', 'exam-rp-luna-v2', 'exam-rp-luna-v3', 'exam-clinical-lab-v3'))
);

create or replace function private.assign_current_exam_ai_prompt_version()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.prompt_version := case new.generation_type
    when 'generate_image' then 'exam-image-clinical-v3'
    when 'generate_lab_results' then 'exam-clinical-lab-v3'
    when 'generate_report' then 'exam-clinical-report-v4'
    when 'generate_exam' then 'exam-clinical-exam-v5'
    else new.prompt_version
  end;
  return new;
end;
$$;

drop trigger if exists exam_ai_generations_current_prompt_version on public.exam_ai_generations;
create trigger exam_ai_generations_current_prompt_version
before insert on public.exam_ai_generations
for each row execute function private.assign_current_exam_ai_prompt_version();

create or replace function private.clinical_text_contains_meta_language(p_value text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select lower(coalesce(p_value, '')) ~
    '(^|[^[:alnum:]_])(gta[[:space:]-]*rp|rp|role[[:space:]-]*play|fict(i|í)ci(o|a|os|as)|simula(ção|ções|cao|coes)|simulad(o|a|os|as)|personagem|personagens|video[[:space:]-]*game|videogame|game)([^[:alnum:]_]|$)';
$$;

create or replace function private.exam_ai_payload_contains_meta_language(p_payload jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select private.clinical_text_contains_meta_language(coalesce(p_payload::text, ''));
$$;

alter function private.validate_exam_ai_suggestion(bigint, text, jsonb)
  rename to validate_exam_ai_suggestion_clinical_v4;

create or replace function private.validate_exam_ai_suggestion(p_exam_id bigint, p_generation_type text, p_payload jsonb)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.validate_exam_ai_suggestion_clinical_v4(p_exam_id, p_generation_type, p_payload);
  if private.exam_ai_payload_contains_meta_language(p_payload) then
    raise exception 'O conteúdo gerado contém referência indevida ao contexto do sistema. Nada foi aplicado.';
  end if;
end;
$$;

create or replace function private.prevent_clinical_report_meta_language()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_report_text text;
begin
  if new.status not in ('awaiting_review', 'completed') then return new; end if;
  v_report_text := concat_ws(
    ' ',
    new.technique,
    new.findings,
    new.conclusion,
    new.result_data->>'notes'
  );
  if private.clinical_text_contains_meta_language(v_report_text) then
    raise exception 'O laudo contém referência indevida ao contexto do sistema. Corrija ou gere novamente.';
  end if;
  return new;
end;
$$;

drop trigger if exists clinical_exams_prevent_meta_language on public.clinical_exams;
create trigger clinical_exams_prevent_meta_language
before update of status, technique, findings, conclusion, result_data on public.clinical_exams
for each row execute function private.prevent_clinical_report_meta_language();

create or replace function private.normalize_ai_clinical_exam_image_metadata()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.source = 'ai_generated' then
    new.original_filename := 'imagem-gerada-ia.png';
    new.caption := 'Imagem gerada por IA.';
  end if;
  return new;
end;
$$;

drop trigger if exists clinical_exam_images_normalize_ai_metadata on public.clinical_exam_images;
create trigger clinical_exam_images_normalize_ai_metadata
before insert or update of source, original_filename, caption on public.clinical_exam_images
for each row execute function private.normalize_ai_clinical_exam_image_metadata();

update public.clinical_exam_images
set original_filename = 'imagem-gerada-ia.png', caption = 'Imagem gerada por IA.'
where source = 'ai_generated'
  and (original_filename is distinct from 'imagem-gerada-ia.png' or caption is distinct from 'Imagem gerada por IA.');

revoke all on function private.assign_current_exam_ai_prompt_version() from public, anon, authenticated, service_role;
revoke all on function private.clinical_text_contains_meta_language(text) from public, anon, authenticated, service_role;
revoke all on function private.exam_ai_payload_contains_meta_language(jsonb) from public, anon, authenticated, service_role;
revoke all on function private.validate_exam_ai_suggestion_clinical_v4(bigint, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.validate_exam_ai_suggestion(bigint, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.prevent_clinical_report_meta_language() from public, anon, authenticated, service_role;
revoke all on function private.normalize_ai_clinical_exam_image_metadata() from public, anon, authenticated, service_role;

comment on function private.clinical_text_contains_meta_language(text) is
  'Detecta linguagem externa ou metalinguagem proibida em conteúdo clínico.';
comment on function private.prevent_clinical_report_meta_language() is
  'Impede que laudos avancem para revisão ou conclusão com referências externas ao atendimento clínico.';

notify pgrst, 'reload schema';
