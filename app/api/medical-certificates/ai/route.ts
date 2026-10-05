import { getSessionBootstrap } from "../../../lib/session";
import { getSupabaseConfig } from "../../../lib/supabase-server";

export async function POST(request: Request) {
  const context = await getSessionBootstrap();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!context.permissionCodes.includes("atestados.create")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
  try {
    const body = await request.json() as Record<string, unknown>;
    const certificateId = positiveInteger(body.certificateId);
    if (!certificateId) return Response.json({ error: "Atestado inválido." }, { status: 400 });
    const { anonKey, url } = getSupabaseConfig();
    const response = await fetch(`${url}/functions/v1/medical-certificate-ai`, {
      method: "POST",
      headers: { apikey: anonKey, authorization: `Bearer ${context.accessToken}`, "content-type": "application/json" },
      body: JSON.stringify({ certificateId }),
      cache: "no-store",
      signal: AbortSignal.timeout(65_000),
    });
    const payload = await response.json().catch(() => null) as Record<string, unknown> | null;
    if (!payload) return Response.json({ error: "Assistente de IA temporariamente indisponível." }, { status: 503 });
    return Response.json(payload, { status: response.status, headers: { "cache-control": "private, no-store" } });
  } catch (error) {
    if (error instanceof DOMException && (error.name === "AbortError" || error.name === "TimeoutError")) {
      return Response.json({ error: "O assistente demorou para responder. Seu rascunho foi preservado." }, { status: 504 });
    }
    return Response.json({ error: "Assistente de IA temporariamente indisponível." }, { status: 503 });
  }
}

function positiveInteger(value: unknown) { const parsed = Number(value); return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null; }

