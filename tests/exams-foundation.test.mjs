import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("clinical and financial records stay independent", async () => {
  const migration = await read("supabase/migrations/20260830003209_phase4_exam_center_foundation.sql");
  assert.match(migration, /attendance_id bigint references public\.attendances\(id\) on delete restrict/);
  assert.doesNotMatch(migration, /create trigger[^;]*after insert[^;]*on public\.(?:attendances|attendance_items)/is);
  assert.match(migration, /p_attendance_id bigint default null/);
  assert.match(migration, /attendance\.patient_id = new\.patient_id/);
  assert.match(migration, /attendance\.status = 'completed'/);
});

test("exam workflow only exposes the approved status transitions", async () => {
  const migration = await read("supabase/migrations/20260830003209_phase4_exam_center_foundation.sql");
  assert.match(migration, /v_old\.status <> 'requested'/);
  assert.match(migration, /set status = 'in_progress', started_at = now\(\)/);
  assert.match(migration, /v_old\.status <> 'in_progress'/);
  assert.match(migration, /set status = 'awaiting_review'/);
  assert.match(migration, /v_old\.status <> 'awaiting_review'/);
  assert.match(migration, /p_decision = 'approve'[\s\S]*?set status = 'completed'/);
  assert.match(migration, /p_decision = 'return'[\s\S]*?status = 'in_progress'/);
});

test("exam permissions and cumulative position levels are migration-controlled", async () => {
  const migration = await read("supabase/migrations/20260830003209_phase4_exam_center_foundation.sql");
  for (const permission of ["exams.view", "exams.create", "exams.perform", "exams.review", "exams.catalog.manage"]) {
    assert.match(migration, new RegExp(permission.replace(".", "\\.")));
  }
  assert.match(migration, /\('exams\.view', 1\),\s*\('exams\.create', 1\),\s*\('exams\.perform', 1\)/);
  assert.match(migration, /\('exams\.review', 11\)/);
  assert.match(migration, /\('exams\.catalog\.manage', 13\)/);
  assert.match(migration, /join grants grant_row on position\.level >= grant_row\.min_level/);
});

test("new exam tables force RLS and authenticated writes go through guarded RPCs", async () => {
  const migration = await read("supabase/migrations/20260830003209_phase4_exam_center_foundation.sql");
  for (const table of ["exam_categories", "exam_types", "clinical_exams", "clinical_exam_status_history"]) {
    assert.match(migration, new RegExp(`alter table public\\.${table} force row level security`));
    assert.match(migration, new RegExp(`revoke all on public\\.${table} from public, anon, authenticated, service_role`));
  }
  assert.doesNotMatch(migration, /grant (?:insert|update|delete|all) on table public\.(?:exam_categories|exam_types|clinical_exams|clinical_exam_status_history) to authenticated/i);
  assert.match(migration, /set search_path = ''/);
  assert.match(migration, /private\.has_permission\(v_actor, 'exams\.review'\)/);
});

test("exam center is lazy, paginated, filtered and does not fetch full profiles", async () => {
  const [shell, navigation, page, data, component, patientLookup] = await Promise.all([
    read("app/components/app-sidebar.tsx"),
    read("app/lib/sidebar-navigation.ts"),
    read("app/exames/page.tsx"),
    read("app/lib/exams.ts"),
    read("app/components/exam-center.tsx"),
    read("app/components/patient-passport-combobox.tsx"),
  ]);
  assert.match(navigation, /href:\s*"\/exames"/);
  assert.match(shell, /href=\{item\.href!\}[\s\S]*?prefetch=\{shouldPrefetchRoute\(item\.href!\)\}/);
  assert.match(page, /page: 1, pageSize: 20/);
  assert.match(data, /p_limit: pageSize/);
  assert.match(data, /p_offset: \(page - 1\) \* pageSize/);
  assert.doesNotMatch(data, /profiles\?/);
  assert.match(component, /setTimeout\(\(\) => void load\(1, filters\), 350\)/);
  assert.match(component, /PatientPassportCombobox/);
  assert.match(patientLookup, /DEBOUNCE_MS = 150/);
});

test("exam RPCs have a finite deadline and a friendly timeout", async () => {
  const [data, route] = await Promise.all([
    read("app/lib/exams.ts"),
    read("app/api/exams/route.ts"),
  ]);
  assert.match(data, /signal: AbortSignal\.timeout\(25_000\)/);
  assert.match(data, /O serviço de exames demorou para responder\. Tente novamente\./);
  assert.match(route, /timeout \? 504/);
});
