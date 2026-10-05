# Sistema hospitalar para GTA RP — código do HPSM

Código do sistema usado pelo Hospital Santa Marcelina em um ambiente fictício de GTA RP. Esta cópia foi preparada para que outros hospitais possam estudar e adaptar o projeto sem receber acesso ao banco, às contas, aos arquivos ou à hospedagem de produção do HPSM.

O código e a documentação técnica estão sob licença MIT. O nome e a identidade visual do HPSM não fazem parte dessa permissão; veja [BRANDING.md](BRANDING.md). Quem instalar para outro hospital deve substituir esses elementos.

## O que está incluído

- Aplicação React/Next/Vinext, interface, APIs e testes.
- Migrações estruturais do PostgreSQL/Supabase, regras de acesso e Edge Functions.
- Exemplo com os nomes das variáveis de ambiente, sem seus valores.

Não inclui pacientes, funcionários, senhas, chaves, arquivos privados, histórico de commits nem o identificador da hospedagem do HPSM. Uma nomeação individual que dependia de pessoas cadastradas em produção foi retirada das migrações desta cópia.

## Para criar uma instalação própria

1. Crie **seus próprios** projetos Supabase e Sites. Nunca utilize chaves, domínio ou identificadores do HPSM.
2. Substitua `REPLACE_WITH_YOUR_OWN_SITE_ID` em `.openai/hosting.json` pelo identificador do seu Site. Configure as variáveis listadas em `.env.example` como segredos do seu ambiente. `SUPABASE_SERVICE_ROLE_KEY`, `PASSPORT_EMAIL_PEPPER`, `OPENAI_API_KEY` e `FIVEMANAGE_API_KEY` nunca devem ser enviados ao navegador ou versionados.
3. Aplique as migrações de `supabase/migrations/` em ordem num banco novo e configure as funções de `supabase/functions/` com validação de JWT e os segredos necessários.
4. Configure autenticação e conta inicial seguindo `supabase/README.md`; mantenha o cadastro público desativado até revisar as permissões. Abra `/configurar` somente na sua instalação para criar o primeiro Diretor Geral.
5. Troque o nome, o logotipo, as cores, os textos institucionais, os catálogos, os cargos, o regimento, os links de documentos e `PUBLIC_SITE_URL` para seu hospital. Busque por `HPSM`, `Santa Marcelina`, `Anjos Pharma` e `seu-hospital.example`.
6. Execute `npm run install:ci`, `npm run typecheck`, `npm test` e `npm run build` antes de publicar.

O código foi desenvolvido para **RP**, não para assistência médica real. A publicação do código não concede acesso à instalação existente do HPSM. Integrações com IA e serviço de imagens exigem contas e custos próprios.

## Estado deste pacote

Esta é uma cópia isolada do sistema original, com histórico novo e sem dados de produção. Os nomes e a identidade visual originais ainda constam de várias telas. A aplicação de todas as migrações em um banco novo ainda não foi exercitada neste pacote; confira esse passo antes de colocar uma instalação própria em funcionamento.
