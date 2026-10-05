import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("phase 4.4 reuses canonical report fields and applies conditional requirements", async () => {
  const migration = await read("supabase/migrations/20260830170000_phase44_clinical_reports.sql");
  assert.doesNotMatch(migration, /add column (?:technique|findings|conclusion)/i);
  assert.match(migration, /private\.clinical_exam_report_config/);
  assert.match(migration, /v_category_code = 'laboratorial'/);
  assert.match(migration, /v_type_code = 'tipagem_sanguinea'/);
  assert.match(migration, /Preencha os campos obrigatórios do laudo/);
});

test("each submission has an immutable version and completion stores the approved snapshot", async () => {
  const migration = await read("supabase/migrations/20260830170000_phase44_clinical_reports.sql");
  assert.match(migration, /create table public\.clinical_exam_report_versions/);
  assert.match(migration, /unique \(exam_id, version_number\)/);
  assert.match(migration, /private\.build_clinical_exam_report_snapshot/);
  assert.match(migration, /final_report_snapshot = v_final_snapshot/);
  assert.match(migration, /decision = 'approved'/);
  assert.match(migration, /decision = 'returned'/);
});

test("report history is RLS protected and authenticated users cannot write it directly", async () => {
  const migration = await read("supabase/migrations/20260830170000_phase44_clinical_reports.sql");
  assert.match(migration, /alter table public\.clinical_exam_report_versions force row level security/);
  assert.match(migration, /private\.has_permission\(\(select auth\.uid\(\)\), 'exams\.view'\)/);
  assert.match(migration, /revoke all on public\.clinical_exam_report_versions from public, anon, authenticated, service_role/);
  assert.doesNotMatch(migration, /grant (?:insert|update|delete|all) on public\.clinical_exam_report_versions to authenticated/i);
});

test("review transitions are serialized, conflict-aware and completed reports are immutable", async () => {
  const [migration, api] = await Promise.all([
    read("supabase/migrations/20260830170000_phase44_clinical_reports.sql"),
    read("app/api/exams/route.ts"),
  ]);
  assert.match(migration, /where id = p_exam_id for update/);
  assert.match(migration, /Este exame foi atualizado por outro profissional\. Recarregue os dados para continuar\./);
  assert.match(migration, /old\.status = 'completed'/);
  assert.match(migration, /new\.status = 'completed' and old\.status <> 'awaiting_review'/);
  assert.match(api, /conflict \? 409/);
});

test("the review report remains readable and does not introduce generation or export actions", async () => {
  const [report, center, styles] = await Promise.all([
    read("app/components/exam-report-view.tsx"),
    read("app/components/exam-center.tsx"),
    read("app/brand.css"),
  ]);
  assert.match(report, /export function ExamReportView/);
  assert.match(report, /Laudo do Exame/);
  assert.match(report, /Executado por/);
  assert.match(report, /Laudo revisado e aprovado por/);
  assert.match(center, /Ciclos de revisão do laudo/);
  assert.match(center, /Correção solicitada/);
  assert.match(styles, /@media \(max-width: 700px\)[\s\S]*?\.exam-report-identification/);
  assert.match(styles, /html\[data-theme="dark"\][\s\S]*?\.exam-report/);
  assert.doesNotMatch(report, /Gerar laudo|Melhorar conclusão|Interpretar resultado|OpenAI|PDF/i);
});
