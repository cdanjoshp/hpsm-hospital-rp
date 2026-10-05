import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type Json = Record<string, unknown>;
type DeleteResult = {
  consultation_id: number;
  deleted?: unknown;
  storage?: {
    clinical_exam_images?: unknown;
    clinical_exam_documents?: unknown;
  };
};

const IMAGE_BUCKET = "clinical-exam-images";
const DOCUMENT_BUCKET = "clinical-exam-documents";

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json({ error: "Método não permitido." }, 405);
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "Sessão inválida." }, 401);

  const url = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !anonKey || !serviceKey) return json({ error: "Exclusão temporariamente indisponível." }, 503);

  try {
    const body = await request.json() as Json;
    const consultationId = positiveInteger(body.consultationId);
    if (!consultationId) return json({ error: "Consulta inválida." }, 400);

    const consultationDocumentPaths = await rpc<unknown>(url, anonKey, authorization, "consultation_document_storage_paths_for_delete", {
      p_consultation_id: consultationId,
    });
    const result = await rpc<DeleteResult>(url, anonKey, authorization, "delete_clinical_consultation", {
      p_consultation_id: consultationId,
    });
    const imagePaths = storagePaths(result.storage?.clinical_exam_images, /^clinical-exams\/\d+\//);
    const documentPaths = [...new Set([
      ...storagePaths(result.storage?.clinical_exam_documents, /^(clinical-exams\/\d+\/documents\/|medical-certificates\/\d+\/documents\/)/),
      ...storagePaths(consultationDocumentPaths, /^(consultations|prescriptions)\/\d+\/documents\//),
    ])];

    const [images, documents] = await Promise.all([
      cleanupBucket(url, serviceKey, IMAGE_BUCKET, imagePaths),
      cleanupBucket(url, serviceKey, DOCUMENT_BUCKET, documentPaths),
    ]);

    return json({
      ok: true,
      consultationId: result.consultation_id,
      deleted: result.deleted ?? {},
      removedFiles: images.removed + documents.removed,
      storageCleanupPending: images.pending || documents.pending,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Não foi possível excluir a consulta.";
    const forbidden = /exclusiva dos cargos de Diretoria|acesso não autorizado|sessão inválida/i.test(message);
    const notFound = /consulta não localizada/i.test(message);
    return json({ error: friendly(message) }, forbidden ? 403 : notFound ? 404 : 400);
  }
});

async function rpc<T>(url: string, key: string, authorization: string, name: string, body: Json): Promise<T> {
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { apikey: key, authorization, "content-type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(25_000),
  });
  const payload = await response.json().catch(() => null) as { message?: string } | null;
  if (!response.ok) throw new Error(payload?.message ?? "Operação protegida indisponível.");
  return payload as T;
}

async function cleanupBucket(url: string, serviceKey: string, bucket: string, paths: string[]) {
  if (!paths.length) return { pending: false, removed: 0 };
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      await removeObjects(url, serviceKey, bucket, paths);
      return { pending: false, removed: paths.length };
    } catch {
      if (attempt === 1) return { pending: true, removed: 0 };
    }
  }
  return { pending: true, removed: 0 };
}

async function removeObjects(url: string, serviceKey: string, bucket: string, paths: string[]) {
  for (let offset = 0; offset < paths.length; offset += 1_000) {
    const response = await fetch(`${url}/storage/v1/object/${bucket}`, {
      method: "DELETE",
      headers: { apikey: serviceKey, authorization: `Bearer ${serviceKey}`, "content-type": "application/json" },
      body: JSON.stringify({ prefixes: paths.slice(offset, offset + 1_000) }),
      signal: AbortSignal.timeout(12_000),
    });
    if (!response.ok) throw new Error("Falha ao remover arquivos privados da consulta.");
  }
}

function storagePaths(value: unknown, allowed: RegExp) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.filter((path): path is string => (
    typeof path === "string"
    && path.length <= 500
    && allowed.test(path)
  )))];
}

function positiveInteger(value: unknown) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function friendly(message: string) {
  if (/exclusiva dos cargos de Diretoria/i.test(message)) return "Somente Diretor Executivo e Diretor Geral podem excluir consultas.";
  if (/consulta não localizada/i.test(message)) return "A consulta não existe mais ou já foi excluída.";
  return message;
}

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "private, no-store" },
  });
}
