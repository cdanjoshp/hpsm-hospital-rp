import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type Json = Record<string, unknown>;
type DeleteResult = { exam_id: number; storage_paths?: unknown; document_storage_paths?: unknown };

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
    const examId = positiveInteger(body.examId);
    if (!examId) return json({ error: "Exame inválido." }, 400);

    const result = await rpc<DeleteResult>(url, anonKey, authorization, "delete_clinical_exam", { p_exam_id: examId });
    const imagePaths = storagePaths(result.storage_paths, examId, false);
    const documentPaths = storagePaths(result.document_storage_paths, examId, true);
    const [images, documents] = await Promise.all([
      cleanupBucket(url, serviceKey, IMAGE_BUCKET, imagePaths),
      cleanupBucket(url, serviceKey, DOCUMENT_BUCKET, documentPaths),
    ]);
    return json({ ok: true, examId: result.exam_id, removedFiles: images.removed + documents.removed, storageCleanupPending: images.pending || documents.pending });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Não foi possível excluir o exame.";
    const forbidden = /somente diretores|acesso não autorizado|sessão inválida/i.test(message);
    const conflict = /não localizado/i.test(message);
    return json({ error: friendly(message) }, forbidden ? 403 : conflict ? 409 : 400);
  }
});

async function rpc<T>(url: string, key: string, authorization: string, name: string, body: Json): Promise<T> {
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: { apikey: key, authorization, "content-type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(15_000),
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
    if (!response.ok) throw new Error("Falha ao remover arquivos privados do exame.");
  }
}

function storagePaths(value: unknown, examId: number, documents: boolean) {
  if (!Array.isArray(value)) return [];
  const prefix = `clinical-exams/${examId}/`;
  return [...new Set(value.filter((path): path is string => typeof path === "string" && path.startsWith(documents ? `${prefix}documents/` : prefix) && path.length <= 500))];
}

function positiveInteger(value: unknown) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function friendly(message: string) {
  if (/somente diretores/i.test(message)) return "Somente diretores podem excluir exames concluídos.";
  if (/exame não localizado/i.test(message)) return "O exame não existe mais ou já foi excluído.";
  return message;
}

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "private, no-store" },
  });
}
