import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("phase 5.2 derives patient summary and pending casts from the canonical clinical table", async () => {
  const migration = await read("supabase/migrations/20260908063705_phase52_cast_patient_pending_integration.sql");
  assert.match(migration, /from public\.clinical_casts cast_record/);
  assert.match(migration, /cast_record\.status = 'in_use'/);
  assert.match(migration, /cast_record\.expected_removal_at <= now\(\)/);
  assert.match(migration, /order by cast_record\.expected_removal_at, cast_record\.id/);
  assert.doesNotMatch(migration, /create table[^;]*(?:pending|cast_history)/i);
  assert.doesNotMatch(migration, /insert into public\.notifications/i);
  assert.doesNotMatch(migration, /cron\.|pg_cron|schedule/i);
});

test("new cast reads enforce the canonical session and existing permissions", async () => {
  const migration = await read("supabase/migrations/20260908063705_phase52_cast_patient_pending_integration.sql");
  assert.equal((migration.match(/v_actor uuid := private\.hpsm_current_actor\(\);/g) ?? []).length, 4);
  assert.match(migration, /has_permission\(v_actor, 'patients\.view'\)[\s\S]*has_permission\(v_actor, 'casts\.view'\)/);
  assert.match(migration, /has_permission\(v_actor, 'casts\.view'\)[\s\S]*has_permission\(v_actor, 'casts\.manage'\)/);
  assert.match(migration, /grant execute on function public\.patient_active_clinical_casts\(bigint\) to authenticated/);
  assert.match(migration, /grant execute on function public\.clinical_cast_overdue_page\(integer\) to authenticated/);
  assert.doesNotMatch(migration, /grant execute[^;]+\bto\s+(?:anon|public|service_role)\b/i);
});

test("patient profile reuses the phase 5.1 detail and supports multiple active casts", async () => {
  const [profile, patientData, casts, styles] = await Promise.all([
    read("app/components/patient-profile.tsx"),
    read("app/lib/patient-center.ts"),
    read("app/lib/casts.ts"),
    read("app/brand.css"),
  ]);
  assert.match(casts, /patient_active_clinical_casts/);
  assert.match(patientData, /active_casts: activeCasts/);
  assert.match(profile, /import\("\.\/cast-control"\).*CastDetailPanel/);
  assert.match(profile, /summary\.active_casts\.map/);
  assert.match(profile, /data-due=\{due\.code\}/);
  assert.match(profile, /Registrar retirada/);
  assert.match(profile, /code: "casts", label: "Gessos"/);
  assert.match(styles, /\.patient-active-cast\[data-due="today"\]/);
  assert.match(styles, /\.patient-active-cast\[data-due="overdue"\]/);
  assert.match(styles, /@media \(max-width: 620px\)[\s\S]*\.patient-active-cast/);
});

test("timeline and central pending link to the same cast record without duplication", async () => {
  const [migration, profile, records, pending, center, control, castPage, shellPermissions] = await Promise.all([
    read("supabase/migrations/20260908063705_phase52_cast_patient_pending_integration.sql"),
    read("app/components/patient-profile.tsx"),
    read("app/components/patient-records-tab.tsx"),
    read("app/lib/pending.ts"),
    read("app/components/pending-center.tsx"),
    read("app/components/cast-control.tsx"),
    read("app/gessos/page.tsx"),
    read("app/lib/permission-codes.ts"),
  ]);
  for (const event of ["cast-applied", "cast-forecast-changed", "cast-removed", "cast-cancelled"]) {
    assert.match(migration, new RegExp(`'${event}'`));
  }
  assert.match(profile, /label: "Gessos"/);
  assert.match(profile, /initialFilter="cast"/);
  assert.match(records, /\/gessos\?registro=\$\{item\.resource_id\}/);
  assert.match(pending, /getOverdueClinicalCasts/);
  assert.match(pending, /\/gessos\?registro=\$\{cast\.id\}/);
  assert.match(center, /Gessos com retirada vencida/);
  assert.match(castPage, /params\.registro/);
  assert.match(castPage, /params\.acao === "retirar"/);
  assert.match(control, /initialCastId/);
  assert.match(shellPermissions, /"casts\.manage"/);
  assert.match(migration, /'pending_count', v_pending_count/);
});
