import assert from "node:assert/strict";
import { rm } from "node:fs/promises";
import test, { after, before } from "node:test";
import { pathToFileURL } from "node:url";
import { build } from "esbuild";

const bundlePath = `/tmp/hpsm-exam-share-route-${process.pid}.mjs`;
const shareId = "ed20e750-1234-4123-8123-bf9300000001";
const documentId = "6d81bf08-2345-4234-8234-c33a00000002";
const png = Uint8Array.from(Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "base64"));
let route;
let originalFetch;
let revoked = false;
let renderVersion = "exam-document-png-v6";
let calls = [];

before(async () => {
  await build({
    bundle: true,
    entryPoints: [new URL("../app/api/exam-share/[file]/route.ts", import.meta.url).pathname],
    format: "esm",
    outfile: bundlePath,
    platform: "node",
    target: "node22",
  });
  process.env.SUPABASE_URL = "https://hpsm-test.supabase.co";
  process.env.SUPABASE_ANON_KEY = "anon-test";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "service-role-test";
  originalFetch = globalThis.fetch;
  globalThis.fetch = async (input, init = {}) => {
    const url = String(input);
    calls.push({ method: init.method ?? "GET", url });
    if (url.includes("/rest/v1/rpc/resolve_clinical_exam_document_share")) {
      return Response.json(revoked ? null : {
        document_id: documentId,
        exam_id: 123,
        file_size: png.byteLength,
        mime_type: "image/png",
        pixel_height: 1800,
        pixel_width: 1200,
        render_version: renderVersion,
        storage_path: `clinical-exams/123/documents/${documentId}.png`,
      });
    }
    if (url.includes("/storage/v1/object/clinical-exam-documents/")) {
      return new Response(png.slice(), { headers: { "content-length": String(png.byteLength), "content-type": "image/png" } });
    }
    throw new Error(`Requisição inesperada: ${url}`);
  };
  route = await import(`${pathToFileURL(bundlePath).href}?${Date.now()}`);
});

after(async () => {
  globalThis.fetch = originalFetch;
  delete process.env.SUPABASE_URL;
  delete process.env.SUPABASE_ANON_KEY;
  delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  await rm(bundlePath, { force: true });
});

test("anonymous GET returns direct PNG bytes without redirect or HTML", async () => {
  revoked = false;
  renderVersion = "exam-document-png-v6";
  calls = [];
  const response = await route.GET(
    new Request(`https://hpsm.example/api/exam-share/${shareId}.png`),
    { params: Promise.resolve({ file: `${shareId}.png` }) },
  );
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "image/png");
  assert.equal(response.headers.get("content-disposition"), 'inline; filename="HPSM_documento_clinico.png"');
  assert.equal(response.headers.get("cache-control"), "no-store, max-age=0");
  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow, noarchive");
  assert.deepEqual(new Uint8Array(await response.arrayBuffer()), png);
  assert.deepEqual(calls.map((call) => call.method), ["POST", "GET"]);
});

test("anonymous HEAD returns the same image headers with an empty body", async () => {
  revoked = false;
  renderVersion = "exam-document-png-v2";
  calls = [];
  const response = await route.HEAD(
    new Request(`https://hpsm.example/api/exam-share/${shareId}.png`, { method: "HEAD" }),
    { params: Promise.resolve({ file: `${shareId}.png` }) },
  );
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "image/png");
  assert.equal(response.headers.get("content-length"), String(png.byteLength));
  assert.equal((await response.arrayBuffer()).byteLength, 0);
  assert.deepEqual(calls.map((call) => call.method), ["POST", "GET"]);
});

test("revoked and malformed public links return 404 without metadata", async () => {
  revoked = true;
  calls = [];
  const revokedResponse = await route.GET(
    new Request(`https://hpsm.example/api/exam-share/${shareId}.png`),
    { params: Promise.resolve({ file: `${shareId}.png` }) },
  );
  assert.equal(revokedResponse.status, 404);
  assert.equal(calls.length, 1);
  assert.equal((await revokedResponse.text()), "");

  calls = [];
  const malformedResponse = await route.GET(
    new Request("https://hpsm.example/api/exam-share/123.png"),
    { params: Promise.resolve({ file: "123.png" }) },
  );
  assert.equal(malformedResponse.status, 404);
  assert.equal(calls.length, 0);
});
