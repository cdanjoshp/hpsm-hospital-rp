import { getPatientPortalExamDetail } from "../../../../lib/patient-portal";

const RESPONSE_HEADERS = { "cache-control": "private, no-store", vary: "Cookie", "x-content-type-options": "nosniff" };

export async function GET(_request: Request, context: { params: Promise<{ id: string }> }) {
  const examId = await examIdFromParams(context.params);
  if (!examId) return notFound();

  try {
    const detail = await getPatientPortalExamDetail(examId);
    if (!detail) return Response.json({ authenticated: false }, { status: 401, headers: RESPONSE_HEADERS });
    if (detail === "not_found") return notFound();
    return Response.json({
      exam: detail.exam,
      patient: detail.patient,
      result: detail.document ? {
        clinicalContext: detail.document.clinicalContext,
        completedAt: detail.document.completedAt,
        content: detail.document.content,
        exam: { category: detail.document.exam.category_name, name: detail.document.exam.name },
        examCode: detail.document.examCode,
        examDate: detail.document.examDate,
        executedBy: { crmCode: detail.document.executedBy.identity?.crm_code ?? null, name: detail.document.executedBy.name, position: detail.document.executedBy.position, rubricUrl: detail.document.executedBy.identity?.rubric_image_url ?? null, signatureUrl: detail.document.executedBy.identity?.signature_image_url ?? null },
        images: detail.document.images.map((image) => ({
          caption: image.caption,
          mimeType: image.mime_type,
          url: image.signed_url,
        })),
        indication: detail.document.indication,
        reportConfig: detail.document.reportConfig,
        resultData: publicResultData(detail.document.resultData),
      } : null,
    }, { headers: RESPONSE_HEADERS });
  } catch {
    return Response.json({ error: "Não foi possível carregar o exame agora." }, { status: 503, headers: RESPONSE_HEADERS });
  }
}

function publicResultData(value: Record<string, unknown>) {
  const result = { ...value };
  delete result.exam_type_snapshot;
  delete result.report_config_snapshot;
  delete result.template_snapshot;
  return result;
}

async function examIdFromParams(params: Promise<{ id: string }>) {
  const { id } = await params;
  if (!/^\d+$/.test(id)) return null;
  const value = Number(id);
  return Number.isSafeInteger(value) && value > 0 ? value : null;
}

function notFound() {
  return Response.json({ error: "Exame não localizado." }, { status: 404, headers: RESPONSE_HEADERS });
}
