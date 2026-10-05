import Link from "next/link";
import type { PatientPortalConsultationDetail } from "../lib/patient-portal";
import { formatPortalDate } from "../lib/patient-portal-format";

const STATUS = {
  scheduled: "Agendada", confirmed: "Confirmada", in_progress: "Em andamento",
  completed: "Concluída", cancelled: "Cancelada", no_show: "Não realizada",
} as const;

function text(value: unknown) { return typeof value === "string" && value.trim() ? value.trim() : null; }

export function PatientPortalConsultationDetailView({ data, prescriptionReady = false }: { data: PatientPortalConsultationDetail; prescriptionReady?: boolean }) {
  const { consultation, snapshot } = data;
  const diagnosis = snapshot?.selected_diagnosis;
  const diagnosisTitle = text(diagnosis?.diagnosis) || text(diagnosis?.title);
  return <div className="patient-portal-attendance-detail">
    <Link className="patient-portal-back-link" href="/portal-paciente/consultas" prefetch={false}>← Voltar às consultas</Link>
    <section className="patient-portal-detail-card" aria-labelledby="patient-consultation-title">
      <header>
        <div><p>Consulta clínica</p><h2 id="patient-consultation-title">{formatPortalDate(consultation.occurredAt, true)}</h2></div>
        <span className="patient-portal-status" data-status={consultation.status}>{STATUS[consultation.status]}</span>
      </header>
      <dl className="patient-portal-detail-meta">
        <div><dt>Profissional</dt><dd>{consultation.professionalName || "Não informado"}{consultation.professionalPosition ? ` · ${consultation.professionalPosition}` : ""}</dd></div>
        <div><dt>Motivo</dt><dd>{consultation.reason || snapshot?.appointment?.reason || "Consulta clínica"}</dd></div>
        {consultation.completedAt ? <div><dt>Concluída em</dt><dd>{formatPortalDate(consultation.completedAt, true)}</dd></div> : null}
      </dl>
    </section>

    {snapshot ? <>
      <section className="patient-portal-detail-card" aria-label="Resultado da consulta">
        <header><div><p>Registro concluído</p><h2>Diagnóstico e plano</h2></div></header>
        {diagnosisTitle ? <p><strong>Diagnóstico:</strong> {diagnosisTitle}</p> : null}
        <p className="patient-portal-consultation-text">{snapshot.final_diagnosis_plan}</p>
      </section>
      <section className="patient-portal-detail-card" aria-label="Orientações ao paciente">
        <header><div><p>Cuidados após a consulta</p><h2>Orientações</h2></div></header>
        <p className="patient-portal-consultation-text">{snapshot.orientation_text}</p>
      </section>
      {snapshot.prescription?.items.length ? <section className="patient-portal-detail-card" aria-label="Prescrição da consulta">
        <header><div><p>Registrado na consulta</p><h2>Prescrição</h2></div></header>
        <ul className="patient-portal-consultation-items">{snapshot.prescription.items.map((item, index) => <li key={index}>
          <strong>{text(item.rp_name_snapshot) || text(item.reference_name_snapshot) || `Item ${index + 1}`}</strong>
          <span>{[text(item.dose_snapshot), text(item.frequency_snapshot), text(item.duration_snapshot), text(item.route_snapshot)].filter(Boolean).join(" · ")}</span>
          {text(item.instructions_snapshot) ? <span>{text(item.instructions_snapshot)}</span> : null}
        </li>)}</ul>
      </section> : null}
      {snapshot.exams.length ? <section className="patient-portal-detail-card" aria-label="Exames vinculados à consulta">
        <header><div><p>Solicitados nesta consulta</p><h2>Exames</h2></div></header>
        <ul className="patient-portal-consultation-items">{snapshot.exams.map((exam, index) => {
          const id = Number(exam.id);
          return <li key={index}><strong>{text(exam.type) || `Exame ${index + 1}`}</strong>
            {Number.isSafeInteger(id) && id > 0 ? <Link href={`/portal-paciente/exames/${id}`} prefetch={false}>Ver exame</Link> : null}
          </li>;
        })}</ul>
      </section> : null}
      <a className="patient-portal-consultation-download" href={`/api/patient-portal/consultations/${consultation.kind}/${consultation.id}/document`}>Baixar prontuário da consulta</a>
      {prescriptionReady ? <a className="patient-portal-consultation-download" href={`/api/patient-portal/consultations/${consultation.kind}/${consultation.id}/prescription`}>Baixar Receita</a> : null}
    </> : <section className="patient-portal-exam-pending"><span aria-hidden="true">i</span><div>
      <h2>Prontuário ainda não disponível</h2><p>As informações clínicas aparecerão aqui após a conclusão da consulta.</p>
    </div></section>}
  </div>;
}
