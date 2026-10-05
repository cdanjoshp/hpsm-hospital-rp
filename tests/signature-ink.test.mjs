import assert from "node:assert/strict";
import { rm } from "node:fs/promises";
import test, { after, before } from "node:test";
import { pathToFileURL } from "node:url";
import UPNGPackage from "@pdf-lib/upng";
import { build } from "esbuild";

const bundlePath = `/tmp/hpsm-signature-ink-${process.pid}.mjs`;
let signatureInk;
const UPNG = UPNGPackage.default ?? UPNGPackage;

before(async () => {
  await build({ bundle: true, entryPoints: [new URL("../app/lib/signature-ink.ts", import.meta.url).pathname], format: "esm", outfile: bundlePath, platform: "node", target: "node22" });
  ({ signatureInk } = await import(`${pathToFileURL(bundlePath).href}?${Date.now()}`));
});
after(async () => rm(bundlePath, { force: true }));

test("a assinatura preserva hastes e remates ao aparar somente margens transparentes", () => {
  const width = 320;
  const height = 240;
  const rgba = new Uint8Array(width * height * 4);
  let sourcePixels = 0;
  for (let x = 10; x <= 309; x += 1) {
    const y = x > 290 ? 172 : 86 + Math.floor(x / 7) % 28;
    const index = (y * width + x) * 4;
    rgba.set([11, 114, 185, 255], index);
    sourcePixels += 1;
  }
  const png = new Uint8Array(UPNG.encode([rgba.buffer], width, height, 0));
  const ink = signatureInk(png);
  const output = UPNG.decode(ink.bytes.buffer.slice(ink.bytes.byteOffset, ink.bytes.byteOffset + ink.bytes.byteLength));
  const pixels = new Uint8Array(UPNG.toRGBA8(output)[0]);
  const visible = pixels.filter((_, index) => index % 4 === 3 && pixels[index] > 8).length;
  assert.equal(visible, sourcePixels);
  assert.ok(ink.height < height);
  assert.ok(ink.width >= 300 && ink.width <= width);
  assert.ok(ink.height > 100, "o remate abaixo da assinatura deve permanecer visível");
});
