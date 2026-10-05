import { NextResponse } from "next/server";
import type { GlobalSearchResponse } from "../../lib/global-search";
import { getSessionAccessToken } from "../../lib/session";
import { callSupabaseUserRpc } from "../../lib/supabase-user";

const PRIVATE_HEADERS = {
  "cache-control": "private, no-store, max-age=0",
  vary: "Cookie",
};

export async function GET(request: Request) {
  const accessToken = await getSessionAccessToken();
  if (!accessToken) return NextResponse.json({ error: "Sessão inválida ou expirada." }, { status: 401, headers: PRIVATE_HEADERS });

  const query = new URL(request.url).searchParams.get("q")?.trim() ?? "";
  if (query.length > 100) return NextResponse.json({ error: "A busca deve ter no máximo 100 caracteres." }, { status: 400, headers: PRIVATE_HEADERS });
  if (query.length < 2) return NextResponse.json({ items: [] } satisfies GlobalSearchResponse, { headers: PRIVATE_HEADERS });

  try {
    const result = await callSupabaseUserRpc<GlobalSearchResponse>(accessToken, "hpsm_global_search", {
      p_limit: 5,
      p_query: query,
    });
    return NextResponse.json({ items: Array.isArray(result?.items) ? result.items : [] } satisfies GlobalSearchResponse, { headers: PRIVATE_HEADERS });
  } catch {
    return NextResponse.json({ error: "Não foi possível realizar a busca agora." }, { status: 503, headers: PRIVATE_HEADERS });
  }
}
