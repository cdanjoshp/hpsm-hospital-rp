import assert from "node:assert/strict";
import { rm } from "node:fs/promises";
import test, { after, before } from "node:test";
import { pathToFileURL } from "node:url";
import { build } from "esbuild";

const bundlePath = `/tmp/hpsm-exam-auto-${process.pid}.mjs`;
let generateExamWithAi;

before(async () => {
  await build({ bundle: true, entryPoints: [new URL("../app/lib/exam-ai-flow.ts", import.meta.url).pathname], format: "esm", outfile: bundlePath, platform: "node", target: "node22" });
  ({ generateExamWithAi } = await import(pathToFileURL(bundlePath).href));
});
after(async () => { await rm(bundlePath, { force: true }); });

test("ao retomar exame de imagem reaproveita o rascunho pronto e encaminha o mesmo pacote à revisão", async () => {
  const originalFetch = globalThis.fetch;
  const actions = [];
  globalThis.fetch = async (url, options) => {
    const body = JSON.parse(options.body);
    actions.push(body.action === "generate" ? body.operation : body.action);
    if (body.action === "status") return Response.json({ draft: { id: "image-123", status: "completed" } });
    if (body.operation === "generate_report") {
      assert.equal(body.imageGenerationId, "image-123");
      return Response.json({ generation: { generation_id: "report-456" }, suggestion: { schema: "hpsm.ai.clinical_report.v3" } });
    }
    if (body.action === "apply_bundle") {
      assert.equal(body.generationId, "image-123");
      assert.equal(body.reportGenerationId, "report-456");
      return Response.json({ ok: true });
    }
    throw new Error(`Ação inesperada: ${String(url)}`);
  };
  try {
    await generateExamWithAi(123, true, () => undefined);
    assert.deepEqual(actions, ["status", "generate_report", "apply_bundle"]);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("exame sem imagem produz resultado e laudo em uma operação", async () => {
  const originalFetch = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url, options) => {
    calls.push({ url, body: JSON.parse(options.body) });
    return Response.json({ generation: { generation_id: "exam-789" }, suggestion: { schema: "hpsm.ai.exam_bundle.v4" } });
  };
  try {
    await generateExamWithAi(789, false, () => undefined);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].body.operation, "generate_exam");
  } finally {
    globalThis.fetch = originalFetch;
  }
});
