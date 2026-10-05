import { hasPermission } from "../../../lib/access";
import { HrActionError } from "../../../lib/hr-server";
import { callNotificationRpc, type SystemNotification } from "../../../lib/notifications";
import { getSessionContext } from "../../../lib/session";

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "communications.manage")) return Response.json({ error: "Você não possui permissão para publicar comunicados." }, { status: 403 });

  try {
    const body = (await request.json()) as Record<string, unknown>;
    const title = typeof body.title === "string" ? body.title.trim() : "";
    const message = typeof body.body === "string" ? body.body.trim() : "";
    const audience = body.audience;
    const priority = body.priority;
    const expiresOn = typeof body.expiresOn === "string" ? body.expiresOn.trim() : "";
    if (title.length < 4 || title.length > 120 || message.length < 10 || message.length > 2000) {
      return Response.json({ error: "Revise o título e a mensagem do aviso." }, { status: 400 });
    }
    if (audience !== "all" && audience !== "directors" && audience !== "employees") {
      return Response.json({ error: "Público do aviso inválido." }, { status: 400 });
    }
    if (priority !== "normal" && priority !== "important" && priority !== "urgent") {
      return Response.json({ error: "Prioridade do aviso inválida." }, { status: 400 });
    }
    let expiresAt: string | null = null;
    if (expiresOn) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(expiresOn)) {
        return Response.json({ error: "Data de validade inválida." }, { status: 400 });
      }
      expiresAt = `${expiresOn}T23:59:59-03:00`;
      if (new Date(expiresAt).getTime() <= Date.now()) {
        return Response.json({ error: "A validade precisa estar no futuro." }, { status: 400 });
      }
    }

    const notification = await callNotificationRpc<SystemNotification>("publish_notification_announcement", {
      p_actor_id: context.profile.user_id,
      p_audience: audience,
      p_body: message,
      p_expires_at: expiresAt,
      p_priority: priority,
      p_title: title,
    });
    return Response.json({ notification });
  } catch (error) {
    const message = error instanceof HrActionError ? error.message : "Não foi possível publicar o aviso.";
    return Response.json({ error: message }, { status: 400 });
  }
}
