"use client";

import { useState, type FormEvent } from "react";
import { todayIso } from "../lib/birth-date";
import type { PatientPortalProfile } from "../lib/patient-portal";
import {
  clearOptionalHpsmPhonePrefix,
  ensureHpsmPhonePrefix,
  formatHpsmPhoneInput,
  parseOptionalEmergencyContact,
  parseOptionalHpsmPhone,
} from "../lib/phone";
import { formatPatientPassport } from "../lib/passport";

export function PatientPortalProfileForm({ initialPatient }: { initialPatient: PatientPortalProfile }) {
  const [savedPatient, setSavedPatient] = useState(initialPatient);
  const [name, setName] = useState(initialPatient.name);
  const [phone, setPhone] = useState(initialPatient.phone ?? "");
  const [birthDate, setBirthDate] = useState(initialPatient.birthDate ?? "");
  const [emergencyContactName, setEmergencyContactName] = useState(initialPatient.emergencyContactName ?? "");
  const [emergencyContactPhone, setEmergencyContactPhone] = useState(initialPatient.emergencyContactPhone ?? "");
  const [allergies, setAllergies] = useState(initialPatient.allergies ?? "");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [saving, setSaving] = useState(false);

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (saving) return;
    setError("");
    setNotice("");
    if (name.trim().length < 2) return setError("Informe seu nome completo.");
    if (!allergies.trim()) return setError("Informe suas alergias ou registre “Não possui”.");
    const primaryPhone = parseOptionalHpsmPhone(phone);
    if (primaryPhone.error) return setError(primaryPhone.error);
    const emergencyContact = parseOptionalEmergencyContact(emergencyContactName, emergencyContactPhone);
    if (emergencyContact.error) return setError(emergencyContact.error);

    setSaving(true);
    try {
      const response = await fetch("/api/patient-portal/profile", {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          allergies,
          birthDate,
          emergencyContactName: emergencyContact.name ?? "",
          emergencyContactPhone: emergencyContact.phone ?? "",
          name,
          phone: primaryPhone.phone ?? "",
        }),
      });
      const payload = await response.json() as { error?: string; patient?: PatientPortalProfile };
      if (!response.ok || !payload.patient) throw new Error(payload.error ?? "Não foi possível salvar seu cadastro.");
      applyProfile(payload.patient);
      setNotice("Cadastro atualizado com sucesso.");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Não foi possível salvar seu cadastro.");
    } finally {
      setSaving(false);
    }
  }

  function applyProfile(patient: PatientPortalProfile) {
    setSavedPatient(patient);
    setName(patient.name);
    setPhone(patient.phone ?? "");
    setBirthDate(patient.birthDate ?? "");
    setEmergencyContactName(patient.emergencyContactName ?? "");
    setEmergencyContactPhone(patient.emergencyContactPhone ?? "");
    setAllergies(patient.allergies ?? "");
  }

  function cancel() {
    applyProfile(savedPatient);
    setError("");
    setNotice("");
  }

  return (
    <form className="patient-portal-profile-form patient-portal-content-card" onSubmit={save}>
      <header>
        <div>
          <p>Dados cadastrais</p>
          <h2>Meu Cadastro</h2>
        </div>
      </header>

      <div className="patient-portal-profile-grid">
        <label>
          <span>Passaporte</span>
          <input aria-describedby="portal-passport-lock" readOnly value={formatPatientPassport(initialPatient.passport)} />
          <small id="portal-passport-lock">🔒 Seu passaporte é protegido e não pode ser alterado pelo Portal.</small>
        </label>
        <label>
          <span>Nome completo</span>
          <input autoComplete="name" maxLength={100} minLength={2} onChange={(event) => setName(event.target.value)} required value={name} />
        </label>
        <label>
          <span>Telefone de contato (opcional)</span>
          <input
            autoComplete="tel"
            inputMode="numeric"
            maxLength={13}
            onBlur={() => setPhone((current) => clearOptionalHpsmPhonePrefix(current))}
            onChange={(event) => setPhone(formatHpsmPhoneInput(event.target.value))}
            onFocus={() => setPhone((current) => ensureHpsmPhonePrefix(current))}
            pattern="\(055\) [0-9]{3}-[0-9]{3}"
            placeholder="(055) 123-456"
            type="tel"
            value={phone}
          />
        </label>
        <label>
          <span>Data de nascimento (opcional)</span>
          <input max={todayIso()} onChange={(event) => setBirthDate(event.target.value)} type="date" value={birthDate} />
          <small>Você pode informar, alterar ou remover esta data.</small>
        </label>
        <label>
          <span>Contato de emergência (opcional)</span>
          <input maxLength={100} onChange={(event) => setEmergencyContactName(event.target.value)} value={emergencyContactName} />
        </label>
        <label>
          <span>Telefone de emergência (opcional)</span>
          <input
            inputMode="numeric"
            maxLength={13}
            onChange={(event) => setEmergencyContactPhone(formatHpsmPhoneInput(event.target.value))}
            pattern="\(055\) [0-9]{3}-[0-9]{3}"
            placeholder="(055) 123-456"
            type="tel"
            value={emergencyContactPhone}
          />
        </label>
        <label className="patient-portal-profile-allergies">
          <span>Alergias</span>
          <textarea
            maxLength={1000}
            onChange={(event) => setAllergies(event.target.value)}
            placeholder="Se não possuir alergias, registre “Não possui”."
            required
            rows={5}
            value={allergies}
          />
          <small>Campo obrigatório ao salvar. “Não possui” é uma resposta válida.</small>
        </label>
      </div>

      {error ? <p className="form-error" role="alert">{error}</p> : null}
      {notice ? <p className="form-success" role="status">{notice}</p> : null}
      <footer className="patient-portal-profile-actions">
        <button className="patient-secondary-button" disabled={saving} onClick={cancel} type="button">Cancelar</button>
        <button className="patient-portal-submit" disabled={saving} type="submit">{saving ? "Salvando…" : "Salvar alterações"}</button>
      </footer>
    </form>
  );
}
