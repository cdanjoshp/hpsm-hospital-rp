import { getPatientPortalExamPage, type PatientPortalExamFilter } from "../../../lib/patient-portal";

const RESPONSE_HEADERS = { "cache-control": "private, no-store", vary: "Cookie" };

export async function GET(request: Request) {
  const url = new URL(request.url);
  const cursorAt = url.searchParams.get("cursorAt");
  const cursorIdValue = url.searchParams.get("cursorId");
  const cursorId = cursorIdValue === null ? null : Number(cursorIdValue);
  const filter = url.searchParams.get("filter") ?? "all";
  if (!isFilter(filter) || !validCursorPair(cursorAt, cursorIdValue, cursorId)) {
    return Response.json({ error: "Consulta inválida." }, { status: 400, headers: RESPONSE_HEADERS });
  }

  try {
    const page = await getPatientPortalExamPage(
      filter,
      cursorAt && cursorId ? { occurredAt: cursorAt, id: cursorId } : null,
    );
    return page
      ? Response.json(page, { headers: RESPONSE_HEADERS })
      : Response.json({ authenticated: false }, { status: 401, headers: RESPONSE_HEADERS });
  } catch {
    return Response.json({ error: "Não foi possível carregar os exames agora." }, { status: 503, headers: RESPONSE_HEADERS });
  }
}

function isFilter(value: string): value is PatientPortalExamFilter {
  return value === "all" || value === "in_progress" || value === "completed";
}

function validCursorPair(cursorAt: string | null, cursorIdValue: string | null, cursorId: number | null) {
  if (!cursorAt && cursorIdValue === null) return true;
  return Boolean(
    cursorAt
      && cursorIdValue
      && !Number.isNaN(new Date(cursorAt).getTime())
      && Number.isSafeInteger(cursorId)
      && Number(cursorId) > 0,
  );
}
