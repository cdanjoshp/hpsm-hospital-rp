/** Cloudflare Worker entry point for the vinext-starter template. */
import { handleImageOptimization, DEFAULT_DEVICE_SIZES, DEFAULT_IMAGE_SIZES } from "vinext/server/image-optimization";
import handler from "vinext/server/app-router-entry";
import { STALE_ASSET_RECOVERY_MODULE_SCRIPT } from "../app/lib/deployment-recovery";
import { PERSISTENT_SESSION_COOKIE_EXPIRES_AT } from "../app/lib/session-cookie-policy";

interface Env {
  SUPABASE_ANON_KEY?: string;
  SUPABASE_URL?: string;
  ASSETS: { fetch(request: Request): Promise<Response> };
  IMAGES: {
    input(stream: ReadableStream): {
      transform(options: Record<string, unknown>): {
        output(options: { format: string; quality: number }): Promise<{ response(): Response }>;
      };
    };
  };
}

interface ExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
  passThroughOnException(): void;
}

const SITES_EDITOR_FRAME_ANCESTORS = [
  "'self'",
  "https://chatgpt.com",
  "https://*.chatgpt.com",
  "https://chat.openai.com",
].join(" ");

const VERSIONED_JAVASCRIPT_ASSET = /^\/assets\/[A-Za-z0-9_.-]+\.js$/;
const ACCESS_COOKIE = "hp_access_token";
const REFRESH_COOKIE = "hp_refresh_token";
const REFRESH_EARLY_SECONDS = 120;
const AUTH_TIMEOUT_MS = 12_000;

// Equivalente server-side a persistSession + autoRefreshToken: os tokens ficam
// somente em cookies HttpOnly e são renovados sob demanda, sem timer no cliente.
const PROFESSIONAL_SESSION_POLICY = Object.freeze({ autoRefreshToken: true, persistSession: true });

type PreparedProfessionalSession = {
  clearCookies: boolean;
  request: Request;
  setCookies: string[];
  unavailable: Response | null;
};

function parseCookies(header: string | null) {
  const cookies = new Map<string, string>();
  for (const part of (header ?? "").split(";")) {
    const separator = part.indexOf("=");
    if (separator <= 0) continue;
    const name = part.slice(0, separator).trim();
    const value = part.slice(separator + 1).trim();
    if (name) cookies.set(name, value);
  }
  return cookies;
}

function requestWithCookies(request: Request, cookies: Map<string, string>) {
  const headers = new Headers(request.headers);
  headers.set("cookie", [...cookies].map(([name, value]) => `${name}=${value}`).join("; "));
  return new Request(request, { headers });
}

function jwtExpiresAt(token: string | undefined) {
  if (!token) return null;
  try {
    const encoded = token.split(".")[1];
    if (!encoded) return null;
    const normalized = encoded.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(encoded.length / 4) * 4, "=");
    const payload = JSON.parse(atob(normalized)) as { exp?: unknown };
    return typeof payload.exp === "number" ? payload.exp * 1000 : null;
  } catch {
    return null;
  }
}

function sessionUnavailable(request: Request) {
  const headers = { "cache-control": "private, no-store", "retry-after": "3" };
  if (request.headers.get("accept")?.includes("text/html")) {
    return new Response("<!doctype html><html lang=\"pt-BR\"><meta charset=\"utf-8\"><title>Sessão preservada</title><body><main><h1>Conexão temporariamente indisponível</h1><p>Sua sessão foi preservada. Recarregue a página em instantes.</p></main></body></html>", {
      status: 503,
      headers: { ...headers, "content-type": "text/html; charset=utf-8" },
    });
  }
  return Response.json({ error: "A conexão está temporariamente indisponível. Sua sessão foi preservada." }, { status: 503, headers });
}

async function prepareProfessionalSession(request: Request, env: Env): Promise<PreparedProfessionalSession> {
  const unchanged = { clearCookies: false, request, setCookies: [], unavailable: null };
  if (!PROFESSIONAL_SESSION_POLICY.autoRefreshToken) return unchanged;
  const url = new URL(request.url);
  const secureCookie = url.protocol === "https:" ? "; Secure" : "";
  if (url.pathname === "/api/auth/login" || url.pathname === "/api/auth/logout") return unchanged;
  if (url.pathname.startsWith("/api/patient-portal/") || url.pathname.startsWith("/portal-paciente")) return unchanged;
  if (url.pathname.startsWith("/assets/") || url.pathname.startsWith("/_next/") || /\.(?:avif|css|gif|ico|jpe?g|js|map|png|svg|webp|woff2?)$/i.test(url.pathname)) return unchanged;

  const cookies = parseCookies(request.headers.get("cookie"));
  const refreshToken = cookies.get(REFRESH_COOKIE);
  if (!refreshToken) return unchanged;
  const accessToken = cookies.get(ACCESS_COOKIE);
  const expiresAt = jwtExpiresAt(accessToken);
  const accessUsable = expiresAt !== null && expiresAt > Date.now();
  if (accessUsable && expiresAt - Date.now() > REFRESH_EARLY_SECONDS * 1000) return unchanged;

  const supabaseUrl = env.SUPABASE_URL?.replace(/\/$/, "");
  const anonKey = env.SUPABASE_ANON_KEY;
  if (!supabaseUrl || !anonKey) {
    return accessUsable ? unchanged : { ...unchanged, unavailable: sessionUnavailable(request) };
  }

  try {
    const refreshResponse = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=refresh_token`, {
      method: "POST",
      headers: { apikey: anonKey, "content-type": "application/json" },
      body: JSON.stringify({ refresh_token: refreshToken }),
      signal: AbortSignal.timeout(AUTH_TIMEOUT_MS),
    });
    if (!refreshResponse.ok) {
      const definitivelyInvalid = [400, 401, 403].includes(refreshResponse.status);
      if (accessUsable || !definitivelyInvalid) {
        return accessUsable ? unchanged : { ...unchanged, unavailable: sessionUnavailable(request) };
      }
      cookies.delete(ACCESS_COOKIE);
      cookies.delete(REFRESH_COOKIE);
      return { clearCookies: true, request: requestWithCookies(request, cookies), setCookies: [], unavailable: null };
    }

    const payload = await refreshResponse.json() as { access_token?: unknown; expires_in?: unknown; refresh_token?: unknown };
    if (typeof payload.access_token !== "string" || typeof payload.refresh_token !== "string") {
      return accessUsable ? unchanged : { ...unchanged, unavailable: sessionUnavailable(request) };
    }
    const expiresIn = typeof payload.expires_in === "number" && payload.expires_in > 0 ? Math.floor(payload.expires_in) : 3600;
    cookies.set(ACCESS_COOKIE, payload.access_token);
    cookies.set(REFRESH_COOKIE, payload.refresh_token);
    return {
      clearCookies: false,
      request: requestWithCookies(request, cookies),
      setCookies: [
        `${ACCESS_COOKIE}=${payload.access_token}; Path=/; HttpOnly${secureCookie}; SameSite=Lax; Max-Age=${expiresIn}`,
        `${REFRESH_COOKIE}=${payload.refresh_token}; Path=/; HttpOnly${secureCookie}; SameSite=Lax; Expires=${new Date(PERSISTENT_SESSION_COOKIE_EXPIRES_AT).toUTCString()}`,
      ],
      unavailable: null,
    };
  } catch {
    return accessUsable ? unchanged : { ...unchanged, unavailable: sessionUnavailable(request) };
  }
}

function allowOfficialSitesEditorFrames(headers: Headers) {
  const currentPolicy = headers.get("content-security-policy");
  const directives = currentPolicy
    ? currentPolicy.split(";").map((directive) => directive.trim()).filter(Boolean)
    : [];
  const policyWithoutFrameAncestors = directives.filter(
    (directive) => !directive.toLowerCase().startsWith("frame-ancestors "),
  );
  policyWithoutFrameAncestors.push(`frame-ancestors ${SITES_EDITOR_FRAME_ANCESTORS}`);
  headers.set("content-security-policy", `${policyWithoutFrameAncestors.join("; ")};`);

  // X-Frame-Options does not support an allowlist and would block the
  // cross-origin iframe used by the official Sites editor.
  headers.delete("x-frame-options");
}

// Image security config. SVG sources with .svg extension auto-skip the
// optimization endpoint on the client side (served directly, no proxy).
// To route SVGs through the optimizer (with security headers), set
// dangerouslyAllowSVG: true in next.config.js and uncomment below:
// const imageConfig: ImageConfig = { dangerouslyAllowSVG: true };

const worker = {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname.startsWith("/api/") && !["GET", "HEAD", "OPTIONS"].includes(request.method)) {
      const origin = request.headers.get("origin");
      if ((origin && origin !== url.origin) || request.headers.get("sec-fetch-site") === "cross-site") {
        return Response.json({ error: "Origem não autorizada." }, { status: 403, headers: { "cache-control": "private, no-store" } });
      }
    }

    if (url.pathname === "/_vinext/image") {
      const allowedWidths = [...DEFAULT_DEVICE_SIZES, ...DEFAULT_IMAGE_SIZES];
      return handleImageOptimization(request, {
        fetchAsset: (path) => env.ASSETS.fetch(new Request(new URL(path, request.url))),
        transformImage: async (body, { width, format, quality }) => {
          const result = await env.IMAGES.input(body).transform(width > 0 ? { width } : {}).output({ format, quality });
          return result.response();
        },
      }, allowedWidths);
    }

    const preparedSession = await prepareProfessionalSession(request, env);
    let original = preparedSession.unavailable ?? await handler.fetch(preparedSession.request, env, ctx);
    if (request.method === "GET" && original.status === 404 && VERSIONED_JAVASCRIPT_ASSET.test(url.pathname)) {
      original = new Response(STALE_ASSET_RECOVERY_MODULE_SCRIPT, {
        status: 200,
        headers: {
          "cache-control": "private, no-store, max-age=0",
          "content-type": "text/javascript; charset=utf-8",
          "x-hpsm-asset-recovery": "1",
        },
      });
    }
    const response = new Response(original.body, original);
    for (const cookie of preparedSession.setCookies) response.headers.append("set-cookie", cookie);
    if (preparedSession.clearCookies) {
      const secureCookie = new URL(request.url).protocol === "https:" ? "; Secure" : "";
      for (const name of [ACCESS_COOKIE, REFRESH_COOKIE]) {
        response.headers.append("set-cookie", `${name}=; Path=/; HttpOnly${secureCookie}; SameSite=Lax; Max-Age=0`);
      }
    }
    if (!response.headers.get("cache-control")?.includes("no-store")) {
      response.headers.set("cache-control", "private, no-store, max-age=0");
    }
    response.headers.set("x-content-type-options", "nosniff");
    allowOfficialSitesEditorFrames(response.headers);
    if (!response.headers.has("referrer-policy")) response.headers.set("referrer-policy", "same-origin");
    if (!response.headers.has("x-robots-tag")) response.headers.set("x-robots-tag", "noindex, nofollow");
    const vary = response.headers.get("vary")?.split(/,\s*/) ?? [];
    if (!vary.includes("Cookie")) response.headers.set("vary", [...vary, "Cookie"].join(", "));
    return response;
  },
};

export default worker;
