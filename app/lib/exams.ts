import type { ClinicalExamStatus } from "./exam-status";
import type { DocumentPublicationClientState } from "./document-media-types";
import { authenticatedHeaders } from "./operational-data";
import { normalizePatientSearch } from "./passport";
import { getSupabaseConfig } from "./supabase-server";
export {
  bloodTypeLabel,
  imagingResultDraft,
  isImagingResultData,
  isLabResultData,
  missingRequiredImagingFields,
  missingRequiredLabParameters,
} from "./exam-result-guards";

export type ExamCategory = {
  active: boolean;
  code: string;
  id: number;
  name: string;
  sort_order: number;
};

export type ExamType = ExamCategory & {
  category_id: number;
  description: string | null;
  result_config: LabTemplate | ImagingTemplate | Record<string, unknown>;
};

export type LabFieldType = "number" | "text" | "select" | "observation" | "percent";
export type LabResultFlag = "normal" | "low" | "high" | "positive" | "negative" | "inconclusive";

export type LabTemplateParameter = {
  active: boolean;
  field_type: LabFieldType;
  key: string;
  label: string;
  options: string[];
  reference: string;
  required: boolean;
  sort_order: number;
  unit: string;
};

export type LabTemplate = {
  kind: "laboratory";
  parameters: LabTemplateParameter[];
  schema: "hpsm.lab_template.v1";
  version: number;
};

export type LabTemplateCatalogItem = {
  active: boolean;
  code: string;
  id: number;
  name: string;
  result_config: LabTemplate;
};

export type LabResultParameter = LabTemplateParameter & {
  flag: LabResultFlag | null;
  value: string;
};

export type LabResultData = {
  exam_type_snapshot?: ClinicalExamTypeSnapshot;
  notes: string;
  parameters: LabResultParameter[];
  report_config_snapshot?: ClinicalExamReportConfig;
  schema: "hpsm.lab_result.v1";
  template_snapshot: LabTemplate & { exam_type_code: string; exam_type_name: string };
  template_version: number;
};

export type ImagingLaterality = "" | "left" | "right" | "bilateral" | "not_applicable";
export type ImagingContrast = "" | "with" | "without" | "not_applicable";

export type ImagingTemplate = {
  allows_multiple_images: boolean;
  kind: "imaging";
  region: { options: string[]; required: boolean };
  requires_image: boolean;
  schema: "hpsm.image_template.v1";
  supports_contrast: boolean;
  supports_laterality: boolean;
  version: number;
};

export type ImagingTemplateCatalogItem = {
  active: boolean;
  code: string;
  id: number;
  name: string;
  result_config: ImagingTemplate;
};

export type ImagingResultData = {
  contrast: ImagingContrast;
  exam_type_snapshot?: ClinicalExamTypeSnapshot;
  laterality: ImagingLaterality;
  notes: string;
  other_region: string;
  region: string;
  report_config_snapshot?: ClinicalExamReportConfig;
  schema: "hpsm.image_result.v1";
  template_snapshot: ImagingTemplate & { exam_type_code: string; exam_type_name: string };
  template_version: number;
};

export type ClinicalExamImage = {
  caption: string | null;
  created_at: string;
  exam_id: number;
  file_size: number;
  id: string;
  mime_type: string;
  original_filename: string;
  signed_url?: string;
  sort_order: number;
  source: "upload" | "ai_generated";
  storage_path: string;
  uploaded_by: string;
};

export type ExamAiImageDraft = {
  completed_at: string | null;
  created_at: string;
  file_size: number | null;
  id: string;
  image_count: 1;
  model: "gpt-image-2";
  prompt_version: "exam-image-rp-v1" | "exam-image-rp-v2" | "exam-image-clinical-v3";
  quality: "low";
  signed_url?: string;
  size: "1024x1024";
  status: "requested" | "completed";
  storage_path: string | null;
};

export type ExamProfessional = {
  id: string;
  identity?: ProfessionalIdentityDocument | null;
  name: string;
  position: string | null;
};

export type ProfessionalIdentityDocument = {
  crm_code: string;
  registration_date: string;
  rubric_image_path: string;
  rubric_image_url?: string;
  signature_image_path: string;
  signature_image_url?: string;
};

export type ClinicalExamReportField = {
  label: string;
  required: boolean;
  visible: boolean;
};

export type ClinicalExamReportConfig = {
  fields: {
    conclusion: ClinicalExamReportField;
    findings: ClinicalExamReportField;
    observations: ClinicalExamReportField;
    technique: ClinicalExamReportField;
  };
  schema: "hpsm.report_config.v1";
};

export type ClinicalExamTypeSnapshot = {
  category_code: string;
  category_id: number;
  category_name: string;
  code: string;
  id: number;
  name: string;
  result_config: Record<string, unknown>;
};

export type ClinicalExamReportSnapshot = {
  clinical_context: string | null;
  content: {
    conclusion: string | null;
    findings: string | null;
    observations: string | null;
    result_data: LabResultData | ImagingResultData | { notes?: string; [key: string]: unknown };
    technique: string | null;
  };
  dates: {
    completed_at: string | null;
    requested_at: string;
    started_at: string | null;
    submitted_for_review_at: string | null;
  };
  exam: ClinicalExamTypeSnapshot;
  executed_by: ExamProfessional;
  images: Array<{ caption: string | null; created_at: string; id: string; mime_type: string; original_filename: string; sort_order: number }>;
  indication: string;
  patient: { id: number; name: string; passport: string };
  report_config: ClinicalExamReportConfig;
  requested_by: ExamProfessional;
  reviewed_by: ExamProfessional | null;
  schema: "hpsm.exam_report_snapshot.v1" | "hpsm.exam_report_snapshot.v2";
};

export type ClinicalExamReportVersion = {
  decision: "pending" | "returned" | "approved";
  id: number;
  review_reason: string | null;
  reviewed_at: string | null;
  reviewed_by: ExamProfessional | null;
  submitted_at: string;
  submitted_by: ExamProfessional;
  version_number: number;
};

export type ExamAiLabSuggestion = {
  notes: string;
  parameters: Array<{ flag: LabResultFlag | null; key: string; value: string }>;
  schema: "hpsm.ai.lab_suggestion.v1";
};

export type ExamAiSimpleReportSuggestion = {
  conclusion: string;
  findings: string[];
  rp_note?: string;
  schema: "hpsm.ai.simple_report.v1" | "hpsm.ai.simple_report.v2";
  summary: string;
};

export type ExamAiClinicalReportSuggestion = {
  conclusion: string;
  conduct: string;
  findings: string[];
  schema: "hpsm.ai.clinical_report.v3";
  technique: string;
};

export type ExamAiExamBundleSuggestion = {
  parameters: Array<{
    flag: "normal" | "low" | "high" | "positive" | "negative" | "inconclusive" | null;
    key: string;
    value: string;
  }>;
  report: {
    conclusion: string;
    conduct: string;
    findings: string[];
    technique: string;
  };
  schema: "hpsm.ai.exam_bundle.v4";
};

export type ExamAiReportSuggestion = ExamAiSimpleReportSuggestion | ExamAiClinicalReportSuggestion;

export type ExamAiLegacyReportSuggestion = {
  fields: Partial<Record<keyof ClinicalExamReportConfig["fields"], string>>;
  schema: "hpsm.ai.report_suggestion.v1";
};

export type ExamAiGeneration = {
  applied_at: string | null;
  completed_at: string | null;
  created_at: string;
  generation_type: "generate_lab_results" | "generate_report" | "generate_exam";
  id: string;
  model: "gpt-5.6-luna" | "gpt-6-sol";
  prompt_version: string;
  reasoning_effort: "low" | "medium";
  source_image_generation_id: string | null;
  source_image_id: string | null;
  status: "requested" | "completed" | "applied";
  suggestion_payload: ExamAiExamBundleSuggestion | ExamAiLabSuggestion | ExamAiReportSuggestion | ExamAiLegacyReportSuggestion | null;
};

export type ExamResultOption = { id: string; title: string; summary: string; result_pattern: string; confidence_context: string; severity: string };
export type ExamResultState = {
  status: "not_started" | "analyzing" | "ready" | "selected" | "failed" | "legacy";
  options: ExamResultOption[];
  selected_option_id: string | null;
  selected_snapshot: (ExamResultOption & { source: string; selected_at: string; professional_id: string }) | null;
  analysis_count: number;
  selected_at: string | null;
  visual_study: Record<string, unknown> | null;
  report_generation_id: string | null;
  error_code: string | null;
};

export type ExamReferenceData = {
  categories: ExamCategory[];
  professionals: ExamProfessional[];
  types: ExamType[];
};

export type ClinicalExamListItem = {
  category_id: number;
  category_name: string;
  exam_type_id: number;
  exam_type_name: string;
  id: number;
  patient_id: number;
  patient_name: string;
  patient_passport: string;
  requested_at: string;
  responsible_name: string;
  responsible_position: string | null;
  responsible_professional_id: string;
  status: ClinicalExamStatus;
};

export type ClinicalExamPage = {
  items: ClinicalExamListItem[];
  page: number;
  pageSize: number;
  total: number;
};

export type ClinicalExamDocumentState = {
  document: {
    created_at: string;
    file_size: number;
    id: string;
    pixel_height: number;
    pixel_width: number;
    render_version: "exam-document-png-v2" | "exam-document-png-v3" | "exam-document-png-v4" | "exam-document-png-v5" | "exam-document-png-v6" | "exam-document-png-v7" | "exam-document-png-v8" | "exam-document-png-v9" | "exam-document-png-v10";
  } | null;
  share: {
    created_at: string;
    id: string;
  } | null;
};

export type ClinicalExamDocumentClientState = ClinicalExamDocumentState & DocumentPublicationClientState & {
  downloadUrl: string | null;
  inlineUrl: string | null;
  shareUrl: string | null;
};

export type ClinicalExamHistoryItem = {
  changed_at: string;
  changed_by: ExamProfessional;
  from_status: ClinicalExamStatus | null;
  id: number;
  note: string | null;
  to_status: ClinicalExamStatus;
};

export type ClinicalExamDetail = {
  ai_generations: ExamAiGeneration[];
  result_state?: ExamResultState;
  attendance_id: number | null;
  clinical_context: string | null;
  completed_at: string | null;
  conclusion: string | null;
  correction_reason: string | null;
  created_at: string;
  exam_type: { category_id: number; category_name: string; id: number; name: string };
  final_report_snapshot: ClinicalExamReportSnapshot | null;
  findings: string | null;
  history: ClinicalExamHistoryItem[];
  id: number;
  indication: string;
  patient: { id: number; name: string; passport: string };
  requested_at: string;
  requested_by: ExamProfessional;
  report_config: ClinicalExamReportConfig;
  report_versions: ClinicalExamReportVersion[];
  responsible_professional: ExamProfessional;
  result_data: LabResultData | ImagingResultData | { exam_type_snapshot?: ClinicalExamTypeSnapshot; notes?: string; report_config_snapshot?: ClinicalExamReportConfig; [key: string]: unknown };
  reviewed_by: ExamProfessional | null;
  started_at: string | null;
  status: ClinicalExamStatus;
  submitted_for_review_at: string | null;
  technique: string | null;
  updated_at: string;
};

export type ExamAttendanceOption = {
  created_at: string;
  id: number;
  summary: string;
  total: number;
};

export type ClinicalExamFilters = {
  categoryId?: number;
  dateFrom?: string;
  dateTo?: string;
  examTypeId?: number;
  page?: number;
  pageSize?: number;
  passport?: string;
  search?: string;
  status?: ClinicalExamStatus;
};

export async function getClinicalExamPage(accessToken: string, filters: ClinicalExamFilters = {}): Promise<ClinicalExamPage> {
  const page = positiveInteger(filters.page, 1);
  const pageSize = Math.min(50, positiveInteger(filters.pageSize, 20));
  const payload = await callExamRpc<{ items?: ClinicalExamListItem[]; total?: number }>(accessToken, "clinical_exam_page", {
    p_category_id: positiveOrNull(filters.categoryId),
    p_date_from: filters.dateFrom || null,
    p_date_to: filters.dateTo || null,
    p_exam_type_id: positiveOrNull(filters.examTypeId),
    p_limit: pageSize,
    p_offset: (page - 1) * pageSize,
    p_passport: normalizePatientSearch(clean(filters.passport)),
    p_search: normalizePatientSearch(clean(filters.search)),
    p_status: filters.status ?? null,
  });
  return { items: payload.items ?? [], page, pageSize, total: Number(payload.total ?? 0) };
}

export function getClinicalExamDetail(accessToken: string, examId: number) {
  return callExamRpc<ClinicalExamDetail>(accessToken, "clinical_exam_detail", { p_exam_id: examId });
}

export function getClinicalExamAiGenerations(accessToken: string, examId: number) {
  return callExamRpc<ExamAiGeneration[]>(accessToken, "clinical_exam_ai_generations", { p_exam_id: examId });
}

export function getClinicalExamResultState(accessToken: string, examId: number) {
  return callExamRpc<ExamResultState>(accessToken, "clinical_exam_result_state", { p_exam_id: examId });
}

export function getClinicalExamReferenceData(accessToken: string) {
  return callExamRpc<ExamReferenceData>(accessToken, "clinical_exam_reference_data", {});
}

export function getClinicalExamTemplateCatalog(accessToken: string) {
  return callExamRpc<LabTemplateCatalogItem[]>(accessToken, "clinical_exam_template_catalog", {});
}

export function getClinicalExamImagingTemplateCatalog(accessToken: string) {
  return callExamRpc<ImagingTemplateCatalogItem[]>(accessToken, "clinical_exam_imaging_template_catalog", {});
}

export function getClinicalExamImageGallery(accessToken: string, examId: number) {
  return callExamRpc<ClinicalExamImage[]>(accessToken, "clinical_exam_image_gallery", { p_exam_id: examId });
}

export function getClinicalExamDocumentState(accessToken: string, examId: number) {
  return callExamRpc<ClinicalExamDocumentState>(accessToken, "clinical_exam_document_state", { p_exam_id: examId });
}

export function registerClinicalExamDocument(accessToken: string, payload: {
  documentId: string;
  examId: number;
  fileSize: number;
  pixelHeight: number;
  pixelWidth: number;
  renderVersion: string;
  storagePath: string;
}) {
  return callExamRpc<ClinicalExamDocumentState>(accessToken, "register_clinical_exam_document", {
    p_document_id: payload.documentId,
    p_exam_id: payload.examId,
    p_file_size: payload.fileSize,
    p_pixel_height: payload.pixelHeight,
    p_pixel_width: payload.pixelWidth,
    p_render_version: payload.renderVersion,
    p_storage_path: payload.storagePath,
  });
}

export function createClinicalExamDocumentShare(accessToken: string, examId: number) {
  return callExamRpc<ClinicalExamDocumentState>(accessToken, "create_clinical_exam_document_share", { p_exam_id: examId });
}

export function revokeClinicalExamDocumentShare(accessToken: string, examId: number) {
  return callExamRpc<ClinicalExamDocumentState>(accessToken, "revoke_clinical_exam_document_share", { p_exam_id: examId });
}

export function getClinicalExamAttendanceOptions(accessToken: string, patientId: number) {
  return callExamRpc<ExamAttendanceOption[]>(accessToken, "clinical_exam_attendance_options", { p_patient_id: patientId });
}

export function runClinicalExamMutation<T>(accessToken: string, name: string, payload: Record<string, unknown>) {
  return callExamRpc<T>(accessToken, name, payload);
}

async function callExamRpc<T>(accessToken: string, name: string, payload: Record<string, unknown>): Promise<T> {
  const { url } = getSupabaseConfig();
  let response: Response;
  try {
    response = await fetch(`${url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: authenticatedHeaders(accessToken),
      body: JSON.stringify(payload),
      cache: "no-store",
      signal: AbortSignal.timeout(25_000),
    });
  } catch (error) {
    if (error instanceof DOMException && (error.name === "AbortError" || error.name === "TimeoutError")) {
      throw new Error("O serviço de exames demorou para responder. Tente novamente.");
    }
    throw error;
  }
  if (!response.ok) {
    const problem = await response.json().catch(() => null) as { message?: string } | null;
    throw new Error(problem?.message || "Não foi possível concluir a operação de exames.");
  }
  if (response.status === 204) return undefined as T;
  const text = await response.text();
  return (text ? JSON.parse(text) : undefined) as T;
}

function positiveInteger(value: number | undefined, fallback: number) {
  return Number.isInteger(value) && Number(value) > 0 ? Number(value) : fallback;
}

function positiveOrNull(value: number | undefined) {
  return Number.isInteger(value) && Number(value) > 0 ? Number(value) : null;
}

function clean(value: string | undefined) {
  const result = value?.trim();
  return result ? result.slice(0, 120) : null;
}
