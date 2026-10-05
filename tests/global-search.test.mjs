import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("professional shell exposes a code-split global search and both keyboard shortcuts", async () => {
  const [shell, launcher] = await Promise.all([
    read("app/components/persistent-app-shell.tsx"),
    read("app/components/global-search-launcher.tsx"),
  ]);
  assert.match(shell, /<GlobalSearchLauncher \/>/);
  assert.match(launcher, /dynamic\([\s\S]*?global-search-palette[\s\S]*?ssr: false/);
  assert.match(launcher, /event\.metaKey \|\| event\.ctrlKey/);
  assert.match(launcher, /event\.key\.toLowerCase\(\) === "k"/);
  assert.match(launcher, /Ctrl\+K/);
  assert.match(launcher, /triggerRef\.current\?\.focus\(\)/);
});

test("palette is accessible, responsive and cancels obsolete searches", async () => {
  const [palette, styles] = await Promise.all([
    read("app/components/global-search-palette.tsx"),
    read("app/brand.css"),
  ]);
  for (const semantic of ['role="dialog"', 'role="combobox"', 'role="listbox"', 'role="option"', 'aria-modal="true"']) {
    assert.match(palette, new RegExp(semantic));
  }
  assert.match(palette, /placeholder="Buscar no HPSM\.\.\."/);
  assert.match(palette, /new AbortController\(\)/);
  assert.match(palette, /requestSequence/);
  assert.match(palette, /}, 275\)/);
  for (const key of ["ArrowDown", "ArrowUp", "Enter", "Escape"]) assert.match(palette, new RegExp(`event\\.key === "${key}"`));
  assert.match(palette, /event\.key !== "Tab"/);
  assert.match(styles, /\.global-search-overlay/);
  assert.match(styles, /html\[data-theme="dark"\] \.global-search-dialog/);
  assert.match(styles, /@media \(max-width: 620px\)[\s\S]*?\.global-search-dialog \{ width: 100%; max-height: calc\(100dvh - 24px\)/);
  assert.match(styles, /@media \(max-width: 360px\)/);
});

test("one no-store backend request delegates authorization to the session-validated RPC", async () => {
  const route = await read("app/api/global-search/route.ts");
  assert.match(route, /getSessionAccessToken\(\)/);
  assert.match(route, /if \(!accessToken\).*status: 401/s);
  assert.match(route, /query\.length < 2/);
  assert.match(route, /query\.length > 100/);
  assert.match(route, /"hpsm_global_search"/);
  assert.match(route, /p_limit: 5/);
  assert.match(route, /private, no-store, max-age=0/);
  assert.match(route, /vary: "Cookie"/);
  assert.doesNotMatch(route, /Promise\.all|clinical_exams|\/api\/exams/);
});

test("database search uses effective permissions, bounded groups and no clinical source", async () => {
  const migration = await read("supabase/migrations/20260911105545_phase7_global_professional_search.sql");
  const body = migration.slice(migration.indexOf("as $$"), migration.indexOf("$$;", migration.indexOf("as $$")));
  assert.match(body, /private\.hpsm_current_actor\(\)/);
  assert.match(body, /public\.effective_permission_codes\(v_actor\)/);
  assert.match(body, /least\(greatest\(coalesce\(p_limit, 5\), 1\), 5\)/);
  for (const permission of ["patients.view", "hr.team.view", "hr.reports.view", "team.manage", "access.manage", "attendances.create", "attendances.manage", "catalog.manage", "recruitment.manage"]) {
    assert.match(body, new RegExp(permission.replace(".", "\\.")));
  }
  for (const source of ["public.patients", "public.profiles", "public.attendances", "public.service_catalog", "public.recruitment_applications"]) {
    assert.match(body, new RegExp(source.replace(".", "\\.")));
  }
  assert.doesNotMatch(body, /clinical_exams|exam_types|exam_categories|clinical_casts/);
  assert.match(migration, /set search_path = ''/);
  assert.match(migration, /revoke all on function public\.hpsm_global_search\(text, integer\)[\s\S]*?from public, anon, authenticated, service_role/);
  assert.match(migration, /grant execute on function public\.hpsm_global_search\(text, integer\)[\s\S]*?to authenticated/);
});

test("ranking and canonical deep links preserve the operational destinations", async () => {
  const [migration, catalogPage, catalog, profilesPage, profiles] = await Promise.all([
    read("supabase/migrations/20260911105545_phase7_global_professional_search.sql"),
    read("app/catalogo/page.tsx"),
    read("app/components/catalog-management.tsx"),
    read("app/administrativo/perfis/page.tsx"),
    read("app/components/functional-profile.tsx"),
  ]);
  assert.match(migration, /upper\(patient\.passport\) = upper\(v_query\) then 1/);
  assert.match(migration, /patient\.passport ilike v_prefix[\s\S]*?then 2/);
  for (const href of ["/pacientes/", "/atendimentos#atendimento-", "/catalogo?item=", "/administrativo/perfis?selecionar=", "/administrativo/recrutamento?selecionar="]) {
    assert.match(migration, new RegExp(href.replace(/[?]/g, "\\?")));
  }
  assert.match(catalogPage, /searchParams: Promise<\{ item\?: string \}>/);
  assert.match(catalog, /initialEditingId/);
  assert.match(profilesPage, /searchParams: Promise<\{ selecionar\?: string \}>/);
  assert.match(profiles, /initialSelectedId/);
});
