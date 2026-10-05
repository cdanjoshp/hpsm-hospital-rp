"use client";

import { useRouter } from "next/navigation";
import { useCallback } from "react";

export function useAppRefresh() {
  const router = useRouter();
  return useCallback((delay = 0) => {
    const refresh = () => {
      window.dispatchEvent(new Event("hpsm:shell-refresh"));
      router.refresh();
    };
    if (delay > 0) window.setTimeout(refresh, delay);
    else refresh();
  }, [router]);
}
