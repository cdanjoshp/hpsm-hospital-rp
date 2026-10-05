"use client";

import Link from "next/link";
import { FormEvent, useMemo, useState } from "react";
import type { CareerAdminData } from "../lib/career";
import { useAppRefresh } from "../lib/client-refresh";
import { staffIdentity } from "../lib/staff-identity";

export function CareerManagement({ actorId, initialData, permissionCodes }: { actorId: string; initialData: CareerAdminData; permissionCodes: string[] }) {
  const refreshApp = useAppRefresh();
  const permissions = useMemo(() => new Set(permissionCodes), [permissionCodes]);
  const courses = initialData.courses;
  const courseRecords = initialData.courseRecords;
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<{ kind: "error" | "success"; text: string } | null>(null);
  const activeReviews = initialData.reviews.filter((review) => review.status === "pending" || review.status === "deferred");
  const appointmentCandidates = initialData.profiles.filter((profile) => {
    const level = position(profile.position_id)?.level ?? 0;
    return profile.status === "active" && level >= 10 && level < 14 && profile.user_id !== actorId;
  });
  const unassignedProfiles = initialData.profiles.filter((profile) => profile.position_id === null && profile.status !== "inactive");

  function position(id: number | null) { return initialData.positions.find((item) => item.id === id); }
  function profileIdentity(id: string) {
    const profile = initialData.profiles.find((item) => item.user_id === id);
    return profile ? `${profile.display_name} · ${staffIdentity(profile.passport, position(profile.position_id)?.name)}` : "Profissional";
  }

  async function decidePromotion(reviewId: number, decision: "promoted" | "deferred") {
    if (loading) return;
    const note = window.prompt(decision === "promoted" ? "Observação da promoção (opcional):" : "Por que a promoção não será realizada agora? (opcional):") ?? "";
    if (note.length > 2000) return;
    setLoading(true); setMessage(null);
    try {
      const response = await jsonRequest("/api/career/promotions", { decision, note, reviewId });
      if (!response.ok) throw new Error(response.error);
      setMessage({ kind: "success", text: decision === "promoted" ? "Promoção registrada sem salto de cargo." : "Decisão preservada; o colaborador não foi promovido." });
      refreshApp(600);
    } catch (error) { setMessage({ kind: "error", text: error instanceof Error ? error.message : "Não foi possível decidir a promoção." }); }
    finally { setLoading(false); }
  }

  async function appoint(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (loading) return;
    const form = event.currentTarget; const values = new FormData(form);
    setLoading(true); setMessage(null);
    try {
      const response = await jsonRequest("/api/career/appointments", { employeeId: values.get("employeeId"), note: values.get("note"), positionId: Number(values.get("positionId")) });
      if (!response.ok) throw new Error(response.error);
      setMessage({ kind: "success", text: "Nomeação registrada na linha do tempo funcional." }); form.reset();
      refreshApp(600);
    } catch (error) { setMessage({ kind: "error", text: error instanceof Error ? error.message : "Não foi possível nomear." }); }
    finally { setLoading(false); }
  }

  async function assignInitialPosition(employeeId: string) {
    if (loading) return;
    setLoading(true); setMessage(null);
    try {
      const response = await jsonRequest("/api/career/initial-position", { employeeId });
      if (!response.ok) throw new Error(response.error);
      setMessage({ kind: "success", text: "Cargo inicial definido como Estagiário de Enfermagem." });
      refreshApp(500);
    } catch (error) { setMessage({ kind: "error", text: error instanceof Error ? error.message : "Não foi possível definir o cargo inicial." }); }
    finally { setLoading(false); }
  }

  return <div className="career-admin-grid">
    {message ? <p className={message.kind === "success" ? "form-success career-message" : "form-error career-message"} role="status">{message.text}</p> : null}

    {permissions.has("sr.directors.view") ? <section className="management-card career-wide-card">
      <div className="section-title"><div><p className="eyebrow">Consulta institucional</p><h2>Carreira e formação</h2></div><span className="count-pill">{initialData.profiles.length}</span></div>
      <p className="hr-card-intro">Visão somente leitura do quadro médico. Diretores do SR não participam desta carreira, das metas ou das avaliações.</p>
      <div className="course-record-list">{initialData.profiles.map((profile) => <article key={profile.user_id}><div><strong>{profile.display_name}</strong><span>{staffIdentity(profile.passport, position(profile.position_id)?.name)} · {initialData.history.filter((item) => item.employee_id === profile.user_id).length} evento(s) funcionais</span></div><em data-status={profile.status}>{profile.status === "active" ? "Ativo" : profile.status === "suspended" ? "Suspenso" : "Inativo"}</em></article>)}</div>
    </section> : null}

    {permissions.has("progression.review") ? <section className="management-card career-wide-card">
      <div className="section-title"><div><p className="eyebrow">Decisão humana</p><h2>Elegíveis para promoção</h2></div><span className="count-pill">{activeReviews.length}</span></div>
      <p className="hr-card-intro">O sistema apenas comprova os mínimos. Analise o perfil e efetive no máximo um nível por decisão.</p>
      <div className="career-review-list">{activeReviews.map((review) => <article key={review.id}><header><div><strong>{profileIdentity(review.employee_id)}</strong><span>{position(review.from_position_id)?.name} → {position(review.to_position_id)?.name}</span></div><em data-status={review.status}>{review.status === "pending" ? "Aguardando análise" : "Adiada"}</em></header><div className="career-requirements"><span data-ok={review.elapsed_days >= review.required_days}><b>{review.elapsed_days}/{review.required_days}</b> dias</span><span data-ok={review.worked_minutes >= 1800}><b>{formatMinutes(review.worked_minutes)}/30h</b> trabalhadas</span><span data-ok={review.attendance_count >= 3}><b>{review.attendance_count}/3</b> atendimentos</span><span data-ok={review.flagged_warning_count === 0}><b>{review.flagged_warning_count}</b> ADV(s) sinalizada(s)</span></div><footer><button type="button" disabled={loading} onClick={() => decidePromotion(review.id, "promoted")}>Promover um nível</button>{review.status === "pending" ? <button type="button" className="secondary-button" disabled={loading} onClick={() => decidePromotion(review.id, "deferred")}>Não promover agora</button> : null}</footer></article>)}{!activeReviews.length ? <Empty title="Nenhuma promoção pendente" text="Os profissionais elegíveis aparecerão aqui para análise." /> : null}</div>
    </section> : null}

    {permissions.has("access.manage") && unassignedProfiles.length ? <section className="management-card career-wide-card">
      <div className="section-title"><div><p className="eyebrow">Perfis anteriores à hierarquia</p><h2>Definir cargo inicial</h2></div><span className="count-pill">{unassignedProfiles.length}</span></div>
      <p className="hr-card-intro">Para preservar os dados existentes, nenhum cargo foi presumido. Regularize cada perfil no nível 1; depois disso, somente os fluxos oficiais poderão alterar o cargo.</p>
      <div className="course-record-list">{unassignedProfiles.map((profile) => <article key={profile.user_id}><div><strong>{profile.display_name}</strong><span>Passaporte {profile.passport} · cargo ainda não definido</span></div><button className="table-action" type="button" disabled={loading} onClick={() => assignInitialPosition(profile.user_id)}>Definir como Estagiário</button></article>)}</div>
    </section> : null}

    {(permissions.has("appointments.manage") || permissions.has("succession.manage")) ? <section className="management-card">
      <div className="section-title"><div><p className="eyebrow">Níveis 11 a 14</p><h2>Nomeações</h2></div><span>↗</span></div>
      <form className="hr-form" onSubmit={appoint}><label>Profissional<select name="employeeId" required defaultValue=""><option value="" disabled>Selecione</option>{appointmentCandidates.map((profile) => <option key={profile.user_id} value={profile.user_id}>{profile.display_name} · {staffIdentity(profile.passport, position(profile.position_id)?.name)}</option>)}</select></label><label>Próximo cargo<select name="positionId" required defaultValue=""><option value="" disabled>Selecione</option>{initialData.positions.filter((item) => item.level !== null && item.level >= 11).map((item) => <option key={item.id} value={item.id}>{item.level} · {item.name}</option>)}</select></label><label>Fundamentação<textarea name="note" minLength={10} maxLength={2000} rows={4} required placeholder="Registre o motivo da nomeação." /></label><button className="submit-button" disabled={loading}>Registrar nomeação</button></form>
      <p className="hr-card-intro">O banco impedirá saltos e aplicará: 13–14 nomeiam Médico Chefe/Diretor Administrativo; somente 14 nomeia Diretor Executivo ou outro Diretor Geral.</p>
    </section> : null}

    {(permissions.has("courses.manage") || permissions.has("courses.completions.manage")) ? <section className="management-card career-wide-card">
      <div className="section-title"><div><p className="eyebrow">Formação</p><h2>Academia HPSM</h2></div></div>
      <p className="hr-card-intro">Cursos, aulas e notas são administrados na Academia. Os registros antigos de carreira permanecem abaixo para consulta.</p>
      {permissions.has("courses.academy.manage") ? <Link className="submit-button" href="/academia/gestao" prefetch={false}>Abrir gestão da Academia</Link> : null}
      {courseRecords.length ? <div className="course-record-list">{courseRecords.slice(0,20).map((record) => <article key={record.id}><div><strong>{profileIdentity(record.employee_id)}</strong><span>{courses.find((item) => item.id === record.course_id)?.name ?? "Curso"}</span></div><em data-status={record.status}>{record.status === "completed" ? "Concluído" : "Pendente"}</em></article>)}</div> : null}
    </section> : null}
  </div>;
}

async function jsonRequest(url: string, body: Record<string, unknown>): Promise<Record<string, unknown> & { error?: string; ok: boolean }> {
  const response = await fetch(url, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
  const payload = (await response.json()) as Record<string, unknown> & { error?: string };
  return { ...payload, ok: response.ok };
}
function Empty({ text, title }: { text: string; title: string }) { return <div className="compact-empty"><span>◇</span><strong>{title}</strong><p>{text}</p></div>; }
function formatMinutes(total: number) { return `${Math.floor(total / 60)}h${String(total % 60).padStart(2, "0")}`; }
