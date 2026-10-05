import { hasAnyPermission } from "../../../lib/access";
import { callHrRpc, HrActionError, isUuid } from "../../../lib/hr-server";
import { getSessionContext } from "../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasAnyPermission(context.profile, ["appointments.manage", "succession.manage"])) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
  try {
    const body = (await request.json()) as Record<string, unknown>;
    const employeeId = typeof body.employeeId === "string" ? body.employeeId : "";
    const positionId = Number(body.positionId);
    const note = typeof body.note === "string" ? body.note.trim() : "";
    if (!isUuid(employeeId) || !Number.isSafeInteger(positionId) || positionId < 1 || note.length < 10 || note.length > 2000) return Response.json({ error: "Informe colaborador, novo cargo e fundamentação." }, { status: 400 });
    const history = await callHrRpc("appoint_staff_position", {
      p_actor_id: context.profile.user_id,
      p_employee_id: employeeId,
      p_note: note,
      p_to_position_id: positionId,
    });
    return Response.json({ history });
  } catch (error) {
    return Response.json({ error: error instanceof HrActionError ? error.message : "Não foi possível registrar a nomeação." }, { status: error instanceof HrActionError ? error.status : 400 });
  }
}
