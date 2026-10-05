import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { ModuleKind, ScriptTarget, transpileModule } from "typescript";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

const source = await read("app/lib/attendance-item-limits.ts");
const code = transpileModule(source, {
  compilerOptions: { module: ModuleKind.ESNext, target: ScriptTarget.ES2022 },
}).outputText;
const limits = await import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`);

const matrix = {
  kitmed: [2, 2, 2],
  bandagem: [5, 5, 5],
  atadura: [10, 20, 15],
  analgesico: [10, 10, 15],
  ritmoneury: [5, 5, 5],
  sinkalmy: [5, 5, 5],
  adrenalina: [3, 5, 5],
};
const benefits = [null, "policiais_arcanjos", "parceiros_hp"];

test("matriz canônica cobre os sete produtos e os três grupos de benefício", () => {
  for (const [code, expected] of Object.entries(matrix)) {
    assert.deepEqual(benefits.map((benefit) => limits.getAttendanceItemLimit(code, benefit)), expected);
  }
  assert.equal(limits.getAttendanceItemLimit("procedimento_livre", null), null);
  assert.equal(limits.getAttendanceItemLimit("atadura", "plano_saude"), 15);
});

test("matriz permanece apenas como referência do atalho MAX", () => {
  assert.equal(typeof limits.clampAttendanceCart, "undefined");
});

test("calculadora oferece MAX e ZERAR sem substituir os controles existentes", async () => {
  const [desk, css, brand] = await Promise.all([
    read("app/components/attendance-desk.tsx"),
    read("app/globals.css"),
    read("app/brand.css"),
  ]);
  assert.match(desk, />MAX<\/button>/);
  assert.match(desk, /quantity > 0 \? <button[\s\S]*?>ZERAR<\/button> : null/);
  assert.match(desk, /disabled=\{quantity >= maximum\}/);
  assert.match(desk, /const maximum = service\.code === "plano_saude_convenio" \? 1 : 99/);
  assert.match(desk, /disabled=\{quantity === itemLimit\}/);
  assert.match(desk, /changeQuantity\(service\.id, itemLimit\)/);
  assert.doesNotMatch(desk, /clampAttendanceCart|applyBenefitLimits|attendance-limit-notice/);
  assert.match(css, /@media \(max-width: 520px\)[\s\S]*?\.service-card-quantity-panel/);
  assert.match(brand, /html\[data-theme="dark"\] \.service-card-limit-actions/);
});

test("API e banco permitem ultrapassar a referência do atalho MAX", async () => {
  const [route, originalMigration, shortcutMigration] = await Promise.all([
    read("app/api/attendances/route.ts"),
    read("supabase/migrations/20260916210500_post1_attendance_item_limits.sql"),
    read("supabase/migrations/20260917011032_attendance_limits_as_shortcut.sql"),
  ]);
  assert.doesNotMatch(route, /getAttendanceItemLimit|getServiceCatalogMetadata|acima do limite permitido/);
  assert.match(shortcutMigration, /create or replace function private\.attendance_item_limit/);
  assert.match(shortcutMigration, /select null::integer/);
  assert.ok(originalMigration.indexOf("private.attendance_item_limit(catalog.code, v_plan_code)") < originalMigration.indexOf("insert into public.attendances"));
  assert.doesNotMatch(`${source}\n${originalMigration}\n${shortcutMigration}`, /create table[^;]*(?:stock|estoque|inventory)|remaining_quantity|historical_limit/i);
});
