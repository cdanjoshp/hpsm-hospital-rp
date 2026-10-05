import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("regimento público possui rota, metadata e acesso institucional pela Home", async () => {
  const [route, home] = await Promise.all([
    read("app/regimento/page.tsx"),
    read("app/components/login-form.tsx"),
  ]);

  assert.match(route, /Regimento Interno \| Hospital Santa Marcelina/);
  assert.match(route, /Regimento Interno e Normas de Boas Práticas do Hospital Santa Marcelina — Cidade dos Anjos\./);
  assert.match(home, /href="\/regimento"/);
  assert.match(home, />Regimento Interno</);
});

test("conteúdo canônico possui artigos 1 a 44, em sequência, e os 14 cargos oficiais", async () => {
  const data = await read("app/lib/regimento-data.ts");
  const articles = [...data.matchAll(/Art\. (\d+)º\./g)].map((match) => Number(match[1]));
  const positions = [
    "Estagiário de Enfermagem", "Estagiário de Medicina", "Auxiliar de Enfermagem", "Técnico de Enfermagem", "Enfermeiro", "Enfermeiro Chefe",
    "Médico 3", "Médico 2", "Médico 1", "Médico Cirurgião", "Médico Chefe",
    "Diretor Administrativo", "Diretor Executivo", "Diretor Geral",
  ];

  assert.deepEqual(articles, Array.from({ length: 44 }, (_, index) => index + 1));
  for (const position of positions) assert.match(data, new RegExp(`— ${position}[;.]`));
  assert.equal((data.match(/\bTCC\b/g) ?? []).length, 1);
  assert.match(data, /O Hospital Santa Marcelina não utiliza Trabalho de Conclusão de Curso — TCC — como requisito de progressão\./);
  assert.match(data, /O cumprimento dos requisitos de carreira não gera promoção automática\./);
});

test("conteúdo preserva contrato, Discord, Beta HCG e análise disciplinar sem desligamento automático", async () => {
  const data = await read("app/lib/regimento-data.ts");
  for (const phrase of [
    "30 dias corridos", "10 horas semanais", "liberdade para organização dos horários de trabalho",
    "R$ 500.000,00", "R$ 100.000,00 por nível hierárquico", "desligamento voluntário ou abandonar suas funções",
    "Discord oficial e sua respectiva call de serviço", "permanecendo na call destinada aos profissionais em atividade",
    "Resultados positivos de Beta HCG", "consentimento relacionado à continuidade do contexto de gestação deverá ser obtido de ambos os genitores",
    "três advertências ativas", "encaminhamento obrigatório do caso para análise da Diretoria",
    "O desligamento decorrente do acúmulo de três advertências não é automático",
  ]) assert.ok(data.includes(phrase), `conteúdo ausente: ${phrase}`);
});

test("busca é local, abre somente as seções relevantes e mantém a navegação compacta e acessível", async () => {
  const [component, styles] = await Promise.all([
    read("app/components/regimento-page.tsx"),
    read("app/brand.css"),
  ]);

  assert.match(component, /placeholder="Buscar no regimento \(ex: atendimento, SAMU, uniforme\)\.\.\."/);
  assert.match(component, /normalize\("NFD"/);
  assert.match(component, /<mark/);
  assert.match(component, /aria-expanded={isOpen}/);
  assert.match(component, /aria-controls={contentId}/);
  assert.match(component, /hashchange/);
  assert.match(component, /scrollIntoView/);
  assert.match(component, /function normalState\(\): OpenSections \{\s*return \{\};\s*\}/);
  assert.match(component, /setOpenSections\(\{ \[target\]: true \}\)/);
  assert.match(component, /subtitle="Compromisso inicial, jornada e permanência"/);
  assert.match(component, /Expandir tudo/);
  assert.match(component, /Recolher tudo/);
  assert.doesNotMatch(component, /fetch\(|supabase|\/api\//i);
  assert.match(styles, /html\[data-theme="dark"\] \.regiment-page/);
  assert.match(styles, /@media \(max-width: 640px\)/);
  assert.match(styles, /@media \(max-width: 340px\)/);
});

test("acesso institucional da Home reutiliza a anatomia dos cartões públicos", async () => {
  const [home, styles] = await Promise.all([
    read("app/components/login-form.tsx"),
    read("app/brand.css"),
  ]);

  assert.match(home, /public-institutional-entry/);
  assert.match(home, /Informações institucionais/);
  assert.match(home, /public-access-option public-regiment-entry/);
  assert.match(home, /public-access-option-icon">▤/);
  assert.match(home, /public-access-arrow">→/);
  assert.match(styles, /\.public-institutional-label::before, \.public-institutional-label::after/);
  assert.match(styles, /\.public-regiment-entry \{ text-decoration: none; \}/);
});
