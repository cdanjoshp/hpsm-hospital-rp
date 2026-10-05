"use client";

import { useEffect, useMemo, useState } from "react";
import { bloodTypeLabel } from "../lib/exam-result-guards";
import {
  type LabFieldType,
  type LabResultData,
  type LabResultFlag,
  type LabTemplateCatalogItem,
  type LabTemplateParameter,
} from "../lib/exams";

const FIELD_TYPES: { value: LabFieldType; label: string }[] = [
  { value: "number", label: "Número" },
  { value: "percent", label: "Percentual" },
  { value: "text", label: "Texto" },
  { value: "select", label: "Seleção" },
  { value: "observation", label: "Observação" },
];

const FLAG_OPTIONS: { value: LabResultFlag; label: string }[] = [
  { value: "normal", label: "Normal ✓" },
  { value: "low", label: "Baixo ↓" },
  { value: "high", label: "Alto ↑" },
  { value: "positive", label: "Positivo +" },
  { value: "negative", label: "Negativo −" },
  { value: "inconclusive", label: "Inconclusivo ?" },
];

export function LaboratoryResultEditor({ disabled, result, onChange }: { disabled: boolean; result: LabResultData; onChange: (value: LabResultData) => void }) {
  function updateParameter(key: string, patch: Partial<{ flag: LabResultFlag | null; value: string }>) {
    onChange({
      ...result,
      parameters: result.parameters.map((parameter) => parameter.key === key ? { ...parameter, ...patch } : parameter),
    });
  }

  return <section className="lab-result-editor" aria-label="Resultados laboratoriais">
    <header className="lab-section-heading">
      <div><span>Laudo estruturado</span><h3>Parâmetros laboratoriais</h3></div>
      <small>Modelo clínico versionado · v{result.template_version}</small>
    </header>
    <div className="lab-parameter-form">
      {result.parameters.map((parameter) => <div className="lab-parameter-field" data-required={parameter.required} key={parameter.key}>
        <label htmlFor={`lab-${parameter.key}`}>
          <span>{parameter.label}{parameter.required ? <em>Obrigatório</em> : null}</span>
          {parameter.reference ? <small>{parameter.reference}</small> : null}
        </label>
        <div className="lab-value-control">
          {parameter.field_type === "select" ? <select id={`lab-${parameter.key}`} value={parameter.value} disabled={disabled} onChange={(event) => updateParameter(parameter.key, { value: event.target.value, flag: inferredFlag(event.target.value, parameter.flag) })}>
            <option value="">Selecione</option>
            {parameter.options.map((option) => <option key={option} value={option}>{option}</option>)}
          </select> : parameter.field_type === "observation" ? <textarea id={`lab-${parameter.key}`} value={parameter.value} disabled={disabled} rows={3} maxLength={2000} onChange={(event) => updateParameter(parameter.key, { value: event.target.value })} /> : <input id={`lab-${parameter.key}`} type={parameter.field_type === "number" || parameter.field_type === "percent" ? "number" : "text"} step="any" value={parameter.value} disabled={disabled} maxLength={2000} onChange={(event) => updateParameter(parameter.key, { value: event.target.value })} />}
          {parameter.unit ? <span>{parameter.unit}</span> : null}
        </div>
        <label className="lab-flag-control">Classificação
          <select value={parameter.flag ?? ""} disabled={disabled} onChange={(event) => updateParameter(parameter.key, { flag: (event.target.value || null) as LabResultFlag | null })}>
            <option value="">Sem flag</option>
            {FLAG_OPTIONS.map((flag) => <option key={flag.value} value={flag.value}>{flag.label}</option>)}
          </select>
        </label>
      </div>)}
    </div>
    <label className="lab-notes-field">Observações do resultado
      <textarea value={result.notes} disabled={disabled} rows={3} maxLength={12000} onChange={(event) => onChange({ ...result, notes: event.target.value })} placeholder="Informações complementares opcionais" />
    </label>
  </section>;
}

export function LaboratoryResultView({ result, showNotes = true }: { result: LabResultData; showNotes?: boolean }) {
  const bloodType = bloodTypeLabel(result);
  return <section className="lab-result-view" aria-label="Resultado laboratorial estruturado">
    <header className="lab-section-heading">
      <div><span>Resultado laboratorial</span><h3>{result.template_snapshot.exam_type_name}</h3></div>
      <small>Modelo preservado · v{result.template_version}</small>
    </header>
    {bloodType ? <div className="lab-blood-type"><span>Tipo sanguíneo</span><strong>{bloodType}</strong></div> : null}
    <div className="lab-result-table">
      <div className="lab-result-head"><span>Parâmetro</span><span>Resultado</span><span>Referência</span><span>Classificação</span></div>
      {result.parameters.map((parameter) => <article key={parameter.key}>
        <div><strong>{parameter.label}</strong><small>{parameter.key}</small></div>
        <div data-label="Resultado"><strong>{parameter.value || "Não informado"}{parameter.value && parameter.unit ? ` ${parameter.unit}` : ""}</strong></div>
        <div data-label="Referência"><span>{parameter.reference || "Sem referência"}</span></div>
        <div data-label="Classificação">{parameter.flag ? <span className="lab-flag" data-flag={parameter.flag}>{flagLabel(parameter.flag)}</span> : <span>Sem flag</span>}</div>
      </article>)}
    </div>
    {showNotes && result.notes ? <div className="lab-result-notes"><strong>Observações do resultado</strong><p>{result.notes}</p></div> : null}
  </section>;
}

export function LaboratoryTemplateManager() {
  const [templates, setTemplates] = useState<LabTemplateCatalogItem[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [parameters, setParameters] = useState<LabTemplateParameter[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const selected = templates.find((template) => template.id === selectedId) ?? null;

  async function load(preferredId?: number) {
    setLoading(true);
    setError("");
    try {
      const response = await fetch("/api/exams?view=templates", { cache: "no-store" });
      const payload = await response.json() as { templates?: LabTemplateCatalogItem[]; error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível carregar os templates.");
      const nextTemplates = payload.templates ?? [];
      const nextId = preferredId && nextTemplates.some((item) => item.id === preferredId) ? preferredId : nextTemplates[0]?.id ?? null;
      setTemplates(nextTemplates);
      setSelectedId(nextId);
      setParameters(cloneParameters(nextTemplates.find((item) => item.id === nextId)?.result_config.parameters ?? []));
    } catch (cause) {
      setError(messageOf(cause));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(timer);
  }, []);

  const dirty = useMemo(() => selected ? JSON.stringify(parameters) !== JSON.stringify(selected.result_config.parameters) : false, [parameters, selected]);

  function chooseTemplate(id: number) {
    const next = templates.find((template) => template.id === id);
    setSelectedId(id);
    setParameters(cloneParameters(next?.result_config.parameters ?? []));
    setNotice("");
    setError("");
  }

  function update(key: string, patch: Partial<LabTemplateParameter>) {
    setParameters((current) => current.map((parameter) => parameter.key === key ? { ...parameter, ...patch } : parameter));
  }

  function addParameter() {
    const used = new Set(parameters.map((parameter) => parameter.key));
    let index = parameters.length + 1;
    while (used.has(`parametro_${index}`)) index += 1;
    setParameters((current) => [...current, {
      active: true,
      field_type: "text",
      key: `parametro_${index}`,
      label: `Novo parâmetro ${index}`,
      options: [],
      reference: "",
      required: false,
      sort_order: (current.length + 1) * 10,
      unit: "",
    }]);
  }

  function move(index: number, direction: -1 | 1) {
    const target = index + direction;
    if (target < 0 || target >= parameters.length) return;
    setParameters((current) => {
      const next = [...current];
      [next[index], next[target]] = [next[target], next[index]];
      return next.map((parameter, position) => ({ ...parameter, sort_order: (position + 1) * 10 }));
    });
  }

  async function save() {
    if (!selected) return;
    setSaving(true);
    setError("");
    setNotice("");
    try {
      const normalized = parameters.map((parameter, index) => ({ ...parameter, sort_order: (index + 1) * 10 }));
      const response = await fetch("/api/exams", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ action: "template", examTypeId: selected.id, expectedVersion: selected.result_config.version, parameters: normalized }),
      });
      const payload = await response.json() as { error?: string; version?: number };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível salvar o template.");
      setNotice(`Template atualizado para a versão ${payload.version}. Novos exames usarão esta configuração.`);
      await load(selected.id);
    } catch (cause) {
      setError(messageOf(cause));
    } finally {
      setSaving(false);
    }
  }

  if (loading) return <div className="lab-template-loading">Carregando templates laboratoriais…</div>;
  return <section className="lab-template-manager">
    {error ? <p className="form-error" role="alert">{error}</p> : null}
    {notice ? <p className="form-success" role="status">{notice}</p> : null}
    <div className="lab-template-toolbar">
      <label>Tipo laboratorial<select value={selectedId ?? ""} onChange={(event) => chooseTemplate(Number(event.target.value))}>{templates.map((template) => <option key={template.id} value={template.id}>{template.name}</option>)}</select></label>
      {selected ? <div><span>Versão atual</span><strong>v{selected.result_config.version}</strong></div> : null}
      <button type="button" className="exam-secondary-button" onClick={addParameter} disabled={!selected || saving}>＋ Adicionar parâmetro</button>
    </div>
    <p className="lab-template-guidance">Inative parâmetros com histórico. A remoção física só é aceita quando nenhum exame já utilizou o identificador.</p>
    <div className="lab-template-list">
      {parameters.map((parameter, index) => <article key={parameter.key} data-active={parameter.active}>
        <div className="lab-template-order"><button type="button" aria-label="Mover para cima" disabled={saving || index === 0} onClick={() => move(index, -1)}>↑</button><button type="button" aria-label="Mover para baixo" disabled={saving || index === parameters.length - 1} onClick={() => move(index, 1)}>↓</button></div>
        <div className="lab-template-fields">
          <label>Nome<input value={parameter.label} maxLength={100} disabled={saving} onChange={(event) => update(parameter.key, { label: event.target.value })} /></label>
          <label>Identificador<input value={parameter.key} maxLength={64} disabled={saving} onChange={(event) => { const key = slugCode(event.target.value); setParameters((current) => current.map((item, itemIndex) => itemIndex === index ? { ...item, key } : item)); }} /></label>
          <label>Tipo<select value={parameter.field_type} disabled={saving} onChange={(event) => update(parameter.key, { field_type: event.target.value as LabFieldType, options: event.target.value === "select" && parameter.options.length < 2 ? ["Opção 1", "Opção 2"] : parameter.options })}>{FIELD_TYPES.map((type) => <option key={type.value} value={type.value}>{type.label}</option>)}</select></label>
          <label>Unidade<input value={parameter.unit} maxLength={40} disabled={saving} onChange={(event) => update(parameter.key, { unit: event.target.value })} /></label>
          <label className="lab-template-reference">Referência<input value={parameter.reference} maxLength={240} disabled={saving} onChange={(event) => update(parameter.key, { reference: event.target.value })} /></label>
          {parameter.field_type === "select" ? <label className="lab-template-options">Opções, separadas por vírgula<input value={parameter.options.join(", ")} disabled={saving} onChange={(event) => update(parameter.key, { options: event.target.value.split(",").map((option) => option.trim()).filter(Boolean).slice(0, 50) })} /></label> : null}
        </div>
        <div className="lab-template-switches">
          <label><input type="checkbox" checked={parameter.required} disabled={saving} onChange={(event) => update(parameter.key, { required: event.target.checked })} /> Obrigatório</label>
          <label><input type="checkbox" checked={parameter.active} disabled={saving} onChange={(event) => update(parameter.key, { active: event.target.checked })} /> Ativo</label>
          <button type="button" className="exam-danger-button" disabled={saving} onClick={() => setParameters((current) => current.filter((_, itemIndex) => itemIndex !== index))}>Remover</button>
        </div>
      </article>)}
    </div>
    <div className="lab-template-actions"><span>{dirty ? "Alterações não salvas" : "Template sincronizado"}</span><button type="button" className="exam-primary-button" disabled={!selected || !dirty || saving} onClick={() => void save()}>{saving ? "Salvando…" : "Salvar nova versão"}</button></div>
  </section>;
}

function inferredFlag(value: string, current: LabResultFlag | null) {
  if (value === "Positivo") return "positive";
  if (value === "Negativo") return "negative";
  if (value === "Inconclusivo") return "inconclusive";
  return value ? current : null;
}

function flagLabel(flag: LabResultFlag) {
  return FLAG_OPTIONS.find((item) => item.value === flag)?.label ?? flag;
}

function cloneParameters(parameters: LabTemplateParameter[]) {
  return parameters.map((parameter) => ({ ...parameter, options: [...parameter.options] }));
}

function slugCode(value: string) {
  return value.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "").slice(0, 64);
}

function messageOf(error: unknown) {
  return error instanceof Error ? error.message : "Não foi possível concluir a operação.";
}
