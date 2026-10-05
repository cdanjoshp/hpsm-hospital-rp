import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const migrationPath = "supabase/migrations/20260908220510_decommission_tcc.sql";

async function sourceFiles(directory) {
  const entries = await readdir(path.join(root, directory), { withFileTypes: true });
  const nested = await Promise.all(entries.map(async (entry) => {
    const relative = path.join(directory, entry.name);
    return entry.isDirectory() ? sourceFiles(relative) : [relative];
  }));
  return nested.flat().filter((file) => /\.(?:css|ts|tsx)$/.test(file));
}

test("active application has no TCC surface while career courses remain", async () => {
  const files = await sourceFiles("app");
  const contents = await Promise.all(files.map(async (file) => [file, await readFile(path.join(root, file), "utf8")]));
  const residue = contents.filter(([file, source]) => file !== "app/lib/regimento-data.ts" && /\btcc\b|tcc_|requires_tcc|tcc_approved/i.test(source));
  const regimento = contents.find(([file]) => file === "app/lib/regimento-data.ts")?.[1] ?? "";

  assert.deepEqual(residue.map(([file]) => file), []);
  assert.equal((regimento.match(/\bTCC\b/g) ?? []).length, 1);
  assert.match(regimento, /O Hospital Santa Marcelina não utiliza Trabalho de Conclusão de Curso — TCC — como requisito de progressão\./);
  assert.ok(!files.some((file) => file.startsWith(path.join("app", "api", "career", "tcc"))));

  const career = await readFile(path.join(root, "app/lib/career.ts"), "utf8");
  assert.match(career, /export type Course/);
  assert.match(career, /staff_course_records/);
  assert.match(career, /courses\.completions\.manage/);
});

test("decommission migration removes the complete database surface", async () => {
  const migration = await readFile(path.join(root, migrationPath), "utf8");

  assert.match(migration, /drop table if exists public\.tcc_votes/);
  assert.match(migration, /drop table if exists public\.tcc_submissions/);
  assert.match(migration, /drop column if exists tcc_approved/);
  assert.match(migration, /drop column if exists requires_tcc/);
  assert.match(migration, /drop function if exists public\.register_tcc_submission/);
  assert.match(migration, /drop function if exists public\.cast_tcc_vote/);
  assert.match(migration, /delete from public\.system_permissions[\s\S]*?'tcc\.submit'[\s\S]*?'tcc\.vote'/);
  assert.match(migration, /delete from storage\.buckets where id = 'tcc-documents'/);
});

test("Resident I progression uses only the normal eligibility predicates", async () => {
  const migration = await readFile(path.join(root, migrationPath), "utf8");
  const progressionFunction = migration.slice(
    migration.indexOf("create or replace function private.get_staff_progression_status"),
    migration.indexOf("create or replace function private.ensure_staff_promotion_review"),
  );

  assert.doesNotMatch(progressionFunction, /tcc/i);
  assert.match(progressionFunction, /v_elapsed >= v_required_days/);
  assert.match(progressionFunction, /v_worked >= v_rule\.min_worked_minutes/);
  assert.match(progressionFunction, /v_attendances >= v_rule\.min_attendances/);
  assert.match(progressionFunction, /v_warnings < 3/);

  const residentScenario = { active: true, attendances: 3, elapsedDays: 15, warnings: 0, workedMinutes: 1800 };
  const eligible = residentScenario.active
    && residentScenario.warnings < 3
    && residentScenario.elapsedDays >= 15
    && residentScenario.workedMinutes >= 1800
    && residentScenario.attendances >= 3;
  assert.equal(eligible, true);
});
