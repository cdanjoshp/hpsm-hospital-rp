import assert from "node:assert/strict";
import { readFile, rm } from "node:fs/promises";
import test, { after, before } from "node:test";
import { pathToFileURL } from "node:url";
import { build } from "esbuild";

const bundle = `/tmp/hpsm-consultation-complementary-${process.pid}.mjs`;
let resolveConsultationComplementaryAction;

before(async () => {
  await build({
    bundle: true,
    entryPoints: [new URL("../app/lib/consultation-complementary-action.ts", import.meta.url).pathname],
    format: "esm",
    outfile: bundle,
    platform: "node",
    target: "node22",
  });
  ({ resolveConsultationComplementaryAction } = await import(`${pathToFileURL(bundle).href}?${Date.now()}`));
});

after(async () => { await rm(bundle, { force: true }); });

test("fratura ou imobilização ativa o fluxo de gesso quando a IA retorna NONE", () => {
  const diagnosis = {
    severity: "normal",
    diagnosis: "Fratura transversal não desviada da diáfise da tíbia esquerda.",
    final_plan: "Manter a perna imobilizada e sem apoio.",
    complementary_action: "NONE",
  };
  assert.equal(resolveConsultationComplementaryAction(diagnosis, "NONE", diagnosis.final_plan), "CAST");
});

test("indicação hospitalar ativa internação e tem precedência sobre gesso", () => {
  const diagnosis = { severity: "grave", diagnosis: "Fratura exposta", final_plan: "Internar em leito hospitalar para cirurgia." };
  assert.equal(resolveConsultationComplementaryAction(diagnosis, "NONE", diagnosis.final_plan), "HOSPITALIZATION");
});

test("negação clínica e dispensa humana impedem reabertura indevida", () => {
  assert.equal(resolveConsultationComplementaryAction({ severity: "normal", diagnosis: "Fratura descartada", final_plan: "Sem indicação de gesso." }, "NONE", ""), "NONE");
  assert.equal(resolveConsultationComplementaryAction({ severity: "grave", diagnosis: "Pneumonia", final_plan: "Sem necessidade de internação." }, "NONE", ""), "NONE");
  assert.equal(resolveConsultationComplementaryAction({ severity: "normal", diagnosis: "Fratura de tíbia", complementary_action_dismissed: true }, "NONE", "Imobilizar membro."), "NONE");
});

test("ação explícita da síntese é preservada", () => {
  assert.equal(resolveConsultationComplementaryAction({ severity: "grave", diagnosis: "Trauma" }, "CAST", ""), "CAST");
  assert.equal(resolveConsultationComplementaryAction({ severity: "grave", diagnosis: "Trauma" }, "HOSPITALIZATION", ""), "HOSPITALIZATION");
});

test("workspace abre o formulário one page e servidor normaliza a seleção", async () => {
  const [workspace, route] = await Promise.all([
    readFile(new URL("../app/components/consultation-workspace.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/api/consultations/route.ts", import.meta.url), "utf8"),
  ]);
  assert.match(workspace, /initialComplementaryAction === "CAST"[\s\S]*setCastFormOpen\(true\)/);
  assert.match(workspace, /nextAction === "HOSPITALIZATION"[\s\S]*await openHospitalizationForm\(\)/);
  assert.match(workspace, /complementary_action_dismissed: true/);
  assert.match(route, /resolveConsultationComplementaryAction/);
  assert.match(route, /p_complementary_action: resolvedComplementaryAction/);
});
