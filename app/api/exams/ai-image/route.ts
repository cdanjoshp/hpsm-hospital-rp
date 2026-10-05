import { getEffectivePermissionCodes } from "../../../lib/access";
import { getSessionContext } from "../../../lib/session";
import { ConfigurationError, getSupabaseConfig } from "../../../lib/supabase-server";

const TIMEOUT_MS = 80_000;

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  try {
    const permissions = new Set(await getEffectivePermissionCodes(context.profile.user_id));
    if (!permissions.has("exams.perform")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
    const body = await request.json() as Record<string, unknown>;
    const { anonKey, url } = getSupabaseConfig();
    const response = await fetch(`${url}/functions/v1/exam-ai-image`, {
      method: "POST",
      headers: { apikey: anonKey, authorization: `Bearer ${context.accessToken}`, "content-type": "application/json" },
      body: JSON.stringify(body), cache: "no-store", signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    const payload = await response.json().catch(() => null);
    return Response.json(payload ?? { error: "Geração de imagem temporariamente indisponível." }, { status: payload ? response.status : 503, headers: { "cache-control": "private, no-store" } });
  } catch (error) {
    if (error instanceof ConfigurationError) return Response.json({ error: "Geração de imagem temporariamente indisponível." }, { status: 503 });
    if (error instanceof Error && (error.name === "AbortError" || error.name === "TimeoutError")) return Response.json({ error: "A geração demorou além do esperado. Verifique o rascunho antes de tentar novamente." }, { status: 504 });
    return Response.json({ error: error instanceof Error ? error.message : "Não foi possível concluir a operação." }, { status: 400 });
  }
}
