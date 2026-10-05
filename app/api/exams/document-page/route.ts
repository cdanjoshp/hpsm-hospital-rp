import { ensurePublishedExamPage } from "../../../lib/exam-document-pages";
import { ensureExamDocumentImage, getCompletedClinicalExam } from "../../../lib/exam-document-image-service";
import { getClinicalExamDocumentState } from "../../../lib/exams";
import { getSessionBootstrap } from "../../../lib/session";

export async function POST(request: Request) {
  const session = await getSessionBootstrap();
  if (!session) return failure("Sessão expirada.", 401);
  if (!session.permissionCodes.includes("exams.view")) return failure("Acesso não autorizado.", 403);
  try {
    const body = await request.json() as { examId?: unknown; page?: unknown };
    const examId = Number(body.examId);
    const preparing = (body as { action?: unknown }).action === "prepare";
    const page = Number(body.page);
    if (!Number.isSafeInteger(examId) || examId < 1 || (!preparing && (!Number.isSafeInteger(page) || page < 1))) return failure("Exame ou página inválidos.", 400);
    await getCompletedClinicalExam(session.accessToken, examId);
    let state = await getClinicalExamDocumentState(session.accessToken, examId);
    if (!state.document) state = (await ensureExamDocumentImage(session.accessToken, examId, session.profile.user_id, false)).state;
    if (preparing) return Response.json({ pageCount: state.document ? state.document.pixel_height / 1697 : 0 }, { headers: { "cache-control": "private, no-store" } });
    if (!state.document || page > state.document.pixel_height / 1697) return failure("A página não existe neste laudo.", 404);
    const url = await ensurePublishedExamPage(session.accessToken, examId, state.document.id, page);
    return Response.json({ url }, { headers: { "cache-control": "private, no-store" } });
  } catch (error) {
    return failure(error instanceof Error ? error.message : "Não foi possível publicar esta página.", 503);
  }
}

function failure(error: string, status: number) { return Response.json({ error }, { status, headers: { "cache-control": "private, no-store" } }); }
