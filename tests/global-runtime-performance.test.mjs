import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

async function sourceFiles(directory) {
  const entries = await readdir(new URL(`../${directory}/`, import.meta.url), { withFileTypes: true });
  const files = await Promise.all(entries.map(async (entry) => {
    const path = `${directory}/${entry.name}`;
    return entry.isDirectory() ? sourceFiles(path) : /\.(?:ts|tsx)$/.test(entry.name) ? [path] : [];
  }));
  return files.flat();
}

test("root layout and shell use one consolidated current-user snapshot each", async () => {
  const [layout, shell] = await Promise.all([
    read("app/layout.tsx"),
    read("app/api/shell/route.ts"),
  ]);
  assert.match(layout, /getSessionBootstrap\(\)/);
  assert.doesNotMatch(layout, /getEffectivePermissionCodes|getPositionDisplayName/);
  assert.match(shell, /"hpsm_shell_snapshot"/);
  assert.doesNotMatch(shell, /getPendingCount|getNotificationCenterData|getHrWeeklyProgress/);
});

test("Meu RH is assembled from one authenticated snapshot", async () => {
  const [page, data] = await Promise.all([
    read("app/meu-rh/page.tsx"),
    read("app/lib/my-hr.ts"),
  ]);
  assert.match(page, /getMyHrData\(context\.accessToken\)/);
  assert.doesNotMatch(page, /getHrSelfData|getCareerSelfData|Promise\.all/);
  assert.match(data, /"hpsm_my_hr_snapshot"/);
});

test("attendance history no longer blocks the operational page", async () => {
  const [page, route, desk, history, data] = await Promise.all([
    read("app/atendimentos/page.tsx"),
    read("app/api/attendances/route.ts"),
    read("app/components/attendance-desk.tsx"),
    read("app/components/attendance-history.tsx"),
    read("app/lib/operational-data.ts"),
  ]);
  assert.doesNotMatch(page, /getAttendanceHistory/);
  assert.doesNotMatch(page, /initialHistory/);
  assert.match(route, /export async function GET\(request: Request\)/);
  assert.match(route, /getAttendanceHistory\(context\.accessToken, page, pageSize, focusId\)/);
  assert.doesNotMatch(desk, /fetch\(`\/api\/attendances\?\$\{params\}`/);
  assert.match(history, /fetch\(`\/api\/attendances\?\$\{params\}`/);
  assert.match(data, /"hpsm_attendance_history_page"/);
  assert.match(data, /p_offset:/);
  assert.match(data, /p_focus_id: focusId/);
  assert.doesNotMatch(data, /staff_positions\(name\)/);
});

test("mutations refresh route data without reloading the full document", async () => {
  const files = await sourceFiles("app");
  const sources = await Promise.all(files.map(async (file) => [file, await read(file)]));
  const offenders = sources.filter(([, source]) => /window\.location\.reload\s*\(/.test(source)).map(([file]) => file);
  assert.deepEqual(offenders, []);
  const refresh = await read("app/lib/client-refresh.ts");
  assert.match(refresh, /router\.refresh\(\)/);
  assert.match(refresh, /hpsm:shell-refresh/);
});

test("heavy clinical editors are split behind dynamic imports", async () => {
  const [profile, patientExams, examCenter] = await Promise.all([
    read("app/components/patient-profile.tsx"),
    read("app/components/patient-exams-tab.tsx"),
    read("app/components/exam-center.tsx"),
  ]);
  assert.match(profile, /dynamic\(\(\) => import\("\.\/patient-exams-tab"\)/);
  assert.match(patientExams, /dynamic\(\(\) => import\("\.\/exam-center"\)/);
  assert.match(examCenter, /dynamic\(\(\) => import\("\.\/imaging-results"\)/);
  assert.match(examCenter, /dynamic\(\(\) => import\("\.\/laboratory-results"\)/);
  assert.match(examCenter, /from "\.\.\/lib\/exam-result-guards"/);
});

test("runtime RPCs validate the Auth session and expose only authenticated entry points", async () => {
  const migration = await read("supabase/migrations/20260831010000_global_runtime_performance.sql");
  assert.match(migration, /from auth\.sessions session/);
  assert.match(migration, /session\.id = v_session_id/);
  assert.match(migration, /profile\.status = 'active'/);
  for (const name of ["hpsm_session_bootstrap", "hpsm_dashboard_summary", "hpsm_attendance_history", "hpsm_my_hr_snapshot", "hpsm_shell_snapshot"]) {
    assert.match(migration, new RegExp(`grant execute on function public\\.${name}`));
  }
  assert.doesNotMatch(migration, /grant execute[\s\S]{0,100}to anon/);
  assert.match(migration, /set search_path = ''/);
});
