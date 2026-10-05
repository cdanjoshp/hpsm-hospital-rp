import { hasPermission } from "../../../lib/access";
import { callHrRpc, HrActionError } from "../../../lib/hr-server";
import { getSessionContext } from "../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "hr.warnings.progression")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
  try {
    const body = (await request.json()) as Record<string, unknown>;
    const warningId = Number(body.warningId);
    const note = typeof body.note === "string" ? body.note.trim() : "";
    if (!Number.isSafeInteger(warningId) || warningId < 1 || typeof body.impacts !== "boolean" || note.length > 1000) return Response.json({ error: "Dados inválidos." }, { status: 400 });
    const warning = await callHrRpc("set_warning_progression_impact", {
      p_actor_id: context.profile.user_id,
      p_impacts: body.impacts,
      p_note: note || null,
      p_warning_id: warningId,
    });
    return Response.json({ warning });
  } catch (error) {
    return Response.json({ error: error instanceof HrActionError ? error.message : "Não foi possível alterar o impacto da advertência." }, { status: error instanceof HrActionError ? error.status : 400 });
  }
}
