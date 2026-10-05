import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("Sol receives institutional clinical context without metagame wording", async () => {
  const edge = await read("supabase/functions/exam-ai-generate/index.ts");
  const prompts = edge.slice(edge.indexOf("const PRIVACY_PROMPT"), edge.indexOf("Deno.serve"));
  const safeInput = edge.slice(edge.indexOf("const safeInput"), edge.indexOf("const visualDataUrl"));

  assert.match(prompts, /documento clínico final destinado ao médico e ao paciente/i);
  assert.match(prompts, /pronto para o médico entregar ao paciente/i);
  assert.doesNotMatch(prompts, /GTA|roleplay|fictíci|para (?:o )?RP|uso no RP|narrativa para RP/i);
  assert.match(safeInput, /Paciente sem identificadores pessoais/);
  assert.doesNotMatch(safeInput, /Paciente fictício do RP/);
});

test("generated clinical content is blocked in the Edge Function and database when it exposes system context", async () => {
  const [edge, migration] = await Promise.all([
    read("supabase/functions/exam-ai-generate/index.ts"),
    read("supabase/migrations/20260901201000_prevent_ai_meta_language.sql"),
  ]);

  assert.match(edge, /META_CLINICAL_BOUNDARY/);
  assert.match(edge, /hasMetaClinicalLanguage\(value\)/);
  assert.match(edge, /hasMetaClinicalLanguage\(\[value\.notes/);
  assert.match(migration, /clinical_text_contains_meta_language/);
  assert.match(migration, /exam_ai_payload_contains_meta_language/);
  assert.match(migration, /clinical_exams_prevent_meta_language/);
  assert.match(migration, /O laudo contém referência indevida ao contexto do sistema/);
});

test("new prompt audit identifiers no longer describe the external environment", async () => {
  const [textEdge, imageEdge, types, migration] = await Promise.all([
    read("supabase/functions/exam-ai-generate/index.ts"),
    read("supabase/functions/exam-ai-image/index.ts"),
    read("app/lib/exams.ts"),
    read("supabase/migrations/20260901201000_prevent_ai_meta_language.sql"),
  ]);

  assert.match(textEdge, /exam-sol-lab-v1/);
  assert.match(textEdge, /exam-sol-legacy-report-v1/);
  assert.match(textEdge, /exam-sol-legacy-final-v1/);
  assert.match(imageEdge, /exam-image-clinical-v3/);
  assert.match(types, /prompt_version: string/);
  assert.match(types, /"gpt-5\.6-luna" \| "gpt-6-sol"/);
  assert.match(migration, /assign_current_exam_ai_prompt_version/);
  assert.match(migration, /Imagem gerada por IA\./);
});

test("the exam assistant and report view never expose metagame wording", async () => {
  const [assistant, center, report, finalDocument] = await Promise.all([
    read("app/components/exam-ai-assistant.tsx"),
    read("app/components/exam-center.tsx"),
    read("app/components/exam-report-view.tsx"),
    read("app/lib/final-exam-document.ts"),
  ]);
  const visibleExamUi = `${assistant}\n${center}\n${report}`;

  assert.match(report, /Documento clínico para revisão e assinatura/);
  assert.match(report, /cleanClinicalText/);
  assert.match(finalDocument, /export function cleanClinicalText/);
  assert.doesNotMatch(visibleExamUi, /\bRP\b|roleplay|fictíci|simulação|personagem/i);
});
