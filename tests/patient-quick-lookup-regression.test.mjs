import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("a busca rápida resolve o plano sem restaurar o helper público removido", async () => {
  const migration = await read("supabase/migrations/20260911162000_fix_patient_quick_lookup_plan_state.sql");

  assert.match(migration, /create or replace function public\.hpsm_patient_quick_lookup/);
  assert.match(migration, /private\.hpsm_current_actor\(\)/);
  assert.match(migration, /'patients\.view' = any\(v_permissions\)/);
  assert.match(migration, /public\.patient_health_plan_requests/);
  assert.match(migration, /request\.status = 'approved'/);
  assert.match(migration, /request\.status = 'pending'/);
  assert.doesNotMatch(migration, /public\.get_patient_health_plan_states/);
  assert.match(migration, /revoke all on function public\.hpsm_patient_quick_lookup/);
  assert.match(migration, /grant execute on function public\.hpsm_patient_quick_lookup[^;]+to authenticated/s);
});
