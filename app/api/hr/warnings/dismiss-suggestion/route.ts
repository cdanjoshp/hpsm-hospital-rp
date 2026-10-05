import { hasPermission } from "../../../../lib/access";
import { callHrRpc, HrActionError } from "../../../../lib/hr-server";
import { getSessionContext } from "../../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "hr.warnings.issue")) {
    return Response.json({ error: "Você não possui permissão para excluir sugestões de ADV." }, { status: 403 });
  }
  try {
    const body = (await request.json()) as { weeklyRecordId?: unknown; note?: unknown };
    const weeklyRecordId = Number(body.weeklyRecordId);
    const note = typeof body.note === "string" ? body.note.trim() : "";
    if (!Number.isSafeInteger(weeklyRecordId) || weeklyRecordId < 1 || note.length > 500) {
      return Response.json({ error: "Informe um fechamento válido e um motivo de até 500 caracteres." }, { status: 400 });
    }
    const result = await callHrRpc<{ weekly_record_id: number; dismissed: boolean }>("dismiss_hr_warning_suggestion", {
      p_actor_id: context.profile.user_id,
      p_note: note,
      p_weekly_record_id: weeklyRecordId,
    });
    return Response.json(result);
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível excluir a sugestão de ADV.";
    return Response.json({ error: message }, { status: error instanceof HrActionError ? error.status : 400 });
  }
}
