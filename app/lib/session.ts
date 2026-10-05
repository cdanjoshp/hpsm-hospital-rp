import { cookies } from "next/headers";
import { cache } from "react";
import { callSupabaseUserRpc } from "./supabase-user";

export type SessionProfile = {
  display_name: string;
  must_change_password: boolean;
  passport: string;
  position_id: number | null;
  role_code: string;
  status: string;
  user_id: string;
};

export type SessionContext = {
  accessToken: string;
  profile: SessionProfile;
};

export type SessionBootstrap = SessionContext & {
  permissionCodes: string[];
  positionDisplayName: string | null;
  positionLevel: number | null;
};

type SessionBootstrapPayload = {
  permissionCodes?: unknown;
  positionDisplayName?: unknown;
  positionLevel?: unknown;
  profile?: Partial<SessionProfile>;
};

async function loadSessionAccessToken(): Promise<string | null> {
  const cookieStore = await cookies();
  return cookieStore.get("hp_access_token")?.value ?? null;
}

// Leitura local do cookie HTTP-only. A validade e a autorização continuam
// sendo confirmadas pela RPC protegida utilizada em cada caminho rápido.
export const getSessionAccessToken = cache(loadSessionAccessToken);

async function loadSessionBootstrap(): Promise<SessionBootstrap | null> {
  try {
    const accessToken = await getSessionAccessToken();
    if (!accessToken) return null;
    const payload = await callSupabaseUserRpc<SessionBootstrapPayload>(accessToken, "hpsm_session_bootstrap");
    if (!isSessionProfile(payload.profile) || !Array.isArray(payload.permissionCodes)) return null;
    return {
      accessToken,
      permissionCodes: payload.profile.must_change_password ? [] : payload.permissionCodes.filter((code): code is string => typeof code === "string"),
      positionDisplayName: typeof payload.positionDisplayName === "string" ? payload.positionDisplayName : null,
      positionLevel: typeof payload.positionLevel === "number" ? payload.positionLevel : null,
      profile: payload.profile,
    };
  } catch {
    return null;
  }
}

// Uma única RPC valida Auth/session e entrega perfil, cargo e permissões.
// A memoização continua limitada à requisição RSC/API atual.
export const getSessionBootstrap = cache(loadSessionBootstrap);

async function loadSessionContext(): Promise<SessionContext | null> {
  const bootstrap = await getSessionBootstrap();
  return bootstrap && !bootstrap.profile.must_change_password ? { accessToken: bootstrap.accessToken, profile: bootstrap.profile } : null;
}

export const getSessionContext = cache(loadSessionContext);

export async function getSessionProfile(): Promise<SessionProfile | null> {
  return (await getSessionBootstrap())?.profile ?? null;
}

function isSessionProfile(profile: Partial<SessionProfile> | undefined): profile is SessionProfile {
  return Boolean(
    profile
    && typeof profile.user_id === "string"
    && typeof profile.passport === "string"
    && typeof profile.display_name === "string"
    && typeof profile.role_code === "string"
    && profile.status === "active"
    && typeof profile.must_change_password === "boolean"
    && (profile.position_id === null || typeof profile.position_id === "number"),
  );
}
