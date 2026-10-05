import { getPatientPortalHistoryPage } from "../../../lib/patient-portal";

const RESPONSE_HEADERS = { "cache-control": "private, no-store", vary: "Cookie" };

export async function GET(request: Request) {
  const url = new URL(request.url);
  const cursorAt = url.searchParams.get("cursorAt");
  const cursorKey = url.searchParams.get("cursorKey");
  if (!validCursorPair(cursorAt, cursorKey)) {
    return Response.json({ error: "Paginação inválida." }, { status: 400, headers: RESPONSE_HEADERS });
  }

  try {
    const page = await getPatientPortalHistoryPage(cursorAt && cursorKey ? { occurredAt: cursorAt, key: cursorKey } : null);
    return page
      ? Response.json(page, { headers: RESPONSE_HEADERS })
      : Response.json({ authenticated: false }, { status: 401, headers: RESPONSE_HEADERS });
  } catch {
    return Response.json({ error: "Não foi possível carregar o histórico agora." }, { status: 503, headers: RESPONSE_HEADERS });
  }
}
function validCursorPair(cursorAt: string | null, cursorKey: string | null) {
  if (!cursorAt && !cursorKey) return true;
  return Boolean(
    cursorAt && cursorKey && cursorKey.length <= 128 && !Number.isNaN(new Date(cursorAt).getTime()),
  );
}
