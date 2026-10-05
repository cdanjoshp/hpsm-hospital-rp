import assert from "node:assert/strict";
import { rm } from "node:fs/promises";
import test, { after, before } from "node:test";
import { pathToFileURL } from "node:url";
import UPNGPackage from "@pdf-lib/upng";
import { build } from "esbuild";

const bundle = `/tmp/hpsm-exam-page-split-${process.pid}.mjs`;
const UPNG = UPNGPackage.default ?? UPNGPackage;
let extractExamPagePng;

before(async () => {
  await build({ bundle: true, entryPoints: [new URL("../app/lib/exam-png-page-split.ts", import.meta.url).pathname], format: "esm", outfile: bundle, platform: "node", target: "node22" });
  ({ extractExamPagePng } = await import(pathToFileURL(bundle).href));
});
after(async () => rm(bundle, { force: true }));

test("cada botão corresponde a um arquivo PNG com somente aquela página", () => {
  const width = 4, pageHeight = 3;
  const pixels = new Uint8Array(width * pageHeight * 2 * 4);
  for (let row = 0; row < pageHeight * 2; row++) for (let col = 0; col < width; col++) {
    pixels.set(row < pageHeight ? [255, 0, 0, 255] : [0, 0, 255, 255], (row * width + col) * 4);
  }
  const image = new Uint8Array(UPNG.encode([pixels.buffer], width, pageHeight * 2, 0));
  const first = UPNG.decode(extractExamPagePng(image, 1, pageHeight, width).buffer);
  const second = UPNG.decode(extractExamPagePng(image, 2, pageHeight, width).buffer);
  assert.equal(first.height, pageHeight);
  assert.equal(second.height, pageHeight);
  assert.deepEqual([...new Uint8Array(UPNG.toRGBA8(first)[0]).slice(0, 4)], [255, 0, 0, 255]);
  assert.deepEqual([...new Uint8Array(UPNG.toRGBA8(second)[0]).slice(0, 4)], [0, 0, 255, 255]);
  assert.throws(() => extractExamPagePng(image, 3, pageHeight, width), /Página do exame inválida/);
});
