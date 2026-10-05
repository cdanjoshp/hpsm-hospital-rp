import { hasAnyPermission, hasPermission } from "../../../lib/access";
import { authenticatedHeaders } from "../../../lib/operational-data";
import { getSessionContext } from "../../../lib/session";
import type { SessionProfile } from "../../../lib/session";
import { getSupabaseAdminConfig, getSupabaseConfig } from "../../../lib/supabase-server";

const MAX_IMAGE_SIZE = 2 * 1024 * 1024;
const IMAGE_TYPES = new Map([
  ["image/jpeg", "jpg"],
  ["image/png", "png"],
  ["image/webp", "webp"],
]);

type CatalogImageRow = { id: number; image_path: string | null };

export async function GET(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await canViewCatalog(context.profile)) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });

  const serviceId = parseServiceId(new URL(request.url).searchParams.get("id"));
  if (!serviceId) return Response.json({ error: "Item inválido." }, { status: 400 });

  try {
    const service = await getService(serviceId, context.accessToken);
    if (!service?.image_path) return Response.json({ error: "Imagem não encontrada." }, { status: 404 });
    const signedUrl = await signImage(service.image_path);
    return new Response(null, {
      status: 302,
      headers: {
        "cache-control": "private, max-age=540",
        location: signedUrl,
      },
    });
  } catch {
    return Response.json({ error: "Não foi possível abrir a imagem." }, { status: 500 });
  }
}

export async function POST(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "catalog.manage")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });

  let storagePath = "";
  try {
    const form = await request.formData();
    const serviceId = parseServiceId(form.get("serviceId"));
    const file = form.get("file");
    if (!serviceId || !(file instanceof File)) return Response.json({ error: "Selecione uma imagem e o item correspondente." }, { status: 400 });
    const extension = IMAGE_TYPES.get(file.type);
    if (!extension || file.size < 1 || file.size > MAX_IMAGE_SIZE || !await isExpectedImage(file, file.type)) {
      return Response.json({ error: "Envie uma imagem JPG, PNG ou WebP válida com até 2 MB." }, { status: 400 });
    }

    const service = await getService(serviceId, context.accessToken);
    if (!service) return Response.json({ error: "Item não localizado." }, { status: 404 });

    storagePath = `items/${serviceId}/${crypto.randomUUID()}.${extension}`;
    await uploadImage(storagePath, file, context.accessToken);
    const updated = await setServiceImage(serviceId, storagePath, context.accessToken, context.profile.user_id);
    if (!updated) throw new Error("update");
    if (service.image_path) await removeImage(service.image_path, context.accessToken).catch(() => null);
    return Response.json({ service: updated });
  } catch {
    if (storagePath) await removeImage(storagePath, context.accessToken).catch(() => null);
    return Response.json({ error: "Não foi possível salvar a imagem. Tente novamente." }, { status: 400 });
  }
}

export async function DELETE(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  if (!await hasPermission(context.profile, "catalog.manage")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });

  const serviceId = parseServiceId(new URL(request.url).searchParams.get("id"));
  if (!serviceId) return Response.json({ error: "Item inválido." }, { status: 400 });
  try {
    const service = await getService(serviceId, context.accessToken);
    if (!service) return Response.json({ error: "Item não localizado." }, { status: 404 });
    const updated = await setServiceImage(serviceId, null, context.accessToken, context.profile.user_id);
    if (!updated) throw new Error("update");
    if (service.image_path) await removeImage(service.image_path, context.accessToken).catch(() => null);
    return Response.json({ service: updated });
  } catch {
    return Response.json({ error: "Não foi possível remover a imagem." }, { status: 400 });
  }
}

async function canViewCatalog(profile: SessionProfile) {
  return hasAnyPermission(profile, ["catalog.view", "catalog.manage"]);
}

function parseServiceId(value: unknown) {
  const id = Number(value);
  return Number.isSafeInteger(id) && id > 0 ? id : null;
}

async function getService(id: number, accessToken: string): Promise<CatalogImageRow | null> {
  const { url } = getSupabaseConfig();
  const response = await fetch(`${url}/rest/v1/service_catalog?select=id,image_path&id=eq.${id}&limit=1`, {
    headers: authenticatedHeaders(accessToken), cache: "no-store",
  });
  if (!response.ok) throw new Error("read");
  return ((await response.json()) as CatalogImageRow[])[0] ?? null;
}

async function uploadImage(path: string, file: File, accessToken: string) {
  const { url } = getSupabaseConfig();
  const response = await fetch(`${url}/storage/v1/object/catalog-images/${storagePath(path)}`, {
    method: "POST",
    headers: { ...authenticatedHeaders(accessToken), "content-type": file.type, "x-upsert": "false" },
    body: await file.arrayBuffer(),
  });
  if (!response.ok) throw new Error("upload");
}

async function setServiceImage(id: number, imagePath: string | null, accessToken: string, userId: string) {
  const { url } = getSupabaseConfig();
  const response = await fetch(`${url}/rest/v1/service_catalog?id=eq.${id}`, {
    method: "PATCH",
    headers: { ...authenticatedHeaders(accessToken), Prefer: "return=representation" },
    body: JSON.stringify({ image_path: imagePath, updated_by: userId }),
  });
  if (!response.ok) throw new Error("update");
  return ((await response.json()) as CatalogImageRow[])[0] ?? null;
}

async function removeImage(path: string, accessToken: string) {
  const { url } = getSupabaseConfig();
  const response = await fetch(`${url}/storage/v1/object/catalog-images/${storagePath(path)}`, {
    method: "DELETE",
    headers: authenticatedHeaders(accessToken),
  });
  if (!response.ok && response.status !== 404) throw new Error("delete");
}

async function signImage(path: string) {
  const { url, serviceRoleKey } = getSupabaseAdminConfig();
  const response = await fetch(`${url}/storage/v1/object/sign/catalog-images/${storagePath(path)}`, {
    method: "POST",
    headers: { apikey: serviceRoleKey, authorization: `Bearer ${serviceRoleKey}`, "content-type": "application/json" },
    body: JSON.stringify({ expiresIn: 600 }),
  });
  const payload = (await response.json().catch(() => null)) as { signedURL?: string; signedUrl?: string } | null;
  const signed = payload?.signedURL ?? payload?.signedUrl;
  if (!response.ok || !signed) throw new Error("sign");
  return signed.startsWith("http") ? signed : `${url}/storage/v1${signed.startsWith("/") ? "" : "/"}${signed}`;
}

function storagePath(path: string) {
  return path.split("/").map(encodeURIComponent).join("/");
}

async function isExpectedImage(file: File, type: string) {
  const bytes = new Uint8Array(await file.slice(0, 16).arrayBuffer());
  if (type === "image/jpeg") return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (type === "image/png") return bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47;
  return type === "image/webp" && bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 && bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50;
}
