"use client";

import { FormEvent, KeyboardEvent, useEffect, useMemo, useRef, useState } from "react";
import { BENEFIT_PLANS, type PlanCode } from "../lib/benefit-plans";
import { invalidateCatalogClientCache } from "../lib/catalog-client-cache";
import type { CatalogService } from "../lib/operational-data";
import { CatalogImage } from "./catalog-image";

type ItemDraft = {
  active: boolean;
  category: string;
  discounts: Record<PlanCode, string>;
  icon: string;
  imageFile: File | null;
  name: string;
  previewUrl: string | null;
  removeImage: boolean;
  sortOrder: string;
  unitPrice: string;
};

export function CatalogManagement({ canManage, initialEditingId, initialServices }: { canManage: boolean; initialEditingId?: number; initialServices: CatalogService[] }) {
  const initialService = initialServices.find((service) => service.id === initialEditingId) ?? null;
  const [services, setServices] = useState(initialServices);
  const [editingId, setEditingId] = useState<number | null>(initialService?.id ?? null);
  const [draft, setDraft] = useState<ItemDraft | null>(() => initialService ? toDraft(initialService) : null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [successId, setSuccessId] = useState<number | null>(null);
  const [quickPriceId, setQuickPriceId] = useState<number | null>(null);
  const [quickPriceValue, setQuickPriceValue] = useState("");
  const [quickPriceSaving, setQuickPriceSaving] = useState(false);
  const [quickPriceError, setQuickPriceError] = useState("");
  const [quickPriceSuccessId, setQuickPriceSuccessId] = useState<number | null>(null);
  const [bulkDraft, setBulkDraft] = useState<Record<PlanCode, string>>(() => commonDiscountDraft(initialServices));
  const [bulkConfirming, setBulkConfirming] = useState(false);
  const [bulkSaving, setBulkSaving] = useState(false);
  const [bulkError, setBulkError] = useState("");
  const [bulkSuccess, setBulkSuccess] = useState("");
  const bulkOpenButtonRef = useRef<HTMLButtonElement | null>(null);
  const bulkDialogRef = useRef<HTMLDivElement | null>(null);
  const editingService = services.find((service) => service.id === editingId) ?? null;
  const categories = useMemo(() => [...new Set(services.map((service) => service.category))].sort(), [services]);
  const pricingBusy = saving || quickPriceSaving || bulkSaving;

  useEffect(() => {
    if (!bulkConfirming) return;
    const dialog = bulkDialogRef.current;
    const focusable = dialog?.querySelectorAll<HTMLElement>('button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])');
    focusable?.[0]?.focus();
    function onKeyDown(event: globalThis.KeyboardEvent) {
      if (event.key === "Escape" && !bulkSaving) {
        event.preventDefault();
        setBulkConfirming(false);
        requestAnimationFrame(() => bulkOpenButtonRef.current?.focus());
        return;
      }
      if (event.key !== "Tab" || !focusable?.length) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [bulkConfirming, bulkSaving]);

  function openEditor(service: CatalogService) {
    if (pricingBusy) return;
    clearPreview();
    setError("");
    setEditingId(service.id);
    setDraft(toDraft(service));
    cancelQuickPrice();
  }

  function closeEditor() {
    if (saving) return;
    clearPreview();
    setEditingId(null);
    setDraft(null);
    setError("");
  }

  function clearPreview() {
    if (draft?.previewUrl) URL.revokeObjectURL(draft.previewUrl);
  }

  function updateDraft<K extends keyof ItemDraft>(key: K, value: ItemDraft[K]) {
    setDraft((current) => current ? { ...current, [key]: value } : current);
  }

  function commitUpdatedService(updated: CatalogService) {
    const next = replaceService(services, updated);
    setServices(next);
    setBulkDraft(commonDiscountDraft(next));
    invalidateCatalogClientCache();
  }

  function updateDiscount(planCode: PlanCode, value: string) {
    setDraft((current) => current ? { ...current, discounts: { ...current.discounts, [planCode]: value } } : current);
  }

  function updateBulkDiscount(planCode: PlanCode, value: string) {
    setBulkDraft((current) => ({ ...current, [planCode]: value }));
    setBulkError("");
    setBulkSuccess("");
  }

  function openQuickPrice(service: CatalogService) {
    if (pricingBusy) return;
    setQuickPriceId(service.id);
    setQuickPriceValue(String(Number(service.unit_price)));
    setQuickPriceError("");
    setQuickPriceSuccessId(null);
  }

  function cancelQuickPrice() {
    if (quickPriceSaving) return;
    setQuickPriceId(null);
    setQuickPriceValue("");
    setQuickPriceError("");
  }

  function quickPriceKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "Escape") {
      event.preventDefault();
      cancelQuickPrice();
    }
  }

  async function saveQuickPrice(event: FormEvent<HTMLFormElement>, service: CatalogService) {
    event.preventDefault();
    if (quickPriceSaving) return;
    const unitPrice = parseNumber(quickPriceValue);
    if (unitPrice < 0) {
      setQuickPriceError(`Informe um preço válido para ${service.name}.`);
      return;
    }

    setQuickPriceSaving(true);
    setQuickPriceError("");
    setQuickPriceSuccessId(null);
    try {
      const response = await fetch("/api/services/pricing", {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ action: "unit_price", serviceId: service.id, unitPrice }),
      });
      const payload = await response.json() as { error?: string; serviceId?: number; unitPrice?: number };
      if (!response.ok || payload.serviceId !== service.id || typeof payload.unitPrice !== "number") {
        setQuickPriceError(payload.error ?? "Não foi possível atualizar o preço.");
        return;
      }
      setServices((current) => current.map((item) => item.id === service.id ? { ...item, unit_price: payload.unitPrice as number } : item));
      invalidateCatalogClientCache();
      setQuickPriceSuccessId(service.id);
      setQuickPriceId(null);
      setQuickPriceValue("");
    } catch {
      setQuickPriceError("Não foi possível atualizar o preço.");
    } finally {
      setQuickPriceSaving(false);
    }
  }

  function reviewBulkDiscounts(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pricingBusy) return;
    const discounts = parsedBulkDiscounts(bulkDraft);
    if (!discounts) {
      setBulkError("Informe uma porcentagem entre 0% e 100% para cada benefício.");
      return;
    }
    setBulkError("");
    setBulkConfirming(true);
  }

  function closeBulkConfirmation() {
    if (bulkSaving) return;
    setBulkConfirming(false);
    requestAnimationFrame(() => bulkOpenButtonRef.current?.focus());
  }

  async function applyBulkDiscounts() {
    if (bulkSaving) return;
    const discounts = parsedBulkDiscounts(bulkDraft);
    if (!discounts) {
      setBulkConfirming(false);
      setBulkError("Informe uma porcentagem entre 0% e 100% para cada benefício.");
      return;
    }

    setBulkSaving(true);
    setBulkError("");
    setBulkSuccess("");
    try {
      const response = await fetch("/api/services/pricing", {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ action: "bulk_discounts", discounts }),
      });
      const payload = await response.json() as { discounts?: Partial<Record<PlanCode, number>>; error?: string; serviceCount?: number; updatedRows?: number };
      if (!response.ok || !payload.discounts || payload.serviceCount !== services.length) {
        setBulkError(payload.error ?? "Não foi possível aplicar os descontos a todos os itens.");
        setBulkConfirming(false);
        return;
      }
      const applied = Object.fromEntries(BENEFIT_PLANS.map((plan) => [plan.code, Number(payload.discounts?.[plan.code])])) as Record<PlanCode, number>;
      if (Object.values(applied).some((value) => !Number.isFinite(value))) {
        setBulkError("Os descontos foram gravados, mas a confirmação recebida é inválida. Atualize a página para conferir os valores.");
        setBulkConfirming(false);
        return;
      }
      setServices((current) => current.map((service) => ({
        ...service,
        plan_discounts: BENEFIT_PLANS.map((plan) => ({ plan_code: plan.code, discount_percent: applied[plan.code] })),
      })));
      invalidateCatalogClientCache();
      setBulkConfirming(false);
      setBulkSuccess(`Descontos aplicados aos ${payload.serviceCount} itens. ${payload.updatedRows ?? 0} valores foram alterados.`);
      requestAnimationFrame(() => bulkOpenButtonRef.current?.focus());
    } catch {
      setBulkError("Não foi possível aplicar os descontos a todos os itens.");
      setBulkConfirming(false);
    } finally {
      setBulkSaving(false);
    }
  }

  function selectImage(file: File | null) {
    if (!file) return;
    if (!["image/jpeg", "image/png", "image/webp"].includes(file.type) || file.size < 1 || file.size > 2 * 1024 * 1024) {
      setError("Envie uma imagem JPG, PNG ou WebP com até 2 MB.");
      return;
    }
    setError("");
    setDraft((current) => {
      if (!current) return current;
      if (current.previewUrl) URL.revokeObjectURL(current.previewUrl);
      return { ...current, imageFile: file, previewUrl: URL.createObjectURL(file), removeImage: false };
    });
  }

  function removeSelectedImage() {
    setDraft((current) => {
      if (!current) return current;
      if (current.previewUrl) URL.revokeObjectURL(current.previewUrl);
      return { ...current, imageFile: null, previewUrl: null, removeImage: true };
    });
  }

  async function saveChanges(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!draft || !editingService || saving) return;
    const unitPrice = parseNumber(draft.unitPrice);
    const sortOrder = Number(draft.sortOrder);
    const discounts = BENEFIT_PLANS.map((plan) => ({ planCode: plan.code, discountPercent: parseNumber(draft.discounts[plan.code]) }));
    if (
      draft.name.trim().length < 2 || draft.category.trim().length < 2 || draft.icon.trim().length < 1
      || unitPrice < 0 || !Number.isSafeInteger(sortOrder)
      || discounts.some((discount) => discount.discountPercent < 0 || discount.discountPercent > 100)
    ) {
      setError("Revise os dados do item, o preço e os descontos antes de salvar.");
      return;
    }

    setSaving(true); setError(""); setSuccessId(null);
    try {
      const response = await fetch("/api/services", {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ active: draft.active, category: draft.category.trim(), discounts, icon: draft.icon.trim(), id: editingService.id, name: draft.name.trim(), sortOrder, unitPrice }),
      });
      const payload = (await response.json()) as { error?: string; service?: CatalogService };
      if (!response.ok || !payload.service) { setError(payload.error ?? "Não foi possível salvar as alterações."); return; }

      let updated = payload.service;
      if (draft.imageFile) {
        const form = new FormData();
        form.set("file", draft.imageFile);
        form.set("serviceId", String(editingService.id));
        const imageResponse = await fetch("/api/services/image", { method: "POST", body: form });
        const imagePayload = (await imageResponse.json()) as { error?: string; service?: Pick<CatalogService, "id" | "image_path"> };
        if (!imageResponse.ok || !imagePayload.service) {
          commitUpdatedService(updated);
          setError(imagePayload.error ?? "Os dados foram salvos, mas a imagem não pôde ser atualizada.");
          return;
        }
        updated = { ...updated, image_path: imagePayload.service.image_path };
      } else if (draft.removeImage && editingService.image_path) {
        const imageResponse = await fetch(`/api/services/image?id=${editingService.id}`, { method: "DELETE" });
        const imagePayload = (await imageResponse.json()) as { error?: string; service?: Pick<CatalogService, "id" | "image_path"> };
        if (!imageResponse.ok || !imagePayload.service) {
          commitUpdatedService(updated);
          setError(imagePayload.error ?? "Os dados foram salvos, mas a imagem não pôde ser removida.");
          return;
        }
        updated = { ...updated, image_path: null };
      }

      commitUpdatedService(updated);
      setSuccessId(updated.id);
      clearPreview();
      setEditingId(null);
      setDraft(null);
    } catch {
      setError("Não foi possível salvar as alterações.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="catalog-unified-management">
      <section className="management-card catalog-unified-card">
        <div className="section-title catalog-unified-heading">
          <div><p className="eyebrow">{canManage ? "Catálogo administrativo" : "Consulta institucional"}</p><h2>Tabela de Preços</h2><p>{canManage ? "Administre catálogo, preços, descontos e imagens de cada item em um único local." : "Visualização somente leitura dos preços e descontos vigentes."}</p></div>
          <span className="count-pill">{services.length} itens</span>
        </div>
        {canManage ? <form className="catalog-bulk-discounts" onSubmit={reviewBulkDiscounts}>
          <div className="catalog-bulk-copy"><span aria-hidden="true">%</span><div><strong>Descontos em massa</strong><p>Defina os três percentuais e aplique de uma vez a todos os itens. Atendimentos já registrados não serão alterados.</p></div></div>
          <div className="catalog-bulk-fields">
            {BENEFIT_PLANS.map((plan) => (
              <label key={plan.code}>{bulkPlanName(plan.code)}<span><input aria-label={`Desconto de ${plan.name} para todos os itens`} disabled={pricingBusy} inputMode="decimal" max="100" min="0" placeholder="0" required step="0.01" type="number" value={bulkDraft[plan.code]} onChange={(event) => updateBulkDiscount(plan.code, event.target.value)} /><i>%</i></span></label>
            ))}
          </div>
          <button className="catalog-bulk-apply" disabled={pricingBusy || !services.length} ref={bulkOpenButtonRef} type="submit">Aplicar a todos os itens</button>
        </form> : null}
        {bulkError ? <p className="form-error catalog-bulk-message" role="alert">{bulkError}</p> : null}
        {bulkSuccess ? <p className="catalog-bulk-success" role="status">✓ {bulkSuccess}</p> : null}
        {error && !editingId ? <p className="form-error" role="alert">{error}</p> : null}
        {quickPriceError ? <p className="form-error" role="alert">{quickPriceError}</p> : null}
        <div className="catalog-unified-table" role="table" aria-label="Tabela de Preços">
          <div className="catalog-unified-row catalog-unified-head" role="row"><span>Item</span><span>Categoria</span><span>Preço</span><span>Descontos dos planos</span><span>Status</span><span>Ação</span></div>
          {services.map((service) => (
            <div className="catalog-unified-row" role="row" key={service.id}>
              <div className="catalog-unified-item"><CatalogImage alt={`Imagem de ${service.name}`} icon={service.icon} imagePath={service.image_path} imageUrl={service.image_url} serviceId={service.id} size="small" /><span><strong>{service.name}</strong><small>{service.code}</small></span></div>
              <span>{service.category}</span>
              <div className="catalog-quick-price">
                {quickPriceId === service.id ? (
                  <form aria-label={`Alterar preço de ${service.name}`} onSubmit={(event) => saveQuickPrice(event, service)}>
                    <span>R$</span><input aria-label={`Novo preço de ${service.name}`} autoFocus disabled={quickPriceSaving} inputMode="decimal" min="0" onKeyDown={quickPriceKeyDown} required step="0.01" type="number" value={quickPriceValue} onChange={(event) => setQuickPriceValue(event.target.value)} />
                    <button aria-label={`Salvar preço de ${service.name}`} disabled={quickPriceSaving} title="Salvar preço" type="submit">{quickPriceSaving ? "…" : "✓"}</button>
                    <button aria-label={`Cancelar alteração de preço de ${service.name}`} disabled={quickPriceSaving} onClick={cancelQuickPrice} title="Cancelar" type="button">×</button>
                  </form>
                ) : (
                  <><strong>{formatMoney(service.unit_price)}</strong>{canManage ? <button aria-label={`Alterar rapidamente o preço de ${service.name}`} disabled={pricingBusy} onClick={() => openQuickPrice(service)} type="button">{quickPriceSuccessId === service.id ? "✓ Salvo" : "Alterar"}</button> : null}</>
                )}
              </div>
              <div className="catalog-discount-summary">{BENEFIT_PLANS.map((plan) => <span key={plan.code}><b>{shortPlanName(plan.code)}</b>{formatPercent(discountFor(service, plan.code))}</span>)}</div>
              <em data-status={service.active ? "active" : "inactive"}>{service.active ? "Ativo" : "Inativo"}</em>
              {canManage ? <button className="table-action catalog-edit-button" disabled={pricingBusy} type="button" onClick={() => openEditor(service)}>{successId === service.id ? "✓ Editar" : "Editar"}</button> : <span>Somente leitura</span>}
            </div>
          ))}
        </div>
      </section>

      {canManage && bulkConfirming ? (
        <div className="catalog-bulk-dialog-overlay" role="presentation" onMouseDown={(event) => event.target === event.currentTarget && closeBulkConfirmation()}>
          <div aria-describedby="catalog-bulk-dialog-description" aria-labelledby="catalog-bulk-dialog-title" aria-modal="true" className="catalog-bulk-dialog" ref={bulkDialogRef} role="dialog">
            <span className="catalog-bulk-dialog-icon" aria-hidden="true">%</span>
            <p className="eyebrow">Confirmar ajuste em massa</p>
            <h2 id="catalog-bulk-dialog-title">Aplicar os mesmos descontos aos {services.length} itens?</h2>
            <p id="catalog-bulk-dialog-description">Os percentuais atuais de cada item serão substituídos. Preços e atendimentos anteriores permanecerão intactos.</p>
            <div className="catalog-bulk-review">{BENEFIT_PLANS.map((plan) => <span key={plan.code}><small>{bulkPlanName(plan.code)}</small><strong>{formatPercent(parseNumber(bulkDraft[plan.code]))}</strong></span>)}</div>
            <footer><button className="secondary-button" disabled={bulkSaving} onClick={closeBulkConfirmation} type="button">Cancelar</button><button className="submit-button" disabled={bulkSaving} onClick={applyBulkDiscounts} type="button">{bulkSaving ? "Aplicando…" : `Aplicar a ${services.length} itens`}</button></footer>
          </div>
        </div>
      ) : null}

      {canManage && editingService && draft ? (
        <div className="catalog-drawer-overlay" role="presentation" onMouseDown={(event) => event.target === event.currentTarget && closeEditor()}>
          <aside aria-labelledby="catalog-drawer-title" aria-modal="true" className="catalog-drawer" role="dialog">
            <header><div><p className="eyebrow">Editar item</p><h2 id="catalog-drawer-title">{editingService.name}</h2></div><button aria-label="Fechar edição" disabled={saving} onClick={closeEditor} type="button">×</button></header>
            <form onSubmit={saveChanges}>
              <section className="catalog-drawer-section catalog-drawer-image-section">
                <div className="catalog-drawer-image">{draft.previewUrl ? <span className="catalog-image catalog-image-preview"><img alt={`Prévia de ${draft.name}`} src={draft.previewUrl} /></span> : <CatalogImage alt={`Imagem de ${draft.name}`} icon={draft.icon || editingService.icon} imagePath={draft.removeImage ? null : editingService.image_path} imageUrl={draft.removeImage ? null : editingService.image_url} serviceId={editingService.id} size="preview" />}</div>
                <div><strong>Imagem do item</strong><small>JPG, PNG ou WebP · até 2 MB</small><div className="catalog-drawer-image-actions"><label>Trocar imagem<input accept="image/jpeg,image/png,image/webp,.jpg,.jpeg,.png,.webp" disabled={saving} onChange={(event) => selectImage(event.target.files?.[0] ?? null)} type="file" /></label><button disabled={saving || (!editingService.image_path && !draft.previewUrl)} onClick={removeSelectedImage} type="button">Remover imagem</button></div></div>
              </section>

              <section className="catalog-drawer-section"><h3>Identificação</h3><div className="catalog-drawer-grid">
                <label className="catalog-field-wide">Nome<input maxLength={100} minLength={2} required value={draft.name} onChange={(event) => updateDraft("name", event.target.value)} /></label>
                <label>Categoria<input list="catalog-categories" maxLength={60} minLength={2} required value={draft.category} onChange={(event) => updateDraft("category", event.target.value)} /><datalist id="catalog-categories">{categories.map((category) => <option key={category} value={category} />)}</datalist></label>
                <label>Ícone padrão<input maxLength={12} minLength={1} required value={draft.icon} onChange={(event) => updateDraft("icon", event.target.value)} /></label>
                <label>Código interno<input readOnly value={editingService.code} /></label>
                <label>Ordem de exibição<input max={10000} min={-10000} required type="number" value={draft.sortOrder} onChange={(event) => updateDraft("sortOrder", event.target.value)} /></label>
                <label>Status<select value={draft.active ? "active" : "inactive"} onChange={(event) => updateDraft("active", event.target.value === "active")}><option value="active">Ativo</option><option value="inactive">Inativo</option></select></label>
              </div></section>

              <section className="catalog-drawer-section"><h3>Preço e benefícios</h3><div className="catalog-drawer-grid">
                <label className="catalog-field-wide">Preço vigente<span className="catalog-drawer-money"><i>R$</i><input inputMode="decimal" min="0" required step="0.01" type="number" value={draft.unitPrice} onChange={(event) => updateDraft("unitPrice", event.target.value)} /></span></label>
                {BENEFIT_PLANS.map((plan) => <label key={plan.code}>{plan.name}<span className="catalog-drawer-percent"><input inputMode="decimal" max="100" min="0" required step="0.01" type="number" value={draft.discounts[plan.code]} onChange={(event) => updateDiscount(plan.code, event.target.value)} /><i>%</i></span></label>)}
              </div><p className="catalog-drawer-note">Os descontos continuam sendo aplicados automaticamente conforme o plano do paciente.</p></section>

              {error ? <p className="form-error" role="alert">{error}</p> : null}
              <footer><button className="secondary-button" disabled={saving} onClick={closeEditor} type="button">Cancelar</button><button className="submit-button" disabled={saving} type="submit">{saving ? "Salvando…" : "Salvar alterações"}</button></footer>
            </form>
          </aside>
        </div>
      ) : null}
    </div>
  );
}

function toDraft(service: CatalogService): ItemDraft {
  return { active: service.active, category: service.category, discounts: Object.fromEntries(BENEFIT_PLANS.map((plan) => [plan.code, String(discountFor(service, plan.code))])) as Record<PlanCode, string>, icon: service.icon, imageFile: null, name: service.name, previewUrl: null, removeImage: false, sortOrder: String(service.sort_order), unitPrice: String(Number(service.unit_price)) };
}

function replaceService(services: CatalogService[], updated: CatalogService) {
  return services.map((service) => service.id === updated.id ? updated : service).sort((a, b) => a.sort_order - b.sort_order || a.name.localeCompare(b.name, "pt-BR"));
}

function commonDiscountDraft(services: CatalogService[]) {
  return Object.fromEntries(BENEFIT_PLANS.map((plan) => {
    const values = new Set(services.map((service) => discountFor(service, plan.code)));
    return [plan.code, values.size === 1 ? String([...values][0]) : ""];
  })) as Record<PlanCode, string>;
}

function parsedBulkDiscounts(draft: Record<PlanCode, string>) {
  const discounts = BENEFIT_PLANS.map((plan) => ({ planCode: plan.code, discountPercent: parseNumber(draft[plan.code]) }));
  return discounts.some((discount) => discount.discountPercent < 0 || discount.discountPercent > 100) ? null : discounts;
}

function discountFor(service: CatalogService, planCode: PlanCode) { return Number(service.plan_discounts.find((discount) => discount.plan_code === planCode)?.discount_percent ?? 0); }
function parseNumber(value: string) { const normalized = value.trim().replace(",", "."); if (!normalized) return -1; const number = Number(normalized); return Number.isFinite(number) ? Math.round(number * 100) / 100 : -1; }
function formatMoney(value: number) { return `R$ ${new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(value))}`; }
function formatPercent(value: number) { return `${new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2 }).format(value)}%`; }
function shortPlanName(code: PlanCode) { return code === "plano_saude" ? "Saúde" : code === "parceiros_hp" ? "Parceiros" : "Polícia"; }
function bulkPlanName(code: PlanCode) { return code === "plano_saude" ? "Convênio / Plano" : code === "parceiros_hp" ? "Parceiros do HP" : "Polícia / Arcanjo"; }
