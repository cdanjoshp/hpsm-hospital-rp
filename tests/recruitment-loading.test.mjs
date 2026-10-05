import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("recruitment applications remain visible when auxiliary identity data fails", async () => {
  const source = await readFile(new URL("app/lib/recruitment-management.ts", root), "utf8");

  assert.match(source, /if \(!applicationsResponse\.ok\)/);
  assert.doesNotMatch(source, /!applicationsResponse\.ok \|\| !decisionsResponse\.ok \|\| !profilesResponse\.ok/);
  assert.match(source, /profiles\?select=user_id,passport,display_name,position_id/);
  assert.match(source, /staff_positions\?select=id,name/);
  assert.doesNotMatch(source, /staff_positions\(name\)/);
});

test("recruitment page does not turn a loading failure into a silent empty queue", async () => {
  const page = await readFile(new URL("app/administrativo/recrutamento/page.tsx", root), "utf8");
  const component = await readFile(new URL("app/components/recruitment-management.tsx", root), "utf8");

  assert.doesNotMatch(page, /catch\(\(\) => \(\{ applications: \[\], decisions: \[\] \}\)\)/);
  assert.match(page, /initialLoadError=\{result\.error\}/);
  assert.match(component, /Falha ao carregar o recrutamento/);
});
