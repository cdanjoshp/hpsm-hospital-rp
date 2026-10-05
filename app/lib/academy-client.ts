export async function academyGet<T>(view: string, params: Record<string, string | number | null | undefined> = {}): Promise<T> {
  const query = new URLSearchParams({ view });
  for (const [key, value] of Object.entries(params)) if (value !== null && value !== undefined && value !== "") query.set(key, String(value));
  const response = await fetch(`/api/academy?${query}`, { cache: "no-store" });
  const data = await response.json() as T & { error?: string };
  if (!response.ok) throw new Error(data.error ?? "Não foi possível carregar a Academia.");
  return data;
}

export async function academyPost<T>(action: string, data: Record<string, unknown>): Promise<T> {
  const response = await fetch("/api/academy", { method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ action, ...data }) });
  const result = await response.json() as T & { error?: string };
  if (!response.ok) throw new Error(result.error ?? "Não foi possível concluir a ação.");
  return result;
}

export function academyDate(value: string | null | undefined) {
  return value ? new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)) : "—";
}
