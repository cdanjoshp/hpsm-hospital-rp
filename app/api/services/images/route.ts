import { attachCatalogImageUrls, getServiceCatalogMetadata } from "../../../lib/operational-data";
import { getSessionAccessToken } from "../../../lib/session";
import { SupabaseUserRpcError } from "../../../lib/supabase-user";

export async function POST(request: Request) {
  const accessToken = await getSessionAccessToken();
  if (!accessToken) return Response.json({ error: "Sessão expirada." }, { status: 401 });

  try {
    const body = (await request.json()) as { serviceIds?: unknown };
    if (!Array.isArray(body.serviceIds) || body.serviceIds.length > 100) {
      return Response.json({ error: "Lista de imagens inválida." }, { status: 400 });
    }
    const serviceIds = new Set(body.serviceIds.map(Number).filter((id) => Number.isSafeInteger(id) && id > 0));
    if (serviceIds.size !== body.serviceIds.length) {
      return Response.json({ error: "Lista de imagens inválida." }, { status: 400 });
    }

    const catalog = await getServiceCatalogMetadata(accessToken);
    const requested = catalog.filter((service) => serviceIds.has(service.id) && service.image_path);
    const resolved = await attachCatalogImageUrls(requested);
    const images = Object.fromEntries(
      resolved.flatMap((service) => typeof service.image_url === "string" ? [[String(service.id), service.image_url]] : []),
    );
    return Response.json({ images }, { headers: { "cache-control": "private, no-store" } });
  } catch (cause) {
    if (cause instanceof SupabaseUserRpcError && (cause.status === 401 || cause.status === 403)) {
      return Response.json({ error: cause.status === 401 ? "Sessão expirada." : "Acesso não autorizado." }, { status: cause.status });
    }
    return Response.json({ error: "Não foi possível carregar as imagens do catálogo." }, { status: 503 });
  }
}
