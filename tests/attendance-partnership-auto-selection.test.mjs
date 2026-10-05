import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { ModuleKind, ScriptTarget, transpileModule } from "typescript";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

const source = await read("app/lib/attendance-benefit-selection.ts");
const code = transpileModule(source, {
  compilerOptions: { module: ModuleKind.ESNext, target: ScriptTarget.ES2022 },
}).outputText;
const selection = await import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`);

function patient(healthPlanStatus, partnerships = []) {
  return { health_plan: { status: healthPlanStatus }, partnerships };
}

test("benefício automático preserva a prioridade do Plano de Saúde", () => {
  assert.deepEqual(
    selection.automaticAttendanceBenefit(patient("active", [{ id: 10, status: "active" }])),
    { benefitCode: "plano_saude", partnershipId: null },
  );
});

test("uma única parceria ativa é selecionada automaticamente", () => {
  assert.deepEqual(
    selection.automaticAttendanceBenefit(patient("none", [{ id: 20, status: "active" }])),
    { benefitCode: "parceiros_hp", partnershipId: 20 },
  );
});

test("parceria inativa ou ausência de benefício não aplica desconto", () => {
  assert.deepEqual(
    selection.automaticAttendanceBenefit(patient("none", [{ id: 30, status: "inactive" }])),
    { benefitCode: null, partnershipId: null },
  );
  assert.deepEqual(
    selection.automaticAttendanceBenefit(patient("none")),
    { benefitCode: null, partnershipId: null },
  );
});

test("múltiplas parcerias ativam o tipo sem escolher vínculo arbitrário", () => {
  assert.deepEqual(
    selection.automaticAttendanceBenefit(patient("expired", [
      { id: 40, status: "active" },
      { id: 41, status: "active" },
    ])),
    { benefitCode: "parceiros_hp", partnershipId: null },
  );
});

test("fluxo limpa a parceria anterior, recalcula e persiste a escolha canônica", async () => {
  const [desk, route, partnershipMigration, lookupMigration] = await Promise.all([
    read("app/components/attendance-desk.tsx"),
    read("app/api/attendances/route.ts"),
    read("supabase/migrations/20260915162000_phase105_partnerships.sql"),
    read("supabase/migrations/20260921205110_post_go_priority_rollup.sql"),
  ]);

  assert.match(desk, /automaticAttendanceBenefit\(selectedPatient\)/);
  assert.match(desk, /setSelectedBenefitCode\(automaticBenefit\.benefitCode\)[\s\S]*?setSelectedPartnershipId\(automaticBenefit\.partnershipId\)/);
  assert.doesNotMatch(desk, /patient\?\.partnerships\?\.\[0\]/);
  assert.match(desk, /Selecione uma parceria/);
  assert.match(desk, /setSelectedBenefitCode\(null\)[\s\S]*?setSelectedPartnershipId\(null\)/);
  assert.match(desk, /discountPercent: selectedBenefitCode \? discountFor\(service, selectedBenefitCode\) : 0/);
  assert.match(desk, /partnershipId: selectedBenefitCode === "parceiros_hp" \? selectedPartnershipId : null/);
  assert.match(route, /p_partnership_id: partnershipId/);
  assert.match(lookupMigration, /membership\.status = 'active'/);
  assert.match(lookupMigration, /partnership\.status = 'active'/);
  assert.match(partnershipMigration, /v_plan_code = 'parceiros_hp'[\s\S]*?membership\.status = 'active'[\s\S]*?partnership\.status = 'active'/);
  assert.match(partnershipMigration, /O paciente não possui vínculo ativo com a parceria selecionada/);
});
