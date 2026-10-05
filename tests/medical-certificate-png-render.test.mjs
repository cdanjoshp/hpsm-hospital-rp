import assert from "node:assert/strict";
import { rm } from "node:fs/promises";
import test, { after, before } from "node:test";
import { pathToFileURL } from "node:url";
import { build } from "esbuild";

const bundlePath = `/tmp/hpsm-medical-certificate-png-${process.pid}.mjs`;
let renderMedicalCertificatePng;

before(async () => {
  await build({
    bundle: true,
    entryPoints: [new URL("../app/lib/medical-certificate-png.ts", import.meta.url).pathname],
    format: "esm",
    loader: { ".woff2": "dataurl", ".png": "dataurl" },
    outfile: bundlePath,
    platform: "node",
    target: "node22",
  });
  ({ renderMedicalCertificatePng } = await import(`${pathToFileURL(bundlePath).href}?${Date.now()}`));
});

after(async () => { await rm(bundlePath, { force: true }); });

test("atestado v3 renderiza o template institucional oficial com diagnóstico, CID, assinatura e rubrica", async () => {
  const professionalId = "11111111-1111-4111-8111-111111111111";
  const tinyPng = Uint8Array.from(Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "base64"));
  const result = await renderMedicalCertificatePng({
    attendance: { created_at: "2026-09-24T12:00:00.000Z", id: 42 },
    certificateCode: "AT-000042",
    certificateId: 42,
    diagnosis: { text: "Quadro clínico que requer afastamento temporário", cid_code: "Z76.3", cid_description: "Pessoa em boa saúde acompanhando pessoa doente" },
    filename: "HPSM_AT-000042_Atestado-Medico.png",
    issuedAt: "2026-09-24T13:00:00.000Z",
    leaveDays: 2,
    originType: "consultation",
    patient: { id: 7, name: "Paciente de Teste", passport: "0007" },
    professional: { crm_code: "05321409", id: professionalId, name: "Profissional de Teste", position: "Médica", registration_date: "2026-01-01", signature_image_path: "private/signature.png" },
    text: "Atesto que o paciente necessita de 2 dias de afastamento por quadro clínico que requer afastamento temporário, classificado pelo CID-10 Z76.3.",
  }, { bytes: tinyPng, personId: professionalId });
  assert.deepEqual(Array.from(result.bytes.slice(0, 8)), [137, 80, 78, 71, 13, 10, 26, 10]);
  assert.equal(result.width, 1200);
  assert.ok(result.height > 1100);
  assert.ok(result.bytes.byteLength < 12 * 1024 * 1024);
});
