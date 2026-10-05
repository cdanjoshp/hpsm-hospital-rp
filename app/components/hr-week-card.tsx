import type { WeeklyProgress } from "../lib/hr";

export function HrWeekCard({ progress }: { progress: WeeklyProgress }) {
  const remaining = progress.remainingDeficitMinutes;
  const percent = progress.requiredMinutes === 0 ? 100 : Math.min(100, Math.round((progress.workedMinutes / progress.requiredMinutes) * 100));
  return (
    <article className="hr-week-card" data-status={progress.status}>
      <header>
        <div><span className="hr-week-icon" aria-hidden="true">◷</span><p>Objetivo no contador da cidade</p><strong>{formatMinutes(progress.counterTargetMinutes)}</strong></div>
        <em>{statusLabel(progress.status, remaining)}</em>
      </header>
      <div className="hr-week-details">
        <span>Atual <strong>{formatMinutes(progress.monthlyAccumulated)}</strong></span>
        <span>Semana <strong>{formatMinutes(progress.workedMinutes)} / {formatMinutes(progress.requiredMinutes)}</strong> · {percent}%</span>
      </div>
      <div className="hr-week-progress" aria-label={`${percent}% da meta semanal`}>
        <span style={{ width: `${percent}%` }} />
      </div>
      <footer>
        <span>Meta semanal oficial <strong>{formatMinutes(progress.baseRequiredMinutes)}</strong></span>
        {progress.leaveDeductionMinutes ? <span>Afastamento <strong>−{formatMinutes(progress.leaveDeductionMinutes)}</strong></span> : null}
        {progress.justificationMinutes ? <span>Abonado <strong>{formatMinutes(progress.justificationMinutes)}</strong></span> : null}
        <span>ADV <strong>{progress.warningCount}/3</strong></span>
        <small>{formatShortDate(progress.weekStart)} a {formatShortDate(progress.weekEnd)} · {progress.latestUpdate ? `atualizado ${formatDateTime(progress.latestUpdate)}` : "aguardando leitura"}</small>
      </footer>
    </article>
  );
}

function statusLabel(status: WeeklyProgress["status"], remaining: number) {
  if (status === "met") return "Meta cumprida";
  if (status === "justified") return "Semana com justificativa aprovada";
  if (status === "awaiting_justification") return `Déficit de ${formatMinutes(remaining)} · envie sua justificativa`;
  if (status === "justification_pending") return "Justificativa aguardando análise";
  if (status === "deficit") return `Déficit mantido: ${formatMinutes(remaining)}`;
  if (status === "awaiting_hours") return "Aguardando atualização das horas";
  return `Faltam ${formatMinutes(remaining)}`;
}

function formatMinutes(total: number | null) {
  if (total === null || !Number.isFinite(total)) return "—";
  const safe = Math.max(0, Math.round(total));
  return `${Math.floor(safe / 60)}h${String(safe % 60).padStart(2, "0")}`;
}

function formatShortDate(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", timeZone: "UTC" })
    .format(new Date(`${value}T00:00:00Z`));
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat("pt-BR", {
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    month: "2-digit",
    timeZone: "America/Sao_Paulo",
  }).format(new Date(value));
}
