import {
  finalExamBloodType,
  finalExamImagingResult,
  finalExamLaboratoryResult,
  flagLabel,
  formatClinicalDateTime,
  genericStructuredFacts,
  imagingContrastLabel,
  imagingLateralityLabel,
  type FinalExamDocumentModel,
} from "./final-exam-document";
import { formatPatientPassport } from "./passport";
export { FINAL_EXAM_PNG_RENDER_VERSION } from "./exam-document-version";
import {
  assertInstitutionalPng,
  INSTITUTIONAL_DOCUMENT,
  institutionalCardBlocks,
  institutionalFactsBlock,
  institutionalRawBlock,
  institutionalSectionTitle,
  institutionalTextBlocks,
  institutionalPngDimensions,
  isInstitutionalPng,
  renderOfficialInstitutionalDocument,
  svgImage,
  type InstitutionalDocumentBlock,
  type InstitutionalIdentityAssets,
} from "./institutional-document-png";

export const FINAL_EXAM_PNG_MAX_BYTES = INSTITUTIONAL_DOCUMENT.maxBytes;
export type FinalExamPngImage = { bytes: Uint8Array; id: string; mimeType: string };
export type FinalExamPngResult = { bytes: Uint8Array; height: number; width: number };

export function renderFinalExamPng(
  document: FinalExamDocumentModel,
  imageAssets: FinalExamPngImage[] = [],
  identityInput?: InstitutionalIdentityAssets | Array<{ bytes: Uint8Array; personId: string }>,
): Promise<FinalExamPngResult> {
  const legacy = Array.isArray(identityInput) ? identityInput.find((asset) => asset.personId === document.executedBy.id) : null;
  const identity: InstitutionalIdentityAssets = !Array.isArray(identityInput) && identityInput
    ? identityInput
    : legacy
      ? { personId: legacy.personId, rubricBytes: legacy.bytes, signatureBytes: legacy.bytes }
      : { personId: document.executedBy.id, rubricBytes: placeholderPng(), signatureBytes: placeholderPng() };
  const blocks: InstitutionalDocumentBlock[] = [];
  if (document.showIndication && document.indication) blocks.push(...institutionalTextBlocks("Solicitação clínica", document.indication));
  if (document.clinicalContext && (!document.showIndication || document.clinicalContext !== document.indication)) blocks.push(...institutionalTextBlocks("Contexto clínico", document.clinicalContext));
  if (document.betaHcgOutcome) blocks.push(institutionalFactsBlock("Dados da solicitação", [{ label: "Resultado informado", value: document.betaHcgOutcome }, ...(document.gestationalWeeks ? [{ label: "Idade gestacional informada", value: `${document.gestationalWeeks} semanas` }] : [])]));

  const imaging = finalExamImagingResult(document);
  if (imaging) blocks.push(institutionalFactsBlock("Informações do exame", [
    { label: "Região", value: imaging.region === "Outra região" ? imaging.other_region : imaging.region },
    ...(imaging.template_snapshot.supports_laterality ? [{ label: "Lateralidade", value: imagingLateralityLabel(imaging.laterality) }] : []),
    ...(imaging.template_snapshot.supports_contrast ? [{ label: "Contraste", value: imagingContrastLabel(imaging.contrast) }] : []),
  ]));

  const bloodType = finalExamBloodType(document);
  if (bloodType) blocks.push(institutionalFactsBlock("Tipagem sanguínea", [
    { label: "Resultado", value: bloodType },
    { label: "Grupo ABO", value: bloodType.replace(/[+-]$/, "") },
    { label: "Fator Rh", value: bloodType.endsWith("+") ? "Positivo" : "Negativo" },
  ]));

  const laboratory = finalExamLaboratoryResult(document);
  if (laboratory) blocks.push(...institutionalCardBlocks("Resultados laboratoriais", laboratory.parameters.map((parameter) =>
    `${parameter.label}: ${parameter.value || "Não informado"} ${parameter.unit || ""} · Referência: ${parameter.reference || "—"} · ${flagLabel(parameter.flag)}`,
  )));
  const facts = genericStructuredFacts(document.resultData);
  if (facts.length) blocks.push(institutionalFactsBlock("Dados estruturados", facts));

  const assets = new Map(imageAssets.map((asset) => [asset.id, asset]));
  document.images.forEach((image, index) => {
    const asset = assets.get(image.id);
    if (!asset) throw new Error("Uma das imagens finais não pôde ser carregada para o documento.");
    blocks.push(institutionalRawBlock(706, (x, y, width) => `<g>
      ${institutionalSectionTitle(x, y, width, `Imagem ${index + 1}`)}
      <rect x="${x}" y="${y + 43}" width="${width}" height="648" rx="12" fill="#e6edf1" stroke="#aec3d1"/>
      ${svgImage(asset.bytes, x + 18, y + 58, width - 36, 618, asset.mimeType, "meet")}
    </g>`));
    if (image.source !== "ai_generated" && image.caption) blocks.push(...institutionalTextBlocks(`Descrição da imagem ${index + 1}`, image.caption));
  });

  const reportSections = [
    { label: document.reportConfig.fields.technique.label || "Técnica / Método", value: document.content.technique },
    { label: document.reportConfig.fields.findings.label || "Achados", value: document.content.findings },
    { label: document.reportConfig.fields.conclusion.label || "Conclusão", value: document.content.conclusion },
    { label: "Conduta / Próximos passos", value: document.content.observations },
  ];
  for (const section of reportSections) if (section.value) blocks.push(...institutionalTextBlocks(section.label, section.value));
  return renderOfficialInstitutionalDocument({
    attendanceDate: formatClinicalDateTime(document.examDate),
    attendanceLabel: document.exam.category_name,
    documentNumber: document.examCode,
    documentTitle: "Laudo de Exame",
    issuedAt: formatClinicalDateTime(document.issuedAt),
    patient: { name: document.patient.name, passport: formatPatientPassport(document.patient.passport) },
    professional: {
      crmCode: document.executedBy.identity?.crm_code ?? "",
      id: document.executedBy.id,
      name: document.executedBy.name,
      role: document.executedBy.position ?? "Cargo não informado",
    },
    recordNumber: String(document.patient.id),
    subtitle: document.exam.name,
  }, blocks, identity, "documento de exame");
}

export function assertFinalExamPng(result: FinalExamPngResult) { assertInstitutionalPng(result, result.height, "documento de exame"); }
export function isPng(bytes: Uint8Array) { return isInstitutionalPng(bytes); }
export function pngDimensions(bytes: Uint8Array) { return institutionalPngDimensions(bytes); }

function placeholderPng() {
  const binary = atob("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M/wHwAF/gL+W9K6WQAAAABJRU5ErkJggg==");
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}
