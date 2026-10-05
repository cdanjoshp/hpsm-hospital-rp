"use client";

import { useEffect } from "react";

/**
 * Pages restored from the browser back-forward cache can contain an old patient
 * tree even after logout or after another patient signs in. Force a fresh
 * server render before that tree becomes usable again.
 */
export function PatientPortalSessionGuard() {
  useEffect(() => {
    function refreshRestoredPage(event: PageTransitionEvent) {
      if (!event.persisted) return;
      document.documentElement.dataset.patientPortalRestoring = "true";
      window.location.replace(window.location.href);
    }

    window.addEventListener("pageshow", refreshRestoredPage);
    return () => window.removeEventListener("pageshow", refreshRestoredPage);
  }, []);

  return null;
}
