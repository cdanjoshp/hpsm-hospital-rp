import type { ReactNode } from "react";
import { EXAM_STATUS_LABELS } from "../lib/exam-status";
import type { ClinicalExamDetail, ClinicalExamReportConfig, ExamProfessional } from "../lib/exams";
import { cleanClinicalText } from "../lib/final-exam-document";
import { isImagingResultData, isLabResultData } from "../lib/exam-result-guards";
import { formatPatientPassport } from "../lib/passport";
import { ImagingResultView } from "./imaging-results";
import { LaboratoryResultView } from "./laboratory-results";

export function ExamReportView({ exam, imageGallery }: { exam: ClinicalExamDetail; imageGallery?: ReactNode }) {
  const finalSnapshot = exam.status === "completed" ? exam.final_report_snapshot : null;
  const patient = finalSnapshot?.patient ?? exam.patient;
  const examType = finalSnapshot?.exam ?? {
    id: exam.exam_type.id,
    code: "",
    name: exam.exam_type.name,
    category_id: exam.exam_type.category_id,
    category_code: "",
    category_name: exam.exam_type.category_name,
    result_config: {},
  };
  const reportConfig = finalSnapshot?.report_config ?? exam.report_config;
  const content = finalSnapshot?.content ?? {
    technique: exam.technique,
    findings: exam.findings,
    conclusion: exam.conclusion,
    observations: typeof exam.result_data?.notes === "string" ? exam.result_data.notes : null,
    result_data: exam.result_data,
  };
  const resultData = content.result_data;
  const laboratoryResult = isLabResultData(resultData) ? resultData : null;
  const imagingResult = isImagingResultData(resultData) ? resultData : null;
  const executedBy = finalSnapshot?.executed_by ?? exam.responsible_professional;
  const reviewedBy = finalSnapshot?.reviewed_by ?? exam.reviewed_by;
  const dates = finalSnapshot?.dates ?? {
    requested_at: exam.requested_at,
    started_at: exam.started_at,
    submitted_for_review_at: exam.submitted_for_review_at,
    completed_at: exam.completed_at,
  };
  const performedAt = dates.completed_at ?? dates.started_at ?? dates.requested_at;
  const aiAssisted = exam.ai_generations?.some((generation) => generation.status === "applied") ?? false;
  const clinicalReportV3Applied = exam.ai_generations?.some((generation) => generation.status === "applied" && generation.suggestion_payload?.schema === "hpsm.ai.clinical_report.v3") ?? false;

  return <article className="exam-report" aria-label={`Laudo do exame ${examType.name}`}>
    <header className="exam-report-header">
      <div><span>Hospital Santa Marcelina</span><h2>Laudo do Exame</h2><p>Documento clínico para revisão e assinatura</p></div>
      <div className="exam-report-badges">{aiAssisted ? <span className="exam-ai-assisted-badge">✦ Assistido por IA</span> : null}<span className="exam-status" data-status={exam.status}>{EXAM_STATUS_LABELS[exam.status]}</span></div>
    </header>

    <dl className="exam-report-identification">
      <div><dt>Paciente</dt><dd>{patient.name}</dd><small>Passaporte {formatPatientPassport(patient.passport)}</small></div>
      <div><dt>Exame</dt><dd>{examType.name}</dd><small>{examType.category_name}</small></div>
      <div><dt>Realizado em</dt><dd>{formatDateTime(performedAt)}</dd><small>Solicitado em {formatDateTime(dates.requested_at)}</small></div>
    </dl>

    {laboratoryResult ? <section className="exam-report-results"><LaboratoryResultView result={laboratoryResult} showNotes={false} /></section> : null}
    {imagingResult ? <section className="exam-report-results"><ImagingResultView result={imagingResult} showNotes={false} /></section> : null}
    {imageGallery ? <section className="exam-report-images">{imageGallery}</section> : null}

    <section className="exam-report-body" aria-label="Conteúdo do laudo">
      <ReportField config={reportConfig} name="technique" value={content.technique} />
      <ReportField config={reportConfig} name="findings" value={content.findings} featured />
      <ReportField config={reportConfig} name="conclusion" value={content.conclusion} featured />
      <ReportField config={reportConfig} label={clinicalReportV3Applied ? "Conduta / Próximos passos" : undefined} name="observations" value={content.observations} optional />
    </section>

    <footer className="exam-report-signatures">
      <Signature label="Executado por" person={executedBy} />
      {reviewedBy ? <Signature label="Laudo revisado e aprovado por" person={reviewedBy} date={dates.completed_at} /> : <div className="exam-report-pending-signature"><span>Revisão clínica</span><strong>Aguardando decisão</strong></div>}
    </footer>
  </article>;
}

function ReportField({ config, featured = false, label, name, optional = false, value }: {
  config: ClinicalExamReportConfig;
  featured?: boolean;
  label?: string;
  name: keyof ClinicalExamReportConfig["fields"];
  optional?: boolean;
  value: string | null;
}) {
  const field = config.fields[name];
  const clinicalValue = cleanClinicalText(value) ?? "";
  if (!field?.visible || (!clinicalValue && optional)) return null;
  return <section className="exam-report-field" data-featured={featured || undefined}>
    <h3>{label ?? field.label}</h3>
    <p>{clinicalValue || (field.required ? "Não informado" : "Sem informação adicional.")}</p>
  </section>;
}

function Signature({ date, label, person }: { date?: string | null; label: string; person: ExamProfessional }) {
  return <div><span>{label}</span><strong>{person.name}</strong><small>{person.position ?? "Cargo não informado"}{date ? ` · ${formatDateTime(date)}` : ""}</small></div>;
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value));
}
