import { getPositionDisplayName, hasPermission } from "../../../lib/access";
import { adminHeaders } from "../../../lib/admin-data";
import {
  ensureRecruitmentProfessionalAuthAccount,
  ProfessionalAccountError,
} from "../../../lib/professional-account";
import { getSessionContext } from "../../../lib/session";
import { getSupabaseAdminConfig } from "../../../lib/supabase-server";

type DecisionInput = {
  applicationId?: unknown;
  decision?: unknown;
  reason?: unknown;
};

type DecisionResult = {
  application_id: string;
  decided_at: string;
  decided_by: string;
  decision: "approved" | "rejected";
  decision_id: number;
  initial_position_id?: number;
  initial_position_name?: string;
  must_change_password?: boolean;
  professional_created_at?: string;
  professional_name?: string;
  professional_passport?: string;
  professional_user_id?: string;
  reason: string | null;
  replayed?: boolean;
};

type ProvisioningStart = {
  application_id: string;
  attempt?: number;
  auth_user_id?: string | null;
  full_name?: string;
  professional_passport?: string;
  professional_user_id?: string;
  replayed?: boolean;
  state: "completed" | "in_progress";
};

type ProvisioningSnapshot = {
  id: string;
  initial_position_id: number | null;
  professional_created_at: string | null;
  professional_passport: string | null;
  professional_user_id: string | null;
  provisioning_error_code: string | null;
  provisioning_state: string;
  review_notes: string | null;
  reviewed_at: string | null;
  reviewed_by: string | null;
  status: string;
};

type ProvisioningFailure = {
  application_id: string;
  error_code?: string;
  state: "completed" | "failed";
};

class RecruitmentProvisioningError extends Error {
  constructor(
    public readonly publicMessage: string,
    public readonly status: number,
    public readonly code: string,
  ) {
    super(publicMessage);
    this.name = "RecruitmentProvisioningError";
  }
}

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "recruitment.manage")) {
    return Response.json({ error: "Você não possui permissão para analisar candidaturas." }, { status: 403 });
  }

  try {
    const body = (await request.json()) as DecisionInput;
    const applicationId = typeof body.applicationId === "string" ? body.applicationId : "";
    const decision = body.decision;
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";

    if (!isUuid(applicationId) || (decision !== "approved" && decision !== "rejected")) {
      return Response.json({ error: "Decisão inválida." }, { status: 400 });
    }
    if (decision === "rejected" && (reason.length < 10 || reason.length > 2000)) {
      return Response.json(
        { error: "Informe um motivo de recusa entre 10 e 2000 caracteres." },
        { status: 400 },
      );
    }

    if (decision === "rejected") {
      return await registerRejection(applicationId, reason, context.profile);
    }
    return await approveAndProvision(applicationId, context.profile);
  } catch {
    return Response.json({ error: "Não foi possível registrar a decisão." }, { status: 400 });
  }
}

async function registerRejection(
  applicationId: string,
  reason: string,
  actor: { display_name: string; passport: string; position_id: number | null; user_id: string },
) {
  const { url, serviceRoleKey } = getSupabaseAdminConfig();
  const response = await callRpc<DecisionResult>(url, serviceRoleKey, "decide_recruitment_application", {
    p_application_id: applicationId,
    p_decision: "rejected",
    p_reason: reason,
    p_actor_id: actor.user_id,
  });

  if (!response.ok || !response.data) {
    return Response.json(
      { error: recruitmentErrorMessage(response.message, "Esta candidatura não está mais disponível para decisão.") },
      { status: response.status },
    );
  }

  const directorPosition = await getPositionDisplayName(actor.position_id).catch(() => null);
  return Response.json(decisionPayload(response.data, actor, directorPosition));
}

async function approveAndProvision(
  applicationId: string,
  actor: { display_name: string; passport: string; position_id: number | null; user_id: string },
) {
  const { url, serviceRoleKey } = getSupabaseAdminConfig();
  const provisioningToken = crypto.randomUUID();
  let claimStarted = false;
  let authUserId: string | null = null;
  let temporaryPassword: string | null = null;

  try {
    const started = await callRpc<ProvisioningStart>(
      url,
      serviceRoleKey,
      "begin_recruitment_professional_provisioning",
      {
        p_application_id: applicationId,
        p_actor_id: actor.user_id,
        p_provisioning_token: provisioningToken,
      },
    );
    if (!started.ok || !started.data) throw provisioningRpcError(started.message, started.status);
    if (started.data.state === "completed") {
      throw new RecruitmentProvisioningError(
        "Esta candidatura já foi aprovada e vinculada ao profissional correspondente.",
        409,
        "already_completed",
      );
    }
    if (!started.data.professional_passport || !started.data.full_name) {
      throw new RecruitmentProvisioningError(
        "A candidatura não possui dados válidos para criar o profissional.",
        400,
        "invalid_application",
      );
    }
    claimStarted = true;

    const authAccount = await ensureRecruitmentProfessionalAuthAccount({
      applicationId,
      knownUserId: started.data.auth_user_id,
      passport: started.data.professional_passport,
    });
    authUserId = authAccount.userId;
    temporaryPassword = authAccount.temporaryPassword;

    const attached = await callRpc(
      url,
      serviceRoleKey,
      "attach_recruitment_provisioning_auth_user",
      {
        p_application_id: applicationId,
        p_actor_id: actor.user_id,
        p_provisioning_token: provisioningToken,
        p_auth_user_id: authUserId,
      },
    );
    if (!attached.ok) throw provisioningRpcError(attached.message, attached.status);

    const completed = await callRpc<DecisionResult>(
      url,
      serviceRoleKey,
      "complete_recruitment_professional_provisioning",
      {
        p_application_id: applicationId,
        p_actor_id: actor.user_id,
        p_provisioning_token: provisioningToken,
        p_auth_user_id: authUserId,
      },
    );
    if (!completed.ok || !completed.data) throw provisioningRpcError(completed.message, completed.status);

    const directorPosition = await getPositionDisplayName(actor.position_id).catch(() => null);
    return Response.json({
      ...decisionPayload(completed.data, actor, directorPosition),
      professional: {
        createdAt: completed.data.professional_created_at,
        initialPosition: completed.data.initial_position_name ?? "Estagiário de Enfermagem",
        name: completed.data.professional_name ?? started.data.full_name,
        passport: completed.data.professional_passport,
        userId: completed.data.professional_user_id,
      },
      temporaryPassword,
    });
  } catch (error) {
    const reconciled = authUserId
      ? await findCompletedProvisioning(url, serviceRoleKey, applicationId, authUserId)
      : null;
    if (reconciled && temporaryPassword) {
      const directorPosition = await getPositionDisplayName(actor.position_id).catch(() => null);
      return Response.json({
        ...decisionPayload(reconciled.result, actor, directorPosition),
        professional: reconciled.professional,
        temporaryPassword,
      });
    }

    const normalizedError = normalizeProvisioningError(error);
    if (claimStarted) {
      const failed = await callRpc<ProvisioningFailure>(
        url,
        serviceRoleKey,
        "fail_recruitment_professional_provisioning",
        {
          p_application_id: applicationId,
          p_actor_id: actor.user_id,
          p_provisioning_token: provisioningToken,
          p_error_code: normalizedError.code,
          p_auth_user_id: authUserId,
        },
      ).catch(() => null);

      if (failed?.ok && failed.data?.state === "completed" && authUserId && temporaryPassword) {
        const completed = await findCompletedProvisioning(url, serviceRoleKey, applicationId, authUserId);
        if (completed) {
          const directorPosition = await getPositionDisplayName(actor.position_id).catch(() => null);
          return Response.json({
            ...decisionPayload(completed.result, actor, directorPosition),
            professional: completed.professional,
            temporaryPassword,
          });
        }
      }
    }

    return Response.json(
      { error: normalizedError.publicMessage },
      { status: normalizedError.status },
    );
  }
}

async function findCompletedProvisioning(
  url: string,
  serviceRoleKey: string,
  applicationId: string,
  authUserId: string,
) {
  try {
    const headers = adminHeaders(serviceRoleKey);
    const applicationResponse = await fetch(
      `${url}/rest/v1/recruitment_applications?select=id,status,review_notes,reviewed_by,reviewed_at,professional_user_id,professional_passport,initial_position_id,professional_created_at,provisioning_state,provisioning_error_code&id=eq.${encodeURIComponent(applicationId)}&limit=1`,
      { headers, cache: "no-store", signal: AbortSignal.timeout(12_000) },
    );
    if (!applicationResponse.ok) return null;
    const applications = (await applicationResponse.json()) as ProvisioningSnapshot[];
    const application = applications[0];
    if (
      !application
      || application.status !== "approved"
      || application.provisioning_state !== "completed"
      || application.professional_user_id !== authUserId
      || !application.reviewed_by
      || !application.reviewed_at
      || !application.professional_passport
      || !application.professional_created_at
      || !application.initial_position_id
    ) return null;

    const [decisionResponse, positionResponse, profileResponse] = await Promise.all([
      fetch(`${url}/rest/v1/recruitment_decisions?select=id,application_id,decision,reason,decided_by,decided_at&application_id=eq.${encodeURIComponent(applicationId)}&decision=eq.approved&order=decided_at.desc,id.desc&limit=1`, { headers, cache: "no-store" }),
      fetch(`${url}/rest/v1/staff_positions?select=name&id=eq.${application.initial_position_id}&limit=1`, { headers, cache: "no-store" }),
      fetch(`${url}/rest/v1/profiles?select=display_name&user_id=eq.${encodeURIComponent(authUserId)}&limit=1`, { headers, cache: "no-store" }),
    ]);
    if (!decisionResponse.ok || !positionResponse.ok || !profileResponse.ok) return null;
    const decisions = (await decisionResponse.json()) as Array<{
      application_id: string;
      decided_at: string;
      decided_by: string;
      decision: "approved";
      id: number;
      reason: null;
    }>;
    const positions = (await positionResponse.json()) as Array<{ name: string }>;
    const profiles = (await profileResponse.json()) as Array<{ display_name: string }>;
    if (!decisions[0] || !positions[0] || !profiles[0]) return null;

    return {
      professional: {
        createdAt: application.professional_created_at,
        initialPosition: positions[0].name,
        name: profiles[0].display_name,
        passport: application.professional_passport,
        userId: authUserId,
      },
      result: {
        application_id: application.id,
        decided_at: decisions[0].decided_at,
        decided_by: decisions[0].decided_by,
        decision: "approved" as const,
        decision_id: decisions[0].id,
        initial_position_id: application.initial_position_id,
        initial_position_name: positions[0].name,
        professional_created_at: application.professional_created_at,
        professional_name: profiles[0].display_name,
        professional_passport: application.professional_passport,
        professional_user_id: authUserId,
        reason: null,
        replayed: true,
      },
    };
  } catch {
    return null;
  }
}

function decisionPayload(
  result: DecisionResult,
  actor: { display_name: string; passport: string },
  directorPosition: string | null,
) {
  return {
    application: {
      id: result.application_id,
      initial_position_id: result.initial_position_id ?? null,
      initial_position_name: result.initial_position_name ?? null,
      professional_created_at: result.professional_created_at ?? null,
      professional_passport: result.professional_passport ?? null,
      professional_user_id: result.professional_user_id ?? null,
      provisioning_error_code: null,
      provisioning_state: result.decision === "approved" ? "completed" : "not_started",
      review_notes: result.reason,
      reviewed_at: result.decided_at,
      reviewed_by: result.decided_by,
      status: result.decision,
    },
    decision: {
      application_id: result.application_id,
      decided_at: result.decided_at,
      decided_by: result.decided_by,
      decision: result.decision,
      director_name: actor.display_name,
      director_passport: actor.passport,
      director_position: directorPosition ?? "Cargo não definido",
      id: result.decision_id,
      reason: result.reason,
    },
  };
}

async function callRpc<T = unknown>(
  url: string,
  serviceRoleKey: string,
  name: string,
  body: Record<string, unknown>,
) {
  try {
    const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
      method: "POST",
      signal: AbortSignal.timeout(25_000),
      headers: adminHeaders(serviceRoleKey),
      body: JSON.stringify(body),
    });
    const payload = await response.json().catch(() => null) as T | { message?: string } | null;
    return {
      data: response.ok ? payload as T : null,
      message: response.ok ? "" : (payload as { message?: string } | null)?.message ?? "",
      ok: response.ok,
      status: response.status === 401 || response.status === 403
        ? 403
        : response.status === 409
          ? 409
          : response.status >= 500
            ? 503
            : 400,
    };
  } catch {
    return { data: null, message: "", ok: false, status: 503 };
  }
}

function provisioningRpcError(message: string, status: number) {
  const publicMessage = recruitmentErrorMessage(message, "Não foi possível concluir o cadastro profissional. Tente novamente.");
  const code = /já existe um profissional/i.test(message)
    ? "professional_duplicate"
    : /passaporte.*inválido/i.test(message)
      ? "invalid_passport"
      : /andamento/i.test(message)
        ? "provisioning_in_progress"
        : "profile_provisioning_failed";
  return new RecruitmentProvisioningError(publicMessage, status, code);
}

function normalizeProvisioningError(error: unknown) {
  if (error instanceof RecruitmentProvisioningError) return error;
  if (error instanceof ProfessionalAccountError) {
    const publicMessage = error.code === "auth_duplicate"
      ? "Já existe uma conta Auth para este passaporte, mas o vínculo com a candidatura não pôde ser confirmado. Resolva o caso administrativamente."
      : error.code === "auth_identity_mismatch"
        ? "A conta Auth encontrada não corresponde com segurança a esta candidatura. Resolva o caso administrativamente."
        : "O serviço de criação de acesso não respondeu. A candidatura foi preservada e pode ser tentada novamente.";
    return new RecruitmentProvisioningError(publicMessage, error.code === "auth_unavailable" ? 503 : 409, error.code);
  }
  return new RecruitmentProvisioningError(
    "Não foi possível concluir o cadastro profissional. A candidatura foi preservada e pode ser tentada novamente.",
    503,
    "provisioning_failed",
  );
}

function recruitmentErrorMessage(message: string, fallback: string) {
  if (/já existe um profissional cadastrado com o passaporte [0-9]{4}/i.test(message)) {
    return message.match(/Já existe um profissional cadastrado com o passaporte [0-9]{4}\./i)?.[0] ?? fallback;
  }
  if (/passaporte.*inválido/i.test(message)) return "O passaporte desta candidatura é inválido para criar uma conta profissional.";
  if (/nome.*incompatível/i.test(message)) return "O nome desta candidatura precisa de correção administrativa antes do cadastro profissional.";
  if (/andamento/i.test(message)) return "O provisionamento desta candidatura já está em andamento. Aguarde e tente novamente.";
  if (/não possui permissão|apenas os cargos/i.test(message)) return "Você não possui permissão para aprovar candidaturas.";
  if (/não está disponível|já decidida/i.test(message)) return "Esta candidatura não está mais disponível para decisão. Atualize a página.";
  return fallback;
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
