import { hasPermission } from "../../../../lib/access";
import type { HrDisciplinaryReview } from "../../../../lib/hr";
import { callHrRpc, HrActionError } from "../../../../lib/hr-server";
import { getSessionContext } from "../../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "hr.discipline.review")) return Response.json({ error: "Você não possui permissão para concluir análises disciplinares." }, { status: 403 });

  try {
    const body = (await request.json()) as { decision?: unknown; note?: unknown; reviewId?: unknown };
    const reviewId = Number(body.reviewId);
    const decision = body.decision;
    const note = typeof body.note === "string" ? body.note.trim() : "";
    if (
      !Number.isSafeInteger(reviewId) || reviewId < 1
      || (decision !== "maintain_suspension" && decision !== "dismiss")
      || note.length < 10 || note.length > 2000
    ) {
      return Response.json({ error: "Informe a decisão e uma fundamentação entre 10 e 2000 caracteres." }, { status: 400 });
    }
    const review = await callHrRpc<HrDisciplinaryReview>("decide_hr_disciplinary_review", {
      p_review_id: reviewId,
      p_decision: decision,
      p_note: note,
      p_actor_id: context.profile.user_id,
    });
    return Response.json({ review });
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível concluir a análise.";
    return Response.json({ error: message }, { status: 400 });
  }
}
