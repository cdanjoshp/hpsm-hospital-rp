"use client";

import dynamic from "next/dynamic";
import { useCallback, useEffect, useRef, useState } from "react";

const GlobalSearchPalette = dynamic(
  () => import("./global-search-palette").then((module) => module.GlobalSearchPalette),
  { ssr: false },
);

export function GlobalSearchLauncher() {
  const [open, setOpen] = useState(false);
  const triggerRef = useRef<HTMLButtonElement>(null);

  const close = useCallback(() => {
    setOpen(false);
    window.setTimeout(() => triggerRef.current?.focus(), 0);
  }, []);

  useEffect(() => {
    function handleShortcut(event: KeyboardEvent) {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setOpen(true);
      }
    }
    window.addEventListener("keydown", handleShortcut);
    return () => window.removeEventListener("keydown", handleShortcut);
  }, []);

  return <>
    <button
      aria-expanded={open}
      aria-haspopup="dialog"
      className="global-search-trigger"
      onClick={() => setOpen(true)}
      ref={triggerRef}
      type="button"
    >
      <span aria-hidden="true" className="global-search-trigger-icon">⌕</span>
      <span>Buscar</span>
      <kbd>Ctrl+K</kbd>
    </button>
    {open ? <GlobalSearchPalette onClose={close} /> : null}
  </>;
}
