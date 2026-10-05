import assert from "node:assert/strict";
import { test } from "node:test";
import { build } from "esbuild";
import { readFile, rm } from "node:fs/promises";

const bundle = `/tmp/hpsm-consultation-exam-suggestions-${process.pid}.mjs`;
await build({
  entryPoints: [new URL("../app/lib/consultation-exam-suggestions.ts", import.meta.url).pathname],
  outfile: bundle,
  bundle: true,
  platform: "node",
  format: "esm",
});
const { pendingExamSuggestions } = await import(bundle);
await rm(bundle);

test("retira sugestões com solicitação, execução ou conclusão vinculada e mantém tipos ainda pendentes", () => {
  const suggestions = [1, 2, 3, 4, 5].map((exam_type_id) => ({ exam_type_id }));
  const exams = [
    { exam_type_id: 1, status: "requested" },
    { exam_type_id: 2, status: "in_progress" },
    { exam_type_id: 3, status: "awaiting_review" },
    { exam_type_id: 4, status: "completed" },
  ];
  assert.deepEqual(pendingExamSuggestions(suggestions, exams), [{ exam_type_id: 5 }]);
  assert.deepEqual(pendingExamSuggestions(suggestions, []), suggestions);
  assert.deepEqual(pendingExamSuggestions([{ exam_type_id: 5 }, { exam_type_id: 5 }], exams), [{ exam_type_id: 5 }]);
});

test("consulta usa o ID de tipo, protege a criação duplicada e pede escolha explícita ao médico", async () => {
  const [migration, legacyGuard, workspace] = await Promise.all([
    readFile(new URL("../supabase/migrations/20260929172500_consultation_exam_suggestions_and_diagnosis_choice.sql", import.meta.url), "utf8"),
    readFile(new URL("../supabase/migrations/20260929172600_guard_legacy_consultation_exam_request.sql", import.meta.url), "utf8"),
    readFile(new URL("../app/components/consultation-workspace.tsx", import.meta.url), "utf8"),
  ]);
  assert.match(migration, /'exam_type_id', exam\.exam_type_id/);
  assert.match(migration, /exam\.consultation_id = p_consultation_id and exam\.exam_type_id = p_exam_type_id/);
  assert.match(legacyGuard, /null::bigint,\s*null::jsonb/);
  assert.match(workspace, /pendingExamSuggestions\(examAnalysis\?\.exam_suggestions \?\? \[\], consultation\.exams\)/);
  assert.match(workspace, /Escolha do médico obrigatória/);
  assert.match(workspace, /Selecionar esta hipótese/);
});
