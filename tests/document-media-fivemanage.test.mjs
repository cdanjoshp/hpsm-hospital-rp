import assert from "node:assert/strict";
import { readFile, rm } from "node:fs/promises";
import test, { after, before } from "node:test";
import { pathToFileURL } from "node:url";
import { build } from "esbuild";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");
const bundle = `/tmp/hpsm-document-media-${process.pid}.mjs`;
let publishDocumentImage;
let currentDocumentImagePublication;

before(async () => {
  await build({ bundle: true, entryPoints: [new URL("../app/lib/document-media.ts", import.meta.url).pathname], format: "esm", outfile: bundle, platform: "node", target: "node22" });
  ({ publishDocumentImage, currentDocumentImagePublication } = await import(`${pathToFileURL(bundle).href}?${Date.now()}`));
});
after(async () => { await rm(bundle, { force: true }); });

test("link de imagem antiga não aparece até que a nova versão seja publicada", () => {
  const oldPublication = { ...publication("PUBLISHED"), render_version: "exam-document-png-v6", cdn_url: "https://r2.fivemanage.com/old.png" };
  assert.equal(currentDocumentImagePublication(oldPublication, "exam-document-png-v7"), null);
  assert.equal(currentDocumentImagePublication(oldPublication, undefined), null);
  assert.equal(currentDocumentImagePublication({ ...oldPublication, render_version: "exam-document-png-v7" }, "exam-document-png-v7")?.cdn_url, oldPublication.cdn_url);
});

test("publisher FiveManage usa somente backend, V3 multipart e resposta canônica", async () => {
  const originalFetch = globalThis.fetch;
  const originalEnv = { ...process.env };
  const requests = [];
  process.env.SUPABASE_URL = "https://project.supabase.co";
  process.env.SUPABASE_ANON_KEY = "anon";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "service-secret";
  process.env.FIVEMANAGE_API_KEY = "fivemanage-secret";
  globalThis.fetch = async (url, init = {}) => {
    requests.push({ init, url: String(url) });
    if (String(url).endsWith("/rpc/begin_document_image_publication")) return Response.json({ attempt_token: "11111111-1111-4111-8111-111111111111", in_progress: false, publication: publication("PUBLISHING"), should_upload: true });
    if (String(url) === "https://api.fivemanage.com/api/v3/file") return Response.json({ data: { id: "asset-42", url: "https://r2.fivemanage.com/team/asset-42.png" }, status: "ok" });
    if (String(url).endsWith("/rpc/complete_document_image_publication")) return Response.json({ ...publication("PUBLISHED"), cdn_url: "https://r2.fivemanage.com/team/asset-42.png", external_asset_id: "asset-42" });
    throw new Error(`Unexpected request: ${url}`);
  };
  try {
    const result = await publishDocumentImage({ bytes: pngBytes(), documentId: 42, documentType: "EXAM", filename: "exame-EX-000042.png", renderVersion: "exam-document-png-v6", uploadedBy: null });
    assert.equal(result.publication_status, "PUBLISHED");
    const upload = requests.find((item) => item.url.includes("fivemanage.com/api/v3/file"));
    assert.equal(upload.init.headers.authorization, "fivemanage-secret");
    assert.ok(upload.init.body instanceof FormData);
    assert.equal(upload.init.body.get("filename"), "exame-EX-000042.png");
    assert.equal(upload.init.body.get("path"), "hpsm/documents/exam/42");
    assert.equal(upload.init.body.get("retentionExempt"), "true");
    assert.doesNotMatch(JSON.stringify([...upload.init.body.entries()].map(([key, value]) => [key, typeof value === "string" ? value : "blob"])), /fivemanage-secret/);
  } finally {
    globalThis.fetch = originalFetch;
    process.env = originalEnv;
  }
});

test("asset publicado é idempotente e não cria novo upload", async () => {
  const originalFetch = globalThis.fetch;
  const originalEnv = { ...process.env };
  let calls = 0;
  process.env.SUPABASE_URL = "https://project.supabase.co";
  process.env.SUPABASE_ANON_KEY = "anon";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "service-secret";
  process.env.FIVEMANAGE_API_KEY = "fivemanage-secret";
  globalThis.fetch = async (url) => {
    calls += 1;
    assert.match(String(url), /begin_document_image_publication$/);
    return Response.json({ attempt_token: null, in_progress: false, publication: { ...publication("PUBLISHED"), cdn_url: "https://r2.fivemanage.com/team/existing.png", external_asset_id: "existing" }, should_upload: false });
  };
  try {
    const result = await publishDocumentImage({ bytes: pngBytes(), documentId: 42, documentType: "EXAM", filename: "exam.png", renderVersion: "exam-document-png-v6", uploadedBy: null });
    assert.equal(result.external_asset_id, "existing");
    assert.equal(calls, 1);
  } finally {
    globalThis.fetch = originalFetch;
    process.env = originalEnv;
  }
});

test("migration protege metadados, concorrência, retry, RLS e auditoria", async () => {
  const sql = await read("supabase/migrations/20260925032500_document_media_fivemanage_publication.sql");
  assert.match(sql, /create table public\.document_media_publications/);
  assert.match(sql, /unique \(document_type, document_id\)/);
  assert.match(sql, /PENDING'[\s\S]*PUBLISHING'[\s\S]*PUBLISHED'[\s\S]*FAILED'/);
  assert.match(sql, /attempt_started_at > now\(\) - interval '2 minutes'/);
  assert.match(sql, /enable row level security/);
  assert.match(sql, /force row level security/);
  assert.match(sql, /revoke all on table public\.document_media_publications from public, anon, authenticated/);
  assert.match(sql, /grant select, insert, update, delete on table public\.document_media_publications to service_role/);
  for (const action of ["DOCUMENT_IMAGE_RENDERED", "DOCUMENT_IMAGE_PUBLISH_STARTED", "DOCUMENT_IMAGE_PUBLISHED", "DOCUMENT_IMAGE_PUBLISH_FAILED", "DOCUMENT_IMAGE_DOWNLOAD", "DOCUMENT_IMAGE_LINK_COPIED"]) assert.match(sql, new RegExp(action));
});

test("todos os documentos usam o serviço central e a interface usa Imagem", async () => {
  const files = await Promise.all([
    read("app/lib/exam-document-image-service.ts"),
    read("app/lib/medical-certificate-document-service.ts"),
    read("app/lib/consultation-document-service.ts"),
    read("app/lib/prescription-document-service.ts"),
    read("app/api/patient-portal/exams/[id]/document/route.ts"),
    read("app/api/patient-portal/medical-certificates/[id]/document/route.ts"),
  ]);
  for (const source of files) assert.match(source, /publishDocumentImage/);
  const visible = await Promise.all([
    read("app/components/exam-document-png-action.tsx"), read("app/components/final-exam-document-actions.tsx"),
    read("app/components/medical-certificate-document-actions.tsx"), read("app/components/consultation-document-actions.tsx"),
    read("app/components/prescription-document-actions.tsx"), read("app/components/patient-portal-exam-actions.tsx"),
  ]);
  for (const source of visible) {
    assert.doesNotMatch(source, /Baixar PDF|Gerar PDF|Visualizar PDF|Baixar PNG|Visualizar PNG|Gerar PNG/);
    assert.doesNotMatch(source, /window\.(open|confirm|alert|prompt)/);
  }
  assert.match(visible.join("\n"), /Visualizar imagem/);
  assert.match(visible.join("\n"), /Baixar imagem/);
  assert.match(visible.join("\n"), /Copiar link/);
});

test("geração e publicação são automáticas, sem ação manual do profissional", async () => {
  const [examRoute, examService, consultationRoute, certificateRoute, ...actions] = await Promise.all([
    read("app/api/exams/route.ts"),
    read("app/lib/exam-document-image-service.ts"),
    read("app/api/consultations/route.ts"),
    read("app/api/medical-certificates/route.ts"),
    read("app/components/final-exam-document-actions.tsx"),
    read("app/components/medical-certificate-document-actions.tsx"),
    read("app/components/consultation-document-actions.tsx"),
    read("app/components/prescription-document-actions.tsx"),
  ]);
  assert.match(examRoute, /decision === "approve"[\s\S]*ensureExamDocumentImage/);
  assert.match(examService, /publishDocumentImage/);
  assert.match(consultationRoute, /Promise\.allSettled\([\s\S]*ensureConsultationDocument[\s\S]*ensurePrescriptionDocument/);
  assert.match(certificateRoute, /ensureMedicalCertificateDocument/);
  for (const source of actions) {
    assert.match(source, /useEffect/);
    assert.match(source, /publica(?:da|ndo) automaticamente|publicação automática/i);
    assert.doesNotMatch(source, /Publicar imagem|Publicar e copiar link|Tentar publicar novamente|Gerar prontuário|Gerar Receita|Gerar imagem/);
  }
});

test("a API key não aparece em componentes nem em variável pública", async () => {
  const [publisher, exam, certificate, consultation, prescription] = await Promise.all([
    read("app/lib/document-media.ts"), read("app/components/final-exam-document-actions.tsx"),
    read("app/components/medical-certificate-document-actions.tsx"), read("app/components/consultation-document-actions.tsx"),
    read("app/components/prescription-document-actions.tsx"),
  ]);
  assert.match(publisher, /process\.env\.FIVEMANAGE_API_KEY/);
  assert.doesNotMatch(publisher, /NEXT_PUBLIC_FIVEMANAGE|[?&]apiKey=/);
  assert.doesNotMatch([exam, certificate, consultation, prescription].join("\n"), /FIVEMANAGE_API_KEY|api\.fivemanage\.com/);
});

test("APIs nunca apresentam o link legado como publicação atual", async () => {
  const sources = await Promise.all([
    read("app/api/exams/document-image/route.ts"),
    read("app/api/consultations/document/route.ts"),
    read("app/api/consultations/prescription/document/route.ts"),
    read("app/api/patient-portal/exams/[id]/document/route.ts"),
  ]);
  for (const source of sources) {
    assert.match(source, /currentDocumentImagePublication\(/);
    assert.match(source, /shareUrl: (?:currentPublication|publication)\?\.publication_status === "PUBLISHED" \? (?:currentPublication|publication)\.cdn_url : null/);
    assert.doesNotMatch(source, /shareUrl:[^\n]*api\/(?:exam|consultation|prescription)-share/);
  }
});

function pngBytes() { const bytes = new Uint8Array(32); bytes.set([0x89, 0x50, 0x4e, 0x47]); return bytes; }
function publication(status) { return { cdn_url: null, created_at: "2026-09-25T00:00:00Z", document_id: 42, document_type: "EXAM", external_asset_id: null, id: "22222222-2222-4222-8222-222222222222", last_error: null, mime_type: "image/png", provider: "fivemanage", publication_status: status, render_version: "exam-document-png-v6", updated_at: "2026-09-25T00:00:00Z", uploaded_at: null }; }
