"use client";

import { useRef, useState, type FormEvent } from "react";
import "./hpsm-assist.css";

type Possibility = { title: string; reason: string; compatibility: string };
type Exam = { exam_id: number; name: string; category: string; reason: string; order: number };
type Medication = { medication_id: string; name: string; reference: string; reason: string; justification: string;
  dose: string; frequency: string; duration: string; route: string; instructions: string; controlled: boolean; antibiotic: boolean };
type Analysis = {
  priority: "LOW" | "MODERATE" | "HIGH" | "EMERGENCY"; summary: string;
  possible_conditions: Possibility[]; checks: string[]; suggested_exams: Exam[];
  suggested_medications: Medication[]; suggested_actions: string[]; warning_signs: string[]; final_guidance: string;
};
const PRIORITY: Record<Analysis["priority"], string> = { LOW: "Baixa", MODERATE: "Moderada", HIGH: "Alta", EMERGENCY: "Emergencial" };

export function HpsmAssist() {
  const [caseText, setCaseText] = useState("");
  const [pain, setPain] = useState<number | null>(null);
  const [result, setResult] = useState<Analysis | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const locked = useRef(false);

  async function analyze(event?: FormEvent) {
    event?.preventDefault();
    if (locked.current) return;
    const text = caseText.trim();
    if (text.length < 20) { setError("Descreva o caso com pelo menos 20 caracteres para iniciar a análise."); return; }
    locked.current = true;
    setPending(true);
    setError("");
    setResult(null);
    try {
      const response = await fetch("/api/hpsm-assist", {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ caseText: text, pain }), cache: "no-store",
      });
      const payload = await response.json() as { result?: Analysis; error?: string };
      if (!response.ok || !payload.result) throw new Error(payload.error || "Não foi possível analisar o caso. Tente novamente.");
      setResult(payload.result);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Não foi possível analisar o caso. Tente novamente.");
    } finally {
      locked.current = false;
      setPending(false);
    }
  }

  function newCase() {
    if (locked.current) return;
    setCaseText(""); setPain(null); setResult(null); setError("");
  }

  return <div className="assist-page">
    <p className="assist-disclaimer">Ferramenta de apoio exclusivamente para uso em RP. As sugestões não geram registros ou ações automaticamente.</p>
    <form className="assist-form" onSubmit={analyze}>
      <label htmlFor="assist-case">Descreva o caso</label>
      <textarea id="assist-case" placeholder="Paciente caiu de moto, apresenta dor intensa na perna direita e dificuldade para apoiar o membro."
        value={caseText} onChange={(event) => setCaseText(event.target.value)} maxLength={6000} rows={7} disabled={pending} />
      <div className="assist-form-bottom">
        <fieldset className="assist-pain">
          <legend>Dor relatada</legend>
          <div className="assist-pain-options">
            <button type="button" className={pain === null ? "selected" : ""} aria-pressed={pain === null} onClick={() => setPain(null)} disabled={pending}>Não informada</button>
            {Array.from({ length: 11 }, (_, n) => <button key={n} type="button" className={pain === n ? "selected" : ""} aria-pressed={pain === n}
              onClick={() => setPain(n)} disabled={pending}>{n}</button>)}
          </div>
          <span className="assist-pain-caption">{pain === null ? "Opcional" : `Dor: ${pain}/10`}</span>
        </fieldset>
        <div className="assist-buttons">
          {(result || caseText || pain !== null) && <button type="button" className="assist-reset" onClick={newCase} disabled={pending}>Novo caso</button>}
          <button type="submit" className="assist-submit" disabled={pending || caseText.trim().length < 20}>{pending ? "Analisando o caso…" : "Analisar caso"}</button>
        </div>
      </div>
    </form>
    {pending && <div className="assist-progress" role="status" aria-live="polite"><span />Analisando o caso…</div>}
    {error && <div className="assist-error" role="alert"><span>{error}</span><button type="button" onClick={() => void analyze()} disabled={pending}>Tentar novamente</button></div>}
    {result && <section className="assist-result" aria-label="Sugestões do HPSM Assist">
      <div className="assist-result-head"><div><span className="assist-eyebrow">Análise do caso</span><h2>Avaliação rápida</h2></div>
        <span className={`assist-priority assist-priority-${result.priority.toLowerCase()}`}>Prioridade {PRIORITY[result.priority] ?? "Não definida"}</span></div>
      <p className="assist-summary">{result.summary}</p>
      <div className="assist-result-grid">
        <ResultSection title="Principais possibilidades" empty="Nenhuma possibilidade específica sugerida.">
          {result.possible_conditions.map((item, i) => <article className="assist-possibility" key={i}><span>{item.compatibility}</span><h4>{item.title}</h4><p>{item.reason}</p></article>)}
        </ResultSection>
        <ResultSection title="O que verificar" empty="Nenhuma verificação adicional sugerida."><SimpleList values={result.checks} /></ResultSection>
        <ResultSection title="Exames sugeridos" empty="Nenhum exame sugerido para o relato atual.">
          {result.suggested_exams.map((exam) => <article className="assist-catalog-item" key={exam.exam_id}><span>{exam.category}</span><h4>{exam.name}</h4><p>{exam.reason}</p></article>)}
        </ResultSection>
        <ResultSection title="Medicamentos RP" empty="Nenhum medicamento sugerido para o relato atual.">
          {result.suggested_medications.map((med) => <article className="assist-catalog-item" key={med.medication_id}>
            <div className="assist-med-title"><h4>{med.name}</h4>{med.controlled && <span className="assist-controlled">Controlado</span>}</div>
            <p>Referência: {med.reference}</p><p>{med.reason}</p>
            <dl><div><dt>Dose RP</dt><dd>{med.dose}</dd></div><div><dt>Frequência</dt><dd>{med.frequency}</dd></div><div><dt>Duração</dt><dd>{med.duration}</dd></div><div><dt>Via</dt><dd>{med.route}</dd></div></dl>
            {med.instructions && <p className="assist-instructions">{med.instructions}</p>}
            {med.controlled && <p className="assist-instructions">Justificativa: {med.justification}</p>}
          </article>)}
        </ResultSection>
        <ResultSection title="Conduta sugerida" empty="Nenhuma conduta adicional sugerida."><SimpleList values={result.suggested_actions} /></ResultSection>
        <ResultSection title="Atenção" empty="Nenhum sinal adicional destacado."><SimpleList values={result.warning_signs} /></ResultSection>
      </div>
      <div className="assist-guidance"><span className="assist-eyebrow">Orientação</span><p>{result.final_guidance}</p></div>
      <p className="assist-result-foot">Sugestões para leitura do profissional. Nenhuma ação foi registrada no HPSM.</p>
    </section>}
  </div>;
}

function ResultSection({ title, empty, children }: { title: string; empty: string; children: React.ReactNode }) {
  const hasContent = Array.isArray(children) ? children.length > 0 : Boolean(children);
  return <section className="assist-section"><h3>{title}</h3>{hasContent ? children : <p className="assist-empty">{empty}</p>}</section>;
}
function SimpleList({ values }: { values: string[] }) {
  return values.length ? <ul className="assist-list">{values.map((value, index) => <li key={index}>{value}</li>)}</ul> : <p className="assist-empty">Nenhuma sugestão adicional.</p>;
}
