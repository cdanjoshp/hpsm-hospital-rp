import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("phase 4.5 keeps clinical_exams canonical and exposes a permission-checked patient page", async () => {
  const migration = await read("supabase/migrations/20260830223000_phase45_patient_exam_integration.sql");
  assert.match(migration, /create or replace function public\.patient_clinical_exam_page/);
  assert.match(migration, /private\.has_permission\(v_actor, 'patients\.view'\)/);
  assert.match(migration, /private\.has_permission\(v_actor, 'exams\.view'\)/);
  assert.match(migration, /from public\.clinical_exams exam/);
  assert.doesNotMatch(migration, /create table/i);
});

test("patient exam listing is paginated, summarized and does not preload clinical payloads or URLs", async () => {
  const [migration, service] = await Promise.all([
    read("supabase/migrations/20260830223000_phase45_patient_exam_integration.sql"),
    read("app/lib/patient-center.ts"),
  ]);
  assert.match(migration, /limit v_limit offset v_offset/);
  assert.match(migration, /'summary', jsonb_build_object/);
  assert.match(migration, /image\.exam_id in \(select page_row\.id/);
  assert.doesNotMatch(migration, /result_data|final_report_snapshot|signed_url/);
  assert.match(service, /safePageSize = Math\.min\(20/);
});

test("exam events enter the patient timeline without exposing them to users lacking exams.view", async () => {
  const migration = await read("supabase/migrations/20260830223000_phase45_patient_exam_integration.sql");
  assert.match(migration, /'exam-requested'/);
  assert.match(migration, /'exam-completed'/);
  assert.match(migration, /'exam_id', limited\.exam_id/);
  assert.match(migration, /and private\.has_permission\(v_actor, 'exams\.view'\)/);
});

test("the patient tab mounts lazily and reuses the official detail, report and fixed-patient create flow", async () => {
  const [profile, tab, center] = await Promise.all([
    read("app/components/patient-profile.tsx"),
    read("app/components/patient-exams-tab.tsx"),
    read("app/components/exam-center.tsx"),
  ]);
  assert.match(profile, /tab === "exams" && canViewExams \? <PatientExamsTab/);
  assert.match(tab, /Promise\.all\(\[load\(1, EMPTY_FILTERS\), loadReferences\(\)\]\)/);
  assert.match(tab, /<ExamDetailPanel[\s\S]*?readOnly/);
  assert.match(tab, /<ExamCreatePanel[^>]*initialPatient=\{patient\}/);
  assert.match(tab, /<ExamCreatePanel[^>]*currentUserId=\{currentUserId\}/);
  assert.match(center, /export function ExamDetailPanel/);
  assert.match(center, /export function ExamCreatePanel/);
});

test("patient exam access is hidden in the UI and repeated by the API", async () => {
  const [page, profile, api] = await Promise.all([
    read("app/pacientes/[id]/page.tsx"),
    read("app/components/patient-profile.tsx"),
    read("app/api/patient-center/route.ts"),
  ]);
  assert.match(page, /canViewExams=\{permissions\.includes\("exams\.view"\)\}/);
  assert.match(profile, /item\.code !== "exams" \|\| canViewExams/);
  assert.match(profile, /item\.code !== "certificates" \|\| canViewCertificates/);
  assert.match(api, /hasPermission\(context\.profile, "exams\.view"\)/);
});
