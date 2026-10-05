"use client";

import { useMemo, useState, type FormEvent } from "react";
import { calculateRpQuantity, hasOptionalMedicationUse, RP_FREQUENCY_OPTIONS } from "../lib/rp-medications";
import type { ConsultationPrescription as Prescription, ConsultationPrescriptionItem, RpMedication } from "../lib/consultations";
import { HpsmButton } from "./hpsm-button";

type Draft = {
  itemId: string | null; medicationId: string; source: "ai" | "manual"; reason: string; dose: string; frequency: string;
  durationDays: number; route: string; instructions: string; justification: string; finalQuantity: number; overrideReason: string;
};

export function ConsultationPrescription({ consultationId, editable, medications, onBeforeMutate, onChanged, patientAllergies, prescription }: {
  consultationId: number; editable: boolean; medications: RpMedication[]; patientAllergies: string | null;
  prescription: Prescription | null; onBeforeMutate: () => Promise<boolean>; onChanged: () => Promise<void>;
}) {
  const [draft, setDraft] = useState<Draft | null>(null);
  const [manualMedicationId, setManualMedicationId] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const items = prescription?.items ?? [];
  const medicationMap = useMemo(() => new Map(medications.map((item) => [item.id, item])), [medications]);

  async function mutate(body: Record<string, unknown>) {
    if (!await onBeforeMutate()) return false;
    setBusy(true); setError("");
    try {
      const response = await fetch("/api/consultations/prescription", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ consultationId, ...body }) });
      const payload = await response.json() as { error?: string };
      if (!response.ok) throw new Error(payload.error || "Não foi possível atualizar a prescrição.");
      await onChanged();
      return true;
    } catch (cause) { setError(cause instanceof Error ? cause.message : "Não foi possível atualizar a prescrição."); return false; }
    finally { setBusy(false); }
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!draft) return;
    if (hasOptionalMedicationUse(`${draft.frequency} ${draft.instructions}`)) { setError("Defina uma frequência de uso regular, sem termos condicionais como ‘se necessário’."); return; }
    const calculation = calculateRpQuantity(draft.frequency, draft.durationDays);
    if (!calculation) { setError("Use uma frequência RP suportada e duração entre 1 e 365 dias."); return; }
    if (draft.finalQuantity !== calculation.quantity && draft.overrideReason.trim().length < 3) { setError("Informe o motivo do ajuste manual da quantidade."); return; }
    const ok = await mutate({ action: "upsert", ...draft });
    if (ok) { setDraft(null); setManualMedicationId(""); }
  }

  function openNew(medication: RpMedication, source: "ai" | "manual", reason: string) {
    const calculation = calculateRpQuantity(medication.default_frequency, medication.default_duration_days);
    setDraft({ itemId: null, medicationId: medication.id, source, reason, dose: medication.default_dose, frequency: medication.default_frequency, durationDays: medication.default_duration_days, route: medication.default_route, instructions: medication.default_instructions, justification: "", finalQuantity: calculation?.quantity ?? 1, overrideReason: "" });
  }
  function openExisting(item: ConsultationPrescriptionItem) {
    setDraft({ itemId: item.id, medicationId: item.medication_id, source: item.source, reason: item.reason_snapshot, dose: item.dose_snapshot, frequency: item.frequency_snapshot, durationDays: item.duration_days, route: item.route_snapshot, instructions: item.instructions_snapshot, justification: item.justification_snapshot ?? "", finalQuantity: item.final_quantity_snapshot, overrideReason: item.override_reason ?? "" });
  }
  const calculation = draft ? calculateRpQuantity(draft.frequency, draft.durationDays) : null;
  const selectedMedication = draft ? medicationMap.get(draft.medicationId) : null;

  return <div className="prescription-workspace">
    {patientAllergies ? <p className="prescription-allergy"><strong>Alergias registradas:</strong> {patientAllergies}. A validação do servidor bloqueia medicamentos incompatíveis.</p> : null}
    <div className="prescription-items"><h4>Itens da prescrição</h4>{items.length ? items.map((item) => <article key={item.id}><div><span>{item.source === "ai" ? "Sugestão do sistema" : "Inclusão manual"}</span><strong>{item.rp_name_snapshot} · {item.reference_name_snapshot}</strong><p>{item.dose_snapshot} · {item.frequency_snapshot} · {item.duration_snapshot} · {item.route_snapshot}</p><small>{item.instructions_snapshot} · Quantidade final: {item.final_quantity_snapshot} item(ns){item.quantity_override_snapshot ? " · ajuste manual auditado" : ""}</small></div>{editable ? <div><HpsmButton disabled={busy} onClick={() => openExisting(item)}>Editar</HpsmButton><HpsmButton disabled={busy} variant="destructive" onClick={() => void mutate({ action: "remove", itemId: item.id, reason: "Item removido após revisão clínica." })}>Remover</HpsmButton></div> : null}</article>) : <p className="clinical-muted">Nenhum medicamento definido para esta prescrição.</p>}</div>

    {editable ? <div className="prescription-manual"><label>Adicionar manualmente<select value={manualMedicationId} onChange={(event) => setManualMedicationId(event.target.value)}><option value="">Selecione no catálogo Anjos Pharma</option>{medications.filter((medication) => !items.some((item) => item.medication_id === medication.id)).map((medication) => <option key={medication.id} value={medication.id}>{medication.rp_name} · {medication.reference_name}</option>)}</select></label><HpsmButton disabled={!manualMedicationId || busy} onClick={() => { const medication = medicationMap.get(manualMedicationId); if (medication) openNew(medication, "manual", "Prescrição manual definida pelo profissional."); }}>Adicionar item</HpsmButton></div> : null}

    {draft && selectedMedication ? <form className="prescription-editor" onSubmit={submit}><header><div><span>{draft.itemId ? "Editar posologia" : "Revisar antes de incluir"}</span><h4>{selectedMedication.rp_name} · {selectedMedication.reference_name}</h4></div><button aria-label="Fechar editor" onClick={() => setDraft(null)} type="button">×</button></header><div className="prescription-fields">
      <label className="wide">Motivo clínico<textarea maxLength={1000} required rows={2} value={draft.reason} onChange={(event) => setDraft({ ...draft, reason: event.target.value })} /></label>
      <label>Dose<input maxLength={80} required value={draft.dose} onChange={(event) => setDraft({ ...draft, dose: event.target.value })} /></label>
      <label>Frequência<input list="rp-frequency-options" maxLength={120} required value={draft.frequency} onChange={(event) => { const frequency = event.target.value; const next = calculateRpQuantity(frequency, draft.durationDays); setDraft({ ...draft, frequency, finalQuantity: draft.finalQuantity === calculation?.quantity && next ? next.quantity : draft.finalQuantity }); }} /><datalist id="rp-frequency-options">{RP_FREQUENCY_OPTIONS.map((option) => <option key={option} value={option} />)}</datalist></label>
      <label>Duração em dias<input min={1} max={365} required type="number" value={draft.durationDays} onChange={(event) => { const durationDays = Number(event.target.value); const next = calculateRpQuantity(draft.frequency, durationDays); setDraft({ ...draft, durationDays, finalQuantity: draft.finalQuantity === calculation?.quantity && next ? next.quantity : draft.finalQuantity }); }} /></label>
      <label>Via<input maxLength={120} required value={draft.route} onChange={(event) => setDraft({ ...draft, route: event.target.value })} /></label>
      <label className="wide">Orientações<textarea maxLength={500} required rows={2} value={draft.instructions} onChange={(event) => setDraft({ ...draft, instructions: event.target.value })} /></label>
      {selectedMedication.requires_justification ? <label className="wide">Justificativa clínica obrigatória ({selectedMedication.controlled ? "controlado" : "antibiótico"})<textarea maxLength={1000} minLength={3} required rows={2} value={draft.justification} onChange={(event) => setDraft({ ...draft, justification: event.target.value })} /></label> : null}
      <label>Quantidade calculada<input disabled value={calculation?.quantity ?? "Frequência inválida"} /></label>
      <label>Quantidade final<input min={1} max={1000} required type="number" value={draft.finalQuantity} onChange={(event) => setDraft({ ...draft, finalQuantity: Number(event.target.value) })} /></label>
      {calculation && draft.finalQuantity !== calculation.quantity ? <label className="wide">Motivo do ajuste manual<textarea maxLength={500} minLength={3} required rows={2} value={draft.overrideReason} onChange={(event) => setDraft({ ...draft, overrideReason: event.target.value })} /></label> : null}
    </div><footer><span>Cálculo: administrações por dia × dias. Todo item prescrito possui uso regular.</span><div><HpsmButton variant="ghost" type="button" onClick={() => setDraft(null)}>Cancelar</HpsmButton><HpsmButton loading={busy} variant="primary" type="submit">Salvar item</HpsmButton></div></footer></form> : null}
    {error ? <p className="form-error" role="alert">{error}</p> : null}
  </div>;
}
