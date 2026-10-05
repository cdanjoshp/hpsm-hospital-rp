import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { transform } from "esbuild";

test("selected imaging result cannot become a report that defers its own findings to an unavailable image", async () => {
  const source = (await readFile(new URL("../supabase/functions/exam-ai-generate/index.ts", import.meta.url), "utf8"))
    .replace(/^import "jsr:@supabase\/functions-js\/edge-runtime\.d\.ts";\s*/, "");
  const { code } = await transform(source, { loader: "ts", format: "esm", target: "es2022" });
  const previous = globalThis.Deno;
  globalThis.Deno = { serve() {} };
  try {
    const { validateReportSuggestion } = await import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`);
    const context = { exam: { category_code: "imagem", type_code: "ressonancia_magnetica" }, selected_result: { title: "Lesão expansiva intracraniana" } };
    const report = {
      schema: "hpsm.ai.clinical_report.v3",
      technique: "Ressonância magnética do encéfalo com contraste.",
      findings: ["Lesão expansiva intracraniana focal com realce após contraste.", "Não foram fornecidos localização, dimensões ou dados sobre edema e efeito de massa. As imagens não estão disponíveis para caracterização adicional."],
      conclusion: "Lesão expansiva intracraniana com realce.",
      conduct: "Complementar a caracterização da lesão por imagem.",
    };
    assert.equal(validateReportSuggestion(report, context), null);
    const coherent = { ...report,
      findings: ["Lesão expansiva frontal esquerda de 2,4 cm com realce heterogêneo e edema perilesional discreto.", "Sem desvio da linha média."],
      conduct: "Correlacionar com o quadro clínico e discutir o achado com a equipe assistente." };
    assert.deepEqual(validateReportSuggestion(coherent, context)?.findings, coherent.findings);
    assert.equal(validateReportSuggestion({ ...coherent, findings: ["Lesão conforme o resultado selecionado."] }, context), null);
    assert.equal(validateReportSuggestion({ ...coherent, conclusion: "Lesão de natureza ainda não definida." }, context), null);
    assert.equal(validateReportSuggestion({ ...coherent, technique: "Incidências não informadas." }, context), null);
  } finally { globalThis.Deno = previous; }
});
