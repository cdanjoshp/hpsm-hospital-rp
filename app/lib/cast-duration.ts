export const CAST_DURATION_DAYS = [1, 2, 3, 4, 5] as const;
export type CastDurationDays = (typeof CAST_DURATION_DAYS)[number];

const DAY_MS = 24 * 60 * 60 * 1000;

export function isCastDurationDays(value: unknown): value is CastDurationDays {
  return typeof value === "number" && Number.isInteger(value) && value >= 1 && value <= 5;
}

export function expectedCastRemovalAt(appliedAt: string, days: CastDurationDays): string | null {
  const applied = Date.parse(appliedAt);
  return Number.isFinite(applied) ? new Date(applied + days * DAY_MS).toISOString() : null;
}

export function castDurationDays(appliedAt: string, expectedRemovalAt: string): CastDurationDays | null {
  const duration = (Date.parse(expectedRemovalAt) - Date.parse(appliedAt)) / DAY_MS;
  return isCastDurationDays(duration) ? duration : null;
}
