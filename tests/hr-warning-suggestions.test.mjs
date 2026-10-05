import assert from "node:assert/strict";
import { test } from "node:test";
import { readFile, rm } from "node:fs/promises";
import { build } from "esbuild";

const bundle = `/tmp/hpsm-hr-warning-suggestions-${process.pid}.mjs`;
await build({ entryPoints: [new URL("../app/lib/hr-warning-suggestions.ts", import.meta.url).pathname], outfile: bundle, bundle: true, platform: "node", format: "esm" });
const { eligibleWarningSuggestions } = await import(bundle);
await rm(bundle);

test("dispensa persiste na lista e não altera o histórico de déficit", () => {
  const record = (id, employee_id, extras = {}) => ({ id, employee_id, closure_status: "closed", remaining_deficit_minutes: 120, warning_suggestion_dismissed_at: null, ...extras });
  const records = [
    record(1, "employee"),
    record(2, "employee", { warning_suggestion_dismissed_at: "2026-09-29T17:40:00Z" }),
    record(3, "employee"),
    record(4, "director"),
    record(5, "employee", { closure_status: "ready" }),
    record(6, "employee", { remaining_deficit_minutes: 0 }),
  ];
  const warnings = [{ weekly_record_id: 3 }];
  const eligible = eligibleWarningSuggestions(records, warnings, new Set(["director"]));
  assert.deepEqual(eligible.map((item) => item.id), [1]);
  assert.deepEqual(eligibleWarningSuggestions(records, warnings, new Set(["director"]), new Set([1])), []);
  assert.equal(records[1].remaining_deficit_minutes, 120);
});

test("a exclusão exige permissão e impede aplicação da ADV para o fechamento excluído", async () => {
  const [migration, route, component] = await Promise.all([
    readFile(new URL("../supabase/migrations/20260929174500_dismiss_hr_warning_suggestions.sql", import.meta.url), "utf8"),
    readFile(new URL("../app/api/hr/warnings/dismiss-suggestion/route.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/components/hr-management.tsx", import.meta.url), "utf8"),
  ]);
  assert.match(migration, /private\.has_permission\(p_actor_id, 'hr\.warnings\.issue'\)/);
  assert.match(migration, /warning_suggestion_dismissed_at is not null/);
  assert.match(migration, /create trigger rh_warnings_reject_dismissed_suggestion/);
  assert.match(route, /getSessionContext\(\)/);
  assert.match(route, /hasPermission\(context\.profile, "hr\.warnings\.issue"\)/);
  assert.match(component, /setDismissedSuggestions/);
});
