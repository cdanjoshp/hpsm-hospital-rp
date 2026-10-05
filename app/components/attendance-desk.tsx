"use client";

import dynamic from "next/dynamic";
import { FormEvent, useEffect, useMemo, useState } from "react";
import { activeAttendancePartnerships, automaticAttendanceBenefit } from "../lib/attendance-benefit-selection";
import { BENEFIT_PLANS, type PlanCode } from "../lib/benefit-plans";
import { getAttendanceItemLimit } from "../lib/attendance-item-limits";
import { isWalkInService } from "../lib/walk-in-sale";
import { isValidBirthDate, todayIso } from "../lib/birth-date";
import { readCatalogCacheVersion } from "../lib/catalog-client-cache";
import type { CatalogService, Patient } from "../lib/operational-data";
import { formatPatientPassport, normalizePatientPassport } from "../lib/passport";
import { clearOptionalHpsmPhonePrefix, ensureHpsmPhonePrefix, formatHpsmPhoneInput, parseOptionalEmergencyContact, parseOptionalHpsmPhone } from "../lib/phone";
import { CatalogImage } from "./catalog-image";
import { clearPatientPassportLookupCache, PatientPassportCombobox, type PatientPassportLookupState } from "./patient-passport-combobox";

const PatientEditForm = dynamic(() => import("./patient-edit-form").then((module) => module.PatientEditForm));

const CATALOG_CACHE_TTL_MS = 60_000;

type TimedCache<T> = { expiresAt: number; value: T };
type CatalogTimedCache = TimedCache<CatalogService[]> & { version: string };

let catalogCache: CatalogTimedCache | null = null;
let catalogMetadataRequest: Promise<CatalogService[]> | null = null;
let catalogImagesRequest: Promise<CatalogService[]> | null = null;

function readCatalogCache() {
  if (!catalogCache || catalogCache.expiresAt <= Date.now() || catalogCache.version !== readCatalogCacheVersion()) {
    catalogCache = null;
    return null;
  }
  return catalogCache.value;
}

function writeCatalogCache(services: CatalogService[]) {
  catalogCache = { expiresAt: Date.now() + CATALOG_CACHE_TTL_MS, value: services, version: readCatalogCacheVersion() };
}

async function requestCatalogMetadata() {
  if (catalogMetadataRequest) return catalogMetadataRequest;
  catalogMetadataRequest = (async () => {
    const response = await fetch("/api/services", { cache: "no-store" });
    const payload = (await response.json()) as { error?: string; services?: CatalogService[] };
    if (!response.ok || !payload.services) throw new Error(payload.error ?? "Não foi possível consultar a tabela de preços.");
    writeCatalogCache(payload.services);
    return payload.services;
  })();
  try {
    return await catalogMetadataRequest;
  } finally {
    catalogMetadataRequest = null;
  }
}

async function requestCatalogImages(services: CatalogService[]) {
  const servicesWithImages = services.filter((service) => service.image_path && !service.image_url);
  if (!servicesWithImages.length) return services;
  if (catalogImagesRequest) return catalogImagesRequest;
  catalogImagesRequest = (async () => {
    const response = await fetch("/api/services/images", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ serviceIds: servicesWithImages.map((service) => service.id) }),
      cache: "no-store",
    });
    const payload = (await response.json()) as { images?: Record<string, string> };
    if (!response.ok || !payload.images) return services;
    const resolved = services.map((service) => {
      const imageUrl = payload.images?.[String(service.id)];
      return imageUrl ? { ...service, image_url: imageUrl } : service;
    });
    writeCatalogCache(resolved);
    return resolved;
  })();
  try {
    return await catalogImagesRequest;
  } finally {
    catalogImagesRequest = null;
  }
}

export function AttendanceDesk({
  canManagePatients,
  canRecordAttendance,
  isDirector,
  services,
  initialPatient = null,
}: {
  canManagePatients: boolean;
  canRecordAttendance: boolean;
  isDirector: boolean;
  services: CatalogService[];
  initialPatient?: Patient | null;
}) {
  const [catalogServices, setCatalogServices] = useState(services);
  const [catalogError, setCatalogError] = useState("");
  const [catalogLoading, setCatalogLoading] = useState(!services.length);
  const [catalogReload, setCatalogReload] = useState(0);
  const activeServices = useMemo(() => catalogServices.filter((service) => service.active), [catalogServices]);
  const [cart, setCart] = useState<Record<number, number>>({});
  const [error, setError] = useState("");
  const [isWalkInSale, setIsWalkInSale] = useState(false);
  const [loading, setLoading] = useState(false);
  const [patient, setPatient] = useState<Patient | null>(initialPatient);
  const [patientEditing, setPatientEditing] = useState(false);
  const [patientError, setPatientError] = useState("");
  const [patientLoading, setPatientLoading] = useState(false);
  const [patientBirthDate, setPatientBirthDate] = useState("");
  const [patientAllergies, setPatientAllergies] = useState("");
  const [patientName, setPatientName] = useState("");
  const [patientPhone, setPatientPhone] = useState("");
  const [selectedBenefitCode, setSelectedBenefitCode] = useState<PlanCode | null>(initialPatient ? automaticAttendanceBenefit(initialPatient).benefitCode : null);
  const [selectedPartnershipId, setSelectedPartnershipId] = useState<number | null>(initialPatient ? automaticAttendanceBenefit(initialPatient).partnershipId : null);
  const [emergencyContactName, setEmergencyContactName] = useState("");
  const [emergencyContactPhone, setEmergencyContactPhone] = useState("");
  const [patientStatus, setPatientStatus] = useState("");
  const [passport, setPassport] = useState(initialPatient?.passport ?? "");
  const [lookupState, setLookupState] = useState<PatientPassportLookupState>("idle");
  const [notes, setNotes] = useState("");
  const [success, setSuccess] = useState("");

  const availableServices = isWalkInSale
    ? activeServices.filter(isWalkInService)
    : activeServices;
  const selectedBenefit = selectedBenefitCode
    ? BENEFIT_PLANS.find((plan) => plan.code === selectedBenefitCode) ?? null
    : null;
  const activePatientPartnerships = patient ? activeAttendancePartnerships(patient) : [];
  const selected = availableServices
    .filter((service) => cart[service.id])
    .map((service) => ({
      ...service,
      quantity: cart[service.id],
      discountPercent: selectedBenefitCode ? discountFor(service, selectedBenefitCode) : 0,
    }));
  const subtotal = selected.reduce((total, service) => total + Number(service.unit_price) * service.quantity, 0);
  const discountValue = selected.reduce((total, service) => total + roundMoney(
    Number(service.unit_price) * service.quantity * service.discountPercent / 100,
  ), 0);
  const total = Math.max(0, subtotal - discountValue);

  useEffect(() => {
    let active = true;

    async function loadCatalog() {
      await Promise.resolve();
      if (!active) return;
      const seeded = services.length ? services : readCatalogCache();
      if (seeded?.length) {
        setCatalogServices(seeded);
        setCatalogLoading(false);
        writeCatalogCache(seeded);
      } else {
        setCatalogLoading(true);
      }
      setCatalogError("");

      try {
        const metadata = services.length ? services : await requestCatalogMetadata();
        const seededById = new Map((seeded ?? []).map((service) => [service.id, service]));
        const displayMetadata = metadata.map((service) => {
          const cachedService = seededById.get(service.id);
          return cachedService?.image_path === service.image_path && cachedService.image_url
            ? { ...service, image_url: cachedService.image_url }
            : service;
        });
        writeCatalogCache(displayMetadata);
        if (active) {
          setCatalogServices(displayMetadata);
          setCatalogLoading(false);
        }
        const withImages = await requestCatalogImages(displayMetadata);
        if (active) setCatalogServices(withImages);
      } catch (cause) {
        if (!active) return;
        setCatalogLoading(false);
        setCatalogError(cause instanceof Error ? cause.message : "Não foi possível consultar a tabela de preços.");
      }
    }

    void loadCatalog();
    return () => { active = false; };
  }, [catalogReload, services]);

  useEffect(() => {
    const match = window.location.hash.match(/^#atendimento-(\d+)$/);
    if (match) window.location.replace(`/atendimentos/registro/${match[1]}`);
  }, []);

  function changeQuantity(serviceId: number, quantity: number) {
    const service = availableServices.find((item) => item.id === serviceId);
    const maximum = service?.code === "plano_saude_convenio" ? 1 : 99;
    setCart((current) => {
      const next = { ...current };
      if (quantity <= 0) delete next[serviceId];
      else next[serviceId] = Math.min(maximum, quantity);
      return next;
    });
  }

  function changeBenefit(nextBenefitCode: PlanCode | null) {
    setSelectedBenefitCode(nextBenefitCode);
    setSelectedPartnershipId(
      nextBenefitCode === "parceiros_hp" && activePatientPartnerships.length === 1
        ? activePatientPartnerships[0].id
        : null,
    );
  }

  function changePassport(value: string) {
    setPassport(value);
    setPatient(null);
    setIsWalkInSale(false);
    setPatientEditing(false);
    setLookupState("idle");
    setPatientError("");
    setPatientStatus("");
    setPatientName("");
    setPatientPhone("");
    setPatientBirthDate("");
    setPatientAllergies("");
    setSelectedBenefitCode(null);
    setSelectedPartnershipId(null);
    setEmergencyContactName("");
    setEmergencyContactPhone("");
    setNotes("");
  }

  function selectPatient(selectedPatient: Patient) {
    const automaticBenefit = automaticAttendanceBenefit(selectedPatient);
    setPatient(selectedPatient);
    setIsWalkInSale(false);
    setSelectedBenefitCode(automaticBenefit.benefitCode);
    setSelectedPartnershipId(automaticBenefit.partnershipId);
    setPatientEditing(false);
    setPassport(selectedPatient.passport);
    setLookupState("idle");
    setPatientError("");
    setPatientStatus("");
    setPatientName("");
    setPatientPhone("");
    setPatientBirthDate("");
    setPatientAllergies("");
    setEmergencyContactName("");
    setEmergencyContactPhone("");
    setNotes("");
  }

  async function registerPatient() {
    if (patientLoading) return;
    setPatientError("");
    setPatientStatus("");
    let canonicalPassport: string;
    try {
      canonicalPassport = normalizePatientPassport(passport);
    } catch (cause) {
      setPatientError(cause instanceof Error ? cause.message : "Informe um passaporte válido com 1 a 4 números.");
      return;
    }
    if (patientName.trim().length < 2) {
      setPatientError("Informe o nome completo do paciente.");
      return;
    }
    if (!patientAllergies.trim()) {
      setPatientError("Informe as alergias do paciente ou registre “Não possui”.");
      return;
    }
    const primaryPhone = parseOptionalHpsmPhone(patientPhone);
    if (primaryPhone.error) {
      setPatientError(primaryPhone.error);
      return;
    }
    if (patientBirthDate && !isValidBirthDate(patientBirthDate)) {
      setPatientError("Informe uma data de nascimento válida.");
      return;
    }
    const emergencyContact = parseOptionalEmergencyContact(emergencyContactName, emergencyContactPhone);
    if (emergencyContact.error) {
      setPatientError(emergencyContact.error);
      return;
    }

    setPatientLoading(true);
    try {
      const response = await fetch("/api/patients", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          allergies: patientAllergies,
          birthDate: patientBirthDate,
          name: patientName,
          passport: canonicalPassport,
          phone: primaryPhone.phone,
          emergencyContactName: emergencyContact.name,
          emergencyContactPhone: emergencyContact.phone,
        }),
      });
      const payload = (await response.json()) as { error?: string; patient?: Patient };
      if (!response.ok || !payload.patient) {
        setPatientError(payload.error ?? "Não foi possível cadastrar o paciente.");
        return;
      }
      clearPatientPassportLookupCache();
      const automaticBenefit = automaticAttendanceBenefit(payload.patient);
      setPatient(payload.patient);
      setIsWalkInSale(false);
      setSelectedBenefitCode(automaticBenefit.benefitCode);
      setSelectedPartnershipId(automaticBenefit.partnershipId);
      setPatientEditing(false);
      setLookupState("idle");
      setPatientName("");
      setPatientPhone("");
      setPatientBirthDate("");
      setPatientAllergies("");
      setEmergencyContactName("");
      setEmergencyContactPhone("");
      setPatientStatus("Paciente cadastrado e selecionado para o atendimento.");
    } catch {
      setPatientError("Não foi possível cadastrar o paciente.");
    } finally {
      setPatientLoading(false);
    }
  }

  function clearPatient() {
    setPatient(null);
    setIsWalkInSale(false);
    setPatientEditing(false);
    setPassport("");
    setLookupState("idle");
    setPatientError("");
    setPatientStatus("");
    setPatientName("");
    setPatientPhone("");
    setPatientBirthDate("");
    setPatientAllergies("");
    setSelectedBenefitCode(null);
    setSelectedPartnershipId(null);
    setEmergencyContactName("");
    setEmergencyContactPhone("");
    setNotes("");
    setCart({});
    setError("");
  }

  function startWalkInSale() {
    setPatient(null);
    setIsWalkInSale(true);
    setPatientEditing(false);
    setPassport("");
    setLookupState("idle");
    setPatientError("");
    setPatientStatus("");
    setPatientName("");
    setPatientPhone("");
    setPatientBirthDate("");
    setPatientAllergies("");
    setSelectedBenefitCode(null);
    setSelectedPartnershipId(null);
    setEmergencyContactName("");
    setEmergencyContactPhone("");
    setNotes("");
    setCart({});
    setError("");
  }

  function leaveWalkInSale() {
    setIsWalkInSale(false);
    setSelectedBenefitCode(null);
    setSelectedPartnershipId(null);
    setNotes("");
    setCart({});
    setError("");
  }

  function resetAttendanceFormAfterSuccess() {
    setPatient(null);
    setIsWalkInSale(false);
    setPatientEditing(false);
    setPassport("");
    setLookupState("idle");
    setPatientError("");
    setPatientStatus("");
    setPatientName("");
    setPatientPhone("");
    setPatientBirthDate("");
    setPatientAllergies("");
    setEmergencyContactName("");
    setEmergencyContactPhone("");
    setSelectedBenefitCode(null);
    setSelectedPartnershipId(null);
    setCart({});
    setNotes("");
  }

  function startPatientEdit() {
    if (!patient || !canManagePatients) return;
    setPatientEditing(true);
    setPatientError("");
    setPatientStatus("");
  }

  function cancelPatientEdit() {
    if (!patient) return;
    setPatientEditing(false);
    setPassport(patient.passport);
    setPatientError("");
  }

  async function submitAttendance(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!canRecordAttendance) {
      setError("");
      setSuccess("Simulação atualizada. Nenhum atendimento ou venda foi registrado.");
      return;
    }
    if (loading) return;
    setError("");
    setSuccess("");
    if (!patient && !isWalkInSale) {
      setError("Localize ou cadastre o paciente pelo passaporte antes de registrar.");
      return;
    }
    if (!selected.length) {
      setError("Adicione ao menos um item.");
      return;
    }
    if (selectedBenefitCode === "parceiros_hp" && !selectedPartnershipId) {
      setError("Selecione qual parceria será utilizada neste atendimento.");
      return;
    }
    setLoading(true);
    try {
      const response = await fetch("/api/attendances", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          patientId: patient?.id ?? null,
          benefitCode: selectedBenefitCode,
          partnershipId: selectedBenefitCode === "parceiros_hp" ? selectedPartnershipId : null,
          notes: isWalkInSale ? notes.trim() || null : null,
          items: selected.map((service) => ({ serviceId: service.id, quantity: service.quantity })),
        }),
      });
      const payload = (await response.json()) as { error?: string; id?: number };
      if (!response.ok || !payload.id) {
        setError(payload.error ?? "Não foi possível registrar o atendimento.");
        return;
      }
      const includesPlan = selected.some((service) => service.code === "plano_saude_convenio");
      if (includesPlan && patient) clearPatientPassportLookupCache();
      setSuccess(includesPlan
        ? `Venda #${payload.id} registrada. O plano aguarda confirmação do corpo clínico.`
        : isWalkInSale ? `Venda avulsa #${payload.id} registrada com sucesso.` : `Atendimento #${payload.id} registrado com sucesso.`);
      resetAttendanceFormAfterSuccess();
      window.dispatchEvent(new Event("hpsm:shell-refresh"));
      window.dispatchEvent(new Event("hpsm:attendance-created"));
    } catch {
      setError("Não foi possível registrar o atendimento.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="attendance-layout">
      <section className="management-card patient-step-card">
        {!canRecordAttendance ? <p className="form-success attendance-submit-message" role="status"><strong>Modo simulação.</strong> Você pode selecionar paciente, benefício e itens para calcular preços e descontos; nada será registrado como venda.</p> : null}
        <div className="section-title">
          <div><p className="eyebrow">Atendimento · Vendas</p><h2>Produtos e procedimentos</h2></div>
        </div>
        {error ? <p className="form-error attendance-submit-message" role="alert">{error}</p> : null}
        {success ? <p className="form-success attendance-submit-message" role="status">{success}</p> : null}
        <div className="attendance-top-row">
        <div className="patient-lookup">
          <div className="attendance-mode" role="group" aria-label="Tipo de atendimento">
            <button type="button" className="attendance-mode-option" data-active={!isWalkInSale} aria-pressed={!isWalkInSale} onClick={isWalkInSale ? leaveWalkInSale : undefined}><span className="attendance-mode-dot" aria-hidden="true" />Atendimento de Paciente</button>
            <button type="button" className="attendance-mode-option" data-active={isWalkInSale} aria-pressed={isWalkInSale} onClick={isWalkInSale ? undefined : startWalkInSale}><span className="attendance-mode-dot" aria-hidden="true" />Venda Avulsa</button>
          </div>
          <div className="patient-lookup-heading">
            <div className="patient-lookup-copy">
              <span>Cadastro do paciente</span>
              <strong>{
                patientEditing ? "Alterar informações" :
                patient ? "Confira os dados antes de prosseguir" :
                isWalkInSale ? "Venda sem vínculo com paciente" :
                lookupState === "not-found" ? "Novo cadastro" :
                lookupState === "results" ? "Selecione na lista" :
                lookupState === "searching" ? "Localizando pacientes…" :
                "Digite o passaporte"
              }</strong>
            </div>
            <div className="patient-lookup-actions">
              {patient && !patientEditing ? <span className="lookup-confirmed">✓ Localizado</span> : null}
            </div>
          </div>

          {!patient && !isWalkInSale ? (
            <div className="passport-search-row">
              <PatientPassportCombobox
                className="passport-search"
                label="Passaporte"
                value={passport}
                selectedPatient={patient}
                showSelectedSummary={false}
                onLookupStateChange={setLookupState}
                onSelect={selectPatient}
                onValueChange={changePassport}
              />
            </div>
          ) : null}

          {(patient || isWalkInSale) && !patientEditing ? (
            <div className="selected-patient" data-walk-in={isWalkInSale}>
              <span className="patient-avatar">{patient ? initials(patient.name) : "AV"}</span>
              <div className="selected-patient-details">
                {patient ? <>
                  <strong>{patient.name}</strong>
                  <p>Passaporte {formatPatientPassport(patient.passport)} · Telefone {patient.phone ?? "não informado"}</p>
                  {patient.emergency_contact_name && patient.emergency_contact_phone ? <p>Emergência: {patient.emergency_contact_name} · {patient.emergency_contact_phone}</p> : null}
                  <p className="selected-patient-allergies"><strong>Alergias:</strong> {patient.allergies ?? "Alergias não informadas"}</p>
                  <span className="patient-plan-badge" data-status={patient.health_plan.status}>{healthPlanStatusLabel(patient)}</span>
                  {patient.health_plan.pending_request_id && patient.health_plan.status !== "awaiting_confirmation" ? (
                    <span className="patient-plan-pending">{patient.health_plan.status === "active" ? "Renovação aguardando confirmação" : "Nova ativação aguardando confirmação"}</span>
                  ) : null}
                  {patient.health_plan.authorized_by_name && patient.health_plan.activated_at ? (
                    <small className="patient-plan-meta">Ativação em {formatDay(patient.health_plan.activated_at)} · autorizada por {patient.health_plan.authorized_by_name}</small>
                  ) : null}
                </> : <>
                  <strong>Venda avulsa</strong>
                  <p>Sem paciente vinculado · insumos, medicamentos, tratamento e deslocamentos</p>
                </>}
              </div>
              <div className="patient-benefit-selector">
                <span>Benefício deste atendimento</span>
                <div aria-label="Benefício aplicado nesta venda" role="radiogroup">
                  {BENEFIT_PLANS.map((plan) => (
                    <button
                      aria-checked={selectedBenefitCode === plan.code}
                      data-active={selectedBenefitCode === plan.code}
                      disabled={Boolean(patient?.health_plan.status === "active" && plan.code !== "plano_saude") || Boolean(plan.code === "parceiros_hp" && !activePatientPartnerships.length)}
                      key={plan.code}
                      role="radio"
                      type="button"
                      onClick={() => {
                        const next = selectedBenefitCode === plan.code ? null : plan.code;
                        changeBenefit(next);
                      }}
                    >
                      {benefitShortName(plan.code)}
                    </button>
                  ))}
                </div>
                {!selectedBenefit ? <small>Nenhum benefício aplicado</small> : null}
                {patient?.health_plan.status === "active" ? <small>O Plano de Saúde ativo tem prioridade neste atendimento.</small> : null}
                {selectedBenefitCode === "parceiros_hp" && activePatientPartnerships.length ? <label className="attendance-partnership-picker"><span>Parceria utilizada</span><select required value={selectedPartnershipId ?? ""} onChange={(event) => setSelectedPartnershipId(Number(event.target.value))}>{selectedPartnershipId === null ? <option value="" disabled>Selecione uma parceria</option> : null}{activePatientPartnerships.map((partnership) => <option key={partnership.id} value={partnership.id}>{partnership.name}</option>)}</select></label> : null}
                {patient && !activePatientPartnerships.length && patient.health_plan.status !== "active" ? <small>Paciente sem parceria ativa.</small> : null}
              </div>
              <div className="selected-patient-actions">
                {patient ? <>
                  {canManagePatients ? <button className="edit-patient-button" type="button" onClick={startPatientEdit} disabled={loading}>Alterar cadastro</button> : null}
                  <button type="button" onClick={clearPatient} disabled={loading}>Trocar paciente</button>
                </> : <button type="button" onClick={leaveWalkInSale} disabled={loading}>Selecionar paciente</button>}
              </div>
              {isWalkInSale ? (
                <details className="walk-in-notes">
                  <summary>Adicionar observação</summary>
                  <label>
                    <span>Observação da venda</span>
                    <textarea maxLength={1000} value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Informação opcional para o histórico" />
                  </label>
                </details>
              ) : null}
            </div>
          ) : patient && patientEditing ? (
            <PatientEditForm
              patient={patient}
              onCancel={cancelPatientEdit}
              onSaved={(updatedPatient) => {
                clearPatientPassportLookupCache();
                setPatient(updatedPatient);
                setPassport(updatedPatient.passport);
                setPatientEditing(false);
                setPatientStatus("Cadastro do paciente atualizado com sucesso.");
              }}
            />
          ) : lookupState === "not-found" ? (
            <div className="patient-registration">
              <div className="not-found-note"><span>＋</span><p><strong>Passaporte não cadastrado</strong>Preencha os dados abaixo para criar a ficha do paciente.</p></div>
              <div className="patient-registration-grid">
                <label>Passaporte<input readOnly value={passport.trim()} /></label>
                <label>Nome completo<input required minLength={2} maxLength={100} value={patientName} onChange={(event) => setPatientName(event.target.value)} placeholder="Maria Exemplo da Silva" /></label>
                <label>Telefone de contato (opcional)<input type="tel" inputMode="numeric" maxLength={13} pattern="\(055\) [0-9]{3}-[0-9]{3}" value={patientPhone} onFocus={() => setPatientPhone((current) => ensureHpsmPhonePrefix(current))} onBlur={() => setPatientPhone((current) => clearOptionalHpsmPhonePrefix(current))} onChange={(event) => setPatientPhone(formatHpsmPhoneInput(event.target.value))} placeholder="(055) 123-456" /></label>
                <label>Data de nascimento (opcional)<input type="date" max={todayIso()} value={patientBirthDate} onChange={(event) => setPatientBirthDate(event.target.value)} aria-describedby="attendance-birth-date-hint" /><small id="attendance-birth-date-hint">DD/MM/AAAA</small></label>
                <label>Contato de emergência (opcional)<input maxLength={100} value={emergencyContactName} onChange={(event) => setEmergencyContactName(event.target.value)} placeholder="José Exemplo de Ribeiro" /></label>
                <label>Telefone de emergência (opcional)<input type="tel" inputMode="numeric" maxLength={13} pattern="\(055\) [0-9]{3}-[0-9]{3}" value={emergencyContactPhone} onChange={(event) => setEmergencyContactPhone(formatHpsmPhoneInput(event.target.value))} placeholder="(055) 123-456" /></label>
                <label>Alergias<textarea required maxLength={1000} value={patientAllergies} onChange={(event) => setPatientAllergies(event.target.value)} placeholder="Ex.: Dipirona. Se não houver, registre “Não possui”." /></label>
              </div>
              <button className="register-patient-button" type="button" onClick={registerPatient} disabled={patientLoading}>{patientLoading ? "Cadastrando…" : "Cadastrar e selecionar paciente"}</button>
            </div>
          ) : !patient ? (
            <p className="patient-search-hint">Selecione um paciente para o atendimento completo ou escolha venda avulsa para lançar insumos, medicamentos, tratamento e deslocamentos.</p>
          ) : null}

          {patientError ? <p className="form-error" role="alert">{patientError}</p> : null}
          {patientStatus ? <p className="form-success" role="status">{patientStatus}</p> : null}
        </div>
        <form className="attendance-finalize-bar" id="attendance-form" onSubmit={submitAttendance} aria-label="Resumo do atendimento">
          <p className="eyebrow">Resumo do atendimento</p>
          <div className="attendance-financial-line"><span>Subtotal</span><strong>{formatMoney(subtotal)}</strong></div>
          <div className="attendance-financial-line"><span>Desconto do benefício</span><strong>− {formatMoney(discountValue)}</strong></div>
          <div className="attendance-financial-total"><span>Total</span><strong aria-label={`Total atual: ${formatMoney(total)}`}>{formatMoney(total)}</strong></div>
          <button className="submit-button" type="submit" disabled={loading || patientLoading || !selected.length}><span>{canRecordAttendance ? (loading ? "Registrando…" : isWalkInSale ? "Registrar venda" : "Registrar atendimento") : "Atualizar simulação"}</span><span aria-hidden="true">→</span></button>
        </form>
        </div>
      </section>

      {patient || isWalkInSale ? (
        <>
          <section className="management-card service-picker" aria-busy={catalogLoading}>
            <div className="section-title">
              <div><p className="eyebrow">Etapa 2 · Tabela vigente</p><h2>{isWalkInSale ? "Itens da venda avulsa" : "Produtos e procedimentos"}</h2></div>
            </div>
            {catalogLoading && !catalogServices.length ? (
              <div className="compact-empty" role="status"><span>◷</span><strong>Carregando tabela vigente</strong><p>Você já pode localizar o paciente enquanto os itens são preparados.</p></div>
            ) : catalogError && !catalogServices.length ? (
              <div className="compact-empty"><span>!</span><strong>Tabela temporariamente indisponível</strong><p>{catalogError}</p><button className="table-action" type="button" onClick={() => { catalogCache = null; setCatalogReload((current) => current + 1); }}>Tentar novamente</button></div>
            ) : availableServices.length ? (
              <div className="service-card-grid">
                {availableServices.map((service) => {
                  const discountPercent = selectedBenefitCode ? discountFor(service, selectedBenefitCode) : 0;
                  const finalUnitPrice = Number(service.unit_price) * (1 - discountPercent / 100);
                  const quantity = cart[service.id] ?? 0;
                  const itemLimit = getAttendanceItemLimit(service.code, selectedBenefitCode);
                  const maximum = service.code === "plano_saude_convenio" ? 1 : 99;
                  return (
                    <article className="service-product-card" data-selected={quantity > 0} key={service.id}>
                      <CatalogImage alt={`Imagem de ${service.name}`} deferUntilResolved icon={service.icon} imagePath={service.image_path} imageUrl={service.image_url} serviceId={service.id} size="card" />
                      <div className="service-item-copy">
                        <strong>{service.name}</strong>
                      </div>
                      <div className="service-card-price" aria-label={`Preço de ${service.name}`}>
                        {discountPercent > 0 ? <small className="service-discount-badge">−{formatPercent(discountPercent)}</small> : null}
                        {discountPercent > 0 ? <del>{formatMoney(service.unit_price)}</del> : null}
                        <span>{formatMoney(finalUnitPrice)}</span>
                      </div>
                      <div className="service-card-quantity-panel">
                        <ServiceQuantityEditor name={service.name} quantity={quantity} maximum={maximum} onChange={(next) => changeQuantity(service.id, next)} />
                        {itemLimit !== null ? (
                          <div className="service-card-limit-actions">
                            <button aria-label={`Definir quantidade máxima de referência de ${service.name}: ${itemLimit}`} disabled={quantity === itemLimit} onClick={() => changeQuantity(service.id, itemLimit)} type="button">MAX</button>
                            {quantity > 0 ? <button aria-label={`Zerar quantidade de ${service.name}`} onClick={() => changeQuantity(service.id, 0)} type="button">ZERAR</button> : null}
                          </div>
                        ) : null}
                      </div>
                    </article>
                  );
                })}
              </div>
            ) : (
              <div className="compact-empty"><span>＋</span><strong>Nenhum item disponível</strong><p>{isDirector ? "Cadastre os valores na Tabela de Preços para liberar a seleção." : "A Diretoria ainda não publicou a tabela de valores."}</p></div>
            )}
          </section>

        </>
      ) : null}
    </div>
  );
}

function ServiceQuantityEditor({ name, quantity, maximum, onChange }: {
  name: string;
  quantity: number;
  maximum: number;
  onChange: (quantity: number) => void;
}) {
  const [draft, setDraft] = useState<string | null>(null);

  function typeQuantity(value: string) {
    if (!/^\d*$/.test(value)) return;
    const next = value === "" ? 0 : Math.min(maximum, Number(value));
    setDraft(value === "" ? "" : String(next));
    onChange(next);
  }

  return <div className="service-card-quantity" aria-label={`Quantidade de ${name}`}>
    <button aria-label={`Diminuir quantidade de ${name}`} type="button" onClick={() => { setDraft(null); onChange(quantity - 1); }} disabled={quantity === 0}>−</button>
    <input
      aria-label={`Digite a quantidade de ${name}`}
      type="text"
      inputMode="numeric"
      pattern="[0-9]*"
      maxLength={3}
      value={draft ?? String(quantity)}
      onChange={(event) => typeQuantity(event.target.value)}
      onFocus={(event) => event.currentTarget.select()}
      onBlur={() => setDraft(null)}
    />
    <button aria-label={`Aumentar quantidade de ${name}`} type="button" onClick={() => { setDraft(null); onChange(quantity + 1); }} disabled={quantity >= maximum}>＋</button>
  </div>;
}

function formatMoney(value: number) {
  return `R$ ${new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(Number(value))}`;
}

function discountFor(service: CatalogService, planCode: PlanCode) {
  return Number(service.plan_discounts.find((discount) => discount.plan_code === planCode)?.discount_percent ?? 0);
}

function formatPercent(value: number) {
  return `${new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 2 }).format(Number(value))}%`;
}

function roundMoney(value: number) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function formatDay(value: string) {
  return new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "America/Sao_Paulo" }).format(new Date(value));
}

function healthPlanStatusLabel(patient: Patient) {
  const plan = patient.health_plan;
  if (plan.status === "active" && plan.valid_until) return `✓ Plano ativo até ${formatDay(plan.valid_until)}`;
  if (plan.status === "expired" && plan.valid_until) return `Plano expirado em ${formatDay(plan.valid_until)}`;
  if (plan.status === "awaiting_confirmation") return "Plano aguardando confirmação";
  return "Sem plano HPSM ativo";
}

function benefitShortName(code: PlanCode) {
  if (code === "plano_saude") return "Plano de Saúde";
  if (code === "parceiros_hp") return "Parceiro HP";
  return "Polícia/Arcanjo";
}

function initials(name: string) {
  return name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");
}
