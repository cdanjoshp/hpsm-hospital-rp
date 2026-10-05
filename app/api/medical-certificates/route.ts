import {
  getMedicalCertificateCidCatalog,
  getMedicalCertificateDetail,
  getMedicalCertificatePage,
  getMedicalCertificateReferenceOptions,
  getPatientMedicalCertificatePage,
  runMedicalCertificateMutation,
  type MedicalCertificateStatus,
} from "../../lib/medical-certificates";
import { ensureMedicalCertificateDocument } from "../../lib/medical-certificate-document-service";
import { getSessionBootstrap } from "../../lib/session";

export async function GET(request: Request) {
  const context = await getSessionBootstrap();
  if (!context) return responseError("Sessão expirada.", 401);
  const permissions = new Set(context.permissionCodes);
  const params = new URL(request.url).searchParams;
  const view = params.get("view") ?? "list";
  try {
    requirePermission(permissions, "atestados.view");
    if (view === "list") {
      const status = optionalStatus(params.get("status"));
      return Response.json(await getMedicalCertificatePage(context.accessToken, {
        createdBy: params.get("createdBy"),
        dateFrom: optionalDate(params.get("dateFrom")),
        dateTo: optionalDate(params.get("dateTo")),
        page: positiveInteger(params.get("page")) ?? 1,
        pageSize: positiveInteger(params.get("pageSize")) ?? 20,
        search: params.get("search") ?? "",
        status,
      }), { headers: privateHeaders() });
    }
    if (view === "detail") {
      return Response.json({ certificate: await getMedicalCertificateDetail(context.accessToken, requiredInteger(params.get("id"), "Atestado inválido.")) }, { headers: privateHeaders() });
    }
    if (view === "options") {
      requirePermission(permissions, "atestados.create");
      requirePermission(permissions, "patients.view");
      const [options, cids] = await Promise.all([
        getMedicalCertificateReferenceOptions(context.accessToken, requiredInteger(params.get("patientId"), "Paciente inválido.")),
        getMedicalCertificateCidCatalog(context.accessToken),
      ]);
      return Response.json({ ...options, cids }, { headers: privateHeaders() });
    }
    if (view === "cid") {
      requirePermission(permissions, "atestados.create");
      return Response.json({ cids: await getMedicalCertificateCidCatalog(context.accessToken, params.get("search") ?? "") }, { headers: privateHeaders() });
    }
    if (view === "patient") {
      requirePermission(permissions, "patients.view");
      return Response.json(await getPatientMedicalCertificatePage(
        context.accessToken,
        requiredInteger(params.get("patientId"), "Paciente inválido."),
        positiveInteger(params.get("page")) ?? 1,
        positiveInteger(params.get("pageSize")) ?? 10,
      ), { headers: privateHeaders() });
    }
    return responseError("Consulta inválida.", 400);
  } catch (error) {
    return actionError(error);
  }
}

export async function POST(request: Request) {
  const context = await getSessionBootstrap();
  if (!context) return responseError("Sessão expirada.", 401);
  const permissions = new Set(context.permissionCodes);
  try {
    const body = await request.json() as Record<string, unknown>;
    const action = text(body.action);
    if (action === "create") {
      requirePermission(permissions, "atestados.create");
      requirePermission(permissions, "patients.view");
      const consultationId = optionalInteger(body.consultationId);
      const common = {
        p_cast_ids: integerArray(body.castIds),
        p_exam_ids: integerArray(body.examIds),
        p_leave_days: requiredInteger(body.leaveDays, "Informe uma quantidade inteira e positiva de dias."),
        p_medical_context: requiredText(body.medicalContext, "Informe o motivo e o contexto médico.", 4_000),
      };
      const certificateId = consultationId
        ? await runMedicalCertificateMutation<number>(context.accessToken, "create_consultation_medical_certificate", { ...common, p_consultation_id: consultationId })
        : await runMedicalCertificateMutation<number>(context.accessToken, "create_medical_certificate", {
          ...common,
          p_attendance_id: requiredInteger(body.attendanceId, "Selecione um atendimento concluído."),
          p_patient_id: requiredInteger(body.patientId, "Paciente inválido."),
        });
      return Response.json({ certificateId }, { status: 201, headers: privateHeaders() });
    }
    if (action === "update") {
      requirePermission(permissions, "atestados.create");
      await runMedicalCertificateMutation(context.accessToken, "update_medical_certificate_v2", {
        p_cast_ids: integerArray(body.castIds),
        p_certificate_id: requiredInteger(body.certificateId, "Atestado inválido."),
        p_cid_code: requiredText(body.cidCode, "Selecione um CID-10 válido.", 8),
        p_diagnosis_text: requiredText(body.diagnosisText, "Informe o diagnóstico do atestado.", 500),
        p_exam_ids: integerArray(body.examIds),
        p_final_text: optionalText(body.finalText, 4_000),
        p_leave_days: requiredInteger(body.leaveDays, "Informe uma quantidade inteira e positiva de dias."),
        p_medical_context: requiredText(body.medicalContext, "Informe o motivo e o contexto médico.", 4_000),
      });
      return Response.json({ ok: true }, { headers: privateHeaders() });
    }
    if (action === "update-context") {
      requirePermission(permissions, "atestados.create");
      await runMedicalCertificateMutation(context.accessToken, "update_medical_certificate", {
        p_cast_ids: integerArray(body.castIds),
        p_certificate_id: requiredInteger(body.certificateId, "Atestado inválido."),
        p_exam_ids: integerArray(body.examIds),
        p_final_text: null,
        p_leave_days: requiredInteger(body.leaveDays, "Informe uma quantidade inteira e positiva de dias."),
        p_medical_context: requiredText(body.medicalContext, "Informe o motivo e o contexto médico.", 4_000),
      });
      return Response.json({ ok: true }, { headers: privateHeaders() });
    }
    if (action === "finalize") {
      requirePermission(permissions, "atestados.finalize");
      const certificateId = requiredInteger(body.certificateId, "Atestado inválido.");
      await runMedicalCertificateMutation(context.accessToken, "finalize_medical_certificate", {
        p_certificate_id: certificateId,
        p_final_text: requiredText(body.finalText, "Revise o texto final do atestado.", 4_000),
      });
      try {
        const state = await ensureMedicalCertificateDocument(context.accessToken, certificateId, context.profile.user_id);
        return Response.json({ documentReady: Boolean(state.document), ok: true }, { headers: privateHeaders() });
      } catch {
        return Response.json({ documentReady: false, ok: true, warning: "O atestado foi finalizado e preservado. A publicação automática no FiveManage será retomada pelo sistema ao reabrir o documento." }, { headers: privateHeaders() });
      }
    }
    if (action === "cancel") {
      requirePermission(permissions, "atestados.cancel");
      await runMedicalCertificateMutation(context.accessToken, "cancel_medical_certificate", {
        p_certificate_id: requiredInteger(body.certificateId, "Atestado inválido."),
        p_reason: requiredText(body.reason, "Informe o motivo do cancelamento.", 500),
      });
      return Response.json({ ok: true }, { headers: privateHeaders() });
    }
    return responseError("Ação inválida.", 400);
  } catch (error) {
    return actionError(error);
  }
}

function optionalStatus(value: string | null): MedicalCertificateStatus | null {
  if (!value || value === "all") return null;
  if (value === "draft" || value === "finalized" || value === "cancelled") return value;
  throw new Error("Status de atestado inválido.");
}
function optionalDate(value: string | null) { if (!value) return null; if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error("Data inválida."); return value; }
function integerArray(value: unknown) { if (value == null) return []; if (!Array.isArray(value) || value.length > 50) throw new Error("Vínculos inválidos."); const items = value.map((item) => requiredInteger(item, "Vínculos inválidos.")); return [...new Set(items)]; }
function positiveInteger(value: unknown) { const parsed = Number(value); return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null; }
function requiredInteger(value: unknown, message: string) { const parsed = positiveInteger(value); if (!parsed) throw new Error(message); return parsed; }
function optionalInteger(value: unknown) { return value === null || value === undefined || value === "" ? null : requiredInteger(value, "Identificador inválido."); }
function text(value: unknown) { return typeof value === "string" ? value.trim() : ""; }
function requiredText(value: unknown, message: string, max: number) { const result = text(value); if (!result || result.length > max) throw new Error(message); return result; }
function optionalText(value: unknown, max: number) { const result = text(value); if (result.length > max) throw new Error("Texto muito extenso."); return result || null; }
function requirePermission(permissions: Set<string>, code: string) { if (!permissions.has(code)) throw new Error("Acesso não autorizado."); }
function privateHeaders() { return { "cache-control": "private, no-store", "x-content-type-options": "nosniff" }; }
function responseError(error: string, status: number) { return Response.json({ error }, { status, headers: privateHeaders() }); }
function actionError(error: unknown) { const message = error instanceof Error ? error.message : "Não foi possível concluir a operação."; const forbidden = /acesso não autorizado|somente o responsável/i.test(message); const conflict = /já foi|já possui|somente rascunhos|não aceita|finalizado|cancelado/i.test(message); return responseError(forbidden ? "Acesso não autorizado." : message, forbidden ? 403 : conflict ? 409 : 400); }
