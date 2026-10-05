export const CAST_STATUSES = ["in_use", "removed", "cancelled"] as const;
export type ClinicalCastStatus = (typeof CAST_STATUSES)[number];

export const CAST_BODY_REGIONS = [
  { code: "hand", label: "Mão" },
  { code: "wrist", label: "Punho" },
  { code: "forearm", label: "Antebraço" },
  { code: "elbow", label: "Cotovelo" },
  { code: "arm", label: "Braço" },
  { code: "foot", label: "Pé" },
  { code: "ankle", label: "Tornozelo" },
  { code: "leg", label: "Perna" },
  { code: "knee", label: "Joelho" },
  { code: "rib", label: "Costela" },
  { code: "other", label: "Outro" },
] as const;
export type CastBodyRegion = (typeof CAST_BODY_REGIONS)[number]["code"];

export const CAST_REFERENCE_REGIONS = ["arm", "leg", "rib"] as const;
export type CastReferenceRegion = (typeof CAST_REFERENCE_REGIONS)[number];

export const CAST_BODY_MODELS = [
  { code: "male", label: "Masculino" },
  { code: "female", label: "Feminino" },
] as const;
export type CastBodyModel = (typeof CAST_BODY_MODELS)[number]["code"];

export const CAST_LATERALITIES = [
  { code: "right", label: "Direito" },
  { code: "left", label: "Esquerdo" },
  { code: "bilateral", label: "Bilateral" },
  { code: "not_applicable", label: "Não se aplica" },
] as const;
export type CastLaterality = (typeof CAST_LATERALITIES)[number]["code"];

export const CAST_STATUS_LABELS: Record<ClinicalCastStatus, string> = {
  in_use: "Em uso",
  removed: "Retirado",
  cancelled: "Cancelado",
};

export type ClinicalCastListItem = {
  id: number;
  patient_id: number;
  patient_name: string;
  patient_passport: string;
  attendance_id: number | null;
  body_region: CastBodyRegion;
  laterality: CastLaterality;
  status: ClinicalCastStatus;
  applied_at: string;
  expected_removal_at: string;
  removed_at: string | null;
  applied_by: string;
  applied_by_name: string;
  applied_by_position: string | null;
  updated_at: string;
};

export type ClinicalCastPage = {
  items: ClinicalCastListItem[];
  page: number;
  pageSize: number;
  total: number;
};

export type ClinicalCastPatientPage = ClinicalCastPage & {
  castTotal: number;
};

export type ClinicalCastDetail = ClinicalCastListItem & {
  attendance_created_at: string | null;
  attendance_total: number | null;
  attendance_summary: string | null;
  application_notes: string | null;
  body_model_snapshot: CastBodyModel | null;
  reference_body_region_snapshot: CastBodyRegion | null;
  reference_laterality_snapshot: CastLaterality | null;
  game_reference_snapshot: string | null;
  reference_description_snapshot: string | null;
  removed_by: string | null;
  removed_by_name: string | null;
  removed_by_position: string | null;
  removal_notes: string | null;
  cancelled_at: string | null;
  cancelled_by: string | null;
  cancelled_by_name: string | null;
  cancelled_by_position: string | null;
  cancellation_reason: string | null;
  created_at: string;
};

export type ClinicalCastReference = {
  id: number;
  body_model: CastBodyModel;
  body_region: CastReferenceRegion;
  laterality: CastLaterality;
  game_reference: string;
  description: string;
  active: boolean;
  updated_at: string;
  updated_by_name: string | null;
};

export type PatientActiveClinicalCast = {
  id: number;
  patient_id: number;
  body_region: CastBodyRegion;
  laterality: CastLaterality;
  status: "in_use";
  applied_at: string;
  expected_removal_at: string;
  applied_by: string;
  applied_by_name: string;
  applied_by_position: string | null;
};

export type OverdueClinicalCast = PatientActiveClinicalCast & {
  patient_name: string;
  patient_passport: string;
};

export type CastAttendanceOption = {
  id: number;
  created_at: string;
  total: number;
  has_cast_item: boolean;
  summary: string;
};

export function isClinicalCastStatus(value: unknown): value is ClinicalCastStatus {
  return typeof value === "string" && CAST_STATUSES.includes(value as ClinicalCastStatus);
}

export function isCastBodyRegion(value: unknown): value is CastBodyRegion {
  return typeof value === "string" && CAST_BODY_REGIONS.some((item) => item.code === value);
}

export function isCastBodyModel(value: unknown): value is CastBodyModel {
  return typeof value === "string" && CAST_BODY_MODELS.some((item) => item.code === value);
}

export function isCastLaterality(value: unknown): value is CastLaterality {
  return typeof value === "string" && CAST_LATERALITIES.some((item) => item.code === value);
}

export function castBodyRegionLabel(value: CastBodyRegion) {
  return CAST_BODY_REGIONS.find((item) => item.code === value)?.label ?? value;
}

export function castBodyModelLabel(value: CastBodyModel) {
  return CAST_BODY_MODELS.find((item) => item.code === value)?.label ?? value;
}

export function castReferenceRegion(value: CastBodyRegion): CastReferenceRegion | null {
  if (["hand", "wrist", "forearm", "elbow", "arm"].includes(value)) return "arm";
  if (["foot", "ankle", "leg", "knee"].includes(value)) return "leg";
  if (value === "rib") return "rib";
  return null;
}

export function castLateralityLabel(value: CastLaterality) {
  return CAST_LATERALITIES.find((item) => item.code === value)?.label ?? value;
}

export function castLocationLabel(region: CastBodyRegion, laterality: CastLaterality) {
  const regionLabel = castBodyRegionLabel(region);
  if (laterality === "not_applicable") return regionLabel;
  if (laterality === "bilateral") return `${regionLabel} bilateral`;
  const feminine = region === "hand" || region === "leg" || region === "rib";
  if (laterality === "right") return `${regionLabel} ${feminine ? "direita" : "direito"}`;
  return `${regionLabel} ${feminine ? "esquerda" : "esquerdo"}`;
}
