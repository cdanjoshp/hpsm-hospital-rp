# Supabase · HPSM 1.1.0

O Site usa o Supabase por HTTPS para autenticação e banco de dados. O e-mail
interno do Supabase é sintético, derivado no servidor a partir da matrícula e
nunca aparece na interface.

## Conectar um projeto

1. Crie um projeto vazio no Supabase.
2. Aplique, em ordem, todas as migrations versionadas em `migrations/`. Não use `HPSM_SCHEMA_1.0.sql` nem `HPSM_SCHEMA_1.1.sql` como migration incremental.
3. Em **Authentication**, mantenha o cadastro público desativado. Não configure
   recuperação de senha por e-mail; a Diretoria redefine senhas no sistema.
4. Configure no ambiente do Site:
   - `SUPABASE_URL`: URL HTTPS do projeto.
   - `SUPABASE_ANON_KEY`: chave pública/anon do projeto.
   - `SUPABASE_SERVICE_ROLE_KEY`: chave secreta, apenas no servidor.
   - `PASSPORT_EMAIL_PEPPER`: segredo aleatório estável com pelo menos 32 caracteres.
5. Com o Site ainda privado, visite `/configurar`. A página cria uma única conta
   de Diretor Geral e mostra a senha temporária uma vez. O primeiro login exige
   uma nova senha pessoal.

## Edge Functions

As funções ativas da versão 1.1 são `exam-ai-generate`, `exam-ai-image`,
`exam-delete` e `professional-identity`, todas com validação JWT. As três funções
de IA também usam `OPENAI_API_KEY`, `OPENAI_TEXT_MODEL` e/ou
`OPENAI_IMAGE_MODEL` conforme o módulo. Valores reais devem permanecer apenas
nos secrets do projeto Supabase.

O snapshot `../HPSM_SCHEMA_1.1.sql` é apenas uma referência estrutural sem dados.
As migrações em `migrations/` são a fonte executável para uma instalação nova.

Não altere o `PASSPORT_EMAIL_PEPPER` após criar usuários: ele participa da
derivação determinística da identidade de autenticação.
