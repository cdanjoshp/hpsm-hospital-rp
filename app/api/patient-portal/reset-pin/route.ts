import { getSessionBootstrap } from "../../../lib/session";
import { callSupabaseUserRpc, SupabaseUserRpcError } from "../../../lib/supabase-user";

type ResetResult = {
  credential_removed?: boolean;
  ok?: boolean;
  sessions_revoked?: number;
};

export async function POST(request: Request) {
  const context = await getSessionBootstrap();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (context.positionLevel === null || context.positionLevel < 11 || context.positionLevel > 14) {
    return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
  }

  try {
    const body = await request.json() as Record<string, unknown>;
    if (Object.keys(body).some((key) => key !== "patientId")) {
      return Response.json({ error: "Operação inválida." }, { status: 400 });
    }
    const patientId = Number(body.patientId);
    if (!Number.isSafeInteger(patientId) || patientId < 1) {
      return Response.json({ error: "Paciente inválido." }, { status: 400 });
    }
    const result = await callSupabaseUserRpc<ResetResult>(context.accessToken, "reset_patient_portal_pin", {
      p_patient_id: patientId,
    });
    if (result.ok !== true) throw new Error("reset_failed");
    return Response.json({
      credentialRemoved: result.credential_removed === true,
      ok: true,
      sessionsRevoked: Math.max(0, Number(result.sessions_revoked) || 0),
    });
  } catch (error) {
    if (error instanceof SupabaseUserRpcError) {
      const status = error.status === 401 || error.status === 403 ? error.status : 400;
      return Response.json({ error: error.rpcMessage ?? "Não foi possível redefinir o PIN." }, { status });
    }
    return Response.json({ error: "Não foi possível redefinir o PIN." }, { status: 400 });
  }
}
