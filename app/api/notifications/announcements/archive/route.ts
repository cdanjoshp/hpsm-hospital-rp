import { hasPermission } from "../../../../lib/access";
import { HrActionError } from "../../../../lib/hr-server";
import { callNotificationRpc, type SystemNotification } from "../../../../lib/notifications";
import { getSessionContext } from "../../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "communications.manage")) return Response.json({ error: "Você não possui permissão para arquivar comunicados." }, { status: 403 });

  try {
    const body = (await request.json()) as { notificationId?: unknown };
    const notificationId = Number(body.notificationId);
    if (!Number.isSafeInteger(notificationId) || notificationId < 1) {
      return Response.json({ error: "Aviso inválido." }, { status: 400 });
    }
    const notification = await callNotificationRpc<SystemNotification>("archive_notification_announcement", {
      p_actor_id: context.profile.user_id,
      p_notification_id: notificationId,
    });
    return Response.json({ notification });
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível arquivar o aviso.";
    return Response.json({ error: message }, { status: 400 });
  }
}
