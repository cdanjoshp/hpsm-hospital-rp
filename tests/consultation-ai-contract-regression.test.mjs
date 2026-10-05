import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("Edge Function e RPC de consultas usam o mesmo contrato de IA", async () => {
  const [edge, migration, permissionsMigration] = await Promise.all([
    read("supabase/functions/consultation-ai/index.ts"),
    read("supabase/migrations/20260929181500_consultation_specialty_neutral_ai.sql"),
    read("supabase/migrations/20260925105156_fix_consultation_ai_prompt_contract.sql"),
  ]);

  const promptVersion = edge.match(/const PROMPT_VERSION = "([^"]+)"/)?.[1];
  assert.equal(promptVersion, "consultation-assistant-v8");
  assert.match(migration, /p_prompt_version not in \('consultation-assistant-v6', 'consultation-assistant-v7', 'consultation-assistant-v8'\)/);
  assert.match(migration, /p_model <> 'gpt-5\.6-luna'/);
  assert.match(permissionsMigration, /revoke all on function public\.complete_consultation_ai_generation_v3[\s\S]*from public, anon, authenticated, service_role/i);
  assert.match(permissionsMigration, /grant execute on function public\.complete_consultation_ai_generation_v3[\s\S]*to service_role/i);
});

test("fluxo cobre melhorar texto, sugerir exames e síntese clínica com retry", async () => {
  const [edge, workspace] = await Promise.all([
    read("supabase/functions/consultation-ai/index.ts"),
    read("app/components/consultation-workspace.tsx"),
  ]);

  for (const action of ["ANAMNESIS_REWRITE", "EXAM_SUGGESTIONS", "CLINICAL_SYNTHESIS"]) {
    assert.match(edge, new RegExp(action));
    assert.match(workspace, new RegExp(action));
  }
  assert.match(edge, /status === "failed"|fail_consultation_ai_generation/);
  assert.match(workspace, /finally \{ setBusy\(null\); \}/);
  assert.match(workspace, /O rascunho foi preservado e o botão foi liberado para uma nova tentativa/);
});

test("consultas de rotina e saúde mental não forçam trauma, exames nem gravidade", async () => {
  const [edge, migration, workspace] = await Promise.all([
    read("supabase/functions/consultation-ai/index.ts"),
    read("supabase/migrations/20260929181500_consultation_specialty_neutral_ai.sql"),
    read("app/components/consultation-workspace.tsx"),
  ]);
  assert.match(edge, /appointment_reason: sanitize\(context\.appointment_reason/);
  assert.match(migration, /'appointment_reason', appointment\.reason/);
  assert.match(migration, /left join public\.patient_appointments appointment/);
  assert.match(edge, /minItems: 1, maxItems: 3/);
  assert.match(migration, /jsonb_array_length\(p_response_payload->'options'\) not between 1 and 3/);
  assert.match(migration, /p_prompt_version <> 'consultation-assistant-v8'/);
  assert.match(edge, /ginecologia, psicologia, psiquiatria e trauma/);
  assert.match(edge, /Não sugira exame de imagem, exame pélvico ou teste laboratorial por rotina/);
  assert.match(edge, /não declare risco ausente sem avaliação/);
  assert.match(workspace, /receber até três opções/);
  assert.doesNotMatch(workspace, /as três opções/);
});
