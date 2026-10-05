import type { ComplementaryAction, ConsultationDiagnosis } from "./consultations";

const CAST_EVIDENCE = /\b(fratura|fraturad[ao]|gesso|engessad[ao]|imobiliza(?:r|cao|do|da)?|tala|ortese)\b/;
const CAST_NEGATION = /\b(?:sem (?:evidencia|sinais|confirmacao|diagnostico) de fratura|fratura (?:foi )?descartad[ao]|sem (?:necessidade|indicacao) de (?:gesso|imobilizacao|tala|ortese)|nao (?:necessita|requer|indica|indicado|sera indicado) (?:de )?(?:gesso|imobilizacao|tala|ortese))\b/;
const HOSPITALIZATION_EVIDENCE = /\b(internacao|internar|hospitalizacao|hospitalizar|admissao hospitalar|ocupacao de leito|leito hospitalar|uti)\b/;
const HOSPITALIZATION_NEGATION = /\b(?:sem (?:necessidade|indicacao) de (?:internacao|hospitalizacao|leito)|nao (?:necessita|requer|indica|indicado|sera indicado) (?:de )?(?:internacao|hospitalizacao|leito)|(?:internacao|hospitalizacao) (?:foi )?descartad[ao])\b/;

export function resolveConsultationComplementaryAction(
  diagnosis: ConsultationDiagnosis | null,
  requestedAction: ComplementaryAction,
  finalPlan: string,
): ComplementaryAction {
  if (requestedAction !== "NONE") return requestedAction;
  if (!diagnosis || diagnosis.complementary_action_dismissed) return "NONE";

  const clinicalText = normalize([
    diagnosis.diagnosis,
    diagnosis.title,
    diagnosis.reasoning_summary,
    diagnosis.rationale,
    diagnosis.final_plan,
    finalPlan,
    diagnosis.orientation,
  ].filter(Boolean).join(". "));

  if (HOSPITALIZATION_EVIDENCE.test(clinicalText) && !HOSPITALIZATION_NEGATION.test(clinicalText)) return "HOSPITALIZATION";
  if (CAST_EVIDENCE.test(clinicalText) && !CAST_NEGATION.test(clinicalText)) return "CAST";
  return "NONE";
}

function normalize(value: string) {
  return value.normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}
