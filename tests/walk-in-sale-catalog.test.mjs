import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { ModuleKind, ScriptTarget, transpileModule } from "typescript";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

const source = await read("app/lib/walk-in-sale.ts");
const code = transpileModule(source, {
  compilerOptions: { module: ModuleKind.ESNext, target: ScriptTarget.ES2022 },
}).outputText;
const walkIn = await import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`);

test("venda avulsa inclui insumos, medicamentos, tratamento e deslocamentos", () => {
  for (const service of [
    { category: "Insumos", code: "kitmed" },
    { category: "Medicamentos", code: "analgesico" },
    { category: "Atendimentos", code: "tratamento" },
    { category: "Deslocamento", code: "desloc_norte" },
    { category: "Outro rótulo", code: "desloc_sul" },
  ]) assert.equal(walkIn.isWalkInService(service), true);

  assert.equal(walkIn.isWalkInService({ category: "Atendimentos", code: "consulta" }), false);
  assert.equal(walkIn.isWalkInService({ category: "Cirurgias", code: "cirurgia" }), false);
});

test("interface e banco compartilham a mesma ampliação restrita da venda avulsa", async () => {
  const [desk, migration] = await Promise.all([
    read("app/components/attendance-desk.tsx"),
    read("supabase/migrations/20260917015858_allow_walk_in_treatment_and_transport.sql"),
  ]);
  assert.match(desk, /activeServices\.filter\(isWalkInService\)/);
  assert.match(desk, /insumos, medicamentos, tratamento e deslocamentos/);
  assert.match(desk, /Itens da venda avulsa/);
  assert.match(migration, /private\.walk_in_service_allowed/);
  assert.match(migration, /'insumos', 'medicamentos', 'deslocamento'/);
  assert.match(migration, /'tratamento', 'desloc_norte', 'desloc_sul'/);
  assert.match(migration, /where not private\.walk_in_service_allowed\(catalog\.code, catalog\.category\)/);
  assert.doesNotMatch(migration, /plano_saude_convenio[^\n]*walk_in_service_allowed/);
});
