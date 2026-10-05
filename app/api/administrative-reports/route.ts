import { getEffectivePermissionCodes } from "../../lib/access";
import {
  getReportFinancial,
  getReportHr,
  getReportIndividual,
  getReportOverview,
  getReportTeam,
  searchReportStaff,
  type ReportFinancialData,
  type ReportFilters,
  type ReportHrData,
  type ReportIndividualData,
} from "../../lib/administrative-reports";
import { getSessionContext } from "../../lib/session";

const RESPONSE_HEADERS = { "cache-control": "private, no-store, max-age=0", vary: "Cookie" };
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

export async function GET(request: Request) {
  const context = await getSessionContext();
  if (!context) return jsonError("Sessão expirada.", 401);
  const permissions = new Set(await getEffectivePermissionCodes(context.profile.user_id));
  if (!permissions.has("hr.reports.view")) return jsonError("Acesso não autorizado.", 403);

  const query = new URL(request.url).searchParams;
  const view = query.get("view") ?? "overview";
  if (view === "staff") {
    const search = (query.get("search") ?? "").trim();
    if (search.length < 2 || search.length > 80) return Response.json({ items: [] }, { headers: RESPONSE_HEADERS });
    try {
      return Response.json(await searchReportStaff(context.accessToken, search), { headers: RESPONSE_HEADERS });
    } catch {
      return jsonError("Não foi possível localizar os profissionais.", 503);
    }
  }

  const filters = parseFilters(query);
  if (!filters) return jsonError("Selecione um período válido de até 12 meses.", 400);
  if (view === "financial" && !permissions.has("attendances.manage") && !permissions.has("sr.directors.view")) return jsonError("Acesso financeiro não autorizado.", 403);

  try {
    if (query.get("export") === "csv") {
      return exportCsv(view, context.accessToken, { ...filters, page: 1, pageSize: 100 });
    }
    const data = view === "overview"
      ? await getReportOverview(context.accessToken, filters)
      : view === "hr"
        ? await getReportHr(context.accessToken, filters)
        : view === "financial"
          ? await getReportFinancial(context.accessToken, filters)
          : view === "team"
            ? await getReportTeam(context.accessToken, filters)
            : view === "individual" && filters.employeeId
              ? await getReportIndividual(context.accessToken, filters)
              : null;
    if (!data) return jsonError("Relatório inválido ou incompleto.", 400);
    return Response.json(data, { headers: RESPONSE_HEADERS });
  } catch {
    return jsonError("Não foi possível gerar este relatório agora.", 503);
  }
}

function parseFilters(query: URLSearchParams): ReportFilters | null {
  const start = query.get("start") ?? "";
  const end = query.get("end") ?? "";
  if (!ISO_DATE.test(start) || !ISO_DATE.test(end)) return null;
  const startDate = new Date(`${start}T00:00:00Z`);
  const endDate = new Date(`${end}T00:00:00Z`);
  const days = Math.round((endDate.getTime() - startDate.getTime()) / 86_400_000);
  if (!Number.isFinite(days) || days < 0 || days > 366) return null;

  const positionId = optionalPositiveInteger(query.get("position"));
  const page = positiveInteger(query.get("page"), 1, 10_000);
  const pageSize = positiveInteger(query.get("pageSize"), 25, 100);
  const employeeId = uuidOrNull(query.get("employee"));
  if (query.get("employee") && !employeeId) return null;
  return {
    direction: query.get("direction") ?? undefined,
    employeeId,
    end,
    page,
    pageSize,
    positionId,
    search: (query.get("search") ?? "").slice(0, 80),
    sort: query.get("sort") ?? undefined,
    start,
    status: query.get("status") ?? undefined,
  };
}

async function exportCsv(view: string, accessToken: string, filters: ReportFilters) {
  let rows: Array<Array<number | string | null>>;
  if (view === "hr") {
    const data = await getReportHr(accessToken, filters) as ReportHrData;
    rows = [
      ["Profissional", "Passaporte", "Cargo", "Situação funcional", "Horas", "Meta base", "Abono", "Meta efetiva", "Diferença", "Resultado", "Semanas cumpridas", "Semanas abaixo", "Semanas integralmente abonadas", "Possui afastamento", "Possui justificativa", "ADVs ativas"],
      ...data.items.map((item) => [
        item.name, item.passport, item.position, profileStatus(item.profile_status), minutes(item.worked_minutes),
        minutes(item.base_target_minutes), minutes(item.leave_minutes), minutes(item.effective_target_minutes), signedMinutes(item.difference_minutes),
        goalStatus(item.goal_status), item.met_weeks, item.below_weeks, item.excused_weeks,
        item.has_absence ? "Sim" : "Não", item.has_justification ? "Sim" : "Não", item.active_warnings,
      ]),
    ];
  } else if (view === "financial") {
    const data = await getReportFinancial(accessToken, filters) as ReportFinancialData;
    rows = [
      ["Profissional", "Passaporte", "Cargo", "Atendimentos/vendas", "Itens/procedimentos", "Valor movimentado", "Ticket médio"],
      ...data.production.map((item) => [item.name, item.passport, item.position, item.attendance_count, item.item_count, decimal(item.total_amount), decimal(item.ticket_average)]),
    ];
  } else if (view === "individual" && filters.employeeId) {
    const data = await getReportIndividual(accessToken, filters) as ReportIndividualData;
    if (!data.found || !data.profile) throw new Error("Profissional não localizado.");
    rows = [
      ["Relatório individual do profissional"],
      ["Profissional", data.profile.name],
      ["Passaporte", data.profile.passport],
      ["Cargo", data.profile.position],
      ["Situação", profileStatus(data.profile.status)],
      ["Período", `${filters.start} a ${filters.end}`],
      ["Horas trabalhadas", minutes(data.journey.worked_minutes)],
      ["Meta base", minutes(data.journey.base_target_minutes)],
      ["Horas abonadas", minutes(data.journey.leave_minutes)],
      ["Meta efetiva", minutes(data.journey.effective_target_minutes)],
      ["Diferença", signedMinutes(data.journey.difference_minutes)],
      ["Semanas cumpridas", data.journey.met_weeks],
      ["Semanas abaixo", data.journey.below_weeks],
      ["Semanas integralmente abonadas", data.journey.excused_weeks],
      ["ADVs ativas", data.rh.active_warnings],
      ["Afastamentos", data.rh.absences],
      ["Justificativas", data.rh.justifications],
      ...(data.production ? [
        ["Atendimentos/vendas", data.production.attendance_count],
        ["Itens/procedimentos", data.production.item_count],
        ["Valor movimentado", decimal(data.production.total_amount)],
        ["Ticket médio", decimal(data.production.ticket_average)],
      ] : []),
    ];
  } else {
    return jsonError("A exportação está disponível para RH, Produção e Relatório Individual.", 400);
  }

  const csv = rows.map((row) => row.map(csvCell).join(";")).join("\r\n");
  return new Response(`\ufeff${csv}`, {
    headers: {
      ...RESPONSE_HEADERS,
      "content-disposition": `attachment; filename="hpsm-relatorio-${view}-${filters.start}-${filters.end}.csv"`,
      "content-type": "text/csv; charset=utf-8",
    },
  });
}

function csvCell(value: number | string | null) {
  let text = value === null ? "" : String(value);
  if (/^[=+\-@]/.test(text)) text = `'${text}`;
  return `"${text.replaceAll('"', '""')}"`;
}

function decimal(value: number) { return Number(value).toFixed(2).replace(".", ","); }
function minutes(value: number) { const safe = Math.max(0, Math.round(Number(value) || 0)); return `${Math.floor(safe / 60)}h${String(safe % 60).padStart(2, "0")}`; }
function signedMinutes(value: number) { return `${value >= 0 ? "+" : "−"}${minutes(Math.abs(value))}`; }
function profileStatus(value: string) { return value === "suspended" ? "Suspenso" : "Ativo"; }
function goalStatus(value: string) { return ({ below: "Meta não atingida", fully_excused: "Meta integralmente abonada", met: "Meta atingida", no_data: "Sem fechamento no período" } as Record<string, string>)[value] ?? value; }
function positiveInteger(value: string | null, fallback: number, maximum: number) { const parsed = Number(value); return Number.isSafeInteger(parsed) && parsed > 0 ? Math.min(parsed, maximum) : fallback; }
function optionalPositiveInteger(value: string | null) { if (!value) return null; const parsed = Number(value); return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null; }
function uuidOrNull(value: string | null) { return value && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value) ? value : null; }
function jsonError(error: string, status: number) { return Response.json({ error }, { status, headers: RESPONSE_HEADERS }); }
