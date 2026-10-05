import { adminHeaders } from "./admin-data";
import { deriveSyntheticEmail, getSupabaseAdminConfig } from "./supabase-server";

type AuthUser = {
  email?: string | null;
  id?: string;
  raw_user_meta_data?: Record<string, unknown> | null;
  user_metadata?: Record<string, unknown> | null;
};

export class ProfessionalAccountError extends Error {
  constructor(
    public readonly code: "auth_duplicate" | "auth_identity_mismatch" | "auth_unavailable",
    message: string,
  ) {
    super(message);
    this.name = "ProfessionalAccountError";
  }
}

export function generateTemporaryPassword() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%";
  const random = new Uint32Array(16);
  crypto.getRandomValues(random);
  return Array.from(random, (value) => alphabet[value % alphabet.length]).join("");
}

export async function createProfessionalAuthAccount(
  passport: string,
  metadata: Record<string, string>,
) {
  assertCanonicalPassport(passport);
  const temporaryPassword = generateTemporaryPassword();
  const email = await deriveSyntheticEmail(passport);
  const { url, serviceRoleKey } = getSupabaseAdminConfig();
  const response = await fetch(`${url}/auth/v1/admin/users`, {
    method: "POST",
    signal: AbortSignal.timeout(12_000),
    headers: adminHeaders(serviceRoleKey),
    body: JSON.stringify({
      email,
      password: temporaryPassword,
      email_confirm: true,
      user_metadata: { passport, ...metadata },
    }),
  });
  const payload = await readAuthUser(response);
  const userId = payload.id;
  if (!response.ok || !userId) {
    throw new ProfessionalAccountError(
      response.status === 409 || response.status === 422 ? "auth_duplicate" : "auth_unavailable",
      "Não foi possível criar a identidade Auth.",
    );
  }
  return { temporaryPassword, userId };
}

export async function ensureRecruitmentProfessionalAuthAccount({
  applicationId,
  knownUserId,
  passport,
}: {
  applicationId: string;
  knownUserId?: string | null;
  passport: string;
}) {
  assertCanonicalPassport(passport);

  if (knownUserId) {
    const knownUser = await getAuthUserById(knownUserId);
    if (knownUser) {
      assertRecruitmentAuthUser(knownUser, applicationId, passport);
      return resetExistingRecruitmentAuthUser(knownUserId);
    }
  }

  try {
    return await createProfessionalAuthAccount(passport, {
      origin: "RECRUITMENT_APPLICATION",
      recruitment_application_id: applicationId,
    });
  } catch (error) {
    if (!(error instanceof ProfessionalAccountError) || error.code !== "auth_duplicate") throw error;
  }

  const recoveredUser = await findRecruitmentAuthUser(applicationId, passport);
  if (!recoveredUser?.id) {
    throw new ProfessionalAccountError(
      "auth_duplicate",
      `Já existe uma identidade Auth relacionada ao passaporte ${passport}, mas ela não pertence com segurança a esta candidatura.`,
    );
  }
  return resetExistingRecruitmentAuthUser(recoveredUser.id);
}

export async function setProfessionalTemporaryPassword(userId: string) {
  const temporaryPassword = generateTemporaryPassword();
  await updateAuthUserPassword(userId, temporaryPassword);
  return temporaryPassword;
}

export async function deleteProfessionalAuthAccount(userId: string) {
  const { url, serviceRoleKey } = getSupabaseAdminConfig();
  try {
    const response = await fetch(`${url}/auth/v1/admin/users/${encodeURIComponent(userId)}`, {
      method: "DELETE",
      signal: AbortSignal.timeout(12_000),
      headers: adminHeaders(serviceRoleKey),
    });
    return response.ok || response.status === 404;
  } catch {
    return false;
  }
}

async function resetExistingRecruitmentAuthUser(userId: string) {
  const temporaryPassword = generateTemporaryPassword();
  await updateAuthUserPassword(userId, temporaryPassword);
  return { temporaryPassword, userId };
}

async function updateAuthUserPassword(userId: string, password: string) {
  const { url, serviceRoleKey } = getSupabaseAdminConfig();
  const response = await fetch(`${url}/auth/v1/admin/users/${encodeURIComponent(userId)}`, {
    method: "PUT",
    signal: AbortSignal.timeout(12_000),
    headers: adminHeaders(serviceRoleKey),
    body: JSON.stringify({ password }),
  });
  if (!response.ok) {
    throw new ProfessionalAccountError("auth_unavailable", "Não foi possível preparar a senha temporária.");
  }
}

async function getAuthUserById(userId: string) {
  const { url, serviceRoleKey } = getSupabaseAdminConfig();
  const response = await fetch(`${url}/auth/v1/admin/users/${encodeURIComponent(userId)}`, {
    signal: AbortSignal.timeout(12_000),
    headers: adminHeaders(serviceRoleKey),
    cache: "no-store",
  });
  const user = await readAuthUser(response);
  if (response.status === 404) return null;
  if (!response.ok || !user.id) {
    throw new ProfessionalAccountError("auth_unavailable", "Não foi possível recuperar a identidade Auth da candidatura.");
  }
  return user;
}

async function findRecruitmentAuthUser(applicationId: string, passport: string) {
  const { url, serviceRoleKey } = getSupabaseAdminConfig();
  const expectedEmail = await deriveSyntheticEmail(passport);
  const perPage = 1000;

  for (let page = 1; page <= 10; page += 1) {
    const response = await fetch(`${url}/auth/v1/admin/users?page=${page}&per_page=${perPage}`, {
      signal: AbortSignal.timeout(12_000),
      headers: adminHeaders(serviceRoleKey),
      cache: "no-store",
    });
    if (!response.ok) {
      throw new ProfessionalAccountError("auth_unavailable", "Não foi possível reconciliar a identidade Auth.");
    }
    const payload = (await response.json()) as { users?: AuthUser[] } | AuthUser[];
    const users = Array.isArray(payload) ? payload : payload.users ?? [];
    const matching = users.find((user) => {
      const metadata = authUserMetadata(user);
      return user.email === expectedEmail
        && metadata.passport === passport
        && metadata.recruitment_application_id === applicationId;
    });
    if (matching) return matching;
    if (users.length < perPage) return null;
  }

  throw new ProfessionalAccountError("auth_unavailable", "A reconciliação da identidade Auth excedeu o limite seguro.");
}

function assertRecruitmentAuthUser(user: AuthUser, applicationId: string, passport: string) {
  const metadata = authUserMetadata(user);
  if (
    metadata.passport !== passport
    || metadata.recruitment_application_id !== applicationId
    || metadata.origin !== "RECRUITMENT_APPLICATION"
  ) {
    throw new ProfessionalAccountError(
      "auth_identity_mismatch",
      "A identidade Auth encontrada não corresponde com segurança à candidatura.",
    );
  }
}

function authUserMetadata(user: AuthUser) {
  return user.user_metadata ?? user.raw_user_meta_data ?? {};
}

async function readAuthUser(response: Response) {
  try {
    const payload = (await response.json()) as AuthUser & { user?: AuthUser };
    return payload.user ?? payload;
  } catch {
    return {} as AuthUser;
  }
}

function assertCanonicalPassport(passport: string) {
  if (!/^[0-9]{4}$/.test(passport)) {
    throw new ProfessionalAccountError("auth_identity_mismatch", "O passaporte profissional precisa ter quatro dígitos.");
  }
}
