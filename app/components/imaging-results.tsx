"use client";

/* eslint-disable @next/next/no-img-element */

import { useEffect, useMemo, useRef, useState } from "react";
import type {
  ClinicalExamImage,
  ImagingContrast,
  ImagingLaterality,
  ImagingResultData,
  ImagingTemplateCatalogItem,
} from "../lib/exams";

const LATERALITY_OPTIONS: Array<{ value: Exclude<ImagingLaterality, "">; label: string }> = [
  { value: "left", label: "Esquerda" },
  { value: "right", label: "Direita" },
  { value: "bilateral", label: "Bilateral" },
  { value: "not_applicable", label: "Não se aplica" },
];
const CONTRAST_OPTIONS: Array<{ value: Exclude<ImagingContrast, "">; label: string }> = [
  { value: "with", label: "Com contraste" },
  { value: "without", label: "Sem contraste" },
  { value: "not_applicable", label: "Não se aplica" },
];

export function ImagingResultEditor({ disabled, result, onChange }: { disabled: boolean; result: ImagingResultData; onChange: (value: ImagingResultData) => void }) {
  const template = result.template_snapshot;
  return <section className="imaging-result-editor" aria-label="Dados estruturados do exame de imagem">
    <header className="lab-section-heading">
      <div><span>Dados da solicitação</span><h3>Informações básicas do exame</h3></div>
      <small>Estas informações seguem prontas para o profissional que executará o exame.</small>
    </header>
    <div className="imaging-field-grid">
      <label>Região examinada{template.region.required ? <em>Obrigatório</em> : null}
        <select value={result.region} disabled={disabled} onChange={(event) => onChange({ ...result, region: event.target.value, other_region: "" })}>
          <option value="">Selecione</option>
          {template.region.options.filter((region) => !/^outr[oa]s?(?:$|\s)/iu.test(region.trim())).map((region) => <option key={region} value={region}>{region}</option>)}
        </select>
      </label>
      {template.supports_laterality ? <label>Lateralidade<em>Obrigatório</em><select value={result.laterality} disabled={disabled} onChange={(event) => onChange({ ...result, laterality: event.target.value as ImagingLaterality })}><option value="">Selecione</option>{LATERALITY_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label> : null}
      {template.supports_contrast ? <label>Contraste<em>Obrigatório</em><select value={result.contrast} disabled={disabled} onChange={(event) => onChange({ ...result, contrast: event.target.value as ImagingContrast })}><option value="">Selecione</option>{CONTRAST_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label> : null}
    </div>
  </section>;
}

export function ImagingResultView({ result, showNotes = true }: { result: ImagingResultData; showNotes?: boolean }) {
  const region = result.region === "Outra região" ? result.other_region : result.region;
  return <section className="imaging-result-view" aria-label="Resultado estruturado do exame de imagem">
    <header className="lab-section-heading">
      <div><span>Dados da solicitação</span><h3>{result.template_snapshot.exam_type_name}</h3></div>
      <small>Modelo preservado · v{result.template_version}</small>
    </header>
    <dl className="imaging-result-facts">
      <div><dt>Região</dt><dd>{region || "Não informada"}</dd></div>
      {result.template_snapshot.supports_laterality ? <div><dt>Lateralidade</dt><dd>{lateralityLabel(result.laterality)}</dd></div> : null}
      {result.template_snapshot.supports_contrast ? <div><dt>Contraste</dt><dd>{contrastLabel(result.contrast)}</dd></div> : null}
    </dl>
    {showNotes && result.notes ? <div className="lab-result-notes"><strong>Observações da aquisição</strong><p>{result.notes}</p></div> : null}
  </section>;
}

export function ClinicalExamImageGallery({
  editable,
  examId,
  examTypeName,
  onStateChange,
  refreshToken = 0,
  required,
}: {
  editable: boolean;
  examId: number;
  examTypeName: string;
  onStateChange?: (state: { count: number; loading: boolean }) => void;
  refreshToken?: number;
  required: boolean;
}) {
  const [images, setImages] = useState<ClinicalExamImage[]>([]);
  const [loading, setLoading] = useState(true);
  const [removingId, setRemovingId] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [previewIndex, setPreviewIndex] = useState<number | null>(null);
  const loadRequest = useRef(0);

  async function load() {
    const requestId = ++loadRequest.current;
    setLoading(true);
    setError("");
    onStateChange?.({ count: images.length, loading: true });
    try {
      const response = await fetch(`/api/exams/images?examId=${examId}`, { cache: "no-store" });
      const payload = await response.json() as { error?: string; images?: ClinicalExamImage[] };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível carregar as imagens.");
      const next = payload.images ?? [];
      if (requestId !== loadRequest.current) return;
      setImages(next);
      onStateChange?.({ count: next.length, loading: false });
    } catch (cause) {
      if (requestId !== loadRequest.current) return;
      setError(messageOf(cause));
      onStateChange?.({ count: 0, loading: false });
    } finally {
      if (requestId === loadRequest.current) setLoading(false);
    }
  }

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(timer);
    // A galeria também recarrega quando uma imagem de IA é aplicada no detalhe aberto.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [examId, refreshToken]);

  async function removeImage(image: ClinicalExamImage) {
    setRemovingId(image.id);
    setError("");
    try {
      const response = await fetch(`/api/exams/images?id=${encodeURIComponent(image.id)}`, { method: "DELETE" });
      const payload = await response.json() as { error?: string };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível remover a imagem.");
      if (previewIndex !== null) setPreviewIndex(null);
      await load();
    } catch (cause) {
      setError(messageOf(cause));
    } finally {
      setRemovingId(null);
    }
  }

  const preview = previewIndex === null ? null : images[previewIndex] ?? null;
  const locked = removingId !== null;
  return <section className="exam-image-gallery" aria-label="Imagens clínicas">
    <header className="exam-image-heading"><div><span>Imagens geradas por IA</span><h3>{images.length ? `${images.length} ${images.length === 1 ? "imagem associada" : "imagens associadas"}` : "Nenhuma imagem associada"}</h3></div><small>{required ? "A geração por IA inclui a imagem obrigatória" : "Imagem opcional gerada por IA"}</small></header>
    {error ? <p className="form-error" role="alert">{error}</p> : null}
    {loading ? <div className="exam-image-loading">Carregando galeria protegida…</div> : images.length ? <div className="exam-image-grid">{images.map((image, index) => <article key={image.id}>
      <button className="exam-image-thumb" type="button" onClick={() => setPreviewIndex(index)} aria-label={`Ampliar imagem ${index + 1} do exame ${examTypeName}`}><img src={image.signed_url} alt={`Imagem do exame ${examTypeName} — ${image.caption || `arquivo ${index + 1}`}`} /></button>
      <div><strong>{image.caption || `Imagem ${index + 1}`}</strong><small>{formatBytes(image.file_size)} · {formatDateTime(image.created_at)}</small>{image.source === "ai_generated" ? <span className="exam-ai-image-badge">Gerada por IA</span> : null}</div>
      {editable ? <button className="exam-danger-button" type="button" disabled={locked} onClick={() => void removeImage(image)}>{removingId === image.id ? "Removendo…" : "Remover"}</button> : null}
    </article>)}</div> : <div className="exam-image-empty"><strong>Galeria vazia</strong><p>{editable ? "Gere o exame com IA para criar e anexar a imagem automaticamente." : "Nenhuma imagem foi gerada para este registro."}</p></div>}
    {preview ? <div className="exam-image-preview" role="dialog" aria-modal="true" aria-label={`Visualização ampliada da imagem ${previewIndex! + 1}`} onMouseDown={(event) => { if (event.target === event.currentTarget) setPreviewIndex(null); }}>
      <section><header><div><strong>{preview.caption || `Imagem ${previewIndex! + 1}`}</strong><small>{preview.original_filename}{preview.source === "ai_generated" ? " · Gerada por IA" : ""}</small></div><button type="button" aria-label="Fechar visualização" onClick={() => setPreviewIndex(null)}>×</button></header><div className="exam-image-preview-stage"><button type="button" aria-label="Imagem anterior" disabled={images.length < 2} onClick={() => setPreviewIndex((previewIndex! - 1 + images.length) % images.length)}>‹</button><img src={preview.signed_url} alt={`Imagem ampliada do exame ${examTypeName} — ${preview.caption || `arquivo ${previewIndex! + 1}`}`} /><button type="button" aria-label="Próxima imagem" disabled={images.length < 2} onClick={() => setPreviewIndex((previewIndex! + 1) % images.length)}>›</button></div><footer>{previewIndex! + 1} de {images.length}</footer></section>
    </div> : null}
  </section>;
}

export function ImagingTemplateManager() {
  const [templates, setTemplates] = useState<ImagingTemplateCatalogItem[]>([]);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [regions, setRegions] = useState<string[]>([]);
  const [regionRequired, setRegionRequired] = useState(true);
  const [supportsLaterality, setSupportsLaterality] = useState(true);
  const [supportsContrast, setSupportsContrast] = useState(false);
  const [requiresImage, setRequiresImage] = useState(true);
  const [allowsMultipleImages, setAllowsMultipleImages] = useState(true);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const selected = templates.find((template) => template.id === selectedId) ?? null;

  function applyTemplate(template: ImagingTemplateCatalogItem | null) {
    const config = template?.result_config;
    setRegions(config?.region.options ?? []);
    setRegionRequired(config?.region.required ?? true);
    setSupportsLaterality(config?.supports_laterality ?? true);
    setSupportsContrast(config?.supports_contrast ?? false);
    setRequiresImage(config?.requires_image ?? true);
    setAllowsMultipleImages(config?.allows_multiple_images ?? true);
  }

  async function load(preferredId?: number) {
    setLoading(true);
    setError("");
    try {
      const response = await fetch("/api/exams?view=imaging-templates", { cache: "no-store" });
      const payload = await response.json() as { error?: string; templates?: ImagingTemplateCatalogItem[] };
      if (!response.ok) throw new Error(payload.error ?? "Não foi possível carregar os templates de imagem.");
      const next = payload.templates ?? [];
      const nextId = preferredId && next.some((item) => item.id === preferredId) ? preferredId : next[0]?.id ?? null;
      setTemplates(next);
      setSelectedId(nextId);
      applyTemplate(next.find((item) => item.id === nextId) ?? null);
    } catch (cause) {
      setError(messageOf(cause));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(timer);
    // O catálogo é carregado somente ao abrir esta aba administrativa.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const draft = useMemo(() => ({ allowsMultipleImages, regionRequired, regions, requiresImage, supportsContrast, supportsLaterality }), [allowsMultipleImages, regionRequired, regions, requiresImage, supportsContrast, supportsLaterality]);
  const original = selected ? {
    allowsMultipleImages: selected.result_config.allows_multiple_images,
    regionRequired: selected.result_config.region.required,
    regions: selected.result_config.region.options,
    requiresImage: selected.result_config.requires_image,
    supportsContrast: selected.result_config.supports_contrast,
    supportsLaterality: selected.result_config.supports_laterality,
  } : null;
  const dirty = original ? JSON.stringify(draft) !== JSON.stringify(original) : false;

  function choose(id: number) {
    const next = templates.find((template) => template.id === id) ?? null;
    setSelectedId(id);
    applyTemplate(next);
    setError("");
    setNotice("");
  }

  async function save() {
    if (!selected) return;
    const normalizedRegions = regions.map((region) => region.trim()).filter(Boolean).slice(0, 60);
    if (!normalizedRegions.length) {
      setError("Informe ao menos uma região disponível.");
      return;
    }
    if (normalizedRegions.some((region) => /^outr[oa]s?(?:$|\s)/iu.test(region))) {
      setError("Escolha regiões específicas; opções genéricas não são permitidas.");
      return;
    }
    setSaving(true);
    setError("");
    setNotice("");
    try {
      const response = await fetch("/api/exams", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "imaging-template", allowsMultipleImages, examTypeId: selected.id, expectedVersion: selected.result_config.version, regionOptions: normalizedRegions, regionRequired, requiresImage, supportsContrast, supportsLaterality }) });
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

  if (loading) return <div className="lab-template-loading">Carregando templates de imagem…</div>;
  return <section className="imaging-template-manager">
    {error ? <p className="form-error" role="alert">{error}</p> : null}
    {notice ? <p className="form-success" role="status">{notice}</p> : null}
    <div className="lab-template-toolbar"><label>Tipo de imagem<select value={selectedId ?? ""} onChange={(event) => choose(Number(event.target.value))}>{templates.map((template) => <option key={template.id} value={template.id}>{template.name}</option>)}</select></label>{selected ? <div><span>Versão atual</span><strong>v{selected.result_config.version}</strong></div> : null}</div>
    <div className="imaging-template-form">
      <label>Regiões disponíveis, uma por linha<textarea value={regions.join("\n")} disabled={saving} rows={10} onChange={(event) => setRegions(event.target.value.split("\n"))} /></label>
      <div className="imaging-template-options">
        <label><input type="checkbox" checked={regionRequired} disabled={saving} onChange={(event) => setRegionRequired(event.target.checked)} /> Região obrigatória</label>
        <label><input type="checkbox" checked={supportsLaterality} disabled={saving} onChange={(event) => setSupportsLaterality(event.target.checked)} /> Usar lateralidade</label>
        <label><input type="checkbox" checked={supportsContrast} disabled={saving} onChange={(event) => setSupportsContrast(event.target.checked)} /> Usar contraste</label>
        <label><input type="checkbox" checked={requiresImage} disabled={saving} onChange={(event) => setRequiresImage(event.target.checked)} /> Exigir imagem</label>
        <label><input type="checkbox" checked={allowsMultipleImages} disabled={saving} onChange={(event) => setAllowsMultipleImages(event.target.checked)} /> Permitir múltiplas imagens</label>
      </div>
    </div>
    <div className="lab-template-actions"><span>{dirty ? "Alterações não salvas" : "Template sincronizado"}</span><button type="button" className="exam-primary-button" disabled={!selected || !dirty || saving} onClick={() => void save()}>{saving ? "Salvando…" : "Salvar nova versão"}</button></div>
  </section>;
}

function lateralityLabel(value: ImagingLaterality) {
  return LATERALITY_OPTIONS.find((option) => option.value === value)?.label ?? "Não informada";
}

function contrastLabel(value: ImagingContrast) {
  return CONTRAST_OPTIONS.find((option) => option.value === value)?.label ?? "Não informado";
}

function formatBytes(value: number) {
  return value >= 1024 * 1024 ? `${(value / (1024 * 1024)).toFixed(1)} MB` : `${Math.max(1, Math.round(value / 1024))} KB`;
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value));
}

function messageOf(error: unknown) {
  return error instanceof Error ? error.message : "Não foi possível concluir a operação.";
}
