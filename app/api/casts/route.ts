import { ActiveCastDuplicateError, getClinicalCastAttendanceOptions, getClinicalCastDetail, getClinicalCastPatientPage, getClinicalCastReferences, runClinicalCastMutation } from "../../lib/casts";
import { isCastBodyModel, isCastBodyRegion, isCastLaterality, isClinicalCastStatus } from "../../lib/cast-types";
import { getSessionBootstrap } from "../../lib/session";
import { expectedCastRemovalAt, isCastDurationDays } from "../../lib/cast-duration";

export async function GET(request: Request) {
  const context = await getSessionBootstrap();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  const permissions = new Set(context.permissionCodes);
  const params = new URL(request.url).searchParams;
  const view = params.get("view") ?? "list";

  try {
    if (view === "list") {
      requirePermission(permissions, "casts.view");
      const rawStatus = params.get("status");
      const status = rawStatus === "all" || rawStatus === null ? null : rawStatus;
      if (status !== null && !isClinicalCastStatus(status)) throw new Error("Status de gesso inválido.");
      return Response.json(await getClinicalCastPatientPage(context.accessToken, {
        page: positiveNumber(params.get("page")) ?? 1,
        pageSize: positiveNumber(params.get("pageSize")) ?? 20,
        search: params.get("search") ?? "",
        status,
      }));
    }
    if (view === "detail") {
      requirePermission(permissions, "casts.view");
      return Response.json({ cast: await getClinicalCastDetail(context.accessToken, requiredNumber(params.get("id"), "Registro de gesso inválido.")) });
    }
    if (view === "attendance-options") {
      requirePermission(permissions, "casts.create");
      requirePermission(permissions, "patients.view");
      return Response.json({ attendances: await getClinicalCastAttendanceOptions(context.accessToken, requiredNumber(params.get("patientId"), "Paciente inválido.")) });
    }
    if (view === "references") {
      requirePermission(permissions, "casts.view");
      const includeInactive = params.get("includeInactive") === "true";
      if (includeInactive) requirePermission(permissions, "casts.manage");
      return Response.json({ references: await getClinicalCastReferences(context.accessToken, includeInactive) });
    }
    return Response.json({ error: "Consulta inválida." }, { status: 400 });
  } catch (error) {
    return castActionError(error);
  }
}

export async function POST(request: Request) {
  const context = await getSessionBootstrap();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  const permissions = new Set(context.permissionCodes);

  try {
    const body = await request.json() as Record<string, unknown>;
    const action = text(body.action);
    if (action === "create") {
      requirePermission(permissions, "casts.create");
      requirePermission(permissions, "patients.view");
      const bodyRegion = text(body.bodyRegion);
      const laterality = text(body.laterality);
      const bodyModel = text(body.bodyModel);
      if (!isCastBodyModel(bodyModel)) throw new Error("Modelo inválido.");
      if (!isCastBodyRegion(bodyRegion)) throw new Error("Região inválida.");
      if (!isCastLaterality(laterality)) throw new Error("Lateralidade inválida.");
      const appliedAt = requiredTimestamp(body.appliedAt, "Informe a data e hora da aplicação.");
      if (!isCastDurationDays(body.castDays)) throw new Error("Selecione de 1 a 5 dias de gesso.");
      const expectedRemovalAt = expectedCastRemovalAt(appliedAt, body.castDays);
      if (!expectedRemovalAt) throw new Error("Informe a data e hora da aplicação.");
      const castId = await runClinicalCastMutation<number>(context.accessToken, "create_clinical_cast", {
        p_applied_at: appliedAt,
        p_application_notes: optionalText(body.applicationNotes, 1000),
        p_attendance_id: optionalNumber(body.attendanceId),
        p_body_model: bodyModel,
        p_body_region: bodyRegion,
        p_confirm_duplicate: body.confirmDuplicate === true,
        p_expected_removal_at: expectedRemovalAt,
        p_laterality: laterality,
        p_patient_id: requiredBodyNumber(body.patientId, "Paciente inválido."),
      });
      const consultationId = optionalNumber(body.consultationId);
      if (consultationId) await runClinicalCastMutation(context.accessToken, "link_consultation_cast", { p_cast_id: castId, p_consultation_id: consultationId });
      return Response.json({ castId });
    }
    if (action === "save-reference") {
      requirePermission(permissions, "casts.manage");
      const bodyModel = text(body.bodyModel);
      const bodyRegion = text(body.bodyRegion);
      const laterality = text(body.laterality);
      if (!isCastBodyModel(bodyModel)) throw new Error("Modelo inválido.");
      if (!["arm", "leg", "rib"].includes(bodyRegion) || !isCastBodyRegion(bodyRegion)) throw new Error("Região inválida.");
      if (!isCastLaterality(laterality)) throw new Error("Lateralidade inválida.");
      if (typeof body.active !== "boolean") throw new Error("Situação da referência inválida.");
      const reference = await runClinicalCastMutation(context.accessToken, "upsert_clinical_cast_reference", {
        p_active: body.active,
        p_body_model: bodyModel,
        p_body_region: bodyRegion,
        p_description: boundedText(body.description, "Informe a descrição.", 2, 160),
        p_game_reference: boundedText(body.gameReference, "Informe o ID no jogo.", 1, 80),
        p_laterality: laterality,
        p_reference_id: optionalNumber(body.referenceId),
      });
      return Response.json({ reference });
    }
    if (action === "update-expected-removal") {
      requireAnyPermission(permissions, ["casts.create", "casts.manage"]);
      if (!isCastDurationDays(body.castDays)) throw new Error("Selecione de 1 a 5 dias de gesso.");
      const castId = requiredBodyNumber(body.castId, "Registro de gesso inválido.");
      const cast = await getClinicalCastDetail(context.accessToken, castId);
      const expectedRemovalAt = expectedCastRemovalAt(cast.applied_at, body.castDays);
      if (!expectedRemovalAt) throw new Error("Data de aplicação inválida no registro de gesso.");
      await runClinicalCastMutation(context.accessToken, "update_clinical_cast_expected_removal", {
        p_cast_id: castId,
        p_expected_removal_at: expectedRemovalAt,
        p_reason: requiredText(body.reason, "Informe o motivo da alteração.", 500),
      });
      return Response.json({ ok: true });
    }
    if (action === "remove") {
      requirePermission(permissions, "casts.remove");
      await runClinicalCastMutation(context.accessToken, "remove_clinical_cast", {
        p_cast_id: requiredBodyNumber(body.castId, "Registro de gesso inválido."),
        p_removal_notes: optionalText(body.removalNotes, 1000),
        p_removed_at: requiredTimestamp(body.removedAt, "Informe a data e hora da retirada."),
      });
      return Response.json({ ok: true });
    }
    if (action === "cancel") {
      requirePermission(permissions, "casts.manage");
      await runClinicalCastMutation(context.accessToken, "cancel_clinical_cast", {
        p_cast_id: requiredBodyNumber(body.castId, "Registro de gesso inválido."),
        p_reason: requiredText(body.reason, "Informe o motivo do cancelamento.", 500),
      });
      return Response.json({ ok: true });
    }
    return Response.json({ error: "Ação inválida." }, { status: 400 });
  } catch (error) {
    return castActionError(error);
  }
}

function castActionError(error: unknown) {
  if (error instanceof CastAccessError) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
  if (error instanceof ActiveCastDuplicateError) {
    return Response.json({ code: "active_cast_duplicate", error: error.message || "O paciente já possui um gesso em uso na mesma região e lateralidade." }, { status: 409 });
  }
  const message = error instanceof Error ? error.message : "Não foi possível concluir a operação de gesso.";
  const forbidden = /acesso não autorizado|sessão inválida|sessão expirada/i.test(message);
  const conflict = /já foi retirado|já foi encerrado|já existe uma referência|somente um gesso em uso|atualizado por outro/i.test(message);
  const notFound = /não localizado/i.test(message);
  const timeout = /demorou para responder/i.test(message);
  return Response.json({ error: forbidden ? "Acesso não autorizado." : message }, { status: forbidden ? 403 : notFound ? 404 : conflict ? 409 : timeout ? 504 : 400 });
}

function requirePermission(permissions: Set<string>, permission: string) {
  if (!permissions.has(permission)) throw new CastAccessError();
}

function requireAnyPermission(permissions: Set<string>, options: string[]) {
  if (!options.some((permission) => permissions.has(permission))) throw new CastAccessError();
}

class CastAccessError extends Error {}

function positiveNumber(value: string | null) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : undefined;
}

function requiredNumber(value: string | null, message: string) {
  const result = positiveNumber(value);
  if (!result) throw new Error(message);
  return result;
}

function requiredBodyNumber(value: unknown, message: string) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) throw new Error(message);
  return parsed;
}

function optionalNumber(value: unknown) {
  if (value === null || value === undefined || value === "") return null;
  return requiredBodyNumber(value, "Identificador inválido.");
}

function text(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function requiredText(value: unknown, message: string, maxLength: number) {
  const result = text(value);
  if (result.length < 2) throw new Error(message);
  if (result.length > maxLength) throw new Error(`O texto deve ter no máximo ${maxLength} caracteres.`);
  return result;
}

function optionalText(value: unknown, maxLength: number) {
  const result = text(value);
  if (!result) return null;
  if (result.length < 2) throw new Error("A observação deve ter ao menos 2 caracteres.");
  if (result.length > maxLength) throw new Error(`A observação deve ter no máximo ${maxLength} caracteres.`);
  return result;
}

function boundedText(value: unknown, message: string, minLength: number, maxLength: number) {
  const result = text(value);
  if (result.length < minLength) throw new Error(message);
  if (result.length > maxLength) throw new Error(`O texto deve ter no máximo ${maxLength} caracteres.`);
  return result;
}

function requiredTimestamp(value: unknown, message: string) {
  const source = text(value);
  const parsed = Date.parse(source);
  if (!source || !Number.isFinite(parsed)) throw new Error(message);
  return new Date(parsed).toISOString();
}
