import {
  ConsultationRpcError,
  getConsultationDetail,
  getConsultationPage,
  getConsultationReferences,
  runConsultationMutation,
  type AppointmentStatus,
  type ComplementaryAction,
  type ConsultationDiagnosis,
} from "../../lib/consultations";
import { resolveConsultationComplementaryAction } from "../../lib/consultation-complementary-action";
import { ensureConsultationDocument } from "../../lib/consultation-document-service";
import { ensurePrescriptionDocument } from "../../lib/prescription-document-service";
import { getSessionBootstrap } from "../../lib/session";
import { getSupabaseConfig } from "../../lib/supabase-server";

export async function GET(request: Request) {
  const context = await getSessionBootstrap();
  if (!context) return responseError("Sessão expirada.", 401);
  const permissions = new Set(context.permissionCodes);
  if (!permissions.has("consultations.view")) return responseError("Acesso não autorizado.", 403);
  const params = new URL(request.url).searchParams;
  try {
    const view = params.get("view") ?? "list";
    if (view === "reference") return Response.json(await getConsultationReferences(context.accessToken), { headers: privateHeaders() });
    if (view === "detail") return Response.json({ consultation: await getConsultationDetail(context.accessToken, requiredInteger(params.get("id"), "Consulta inválida.")) }, { headers: privateHeaders() });
    if (view === "list") return Response.json(await getConsultationPage(context.accessToken, {
      dateFrom: timestamp(params.get("dateFrom")),
      dateTo: timestamp(params.get("dateTo")),
      mine: params.get("mine") === "true",
      page: positiveInteger(params.get("page")) ?? 1,
      pageSize: positiveInteger(params.get("pageSize")) ?? 50,
      professionalId: uuid(params.get("professionalId")),
      search: params.get("search") ?? "",
      status: appointmentStatus(params.get("status")),
    }), { headers: privateHeaders() });
    return responseError("Consulta inválida.", 400);
  } catch (error) { return actionError(error); }
}

export async function POST(request: Request) {
  const context = await getSessionBootstrap();
  if (!context) return responseError("Sessão expirada.", 401);
  const permissions = new Set(context.permissionCodes);
  try {
    const body = await request.json() as Record<string, unknown>;
    const action = text(body.action);
    if (action === "schedule") {
      requirePermission(permissions, "consultations.create");
      const appointmentId = await runConsultationMutation<number>(context.accessToken, "create_patient_appointment", {
        p_duration_minutes: requiredInteger(body.durationMinutes, "Informe a duração."),
        p_follow_up_of_consultation_id: optionalInteger(body.followUpOfConsultationId),
        p_notes: optionalText(body.notes, 4_000),
        p_patient_id: requiredInteger(body.patientId, "Selecione um paciente."),
        p_professional_id: uuidValue(body.professionalId) || context.profile.user_id,
        p_reason: requiredText(body.reason, "Informe o motivo da consulta.", 500),
        p_scheduled_start: requiredTimestamp(body.scheduledStart, "Informe a data e hora da consulta."),
      });
      return Response.json({ appointmentId }, { status: 201, headers: privateHeaders() });
    }
    if (action === "status") {
      requirePermission(permissions, "consultations.create");
      const status = text(body.status);
      if (!(["confirmed", "cancelled", "no_show"] as string[]).includes(status)) throw new Error("Status inválido.");
      await runConsultationMutation(context.accessToken, "set_patient_appointment_status", {
        p_appointment_id: requiredInteger(body.appointmentId, "Agendamento inválido."),
        p_reason: optionalText(body.reason, 500), p_status: status,
      });
      return Response.json({ ok: true }, { headers: privateHeaders() });
    }
    if (action === "start") {
      requirePermission(permissions, "consultations.create");
      const consultationId = await runConsultationMutation<number>(context.accessToken, "start_scheduled_consultation", { p_appointment_id: requiredInteger(body.appointmentId, "Agendamento inválido.") });
      return Response.json({ consultationId }, { headers: privateHeaders() });
    }
    if (action === "walk-in") {
      requirePermission(permissions, "consultations.create");
      const consultationId = await runConsultationMutation<number>(context.accessToken, "start_walk_in_consultation", { p_patient_id: requiredInteger(body.patientId, "Selecione um paciente.") });
      return Response.json({ consultationId }, { status: 201, headers: privateHeaders() });
    }
    if (action === "save") {
      requirePermission(permissions, "consultations.complete");
      const diagnosis = diagnosisValue(body.selectedDiagnosis);
      await runConsultationMutation(context.accessToken, "save_clinical_consultation_draft", {
        p_anamnesis: optionalText(body.anamnesis, 12_000),
        p_blood_pressure_class: optionalText(body.bloodPressureClass, 40),
        p_blood_pressure_diastolic: optionalInteger(body.bloodPressureDiastolic),
        p_blood_pressure_systolic: optionalInteger(body.bloodPressureSystolic),
        p_complementary_action: complementaryAction(body.complementaryAction),
        p_consultation_id: requiredInteger(body.consultationId, "Consulta inválida."),
        p_final_diagnosis_plan: optionalText(body.finalDiagnosisPlan, 12_000),
        p_heart_rate_bpm: optionalInteger(body.heartRate),
        p_heart_rate_class: optionalText(body.heartRateClass, 40),
        p_orientation_text: optionalText(body.orientationText, 12_000),
        p_oxygen_saturation_class: optionalText(body.oxygenSaturationClass, 40),
        p_oxygen_saturation_percent: optionalInteger(body.oxygenSaturation),
        p_pain_score: optionalIntegerAllowZero(body.painScore),
        p_selected_diagnosis: diagnosis,
        p_temperature_c: optionalNumber(body.temperature),
        p_temperature_class: optionalText(body.temperatureClass, 40),
      });
      return Response.json({ ok: true }, { headers: privateHeaders() });
    }
    if (action === "select-diagnosis") {
      requirePermission(permissions, "consultations.complete");
      const diagnosis = diagnosisValue(body.selectedDiagnosis);
      if (!diagnosis) throw new Error("Selecione uma hipótese diagnóstica.");
      const finalDiagnosisPlan = requiredText(body.finalDiagnosisPlan, "Informe o diagnóstico final e o plano.", 12_000);
      const resolvedComplementaryAction = resolveConsultationComplementaryAction(
        diagnosis,
        complementaryAction(body.complementaryAction),
        finalDiagnosisPlan,
      );
      const result = await runConsultationMutation<Record<string, unknown>>(context.accessToken, "select_consultation_diagnosis", {
        p_complementary_action: resolvedComplementaryAction,
        p_consultation_id: requiredInteger(body.consultationId, "Consulta inválida."),
        p_final_diagnosis_plan: finalDiagnosisPlan,
        p_orientation_text: requiredText(body.orientationText, "Informe as orientações ao paciente.", 12_000),
        p_selected_diagnosis: diagnosis,
      });
      return Response.json({ ok: true, ...result }, { headers: privateHeaders() });
    }
    if (action === "complete") {
      requirePermission(permissions, "consultations.complete");
      const consultationId = requiredInteger(body.consultationId, "Consulta inválida.");
      const snapshot = await runConsultationMutation<Record<string, unknown>>(context.accessToken, "complete_clinical_consultation", { p_consultation_id: consultationId });
      const hasPrescription = snapshotHasPrescription(snapshot);
      const [documentResult, prescriptionResult] = await Promise.allSettled([
        ensureConsultationDocument(context.accessToken, consultationId, context.profile.user_id),
        hasPrescription ? ensurePrescriptionDocument(context.accessToken, consultationId, context.profile.user_id) : Promise.resolve(null),
      ]);
      const documentReady = documentResult.status === "fulfilled";
      const prescriptionReady = hasPrescription && prescriptionResult.status === "fulfilled";
      return Response.json({
        documentReady,
        documentWarning: documentReady && (!hasPrescription || prescriptionReady)
          ? undefined
          : "Consulta concluída. Os documentos foram preservados e a publicação automática no FiveManage será retomada pelo sistema ao reabrir a consulta.",
        ok: true,
        prescriptionReady,
        snapshot,
      }, { headers: privateHeaders() });
    }
    if (action === "delete") {
      requirePermission(permissions, "consultations.delete");
      if (context.positionLevel !== 13 && context.positionLevel !== 14) throw new AccessError();
      return await deleteClinicalConsultation(context.accessToken, requiredInteger(body.consultationId, "Consulta inválida."));
    }
    if (action === "delete-terminal-appointment") {
      requirePermission(permissions, "consultations.delete");
      if (context.positionLevel !== 14) throw new AccessError();
      const result = await runConsultationMutation<{ appointment_id: number; deleted: boolean }>(
        context.accessToken,
        "delete_terminal_patient_appointment",
        { p_appointment_id: requiredInteger(body.appointmentId, "Agendamento inválido.") },
      );
      return Response.json({ ok: true, ...result }, { headers: privateHeaders() });
    }
    if (action === "exam") {
      requirePermission(permissions, "consultations.complete"); requirePermission(permissions, "exams.create");
      const examId = await runConsultationMutation<number>(context.accessToken, "create_consultation_clinical_exam", {
        p_clinical_context: optionalText(body.clinicalContext, 4_000),
        p_consultation_id: requiredInteger(body.consultationId, "Consulta inválida."),
        p_exam_type_id: requiredInteger(body.examTypeId, "Tipo de exame inválido."),
        p_indication: requiredText(body.indication, "Informe a indicação clínica.", 2_000),
      });
      return Response.json({ examId }, { status: 201, headers: privateHeaders() });
    }
    return responseError("Ação inválida.", 400);
  } catch (error) { return actionError(error); }
}

async function deleteClinicalConsultation(accessToken: string, consultationId: number) {
  const { anonKey, url } = getSupabaseConfig();
  const response = await fetch(`${url}/functions/v1/consultation-delete`, {
    method: "POST",
    headers: { apikey: anonKey, authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
    body: JSON.stringify({ consultationId }),
    cache: "no-store",
    signal: AbortSignal.timeout(40_000),
  });
  const payload = await response.json().catch(() => null) as { error?: string; ok?: boolean } | null;
  if (!response.ok || !payload?.ok) throw new Error(payload?.error ?? "Não foi possível excluir a consulta.");
  return Response.json(payload, { headers: privateHeaders() });
}

function requirePermission(permissions: Set<string>, code: string) { if (!permissions.has(code)) throw new AccessError(); }
function text(value: unknown) { return typeof value === "string" ? value.trim() : ""; }
function positiveInteger(value: unknown) { const parsed = Number(value); return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null; }
function requiredInteger(value: unknown, message: string) { const result = positiveInteger(value); if (!result) throw new Error(message); return result; }
function optionalInteger(value: unknown) { return value === null || value === undefined || value === "" ? null : requiredInteger(value, "Valor inválido."); }
function optionalIntegerAllowZero(value: unknown) { if (value === null || value === undefined || value === "") return null; const parsed = Number(value); if (!Number.isSafeInteger(parsed) || parsed < 0) throw new Error("Valor inválido."); return parsed; }
function optionalNumber(value: unknown) { if (value === null || value === undefined || value === "") return null; const parsed = Number(value); if (!Number.isFinite(parsed)) throw new Error("Valor inválido."); return parsed; }
function requiredText(value: unknown, message: string, max: number) { const result = text(value); if (result.length < 3 || result.length > max) throw new Error(message); return result; }
function optionalText(value: unknown, max: number) { const result = text(value); if (result.length > max) throw new Error("Texto muito extenso."); return result || null; }
function requiredTimestamp(value: unknown, message: string) { const result = text(value); if (!result || Number.isNaN(Date.parse(result))) throw new Error(message); return new Date(result).toISOString(); }
function timestamp(value: string | null) { if (!value) return null; if (Number.isNaN(Date.parse(value))) throw new Error("Data inválida."); return new Date(value).toISOString(); }
function uuid(value: string | null) { return value ? uuidValue(value) : null; }
function uuidValue(value: unknown) { const result = text(value); if (!result) return null; if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(result)) throw new Error("Profissional inválido."); return result; }
function appointmentStatus(value: string | null): AppointmentStatus | null { if (!value || value === "all") return null; if (["scheduled", "confirmed", "in_progress", "completed", "cancelled", "no_show"].includes(value)) return value as AppointmentStatus; throw new Error("Status inválido."); }
function complementaryAction(value: unknown): ComplementaryAction { const result = text(value) || "NONE"; if (result === "NONE" || result === "CAST" || result === "HOSPITALIZATION") return result; throw new Error("Conduta complementar inválida."); }
function diagnosisValue(value: unknown): ConsultationDiagnosis | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== "object" || Array.isArray(value)) throw new Error("Diagnóstico inválido.");
  const item = value as Record<string, unknown>;
  const severity = text(item.severity);
  const diagnosis = text(item.diagnosis) || text(item.title);
  if (!["normal", "grave", "gravissimo"].includes(severity) || diagnosis.length < 3 || diagnosis.length > 500) throw new Error("Diagnóstico inválido.");
  const complementary = item.complementary_action === undefined ? undefined : complementaryAction(item.complementary_action);
  return {
    severity: severity as ConsultationDiagnosis["severity"],
    diagnosis: text(item.diagnosis) || undefined,
    reasoning_summary: optionalText(item.reasoning_summary, 2_000) ?? undefined,
    final_plan: optionalText(item.final_plan, 12_000) ?? undefined,
    complementary_action: complementary,
    ...(item.complementary_action_dismissed === true ? { complementary_action_dismissed: true } : {}),
    orientation: optionalText(item.orientation, 12_000) ?? undefined,
    medication_suggestions: medicationSuggestions(item.medication_suggestions),
    title: text(item.title) || undefined,
    rationale: optionalText(item.rationale, 2_000) ?? undefined,
  };
}
function medicationSuggestions(value: unknown) {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 5) throw new Error("Sugestões de medicamentos inválidas.");
  const seen = new Set<string>();
  return value.map((entry) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) throw new Error("Sugestão de medicamento inválida.");
    const item = entry as Record<string, unknown>;
    const medicationId = text(item.medication_id).toUpperCase();
    const reason = requiredText(item.reason, "Informe o motivo da sugestão de medicamento.", 1_000);
    if (!/^[A-Z0-9_]{3,40}$/.test(medicationId) || seen.has(medicationId)) throw new Error("Sugestão de medicamento inválida.");
    seen.add(medicationId);
    return { medication_id: medicationId, reason };
  });
}
function snapshotHasPrescription(snapshot: Record<string, unknown>) {
  const prescription = snapshot.prescription;
  return Boolean(prescription && typeof prescription === "object" && !Array.isArray(prescription) && Array.isArray((prescription as Record<string, unknown>).items) && ((prescription as Record<string, unknown>).items as unknown[]).length);
}
function privateHeaders() { return { "cache-control": "private, no-store", "x-content-type-options": "nosniff" }; }
function responseError(error: string, status: number) { return Response.json({ error }, { status, headers: privateHeaders() }); }
function actionError(error: unknown) { const message = error instanceof Error ? error.message : "Não foi possível concluir a operação."; const forbidden = error instanceof AccessError || /acesso não autorizado|somente o profissional|somente o Diretor Geral|sessão/i.test(message); const conflict = error instanceof ConsultationRpcError && error.code === "23P01"; const notFound = /não localizad/i.test(message); return responseError(forbidden ? "Acesso não autorizado." : message, forbidden ? 403 : conflict ? 409 : notFound ? 404 : 400); }
class AccessError extends Error {}
