import assert from "node:assert/strict";
import { readFile, rm } from "node:fs/promises";
import test, { after, before } from "node:test";
import { pathToFileURL } from "node:url";
import { build } from "esbuild";

const bundle = `/tmp/hpsm-consultation-prefill-${process.pid}.mjs`;
let prefill;

before(async () => {
  await build({
    bundle: true,
    entryPoints: [new URL("../app/lib/consultation-form-prefill.ts", import.meta.url).pathname],
    format: "esm",
    outfile: bundle,
    platform: "node",
    target: "node22",
  });
  prefill = await import(`${pathToFileURL(bundle).href}?${Date.now()}`);
});

after(async () => { await rm(bundle, { force: true }); });

test("Raio-X sugerido para tíbia esquerda abre com Perna e Esquerda selecionadas", () => {
  const result = prefill.consultationImagingPrefill(imagingType("raio_x", ["Tórax", "Braço", "Perna", "Outra região"], false), {
    suggestion: "Realizar Raio-X para avaliar fratura da tíbia esquerda.",
  });
  assert.equal(result.region, "Perna");
  assert.equal(result.laterality, "left");
  assert.equal(result.contrast, "not_applicable");
});

test("Tomografia converte anatomia detalhada para o grupo aceito pelo template", () => {
  const result = prefill.consultationImagingPrefill(imagingType("tomografia", ["Crânio", "Membro superior", "Membro inferior", "Outra região"], true), {
    suggestion: "Tomografia do rádio direito sem contraste.",
  });
  assert.equal(result.region, "Membro superior");
  assert.equal(result.laterality, "right");
  assert.equal(result.contrast, "without");
});

test("Gesso recebe região, lateralidade e observação derivadas do diagnóstico", () => {
  const result = prefill.consultationCastPrefill({
    diagnosis: "Fratura transversal da diáfise da tíbia esquerda.",
    plan: "Manter a perna imobilizada e sem apoio.",
  });
  assert.equal(result.bodyRegion, "leg");
  assert.equal(result.laterality, "left");
  assert.match(result.applicationNotes, /Diagnóstico: Fratura transversal/);
  assert.match(result.applicationNotes, /Conduta e plano: Manter a perna imobilizada/);
});

test("campos sem evidência clínica permanecem para revisão humana", () => {
  const imaging = prefill.consultationImagingPrefill(imagingType("ressonancia_magnetica", ["Crânio", "Joelho", "Outra região"], true), { suggestion: "Avaliação complementar." });
  const cast = prefill.consultationCastPrefill({ diagnosis: "Trauma sem localização informada." });
  assert.equal(imaging.region, "");
  assert.equal(imaging.laterality, "");
  assert.equal(imaging.contrast, "");
  assert.equal(cast.bodyRegion, "");
  assert.equal(cast.laterality, "");
});

test("internação e retorno reutilizam diagnóstico, plano e orientação", () => {
  const context = { diagnosis: "Pneumonia", plan: "Internar para observação.", orientation: "Monitorar saturação." };
  const hospitalization = prefill.consultationHospitalizationPrefill(context);
  const followUp = prefill.consultationFollowUpPrefill(context);
  assert.match(hospitalization.reason, /Diagnóstico: Pneumonia/);
  assert.equal(hospitalization.notes, "Monitorar saturação.");
  assert.equal(followUp.reason, "Retorno: Pneumonia");
  assert.match(followUp.notes, /Internar para observação/);
});

test("One Page encaminha os prefills aos formulários canônicos", async () => {
  const [workspace, exam, cast, hospitalization] = await Promise.all([
    readFile(new URL("../app/components/consultation-workspace.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/components/exam-center.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/components/cast-control.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/components/hospitalization-center.tsx", import.meta.url), "utf8"),
  ]);
  assert.match(workspace, /initialImagingRequest=\{consultationImagingPrefill/);
  assert.match(workspace, /consultationPrefill=\{\{ \.\.\.castPrefill/);
  assert.match(workspace, /consultationPrefill=\{\{ \.\.\.hospitalizationPrefill/);
  assert.match(workspace, /defaultNotes=\{followUpPrefill\.notes\}/);
  assert.match(exam, /initialImagingRequest \?\? imagingResultDraft/);
  assert.match(cast, /consultationPrefill\?\.bodyRegion/);
  assert.match(hospitalization, /consultationPrefill\?\.notes/);
});

function imagingType(code, regions, supportsContrast) {
  return {
    active: true,
    category_id: 1,
    code,
    description: null,
    id: 1,
    name: code,
    result_config: {
      allows_multiple_images: true,
      kind: "imaging",
      region: { options: regions, required: true },
      requires_image: true,
      schema: "hpsm.image_template.v1",
      supports_contrast: supportsContrast,
      supports_laterality: true,
      version: 1,
    },
    sort_order: 1,
  };
}
