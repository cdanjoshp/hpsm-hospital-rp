import assert from "node:assert/strict";
import test from "node:test";
import { readFile } from "node:fs/promises";
import { transpileModule, ModuleKind, ScriptTarget } from "typescript";

const source = await readFile(new URL("../app/lib/professional-logout.ts", import.meta.url), "utf8");
const code = transpileModule(source, { compilerOptions: { module: ModuleKind.ESNext, target: ScriptTarget.ES2022 } }).outputText;
const { revokeProfessionalSession } = await import(`data:text/javascript;base64,${Buffer.from(code).toString("base64")}`);
const config = { url: "https://auth.example.test", anonKey: "public-fixture" };

test("logout revokes only the current session before completing", async () => {
  const requests = [];
  await revokeProfessionalSession(config, "fixture-access", "fixture-refresh", async (url, init) => {
    requests.push({ url, init });
    return new Response(null, { status: 204 });
  });
  assert.equal(requests.length, 1);
  assert.equal(requests[0].url, `${config.url}/auth/v1/logout?scope=local`);
  assert.equal(requests[0].init.headers.authorization, "Bearer fixture-access");
  assert.ok(requests[0].init.signal instanceof AbortSignal);
});

test("expired access is refreshed only to revoke its remaining session", async () => {
  const requests = [];
  await revokeProfessionalSession(config, null, "fixture-refresh", async (url, init) => {
    requests.push({ url, init });
    return requests.length === 1 ? Response.json({ access_token: "renewed-fixture" }) : new Response(null, { status: 204 });
  });
  assert.equal(requests.length, 2);
  assert.match(requests[0].url, /grant_type=refresh_token$/);
  assert.equal(requests[1].init.headers.authorization, "Bearer renewed-fixture");
  assert.match(requests[1].url, /logout\?scope=local$/);
});

test("Auth outage does not report a false successful logout", async () => {
  await assert.rejects(revokeProfessionalSession(config, "fixture-access", "fixture-refresh", async () => new Response(null, { status: 503 })), /Logout indisponível/);
});

test("already revoked credentials and an anonymous logout complete safely", async () => {
  await revokeProfessionalSession(config, null, "revoked-fixture", async () => new Response(null, { status: 400 }));
  await revokeProfessionalSession(config, null, null, async () => assert.fail("No Auth request is needed without cookies"));
});
