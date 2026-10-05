import { hasPermission } from "../../../../lib/access";
import type { HrAbsenceRequest } from "../../../../lib/hr";
import { callHrRpc, HrActionError } from "../../../../lib/hr-server";
import { getSessionContext } from "../../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "hr.absences.review")) return Response.json({ error: "Você não possui permissão para analisar afastamentos." }, { status: 403 });

  try {
    const body = (await request.json()) as { adjustments?: unknown; decision?: unknown; note?: unknown; requestId?: unknown };
    const requestId = Number(body.requestId);
    const decision = body.decision;
    const note = typeof body.note === "string" ? body.note.trim() : "";
    const adjustments = Array.isArray(body.adjustments) ? body.adjustments : [];
    if (!Number.isSafeInteger(requestId) || requestId < 1 || (decision !== "approved" && decision !== "rejected")) {
      return Response.json({ error: "Decisão inválida." }, { status: 400 });
    }
    if (decision === "approved" && !adjustments.length) {
      return Response.json({ error: "Informe as horas abatidas em cada semana afetada." }, { status: 400 });
    }
    if (decision === "rejected" && (note.length < 10 || note.length > 2000)) {
      return Response.json({ error: "Informe o motivo da recusa entre 10 e 2000 caracteres." }, { status: 400 });
    }
    if (decision === "approved" && note.length === 1) {
      return Response.json({ error: "A observação deve ter ao menos 2 caracteres ou permanecer vazia." }, { status: 400 });
    }

    const result = await callHrRpc<{ deducted_minutes: number; leave: HrAbsenceRequest }>("review_hr_leave_request", {
      p_request_id: requestId,
      p_decision: decision,
      p_adjustments: decision === "approved" ? adjustments : [],
      p_note: note || null,
      p_actor_id: context.profile.user_id,
    });
    return Response.json(result);
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível registrar a decisão.";
    return Response.json({ error: message }, { status: 400 });
  }
}
