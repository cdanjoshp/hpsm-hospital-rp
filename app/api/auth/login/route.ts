import { NextResponse } from "next/server";
import {
  ConfigurationError,
  deriveSyntheticEmail,
  getSupabaseConfig,
  normalizePassport,
} from "../../../lib/supabase-server";
import { persistentSessionCookieExpires } from "../../../lib/session-cookie-policy";

type AuthPayload = {
  access_token?: string;
  expires_in?: number;
  refresh_token?: string;
  user?: { id?: string };
};

type Profile = {
  must_change_password: boolean;
  status: string;
};

const UPSTREAM_TIMEOUT_MS = 12_000;

export async function POST(request: Request) {
  const browserNavigation = isBrowserNavigation(request);
  try {
    const body = await readCredentials(request, browserNavigation);
    if (typeof body.passport !== "string" || typeof body.password !== "string") {
      return loginError(request, browserNavigation, "invalid_request", "Informe matrícula e senha.", 400);
    }

    const passport = normalizePassport(body.passport);
    if (body.password.length < 8 || body.password.length > 128) {
      return invalidCredentials(request, browserNavigation);
    }

    const { url, anonKey } = getSupabaseConfig();
    const email = await deriveSyntheticEmail(passport);
    const authResponse = await fetch(`${url}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: {
        apikey: anonKey,
        "content-type": "application/json",
      },
      body: JSON.stringify({ email, password: body.password }),
      cache: "no-store",
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });

    if (!authResponse.ok) return invalidCredentials(request, browserNavigation);

    const auth = (await authResponse.json()) as AuthPayload;
    const userId = auth.user?.id;
    if (!auth.access_token || !auth.refresh_token || !userId) {
      return Response.json(
        { error: "O serviço de acesso retornou uma resposta incompleta." },
        { status: 502 },
      );
    }

    const profileResponse = await fetch(
      `${url}/rest/v1/profiles?select=must_change_password,status&user_id=eq.${encodeURIComponent(userId)}&limit=1`,
      {
        headers: {
          apikey: anonKey,
          authorization: `Bearer ${auth.access_token}`,
        },
        cache: "no-store",
        signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
      },
    );
    const profiles = profileResponse.ok
      ? ((await profileResponse.json()) as Profile[])
      : [];
    const profile = profiles[0];

    if (!profile || profile.status !== "active") {
      return loginError(request, browserNavigation, "inactive", "A conta não está liberada. Procure a diretoria.", 403);
    }

    const redirectTo = profile.must_change_password ? "/primeiro-acesso" : "/painel";
    const response = browserNavigation
      ? NextResponse.redirect(new URL(redirectTo, request.url), 303)
      : NextResponse.json({ redirectTo });
    const secure = process.env.NODE_ENV === "production";
    response.cookies.set("hp_access_token", auth.access_token, {
      httpOnly: true,
      maxAge: auth.expires_in ?? 3600,
      path: "/",
      sameSite: "lax",
      secure,
    });
    response.cookies.set("hp_refresh_token", auth.refresh_token, {
      httpOnly: true,
      expires: persistentSessionCookieExpires(),
      path: "/",
      sameSite: "lax",
      secure,
    });

    return response;
  } catch (error) {
    if (error instanceof ConfigurationError) {
      return loginError(request, browserNavigation, "configuration", "A conexão segura com o hospital está sendo configurada.", 503);
    }
    if (isTimeoutError(error)) {
      return loginError(request, browserNavigation, "timeout", "O serviço de acesso demorou para responder. Tente novamente.", 504);
    }
    if (error instanceof SyntaxError || error instanceof Error) {
      return loginError(request, browserNavigation, "invalid", "Não foi possível validar os dados informados.", 400);
    }
    return loginError(request, browserNavigation, "invalid", "Falha inesperada de autenticação.", 500);
  }
}

async function readCredentials(request: Request, browserNavigation: boolean) {
  if (browserNavigation) {
    const form = await request.formData();
    return { passport: form.get("passport"), password: form.get("password") };
  }
  return (await request.json()) as { passport?: unknown; password?: unknown };
}

function isBrowserNavigation(request: Request) {
  const contentType = request.headers.get("content-type") ?? "";
  return contentType.includes("application/x-www-form-urlencoded") || contentType.includes("multipart/form-data");
}

function invalidCredentials(request: Request, browserNavigation: boolean) {
  return loginError(request, browserNavigation, "invalid", "Matrícula ou senha inválida.", 401);
}

function loginError(request: Request, browserNavigation: boolean, code: string, message: string, status: number) {
  if (!browserNavigation) return NextResponse.json({ error: message }, { status });
  const destination = new URL("/", request.url);
  destination.searchParams.set("access", "professional");
  destination.searchParams.set("loginError", code);
  return NextResponse.redirect(destination, 303);
}

function isTimeoutError(error: unknown) {
  return error instanceof Error && (error.name === "AbortError" || error.name === "TimeoutError");
}
