-- A busca canônica delega ao snapshot pré-normalização; amplia o leitor na
-- função-fonte para que a consulta institucional alcance catálogo e seleção.
do $$
declare
  v_oid oid;
  v_definition text;
begin
  select procedure.oid into v_oid
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname = 'hpsm_global_search_pre_canonical';

  if v_oid is null then
    raise exception 'Função-fonte da busca global não localizada.';
  end if;

  v_definition := pg_get_functiondef(v_oid);
  v_definition := replace(
    v_definition,
    '''recruitment.manage'' = any(v_permissions)',
    '(''recruitment.manage'' = any(v_permissions) or ''sr.directors.view'' = any(v_permissions))'
  );
  v_definition := replace(
    v_definition,
    '''catalog.manage'' = any(v_permissions)',
    '(''catalog.manage'' = any(v_permissions) or ''catalog.view'' = any(v_permissions))'
  );
  execute v_definition;
end;
$$;
