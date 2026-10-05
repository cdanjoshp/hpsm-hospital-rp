import type { ExamType, ImagingResultData, ImagingTemplate, LabResultData } from "./exams";

export function imagingResultDraft(examType: ExamType | null | undefined): ImagingResultData | null {
  const template = examType?.result_config;
  if (!examType || !isImagingTemplate(template)) return null;
  return {
    contrast: template.supports_contrast ? "" : "not_applicable",
    laterality: template.supports_laterality ? "" : "not_applicable",
    notes: "",
    other_region: "",
    region: "",
    schema: "hpsm.image_result.v1",
    template_snapshot: { ...template, exam_type_code: examType.code, exam_type_name: examType.name },
    template_version: template.version,
  };
}

export function isLabResultData(value: unknown): value is LabResultData {
  if (!value || typeof value !== "object") return false;
  const result = value as Partial<LabResultData>;
  return result.schema === "hpsm.lab_result.v1"
    && Number.isInteger(result.template_version)
    && Array.isArray(result.parameters)
    && Boolean(result.template_snapshot && typeof result.template_snapshot === "object");
}

export function isImagingResultData(value: unknown): value is ImagingResultData {
  if (!value || typeof value !== "object") return false;
  const result = value as Partial<ImagingResultData>;
  return result.schema === "hpsm.image_result.v1"
    && Number.isInteger(result.template_version)
    && typeof result.region === "string"
    && Boolean(result.template_snapshot && typeof result.template_snapshot === "object");
}

export function missingRequiredImagingFields(result: ImagingResultData) {
  const missing: string[] = [];
  if (result.template_snapshot.region.required && !result.region.trim()) missing.push("região");
  if (result.region === "Outra região" && !result.other_region.trim()) missing.push("outra região");
  if (result.template_snapshot.supports_laterality && !result.laterality) missing.push("lateralidade");
  if (result.template_snapshot.supports_contrast && !result.contrast) missing.push("uso de contraste");
  return missing;
}

export function missingRequiredLabParameters(result: LabResultData) {
  return result.parameters.filter((parameter) => parameter.active && parameter.required && !parameter.value.trim());
}

export function bloodTypeLabel(result: LabResultData) {
  if (result.template_snapshot.exam_type_code !== "tipagem_sanguinea") return null;
  const abo = result.parameters.find((parameter) => parameter.key === "grupo_abo")?.value;
  const rh = result.parameters.find((parameter) => parameter.key === "fator_rh")?.value;
  if (!abo || !rh) return null;
  return `${abo}${rh === "Positivo" ? "+" : "−"}`;
}

function isImagingTemplate(value: unknown): value is ImagingTemplate {
  if (!value || typeof value !== "object") return false;
  const template = value as Partial<ImagingTemplate>;
  return template.schema === "hpsm.image_template.v1"
    && template.kind === "imaging"
    && Number.isInteger(template.version)
    && Boolean(template.region && Array.isArray(template.region.options))
    && typeof template.region?.required === "boolean"
    && typeof template.supports_laterality === "boolean"
    && typeof template.supports_contrast === "boolean"
    && typeof template.requires_image === "boolean"
    && typeof template.allows_multiple_images === "boolean";
}
