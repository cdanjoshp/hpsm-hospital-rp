type AuthConfig = { url: string; anonKey: string };

/** Revoke the current Auth session before removing its browser credentials. */
export async function revokeProfessionalSession(
  config: AuthConfig,
  accessToken: string | null,
  refreshToken: string | null,
  request: typeof fetch = fetch,
): Promise<void> {
  async function revoke(token: string) {
    return request(`${config.url}/auth/v1/logout?scope=local`, {
      method: "POST",
      headers: { apikey: config.anonKey, authorization: `Bearer ${token}` },
      cache: "no-store",
      signal: AbortSignal.timeout(12_000),
    });
  }
  if (accessToken) {
    const response = await revoke(accessToken);
    if (response.ok) return;
    if (![401, 403, 404].includes(response.status)) throw new Error("Logout indisponível.");
  }
  if (!refreshToken) return;
  // The access cookie can expire before logout. Refresh only to revoke the
  // remaining session; never return the renewed credentials to the browser.
  const refreshed = await request(`${config.url}/auth/v1/token?grant_type=refresh_token`, {
    method: "POST",
    headers: { apikey: config.anonKey, "content-type": "application/json" },
    body: JSON.stringify({ refresh_token: refreshToken }),
    cache: "no-store",
    signal: AbortSignal.timeout(12_000),
  });
  if ([400, 401, 403].includes(refreshed.status)) return;
  if (!refreshed.ok) throw new Error("Logout indisponível.");
  const payload = await refreshed.json() as { access_token?: unknown };
  if (typeof payload.access_token !== "string") throw new Error("Logout indisponível.");
  const response = await revoke(payload.access_token);
  if (!response.ok && ![401, 403, 404].includes(response.status)) throw new Error("Logout indisponível.");
}
