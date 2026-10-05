import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("recruitment access is restricted to official levels 11 through 14", async () => {
  const migration = await readFile(new URL("supabase/migrations/20260831220000_restrict_recruitment_to_levels_11_14.sql", root), "utf8");

  assert.match(migration, /position\.level between 11 and 14/);
  assert.match(migration, /p_permission_code <> 'recruitment\.manage'/);
  assert.match(migration, /permission_grant\.permission_code <> 'recruitment\.manage'/);
  assert.match(migration, /private\.has_permission\(\(select auth\.uid\(\)\), 'recruitment\.manage'\)/);
  assert.match(migration, /Apenas os cargos 11 a 14 podem decidir candidaturas/);
  assert.doesNotMatch(migration, /private\.is_director\(\)/);
});
