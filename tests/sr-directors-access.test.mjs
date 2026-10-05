import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("Diretores do SR formam categoria externa sem nível, meta ou ADV", async () => {
  const [migration, identityGuard, passwordRoute, shell] = await Promise.all([
    read("supabase/migrations/20260923205742_diretores_sr_external_access.sql"),
    read("supabase/migrations/20260923213500_diretores_sr_professional_identity_guard.sql"),
    read("app/api/auth/change-password/route.ts"),
    read("app/components/persistent-app-shell.tsx"),
  ]);

  assert.match(migration, /'diretores_sr',[\s\S]*?'Diretores do SR',[\s\S]*?null,[\s\S]*?'external'/);
  assert.match(migration, /official,[\s\S]*?false/);
  assert.match(migration, /private\.is_hpsm_workforce/);
  assert.match(migration, /rh_weekly_records_require_workforce/);
  assert.match(migration, /rh_warnings_require_workforce/);
  assert.match(migration, /not private\.is_hpsm_workforce\(p_employee_id\)/);
  assert.match(identityGuard, /professional_identity_generation_context/);
  assert.match(identityGuard, /begin_professional_identity_generation/);
  assert.match(passwordRoute, /context\.positionDisplayName !== "Diretores do SR"/);
  assert.match(shell, /!permissionCodes\.includes\("sr\.directors\.view"\) \? <ProfessionalIdentityInitializer/);
});

test("matriz libera pacientes e leitos sem conceder venda efetiva", async () => {
  const [migration, guard] = await Promise.all([
    read("supabase/migrations/20260923205742_diretores_sr_external_access.sql"),
    read("supabase/migrations/20260923212500_diretores_sr_permission_exception_guard.sql"),
  ]);
  const matrix = migration.match(/permission\.code = any\(array\[([\s\S]*?)\]::text\[\]\)/)?.[1] ?? "";

  assert.match(matrix, /'patients\.view'/);
  assert.match(matrix, /'hospitalizations\.create'/);
  assert.match(matrix, /'hospitalizations\.update'/);
  assert.match(matrix, /'hospitalizations\.discharge'/);
  assert.doesNotMatch(matrix, /'attendances\.create'/);
  assert.doesNotMatch(matrix, /'attendances\.manage'/);
  assert.doesNotMatch(matrix, /'patients\.manage'/);
  assert.match(guard, /position\.advancement_mode <> 'external'/);
  assert.match(guard, /user_permission_grants_external_guard/);
});

test("vendas ficam em simulação e o endpoint de gravação mantém a permissão forte", async () => {
  const [page, desk, route] = await Promise.all([
    read("app/atendimentos/page.tsx"),
    read("app/components/attendance-desk.tsx"),
    read("app/api/attendances/route.ts"),
  ]);

  assert.match(page, /canSimulateAttendances = permissionCodes\.includes\("sr\.directors\.view"\)/);
  assert.match(page, /canRecordAttendance=\{canCreateAttendances\}/);
  assert.match(desk, /Modo simulação/);
  assert.match(desk, /if \(!canRecordAttendance\)/);
  assert.match(route, /hasPermission\(context\.profile, "attendances\.create"\)/);
});

test("áreas administrativas distinguem consulta de decisão", async () => {
  const [permissions, recruitment, team, reports] = await Promise.all([
    read("app/lib/administrative.ts"),
    read("app/components/recruitment-management.tsx"),
    read("app/administrativo/equipe/page.tsx"),
    read("app/api/administrative-reports/route.ts"),
  ]);

  assert.match(permissions, /id: "recruitment"[\s\S]*?observerPermissionCodes: \["sr\.directors\.view"\][\s\S]*?permissionCodes: \["recruitment\.manage"\]/);
  assert.match(recruitment, /!canDecide \? <div className="decision-locked"/);
  assert.match(team, /canManage=\{canManageTeam\}/);
  assert.match(reports, /!permissions\.has\("attendances\.manage"\) && !permissions\.has\("sr\.directors\.view"\)/);
});
