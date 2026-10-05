"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import {
  availabilityLabel,
  externalCallsLabel,
  interestAreaLabel,
  recruitmentStatusLabel,
} from "../lib/recruitment-management";
import type {
  RecruitmentApplication,
  RecruitmentDecision,
  RecruitmentStatus,
} from "../lib/recruitment-management";
import { staffIdentity } from "../lib/staff-identity";
import { HpsmLogo } from "./hpsm-logo";

type DecisionPayload = {
  application?: Pick<
    RecruitmentApplication,
    "id" | "initial_position_id" | "initial_position_name" | "professional_created_at"
    | "professional_passport" | "professional_user_id" | "provisioning_error_code"
    | "provisioning_state" | "review_notes" | "reviewed_at" | "reviewed_by" | "status"
  >;
  decision?: RecruitmentDecision;
  error?: string;
  professional?: {
    createdAt?: string;
    initialPosition?: string;
    name?: string;
    passport?: string;
    userId?: string;
  };
  temporaryPassword?: string;
};

type DecisionModal = {
  applicationId: string;
  decision: "approved" | "rejected";
};

type TemporaryCredential = {
  displayName: string;
  initialPosition: string;
  passport: string;
  password: string;
};

export function RecruitmentManagement({
  canDecide = true,
  initialApplications,
  initialDecisions,
  initialLoadError = "",
  initialSelectedId,
  onDecision,
}: {
  canDecide?: boolean;
  initialApplications: RecruitmentApplication[];
  initialDecisions: RecruitmentDecision[];
  initialLoadError?: string;
  initialSelectedId?: string;
  onDecision?: (applicationId: string) => void;
}) {
  const [applications, setApplications] = useState(initialApplications);
  const [decisions, setDecisions] = useState(initialDecisions);
  const [selectedId, setSelectedId] = useState(
    initialApplications.some((application) => application.id === initialSelectedId)
      ? initialSelectedId!
      : initialApplications[0]?.id ?? "",
  );
  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState("pending");
  const [modal, setModal] = useState<DecisionModal | null>(null);
  const [credential, setCredential] = useState<TemporaryCredential | null>(null);
  const [reason, setReason] = useState("");
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);

  const filteredApplications = useMemo(() => applications.filter((application) => {
    const normalizedQuery = query.trim().toLocaleLowerCase("pt-BR");
    const matchesQuery = !normalizedQuery || `${application.full_name} ${application.passport} ${application.discord_id}`
      .toLocaleLowerCase("pt-BR")
      .includes(normalizedQuery);
    const matchesStatus = statusFilter === "all"
      || (statusFilter === "pending" && isPending(application.status))
      || application.status === statusFilter;
    return matchesQuery && matchesStatus;
  }), [applications, query, statusFilter]);

  const selected = applications.find((application) => application.id === selectedId)
    ?? filteredApplications[0]
    ?? applications[0]
    ?? null;
  const selectedDecisions = selected
    ? decisions.filter((decision) => decision.application_id === selected.id)
    : [];

  const pendingCount = applications.filter((application) => isPending(application.status)).length;
  const approvedCount = applications.filter((application) => application.status === "approved").length;
  const rejectedCount = applications.filter((application) => application.status === "rejected").length;

  function openDecision(decision: "approved" | "rejected") {
    if (!canDecide || !selected || !isPending(selected.status)) return;
    setReason("");
    setError("");
    setModal({ applicationId: selected.id, decision });
  }

  function closeDecision() {
    if (saving) return;
    setModal(null);
    setReason("");
    setError("");
  }

  async function submitDecision() {
    if (!canDecide || !modal || saving) return;
    if (modal.decision === "rejected" && reason.trim().length < 10) {
      setError("Explique o motivo da recusa com pelo menos 10 caracteres.");
      return;
    }

    setSaving(true);
    setError("");
    try {
      const response = await fetch("/api/recruitment/decide", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          applicationId: modal.applicationId,
          decision: modal.decision,
          reason: modal.decision === "rejected" ? reason.trim() : null,
        }),
      });
      const payload = (await response.json()) as DecisionPayload;
      if (!response.ok || !payload.application || !payload.decision) {
        setError(payload.error ?? "Não foi possível registrar a decisão.");
        return;
      }
      if (modal.decision === "approved" && (!payload.temporaryPassword || !payload.professional?.passport)) {
        setError("A candidatura foi processada, mas a credencial temporária não pôde ser confirmada. Consulte Equipe e Acessos.");
        return;
      }

      setApplications((current) => current.map((application) => application.id === payload.application!.id
        ? { ...application, ...payload.application }
        : application));
      setDecisions((current) => [payload.decision!, ...current]);
      if (modal.decision === "approved") {
        setCredential({
          displayName: payload.professional?.name ?? selected?.full_name ?? "novo profissional",
          initialPosition: payload.professional?.initialPosition ?? "Estagiário de Enfermagem",
          passport: payload.professional!.passport!,
          password: payload.temporaryPassword!,
        });
      }
      onDecision?.(modal.applicationId);
      setModal(null);
      setReason("");
    } catch {
      setError("Não foi possível registrar a decisão.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="applications-management">
      {initialLoadError ? <section className="management-card compact-empty" role="alert"><span>!</span><strong>Falha ao carregar o recrutamento</strong><p>{initialLoadError}</p></section> : null}
      <section className="application-metrics" aria-label="Resumo das candidaturas">
        <Metric label="Aguardando decisão" value={pendingCount} tone="pending" />
        <Metric label="Aprovadas" value={approvedCount} tone="approved" />
        <Metric label="Recusadas" value={rejectedCount} tone="rejected" />
      </section>

      <section className="applications-workspace">
        <aside className="management-card applications-inbox">
          <div className="section-title">
            <div><p className="eyebrow">Fila de recrutamento</p><h2>Candidatos</h2></div>
            <span className="count-pill">{applications.length}</span>
          </div>
          <div className="applications-toolbar">
            <label>
              <span>Buscar</span>
              <input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Nome, passaporte ou Discord"
              />
            </label>
            <label>
              <span>Situação</span>
              <select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>
                <option value="pending">Pendentes</option>
                <option value="all">Todas</option>
                <option value="approved">Aprovadas</option>
                <option value="rejected">Recusadas</option>
              </select>
            </label>
          </div>

          <div className="applications-list">
            {filteredApplications.map((application) => (
              <button
                data-selected={selected?.id === application.id}
                key={application.id}
                onClick={() => setSelectedId(application.id)}
                type="button"
              >
                <span className="application-avatar">{initials(application.full_name)}</span>
                <span className="application-list-copy">
                  <strong>{application.full_name}</strong>
                  <small>Passaporte {application.passport} · {formatCompactDate(application.created_at)}</small>
                </span>
                <em data-status={application.status}>{recruitmentStatusLabel(application.status)}</em>
              </button>
            ))}
            {!filteredApplications.length ? (
              <div className="compact-empty">
                <span>◇</span><strong>Nenhuma candidatura encontrada</strong>
                <p>Altere a busca ou o filtro de situação.</p>
              </div>
            ) : null}
          </div>
        </aside>

        <section className="management-card application-file">
          {selected ? (
            <>
              <header className="application-file-header">
                <div>
                  <p className="eyebrow">Ficha {protocol(selected.id)}</p>
                  <h2>{selected.full_name}</h2>
                  <p>Recebida em {formatDateTime(selected.created_at)}</p>
                </div>
                <span className="application-status" data-status={selected.status}>
                  {recruitmentStatusLabel(selected.status)}
                </span>
              </header>

              <section className="application-section">
                <div className="application-section-heading"><span>01</span><div><h3>Identificação e contato</h3><p>Dados informados para o personagem e contato oficial.</p></div></div>
                <div className="application-data-grid">
                  <DataField label="Nome completo" value={selected.full_name} wide />
                  <DataField label="Passaporte" value={selected.passport} />
                  <DataField label="Nascimento" value={`${String(selected.birth_day).padStart(2, "0")}/${String(selected.birth_month).padStart(2, "0")}`} />
                  <DataField label="Telefone na cidade" value={selected.city_phone} />
                  <DataField label="ID real do Discord" value={selected.discord_id} monospaced />
                </div>
              </section>

              <section className="application-section">
                <div className="application-section-heading"><span>02</span><div><h3>Perfil profissional</h3><p>Interesses, experiência e disponibilidade declarados.</p></div></div>
                <div className="application-data-grid">
                  <DataField label="Área de interesse" value={interestAreaLabel(selected.interest_area)} />
                  <DataField label="Chamados externos e direção" value={externalCallsLabel(selected.external_calls)} />
                  <DataField label="Experiência médica anterior" value={selected.prior_experience ? "Sim" : "Não"} />
                  <div className="application-data-field application-data-wide">
                    <small>Períodos disponíveis</small>
                    <div className="application-shifts">{selected.availability.map((shift) => <span key={shift}>{availabilityLabel(shift)}</span>)}</div>
                  </div>
                  <DataField
                    label="Resumo da experiência"
                    value={selected.experience_summary || "Não informado"}
                    wide
                    long
                  />
                  <DataField label="Motivação para fazer parte do HPSM" value={selected.motivation} wide long />
                </div>
              </section>

              <section className="application-section application-decision-history">
                <div className="application-section-heading"><span>03</span><div><h3>Decisão da Diretoria</h3><p>Registro permanente de autoria, data, hora e justificativa.</p></div></div>
                {selectedDecisions.length ? (
                  <div className="decision-history-list">
                    {selectedDecisions.map((decision) => (
                      <article data-decision={decision.decision} key={decision.id}>
                        <span aria-hidden="true">{decision.decision === "approved" ? "✓" : "×"}</span>
                        <div>
                          <strong>{decision.decision === "approved" ? "Candidatura aprovada" : "Candidatura recusada"}</strong>
                          <p>Por {decision.director_name} · {staffIdentity(decision.director_passport, decision.director_position)}</p>
                          {decision.reason ? <blockquote>{decision.reason}</blockquote> : null}
                        </div>
                        <time dateTime={decision.decided_at}>{formatDateTime(decision.decided_at)}</time>
                      </article>
                    ))}
                  </div>
                ) : (
                  <div className="decision-empty"><span>◷</span><p>Esta candidatura ainda não possui decisão registrada.</p></div>
                )}
              </section>

              {selected.professional_user_id && selected.professional_passport ? (
                <section className="application-section application-professional-link">
                  <div className="application-section-heading"><span>04</span><div><h3>Profissional criado</h3><p>Conta vinculada permanentemente à candidatura original.</p></div></div>
                  <div className="application-data-grid">
                    <DataField label="Nome" value={selected.full_name} />
                    <DataField label="Passaporte" value={selected.professional_passport} monospaced />
                    <DataField label="Cargo inicial" value={selected.initial_position_name ?? "Estagiário de Enfermagem"} />
                    <DataField label="Criado em" value={selected.professional_created_at ? formatDateTime(selected.professional_created_at) : "Data não localizada"} />
                  </div>
                  <Link className="application-professional-action" href={`/administrativo/perfis?selecionar=${encodeURIComponent(selected.professional_user_id)}`} prefetch={false}>Ver profissional</Link>
                </section>
              ) : null}

              <footer className="application-decision-bar">
                {!canDecide ? <div className="decision-locked"><span>◇</span><div><strong>Consulta somente leitura</strong><p>Você pode acompanhar a candidatura e o histórico, sem aprovar ou recusar.</p></div></div> : isPending(selected.status) ? (
                  <>
                    <div>
                      <strong>{selected.provisioning_state === "failed" ? "Cadastro não concluído" : selected.provisioning_state === "in_progress" ? "Provisionamento em andamento" : "Decisão definitiva"}</strong>
                      <p>{selected.provisioning_state === "failed" ? "A candidatura foi preservada. A aprovação pode ser tentada novamente com segurança." : "Ao aprovar, a conta profissional será criada automaticamente e vinculada à sua sessão."}</p>
                    </div>
                    <div className="application-decision-actions">
                      <button className="reject-application-button" onClick={() => openDecision("rejected")} type="button">Recusar</button>
                      <button className="approve-application-button" onClick={() => openDecision("approved")} type="button">
                        {selected.provisioning_state === "failed" ? "Tentar cadastro novamente" : selected.provisioning_state === "in_progress" ? "Retomar provisionamento" : "Aprovar candidatura"}
                      </button>
                    </div>
                  </>
                ) : (
                  <div className="decision-locked"><span>✓</span><div><strong>Decisão registrada</strong><p>O resultado acima está protegido contra uma segunda decisão acidental.</p></div></div>
                )}
              </footer>
            </>
          ) : (
            <div className="empty-state"><span>◇</span><strong>Nenhuma candidatura recebida</strong><p>As novas fichas aparecerão aqui para avaliação da Diretoria.</p></div>
          )}
        </section>
      </section>

      {canDecide && modal ? (
        <div className="credential-overlay" role="dialog" aria-modal="true" aria-labelledby="decision-dialog-title">
          <section className="credential-dialog decision-dialog" data-decision={modal.decision}>
            <span className="decision-dialog-symbol" aria-hidden="true">{modal.decision === "approved" ? "✓" : "×"}</span>
            <p className="eyebrow">Decisão da Diretoria</p>
            <h2 id="decision-dialog-title">
              {modal.decision === "approved" ? "Aprovar candidatura?" : "Registrar recusa"}
            </h2>
            {modal.decision === "approved" ? (
              <p>Ao aprovar, o candidato será cadastrado automaticamente como profissional do HPSM no cargo de Estagiário de Enfermagem. A senha temporária será exibida uma única vez.</p>
            ) : (
              <>
                <p>Explique de forma objetiva o motivo da recusa. A justificativa fará parte do histórico interno desta ficha.</p>
                <label className="decision-reason-field">
                  <span>Motivo da recusa *</span>
                  <textarea
                    autoFocus
                    maxLength={2000}
                    onChange={(event) => { setReason(event.target.value); if (error) setError(""); }}
                    placeholder="Descreva o motivo considerado pela Diretoria..."
                    rows={6}
                    value={reason}
                  />
                  <small>{reason.trim().length}/2000 caracteres · mínimo 10</small>
                </label>
              </>
            )}
            {error ? <p className="form-error" role="alert">{error}</p> : null}
            <div className="decision-dialog-actions">
              <button className="secondary-button" disabled={saving} onClick={closeDecision} type="button">Cancelar</button>
              <button
                className={modal.decision === "approved" ? "approve-application-button" : "reject-application-button solid"}
                disabled={saving}
                onClick={submitDecision}
                type="button"
              >
                {saving ? "Registrando…" : modal.decision === "approved" ? "Confirmar aprovação" : "Confirmar recusa"}
              </button>
            </div>
          </section>
        </div>
      ) : null}

      {credential ? (
        <div className="credential-overlay" role="dialog" aria-modal="true" aria-labelledby="recruitment-credential-title">
          <section className="credential-dialog">
            <HpsmLogo className="large-mark" markOnly />
            <p className="eyebrow">Candidatura aprovada · exibição única</p>
            <h2 id="recruitment-credential-title">Profissional criado</h2>
            <p>Entregue os dados diretamente a {credential.displayName}. A senha não poderá ser consultada novamente.</p>
            <div className="credential-field"><span>Passaporte</span><strong>{credential.passport}</strong></div>
            <div className="credential-field"><span>Cargo inicial</span><strong>{credential.initialPosition}</strong></div>
            <div className="credential-field"><span>Senha temporária</span><strong>{credential.password}</strong></div>
            <button className="submit-button" type="button" onClick={() => setCredential(null)}><span>Confirmar que anotei</span><span>✓</span></button>
          </section>
        </div>
      ) : null}
    </div>
  );
}

function Metric({ label, tone, value }: { label: string; tone: string; value: number }) {
  return <article data-tone={tone}><span>{tone === "approved" ? "✓" : tone === "rejected" ? "×" : "◷"}</span><div><strong>{value}</strong><p>{label}</p></div></article>;
}

function DataField({
  label,
  long = false,
  monospaced = false,
  value,
  wide = false,
}: {
  label: string;
  long?: boolean;
  monospaced?: boolean;
  value: string;
  wide?: boolean;
}) {
  return (
    <div className={`application-data-field${wide ? " application-data-wide" : ""}${long ? " application-data-long" : ""}`}>
      <small>{label}</small><strong data-monospaced={monospaced}>{value}</strong>
    </div>
  );
}

function isPending(status: RecruitmentStatus) {
  return ["submitted", "under_review", "interview"].includes(status);
}

function initials(name: string) {
  return name.split(/\s+/).slice(0, 2).map((part) => part[0]?.toUpperCase()).join("");
}

function protocol(id: string) {
  return `HPSM-${id.slice(0, 8).toUpperCase()}`;
}

function formatCompactDate(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value));
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
    timeZone: "America/Sao_Paulo",
  }).format(new Date(value));
}
