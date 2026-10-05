import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("Sol generates results and a complete report in one strict response", async () => {
  const [edge, types] = await Promise.all([
    read("supabase/functions/exam-ai-generate/index.ts"),
    read("app/lib/exams.ts"),
  ]);
  assert.match(edge, /const EXAM_PROMPT_VERSION = "exam-sol-legacy-final-v1"/);
  assert.match(edge, /hpsm\.ai\.exam_bundle\.v4/);
  assert.match(edge, /function completeExamSchema/);
  assert.match(edge, /required: \["schema", "parameters", "report"\]/);
  assert.match(edge, /parameterObjectSchema/);
  assert.match(edge, /normalizeParameterSuggestions/);
  assert.match(edge, /required: \["technique", "findings", "conclusion", "conduct"\]/);
  assert.match(edge, /laboratory_template: context\.lab_template/);
  assert.match(edge, /apply_and_submit_clinical_exam_ai_generation/);
  assert.match(types, /ExamAiExamBundleSuggestion/);
  assert.match(types, /generation_type: "generate_lab_results" \| "generate_report" \| "generate_exam"/);
});

test("complete generation is applied and submitted atomically for textual and imaging exams", async () => {
  const [migration, assistant, imageEdge, flow] = await Promise.all([
    read("supabase/migrations/20260901193000_complete_exam_ai_v4_automatic_review.sql"),
    read("app/components/exam-ai-assistant.tsx"),
    read("supabase/functions/exam-ai-image/index.ts"),
    read("app/lib/exam-ai-flow.ts"),
  ]);
  assert.match(migration, /create or replace function public\.apply_and_submit_clinical_exam_ai_generation/);
  assert.match(migration, /perform private\.submit_clinical_exam_review_as\(v_exam\.id, p_actor\)/);
  assert.match(migration, /create or replace function public\.apply_clinical_exam_ai_bundle/);
  assert.match(migration, /'status', 'awaiting_review'/);
  assert.match(flow, /requestSuggestion\(examId, "generate_exam"\)/);
  assert.match(flow, /callImage\(examId, "apply_bundle"/);
  assert.doesNotMatch(assistant, /Aplicar exame|Aplicar ao rascunho|Usar esta imagem/);
  assert.doesNotMatch(imageEdge, /\["status", "generate", "apply",/);
});

test("manual upload is blocked in UI, API, RPC grants and Storage policy", async () => {
  const [gallery, api, migration] = await Promise.all([
    read("app/components/imaging-results.tsx"),
    read("app/api/exams/images/route.ts"),
    read("supabase/migrations/20260901193000_complete_exam_ai_v4_automatic_review.sql"),
  ]);
  assert.doesNotMatch(gallery, /type="file"|Adicionar imagem|request\.formData/);
  assert.match(gallery, /Imagens geradas por IA/);
  assert.match(api, /status: 405/);
  assert.doesNotMatch(api, /request\.formData|uploadImage/);
  assert.match(migration, /drop policy if exists clinical_exam_images_storage_insert/);
  assert.match(migration, /revoke execute on function public\.clinical_exam_image_upload_context\(bigint\) from authenticated/);
  assert.match(migration, /revoke execute on function public\.register_clinical_exam_image[\s\S]*from authenticated/);
});

test("approval is restricted to the requester or responsible professional and positions 11 through 14", async () => {
  const [migration, page, center, api] = await Promise.all([
    read("supabase/migrations/20260901193000_complete_exam_ai_v4_automatic_review.sql"),
    read("app/exames/page.tsx"),
    read("app/components/exam-center.tsx"),
    read("app/api/exams/route.ts"),
  ]);
  const review = migration.slice(migration.indexOf("create or replace function public.review_clinical_exam"));
  assert.match(review, /private\.current_position_level\(v_actor\) between 11 and 14/);
  assert.match(review, /v_actor not in \(v_old\.requested_by, v_old\.responsible_professional_id\)/);
  assert.match(review, /p_decision = 'return'[\s\S]*not v_is_authority/);
  assert.match(page, /context\.positionLevel >= 11 && context\.positionLevel <= 14/);
  assert.match(center, /exam\.requested_by\.id === currentUserId \|\| exam\.responsible_professional\.id === currentUserId/);
  assert.match(api, /decision === "return"[\s\S]*requirePermission\(permissions, "exams\.review"\)/);
});

test("request form uses ordinary language and keeps manual editing as a fallback", async () => {
  const center = await read("app/components/exam-center.tsx");
  assert.match(center, /Suspeita e contexto do caso/);
  assert.doesNotMatch(center, /O que precisa aparecer no exame\?|Contexto do caso \(opcional\)/);
  assert.match(center, /Editar ou preencher manualmente/);
  assert.match(center, /showManualEditing/);
});

test("toxicology always produces binary results and uses a random fallback for insufficient context", async () => {
  const [edge, migration] = await Promise.all([
    read("supabase/functions/exam-ai-generate/index.ts"),
    read("supabase/migrations/20260918215514_standardize_exam_requests_and_toxicology.sql"),
  ]);
  assert.match(edge, /Regra obrigatória para Toxicologia/);
  assert.match(edge, /Nunca use “Inconclusivo”, “Indeterminado”/);
  assert.match(edge, /toxicology_tiebreak_outcomes/);
  assert.match(edge, /crypto\.getRandomValues\(randomValues\)/);
  assert.match(edge, /TOXICOLOGY_OUTCOMES = \["Positivo", "Negativo"\]/);
  assert.match(edge, /TOXICOLOGY_FLAG_VALUES = \["positive", "negative"\]/);
  assert.match(edge, /suggestions\.every\(isBinaryToxicologyParameter\)/);
  assert.match(edge, /hasInconclusiveLanguage\(reportText\)/);
  assert.match(migration, /'\["Negativo", "Positivo"\]'::jsonb/);
  assert.match(migration, /exam-clinical-exam-v6/);
  assert.match(migration, /A Toxicologia gerada pela IA deve ter somente resultados Positivo ou Negativo/);
  assert.match(migration, /validate_exam_ai_suggestion_clinical_v5/);
});
