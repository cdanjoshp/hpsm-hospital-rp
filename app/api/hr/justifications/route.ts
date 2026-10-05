import type { HrHourJustification } from "../../../lib/hr";
import { callHrRpc, HrActionError } from "../../../lib/hr-server";
import { getSessionContext } from "../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (context.profile.role_code === "diretor_geral") {
    return Response.json({ error: "A conta institucional não participa do fechamento semanal." }, { status: 403 });
  }

  try {
    const body = (await request.json()) as { reason?: unknown; weeklyRecordId?: unknown };
    const weeklyRecordId = Number(body.weeklyRecordId);
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";
    if (!Number.isSafeInteger(weeklyRecordId) || weeklyRecordId < 1 || reason.length < 10 || reason.length > 2000) {
      return Response.json({ error: "Informe uma justificativa entre 10 e 2000 caracteres." }, { status: 400 });
    }
    const justification = await callHrRpc<HrHourJustification>("submit_hr_hour_justification", {
      p_actor_id: context.profile.user_id,
      p_reason: reason,
      p_weekly_record_id: weeklyRecordId,
    });
    return Response.json({ justification }, { status: 201 });
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível enviar a justificativa.";
    return Response.json({ error: message }, { status: error instanceof HrActionError ? error.status : 400 });
  }
}
