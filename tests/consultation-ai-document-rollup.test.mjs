import assert from "node:assert/strict";
import { readFile, rm } from "node:fs/promises";
import test, { after, before } from "node:test";
import { pathToFileURL } from "node:url";
import { build } from "esbuild";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");
const bundlePath = `/tmp/hpsm-consultation-png-${process.pid}.mjs`;
let renderConsultationDocumentPng;

before(async () => {
  await build({
    bundle: true,
    entryPoints: [new URL("../app/lib/consultation-document-png.ts", import.meta.url).pathname],
    format: "esm",
    loader: { ".woff2": "dataurl", ".png": "dataurl" },
    outfile: bundlePath,
    platform: "node",
    target: "node22",
  });
  ({ renderConsultationDocumentPng } = await import(`${pathToFileURL(bundlePath).href}?${Date.now()}`));
});

after(async () => { await rm(bundlePath, { force: true }); });

test("consulta consolida o fluxo em no máximo três ações de IA com telemetria", async () => {
  const [edge, migration, workspace] = await Promise.all([
    read("supabase/functions/consultation-ai/index.ts"),
    read("supabase/migrations/20260924165125_consultation_ai_document_rollup.sql"),
    read("app/components/consultation-workspace.tsx"),
  ]);
  assert.match(edge, /consultation-assistant-v8/);
  assert.match(edge, /new Set<Action>\(\["ANAMNESIS_REWRITE", "EXAM_SUGGESTIONS", "CLINICAL_SYNTHESIS"\]\)/);
  assert.doesNotMatch(edge, /type Action[^\n]*(?:DIAGNOSIS_OPTIONS|FINAL_DIAGNOSIS_PLAN|ORIENTATION_MEDICATION)/);
  assert.match(edge, /input_tokens_details\?: \{ cached_tokens\?: number \}/);
  assert.match(edge, /complete_consultation_ai_generation_v3/);
  assert.match(migration, /input_tokens integer/);
  assert.match(migration, /cached_input_tokens integer/);
  assert.match(workspace, /pendingSynthesis/);
  assert.match(workspace, /Aguardar resultados/);
  assert.match(workspace, /Prosseguir mesmo assim/);
  assert.match(workspace, /Existem exames ainda sem resultado/);
});

test("síntese clínica pode atualizar hipóteses até três vezes e aplica a opção sem chamada adicional", async () => {
  const [edge, workspace, migration] = await Promise.all([
    read("supabase/functions/consultation-ai/index.ts"),
    read("app/components/consultation-workspace.tsx"),
    read("supabase/migrations/20260924165125_consultation_ai_document_rollup.sql"),
  ]);
  for (const field of ["severity", "diagnosis", "reasoning_summary", "final_plan", "complementary_action", "orientation", "medication_suggestions"]) assert.match(edge, new RegExp(field));
  assert.match(workspace, /synthesisUses >= 3/);
  assert.match(workspace, /Gerar novas hipóteses/);
  assert.match(workspace, /setFinalPlan\(nextPlan\)/);
  assert.match(workspace, /setComplementaryAction\(nextAction\)/);
  assert.match(workspace, /setOrientation\(nextOrientation\)/);
  assert.match(workspace, /Substituir edição clínica/);
  assert.match(migration, /jsonb_array_length\(p_response_payload->'options'\) <> 3/);
});

test("atestado da consulta usa template determinístico e bloqueia IA no backend", async () => {
  const [workspace, certificate, edge] = await Promise.all([
    read("app/components/consultation-workspace.tsx"),
    read("app/components/medical-certificate-center.tsx"),
    read("supabase/functions/medical-certificate-ai/index.ts"),
  ]);
  assert.match(workspace, /CertificateDetailPanel aiEnabled=\{false\}/);
  assert.match(workspace, /contextOverride \?\? defaultContext/);
  assert.match(workspace, /certificateContext\(diagnosis, finalPlan, anamnesis\)/);
  assert.match(certificate, /Aplicar texto institucional/);
  assert.match(certificate, /forma determinística, sem consumo de IA/);
  assert.match(edge, /Atestados vinculados a consultas usam texto institucional sem IA/);
});

test("erros de marcação ficam no formulário e preservam os dados", async () => {
  const center = await read("app/components/consultation-center.tsx");
  assert.match(center, /Promise<MutationResult>/);
  assert.match(center, /if \(result\.ok\) setCreating\(false\)/);
  assert.match(center, /if \(!result\.ok\) setError\(result\.error\)/);
  assert.match(center, /role="alert"/);
  assert.doesNotMatch(center, /await mutate\(body\); setCreating\(false\)/);
});

test("prontuário PNG é privado, imutável, compartilhável e removido com a consulta", async () => {
  const [migration, route, share, deletion] = await Promise.all([
    read("supabase/migrations/20260924165125_consultation_ai_document_rollup.sql"),
    read("app/api/consultations/document/route.ts"),
    read("app/api/consultation-share/[file]/route.ts"),
    read("supabase/functions/consultation-delete/index.ts"),
  ]);
  assert.match(migration, /hpsm\.clinical_consultation\.v2/);
  assert.match(migration, /alter table public\.consultation_documents force row level security/);
  assert.match(migration, /consultation-document-png-v1/);
  assert.match(migration, /create_consultation_document_share/);
  assert.match(migration, /revoke_consultation_document_share/);
  assert.match(route, /ensureConsultationDocument/);
  assert.match(route, /downloadStoredConsultationDocument/);
  assert.match(share, /resolve_consultation_document_share/);
  assert.match(share, /noindex, nofollow, noarchive/);
  assert.match(deletion, /consultation_document_storage_paths_for_delete/);
  assert.match(deletion, /consultations\|prescriptions/);
});

test("prontuário completo renderiza uma única imagem institucional", async () => {
  const professionalId = "11111111-1111-4111-8111-111111111111";
  const tinyPng = Uint8Array.from(Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "base64"));
  const result = await renderConsultationDocumentPng({
    schema: "hpsm.clinical_consultation.v2",
    consultation_id: 42,
    patient: { id: 7, name: "Paciente de Teste", passport: "0007", birth_date: "2000-01-01", phone: null, emergency_contact_name: null, emergency_contact_phone: null, allergies: "Nenhuma", plan_code: null, health_plan: null, partnerships: [] },
    professional: { id: professionalId, name: "Profissional de Teste", position: "Médica", crm_code: "05321409", signature_image_path: "professionals/a/b/signature.png" },
    appointment: { id: 8, scheduled_start: "2026-09-24T12:00:00.000Z", scheduled_end: "2026-09-24T12:30:00.000Z", reason: "Avaliação clínica", notes: null },
    started_at: "2026-09-24T12:00:00.000Z", completed_at: "2026-09-24T13:00:00.000Z",
    vitals: { blood_pressure_systolic: 120, blood_pressure_diastolic: 80, blood_pressure_class: "Normal", temperature_c: 36.5, temperature_class: "Normal", heart_rate_bpm: 72, heart_rate_class: "Normal", oxygen_saturation_percent: 98, oxygen_saturation_class: "Normal", pain_score: 1 },
    anamnesis: "Paciente em avaliação, estável e sem queixas adicionais informadas.",
    selected_diagnosis: { severity: "normal", diagnosis: "Quadro clínico estável", reasoning_summary: "Sinais vitais dentro das faixas registradas." },
    final_diagnosis_plan: "Manter observação e seguimento clínico.", complementary_action: "NONE", orientation_text: "Retornar se surgirem sinais de alerta.",
    exam_analysis: { no_exam_needed: true, reason: "Sem indicação clínica atual." }, exams: [], casts: [], hospitalizations: [], certificates: [], follow_ups: [],
  }, { bytes: tinyPng, personId: professionalId });
  assert.deepEqual(Array.from(result.bytes.slice(0, 8)), [137, 80, 78, 71, 13, 10, 26, 10]);
  assert.equal(result.width, 1200);
  assert.ok(result.height > 1800 && result.height <= 14_000);
  assert.ok(result.bytes.byteLength < 12 * 1024 * 1024);
});
