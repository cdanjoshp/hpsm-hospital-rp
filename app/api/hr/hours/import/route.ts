import { hasPermission } from "../../../../lib/access";
import { HR_HOUR_SNAPSHOT_SELECT, type HrHourSnapshot, type HrProfile } from "../../../../lib/hr";
import { adminRest, callHrRpc, HrActionError, isIsoDate } from "../../../../lib/hr-server";
import { getSessionContext } from "../../../../lib/session";

type PreviewRow = {
  differenceMinutes: number | null;
  employeeId: string | null;
  line: number;
  message: string;
  name: string | null;
  passport: string;
  positionName: string | null;
  previousMinutes: number | null;
  status: "found" | "invalid" | "unknown";
  totalMinutes: number | null;
};

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "hr.hours.import")) return Response.json({ error: "Você não possui permissão para importar horas." }, { status: 403 });
  try {
    const body = (await request.json()) as { action?: unknown; readingDate?: unknown; text?: unknown };
    const action = body.action;
    const readingDate = typeof body.readingDate === "string" ? body.readingDate : "";
    const text = typeof body.text === "string" ? body.text : "";
    if ((action !== "preview" && action !== "confirm") || !isIsoDate(readingDate) || !text.trim()) {
      return Response.json({ error: "Informe a data e cole ao menos uma leitura." }, { status: 400 });
    }
    const preview = await buildPreview(text, readingDate);
    const found = preview.filter((row) => row.status === "found");
    if (action === "preview") return Response.json(summary(preview));
    if (!found.length) return Response.json({ error: "Nenhuma leitura válida foi encontrada para salvar.", ...summary(preview) }, { status: 400 });
    const result = await callHrRpc<Record<string, unknown>>("import_hr_hour_snapshots", {
      p_actor_id: context.profile.user_id,
      p_reading_date: readingDate,
      p_rows: found.map((row) => ({ passport: row.passport, total_minutes: row.totalMinutes })),
    });
    return Response.json({ ...summary(preview), result });
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível processar a importação.";
    return Response.json({ error: message }, { status: error instanceof HrActionError ? error.status : 400 });
  }
}

async function buildPreview(text: string, readingDate: string): Promise<PreviewRow[]> {
  const [profiles, positions, snapshots] = await Promise.all([
    adminRest<HrProfile[]>("profiles?select=user_id,passport,display_name,position_id,role_code,status&role_code=neq.diretor_geral&status=neq.inactive"),
    adminRest<Array<{ id: number; name: string }>>("staff_positions?select=id,name&limit=50"),
    adminRest<HrHourSnapshot[]>(`rh_hour_snapshots?select=${HR_HOUR_SNAPSHOT_SELECT}&reference_month=eq.${readingDate.slice(0, 7)}-01&reading_date=lt.${readingDate}&order=reading_date.desc`),
  ]);
  const positionById = new Map(positions.map((position) => [position.id, position.name]));
  const profilesByPassport = new Map(profiles.map((profile) => [profile.passport, profile]));
  const previousByEmployee = new Map<string, number>();
  for (const snapshot of snapshots) if (!previousByEmployee.has(snapshot.employee_id)) previousByEmployee.set(snapshot.employee_id, snapshot.total_minutes);
  const seen = new Set<string>();

  return text.split(/\r?\n/).map((raw, index): PreviewRow | null => {
    const value = normalizeImportLine(raw);
    if (!value) return null;
    const match = value.match(/^(\d{1,4})\s+(\d{1,3}):([0-5]\d)$/);
    if (!match) return invalid(index, "", "Use uma linha por pessoa: passaporte 00:00.");
    const passport = match[1];
    const totalMinutes = Number(match[2]) * 60 + Number(match[3]);
    if (seen.has(passport)) return invalid(index, passport, "Passaporte repetido nesta lista.");
    seen.add(passport);
    const profile = profilesByPassport.get(passport);
    if (!profile) return { differenceMinutes: null, employeeId: null, line: index + 1, message: "Passaporte não encontrado.", name: null, passport, positionName: null, previousMinutes: null, status: "unknown", totalMinutes };
    const previousMinutes = previousByEmployee.get(profile.user_id) ?? 0;
    if (totalMinutes < previousMinutes) return invalid(index, passport, "Total menor que a leitura anterior deste mês.", totalMinutes, previousMinutes, profile);
    return { differenceMinutes: totalMinutes - previousMinutes, employeeId: profile.user_id, line: index + 1, message: previousMinutes ? "Pronto para salvar." : "Primeira leitura do mês; cálculo iniciado em zero.", name: profile.display_name, passport, positionName: positionById.get(profile.position_id ?? -1) ?? "Cargo não definido", previousMinutes, status: "found", totalMinutes };
  }).filter((row): row is PreviewRow => row !== null);
}

function normalizeImportLine(line: string) {
  const value = line.trim().replace(/\t+/g, " ").replace(/\s*;\s*/g, " ").replace(/\s+/g, " ");
  const match = value.match(/^(\d{1,4})\s+(\d{1,3})\s*[hH.:]\s*([0-5]\d)$/);
  return match ? `${match[1]} ${match[2]}:${match[3]}` : value;
}

function invalid(index: number, passport: string, message: string, totalMinutes: number | null = null, previousMinutes: number | null = null, profile?: HrProfile): PreviewRow {
  return { differenceMinutes: null, employeeId: profile?.user_id ?? null, line: index + 1, message, name: profile?.display_name ?? null, passport, positionName: null, previousMinutes, status: "invalid", totalMinutes };
}

function summary(rows: PreviewRow[]) {
  return {
    counts: {
      found: rows.filter((row) => row.status === "found").length,
      invalid: rows.filter((row) => row.status === "invalid").length,
      unknown: rows.filter((row) => row.status === "unknown").length,
    },
    rows,
  };
}
