"use client";

import Link from "next/link";
import dynamic from "next/dynamic";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState, type FormEvent } from "react";
import {
  classifyBloodPressure,
  classifyHeartRate,
  classifyOxygenSaturation,
  classifyTemperature,
  generateVitalForClassification,
  type VitalClassification,
} from "../lib/consultation-vitals";
import { resolveConsultationComplementaryAction } from "../lib/consultation-complementary-action";
import {
  consultationCastPrefill,
  consultationFollowUpPrefill,
  consultationHospitalizationPrefill,
  consultationImagingPrefill,
  type ConsultationPrefillContext,
} from "../lib/consultation-form-prefill";
import type {
  ComplementaryAction,
  ConsultationAiAction,
  ConsultationDetail,
  ConsultationDiagnosis,
  ConsultationReferenceData,
} from "../lib/consultations";
import type { ExamReferenceData } from "../lib/exams";
import type { HospitalBedBoard } from "../lib/hospitalizations";
import type { MedicalCertificateDetail } from "../lib/medical-certificates";
import type { Patient } from "../lib/operational-data";
import { HpsmButton, HpsmButtonLink } from "./hpsm-button";
import { HpsmDialog } from "./hpsm-dialog";
import { EXAM_STATUS_LABELS, type ClinicalExamStatus } from "../lib/exam-status";
import type { ClinicalExamDetail } from "../lib/exams";
import { pendingExamSuggestions } from "../lib/consultation-exam-suggestions";

const ExamCreatePanel = dynamic(() => import("./exam-center").then((module) => module.ExamCreatePanel));
const ExamDetailPanel = dynamic(() => import("./exam-center").then((module) => module.ExamDetailPanel));
const CastCreatePanel = dynamic(() => import("./cast-control").then((module) => module.CastCreatePanel));
const HospitalizationForm = dynamic(() => import("./hospitalization-center").then((module) => module.HospitalizationForm));
const CertificateDetailPanel = dynamic(() => import("./medical-certificate-center").then((module) => module.CertificateDetailPanel));
const ConsultationDocumentActions = dynamic(() => import("./consultation-document-actions").then((module) => module.ConsultationDocumentActions));
const ConsultationPrescription = dynamic(() => import("./consultation-prescription").then((module) => module.ConsultationPrescription));
const PrescriptionDocumentActions = dynamic(() => import("./prescription-document-actions").then((module) => module.PrescriptionDocumentActions));
const AI_REQUEST_TIMEOUT_MS = 75_000;

type AiResult = Record<string, unknown>;
type ExamSuggestion = { exam_type_id: number; reason: string; priority: "routine" | "priority" | "urgent" };
type ExamAnalysis = { no_exam_needed: boolean; reason: string; exam_suggestions: ExamSuggestion[] };

const severityLabels = { normal: "Normal", grave: "Grave", gravissimo: "Gravíssimo" } as const;

export function ConsultationWorkspace({ canCreateCast, canCreateCertificate, canFinalizeCertificate, canCreateExam, canPerformExam, canReviewExam, canViewExam, canCreateHospitalization, canDeleteConsultation, consultation: initial, currentUserId, examReferences, references }: {
  canCreateCast: boolean; canCreateCertificate: boolean; canFinalizeCertificate: boolean; canCreateExam: boolean; canPerformExam: boolean; canReviewExam: boolean; canViewExam: boolean; canCreateHospitalization: boolean; canDeleteConsultation: boolean; consultation: ConsultationDetail; currentUserId: string; examReferences: ExamReferenceData | null; references: ConsultationReferenceData;
}) {
  const router = useRouter();
  const initialComplementaryAction = resolveConsultationComplementaryAction(initial.selected_diagnosis, initial.complementary_action, initial.final_diagnosis_plan ?? "");
  const [consultation, setConsultation] = useState(initial);
  const [systolic, setSystolic] = useState<number | "">(initial.vitals.blood_pressure_systolic ?? "");
  const [diastolic, setDiastolic] = useState<number | "">(initial.vitals.blood_pressure_diastolic ?? "");
  const [bloodClass, setBloodClass] = useState(initial.vitals.blood_pressure_class ?? "");
  const [temperature, setTemperature] = useState<number | "">(initial.vitals.temperature_c ?? "");
  const [temperatureClass, setTemperatureClass] = useState(initial.vitals.temperature_class ?? "");
  const [heartRate, setHeartRate] = useState<number | "">(initial.vitals.heart_rate_bpm ?? "");
  const [heartRateClass, setHeartRateClass] = useState(initial.vitals.heart_rate_class ?? "");
  const [oxygen, setOxygen] = useState<number | "">(initial.vitals.oxygen_saturation_percent ?? "");
  const [oxygenClass, setOxygenClass] = useState(initial.vitals.oxygen_saturation_class ?? "");
  const [pain, setPain] = useState<number>(initial.vitals.pain_score ?? 0);
  const [anamnesis, setAnamnesis] = useState(initial.anamnesis ?? "");
  const [diagnosis, setDiagnosis] = useState<ConsultationDiagnosis | null>(initial.selected_diagnosis);
  const [diagnosisOptions, setDiagnosisOptions] = useState<ConsultationDiagnosis[]>(() => aiOptions(initial, "CLINICAL_SYNTHESIS"));
  const [examAnalysis, setExamAnalysis] = useState<ExamAnalysis | null>(() => aiExamAnalysis(initial));
  const [finalPlan, setFinalPlan] = useState(initial.final_diagnosis_plan ?? "");
  const [complementaryAction, setComplementaryAction] = useState<ComplementaryAction>(initialComplementaryAction);
  const [orientation, setOrientation] = useState(initial.orientation_text ?? "");
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [pendingExam, setPendingExam] = useState<ExamSuggestion | null>(null);
  const [activeExam, setActiveExam] = useState<ExamSuggestion | null>(null);
  const [expandedExamId, setExpandedExamId] = useState<number | null>(null);
  const [examDetail, setExamDetail] = useState<ClinicalExamDetail | null>(null);
  const [examDetailLoading, setExamDetailLoading] = useState(false);
  const [castFormOpen, setCastFormOpen] = useState(initialComplementaryAction === "CAST" && initial.can_edit && initial.status === "in_progress" && canCreateCast && !initial.casts.length);
  const [hospitalizationBoard, setHospitalizationBoard] = useState<HospitalBedBoard | null>(null);
  const [hospitalizationFormOpen, setHospitalizationFormOpen] = useState(false);
  const [expandedCertificateId, setExpandedCertificateId] = useState<number | null>(null);
  const [certificateDetail, setCertificateDetail] = useState<MedicalCertificateDetail | null>(null);
  const [certificateLoading, setCertificateLoading] = useState(false);
  const [completeConfirm, setCompleteConfirm] = useState(false);
  const [completionError, setCompletionError] = useState("");
  const [pendingSynthesis, setPendingSynthesis] = useState(false);
  const [pendingDiagnosis, setPendingDiagnosis] = useState<ConsultationDiagnosis | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState(false);
  const [deleteConfirmation, setDeleteConfirmation] = useState("");
  const editable = consultation.can_edit && consultation.status === "in_progress";
  const completedAi = useMemo(() => new Set(consultation.ai_generations.filter((item) => item.status === "completed").map((item) => item.action_type)), [consultation.ai_generations]);
  const legacyExamAnalysisPending = completedAi.has("ANAMNESIS_REWRITE") && !completedAi.has("EXAM_SUGGESTIONS");
  const synthesisUses = consultation.ai_generations.filter((item) => item.action_type === "CLINICAL_SYNTHESIS" && item.status === "completed").length;
  const examSuggestions = pendingExamSuggestions(examAnalysis?.exam_suggestions ?? [], consultation.exams);
  const prefillContext: ConsultationPrefillContext = {
    anamnesis,
    diagnosis: diagnosis ? diagnosisTitle(diagnosis) : "",
    orientation,
    plan: finalPlan,
    rationale: diagnosis ? diagnosisRationale(diagnosis) : "",
  };
  const castPrefill = consultationCastPrefill(prefillContext);
  const hospitalizationPrefill = consultationHospitalizationPrefill(prefillContext);
  const followUpPrefill = consultationFollowUpPrefill(prefillContext);
  const diagnosisPrefillKey = diagnosis ? `${diagnosis.severity}-${diagnosisTitle(diagnosis)}` : "sem-diagnostico";

  useEffect(() => {
    if (initialComplementaryAction !== "HOSPITALIZATION" || !initial.can_edit || initial.status !== "in_progress" || !canCreateHospitalization || initial.hospitalizations.length) return;
    const controller = new AbortController();
    void (async () => {
      setBusy("hospitalization-board"); setError("");
      try {
        const response = await fetch("/api/hospitalizations?view=board", { cache: "no-store", signal: controller.signal });
        const payload = await response.json() as HospitalBedBoard & { error?: string };
        if (!response.ok) throw new Error(payload.error || "Não foi possível carregar os leitos.");
        setHospitalizationBoard(payload); setHospitalizationFormOpen(true);
      } catch (reason) {
        if (!controller.signal.aborted) setError(reason instanceof Error ? reason.message : "Não foi possível carregar os leitos.");
      } finally {
        if (!controller.signal.aborted) setBusy(null);
      }
    })();
    return () => controller.abort();
  }, [canCreateHospitalization, initial.can_edit, initial.hospitalizations.length, initial.status, initialComplementaryAction]);

  const draft = () => ({
    action: "save", consultationId: consultation.id,
    bloodPressureSystolic: nullable(systolic), bloodPressureDiastolic: nullable(diastolic), bloodPressureClass: bloodClass,
    temperature: nullable(temperature), temperatureClass,
    heartRate: nullable(heartRate), heartRateClass,
    oxygenSaturation: nullable(oxygen), oxygenSaturationClass: oxygenClass,
    painScore: nullable(pain), anamnesis, selectedDiagnosis: diagnosis,
    finalDiagnosisPlan: finalPlan, complementaryAction, orientationText: orientation,
  });

  async function post(body: Record<string, unknown>, label: string) {
    setBusy(label); setError(""); setMessage("");
    try {
      const response = await fetch("/api/consultations", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
      const payload = await response.json() as { automatic_medications_inserted?: number; documentWarning?: string; error?: string; examId?: number };
      if (!response.ok) throw new Error(payload.error || "Não foi possível concluir a operação.");
      return payload;
    } catch (reason) {
      const failure = reason instanceof Error ? reason.message : "Não foi possível concluir a operação.";
      if (completeConfirm && (label === "save" || label === "complete")) setCompletionError(failure);
      else setError(failure);
      return null;
    }
    finally { setBusy(null); }
  }

  async function save(showMessage = true) {
    const result = await post(draft(), "save");
    if (result && showMessage) setMessage("Rascunho salvo com segurança.");
    return Boolean(result);
  }

  async function reload() {
    const response = await fetch(`/api/consultations?view=detail&id=${consultation.id}`, { cache: "no-store" });
    const payload = await response.json() as { consultation?: ConsultationDetail };
    if (response.ok && payload.consultation) setConsultation(payload.consultation);
  }

  async function runAi(action: ConsultationAiAction, proceedWithPendingExams = false) {
    if (action === "CLINICAL_SYNTHESIS" && consultation.exams.some((exam) => exam.status !== "completed") && !proceedWithPendingExams) {
      setPendingSynthesis(true);
      return;
    }
    if (!await save(false)) return;
    setBusy(action); setError(""); setMessage("");
    try {
      const response = await fetchConsultationAi({ consultationId: consultation.id, action, proceedWithPendingExams });
      const payload = await response.json() as { code?: string; error?: string; result?: AiResult; reused?: boolean };
      if (response.status === 409 && payload.code === "PENDING_EXAMS") { setPendingSynthesis(true); return; }
      if (!response.ok || !payload.result) throw new Error(payload.error || "Não foi possível gerar a assistência.");
      applyAiResult(action, payload.result);
      // A versão combinada grava texto e exames na mesma transação no banco.
      if (action === "ANAMNESIS_REWRITE" && !Array.isArray(payload.result.exam_suggestions)) await persistLegacyAiText(payload.result);
      await reload();
      setMessage(payload.reused ? "Resultado já existente recuperado." : "Sugestão gerada. Revise antes de continuar.");
    } catch (reason) {
      setError(isAbortError(reason)
        ? "A assistência demorou para responder. O rascunho foi preservado e o botão foi liberado para uma nova tentativa."
        : reason instanceof Error ? reason.message : "Não foi possível gerar a assistência.");
    }
    finally { setBusy(null); }
  }

  function applyAiResult(action: ConsultationAiAction, result: AiResult) {
    if (action === "ANAMNESIS_REWRITE" && typeof result.text === "string") setAnamnesis(result.text);
    if ((action === "ANAMNESIS_REWRITE" || action === "EXAM_SUGGESTIONS") && Array.isArray(result.exam_suggestions)) setExamAnalysis(normalizeExamAnalysis(result));
    if (action === "CLINICAL_SYNTHESIS" && Array.isArray(result.options)) setDiagnosisOptions(result.options as ConsultationDiagnosis[]);
  }

  async function persistLegacyAiText(result: AiResult) {
    const next = draft();
    if (typeof result.text !== "string") return;
    next.anamnesis = result.text;
    const response = await fetch("/api/consultations", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(next) });
    const payload = await response.json() as { error?: string };
    if (!response.ok) throw new Error(payload.error || "A sugestão foi preservada, mas não pôde ser aplicada ao rascunho.");
  }

  async function complete() {
    setCompletionError("");
    if (!await save(false)) return;
    const result = await post({ action: "complete", consultationId: consultation.id }, "complete");
    if (result) { setCompleteConfirm(false); await reload(); setMessage(result.documentWarning || "Consulta concluída, snapshot preservado e prontuário completo preparado."); }
  }

  function requestCompletion() {
    setCompletionError("");
    if (!diagnosis) {
      setCompletionError("Selecione uma hipótese clínica antes de concluir a consulta.");
      document.getElementById("clinical-diagnosis-step")?.scrollIntoView({ behavior: "smooth", block: "center" });
      return;
    }
    setCompleteConfirm(true);
  }

  function chooseDiagnosis(option: ConsultationDiagnosis, force = false) {
    if (!force && diagnosis && hasEditedSynthesis(diagnosis, finalPlan, complementaryAction, orientation)) {
      setPendingDiagnosis(option);
      return;
    }
    setPendingDiagnosis(null);
    setCompletionError("");
    void applyDiagnosis(option);
  }

  async function applyDiagnosis(option: ConsultationDiagnosis) {
    const nextPlan = option.final_plan ?? finalPlan;
    const nextAction = resolveConsultationComplementaryAction(option, option.complementary_action ?? "NONE", nextPlan);
    const selectedOption = { ...option, complementary_action: nextAction, complementary_action_dismissed: false };
    const nextOrientation = option.orientation ?? orientation;
    const result = await post({
      action: "select-diagnosis",
      consultationId: consultation.id,
      selectedDiagnosis: option,
      finalDiagnosisPlan: nextPlan,
      complementaryAction: nextAction,
      orientationText: nextOrientation,
    }, "diagnosis");
    if (!result) return;
    setDiagnosis(selectedOption);
    setFinalPlan(nextPlan);
    setComplementaryAction(nextAction);
    setOrientation(nextOrientation);
    await reload();
    if (nextAction === "CAST" && canCreateCast && !consultation.casts.length) {
      setHospitalizationFormOpen(false);
      setCastFormOpen(true);
    } else if (nextAction === "HOSPITALIZATION" && canCreateHospitalization && !consultation.hospitalizations.length) {
      setCastFormOpen(false);
      await openHospitalizationForm();
    }
    const inserted = result.automatic_medications_inserted ?? 0;
    setMessage(inserted > 0
      ? `Hipótese selecionada e ${inserted} ${inserted === 1 ? "medicação incluída" : "medicações incluídas"} automaticamente na prescrição.`
      : "Hipótese selecionada. A prescrição atual foi preservada.");
  }

  async function deleteConsultation() {
    const result = await post({ action: "delete", consultationId: consultation.id }, "delete");
    if (!result) return;
    setDeleteConfirm(false);
    router.replace("/consultas");
    router.refresh();
  }

  async function openHospitalizationForm() {
    setBusy("hospitalization-board"); setError("");
    try {
      const response = await fetch("/api/hospitalizations?view=board", { cache: "no-store" });
      const payload = await response.json() as HospitalBedBoard & { error?: string };
      if (!response.ok) throw new Error(payload.error || "Não foi possível carregar os leitos.");
      setHospitalizationBoard(payload); setHospitalizationFormOpen(true);
    } catch (reason) { setError(reason instanceof Error ? reason.message : "Não foi possível carregar os leitos."); }
    finally { setBusy(null); }
  }

  async function openExam(examId: number) {
    if (expandedExamId === examId) { setExpandedExamId(null); setExamDetail(null); return; }
    setExpandedExamId(examId); setExamDetail(null); setExamDetailLoading(true); setError("");
    try {
      const response = await fetch(`/api/exams?view=detail&id=${examId}`, { cache: "no-store" });
      const payload = await response.json() as { exam?: ClinicalExamDetail; error?: string };
      if (!response.ok || !payload.exam) throw new Error(payload.error || "Não foi possível abrir o exame.");
      setExamDetail(payload.exam);
    } catch (reason) { setExpandedExamId(null); setError(reason instanceof Error ? reason.message : "Não foi possível abrir o exame."); }
    finally { setExamDetailLoading(false); }
  }

  async function refreshExamDetail(examId: number) {
    const response = await fetch(`/api/exams?view=detail&id=${examId}`, { cache: "no-store" });
    const payload = await response.json() as { exam?: ClinicalExamDetail; error?: string };
    if (!response.ok || !payload.exam) throw new Error(payload.error || "Não foi possível atualizar o exame.");
    setExamDetail(payload.exam);
  }

  async function openCertificate(certificateId: number) {
    if (expandedCertificateId === certificateId) { setExpandedCertificateId(null); setCertificateDetail(null); return; }
    setExpandedCertificateId(certificateId); setCertificateDetail(null); setCertificateLoading(true); setError("");
    try {
      const response = await fetch(`/api/medical-certificates?view=detail&id=${certificateId}`, { cache: "no-store" });
      const payload = await response.json() as { certificate?: MedicalCertificateDetail; error?: string };
      if (!response.ok || !payload.certificate) throw new Error(payload.error || "Não foi possível abrir o atestado.");
      setCertificateDetail(payload.certificate);
    } catch (reason) { setExpandedCertificateId(null); setError(reason instanceof Error ? reason.message : "Não foi possível abrir o atestado."); }
    finally { setCertificateLoading(false); }
  }

  async function refreshCertificate(certificateId: number, notice: string) {
    const response = await fetch(`/api/medical-certificates?view=detail&id=${certificateId}`, { cache: "no-store" });
    const payload = await response.json() as { certificate?: MedicalCertificateDetail; error?: string };
    if (!response.ok || !payload.certificate) throw new Error(payload.error || "Não foi possível atualizar o atestado.");
    setCertificateDetail(payload.certificate);
    await reload();
    setMessage(notice);
  }

  async function dismissComplementaryAction() {
    const previous = complementaryAction;
    const previousDiagnosis = diagnosis;
    const dismissedDiagnosis = diagnosis ? { ...diagnosis, complementary_action: "NONE" as const, complementary_action_dismissed: true } : null;
    setComplementaryAction("NONE"); setDiagnosis(dismissedDiagnosis); setCastFormOpen(false); setHospitalizationFormOpen(false);
    const result = await post({ ...draft(), selectedDiagnosis: dismissedDiagnosis, complementaryAction: "NONE" }, "save");
    if (result) setMessage("Sugestão complementar dispensada pelo profissional.");
    else { setComplementaryAction(previous); setDiagnosis(previousDiagnosis); }
  }

  return <div className="consultation-workspace">
    <header className="clinical-header">
      <div><Link href="/consultas">← Voltar à agenda</Link><span className="consultation-kicker">Consulta #{consultation.id}</span><h2>{consultation.patient.name}</h2><p>Passaporte {consultation.patient.passport} · {consultation.professional.name}{consultation.professional.position ? ` · ${consultation.professional.position}` : ""}</p></div>
      <div className="clinical-header-meta"><span className={`consultation-status status-${consultation.status}`}>{consultation.status === "completed" ? "Concluída" : "Em consulta"}</span><strong>{formatDateTime(consultation.appointment?.scheduled_start ?? consultation.started_at)}</strong></div>
      <div className="clinical-alerts"><PatientFlag active={Boolean(consultation.patient.allergies)} label={consultation.patient.allergies ? `Alergias: ${consultation.patient.allergies}` : "Alergias não informadas"} tone={consultation.patient.allergies ? "warning" : "neutral"} /><PatientFlag active={consultation.patient.plan_active} label="Plano ativo" /><PatientFlag active={consultation.patient.cast_active} label="Gesso ativo" /><PatientFlag active={consultation.patient.hospitalization_active} label="Internação ativa" tone="warning" /></div>
    </header>

    {!editable ? <div className="clinical-readonly"><strong>Prontuário em modo de leitura</strong><span>{consultation.status === "completed" ? "Esta consulta foi concluída e não pode mais ser alterada." : "Somente o profissional responsável pode editar esta consulta."}</span></div> : null}
    {error ? <p className="form-error" role="alert">{error}</p> : null}{message ? <p className="form-success" role="status">{message}</p> : null}

    <ClinicalStep number="01" title="Sinais vitais" description="Todos os campos e classificações são obrigatórios para concluir.">
      <div className="vitals-grid">
        <VitalField label="Pressão arterial" classification={bloodClass} suffix="mmHg"><div className="paired-input"><input aria-label="Pressão sistólica" disabled={!editable} type="number" min={40} max={300} value={systolic} onChange={(event) => { const value = numberOrEmpty(event.target.value); setSystolic(value); if (value !== "" && diastolic !== "") setBloodClass(classifyBloodPressure(value, diastolic, references.vital_ranges)); }} /><span>/</span><input aria-label="Pressão diastólica" disabled={!editable} type="number" min={20} max={200} value={diastolic} onChange={(event) => { const value = numberOrEmpty(event.target.value); setDiastolic(value); if (systolic !== "" && value !== "") setBloodClass(classifyBloodPressure(systolic, value, references.vital_ranges)); }} /></div><VitalClassButtons disabled={!editable} value={bloodClass} onChange={(classification) => { const generated = generateVitalForClassification("blood_pressure", classification, references.vital_ranges); if (generated && "systolic" in generated) { setSystolic(generated.systolic); setDiastolic(generated.diastolic); setBloodClass(classification); } }} /></VitalField>
        <VitalField label="Temperatura" classification={temperatureClass} suffix="°C"><input disabled={!editable} type="number" min={30} max={45} step="0.1" value={temperature} onChange={(event) => { const value = numberOrEmpty(event.target.value); setTemperature(value); if (value !== "") setTemperatureClass(classifyTemperature(value, references.vital_ranges)); }} /><VitalClassButtons disabled={!editable} value={temperatureClass} onChange={(classification) => { const generated = generateVitalForClassification("temperature", classification, references.vital_ranges); if (generated && "value" in generated) { setTemperature(generated.value); setTemperatureClass(classification); } }} /></VitalField>
        <VitalField label="Frequência cardíaca" classification={heartRateClass} suffix="bpm"><input disabled={!editable} type="number" min={20} max={260} value={heartRate} onChange={(event) => { const value = numberOrEmpty(event.target.value); setHeartRate(value); if (value !== "") setHeartRateClass(classifyHeartRate(value, references.vital_ranges)); }} /><VitalClassButtons disabled={!editable} value={heartRateClass} onChange={(classification) => { const generated = generateVitalForClassification("heart_rate", classification, references.vital_ranges); if (generated && "value" in generated) { setHeartRate(generated.value); setHeartRateClass(classification); } }} /></VitalField>
        <VitalField label="Saturação de oxigênio" classification={oxygenClass} suffix="%"><input disabled={!editable} type="number" min={50} max={100} value={oxygen} onChange={(event) => { const value = numberOrEmpty(event.target.value); setOxygen(value); if (value !== "") setOxygenClass(classifyOxygenSaturation(value, references.vital_ranges)); }} /><VitalClassButtons disabled={!editable} value={oxygenClass} onChange={(classification) => { const generated = generateVitalForClassification("oxygen_saturation", classification, references.vital_ranges); if (generated && "value" in generated) { setOxygen(generated.value); setOxygenClass(classification); } }} /></VitalField>
        <VitalField label="Dor" classification={painClassification(pain)} showClassification suffix="0–10"><div className="pain-range"><input aria-label="Escala de dor" disabled={!editable} type="range" min={0} max={10} step={1} value={pain} onChange={(event) => setPain(Number(event.target.value))} /><output>{pain}</output></div><small>Escala manual de 0 a 10</small></VitalField>
      </div>
    </ClinicalStep>

    <ClinicalStep number="02" title="Anamnese e evolução" description="A assistência reescreve uma única vez, sem criar fatos.">
      <textarea disabled={!editable} value={anamnesis} onChange={(event) => setAnamnesis(event.target.value)} rows={9} maxLength={12000} placeholder="Queixa, história, antecedentes relevantes, exame clínico e evolução…" />
      {editable ? <AiButton action={legacyExamAnalysisPending ? "EXAM_SUGGESTIONS" : "ANAMNESIS_REWRITE"} busy={busy} completed={completedAi.has("ANAMNESIS_REWRITE") && !legacyExamAnalysisPending} onClick={runAi}>{legacyExamAnalysisPending ? "Completar assistência" : "Assistência"}</AiButton> : null}
    </ClinicalStep>

    <ClinicalStep number="03" title="Exames complementares" description="Sugestões usam apenas tipos ativos. O exame só é criado após confirmação humana.">
      {consultation.exams.length ? <div className="clinical-linked-list clinical-exam-accordion">{consultation.exams.map((exam) => <article key={exam.id}><button aria-expanded={expandedExamId === exam.id} disabled={!canViewExam || examDetailLoading} onClick={() => void openExam(exam.id)} type="button"><strong>{exam.type} · #{exam.id}</strong><span>{exam.status === "completed" ? exam.conclusion || "Concluído" : examStatusLabel(exam.status)}</span><i aria-hidden="true">{expandedExamId === exam.id ? "−" : "+"}</i></button>{expandedExamId === exam.id && examDetailLoading ? <p className="clinical-muted">Carregando exame…</p> : null}{expandedExamId === exam.id && examDetail ? <ExamDetailPanel allowDelete={false} canPerform={canPerformExam} canReview={canReviewExam} currentUserId={currentUserId} exam={examDetail} inline key={`${examDetail.id}-${examDetail.updated_at}`} onClose={() => { setExpandedExamId(null); setExamDetail(null); }} onChanged={async () => { await refreshExamDetail(exam.id); await reload(); }} /> : null}</article>)}</div> : <p className="clinical-muted">Nenhum exame vinculado.</p>}
      {examSuggestions.length ? <div className="ai-suggestion-list">{examSuggestions.map((suggestion) => { const type = references.exam_types.find((item) => item.id === suggestion.exam_type_id); return <article key={`${suggestion.exam_type_id}-${suggestion.reason}`}><div><span className={`priority-${suggestion.priority}`}>{priorityLabel(suggestion.priority)}</span><h4>{type?.name ?? "Exame indisponível"}</h4><p>{suggestion.reason}</p></div>{editable && canCreateExam && type ? <HpsmButton disabled={busy !== null} onClick={() => setPendingExam(suggestion)}>Criar solicitação</HpsmButton> : null}</article>; })}</div> : null}
      {examAnalysis?.no_exam_needed ? <div className="clinical-analysis-complete"><strong>Nenhum exame complementar necessário.</strong><span>{examAnalysis.reason}</span></div> : null}
      {activeExam && examReferences ? <ExamCreatePanel consultationId={consultation.id} currentUserId={currentUserId} initialExamTypeId={activeExam.exam_type_id} initialImagingRequest={consultationImagingPrefill(examReferences.types.find((type) => type.id === activeExam.exam_type_id), { ...prefillContext, suggestion: activeExam.reason })} initialIndication={examIndication(activeExam.reason, anamnesis)} initialPatient={consultationPatient(consultation)} inline references={examReferences} onClose={() => setActiveExam(null)} onCreated={async (examId) => { setActiveExam(null); await reload(); await openExam(examId); setMessage(`Exame #${examId} solicitado e vinculado à consulta.`); }} /> : null}
    </ClinicalStep>

    <ClinicalStep id="clinical-diagnosis-step" number="04" title="Hipóteses diagnósticas" description="A síntese apresenta opções; o médico deve escolher uma para seguir com a consulta.">
      {completionError && !completeConfirm && !diagnosis ? <p className="form-error" role="alert">{completionError}</p> : null}
      <div className="diagnosis-decision-notice" role="status"><strong>{diagnosis ? "Hipótese escolhida pelo médico" : "Escolha do médico obrigatória"}</strong><span>{diagnosis ? "A hipótese selecionada aparece abaixo e pode ser alterada antes de concluir." : diagnosisOptions.length ? "Revise as opções e clique em “Selecionar esta hipótese” na que corresponde à avaliação clínica." : "Execute a síntese clínica para receber até três opções. Em seguida, selecione uma delas; a IA não faz essa escolha."}</span></div>
      {consultation.related_protocols.length ? <div className="related-protocols"><header><div><span className="consultation-kicker">Contexto local</span><h4>Protocolos relacionados</h4></div><Link href="/consultas/protocolos">Abrir biblioteca</Link></header><div>{consultation.related_protocols.map((protocol) => <article key={protocol.id}><span>{protocol.state} · {Math.round(protocol.similarity * 100)}% de similaridade</span><strong>{protocol.display_name}</strong><p>{protocol.observed_count} atendimento(s) confirmado(s) · {protocol.case_tags.slice(0, 4).join(" · ") || protocol.body_system}</p>{protocol.medications.length ? <small>Medicações observadas: {protocol.medications.slice(0, 3).map((item) => item.name).join(", ")}</small> : null}</article>)}</div></div> : null}
      {diagnosisOptions.length ? <div className="diagnosis-options" role="group" aria-label="Selecione uma hipótese diagnóstica">{diagnosisOptions.map((option) => { const selected = diagnosis?.severity === option.severity && diagnosisTitle(diagnosis) === diagnosisTitle(option); return <button type="button" disabled={!editable || busy !== null} aria-pressed={selected} className={`diagnosis-${option.severity}`} key={`${option.severity}-${diagnosisTitle(option)}`} onClick={() => chooseDiagnosis(option)}><span>{severityLabels[option.severity]}</span><strong>{diagnosisTitle(option)}</strong><small>{diagnosisRationale(option)}</small><em>{selected ? "✓ Hipótese selecionada" : "Selecionar esta hipótese"}</em></button>; })}</div> : <p className="clinical-muted">Revise os dados clínicos e execute a síntese para receber hipóteses compatíveis com a consulta.</p>}
      {editable ? <AiButton action="CLINICAL_SYNTHESIS" busy={busy} completed={synthesisUses >= 3} completedLabel="Limite de 3 gerações atingido" disabled={!completedAi.has("EXAM_SUGGESTIONS")} onClick={runAi}>{synthesisUses ? `Gerar novas hipóteses (${synthesisUses}/3)` : "Executar síntese clínica"}</AiButton> : null}
    </ClinicalStep>

    <ClinicalStep number="05" title="Diagnóstico final e plano" description="Carregado da síntese selecionada, sem nova chamada, e editável antes da conclusão.">
      {diagnosis ? <article className="selected-diagnosis" data-severity={diagnosis.severity}><span aria-hidden="true">✓</span><div><small>Diagnóstico selecionado · {severityLabels[diagnosis.severity]}</small><strong>{diagnosisTitle(diagnosis)}</strong>{diagnosisRationale(diagnosis) ? <p>{diagnosisRationale(diagnosis)}</p> : null}</div></article> : null}
      <textarea disabled={!editable} value={finalPlan} onChange={(event) => setFinalPlan(event.target.value)} rows={8} maxLength={12000} placeholder="Diagnóstico final, conduta, próximos passos e plano…" />
    </ClinicalStep>

    {complementaryAction !== "NONE" || consultation.casts.length || consultation.hospitalizations.length ? <ClinicalStep number="06" title="Conduta complementar" description="A assistência apenas sugere; a decisão e o registro permanecem humanos.">
      {complementaryAction === "CAST" ? <article className="clinical-action-card"><div><span>Gesso sugerido</span><strong>Registrar imobilização vinculada à consulta</strong><p>Revise região, lateralidade, material e observações antes de confirmar.</p></div>{editable && !consultation.casts.length ? <div>{canCreateCast && !castFormOpen ? <HpsmButton variant="primary" onClick={() => setCastFormOpen(true)}>Registrar aplicação de gesso</HpsmButton> : null}<HpsmButton variant="ghost" onClick={() => void dismissComplementaryAction()}>Não aplicar</HpsmButton></div> : null}</article> : null}
      {complementaryAction === "HOSPITALIZATION" ? <article className="clinical-action-card"><div><span>Internação sugerida</span><strong>Registrar internação e ocupação de leito</strong><p>Confira a disponibilidade e complete o formulário institucional antes de confirmar.</p></div>{editable && !consultation.hospitalizations.length ? <div>{canCreateHospitalization && !hospitalizationFormOpen ? <HpsmButton variant="primary" loading={busy === "hospitalization-board"} onClick={() => void openHospitalizationForm()}>Registrar internação</HpsmButton> : null}<HpsmButton variant="ghost" onClick={() => void dismissComplementaryAction()}>Não aplicar</HpsmButton></div> : null}</article> : null}
      {consultation.casts.length ? <div className="clinical-linked-list">{consultation.casts.map((cast) => <Link href={`/gessos?registro=${cast.id}`} key={cast.id}><strong>Gesso #{cast.id} · {cast.body_region}</strong><span>{castStatusLabel(cast.status)}</span></Link>)}</div> : null}
      {consultation.hospitalizations.length ? <div className="clinical-linked-list">{consultation.hospitalizations.map((hospitalization) => <Link href={`/internacoes?registro=${hospitalization.id}`} key={hospitalization.id}><strong>Internação IN-{String(hospitalization.id).padStart(6, "0")}</strong><span>{hospitalizationStatusLabel(hospitalization.status)}</span></Link>)}</div> : null}
      {complementaryAction === "CAST" && castFormOpen ? <CastCreatePanel consultationPrefill={{ ...castPrefill, consultationId: consultation.id, patient: consultationPatient(consultation) }} currentProfessional={{ id: currentUserId, name: consultation.professional.name, position: consultation.professional.position }} inline key={`cast-${diagnosisPrefillKey}`} onClose={() => setCastFormOpen(false)} onCreated={async (castId) => { setCastFormOpen(false); await reload(); setMessage(`Aplicação de gesso #${castId} registrada e vinculada.`); }} /> : null}
      {complementaryAction === "HOSPITALIZATION" && hospitalizationFormOpen && hospitalizationBoard ? <HospitalizationForm board={hospitalizationBoard} canSearchPatients consultationPrefill={{ ...hospitalizationPrefill, consultationId: consultation.id, patient: consultationPatient(consultation) }} initial={null} inline key={`hospitalization-${diagnosisPrefillKey}`} onClose={() => setHospitalizationFormOpen(false)} onSaved={(nextMessage) => { setHospitalizationFormOpen(false); void reload(); setMessage(nextMessage); }} /> : null}
    </ClinicalStep> : null}

    <ClinicalStep number="07" title="Atestado médico" description="Os dias são definidos manualmente pelo profissional; a assistência nunca escolhe o período.">
      {consultation.certificates.length ? <div className="clinical-certificate-list clinical-certificate-accordion">{consultation.certificates.map((certificate) => <article key={certificate.id}><button aria-expanded={expandedCertificateId === certificate.id} disabled={certificateLoading} onClick={() => void openCertificate(certificate.id)} type="button"><span><strong>AT-{String(certificate.id).padStart(6, "0")}</strong><small>{certificate.leave_days} {certificate.leave_days === 1 ? "dia" : "dias"} · {certificateStatusLabel(certificate.status)}</small></span><i aria-hidden="true">{expandedCertificateId === certificate.id ? "−" : "+"}</i></button>{expandedCertificateId === certificate.id && certificateLoading ? <p className="clinical-muted">Carregando atestado…</p> : null}{expandedCertificateId === certificate.id && certificateDetail ? <CertificateDetailPanel aiEnabled={false} canCancel={false} canFinalize={canFinalizeCertificate} certificate={certificateDetail} currentUserId={currentUserId} inline key={`${certificateDetail.id}-${certificateDetail.updated_at}`} onChanged={(notice) => refreshCertificate(certificate.id, notice)} onClose={() => { setExpandedCertificateId(null); setCertificateDetail(null); }} /> : null}</article>)}</div> : null}
      {!consultation.certificates.length && editable && canCreateCertificate ? <CertificateForm consultationId={consultation.id} defaultContext={certificateContext(diagnosis, finalPlan, anamnesis)} onCreated={async (certificateId) => { await reload(); await openCertificate(certificateId); setMessage("Atestado criado e vinculado à consulta."); }} /> : null}
    </ClinicalStep>

    <ClinicalStep number="08" title="Orientações e medicação" description="Carregadas da mesma síntese clínica, sem nova chamada, e sempre revisadas pelo profissional.">
      <textarea disabled={!editable} value={orientation} onChange={(event) => setOrientation(event.target.value)} rows={7} maxLength={12000} placeholder="Orientações gerais, sinais de alerta e cuidados…" />
      <ConsultationPrescription
        consultationId={consultation.id}
        editable={editable}
        medications={references.medications}
        onBeforeMutate={() => save(false)}
        onChanged={reload}
        patientAllergies={consultation.patient.allergies}
        prescription={consultation.prescription}
      />
    </ClinicalStep>

    <ClinicalStep number="09" title="Retorno" description="Cria um novo agendamento ligado a esta consulta e protegido contra conflito de horário.">
      {editable ? <FollowUpForm consultation={consultation} defaultNotes={followUpPrefill.notes} defaultReason={followUpPrefill.reason} onCreated={() => setMessage("Retorno agendado e vinculado à consulta.")} /> : <p className="clinical-muted">A consulta está em modo de leitura.</p>}
    </ClinicalStep>

    {consultation.status === "completed" ? <><ConsultationDocumentActions consultationId={consultation.id} />{consultation.prescription?.status === "finalized" && consultation.prescription.items.length ? <PrescriptionDocumentActions consultationId={consultation.id} /> : null}</> : null}

    {completionError && !completeConfirm && diagnosis ? <p className="form-error" role="alert">{completionError}</p> : null}
    <footer className="clinical-sticky-actions"><div><strong>{consultation.status === "completed" ? "Consulta concluída" : "Rascunho clínico"}</strong><span>{consultation.status === "completed" ? canDeleteConsultation ? "Registro concluído. A exclusão permanece restrita à Diretoria." : "Registro imutável e preservado." : "Salve durante o preenchimento e conclua após a revisão."}</span></div>{editable || canDeleteConsultation ? <div>{canDeleteConsultation ? <HpsmButton variant="destructive" disabled={busy !== null} onClick={() => { setDeleteConfirmation(""); setDeleteConfirm(true); }}>Excluir consulta</HpsmButton> : null}{editable ? <><HpsmButtonLink href="/consultas" variant="ghost">Cancelar</HpsmButtonLink><HpsmButton disabled={busy !== null} loading={busy === "save"} onClick={() => void save()}>{busy === "save" ? "Salvando…" : "Salvar rascunho"}</HpsmButton><HpsmButton variant="primary" disabled={busy !== null} onClick={requestCompletion}>Concluir consulta</HpsmButton></> : null}</div> : null}</footer>
    {pendingExam ? <HpsmDialog confirmLabel="Continuar para o formulário" description={`A assistência sugeriu ${references.exam_types.find((item) => item.id === pendingExam.exam_type_id)?.name ?? "este exame"}. Confirme para revisar os dados antes de criar a solicitação.`} onClose={() => setPendingExam(null)} onConfirm={() => { setActiveExam(pendingExam); setPendingExam(null); }} title="Revisar solicitação de exame" /> : null}
    {pendingSynthesis ? <HpsmDialog cancelLabel="Aguardar resultados" confirmLabel="Prosseguir mesmo assim" description="Existem exames ainda sem resultado. A síntese registrará esses exames apenas como pendentes e não inventará resultados." onClose={() => setPendingSynthesis(false)} onConfirm={() => { setPendingSynthesis(false); void runAi("CLINICAL_SYNTHESIS", true); }} title="Existem exames ainda sem resultado" /> : null}
    {pendingDiagnosis ? <HpsmDialog confirmLabel="Substituir pelos novos textos" description="O diagnóstico final, o plano, a conduta ou as orientações foram editados. Trocar a hipótese substituirá esse conteúdo pelo texto persistido na síntese selecionada." onClose={() => setPendingDiagnosis(null)} onConfirm={() => chooseDiagnosis(pendingDiagnosis, true)} title="Substituir edição clínica?" /> : null}
    {completeConfirm ? <HpsmDialog confirmLabel="Concluir consulta" description="Revise todos os dados antes de continuar. Após a conclusão, o prontuário ficará imutável e preservado no histórico." loading={busy === "complete" || busy === "save"} onClose={() => setCompleteConfirm(false)} onConfirm={() => void complete()} title="Concluir atendimento clínico">
      {completionError ? <div className="clinical-completion-feedback" role="alert"><strong>Não foi possível concluir</strong><span>{completionError}</span></div> : null}
    </HpsmDialog> : null}
    {deleteConfirm ? <HpsmDialog confirmLabel={deleteConfirmation === `EXCLUIR ${consultation.id}` ? "Excluir definitivamente" : undefined} confirmVariant="destructive" description="Esta ação apaga permanentemente a consulta, seu agendamento de origem e tudo que foi gerado por ela, incluindo atestados, exames, arquivos, gessos, internações, assistência de IA e retornos ainda não iniciados. Não é possível desfazer." loading={busy === "delete"} onClose={() => { setDeleteConfirm(false); setDeleteConfirmation(""); }} onConfirm={deleteConfirmation === `EXCLUIR ${consultation.id}` ? () => void deleteConsultation() : undefined} title="Excluir consulta e dependências">
      <label className="consultation-delete-confirmation">Digite <strong>EXCLUIR {consultation.id}</strong> para confirmar<input autoComplete="off" disabled={busy === "delete"} value={deleteConfirmation} onChange={(event) => setDeleteConfirmation(event.target.value.toUpperCase())} /></label>
    </HpsmDialog> : null}
  </div>;
}

async function fetchConsultationAi(body: Record<string, unknown>) {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), AI_REQUEST_TIMEOUT_MS);
  try {
    return await fetch("/api/consultations/ai", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
  } finally {
    window.clearTimeout(timeout);
  }
}

function isAbortError(reason: unknown) {
  return reason instanceof DOMException && reason.name === "AbortError";
}

function ClinicalStep({ children, description, id, number, title }: { children: React.ReactNode; description: string; id?: string; number: string; title: string }) { return <section className="clinical-step" id={id}><header><span>{number}</span><div><h3>{title}</h3><p>{description}</p></div></header><div className="clinical-step-body">{children}</div></section>; }
function PatientFlag({ active, label, tone = "positive" }: { active: boolean; label: string; tone?: "positive" | "warning" | "neutral" }) { return <span className={`patient-flag ${active ? tone : "neutral"}`}><i />{label}</span>; }
function VitalField({ children, classification, label, showClassification = false, suffix }: { children: React.ReactNode; classification: string; label: string; showClassification?: boolean; suffix: string }) { return <div className="vital-card"><span><strong>{label}</strong><em>{suffix}</em></span>{children}{showClassification ? <b data-classification={classification.toLowerCase()}>{classification}</b> : null}</div>; }
function VitalClassButtons({ disabled, onChange, value }: { disabled: boolean; onChange: (value: VitalClassification) => void; value: string }) { const options: Array<{ label: string; value: VitalClassification }> = [{ label: "Baixa", value: "Baixo" }, { label: "Normal", value: "Normal" }, { label: "Elevada", value: "Elevado" }, { label: "Crítica", value: "Crítico" }]; return <div className="vital-class-buttons" role="group" aria-label="Gerar valor por classificação">{options.map((option) => <button aria-pressed={value === option.value} disabled={disabled} key={option.value} onClick={() => onChange(option.value)} type="button">{option.label}</button>)}</div>; }
function AiButton({ action, busy, children, completed, completedLabel = "Assistência já utilizada", disabled = false, onClick }: { action: ConsultationAiAction; busy: string | null; children: React.ReactNode; completed: boolean; completedLabel?: string; disabled?: boolean; onClick: (action: ConsultationAiAction) => Promise<void> }) { return <button className="ai-assist-button" disabled={disabled || busy !== null || completed} onClick={() => void onClick(action)} type="button"><span aria-hidden="true">✦</span>{completed ? completedLabel : busy === action ? "Gerando com segurança…" : children}</button>; }

function CertificateForm({ consultationId, defaultContext, onCreated }: { consultationId: number; defaultContext: string; onCreated: (certificateId: number) => Promise<void> }) {
  const [days, setDays] = useState("");
  const [contextOverride, setContextOverride] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const context = contextOverride ?? defaultContext;
  async function submit(event: FormEvent) {
    event.preventDefault(); setBusy(true); setError("");
    const response = await fetch("/api/medical-certificates", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "create", consultationId, patientId: null, leaveDays: Number(days), medicalContext: context, examIds: [], castIds: [] }) });
    const payload = await response.json() as { certificateId?: number; error?: string };
    if (!response.ok || !payload.certificateId) setError(payload.error || "Não foi possível criar o atestado.");
    else { setDays(""); await onCreated(payload.certificateId); }
    setBusy(false);
  }
  return <form className="inline-clinical-form" onSubmit={submit}><label>Dias de afastamento<input required min={1} max={365} inputMode="numeric" type="number" value={days} onChange={(event) => setDays(event.target.value)} /></label><label className="wide">Contexto médico<textarea required minLength={3} maxLength={4000} rows={3} value={context} onChange={(event) => setContextOverride(event.target.value)} /></label>{error ? <p className="form-error">{error}</p> : null}<HpsmButton disabled={busy} loading={busy} type="submit" variant="primary">{busy ? "Criando…" : "Criar rascunho de atestado"}</HpsmButton></form>;
}
function FollowUpForm({ consultation, defaultNotes, defaultReason, onCreated }: { consultation: ConsultationDetail; defaultNotes: string; defaultReason: string; onCreated: () => void }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [reasonOverride, setReasonOverride] = useState<string | null>(null);
  const [notesOverride, setNotesOverride] = useState<string | null>(null);
  const reason = reasonOverride ?? defaultReason;
  const notes = notesOverride ?? defaultNotes;
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const formElement = event.currentTarget;
    const form = new FormData(formElement);
    const scheduledDate = new Date(String(form.get("scheduledStart")));
    if (Number.isNaN(scheduledDate.getTime())) { setError("Informe uma data e hora válidas."); return; }
    setBusy(true); setError("");
    try {
      const response = await fetch("/api/consultations", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "schedule", patientId: consultation.patient.id, professionalId: consultation.professional.id, scheduledStart: scheduledDate.toISOString(), durationMinutes: 30, reason, notes, followUpOfConsultationId: consultation.id }) });
      const payload = await response.json() as { error?: string };
      if (!response.ok) setError(payload.error || "Não foi possível agendar o retorno.");
      else { formElement.reset(); setReasonOverride(null); setNotesOverride(null); onCreated(); }
    } catch { setError("Não foi possível agendar o retorno."); }
    finally { setBusy(false); }
  }
  return <form className="inline-clinical-form" onSubmit={submit}><label>Data e hora<input required name="scheduledStart" type="datetime-local" onChange={() => setError("")} /></label><label className="wide">Motivo<input required minLength={3} maxLength={500} value={reason} name="reason" onChange={(event) => { setReasonOverride(event.target.value); setError(""); }} /></label><label className="wide">Observações<textarea value={notes} maxLength={4000} name="notes" rows={2} onChange={(event) => setNotesOverride(event.target.value)} /></label>{error ? <p className="form-error" role="alert">{error}</p> : null}<HpsmButton loading={busy} disabled={busy} type="submit">{busy ? "Agendando…" : "Agendar retorno"}</HpsmButton></form>;
}

function aiOptions(consultation: ConsultationDetail, action: ConsultationAiAction) { const result = consultation.ai_generations.filter((item) => item.action_type === action && item.status === "completed").at(-1)?.response; return result && Array.isArray(result.options) ? result.options as ConsultationDiagnosis[] : []; }
function aiExamAnalysis(consultation: ConsultationDetail) { const result = consultation.ai_generations.find((item) => item.action_type === "EXAM_SUGGESTIONS" && item.status === "completed")?.response; return result ? normalizeExamAnalysis(result) : null; }
function normalizeExamAnalysis(result: AiResult): ExamAnalysis { return { no_exam_needed: result.no_exam_needed === true, reason: typeof result.reason === "string" ? result.reason : "Análise de exames concluída.", exam_suggestions: Array.isArray(result.exam_suggestions) ? result.exam_suggestions as ExamSuggestion[] : [] }; }
function diagnosisTitle(value: ConsultationDiagnosis) { return value.diagnosis ?? value.title ?? "Diagnóstico não informado"; }
function diagnosisRationale(value: ConsultationDiagnosis) { return value.reasoning_summary ?? value.rationale ?? ""; }
function certificateContext(diagnosis: ConsultationDiagnosis | null, finalPlan: string, anamnesis: string) {
  const diagnosisText = diagnosis ? `Diagnóstico: ${diagnosisTitle(diagnosis)}${diagnosisRationale(diagnosis) ? `. ${diagnosisRationale(diagnosis)}` : ""}` : "";
  const clinicalText = finalPlan.trim() ? `Conduta e plano: ${finalPlan.trim()}` : anamnesis.trim();
  return [diagnosisText, clinicalText].filter(Boolean).join("\n\n").slice(0, 4000);
}
function hasEditedSynthesis(value: ConsultationDiagnosis, finalPlan: string, action: ComplementaryAction, orientation: string) {
  if (!value.final_plan || !value.orientation || !value.complementary_action) return true;
  return finalPlan.trim() !== value.final_plan.trim()
    || action !== value.complementary_action
    || orientation.trim() !== value.orientation.trim();
}
function numberOrEmpty(value: string): number | "" { return value === "" ? "" : Number(value); }
function nullable(value: number | "") { return value === "" ? null : value; }
function painClassification(value: number) { return value <= 2 ? "Leve" : value <= 5 ? "Moderada" : value <= 8 ? "Intensa" : "Crítica"; }
function examIndication(reason: string, anamnesis: string) { return [reason.trim(), anamnesis.trim() ? `Contexto clínico da consulta:\n${anamnesis.trim()}` : ""].filter(Boolean).join("\n\n").slice(0, 4000); }
function consultationPatient(consultation: ConsultationDetail): Patient { return { allergies: consultation.patient.allergies, birth_date: null, created_at: consultation.started_at, emergency_contact_name: null, emergency_contact_phone: null, health_plan: { activated_at: null, authorized_by: null, authorized_by_name: null, pending_request_id: null, pending_requested_at: null, status: consultation.patient.plan_active ? "active" : "none", valid_until: null }, id: consultation.patient.id, name: consultation.patient.name, passport: consultation.patient.passport, phone: null, updated_at: consultation.started_at }; }
function priorityLabel(value: ExamSuggestion["priority"]) { return value === "urgent" ? "Urgente" : value === "priority" ? "Prioritário" : "Rotina"; }
function examStatusLabel(value: string) { return EXAM_STATUS_LABELS[value as ClinicalExamStatus] ?? "Status indisponível"; }
function certificateStatusLabel(value: string) { return ({ cancelled: "Cancelado", draft: "Rascunho", finalized: "Finalizado" } as Record<string, string>)[value] ?? "Status indisponível"; }
function castStatusLabel(value: string) { return ({ active: "Ativo", removed: "Retirado", cancelled: "Cancelado" } as Record<string, string>)[value] ?? "Status indisponível"; }
function hospitalizationStatusLabel(value: string) { return ({ active: "Ativa", discharged: "Alta registrada", cancelled: "Cancelada" } as Record<string, string>)[value] ?? "Status indisponível"; }
function formatDateTime(value: string) { return new Intl.DateTimeFormat("pt-BR", { dateStyle: "medium", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(new Date(value)); }
