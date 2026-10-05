import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

async function appSources(directory = "app") {
  const entries = await readdir(new URL(`../${directory}/`, import.meta.url), { withFileTypes: true });
  const nested = await Promise.all(entries.map((entry) => {
    const path = `${directory}/${entry.name}`;
    return entry.isDirectory() ? appSources(path) : /\.(?:ts|tsx)$/.test(entry.name) ? read(path) : [];
  }));
  return nested.flat();
}

test("progression administration uses one server-only batch RPC", async () => {
  const [career, migration] = await Promise.all([
    read("app/lib/career.ts"),
    read("supabase/migrations/20260909053000_global_performance_consolidation.sql"),
  ]);
  assert.match(career, /"get_staff_progression_statuses"/);
  assert.doesNotMatch(career, /progressiveProfiles\.map\(async/);
  assert.match(migration, /jsonb_object_agg\(profile\.user_id::text, private\.get_staff_progression_status/);
  assert.match(migration, /revoke all on function public\.get_staff_progression_statuses\(uuid\)[\s\S]*?from public, anon, authenticated/);
  assert.match(migration, /grant execute on function public\.get_staff_progression_statuses\(uuid\)[\s\S]*?to service_role/);
});

test("attendance and audit histories are permission-protected and paginated in the database", async () => {
  const [migration, attendance, audit] = await Promise.all([
    read("supabase/migrations/20260909053000_global_performance_consolidation.sql"),
    read("app/components/attendance-history.tsx"),
    read("app/auditoria/page.tsx"),
  ]);
  assert.match(migration, /create or replace function public\.hpsm_attendance_history_page/);
  assert.match(migration, /private\.hpsm_current_actor\(\)/);
  assert.match(migration, /'attendances\.create' = any\(v_permissions\)/);
  assert.match(migration, /create or replace function public\.hpsm_audit_page/);
  assert.match(migration, /private\.has_permission\(v_actor, 'audit\.view'\)/);
  assert.match(migration, /limit v_limit[\s\S]*?offset v_offset/);
  assert.match(attendance, /pageSize: "20"/);
  assert.match(attendance, /controllerRef\.current\?\.abort\(\)/);
  assert.match(audit, /method="get"/);
  assert.match(audit, /auditHref\(auditPage\.page \+ 1/);
});

test("HR production is aggregated server-side instead of transferring raw attendances", async () => {
  const [data, migration] = await Promise.all([
    read("app/lib/hr-production.ts"),
    read("supabase/migrations/20260909055500_hr_production_aggregate.sql"),
  ]);
  assert.match(data, /"hpsm_hr_production"/);
  assert.doesNotMatch(data, /while \(true\)|\/rest\/v1\/attendances/);
  assert.match(migration, /group by attendance\.performed_by/);
  assert.match(migration, /private\.has_permission\(v_actor, 'hr\.reports\.view'\)/);
  assert.match(migration, /at time zone 'America\/Sao_Paulo'/);
});

test("read payloads use explicit projections and repeated employee work is pre-grouped", async () => {
  const [sources, hr, notifications] = await Promise.all([
    appSources(),
    read("app/lib/hr.ts"),
    read("app/lib/notifications.ts"),
  ]);
  assert.doesNotMatch(sources.join("\n"), /select=\*/);
  assert.match(hr, /groupByEmployee\(snapshots\)/);
  assert.match(hr, /snapshotsByEmployee\.get\(profile\.user_id\)/);
  assert.match(notifications, /readsByNotification/);
  assert.match(notifications, /eligibleByAudience/);
});

test("stale clinical list requests are cancelled and ignored", async () => {
  const files = [
    "app/components/exam-center.tsx",
    "app/components/patient-exams-tab.tsx",
    "app/components/cast-control.tsx",
    "app/components/patient-profile.tsx",
  ];
  const sources = await Promise.all(files.map(read));
  sources.forEach((source, index) => {
    assert.match(source, /AbortController/, `${files[index]} deve cancelar a requisição anterior`);
    assert.match(source, /signal:/, `${files[index]} deve vincular o sinal ao fetch`);
    assert.match(source, /AbortError/, `${files[index]} deve ignorar cancelamentos esperados`);
  });
});
