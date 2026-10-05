import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");
const migrationPath = "supabase/migrations/20260922201203_post_go_cast_references_and_multiple_directors.sql";
const groupMigrationPath = "supabase/migrations/20260923022108_group_cast_application_references.sql";

test("cast application references are persistent, unique and seeded exactly", async () => {
  const migration = await read(migrationPath);
  assert.match(migration, /create table public\.clinical_cast_references/);
  assert.match(migration, /unique \(body_model, body_region, laterality\)/);
  for (const row of [
    /'male',\s*'leg',\s*'left',\s*'245',\s*'Adesivo 245'/,
    /'male',\s*'arm',\s*'left',\s*'223',\s*'Camiseta 223'/,
    /'male',\s*'leg',\s*'right',\s*'246 \/ 158',\s*'Adesivo 246 \/ Sapato 158'/,
    /'male',\s*'rib',\s*'not_applicable',\s*'659',\s*'Jaqueta 659'/,
    /'male',\s*'arm',\s*'right',\s*'231 \/ 64',\s*'Camiseta 231 \/ Colete 64'/,
    /'female',\s*'leg',\s*'right',\s*'262 \/ 166',\s*'Adesivo 262 \/ Sapato 166'/,
    /'female',\s*'leg',\s*'left',\s*'262',\s*'Adesivo 262'/,
    /'female',\s*'arm',\s*'right',\s*'303 \/ 269',\s*'Camiseta 303 \/ 269'/,
    /'female',\s*'rib',\s*'not_applicable',\s*'740',\s*'Jaqueta 740'/,
    /'female',\s*'arm',\s*'left',\s*'64',\s*'Colete 64'/,
  ]) assert.match(migration, row);
});

test("reference reads and edits repeat authorization in RLS and RPCs", async () => {
  const [migration, api] = await Promise.all([read(migrationPath), read("app/api/casts/route.ts")]);
  assert.match(migration, /alter table public\.clinical_cast_references force row level security/);
  assert.match(migration, /private\.has_permission\(private\.hpsm_current_actor\(\), 'casts\.view'\)/);
  assert.match(migration, /not private\.has_permission\(v_actor, 'casts\.manage'\)/);
  assert.doesNotMatch(migration, /grant (?:insert|update|delete|all)[^;]*clinical_cast_references to authenticated/i);
  assert.match(api, /action === "save-reference"[\s\S]*?requirePermission\(permissions, "casts\.manage"\)/);
  assert.match(api, /includeInactive\) requirePermission\(permissions, "casts\.manage"\)/);
});

test("new cast records freeze the selected model and displayed reference", async () => {
  const [migration, component, types] = await Promise.all([
    read(migrationPath),
    read("app/components/cast-control.tsx"),
    read("app/lib/cast-types.ts"),
  ]);
  assert.match(migration, /body_model_snapshot/);
  assert.match(migration, /game_reference_snapshot/);
  assert.match(migration, /reference_description_snapshot/);
  assert.match(migration, /from public\.clinical_cast_references reference[\s\S]*?reference\.active/);
  assert.match(component, /Nenhuma referência cadastrada para esta posição\./);
  assert.match(component, /Registros antigos mantêm o snapshot original/);
  assert.match(component, /record\.game_reference_snapshot/);
  assert.match(types, /\{ code: "rib", label: "Costela" \}/);
});

test("parts of the same limb reuse the canonical arm or leg game reference", async () => {
  const [types, component, migration, transaction] = await Promise.all([
    read("app/lib/cast-types.ts"),
    read("app/components/cast-control.tsx"),
    read(groupMigrationPath),
    read("tests/sql/post_go_cast_application_groups_transaction.sql"),
  ]);
  assert.match(types, /\["hand", "wrist", "forearm", "elbow", "arm"\][\s\S]*?return "arm"/);
  assert.match(types, /\["foot", "ankle", "leg", "knee"\][\s\S]*?return "leg"/);
  assert.match(component, /castReferenceRegion\(bodyRegion\)/);
  assert.match(component, /Aplicação compartilhada/);
  assert.match(migration, /private\.clinical_cast_application_region/);
  assert.match(migration, /reference\.body_region = v_application_region/);
  assert.match(migration, /reference_body_region_snapshot[\s\S]*?v_application_region/);
  assert.match(migration, /mesmo grupo de aplicação e lateralidade/);
  assert.match(transaction, /array\['hand', 'wrist', 'forearm', 'elbow', 'arm'\]/);
  assert.match(transaction, /array\['foot', 'ankle', 'leg', 'knee'\]/);
  assert.match(transaction, /rollback/);
});

test("multiple general directors are supported without a production-specific promotion", async () => {
  const migration = await read(migrationPath);
  assert.match(migration, /drop index if exists public\.profiles_single_general_director/);
  assert.doesNotMatch(migration, /profile\.display_name\s*=/);
  assert.match(migration, /create or replace function public\.override_staff_position/);
  assert.match(migration, /role_code = case when v_to\.level = 14 then 'diretor_geral'/);
  assert.doesNotMatch(migration, /update auth\.users|insert into auth\.users|professional_identities/);
  assert.doesNotMatch(migration, /set must_change_password|must_change_password\s*=/);
});

test("sidebar contains only overview, assistance and management in the requested order", async () => {
  const navigation = await read("app/lib/sidebar-navigation.ts");
  assert.match(navigation, /id: "overview"[\s\S]*?id: "my-hr"/);
  assert.match(navigation, /id: "assistance"[\s\S]*?id: "attendances"/);
  assert.match(navigation, /id: "management"[\s\S]*?id: "catalog"/);
  assert.doesNotMatch(navigation, /id: "operation"|id: "personal"|label: "Operação"|label: "Minha área"/);
});
