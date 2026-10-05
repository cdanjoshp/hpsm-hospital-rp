import { extractExamPagePng } from "./exam-png-page-split";
import { downloadStoredExamDocument, examDocumentStoragePath } from "./exam-document-storage";
import { getClinicalExamDocumentState } from "./exams";
import { getSupabaseAdminConfig } from "./supabase-server";

type PageRecord = { cdn_url: string; external_asset_id: string };

export async function ensurePublishedExamPage(accessToken: string, examId: number, documentId: string, page: number) {
  const existing = await findPage(documentId, page);
  if (existing) return existing.cdn_url;
  const stored = await downloadStoredExamDocument(examDocumentStoragePath(examId, documentId));
  if (!stored.ok) throw new Error("O arquivo do exame não está disponível.");
  const bytes = extractExamPagePng(new Uint8Array(await stored.arrayBuffer()), page);
  const key = process.env.FIVEMANAGE_API_KEY;
  if (!key) throw new Error("A publicação das páginas não está disponível.");
  const form = new FormData();
  form.append("file", new Blob([bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer], { type: "image/png" }), `hpsm-exame-${examId}-pagina-${page}.png`);
  form.append("filename", `hpsm-exame-${examId}-pagina-${page}.png`);
  form.append("path", `hpsm/documents/exam/${examId}/pages`);
  form.append("metadata", JSON.stringify({ documentId: examId, documentType: "EXAM", page, name: `hpsm-exame-${examId}-pagina-${page}.png` }));
  form.append("retentionExempt", "true");
  const response = await fetch("https://api.fivemanage.com/api/v3/file", {
    method: "POST", body: form, headers: { authorization: key }, signal: AbortSignal.timeout(30000),
  });
  const uploaded = await response.json().catch(() => null) as { data?: { id?: unknown; url?: unknown } } | null;
  if (!response.ok || typeof uploaded?.data?.id !== "string" || typeof uploaded.data.url !== "string") throw new Error("Não foi possível publicar a página do exame.");
  const url = new URL(uploaded.data.url);
  if (url.protocol !== "https:" || (url.hostname !== "fivemanage.com" && !url.hostname.endsWith(".fivemanage.com"))) throw new Error("O endereço da página publicada é inválido.");
  const currentState = await getClinicalExamDocumentState(accessToken, examId);
  if (currentState.document?.id !== documentId) throw new Error("O laudo foi atualizado; abra novamente o exame para obter a página atual.");
  const { serviceRoleKey, url: base } = getSupabaseAdminConfig();
  const saved = await fetch(`${base}/rest/v1/clinical_exam_page_publications?on_conflict=document_id,page_number`, {
    method: "POST", cache: "no-store", headers: {
      apikey: serviceRoleKey, authorization: `Bearer ${serviceRoleKey}`, "content-type": "application/json", prefer: "resolution=ignore-duplicates,return=representation",
    },
    body: JSON.stringify({ exam_id: examId, document_id: documentId, page_number: page, external_asset_id: uploaded.data.id, cdn_url: url.toString() }),
    signal: AbortSignal.timeout(15000),
  });
  if (!saved.ok) throw new Error("A página foi publicada, mas não foi possível guardar o link.");
  return (await findPage(documentId, page))?.cdn_url ?? url.toString();
}

async function findPage(documentId: string, page: number): Promise<PageRecord | null> {
  const { serviceRoleKey, url } = getSupabaseAdminConfig();
  const response = await fetch(`${url}/rest/v1/clinical_exam_page_publications?select=cdn_url,external_asset_id&document_id=eq.${encodeURIComponent(documentId)}&page_number=eq.${page}&limit=1`, {
    cache: "no-store", headers: { apikey: serviceRoleKey, authorization: `Bearer ${serviceRoleKey}` }, signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error("Não foi possível consultar os links das páginas.");
  return ((await response.json()) as PageRecord[])[0] ?? null;
}
