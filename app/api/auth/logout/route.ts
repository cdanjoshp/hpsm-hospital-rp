import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { revokeProfessionalSession } from "../../../lib/professional-logout";
import { getSupabaseConfig } from "../../../lib/supabase-server";

export async function POST(request: Request) {
  const cookieStore = await cookies();
  const accessToken = cookieStore.get("hp_access_token")?.value ?? null;
  const refreshToken = cookieStore.get("hp_refresh_token")?.value ?? null;
  try {
    if (accessToken || refreshToken) {
      await revokeProfessionalSession(getSupabaseConfig(), accessToken, refreshToken);
    }
  } catch {
    const response = NextResponse.redirect(new URL("/painel?sessionError=logout", request.url), 303);
    response.headers.set("cache-control", "private, no-store");
    return response;
  }
  const response = NextResponse.redirect(new URL("/?access=professional", request.url), 303);
  response.headers.set("cache-control", "private, no-store");
  response.headers.set("clear-site-data", '"cache"');
  for (const name of ["hp_access_token", "hp_refresh_token"]) {
    response.cookies.set(name, "", { httpOnly: true, maxAge: 0, path: "/", sameSite: "lax", secure: process.env.NODE_ENV === "production" });
  }
  return response;
}
