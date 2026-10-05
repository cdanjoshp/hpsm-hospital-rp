import { callNotificationRpc } from "../../../lib/notifications";
import { HrActionError } from "../../../lib/hr-server";
import { getSessionContext } from "../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });

  try {
    const body = (await request.json()) as { all?: unknown; notificationId?: unknown };
    if (body.all === true) {
      const count = await callNotificationRpc<number>("mark_all_notifications_read", {
        p_actor_id: context.profile.user_id,
      });
      return Response.json({ count });
    }

    const notificationId = Number(body.notificationId);
    if (!Number.isSafeInteger(notificationId) || notificationId < 1) {
      return Response.json({ error: "Notificação inválida." }, { status: 400 });
    }
    const read = await callNotificationRpc<Record<string, unknown>>("mark_notification_read", {
      p_actor_id: context.profile.user_id,
      p_notification_id: notificationId,
    });
    return Response.json({ read });
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível registrar a leitura.";
    return Response.json({ error: message }, { status: 400 });
  }
}

