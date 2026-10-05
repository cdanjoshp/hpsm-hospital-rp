import { hasPermission } from "../../../lib/access";
import { authenticatedHeaders } from "../../../lib/operational-data";
import { getSessionContext } from "../../../lib/session";
import { getSupabaseConfig } from "../../../lib/supabase-server";

type ReviewInput = {
  decision?: unknown;
  reason?: unknown;
  requestId?: unknown;
};

type ReviewResult = {
  already_reviewed: boolean;
  id: number;
  status: "approved" | "rejected";
  valid_until: string | null;
};

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "healthplans.review")) {
    return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
  }

  try {
    const body = (await request.json()) as ReviewInput;
    const requestId = Number(body.requestId);
    const decision = body.decision;
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";
    if (
      !Number.isSafeInteger(requestId) || requestId < 1 ||
      (decision !== "approved" && decision !== "rejected") ||
      (decision === "rejected" && (reason.length < 10 || reason.length > 2000))
    ) {
      return Response.json({ error: "Revise a decisão e o motivo informado." }, { status: 400 });
    }

    const { url } = getSupabaseConfig();
    const response = await fetch(`${url}/rest/v1/rpc/review_patient_health_plan_request`, {
      method: "POST",
      signal: AbortSignal.timeout(15_000),
      headers: authenticatedHeaders(context.accessToken),
      body: JSON.stringify({
        p_request_id: requestId,
        p_decision: decision,
        p_reason: decision === "rejected" ? reason : null,
      }),
    });
    if (!response.ok) {
      const status = response.status === 404 ? 404 : response.status === 409 ? 409 : 400;
      return Response.json({ error: "A solicitação não existe ou já recebeu outra decisão." }, { status });
    }
    const result = (await response.json()) as ReviewResult;
    return Response.json({
      alreadyReviewed: result.already_reviewed,
      id: result.id,
      status: result.status,
      validUntil: result.valid_until,
    });
  } catch {
    return Response.json({ error: "Não foi possível registrar a decisão do plano." }, { status: 500 });
  }
}
