import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const files = {
  center: new URL("../app/components/consultation-center.tsx", import.meta.url),
  workspace: new URL("../app/components/consultation-workspace.tsx", import.meta.url),
  cast: new URL("../app/components/cast-control.tsx", import.meta.url),
  exam: new URL("../app/components/exam-center.tsx", import.meta.url),
  hospitalization: new URL("../app/components/hospitalization-center.tsx", import.meta.url),
  certificate: new URL("../app/components/medical-certificate-center.tsx", import.meta.url),
  certificateEdge: new URL("../supabase/functions/medical-certificate-ai/index.ts", import.meta.url),
  consultationEdge: new URL("../supabase/functions/consultation-ai/index.ts", import.meta.url),
  migration: new URL("../supabase/migrations/20260924024856_consultation_first_correction_rollup.sql", import.meta.url),
  hardening: new URL("../supabase/migrations/20260924031456_harden_correction_ai_persistence.sql", import.meta.url),
  secondMigration: new URL("../supabase/migrations/20260924150331_consultation_second_correction_rollup.sql", import.meta.url),
  thirdMigration: new URL("../supabase/migrations/20260924165125_consultation_ai_document_rollup.sql", import.meta.url),
};

test("agenda usa duração interna, ações diretas e diálogos HPSM", async () => {
  const center = await readFile(files.center, "utf8");
  assert.match(center, /durationMinutes: 30/);
  assert.doesNotMatch(center, />Duração</);
  assert.match(center, />Iniciar</);
  assert.doesNotMatch(center, />Confirmar</);
  assert.match(center, />Cancelar</);
  assert.match(center, /HpsmDialog/);
  assert.doesNotMatch(center, /window\.(?:alert|confirm|prompt)/);
});

test("sinais vitais são locais, dor é slider e faixas vêm do banco", async () => {
  const [workspace, migration] = await Promise.all([readFile(files.workspace, "utf8"), readFile(files.migration, "utf8")]);
  assert.match(workspace, /generateVitalForClassification/);
  assert.match(workspace, /VitalClassButtons/);
  assert.match(workspace, /type="range" min=\{0\} max=\{10\}/);
  assert.doesNotMatch(workspace, /Gerar valores clínicos/);
  for (const code of ["blood_pressure", "temperature", "heart_rate", "oxygen_saturation"]) assert.match(migration, new RegExp(`when '${code}'`));
  assert.match(migration, /"generation"/);
});

test("formulários clínicos canônicos abrem inline e não usam caixas nativas", async () => {
  const [workspace, exam, cast, hospitalization] = await Promise.all([files.workspace, files.exam, files.cast, files.hospitalization].map((file) => readFile(file, "utf8")));
  assert.match(workspace, /<ExamCreatePanel[\s\S]*inline/);
  assert.match(workspace, /<CastCreatePanel[\s\S]*inline/);
  assert.match(workspace, /<HospitalizationForm[\s\S]*inline/);
  assert.match(exam, /inline-module-panel/);
  assert.match(cast, /inline-module-panel/);
  assert.match(hospitalization, /inline-module-panel/);
  assert.doesNotMatch([workspace, exam, cast, hospitalization].join("\n"), /window\.(?:alert|confirm|prompt)/);
});

test("atestado por consulta é único, valida CID e corrige o caminho PNG", async () => {
  const [migration, certificate, actions, edge] = await Promise.all([files.migration, files.certificate, new URL("../app/components/medical-certificate-document-actions.tsx", import.meta.url), files.certificateEdge].map((file) => readFile(file, "utf8")));
  assert.match(migration, /create unique index[\s\S]*medical_certificates_one_per_consultation_uidx/i);
  assert.match(migration, /inclusive no histórico de cancelamentos/i);
  assert.match(migration, /medical_cid10_catalog/);
  assert.match(migration, /documents\/\[0-9a-f-\]\{36\}\[\.\]png/);
  assert.match(certificate, /CID-10 validado/);
  assert.match(certificate, /<MedicalCertificateDocumentActions/);
  assert.match(actions, />Visualizar imagem</);
  assert.match(actions, />Baixar imagem</);
  assert.match(edge, /medical-certificate-v2/);
  assert.match(edge, /cid_catalog/);
  assert.match(edge, /Nunca invente, complete ou transforme um código/);
});

test("síntese v5 preserva o fluxo v4 e amplia medicação na mesma chamada", async () => {
  const [edge, hardening] = await Promise.all([readFile(files.consultationEdge, "utf8"), readFile(files.thirdMigration, "utf8")]);
  assert.match(edge, /consultation-assistant-v8/);
  assert.match(edge, /linked_exams/);
  assert.match(edge, /uma a três opções plausíveis/);
  assert.match(edge, /medication_suggestions/);
  assert.match(edge, /case_signature/);
  assert.match(edge, /complete_consultation_ai_generation_v3/);
  assert.match(hardening, /p_prompt_version <> 'consultation-assistant-v4'/);
  assert.match(hardening, /revoke all on function public\.complete_consultation_ai_generation_v2[^\n]*from public, anon, authenticated/i);
  assert.match(hardening, /grant execute on function public\.complete_consultation_ai_generation_v2[\s\S]*to service_role/i);
});

test("persistência da IA de atestado permanece exclusiva ao serviço", async () => {
  const [edge, hardening] = await Promise.all([readFile(files.certificateEdge, "utf8"), readFile(files.hardening, "utf8")]);
  assert.match(edge, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(hardening, /revoke all on function public\.apply_medical_certificate_ai_result[^\n]*from public, anon, authenticated/i);
  assert.match(hardening, /grant execute on function public\.apply_medical_certificate_ai_result[\s\S]*to service_role/i);
});
