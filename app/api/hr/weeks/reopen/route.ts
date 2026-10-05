import { hasPermission } from "../../../../lib/access";
import { callHrRpc, HrActionError, isIsoDate } from "../../../../lib/hr-server";
import { getSessionContext } from "../../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "hr.weeks.reopen")) return Response.json({ error: "Você não possui permissão para reabrir semanas." }, { status: 403 });
  try {
    const body = (await request.json()) as { reason?: unknown; weekStart?: unknown };
    const weekStart = typeof body.weekStart === "string" ? body.weekStart : "";
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";
    if (!isIsoDate(weekStart) || reason.length < 10 || reason.length > 2000) {
      return Response.json({ error: "Informe a semana e o motivo da reabertura entre 10 e 2000 caracteres." }, { status: 400 });
    }
    const result = await callHrRpc<Record<string, unknown>>("reopen_hr_week_closure", {
      p_actor_id: context.profile.user_id,
      p_reason: reason,
      p_week_start: weekStart,
    });
    return Response.json(result);
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível reabrir a semana.";
    return Response.json({ error: message }, { status: error instanceof HrActionError ? error.status : 400 });
  }
}
