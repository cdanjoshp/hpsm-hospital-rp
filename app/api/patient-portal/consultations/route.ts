import { getPatientPortalConsultationPage } from "../../../lib/patient-portal";

const HEADERS = { "cache-control": "private, no-store", vary: "Cookie" };
export async function GET(request: Request) {
  const params = new URL(request.url).searchParams;
  const cursorAt = params.get("cursorAt");
  const cursorKey = params.get("cursorKey");
  if ((cursorAt === null) !== (cursorKey === null) || (cursorAt !== null && (Number.isNaN(Date.parse(cursorAt)) || !/^(appointment|consultation):[1-9]\d*$/.test(cursorKey ?? "")))) {
    return Response.json({ error: "Cursor inválido." }, { status: 400, headers: HEADERS });
  }
  try {
    const page = await getPatientPortalConsultationPage(cursorAt && cursorKey ? { occurredAt: cursorAt, key: cursorKey } : null);
    return page ? Response.json(page, { headers: HEADERS }) : Response.json({ authenticated: false }, { status: 401, headers: HEADERS });
  } catch {
    return Response.json({ error: "Não foi possível carregar suas consultas agora." }, { status: 503, headers: HEADERS });
  }
}
