import type { CareerSelfData } from "../lib/career";

export function CareerSelfPanel({ initialData }: { initialData: CareerSelfData }) {
  const progression = initialData.progression;

  return <section className="career-self-section">
    <div className="career-self-grid career-self-primary" data-single="true">
      <article className="management-card career-current-card">
        <div className="section-title"><div><p className="eyebrow">Carreira</p><h2>{initialData.position?.name ?? "Cargo não definido"}</h2></div><span className="career-level">{initialData.position ? initialData.position.level : "—"}</span></div>
        {progression.level && progression.level <= 9 ? <><p className="career-next-position">Próximo cargo: <strong>{progression.next_position_name}</strong></p><div className="career-self-metrics"><Requirement label="Dias" current={progression.elapsed_days ?? 0} target={progression.required_days ?? 15} /><Requirement label="Horas" current={progression.worked_minutes ?? 0} target={progression.required_worked_minutes ?? 1800} minutes /><Requirement label="Atendimentos" current={progression.attendance_count ?? 0} target={progression.required_attendances ?? 3} /></div><div className="career-eligibility" data-status={progression.blocked ? "blocked" : progression.eligible ? "eligible" : "progress"}><strong>{progression.blocked ? "Progressão bloqueada" : progression.eligible ? "Elegível para análise de promoção" : "Requisitos em andamento"}</strong><span>{progression.flagged_warning_count ? `${progression.flagged_warning_count} advertência(s) sinalizada(s): prazo mínimo de ${progression.required_days} dias.` : "A promoção depende de análise e nunca acontece automaticamente."}</span></div></> : <p className="hr-card-intro">{progression.reason ?? "Este cargo segue o fluxo de nomeação da hierarquia."}</p>}
      </article>
    </div>

    <div className="career-self-grid career-self-records">
      <article className="management-card">
        <div className="section-title"><div><p className="eyebrow">Formação no RP</p><h2>Meus cursos</h2></div><span className="count-pill">{initialData.courseRecords.length}</span></div>
        <div className="course-record-list">{initialData.courseRecords.map((record) => <article key={record.id}><div><strong>{initialData.courses.find((course) => course.id === record.course_id)?.name ?? "Curso"}</strong><span>{record.status === "completed" && record.completed_at ? `Concluído em ${formatDate(record.completed_at)}` : `Vinculado em ${formatDate(record.assigned_at)}`}</span></div><em data-status={record.status}>{record.status === "completed" ? "Concluído" : "Pendente"}</em></article>)}{!initialData.courseRecords.length ? <Empty text="Nenhum curso foi vinculado ao seu perfil." /> : null}</div>
      </article>
      <article className="management-card">
        <div className="section-title"><div><p className="eyebrow">Histórico permanente</p><h2>Movimentações de cargo</h2></div><span className="count-pill">{initialData.history.length}</span></div>
        <div className="position-history-list">{initialData.history.map((history) => <article key={history.id}><span>{history.event_type === "promotion" ? "↑" : history.event_type === "initial_assignment" ? "•" : "★"}</span><div><strong>{positionName(history.to_position_id, initialData)}</strong><small>{eventLabel(history.event_type)} · {formatDate(history.effective_at)}</small>{history.note ? <p>{history.note}</p> : null}</div></article>)}</div>
      </article>
    </div>
  </section>;
}

function Requirement({ current, label, minutes = false, target }: { current: number; label: string; minutes?: boolean; target: number }) { const done = current >= target; return <span data-ok={done}><b>{minutes ? formatMinutes(current) : current}/{minutes ? formatMinutes(target) : target}</b><small>{label}</small></span>; }
function Empty({ text }: { text: string }) { return <div className="compact-empty"><span>◇</span><strong>Nenhum registro</strong><p>{text}</p></div>; }
function positionName(id: number, data: CareerSelfData) { return data.positions.find((position) => position.id === id)?.name ?? "Cargo"; }
function eventLabel(value: string) { return ({ initial_assignment: "Ingresso", promotion: "Promoção", appointment: "Nomeação", succession: "Sucessão", override: "Alteração direta da Direção Geral" } as Record<string, string>)[value] ?? value; }
function formatMinutes(total: number) { return `${Math.floor(total / 60)}h${String(total % 60).padStart(2, "0")}`; }
function formatDate(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
