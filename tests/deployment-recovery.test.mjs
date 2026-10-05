import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("the root layout detects stale deployment chunks and reloads only once per guard window", async () => {
  const [layout, recovery] = await Promise.all([
    read("app/layout.tsx"),
    read("app/lib/deployment-recovery.ts"),
  ]);
  assert.match(layout, /DEPLOYMENT_RECOVERY_BOOTSTRAP_SCRIPT/);
  assert.match(layout, /dangerouslySetInnerHTML/);
  assert.match(recovery, /vite:preloadError/);
  assert.match(recovery, /unhandledrejection/);
  assert.match(recovery, /sessionStorage\.getItem\(recoveryKey\)/);
  assert.match(recovery, /RECOVERY_GUARD_MS = 60_000/);
  assert.match(recovery, /window\.location\.replace\(window\.location\.href\)/);
});

test("the worker converts missing hashed JavaScript into a no-store recovery module", async () => {
  const [worker, recovery, boundary] = await Promise.all([
    read("worker/index.ts"),
    read("app/lib/deployment-recovery.ts"),
    read("app/error.tsx"),
  ]);
  assert.match(worker, /original\.status === 404/);
  assert.match(worker, /VERSIONED_JAVASCRIPT_ASSET\.test\(url\.pathname\)/);
  assert.match(worker, /STALE_ASSET_RECOVERY_MODULE_SCRIPT/);
  assert.match(worker, /"content-type": "text\/javascript; charset=utf-8"/);
  assert.match(worker, /"x-hpsm-asset-recovery": "1"/);
  assert.match(recovery, /export default \{\};/);
  assert.match(boundary, /window\.location\.replace\(window\.location\.href\)/);
});
