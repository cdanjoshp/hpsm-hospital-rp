export const RP_FREQUENCY_OPTIONS = [
  "1x/dia",
  "2x/dia",
  "3x/dia",
  "4x/dia",
  "a cada 24 horas",
  "a cada 12 horas",
  "a cada 8 horas",
  "a cada 6 horas",
  "a cada 4 horas",
] as const;

const OPTIONAL_USE_PATTERN = /\b(?:(?:se|quando|caso)\s+necess[aá]ri[oa]s?|conforme\s+(?:a\s+)?necessidade|sob\s+demanda|prn)\b/i;

export function hasOptionalMedicationUse(value: string) {
  return OPTIONAL_USE_PATTERN.test(value);
}

export function rpDosesPerDay(frequency: string) {
  const normalized = frequency.trim().toLowerCase().replace(/\s+/g, " ");
  const times = normalized.match(/(?:^|\D)([1-9]|1\d|2[0-4])\s*x\s*\/?\s*dia/);
  if (times) return Number(times[1]);
  const interval = normalized.match(/(?:^|\D)(24|12|8|6|4)\s*\/\s*\1\s*h/)
    ?? normalized.match(/a cada\s+(24|12|8|6|4)\s+hora/);
  if (!interval) return null;
  return 24 / Number(interval[1]);
}

export function calculateRpQuantity(frequency: string, durationDays: number) {
  if (hasOptionalMedicationUse(frequency)) return null;
  const dosesPerDay = rpDosesPerDay(frequency);
  if (!dosesPerDay || !Number.isSafeInteger(durationDays) || durationDays < 1 || durationDays > 365) return null;
  const quantity = dosesPerDay * durationDays;
  if (!Number.isSafeInteger(quantity) || quantity < 1 || quantity > 1_000) return null;
  return {
    dosesPerDay,
    quantity,
  };
}
