import { hasPermission } from "../../../lib/access";
import { callHrRpc, HrActionError } from "../../../lib/hr-server";
import { getSessionContext } from "../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "progression.review")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
  try {
    const body = (await request.json()) as Record<string, unknown>;
    if (body.action === "refresh") {
      const result = await callHrRpc("refresh_staff_promotion_reviews", { p_actor_id: context.profile.user_id });
      return Response.json({ result });
    }
    const reviewId = Number(body.reviewId);
    const decision = body.decision === "promoted" ? "promoted" : body.decision === "deferred" ? "deferred" : "";
    const note = typeof body.note === "string" ? body.note.trim() : "";
    if (!Number.isSafeInteger(reviewId) || reviewId < 1 || !decision || note.length > 2000) return Response.json({ error: "Decisão inválida." }, { status: 400 });
    const review = await callHrRpc("decide_staff_promotion_review", {
      p_actor_id: context.profile.user_id,
      p_decision: decision,
      p_note: note || null,
      p_review_id: reviewId,
    });
    return Response.json({ review });
  } catch (error) {
    return actionError(error, "Não foi possível registrar a decisão de promoção.");
  }
}

function actionError(error: unknown, fallback: string) {
  return Response.json({ error: error instanceof HrActionError ? error.message : fallback }, { status: error instanceof HrActionError ? error.status : 400 });
}
