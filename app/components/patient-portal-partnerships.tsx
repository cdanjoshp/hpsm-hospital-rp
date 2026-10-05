"use client";

import { useState } from "react";
import type { PatientPortalPartnershipImportResult, PatientPortalPartnershipMember, PatientPortalPartnershipMemberPage, PatientPortalPartnershipPage } from "../lib/patient-portal";
import { formatPortalDate } from "../lib/patient-portal-format";
import { formatPatientPassport } from "../lib/passport";
import { useModalFocus } from "./use-modal-focus";

export function PatientPortalPartnerships({ initialMembers, initialPage }: { initialMembers: PatientPortalPartnershipMemberPage | null; initialPage: PatientPortalPartnershipPage }) {
  const [selectedId, setSelectedId] = useState<number | null>(initialMembers?.partnership.id ?? initialPage.items[0]?.id ?? null);
  const [members, setMembers] = useState<PatientPortalPartnershipMemberPage | null>(initialMembers);
  const [filter, setFilter] = useState("all");
  const [search, setSearch] = useState("");
  const [offset, setOffset] = useState(0);
  const [showImport, setShowImport] = useState(false);
  const [pendingAction, setPendingAction] = useState<PatientPortalPartnershipMember | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [loading, setLoading] = useState(false);
  const selected = initialPage.items.find((item) => item.id === selectedId) ?? null;

  async function load(partnershipId: number, nextFilter = filter, nextSearch = search, nextOffset = 0) {
    setLoading(true); setError("");
    try {
      const query = new URLSearchParams({ partnershipId: String(partnershipId), filter: nextFilter, search: nextSearch.trim(), offset: String(nextOffset) });
      const response = await fetch(`/api/patient-portal/partnerships?${query}`, { cache: "no-store" });
      const payload = await response.json() as PatientPortalPartnershipMemberPage & { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível consultar a parceria.");
      setSelectedId(partnershipId); setMembers(payload); setOffset(payload.offset);
    } catch (cause) { setError(messageOf(cause)); } finally { setLoading(false); }
  }

  async function mutate(action: "cancel" | "unlink", member: PatientPortalPartnershipMember) {
    if (!selectedId) return;
    setLoading(true); setError("");
    try {
      const response = await fetch("/api/patient-portal/partnerships", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action, partnershipId: selectedId, recordKey: member.recordKey }) });
      const payload = await response.json() as { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível concluir a operação.");
      setPendingAction(null); setNotice(action === "unlink" ? "Beneficiário removido da parceria." : "Pré-beneficiário cancelado."); await load(selectedId);
    } catch (cause) { setError(messageOf(cause)); } finally { setLoading(false); }
  }

  return <div className="patient-portal-partnerships">
    {error ? <p className="form-error" role="alert">{error}</p> : null}{notice ? <p className="form-success" role="status">{notice}</p> : null}
    <section className="patient-portal-partnership-cards" aria-label="Parcerias sob sua responsabilidade">
      {initialPage.items.map((partnership) => <button aria-pressed={selectedId === partnership.id} key={partnership.id} onClick={() => void load(partnership.id)} type="button"><span><strong>{partnership.name}</strong><small>{partnership.role === "primary" ? "Responsável principal" : "Responsável adicional"} · {partnership.status === "active" ? "ativa" : "inativa"}</small></span><em>{partnership.totalInformed}</em><small>{partnership.linked} vinculados · {partnership.pendingRegistration} aguardando cadastro · {partnership.nameReview} em revisão</small></button>)}
    </section>
    {selected && members ? <section className="patient-portal-content-card patient-portal-partnership-members">
      <header><div><p className="eyebrow">Composição da parceria</p><h2>{members.partnership.name}</h2><p>Somente nome, passaporte e situação são exibidos neste espaço.</p></div>{members.partnership.status === "active" ? <button className="patient-portal-submit" onClick={() => setShowImport(true)} type="button">Adicionar pessoas</button> : <span className="patient-portal-plan-status" data-tone="expired">Inativa</span>}</header>
      {members.partnership.status === "inactive" ? <p className="patient-portal-plan-message"><strong>Alterações bloqueadas.</strong> A parceria está inativa. O histórico permanece disponível para consulta.</p> : null}
      <div className="patient-portal-partnership-tools"><label><span>Situação</span><select value={filter} onChange={(event) => { setFilter(event.target.value); void load(selected.id, event.target.value); }}><option value="all">Todas</option><option value="linked">Vinculados</option><option value="pending_registration">Aguardando cadastro</option><option value="name_review">Revisão interna</option></select></label><label><span>Buscar</span><input placeholder="Nome ou passaporte" value={search} onChange={(event) => setSearch(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter") void load(selected.id); }} /></label><button disabled={loading} onClick={() => void load(selected.id)} type="button">Buscar</button></div>
      <div className="patient-portal-partnership-list">{members.items.map((member) => <article key={member.recordKey}><span className="patient-portal-partnership-avatar">{initials(member.name)}</span><div><strong>{member.name}</strong><small>Passaporte {formatPatientPassport(member.passport)} · {formatPortalDate(member.occurredAt)}</small></div><em data-status={member.status}>{statusLabel(member.status)}</em>{members.partnership.status === "active" && member.status !== "name_review" ? <button onClick={() => setPendingAction(member)} type="button">{member.status === "linked" ? "Remover" : "Cancelar"}</button> : null}</article>)}</div>
      {!members.items.length ? <div className="patient-portal-empty"><strong>Nenhum registro encontrado.</strong><p>Altere os filtros ou adicione pessoas à parceria.</p></div> : null}
      {members.total > members.limit ? <div className="patient-portal-pagination" aria-label="Paginação dos beneficiários"><button disabled={loading || offset === 0} onClick={() => void load(selected.id, filter, search, Math.max(0, offset - members.limit))} type="button">← Anterior</button><span>{offset + 1}–{Math.min(offset + members.items.length, members.total)} de {members.total}</span><button disabled={loading || offset + members.limit >= members.total} onClick={() => void load(selected.id, filter, search, offset + members.limit)} type="button">Próxima →</button></div> : null}
    </section> : null}
    {showImport && selectedId ? <PortalImportModal partnershipId={selectedId} onClose={() => setShowImport(false)} onSaved={async (result) => { setShowImport(false); setNotice(importMessage(result)); await load(selectedId); }} /> : null}
    {pendingAction && selectedId ? <PortalConfirm member={pendingAction} onClose={() => setPendingAction(null)} onConfirm={() => void mutate(pendingAction.status === "linked" ? "unlink" : "cancel", pendingAction)} saving={loading} /> : null}
  </div>;
}

function PortalImportModal({ onClose, onSaved, partnershipId }: { onClose: () => void; onSaved: (result: PatientPortalPartnershipImportResult) => void; partnershipId: number }) {
  const [text, setText] = useState(""); const [error, setError] = useState(""); const [saving, setSaving] = useState(false);
  async function submit() { const people = text.split(/\r?\n/).map((line) => { const [passport, ...name] = line.split(/[;,\t]/); return { passport: passport?.trim(), name: name.join(" ").trim() }; }).filter((person) => person.passport || person.name); if (!people.length) return setError("Informe ao menos uma linha no formato passaporte; nome."); setSaving(true); setError(""); try { const response = await fetch("/api/patient-portal/partnerships", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "import", partnershipId, people }) }); const payload = await response.json() as PatientPortalPartnershipImportResult & { error?: string }; if (!response.ok) throw new Error(payload.error ?? "Não foi possível processar a lista."); onSaved(payload); } catch (cause) { setError(messageOf(cause)); } finally { setSaving(false); } }
  return <PortalModal title="Adicionar pessoas" description="Use uma linha por pessoa: passaporte; nome completo." onClose={onClose}>{error ? <p className="form-error" role="alert">{error}</p> : null}<label><span>Lista de beneficiários</span><textarea autoFocus placeholder={"123; Maria da Silva\n456; João Souza"} rows={8} value={text} onChange={(event) => setText(event.target.value)} /></label><p className="partnership-help">Cadastros existentes com nome compatível são vinculados. Os demais aguardam cadastro ou revisão interna.</p><div><button disabled={saving} onClick={onClose} type="button">Voltar</button><button className="patient-portal-submit" disabled={saving} onClick={() => void submit()} type="button">{saving ? "Processando…" : "Processar lista"}</button></div></PortalModal>;
}
function PortalConfirm({ member, onClose, onConfirm, saving }: { member: PatientPortalPartnershipMember; onClose: () => void; onConfirm: () => void; saving: boolean }) { const removing = member.status === "linked"; return <PortalModal title={removing ? "Remover beneficiário" : "Cancelar pré-beneficiário"} description={`${member.name} · passaporte ${formatPatientPassport(member.passport)}. O histórico da operação será preservado.`} onClose={onClose}><div><button disabled={saving} onClick={onClose} type="button">Voltar</button><button className="danger-action" disabled={saving} onClick={onConfirm} type="button">{saving ? "Confirmando…" : "Confirmar"}</button></div></PortalModal>; }
function PortalModal({ children, description, onClose, title }: { children: React.ReactNode; description: string; onClose: () => void; title: string }) { const dialogRef = useModalFocus(onClose); return <div className="partnership-modal-backdrop" onMouseDown={(event) => { if (event.currentTarget === event.target) onClose(); }} role="presentation"><section aria-modal="true" className="partnership-modal patient-portal-content-card" ref={dialogRef} role="dialog" tabIndex={-1}><header><div><p className="eyebrow">Portal do Paciente</p><h2>{title}</h2><p>{description}</p></div><button aria-label="Fechar" onClick={onClose} type="button">×</button></header>{children}</section></div>; }
function initials(name: string) { return name.trim().split(/\s+/).slice(0, 2).map((part) => part[0]).join("").toUpperCase(); }
function statusLabel(status: PatientPortalPartnershipMember["status"]) { return status === "linked" ? "Vinculado" : status === "pending_registration" ? "Aguardando cadastro" : "Revisão interna"; }
function messageOf(value: unknown) { return value instanceof Error && value.message ? value.message : "Não foi possível concluir a operação."; }
function importMessage(result: PatientPortalPartnershipImportResult) { const summary = result.summary; return `Lista processada: ${summary.linked} vinculado(s), ${summary.already_linked} já existente(s), ${summary.pending_registration} aguardando cadastro, ${summary.name_review} em revisão e ${summary.invalid} inválido(s).`; }
