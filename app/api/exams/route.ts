import { getEffectivePermissionCodes } from "../../lib/access";
import { isClinicalExamStatus } from "../../lib/exam-status";
import { ensureExamDocumentImage } from "../../lib/exam-document-image-service";
import {
  getClinicalExamAttendanceOptions,
  getClinicalExamAiGenerations,
  getClinicalExamDetail,
  getClinicalExamImagingTemplateCatalog,
  getClinicalExamPage,
  getClinicalExamReferenceData,
  getClinicalExamResultState,
  getClinicalExamTemplateCatalog,
  runClinicalExamMutation,
} from "../../lib/exams";
import { getSessionContext } from "../../lib/session";
import { getSupabaseConfig } from "../../lib/supabase-server";
import { enrichClinicalExamIdentities } from "../../lib/professional-identity";
import { getExamCardContexts } from "../../lib/exam-card-context";

export async function GET(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  const permissions = new Set(await getEffectivePermissionCodes(context.profile.user_id));
  const params = new URL(request.url).searchParams;
  const view = params.get("view") ?? "list";

  try {
    if (view === "list") {
      requirePermission(permissions, "exams.view");
      const status = params.get("status");
      if (status && !isClinicalExamStatus(status)) throw new Error("Status de exame inválido.");
      const page = await getClinicalExamPage(context.accessToken, {
        categoryId: numberParam(params.get("categoryId")),
        dateFrom: dateParam(params.get("dateFrom")),
        dateTo: dateParam(params.get("dateTo")),
        examTypeId: numberParam(params.get("examTypeId")),
        page: numberParam(params.get("page")) ?? 1,
        pageSize: numberParam(params.get("pageSize")) ?? 20,
        passport: params.get("passport") ?? "",
        search: params.get("search") ?? "",
        status: status && isClinicalExamStatus(status) ? status : undefined,
      });
      return Response.json({ ...page, contexts: await getExamCardContexts(page.items, permissions) });
    }
    if (view === "detail") {
      requirePermission(permissions, "exams.view");
      const examId = requiredNumber(params.get("id"), "Exame inválido.");
      const [exam, aiGenerations, resultState] = await Promise.all([
        getClinicalExamDetail(context.accessToken, examId),
        getClinicalExamAiGenerations(context.accessToken, examId),
        getClinicalExamResultState(context.accessToken, examId),
      ]);
      const enriched = await enrichClinicalExamIdentities(exam);
      return Response.json({ exam: { ...enriched, ai_generations: aiGenerations, result_state: resultState } });
    }
    if (view === "reference") {
      requireAnyPermission(permissions, ["exams.view", "exams.create", "exams.perform", "exams.review", "exams.catalog.manage"]);
      return Response.json(await getClinicalExamReferenceData(context.accessToken));
    }
    if (view === "templates") {
      requirePermission(permissions, "exams.catalog.manage");
      return Response.json({ templates: await getClinicalExamTemplateCatalog(context.accessToken) });
    }
    if (view === "imaging-templates") {
      requirePermission(permissions, "exams.catalog.manage");
      return Response.json({ templates: await getClinicalExamImagingTemplateCatalog(context.accessToken) });
    }
    if (view === "attendance-options") {
      requirePermission(permissions, "exams.create");
      requirePermission(permissions, "patients.view");
      const patientId = requiredNumber(params.get("patientId"), "Paciente inválido.");
      return Response.json({ attendances: await getClinicalExamAttendanceOptions(context.accessToken, patientId) });
    }
    return Response.json({ error: "Consulta inválida." }, { status: 400 });
  } catch (error) {
    return actionError(error);
  }
}

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  const permissions = new Set(await getEffectivePermissionCodes(context.profile.user_id));

  try {
    const body = await request.json() as Record<string, unknown>;
    const action = stringValue(body.action);
    if (action === "create") {
      requirePermission(permissions, "exams.create");
      requirePermission(permissions, "patients.view");
      const consultationId = optionalNumber(body.consultationId);
      const examId = await runClinicalExamMutation<number>(context.accessToken, consultationId ? "create_consultation_clinical_exam" : "create_clinical_exam", consultationId ? {
        p_attendance_id: optionalNumber(body.attendanceId),
        p_clinical_context: optionalText(body.clinicalContext, 4000),
        p_consultation_id: consultationId,
        p_exam_type_id: requiredBodyNumber(body.examTypeId, "Tipo de exame inválido."),
        p_indication: requiredText(body.indication, "Informe a indicação clínica.", 4000),
        p_initial_result_data: jsonObject(body.initialResultData),
      } : {
        p_attendance_id: optionalNumber(body.attendanceId),
        p_clinical_context: optionalText(body.clinicalContext, 4000),
        p_exam_type_id: requiredBodyNumber(body.examTypeId, "Tipo de exame inválido."),
        p_indication: requiredText(body.indication, "Informe a indicação clínica.", 4000),
        p_initial_result_data: jsonObject(body.initialResultData),
        p_patient_id: requiredBodyNumber(body.patientId, "Paciente inválido."),
        p_responsible_professional_id: context.profile.user_id,
      });
      return Response.json({ examId });
    }
    if (action === "start") {
      requireAnyPermission(permissions, ["exams.perform", "exams.review"]);
      await runClinicalExamMutation(context.accessToken, "start_clinical_exam", { p_exam_id: requiredBodyNumber(body.examId, "Exame inválido.") });
      return Response.json({ ok: true });
    }
    if (action === "save") {
      requireAnyPermission(permissions, ["exams.perform", "exams.review"]);
      await runClinicalExamMutation(context.accessToken, "save_clinical_exam_draft", {
        p_conclusion: optionalText(body.conclusion, 4000),
        p_exam_id: requiredBodyNumber(body.examId, "Exame inválido."),
        p_findings: optionalText(body.findings, 8000),
        p_result_data: jsonObject(body.resultData) ?? { notes: optionalText(body.notes, 12000) ?? "" },
        p_technique: optionalText(body.technique, 4000),
      });
      return Response.json({ ok: true });
    }
    if (action === "submit") {
      requireAnyPermission(permissions, ["exams.perform", "exams.review"]);
      await runClinicalExamMutation(context.accessToken, "submit_clinical_exam_review", { p_exam_id: requiredBodyNumber(body.examId, "Exame inválido.") });
      return Response.json({ ok: true });
    }
    if (action === "review") {
      const decision = stringValue(body.decision);
      if (decision !== "approve" && decision !== "return") throw new Error("Decisão de revisão inválida.");
      if (decision === "return") requirePermission(permissions, "exams.review");
      else requireAnyPermission(permissions, ["exams.create", "exams.perform", "exams.review"]);
      const examId = requiredBodyNumber(body.examId, "Exame inválido.");
      await runClinicalExamMutation(context.accessToken, "review_clinical_exam", {
        p_decision: decision,
        p_exam_id: examId,
        p_reason: optionalText(body.reason, 2000),
      });
      if (decision === "approve") {
        try {
          await ensureExamDocumentImage(context.accessToken, examId, context.profile.user_id);
          return Response.json({ documentReady: true, ok: true });
        } catch {
          return Response.json({
            documentReady: false,
            documentWarning: "Exame aprovado. A publicação automática no FiveManage será retomada pelo sistema ao abrir o documento.",
            ok: true,
          });
        }
      }
      return Response.json({ ok: true });
    }
    if (action === "delete") {
      requireAnyPermission(permissions, ["exams.perform", "exams.review", "exams.delete"]);
      return await deleteClinicalExam(context.accessToken, requiredBodyNumber(body.examId, "Exame inválido."));
    }
    if (action === "category") {
      requirePermission(permissions, "exams.catalog.manage");
      const id = await runClinicalExamMutation<number>(context.accessToken, "manage_exam_category", {
        p_active: booleanValue(body.active, true),
        p_code: requiredText(body.code, "Informe o código da categoria.", 40),
        p_id: optionalNumber(body.id),
        p_name: requiredText(body.name, "Informe o nome da categoria.", 80),
        p_sort_order: integerValue(body.sortOrder, 0),
      });
      return Response.json({ id });
    }
    if (action === "type") {
      requirePermission(permissions, "exams.catalog.manage");
      const id = await runClinicalExamMutation<number>(context.accessToken, "manage_exam_type", {
        p_active: booleanValue(body.active, true),
        p_category_id: requiredBodyNumber(body.categoryId, "Categoria inválida."),
        p_code: requiredText(body.code, "Informe o código do tipo.", 50),
        p_description: optionalText(body.description, 1000),
        p_id: optionalNumber(body.id),
        p_name: requiredText(body.name, "Informe o nome do tipo de exame.", 100),
        p_sort_order: integerValue(body.sortOrder, 0),
      });
      return Response.json({ id });
    }
    if (action === "template") {
      requirePermission(permissions, "exams.catalog.manage");
      const version = await runClinicalExamMutation<number>(context.accessToken, "manage_exam_template", {
        p_exam_type_id: requiredBodyNumber(body.examTypeId, "Tipo de exame inválido."),
        p_expected_version: requiredBodyNumber(body.expectedVersion, "Versão do template inválida."),
        p_parameters: jsonArray(body.parameters, "Parâmetros do template inválidos."),
      });
      return Response.json({ version });
    }
    if (action === "imaging-template") {
      requirePermission(permissions, "exams.catalog.manage");
      const version = await runClinicalExamMutation<number>(context.accessToken, "manage_exam_imaging_template", {
        p_allows_multiple_images: booleanValue(body.allowsMultipleImages, true),
        p_exam_type_id: requiredBodyNumber(body.examTypeId, "Tipo de exame inválido."),
        p_expected_version: requiredBodyNumber(body.expectedVersion, "Versão do template inválida."),
        p_region_options: jsonArray(body.regionOptions, "Regiões do template inválidas."),
        p_region_required: booleanValue(body.regionRequired, true),
        p_requires_image: booleanValue(body.requiresImage, true),
        p_supports_contrast: booleanValue(body.supportsContrast, false),
        p_supports_laterality: booleanValue(body.supportsLaterality, false),
      });
      return Response.json({ version });
    }
    return Response.json({ error: "Ação inválida." }, { status: 400 });
  } catch (error) {
    return actionError(error);
  }
}

async function deleteClinicalExam(accessToken: string, examId: number) {
  const { anonKey, url } = getSupabaseConfig();
  const response = await fetch(`${url}/functions/v1/exam-delete`, {
    method: "POST",
    headers: { apikey: anonKey, authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
    body: JSON.stringify({ examId }),
    cache: "no-store",
    signal: AbortSignal.timeout(30_000),
  });
  const payload = await response.json().catch(() => null) as { error?: string; ok?: boolean } | null;
  if (!response.ok || !payload?.ok) throw new Error(payload?.error ?? "Não foi possível excluir o exame.");
  return Response.json(payload, { headers: { "cache-control": "private, no-store" } });
}

function requirePermission(permissions: Set<string>, permission: string) {
  if (!permissions.has(permission)) throw new ExamAccessError();
}

function requireAnyPermission(permissions: Set<string>, options: string[]) {
  if (!options.some((permission) => permissions.has(permission))) throw new ExamAccessError();
}

class ExamAccessError extends Error {}

function actionError(error: unknown) {
  if (error instanceof ExamAccessError) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
  const message = error instanceof Error ? error.message : "Não foi possível concluir a operação de exames.";
  const forbidden = /acesso não autorizado/i.test(message);
  const conflict = /atualizado por outro profissional/i.test(message);
  const timeout = /demorou para responder/i.test(message);
  return Response.json({ error: forbidden ? "Acesso não autorizado." : message }, { status: forbidden ? 403 : conflict ? 409 : timeout ? 504 : 400 });
}

function numberParam(value: string | null) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : undefined;
}

function requiredNumber(value: string | null, message: string) {
  const result = numberParam(value);
  if (!result) throw new Error(message);
  return result;
}

function requiredBodyNumber(value: unknown, message: string) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new Error(message);
  return parsed;
}

function optionalNumber(value: unknown) {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) throw new Error("Identificador inválido.");
  return parsed;
}

function dateParam(value: string | null) {
  return value && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : undefined;
}

function stringValue(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

function requiredText(value: unknown, message: string, maxLength: number) {
  const result = stringValue(value);
  if (!result) throw new Error(message);
  return result.slice(0, maxLength);
}

function optionalText(value: unknown, maxLength: number) {
  const result = stringValue(value);
  return result ? result.slice(0, maxLength) : null;
}

function integerValue(value: unknown, fallback: number) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : fallback;
}

function booleanValue(value: unknown, fallback: boolean) {
  return typeof value === "boolean" ? value : fallback;
}

function jsonObject(value: unknown) {
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

function jsonArray(value: unknown, message: string) {
  if (!Array.isArray(value) || value.length > 100) throw new Error(message);
  return value;
}
