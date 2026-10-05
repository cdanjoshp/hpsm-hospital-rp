import { downloadStorageObject } from "../../../../../../lib/exam-document-storage";
import { getPatientPortalExamImage } from "../../../../../../lib/patient-portal";

const PRIVATE_IMAGE_HEADERS = {
  "cache-control": "private, no-store, max-age=0",
  pragma: "no-cache",
  vary: "Cookie",
  "x-content-type-options": "nosniff",
};

export async function GET(_request: Request, context: { params: Promise<{ id: string; imageId: string }> }) {
  const { id, imageId } = await context.params;
  const examId = /^\d+$/.test(id) ? Number(id) : 0;
  if (!Number.isSafeInteger(examId) || examId < 1) return notFound();

  try {
    const image = await getPatientPortalExamImage(examId, imageId);
    if (!image) return new Response(null, { status: 401, headers: PRIVATE_IMAGE_HEADERS });
    if (image === "not_found" || !["image/jpeg", "image/png", "image/webp"].includes(image.mimeType)) return notFound();
    const stored = await downloadStorageObject("clinical-exam-images", image.storagePath);
    if (!stored.ok || !stored.body) return notFound();
    return new Response(stored.body, { headers: {
      ...PRIVATE_IMAGE_HEADERS,
      "content-length": stored.headers.get("content-length") ?? String(image.fileSize),
      "content-type": image.mimeType,
    } });
  } catch {
    return notFound();
  }
}

function notFound() {
  return new Response(null, { status: 404, headers: PRIVATE_IMAGE_HEADERS });
}
