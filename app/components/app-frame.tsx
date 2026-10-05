import type { SessionProfile } from "../lib/session";
import type { SystemNotification } from "../lib/notifications";
import type { WeeklyProgress } from "../lib/hr";

type AppFrameProps = {
  active: "dashboard" | "patients" | "consultations" | "assist" | "attendances" | "exams" | "casts" | "hospitalizations" | "certificates" | "catalog" | "audit" | "my-hr" | "hr" | "notifications";
  children: React.ReactNode;
  profile: SessionProfile;
  title: string;
  description: string;
  unreadNotificationCount?: number;
  headerNotifications?: SystemNotification[];
  weeklyProgress?: WeeklyProgress | null;
};

export function AppFrame({
  children,
}: AppFrameProps) {
  return children;
}
