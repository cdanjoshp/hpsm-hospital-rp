import { hasPermission } from "../../../../lib/access";
import { callHrRpc, HrActionError } from "../../../../lib/hr-server";
import { getSessionContext } from "../../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "hr.warnings.annul")) return Response.json({ error: "Você não possui permissão para anular advertências." }, { status: 403 });

  try {
    const body = (await request.json()) as { reason?: unknown; warningId?: unknown };
    const warningId = Number(body.warningId);
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";
    if (!Number.isSafeInteger(warningId) || warningId < 1 || reason.length < 10 || reason.length > 2000) {
      return Response.json({ error: "Informe uma advertência e um motivo entre 10 e 2000 caracteres." }, { status: 400 });
    }
    const result = await callHrRpc<Record<string, unknown>>("annul_hr_warning", {
      p_warning_id: warningId,
      p_reason: reason,
      p_actor_id: context.profile.user_id,
    });
    return Response.json({ result });
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível anular a advertência.";
    return Response.json({ error: message }, { status: 400 });
  }
}
