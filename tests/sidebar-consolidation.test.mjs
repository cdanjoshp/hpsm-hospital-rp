import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { visibleAdministrativeAreas } from "../app/lib/administrative.ts";
import { buildSidebarNavigation, isSidebarNavigationItemActive } from "../app/lib/sidebar-navigation.ts";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");
const administrativeChildrenFor = (permissionCodes) => visibleAdministrativeAreas(permissionCodes)
  .map((area) => ({ href: area.href, icon: area.id, id: area.id, label: area.label }));
const buildFor = (permissionCodes) => buildSidebarNavigation(permissionCodes, 3, administrativeChildrenFor(permissionCodes));
const itemsFor = (permissionCodes) => buildFor(permissionCodes).flatMap((section) => section.items);

test("sidebar renders only the modules represented by effective permission codes", () => {
  const sections = buildFor(["patients.view", "attendances.create", "exams.view", "casts.view", "hr.self.view", "catalog.manage", "audit.view", "communications.manage"]);
  const navigation = sections.flatMap((section) => section.items);
  assert.deepEqual(sections.map((section) => section.label), ["Visão geral", "Assistência", "Gestão"]);
  assert.equal(sections[0].items[0].label, "Página Inicial");
  assert.deepEqual(navigation.map((item) => item.id), ["dashboard", "my-hr", "patients", "attendances", "exams", "casts", "catalog", "audit", "communications"]);
  assert.equal(navigation.some((item) => item.id === "hr"), false);
  assert.equal(navigation.some((item) => item.id === "records"), false);
});

test("Comunicados is available to every authenticated professional without exposing management actions", () => {
  const navigation = itemsFor([]);
  assert.deepEqual(navigation.map((item) => item.id), ["dashboard", "communications"]);
  assert.equal(navigation.find((item) => item.id === "communications")?.href, "/notificacoes");
});

test("operational links move to Assistance and Management without empty legacy categories", () => {
  const broad = buildFor(["attendances.create", "catalog.manage"]);
  assert.deepEqual(broad.find((section) => section.id === "assistance")?.items.map((item) => [item.id, item.label, item.href]), [
    ["attendances", "Vendas", "/atendimentos"],
  ]);
  assert.deepEqual(broad.find((section) => section.id === "management")?.items.map((item) => [item.id, item.label, item.href]), [
    ["catalog", "Tabela de Preços", "/catalogo"],
    ["communications", "Comunicados", "/notificacoes"],
  ]);
  assert.equal(broad.some((section) => section.label === "Operação" || section.label === "Minha área"), false);
});

test("parent and child active states follow the current route without highlighting every flyout item", () => {
  const attendance = itemsFor(["attendances.create", "catalog.manage"]).find((item) => item.id === "attendances");
  const administrative = itemsFor(["admin.pending.manage", "recruitment.manage"]).find((item) => item.id === "hr");

  assert.equal(isSidebarNavigationItemActive(attendance, "attendances", "/atendimentos"), true);
  assert.equal(isSidebarNavigationItemActive(attendance, "patients", "/pacientes"), false);
  assert.equal(isSidebarNavigationItemActive(administrative, "hr", "/administrativo/pendencias"), true);
  assert.equal(isSidebarNavigationItemActive(administrative, "hr", "/administrativo"), true);
});

test("Academia pages stay in the professional shell and highlight only their own menu entry", async () => {
  const shell = await read("app/components/persistent-app-shell.tsx");
  assert.match(shell, /function isPortalRoute[\s\S]*?"\/academia"/);
  assert.match(shell, /pathname\.startsWith\("\/academia\/gestao"\)\) return "academy_management"/);
  assert.match(shell, /pathname\.startsWith\("\/academia"\)\) return "academy"/);

  const navigation = itemsFor(["courses.study", "courses.academy.manage"]);
  const catalog = navigation.find((item) => item.id === "academy");
  const management = navigation.find((item) => item.id === "academy_management");
  assert.equal(isSidebarNavigationItemActive(catalog, "academy", "/academia"), true);
  assert.equal(isSidebarNavigationItemActive(catalog, "academy", "/academia/42"), true);
  assert.equal(isSidebarNavigationItemActive(catalog, "academy_management", "/academia/gestao"), false);
  assert.equal(isSidebarNavigationItemActive(management, "academy_management", "/academia/gestao"), true);
  assert.equal(isSidebarNavigationItemActive(management, "academy", "/academia/42"), false);
});

test("HPSM Assist remains inside the professional shell with its own active entry and heading", async () => {
  const shell = await read("app/components/persistent-app-shell.tsx");
  assert.match(shell, /function isPortalRoute[\s\S]*?"\/hpsm-assist"/);
  assert.match(shell, /function activeSection[\s\S]*?pathname\.startsWith\("\/hpsm-assist"\)\) return "assist"/);
  assert.match(shell, /function routeHeading[\s\S]*?pathname\.startsWith\("\/hpsm-assist"\)\) return \{ title: "HPSM Assist"/);
});

test("administrative access may be broad, partial or absent without empty groups", () => {
  const everyAdministrativePermission = [
    "admin.pending.manage", "hr.hours.manage", "progression.review", "recruitment.manage",
    "partnerships.view", "team.manage", "hr.team.view", "hr.reports.view",
  ];
  const broad = itemsFor(everyAdministrativePermission).find((item) => item.id === "hr");
  assert.deepEqual(broad?.children?.map((item) => item.id), ["pending", "rh", "career", "recruitment", "partnerships", "team", "profiles", "reports"]);

  const partial = itemsFor(["admin.pending.manage", "recruitment.manage"]).find((item) => item.id === "hr");
  assert.deepEqual(partial?.children?.map((item) => item.id), ["pending", "recruitment"]);

  const absent = itemsFor(["patients.view"]);
  assert.equal(absent.some((item) => item.id === "hr"), false);
});

test("individual and valid temporary grants behave like every other effective code; expired grants disappear upstream", () => {
  const individualGrantResult = itemsFor(["team.manage"]);
  const validTemporaryGrantResult = itemsFor(["team.manage"]);
  const expiredGrantResult = itemsFor([]);

  assert.deepEqual(individualGrantResult, validTemporaryGrantResult);
  assert.deepEqual(individualGrantResult.find((item) => item.id === "hr")?.children?.map((item) => item.id), ["team", "profiles"]);
  assert.equal(expiredGrantResult.some((item) => item.id === "hr"), false);
});

test("canonical permission RPC aggregates position and active grants and excludes revoked, future and expired grants", async () => {
  const resolver = await read("supabase/migrations/20260831220000_restrict_recruitment_to_levels_11_14.sql");
  assert.match(resolver, /join public\.staff_position_permissions position_permission/);
  assert.match(resolver, /join public\.user_permission_grants permission_grant/);
  assert.match(resolver, /permission_grant\.revoked_at is null/);
  assert.match(resolver, /permission_grant\.valid_from <= now\(\)/);
  assert.match(resolver, /permission_grant\.expires_at is null or permission_grant\.expires_at > now\(\)/);
});

test("desktop, collapsed, flyout and mobile consume the same prefiltered navigation", async () => {
  const [sidebar, shell] = await Promise.all([
    read("app/components/app-sidebar.tsx"),
    read("app/components/persistent-app-shell.tsx"),
  ]);
  assert.match(sidebar, /const navigation = useMemo/);
  assert.match(sidebar, /navigationSections\.map\(\(section\) => <NavigationSection/);
  assert.match(sidebar, /items=\{section\.items\}/);
  assert.match(sidebar, /item: navigation\.find/);
  assert.match(sidebar, /!desktopMenu && isOpen \? <InlineSubmenu item=\{item\}/);
  assert.match(sidebar, /data-active=\{pathname === item\.href\}/);
  assert.doesNotMatch(sidebar, /profile\.position_id === null|role_code\s*[>=]/);
  assert.doesNotMatch(sidebar, /Prontuários|nav-disabled|disabled:\s*true/);
  assert.match(shell, /pathname\.startsWith\("\/notificacoes"\)\) return "communications"/);
});

test("administrative sibling navigation was replaced by breadcrumbs while functional tabs remain", async () => {
  const pagePaths = ["pendencias", "rh", "carreira", "recrutamento", "parcerias", "equipe", "perfis", "relatorios"]
    .map((area) => `app/administrativo/${area}/page.tsx`);
  const [pages, breadcrumb, hr] = await Promise.all([
    Promise.all(pagePaths.map(read)).then((sources) => sources.join("\n")),
    read("app/components/administrative-breadcrumb.tsx"),
    read("app/components/hr-management.tsx"),
  ]);
  assert.doesNotMatch(pages, /AdministrativeSectionNav|administrative-section-nav/);
  assert.equal((pages.match(/<AdministrativeBreadcrumb/g) ?? []).length, 8);
  assert.match(breadcrumb, /aria-label="Breadcrumb"/);
  assert.match(breadcrumb, /aria-current="page"/);
  assert.match(hr, /visibleTabs/);
  assert.match(hr, /className="hr-tabs"/);
  assert.match(hr, /className="hr-report-switch"/);
});

test("sidebar typography, icons, focus, motion, dark theme and touch targets use shared visual rules", async () => {
  const [styles, icons, sidebar] = await Promise.all([
    read("app/brand.css"),
    read("app/components/sidebar-icon.tsx"),
    read("app/components/app-sidebar.tsx"),
  ]);
  assert.match(styles, /\.sidebar-modern \.sidebar-nav-item \{[\s\S]*?color:\s*#62c3ff;[\s\S]*?font-family:\s*inherit;[\s\S]*?font-size:\s*1rem;[\s\S]*?font-weight:\s*650;[\s\S]*?line-height:\s*var\(--leading-compact\);/);
  assert.match(styles, /\.sidebar-modern \.sidebar-nav-icon \{ width: 20px; height: 20px; display: grid; place-items: center;/);
  assert.match(styles, /\.sidebar-modern \.sidebar-nav-item > \.sidebar-nav-label \{[\s\S]*?color:\s*inherit; font:\s*inherit;[\s\S]*?text-align:\s*left;/);
  assert.doesNotMatch(styles, /\.sidebar-modern \.sidebar-group-trigger\s*\{[^}]*font-(?:family|size|weight)/);
  assert.match(sidebar, /className="sidebar-nav-item"/);
  assert.match(sidebar, /className="sidebar-nav-item sidebar-group-trigger"/);
  assert.match(styles, /\.sidebar-flyout-layer[\s\S]*?\.sidebar-flyout-bridge/);
  assert.match(styles, /html\[data-theme="dark"\] \.sidebar-flyout/);
  assert.match(styles, /@media \(prefers-reduced-motion: reduce\)/);
  assert.match(styles, /@media \(max-width: 820px\)[\s\S]*?\.sidebar-modern \.sidebar-nav-item \{ justify-content:\s*flex-start;[\s\S]*?text-align:\s*left;/);
  assert.doesNotMatch(styles, /@media \(max-width: 820px\)[\s\S]*?\.sidebar-modern \.sidebar-group-trigger \{ justify-content:\s*flex-start;/);
  assert.match(styles, /@media \(max-width: 820px\)[\s\S]*?\.sidebar-modern \.sidebar-nav-section > p \{ display:\s*block;/);
  assert.match(icons, /<svg aria-hidden="true"/);
});

test("mobile sidebar is an accessible overlay and keeps every navigation label visible", async () => {
  const [styles, sidebar] = await Promise.all([
    read("app/brand.css"),
    read("app/components/app-sidebar.tsx"),
  ]);
  assert.match(sidebar, /aria-controls="professional-navigation"/);
  assert.match(sidebar, /className="sidebar-mobile-backdrop"/);
  assert.match(sidebar, /className="sidebar-mobile-close"/);
  assert.match(sidebar, /document\.body\.style\.overflow = "hidden"/);
  assert.match(sidebar, /event\.key !== "Escape"/);
  assert.match(sidebar, /setMobileOpen\(false\)/);
  assert.match(styles, /@media \(max-width: 820px\)[\s\S]*?\.sidebar-modern \{[\s\S]*?position:\s*fixed;[\s\S]*?height:\s*100dvh;/);
  assert.match(styles, /\.sidebar-modern\[data-mobile-open="true"\] \{ transform:\s*translateX\(0\); visibility:\s*visible;/);
  assert.match(styles, /\.sidebar-modern \.sidebar-nav-item > \.sidebar-nav-label \{ display:\s*block; \}/);
  assert.match(styles, /\.sidebar-modern \.sidebar-inline-submenu a > span \{ display:\s*grid; \}/);
});

test("direct administrative routes keep server-side permission protection", async () => {
  const guard = await read("app/lib/administrative-server.ts");
  assert.match(guard, /getEffectivePermissionCodes\(context\.profile\.user_id\)/);
  assert.match(guard, /canAccessAdministrativeArea\(permissionCodes, areaId\)/);
  assert.match(guard, /redirect\("\/painel"\)/);
  assert.match(guard, /redirect\("\/administrativo"\)/);
});
