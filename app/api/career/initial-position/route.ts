import { hasPermission } from "../../../lib/access";
import { callHrRpc, HrActionError, isUuid } from "../../../lib/hr-server";
import { getSessionContext } from "../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "access.manage")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
  try {
    const body = (await request.json()) as Record<string, unknown>;
    const employeeId = typeof body.employeeId === "string" ? body.employeeId : "";
    if (!isUuid(employeeId)) return Response.json({ error: "Colaborador inválido." }, { status: 400 });
    const history = await callHrRpc("assign_initial_staff_position", { p_actor_id: context.profile.user_id, p_employee_id: employeeId });
    return Response.json({ history });
  } catch (error) {
    return Response.json({ error: error instanceof HrActionError ? error.message : "Não foi possível definir o cargo inicial." }, { status: error instanceof HrActionError ? error.status : 400 });
  }
}
