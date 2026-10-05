"use client";

import { useRouter } from "next/navigation";
import { useEffect, useId, useRef, useState, type KeyboardEvent } from "react";
import { createPortal } from "react-dom";
import { GLOBAL_SEARCH_GROUPS, type GlobalSearchItem, type GlobalSearchResponse } from "../lib/global-search";

export function GlobalSearchPalette({ onClose }: { onClose: () => void }) {
  const router = useRouter();
  const inputRef = useRef<HTMLInputElement>(null);
  const dialogRef = useRef<HTMLElement>(null);
  const requestSequence = useRef(0);
  const listboxId = useId();
  const [query, setQuery] = useState("");
  const [items, setItems] = useState<GlobalSearchItem[]>([]);
  const [activeIndex, setActiveIndex] = useState(0);
  const [state, setState] = useState<"error" | "idle" | "loading" | "ready">("idle");

  useEffect(() => { inputRef.current?.focus(); }, []);

  useEffect(() => {
    function handleDialogKey(event: globalThis.KeyboardEvent) {
      if (event.key === "Escape") {
        event.preventDefault();
        onClose();
        return;
      }
      if (event.key !== "Tab" || !dialogRef.current) return;
      const focusable = [...dialogRef.current.querySelectorAll<HTMLElement>("button:not([disabled]), input:not([disabled])")];
      const first = focusable[0];
      const last = focusable.at(-1);
      if (!first || !last) return;
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
    document.addEventListener("keydown", handleDialogKey);
    return () => document.removeEventListener("keydown", handleDialogKey);
  }, [onClose]);

  useEffect(() => {
    const normalized = query.trim();
    if (normalized.length < 2) return;

    const controller = new AbortController();
    const sequence = ++requestSequence.current;
    const timeout = window.setTimeout(() => {
      setState("loading");
      void fetch(`/api/global-search?q=${encodeURIComponent(normalized)}`, {
        cache: "no-store",
        signal: controller.signal,
      }).then(async (response) => {
        const payload = (await response.json()) as GlobalSearchResponse & { error?: string };
        if (!response.ok) throw new Error(payload.error ?? "Não foi possível realizar a busca.");
        if (sequence !== requestSequence.current) return;
        setItems(Array.isArray(payload.items) ? payload.items : []);
        setActiveIndex(0);
        setState("ready");
      }).catch(() => {
        if (controller.signal.aborted || sequence !== requestSequence.current) return;
        setItems([]);
        setState("error");
      });
    }, 275);

    return () => {
      window.clearTimeout(timeout);
      controller.abort();
    };
  }, [query]);

  function openItem(item: GlobalSearchItem | undefined) {
    if (!item) return;
    onClose();
    router.push(item.category === "attendances" ? `/atendimentos/registro/${item.id}` : item.href);
  }

  function changeQuery(value: string) {
    setQuery(value);
    requestSequence.current += 1;
    setItems([]);
    setActiveIndex(0);
    setState(value.trim().length >= 2 ? "loading" : "idle");
  }

  function handleKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (!items.length) return;
    if (event.key === "ArrowDown") {
      event.preventDefault();
      setActiveIndex((current) => (current + 1) % items.length);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      setActiveIndex((current) => (current - 1 + items.length) % items.length);
    } else if (event.key === "Enter") {
      event.preventDefault();
      openItem(items[activeIndex]);
    }
  }

  const palette = <div className="global-search-overlay" onMouseDown={(event) => event.target === event.currentTarget && onClose()} role="presentation">
    <section aria-labelledby="global-search-title" aria-modal="true" className="global-search-dialog" ref={dialogRef} role="dialog">
      <header className="global-search-header">
        <div><p className="eyebrow">Busca Global</p><h2 id="global-search-title">Encontre no HPSM</h2></div>
        <button aria-label="Fechar busca" onClick={onClose} type="button">×</button>
      </header>
      <div className="global-search-field">
        <span aria-hidden="true">⌕</span>
        <input
          aria-activedescendant={items[activeIndex] ? `${listboxId}-${activeIndex}` : undefined}
          aria-autocomplete="list"
          aria-controls={listboxId}
          aria-expanded={query.trim().length >= 2}
          aria-label="Buscar no HPSM"
          autoComplete="off"
          onChange={(event) => changeQuery(event.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Buscar no HPSM..."
          ref={inputRef}
          role="combobox"
          value={query}
        />
        {state === "loading" ? <i aria-label="Buscando" className="global-search-spinner" role="status" /> : null}
      </div>
      <div aria-live="polite" className="global-search-results" id={listboxId} role="listbox">
        {query.trim().length < 2 ? <SearchMessage icon="⌘" title="Digite para buscar no HPSM" text="Use ao menos dois caracteres para localizar registros autorizados." /> : null}
        {state === "loading" ? <SearchMessage icon="◷" title="Buscando…" text="Consultando apenas as áreas permitidas para o seu acesso." /> : null}
        {state === "error" ? <SearchMessage icon="!" title="Busca indisponível" text="Não foi possível consultar os registros agora. Tente novamente." /> : null}
        {state === "ready" && !items.length ? <SearchMessage icon="◇" title="Nenhum resultado" text="Tente o nome, passaporte, identificação ou categoria." /> : null}
        {state === "ready" ? GLOBAL_SEARCH_GROUPS.map((group) => {
          const groupItems = items.map((item, index) => ({ index, item })).filter(({ item }) => item.category === group.category);
          if (!groupItems.length) return null;
          return <section className="global-search-group" key={group.category}>
            <h3>{group.label}</h3>
            {groupItems.map(({ index, item }) => <button
              aria-selected={activeIndex === index}
              className="global-search-result"
              data-active={activeIndex === index}
              id={`${listboxId}-${index}`}
              key={`${item.category}-${item.id}`}
              onClick={() => openItem(item)}
              onMouseEnter={() => setActiveIndex(index)}
              role="option"
              type="button"
            >
              <span><strong>{item.title}</strong><small>{item.subtitle}</small></span>
              {item.amount !== null ? <em>{formatMoney(item.amount)}</em> : <b aria-hidden="true">→</b>}
            </button>)}
          </section>;
        }) : null}
      </div>
      <footer className="global-search-footer"><span><kbd>↑</kbd><kbd>↓</kbd> navegar</span><span><kbd>Enter</kbd> abrir</span><span><kbd>Esc</kbd> fechar</span></footer>
    </section>
  </div>;

  return createPortal(palette, document.body);
}

function SearchMessage({ icon, text, title }: { icon: string; text: string; title: string }) {
  return <div className="global-search-message"><span aria-hidden="true">{icon}</span><strong>{title}</strong><p>{text}</p></div>;
}

function formatMoney(value: number) {
  return new Intl.NumberFormat("pt-BR", { currency: "BRL", style: "currency" }).format(value);
}
