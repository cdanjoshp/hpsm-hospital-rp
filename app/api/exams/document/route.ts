import { getEffectivePermissionCodes } from "../../../lib/access";
import { adminHeaders } from "../../../lib/admin-data";
import { getClinicalExamDetail, getClinicalExamImageGallery } from "../../../lib/exams";
import { buildFinalExamDocument } from "../../../lib/final-exam-document";
import { renderFinalExamPdf, type FinalExamPdfImage } from "../../../lib/final-exam-pdf";
import { getSessionContext } from "../../../lib/session";
import { getSupabaseAdminConfig } from "../../../lib/supabase-server";
import { enrichClinicalExamIdentities, loadProfessionalDocumentIdentity } from "../../../lib/professional-identity";

const MAX_PDF_IMAGE_BYTES = 40 * 1024 * 1024;

export async function GET(request: Request) {
  const context = await getSessionContext();
  if (!context) return pdfError("Sessão expirada.", 401);
  const permissions = new Set(await getEffectivePermissionCodes(context.profile.user_id));
  if (!permissions.has("exams.view")) return pdfError("Acesso não autorizado.", 403);

  const url = new URL(request.url);
  const examId = positiveInteger(url.searchParams.get("id"));
  if (!examId) return pdfError("Exame inválido.", 400);
  const disposition = url.searchParams.get("view") === "1" ? "inline" : "attachment";

  try {
    const exam = await enrichClinicalExamIdentities(await getClinicalExamDetail(context.accessToken, examId));
    if (exam.status !== "completed" || !exam.final_report_snapshot) {
      return pdfError("O PDF está disponível somente para exames concluídos.", 409);
    }

    const expectedImages = exam.final_report_snapshot.images.length;
    const images = expectedImages ? await getClinicalExamImageGallery(context.accessToken, examId) : [];
    const finalDocument = buildFinalExamDocument(exam, images);
    if (finalDocument.images.length !== expectedImages) throw new Error("Uma das imagens finais do exame não está disponível.");

    const imageAssets = await loadPrivateImages(finalDocument.images);
    const identity = await loadProfessionalDocumentIdentity(finalDocument.executedBy);
    const bytes = await renderFinalExamPdf(finalDocument, imageAssets, identity);
    return new Response(new Uint8Array(bytes), {
      headers: {
        "cache-control": "private, no-store, max-age=0",
        "content-disposition": `${disposition}; filename="${finalDocument.filename}"`,
        "content-length": String(bytes.byteLength),
        "content-type": "application/pdf",
        pragma: "no-cache",
        "x-content-type-options": "nosniff",
      },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Não foi possível gerar o PDF do exame.";
    const forbidden = /acesso não autorizado/i.test(message);
    return pdfError(forbidden ? "Acesso não autorizado." : message, forbidden ? 403 : 400);
  }
}

async function loadPrivateImages(images: Array<{ id: string; mime_type: string; storage_path: string }>) {
  const { serviceRoleKey, url } = getSupabaseAdminConfig();
  const assets: FinalExamPdfImage[] = [];
  let totalBytes = 0;
  for (const image of images) {
    const response = await fetch(`${url}/storage/v1/object/clinical-exam-images/${storagePath(image.storage_path)}`, {
      headers: adminHeaders(serviceRoleKey),
      cache: "no-store",
      signal: AbortSignal.timeout(20_000),
    });
    if (!response.ok) throw new Error("Uma das imagens finais não pôde ser carregada para o PDF.");
    const bytes = new Uint8Array(await response.arrayBuffer());
    totalBytes += bytes.byteLength;
    if (totalBytes > MAX_PDF_IMAGE_BYTES) throw new Error("As imagens deste exame excedem o limite seguro para emissão do PDF.");
    assets.push({ bytes, id: image.id, mimeType: response.headers.get("content-type")?.split(";")[0] || image.mime_type });
  }
  return assets;
}

function storagePath(path: string) {
  return path.split("/").map(encodeURIComponent).join("/");
}

function positiveInteger(value: string | null) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

function pdfError(error: string, status: number) {
  return Response.json({ error }, { status, headers: { "cache-control": "private, no-store", "x-content-type-options": "nosniff" } });
}
