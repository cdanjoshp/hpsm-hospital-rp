import { getPatientPortalMedicalCertificatePage } from "../../../lib/patient-portal";

const HEADERS = { "cache-control": "private, no-store", vary: "Cookie" };

export async function GET(request: Request) {
  const page = Number(new URL(request.url).searchParams.get("page") ?? "1");
  if (!Number.isSafeInteger(page) || page <= 0) return Response.json({ error: "Consulta inválida." }, { status: 400, headers: HEADERS });
  try {
    const result = await getPatientPortalMedicalCertificatePage(page, 15);
    return result ? Response.json(result, { headers: HEADERS }) : Response.json({ authenticated: false }, { status: 401, headers: HEADERS });
  } catch {
    return Response.json({ error: "Não foi possível carregar os atestados agora." }, { status: 503, headers: HEADERS });
  }
}
