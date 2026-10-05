import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("phase 5.1 keeps financial attendance and clinical cast records independent", async () => {
  const migration = await read("supabase/migrations/20260907205322_phase51_clinical_cast_control.sql");
  assert.match(migration, /create table public\.clinical_casts/);
  assert.match(migration, /attendance_id bigint references public\.attendances\(id\) on delete restrict/);
  assert.match(migration, /attendance\.patient_id = new\.patient_id/);
  assert.match(migration, /attendance\.status = 'completed'/);
  assert.doesNotMatch(migration, /create trigger[^;]*on public\.(?:attendances|attendance_items)/is);
});

test("cast permissions, RLS and write-only RPCs follow the clinical authorization pattern", async () => {
  const migration = await read("supabase/migrations/20260907205322_phase51_clinical_cast_control.sql");
  for (const permission of ["casts.view", "casts.create", "casts.remove", "casts.manage"]) {
    assert.match(migration, new RegExp(permission.replace(".", "\\.")));
  }
  assert.match(migration, /\('casts\.view', 1\),\s*\('casts\.create', 1\),\s*\('casts\.remove', 1\),\s*\('casts\.manage', 11\)/);
  assert.match(migration, /alter table public\.clinical_casts force row level security/);
  assert.match(migration, /grant select on public\.clinical_casts to authenticated/);
  assert.doesNotMatch(migration, /grant (?:insert|update|delete|all)[^;]*public\.clinical_casts to authenticated/i);
  assert.match(migration, /for update/);
  assert.match(migration, /private\.audit_cast_action/);
});

test("cast constraints preserve dates, final states and audited cancellation", async () => {
  const migration = await read("supabase/migrations/20260907205322_phase51_clinical_cast_control.sql");
  assert.match(migration, /expected_removal_at > applied_at/);
  assert.match(migration, /removed_at >= applied_at/);
  assert.match(migration, /old\.status in \('removed', 'cancelled'\)/);
  assert.match(migration, /CAST_EXPECTED_REMOVAL_CHANGED/);
  assert.match(migration, /CAST_REMOVED/);
  assert.match(migration, /CAST_CANCELLED/);
  assert.match(migration, /HPSM_ACTIVE_CAST_DUPLICATE/);
});

test("every cast RPC validates the canonical active session and uses the stable GESSO code", async () => {
  const [hardening, policyFix] = await Promise.all([
    read("supabase/migrations/20260907214221_phase51_clinical_cast_session_hardening.sql"),
    read("supabase/migrations/20260908052914_phase51_fix_clinical_cast_read_policy.sql"),
  ]);
  assert.equal((hardening.match(/v_actor := private\.hpsm_current_actor\(\);/g) ?? []).length, 7);
  assert.match(hardening, /catalog\.code = 'gesso'/);
  assert.doesNotMatch(hardening, /v_actor uuid := auth\.uid\(\)/);
  assert.match(policyFix, /private\.has_permission\(\(select auth\.uid\(\)\), 'casts\.view'\)/);
  assert.doesNotMatch(policyFix, /grant execute[^;]*hpsm_current_actor/i);
});

test("control page is lazy, paginated, responsive and derives the professional from the login", async () => {
  const [page, component, api, data, shell, navigation, styles] = await Promise.all([
    read("app/gessos/page.tsx"),
    read("app/components/cast-control.tsx"),
    read("app/api/casts/route.ts"),
    read("app/lib/casts.ts"),
    read("app/components/app-sidebar.tsx"),
    read("app/lib/sidebar-navigation.ts"),
    read("app/brand.css"),
  ]);
  assert.match(page, /permissions\.includes\("casts\.view"\)/);
  assert.match(page, /page: 1, pageSize: 20, status: "in_use"/);
  assert.match(navigation, /href:\s*"\/gessos"/);
  assert.match(shell, /href=\{item\.href!\}[\s\S]*?prefetch=\{shouldPrefetchRoute\(item\.href!\)\}/);
  assert.match(component, /setTimeout\(\(\) => void load\(1, status, search\), 350\)/);
  assert.match(component, /Preenchido automaticamente pelo seu login/);
  assert.match(component, /has_cast_item \? "Gesso · " : ""/);
  assert.match(component, /\/atendimentos\/registro\//);
  assert.match(page, /id: context\.profile\.user_id/);
  assert.doesNotMatch(api, /p_applied_by|body\.appliedBy/);
  assert.match(data, /AbortSignal\.timeout\(20_000\)/);
  assert.match(styles, /html\[data-theme="dark"\][\s\S]*\.cast-summary-card/);
  assert.match(styles, /@media \(max-width: 700px\)[\s\S]*\.cast-form/);
});

test("attendance history accepts a focused link from a cast detail", async () => {
  const [history, detailPage, migration] = await Promise.all([
    read("app/components/attendance-history.tsx"),
    read("app/atendimentos/registro/[id]/page.tsx"),
    read("supabase/migrations/20260909061000_attendance_history_focus_page.sql"),
  ]);
  assert.match(detailPage, /focusId=\{recordId\}/);
  assert.match(history, /loadHistory\(1, focusId \?\? focusedAttendanceId\(\)\)/);
  assert.match(history, /params\.set\("focusId", String\(focusId\)\)/);
  assert.match(history, /id=\{`atendimento-\$\{record\.id\}`\}/);
  assert.match(migration, /p_focus_id bigint default null/);
  assert.match(migration, /v_offset := \(v_rows_before \/ v_limit\) \* v_limit/);
});
