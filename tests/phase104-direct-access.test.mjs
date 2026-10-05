import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("comunicados não lidos aparecem antes dos acessos rápidos e somem após leitura", async () => {
  const [component, announcements] = await Promise.all([
    read("app/components/professional-dashboard.tsx"),
    read("app/components/dashboard-announcements.tsx"),
  ]);
  assert.ok(component.indexOf("<DashboardAnnouncements") < component.indexOf("<ShortcutCard"));
  assert.match(announcements, /filter\(\(item\) => !item\.read_at && !readIds\.has\(item\.id\)\)/);
  assert.match(announcements, /if \(!unread\.length\) return null/);
  assert.match(announcements, /hpsm:notifications-read/);
  assert.match(announcements, /href="\/notificacoes"/);
});

test("preferências legadas permanecem válidas e não controlam mais os blocos", async () => {
  const [config, component, migration] = await Promise.all([
    read("app/lib/dashboard-customization.ts"),
    read("app/components/professional-dashboard.tsx"),
    read("supabase/migrations/20260930150000_dashboard_consultations_hospitalizations_shortcuts.sql"),
  ]);
  assert.match(config, /"attendances"/);
  assert.match(config, /hiddenWidgets: preference\.hiddenWidgets\.filter/);
  assert.match(component, /defaultDashboardPreference\(permissionCodes\), shortcuts: \[\.\.\.draftShortcuts, \.\.\.unavailable\]/);
  assert.match(migration, /'new_attendance', 'attendances'/);
  assert.match(migration, /where left_item\.position < right_item\.position|on left_item\.position < right_item\.position/);
});
