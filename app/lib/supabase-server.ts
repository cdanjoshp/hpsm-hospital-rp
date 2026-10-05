import { PASSPORT_PATTERN } from "./passport";

export type SupabaseConfig = {
  anonKey: string;
  url: string;
};

export class ConfigurationError extends Error {}

export function getSupabaseConfig(): SupabaseConfig {
  const url = process.env.SUPABASE_URL?.replace(/\/$/, "");
  const anonKey = process.env.SUPABASE_ANON_KEY;

  if (!url || !anonKey) {
    throw new ConfigurationError("Supabase ainda não foi configurado.");
  }

  if (!url.startsWith("https://")) {
    throw new ConfigurationError("A URL do Supabase precisa usar HTTPS.");
  }

  return { url, anonKey };
}

export function getSupabaseAdminConfig() {
  const base = getSupabaseConfig();
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceRoleKey) {
    throw new ConfigurationError("A chave administrativa não foi configurada.");
  }
  return { ...base, serviceRoleKey };
}

export async function deriveSyntheticEmail(passport: string): Promise<string> {
  const pepper = process.env.PASSPORT_EMAIL_PEPPER;
  if (!pepper || pepper.length < 24) {
    throw new ConfigurationError(
      "A proteção interna de matrículas ainda não foi configurada.",
    );
  }

  const normalizedPassport = normalizePassport(passport);
  const input = new TextEncoder().encode(`${pepper}:${normalizedPassport}`);
  const digest = await crypto.subtle.digest("SHA-256", input);
  const hash = Array.from(new Uint8Array(digest))
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");

  return `${hash}@auth.hp-sul.internal`;
}

export function normalizePassport(value: string): string {
  const normalized = value.trim();
  if (!PASSPORT_PATTERN.test(normalized)) {
    throw new Error("Passaporte ou matrícula inválido. Use de 1 a 4 números.");
  }
  return normalized;
}

export function normalizeProfessionalPassport(value: string): string {
  return normalizePassport(value).padStart(4, "0");
}
