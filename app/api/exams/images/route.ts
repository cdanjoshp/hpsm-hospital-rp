import { getEffectivePermissionCodes } from "../../../lib/access";
import { adminHeaders } from "../../../lib/admin-data";
import { getClinicalExamImageGallery, runClinicalExamMutation, type ClinicalExamImage } from "../../../lib/exams";
import { getSessionContext } from "../../../lib/session";
import { getSupabaseAdminConfig } from "../../../lib/supabase-server";

export async function GET(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  const permissions = new Set(await getEffectivePermissionCodes(context.profile.user_id));
  if (!permissions.has("exams.view")) return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
  const examId = positiveInteger(new URL(request.url).searchParams.get("examId"));
  if (!examId) return Response.json({ error: "Exame inválido." }, { status: 400 });

  try {
    const images = await getClinicalExamImageGallery(context.accessToken, examId);
    const signed = await signImages(images);
    return Response.json({ images: signed }, { headers: { "cache-control": "private, no-store" } });
  } catch (error) {
    return examError(error, "Não foi possível carregar as imagens.");
  }
}

export async function POST() {
  return Response.json({ error: "O envio manual de imagens foi desativado. Gere a imagem pela IA dentro do exame." }, { status: 405 });
}

export async function DELETE(request: Request) {
  const context = await getSessionContext();
  if (!context) return Response.json({ error: "Sessão expirada." }, { status: 401 });
  const permissions = new Set(await getEffectivePermissionCodes(context.profile.user_id));
  if (!permissions.has("exams.perform") && !permissions.has("exams.review")) {
    return Response.json({ error: "Acesso não autorizado." }, { status: 403 });
  }
  const imageId = new URL(request.url).searchParams.get("id") ?? "";
  if (!isUuid(imageId)) return Response.json({ error: "Imagem inválida." }, { status: 400 });

  try {
    const storagePath = await runClinicalExamMutation<string>(context.accessToken, "remove_clinical_exam_image", { p_image_id: imageId });
    try {
      await deleteStoredImage(storagePath);
    } catch (storageError) {
      await runClinicalExamMutation(context.accessToken, "restore_clinical_exam_image", { p_image_id: imageId });
      throw storageError;
    }
    return Response.json({ ok: true });
  } catch (error) {
    return examError(error, "Não foi possível remover a imagem.");
  }
}

async function deleteStoredImage(path: string) {
  const { url, serviceRoleKey } = getSupabaseAdminConfig();
  const response = await fetch(`${url}/storage/v1/object/clinical-exam-images/${storagePath(path)}`, {
    method: "DELETE",
    headers: adminHeaders(serviceRoleKey),
  });
  if (!response.ok && response.status !== 404) throw new Error("O arquivo não pôde ser removido do Storage.");
}

async function signImages(images: ClinicalExamImage[]) {
  if (!images.length) return images;
  const { url, serviceRoleKey } = getSupabaseAdminConfig();
  const response = await fetch(`${url}/storage/v1/object/sign/clinical-exam-images`, {
    method: "POST",
    headers: adminHeaders(serviceRoleKey),
    body: JSON.stringify({ expiresIn: 120, paths: images.map((image) => image.storage_path) }),
  });
  const payload = await response.json().catch(() => null) as Array<{ error?: string; path?: string; signedURL?: string; signedUrl?: string }> | null;
  if (!response.ok || !Array.isArray(payload)) throw new Error("Não foi possível autorizar a visualização das imagens.");
  return images.map((image, index) => {
    const item = payload[index];
    const signed = item?.signedURL ?? item?.signedUrl;
    if (!signed || item?.error) throw new Error("Não foi possível autorizar uma das imagens.");
    return { ...image, signed_url: signed.startsWith("http") ? signed : `${url}/storage/v1${signed.startsWith("/") ? "" : "/"}${signed}` };
  });
}

function positiveInteger(value: unknown) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

function storagePath(path: string) {
  return path.split("/").map(encodeURIComponent).join("/");
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function examError(error: unknown, fallback: string) {
  const message = error instanceof Error ? error.message : fallback;
  const forbidden = /acesso não autorizado/i.test(message);
  return Response.json({ error: forbidden ? "Acesso não autorizado." : message }, { status: forbidden ? 403 : 400 });
}
