import { adminHeaders } from "./admin-data";
import { getSupabaseAdminConfig } from "./supabase-server";

export async function callHrRpc<T>(name: string, payload: Record<string, unknown>): Promise<T> {
  const { url, serviceRoleKey } = getSupabaseAdminConfig();
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: adminHeaders(serviceRoleKey),
    body: JSON.stringify(payload),
    cache: "no-store",
    signal: AbortSignal.timeout(25_000),
  });
  if (!response.ok) {
    const body = (await response.json().catch(() => null)) as { message?: string } | null;
    throw new HrActionError(body?.message ?? "Não foi possível concluir a operação.", response.status);
  }
  return (await response.json()) as T;
}

export async function adminRest<T>(path: string, init?: RequestInit): Promise<T> {
  const { url, serviceRoleKey } = getSupabaseAdminConfig();
  const response = await fetch(`${url}/rest/v1/${path}`, {
    ...init,
    headers: {
      ...adminHeaders(serviceRoleKey),
      ...(init?.headers ?? {}),
    },
    cache: "no-store",
    signal: init?.signal ?? AbortSignal.timeout(25_000),
  });
  if (!response.ok) {
    const body = (await response.json().catch(() => null)) as { message?: string } | null;
    throw new HrActionError(body?.message ?? "Não foi possível concluir a operação.", response.status);
  }
  return (await response.json()) as T;
}

export async function adminCount(path: string): Promise<number> {
  const { url, serviceRoleKey } = getSupabaseAdminConfig();
  const response = await fetch(`${url}/rest/v1/${path}`, {
    headers: {
      ...adminHeaders(serviceRoleKey),
      prefer: "count=exact",
      range: "0-0",
    },
    cache: "no-store",
    signal: AbortSignal.timeout(25_000),
  });
  if (!response.ok) {
    const body = (await response.json().catch(() => null)) as { message?: string } | null;
    throw new HrActionError(body?.message ?? "Não foi possível concluir a operação.", response.status);
  }
  const total = Number(response.headers.get("content-range")?.split("/")[1]);
  if (Number.isFinite(total)) return total;
  const rows = (await response.json()) as unknown[];
  return rows.length;
}

export class HrActionError extends Error {
  constructor(message: string, public status = 400) {
    super(message);
  }
}

export function isIsoDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(date.valueOf()) && date.toISOString().slice(0, 10) === value;
}

export function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
