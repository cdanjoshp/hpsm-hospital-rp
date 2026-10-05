import { bloodTypeLabel, isImagingResultData, isLabResultData } from "./exam-result-guards";
import type {
  ClinicalExamDetail,
  ClinicalExamImage,
  ClinicalExamReportConfig,
  ClinicalExamTypeSnapshot,
  ExamProfessional,
  ImagingResultData,
  LabResultData,
} from "./exams";

export type FinalExamDocumentImage = Pick<ClinicalExamImage,
  "caption" | "created_at" | "id" | "mime_type" | "original_filename" | "signed_url" | "sort_order" | "source" | "storage_path"
>;

export type FinalExamDocumentModel = {
  clinicalContext: string | null;
  completedAt: string;
  content: {
    conclusion: string | null;
    findings: string | null;
    observations: string | null;
    technique: string | null;
  };
  exam: ClinicalExamTypeSnapshot;
  examCode: string;
  examDate: string;
  examId: number;
  executedBy: ExamProfessional;
  filename: string;
  betaHcgOutcome: "Positivo" | "Negativo" | null;
  gestationalWeeks: number | null;
  images: FinalExamDocumentImage[];
  indication: string;
  issuedAt: string;
  patient: { id: number; name: string; passport: string };
  reportConfig: ClinicalExamReportConfig;
  resultData: ClinicalExamDetail["result_data"];
  reviewedBy: ExamProfessional;
  showIndication: boolean;
};

export function buildFinalExamDocument(
  exam: ClinicalExamDetail,
  images: FinalExamDocumentImage[] = [],
  issuedAt = new Date().toISOString(),
): FinalExamDocumentModel {
  if (exam.status !== "completed") throw new Error("O documento final está disponível somente para exames concluídos.");

  const snapshot = exam.final_report_snapshot;
  const patient = snapshot?.patient ?? exam.patient;
  const examType = snapshot?.exam ?? fallbackExamType(exam);
  const content = snapshot?.content ?? {
    conclusion: exam.conclusion,
    findings: exam.findings,
    observations: typeof exam.result_data?.notes === "string" ? exam.result_data.notes : null,
    result_data: exam.result_data,
    technique: exam.technique,
  };
  const dates = snapshot?.dates ?? {
    completed_at: exam.completed_at,
    requested_at: exam.requested_at,
    started_at: exam.started_at,
    submitted_for_review_at: exam.submitted_for_review_at,
  };
  const reviewedBy = snapshot?.reviewed_by ?? exam.reviewed_by;
  const completedAt = dates.completed_at ?? exam.completed_at;
  if (!reviewedBy || !completedAt) throw new Error("O exame concluído não possui a revisão final necessária.");

  const orderedImages = orderSnapshotImages(snapshot?.images ?? [], images);
  const storedIndication = snapshot?.indication ?? exam.indication;
  const outcomeMatch = examType.code === "beta_hcg" ? storedIndication.match(/\nResultado esperado do Beta HCG: (Positivo|Negativo)\.(?:\nIdade gestacional informada pelo médico: [0-9]{1,2} semanas\.)?$/) : null;
  const weekMatch = examType.code === "beta_hcg" ? storedIndication.match(/\nIdade gestacional informada pelo médico: ([0-9]{1,2}) semanas\.$/) : null;
  const gestationalWeeks = weekMatch && Number(weekMatch[1]) >= 3 && Number(weekMatch[1]) <= 40 ? Number(weekMatch[1]) : null;
  const betaHcgOutcome = outcomeMatch ? outcomeMatch[1] as "Positivo" | "Negativo" : gestationalWeeks ? "Positivo" : null;
  const examCode = formatExamCode(exam.id);
  return {
    clinicalContext: cleanClinicalText(snapshot?.clinical_context ?? exam.clinical_context),
    completedAt,
    content: {
      conclusion: cleanClinicalText(content.conclusion),
      findings: cleanClinicalText(content.findings),
      observations: cleanClinicalText(content.observations),
      technique: cleanClinicalText(content.technique),
    },
    exam: examType,
    examCode,
    examDate: dates.started_at ?? dates.requested_at,
    examId: exam.id,
    // O documento oficial identifica somente o médico solicitante como responsável final.
    executedBy: snapshot?.requested_by ?? exam.requested_by,
    filename: finalExamFilename(exam.id, examType.name),
    betaHcgOutcome,
    gestationalWeeks,
    images: orderedImages,
    indication: cleanClinicalText(outcomeMatch ? storedIndication.slice(0, outcomeMatch.index) : gestationalWeeks ? storedIndication.slice(0, weekMatch!.index) : storedIndication) ?? "",
    issuedAt,
    patient,
    reportConfig: snapshot?.report_config ?? exam.report_config,
    resultData: content.result_data ?? exam.result_data,
    reviewedBy,
    showIndication: snapshot?.schema !== "hpsm.exam_report_snapshot.v2",
  };
}

export function finalExamFilename(examId: number, examTypeName: string) {
  return `${finalExamBaseFilename(examId, examTypeName)}.pdf`;
}

export function finalExamPngFilename(examId: number, examTypeName: string) {
  return `${finalExamBaseFilename(examId, examTypeName)}.png`;
}

function finalExamBaseFilename(examId: number, examTypeName: string) {
  const safeType = examTypeName
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^A-Za-z0-9-]+/g, "-")
    .replace(/^-+|-+$/g, "") || "Exame";
  return `HPSM_${formatExamCode(examId)}_${safeType}`;
}

export function formatExamCode(examId: number) {
  return `EX-${String(examId).padStart(6, "0")}`;
}

export function formatClinicalDate(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    timeZone: "America/Sao_Paulo",
    year: "numeric",
  }).format(new Date(value));
}

export function formatClinicalDateTime(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    hour: "2-digit",
    hour12: false,
    minute: "2-digit",
    month: "2-digit",
    timeZone: "America/Sao_Paulo",
    year: "numeric",
  }).format(new Date(value));
}

export function finalExamLaboratoryResult(model: FinalExamDocumentModel): LabResultData | null {
  return isLabResultData(model.resultData) ? model.resultData : null;
}

export function finalExamImagingResult(model: FinalExamDocumentModel): ImagingResultData | null {
  return isImagingResultData(model.resultData) ? model.resultData : null;
}

export function finalExamBloodType(model: FinalExamDocumentModel) {
  const result = finalExamLaboratoryResult(model);
  return result ? bloodTypeLabel(result) : null;
}

export function flagLabel(flag: string | null) {
  const labels: Record<string, string> = {
    high: "Alto",
    inconclusive: "Inconclusivo",
    low: "Baixo",
    negative: "Negativo",
    normal: "Normal",
    positive: "Positivo",
  };
  return flag ? labels[flag] ?? flag : "Sem classificação";
}

export function imagingLateralityLabel(value: string) {
  return ({ bilateral: "Bilateral", left: "Esquerda", not_applicable: "Não se aplica", right: "Direita" } as Record<string, string>)[value] ?? "Não informada";
}

export function imagingContrastLabel(value: string) {
  return ({ not_applicable: "Não se aplica", with: "Com contraste", without: "Sem contraste" } as Record<string, string>)[value] ?? "Não informado";
}

export function genericStructuredFacts(resultData: ClinicalExamDetail["result_data"]) {
  if (isLabResultData(resultData) || isImagingResultData(resultData)) return [];
  const labelByKey: Record<string, string> = {
    frequency: "Frequência",
    heart_rate: "Frequência cardíaca",
    material: "Material / amostra",
    method: "Método",
    rate: "Frequência",
    rhythm: "Ritmo",
    sample: "Material / amostra",
    specimen: "Material / amostra",
  };
  return Object.entries(resultData)
    .filter(([key, value]) => key in labelByKey && (typeof value === "string" || typeof value === "number") && String(value).trim())
    .map(([key, value]) => ({ label: labelByKey[key], value: cleanClinicalText(String(value)) ?? "" }));
}

export function cleanClinicalText(value: string | null | undefined) {
  if (!value) return null;
  const cleaned = value
    .replace(/\b(?:para|no|na|do|da|de|em)\s+(?:(?:o|a)\s+)?(?:gta\s*[-–—]?\s*rp|rp|role[\s-]*play|fict[ií]ci[oa]s?|simula(?:ç(?:ão|ões)|c(?:ao|oes))|simulad[oa]s?|personage(?:m|ns)|video\s*game|videogame|game)\b/giu, "")
    .replace(/\b(?:gta\s*[-–—]?\s*rp|rp|role[\s-]*play|fict[ií]ci[oa]s?|simula(?:ç(?:ão|ões)|c(?:ao|oes))|simulad[oa]s?|personage(?:m|ns)|video\s*game|videogame|game)\b/giu, "")
    .replace(/\s{2,}/g, " ")
    .replace(/\s+([.,;:!?])/g, "$1")
    .trim();
  return cleaned || null;
}

function fallbackExamType(exam: ClinicalExamDetail): ClinicalExamTypeSnapshot {
  const snapshot = exam.result_data?.exam_type_snapshot;
  if (snapshot) return snapshot;
  return {
    category_code: "",
    category_id: exam.exam_type.category_id,
    category_name: exam.exam_type.category_name,
    code: "",
    id: exam.exam_type.id,
    name: exam.exam_type.name,
    result_config: {},
  };
}

function orderSnapshotImages(snapshotImages: Array<{ id: string; sort_order: number }>, images: FinalExamDocumentImage[]) {
  if (!snapshotImages.length) return [...images].sort((left, right) => left.sort_order - right.sort_order || left.created_at.localeCompare(right.created_at));
  const byId = new Map(images.map((image) => [image.id, image]));
  return snapshotImages
    .slice()
    .sort((left, right) => left.sort_order - right.sort_order)
    .map((snapshotImage) => byId.get(snapshotImage.id))
    .filter((image): image is FinalExamDocumentImage => Boolean(image));
}
