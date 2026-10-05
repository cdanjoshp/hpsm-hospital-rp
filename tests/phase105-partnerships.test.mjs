import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("fase 10.5 cria uma superfície administrativa permissionada sem entrar na busca global", async () => {
  const [admin, page, api, dashboard, search] = await Promise.all([
    read("app/lib/administrative.ts"), read("app/administrativo/parcerias/page.tsx"), read("app/api/partnerships/route.ts"),
    read("app/lib/dashboard-customization.ts"), read("app/lib/global-search.ts"),
  ]);
  assert.match(admin, /id: "partnerships"[\s\S]*?permissionCodes: \["partnerships\.view", "partnerships\.manage"\]/);
  assert.match(page, /requireAdministrativeContext\("partnerships"\)/);
  assert.match(api, /hasPermission\(context\.profile, "partnerships\.view"\)/);
  assert.match(api, /hasPermission\(context\.profile, "partnerships\.manage"\)/);
  assert.match(dashboard, /partnerships: "Organizações e beneficiários"/);
  assert.doesNotMatch(search, /partnership/i);
});

test("tabelas de parceria forçam RLS e todas as escritas passam por RPCs autorizadas", async () => {
  const sql = await read("supabase/migrations/20260915162000_phase105_partnerships.sql");
  for (const table of ["partnerships", "partnership_responsible_history", "partnership_status_history", "patient_partnerships", "partnership_pending_beneficiaries"]) {
    assert.match(sql, new RegExp(`alter table public\\.${table} force row level security`));
  }
  assert.match(sql, /revoke all on public\.partnerships,[\s\S]*?from public, anon, authenticated, service_role/);
  assert.match(sql, /private\.partnership_assert_professional\('partnerships\.manage'\)/);
  assert.match(sql, /grant execute on function public\.hpsm_partnership_page[\s\S]*?to authenticated/);
});

test("responsável do Portal é revalidado em toda mutação e recebe apenas dados mínimos", async () => {
  const [sql, api, portal] = await Promise.all([
    read("supabase/migrations/20260915162000_phase105_partnerships.sql"),
    read("app/api/patient-portal/partnerships/route.ts"),
    read("app/components/patient-portal-partnerships.tsx"),
  ]);
  assert.match(sql, /private\.partnership_portal_actor\(p_token_hash, p_partnership_id, true\)/);
  assert.match(sql, /where partnership\.responsible_patient_id = v_session\.patient_id/);
  assert.match(sql, /'record_key'.*?'name'.*?'passport'.*?'status'.*?'occurred_at'/s);
  assert.doesNotMatch(sql.slice(sql.indexOf("create or replace function public.patient_portal_partnership_member_page"), sql.indexOf("create or replace function public.patient_portal_import_partnership_people")), /birth_date|phone|clinical|attendance|total_amount/);
  assert.doesNotMatch(api, /patientId|patient_id/);
  assert.match(portal, /Somente nome, passaporte e situação/);
  assert.doesNotMatch(portal, /window\.confirm|window\.prompt/);
});

test("importação é parcial, idempotente e nunca cria paciente incompleto", async () => {
  const sql = await read("supabase/migrations/20260915162000_phase105_partnerships.sql");
  const apply = sql.slice(sql.indexOf("create or replace function private.partnership_apply_people"), sql.indexOf("-- ---------------------------------------------------------------------------\n-- RPCs profissionais"));
  assert.match(apply, /jsonb_array_length\(p_people\) > 500/);
  assert.match(apply, /v_result := 'invalid'/);
  assert.match(apply, /v_result := 'already_linked'/);
  assert.match(apply, /'pending_registration'/);
  assert.match(apply, /'name_review'/);
  assert.doesNotMatch(apply, /insert into public\.patients/);
  assert.match(sql, /create trigger patients_resolve_partnership_pending[\s\S]*?after insert on public\.patients/);
});

test("passaporte soberano resolve pendência exata e envia divergência de nome à revisão interna", async () => {
  const sql = await read("supabase/migrations/20260915162000_phase105_partnerships.sql");
  assert.match(sql, /where patient\.passport = v_passport/);
  assert.match(sql, /partnership_name_key\(v_patient\.name\) = private\.partnership_name_key\(v_name\)/);
  assert.match(sql, /status = 'name_review'/);
  assert.match(sql, /review_partnership_pending\(p_pending_id bigint, p_decision text/);
});

test("atendimento exige vínculo ativo, grava o snapshot e preserva linhas históricas legadas", async () => {
  const [sql, route, desk] = await Promise.all([
    read("supabase/migrations/20260915162000_phase105_partnerships.sql"), read("app/api/attendances/route.ts"), read("app/components/attendance-desk.tsx"),
  ]);
  assert.match(sql, /v_plan_code = 'parceiros_hp'[\s\S]*?membership\.status = 'active'[\s\S]*?partnership\.status = 'active'/);
  assert.match(sql, /partnership_id, partnership_name,[\s\S]*?p_partnership_id, v_partnership_name/);
  assert.match(sql, /plan_code = 'parceiros_hp'[\s\S]*?partnership_id is null and partnership_name is null/);
  assert.match(route, /p_partnership_id: partnershipId/);
  assert.match(desk, /Selecione qual parceria será utilizada neste atendimento/);
  assert.match(desk, /O Plano de Saúde ativo tem prioridade neste atendimento/);
});

test("perfil, histórico e relatório mostram a parceria sem alterar o benefício existente", async () => {
  const [profile, reports, reportUi, migration, benefitPlans] = await Promise.all([
    read("app/components/patient-profile.tsx"), read("app/lib/administrative-reports.ts"), read("app/components/administrative-reports.tsx"),
    read("supabase/migrations/20260915162000_phase105_partnerships.sql"), read("app/lib/benefit-plans.ts"),
  ]);
  assert.match(profile, /code: "partnerships", label: "Parcerias"/);
  assert.match(migration, /'partnership_id', attendance\.partnership_id,[\s\S]*?'partnership_name', attendance\.partnership_name/);
  assert.match(reports, /hpsm_report_partnerships/);
  assert.match(reportUi, /Utilização por parceria/);
  assert.match(benefitPlans, /parceiros_hp/);
});

test("interface cobre tema escuro, celular e não usa caixas nativas bloqueantes", async () => {
  const [styles, admin, portal, modalFocus] = await Promise.all([
    read("app/brand.css"), read("app/components/partnership-management.tsx"), read("app/components/patient-portal-partnerships.tsx"), read("app/components/use-modal-focus.ts"),
  ]);
  assert.match(styles, /Fase 10\.5 · Parcerias e Convênios/);
  assert.match(styles, /html\[data-theme="dark"\] \.partnership-metrics/);
  assert.match(styles, /@media \(max-width: 620px\)[\s\S]*?\.partnership-metrics/);
  assert.doesNotMatch(`${admin}\n${portal}`, /window\.confirm|window\.alert|window\.prompt/);
  assert.match(admin, /aria-modal="true"/);
  assert.match(portal, /aria-modal="true"/);
  assert.match(`${admin}\n${portal}`, /useModalFocus/);
  assert.match(modalFocus, /event\.key === "Escape"/);
  assert.match(modalFocus, /event\.key !== "Tab"/);
  assert.match(styles, /\.patient-portal-partnership-tools label/);
});

test("seleção do responsável aceita todo paciente canônico sem exigir campos opcionais", async () => {
  const [admin, migration, sql] = await Promise.all([
    read("app/components/partnership-management.tsx"),
    read("supabase/migrations/20260923152912_patient_portal_pin_and_self_service.sql"),
    read("supabase/migrations/20260915162000_phase105_partnerships.sql"),
  ]);
  assert.doesNotMatch(admin, /disabled=\{!patient\.portal_ready\}|Completar cadastro|falta informar a data de nascimento/);
  assert.match(admin, /setResponsible\(patient\)/);
  assert.match(migration, /private\.partnership_patient_can_use_portal[\s\S]*?patient\.passport ~ '\^\[0-9\]\{4\}\$'/);
  assert.doesNotMatch(migration.match(/create or replace function private\.partnership_patient_can_use_portal[\s\S]*?\$\$;/)?.[0] ?? "", /birth_date/);
  assert.match(sql, /not private\.partnership_patient_can_use_portal\(p_responsible_patient_id\)/);
});
