import { hasPermission } from "../../../../lib/access";
import { callHrRpc, HrActionError, isIsoDate } from "../../../../lib/hr-server";
import { getSessionContext } from "../../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "hr.weeks.close")) return Response.json({ error: "Você não possui permissão para fechar semanas." }, { status: 403 });
  try {
    const body = (await request.json()) as { weekStart?: unknown };
    const weekStart = typeof body.weekStart === "string" ? body.weekStart : "";
    if (!isIsoDate(weekStart)) return Response.json({ error: "Semana inválida." }, { status: 400 });
    const result = await callHrRpc<Record<string, unknown>>("finalize_hr_week_closure", {
      p_actor_id: context.profile.user_id,
      p_week_start: weekStart,
    });
    return Response.json(result);
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível confirmar o fechamento.";
    return Response.json({ error: message }, { status: error instanceof HrActionError ? error.status : 400 });
  }
}
