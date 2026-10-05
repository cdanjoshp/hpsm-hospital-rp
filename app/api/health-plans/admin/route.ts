import { getSessionBootstrap } from "../../../lib/session";
import { callSupabaseUserRpc, SupabaseUserRpcError } from "../../../lib/supabase-user";

type AdminPlanInput = {
  patientId?: unknown;
  validUntil?: unknown;
};

type AdminPlanResult = {
  action: "expiry_adjustment" | "grant";
  activated_at: string;
  authorized_by: string;
  authorized_by_name: string;
  financial_value: number;
  id: number;
  status: "active";
  valid_until: string;
};

export async function POST(request: Request) {
  const context = await getSessionBootstrap();
  if (!context || context.profile.must_change_password) return responseError("Sessão expirada.", 401);
  if (
    context.positionLevel === null
    || context.positionLevel < 11
    || context.positionLevel > 14
    || !context.permissionCodes.includes("healthplans.review")
  ) {
    return responseError("Somente os cargos 11 a 14 podem conceder ou ajustar o Plano de Saúde.", 403);
  }

  try {
    const body = await request.json() as AdminPlanInput;
    const patientId = Number(body.patientId);
    const validUntil = typeof body.validUntil === "string" ? body.validUntil.trim() : "";
    if (!Number.isSafeInteger(patientId) || patientId < 1) return responseError("Selecione um paciente válido.", 400);
    if (!isoDate(validUntil)) return responseError("Informe uma data de vencimento válida.", 400);

    const result = await callSupabaseUserRpc<AdminPlanResult>(context.accessToken, "admin_set_patient_health_plan", {
      p_patient_id: patientId,
      p_valid_until: validUntil,
    });
    return Response.json({
      action: result.action,
      activatedAt: result.activated_at,
      authorizedBy: result.authorized_by,
      authorizedByName: result.authorized_by_name,
      financialValue: Number(result.financial_value),
      id: Number(result.id),
      status: result.status,
      validUntil: result.valid_until,
    }, { headers: privateHeaders() });
  } catch (error) {
    if (error instanceof SupabaseUserRpcError) {
      const status = error.code === "42501" || error.status === 403 ? 403
        : error.code === "P0002" || error.status === 404 ? 404
          : error.code === "P0001" ? 409 : 400;
      return responseError(error.rpcMessage ?? "Não foi possível conceder ou ajustar o plano.", status);
    }
    return responseError("Não foi possível conceder ou ajustar o plano.", 500);
  }
}

function isoDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(parsed.valueOf()) && parsed.toISOString().slice(0, 10) === value;
}

function privateHeaders() { return { "cache-control": "private, no-store", "x-content-type-options": "nosniff" }; }
function responseError(error: string, status: number) { return Response.json({ error }, { status, headers: privateHeaders() }); }
