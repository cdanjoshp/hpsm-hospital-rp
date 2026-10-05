import { hasPermission } from "../../lib/access";
import { adminRest } from "../../lib/hr-server";
import { authenticatedHeaders } from "../../lib/operational-data";
import type { Patient, PatientHealthPlan } from "../../lib/operational-data";
import { getSessionAccessToken, getSessionContext } from "../../lib/session";
import { parseOptionalEmergencyContact, parseOptionalHpsmPhone } from "../../lib/phone";
import { isValidBirthDate } from "../../lib/birth-date";
import { normalizePatientPassport } from "../../lib/passport";
import { getSupabaseConfig } from "../../lib/supabase-server";
import { callSupabaseUserRpc, SupabaseUserRpcError } from "../../lib/supabase-user";

export async function GET(request: Request) {
  const accessToken = await getSessionAccessToken();
  if (!accessToken) return Response.json({ error: "Sessão expirada." }, { status: 401 });

  try {
    const passport = patientPassport(new URL(request.url).searchParams.get("passport"));
    const patients = await callSupabaseUserRpc<Patient[]>(accessToken, "hpsm_patient_quick_lookup", {
      p_passport: passport,
      p_limit: 8,
    });
    return Response.json({ patients }, { headers: { "cache-control": "private, no-store" } });
  } catch (cause) {
    if (cause instanceof SupabaseUserRpcError) {
      if (cause.status === 401 || cause.status === 403) {
        return Response.json({ error: cause.status === 401 ? "Sessão expirada." : "Acesso não autorizado." }, { status: cause.status });
      }
      return Response.json({ error: "Não foi possível consultar os pacientes." }, { status: 503 });
    }
    return Response.json({ error: "Informe um passaporte válido." }, { status: 400 });
  }
}

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "patients.view")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });

  try {
    const body = (await request.json()) as {
      allergies?: unknown;
      birthDate?: unknown;
      emergencyContactName?: unknown;
      emergencyContactPhone?: unknown;
      name?: unknown;
      passport?: unknown;
      phone?: unknown;
    };
    if (
      typeof body.name !== "string" ||
      typeof body.allergies !== "string" ||
      typeof body.passport !== "string" ||
      (body.phone != null && typeof body.phone !== "string") ||
      typeof body.birthDate !== "string" ||
      (body.emergencyContactName != null && typeof body.emergencyContactName !== "string") ||
      (body.emergencyContactPhone != null && typeof body.emergencyContactPhone !== "string")
    ) {
      return Response.json({ error: "Preencha os dados do paciente." }, { status: 400 });
    }

    const name = body.name.trim();
    const allergies = body.allergies.trim();
    if (!allergies || allergies.length > 1000) return Response.json({ error: "Informe as alergias do paciente ou registre “Não possui”." }, { status: 400 });
    const birthDate = body.birthDate.trim() || null;
    if (birthDate && !isValidBirthDate(birthDate)) return Response.json({ error: "Informe uma data de nascimento válida." }, { status: 400 });
    const passport = patientPassport(body.passport);
    const primaryPhone = parseOptionalHpsmPhone(typeof body.phone === "string" ? body.phone : "");
    const emergencyContact = parseOptionalEmergencyContact(
      typeof body.emergencyContactName === "string" ? body.emergencyContactName : "",
      typeof body.emergencyContactPhone === "string" ? body.emergencyContactPhone : "",
    );
    if (name.length < 2 || name.length > 100) return Response.json({ error: "Informe o nome completo do paciente." }, { status: 400 });
    if (primaryPhone.error) return Response.json({ error: primaryPhone.error }, { status: 400 });
    if (emergencyContact.error) return Response.json({ error: emergencyContact.error }, { status: 400 });

    const { url } = getSupabaseConfig();
    const response = await fetch(`${url}/rest/v1/patients`, {
      method: "POST",
      headers: { ...authenticatedHeaders(context.accessToken), prefer: "return=representation" },
      body: JSON.stringify({
        allergies,
        passport,
        name,
        phone: primaryPhone.phone,
        birth_date: birthDate,
        emergency_contact_name: emergencyContact.name,
        emergency_contact_phone: emergencyContact.phone,
        created_by: context.profile.user_id,
        updated_by: context.profile.user_id,
      }),
    });
    if (response.status === 409) {
      return Response.json({ error: "Passaporte já cadastrado." }, { status: 409 });
    }
    if (!response.ok) throw new Error("insert");
    const patients = (await response.json()) as Omit<Patient, "health_plan">[];
    if (!patients[0]) throw new Error("representation");
    const patient = await hydratePatient(context.accessToken, patients[0]);
    return Response.json({ patient }, { status: 201 });
  } catch {
    return Response.json({ error: "Não foi possível cadastrar o paciente." }, { status: 400 });
  }
}

export async function PATCH(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "patients.manage")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });

  try {
    const body = (await request.json()) as {
      allergies?: unknown;
      birthDate?: unknown;
      emergencyContactName?: unknown;
      emergencyContactPhone?: unknown;
      name?: unknown;
      passport?: unknown;
      patientId?: unknown;
      phone?: unknown;
    };
    if (
      typeof body.patientId !== "number" ||
      !Number.isInteger(body.patientId) ||
      body.patientId <= 0 ||
      typeof body.name !== "string" ||
      typeof body.allergies !== "string" ||
      typeof body.passport !== "string" ||
      (body.phone != null && typeof body.phone !== "string") ||
      typeof body.birthDate !== "string" ||
      (body.emergencyContactName != null && typeof body.emergencyContactName !== "string") ||
      (body.emergencyContactPhone != null && typeof body.emergencyContactPhone !== "string")
    ) {
      return Response.json({ error: "Preencha os dados do paciente." }, { status: 400 });
    }

    const name = body.name.trim();
    const allergies = body.allergies.trim();
    if (!allergies || allergies.length > 1000) return Response.json({ error: "Informe as alergias do paciente ou registre “Não possui”." }, { status: 400 });
    const birthDate = body.birthDate.trim() || null;
    if (birthDate && !isValidBirthDate(birthDate)) return Response.json({ error: "Informe uma data de nascimento válida." }, { status: 400 });
    const passport = patientPassport(body.passport);
    const primaryPhone = parseOptionalHpsmPhone(typeof body.phone === "string" ? body.phone : "");
    const emergencyContact = parseOptionalEmergencyContact(
      typeof body.emergencyContactName === "string" ? body.emergencyContactName : "",
      typeof body.emergencyContactPhone === "string" ? body.emergencyContactPhone : "",
    );
    if (name.length < 2 || name.length > 100) return Response.json({ error: "Informe o nome completo do paciente." }, { status: 400 });
    if (primaryPhone.error) return Response.json({ error: primaryPhone.error }, { status: 400 });
    if (emergencyContact.error) return Response.json({ error: emergencyContact.error }, { status: 400 });

    const { url } = getSupabaseConfig();
    const response = await fetch(
      `${url}/rest/v1/patients?id=eq.${body.patientId}&select=id,passport,name,phone,birth_date,emergency_contact_name,emergency_contact_phone,allergies,created_at,updated_at`,
      {
        method: "PATCH",
        headers: { ...authenticatedHeaders(context.accessToken), prefer: "return=representation" },
        body: JSON.stringify({
          allergies,
          passport,
          name,
          phone: primaryPhone.phone,
          birth_date: birthDate,
          emergency_contact_name: emergencyContact.name,
          emergency_contact_phone: emergencyContact.phone,
          updated_by: context.profile.user_id,
        }),
      },
    );
    if (response.status === 409) {
      return Response.json({ error: "Passaporte já cadastrado." }, { status: 409 });
    }
    if (!response.ok) throw new Error("update");
    const patients = (await response.json()) as Omit<Patient, "health_plan">[];
    if (!patients[0]) {
      return Response.json({ error: "Paciente não localizado ou sem permissão para alteração." }, { status: 404 });
    }
    const patient = await hydratePatient(context.accessToken, patients[0]);
    return Response.json({ patient });
  } catch {
    return Response.json({ error: "Não foi possível atualizar o paciente." }, { status: 400 });
  }
}

function patientPassport(value: unknown) {
  if (typeof value !== "string") throw new Error("passport");
  return normalizePatientPassport(value);
}

type HealthPlanRequestRow = {
  coverage_end: string | null;
  coverage_start: string | null;
  id: number;
  patient_id: number;
  requested_at: string;
  reviewed_by: string | null;
  status: "approved" | "pending";
};

async function attachHealthPlanStates(
  patients: Omit<Patient, "health_plan">[],
): Promise<Patient[]> {
  if (!patients.length) return [];
  const ids = patients.map((patient) => patient.id).join(",");
  const requests = await adminRest<HealthPlanRequestRow[]>(
    `patient_health_plan_requests?select=id,patient_id,status,requested_at,reviewed_by,coverage_start,coverage_end&patient_id=in.(${ids})&status=in.(approved,pending)&order=patient_id.asc,coverage_end.desc.nullslast,requested_at.asc&limit=500`,
  );
  const reviewerIds = [...new Set(requests.map((request) => request.reviewed_by).filter((id): id is string => Boolean(id)))];
  const reviewers = reviewerIds.length
    ? await adminRest<Array<{ display_name: string; user_id: string }>>(
      `profiles?select=user_id,display_name&user_id=in.(${reviewerIds.join(",")})&limit=500`,
    )
    : [];
  const reviewerName = new Map(reviewers.map((reviewer) => [reviewer.user_id, reviewer.display_name]));
  const requestsByPatient = new Map<number, HealthPlanRequestRow[]>();
  requests.forEach((request) => {
    const grouped = requestsByPatient.get(request.patient_id);
    if (grouped) grouped.push(request);
    else requestsByPatient.set(request.patient_id, [request]);
  });
  const byPatient = new Map<number, PatientHealthPlan>();
  for (const patient of patients) {
    const patientRequests = requestsByPatient.get(patient.id) ?? [];
    const approved = patientRequests
      .filter((request) => request.status === "approved" && request.coverage_end)
      .sort((a, b) => String(b.coverage_end).localeCompare(String(a.coverage_end)))[0];
    const pending = patientRequests
      .filter((request) => request.status === "pending")
      .sort((a, b) => a.requested_at.localeCompare(b.requested_at))[0];
    const active = Boolean(approved?.coverage_end && new Date(approved.coverage_end).getTime() > Date.now());
    byPatient.set(patient.id, {
      activated_at: approved?.coverage_start ?? null,
      authorized_by: approved?.reviewed_by ?? null,
      authorized_by_name: approved?.reviewed_by ? reviewerName.get(approved.reviewed_by) ?? null : null,
      pending_request_id: pending?.id ?? null,
      pending_requested_at: pending?.requested_at ?? null,
      status: active ? "active" : approved ? "expired" : pending ? "awaiting_confirmation" : "none",
      valid_until: approved?.coverage_end ?? null,
    });
  }
  return patients.map((patient) => ({
    ...patient,
    health_plan: byPatient.get(patient.id) ?? emptyHealthPlan(),
  }));
}

function emptyHealthPlan(): PatientHealthPlan {
  return {
    activated_at: null,
    authorized_by: null,
    authorized_by_name: null,
    pending_request_id: null,
    pending_requested_at: null,
    status: "none",
    valid_until: null,
  };
}

async function hydratePatient(accessToken: string, patient: Omit<Patient, "health_plan">): Promise<Patient> {
  const matches = await callSupabaseUserRpc<Patient[]>(accessToken, "hpsm_patient_quick_lookup", {
    p_limit: 8,
    p_passport: patient.passport,
  }).catch(() => []);
  const exact = matches.find((item) => item.id === patient.id);
  if (exact) return exact;
  const [fallback] = await attachHealthPlanStates([patient]);
  return { ...fallback, partnerships: [] };
}
