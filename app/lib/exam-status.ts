export const EXAM_STATUSES = ["requested", "in_progress", "awaiting_review", "completed"] as const;

export type ClinicalExamStatus = (typeof EXAM_STATUSES)[number];

export const EXAM_STATUS_LABELS: Record<ClinicalExamStatus, string> = {
  requested: "Solicitado",
  in_progress: "Em execução",
  awaiting_review: "Aguardando revisão",
  completed: "Concluído",
};

export function isClinicalExamStatus(value: unknown): value is ClinicalExamStatus {
  return typeof value === "string" && EXAM_STATUSES.includes(value as ClinicalExamStatus);
}
