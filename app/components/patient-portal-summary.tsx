import Link from "next/link";
import type { ReactNode } from "react";
import { castLocationLabel, isCastBodyRegion, isCastLaterality } from "../lib/cast-types";
import type { PatientPortalSummary } from "../lib/patient-portal";
import { formatPortalDate, formatPortalMoney } from "../lib/patient-portal-format";
import { PatientPortalShell } from "./patient-portal-shell";
import { SidebarIcon } from "./sidebar-icon";

const EXAM_STATUS_LABELS = {
  awaiting_review: "Em finalização",
  completed: "Concluído",
  in_progress: "Em andamento",
  requested: "Solicitado",
} satisfies Record<PatientPortalSummary["recentExams"][number]["status"], string>;

export function PatientPortalSummaryView({ data }: { data: PatientPortalSummary }) {
  const lastAttendance = data.metrics.lastAttendance;

  return (
    <PatientPortalShell
      active="summary"
      description="Veja um resumo dos seus registros no Hospital Santa Marcelina."
      patient={data.patient}
    >
      <section className="patient-portal-metrics" aria-label="Indicadores do paciente">
        <PortalMetric icon="attendances" label="Atendimentos realizados">
          <strong>{data.metrics.totalAttendances}</strong>
          <small>{data.metrics.totalAttendances === 1 ? "registro concluído" : "registros concluídos"}</small>
        </PortalMetric>
        <PortalMetric icon="my-hr" label="Último atendimento">
          <strong>{lastAttendance ? formatPortalDate(lastAttendance.occurredAt) : "Nenhum registro"}</strong>
          <small>{lastAttendance ? `${formatPortalMoney(lastAttendance.total)}${lastAttendance.professionalName ? ` · ${lastAttendance.professionalName}` : ""}` : "Seu primeiro atendimento aparecerá aqui"}</small>
        </PortalMetric>
        <PortalMetric icon="catalog" label="Total gasto no hospital">
          <strong>{formatPortalMoney(data.metrics.lifetimeSpent)}</strong>
          <small>Valores finais dos atendimentos concluídos</small>
        </PortalMetric>
        <PortalMetric href="/portal-paciente/plano-saude" icon="patients" label="Plano de Saúde">
          <strong>{healthPlanTitle(data.healthPlan.status)}</strong>
          <small>{healthPlanDetail(data.healthPlan)}</small>
        </PortalMetric>
      </section>

      <Link className="patient-portal-profile-callout patient-portal-content-card" href="/portal-paciente/meus-dados" prefetch={false}>
        <span className="patient-portal-section-icon"><SidebarIcon name="patients" /></span>
        <span><strong>Meu Cadastro</strong><small>Atualize nome, contatos, nascimento e alergias.</small></span>
        <b aria-hidden="true">→</b>
      </Link>

      <Link className="patient-portal-profile-callout patient-portal-content-card" href="/portal-paciente/consultas" prefetch={false}>
        <span className="patient-portal-section-icon"><SidebarIcon name="attendances" /></span>
        <span><strong>Minhas Consultas</strong><small>Acompanhe agendamentos e veja orientações e prontuários concluídos.</small></span>
        <b aria-hidden="true">→</b>
      </Link>

      <div className="patient-portal-summary-grid">
        <section className="patient-portal-content-card" aria-labelledby="patient-portal-exams-title">
          <header>
            <div>
              <span className="patient-portal-section-icon"><SidebarIcon name="exams" /></span>
              <div><p>Saúde</p><h2 id="patient-portal-exams-title">Exames recentes</h2></div>
            </div>
            {data.recentExams.length ? <span>{data.recentExams.length}</span> : null}
          </header>
          {data.recentExams.length ? (
            <div className="patient-portal-record-list">
              {data.recentExams.map((exam, index) => (
                <article key={exam.id || `${exam.occurredAt}-${exam.type}-${index}`}>
                  <div><strong>{exam.type}</strong><time dateTime={exam.occurredAt}>{formatPortalDate(exam.occurredAt)}</time></div>
                  <div className="patient-portal-record-action">
                    <span className="patient-portal-status" data-status={exam.status}>{EXAM_STATUS_LABELS[exam.status]}</span>
                    {exam.status === "completed" ? <Link href={`/portal-paciente/exames/${exam.id}`} prefetch={false}>Ver resultado</Link> : null}
                  </div>
                </article>
              ))}
            </div>
          ) : <p className="patient-portal-empty">Nenhum exame recente.</p>}
        </section>

        <section className="patient-portal-content-card" aria-labelledby="patient-portal-casts-title">
          <header>
            <div>
              <span className="patient-portal-section-icon"><SidebarIcon name="casts" /></span>
              <div><p>Cuidados atuais</p><h2 id="patient-portal-casts-title">Gessos em uso</h2></div>
            </div>
            {data.activeCasts.length ? <span>{data.activeCasts.length}</span> : null}
          </header>
          {data.activeCasts.length ? (
            <div className="patient-portal-cast-list">
              {data.activeCasts.map((cast, index) => {
                const overdue = new Date(cast.expectedRemovalAt).getTime() < new Date(data.referenceTime).getTime();
                return (
                  <article key={`${cast.appliedAt}-${cast.bodyRegion}-${cast.laterality}-${index}`} data-overdue={overdue}>
                    <strong>{castLocation(cast.bodyRegion, cast.laterality)}</strong>
                    <dl>
                      <div><dt>Aplicado em</dt><dd>{formatPortalDate(cast.appliedAt)}</dd></div>
                      <div><dt>Retirada prevista</dt><dd>{formatPortalDate(cast.expectedRemovalAt)}</dd></div>
                    </dl>
                    {overdue ? <p>Retirada prevista já atingida</p> : null}
                  </article>
                );
              })}
            </div>
          ) : <p className="patient-portal-empty">Nenhum gesso em uso.</p>}
          <Link className="patient-portal-summary-link" href="/portal-paciente/gessos" prefetch={false}>Consultar gessos</Link>
        </section>
      </div>

    </PatientPortalShell>
  );
}

function PortalMetric({ children, href, icon, label }: { children: ReactNode; href?: string; icon: "attendances" | "catalog" | "my-hr" | "patients"; label: string }) {
  const content = (
    <>
      <span className="patient-portal-metric-icon"><SidebarIcon name={icon} /></span>
      <div><p>{label}</p>{children}</div>
    </>
  );
  return href
    ? <Link aria-label={`Consultar ${label}`} className="patient-portal-metric patient-portal-metric-link" href={href} prefetch={false}>{content}</Link>
    : <article className="patient-portal-metric">{content}</article>;
}

function castLocation(region: string, laterality: string) {
  return isCastBodyRegion(region) && isCastLaterality(laterality)
    ? castLocationLabel(region, laterality)
    : "Região informada";
}

function healthPlanTitle(status: PatientPortalSummary["healthPlan"]["status"]) {
  if (status === "active") return "Plano ativo";
  if (status === "expired") return "Plano expirado";
  if (status === "awaiting_confirmation") return "Aguardando confirmação";
  return "Sem plano ativo";
}

function healthPlanDetail(plan: PatientPortalSummary["healthPlan"]) {
  if (plan.status === "active" && plan.validUntil) return `Ativo até ${formatPortalDate(plan.validUntil)}`;
  if (plan.status === "expired" && plan.validUntil) return `Última validade: ${formatPortalDate(plan.validUntil)}`;
  if (plan.status === "awaiting_confirmation") return "Solicitação em análise";
  return "Nenhum Plano de Saúde vigente";
}
