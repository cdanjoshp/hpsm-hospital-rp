export const HPSM_PHONE_PREFIX = "(055) ";
export const HPSM_PHONE_PATTERN = /^\(055\) [0-9]{3}-[0-9]{3}$/;

export function formatHpsmPhoneInput(value: string) {
  const digits = value.replace(/\D/g, "");
  const localDigits = (digits.startsWith("055")
    ? digits.slice(3)
    : digits.length > 6
      ? digits.slice(-6)
      : digits).slice(0, 6);

  if (!localDigits.length) return value ? HPSM_PHONE_PREFIX : "";
  if (localDigits.length <= 3) return `${HPSM_PHONE_PREFIX}${localDigits}`;
  return `${HPSM_PHONE_PREFIX}${localDigits.slice(0, 3)}-${localDigits.slice(3)}`;
}

export function ensureHpsmPhonePrefix(value: string) {
  return value || HPSM_PHONE_PREFIX;
}

export function isValidHpsmPhone(value: string) {
  return HPSM_PHONE_PATTERN.test(value);
}

export function clearOptionalHpsmPhonePrefix(value: string) {
  return value.trim() === HPSM_PHONE_PREFIX.trim() ? "" : value;
}

export type OptionalHpsmPhone = {
  error: string | null;
  phone: string | null;
};

export function parseOptionalHpsmPhone(value: string): OptionalHpsmPhone {
  const trimmedPhone = value.trim();
  const normalizedPhone = trimmedPhone === HPSM_PHONE_PREFIX.trim() ? "" : trimmedPhone;

  if (!normalizedPhone) return { error: null, phone: null };
  if (!isValidHpsmPhone(normalizedPhone)) {
    return {
      error: "Informe o telefone de contato no formato (055) 123-456 ou deixe o campo em branco.",
      phone: null,
    };
  }
  return { error: null, phone: normalizedPhone };
}

export type OptionalEmergencyContact = {
  error: string | null;
  name: string | null;
  phone: string | null;
};

export function parseOptionalEmergencyContact(name: string, phone: string): OptionalEmergencyContact {
  const normalizedName = name.trim();
  const trimmedPhone = phone.trim();
  const normalizedPhone = trimmedPhone === HPSM_PHONE_PREFIX.trim() ? "" : trimmedPhone;

  if (!normalizedName && !normalizedPhone) {
    return { error: null, name: null, phone: null };
  }
  if (!normalizedName || !normalizedPhone) {
    return {
      error: "Informe o nome e o telefone do contato de emergência ou deixe os dois campos em branco.",
      name: null,
      phone: null,
    };
  }
  if (normalizedName.length < 2 || normalizedName.length > 100) {
    return {
      error: "O nome do contato de emergência deve ter entre 2 e 100 caracteres.",
      name: null,
      phone: null,
    };
  }
  if (!isValidHpsmPhone(normalizedPhone)) {
    return {
      error: "Informe o telefone de emergência no formato (055) 123-456 ou deixe o contato em branco.",
      name: null,
      phone: null,
    };
  }
  return { error: null, name: normalizedName, phone: normalizedPhone };
}
