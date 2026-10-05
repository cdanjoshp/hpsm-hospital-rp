import { hasPermission } from "../../../../lib/access";
import { calculateWorkedMinutes, HR_HOUR_SNAPSHOT_SELECT } from "../../../../lib/hr";
import type { HrHourSnapshot } from "../../../../lib/hr";
import { adminRest, callHrRpc, HrActionError, isIsoDate, isUuid } from "../../../../lib/hr-server";
import { getSessionContext } from "../../../../lib/session";

type CloseResult = {
  active_warnings: number;
  status: string;
  suspended: boolean;
  warning_id: number | null;
  weekly_record_id: number;
};

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "hr.weeks.close")) return Response.json({ error: "Você não possui permissão para apurar semanas." }, { status: 403 });

  try {
    const body = (await request.json()) as { employeeId?: unknown; note?: unknown; weekStart?: unknown };
    const employeeId = typeof body.employeeId === "string" ? body.employeeId : "";
    const weekStart = typeof body.weekStart === "string" ? body.weekStart : "";
    const note = typeof body.note === "string" ? body.note.trim() : "";
    if (!isUuid(employeeId) || !isIsoDate(weekStart)) {
      return Response.json({ error: "Informe o colaborador e uma semana válida." }, { status: 400 });
    }

    const snapshots = await adminRest<HrHourSnapshot[]>(
      `rh_hour_snapshots?select=${HR_HOUR_SNAPSHOT_SELECT}&employee_id=eq.${encodeURIComponent(employeeId)}&order=reading_date.asc`,
    );
    const calculation = calculateWorkedMinutes(snapshots, weekStart, addDays(weekStart, 6));
    if (!calculation.complete) {
      return Response.json({ error: "Faltam leituras mensais para calcular esta semana com segurança." }, { status: 400 });
    }
    const relevantSnapshotIds = snapshots
      .filter((snapshot) => snapshot.reading_date <= addDays(weekStart, 6))
      .map((snapshot) => snapshot.id);

    const result = await callHrRpc<CloseResult>("close_hr_week", {
      p_employee_id: employeeId,
      p_week_start: weekStart,
      p_worked_minutes: calculation.workedMinutes,
      p_calculation_details: {
        baseline_minutes: calculation.baselineMinutes,
        latest_update: calculation.latestUpdate,
        snapshot_ids: relevantSnapshotIds,
      },
      p_closure_note: note || null,
      p_actor_id: context.profile.user_id,
    });
    return Response.json({ result });
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível fechar a semana.";
    return Response.json({ error: message }, { status: 400 });
  }
}

function addDays(date: string, days: number) {
  const parsed = new Date(`${date}T00:00:00.000Z`);
  parsed.setUTCDate(parsed.getUTCDate() + days);
  return parsed.toISOString().slice(0, 10);
}
