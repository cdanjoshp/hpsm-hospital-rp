import Link from "next/link";
import type { PatientPortalExamDetail, PatientPortalExamStatus } from "../lib/patient-portal";
import { FinalExamDocument } from "./final-exam-document";
import { PatientPortalExamActions } from "./patient-portal-exam-actions";
import { formatPortalDate } from "../lib/patient-portal-format";

const STATUS_LABELS: Record<PatientPortalExamStatus, string> = {
  awaiting_review: "Em finalização",
  completed: "Concluído",
  in_progress: "Em andamento",
  requested: "Solicitado",
};

export function PatientPortalExamDetailView({ data }: { data: PatientPortalExamDetail }) {
  return (
    <div className="patient-portal-exam-detail">
      <Link className="patient-portal-back-link" href="/portal-paciente/exames" prefetch={false}>← Voltar aos exames</Link>
      <section className="patient-portal-detail-card patient-portal-exam-overview" aria-labelledby="patient-portal-exam-title">
        <header>
          <div><p>{data.exam.category}</p><h2 id="patient-portal-exam-title">{data.exam.type}</h2></div>
          <span className="patient-portal-status" data-status={data.exam.status}>{STATUS_LABELS[data.exam.status]}</span>
        </header>
        <dl className="patient-portal-detail-meta">
          <div><dt>Solicitado em</dt><dd>{formatPortalDate(data.exam.occurredAt, true)}</dd></div>
          <div><dt>Conclusão</dt><dd>{data.exam.completedAt ? formatPortalDate(data.exam.completedAt, true) : "Ainda não concluído"}</dd></div>
        </dl>
      </section>

      {data.document ? (
        <>
          <PatientPortalExamActions examId={data.exam.id} />
          <div className="patient-portal-final-document"><FinalExamDocument document={data.document} /></div>
        </>
      ) : (
        <section className="patient-portal-exam-pending" aria-labelledby="patient-portal-exam-pending-title">
          <span aria-hidden="true">i</span>
          <div><h2 id="patient-portal-exam-pending-title">Resultado ainda não disponível</h2><p>O resultado final aparecerá aqui somente após a conclusão e aprovação do exame.</p></div>
        </section>
      )}
    </div>
  );
}
