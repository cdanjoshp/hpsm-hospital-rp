import { adminHeaders } from "../../../lib/admin-data";
import { getSupabaseAdminConfig } from "../../../lib/supabase-server";

type SharedConsultationDocument = {
  document_id: string;
  consultation_id: number;
  file_size: number;
  mime_type: "image/png";
  render_version: "consultation-document-png-v3";
  storage_path: string;
};

export async function GET(_request: Request, context: { params: Promise<{ file: string }> }) {
  return serve(await context.params, false);
}

export async function HEAD(_request: Request, context: { params: Promise<{ file: string }> }) {
  return serve(await context.params, true);
}

async function serve(params: { file: string }, headOnly: boolean) {
  const shareId = shareIdFromFilename(params.file);
  if (!shareId) return notFound();
  try {
    const document = await resolveShare(shareId);
    if (!document || document.mime_type !== "image/png" || document.render_version !== "consultation-document-png-v3") return notFound();
    const stored = await fetchStoredDocument(document.storage_path);
    if (!stored.ok || (!headOnly && !stored.body)) return notFound();
    const headers = imageHeaders(document.file_size, stored.headers.get("content-length"));
    if (headOnly) await stored.body?.cancel();
    return new Response(headOnly ? null : stored.body, { headers, status: 200 });
  } catch {
    return notFound();
  }
}

async function resolveShare(shareId: string) {
  const { serviceRoleKey, url } = getSupabaseAdminConfig();
  const response = await fetch(`${url}/rest/v1/rpc/resolve_consultation_document_share`, {
    body: JSON.stringify({ p_share_id: shareId }),
    cache: "no-store",
    headers: adminHeaders(serviceRoleKey),
    method: "POST",
    signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) return null;
  return await response.json().catch(() => null) as SharedConsultationDocument | null;
}

async function fetchStoredDocument(path: string) {
  const { serviceRoleKey, url } = getSupabaseAdminConfig();
  return fetch(`${url}/storage/v1/object/clinical-exam-documents/${storagePath(path)}`, {
    cache: "no-store",
    headers: adminHeaders(serviceRoleKey),
    signal: AbortSignal.timeout(20_000),
  });
}

function shareIdFromFilename(file: string) {
  return /^([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\.png$/i.exec(file)?.[1]?.toLowerCase() ?? null;
}
function storagePath(path: string) { return path.split("/").map(encodeURIComponent).join("/"); }
function imageHeaders(fileSize: number, storageLength: string | null) { return {
  "cache-control": "no-store, max-age=0",
  "content-disposition": 'inline; filename="HPSM_prontuario_consulta.png"',
  "content-length": storageLength ?? String(fileSize),
  "content-type": "image/png",
  pragma: "no-cache",
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
  "x-robots-tag": "noindex, nofollow, noarchive",
}; }
function notFound() { return new Response(null, { status: 404, headers: { "cache-control": "no-store, max-age=0", "content-type": "text/plain; charset=utf-8", "x-content-type-options": "nosniff", "x-robots-tag": "noindex, nofollow, noarchive" } }); }
