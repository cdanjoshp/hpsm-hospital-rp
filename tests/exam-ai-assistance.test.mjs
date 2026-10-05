import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("phase 4.6 persists auditable suggestions with RLS, idempotency and rate limiting", async () => {
  const migration = await read("supabase/migrations/20260831150204_phase46_exam_ai_assistance.sql");
  assert.match(migration, /create table public\.exam_ai_generations/);
  assert.match(migration, /model = 'gpt-5\.6-luna'/);
  assert.match(migration, /reasoning_effort = 'low'/);
  assert.match(migration, /prompt_version = 'exam-rp-luna-v1'/);
  assert.match(migration, /unique \(idempotency_key\)/);
  assert.match(migration, /where status = 'requested'/);
  assert.match(migration, /interval '10 minutes'/);
  assert.match(migration, /v_recent_count >= 6/);
  assert.match(migration, /force row level security/);
  assert.match(migration, /clinical_exam\.ai_(?:requested|completed|failed|applied|discarded)/);
  assert.doesNotMatch(migration, /grant (?:insert|update|delete|all) on public\.exam_ai_generations to authenticated/i);
});

test("AI application remains human, atomic and rejects stale exam drafts", async () => {
  const migration = await read("supabase/migrations/20260831150204_phase46_exam_ai_assistance.sql");
  const applyFunction = migration.slice(
    migration.indexOf("create or replace function public.apply_clinical_exam_ai_generation"),
    migration.indexOf("create or replace function public.discard_clinical_exam_ai_generation"),
  );
  assert.match(applyFunction, /private\.hpsm_current_actor\(\)/);
  assert.match(applyFunction, /for update/);
  assert.match(applyFunction, /pg_advisory_xact_lock/);
  assert.match(applyFunction, /source_exam_updated_at/);
  assert.match(applyFunction, /private\.validate_exam_ai_suggestion/);
  assert.match(applyFunction, /status = 'applied'/);
  assert.doesNotMatch(applyFunction, /status = '(?:awaiting_review|completed)'/);
  assert.doesNotMatch(applyFunction, /reviewed_by|completed_at\s*=/);
});

test("the Edge Function uses Sol for new and legacy exam reports with strict non-retained output", async () => {
  const edge = await read("supabase/functions/exam-ai-generate/index.ts");
  assert.match(edge, /const model = SOL_MODEL/);
  assert.match(edge, /const REASONING_EFFORT = "medium"/);
  assert.match(edge, /https:\/\/api\.openai\.com\/v1\/responses/);
  assert.match(edge, /const SOL_MODEL = "gpt-6-sol"/);
  assert.match(edge, /reasoning: \{ effort: REASONING_EFFORT \}/);
  assert.match(edge, /OPENAI_EXAM_SOL_MODEL/);
  assert.doesNotMatch(edge, /OPENAI_TEXT_MODEL|const MODEL = "gpt-5\.6-luna"/);
  assert.match(edge, /store: false/);
  assert.match(edge, /type: "json_schema"/);
  assert.match(edge, /strict: true/);
  assert.match(edge, /additionalProperties: false/);
  assert.match(edge, /Deno\.env\.get\("OPENAI_API_KEY"\)/);
  assert.match(edge, /configuredModel !== model/);
  assert.match(edge, /Assistente de IA temporariamente indisponível/);
  assert.doesNotMatch(edge, /gpt-5\.6-(?:terra|sol)|chat\/completions|fallback|tools:/i);
});

test("the model receives only sanitized clinical context and one private image when available", async () => {
  const [migration, currentContextMigration, edge] = await Promise.all([
    read("supabase/migrations/20260901010000_simplify_exam_ai_workflow.sql"),
    read("supabase/migrations/20260901163458_simplify_exam_request_and_filter_attendances.sql"),
    read("supabase/functions/exam-ai-generate/index.ts"),
  ]);
  const safeContext = migration.slice(
    migration.indexOf("create or replace function public.clinical_exam_ai_context"),
    migration.indexOf("create or replace function public.clinical_exam_ai_visual_input"),
  );
  const safeInput = edge.slice(edge.indexOf("const safeInput"), edge.indexOf("const visualDataUrl"));
  for (const identifier of ["patient.name", "passport", "phone", "emergency_contact", "discord", "email", "patient_id"]) {
    assert.doesNotMatch(safeContext, new RegExp(identifier.replace(".", "\\."), "i"));
    assert.doesNotMatch(safeInput, new RegExp(identifier.replace(".", "\\."), "i"));
  }
  assert.match(safeInput, /Paciente sem identificadores pessoais/);
  assert.doesNotMatch(safeInput, /Paciente fictício do RP/);
  assert.match(safeContext, /short_context/);
  assert.match(safeContext, /main_suspicion/);
  assert.match(currentContextMigration, /'case_context', jsonb_build_object\('summary', private\.clinical_exam_case_summary/);
  assert.match(safeInput, /case_context: \{ summary: clinicalCaseSummary\(context\.case_context\) \}/);
  assert.match(edge, /clinical_exam_ai_visual_input/);
  assert.match(edge, /type: "input_image"/);
  assert.match(edge, /image_url: visualDataUrl/);
  assert.match(edge, /downloadVisualInput/);
  assert.match(edge, /data:\$\{mimeType\};base64/);
  assert.doesNotMatch(safeInput, /storage_path|signed_url|actor_id|exam_id/i);
  assert.doesNotMatch(edge, /createSignedUrl|signedURL/);
});

test("AI loads only in exam detail and sends the complete exam directly to human review", async () => {
  const [route, center, assistant, report, flow] = await Promise.all([
    read("app/api/exams/route.ts"),
    read("app/components/exam-center.tsx"),
    read("app/components/exam-ai-assistant.tsx"),
    read("app/components/exam-report-view.tsx"),
    read("app/lib/exam-ai-flow.ts"),
  ]);
  const listBranch = route.slice(route.indexOf('if (view === "list")'), route.indexOf('if (view === "detail")'));
  const detailBranch = route.slice(route.indexOf('if (view === "detail")'), route.indexOf('if (view === "reference")'));
  assert.doesNotMatch(listBranch, /AiGenerations|ai_generations/);
  assert.match(detailBranch, /Promise\.all/);
  assert.match(detailBranch, /getClinicalExamAiGenerations/);
  assert.match(center, /dynamic\(\(\) => import\("\.\/exam-ai-assistant"\)/);
  assert.match(center, /exam\.status === "in_progress"/);
  assert.match(center, /await postExamAction\(\{ action: "start", examId: exam\.id \}\);[\s\S]*await generateExamWithAi/);
  assert.match(flow, /requestSuggestion\(examId, "generate_exam"\)/);
  assert.match(flow, /callImage\(examId, "apply_bundle"/);
  assert.match(assistant, /Retomar geração automática/);
  assert.match(assistant, /A aprovação final permanece humana/);
  assert.doesNotMatch(assistant, /Gerar só imagem|Gerar só laudo|Aplicar exame|Usar esta imagem/);
  assert.match(center, /Editar ou preencher manualmente/);
  assert.match(assistant, /disabled=\{dirty/);
  assert.match(center, /await onChanged\(\)/);
  assert.match(report, /Assistido por IA/);
});

test("the simplified rollup relates image and report, preserves v1 history and applies a bundle atomically", async () => {
  const [migration, indexes] = await Promise.all([
    read("supabase/migrations/20260901010000_simplify_exam_ai_workflow.sql"),
    read("supabase/migrations/20260901013000_index_exam_ai_image_sources.sql"),
  ]);
  assert.match(migration, /source_image_generation_id uuid/);
  assert.match(migration, /source_image_id uuid references public\.clinical_exam_images/);
  assert.match(migration, /prompt_version in \('exam-image-rp-v1', 'exam-image-rp-v2'\)/);
  assert.match(migration, /prompt_version in \('exam-rp-luna-v1', 'exam-rp-luna-v2'\)/);
  assert.match(migration, /create or replace function public\.clinical_exam_ai_visual_input/);
  assert.match(migration, /order by completed_at desc nulls last/);
  assert.match(migration, /order by created_at desc, id desc limit 1/);
  assert.match(migration, /create or replace function public\.apply_clinical_exam_ai_bundle/);
  assert.match(migration, /pg_advisory_xact_lock/);
  assert.match(migration, /clinical_exam\.ai_bundle_applied/);
  assert.match(migration, /grant execute on function public\.clinical_exam_ai_visual_input[^;]+to service_role/);
  assert.doesNotMatch(migration, /grant execute on function public\.clinical_exam_ai_visual_input[^;]+to authenticated/);
  assert.match(indexes, /exam_ai_generations_source_image_generation_idx/);
  assert.match(indexes, /exam_ai_generations_source_image_id_idx/);
  assert.match(indexes, /where source_image_generation_id is not null/);
  assert.match(indexes, /where source_image_id is not null/);
});
