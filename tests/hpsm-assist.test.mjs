import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";
import { transformSync } from "esbuild";

const source = readFileSync(new URL("../supabase/functions/hpsm-assist/index.ts", import.meta.url), "utf8")
  .replace(/^import "jsr:.*";\n/, "");
const compiled = transformSync(source, { loader: "ts", format: "cjs" }).code;
const refs = {
  actor_id: "doctor-1",
  exam_types: [{ id: 10, name: "Raio-X", category: "Imagem" }],
  medications: [
    { id: "ANALGEX", rp_name: "Analgex", reference_name: "Dipirona", dose: "1 comprimido",
      frequency: "8 horas", duration: "3 dias", route: "oral", instructions: "Após alimentação",
      controlled: false, antibiotic: false, allergy_keywords: ["dipirona"] },
  ],
};
function analysis(priority, overrides = {}) {
  return {
    priority, summary: "Avaliar o relato.", possible_conditions: [], checks: [],
    suggested_exams: [], suggested_medications: [], suggested_actions: [],
    warning_signs: [], final_guidance: "Reavaliar no RP.", ...overrides,
  };
}
function setup(result, { pause = false } = {}) {
  let handler;
  let openai = 0;
  let dbWrites = 0;
  let body;
  let finish;
  const fetch = async (url, options) => {
    if (url.endsWith("/rpc/hpsm_assist_reference_data")) {
      if (options.body !== "{}" || options.method !== "POST") dbWrites++;
      return Response.json(refs);
    }
    assert.equal(url, "https://api.openai.com/v1/responses");
    openai++;
    body = JSON.parse(options.body);
    if (pause) await new Promise((resolve) => { finish = resolve; });
    return Response.json({ status: "completed", output: [{ content: [{ type: "output_text", text: JSON.stringify(result) }] }] });
  };
  vm.runInNewContext(compiled, {
    Deno: { env: { get: (key) => ({ SUPABASE_URL: "https://example.supabase.co", SUPABASE_ANON_KEY: "anon", OPENAI_API_KEY: "server-secret" })[key] }, serve: (fn) => { handler = fn; } },
    fetch, Response, Request, AbortSignal, Date, Number, JSON, Set, Map, Error, DOMException, Array, String,
  });
  const request = (caseText, pain = null) => new Request("https://example.test/hpsm-assist", {
    method: "POST", headers: { authorization: "Bearer session", "content-type": "application/json" },
    body: JSON.stringify({ action: "HPSM_ASSIST_ANALYSIS", caseText, pain }),
  });
  return { request, handler, finish: () => finish?.(), stats: () => ({ openai, dbWrites, body }) };
}

test("caso de rotina usa uma chamada Sol com orçamento rápido sem histórico clínico", async () => {
  const app = setup(analysis("LOW"));
  const response = await app.handler(app.request("Paciente em consulta de rotina, sem queixa específica."));
  assert.equal(response.status, 200);
  assert.equal((await response.json()).result.priority, "LOW");
  assert.equal(app.stats().openai, 1);
  assert.equal(app.stats().dbWrites, 0);
  assert.equal(app.stats().body.model, "gpt-6-sol");
  assert.equal(app.stats().body.service_tier, "fast");
  assert.equal(app.stats().body.reasoning.effort, "medium");
  assert.equal(app.stats().body.max_output_tokens, 6_000);
  assert.equal(app.stats().body.store, false);
});

test("trauma mantém prioridade proporcional e elimina IDs inexistentes e alergia", async () => {
  const app = setup(analysis("HIGH", {
    suggested_exams: [{ exam_id: 10, reason: "Investigar fratura.", order: 1 }, { exam_id: 999, reason: "Inexistente.", order: 2 }],
    suggested_medications: [{ medication_id: "ANALGEX", reason: "Dor.", justification: "" }, { medication_id: "FAKE", reason: "Falso.", justification: "" }],
  }));
  const response = await app.handler(app.request("Trauma na perna com dor, alergia à dipirona, dificuldade de apoio.", 8));
  const result = (await response.json()).result;
  assert.equal(result.priority, "HIGH");
  assert.deepEqual(JSON.parse(JSON.stringify(result.suggested_exams.map((item) => item.name))), ["Raio-X"]);
  assert.equal(result.suggested_medications.length, 0);
  assert.equal(app.stats().openai, 1);
});

test("emergência relatada não cria ações e rejeita clique duplicado", async () => {
  const app = setup(analysis("EMERGENCY"), { pause: true });
  const first = app.handler(app.request("Paciente com perda de consciência e dificuldade para respirar."));
  await new Promise((resolve) => setTimeout(resolve, 0));
  const duplicate = await app.handler(app.request("Paciente com perda de consciência e dificuldade para respirar."));
  assert.equal(duplicate.status, 409);
  app.finish();
  assert.equal((await (await first).json()).result.priority, "EMERGENCY");
  assert.equal(app.stats().openai, 1);
  assert.equal(app.stats().dbWrites, 0);
});

test("relato insuficiente é recusado antes de inferência", async () => {
  const app = setup(analysis("LOW"));
  assert.equal((await app.handler(app.request("dor"))).status, 400);
  assert.equal(app.stats().openai, 0);
});
