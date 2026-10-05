import { hasPermission } from "../../../../lib/access";
import { getHrProductionData } from "../../../../lib/hr-production";
import { getSessionContext } from "../../../../lib/session";

export async function GET(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "hr.reports.view")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });

  const month = new URL(request.url).searchParams.get("month") ?? "";
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) {
    return Response.json({ error: "Selecione uma competência válida." }, { status: 400 });
  }

  try {
    return Response.json(await getHrProductionData(context.accessToken, month));
  } catch {
    return Response.json({ error: "Não foi possível consultar os atendimentos da competência." }, { status: 500 });
  }
}
