import { getSessionBootstrap } from "../../../lib/session";
import { getSupabaseConfig } from "../../../lib/supabase-server";
import type { ConsultationAiAction } from "../../../lib/consultations";

const actions = new Set<ConsultationAiAction>(["ANAMNESIS_REWRITE", "EXAM_SUGGESTIONS", "CLINICAL_SYNTHESIS"]);

export async function POST(request: Request) {
  const context = await getSessionBootstrap();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!context.permissionCodes.includes("consultations.complete")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
  try {
    const body = await request.json() as Record<string, unknown>;
    const consultationId = positiveInteger(body.consultationId);
    const action = typeof body.action === "string" && actions.has(body.action as ConsultationAiAction) ? body.action as ConsultationAiAction : null;
    if (!consultationId || !action) return Response.json({ error: "Solicitação de IA inválida." }, { status: 400 });
    const { anonKey, url } = getSupabaseConfig();
    const response = await fetch(`${url}/functions/v1/consultation-ai`, {
      method: "POST",
      headers: { apikey: anonKey, authorization: `Bearer ${context.accessToken}`, "content-type": "application/json" },
      body: JSON.stringify({ consultationId, action, proceedWithPendingExams: body.proceedWithPendingExams === true }),
      cache: "no-store",
      signal: AbortSignal.timeout(70_000),
    });
    const payload = await response.json().catch(() => null) as Record<string, unknown> | null;
    if (!payload) return Response.json({ error: "Assistente de IA temporariamente indisponível." }, { status: 503 });
    return Response.json(payload, { status: response.status, headers: { "cache-control": "private, no-store" } });
  } catch (error) {
    if (error instanceof DOMException && (error.name === "AbortError" || error.name === "TimeoutError")) return Response.json({ error: "O assistente demorou para responder. O rascunho foi preservado." }, { status: 504 });
    return Response.json({ error: "Assistente de IA temporariamente indisponível." }, { status: 503 });
  }
}

function positiveInteger(value: unknown) { const parsed = Number(value); return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null; }
