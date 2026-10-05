import { getSupabaseConfig } from "./supabase-server";

export async function callSupabaseUserRpc<T>(
  accessToken: string,
  name: string,
  payload: Record<string, unknown> = {},
): Promise<T> {
  const { anonKey, url } = getSupabaseConfig();
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      authorization: `Bearer ${accessToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
    cache: "no-store",
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) {
    const payload = await response.json().catch(() => null) as { code?: unknown; message?: unknown } | null;
    throw new SupabaseUserRpcError(
      response.status,
      typeof payload?.message === "string" ? payload.message : null,
      typeof payload?.code === "string" ? payload.code : null,
    );
  }
  if (response.status === 204) return undefined as T;
  const text = await response.text();
  return (text ? JSON.parse(text) : undefined) as T;
}

export class SupabaseUserRpcError extends Error {
  constructor(public status: number, public rpcMessage: string | null = null, public code: string | null = null) {
    super("Não foi possível consultar os dados do usuário.");
  }
}
