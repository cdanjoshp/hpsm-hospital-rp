import { imagingResultDraft } from "./exam-result-guards";
import type { ExamType, ImagingContrast, ImagingLaterality, ImagingResultData } from "./exams";
import type { CastBodyRegion, CastLaterality } from "./cast-types";

export type ConsultationPrefillContext = {
  anamnesis?: string | null;
  diagnosis?: string | null;
  orientation?: string | null;
  plan?: string | null;
  rationale?: string | null;
  suggestion?: string | null;
};

export type ConsultationCastFormPrefill = {
  applicationNotes: string;
  bodyRegion: CastBodyRegion | "";
  laterality: CastLaterality | "";
};

type RegionRule = {
  castRegion: CastBodyRegion;
  imagingHints: string[];
  terms: string[];
};

const REGION_RULES: RegionRule[] = [
  { castRegion: "wrist", imagingHints: ["punho"], terms: ["punho", "carpo"] },
  { castRegion: "forearm", imagingHints: ["antebraco"], terms: ["antebraco", "radio", "ulna"] },
  { castRegion: "elbow", imagingHints: ["cotovelo"], terms: ["cotovelo", "olecrano"] },
  { castRegion: "arm", imagingHints: ["ombro", "clavicula"], terms: ["ombro", "clavicula", "escapula"] },
  { castRegion: "hand", imagingHints: ["mao"], terms: ["mao", "metacarpo", "metacarpiano", "dedo", "falange"] },
  { castRegion: "arm", imagingHints: ["braco", "umero"], terms: ["braco", "umero", "membro superior"] },
  { castRegion: "ankle", imagingHints: ["tornozelo"], terms: ["tornozelo", "maleolo"] },
  { castRegion: "foot", imagingHints: ["pe"], terms: ["pe", "metatarso", "metatarsiano", "calcaneo"] },
  { castRegion: "knee", imagingHints: ["joelho"], terms: ["joelho", "patela", "rotula"] },
  { castRegion: "leg", imagingHints: ["perna"], terms: ["perna", "tibia", "fibula", "peronio", "membro inferior"] },
  { castRegion: "leg", imagingHints: ["coxa", "femur"], terms: ["coxa", "femur"] },
  { castRegion: "leg", imagingHints: ["quadril", "pelve", "bacia"], terms: ["quadril", "pelve", "bacia"] },
  { castRegion: "rib", imagingHints: ["costela", "torax", "peito"], terms: ["costela", "arco costal", "torax", "peito"] },
  { castRegion: "other", imagingHints: ["coluna cervical", "cervical"], terms: ["coluna cervical", "cervical"] },
  { castRegion: "other", imagingHints: ["coluna toracica", "toracica"], terms: ["coluna toracica", "vertebra toracica"] },
  { castRegion: "other", imagingHints: ["coluna lombar", "lombar"], terms: ["coluna lombar", "lombar"] },
  { castRegion: "other", imagingHints: ["coluna", "vertebra"], terms: ["coluna", "vertebra"] },
  { castRegion: "other", imagingHints: ["cabeca", "cranio", "encefalo", "cerebro"], terms: ["cabeca", "cranio", "encefalo", "cerebro"] },
  { castRegion: "other", imagingHints: ["face", "facial"], terms: ["face", "facial", "mandibula", "maxilar"] },
  { castRegion: "other", imagingHints: ["abdome", "abdominal"], terms: ["abdome", "abdominal"] },
];

const NON_LATERAL_IMAGING_HINTS = ["abdome", "bacia", "cabeca", "cerebro", "coluna", "cranio", "encefalo", "pelve", "torax"];

export function consultationClinicalText(context: ConsultationPrefillContext) {
  return [context.suggestion, context.diagnosis, context.rationale, context.plan, context.orientation, context.anamnesis]
    .map((value) => value?.trim())
    .filter(Boolean)
    .join(". ");
}

export function consultationClinicalSummary(context: ConsultationPrefillContext, maxLength = 2_000) {
  const sections = [
    context.diagnosis?.trim() ? `Diagnóstico: ${context.diagnosis.trim()}${context.rationale?.trim() ? `. ${context.rationale.trim()}` : ""}` : "",
    context.plan?.trim() ? `Conduta e plano: ${context.plan.trim()}` : "",
    !context.diagnosis?.trim() && !context.plan?.trim() && context.anamnesis?.trim() ? context.anamnesis.trim() : "",
  ];
  return sections.filter(Boolean).join("\n\n").slice(0, maxLength);
}

export function consultationImagingPrefill(examType: ExamType | null | undefined, context: ConsultationPrefillContext): ImagingResultData | null {
  const draft = imagingResultDraft(examType);
  if (!draft) return null;
  const normalizedText = normalize(consultationClinicalText(context));
  const region = imagingRegion(draft.template_snapshot.region.options, normalizedText);
  const laterality = draft.template_snapshot.supports_laterality
    ? imagingLaterality(normalizedText, region)
    : "not_applicable";
  const contrast = draft.template_snapshot.supports_contrast ? imagingContrast(normalizedText) : "not_applicable";
  return { ...draft, region, laterality, contrast };
}

export function consultationCastPrefill(context: ConsultationPrefillContext): ConsultationCastFormPrefill {
  const normalizedText = normalize(consultationClinicalText(context));
  const rule = REGION_RULES.find((item) => item.terms.some((term) => hasTerm(normalizedText, term)));
  const bodyRegion = rule && rule.castRegion !== "other" && isCastRegion(rule.castRegion) ? rule.castRegion : "";
  const laterality = bodyRegion === "rib" ? "not_applicable" : castLaterality(normalizedText);
  return {
    applicationNotes: consultationClinicalSummary(context, 1_000),
    bodyRegion,
    laterality,
  };
}

export function consultationHospitalizationPrefill(context: ConsultationPrefillContext) {
  return {
    notes: context.orientation?.trim().slice(0, 2_000) ?? "",
    reason: consultationClinicalSummary(context, 2_000) || context.anamnesis?.trim().slice(0, 2_000) || "",
  };
}

export function consultationFollowUpPrefill(context: ConsultationPrefillContext) {
  return {
    notes: [context.plan?.trim(), context.orientation?.trim()].filter(Boolean).join("\n\n").slice(0, 4_000),
    reason: context.diagnosis?.trim() ? `Retorno: ${context.diagnosis.trim()}`.slice(0, 500) : "Retorno clínico",
  };
}

function imagingRegion(options: string[], normalizedText: string) {
  const explicit = [...options]
    .filter((option) => normalize(option) !== "outra regiao")
    .sort((left, right) => normalize(right).length - normalize(left).length)
    .find((option) => hasTerm(normalizedText, normalize(option)));
  if (explicit) return explicit;
  const rule = REGION_RULES.find((item) => item.terms.some((term) => hasTerm(normalizedText, term)));
  if (!rule) return "";
  const direct = options.find((option) => rule.imagingHints.some((hint) => hasTerm(normalize(option), hint)));
  if (direct) return direct;
  if (["hand", "wrist", "forearm", "elbow", "arm"].includes(rule.castRegion)) {
    return options.find((option) => hasTerm(normalize(option), "membro superior")) ?? "";
  }
  if (["foot", "ankle", "leg", "knee"].includes(rule.castRegion)) {
    return options.find((option) => hasTerm(normalize(option), "membro inferior")) ?? "";
  }
  return "";
}

function imagingLaterality(normalizedText: string, region: string): ImagingLaterality {
  const laterality = detectedLaterality(normalizedText);
  if (laterality) return laterality;
  const normalizedRegion = normalize(region);
  if (normalizedRegion && NON_LATERAL_IMAGING_HINTS.some((hint) => hasTerm(normalizedRegion, hint))) return "not_applicable";
  return "";
}

function castLaterality(normalizedText: string): CastLaterality | "" {
  return detectedLaterality(normalizedText) ?? "";
}

function detectedLaterality(normalizedText: string): "left" | "right" | "bilateral" | null {
  if (hasTerm(normalizedText, "bilateral") || hasTerm(normalizedText, "ambos os lados") || (containsLeft(normalizedText) && containsRight(normalizedText))) return "bilateral";
  if (containsLeft(normalizedText)) return "left";
  if (containsRight(normalizedText)) return "right";
  return null;
}

function imagingContrast(normalizedText: string): ImagingContrast {
  if (hasTerm(normalizedText, "sem contraste") || hasTerm(normalizedText, "nao contrastado") || hasTerm(normalizedText, "nao contrastada")) return "without";
  if (hasTerm(normalizedText, "com contraste") || hasTerm(normalizedText, "contrastado") || hasTerm(normalizedText, "contrastada")) return "with";
  if (hasTerm(normalizedText, "contraste nao se aplica")) return "not_applicable";
  return "";
}

function containsLeft(value: string) { return ["esquerda", "esquerdo", "lado esquerdo"].some((term) => hasTerm(value, term)); }
function containsRight(value: string) { return ["direita", "direito", "lado direito"].some((term) => hasTerm(value, term)); }
function hasTerm(value: string, term: string) { return ` ${value} `.includes(` ${normalize(term)} `); }
function normalize(value: string) { return value.normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim(); }
function isCastRegion(value: string): value is CastBodyRegion { return ["hand", "wrist", "forearm", "elbow", "arm", "foot", "ankle", "leg", "knee", "rib"].includes(value); }
