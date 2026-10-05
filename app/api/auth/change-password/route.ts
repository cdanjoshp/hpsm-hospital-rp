import { getSessionBootstrap } from "../../../lib/session";
import { adminHeaders } from "../../../lib/admin-data";
import {
  ConfigurationError,
  getSupabaseAdminConfig,
  getSupabaseConfig,
} from "../../../lib/supabase-server";
import { callProfessionalIdentityGeneration } from "../../../lib/professional-identity";

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as { password?: unknown };
    if (typeof body.password !== "string" || !isStrongPassword(body.password)) {
      return Response.json(
        { error: "A nova senha não atende aos requisitos de segurança." },
        { status: 400 },
      );
    }

    const context = await getSessionBootstrap();
    const accessToken = context?.accessToken;
    if (!accessToken) {
      return Response.json({ error: "Sua sessão expirou. Entre novamente." }, { status: 401 });
    }

    const { url, anonKey } = getSupabaseConfig();
    const passwordResponse = await fetch(`${url}/auth/v1/user`, {
      method: "PUT",
      headers: {
        apikey: anonKey,
        authorization: `Bearer ${accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ password: body.password }),
      signal: AbortSignal.timeout(12_000),
    });
    if (!passwordResponse.ok) {
      return Response.json({ error: "Não foi possível atualizar a senha." }, { status: 502 });
    }

    const updatedUser = (await passwordResponse.json()) as { id?: string };
    if (!updatedUser.id) {
      return Response.json(
        { error: "Não foi possível confirmar a identidade atualizada." },
        { status: 502 },
      );
    }

    const adminConfig = getSupabaseAdminConfig();
    const profileResponse = await fetch(
      `${url}/rest/v1/profiles?user_id=eq.${encodeURIComponent(updatedUser.id)}`,
      {
        method: "PATCH",
        signal: AbortSignal.timeout(12_000),
        headers: {
          ...adminHeaders(adminConfig.serviceRoleKey),
          prefer: "return=minimal",
        },
        body: JSON.stringify({
          must_change_password: false,
          updated_by: updatedUser.id,
        }),
      },
    );
    if (!profileResponse.ok) {
      return Response.json(
        { error: "Senha atualizada, mas o acesso ainda precisa ser liberado pela diretoria." },
        { status: 502 },
      );
    }

    let identityStatus = context.positionDisplayName === "Diretores do SR" ? "active" : "pending";
    if (context.positionDisplayName !== "Diretores do SR") {
      try {
        const identity = await callProfessionalIdentityGeneration(accessToken, { action: "ensure" });
        identityStatus = identity.status ?? "pending";
      } catch {
        // A troca da senha e a liberação do acesso são definitivas. Uma falha da IA
        // mantém somente a identidade pendente para reprocessamento idempotente.
      }
    }

    return Response.json({ identityStatus, ok: true });
  } catch (error) {
    const status = error instanceof ConfigurationError ? 503 : 500;
    return Response.json(
      { error: "O serviço de segurança não está disponível neste momento." },
      { status },
    );
  }
}

function isStrongPassword(value: string) {
  return (
    value.length >= 10 &&
    value.length <= 128 &&
    /[A-Za-z]/.test(value) &&
    /\d/.test(value) &&
    /[^A-Za-z0-9]/.test(value)
  );
}
