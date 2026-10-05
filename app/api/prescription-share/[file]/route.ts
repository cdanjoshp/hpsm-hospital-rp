import { adminHeaders } from "../../../lib/admin-data";
import { getSupabaseAdminConfig } from "../../../lib/supabase-server";

type SharedPrescriptionDocument = { document_id: string; consultation_id: number; file_size: number; mime_type: "image/png"; render_version: "prescription-document-png-v2"; storage_path: string };
export async function GET(_request: Request, context: { params: Promise<{ file: string }> }) { return serve(await context.params, false); }
export async function HEAD(_request: Request, context: { params: Promise<{ file: string }> }) { return serve(await context.params, true); }
async function serve(params: { file: string }, headOnly: boolean) {
  const shareId = /^([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\.png$/i.exec(params.file)?.[1]?.toLowerCase();
  if (!shareId) return notFound();
  try {
    const document = await resolveShare(shareId);
    if (!document || document.mime_type !== "image/png" || document.render_version !== "prescription-document-png-v2") return notFound();
    const stored = await fetchStoredDocument(document.storage_path);
    if (!stored.ok || (!headOnly && !stored.body)) return notFound();
    if (headOnly) await stored.body?.cancel();
    return new Response(headOnly ? null : stored.body, { status: 200, headers: {
      "cache-control": "no-store, max-age=0", "content-disposition": 'inline; filename="HPSM_receita_RP.png"',
      "content-length": stored.headers.get("content-length") ?? String(document.file_size), "content-type": "image/png", pragma: "no-cache",
      "referrer-policy": "no-referrer", "x-content-type-options": "nosniff", "x-robots-tag": "noindex, nofollow, noarchive",
    } });
  } catch { return notFound(); }
}
async function resolveShare(shareId: string) { const { serviceRoleKey, url } = getSupabaseAdminConfig(); const response = await fetch(`${url}/rest/v1/rpc/resolve_prescription_document_share`, { body: JSON.stringify({ p_share_id: shareId }), cache: "no-store", headers: adminHeaders(serviceRoleKey), method: "POST", signal: AbortSignal.timeout(10_000) }); if (!response.ok) return null; return await response.json().catch(() => null) as SharedPrescriptionDocument | null; }
async function fetchStoredDocument(path: string) { const { serviceRoleKey, url } = getSupabaseAdminConfig(); return fetch(`${url}/storage/v1/object/clinical-exam-documents/${path.split("/").map(encodeURIComponent).join("/")}`, { cache: "no-store", headers: adminHeaders(serviceRoleKey), signal: AbortSignal.timeout(20_000) }); }
function notFound() { return new Response(null, { status: 404, headers: { "cache-control": "no-store, max-age=0", "content-type": "text/plain; charset=utf-8", "x-content-type-options": "nosniff", "x-robots-tag": "noindex, nofollow, noarchive" } }); }
