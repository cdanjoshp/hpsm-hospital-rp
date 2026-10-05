import { hasPermission } from "../../lib/access";
import { isClinicalExamStatus } from "../../lib/exam-status";
import {
  getPatientActivityPage,
  getPatientActiveHospitalization,
  getPatientCardPage,
  getPatientClinicalExamPage,
  getPatientDirectoryEntry,
  getPatientLegacyHistoryPage,
  getPatientPlanHistoryPage,
  getPatientRecordPage,
  getPatientPartnershipPage,
  getPatientSummary,
  getPatientTimeline,
  isPatientLegacyRecordType,
  type PatientCardFilter,
  type PatientRecordFilter,
} from "../../lib/patient-center";
import { getSessionContext } from "../../lib/session";

export async function GET(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "patients.view")) {
    return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
  }

  try {
    const params = new URL(request.url).searchParams;
    const view = params.get("view") ?? "list";
    const page = numberParam(params.get("page"), 1);
    const pageSize = numberParam(params.get("pageSize"), view === "list" ? 20 : 10);

    if (view === "list") {
      const filter = (params.get("filter") ?? "all") as PatientCardFilter;
      return Response.json(await getPatientCardPage(context.accessToken, {
        filter,
        page,
        pageSize,
        search: params.get("search") ?? "",
      }));
    }

    const patientId = numberParam(params.get("patientId"), 0);
    if (!patientId) return Response.json({ error: "Paciente inválido." }, { status: 400 });

    if (view === "profile") {
      const patient = await getPatientDirectoryEntry(context.accessToken, patientId);
      return patient
        ? Response.json({ patient })
        : Response.json({ error: "Paciente não localizado." }, { status: 404 });
    }
    if (view === "summary") {
      const canViewCasts = await hasPermission(context.profile, "casts.view");
      return Response.json(await getPatientSummary(context.accessToken, patientId, canViewCasts));
    }
    if (view === "active-hospitalization") {
      if (!await hasPermission(context.profile, "hospitalizations.history")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
      return Response.json({ hospitalization: await getPatientActiveHospitalization(context.accessToken, patientId) });
    }
    if (view === "timeline") return Response.json({ events: await getPatientTimeline(context.accessToken, patientId) });
    if (view === "timeline-page" || view === "documents") {
      const filter = params.get("filter") ?? "all";
      const allowed: PatientRecordFilter[] = ["all", "attendance", "procedure", "purchase", "exam", "cast", "hospitalization", "plan", "certificate", "prescription", "record"];
      if (!allowed.includes(filter as PatientRecordFilter)) return Response.json({ error: "Filtro inválido." }, { status: 400 });
      return Response.json(await getPatientRecordPage(context.accessToken, patientId, view === "documents" ? "documents" : "timeline", filter as PatientRecordFilter, page, pageSize));
    }
    if (view === "exams") {
      if (!await hasPermission(context.profile, "exams.view")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
      const status = params.get("status");
      if (status && !isClinicalExamStatus(status)) return Response.json({ error: "Status de exame inválido." }, { status: 400 });
      return Response.json(await getPatientClinicalExamPage(context.accessToken, patientId, {
        categoryId: optionalNumberParam(params.get("categoryId")),
        dateFrom: dateParam(params.get("dateFrom")),
        dateTo: dateParam(params.get("dateTo")),
        examTypeId: optionalNumberParam(params.get("examTypeId")),
        status: status && isClinicalExamStatus(status) ? status : undefined,
      }, page, pageSize));
    }
    const month = params.get("month") ?? undefined;
    if (view === "attendances") return Response.json(await getPatientActivityPage(context.accessToken, patientId, "all", page, pageSize, month));
    if (view === "purchases") return Response.json(await getPatientActivityPage(context.accessToken, patientId, "purchases", page, pageSize, month));
    if (view === "procedures") return Response.json(await getPatientActivityPage(context.accessToken, patientId, "procedures", page, pageSize, month));
    if (view === "legacy") {
      const recordType = params.get("recordType");
      if (recordType && !isPatientLegacyRecordType(recordType)) return Response.json({ error: "Tipo de histórico legado inválido." }, { status: 400 });
      const safeRecordType = recordType && isPatientLegacyRecordType(recordType) ? recordType : undefined;
      return Response.json(await getPatientLegacyHistoryPage(context.accessToken, patientId, safeRecordType, page, pageSize));
    }
    if (view === "plans") return Response.json(await getPatientPlanHistoryPage(context.accessToken, patientId, page, pageSize));
    if (view === "partnerships") return Response.json(await getPatientPartnershipPage(context.accessToken, patientId));

    return Response.json({ error: "Consulta inválida." }, { status: 400 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Não foi possível consultar os pacientes.";
    return Response.json({ error: message }, { status: 400 });
  }
}

function numberParam(value: string | null, fallback: number) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : fallback;
}

function optionalNumberParam(value: string | null) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : undefined;
}

function dateParam(value: string | null) {
  return value && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : undefined;
}
