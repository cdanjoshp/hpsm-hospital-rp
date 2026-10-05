import {
  buildWeeklyProgress,
  type HrHourSnapshot,
  type HrLeaveWeekAdjustment,
  type HrWarning,
  type HrWeeklyRecord,
} from "../../lib/hr";
import type { SystemNotification } from "../../lib/notifications";
import { getSessionContext } from "../../lib/session";
import { callSupabaseUserRpc } from "../../lib/supabase-user";

type ShellSnapshot = {
  notifications: SystemNotification[];
  pending_count: number;
  unread_count: number;
  weekly_inputs: null | {
    leaveAdjustments: HrLeaveWeekAdjustment[];
    snapshots: HrHourSnapshot[];
    warnings: HrWarning[];
    weeklyRecords: HrWeeklyRecord[];
  };
};

export async function GET() {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão inválida." }, { status: 401 });
  try {
    const snapshot = await callSupabaseUserRpc<ShellSnapshot>(context.accessToken, "hpsm_shell_snapshot");
    const weeklyProgress = snapshot.weekly_inputs
      ? buildWeeklyProgress(
        snapshot.weekly_inputs.snapshots,
        snapshot.weekly_inputs.leaveAdjustments,
        snapshot.weekly_inputs.warnings,
        snapshot.weekly_inputs.weeklyRecords,
      )
      : null;
    return Response.json({
      notifications: snapshot.notifications,
      pendingCount: Number(snapshot.pending_count) || 0,
      unreadCount: Number(snapshot.unread_count) || 0,
      weeklyProgress,
    }, { headers: { "cache-control": "private, no-store" } });
  } catch {
    return Response.json({ notifications: [], pendingCount: 0, unreadCount: 0, weeklyProgress: null }, {
      headers: { "cache-control": "private, no-store" },
      status: 503,
    });
  }
}
