"use client";

import { FormEvent, useState } from "react";
import type { ManagedProfile } from "../lib/admin-data";
import type { StaffPosition } from "../lib/access";
import { positionName } from "../lib/staff-position";
import { sanitizePassportInput } from "../lib/passport";
import { staffIdentity } from "../lib/staff-identity";
import { HpsmLogo } from "./hpsm-logo";

type TemporaryCredential = {
  displayName: string;
  passport: string;
  password: string;
};

type EditState = {
  displayName: string;
  status: string;
  userId: string;
};

export function UserManagement({ canManage, canOverridePosition, initialProfiles, positions }: { canManage: boolean; canOverridePosition: boolean; initialProfiles: ManagedProfile[]; positions: StaffPosition[] }) {
  const [profiles, setProfiles] = useState(initialProfiles);
  const [credential, setCredential] = useState<TemporaryCredential | null>(null);
  const [editing, setEditing] = useState<EditState | null>(null);
  const [overrideTarget, setOverrideTarget] = useState<ManagedProfile | null>(null);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [loading, setLoading] = useState(false);
  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");

  async function createUser(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (loading) return;
    const formElement = event.currentTarget;
    setLoading(true);
    setError("");
    setCredential(null);

    const form = new FormData(formElement);
    try {
      const response = await fetch("/api/users", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          displayName: form.get("displayName"),
          passport: form.get("passport"),
        }),
      });
      const payload = (await response.json()) as {
        error?: string;
        profile?: ManagedProfile;
        temporaryPassword?: string;
      };
      if (!response.ok || !payload.profile || !payload.temporaryPassword) {
        setError(payload.error ?? "Não foi possível criar o acesso.");
        return;
      }

      setProfiles((current) => [...current, payload.profile!].sort((a, b) => a.display_name.localeCompare(b.display_name)));
      setCredential({
        displayName: payload.profile.display_name,
        passport: payload.profile.passport,
        password: payload.temporaryPassword,
      });
      formElement.reset();
    } catch {
      setError("Não foi possível concluir a criação da conta.");
    } finally {
      setLoading(false);
    }
  }

  async function saveProfile(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (loading || !editing) return;
    setLoading(true);
    setError("");
    try {
      const response = await fetch("/api/users", {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(editing),
      });
      const payload = (await response.json()) as { error?: string; profile?: ManagedProfile };
      if (!response.ok || !payload.profile) {
        setError(payload.error ?? "Não foi possível atualizar o profissional.");
        return;
      }
      setProfiles((current) => current
        .map((profile) => profile.user_id === payload.profile!.user_id ? payload.profile! : profile)
        .sort((a, b) => a.display_name.localeCompare(b.display_name)));
      setEditing(null);
    } catch {
      setError("Não foi possível atualizar o profissional.");
    } finally {
      setLoading(false);
    }
  }

  async function overridePosition(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (loading || !overrideTarget) return;
    const values = new FormData(event.currentTarget);
    const positionId = Number(values.get("positionId"));
    setLoading(true);
    setError("");
    setSuccess("");
    try {
      const response = await fetch("/api/career/override-position", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ employeeId: overrideTarget.user_id, note: values.get("note"), positionId }),
      });
      const payload = (await response.json()) as { error?: string };
      if (!response.ok) {
        setError(payload.error ?? "Não foi possível alterar o cargo.");
        return;
      }
      setProfiles((current) => current.map((profile) => profile.user_id === overrideTarget.user_id ? { ...profile, position_id: positionId } : profile));
      setSuccess(`Cargo de ${overrideTarget.display_name} alterado e registrado no histórico funcional.`);
      setOverrideTarget(null);
    } catch {
      setError("Não foi possível alterar o cargo.");
    } finally {
      setLoading(false);
    }
  }

  const filteredProfiles = profiles.filter((profile) => {
    const matchesQuery = `${profile.display_name} ${profile.passport} ${positionName(profile, positions)}`
      .toLocaleLowerCase("pt-BR")
      .includes(query.toLocaleLowerCase("pt-BR"));
    return matchesQuery && (statusFilter === "all" || profile.status === statusFilter);
  });

  async function resetPassword(profile: ManagedProfile) {
    if (loading) return;
    setLoading(true);
    setError("");
    setCredential(null);
    try {
      const response = await fetch("/api/users/reset-password", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ userId: profile.user_id }),
      });
      const payload = (await response.json()) as { error?: string; temporaryPassword?: string };
      if (!response.ok || !payload.temporaryPassword) {
        setError(payload.error ?? "Não foi possível redefinir a senha.");
        return;
      }
      setProfiles((current) => current.map((item) => item.user_id === profile.user_id ? { ...item, must_change_password: true } : item));
      setCredential({ displayName: profile.display_name, passport: profile.passport, password: payload.temporaryPassword });
    } catch {
      setError("Não foi possível redefinir a senha.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="management-layout">
      {canManage ? <section className="management-card create-card">
        <div className="section-title"><div><p className="eyebrow">Novo profissional</p><h2>Criar acesso</h2></div><span>＋</span></div>
        <form onSubmit={createUser} className="create-user-form">
          <label htmlFor="displayName">Nome do profissional</label>
          <input id="displayName" name="displayName" maxLength={80} required placeholder="Maria Exemplo da Silva" />
          <div className="form-row">
            <div><label htmlFor="passport">Passaporte / Matrícula</label><input id="passport" name="passport" type="text" inputMode="numeric" minLength={1} maxLength={4} pattern="[0-9]{1,4}" required placeholder="Somente números (até 4)" onInput={(event) => { event.currentTarget.value = sanitizePassportInput(event.currentTarget.value); }} /></div>
            <div className="initial-position-preview"><span>Cargo inicial</span><strong>1 · Estagiário de Enfermagem</strong><small>Os próximos cargos dependem de promoção ou nomeação.</small></div>
          </div>
          {error ? <p className="form-error" role="alert">{error}</p> : null}
          <button className="submit-button" type="submit" disabled={loading}><span>{loading ? "Processando…" : "Gerar acesso temporário"}</span><span>→</span></button>
        </form>
      </section> : null}

      <section className="management-card team-card">
        <div className="section-title"><div><p className="eyebrow">Controle de acesso</p><h2>Equipe cadastrada</h2></div><span className="count-pill">{profiles.length}</span></div>
        <div className="team-toolbar">
          <label><span>Buscar profissional</span><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Nome, passaporte ou cargo" /></label>
          <label><span>Situação</span><select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}><option value="all">Todas</option><option value="active">Ativos</option><option value="suspended">Suspensos</option><option value="inactive">Inativos</option></select></label>
        </div>
        {error ? <p className="form-error team-error" role="alert">{error}</p> : null}
        {success ? <p className="form-success team-error" role="status">{success}</p> : null}
        <div className="team-table" role="table" aria-label="Equipe cadastrada">
          <div className="team-row team-head" role="row"><span>Profissional</span><span>Cargo</span><span>Situação</span><span>{canManage ? "Ação" : "Acesso"}</span></div>
          {filteredProfiles.map((profile) => (
            <div className="team-row" role="row" key={profile.user_id}>
              <span><strong>{profile.display_name}</strong><small>{staffIdentity(profile.passport, positionName(profile, positions))}</small></span>
              <span><strong>{positionName(profile, positions)}</strong><small>{positionLevelLabel(profile.position_id, positions)}</small></span>
              <span><em data-status={profile.status}>{profile.must_change_password ? "Primeiro acesso" : statusLabel(profile.status)}</em></span>
              <span className="row-actions">{canManage ? <><button className="table-action" type="button" onClick={() => setEditing({ displayName: profile.display_name, status: profile.status, userId: profile.user_id })} disabled={loading || profile.role_code === "diretor_geral"}>Editar</button>{canOverridePosition && profile.role_code !== "diretor_geral" ? <button className="table-action" type="button" onClick={() => { setOverrideTarget(profile); setError(""); setSuccess(""); }} disabled={loading}>Alterar cargo</button> : null}<button className="table-action" type="button" onClick={() => resetPassword(profile)} disabled={loading || profile.role_code === "diretor_geral"}>Nova senha</button></> : <span>Somente leitura</span>}</span>
            </div>
          ))}
          {!filteredProfiles.length ? <div className="compact-empty"><span>◇</span><strong>Nenhum profissional encontrado</strong><p>Altere a busca ou o filtro de situação.</p></div> : null}
        </div>
      </section>

      {canManage && editing ? (
        <div className="credential-overlay" role="dialog" aria-modal="true" aria-labelledby="edit-profile-title">
          <section className="credential-dialog edit-dialog">
            <p className="eyebrow">Gestão de acesso</p>
            <h2 id="edit-profile-title">Editar profissional</h2>
            <form className="create-user-form" onSubmit={saveProfile}>
              <label>Nome do profissional<input required minLength={2} maxLength={80} value={editing.displayName} onChange={(event) => setEditing({ ...editing, displayName: event.target.value })} /></label>
              <label>Situação<select value={editing.status} onChange={(event) => setEditing({ ...editing, status: event.target.value })}><option value="active">Ativo</option><option value="suspended">Suspenso</option><option value="inactive">Inativo</option></select></label>
              <p className="hr-card-intro">O cargo é alterado somente pelos fluxos de promoção, nomeação ou sucessão.</p>
              {error ? <p className="form-error" role="alert">{error}</p> : null}
              <button className="submit-button" type="submit" disabled={loading}><span>{loading ? "Salvando…" : "Salvar alterações"}</span><span>✓</span></button>
              <button className="secondary-button" type="button" onClick={() => { setEditing(null); setError(""); }} disabled={loading}>Cancelar</button>
            </form>
          </section>
        </div>
      ) : null}

      {canManage && overrideTarget ? (
        <div className="credential-overlay" role="dialog" aria-modal="true" aria-labelledby="override-position-title">
          <section className="credential-dialog edit-dialog">
            <p className="eyebrow">Override do Diretor Geral</p>
            <h2 id="override-position-title">Alterar cargo diretamente</h2>
            <p><strong>{overrideTarget.display_name}</strong><br />Cargo atual: {positionName(overrideTarget, positions)}</p>
            <form className="create-user-form" onSubmit={overridePosition}>
              <label>Novo cargo<select name="positionId" required defaultValue=""><option value="" disabled>Selecione</option>{positions.filter((position) => position.active && position.id !== overrideTarget.position_id).map((position) => <option key={position.id} value={position.id}>{position.level === null ? "Externo" : position.level} · {position.name}</option>)}</select></label>
              <label>Motivo ou observação <small>Opcional</small><textarea name="note" minLength={2} maxLength={2000} rows={4} placeholder="Contexto administrativo da alteração." /></label>
              {error ? <p className="form-error" role="alert">{error}</p> : null}
              <button className="submit-button" type="submit" disabled={loading}><span>{loading ? "Alterando…" : "Confirmar alteração de cargo"}</span><span>✓</span></button>
              <button className="secondary-button" type="button" onClick={() => { setOverrideTarget(null); setError(""); }} disabled={loading}>Cancelar</button>
            </form>
          </section>
        </div>
      ) : null}

      {credential ? (
        <div className="credential-overlay" role="dialog" aria-modal="true" aria-labelledby="credential-title">
          <section className="credential-dialog">
            <HpsmLogo className="large-mark" markOnly />
            <p className="eyebrow">Exibição única</p>
            <h2 id="credential-title">Credencial temporária</h2>
            <p>Entregue estes dados diretamente a {credential.displayName}. A senha não poderá ser consultada novamente.</p>
            <div className="credential-field"><span>Matrícula</span><strong>{credential.passport}</strong></div>
            <div className="credential-field"><span>Senha temporária</span><strong>{credential.password}</strong></div>
            <button className="submit-button" type="button" onClick={() => setCredential(null)}><span>Confirmar que anotei</span><span>✓</span></button>
          </section>
        </div>
      ) : null}
    </div>
  );
}

function statusLabel(status: string) {
  return ({ active: "Ativo", suspended: "Suspenso", inactive: "Inativo" } as Record<string, string>)[status] ?? status;
}

function positionLevelLabel(positionId: number | null, positions: StaffPosition[]) {
  const position = positions.find((item) => item.id === positionId);
  return position ? (position.level === null ? "Categoria institucional externa" : `Nível ${position.level}`) : "Sem nível definido";
}
