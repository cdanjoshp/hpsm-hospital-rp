import { academyError, readAcademy } from "../../lib/academy";
import { callSupabaseUserRpc } from "../../lib/supabase-user";
import { getSessionBootstrap } from "../../lib/session";

export async function GET(request: Request) {
  const context = await getSessionBootstrap();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  const params = new URL(request.url).searchParams;
  const view = params.get("view") ?? "catalog";
  const isAdmin = view.startsWith("admin");
  if (isAdmin ? !(context.permissionCodes.includes("courses.academy.manage") && context.permissionCodes.includes("courses.manage") && context.positionLevel !== null && context.positionLevel >= 12 && context.positionLevel <= 14)
    : !context.permissionCodes.includes("courses.study")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
  try {
    return Response.json(await readAcademy(context.accessToken, view, number(params.get("courseId")), number(params.get("refId")),
      Math.max(1, Math.min(100000, number(params.get("page")) ?? 1)), params.get("search")?.slice(0, 80) ?? ""));
  } catch (error) { return academyError(error); }
}

export async function POST(request: Request) {
  const context = await getSessionBootstrap();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  try {
    const raw = await request.text();
    if (raw.length > 60000) return Response.json({ error: "Conteúdo muito extenso." }, { status: 413 });
    const body = JSON.parse(raw) as Record<string, unknown>;
    const action = typeof body.action === "string" ? body.action : "";
    const adminActions = ["create_course","update_course","publish","unpublish","archive","save_lesson","remove_lesson","reorder_lessons",
      "save_assessment","save_question","remove_question","override_grade","grant_attempt"];
    const studentActions = ["enroll","lesson_start","lesson_complete","attempt_start","attempt_save","attempt_submit"];
    if (!adminActions.includes(action) && !studentActions.includes(action)) return Response.json({ error: "Ação inválida." }, { status: 400 });
    const director = context.positionLevel !== null && context.positionLevel >= 12 && context.positionLevel <= 14;
    const allowed = adminActions.includes(action)
      ? director && context.permissionCodes.includes("courses.academy.manage") && context.permissionCodes.includes(action === "override_grade" ? "courses.results.manage" : action === "grant_attempt" ? "courses.attempts.reopen" : "courses.manage")
      : context.permissionCodes.includes(action.startsWith("attempt") ? "courses.takeexam" : "courses.study");
    if (!allowed) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
    const payload = { ...body };
    delete payload.action;
    if (action === "reorder_lessons") {
      if (!Number.isSafeInteger(body.course_id) || Number(body.course_id) < 1 || !Array.isArray(body.lesson_ids)
        || !body.lesson_ids.every((id) => Number.isSafeInteger(id) && id > 0))
        return Response.json({ error: "Ordem das aulas inválida." }, { status: 400 });
      return Response.json(await callSupabaseUserRpc(context.accessToken, "academy_reorder_lessons",
        { p_course_id: body.course_id, p_lesson_ids: body.lesson_ids }));
    }
    return Response.json(await callSupabaseUserRpc(context.accessToken, adminActions.includes(action) ? "academy_manage" : "academy_study",
      { p_action: action, p_payload: payload }));
  } catch (error) { return academyError(error); }
}

function number(value: string | null) {
  if (!value) return null;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}
