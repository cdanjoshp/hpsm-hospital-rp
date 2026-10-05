-- Mesmo uma identidade médica histórica não pode reabrir o provisionamento
-- enquanto a conta pertencer à categoria externa.
do $$
declare
  v_function record;
  v_definition text;
begin
  for v_function in
    select procedure.oid, procedure.proname
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'professional_identity_generation_context',
        'begin_professional_identity_generation'
      )
  loop
    v_definition := pg_get_functiondef(v_function.oid);
    if v_function.proname = 'professional_identity_generation_context' then
      v_definition := replace(
        v_definition,
        'begin
  if p_operation not in',
        'begin
  if not private.is_hpsm_workforce(v_target) then
    raise exception ''Esta conta institucional não utiliza identidade profissional médica.'' using errcode = ''42501'';
  end if;
  if p_operation not in'
      );
    else
      v_definition := replace(
        v_definition,
        'if not found then raise exception ''Profissional nao localizado.'' using errcode = ''P0002''; end if;',
        'if not found then raise exception ''Profissional nao localizado.'' using errcode = ''P0002''; end if;
  if not private.is_hpsm_workforce(p_target_user_id) then
    raise exception ''Esta conta institucional nao utiliza identidade profissional medica.'' using errcode = ''42501'';
  end if;'
      );
    end if;
    execute v_definition;
  end loop;
end;
$$;
