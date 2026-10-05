"use client";

import { useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import type { StaffPosition } from "../lib/access";
import { positionName } from "../lib/staff-position";
import type { FunctionalProfileData, FunctionalTimelineEvent } from "../lib/functional-profile";
import type { HrProfile } from "../lib/hr";
import { staffIdentity } from "../lib/staff-identity";

type ProfileSection = "access" | "career" | "identity" | "overview" | "rh" | "timeline";
type IdentityAction = "correct-crm" | "regenerate" | "reprocess";

export function FunctionalProfile({ canManageIdentity, initialSelectedId, positions, profiles }: { canManageIdentity: boolean; initialSelectedId?: string; positions: StaffPosition[]; profiles: HrProfile[] }) {
  const selectableProfiles = useMemo(
    () => [...profiles].sort((a, b) => a.display_name.localeCompare(b.display_name, "pt-BR")),
    [profiles],
  );
  const [selectedId, setSelectedId] = useState(
    selectableProfiles.find((profile) => profile.user_id === initialSelectedId)?.user_id
      ?? selectableProfiles.find((profile) => profile.status === "active")?.user_id
      ?? selectableProfiles[0]?.user_id
      ?? "",
  );
  const [data, setData] = useState<FunctionalProfileData | null>(null);
  const [error, setError] = useState("");
  const [section, setSection] = useState<ProfileSection>("overview");
  const [visibleTimeline, setVisibleTimeline] = useState(18);
  const [reloadIndex, setReloadIndex] = useState(0);
  const [identityAction, setIdentityAction] = useState<IdentityAction | null>(null);
  const [identityReason, setIdentityReason] = useState("");
  const [identityRegistrationDate, setIdentityRegistrationDate] = useState("");
  const [identityBusy, setIdentityBusy] = useState(false);
  const [identityMessage, setIdentityMessage] = useState("");
  const identityBusyRef = useRef(false);
  const identityDialogRef = useRef<HTMLElement>(null);
  const identityReturnFocusRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (!selectedId) return;
    const controller = new AbortController();
    void fetch(`/api/hr/profile?employeeId=${encodeURIComponent(selectedId)}`, { signal: controller.signal })
      .then(async (response) => {
        const payload = (await response.json()) as FunctionalProfileData & { error?: string };
        if (!response.ok) throw new Error(payload.error ?? "Não foi possível carregar o perfil funcional.");
        setData(payload);
      })
      .catch((requestError: unknown) => {
        if (requestError instanceof DOMException && requestError.name === "AbortError") return;
        setError(requestError instanceof Error ? requestError.message : "Não foi possível carregar o perfil funcional.");
      });
    return () => controller.abort();
  }, [reloadIndex, selectedId]);

  useEffect(() => {
    if (!identityAction) return;
    const dialog = identityDialogRef.current;
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !identityBusyRef.current) {
        event.preventDefault();
        setIdentityAction(null);
        return;
      }
      if (event.key !== "Tab" || !dialog) return;
      const focusable = [...dialog.querySelectorAll<HTMLElement>('button:not([disabled]), input:not([disabled]), textarea:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])')];
      if (!focusable.length) return;
      const first = focusable[0];
      const last = focusable.at(-1)!;
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      identityReturnFocusRef.current?.focus();
    };
  }, [identityAction]);

  const loading = Boolean(selectedId && !error && data?.profile.userId !== selectedId);

  function selectProfile(userId: string) {
    setSelectedId(userId);
    setData(null);
    setError("");
    setVisibleTimeline(18);
    setIdentityMessage("");
  }

  function openIdentityAction(action: IdentityAction) {
    identityReturnFocusRef.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    setIdentityAction(action);
    setIdentityReason("");
    setIdentityRegistrationDate(data?.identity?.registrationDate ?? "");
    setIdentityMessage("");
  }

  async function submitIdentityAction(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!identityAction || !data) return;
    identityBusyRef.current = true;
    setIdentityBusy(true);
    setIdentityMessage("");
    try {
      const response = await fetch("/api/professional-identity", {
        body: JSON.stringify({
          action: identityAction,
          reason: identityReason,
          registrationDate: identityAction === "correct-crm" ? identityRegistrationDate : undefined,
          targetUserId: data.profile.userId,
        }),
        headers: { "content-type": "application/json" },
        method: "POST",
      });
      const payload = await response.json() as { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível atualizar a identidade.");
      setIdentityAction(null);
      setData(null);
      setReloadIndex((value) => value + 1);
      setIdentityMessage(identityAction === "correct-crm" ? "CRM corrigido e auditado." : "Identidade profissional atualizada e auditada.");
    } catch (cause) {
      setIdentityMessage(cause instanceof Error ? cause.message : "Não foi possível atualizar a identidade.");
    } finally {
      identityBusyRef.current = false;
      setIdentityBusy(false);
    }
  }

  return (
    <div className="functional-profile hr-tab-panel">
      <section className="management-card functional-profile-selector">
        <div><p className="eyebrow">Trajetória administrativa</p><h2>Perfil funcional do colaborador</h2><p>Consulte carreira, formação, RH, acessos e acontecimentos reais sem substituir a auditoria técnica.</p></div>
        <label>Colaborador<select value={selectedId} onChange={(event) => selectProfile(event.target.value)}><option value="" disabled>Selecione</option>{selectableProfiles.map((profile) => <option key={profile.user_id} value={profile.user_id}>{profile.display_name} · {staffIdentity(profile.passport, positionName(profile, positions))}</option>)}</select></label>
      </section>

      {loading ? <section className="management-card functional-profile-loading" role="status"><span>◷</span><div><strong>Montando o perfil funcional…</strong><p>Os históricos estão sendo carregados somente para o colaborador selecionado.</p></div></section> : null}
      {error ? <p className="form-error hr-global-message" role="alert">{error}</p> : null}
      {!loading && !error && !data ? <section className="management-card functional-profile-loading"><span>◇</span><div><strong>Nenhum perfil selecionado</strong><p>Escolha um colaborador para consultar sua trajetória.</p></div></section> : null}

      {data ? <>
        <section className="management-card functional-profile-hero">
          <header>
            <div className="functional-profile-avatar" aria-hidden="true">{initials(data.profile.displayName)}</div>
            <div><p className="eyebrow">Cadastro funcional</p><h2>{data.profile.displayName}</h2><span>{staffIdentity(data.profile.passport, data.profile.currentPosition)}</span></div>
            <em data-status={data.profile.status}>{profileStatus(data.profile.status)}</em>
          </header>
          <div className="functional-profile-metrics">
            <ProfileMetric label="Horas registradas" value={formatMinutes(data.summary.workedMinutes)} />
            <ProfileMetric label="Atend./vendas" value={String(data.summary.attendanceCount)} />
            <ProfileMetric label="Valor registrado" value={formatMoney(data.summary.attendanceValue)} />
            <ProfileMetric label="Cursos concluídos" value={String(data.summary.completedCourses)} />
            <ProfileMetric label="ADVs no ciclo" value={`${data.summary.activeWarningsInCycle}/3`} tone={data.summary.activeWarningsInCycle ? "warning" : undefined} />
            <ProfileMetric label="Acessos temporários" value={String(data.summary.activeTemporaryPermissions)} />
          </div>
        </section>

        <nav className="functional-profile-tabs" aria-label="Seções do perfil funcional">
          {([['overview', 'Visão geral'], ['identity', 'Identidade profissional'], ['career', 'Carreira e formação'], ['rh', 'RH e disciplina'], ['access', 'Acessos'], ['timeline', 'Timeline']] as Array<[ProfileSection, string]>).map(([value, label]) => <button type="button" key={value} data-active={section === value} onClick={() => setSection(value)}>{label}</button>)}
        </nav>

        {section === "identity" ? <section className="management-card professional-identity-panel">
          <div className="section-title"><div><p className="eyebrow">Identidade institucional</p><h3>CRM interno, assinatura e rubrica</h3></div>{data.identity ? <span className="identity-status" data-status={data.identity.status}>{identityStatus(data.identity.status)}</span> : null}</div>
          {identityMessage ? <p className="identity-action-message" role="status">{identityMessage}</p> : null}
          {data.identity ? <>
            <dl className="professional-identity-facts">
              <div><dt>CRM interno</dt><dd>{data.identity.crmCode}</dd></div>
              <div><dt>Data de registro</dt><dd>{formatDateOnly(data.identity.registrationDate)}</dd></div>
              <div><dt>Versão ativa</dt><dd>{data.identity.generationVersion || "Pendente"}</dd></div>
              <div><dt>Proteção</dt><dd>{data.identity.identityLocked ? "Bloqueada para edição" : "Liberada para reprocessamento"}</dd></div>
            </dl>
            <div className="professional-identity-assets">
              <article><span>Assinatura principal</span>{data.identity.signatureUrl ? <>
                {/* eslint-disable-next-line @next/next/no-img-element -- ativo privado com URL assinada temporária. */}
                <img alt={`Assinatura de ${data.profile.displayName}`} src={data.identity.signatureUrl} />
              </> : <IdentityAssetPending />}</article>
              <article data-compact="true"><span>Rubrica</span>{data.identity.rubricUrl ? <>
                {/* eslint-disable-next-line @next/next/no-img-element -- ativo privado com URL assinada temporária. */}
                <img alt={`Rubrica de ${data.profile.displayName}`} src={data.identity.rubricUrl} />
              </> : <IdentityAssetPending />}</article>
            </div>
            <dl className="professional-identity-history">
              <div><dt>Geração inicial</dt><dd>{data.identity.generatedAt ? `${formatDateTime(data.identity.generatedAt)} · ${data.identity.generatedByName ?? "Sistema"}` : "Ainda não concluída"}</dd></div>
              <div><dt>Última regeneração</dt><dd>{data.identity.regeneratedAt ? `${formatDateTime(data.identity.regeneratedAt)} · ${data.identity.regeneratedByName ?? "Diretor Geral"}` : "Nenhuma regeneração"}</dd></div>
              {data.identity.regenerationReason ? <div><dt>Motivo registrado</dt><dd>{data.identity.regenerationReason}</dd></div> : null}
            </dl>
            {canManageIdentity ? <div className="professional-identity-actions">
              <button type="button" disabled={data.identity.status !== "active"} onClick={() => openIdentityAction("regenerate")}>Regenerar assinatura e rubrica</button>
              <button type="button" onClick={() => openIdentityAction("correct-crm")}>Corrigir CRM</button>
              <button type="button" onClick={() => openIdentityAction("reprocess")}>Desbloquear e reprocessar</button>
            </div> : <p className="functional-profile-note">A identidade é somente leitura. Correções e regenerações são exclusivas do Diretor Geral.</p>}
          </> : <div className="compact-empty"><span>◇</span><strong>Identidade indisponível</strong><p>O cadastro institucional ainda não foi provisionado.</p></div>}
        </section> : null}

        {section === "overview" ? <div className="functional-profile-overview">
          <section className="management-card functional-profile-facts">
            <div className="section-title"><div><p className="eyebrow">Situação atual</p><h3>Dados funcionais</h3></div></div>
            <dl>
              <div><dt>Admissão</dt><dd>{formatDate(data.profile.admittedAt)}</dd></div>
              <div><dt>Cargo atual</dt><dd>{data.profile.currentPosition}{data.profile.currentPositionLevel ? ` · nível ${data.profile.currentPositionLevel}` : ""}</dd></div>
              <div><dt>No cargo desde</dt><dd>{formatDate(data.profile.currentPositionSince)} · {elapsedLabel(data.profile.currentPositionSince)}</dd></div>
              <div><dt>Situação</dt><dd>{profileStatus(data.profile.status)}</dd></div>
            </dl>
          </section>
          <section className="management-card functional-profile-facts">
            <div className="section-title"><div><p className="eyebrow">Resumo do histórico</p><h3>Registros vinculados</h3></div></div>
            <dl>
              <div><dt>Cursos</dt><dd>{data.summary.completedCourses} concluído(s) · {data.summary.pendingCourses} pendente(s)</dd></div>
              <div><dt>Afastamentos</dt><dd>{data.absences.length} registro(s)</dd></div>
              <div><dt>Justificativas</dt><dd>{data.justifications.length} registro(s)</dd></div>
            </dl>
          </section>
          <section className="management-card functional-profile-recent">
            <div className="section-title"><div><p className="eyebrow">Últimos acontecimentos</p><h3>Trajetória recente</h3></div><button type="button" className="table-action" onClick={() => setSection("timeline")}>Ver timeline completa</button></div>
            <Timeline events={data.timeline.slice(0, 6)} />
          </section>
        </div> : null}

        {section === "career" ? <div className="functional-profile-grid">
          <ProfileList title="Histórico de cargos" empty="Nenhuma alteração de cargo registrada." rows={data.positionHistory.map((event) => ({ id: `position-${event.id}`, primary: `${event.fromPosition ? `${event.fromPosition} → ` : ""}${event.toPosition}`, secondary: `${positionEventLabel(event.eventType)} · ${event.decidedByName} · ${formatDateTime(event.effectiveAt)}${event.note ? ` · ${event.note}` : ""}`, status: positionEventLabel(event.eventType), statusCode: "active" }))} />
          <ProfileList title="Cursos" empty="Nenhum curso vinculado." rows={data.courses.map((course) => ({ id: `course-${course.id}`, primary: course.name, secondary: course.status === "completed" ? `Concluído em ${formatDateTime(course.completedAt!)} · ${course.completedByName ?? "Responsável não identificado"}` : `Vinculado em ${formatDateTime(course.assignedAt)} · ${course.assignedByName}`, status: course.status === "completed" ? "Concluído" : "Pendente", statusCode: course.status }))} />
        </div> : null}

        {section === "rh" ? <div className="functional-profile-grid">
          <ProfileList title="Advertências" empty="Nenhuma advertência registrada." rows={data.warnings.map((warning) => ({ id: `warning-${warning.id}`, primary: `${warning.sequence}ª ADV · ${warning.reason}`, secondary: `${formatMonth(warning.cycleMonth)} · emitida por ${warning.issuedByName} em ${formatDateTime(warning.issuedAt)}${warning.impactsProgression ? " · impacta progressão" : ""}`, status: warning.status === "annulled" ? "Anulada" : "Ativa", statusCode: warning.status }))} />
          <ProfileList title="Afastamentos" empty="Nenhum afastamento registrado." rows={data.absences.map((absence) => ({ id: `absence-${absence.id}`, primary: `${formatDateOnly(absence.startDate)} — ${formatDateOnly(absence.endDate)}`, secondary: `${absence.reason}${absence.reviewerName ? ` · análise de ${absence.reviewerName}` : ""}`, status: absenceStatus(absence.status), statusCode: absence.status }))} />
          <ProfileList title="Justificativas de horas" empty="Nenhuma justificativa registrada." rows={data.justifications.map((justification) => ({ id: `justification-${justification.id}`, primary: justification.reason, secondary: `Déficit ${formatMinutes(justification.deficitMinutes)}${justification.creditedMinutes !== null ? ` · abonado ${formatMinutes(justification.creditedMinutes)}` : ""}${justification.reviewerName ? ` · ${justification.reviewerName}` : ""}`, status: justificationStatus(justification.status), statusCode: justification.status }))} />
        </div> : null}

        {section === "access" ? <section className="management-card functional-profile-access">
          <div className="section-title"><div><p className="eyebrow">Exceções ao pacote do cargo</p><h3>Permissões individuais e temporárias</h3></div><span className="count-pill">{data.permissions.length}</span></div>
          <ProfileList bare title="" empty="Nenhuma permissão individual ou temporária foi concedida." rows={data.permissions.map((permission) => ({ id: `permission-${permission.id}`, primary: permission.label, secondary: `${permission.module} · ${permission.grantKind === "temporary" ? `temporária de ${formatDateTime(permission.validFrom)} até ${formatDateTime(permission.expiresAt!)}` : "individual sem expiração"} · concedida por ${permission.grantedByName}${permission.reason ? ` · ${permission.reason}` : ""}`, status: permissionStatus(permission.status), statusCode: permission.status }))} />
        </section> : null}

        {section === "timeline" ? <section className="management-card functional-profile-timeline">
          <div className="section-title"><div><p className="eyebrow">Histórico amigável para gestão</p><h3>Timeline funcional</h3></div><span className="count-pill">{data.timeline.length} evento(s)</span></div>
          <p className="functional-profile-note">Esta timeline reúne acontecimentos administrativos reais. A Auditoria permanece separada e continua registrando as operações técnicas completas do sistema.</p>
          <Timeline events={data.timeline.slice(0, visibleTimeline)} />
          {visibleTimeline < data.timeline.length ? <button className="functional-profile-more" type="button" onClick={() => setVisibleTimeline((current) => current + 18)}>Carregar mais acontecimentos</button> : null}
        </section> : null}
        {identityAction && canManageIdentity ? <div className="identity-dialog-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget && !identityBusy) setIdentityAction(null); }}><section aria-labelledby="identity-dialog-title" aria-modal="true" className="identity-dialog" ref={identityDialogRef} role="dialog"><form onSubmit={submitIdentityAction}>
          <header><div><p className="eyebrow">Ação exclusiva do Diretor Geral</p><h3 id="identity-dialog-title">{identityActionTitle(identityAction)}</h3></div><button aria-label="Fechar" disabled={identityBusy} type="button" onClick={() => setIdentityAction(null)}>×</button></header>
          <p>{identityActionDescription(identityAction)}</p>
          {identityAction === "correct-crm" ? <label>Data de registro<input required type="date" value={identityRegistrationDate} onChange={(event) => setIdentityRegistrationDate(event.target.value)} /></label> : null}
          <label>Motivo obrigatório<textarea autoFocus maxLength={500} minLength={5} required value={identityReason} onChange={(event) => setIdentityReason(event.target.value)} placeholder="Registre por que esta ação é necessária." /></label>
          {identityMessage ? <p className="form-error" role="alert">{identityMessage}</p> : null}
          <footer><button className="secondary-button" disabled={identityBusy} type="button" onClick={() => setIdentityAction(null)}>Cancelar</button><button disabled={identityBusy || identityReason.trim().length < 5} type="submit">{identityBusy ? "Processando…" : "Confirmar e auditar"}</button></footer>
        </form></section></div> : null}
      </> : null}
    </div>
  );
}

function ProfileMetric({ label, tone, value }: { label: string; tone?: string; value: string }) {
  return <article data-tone={tone}><strong>{value}</strong><span>{label}</span></article>;
}

function ProfileList({ bare = false, empty, rows, title }: { bare?: boolean; empty: string; rows: Array<{ id: string; primary: string; secondary: string; status: string; statusCode: string }>; title: string }) {
  return <section className={bare ? "functional-profile-list bare" : "management-card functional-profile-list"}>{title ? <div className="section-title"><div><h3>{title}</h3></div><span className="count-pill">{rows.length}</span></div> : null}<div>{rows.map((row) => <article key={row.id}><div><strong>{row.primary}</strong><p>{row.secondary}</p></div><em data-status={row.statusCode}>{row.status}</em></article>)}{!rows.length ? <div className="compact-empty"><span>◇</span><strong>Nenhum registro</strong><p>{empty}</p></div> : null}</div></section>;
}

function Timeline({ events }: { events: FunctionalTimelineEvent[] }) {
  return <div className="functional-timeline">{events.map((event) => <article key={event.id} data-tone={event.tone}><span aria-hidden="true" /><div><time dateTime={event.occurredAt}>{formatDateTime(event.occurredAt)}</time><strong>{event.title}</strong><p>{event.description}</p></div></article>)}{!events.length ? <div className="compact-empty"><span>◇</span><strong>Nenhum acontecimento</strong><p>A trajetória funcional começará a aparecer conforme os registros forem realizados.</p></div> : null}</div>;
}

function IdentityAssetPending() { return <div className="identity-asset-pending"><span aria-hidden="true">◇</span><small>Ativo pendente</small></div>; }
function identityStatus(status: string) { return ({ active: "Ativa", failed: "Pendente de reprocessamento", generating: "Em geração", pending: "Pendente" } as Record<string, string>)[status] ?? status; }
function identityActionTitle(action: IdentityAction) { return ({ "correct-crm": "Corrigir o CRM interno", regenerate: "Regenerar assinatura e rubrica", reprocess: "Desbloquear e reprocessar" } as Record<IdentityAction, string>)[action]; }
function identityActionDescription(action: IdentityAction) { return ({ "correct-crm": "A data informada recompõe o CRM a partir do passaporte. A correção não altera assinaturas já registradas em documentos anteriores.", regenerate: "Uma nova assinatura e uma nova rubrica coerentes serão geradas por IA. O CRM permanecerá igual.", reprocess: "Use esta ação quando a geração inicial estiver pendente ou tiver falhado. O acesso do profissional não será alterado." } as Record<IdentityAction, string>)[action]; }

function initials(name: string) { return name.split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]).join("").toUpperCase(); }
function profileStatus(status: string) { return ({ active: "Ativo", inactive: "Desligado", suspended: "Suspenso" } as Record<string, string>)[status] ?? status; }
function positionEventLabel(type: string) { return ({ appointment: "Nomeação", initial_assignment: "Admissão", promotion: "Promoção", succession: "Sucessão", override: "Alteração direta" } as Record<string, string>)[type] ?? "Alteração de cargo"; }
function absenceStatus(status: string) { return ({ approved: "Aprovado", cancelled: "Cancelado", pending: "Pendente", rejected: "Recusado" } as Record<string, string>)[status] ?? status; }
function justificationStatus(status: string) { return ({ approved: "Aprovada", pending: "Pendente", rejected: "Recusada" } as Record<string, string>)[status] ?? status; }
function permissionStatus(status: string) { return ({ active: "Ativa", expired: "Expirada", revoked: "Revogada", scheduled: "Agendada" } as Record<string, string>)[status] ?? status; }
function formatMinutes(total: number) { return `${Math.floor(total / 60)}h${String(total % 60).padStart(2, "0")}`; }
function formatMoney(value: number) { return new Intl.NumberFormat("pt-BR", { currency: "BRL", style: "currency" }).format(value); }
function formatDate(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "long", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
function formatDateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
function formatDateOnly(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeZone: "UTC" }).format(new Date(`${value.slice(0, 10)}T00:00:00Z`)); }
function formatMonth(value: string) { return new Intl.DateTimeFormat("pt-BR", { month: "long", timeZone: "UTC", year: "numeric" }).format(new Date(`${value.slice(0, 10)}T00:00:00Z`)); }
function elapsedLabel(value: string) {
  const days = Math.max(0, Math.floor((Date.now() - new Date(value).getTime()) / 86_400_000));
  if (days < 30) return `${days} dia(s)`;
  const months = Math.floor(days / 30);
  if (months < 12) return `${months} mês(es)`;
  const years = Math.floor(months / 12);
  const remainingMonths = months % 12;
  return `${years} ano(s)${remainingMonths ? ` e ${remainingMonths} mês(es)` : ""}`;
}
