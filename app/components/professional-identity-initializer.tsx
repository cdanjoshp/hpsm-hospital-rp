"use client";

import { useEffect } from "react";

export function ProfessionalIdentityInitializer() {
  useEffect(() => {
    const controller = new AbortController();
    void fetch("/api/professional-identity", {
      body: JSON.stringify({ action: "ensure" }),
      cache: "no-store",
      headers: { "content-type": "application/json" },
      method: "POST",
      signal: controller.signal,
    }).catch(() => undefined);
    return () => controller.abort();
  }, []);
  return null;
}
