import { getPatientPortalSummary } from "../../../lib/patient-portal";

const RESPONSE_HEADERS = {
  "cache-control": "private, no-store",
  vary: "Cookie",
};

export async function GET() {
  try {
    const summary = await getPatientPortalSummary();
    return summary
      ? Response.json(summary, { headers: RESPONSE_HEADERS })
      : Response.json({ authenticated: false }, { status: 401, headers: RESPONSE_HEADERS });
  } catch {
    return Response.json(
      { error: "Não foi possível carregar seus dados agora. Tente novamente." },
      { status: 503, headers: RESPONSE_HEADERS },
    );
  }
}
