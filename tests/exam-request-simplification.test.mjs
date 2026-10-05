import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("all exam requests use one case field only after the exam type is selected", async () => {
  const [center, assistant, imaging, migration] = await Promise.all([
    read("app/components/exam-center.tsx"),
    read("app/components/exam-ai-assistant.tsx"),
    read("app/components/imaging-results.tsx"),
    read("supabase/migrations/20260901163458_simplify_exam_request_and_filter_attendances.sql"),
  ]);
  const createPanel = center.slice(center.indexOf("export function ExamCreatePanel"), center.indexOf("export function ExamDetailPanel"));
  const imagingEditor = imaging.slice(imaging.indexOf("export function ImagingResultEditor"), imaging.indexOf("export function ImagingResultView"));
  assert.match(createPanel, /Suspeita e contexto do caso/);
  assert.match(createPanel, /\{examTypeId \? <label className="exam-full-field">Suspeita e contexto do caso/);
  assert.doesNotMatch(createPanel, /O que precisa aparecer no exame\?|Contexto do caso \(opcional\)|Suspeita principal|Contexto curto do caso/);
  assert.doesNotMatch(createPanel, /clinicalContext/);
  assert.doesNotMatch(assistant, /Suspeita principal|Contexto curto do caso/);
  assert.doesNotMatch(imagingEditor, /Observação adicional/);
  assert.match(migration, /'notes', ''/);
  assert.match(migration, /clinical_exam_case_summary/);
});

test("the authenticated actor is the only responsible professional", async () => {
  const [center, api, migration] = await Promise.all([
    read("app/components/exam-center.tsx"),
    read("app/api/exams/route.ts"),
    read("supabase/migrations/20260901163458_simplify_exam_request_and_filter_attendances.sql"),
  ]);
  const createPanel = center.slice(center.indexOf("export function ExamCreatePanel"), center.indexOf("export function ExamDetailPanel"));
  assert.match(createPanel, /Profissional responsável<input[^>]+readOnly/);
  assert.doesNotMatch(createPanel, /Profissional responsável<select/);
  assert.doesNotMatch(createPanel, /responsibleProfessionalId:/);
  assert.match(api, /p_responsible_professional_id: context\.profile\.user_id/);
  assert.match(migration, /v_responsible uuid := auth\.uid\(\)/);
  assert.match(migration, /where profile\.user_id = v_actor/);
});

test("attendance links only accept the two eligible sale items", async () => {
  const migration = await read("supabase/migrations/20260901163458_simplify_exam_request_and_filter_attendances.sql");
  assert.match(migration, /clinical_exam_attendance_options/);
  assert.match(migration, /sale\.patient_id = p_patient_id/);
  assert.match(migration, /sale\.status = 'completed'/);
  assert.match(migration, /EXAMES \/ RAIO-X/);
  assert.match(migration, /RESSON\. TOMO\./);
  assert.match(migration, /O atendimento relacionado deve ser uma venda concluída deste paciente/);
});

test("the AI image prompt consumes the unified case without additional observation", async () => {
  const [edge, migration] = await Promise.all([
    read("supabase/functions/exam-ai-image/index.ts"),
    read("supabase/migrations/20260901163458_simplify_exam_request_and_filter_attendances.sql"),
  ]);
  assert.match(edge, /case_summary/);
  assert.match(edge, /Suspeita e contexto do caso/);
  assert.doesNotMatch(edge, /Observação adicional/);
  assert.match(migration, /'case_summary', private\.clinical_exam_case_summary/);
  const imageContext = migration.slice(migration.indexOf("create or replace function public.clinical_exam_ai_image_context"), migration.indexOf("revoke all on function public.clinical_exam_reference_data"));
  assert.doesNotMatch(imageContext, /'observation'/);
});
