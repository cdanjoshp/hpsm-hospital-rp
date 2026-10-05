import { getPatientPortalHospitalizationPage } from "../../../lib/patient-portal";

const HEADERS = { "cache-control": "private, no-store", vary: "Cookie" };
export async function GET(request: Request) {
  const raw = new URL(request.url).searchParams.get("page") ?? "1";
  if (!/^[1-9]\d*$/.test(raw) || !Number.isSafeInteger(Number(raw))) return Response.json({ error: "Página inválida." }, { status: 400, headers: HEADERS });
  try {
    const page = await getPatientPortalHospitalizationPage(Number(raw));
    return page ? Response.json(page, { headers: HEADERS }) : Response.json({ authenticated: false }, { status: 401, headers: HEADERS });
  } catch { return Response.json({ error: "Não foi possível carregar suas internações agora." }, { status: 503, headers: HEADERS }); }
}
