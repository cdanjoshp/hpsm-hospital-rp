-- A sugestão é derivada do déficit. Registrar a dispensa na apuração impede
-- que ela reapareça sem alterar horas, justificativas ou advertências emitidas.
alter table public.rh_weekly_records
  add column warning_suggestion_dismissed_at timestamptz,
  add column warning_suggestion_dismissed_by uuid references public.profiles(user_id) on delete restrict,
  add column warning_suggestion_dismissal_note text,
  add constraint rh_weekly_records_warning_dismissal_consistency check (
    (warning_suggestion_dismissed_at is null and warning_suggestion_dismissed_by is null and warning_suggestion_dismissal_note is null)
    or (warning_suggestion_dismissed_at is not null and warning_suggestion_dismissed_by is not null)
  ),
  add constraint rh_weekly_records_warning_dismissal_note_length check (
    warning_suggestion_dismissal_note is null or char_length(warning_suggestion_dismissal_note) <= 500
  );

create or replace function public.dismiss_hr_warning_suggestion(
  p_weekly_record_id bigint,
  p_note text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_record public.rh_weekly_records;
begin
  if not private.has_permission(p_actor_id, 'hr.warnings.issue') then
    raise exception 'Você não possui permissão para excluir sugestões de ADV.' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_note, ''))) > 500 then
    raise exception 'O motivo deve ter até 500 caracteres.' using errcode = '22023';
  end if;

  select * into v_record
  from public.rh_weekly_records
  where id = p_weekly_record_id
  for update;
  if v_record.id is null or v_record.closure_status <> 'closed'
     or v_record.remaining_deficit_minutes <= 0
     or exists (select 1 from public.rh_warnings warning where warning.weekly_record_id = p_weekly_record_id) then
    raise exception 'Esta sugestão não está mais disponível.' using errcode = '22023';
  end if;
  if v_record.warning_suggestion_dismissed_at is not null then
    raise exception 'Esta sugestão já foi excluída.' using errcode = '22023';
  end if;

  update public.rh_weekly_records
  set warning_suggestion_dismissed_at = now(),
      warning_suggestion_dismissed_by = p_actor_id,
      warning_suggestion_dismissal_note = nullif(btrim(p_note), ''),
      updated_at = now()
  where id = p_weekly_record_id;

  return jsonb_build_object('weekly_record_id', p_weekly_record_id, 'dismissed', true);
end;
$$;

-- A aplicação usa o mesmo registro de fechamento. Respeitar a dispensa também
-- nas escritas evita que uma tela antiga ou uma chamada concorrente a ignore.
create or replace function private.reject_dismissed_hr_warning_suggestion()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.weekly_record_id is not null and exists (
    select 1 from public.rh_weekly_records record
    where record.id = new.weekly_record_id and record.warning_suggestion_dismissed_at is not null
  ) then
    raise exception 'A sugestão de ADV deste fechamento foi excluída pela Diretoria.' using errcode = '22023';
  end if;
  return new;
end;
$$;

create trigger rh_warnings_reject_dismissed_suggestion
before insert or update of weekly_record_id on public.rh_warnings
for each row execute function private.reject_dismissed_hr_warning_suggestion();

revoke all on function public.dismiss_hr_warning_suggestion(bigint, text, uuid) from public, anon, authenticated, service_role;
grant execute on function public.dismiss_hr_warning_suggestion(bigint, text, uuid) to service_role;
revoke all on function private.reject_dismissed_hr_warning_suggestion() from public, anon, authenticated, service_role;
