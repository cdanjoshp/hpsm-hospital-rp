import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = await readFile(new URL("../app/components/pending-center.tsx", import.meta.url), "utf8");

test("plan approval uses an accessible in-app confirmation instead of a native dialog", () => {
  assert.doesNotMatch(source, /window\.confirm/);
  assert.match(source, /aria-labelledby="approve-health-plan-title"/);
  assert.match(source, /Confirmar pagamento e ativar/);
  assert.match(source, /reviewPlan\(approving, "approved"\)/);
});
