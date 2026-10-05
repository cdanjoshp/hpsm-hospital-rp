import { redirect } from "next/navigation";
import { AppFrame } from "../components/app-frame";
import { NotificationCenter } from "../components/notification-center";
import { hasPermission } from "../lib/access";
import { getAnnouncementManagementData, getAnnouncementReaderData } from "../lib/notifications";
import { getSessionProfile } from "../lib/session";

export const dynamic = "force-dynamic";

export default async function NotificationsPage() {
  const profile = await getSessionProfile();
  if (!profile) redirect("/");
  if (profile.must_change_password) redirect("/primeiro-acesso");

  const canManage = await hasPermission(profile, "communications.manage");
  const announcements = canManage
    ? await getAnnouncementManagementData(profile)
    : await getAnnouncementReaderData(profile);
  return (
    <AppFrame
      active="notifications"
      profile={profile}
      title="Comunicados"
      description={canManage
        ? "Publique avisos e acompanhe alcance, visualizações e situação de leitura."
        : "Consulte os comunicados institucionais destinados a você."}
    >
      <NotificationCenter
        key={announcements.map((item) => `${item.id}:${item.archived_at ?? "active"}:${item.read_at ?? "unread"}`).join("|")}
        canManage={canManage}
        initialAnnouncements={announcements}
        referenceTime={new Date().toISOString()}
      />
    </AppFrame>
  );
}
