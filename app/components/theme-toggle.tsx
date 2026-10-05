"use client";

import { useEffect, useState } from "react";

type Theme = "dark" | "light";

export function ThemeToggle({ userId }: { userId: string }) {
  const [dark, setDark] = useState(false);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const storageKey = themeStorageKey(userId);
    const saved = window.localStorage.getItem(storageKey);
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const initialTheme: Theme = saved === "dark" || saved === "light"
      ? saved
      : media.matches ? "dark" : "light";

    applyTheme(initialTheme);
    const frame = window.requestAnimationFrame(() => {
      setDark(initialTheme === "dark");
      setReady(true);
    });

    function followSystem(event: MediaQueryListEvent) {
      if (window.localStorage.getItem(storageKey)) return;
      const nextTheme: Theme = event.matches ? "dark" : "light";
      applyTheme(nextTheme);
      setDark(nextTheme === "dark");
    }

    media.addEventListener("change", followSystem);
    return () => {
      window.cancelAnimationFrame(frame);
      media.removeEventListener("change", followSystem);
    };
  }, [userId]);

  function toggleTheme() {
    const nextTheme: Theme = dark ? "light" : "dark";
    window.localStorage.setItem(themeStorageKey(userId), nextTheme);
    applyTheme(nextTheme);
    setDark(nextTheme === "dark");
  }

  return (
    <button
      aria-checked={dark}
      aria-label={`${dark ? "Desativar" : "Ativar"} modo noturno`}
      className="theme-toggle"
      disabled={!ready}
      onClick={toggleTheme}
      role="switch"
      type="button"
    >
      <span className="theme-toggle-icon" aria-hidden="true">{dark ? "☾" : "☀"}</span>
      <span className="theme-toggle-copy"><strong>Modo noturno</strong><small>{dark ? "Ligado" : "Desligado"}</small></span>
      <span className="theme-toggle-track" aria-hidden="true"><span /></span>
    </button>
  );
}

function applyTheme(theme: Theme) {
  document.documentElement.dataset.theme = theme;
  document.documentElement.style.colorScheme = theme;
}

function themeStorageKey(userId: string) {
  return `hp-sul-theme:${userId}`;
}
