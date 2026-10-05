export const PASSPORT_PATTERN = /^[0-9]{1,4}$/;

export const PATIENT_PASSPORT_PATTERN = /^[0-9]{4}$/;

export function sanitizePassportInput(value: string) {
  return value.replace(/\D/g, "").slice(0, 4);
}

export function normalizePatientPassport(value: string) {
  const normalized = value.trim();
  if (!PASSPORT_PATTERN.test(normalized)) {
    throw new Error("Informe um passaporte válido com 1 a 4 números.");
  }
  return normalized.padStart(4, "0");
}

export function normalizePatientSearch(value: string | null | undefined) {
  const normalized = value?.trim() ?? "";
  if (!normalized) return null;
  return PASSPORT_PATTERN.test(normalized) ? normalizePatientPassport(normalized) : normalized;
}

export function formatPatientPassport(value: string | null | undefined) {
  const normalized = value?.trim() ?? "";
  return PASSPORT_PATTERN.test(normalized) ? normalized.padStart(4, "0") : normalized || "—";
}
