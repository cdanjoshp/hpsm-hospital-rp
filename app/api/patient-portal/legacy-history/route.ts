import { getPatientPortalLegacyHistoryPage, type PatientPortalLegacyRecordType } from "../../../lib/patient-portal";

const HEADERS = { "cache-control": "private, no-store", vary: "Cookie" };
const TYPES = ["registration", "attendance", "exam", "vaccine", "appointment", "health_plan"];
export async function GET(request: Request) {
  const params = new URL(request.url).searchParams;
  const raw = params.get("page") ?? "1";
  const type = params.get("recordType");
  if (!/^[1-9]\d*$/.test(raw) || !Number.isSafeInteger(Number(raw)) || (type !== null && !TYPES.includes(type))) {
    return Response.json({ error: "Consulta inválida." }, { status: 400, headers: HEADERS });
  }
  try {
    const page = await getPatientPortalLegacyHistoryPage(Number(raw), type as PatientPortalLegacyRecordType | null);
    return page ? Response.json(page, { headers: HEADERS }) : Response.json({ authenticated: false }, { status: 401, headers: HEADERS });
  } catch { return Response.json({ error: "Não foi possível carregar o histórico HP Norte agora." }, { status: 503, headers: HEADERS }); }
}
