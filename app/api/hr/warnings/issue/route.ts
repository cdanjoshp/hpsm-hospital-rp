import { hasPermission } from "../../../../lib/access";
import { callHrRpc, HrActionError, isIsoDate, isUuid } from "../../../../lib/hr-server";
import { getSessionContext } from "../../../../lib/session";

const categories = new Set(["weekly_goal", "attendance", "conduct", "internal_rules", "other"]);

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "hr.warnings.issue")) return Response.json({ error: "Você não possui permissão para aplicar advertências." }, { status: 403 });
  try {
    const body = (await request.json()) as { category?: unknown; cycleMonth?: unknown; employeeId?: unknown; reason?: unknown; weeklyRecordId?: unknown };
    const employeeId = typeof body.employeeId === "string" ? body.employeeId : "";
    const category = typeof body.category === "string" ? body.category : "";
    const cycleMonth = typeof body.cycleMonth === "string" ? `${body.cycleMonth.slice(0, 7)}-01` : "";
    const weeklyRecordId = body.weeklyRecordId == null ? null : Number(body.weeklyRecordId);
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";
    if (!isUuid(employeeId) || !categories.has(category) || !isIsoDate(cycleMonth) || reason.length < 10 || reason.length > 1000) {
      return Response.json({ error: "Preencha colaborador, categoria, competência e ocorrência corretamente." }, { status: 400 });
    }
    if (weeklyRecordId !== null && (!Number.isSafeInteger(weeklyRecordId) || weeklyRecordId < 1)) {
      return Response.json({ error: "Fechamento semanal inválido." }, { status: 400 });
    }
    const result = await callHrRpc<Record<string, unknown>>("issue_hr_warning", {
      p_actor_id: context.profile.user_id,
      p_category: category,
      p_cycle_month: cycleMonth,
      p_employee_id: employeeId,
      p_reason: reason,
      p_weekly_record_id: weeklyRecordId,
    });
    return Response.json(result, { status: 201 });
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível aplicar a advertência.";
    return Response.json({ error: message }, { status: error instanceof HrActionError ? error.status : 400 });
  }
}
