import { adminRest } from "../../lib/hr-server";
import {
  callProfessionalIdentityGeneration,
  ProfessionalIdentityError,
  type ProfessionalIdentityRow,
} from "../../lib/professional-identity";
import { getSessionBootstrap } from "../../lib/session";
import { callSupabaseUserRpc, SupabaseUserRpcError } from "../../lib/supabase-user";

export async function POST(request: Request) {
  const context = await getSessionBootstrap();
  if (!context || context.profile.must_change_password) return responseError("Sessão expirada.", 401);
  try {
    const body = await request.json() as Record<string, unknown>;
    const action = text(body.action);
    if (action === "ensure") {
      if (context.permissionCodes.includes("sr.directors.view")) return responseError("Esta conta institucional não utiliza identidade profissional médica.", 403);
      const rows = await adminRest<Array<Pick<ProfessionalIdentityRow, "status">>>(
        `professional_identities?select=status&user_id=eq.${context.profile.user_id}&limit=1`,
      );
      if (rows[0]?.status === "active") return Response.json({ status: "active" }, { headers: privateHeaders() });
      const result = await callProfessionalIdentityGeneration(context.accessToken, { action: "ensure" });
      return Response.json(result, { status: result.status === "generating" ? 202 : 200, headers: privateHeaders() });
    }

    if (context.positionLevel !== 14) return responseError("Somente o Diretor Geral pode administrar identidades profissionais.", 403);
    const targetUserId = uuid(body.targetUserId);
    if (!targetUserId) return responseError("Profissional inválido.", 400);
    const reason = text(body.reason).slice(0, 500);

    if (action === "correct-crm") {
      const registrationDate = text(body.registrationDate);
      if (!isoDate(registrationDate) || reason.length < 5) return responseError("Informe a data de registro e o motivo da correção.", 400);
      const result = await callSupabaseUserRpc(context.accessToken, "correct_professional_identity_crm", {
        p_reason: reason,
        p_registration_date: registrationDate,
        p_target_user_id: targetUserId,
      });
      return Response.json({ identity: result }, { headers: privateHeaders() });
    }

    if (action !== "regenerate" && action !== "reprocess") return responseError("Ação inválida.", 400);
    if (reason.length < 5) return responseError("Informe o motivo da regeneração.", 400);
    await callSupabaseUserRpc(context.accessToken,
      action === "reprocess" ? "unlock_professional_identity_reprocess" : "prepare_professional_identity_regeneration",
      { p_reason: reason, p_target_user_id: targetUserId },
    );
    const result = await callProfessionalIdentityGeneration(context.accessToken, { action, reason, targetUserId });
    return Response.json(result, { status: result.status === "generating" ? 202 : 200, headers: privateHeaders() });
  } catch (error) {
    if (error instanceof ProfessionalIdentityError || error instanceof SupabaseUserRpcError) {
      return responseError(error instanceof ProfessionalIdentityError ? error.message : "A operação foi recusada pelo banco.", error.status);
    }
    return responseError("Não foi possível concluir a operação de identidade.", 500);
  }
}

function text(value: unknown) { return typeof value === "string" ? value.trim() : ""; }
function uuid(value: unknown) { const result = text(value); return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(result) ? result.toLowerCase() : ""; }
function isoDate(value: string) { if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false; const parsed = new Date(`${value}T00:00:00Z`); return !Number.isNaN(parsed.valueOf()) && parsed.toISOString().slice(0, 10) === value; }
function privateHeaders() { return { "cache-control": "private, no-store", "x-content-type-options": "nosniff" }; }
function responseError(error: string, status: number) { return Response.json({ error }, { status, headers: privateHeaders() }); }
