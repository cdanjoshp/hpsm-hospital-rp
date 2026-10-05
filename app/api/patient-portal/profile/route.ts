import { isValidBirthDate } from "../../../lib/birth-date";
import {
  getPatientPortalProfile,
  PatientPortalRpcError,
  updatePatientPortalProfile,
} from "../../../lib/patient-portal";
import { parseOptionalEmergencyContact, parseOptionalHpsmPhone } from "../../../lib/phone";

const MAX_PROFILE_BODY_LENGTH = 8_192;
const PROFILE_KEYS = [
  "allergies",
  "birthDate",
  "emergencyContactName",
  "emergencyContactPhone",
  "name",
  "phone",
] as const;

export async function GET() {
  try {
    const patient = await getPatientPortalProfile();
    if (!patient) return Response.json({ error: "Sessão expirada." }, { status: 401, headers: privateHeaders() });
    return Response.json({ patient }, { headers: privateHeaders() });
  } catch {
    return Response.json({ error: "Não foi possível carregar seu cadastro." }, { status: 503, headers: privateHeaders() });
  }
}

export async function PATCH(request: Request) {
  try {
    const body = await readBody(request);
    if (Object.keys(body).some((key) => !(PROFILE_KEYS as readonly string[]).includes(key))) {
      return Response.json({ error: "O cadastro contém um campo que não pode ser alterado pelo Portal." }, { status: 400, headers: privateHeaders() });
    }
    if (
      typeof body.name !== "string" ||
      typeof body.allergies !== "string" ||
      typeof body.birthDate !== "string" ||
      typeof body.phone !== "string" ||
      typeof body.emergencyContactName !== "string" ||
      typeof body.emergencyContactPhone !== "string"
    ) {
      return Response.json({ error: "Preencha os campos do cadastro." }, { status: 400, headers: privateHeaders() });
    }

    const name = body.name.trim();
    const allergies = body.allergies.trim();
    const birthDate = body.birthDate.trim() || null;
    if (name.length < 2 || name.length > 100) {
      return Response.json({ error: "Informe seu nome completo." }, { status: 400, headers: privateHeaders() });
    }
    if (!allergies || allergies.length > 1000) {
      return Response.json({ error: "Informe suas alergias ou registre “Não possui”." }, { status: 400, headers: privateHeaders() });
    }
    if (birthDate && !isValidBirthDate(birthDate)) {
      return Response.json({ error: "Informe uma data de nascimento válida." }, { status: 400, headers: privateHeaders() });
    }
    const primaryPhone = parseOptionalHpsmPhone(body.phone);
    if (primaryPhone.error) return Response.json({ error: primaryPhone.error }, { status: 400, headers: privateHeaders() });
    const emergencyContact = parseOptionalEmergencyContact(body.emergencyContactName, body.emergencyContactPhone);
    if (emergencyContact.error) return Response.json({ error: emergencyContact.error }, { status: 400, headers: privateHeaders() });

    const patient = await updatePatientPortalProfile({
      allergies,
      birthDate,
      emergencyContactName: emergencyContact.name,
      emergencyContactPhone: emergencyContact.phone,
      name,
      phone: primaryPhone.phone,
    });
    if (!patient) return Response.json({ error: "Sessão expirada." }, { status: 401, headers: privateHeaders() });
    return Response.json({ patient }, { headers: privateHeaders() });
  } catch (error) {
    if (error instanceof PatientPortalRpcError) {
      const status = error.status === 401 || error.status === 403 ? error.status : 400;
      return Response.json({ error: error.rpcMessage ?? "Não foi possível salvar seu cadastro." }, { status, headers: privateHeaders() });
    }
    return Response.json({ error: "Não foi possível salvar seu cadastro." }, { status: 400, headers: privateHeaders() });
  }
}

async function readBody(request: Request): Promise<Record<string, unknown>> {
  const declaredLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_PROFILE_BODY_LENGTH) throw new Error("profile_body_too_large");
  const raw = await request.text();
  if (raw.length > MAX_PROFILE_BODY_LENGTH) throw new Error("profile_body_too_large");
  const value = JSON.parse(raw) as unknown;
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("profile_invalid_body");
  return value as Record<string, unknown>;
}

function privateHeaders() {
  return { "cache-control": "private, no-store" };
}
