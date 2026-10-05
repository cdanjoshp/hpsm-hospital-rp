-- HPSM — alinha o texto da permissão ao modelo com múltiplos Diretores Gerais.

update public.system_permissions
set label = 'Nomear Diretor Geral',
    description = 'Nomeia outro Diretor Geral com histórico, sem retirar os ocupantes atuais.'
where code = 'succession.manage';
