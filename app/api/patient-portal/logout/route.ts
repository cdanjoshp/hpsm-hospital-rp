import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import {
  callPatientPortalRpc,
  hashPatientPortalValue,
  isPatientPortalToken,
  PATIENT_PORTAL_COOKIE,
} from "../../../lib/patient-portal";

export async function POST(request: Request) {
  const cookieStore = await cookies();
  const token = cookieStore.get(PATIENT_PORTAL_COOKIE)?.value ?? "";
  if (isPatientPortalToken(token)) {
    try {
      await callPatientPortalRpc<boolean>("patient_portal_revoke_session", {
        p_token_hash: await hashPatientPortalValue(token),
      });
    } catch {
      const destination = new URL("/portal-paciente", request.url);
      destination.searchParams.set("portalError", "logout");
      const response = NextResponse.redirect(destination, 303);
      response.headers.set("cache-control", "private, no-store");
      response.headers.set("vary", "Cookie");
      return response;
    }
  }

  const response = NextResponse.redirect(new URL("/?access=patient", request.url), 303);
  response.headers.set("cache-control", "private, no-store");
  response.headers.set("clear-site-data", '"cache"');
  response.headers.set("vary", "Cookie");
  response.cookies.set(PATIENT_PORTAL_COOKIE, "", {
    httpOnly: true,
    maxAge: 0,
    path: "/",
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
  });
  return response;
}
