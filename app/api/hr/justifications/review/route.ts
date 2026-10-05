import { hasPermission } from "../../../../lib/access";
import type { HrHourJustification } from "../../../../lib/hr";
import { callHrRpc, HrActionError } from "../../../../lib/hr-server";
import { getSessionContext } from "../../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "hr.justifications.review")) return Response.json({ error: "Você não possui permissão para analisar justificativas." }, { status: 403 });

  try {
    const body = (await request.json()) as { creditedMinutes?: unknown; decision?: unknown; justificationId?: unknown; note?: unknown };
    const justificationId = Number(body.justificationId);
    const decision = body.decision;
    const creditedMinutes = Number(body.creditedMinutes);
    const note = typeof body.note === "string" ? body.note.trim() : "";
    if (!Number.isSafeInteger(justificationId) || justificationId < 1 || (decision !== "approved" && decision !== "rejected")) {
      return Response.json({ error: "Decisão inválida." }, { status: 400 });
    }
    if (decision === "approved" && (!Number.isSafeInteger(creditedMinutes) || creditedMinutes < 1)) {
      return Response.json({ error: "Informe quantas horas serão abonadas." }, { status: 400 });
    }
    if (decision === "rejected" && (note.length < 10 || note.length > 2000)) {
      return Response.json({ error: "Informe o motivo da recusa entre 10 e 2000 caracteres." }, { status: 400 });
    }
    const result = await callHrRpc<{ justification: HrHourJustification; remaining_deficit_minutes: number }>("review_hr_hour_justification", {
      p_actor_id: context.profile.user_id,
      p_credited_minutes: decision === "approved" ? creditedMinutes : 0,
      p_decision: decision,
      p_justification_id: justificationId,
      p_note: note || null,
    });
    return Response.json(result);
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível registrar a decisão.";
    return Response.json({ error: message }, { status: error instanceof HrActionError ? error.status : 400 });
  }
}
