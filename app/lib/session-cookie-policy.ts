// A aplicação não impõe prazo absoluto às sessões persistentes. Navegadores
// podem limitar cookies persistentes por política própria; cada rotação do
// refresh token renova o cookie profissional dentro desse limite.
export const PERSISTENT_SESSION_COOKIE_EXPIRES_AT = "9999-12-31T23:59:59.000Z";

export function persistentSessionCookieExpires() {
  return new Date(PERSISTENT_SESSION_COOKIE_EXPIRES_AT);
}
