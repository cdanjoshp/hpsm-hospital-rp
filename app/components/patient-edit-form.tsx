"use client";

import { useState } from "react";
import type { Patient } from "../lib/operational-data";
import { isValidBirthDate, todayIso } from "../lib/birth-date";
import { normalizePatientPassport } from "../lib/passport";
import { clearOptionalHpsmPhonePrefix, ensureHpsmPhonePrefix, formatHpsmPhoneInput, parseOptionalEmergencyContact, parseOptionalHpsmPhone } from "../lib/phone";

export function PatientEditForm({
  onCancel,
  onSaved,
  patient,
}: {
  onCancel: () => void;
  onSaved: (patient: Patient) => void;
  patient: Patient;
}) {
  const [allergies, setAllergies] = useState(patient.allergies ?? "");
  const [emergencyContactName, setEmergencyContactName] = useState(patient.emergency_contact_name ?? "");
  const [emergencyContactPhone, setEmergencyContactPhone] = useState(patient.emergency_contact_phone ?? "");
  const [birthDate, setBirthDate] = useState(patient.birth_date ?? "");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [name, setName] = useState(patient.name);
  const [passport, setPassport] = useState(patient.passport);
  const [phone, setPhone] = useState(patient.phone ?? "");

  async function save() {
    if (loading) return;
    setError("");
    let canonicalPassport: string;
    try {
      canonicalPassport = normalizePatientPassport(passport);
    } catch (cause) {
      return setError(cause instanceof Error ? cause.message : "Informe um passaporte válido com 1 a 4 números.");
    }
    if (name.trim().length < 2) return setError("Informe o nome completo do paciente.");
    if (!allergies.trim()) return setError("Informe as alergias do paciente ou registre “Não possui”.");
    const primaryPhone = parseOptionalHpsmPhone(phone);
    if (primaryPhone.error) return setError(primaryPhone.error);
    if (birthDate && !isValidBirthDate(birthDate)) return setError("Informe uma data de nascimento válida.");
    const emergencyContact = parseOptionalEmergencyContact(emergencyContactName, emergencyContactPhone);
    if (emergencyContact.error) return setError(emergencyContact.error);

    setLoading(true);
    try {
      const response = await fetch("/api/patients", {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          allergies,
          birthDate,
          emergencyContactName: emergencyContact.name,
          emergencyContactPhone: emergencyContact.phone,
          name,
          passport: canonicalPassport,
          patientId: patient.id,
          phone: primaryPhone.phone,
        }),
      });
      const payload = (await response.json()) as { error?: string; patient?: Patient };
      if (!response.ok || !payload.patient) {
        setError(payload.error ?? "Não foi possível atualizar o paciente.");
        return;
      }
      onSaved(payload.patient);
    } catch {
      setError("Não foi possível atualizar o paciente.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="patient-edit-form">
      <div className="patient-registration-grid">
        <label>Passaporte<input required inputMode="numeric" maxLength={4} pattern="[0-9]{1,4}" value={passport} onChange={(event) => setPassport(event.target.value)} /></label>
        <label>Nome completo<input required minLength={2} maxLength={100} value={name} onChange={(event) => setName(event.target.value)} /></label>
        <label>Telefone de contato (opcional)<input inputMode="numeric" maxLength={13} pattern="\(055\) [0-9]{3}-[0-9]{3}" type="tel" value={phone} onFocus={() => setPhone((current) => ensureHpsmPhonePrefix(current))} onBlur={() => setPhone((current) => clearOptionalHpsmPhonePrefix(current))} onChange={(event) => setPhone(formatHpsmPhoneInput(event.target.value))} placeholder="(055) 123-456" /></label>
        <label>Data de nascimento (opcional)<input type="date" max={todayIso()} value={birthDate} onChange={(event) => setBirthDate(event.target.value)} aria-describedby="patient-edit-birth-date-hint" /><small id="patient-edit-birth-date-hint">DD/MM/AAAA</small></label>
        <label>Contato de emergência (opcional)<input maxLength={100} value={emergencyContactName} onChange={(event) => setEmergencyContactName(event.target.value)} /></label>
        <label>Telefone de emergência (opcional)<input inputMode="numeric" maxLength={13} pattern="\(055\) [0-9]{3}-[0-9]{3}" type="tel" value={emergencyContactPhone} onChange={(event) => setEmergencyContactPhone(formatHpsmPhoneInput(event.target.value))} placeholder="(055) 123-456" /></label>
        <label>Alergias<textarea required maxLength={1000} value={allergies} onChange={(event) => setAllergies(event.target.value)} placeholder="Ex.: Dipirona. Se não houver, registre “Não possui”." /></label>
      </div>
      {error ? <p className="form-error" role="alert">{error}</p> : null}
      <div className="patient-edit-actions">
        <button className="patient-secondary-button" type="button" onClick={onCancel} disabled={loading}>Cancelar</button>
        <button className="register-patient-button" type="button" onClick={save} disabled={loading}>{loading ? "Salvando…" : "Salvar alterações"}</button>
      </div>
    </div>
  );
}
