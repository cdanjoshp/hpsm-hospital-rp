import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("Meu RH groups its domains without removing existing flows", async () => {
  const source = await read("app/components/my-hr-panel.tsx");
  assert.match(source, /type MyHrSection = "career" \| "absences" \| "history"/);
  assert.match(source, /Carreira e formação/);
  assert.match(source, /Afastamentos/);
  assert.match(source, /Histórico semanal/);
  assert.match(source, /section === "career"/);
  assert.match(source, /section === "absences"/);
  assert.match(source, /section === "history"/);
  assert.match(source, /fetch\("\/api\/hr\/absences"/);
  assert.match(source, /fetch\("\/api\/hr\/justifications"/);
  assert.match(source, /Justificar déficit/);
  assert.match(source, /Advertências no ciclo/);
});

test("Meu RH keeps career progression full-width and responsive dark styles", async () => {
  const [career, css] = await Promise.all([
    read("app/components/career-self-panel.tsx"),
    read("app/brand.css"),
  ]);
  assert.match(career, /career-self-primary/);
  assert.match(career, /data-single="true"/);
  assert.doesNotMatch(career, /tcc/i);
  assert.match(css, /\.career-self-primary\[data-single="true"\]\s*\{\s*grid-template-columns:\s*1fr/);
  assert.match(css, /\.my-hr-summary-grid/);
  assert.match(css, /\.my-hr-section-nav/);
  assert.match(css, /html\[data-theme="dark"\][\s\S]*?\.my-hr-snapshot-card/);
  assert.match(css, /@media \(max-width: 560px\)[\s\S]*?\.my-hr-snapshot-grid/);
});
