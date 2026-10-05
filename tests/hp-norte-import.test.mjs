import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("HP Norte import migrations are tracked and idempotent", async () => {
  const migration = await read("supabase/migrations/20260922160056_post_go_hp_norte_import.sql");
  assert.match(migration, /legacy_import_batches_file_unique unique \(source_system, source_file_sha256\)/);
  assert.match(migration, /legacy_patient_records_unique unique \(source_system, source_record_id\)/);
  assert.match(migration, /legacy_import_conflicts_unique unique \(source_system, source_record_id, conflict_type\)/);
  assert.match(migration, /on conflict \(source_system, source_record_id\) do nothing/);
  assert.match(migration, /completed_with_conflicts/);
  assert.doesNotMatch(migration, /insert into public\.attendances/i);
  assert.doesNotMatch(migration, /insert into public\.clinical_exams/i);
});

test("legacy records stay deny-all and are exposed only by the authorized patient RPC", async () => {
  const migration = await read("supabase/migrations/20260922160056_post_go_hp_norte_import.sql");
  assert.match(migration, /alter table public\.legacy_patient_records force row level security/);
  assert.match(migration, /revoke all on public\.legacy_patient_records from public, anon, authenticated, service_role/);
  assert.match(migration, /private\.has_permission\(v_actor, 'patients\.view'\)/);
  assert.match(migration, /grant execute on function public\.patient_legacy_history_page[\s\S]*to authenticated/);
  assert.match(migration, /Histórico HP Norte carregado sob demanda exclusivamente no Perfil do Paciente profissional/);
});

test("legacy birth-date exception remains scoped to the private importer", async () => {
  const migration = await read("supabase/migrations/20260922160657_allow_hp_norte_legacy_birth_date.sql");
  assert.match(migration, /private\.hp_norte_import_context/);
  assert.match(migration, /backend_pid = pg_backend_pid\(\)/);
  assert.match(migration, /A exceção de nascimento legado não aceita autoria operacional/);
  assert.match(migration, /delete from private\.hp_norte_import_context where backend_pid = pg_backend_pid\(\)/);
});

test("private import context is protected and foreign keys are indexed", async () => {
  const migration = await read("supabase/migrations/20260922195007_harden_hp_norte_import_context.sql");
  assert.match(migration, /enable row level security/);
  assert.match(migration, /force row level security/);
  assert.match(migration, /revoke all on private\.hp_norte_import_context from public, anon, authenticated, service_role/);
  for (const index of [
    "hp_norte_import_context_batch_idx",
    "legacy_import_batches_executed_by_idx",
    "legacy_import_conflicts_resolved_by_idx",
  ]) assert.match(migration, new RegExp(index));
});

test("patient profile loads HP Norte history lazily without adding it to Portal or Global Search", async () => {
  const [profile, component, api, library, portal, globalSearch] = await Promise.all([
    read("app/components/patient-profile.tsx"),
    read("app/components/patient-legacy-history-tab.tsx"),
    read("app/api/patient-center/route.ts"),
    read("app/lib/patient-center.ts"),
    read("app/lib/patient-portal.ts"),
    read("app/lib/global-search.ts"),
  ]);
  assert.match(profile, /dynamic\(\(\) => import\("\.\/patient-legacy-history-tab"\)/);
  assert.match(profile, /Histórico HP Norte/);
  assert.match(component, /view: "legacy"/);
  assert.match(component, /somente leitura/i);
  assert.match(component, /Dados preservados da unidade de origem/i);
  assert.match(api, /getPatientLegacyHistoryPage/);
  assert.match(library, /patient_legacy_history_page/);
  assert.doesNotMatch(portal, /legacy_patient_records|patient_legacy_history_page/);
  assert.doesNotMatch(globalSearch, /legacy_patient_records|patient_legacy_history_page/);
});

test("temporary maintenance Edge Functions remain closed and reproducible", async () => {
  const [passwordReset, identityRepair] = await Promise.all([
    read("supabase/functions/one-time-password-reset/index.ts"),
    read("supabase/functions/professional-identity-repair/index.ts"),
  ]);
  for (const source of [passwordReset, identityRepair]) {
    assert.match(source, /status: 410/);
    assert.match(source, /cache-control": "no-store/);
    assert.doesNotMatch(source, /SUPABASE_SERVICE_ROLE_KEY|auth\.admin|updateUserById/);
  }
});
