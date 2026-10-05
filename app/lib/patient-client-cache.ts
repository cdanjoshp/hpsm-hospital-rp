const PATIENT_CACHE_VERSION_KEY = "hpsm-patient-version";

export function readPatientCacheVersion() {
  if (typeof window === "undefined") return "server";
  try { return window.localStorage.getItem(PATIENT_CACHE_VERSION_KEY) ?? "initial"; } catch { return "unavailable"; }
}

export function invalidatePatientClientCache() {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(PATIENT_CACHE_VERSION_KEY, `${Date.now()}:${crypto.randomUUID()}`);
  } catch {
    // A busca expira em 60 segundos mesmo quando o armazenamento local está indisponível.
  }
}
