import {
  getHospitalBedBoard,
  getHospitalizationHistory,
  getPatientHospitalizationHistory,
  HospitalizationConflictError,
  runHospitalizationMutation,
  type HospitalizationSource,
  type HospitalizationStatus,
} from "../../lib/hospitalizations";
import { getSessionBootstrap } from "../../lib/session";

export async function GET(request: Request) {
  const context = await getSessionBootstrap();
  if (!context) return responseError("Sessão expirada.", 401);
  const permissions = new Set(context.permissionCodes);
  const params = new URL(request.url).searchParams;
  const view = params.get("view") ?? "board";
  try {
    if (view === "board") {
      requirePermission(permissions, "hospitalizations.view");
      return Response.json(await getHospitalBedBoard(context.accessToken), { headers: privateHeaders() });
    }
    if (view === "history") {
      requirePermission(permissions, "hospitalizations.history");
      return Response.json(await getHospitalizationHistory(context.accessToken, {
        bedId: optionalInteger(params.get("bedId")),
        dateFrom: optionalDate(params.get("dateFrom")),
        dateTo: optionalDate(params.get("dateTo")),
        page: positiveInteger(params.get("page")) ?? 1,
        pageSize: positiveInteger(params.get("pageSize")) ?? 20,
        search: params.get("search") ?? "",
        source: optionalSource(params.get("source")),
        status: optionalStatus(params.get("status")),
      }), { headers: privateHeaders() });
    }
    if (view === "patient") {
      requirePermission(permissions, "hospitalizations.history");
      requirePermission(permissions, "patients.view");
      return Response.json(await getPatientHospitalizationHistory(
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
    if (action === "create" || action === "update") {
      requirePermission(permissions, action === "create" ? "hospitalizations.create" : "hospitalizations.update");
      const source = requiredSource(body.source);
      if (source === "hpsm") requirePermission(permissions, "patients.view");
      const payload = {
        p_admitted_at: requiredTimestamp(body.admittedAt, "Informe a data e hora da internação."),
        p_bed_id: requiredInteger(body.bedId, "Selecione um leito."),
        p_external_passport: optionalText(body.externalPassport, 32),
        p_external_patient_name: source === "hp_norte" ? requiredText(body.externalPatientName, "Informe o nome do paciente externo.", 120) : null,
        p_notes: optionalText(body.notes, 2_000),
        p_patient_id: source === "hpsm" ? requiredInteger(body.patientId, "Selecione um paciente HPSM.") : null,
        p_reason: requiredText(body.reason, "Informe o motivo da internação.", 2_000),
        p_source: source,
      };
      if (action === "create") {
        const hospitalizationId = await runHospitalizationMutation<number>(context.accessToken, "create_hospitalization", payload);
        const consultationId = optionalInteger(body.consultationId);
        if (consultationId) await runHospitalizationMutation(context.accessToken, "link_consultation_hospitalization", { p_consultation_id: consultationId, p_hospitalization_id: hospitalizationId });
        return Response.json({ hospitalizationId }, { status: 201, headers: privateHeaders() });
      }
      await runHospitalizationMutation(context.accessToken, "update_hospitalization", {
        ...payload,
        p_hospitalization_id: requiredInteger(body.hospitalizationId, "Internação inválida."),
      });
      return Response.json({ ok: true }, { headers: privateHeaders() });
    }
    if (action === "discharge") {
      requirePermission(permissions, "hospitalizations.discharge");
      await runHospitalizationMutation(context.accessToken, "discharge_hospitalization", {
        p_discharged_at: requiredTimestamp(body.dischargedAt, "Informe a data e hora da alta."),
        p_hospitalization_id: requiredInteger(body.hospitalizationId, "Internação inválida."),
      });
      return Response.json({ ok: true }, { headers: privateHeaders() });
    }
    if (action === "cancel") {
      requirePermission(permissions, "hospitalizations.update");
      await runHospitalizationMutation(context.accessToken, "cancel_hospitalization", {
        p_hospitalization_id: requiredInteger(body.hospitalizationId, "Internação inválida."),
        p_reason: requiredText(body.reason, "Informe o motivo do cancelamento.", 500),
      });
      return Response.json({ ok: true }, { headers: privateHeaders() });
    }
    return responseError("Ação inválida.", 400);
  } catch (error) {
    return actionError(error);
  }
}

function optionalSource(value: string | null): HospitalizationSource | null { if (!value || value === "all") return null; if (value === "hpsm" || value === "hp_norte") return value; throw new Error("Origem inválida."); }
function requiredSource(value: unknown): HospitalizationSource { const result = text(value); if (result === "hpsm" || result === "hp_norte") return result; throw new Error("Origem inválida."); }
function optionalStatus(value: string | null): HospitalizationStatus | null { if (!value || value === "all") return null; if (value === "active" || value === "discharged" || value === "cancelled") return value; throw new Error("Status inválido."); }
function optionalDate(value: string | null) { if (!value) return null; if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error("Data inválida."); return value; }
function positiveInteger(value: unknown) { const parsed = Number(value); return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null; }
function optionalInteger(value: unknown) { return value === null || value === undefined || value === "" ? null : requiredInteger(value, "Identificador inválido."); }
function requiredInteger(value: unknown, message: string) { const parsed = positiveInteger(value); if (!parsed) throw new Error(message); return parsed; }
function text(value: unknown) { return typeof value === "string" ? value.trim() : ""; }
function requiredText(value: unknown, message: string, max: number) { const result = text(value); if (result.length < 2 || result.length > max) throw new Error(message); return result; }
function optionalText(value: unknown, max: number) { const result = text(value); if (result.length > max) throw new Error("Texto muito extenso."); if (result.length === 1) throw new Error("O texto deve ter pelo menos 2 caracteres."); return result || null; }
function requiredTimestamp(value: unknown, message: string) { const result = text(value); const parsed = Date.parse(result); if (!result || Number.isNaN(parsed)) throw new Error(message); return new Date(parsed).toISOString(); }
function requirePermission(permissions: Set<string>, permission: string) { if (!permissions.has(permission)) throw new HospitalizationAccessError(); }
function privateHeaders() { return { "cache-control": "private, no-store", "x-content-type-options": "nosniff" }; }
function responseError(error: string, status: number) { return Response.json({ error }, { status, headers: privateHeaders() }); }
function actionError(error: unknown) {
  if (error instanceof HospitalizationAccessError) return responseError("Acesso não autorizado.", 403);
  const message = error instanceof Error ? error.message : "Não foi possível concluir a operação de internação.";
  const forbidden = /acesso não autorizado|sessão inválida|sessão expirada/i.test(message);
  const conflict = error instanceof HospitalizationConflictError || /já possui|já está|acabou de ser ocupado|somente uma internação/i.test(message);
  const notFound = /não localizad/i.test(message);
  const timeout = /demorou para responder/i.test(message);
  return responseError(forbidden ? "Acesso não autorizado." : message, forbidden ? 403 : notFound ? 404 : conflict ? 409 : timeout ? 504 : 400);
}
class HospitalizationAccessError extends Error {}
