import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("mural de Comunicados accepts every active professional and separates reader data from management data", async () => {
  const [page, notifications] = await Promise.all([
    read("app/notificacoes/page.tsx"),
    read("app/lib/notifications.ts"),
  ]);

  assert.match(page, /const canManage = await hasPermission\(profile, "communications\.manage"\)/);
  assert.match(page, /canManage\s*\?\s*await getAnnouncementManagementData\(profile\)\s*:\s*await getAnnouncementReaderData\(profile\)/);
  assert.doesNotMatch(page, /hasPermission\(profile, "communications\.manage"\)\) redirect/);
  assert.match(notifications, /getAnnouncementReaderData[\s\S]*?getNotificationCenterData\(profile\)[\s\S]*?notification\.kind === "announcement"/);
});

test("publication and archive remain protected by communications.manage", async () => {
  const [publishRoute, archiveRoute, component] = await Promise.all([
    read("app/api/notifications/announcements/route.ts"),
    read("app/api/notifications/announcements/archive/route.ts"),
    read("app/components/notification-center.tsx"),
  ]);

  assert.match(publishRoute, /hasPermission\(context\.profile, "communications\.manage"\)/);
  assert.match(archiveRoute, /hasPermission\(context\.profile, "communications\.manage"\)/);
  assert.match(component, /canManage \? <ManagementBoard/);
  assert.match(component, /canManage && showComposer/);
});

test("every displayed announcement opens a complete accessible modal and records its reading", async () => {
  const [component, styles, dashboard] = await Promise.all([
    read("app/components/notification-center.tsx"),
    read("app/brand.css"),
    read("app/components/dashboard-announcements.tsx"),
  ]);

  assert.match(component, /communication-open-button/);
  assert.match(component, /notification-reader-card/);
  assert.match(component, /<AnnouncementDialog/);
  assert.match(component, /useModalFocus\(onClose\)/);
  assert.match(component, /aria-modal="true"/);
  assert.match(component, /fetch\("\/api\/notifications\/read"/);
  assert.match(styles, /\.communication-modal-backdrop/);
  assert.match(styles, /\.communication-modal-body[\s\S]*?white-space:\s*pre-wrap/);
  assert.match(dashboard, /href="\/notificacoes"/);
  assert.doesNotMatch(dashboard, /canViewAll/);
});
