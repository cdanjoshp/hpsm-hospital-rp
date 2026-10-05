"use client";

import { useCallback, useEffect, useId, useRef, useState, type KeyboardEvent } from "react";
import type { Patient } from "../lib/operational-data";
import { formatPatientPassport, normalizePatientPassport } from "../lib/passport";
import { readPatientCacheVersion } from "../lib/patient-client-cache";

export type PatientPassportLookupState = "idle" | "searching" | "results" | "not-found" | "error";

type CachedPatients = { expiresAt: number; patients: Patient[]; version: string };

const CACHE_TTL_MS = 60_000;
const DEBOUNCE_MS = 150;
const patientCache = new Map<string, CachedPatients>();

export function clearPatientPassportLookupCache() {
  patientCache.clear();
}

export function PatientPassportCombobox({
  className = "",
  disabled = false,
  label = "Passaporte do paciente",
  onLookupStateChange,
  onSelect,
  onValueChange,
  selectedPatient,
  showSelectedSummary = true,
  value,
}: {
  className?: string;
  disabled?: boolean;
  label?: string;
  onLookupStateChange?: (state: PatientPassportLookupState) => void;
  onSelect: (patient: Patient) => void;
  onValueChange: (value: string) => void;
  selectedPatient: Patient | null;
  showSelectedSummary?: boolean;
  value: string;
}) {
  const reactId = useId();
  const inputId = `patient-passport-${reactId.replace(/:/g, "")}`;
  const listId = `${inputId}-results`;
  const rootRef = useRef<HTMLDivElement>(null);
  const controllerRef = useRef<AbortController | null>(null);
  const timerRef = useRef<number | null>(null);
  const queryRef = useRef("");
  const [activeIndex, setActiveIndex] = useState(0);
  const [lookupState, setLookupState] = useState<PatientPassportLookupState>("idle");
  const [open, setOpen] = useState(false);
  const [patients, setPatients] = useState<Patient[]>([]);

  const updateLookupState = useCallback((state: PatientPassportLookupState) => {
    setLookupState(state);
    onLookupStateChange?.(state);
  }, [onLookupStateChange]);

  const lookup = useCallback(async (passport: string) => {
    queryRef.current = passport;
    const cached = patientCache.get(passport);
    if (cached && cached.expiresAt > Date.now() && cached.version === readPatientCacheVersion()) {
      setPatients(cached.patients);
      setActiveIndex(0);
      setOpen(true);
      updateLookupState(cached.patients.length ? "results" : "not-found");
      return;
    }
    if (cached) patientCache.delete(passport);

    controllerRef.current?.abort();
    const controller = new AbortController();
    controllerRef.current = controller;
    setOpen(true);
    updateLookupState("searching");
    try {
      const response = await fetch(`/api/patients?passport=${encodeURIComponent(passport)}`, {
        cache: "no-store",
        signal: controller.signal,
      });
      const payload = await response.json() as { error?: string; patients?: Patient[] };
      if (queryRef.current !== passport) return;
      if (!response.ok) {
        setPatients([]);
        updateLookupState("error");
        return;
      }
      const results = payload.patients ?? [];
      if (patientCache.size >= 32 && !patientCache.has(passport)) {
        const oldest = patientCache.keys().next().value as string | undefined;
        if (oldest) patientCache.delete(oldest);
      }
      patientCache.set(passport, { expiresAt: Date.now() + CACHE_TTL_MS, patients: results, version: readPatientCacheVersion() });
      setPatients(results);
      setActiveIndex(0);
      updateLookupState(results.length ? "results" : "not-found");
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") return;
      if (queryRef.current !== passport) return;
      setPatients([]);
      updateLookupState("error");
    } finally {
      if (controllerRef.current === controller) controllerRef.current = null;
    }
  }, [updateLookupState]);

  useEffect(() => {
    if (selectedPatient || disabled || !value.trim()) return;
    let normalized: string;
    try {
      normalized = normalizePatientPassport(value);
    } catch {
      return;
    }
    timerRef.current = window.setTimeout(() => {
      timerRef.current = null;
      void lookup(normalized);
    }, DEBOUNCE_MS);
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
      timerRef.current = null;
      controllerRef.current?.abort();
    };
  }, [disabled, lookup, selectedPatient, updateLookupState, value]);

  useEffect(() => {
    function closeOnOutsideClick(event: MouseEvent) {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", closeOnOutsideClick);
    return () => document.removeEventListener("mousedown", closeOnOutsideClick);
  }, []);

  function changeValue(nextValue: string) {
    if (!/^\d{0,4}$/.test(nextValue)) return;
    queryRef.current = "";
    controllerRef.current?.abort();
    setPatients([]);
    setOpen(Boolean(nextValue));
    setActiveIndex(0);
    updateLookupState("idle");
    onValueChange(nextValue);
  }

  function choose(patient: Patient) {
    setOpen(false);
    setPatients([]);
    updateLookupState("idle");
    onSelect(patient);
  }

  function handleKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "Escape") {
      setOpen(false);
      return;
    }
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      if (!patients.length) return;
      event.preventDefault();
      setOpen(true);
      setActiveIndex((current) => event.key === "ArrowDown"
        ? (current + 1) % patients.length
        : (current - 1 + patients.length) % patients.length);
      return;
    }
    if (event.key !== "Enter" || selectedPatient) return;
    event.preventDefault();
    if (open && patients[activeIndex]) {
      choose(patients[activeIndex]);
      return;
    }
    try {
      const normalized = normalizePatientPassport(value);
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
      timerRef.current = null;
      void lookup(normalized);
    } catch {
      // A validação visual permanece no próprio campo até haver 1–4 dígitos.
    }
  }

  const dropdownVisible = open && !selectedPatient && lookupState !== "idle";
  return <div className={`patient-passport-combobox ${className}`.trim()} ref={rootRef}>
    <label htmlFor={inputId}>{label}</label>
    <input
      id={inputId}
      aria-activedescendant={dropdownVisible && patients[activeIndex] ? `${listId}-${patients[activeIndex].id}` : undefined}
      aria-autocomplete="list"
      aria-controls={listId}
      aria-expanded={dropdownVisible}
      autoComplete="off"
      disabled={disabled}
      inputMode="numeric"
      maxLength={4}
      pattern="[0-9]{1,4}"
      placeholder="Somente números (até 4)"
      role="combobox"
      value={value}
      onChange={(event) => changeValue(event.target.value)}
      onFocus={() => { if (!selectedPatient && lookupState !== "idle") setOpen(true); }}
      onKeyDown={handleKeyDown}
    />
    {dropdownVisible ? <div className="patient-dropdown" id={listId} role="listbox" aria-label="Pacientes encontrados">
      {lookupState === "searching" ? <div className="patient-dropdown-loading" role="status"><span className="patient-search-spinner" aria-hidden="true" />Localizando pelo passaporte…</div> : null}
      {lookupState === "not-found" ? <div className="patient-dropdown-empty" role="status"><strong>Nenhum paciente encontrado</strong><span>Confira o passaporte informado.</span></div> : null}
      {lookupState === "error" ? <div className="patient-dropdown-empty" role="alert"><strong>Consulta indisponível</strong><span>Tente novamente em instantes.</span></div> : null}
      {lookupState === "results" ? patients.map((patient, index) => <button
        aria-selected={index === activeIndex}
        id={`${listId}-${patient.id}`}
        key={patient.id}
        onClick={() => choose(patient)}
        onMouseEnter={() => setActiveIndex(index)}
        role="option"
        type="button"
      >
        <span className="patient-result-avatar">{initials(patient.name)}</span>
        <span><strong>{patient.name}</strong><small>Passaporte {formatPatientPassport(patient.passport)}</small></span>
        <em>{patient.phone ?? "Sem telefone"}</em>
      </button>) : null}
    </div> : null}
    {selectedPatient && showSelectedSummary ? <div className="patient-passport-selection">
      <span className="patient-result-avatar">{initials(selectedPatient.name)}</span>
      <span><strong>{selectedPatient.name}</strong><small>Passaporte {formatPatientPassport(selectedPatient.passport)}</small></span>
      <button type="button" onClick={() => changeValue("")} disabled={disabled}>Trocar</button>
    </div> : null}
  </div>;
}

function initials(name: string) {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]).join("").toUpperCase();
}
