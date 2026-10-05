import { getSessionContext } from "../../../lib/session";
import type { HrAbsenceRequest } from "../../../lib/hr";
import { callHrRpc, HrActionError, isIsoDate } from "../../../lib/hr-server";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (context.profile.role_code === "diretor_geral") {
    return Response.json({ error: "A conta institucional do Diretor Geral não participa da meta semanal." }, { status: 403 });
  }

  try {
    const body = (await request.json()) as { endDate?: unknown; observation?: unknown; reason?: unknown; startDate?: unknown };
    const startDate = typeof body.startDate === "string" ? body.startDate : "";
    const endDate = typeof body.endDate === "string" ? body.endDate : "";
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";
    const observation = typeof body.observation === "string" ? body.observation.trim() : "";
    if (!isIsoDate(startDate) || !isIsoDate(endDate) || endDate < startDate) {
      return Response.json({ error: "Informe um período válido." }, { status: 400 });
    }
    const duration = Math.round((Date.parse(`${endDate}T00:00:00Z`) - Date.parse(`${startDate}T00:00:00Z`)) / 86400000) + 1;
    if (duration > 90 || reason.length < 10 || reason.length > 2000 || (observation.length === 1 || observation.length > 2000)) {
      return Response.json({ error: "O período deve ter até 90 dias e o motivo entre 10 e 2000 caracteres." }, { status: 400 });
    }

    const absence = await callHrRpc<HrAbsenceRequest>("create_hr_leave_request", {
      p_actor_id: context.profile.user_id,
      p_end_date: endDate,
      p_observation: observation || null,
      p_reason: reason,
      p_start_date: startDate,
    });
    return Response.json({ absence }, { status: 201 });
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível solicitar o afastamento.";
    return Response.json({ error: message }, { status: 400 });
  }
}

export async function PATCH(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });

  try {
    const body = (await request.json()) as { requestId?: unknown };
    const requestId = Number(body.requestId);
    if (!Number.isSafeInteger(requestId) || requestId < 1) {
      return Response.json({ error: "Solicitação inválida." }, { status: 400 });
    }
    const absence = await callHrRpc<HrAbsenceRequest>("cancel_hr_leave_request", {
      p_actor_id: context.profile.user_id,
      p_request_id: requestId,
    });
    return Response.json({ absence });
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível cancelar a solicitação.";
    return Response.json({ error: message }, { status: 400 });
  }
}
