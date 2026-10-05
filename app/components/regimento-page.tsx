"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  REGIMENTO_FINAL_DISPOSITIONS,
  REGIMENTO_PREAMBLE,
  REGIMENTO_SECTIONS,
  REGIMENTO_UPDATED_AT,
  type RegimentoSection,
} from "../lib/regimento-data";
import { HpsmLogo } from "./hpsm-logo";
import { ThemeToggle } from "./theme-toggle";

type OpenSections = Record<string, boolean>;

const PREAMBLE_ID = "preambulo";
const FINAL_ID = "disposicoes-finais";
const ALL_SECTION_IDS = [PREAMBLE_ID, ...REGIMENTO_SECTIONS.map((section) => section.id), FINAL_ID];

function normalise(value: string) {
  return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("pt-BR");
}

function normalState(): OpenSections {
  return {};
}

function sectionContains(section: RegimentoSection, term: string) {
  return normalise(`${section.title}\n${section.content}`).includes(term);
}

export function RegimentoPage() {
  const [openSections, setOpenSections] = useState<OpenSections>(normalState);
  const [query, setQuery] = useState("");
  const searchTerm = normalise(query.trim());
  const matchedSections = useMemo(
    () => REGIMENTO_SECTIONS.filter((section) => sectionContains(section, searchTerm)),
    [searchTerm],
  );
  const preambleMatches = normalise(REGIMENTO_PREAMBLE).includes(searchTerm);
  const finalMatches = normalise(REGIMENTO_FINAL_DISPOSITIONS).includes(searchTerm);

  const openHashTarget = useCallback(() => {
    const target = window.location.hash.slice(1);
    if (!ALL_SECTION_IDS.includes(target)) return;

    setQuery("");
    setOpenSections({ [target]: true });
    window.requestAnimationFrame(() => document.getElementById(target)?.scrollIntoView({ behavior: "smooth", block: "start" }));
  }, []);

  useEffect(() => {
    if (window.location.hash) window.requestAnimationFrame(openHashTarget);
    window.addEventListener("hashchange", openHashTarget);
    return () => window.removeEventListener("hashchange", openHashTarget);
  }, [openHashTarget]);

  function toggleSection(id: string) {
    setOpenSections((current) => ({ ...current, [id]: !current[id] }));
  }

  function handleSearch(value: string) {
    setQuery(value);
    const term = normalise(value.trim());
    if (!term) {
      setOpenSections(normalState());
      return;
    }

    const next: OpenSections = {};
    if (normalise(REGIMENTO_PREAMBLE).includes(term)) next[PREAMBLE_ID] = true;
    if (normalise(REGIMENTO_FINAL_DISPOSITIONS).includes(term)) next[FINAL_ID] = true;
    for (const section of REGIMENTO_SECTIONS) {
      if (sectionContains(section, term)) next[section.id] = true;
    }
    setOpenSections(next);
  }

  return (
    <main className="regiment-page">
      <div className="regiment-toolbar"><ThemeToggle userId="public-entry" /></div>
      <div className="regiment-shell">
        <header className="regiment-header">
          <div className="regiment-back-row"><Link className="regiment-back" href="/">← Voltar para a Home</Link></div>
          <div className="regiment-hero-copy">
            <HpsmLogo className="regiment-logo" />
            <p className="eyebrow">Hospital Santa Marcelina · Cidade dos Anjos</p>
            <h1>Regimento Interno<br />e Normas de Boas Práticas</h1>
            <p className="regiment-intro">Documento institucional público do Hospital Santa Marcelina.</p>
          </div>
        </header>

        <section aria-label="Ferramentas do regimento" className="regiment-tools">
          <label className="regiment-search-label" htmlFor="regiment-search">Buscar no regimento</label>
          <div className="regiment-search-wrap">
            <span aria-hidden="true">⌕</span>
            <input
              id="regiment-search"
              onChange={(event) => handleSearch(event.target.value)}
              placeholder="Buscar no regimento (ex: atendimento, SAMU, uniforme)..."
              type="search"
              value={query}
            />
          </div>
          {query.trim() ? <p aria-live="polite" className="regiment-search-status">{matchedSections.length + Number(preambleMatches) + Number(finalMatches)} seção(ões) relacionada(s).</p> : null}
          <div className="regiment-tool-actions">
            <button onClick={() => setOpenSections(Object.fromEntries(ALL_SECTION_IDS.map((id) => [id, true])))} type="button">Expandir tudo</button>
            <button onClick={() => setOpenSections(normalState())} type="button">Recolher tudo</button>
          </div>
        </section>

        <section className="regiment-document" aria-label="Conteúdo do Regimento Interno">
          <RegimentSection
            content={REGIMENTO_PREAMBLE}
            id={PREAMBLE_ID}
            isOpen={Boolean(openSections[PREAMBLE_ID])}
            onToggle={toggleSection}
            query={query}
            subtitle="Compromisso inicial, jornada e permanência"
            title="PREÂMBULO"
          />
          {REGIMENTO_SECTIONS.map((section) => (
            <RegimentSection
              content={section.content}
              id={section.id}
              isOpen={Boolean(openSections[section.id])}
              key={section.id}
              onToggle={toggleSection}
              query={query}
              title={section.title}
            />
          ))}
          <RegimentSection
            content={REGIMENTO_FINAL_DISPOSITIONS}
            id={FINAL_ID}
            isOpen={Boolean(openSections[FINAL_ID])}
            onToggle={toggleSection}
            query={query}
            title="DISPOSIÇÕES FINAIS"
          />
        </section>

        <footer className="regiment-closing">
          <strong>Hospital Santa Marcelina</strong>
          <span>Cidade dos Anjos</span>
          <p>Regimento Interno e Normas de Boas Práticas</p>
          <small>Versão vigente conforme normas institucionais do HPSM.</small>
          <small>Última atualização: {REGIMENTO_UPDATED_AT}.</small>
        </footer>
      </div>
    </main>
  );
}

function RegimentSection({
  content,
  id,
  isOpen,
  onToggle,
  query,
  subtitle,
  title,
}: {
  content: string;
  id: string;
  isOpen: boolean;
  onToggle: (id: string) => void;
  query: string;
  subtitle?: string;
  title: string;
}) {
  const contentId = `${id}-content`;

  return (
    <section className="regiment-section" id={id}>
      <h2>
        <button aria-controls={contentId} aria-expanded={isOpen} onClick={() => onToggle(id)} type="button">
          <span className="regiment-section-heading">
            <span aria-hidden="true" className="regiment-section-marker">▤</span>
            <span><strong>{title}</strong>{subtitle ? <small>{subtitle}</small> : null}</span>
          </span>
          <span aria-hidden="true" className="regiment-chevron">{isOpen ? "▲" : "▼"}</span>
        </button>
      </h2>
      {isOpen ? <div className="regiment-section-content" id={contentId}><RegimentContent content={content} query={query} /></div> : null}
    </section>
  );
}

function RegimentContent({ content, query }: { content: string; query: string }) {
  return (
    <div className="regiment-prose">
      {content.split("\n\n").map((block, index) => {
        const className = block.startsWith("CAPÍTULO")
          ? "regiment-chapter"
          : block.startsWith("Art.")
            ? "regiment-article"
            : block.startsWith("§")
              ? "regiment-paragraph"
              : /^[IVX]+ —/.test(block)
                ? "regiment-clause"
                : "regiment-copy";
        return <p className={className} key={`${block.slice(0, 20)}-${index}`}><HighlightedText query={query} text={block} /></p>;
      })}
    </div>
  );
}

function HighlightedText({ query, text }: { query: string; text: string }) {
  const term = query.trim();
  if (!term) return text;
  const expression = new RegExp(`(${escapeRegExp(term)})`, "gi");
  return text.split(expression).map((part, index) => (
    normalise(part) === normalise(term) ? <mark key={`${part}-${index}`}>{part}</mark> : part
  ));
}

function escapeRegExp(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
