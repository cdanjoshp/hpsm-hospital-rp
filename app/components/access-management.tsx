"use client";

import { FormEvent, useMemo, useState } from "react";
import type { ManagedProfile } from "../lib/admin-data";
import type { AccessManagementData, SystemPermission } from "../lib/access";
import { positionName } from "../lib/staff-position";
import { staffIdentity } from "../lib/staff-identity";

export function AccessManagement({ canManage, initialData, profiles, referenceTime }: { canManage: boolean; initialData: AccessManagementData; profiles: ManagedProfile[]; referenceTime: string }) {
  const [data, setData] = useState(initialData);
  const [draftPermissions, setDraftPermissions] = useState<Record<number, string[]>>(() => Object.fromEntries(
    initialData.positions.map((position) => [position.id, initialData.positionPermissions.filter((item) => item.position_id === position.id).map((item) => item.permission_code)]),
  ));
  const [grantKind, setGrantKind] = useState<"individual" | "temporary">("individual");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<{ kind: "error" | "success"; text: string } | null>(null);
  const activeGrants = useMemo(() => data.grants.filter((grant) => !grant.revoked_at && (grant.expires_at === null || grant.expires_at > referenceTime)), [data.grants, referenceTime]);
  const manageableProfiles = profiles.filter((profile) => {
    const position = data.positions.find((item) => item.id === profile.position_id);
    return position?.level !== null && position?.level !== 14 && profile.status !== "inactive";
  });
  const permissionGroups = useMemo(() => {
    const groups = data.permissions.reduce<Record<string, SystemPermission[]>>((result, permission) => {
      (result[permission.module] ??= []).push(permission);
      return result;
    }, {});
    return Object.entries(groups);
  }, [data.permissions]);

  async function savePermissions(positionId: number) {
    if (loading) return;
    setLoading(true); setMessage(null);
    try {
      const response = await fetch("/api/access/positions", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "permissions", positionId, permissionCodes: draftPermissions[positionId] ?? [] }) });
      const payload = (await response.json()) as { error?: string };
      if (!response.ok) { setMessage({ kind: "error", text: payload.error ?? "Não foi possível salvar as permissões." }); return; }
      setData((current) => ({ ...current, positionPermissions: [
        ...current.positionPermissions.filter((item) => item.position_id !== positionId),
        ...(draftPermissions[positionId] ?? []).map((permission_code) => ({ permission_code, position_id: positionId })),
      ] }));
      setMessage({ kind: "success", text: "Pacote padrão do cargo atualizado." });
    } catch { setMessage({ kind: "error", text: "Não foi possível salvar as permissões." }); }
    finally { setLoading(false); }
  }

  async function grantPermission(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (loading) return;
    const form = event.currentTarget;
    const values = new FormData(form);
    setLoading(true); setMessage(null);
    try {
      const response = await fetch("/api/access/grants", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({
        action: "grant",
        grantKind,
        expiresAt: grantKind === "temporary" ? values.get("expiresAt") : null,
        permissionCode: values.get("permissionCode"),
        reason: values.get("reason"),
        userId: values.get("userId"),
      }) });
      const payload = (await response.json()) as { error?: string; grant?: AccessManagementData["grants"][number] };
      if (!response.ok || !payload.grant) { setMessage({ kind: "error", text: payload.error ?? "Não foi possível conceder a permissão." }); return; }
      setData((current) => ({ ...current, grants: [payload.grant!, ...current.grants] }));
      form.reset();
      setMessage({ kind: "success", text: grantKind === "temporary" ? "Permissão temporária concedida; ela expirará automaticamente." : "Exceção individual concedida." });
    } catch { setMessage({ kind: "error", text: "Não foi possível conceder a permissão." }); }
    finally { setLoading(false); }
  }

  async function revoke(grantId: number) {
    const reason = window.prompt("Informe o motivo para encerrar esta permissão:");
    if (!reason || reason.trim().length < 10 || loading) return;
    setLoading(true); setMessage(null);
    try {
      const response = await fetch("/api/access/grants", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "revoke", grantId, reason }) });
      const payload = (await response.json()) as { error?: string; grant?: AccessManagementData["grants"][number] };
      if (!response.ok || !payload.grant) { setMessage({ kind: "error", text: payload.error ?? "Não foi possível encerrar a permissão." }); return; }
      setData((current) => ({ ...current, grants: current.grants.map((grant) => grant.id === grantId ? payload.grant! : grant) }));
      setMessage({ kind: "success", text: "Permissão encerrada e preservada no histórico." });
    } catch { setMessage({ kind: "error", text: "Não foi possível encerrar a permissão." }); }
    finally { setLoading(false); }
  }

  function togglePermission(positionId: number, permissionCode: string) {
    setDraftPermissions((current) => {
      const values = current[positionId] ?? [];
      return { ...current, [positionId]: values.includes(permissionCode) ? values.filter((code) => code !== permissionCode) : [...values, permissionCode] };
    });
  }

  return (
    <div className="access-management">
      {message ? <p className={message.kind === "success" ? "form-success" : "form-error"} role="status">{message.text}</p> : null}
      <section className="management-card access-position-card">
        <div className="section-title"><div><p className="eyebrow">Cargo fornece o padrão</p><h2>Cargos e níveis de acesso</h2></div><span className="count-pill">{data.positions.length}</span></div>
        <p className="hr-card-intro">A hierarquia médica mantém 14 níveis; categorias institucionais externas ficam sem nível e fora da carreira.</p>
        <div className="access-position-list">
          {data.positions.map((position) => <details key={position.id}><summary><span><b>{position.level ?? "EXT"}</b><strong>{position.name}</strong></span><small>{(draftPermissions[position.id] ?? []).length} permissão(ões) · {advancementLabel(position.advancement_mode)}</small></summary>
            <div className="access-permission-sections">{permissionGroups.map(([module, permissions]) => <fieldset key={module}><legend>{module}</legend><div className="access-permission-grid">{permissions.map((permission) => <label key={permission.code}><input disabled={!canManage || position.advancement_mode === "external"} type="checkbox" checked={(draftPermissions[position.id] ?? []).includes(permission.code)} onChange={() => togglePermission(position.id, permission.code)} /><span><strong>{permission.label}</strong><small>{permission.description}</small></span></label>)}</div></fieldset>)}</div>
            {canManage && position.advancement_mode !== "external" ? <button className="secondary-button" type="button" disabled={loading} onClick={() => savePermissions(position.id)}>Salvar pacote deste cargo</button> : <p className="hr-card-intro">{position.advancement_mode === "external" ? "Pacote protegido para preservar a separação do quadro médico." : "Visualização somente leitura."}</p>}
          </details>)}
        </div>
      </section>

      <section className="management-card temporary-access-card">
        <div className="section-title"><div><p className="eyebrow">Exceções sem alterar o cargo</p><h2>Permissões individuais</h2></div><span className="count-pill">{activeGrants.length}</span></div>
        {canManage ? <><div className="access-kind-switch" role="group" aria-label="Tipo de concessão"><button type="button" data-active={grantKind === "individual"} onClick={() => setGrantKind("individual")}>Permanente</button><button type="button" data-active={grantKind === "temporary"} onClick={() => setGrantKind("temporary")}>Temporária</button></div>
        <form className="temporary-access-form" onSubmit={grantPermission}>
          <label>Profissional<select name="userId" required defaultValue=""><option value="" disabled>Selecione</option>{manageableProfiles.map((profile) => <option key={profile.user_id} value={profile.user_id}>{profile.display_name} · {staffIdentity(profile.passport, positionName(profile, data.positions))}</option>)}</select></label>
          <label>Permissão<select name="permissionCode" required defaultValue=""><option value="" disabled>Selecione</option>{data.permissions.filter((permission) => !["access.manage", "access.grants.manage", "succession.manage", "settings.critical"].includes(permission.code)).map((permission) => <option key={permission.code} value={permission.code}>{permission.label}</option>)}</select></label>
          {grantKind === "temporary" ? <label>Válida até<input name="expiresAt" type="datetime-local" min={localDateTimeMin()} required /></label> : <div className="access-permanent-note"><strong>Sem data de expiração</strong><span>Válida até revogação administrativa.</span></div>}
          <label className="temporary-reason">Motivo ou observação <small>Opcional</small><textarea name="reason" maxLength={1000} rows={3} placeholder="Contexto da concessão, se necessário." /></label>
          <button className="submit-button" disabled={loading} type="submit">Conceder permissão</button>
        </form></> : <p className="hr-card-intro">Consulta das exceções atualmente vigentes, sem permissão para conceder ou revogar acessos.</p>}
        <div className="temporary-access-list">{activeGrants.map((grant) => <article key={grant.id}><div><strong>{profileIdentity(grant.user_id, profiles, data)}</strong><span>{permissionName(grant.permission_code, data)}</span><small>{grant.grant_kind === "individual" ? "Individual · sem expiração" : `Temporária · até ${formatDateTime(grant.expires_at!)}`} · concedida por {profileIdentity(grant.granted_by, profiles, data)}</small></div>{canManage ? <button className="table-action" type="button" disabled={loading} onClick={() => revoke(grant.id)}>Encerrar</button> : <span>Somente leitura</span>}</article>)}{!activeGrants.length ? <div className="compact-empty"><span>✓</span><strong>Nenhuma exceção ativa</strong><p>Todos os acessos seguem apenas o pacote padrão do cargo.</p></div> : null}</div>
      </section>
    </div>
  );
}

function profileIdentity(userId: string, profiles: ManagedProfile[], data: AccessManagementData) {
  const profile = profiles.find((item) => item.user_id === userId);
  return profile ? `${profile.display_name} · ${staffIdentity(profile.passport, positionName(profile, data.positions))}` : "Profissional";
}
function permissionName(code: string, data: AccessManagementData) { return data.permissions.find((permission) => permission.code === code)?.label ?? code; }
function advancementLabel(mode: string) { return mode === "progression" ? "Progressão" : mode === "appointment" ? "Nomeação" : mode === "external" ? "Institucional externo" : "Sucessão"; }
function localDateTimeMin() { const date = new Date(Date.now() + 15 * 60_000); const offset = date.getTimezoneOffset() * 60_000; return new Date(date.getTime() - offset).toISOString().slice(0, 16); }
function formatDateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
