import { hasPermission } from "../../../lib/access";
import type { HrHourSnapshot } from "../../../lib/hr";
import { parseDuration } from "../../../lib/hr";
import { callHrRpc, isIsoDate, isUuid } from "../../../lib/hr-server";
import { getSessionContext } from "../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "hr.hours.import")) return Response.json({ error: "Você não possui permissão para lançar horas." }, { status: 403 });

  try {
    const body = (await request.json()) as {
      employeeId?: unknown;
      note?: unknown;
      readingDate?: unknown;
      referenceMonth?: unknown;
      total?: unknown;
    };
    const employeeId = typeof body.employeeId === "string" ? body.employeeId : "";
    const readingDate = typeof body.readingDate === "string" ? body.readingDate : "";
    const monthValue = typeof body.referenceMonth === "string" ? body.referenceMonth : "";
    const referenceMonth = /^\d{4}-\d{2}$/.test(monthValue) ? `${monthValue}-01` : "";
    const total = typeof body.total === "string" ? parseDuration(body.total) : NaN;
    const note = typeof body.note === "string" ? body.note.trim() : "";
    if (!isUuid(employeeId) || !isIsoDate(readingDate) || !isIsoDate(referenceMonth) || !Number.isFinite(total)) {
      return Response.json({ error: "Preencha corretamente o colaborador, competência, data e acumulado." }, { status: 400 });
    }

    const snapshot = await callHrRpc<HrHourSnapshot>("record_hr_hour_snapshot", {
      p_employee_id: employeeId,
      p_reference_month: referenceMonth,
      p_reading_date: readingDate,
      p_total_minutes: total,
      p_note: note || null,
      p_actor_id: context.profile.user_id,
    });
    return Response.json({ snapshot });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Não foi possível registrar as horas.";
    return Response.json({ error: message }, { status: 400 });
  }
}
