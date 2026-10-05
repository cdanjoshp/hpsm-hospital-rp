-- A anulação que reduz o ciclo para menos de três ADV também regulariza
-- suspensões que já haviam sido mantidas pela Diretoria.

create or replace function public.annul_hr_warning(
  p_warning_id bigint,
  p_reason text,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_warning public.rh_warnings;
  v_remaining integer;
  v_reactivated boolean := false;
begin
  if not private.is_director_user(p_actor_id) then
    raise exception using errcode = '42501', message = 'Apenas a Diretoria pode anular advertências.';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 10 and 2000 then
    raise exception using errcode = '22023', message = 'Informe o motivo da anulação entre 10 e 2000 caracteres.';
  end if;

  select * into v_warning
  from public.rh_warnings
  where id = p_warning_id
  for update;

  if not found or v_warning.status <> 'active' then
    raise exception using errcode = 'P0002', message = 'Advertência não encontrada ou já anulada.';
  end if;
  if v_warning.employee_id = p_actor_id then
    raise exception using errcode = '42501', message = 'Um diretor não pode anular a própria advertência.';
  end if;

  perform 1 from public.profiles where user_id = v_warning.employee_id for update;

  update public.rh_warnings
  set status = 'annulled',
      annulled_by = p_actor_id,
      annulled_at = now(),
      annulment_reason = btrim(p_reason),
      updated_at = now()
  where id = p_warning_id
  returning * into v_warning;

  update public.rh_weekly_records
  set status = 'warning_annulled', updated_at = now()
  where id = v_warning.weekly_record_id;

  select count(*)::integer into v_remaining
  from public.rh_warnings
  where employee_id = v_warning.employee_id
    and cycle_month = v_warning.cycle_month
    and status = 'active';

  if v_remaining < 3 and exists (
    select 1 from public.rh_disciplinary_reviews
    where employee_id = v_warning.employee_id
      and cycle_month = v_warning.cycle_month
      and status in ('pending', 'suspension_maintained')
  ) then
    update public.rh_disciplinary_reviews
    set status = 'reactivated',
        decided_by = p_actor_id,
        decided_at = now(),
        decision_note = btrim(p_reason),
        updated_at = now()
    where employee_id = v_warning.employee_id
      and cycle_month = v_warning.cycle_month
      and status in ('pending', 'suspension_maintained');

    update public.profiles
    set status = 'active', updated_by = p_actor_id, updated_at = now()
    where user_id = v_warning.employee_id and status = 'suspended';
    v_reactivated := true;
  end if;

  return jsonb_build_object(
    'warning', to_jsonb(v_warning),
    'active_warnings', v_remaining,
    'reactivated', v_reactivated
  );
end;
$$;

revoke all on function public.annul_hr_warning(bigint, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.annul_hr_warning(bigint, text, uuid) to service_role;

notify pgrst, 'reload schema';
