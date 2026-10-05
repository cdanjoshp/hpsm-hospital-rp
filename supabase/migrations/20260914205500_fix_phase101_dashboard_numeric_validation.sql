-- Corrige a expressão numérica da função já instalada na primeira aplicação.
-- Timestamp alinhado ao histórico canônico aplicado no Supabase.
-- Em instalações novas, a migration principal já contém a expressão final e
-- este bloco confirma que não há mais a variante anterior.

do $migration$
declare
  v_definition text := pg_get_functiondef('private.hpsm_dashboard_config_valid(jsonb)'::regprocedure);
  v_old text := chr(39) || '^' || chr(92) || chr(92) || 'd+$' || chr(39);
  v_new text := chr(39) || '^[0-9]+$' || chr(39);
begin
  if position(v_old in v_definition) > 0 then
    execute replace(v_definition, v_old, v_new);
  elsif position(v_new in v_definition) = 0 then
    raise exception 'A validação numérica do Dashboard não foi reconhecida.';
  end if;
end;
$migration$;
