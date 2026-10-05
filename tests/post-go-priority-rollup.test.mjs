import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("patient allergies are required by every write flow while legacy nulls remain valid", async () => {
  const [migration, api, create, edit, attendance, profile, patientCenter, operational] = await Promise.all([
    read("supabase/migrations/20260921205110_post_go_priority_rollup.sql"),
    read("app/api/patients/route.ts"),
    read("app/components/patient-create-form.tsx"),
    read("app/components/patient-edit-form.tsx"),
    read("app/components/attendance-desk.tsx"),
    read("app/components/patient-profile.tsx"),
    read("app/lib/patient-center.ts"),
    read("app/lib/operational-data.ts"),
  ]);

  assert.match(migration, /add column if not exists allergies text/);
  assert.match(migration, /allergies is null/);
  assert.doesNotMatch(migration, /update public\.patients[\s\S]*?Não possui/i);
  assert.match(migration, /'allergies', matching\.allergies/);
  assert.match(migration, /patient\.allergies/);
  assert.match(operational, /allergies: string \| null/);
  assert.match(patientCenter, /allergies: row\.allergies/);

  for (const source of [api, create, edit, attendance]) {
    assert.match(source, /allergies/);
    assert.match(source, /Não possui/);
  }
  assert.match(api, /const allergies = body\.allergies\.trim\(\)/);
  assert.match(create, /if \(!allergies\.trim\(\)\)/);
  assert.match(edit, /if \(!allergies\.trim\(\)\)/);
  assert.match(attendance, /if \(!patientAllergies\.trim\(\)\)/);
  assert.match(profile, /Alergias não informadas/);
  assert.match(attendance, /Alergias não informadas/);
});

test("attendance form is cleared only inside the confirmed-success branch", async () => {
  const attendance = await read("app/components/attendance-desk.tsx");
  const submit = attendance.slice(attendance.indexOf("async function submitAttendance"), attendance.indexOf('    <div className="attendance-layout">'));
  const successCheck = submit.indexOf("if (!response.ok || !payload.id)");
  const resetCall = submit.indexOf("resetAttendanceFormAfterSuccess();");

  assert.ok(successCheck >= 0 && resetCall > successCheck);
  assert.match(attendance, /function resetAttendanceFormAfterSuccess\(\)[\s\S]*?setPatient\(null\)[\s\S]*?setPassport\(""\)[\s\S]*?setSelectedBenefitCode\(null\)[\s\S]*?setSelectedPartnershipId\(null\)[\s\S]*?setCart\(\{\}\)[\s\S]*?setNotes\(""\)/);
  assert.doesNotMatch(submit.slice(submit.indexOf("catch")), /resetAttendanceFormAfterSuccess/);
  assert.match(submit, /if \(loading\) return/);
  assert.match(attendance, /disabled=\{loading \|\| patientLoading/);
});

test("new v2 exam snapshots omit indication only from final presentation", async () => {
  const [migration, types, model, component, pdf, png] = await Promise.all([
    read("supabase/migrations/20260921205110_post_go_priority_rollup.sql"),
    read("app/lib/exams.ts"),
    read("app/lib/final-exam-document.ts"),
    read("app/components/final-exam-document.tsx"),
    read("app/lib/final-exam-pdf.ts"),
    read("app/lib/final-exam-png.ts"),
  ]);

  assert.match(migration, /hpsm\.exam_report_snapshot\.v1/);
  assert.match(migration, /hpsm\.exam_report_snapshot\.v2/);
  assert.doesNotMatch(migration, /update public\.clinical_exams/);
  assert.match(types, /"hpsm\.exam_report_snapshot\.v1" \| "hpsm\.exam_report_snapshot\.v2"/);
  assert.match(model, /const storedIndication = snapshot\?\.indication \?\? exam\.indication/);
  assert.match(model, /indication: cleanClinicalText\(outcomeMatch \? storedIndication\.slice/);
  assert.match(model, /showIndication: snapshot\?\.schema !== "hpsm\.exam_report_snapshot\.v2"/);
  for (const renderer of [component, pdf, png]) {
    assert.match(renderer, /showIndication/);
    assert.match(renderer, /Indicação clínica|Solicitação clínica/);
  }
});

test("there is no HPSM idle logout while manual and technical session controls remain", async () => {
  const [shell, sidebar, login, logout, session] = await Promise.all([
    read("app/components/persistent-app-shell.tsx"),
    read("app/components/app-sidebar.tsx"),
    read("app/api/auth/login/route.ts"),
    read("app/api/auth/logout/route.ts"),
    read("app/lib/session.ts"),
  ]);

  assert.doesNotMatch(shell, /mousemove|pointermove|pointerdown|touchstart|lastActivity|idleTimeout|inactivity/i);
  assert.doesNotMatch(shell, /\/api\/auth\/logout/);
  assert.match(sidebar, /action="\/api\/auth\/logout"/);
  assert.match(logout, /revokeProfessionalSession/);
  assert.match(login, /hp_refresh_token/);
  assert.match(session, /must_change_password/);
});
