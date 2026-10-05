const ISO_DATE_PATTERN = /^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;

export function normalizeBirthDate(value: unknown) {
  if (typeof value !== "string") throw new Error("birth_date");
  const normalized = value.trim();
  if (!isValidBirthDate(normalized)) throw new Error("birth_date");
  return normalized;
}

export function isValidBirthDate(value: string) {
  if (!ISO_DATE_PATTERN.test(value)) return false;
  const [year, month, day] = value.split("-").map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) return false;
  return value <= todayIso();
}

export function formatBirthDate(value: string | null) {
  if (!value || !ISO_DATE_PATTERN.test(value)) return "Não informada";
  const [year, month, day] = value.split("-");
  return `${day}/${month}/${year}`;
}

export function todayIso() {
  const today = new Date();
  return [
    today.getUTCFullYear().toString().padStart(4, "0"),
    String(today.getUTCMonth() + 1).padStart(2, "0"),
    String(today.getUTCDate()).padStart(2, "0"),
  ].join("-");
}
