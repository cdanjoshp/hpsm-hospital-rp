import { callAccessRpc, hasPermission, type UserPermissionGrant } from "../../../lib/access";
import { HrActionError } from "../../../lib/hr-server";
import { getSessionContext } from "../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "access.grants.manage")) {
    return Response.json({ error: "Você não possui permissão para conceder acessos." }, { status: 403 });
  }
  try {
    const body = (await request.json()) as Record<string, unknown>;
    if (body.action === "grant") {
      const userId = typeof body.userId === "string" ? body.userId : "";
      const permissionCode = typeof body.permissionCode === "string" ? body.permissionCode : "";
      const grantKind = body.grantKind === "temporary" ? "temporary" : body.grantKind === "individual" ? "individual" : "";
      const expiresAt = typeof body.expiresAt === "string" ? body.expiresAt : null;
      const reason = typeof body.reason === "string" ? body.reason.trim() : "";
      if (!isUuid(userId) || !permissionCode || !grantKind || (grantKind === "temporary" && (!expiresAt || !validDate(expiresAt))) || reason.length > 1000) {
        return Response.json({ error: "Confira o profissional, a permissão e a validade." }, { status: 400 });
      }
      const grant = await callAccessRpc<UserPermissionGrant>("grant_user_permission", {
        p_actor_id: context.profile.user_id,
        p_expires_at: expiresAt ? new Date(expiresAt).toISOString() : null,
        p_grant_kind: grantKind,
        p_permission_code: permissionCode,
        p_reason: reason || null,
        p_user_id: userId,
        p_valid_from: null,
      });
      return Response.json({ grant });
    }
    if (body.action === "revoke") {
      const grantId = Number(body.grantId);
      const reason = typeof body.reason === "string" ? body.reason.trim() : "";
      if (!Number.isSafeInteger(grantId) || grantId < 1 || reason.length < 10) {
        return Response.json({ error: "Informe uma justificativa para encerrar o acesso." }, { status: 400 });
      }
      const grant = await callAccessRpc<UserPermissionGrant>("revoke_temporary_permission", {
        p_actor_id: context.profile.user_id,
        p_grant_id: grantId,
        p_reason: reason,
      });
      return Response.json({ grant });
    }
    return Response.json({ error: "Ação inválida." }, { status: 400 });
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível atualizar o acesso temporário.";
    return Response.json({ error: message }, { status: error instanceof HrActionError ? error.status : 400 });
  }
}

function validDate(value: string) { const parsed = new Date(value); return value.length >= 16 && !Number.isNaN(parsed.valueOf()) && parsed.getTime() > Date.now(); }
function isUuid(value: string) { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
