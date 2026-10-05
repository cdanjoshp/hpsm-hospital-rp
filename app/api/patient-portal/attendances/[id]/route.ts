import { getPatientPortalAttendanceDetail } from "../../../../lib/patient-portal";

const RESPONSE_HEADERS = { "cache-control": "private, no-store", vary: "Cookie" };

export async function GET(_request: Request, context: { params: Promise<{ id: string }> }) {
  const { id } = await context.params;
  if (!/^\d+$/.test(id)) {
    return Response.json({ error: "Atendimento não localizado." }, { status: 404, headers: RESPONSE_HEADERS });
  }
  const attendanceId = Number(id);
  if (!Number.isSafeInteger(attendanceId) || attendanceId < 1) {
    return Response.json({ error: "Atendimento não localizado." }, { status: 404, headers: RESPONSE_HEADERS });
  }

  try {
    const detail = await getPatientPortalAttendanceDetail(attendanceId);
    if (!detail) return Response.json({ authenticated: false }, { status: 401, headers: RESPONSE_HEADERS });
    if (detail === "not_found") {
      return Response.json({ error: "Atendimento não localizado." }, { status: 404, headers: RESPONSE_HEADERS });
    }
    return Response.json(detail, { headers: RESPONSE_HEADERS });
  } catch {
    return Response.json({ error: "Não foi possível carregar o atendimento agora." }, { status: 503, headers: RESPONSE_HEADERS });
  }
}
