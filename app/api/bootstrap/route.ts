import { headers } from "next/headers";
import { adminHeaders } from "../../lib/admin-data";
import {
  createProfessionalAuthAccount,
  deleteProfessionalAuthAccount,
  ProfessionalAccountError,
} from "../../lib/professional-account";
import { getSupabaseAdminConfig, normalizeProfessionalPassport } from "../../lib/supabase-server";

export async function POST(request: Request) {
  const requestHeaders = await headers();
  const openAiUser = requestHeaders.get("oai-authenticated-user-email");
  if (!openAiUser) return Response.json({ error: "Configuração não autorizada." }, { status: 403 });

  let createdUserId: string | null = null;
  let duplicatePassport = false;
  try {
    const body = (await request.json()) as { displayName?: unknown; passport?: unknown };
    if (typeof body.displayName !== "string" || typeof body.passport !== "string") return Response.json({ error: "Preencha os dados do Diretor Geral." }, { status: 400 });
    const displayName = body.displayName.trim();
    const passport = normalizeProfessionalPassport(body.passport);
    if (displayName.length < 2 || displayName.length > 80) return Response.json({ error: "Nome inválido." }, { status: 400 });

    const { url, serviceRoleKey } = getSupabaseAdminConfig();
    const serviceHeaders = adminHeaders(serviceRoleKey);
    const existingResponse = await fetch(`${url}/rest/v1/profiles?select=user_id&role_code=eq.diretor_geral&limit=1`, { headers: serviceHeaders });
    const existing = existingResponse.ok ? ((await existingResponse.json()) as unknown[]) : [];
    if (existing.length) return Response.json({ error: "O sistema já possui uma conta semente. Nenhuma nova senha foi gerada." }, { status: 409 });
    const duplicateResponse = await fetch(`${url}/rest/v1/profiles?select=user_id&passport=eq.${encodeURIComponent(passport)}&limit=1`, { headers: serviceHeaders });
    const duplicates = duplicateResponse.ok ? ((await duplicateResponse.json()) as unknown[]) : [];
    if (duplicates.length) return Response.json({ error: "Este passaporte já pertence a outro profissional." }, { status: 409 });

    const authAccount = await createProfessionalAuthAccount(passport, { origin: "BOOTSTRAP" });
    createdUserId = authAccount.userId;

    const profileResponse = await fetch(`${url}/rest/v1/profiles`, {
      method: "POST",
      headers: { ...serviceHeaders, prefer: "return=minimal" },
      body: JSON.stringify({ user_id: createdUserId, passport, display_name: displayName, role_code: "diretor_geral", status: "active", must_change_password: true }),
    });
    if (!profileResponse.ok) {
      duplicatePassport = profileResponse.status === 409;
      throw new Error("profile");
    }

    await fetch(`${url}/rest/v1/system_settings`, {
      method: "POST",
      headers: { ...serviceHeaders, prefer: "resolution=merge-duplicates" },
      body: JSON.stringify({ key: "bootstrap", value: { completed: true, completed_at: new Date().toISOString() } }),
    });

    return Response.json({ passport, temporaryPassword: authAccount.temporaryPassword }, { status: 201 });
  } catch (error) {
    if (error instanceof ProfessionalAccountError && error.code === "auth_duplicate") {
      duplicatePassport = true;
    }
    if (createdUserId) {
      await deleteProfessionalAuthAccount(createdUserId);
    }
    if (duplicatePassport) {
      return Response.json({ error: "Este passaporte já pertence a outro profissional." }, { status: 409 });
    }
    return Response.json({ error: "A inicialização não pôde ser concluída. Nenhuma credencial válida foi emitida." }, { status: 500 });
  }
}
