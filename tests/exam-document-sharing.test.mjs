import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("PNG document metadata and random revocable links remain protected by RLS", async () => {
  const migration = await read("supabase/migrations/20260907045521_phase481_png_document_sharing.sql");
  const storageGuard = await read("supabase/migrations/20260907053500_phase481_verify_document_storage.sql");
  assert.match(migration, /create table public\.clinical_exam_documents/);
  assert.match(migration, /create table public\.clinical_exam_document_shares/);
  assert.match(migration, /force row level security/g);
  assert.match(migration, /clinical_exam_document_shares_one_active_uidx/);
  assert.match(migration, /default gen_random_uuid\(\)/);
  assert.match(migration, /grant execute on function public\.resolve_clinical_exam_document_share\(uuid\) to service_role/);
  assert.doesNotMatch(migration, /grant (?:select|execute).* to anon/);
  assert.match(storageGuard, /from storage\.objects object/);
  assert.match(storageGuard, /object\.bucket_id = 'clinical-exam-documents'/);
  assert.match(storageGuard, /object\.metadata ->> 'mimetype'/);
  assert.match(storageGuard, /object\.metadata ->> 'size'/);
});

test("public PNG route is direct, anonymous, non-indexed and supports GET plus HEAD", async () => {
  const route = await read("app/api/exam-share/[file]/route.ts");
  assert.match(route, /export async function GET/);
  assert.match(route, /export async function HEAD/);
  assert.match(route, /\\\.png\$/);
  assert.match(route, /"content-type": "image\/png"/);
  assert.match(route, /"cache-control": "no-store, max-age=0"/);
  assert.match(route, /"x-robots-tag": "noindex, nofollow, noarchive"/);
  assert.match(route, /new Response\(headOnly \? null : stored\.body/);
  assert.doesNotMatch(route, /getSession|getEffectivePermission|redirect|createSignedUrl/);
});

test("authenticated management reuses one canonical PNG, publishes automatically and compensates orphan uploads", async () => {
  const [route, service, storage, renderer, version, template, actions] = await Promise.all([
    read("app/api/exams/document-image/route.ts"),
    read("app/lib/exam-document-image-service.ts"),
    read("app/lib/exam-document-storage.ts"),
    read("app/lib/final-exam-png.ts"),
    read("app/lib/exam-document-version.ts"),
    read("app/lib/institutional-document-png.ts"),
    read("app/components/final-exam-document-actions.tsx"),
  ]);
  assert.match(route, /getSessionBootstrap\(\)/);
  assert.match(route, /permissionCodes\.includes\("exams\.view"\)/);
  assert.match(service, /exam\.status !== "completed" \|\| !exam\.final_report_snapshot/);
  assert.match(service, /if \(!state\.document\)/);
  assert.match(service, /publishDocumentImage/);
  assert.match(service, /deleteStoredExamDocument\(storagePath\)/);
  assert.match(route, /ensureExamDocumentImage/);
  assert.match(storage, /clinical-exam-documents/);
  assert.match(storage, /x-upsert": "false"/);
  assert.match(renderer, /buildFinalExamDocument|FinalExamDocumentModel/);
  assert.match(renderer, /FINAL_EXAM_PNG_RENDER_VERSION/);
  assert.match(version, /exam-document-png-v10/);
  assert.equal(template.match(/Documento gerado exclusivamente para uso em RP\./g)?.length, 1);
  assert.doesNotMatch(renderer, /Imagem gerada por IA\./);
  assert.doesNotMatch(renderer, /GTA|roleplay|fictíci|simulação|personagem/i);
  assert.match(actions, /Baixar imagem/);
  assert.match(actions, /Copiar link/);
  assert.match(actions, /prepareDocumentAutomatically/);
  assert.doesNotMatch(actions, /Publicar imagem|Tentar publicar novamente|Gerar imagem/);
  assert.doesNotMatch(actions, /Baixar PDF/);
});
