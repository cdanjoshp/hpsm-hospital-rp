import { dashboardInactiveWidgetIds, validateDashboardPreference } from "../../lib/dashboard-customization";
import { getSessionBootstrap } from "../../lib/session";
import { callSupabaseUserRpc, SupabaseUserRpcError } from "../../lib/supabase-user";

const PRIVATE_HEADERS = { "cache-control": "private, no-store, max-age=0", vary: "Cookie" };
const MAX_BODY_BYTES = 32 * 1024;

export async function POST(request: Request) {
  const bootstrap = await getSessionBootstrap();
  if (!bootstrap || bootstrap.profile.must_change_password) return Response.json({ error: "Sessão inválida ou expirada." }, { headers: PRIVATE_HEADERS, status: 401 });

  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > MAX_BODY_BYTES) {
    return Response.json({ error: "Configuração do Dashboard muito grande." }, { headers: PRIVATE_HEADERS, status: 413 });
  }

  try {
    const raw = await request.text();
    if (new TextEncoder().encode(raw).byteLength > MAX_BODY_BYTES) {
      return Response.json({ error: "Configuração do Dashboard muito grande." }, { headers: PRIVATE_HEADERS, status: 413 });
    }
    const body: unknown = JSON.parse(raw);
    const validation = validateDashboardPreference(body, dashboardInactiveWidgetIds(bootstrap.permissionCodes));
    if (!validation.valid) {
      return Response.json({ error: validation.error }, { headers: PRIVATE_HEADERS, status: 400 });
    }
    const saved = await callSupabaseUserRpc(bootstrap.accessToken, "save_dashboard_preferences", { p_config: body });
    return Response.json({ preferences: saved }, { headers: PRIVATE_HEADERS });
  } catch (error) {
    if (error instanceof SyntaxError) {
      return Response.json({ error: "A configuração recebida está corrompida e não pôde ser lida. Recarregue a Dashboard e tente novamente." }, { headers: PRIVATE_HEADERS, status: 400 });
    }
    const status = error instanceof SupabaseUserRpcError && error.status === 400 ? 400 : 503;
    const databaseMessage = error instanceof SupabaseUserRpcError && error.code === "22023" && error.rpcMessage
      ? error.rpcMessage === "Configuração do Dashboard inválida."
        ? "O banco recusou a organização atual dos quadros. Recarregue a Dashboard ou use “Restaurar padrão” antes de tentar novamente."
        : error.rpcMessage
      : null;
    return Response.json({ error: status === 400 ? databaseMessage ?? "O banco recusou os dados enviados pela Dashboard. Recarregue a página e tente novamente." : "Não foi possível salvar seu Dashboard agora." }, {
      headers: PRIVATE_HEADERS,
      status,
    });
  }
}
