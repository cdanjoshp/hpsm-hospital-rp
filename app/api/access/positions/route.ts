import { callAccessRpc, hasPermission, type StaffPosition } from "../../../lib/access";
import { HrActionError } from "../../../lib/hr-server";
import { getSessionContext } from "../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "access.manage")) {
    return Response.json({ error: "Você não possui permissão para configurar cargos." }, { status: 403 });
  }
  try {
    const body = (await request.json()) as Record<string, unknown>;
    const action = body.action;
    if (action === "create") {
      return Response.json({ error: "A hierarquia utiliza somente os 14 cargos oficiais." }, { status: 409 });
    }
    if (action === "permissions") {
      const positionId = Number(body.positionId);
      const permissionCodes = Array.isArray(body.permissionCodes)
        ? body.permissionCodes.filter((value): value is string => typeof value === "string")
        : null;
      if (!Number.isSafeInteger(positionId) || positionId < 1 || !permissionCodes) {
        return Response.json({ error: "Cargo ou permissões inválidas." }, { status: 400 });
      }
      const result = await callAccessRpc<Record<string, unknown>>("set_staff_position_permissions", {
        p_actor_id: context.profile.user_id,
        p_permission_codes: permissionCodes,
        p_position_id: positionId,
      });
      return Response.json({ result });
    }
    if (action === "update") {
      const positionId = Number(body.positionId);
      const name = typeof body.name === "string" ? body.name.trim() : "";
      if (!Number.isSafeInteger(positionId) || positionId < 1 || name.length < 2 || name.length > 80 || typeof body.active !== "boolean") {
        return Response.json({ error: "Dados do cargo inválidos." }, { status: 400 });
      }
      const position = await callAccessRpc<StaffPosition>("update_staff_position", {
        p_active: body.active,
        p_actor_id: context.profile.user_id,
        p_name: name,
        p_position_id: positionId,
      });
      return Response.json({ position });
    }
    return Response.json({ error: "Ação inválida." }, { status: 400 });
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível atualizar os cargos.";
    return Response.json({ error: message }, { status: error instanceof HrActionError ? error.status : 400 });
  }
}
