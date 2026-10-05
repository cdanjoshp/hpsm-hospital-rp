import type { ConsultationSnapshot } from "./consultation-document";
import { institutionalCardBlocks, renderOfficialInstitutionalDocument, type InstitutionalIdentityAssets } from "./institutional-document-png";
import { formatPatientPassport } from "./passport";

export const CONSULTATION_DOCUMENT_RENDER_VERSION = "consultation-document-png-v7";

type Section = { lines: string[]; title: string };
export function renderConsultationDocumentPng(snapshot: ConsultationSnapshot, identity: InstitutionalIdentityAssets) {
  const sections = consultationSections(snapshot);
  const blocks = sections.flatMap((section) => institutionalCardBlocks(section.title, section.lines));
  return renderOfficialInstitutionalDocument({
    attendanceDate: formatDateTime(snapshot.started_at),
    attendanceLabel: snapshot.appointment ? `Consulta agendada #${snapshot.appointment.id}` : "Consulta sem agendamento",
    documentNumber: consultationCode(snapshot.consultation_id),
    documentTitle: "Prontuário Completo",
    issuedAt: formatDateTime(snapshot.completed_at),
    patient: {
      birthDate: formatDate(snapshot.patient.birth_date),
      name: snapshot.patient.name,
      passport: formatPatientPassport(snapshot.patient.passport),
    },
    professional: {
      crmCode: snapshot.professional.crm_code,
      id: snapshot.professional.id,
      name: snapshot.professional.name,
      role: snapshot.professional.position ?? "Cargo não informado",
    },
    recordNumber: formatPatientPassport(snapshot.patient.passport),
    subtitle: "Consulta clínica consolidada",
  }, blocks, identity, "prontuário da consulta");
}

function consultationSections(snapshot: ConsultationSnapshot): Section[] {
  const diagnosis = snapshot.selected_diagnosis;
  const examAnalysis = snapshot.exam_analysis;
  const sections: Section[] = [
    section("Identificação e cobertura", [
      `Nascimento: ${formatDate(snapshot.patient.birth_date)} · Telefone: ${snapshot.patient.phone || "Não informado"}`,
      `Contato de emergência: ${joinPresent(snapshot.patient.emergency_contact_name, snapshot.patient.emergency_contact_phone) || "Não informado"}`,
      `Alergias: ${snapshot.patient.allergies || "Não informadas"}`,
      `Plano: ${snapshot.patient.plan_code || "Não informado"}${snapshot.patient.health_plan ? ` · cobertura ${formatDate(snapshot.patient.health_plan.coverage_start ?? null)} a ${formatDate(snapshot.patient.health_plan.coverage_end ?? null)}` : ""}`,
      `Parcerias: ${snapshot.patient.partnerships.map((item) => item.name).join(", ") || "Nenhuma parceria ativa"}`,
    ]),
    section("Agendamento e motivo", snapshot.appointment ? [
      `Horário previsto: ${formatDateTime(snapshot.appointment.scheduled_start)} a ${formatDateTime(snapshot.appointment.scheduled_end)}`,
      `Motivo: ${snapshot.appointment.reason}`,
      `Observações: ${snapshot.appointment.notes || "Não informadas"}`,
    ] : ["Consulta sem agendamento prévio (demanda espontânea)."]),
    section("Sinais vitais e classificações", [
      `Pressão arterial: ${value(snapshot.vitals.blood_pressure_systolic)}/${value(snapshot.vitals.blood_pressure_diastolic)} mmHg · ${value(snapshot.vitals.blood_pressure_class)}`,
      `Temperatura: ${value(snapshot.vitals.temperature_c)} °C · ${value(snapshot.vitals.temperature_class)}`,
      `Frequência cardíaca: ${value(snapshot.vitals.heart_rate_bpm)} bpm · ${value(snapshot.vitals.heart_rate_class)}`,
      `Saturação de oxigênio: ${value(snapshot.vitals.oxygen_saturation_percent)}% · ${value(snapshot.vitals.oxygen_saturation_class)}`,
      `Escala de dor: ${value(snapshot.vitals.pain_score)}/10`,
    ]),
    section("Anamnese e evolução", [snapshot.anamnesis]),
    section("Análise de exames", [
      examAnalysis?.no_exam_needed === true ? "Conclusão: nenhum exame necessário." : "Conclusão: exames complementares avaliados.",
      `Justificativa: ${stringValue(examAnalysis?.reason) || "Não informada"}`,
      ...snapshot.exams.flatMap((exam) => [
        `Exame #${value(exam.id)} · ${value(exam.type)} · ${statusLabel(stringValue(exam.status))} · solicitado em ${formatDateTime(stringValue(exam.requested_at))}`,
        `Indicação: ${stringValue(exam.indication) || "Não informada"}`,
        stringValue(exam.status) === "completed" ? `Resultado: ${resultText(exam.result)}` : "Resultado: pendente no momento da conclusão.",
      ]),
      ...(snapshot.exams.length ? [] : ["Nenhum exame foi vinculado à consulta."]),
    ]),
    section("Diagnóstico selecionado", [
      `Gravidade: ${severityLabel(stringValue(diagnosis.severity))}`,
      `Diagnóstico: ${stringValue(diagnosis.diagnosis) || stringValue(diagnosis.title) || "Não informado"}`,
      `Justificativa clínica: ${stringValue(diagnosis.reasoning_summary) || stringValue(diagnosis.rationale) || "Não informada"}`,
    ]),
    section("Diagnóstico final e plano", [snapshot.final_diagnosis_plan]),
  ];

  if (snapshot.casts.length || snapshot.hospitalizations.length || snapshot.complementary_action !== "NONE") {
    sections.push(section("Condutas complementares", [
      `Conduta selecionada: ${complementaryLabel(snapshot.complementary_action)}`,
      ...snapshot.casts.map((cast) => `Gesso #${value(cast.id)} · ${value(cast.body_region)} · ${value(cast.laterality)} · ${statusLabel(stringValue(cast.status))} · aplicado em ${formatDateTime(stringValue(cast.applied_at))} · responsável ${value(cast.responsible)}`),
      ...snapshot.hospitalizations.map((hospitalization) => `Internação #${value(hospitalization.id)} · leito ${value(hospitalization.bed)} · ${statusLabel(stringValue(hospitalization.status))} · ${value(hospitalization.reason)} · admitida em ${formatDateTime(stringValue(hospitalization.admitted_at))}`),
    ]));
  }
  if (snapshot.certificates.length) sections.push(section("Atestados vinculados", snapshot.certificates.map((certificate) => `Atestado AT-${String(value(certificate.id)).padStart(6, "0")} · ${value(certificate.leave_days)} dia(s) · CID-10 ${value(certificate.cid_code)} · ${statusLabel(stringValue(certificate.status))}`)));
  if (snapshot.follow_ups.length) sections.push(section("Retornos agendados", snapshot.follow_ups.map((followUp) => `Retorno #${value(followUp.id)} · ${formatDateTime(stringValue(followUp.scheduled_start))} · ${value(followUp.professional)} · ${statusLabel(stringValue(followUp.status))} · ${value(followUp.reason)}`)));
  if (snapshot.prescription?.items.length) sections.push(section("Prescrição RP", [
    ...snapshot.prescription.items.flatMap((item, index) => [
      `${index + 1}. ${value(item.rp_name_snapshot)} (${value(item.reference_name_snapshot)}) · ${value(item.final_quantity_snapshot)} item(ns)`,
      `Posologia: ${value(item.dose_snapshot)} · ${value(item.frequency_snapshot)} · ${value(item.duration_snapshot)} · ${value(item.route_snapshot)}`,
      `Orientações: ${value(item.instructions_snapshot)}${item.justification_snapshot ? ` · Justificativa: ${value(item.justification_snapshot)}` : ""}`,
    ]),
    snapshot.prescription.rp_notice,
  ]));
  sections.push(section("Orientações ao paciente", [snapshot.orientation_text]));
  return sections;
}

function section(title: string, values: string[]): Section {
  const lines = values.flatMap((item) => wrapText(item || "Não informado", 94));
  return { lines: lines.length ? lines : ["Não informado"], title };
}

function wrapText(input: string, maxCharacters: number) {
  const lines: string[] = [];
  for (const paragraph of input.replace(/\r/g, "").split("\n")) {
    const words = paragraph.trim().split(/\s+/).filter(Boolean);
    if (!words.length) { lines.push(""); continue; }
    let line = "";
    for (const word of words) {
      const candidate = line ? `${line} ${word}` : word;
      if (candidate.length <= maxCharacters) line = candidate;
      else { if (line) lines.push(line); line = word.length <= maxCharacters ? word : `${word.slice(0, maxCharacters - 1)}…`; }
    }
    if (line) lines.push(line);
  }
  return lines;
}

function resultText(input: unknown): string {
  if (!input) return "Não informado";
  if (typeof input === "string") return input;
  if (Array.isArray(input)) return input.map(resultText).join("; ");
  if (typeof input === "object") return Object.entries(input as Record<string, unknown>)
    .filter(([, item]) => item !== null && item !== "" && item !== undefined)
    .map(([key, item]) => `${humanize(key)}: ${resultText(item)}`).join("; ") || "Não informado";
  return String(input);
}

function value(input: unknown) { return input === null || input === undefined || input === "" ? "Não informado" : String(input); }
function stringValue(input: unknown) { return typeof input === "string" ? input : ""; }
function joinPresent(...items: Array<string | null>) { return items.filter(Boolean).join(" · "); }
function complementaryLabel(input: string) { return ({ NONE: "Nenhuma", CAST: "Imobilização com gesso", HOSPITALIZATION: "Internação" } as Record<string, string>)[input] ?? input; }
function severityLabel(input: string) { return ({ normal: "Normal", grave: "Grave", gravissimo: "Gravíssimo" } as Record<string, string>)[input] ?? "Não informada"; }
function statusLabel(input: string) { return (({ requested: "Solicitado", in_progress: "Em andamento", awaiting_review: "Aguardando revisão", completed: "Concluído", active: "Ativo", discharged: "Alta registrada", cancelled: "Cancelado", finalized: "Finalizado", draft: "Rascunho", scheduled: "Agendado", confirmed: "Confirmado", no_show: "Não compareceu" } as Record<string, string>)[input] ?? input) || "Não informado"; }
function humanize(input: string) { return input.replace(/_/g, " ").replace(/^./, (valueText) => valueText.toUpperCase()); }
function formatDate(input: string | null) { if (!input) return "Não informado"; const date = new Date(`${input}T12:00:00`); return Number.isNaN(date.getTime()) ? "Não informado" : new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeZone: "America/Sao_Paulo" }).format(date); }
function formatDateTime(input: string) { const date = new Date(input); return Number.isNaN(date.getTime()) ? "Não informado" : new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" }).format(date); }
function consultationCode(id: number) { return `CONS-${String(id).padStart(6, "0")}`; }
