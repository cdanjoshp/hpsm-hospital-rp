import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("the unified public entry keeps professional login native and patient PIN access isolated", async () => {
  const [form, professionalRoute, patientRoute, home] = await Promise.all([
    read("app/components/login-form.tsx"),
    read("app/api/auth/login/route.ts"),
    read("app/api/patient-portal/login/route.ts"),
    read("app/page.tsx"),
  ]);

  assert.match(home, /<LoginForm/);
  assert.match(home, /getSessionProfile\(\)/);
  assert.match(home, /redirect\(profile\.must_change_password \? "\/primeiro-acesso" : "\/painel"\)/);
  assert.match(home, /Cuidado que orienta\./);
  assert.match(home, /ambiente reservado, seguro e organizado/);
  assert.match(form, />Sou Profissional</);
  assert.match(form, />Sou Paciente</);
  assert.match(form, /action="\/api\/auth\/login"/);
  assert.match(form, /fetch\("\/api\/patient-portal\/login"/);
  assert.equal((form.match(/method="post"/g) ?? []).length, 1);
  assert.match(form, /patientStep === "passport" \? "check"/);
  assert.match(form, /window\.location\.assign\("\/portal-paciente"\)/);
  assert.doesNotMatch(form, /name="patientId"|name="patient_id"/);

  assert.match(professionalRoute, /NextResponse\.redirect\(new URL\(redirectTo, request\.url\), 303\)/);
  assert.match(professionalRoute, /destination\.searchParams\.set\("access", "professional"\)/);
  assert.match(professionalRoute, /AbortSignal\.timeout\(UPSTREAM_TIMEOUT_MS\)/);
  assert.match(patientRoute, /patient_portal_access_state/);
  assert.match(patientRoute, /patient_portal_create_pin_session/);
  assert.match(patientRoute, /patient_portal_create_session/);
  assert.doesNotMatch(patientRoute, /birthDate|p_birth_date/);
});

test("the two forms preserve text passports, accessibility and safe submission state", async () => {
  const form = await read("app/components/login-form.tsx");
  const inputs = [...form.matchAll(/<input[\s\S]*?\/>/g)].map((match) => match[0]);

  assert.equal(inputs.length, 5);
  assert.ok((form.match(/sanitizePassportInput/g) ?? []).length >= 4);
  assert.equal((form.match(/pattern="\[0-9\]\{1,4\}"/g) ?? []).length, 2);
  assert.equal((form.match(/pattern="\[0-9\]\{4\}"/g) ?? []).length, 2);
  assert.equal((form.match(/inputMode="numeric"/g) ?? []).length, 4);
  assert.equal((form.match(/type="text"/g) ?? []).length, 2);
  assert.match(form, /autoComplete="current-password"/);
  assert.match(form, /PRIMEIRO ACESSO/);
  assert.match(form, /Crie seu PIN de 4 números/);
  assert.doesNotMatch(form, /type="date"|Data de nascimento/);
  assert.match(form, /event\.preventDefault\(\)/);
  assert.match(form, /disabled=\{loading\}/);
  assert.match(form, /readOnly=\{loading \|\| patientStep !== "passport"\}/);
  assert.match(form, /aria-busy=\{loading\}/);
  assert.match(form, /autoFocus/g);
  assert.match(form, /Escolher outro acesso/);
});

test("switching or returning through browser history clears credentials without persistence", async () => {
  const form = await read("app/components/login-form.tsx");

  assert.match(form, /function clearFormState\(\)[\s\S]*?setProfessionalPassport\(""\)[\s\S]*?setPatientPassport\(""\)[\s\S]*?setPassword\(""\)[\s\S]*?setPatientStep\("passport"\)[\s\S]*?setPin\(""\)[\s\S]*?setPinConfirmation\(""\)/);
  assert.match(form, /window\.addEventListener\("pageshow", clearRestoredCredentials\)/);
  assert.doesNotMatch(form, /localStorage|sessionStorage|document\.cookie|console\./);
});

test("legacy portal entry and both logout flows return to the unified home", async () => {
  const [portal, professionalLogout, patientLogout] = await Promise.all([
    read("app/portal-paciente/page.tsx"),
    read("app/api/auth/logout/route.ts"),
    read("app/api/patient-portal/logout/route.ts"),
  ]);

  assert.match(portal, /getPatientPortalSummary\(\)/);
  assert.match(portal, /redirect\(errorCode \? "\/\?access=patient&portalError=invalid" : "\/\?access=patient"\)/);
  assert.match(portal, /summary \? <PatientPortalSummaryView/);
  assert.doesNotMatch(portal, /action="\/api\/patient-portal\/login"/);
  assert.match(professionalLogout, /\/\?access=professional/);
  assert.match(patientLogout, /patient_portal_revoke_session/);
  assert.match(patientLogout, /\/\?access=patient/);
  assert.match(patientLogout, /maxAge: 0/);
});

test("professional and patient sessions remain technically isolated", async () => {
  const [professionalRoute, patientRoute, professionalLogout, patientLogout, portalLib] = await Promise.all([
    read("app/api/auth/login/route.ts"),
    read("app/api/patient-portal/login/route.ts"),
    read("app/api/auth/logout/route.ts"),
    read("app/api/patient-portal/logout/route.ts"),
    read("app/lib/patient-portal.ts"),
  ]);

  assert.match(professionalRoute, /hp_access_token/);
  assert.match(professionalRoute, /hp_refresh_token/);
  assert.doesNotMatch(professionalRoute, /PATIENT_PORTAL_COOKIE|patient_portal_create_session/);
  assert.match(patientRoute, /PATIENT_PORTAL_COOKIE/);
  assert.match(patientRoute, /patient_portal_create_session/);
  assert.doesNotMatch(patientRoute, /hp_access_token|hp_refresh_token|grant_type=password/);
  assert.doesNotMatch(professionalLogout, /PATIENT_PORTAL_COOKIE|patient_portal_revoke_session/);
  assert.doesNotMatch(patientLogout, /hp_access_token|hp_refresh_token/);
  assert.match(portalLib, /export const PATIENT_PORTAL_COOKIE = "hp_patient_portal_session"/);
});

test("the public entry covers small screens, dark mode and a lightweight route boundary", async () => {
  const [styles, home, form] = await Promise.all([
    read("app/brand.css"),
    read("app/page.tsx"),
    read("app/components/login-form.tsx"),
  ]);

  assert.match(styles, /\.public-access-layout \{[\s\S]*?grid-template-columns: minmax\(310px, 0\.82fr\) minmax\(500px, 1\.18fr\)/);
  assert.match(styles, /\.public-access-story \{[\s\S]*?background: linear-gradient/);
  assert.match(styles, /@media \(max-width: 900px\)[\s\S]*?\.public-access-story/);
  assert.match(styles, /html\[data-theme="dark"\] \.public-access-page/);
  assert.match(styles, /@media \(max-width: 520px\)[\s\S]*?\.public-access-page/);
  assert.match(styles, /@media \(max-width: 340px\)[\s\S]*?\.public-access-option/);
  assert.match(styles, /@media \(max-height: 720px\)[\s\S]*?align-items: flex-start/);
  assert.match(styles, /@media \(max-height: 720px\)[\s\S]*?\.rp-disclaimer \{[\s\S]*?position: static/);
  assert.match(styles, /@media \(prefers-reduced-motion: reduce\)[\s\S]*?\.public-access-view/);
  assert.doesNotMatch(home, /persistent-app-shell|exam-center|patient-portal-summary|patient-portal-shell/);
  assert.doesNotMatch(form, /exam-center|patient-portal-summary|patient-portal-shell|supabase-server/);
});
