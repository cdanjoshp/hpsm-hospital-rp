import assert from "node:assert/strict";
import test from "node:test";
import { register } from "node:module";

register("./helpers/worker-wasm-loader.mjs", import.meta.url);

test("renders HPSM production metadata", async () => {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  const response = await worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );

  assert.equal(response.status, 200);
  assert.match(
    response.headers.get("content-type") ?? "",
    /^text\/html\b/i,
  );
  const html = await response.text();
  assert.match(html, /<title>HPSM — Sistema Interno<\/title>/i);
  assert.match(html, /<meta(?=[^>]*property=["']og:image["'])[^>]*>/i);
  assert.match(html, /Hospital Santa Marcelina — Ambiente fictício criado exclusivamente para fins de RP\./i);
  assert.doesNotMatch(html, /name=["']codex-preview["']/i);
});

test("serves both unified login states and redirects the legacy patient entry", async () => {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `unified-entry-${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);
  const env = { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } };
  const context = { waitUntil() {}, passThroughOnException() {} };

  const patientHome = await worker.fetch(new Request("http://localhost/?access=patient"), env, context);
  const patientHtml = await patientHome.text();
  assert.equal(patientHome.status, 200);
  assert.match(patientHtml, /Portal do Paciente/);
  assert.match(patientHtml, /Passaporte/);
  assert.doesNotMatch(patientHtml, /Data de nascimento/);
  assert.doesNotMatch(patientHtml, /action="\/api\/auth\/login"/);

  const professionalHome = await worker.fetch(new Request("http://localhost/?access=professional"), env, context);
  const professionalHtml = await professionalHome.text();
  assert.equal(professionalHome.status, 200);
  assert.match(professionalHtml, /Acesso Profissional/);
  assert.match(professionalHtml, /action="\/api\/auth\/login"/);
  assert.doesNotMatch(professionalHtml, /action="\/api\/patient-portal\/login"/);

  const legacyPortal = await worker.fetch(new Request("http://localhost/portal-paciente"), env, context);
  assert.ok([303, 307, 308].includes(legacyPortal.status));
  assert.equal(new URL(legacyPortal.headers.get("location"), "http://localhost").pathname + new URL(legacyPortal.headers.get("location"), "http://localhost").search, "/?access=patient");
});

test("invalid submissions remain isolated in each access flow", async () => {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `unified-submit-${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);
  const env = { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } };
  const context = { waitUntil() {}, passThroughOnException() {} };

  const professional = await worker.fetch(new Request("http://localhost/api/auth/login", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: "passport=&password=",
  }), env, context);
  assert.equal(professional.status, 303);
  assert.match(professional.headers.get("location") ?? "", /\?access=professional&loginError=invalid(?:_request)?$/);

  const patient = await worker.fetch(new Request("http://localhost/api/patient-portal/login", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ action: "check", passport: "invalid" }),
  }), env, context);
  assert.equal(patient.status, 400);
  assert.match(await patient.text(), /passaporte válido/);
});

test("keeps operational fast paths closed without an HPSM session", async () => {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `fast-path-${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);
  const env = {
    ASSETS: {
      fetch: async () => new Response("Not found", { status: 404 }),
    },
  };
  const context = {
    waitUntil() {},
    passThroughOnException() {},
  };

  const patientResponse = await worker.fetch(new Request("http://localhost/api/patients?passport=1"), env, context);
  const catalogResponse = await worker.fetch(new Request("http://localhost/api/services"), env, context);
  const globalSearchResponse = await worker.fetch(new Request("http://localhost/api/global-search?q=lucas"), env, context);
  const imageResponse = await worker.fetch(new Request("http://localhost/api/services/images", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ serviceIds: [1] }),
  }), env, context);

  assert.equal(patientResponse.status, 401);
  assert.equal(catalogResponse.status, 401);
  assert.equal(globalSearchResponse.status, 401);
  assert.equal(globalSearchResponse.headers.get("cache-control"), "private, no-store, max-age=0");
  assert.ok((globalSearchResponse.headers.get("vary") ?? "").split(/,\s*/).includes("Cookie"));
  assert.equal(imageResponse.status, 401);
});

test("keeps the patient summary closed without a Portal session", async () => {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `patient-summary-${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);
  const response = await worker.fetch(
    new Request("http://localhost/api/patient-portal/summary"),
    { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } },
    { waitUntil() {}, passThroughOnException() {} },
  );

  assert.equal(response.status, 401);
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  assert.deepEqual(await response.json(), { authenticated: false });
});

test("keeps patient read-only APIs closed without a Portal session", async () => {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `patient-phase63-${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);
  const env = { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } };
  const context = { waitUntil() {}, passThroughOnException() {} };

  for (const path of [
    "/api/patient-portal/history",
    "/api/patient-portal/attendances",
    "/api/patient-portal/attendances/1",
    "/api/patient-portal/health-plan",
    "/api/patient-portal/casts",
  ]) {
    const response = await worker.fetch(new Request(`http://localhost${path}`), env, context);
    assert.equal(response.status, 401, path);
    assert.equal(response.headers.get("cache-control"), "private, no-store", path);
    assert.deepEqual(await response.json(), { authenticated: false }, path);
  }
});

test("blocks cross-origin mutations before reaching Auth or application handlers", async () => {
  const { default: worker } = await import("../dist/server/index.js");
  const env = { ASSETS: { fetch: async () => new Response(null, { status: 404 }) } };
  const context = { waitUntil() {}, passThroughOnException() {} };
  for (const path of ["/api/auth/login", "/api/auth/logout", "/api/patients", "/api/patient-portal/login"]) {
    for (const headers of [{ origin: "https://unrelated.example" }, { "sec-fetch-site": "cross-site" }]) {
      const response = await worker.fetch(new Request(`http://localhost${path}`, { method: "POST", headers }), env, context);
      assert.equal(response.status, 403, path);
      assert.match(response.headers.get("cache-control") ?? "", /no-store/);
      assert.deepEqual(await response.json(), { error: "Origem não autorizada." });
    }
  }
});

test("protects dynamic pages from shared caching and renders a useful 404", async () => {
  const { default: worker } = await import("../dist/server/index.js");
  const env = { ASSETS: { fetch: async () => new Response(null, { status: 404 }) } };
  const context = { waitUntil() {}, passThroughOnException() {} };
  const home = await worker.fetch(new Request("http://localhost/"), env, context);
  assert.match(home.headers.get("cache-control") ?? "", /no-store/);
  assert.equal(home.headers.get("x-content-type-options"), "nosniff");
  assert.equal(home.headers.get("x-frame-options"), null);
  assert.match(home.headers.get("content-security-policy") ?? "", /frame-ancestors 'self' https:\/\/chatgpt\.com https:\/\/\*\.chatgpt\.com https:\/\/chat\.openai\.com/);
  assert.equal(home.headers.get("referrer-policy"), "same-origin");
  const missing = await worker.fetch(new Request("http://localhost/phase10-route-that-does-not-exist"), env, context);
  assert.equal(missing.status, 404);
  const html = await missing.text();
  assert.match(html, /Página não encontrada/);
  assert.match(html, /Voltar ao início/);
});
