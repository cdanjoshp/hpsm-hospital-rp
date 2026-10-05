import { cookies } from "next/headers";
import { PATIENT_PORTAL_COOKIE, resolvePatientPortalSession } from "../../../lib/patient-portal";

export async function GET() {
  const cookieStore = await cookies();
  const token = cookieStore.get(PATIENT_PORTAL_COOKIE)?.value ?? "";
  const session = await resolvePatientPortalSession(token);
  return session
    ? Response.json({ authenticated: true, expiresAt: session.expiresAt, name: session.name, passport: session.passport }, { headers: { "cache-control": "private, no-store", vary: "Cookie" } })
    : Response.json({ authenticated: false }, { status: 401, headers: { "cache-control": "private, no-store", vary: "Cookie" } });
}
