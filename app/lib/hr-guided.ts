export type GuidedWeekSegment = {
  baselineDate: string | null;
  endDate: string;
  referenceMonth: string;
};

export function getGuidedWeekSegments(weekStart: string, throughDate: string): GuidedWeekSegment[] {
  const weekEnd = addIsoDays(weekStart, 6);
  const effectiveEnd = throughDate < weekEnd ? throughDate : weekEnd;
  const segments: GuidedWeekSegment[] = [];
  let referenceMonth = isoMonthStart(weekStart);
  const finalMonth = isoMonthStart(effectiveEnd);

  while (referenceMonth <= finalMonth) {
    const periodStart = weekStart > referenceMonth ? weekStart : referenceMonth;
    const monthEnd = addIsoDays(addIsoMonths(referenceMonth, 1), -1);
    const endDate = effectiveEnd < monthEnd ? effectiveEnd : monthEnd;
    segments.push({
      baselineDate: periodStart === referenceMonth ? null : addIsoDays(periodStart, -1),
      endDate,
      referenceMonth,
    });
    referenceMonth = addIsoMonths(referenceMonth, 1);
  }

  return segments;
}

export function calculateGuidedWeekMinutes(
  segments: GuidedWeekSegment[],
  getTotal: (date: string) => number | null,
) {
  let total = 0;
  for (const segment of segments) {
    const baseline = segment.baselineDate ? getTotal(segment.baselineDate) : 0;
    const current = getTotal(segment.endDate);
    if (baseline === null || current === null) return { complete: false, invalid: false, minutes: 0 };
    if (current < baseline) return { complete: true, invalid: true, minutes: 0 };
    total += current - baseline;
  }
  return { complete: true, invalid: false, minutes: total };
}

export function clockValueToMinutes(value: string) {
  const match = value.trim().match(/^([0-9]{1,3}):([0-5][0-9])$/);
  if (!match) return null;
  const minutes = Number(match[1]) * 60 + Number(match[2]);
  return minutes <= 60000 ? minutes : null;
}

export function minutesToClockValue(minutes: number) {
  const safe = Math.max(0, Math.round(minutes));
  return `${Math.floor(safe / 60)}:${String(safe % 60).padStart(2, "0")}`;
}

export function normalizeClockInput(value: string) {
  const digits = value.replace(/\D/g, "").slice(0, 5);
  if (digits.length <= 2) return digits;
  return `${digits.slice(0, -2)}:${digits.slice(-2)}`;
}

export function addIsoDays(value: string, days: number) {
  const date = new Date(`${value}T00:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

export function isoMonthStart(value: string) {
  return `${value.slice(0, 7)}-01`;
}

function addIsoMonths(value: string, months: number) {
  const date = new Date(`${isoMonthStart(value)}T00:00:00.000Z`);
  date.setUTCMonth(date.getUTCMonth() + months);
  return date.toISOString().slice(0, 10);
}

