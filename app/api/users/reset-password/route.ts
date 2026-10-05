import { getSessionProfile } from "../../../lib/session";
import { adminHeaders } from "../../../lib/admin-data";
import { hasPermission } from "../../../lib/access";
import { setProfessionalTemporaryPassword } from "../../../lib/professional-account";
import { getSupabaseAdminConfig } from "../../../lib/supabase-server";

export async function POST(request: Request) {
  const actor = await getSessionProfile();
  if (!actor) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(actor, "team.manage")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });

  try {
    const body = (await request.json()) as { userId?: unknown };
    if (typeof body.userId !== "string") return Response.json({ error: "Conta inválida." }, { status: 400 });

    const { url, serviceRoleKey } = getSupabaseAdminConfig();
    const headers = adminHeaders(serviceRoleKey);
    const targetResponse = await fetch(`${url}/rest/v1/profiles?select=role_code&user_id=eq.${encodeURIComponent(body.userId)}&limit=1`, { headers });
    const targets = targetResponse.ok ? ((await targetResponse.json()) as { role_code: string }[]) : [];
    if (!targets[0] || targets[0].role_code === "diretor_geral") return Response.json({ error: "Essa conta não pode ser redefinida por este fluxo." }, { status: 403 });

    const temporaryPassword = await setProfessionalTemporaryPassword(body.userId);

    const profileResponse = await fetch(`${url}/rest/v1/profiles?user_id=eq.${encodeURIComponent(body.userId)}`, {
      method: "PATCH",
      headers,
      body: JSON.stringify({
        must_change_password: true,
        password_reset_by: actor.user_id,
        updated_by: actor.user_id,
      }),
    });
    if (!profileResponse.ok) throw new Error("profile");

    return Response.json({ temporaryPassword });
  } catch {
    return Response.json({ error: "Não foi possível redefinir a senha." }, { status: 500 });
  }
}
