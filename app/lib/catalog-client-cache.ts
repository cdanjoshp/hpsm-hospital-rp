const CATALOG_CACHE_VERSION_KEY = "hpsm-catalog-version";

export function readCatalogCacheVersion() {
  if (typeof window === "undefined") return "server";
  try { return window.localStorage.getItem(CATALOG_CACHE_VERSION_KEY) ?? "initial"; } catch { return "unavailable"; }
}

export function invalidateCatalogClientCache() {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(CATALOG_CACHE_VERSION_KEY, `${Date.now()}:${crypto.randomUUID()}`);
  } catch {
    // O cache expira em 60 segundos mesmo quando o armazenamento local está indisponível.
  }
}
