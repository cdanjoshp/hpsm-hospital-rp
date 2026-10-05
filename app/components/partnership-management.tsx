"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type {
  PartnershipDetailPage,
  PartnershipImportResult,
  PartnershipMember,
  PartnershipMemberPage,
  PartnershipPage,
  PartnershipPatient,
  PartnershipStatus,
} from "../lib/partnerships";
import { formatPatientPassport } from "../lib/passport";
import { useModalFocus } from "./use-modal-focus";

type ActionState =
  | { kind: "cancel" | "unlink"; member: PartnershipMember }
  | { kind: "status"; status: PartnershipStatus }
  | { decision: "confirm" | "reject"; kind: "review"; member: PartnershipMember };

export function PartnershipManagement({ canManage, initialDetail = null, initialMembers, initialPage }: { canManage: boolean; initialDetail?: PartnershipDetailPage | null; initialMembers?: PartnershipMemberPage; initialPage: PartnershipPage }) {
  const [page, setPage] = useState(initialPage);
  const [selectedId, setSelectedId] = useState<number | null>(initialPage.items[0]?.id ?? null);
  const [detail, setDetail] = useState<PartnershipDetailPage | null>(initialDetail);
  const [members, setMembers] = useState<PartnershipMemberPage>(initialMembers ?? { items: [], limit: 20, offset: 0, total: 0 });
  const [status, setStatus] = useState<PartnershipStatus>("active");
  const [search, setSearch] = useState("");
  const [memberFilter, setMemberFilter] = useState("all");
  const [memberSearch, setMemberSearch] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [showCreate, setShowCreate] = useState(false);
  const [showImport, setShowImport] = useState(false);
  const [action, setAction] = useState<ActionState | null>(null);
  const initialSelection = useRef(Boolean(initialDetail && initialMembers));

  useEffect(() => {
    if (!selectedId) return;
    if (initialSelection.current) {
      initialSelection.current = false;
      return;
    }
    void loadSelected(selectedId, memberFilter, memberSearch);
  }, [selectedId, memberFilter, memberSearch]); // eslint-disable-line react-hooks/exhaustive-deps

  async function loadList(nextStatus = status, nextSearch = search) {
    setLoading(true); setError("");
    try {
      const response = await fetch(`/api/partnerships?view=list&status=${nextStatus}&search=${encodeURIComponent(nextSearch.trim())}`, { cache: "no-store" });
      const payload = await response.json() as PartnershipPage & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível carregar as parcerias.");
      setPage(payload);
      if (!payload.items.length) {
        setDetail(null);
        setMembers({ items: [], limit: 20, offset: 0, total: 0 });
      }
      setSelectedId((current) => payload.items.some((item) => item.id === current) ? current : payload.items[0]?.id ?? null);
    } catch (cause) { setError(messageOf(cause)); } finally { setLoading(false); }
  }

  async function loadSelected(id: number, filter = memberFilter, query = memberSearch) {
    setLoading(true); setError("");
    try {
      const [detailResponse, memberResponse] = await Promise.all([
        fetch(`/api/partnerships?view=detail&partnershipId=${id}`, { cache: "no-store" }),
        fetch(`/api/partnerships?view=members&partnershipId=${id}&filter=${filter}&search=${encodeURIComponent(query.trim())}`, { cache: "no-store" }),
      ]);
      const detailPayload = await detailResponse.json() as PartnershipDetailPage & { error?: string };
      const memberPayload = await memberResponse.json() as PartnershipMemberPage & { error?: string };
      if (!detailResponse.ok) throw new Error(detailPayload.error ?? "Não foi possível carregar a parceria.");
      if (!memberResponse.ok) throw new Error(memberPayload.error ?? "Não foi possível carregar os beneficiários.");
      setDetail(detailPayload); setMembers(memberPayload);
    } catch (cause) { setError(messageOf(cause)); } finally { setLoading(false); }
  }

  async function refreshSelected(success: string) {
    setNotice(success);
    await Promise.all([loadList(), selectedId ? loadSelected(selectedId) : Promise.resolve()]);
  }

  const totals = useMemo(() => page.items.reduce((result, item) => ({
    linked: result.linked + item.linked,
    pending: result.pending + item.pending_registration,
    review: result.review + item.name_review,
  }), { linked: 0, pending: 0, review: 0 }), [page.items]);

  return <div className="partnership-management">
    <section className="partnership-metrics" aria-label="Resumo das parcerias exibidas">
      <PartnershipMetric label={status === "active" ? "Parcerias ativas" : "Parcerias inativas"} value={page.total} />
      <PartnershipMetric label="Beneficiários vinculados" value={totals.linked} />
      <PartnershipMetric label="Aguardando cadastro" value={totals.pending} tone={totals.pending ? "pending" : undefined} />
      <PartnershipMetric label="Revisão de nome" value={totals.review} tone={totals.review ? "warning" : undefined} />
    </section>

    {error ? <p className="form-error" role="alert">{error}</p> : null}
    {notice ? <p className="form-success" role="status">{notice}</p> : null}

    <section className="partnership-toolbar management-card">
      <div><p className="eyebrow">Parcerias e convênios</p><h2>Organizações parceiras</h2></div>
      <label><span>Buscar parceria</span><input onChange={(event) => setSearch(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter") void loadList(); }} placeholder="Nome da organização" value={search} /></label>
      <label><span>Situação</span><select value={status} onChange={(event) => { const next = event.target.value as PartnershipStatus; setStatus(next); void loadList(next); }}><option value="active">Ativas</option><option value="inactive">Inativas</option></select></label>
      <button className="secondary-action" disabled={loading} onClick={() => void loadList()} type="button">Buscar</button>
      {canManage ? <button className="primary-action" onClick={() => setShowCreate(true)} type="button">Nova parceria</button> : null}
    </section>

    <section className="partnership-workspace">
      <aside className="management-card partnership-list" aria-label="Lista de parcerias">
        {page.items.map((item) => <button data-selected={selectedId === item.id} key={item.id} onClick={() => setSelectedId(item.id)} type="button">
          <span className="partnership-list-mark" aria-hidden="true">⌁</span>
          <span><strong>{item.name}</strong><small>{item.responsible ? `Responsável: ${item.responsible.name}` : "Sem responsável definido"}{item.secondary_responsible ? ` · ${item.secondary_responsible.name}` : ""}</small><small>{item.linked} vinculados · {item.pending_registration + item.name_review} pendentes</small></span>
          <em data-status={item.status}>{item.status === "active" ? "Ativa" : "Inativa"}</em>
        </button>)}
        {!page.items.length ? <Empty title="Nenhuma parceria encontrada" text="Altere a busca ou cadastre uma nova organização." /> : null}
      </aside>

      <main className="partnership-detail">
        {detail?.found && detail.partnership ? <>
          <PartnershipEditor canManage={canManage} data={detail} key={detail.partnership.id} onChanged={(message) => void refreshSelected(message)} onError={setError} onStatus={(next) => setAction({ kind: "status", status: next })} />
          <section className="management-card partnership-members">
            <header><div><p className="eyebrow">Composição</p><h2>Beneficiários e pendências</h2></div>{canManage && detail.partnership.status === "active" ? <button className="primary-action" onClick={() => setShowImport(true)} type="button">Adicionar pessoas</button> : null}</header>
            <div className="partnership-member-tools">
              <label><span>Filtrar</span><select value={memberFilter} onChange={(event) => setMemberFilter(event.target.value)}><option value="all">Todos</option><option value="linked">Vinculados</option><option value="pending_registration">Aguardando cadastro</option><option value="name_review">Revisão de nome</option></select></label>
              <label><span>Buscar</span><input placeholder="Nome ou passaporte" value={memberSearch} onChange={(event) => setMemberSearch(event.target.value)} /></label>
            </div>
            <div className="partnership-member-list">
              {members.items.map((member) => <article key={`${member.record_type}-${member.id}`}>
                <span className="partnership-member-avatar">{initials(member.name)}</span>
                <div><strong>{member.name}</strong><small>Passaporte {formatPatientPassport(member.passport)} · {formatDate(member.occurred_at)}</small>{member.canonical_name ? <small>Cadastro atual: {member.canonical_name}</small> : null}</div>
                <span className="partnership-state" data-status={member.status}>{statusLabel(member.status)}</span>
                {canManage ? <div className="partnership-member-actions">
                  {member.status === "name_review" ? <><button onClick={() => setAction({ decision: "confirm", kind: "review", member })} type="button">Confirmar nome</button><button onClick={() => setAction({ decision: "reject", kind: "review", member })} type="button">Recusar</button></> : null}
                  {member.status === "linked" ? <button onClick={() => setAction({ kind: "unlink", member })} type="button">Remover</button> : null}
                  {member.status === "pending_registration" ? <button onClick={() => setAction({ kind: "cancel", member })} type="button">Cancelar</button> : null}
                </div> : null}
              </article>)}
              {!members.items.length ? <Empty title="Nenhum registro neste filtro" text="A composição da parceria aparecerá aqui." /> : null}
            </div>
            {members.total > members.items.length ? <p className="partnership-page-note">Mostrando {members.items.length} de {members.total}. Refine a busca para localizar outros registros.</p> : null}
          </section>
        </> : <section className="management-card"><Empty title="Selecione uma parceria" text="Os dados e a composição serão carregados aqui." /></section>}
      </main>
    </section>

    {showCreate ? <PartnershipFormModal onClose={() => setShowCreate(false)} onSaved={async (id) => { setShowCreate(false); await loadList("active", ""); setSelectedId(id); setNotice("Parceria cadastrada com sucesso."); }} /> : null}
    {showImport && selectedId ? <ImportModal partnershipId={selectedId} onClose={() => setShowImport(false)} onSaved={async (result) => { setShowImport(false); await refreshSelected(importMessage(result)); }} /> : null}
    {action && selectedId ? <ActionModal action={action} partnershipId={selectedId} onClose={() => setAction(null)} onSaved={async (message) => { setAction(null); await refreshSelected(message); }} /> : null}
  </div>;
}

function PartnershipEditor({ canManage, data, onChanged, onError, onStatus }: { canManage: boolean; data: PartnershipDetailPage; onChanged: (message: string) => void; onError: (message: string) => void; onStatus: (status: PartnershipStatus) => void }) {
  const partnership = data.partnership!;
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(partnership.name);
  const [notes, setNotes] = useState(partnership.notes ?? "");
  const [responsible, setResponsible] = useState<PartnershipPatient | null>(partnership.responsible);
  const [secondaryResponsible, setSecondaryResponsible] = useState<PartnershipPatient | null>(partnership.secondary_responsible);
  const [responsibleTarget, setResponsibleTarget] = useState<"primary" | "secondary">(partnership.responsible ? "secondary" : "primary");
  const [responsibleSearch, setResponsibleSearch] = useState("");
  const [patients, setPatients] = useState<PartnershipPatient[]>([]);
  const [saving, setSaving] = useState(false);

  function cancelEditing() {
    setName(partnership.name); setNotes(partnership.notes ?? "");
    setResponsible(partnership.responsible); setSecondaryResponsible(partnership.secondary_responsible);
    setPatients([]); setResponsibleSearch(""); setEditing(false);
  }

  async function searchPatients() {
    if (!responsibleSearch.trim()) return setPatients([]);
    try {
      const response = await fetch(`/api/partnerships?view=patients&search=${encodeURIComponent(responsibleSearch.trim())}`, { cache: "no-store" });
      const payload = await response.json() as { error?: string; items?: PartnershipPatient[] };
      if (!response.ok) throw new Error(payload.error); setPatients(payload.items ?? []);
    } catch (cause) { onError(messageOf(cause)); }
  }

  async function save() {
    if (secondaryResponsible && !responsible) return onError("Selecione primeiro o responsável principal.");
    if (secondaryResponsible && secondaryResponsible.id === responsible?.id) return onError("Selecione pessoas diferentes para cada responsabilidade.");
    setSaving(true); onError("");
    try {
      const response = await fetch("/api/partnerships", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "update", name, notes, partnershipId: partnership.id, responsiblePatientId: responsible?.id ?? null, secondaryResponsiblePatientId: secondaryResponsible?.id ?? null }) });
      const payload = await response.json() as { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível salvar a parceria.");
      setEditing(false); onChanged("Parceria atualizada com sucesso.");
    } catch (cause) { onError(messageOf(cause)); } finally { setSaving(false); }
  }

  return <section className="management-card partnership-file">
    <header><div><p className="eyebrow">Cadastro institucional</p><h2>{partnership.name}</h2><p>Criada em {formatDate(partnership.created_at)} · atualizada em {formatDate(partnership.updated_at)}</p></div><span className="partnership-state" data-status={partnership.status}>{partnership.status === "active" ? "Ativa" : "Inativa"}</span></header>
    <div className="partnership-detail-metrics"><span><strong>{data.metrics?.linked ?? 0}</strong> vinculados</span><span><strong>{data.metrics?.pending_registration ?? 0}</strong> aguardando cadastro</span><span><strong>{data.metrics?.name_review ?? 0}</strong> revisão de nome</span></div>
    {editing ? <div className="partnership-edit-grid">
      <label><span>Nome da parceria</span><input maxLength={120} value={name} onChange={(event) => setName(event.target.value)} /></label>
      <label className="wide"><span>Observações internas</span><textarea maxLength={2000} rows={3} value={notes} onChange={(event) => setNotes(event.target.value)} /></label>
      <div className="partnership-responsible-assignments wide">
        <p className="partnership-selected-patient"><span><small>Responsável principal</small>{responsible ? <><strong>{responsible.name}</strong> · passaporte {formatPatientPassport(responsible.passport)}</> : "Nenhum paciente selecionado."}</span>{responsible ? <button onClick={() => { setResponsible(null); setSecondaryResponsible(null); setResponsibleTarget("primary"); }} type="button">Remover</button> : null}</p>
        <p className="partnership-selected-patient"><span><small>Responsável adicional</small>{secondaryResponsible ? <><strong>{secondaryResponsible.name}</strong> · passaporte {formatPatientPassport(secondaryResponsible.passport)}</> : "Nenhum paciente selecionado."}</span>{secondaryResponsible ? <button onClick={() => setSecondaryResponsible(null)} type="button">Remover</button> : null}</p>
      </div>
      <div className="partnership-responsible-target wide" role="group" aria-label="Responsabilidade a preencher"><button aria-pressed={responsibleTarget === "primary"} onClick={() => { setResponsibleTarget("primary"); setPatients([]); }} type="button">Escolher principal</button><button aria-pressed={responsibleTarget === "secondary"} onClick={() => { setResponsibleTarget("secondary"); setPatients([]); }} type="button">Escolher adicional</button></div>
      <div className="partnership-responsible-picker wide"><label><span>Buscar {responsibleTarget === "primary" ? "responsável principal" : "responsável adicional"} no cadastro de pacientes</span><input placeholder="Nome ou passaporte" value={responsibleSearch} onChange={(event) => setResponsibleSearch(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter") { event.preventDefault(); void searchPatients(); } }} /></label><button className="secondary-action" onClick={() => void searchPatients()} type="button">Buscar</button></div>
      {patients.length ? <div className="partnership-patient-results wide">{patients.map((patient) => <div className="partnership-patient-result" key={patient.id}>
        <button disabled={patient.id === (responsibleTarget === "primary" ? secondaryResponsible?.id : responsible?.id) || (responsibleTarget === "secondary" && !responsible)} onClick={() => { if (responsibleTarget === "primary") setResponsible(patient); else setSecondaryResponsible(patient); setPatients([]); setResponsibleSearch(""); }} type="button"><strong>{patient.name}</strong><small>Passaporte {formatPatientPassport(patient.passport)}</small></button>
      </div>)}</div> : null}
      <div className="partnership-form-actions wide"><button className="secondary-action" disabled={saving} onClick={cancelEditing} type="button">Cancelar</button><button className="primary-action" disabled={saving} onClick={() => void save()} type="button">{saving ? "Salvando…" : "Salvar alterações"}</button></div>
    </div> : <div className="partnership-read-grid"><div><span>Responsável principal</span><strong>{partnership.responsible?.name ?? "Não definido"}</strong><small>{partnership.responsible ? `Passaporte ${formatPatientPassport(partnership.responsible.passport)}` : "Selecione um paciente cadastrado."}</small></div><div><span>Responsável adicional</span><strong>{partnership.secondary_responsible?.name ?? "Não definido"}</strong><small>{partnership.secondary_responsible ? `Passaporte ${formatPatientPassport(partnership.secondary_responsible.passport)}` : "Selecione outro paciente cadastrado."}</small></div><div><span>Observações internas</span><p>{partnership.notes || "Nenhuma observação cadastrada."}</p></div>{partnership.deactivation_reason ? <div><span>Motivo da inativação</span><p>{partnership.deactivation_reason}</p></div> : null}</div>}
    {canManage && !editing ? <footer><button className="secondary-action" onClick={() => setEditing(true)} type="button">Editar parceria</button><button className={partnership.status === "active" ? "danger-action" : "primary-action"} onClick={() => onStatus(partnership.status === "active" ? "inactive" : "active")} type="button">{partnership.status === "active" ? "Inativar parceria" : "Reativar parceria"}</button></footer> : null}
  </section>;
}

function PartnershipFormModal({ onClose, onSaved }: { onClose: () => void; onSaved: (id: number) => void }) {
  const [name, setName] = useState(""); const [notes, setNotes] = useState(""); const [error, setError] = useState(""); const [saving, setSaving] = useState(false);
  async function submit() { setSaving(true); setError(""); try { const response = await fetch("/api/partnerships", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "create", name, notes }) }); const payload = await response.json() as { error?: string; id?: number }; if (!response.ok || !payload.id) throw new Error(payload.error ?? "Não foi possível cadastrar a parceria."); onSaved(payload.id); } catch (cause) { setError(messageOf(cause)); } finally { setSaving(false); } }
  return <Modal title="Nova parceria" description="Cadastre a organização. O responsável e os beneficiários podem ser definidos em seguida." onClose={onClose}>{error ? <p className="form-error" role="alert">{error}</p> : null}<label><span>Nome da parceria</span><input autoFocus maxLength={120} value={name} onChange={(event) => setName(event.target.value)} /></label><label><span>Observações internas</span><textarea maxLength={2000} rows={4} value={notes} onChange={(event) => setNotes(event.target.value)} /></label><div className="partnership-form-actions"><button className="secondary-action" disabled={saving} onClick={onClose} type="button">Cancelar</button><button className="primary-action" disabled={saving || name.trim().length < 2} onClick={() => void submit()} type="button">{saving ? "Cadastrando…" : "Cadastrar parceria"}</button></div></Modal>;
}

function ImportModal({ onClose, onSaved, partnershipId }: { onClose: () => void; onSaved: (result: PartnershipImportResult) => void; partnershipId: number }) {
  const [text, setText] = useState(""); const [error, setError] = useState(""); const [saving, setSaving] = useState(false);
  async function submit() { const people = text.split(/\r?\n/).map((line) => { const [passport, ...name] = line.split(/[;,\t]/); return { passport: passport?.trim(), name: name.join(" ").trim() }; }).filter((person) => person.passport || person.name); if (!people.length) return setError("Informe ao menos uma linha no formato passaporte; nome."); setSaving(true); setError(""); try { const response = await fetch("/api/partnerships", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "import", partnershipId, people }) }); const payload = await response.json() as PartnershipImportResult & { error?: string }; if (!response.ok) throw new Error(payload.error ?? "Não foi possível processar a lista."); onSaved(payload); } catch (cause) { setError(messageOf(cause)); } finally { setSaving(false); } }
  return <Modal title="Adicionar pessoas" description="Uma pessoa por linha: passaporte; nome completo. O sistema vincula pacientes existentes e preserva os demais como pendentes." onClose={onClose}>{error ? <p className="form-error" role="alert">{error}</p> : null}<label><span>Lista de pessoas</span><textarea autoFocus placeholder={"123; Maria da Silva\n456; João Souza"} rows={9} value={text} onChange={(event) => setText(event.target.value)} /></label><p className="partnership-help">Limite de 500 linhas por envio. Linhas inválidas são informadas sem impedir as válidas.</p><div className="partnership-form-actions"><button className="secondary-action" disabled={saving} onClick={onClose} type="button">Cancelar</button><button className="primary-action" disabled={saving} onClick={() => void submit()} type="button">{saving ? "Processando…" : "Processar lista"}</button></div></Modal>;
}

function ActionModal({ action, onClose, onSaved, partnershipId }: { action: ActionState; onClose: () => void; onSaved: (message: string) => void; partnershipId: number }) {
  const [reason, setReason] = useState(""); const [error, setError] = useState(""); const [saving, setSaving] = useState(false);
  const destructive = action.kind !== "review" || action.decision === "reject";
  const needsReason = (action.kind === "status" && action.status === "inactive") || action.kind === "unlink" || action.kind === "cancel" || (action.kind === "review" && action.decision === "reject");
  const title = actionTitle(action);
  async function submit() { setSaving(true); setError(""); try { const body: Record<string, unknown> = { partnershipId, reason }; if (action.kind === "status") Object.assign(body, { action: "status", status: action.status }); else if (action.kind === "review") Object.assign(body, { action: "review", decision: action.decision, recordId: action.member.id }); else Object.assign(body, { action: action.kind, recordId: action.member.id }); const response = await fetch("/api/partnerships", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) }); const payload = await response.json() as { error?: string }; if (!response.ok) throw new Error(payload.error ?? "Não foi possível concluir a operação."); onSaved(`${title} concluído com sucesso.`); } catch (cause) { setError(messageOf(cause)); } finally { setSaving(false); } }
  return <Modal title={title} description={action.kind === "review" && action.decision === "confirm" ? `O cadastro atual é “${action.member.canonical_name}” e a parceria informou “${action.member.name}”. Confirme somente após verificar a identidade.` : "Esta ação preservará o histórico completo para auditoria."} onClose={onClose}>{error ? <p className="form-error" role="alert">{error}</p> : null}{needsReason ? <label><span>Motivo</span><textarea autoFocus maxLength={500} rows={3} value={reason} onChange={(event) => setReason(event.target.value)} /></label> : null}<div className="partnership-form-actions"><button className="secondary-action" disabled={saving} onClick={onClose} type="button">Voltar</button><button className={destructive ? "danger-action" : "primary-action"} disabled={saving || (needsReason && reason.trim().length < 2)} onClick={() => void submit()} type="button">{saving ? "Confirmando…" : "Confirmar"}</button></div></Modal>;
}

function Modal({ children, description, onClose, title }: { children: React.ReactNode; description: string; onClose: () => void; title: string }) { const dialogRef = useModalFocus(onClose); return <div className="partnership-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.currentTarget === event.target) onClose(); }}><section aria-describedby="partnership-modal-description" aria-labelledby="partnership-modal-title" aria-modal="true" className="partnership-modal management-card" ref={dialogRef} role="dialog" tabIndex={-1}><header><div><p className="eyebrow">Parcerias e convênios</p><h2 id="partnership-modal-title">{title}</h2><p id="partnership-modal-description">{description}</p></div><button aria-label="Fechar" onClick={onClose} type="button">×</button></header>{children}</section></div>; }
function PartnershipMetric({ label, tone, value }: { label: string; tone?: string; value: number }) { return <article data-tone={tone}><strong>{value}</strong><span>{label}</span></article>; }
function Empty({ text, title }: { text: string; title: string }) { return <div className="compact-empty"><span>◇</span><strong>{title}</strong><p>{text}</p></div>; }
function initials(name: string) { return name.trim().split(/\s+/).slice(0, 2).map((part) => part[0]).join("").toUpperCase(); }
function formatDate(value: string) { const date = new Date(value); return Number.isNaN(date.getTime()) ? "data não informada" : new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeZone: "America/Sao_Paulo" }).format(date); }
function statusLabel(status: PartnershipMember["status"]) { return status === "linked" ? "Vinculado" : status === "pending_registration" ? "Aguardando cadastro" : "Revisão de nome"; }
function messageOf(value: unknown) { return value instanceof Error && value.message ? value.message : "Não foi possível concluir a operação."; }
function importMessage(result: PartnershipImportResult) { const summary = result.summary; return `Lista processada: ${summary.linked} vinculado(s), ${summary.already_linked} já existente(s), ${summary.pending_registration} aguardando cadastro, ${summary.name_review} em revisão e ${summary.invalid} inválido(s).`; }
function actionTitle(action: ActionState) { if (action.kind === "status") return action.status === "inactive" ? "Inativar parceria" : "Reativar parceria"; if (action.kind === "unlink") return "Remover beneficiário"; if (action.kind === "cancel") return "Cancelar pré-beneficiário"; if (action.kind === "review") return action.decision === "confirm" ? "Confirmar divergência de nome" : "Recusar divergência de nome"; return "Confirmar operação"; }
