import { NextResponse } from "next/server";
import {
  callPatientPortalRpc,
  createPatientPortalToken,
  hashPatientPortalValue,
  PATIENT_PORTAL_COOKIE,
  PATIENT_PORTAL_COOKIE_EXPIRES,
  patientPortalRequestHashes,
  type PatientPortalAccessResult,
  type PatientPortalLoginResult,
} from "../../../lib/patient-portal";
import { normalizePatientPassport } from "../../../lib/passport";

const MAX_LOGIN_BODY_LENGTH = 512;
const PIN_PATTERN = /^[0-9]{4}$/;

type AccessBody = {
  action?: unknown;
  passport?: unknown;
  pin?: unknown;
  pinConfirmation?: unknown;
};

export async function POST(request: Request) {
  try {
    const body = await readBody(request);
    if (typeof body.action !== "string" || typeof body.passport !== "string") {
      return failure("Preencha os dados solicitados.", 400);
    }

    const allowedKeys = body.action === "check"
      ? ["action", "passport"]
      : body.action === "login"
        ? ["action", "passport", "pin"]
        : body.action === "create"
          ? ["action", "passport", "pin", "pinConfirmation"]
          : [];
    if (!allowedKeys.length || Object.keys(body).some((key) => !allowedKeys.includes(key))) {
      return failure("Operação inválida.", 400);
    }

    let passport: string;
    try {
      passport = normalizePatientPassport(body.passport);
    } catch {
      return failure("Informe um passaporte válido com 1 a 4 números.", 400);
    }
    const { clientHash, originHash } = await patientPortalRequestHashes(request);

    if (body.action === "check") {
      const result = await callPatientPortalRpc<PatientPortalAccessResult>("patient_portal_access_state", {
        p_client_hash: clientHash,
        p_origin_hash: originHash,
        p_passport: passport,
      });
      if (result.blocked) return failure("Muitas tentativas. Aguarde alguns minutos e tente novamente.", 429);
      if (result.found !== true) return failure("Paciente não encontrado.", 404);
      return NextResponse.json({ hasPin: result.has_pin === true, ok: true, passport }, { headers: privateHeaders() });
    }

    if (typeof body.pin !== "string" || !PIN_PATTERN.test(body.pin)) {
      return failure("O PIN deve conter exatamente 4 números.", 400);
    }
    if (body.action === "create") {
      if (typeof body.pinConfirmation !== "string" || !PIN_PATTERN.test(body.pinConfirmation)) {
        return failure("Confirme o PIN com exatamente 4 números.", 400);
      }
      if (body.pinConfirmation !== body.pin) return failure("Os PINs não coincidem.", 400);
    }

    const token = createPatientPortalToken();
    const tokenHash = await hashPatientPortalValue(token);
    const result = body.action === "create"
      ? await callPatientPortalRpc<PatientPortalLoginResult>("patient_portal_create_pin_session", {
          p_client_hash: clientHash,
          p_origin_hash: originHash,
          p_passport: passport,
          p_pin: body.pin,
          p_pin_confirmation: body.pinConfirmation,
          p_token_hash: tokenHash,
        })
      : await callPatientPortalRpc<PatientPortalLoginResult>("patient_portal_create_session", {
          p_client_hash: clientHash,
          p_origin_hash: originHash,
          p_passport: passport,
          p_pin: body.pin,
          p_token_hash: tokenHash,
        });

    if (result.ok !== true) return rpcFailure(result);

    const response = NextResponse.json({ ok: true }, { headers: privateHeaders() });
    response.cookies.set(PATIENT_PORTAL_COOKIE, token, {
      httpOnly: true,
      expires: PATIENT_PORTAL_COOKIE_EXPIRES(),
      path: "/",
      sameSite: "lax",
      secure: process.env.NODE_ENV === "production",
    });
    return response;
  } catch (error) {
    const unavailable = error instanceof Error && (
      error.name === "AbortError" || error.name === "TimeoutError" || error.message.startsWith("patient_portal_rpc_")
    );
    return failure(unavailable ? "O Portal está temporariamente indisponível." : "Não foi possível concluir o acesso.", unavailable ? 503 : 400);
  }
}

async function readBody(request: Request): Promise<AccessBody> {
  const declaredLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_LOGIN_BODY_LENGTH) {
    throw new Error("patient_portal_login_body_too_large");
  }
  const rawBody = await request.text();
  if (rawBody.length > MAX_LOGIN_BODY_LENGTH) throw new Error("patient_portal_login_body_too_large");
  const value = JSON.parse(rawBody) as unknown;
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("patient_portal_invalid_body");
  return value as AccessBody;
}

function rpcFailure(result: PatientPortalLoginResult) {
  if (result.blocked || result.code === "rate_limited") {
    return failure("Muitas tentativas. Aguarde alguns minutos e tente novamente.", 429);
  }
  if (result.code === "patient_not_found") return failure("Paciente não encontrado.", 404);
  if (result.code === "first_access") return failure("Crie seu PIN para continuar.", 409, "first_access");
  if (result.code === "pin_exists") return failure("Seu PIN já foi criado. Entre com ele para continuar.", 409, "pin_exists");
  if (result.code === "pin_mismatch") return failure("Os PINs não coincidem.", 400);
  if (result.code === "invalid_pin_format") return failure("O PIN deve conter exatamente 4 números.", 400);
  return failure("PIN incorreto.", 401);
}

function failure(message: string, status: number, code?: string) {
  return NextResponse.json({ code, error: message }, { status, headers: privateHeaders() });
}

function privateHeaders() {
  return { "cache-control": "private, no-store" };
}
