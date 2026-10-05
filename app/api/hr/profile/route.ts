import { hasAnyPermission } from "../../../lib/access";
import { getFunctionalProfile } from "../../../lib/functional-profile";
import { isUuid } from "../../../lib/hr-server";
import { getSessionContext } from "../../../lib/session";

const PROFILE_PERMISSION_CODES = ["hr.team.view", "hr.reports.view", "team.manage", "access.manage"] as const;

export async function GET(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasAnyPermission(context.profile, PROFILE_PERMISSION_CODES)) {
    return Response.json({ error: "Você não possui permissão para consultar perfis funcionais." }, { status: 403 });
  }

  const employeeId = new URL(request.url).searchParams.get("employeeId") ?? "";
  if (!isUuid(employeeId)) return Response.json({ error: "Selecione um colaborador válido." }, { status: 400 });

  try {
    const profile = await getFunctionalProfile(employeeId);
    if (!profile) return Response.json({ error: "Colaborador não encontrado." }, { status: 404 });
    return Response.json(profile);
  } catch {
    return Response.json({ error: "Não foi possível carregar o perfil funcional." }, { status: 500 });
  }
}
