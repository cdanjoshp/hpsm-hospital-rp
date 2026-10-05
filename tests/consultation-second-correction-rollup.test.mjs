import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("agenda remove a confirmação operacional e mantém compatibilidade histórica", async () => {
  const center = await read("app/components/consultation-center.tsx");
  assert.doesNotMatch(center, />Confirmar</);
  assert.match(center, /item\.status === "scheduled" \|\| item\.status === "confirmed"/);
  assert.match(center, /item\.status === "cancelled" \|\| item\.status === "no_show"/);
  assert.match(center, />Visualizar</);
});

test("sinais vitais ficam compactos e só a dor mantém classificação inferior", async () => {
  const [workspace, styles] = await Promise.all([read("app/components/consultation-workspace.tsx"), read("app/globals.css")]);
  assert.match(workspace, /showClassification suffix="0–10"/);
  assert.match(workspace, /value <= 2 \? "Leve" : value <= 5 \? "Moderada" : value <= 8 \? "Intensa" : "Crítica"/);
  assert.match(workspace, /showClassification \? <b/);
  assert.match(styles, /\.vital-card[^{]*\{[^}]*gap: 5px;[^}]*padding: 9px/);
});

test("anamnese preservada na v5 incorpora somente os sinais vitais registrados", async () => {
  const [edge, migration] = await Promise.all([
    read("supabase/functions/consultation-ai/index.ts"),
    read("supabase/migrations/20260924165125_consultation_ai_document_rollup.sql"),
  ]);
  assert.match(edge, /consultation-assistant-v8/);
  assert.match(edge, /Integre somente os sinais vitais efetivamente registrados/);
  assert.match(edge, /vitals: sanitizeStructured\(context\.vitals\)/);
  assert.match(edge, /Não invente exame físico, sintoma, duração, antecedente, hipótese, resultado ou conduta/);
  assert.match(migration, /p_prompt_version <> 'consultation-assistant-v4'/);
});

test("exames e atestados usam os painéis canônicos dentro da consulta", async () => {
  const [workspace, exams, certificates] = await Promise.all([
    read("app/components/consultation-workspace.tsx"),
    read("app/components/exam-center.tsx"),
    read("app/components/medical-certificate-center.tsx"),
  ]);
  assert.match(workspace, /<ExamDetailPanel[\s\S]*inline/);
  assert.match(workspace, /<CertificateDetailPanel[\s\S]*inline/);
  assert.doesNotMatch(workspace, /href=\{`\/exames\?registro=/);
  assert.doesNotMatch(workspace, /href=\{`\/atestados\?registro=/);
  assert.match(exams, /inline-exam-detail/);
  assert.match(certificates, /inline-certificate-detail/);
  assert.match(certificates, /MedicalCertificateDocumentActions/);
  assert.match(workspace, /requested: "Solicitado"|EXAM_STATUS_LABELS/);
  assert.match(workspace, /draft: "Rascunho"/);
});

test("schema laboratorial é derivado do template e normalizado antes de persistir", async () => {
  const [edge, migration] = await Promise.all([
    read("supabase/functions/exam-ai-generate/index.ts"),
    read("supabase/migrations/20260924150331_consultation_second_correction_rollup.sql"),
  ]);
  assert.match(edge, /LAB_PROMPT_VERSION = "exam-sol-lab-v1"/);
  assert.match(edge, /EXAM_PROMPT_VERSION = "exam-sol-legacy-final-v1"/);
  assert.match(edge, /properties: Object\.fromEntries\(parameters\.map/);
  assert.match(edge, /required: parameters\.map\(\(parameter\) => parameter\.key\)/);
  assert.match(edge, /normalizeParameterSuggestions/);
  assert.match(edge, /use a edição manual ou tente novamente/);
  assert.match(migration, /exam-clinical-exam-v7/);
  assert.match(migration, /exam-clinical-lab-v4/);
});

test("conduta complementar é contextual e decisão humana", async () => {
  const workspace = await read("app/components/consultation-workspace.tsx");
  assert.doesNotMatch(workspace, /className="clinical-action-select"/);
  assert.match(workspace, /complementaryAction !== "NONE" \|\| consultation\.casts\.length \|\| consultation\.hospitalizations\.length/);
  assert.match(workspace, /Não aplicar/);
  assert.match(workspace, /Sugestão complementar dispensada pelo profissional/);
});

test("atestado e laudo compartilham o template institucional oficial versionado", async () => {
  const [shared, exam, certificate, service, migration] = await Promise.all([
    read("app/lib/institutional-document-png.ts"),
    read("app/lib/final-exam-png.ts"),
    read("app/lib/medical-certificate-png.ts"),
    read("app/lib/medical-certificate-document-service.ts"),
    read("supabase/migrations/20260924150331_consultation_second_correction_rollup.sql"),
  ]);
  assert.match(shared, /renderOfficialInstitutionalDocument/);
  assert.match(shared, /officialPageShell/);
  assert.match(exam, /renderOfficialInstitutionalDocument/);
  assert.match(certificate, /medical-certificate-png-v7/);
  assert.match(certificate, /Diagnóstico e classificação/);
  assert.match(certificate, /documentTitle: "Atestado Médico"/);
  assert.match(service, /render_version === MEDICAL_CERTIFICATE_PNG_RENDER_VERSION/);
  assert.match(migration, /final_png_render_version is distinct from p_render_version/);
});
