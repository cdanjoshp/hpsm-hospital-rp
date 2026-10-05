import type { DocumentImagePublication, DocumentMediaType } from "./document-media-types";
import { getSupabaseAdminConfig } from "./supabase-server";

const FIVEMANAGE_UPLOAD_URL = "https://api.fivemanage.com/api/v3/file";
const MAX_DOCUMENT_BYTES = 12 * 1024 * 1024;

type BeginPublication = {
  attempt_token: string | null;
  in_progress: boolean;
  publication: DocumentImagePublication;
  should_upload: boolean;
};

export async function getDocumentImagePublication(documentType: DocumentMediaType, documentId: number) {
  return callDocumentMediaRpc<DocumentImagePublication | null>("document_image_publication_state", {
    p_document_id: documentId,
    p_document_type: documentType,
  });
}

export async function publishDocumentImage(input: {
  bytes: Uint8Array;
  documentId: number;
  documentType: DocumentMediaType;
  filename: string;
  renderVersion: string;
  uploadedBy: string | null;
}) {
  assertPng(input.bytes);
  const begin = await callDocumentMediaRpc<BeginPublication>("begin_document_image_publication", {
    p_document_id: input.documentId,
    p_document_type: input.documentType,
    p_render_version: input.renderVersion,
    p_uploaded_by: input.uploadedBy,
  });
  if (!begin.should_upload) {
    if (begin.publication.publication_status === "PUBLISHED") return begin.publication;
    if (begin.in_progress) throw new Error("A imagem já está sendo publicada. Aguarde alguns instantes.");
    return begin.publication;
  }
  if (!begin.attempt_token) throw new Error("Não foi possível iniciar a publicação da imagem.");

  try {
    const apiKey = process.env.FIVEMANAGE_API_KEY;
    if (!apiKey) throw new PublicationError("CONFIGURATION", "A publicação automática no FiveManage não está disponível no momento.");
    const filename = safePngFilename(input.filename);
    const form = new FormData();
    const data = input.bytes.buffer.slice(input.bytes.byteOffset, input.bytes.byteOffset + input.bytes.byteLength) as ArrayBuffer;
    form.append("file", new Blob([data], { type: "image/png" }), filename);
    form.append("filename", filename);
    form.append("path", `hpsm/documents/${input.documentType.toLowerCase()}/${input.documentId}`);
    form.append("metadata", JSON.stringify({ documentId: input.documentId, documentType: input.documentType, name: filename }));
    form.append("retentionExempt", "true");
    const response = await fetch(FIVEMANAGE_UPLOAD_URL, {
      body: form,
      headers: { authorization: apiKey },
      method: "POST",
      signal: AbortSignal.timeout(30_000),
    });
    const payload = await response.json().catch(() => null) as { data?: { id?: unknown; url?: unknown }; status?: unknown } | null;
    if (!response.ok) throw new PublicationError(response.status === 401 || response.status === 403 ? "AUTH" : "REJECTED", "A publicação automática no FiveManage não foi concluída.");
    const externalAssetId = typeof payload?.data?.id === "string" ? payload.data.id.trim() : "";
    const cdnUrl = typeof payload?.data?.url === "string" ? canonicalFiveManageUrl(payload.data.url) : null;
    if (!externalAssetId || !cdnUrl) throw new PublicationError("INVALID_RESPONSE", "Não foi possível confirmar a publicação da imagem.");
    return await callDocumentMediaRpc<DocumentImagePublication>("complete_document_image_publication", {
      p_attempt_token: begin.attempt_token,
      p_cdn_url: cdnUrl,
      p_document_id: input.documentId,
      p_document_type: input.documentType,
      p_external_asset_id: externalAssetId,
    });
  } catch (cause) {
    const error = publicationError(cause);
    await callDocumentMediaRpc("fail_document_image_publication", {
      p_attempt_token: begin.attempt_token,
      p_document_id: input.documentId,
      p_document_type: input.documentType,
      p_error_code: error.code,
      p_error_message: error.message,
    }).catch(() => undefined);
    throw error;
  }
}

export function recordDocumentImageEvent(documentType: DocumentMediaType, documentId: number, actorUserId: string | null, action: "DOCUMENT_IMAGE_DOWNLOAD" | "DOCUMENT_IMAGE_LINK_COPIED" | "DOCUMENT_IMAGE_RENDERED") {
  return callDocumentMediaRpc<void>("record_document_image_event", {
    p_action: action,
    p_actor_user_id: actorUserId,
    p_document_id: documentId,
    p_document_type: documentType,
  });
}

export function publicationClientState(publication: DocumentImagePublication | null) {
  return {
    publication,
    publicationError: publication?.publication_status === "FAILED" ? publication.last_error : null,
    publicationStatus: publication?.publication_status ?? null,
  };
}

export function currentDocumentImagePublication(publication: DocumentImagePublication | null, renderVersion: string | undefined) {
  return renderVersion && publication?.render_version === renderVersion ? publication : null;
}

async function callDocumentMediaRpc<T>(name: string, body: Record<string, unknown>): Promise<T> {
  const { serviceRoleKey, url } = getSupabaseAdminConfig();
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    body: JSON.stringify(body),
    cache: "no-store",
    headers: { apikey: serviceRoleKey, authorization: `Bearer ${serviceRoleKey}`, "content-type": "application/json" },
    method: "POST",
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) {
    const payload = await response.json().catch(() => null) as { message?: string } | null;
    throw new Error(payload?.message || "Não foi possível atualizar a publicação da imagem.");
  }
  if (response.status === 204) return undefined as T;
  return await response.json() as T;
}

function assertPng(bytes: Uint8Array) {
  if (bytes.byteLength < 32 || bytes.byteLength > MAX_DOCUMENT_BYTES || bytes[0] !== 0x89 || bytes[1] !== 0x50 || bytes[2] !== 0x4e || bytes[3] !== 0x47) {
    throw new PublicationError("INVALID_FILE", "A imagem gerada não pôde ser publicada.");
  }
}

function safePngFilename(value: string) {
  const normalized = value.normalize("NFKD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/^-+|-+$/g, "");
  return `${normalized.replace(/[.]png$/i, "").slice(0, 120) || "documento-hpsm"}.png`;
}

function canonicalFiveManageUrl(value: string) {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || (url.hostname !== "fivemanage.com" && !url.hostname.endsWith(".fivemanage.com"))) return null;
    return url.toString();
  } catch {
    return null;
  }
}

class PublicationError extends Error {
  constructor(readonly code: string, message: string) { super(message); }
}

function publicationError(cause: unknown) {
  if (cause instanceof PublicationError) return cause;
  if (cause instanceof DOMException && (cause.name === "AbortError" || cause.name === "TimeoutError")) {
    return new PublicationError("TIMEOUT", "A publicação automática demorou além do esperado e será retomada pelo sistema.");
  }
  return new PublicationError("UNAVAILABLE", cause instanceof Error ? cause.message : "A publicação automática no FiveManage não foi concluída.");
}
