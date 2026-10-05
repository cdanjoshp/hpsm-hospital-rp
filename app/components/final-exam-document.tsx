import { HpsmLogo } from "./hpsm-logo";
import {
  finalExamBloodType,
  finalExamImagingResult,
  finalExamLaboratoryResult,
  flagLabel,
  formatClinicalDate,
  formatClinicalDateTime,
  genericStructuredFacts,
  imagingContrastLabel,
  imagingLateralityLabel,
  type FinalExamDocumentModel,
} from "../lib/final-exam-document";
import { formatPatientPassport } from "../lib/passport";

export function FinalExamDocument({ document }: { document: FinalExamDocumentModel }) {
  const laboratoryResult = finalExamLaboratoryResult(document);
  const imagingResult = finalExamImagingResult(document);
  const bloodType = finalExamBloodType(document);
  const structuredFacts = genericStructuredFacts(document.resultData);
  const reportSections = [
    { key: "technique", label: document.reportConfig.fields.technique.label || "Técnica / Método", value: document.content.technique },
    { key: "findings", label: document.reportConfig.fields.findings.label || "Achados", value: document.content.findings },
    { key: "conclusion", label: document.reportConfig.fields.conclusion.label || "Conclusão", value: document.content.conclusion },
    { key: "observations", label: "Conduta / Próximos passos", value: document.content.observations },
  ].filter((section) => section.value);

  return <article className="final-exam-document" aria-label={`Documento final ${document.examCode}`}>
    <header className="final-exam-header">
      <HpsmLogo className="final-exam-logo" />
      <div>
        <span>Cidade dos Anjos</span>
        <h2>Laudo de Exame</h2>
        <strong>{document.exam.name}</strong>
      </div>
      <p>{document.examCode}</p>
    </header>

    <section className="final-exam-identification" aria-label="Identificação do exame">
      <DocumentFact label="Paciente" value={document.patient.name} detail={`Passaporte ${formatPatientPassport(document.patient.passport)}`} />
      <DocumentFact label="Identificador" value={document.examCode} detail={document.exam.category_name} />
      <DocumentFact label="Data do exame" value={formatClinicalDateTime(document.examDate)} detail={`Concluído em ${formatClinicalDateTime(document.completedAt)}`} />
    </section>

    {document.betaHcgOutcome ? <section className="final-exam-structured-section"><h3>Dados da solicitação</h3><dl className="final-exam-imaging-facts"><DocumentFact label="Resultado informado" value={document.betaHcgOutcome} />{document.gestationalWeeks ? <DocumentFact label="Idade gestacional informada" value={`${document.gestationalWeeks} semanas`} /> : null}</dl></section> : null}

    {(document.showIndication && document.indication) || document.clinicalContext ? <section className="final-exam-clinical-context">
      {document.showIndication && document.indication ? <DocumentSection title="Indicação clínica" text={document.indication} /> : null}
      {document.clinicalContext && (!document.showIndication || document.clinicalContext !== document.indication) ? <DocumentSection title="Contexto clínico" text={document.clinicalContext} /> : null}
    </section> : null}

    {imagingResult ? <section className="final-exam-structured-section">
      <h3>Informações do exame</h3>
      <dl className="final-exam-imaging-facts">
        <DocumentFact label="Região" value={imagingResult.region === "Outra região" ? imagingResult.other_region : imagingResult.region} />
        {imagingResult.template_snapshot.supports_laterality ? <DocumentFact label="Lateralidade" value={imagingLateralityLabel(imagingResult.laterality)} /> : null}
        {imagingResult.template_snapshot.supports_contrast ? <DocumentFact label="Contraste" value={imagingContrastLabel(imagingResult.contrast)} /> : null}
      </dl>
    </section> : null}

    {bloodType ? <section className="final-exam-blood-type">
      <div><span>Tipagem sanguínea</span><strong>{bloodType}</strong></div>
      <dl><DocumentFact label="Grupo ABO" value={bloodType.replace(/[+-]$/, "")} /><DocumentFact label="Fator Rh" value={bloodType.endsWith("+") ? "Positivo" : "Negativo"} /></dl>
    </section> : null}

    {laboratoryResult ? <section className="final-exam-structured-section final-exam-laboratory">
      <h3>Resultados</h3>
      <div className="final-exam-table-wrap"><table>
        <thead><tr><th>Parâmetro</th><th>Resultado</th><th>Unidade</th><th>Referência</th><th>Situação</th></tr></thead>
        <tbody>{laboratoryResult.parameters.map((parameter) => <tr key={parameter.key}>
          <th scope="row">{parameter.label}</th><td>{parameter.value || "Não informado"}</td><td>{parameter.unit || "-"}</td><td>{parameter.reference || "-"}</td><td>{flagLabel(parameter.flag)}</td>
        </tr>)}</tbody>
      </table></div>
    </section> : null}

    {structuredFacts.length ? <section className="final-exam-structured-section">
      <h3>Dados estruturados</h3>
      <dl className="final-exam-generic-facts">{structuredFacts.map((fact) => <DocumentFact key={fact.label} label={fact.label} value={fact.value} />)}</dl>
    </section> : null}

    {document.images.length ? <section className="final-exam-images" aria-label="Imagens do exame">
      <h3>Imagens do exame</h3>
      {document.images.map((image, index) => <figure key={image.id}>
        {image.signed_url ? <>
          {/* eslint-disable-next-line @next/next/no-img-element -- URL privada temporária com proporção nativa para impressão. */}
          <img src={image.signed_url} alt={`Imagem ${index + 1} do exame ${document.examCode}`} />
        </> : <div className="final-exam-image-unavailable">Imagem disponível somente na emissão autorizada.</div>}
        <figcaption><span>Imagem {index + 1}</span>{image.source !== "ai_generated" && image.caption ? <p>{image.caption}</p> : null}</figcaption>
      </figure>)}
    </section> : null}

    {reportSections.length ? <section className="final-exam-report-body" aria-label="Laudo final aprovado">
      {reportSections.map((section) => <DocumentSection key={section.key} title={section.label} text={section.value ?? ""} />)}
    </section> : null}

    <section className="final-exam-professionals" aria-label="Médico responsável">
      <DocumentProfessional label="Médico responsável" person={document.executedBy} />
      <div><span>Concluído em</span><strong>{formatClinicalDateTime(document.completedAt)}</strong><small>Resultado final aprovado</small></div>
    </section>

    <footer className="final-exam-footer">
      <strong>Documento gerado exclusivamente para uso em RP.</strong>
      <span>seu-hospital.example</span>
      <span>Cuidar de pessoas transforma realidades.</span>
      <span>{document.examCode}</span>
      <span>Emitido em {formatClinicalDate(document.issuedAt)} às {new Intl.DateTimeFormat("pt-BR", { hour: "2-digit", hour12: false, minute: "2-digit", timeZone: "America/Sao_Paulo" }).format(new Date(document.issuedAt))}</span>
    </footer>
  </article>;
}

function DocumentFact({ detail, label, value }: { detail?: string; label: string; value: string }) {
  return <div><dt>{label}</dt><dd>{value || "Não informado"}</dd>{detail ? <small>{detail}</small> : null}</div>;
}

function DocumentSection({ text, title }: { text: string; title: string }) {
  return <section className="final-exam-section"><h3>{title}</h3><p>{text}</p></section>;
}

function DocumentProfessional({ label, person }: { label: string; person: FinalExamDocumentModel["executedBy"] }) {
  return <div className="final-exam-professional-identity"><span>{label}</span>
    {person.identity?.signature_image_url ? <>
      {/* eslint-disable-next-line @next/next/no-img-element -- assinatura privada com URL temporária, preservada no documento. */}
      <img className="final-exam-ink-signature" alt={`Assinatura de ${person.name}`} src={person.identity.signature_image_url} />
    </> : null}
    <strong>{person.name}</strong>
    {person.identity?.crm_code ? <small>CRM interno {person.identity.crm_code}</small> : null}
    <small>{person.position ?? "Cargo não informado"}</small>
    {person.identity?.rubric_image_url ? <div className="final-exam-rubric">
      {/* eslint-disable-next-line @next/next/no-img-element -- rubrica privada com URL temporária, preservada no documento. */}
      <img className="final-exam-ink-rubric" alt={`Rubrica de ${person.name}`} src={person.identity.rubric_image_url} />
      <span>Rubrica do responsável</span>
    </div> : null}
  </div>;
}
