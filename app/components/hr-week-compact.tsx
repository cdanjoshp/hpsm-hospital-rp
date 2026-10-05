import Link from "next/link";
import type { WeeklyProgress } from "../lib/hr";

export function HrWeekCompact({ progress }: { progress: WeeklyProgress }) {
  const percent = progress.requiredMinutes === 0 ? 100 : Math.min(100, Math.round((progress.workedMinutes / progress.requiredMinutes) * 100));
  return <Link className="hr-week-compact" data-status={progress.status} href="/meu-rh" aria-label={`Objetivo no contador da cidade: ${formatMinutes(progress.counterTargetMinutes)}. Atual: ${formatMinutes(progress.monthlyAccumulated)}. Semana: ${formatMinutes(progress.workedMinutes)} de ${formatMinutes(progress.requiredMinutes)}, ${percent}%`}>
    <span className="hr-week-compact-icon" aria-hidden="true">◷</span>
    <span className="hr-week-compact-copy"><small>Objetivo no contador</small><strong>{formatMinutes(progress.counterTargetMinutes)} <em>· atual {formatMinutes(progress.monthlyAccumulated)}</em></strong><em>Semana {formatMinutes(progress.workedMinutes)} / {formatMinutes(progress.requiredMinutes)} · {percent}%</em><i><b style={{ width: `${percent}%` }} /></i></span>
    {progress.remainingDeficitMinutes > 0 && progress.status !== "in_progress" ? <mark>{formatMinutes(progress.remainingDeficitMinutes)}</mark> : null}
  </Link>;
}

function formatMinutes(total: number | null) { if (total === null || !Number.isFinite(total)) return "—"; const safe = Math.max(0, Math.round(total)); return `${Math.floor(safe / 60)}h${String(safe % 60).padStart(2, "0")}`; }
