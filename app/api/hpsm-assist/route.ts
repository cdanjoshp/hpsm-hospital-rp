import { getSessionBootstrap } from "../../lib/session";
import { getSupabaseConfig } from "../../lib/supabase-server";

export async function POST(request: Request) {
  const context = await getSessionBootstrap();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!context.permissionCodes.includes("hpsm.assist.use")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
  try {
    if (Number(request.headers.get("content-length") ?? 0) > 16_000) return Response.json({ error: "Relato muito longo." }, { status: 413 });
    const body = await request.json() as Record<string, unknown>;
    const caseText = typeof body.caseText === "string" ? body.caseText.trim() : "";
    const pain = body.pain === null || body.pain === undefined ? null : body.pain;
    if (caseText.length < 20 || caseText.length > 6_000 || (pain !== null && (!Number.isInteger(pain) || Number(pain) < 0 || Number(pain) > 10))) {
      return Response.json({ error: "Descreva o caso com pelo menos 20 caracteres e informe dor de 0 a 10, se aplicável." }, { status: 400 });
    }
    const { anonKey, url } = getSupabaseConfig();
    const response = await fetch(`${url}/functions/v1/hpsm-assist`, {
      method: "POST",
      headers: { apikey: anonKey, authorization: `Bearer ${context.accessToken}`, "content-type": "application/json" },
      body: JSON.stringify({ action: "HPSM_ASSIST_ANALYSIS", caseText, pain }),
      cache: "no-store", signal: AbortSignal.timeout(120_000),
    });
    const payload = await response.json().catch(() => null);
    return Response.json(payload ?? { error: "Não foi possível analisar o caso. Tente novamente." }, {
      status: payload ? response.status : 503, headers: { "cache-control": "private, no-store" },
    });
  } catch {
    return Response.json({ error: "Não foi possível analisar o caso. Tente novamente." }, {
      status: 503, headers: { "cache-control": "private, no-store" },
    });
  }
}
