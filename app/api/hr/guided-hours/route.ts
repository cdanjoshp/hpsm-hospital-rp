import { hasPermission } from "../../../lib/access";
import { calculateWorkedMinutes, HR_HOUR_SNAPSHOT_SELECT, type HrHourSnapshot } from "../../../lib/hr";
import { addIsoDays, clockValueToMinutes, getGuidedWeekSegments, isoMonthStart } from "../../../lib/hr-guided";
import { adminRest, callHrRpc, HrActionError, isIsoDate, isUuid } from "../../../lib/hr-server";
import { getSessionContext } from "../../../lib/session";

type EntryInput = {
  employeeId?: unknown;
  readings?: unknown;
};

type ReadingInput = {
  date?: unknown;
  minutes?: unknown;
  referenceMonth?: unknown;
};

type CloseResult = {
  status: string;
};

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "hr.hours.import")) return Response.json({ error: "Você não possui permissão para gerenciar horas." }, { status: 403 });

  try {
    const body = (await request.json()) as { action?: unknown; entries?: unknown; weekStart?: unknown };
    const action = body.action;
    const weekStart = typeof body.weekStart === "string" ? body.weekStart : "";
    const entries = Array.isArray(body.entries) ? body.entries as EntryInput[] : [];
    const today = todayInSaoPaulo();
    const currentWeek = mondayOf(today);
    const weekEnd = addIsoDays(weekStart, 6);
    if ((action !== "update" && action !== "close") || !isIsoDate(weekStart) || mondayOf(weekStart) !== weekStart) {
      return Response.json({ error: "Selecione uma semana válida, iniciada na segunda-feira." }, { status: 400 });
    }
    if (!entries.length || entries.length > 250) {
      return Response.json({ error: "Nenhum profissional válido foi informado." }, { status: 400 });
    }
    if (action === "update" && weekStart !== currentWeek) {
      return Response.json({ error: "Atualizações sem fechamento são permitidas apenas na semana atual." }, { status: 400 });
    }
    if (action === "close" && weekEnd > today) {
      return Response.json({ error: "Esta semana ainda não terminou." }, { status: 400 });
    }

    const throughDate = action === "close" ? weekEnd : today;
    const allowedDates = new Set(getGuidedWeekSegments(weekStart, throughDate).flatMap((segment) => (
      segment.baselineDate ? [segment.baselineDate, segment.endDate] : [segment.endDate]
    )));
    const seenEmployees = new Set<string>();
    const normalized = entries.map((entry) => normalizeEntry(entry, allowedDates, seenEmployees, action === "close"));
    const results: Array<{ employeeId: string; error?: string; status?: string }> = [];

    for (const entry of normalized) {
      try {
        for (const reading of entry.readings.sort((a, b) => a.date.localeCompare(b.date))) {
          await callHrRpc<HrHourSnapshot>("record_hr_hour_snapshot", {
            p_actor_id: context.profile.user_id,
            p_employee_id: entry.employeeId,
            p_note: action === "close" ? `Fechamento guiado da semana ${weekStart}.` : `Atualização guiada da semana ${weekStart}.`,
            p_reading_date: reading.date,
            p_reference_month: reading.referenceMonth,
            p_total_minutes: reading.minutes,
          });
        }

        if (action === "update") {
          results.push({ employeeId: entry.employeeId, status: "updated" });
          continue;
        }

        const snapshots = await adminRest<HrHourSnapshot[]>(
          `rh_hour_snapshots?select=${HR_HOUR_SNAPSHOT_SELECT}&employee_id=eq.${encodeURIComponent(entry.employeeId)}&order=reading_date.asc`,
        );
        const calculation = calculateWorkedMinutes(snapshots, weekStart, weekEnd);
        if (!calculation.complete) throw new Error("Ainda falta uma leitura para calcular a semana.");
        const relevantSnapshotIds = snapshots
          .filter((snapshot) => allowedDates.has(snapshot.reading_date))
          .map((snapshot) => snapshot.id);
        const closed = await callHrRpc<CloseResult>("close_hr_week", {
          p_actor_id: context.profile.user_id,
          p_calculation_details: {
            baseline_minutes: calculation.baselineMinutes,
            guided: true,
            latest_update: calculation.latestUpdate,
            snapshot_ids: relevantSnapshotIds,
          },
          p_closure_note: "Fechamento semanal coletivo guiado.",
          p_employee_id: entry.employeeId,
          p_week_start: weekStart,
          p_worked_minutes: calculation.workedMinutes,
        });
        results.push({ employeeId: entry.employeeId, status: closed.status });
      } catch (error) {
        results.push({ employeeId: entry.employeeId, error: readableError(error) });
      }
    }

    const successCount = results.filter((result) => !result.error).length;
    return Response.json(
      { results, successCount },
      { status: successCount ? 200 : 400 },
    );
  } catch (error) {
    return Response.json({ error: readableError(error) }, { status: 400 });
  }
}

function normalizeEntry(entry: EntryInput, allowedDates: Set<string>, seenEmployees: Set<string>, allowEmpty: boolean) {
  const employeeId = typeof entry.employeeId === "string" ? entry.employeeId : "";
  const readings = Array.isArray(entry.readings) ? entry.readings as ReadingInput[] : [];
  if (!isUuid(employeeId) || employeeId === "" || seenEmployees.has(employeeId)) {
    throw new Error("A lista contém um profissional inválido ou repetido.");
  }
  if ((!readings.length && !allowEmpty) || readings.length > 4) throw new Error("Preencha as leituras necessárias para cada profissional.");
  seenEmployees.add(employeeId);
  const seenDates = new Set<string>();
  return {
    employeeId,
    readings: readings.map((reading) => {
      const date = typeof reading.date === "string" ? reading.date : "";
      const referenceMonth = typeof reading.referenceMonth === "string" ? reading.referenceMonth : "";
      const minutes = typeof reading.minutes === "number"
        ? reading.minutes
        : typeof reading.minutes === "string" ? clockValueToMinutes(reading.minutes) : null;
      if (!isIsoDate(date) || !allowedDates.has(date) || seenDates.has(date) || referenceMonth !== isoMonthStart(date) || minutes === null || !Number.isSafeInteger(minutes) || minutes < 0 || minutes > 60000) {
        throw new Error("Uma das leituras informadas é inválida.");
      }
      seenDates.add(date);
      return { date, minutes, referenceMonth };
    }),
  };
}

function todayInSaoPaulo() {
  const parts = new Intl.DateTimeFormat("en-US", { day: "2-digit", month: "2-digit", timeZone: "America/Sao_Paulo", year: "numeric" }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function mondayOf(value: string) {
  const date = new Date(`${value}T00:00:00.000Z`);
  return addIsoDays(value, -((date.getUTCDay() + 6) % 7));
}

function readableError(error: unknown) {
  if (error instanceof HrActionError || error instanceof Error) return error.message;
  return "Não foi possível concluir o controle semanal.";
}
