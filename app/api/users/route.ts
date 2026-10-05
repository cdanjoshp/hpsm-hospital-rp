import { getSessionProfile } from "../../lib/session";
import { adminHeaders } from "../../lib/admin-data";
import { hasPermission } from "../../lib/access";
import {
  createProfessionalAuthAccount,
  deleteProfessionalAuthAccount,
  ProfessionalAccountError,
} from "../../lib/professional-account";
import { getSupabaseAdminConfig, normalizeProfessionalPassport } from "../../lib/supabase-server";

export async function POST(request: Request) {
  const actor = await getSessionProfile();
  if (!actor) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(actor, "team.manage")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });

  let createdUserId: string | null = null;
  let duplicatePassport = false;
  try {
    const body = (await request.json()) as { displayName?: unknown; passport?: unknown };
    if (typeof body.displayName !== "string" || typeof body.passport !== "string") {
      return Response.json({ error: "Preencha todos os dados do profissional." }, { status: 400 });
    }
    const displayName = body.displayName.trim();
    const passport = normalizeProfessionalPassport(body.passport);
    if (displayName.length < 2 || displayName.length > 80) {
      return Response.json({ error: "Os dados informados não são válidos." }, { status: 400 });
    }

    const { url, serviceRoleKey } = getSupabaseAdminConfig();
    const headers = adminHeaders(serviceRoleKey);
    const [positionResponse, duplicateResponse] = await Promise.all([
      fetch(`${url}/rest/v1/staff_positions?select=id&level=eq.1&active=is.true&limit=1`, { headers }),
      fetch(`${url}/rest/v1/profiles?select=user_id&passport=eq.${encodeURIComponent(passport)}&limit=1`, { headers }),
    ]);
    const startingPositions = positionResponse.ok ? ((await positionResponse.json()) as Array<{ id: number }>) : [];
    if (!startingPositions[0]) return Response.json({ error: "O cargo inicial ainda não está configurado." }, { status: 409 });
    const duplicates = duplicateResponse.ok ? ((await duplicateResponse.json()) as unknown[]) : [];
    if (duplicates.length) return Response.json({ error: "Essa matrícula já está cadastrada." }, { status: 409 });

    const authAccount = await createProfessionalAuthAccount(passport, { origin: "MANUAL" });
    createdUserId = authAccount.userId;

    const profile = {
      user_id: createdUserId,
      passport,
      display_name: displayName,
      position_id: startingPositions[0].id,
      role_code: "funcionario",
      status: "active",
      must_change_password: true,
      created_by: actor.user_id,
      updated_by: actor.user_id,
    };
    const profileResponse = await fetch(`${url}/rest/v1/profiles`, {
      method: "POST",
      headers: { ...headers, prefer: "return=representation" },
      body: JSON.stringify(profile),
    });
    if (!profileResponse.ok) {
      duplicatePassport = profileResponse.status === 409;
      throw new Error("Não foi possível registrar o perfil.");
    }
    const createdProfiles = (await profileResponse.json()) as Array<typeof profile & { created_at: string }>;

    return Response.json({ profile: createdProfiles[0], temporaryPassword: authAccount.temporaryPassword }, { status: 201 });
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
    return Response.json({ error: "Não foi possível criar o acesso. Nenhuma senha foi emitida." }, { status: 500 });
  }
}

export async function PATCH(request: Request) {
  const actor = await getSessionProfile();
  if (!actor) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(actor, "team.manage")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });

  try {
    const body = (await request.json()) as {
      displayName?: unknown;
      status?: unknown;
      userId?: unknown;
    };
    if (
      typeof body.userId !== "string" ||
      typeof body.displayName !== "string" ||
      typeof body.status !== "string"
    ) {
      return Response.json({ error: "Preencha todos os dados do profissional." }, { status: 400 });
    }

    const displayName = body.displayName.trim();
    const allowedStatuses = new Set(["active", "inactive", "suspended"]);
    if (
      displayName.length < 2 ||
      displayName.length > 80 ||
      !allowedStatuses.has(body.status)
    ) {
      return Response.json({ error: "Os dados informados não são válidos." }, { status: 400 });
    }
    if (body.status === "inactive" && !await hasPermission(actor, "team.dismiss")) {
      return Response.json({ error: "Você não possui permissão para desligar colaboradores." }, { status: 403 });
    }

    const { url, serviceRoleKey } = getSupabaseAdminConfig();
    const headers = adminHeaders(serviceRoleKey);
    const targetResponse = await fetch(
      `${url}/rest/v1/profiles?select=user_id,role_code,status&user_id=eq.${encodeURIComponent(body.userId)}&limit=1`,
      { headers },
    );
    const targets = targetResponse.ok
      ? ((await targetResponse.json()) as { role_code: string; status: string; user_id: string }[])
      : [];
    const target = targets[0];
    if (!target) return Response.json({ error: "Profissional não encontrado." }, { status: 404 });
    if (target.role_code === "diretor_geral") {
      return Response.json({ error: "A conta do Diretor Geral é protegida." }, { status: 403 });
    }
    if (target.user_id === actor.user_id && body.status !== "active") {
      return Response.json({ error: "Você não pode bloquear sua própria conta." }, { status: 400 });
    }
    if (target.status === "suspended" && body.status !== "suspended") {
      const reviewResponse = await fetch(
        `${url}/rest/v1/rh_disciplinary_reviews?select=id&employee_id=eq.${encodeURIComponent(body.userId)}&status=in.(pending,suspension_maintained)&limit=1`,
        { headers },
      );
      const pendingReviews = reviewResponse.ok ? ((await reviewResponse.json()) as unknown[]) : [];
      if (pendingReviews.length) {
        return Response.json({ error: "Regularize a suspensão na área de RH antes de alterar este acesso." }, { status: 409 });
      }
    }

    const response = await fetch(`${url}/rest/v1/profiles?user_id=eq.${encodeURIComponent(body.userId)}`, {
      method: "PATCH",
      headers: { ...headers, prefer: "return=representation" },
      body: JSON.stringify({
        display_name: displayName,
        status: body.status,
        updated_by: actor.user_id,
      }),
    });
    if (!response.ok) throw new Error("profile");
    const profiles = (await response.json()) as Array<{
      created_at: string;
      display_name: string;
      must_change_password: boolean;
      passport: string;
      position_id: number | null;
      role_code: string;
      status: string;
      user_id: string;
    }>;
    return Response.json({ profile: profiles[0] });
  } catch {
    return Response.json({ error: "Não foi possível atualizar o profissional." }, { status: 500 });
  }
}
