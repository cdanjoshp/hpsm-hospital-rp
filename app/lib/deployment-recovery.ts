const RECOVERY_STORAGE_KEY = "hpsm:deployment-recovery";
const RECOVERY_GUARD_MS = 60_000;

const RECOVERY_ATTEMPT = `
  const recoveryKey = ${JSON.stringify(RECOVERY_STORAGE_KEY)};
  const recoveryGuardMs = ${RECOVERY_GUARD_MS};
  const now = Date.now();
  let lastRecovery = 0;
  try { lastRecovery = Number(window.sessionStorage.getItem(recoveryKey) || 0); } catch {}
  if (!lastRecovery || now - lastRecovery > recoveryGuardMs) {
    try { window.sessionStorage.setItem(recoveryKey, String(now)); } catch {}
    window.location.replace(window.location.href);
    return true;
  }
  return false;
`;

export const DEPLOYMENT_RECOVERY_BOOTSTRAP_SCRIPT = `
(() => {
  if (window.__hpsmDeploymentRecoveryInstalled) return;
  window.__hpsmDeploymentRecoveryInstalled = true;
  const recover = () => {${RECOVERY_ATTEMPT}};
  window.__hpsmRecoverDeployment = recover;

  window.addEventListener("vite:preloadError", (event) => {
    event.preventDefault();
    recover();
  });

  window.addEventListener("error", (event) => {
    const target = event.target;
    const source = target && (target.src || target.href);
    if (source && String(source).includes("/assets/") && String(source).includes(".js")) recover();
  }, true);

  window.addEventListener("unhandledrejection", (event) => {
    const reason = event.reason;
    const message = String(reason && reason.message ? reason.message : reason || "");
    if (/Failed to fetch dynamically imported module|Importing a module script failed|ChunkLoadError|Load failed|\\/assets\\/.*\\.js/i.test(message)) {
      event.preventDefault();
      recover();
    }
  });
})();
`;

export const STALE_ASSET_RECOVERY_MODULE_SCRIPT = `
(() => {${RECOVERY_ATTEMPT}})();
export default {};
`;
