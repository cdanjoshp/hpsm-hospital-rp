import { PDFDocument, PageSizes, StandardFonts, rgb, type PDFFont, type PDFImage, type PDFPage } from "pdf-lib";
import {
  finalExamBloodType,
  finalExamImagingResult,
  finalExamLaboratoryResult,
  flagLabel,
  formatClinicalDateTime,
  genericStructuredFacts,
  imagingContrastLabel,
  imagingLateralityLabel,
  type FinalExamDocumentModel,
} from "./final-exam-document";
import type { ProfessionalDocumentIdentityAssets } from "./professional-identity";
import { formatPatientPassport } from "./passport";
import { HPSM_COMPASS_FACETS } from "./hpsm-brand";
import { fitSignatureInk, signatureInk } from "./signature-ink";

export type FinalExamPdfImage = {
  bytes: Uint8Array;
  id: string;
  mimeType: string;
};

const PAGE_WIDTH = PageSizes.A4[0];
const PAGE_HEIGHT = PageSizes.A4[1];
const MARGIN_X = 42;
const CONTENT_WIDTH = PAGE_WIDTH - MARGIN_X * 2;
const CONTENT_BOTTOM = 52;
const BLUE = rgb(0.035, 0.36, 0.62);
const NAVY = rgb(0.035, 0.16, 0.29);
const INK = rgb(0.043, 0.051, 0.063);
const MUTED = rgb(0.086, 0.098, 0.114);
const LINE = rgb(0.78, 0.84, 0.88);
const SOFT_BLUE = rgb(0.94, 0.975, 0.995);
const WHITE = rgb(1, 1, 1);

export async function renderFinalExamPdf(
  document: FinalExamDocumentModel,
  imageAssets: FinalExamPdfImage[] = [],
  identityInput?: ProfessionalDocumentIdentityAssets | Array<{ bytes: Uint8Array; personId: string }>,
) {
  const pdf = await PDFDocument.create();
  const regular = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const renderer = new PdfRenderer(pdf, regular, bold, document);
  renderer.firstPage();
  renderer.identification();

  if (document.showIndication && document.indication) renderer.textSection("Indicação clínica", document.indication);
  if (document.clinicalContext && (!document.showIndication || document.clinicalContext !== document.indication)) renderer.textSection("Contexto clínico", document.clinicalContext);
  if (document.betaHcgOutcome) renderer.factsSection("Dados da solicitação", [{ label: "Resultado informado", value: document.betaHcgOutcome }, ...(document.gestationalWeeks ? [{ label: "Idade gestacional informada", value: `${document.gestationalWeeks} semanas` }] : [])]);

  const imagingResult = finalExamImagingResult(document);
  if (imagingResult) {
    const facts = [
      { label: "Região", value: imagingResult.region === "Outra região" ? imagingResult.other_region : imagingResult.region },
      ...(imagingResult.template_snapshot.supports_laterality ? [{ label: "Lateralidade", value: imagingLateralityLabel(imagingResult.laterality) }] : []),
      ...(imagingResult.template_snapshot.supports_contrast ? [{ label: "Contraste", value: imagingContrastLabel(imagingResult.contrast) }] : []),
    ];
    renderer.factsSection("Informações do exame", facts);
  }

  const bloodType = finalExamBloodType(document);
  if (bloodType) renderer.bloodType(bloodType);

  const laboratoryResult = finalExamLaboratoryResult(document);
  if (laboratoryResult) {
    renderer.labTable(laboratoryResult.parameters.map((parameter) => [
      parameter.label,
      parameter.value || "Não informado",
      parameter.unit || "-",
      parameter.reference || "-",
      flagLabel(parameter.flag),
    ]));
  }

  const structuredFacts = genericStructuredFacts(document.resultData);
  if (structuredFacts.length) renderer.factsSection("Dados estruturados", structuredFacts);

  const assetById = new Map(imageAssets.map((asset) => [asset.id, asset]));
  for (let index = 0; index < document.images.length; index += 1) {
    const image = document.images[index];
    const asset = assetById.get(image.id);
    if (!asset) throw new Error("Uma das imagens finais não pôde ser carregada para o PDF.");
    await renderer.examImage(asset, index + 1, image.source === "ai_generated" ? null : image.caption);
  }

  const reportSections = [
    { label: document.reportConfig.fields.technique.label || "Técnica / Método", value: document.content.technique },
    { label: document.reportConfig.fields.findings.label || "Achados", value: document.content.findings },
    { label: document.reportConfig.fields.conclusion.label || "Conclusão", value: document.content.conclusion },
    { label: "Conduta / Próximos passos", value: document.content.observations },
  ];
  for (const section of reportSections) if (section.value) renderer.textSection(section.label, section.value);

  const legacy = Array.isArray(identityInput) ? identityInput.find((asset) => asset.personId === document.executedBy.id) : null;
  const identity = !Array.isArray(identityInput) ? identityInput : legacy ? { personId: legacy.personId, rubricBytes: legacy.bytes, signatureBytes: legacy.bytes } : undefined;
  await renderer.professional(identity);
  renderer.finish();
  pdf.setTitle(`${document.examCode} - ${document.exam.name}`);
  pdf.setAuthor("Hospital Santa Marcelina");
  pdf.setSubject("Laudo final de exame concluído");
  pdf.setCreator("Hospital Santa Marcelina");
  pdf.setProducer("Hospital Santa Marcelina");
  pdf.setCreationDate(new Date(document.issuedAt));
  return pdf.save({ useObjectStreams: true });
}

class PdfRenderer {
  private page!: PDFPage;
  private y = 0;

  constructor(
    private readonly pdf: PDFDocument,
    private readonly regular: PDFFont,
    private readonly bold: PDFFont,
    private readonly document: FinalExamDocumentModel,
  ) {}

  firstPage() {
    this.page = this.pdf.addPage(PageSizes.A4);
    this.drawOfficialHeader(false);
    this.y = PAGE_HEIGHT - 132;
  }

  private continuationPage() {
    this.page = this.pdf.addPage(PageSizes.A4);
    this.drawOfficialHeader(true);
    this.y = PAGE_HEIGHT - 132;
  }

  private drawOfficialHeader(continuation: boolean) {
    this.page.drawRectangle({ x: 0, y: PAGE_HEIGHT - 105, width: PAGE_WIDTH, height: 105, color: NAVY });
    this.drawLogo(48, PAGE_HEIGHT - 52);
    this.draw("HPSM", 79, PAGE_HEIGHT - 39, 18, this.bold, WHITE);
    this.draw("HOSPITAL SANTA MARCELINA", 79, PAGE_HEIGHT - 57, 8.3, this.bold, SOFT_BLUE);
    this.draw(continuation ? "LAUDO DE EXAME · CONTINUAÇÃO" : "LAUDO DE EXAME", 79, PAGE_HEIGHT - 78, 12.5, this.bold, WHITE);
    this.drawRight(this.document.examCode, PAGE_WIDTH - MARGIN_X, PAGE_HEIGHT - 45, 9.5, this.bold, SOFT_BLUE);
    this.drawRight(this.document.exam.name, PAGE_WIDTH - MARGIN_X, PAGE_HEIGHT - 67, 9, this.bold, WHITE);
  }

  identification() {
    const boxHeight = 79;
    this.ensure(boxHeight + 8);
    this.page.drawRectangle({ x: MARGIN_X, y: this.y - boxHeight, width: CONTENT_WIDTH, height: boxHeight, color: SOFT_BLUE, borderColor: LINE, borderWidth: 0.6 });
    const columns = [MARGIN_X + 13, MARGIN_X + 205, MARGIN_X + 354];
    this.labelValue(columns[0], this.y - 17, 178, "Paciente", this.document.patient.name, `Passaporte ${formatPatientPassport(this.document.patient.passport)}`);
    this.labelValue(columns[1], this.y - 17, 133, "Identificador", this.document.examCode, this.document.exam.category_name);
    this.labelValue(columns[2], this.y - 17, 143, "Data do exame", formatClinicalDateTime(this.document.examDate), `Concluído em ${formatClinicalDateTime(this.document.completedAt)}`);
    this.y -= boxHeight + 13;
  }

  textSection(title: string, text: string) {
    const titleHeight = 22;
    this.ensure(titleHeight + 24);
    this.sectionHeading(title);
    const lines = wrapText(pdfSafe(text), this.regular, 10.2, CONTENT_WIDTH);
    for (const line of lines) {
      this.ensure(15);
      this.draw(line, MARGIN_X, this.y, 10.2, this.regular, INK);
      this.y -= 14.5;
    }
    this.y -= 8;
  }

  factsSection(title: string, facts: Array<{ label: string; value: string }>) {
    if (!facts.length) return;
    this.ensure(70);
    this.sectionHeading(title);
    const columnWidth = CONTENT_WIDTH / Math.min(3, facts.length);
    const maxLines = Math.max(...facts.map((fact) => wrapText(pdfSafe(fact.value), this.bold, 9.5, columnWidth - 18).length));
    const height = 31 + maxLines * 12;
    this.ensure(height);
    facts.forEach((fact, index) => {
      const x = MARGIN_X + index * columnWidth;
      this.draw(pdfSafe(fact.label).toUpperCase(), x, this.y, 7.2, this.bold, MUTED);
      wrapText(pdfSafe(fact.value), this.bold, 9.5, columnWidth - 18).forEach((line, lineIndex) => this.draw(line, x, this.y - 15 - lineIndex * 12, 9.5, this.bold, NAVY));
    });
    this.y -= height;
  }

  bloodType(value: string) {
    this.ensure(82);
    this.sectionHeading("Tipagem sanguínea");
    this.page.drawRectangle({ x: MARGIN_X, y: this.y - 49, width: 90, height: 49, color: SOFT_BLUE, borderColor: BLUE, borderWidth: 0.8 });
    this.draw(value, MARGIN_X + 17, this.y - 34, 24, this.bold, BLUE);
    this.labelValue(MARGIN_X + 112, this.y - 12, 120, "Grupo ABO", value.replace(/[+-]$/, ""));
    this.labelValue(MARGIN_X + 266, this.y - 12, 150, "Fator Rh", value.endsWith("+") ? "Positivo" : "Negativo");
    this.y -= 65;
  }

  labTable(rows: string[][]) {
    this.ensure(70);
    this.sectionHeading("Resultados");
    const widths = [132, 84, 58, 150, 87];
    this.drawTableRow(["Parâmetro", "Resultado", "Unidade", "Referência", "Situação"], widths, true);
    for (const row of rows) this.drawTableRow(row, widths, false);
    this.y -= 10;
  }

  async examImage(asset: FinalExamPdfImage, index: number, caption: string | null) {
    let embedded: PDFImage;
    if (isPng(asset.bytes, asset.mimeType)) embedded = await this.pdf.embedPng(asset.bytes);
    else if (isJpeg(asset.bytes, asset.mimeType)) embedded = await this.pdf.embedJpg(asset.bytes);
    else throw new Error("Uma imagem final está em formato incompatível com o PDF.");

    const dimensions = embedded.scale(1);
    const maxWidth = CONTENT_WIDTH;
    const maxHeight = 590;
    const scale = Math.min(maxWidth / dimensions.width, maxHeight / dimensions.height, 1);
    const width = dimensions.width * scale;
    const height = dimensions.height * scale;
    const captionLines = caption ? wrapText(pdfSafe(caption), this.regular, 8.5, CONTENT_WIDTH) : [];
    const blockHeight = 31 + height + 18 + captionLines.length * 11;
    if (blockHeight > this.y - CONTENT_BOTTOM || (index > 1 && this.y < PAGE_HEIGHT - 160)) this.continuationPage();
    this.ensure(Math.min(blockHeight, PAGE_HEIGHT - 120));
    this.sectionHeading(`Imagem ${index}`);
    const x = MARGIN_X + (CONTENT_WIDTH - width) / 2;
    this.page.drawImage(embedded, { x, y: this.y - height, width, height });
    this.y -= height + 11;
    if (captionLines.length) {
      for (const line of captionLines) {
        this.ensure(12);
        this.draw(line, MARGIN_X, this.y, 8.5, this.regular, MUTED);
        this.y -= 11;
      }
    }
    this.y -= 8;
  }

  async professional(identity?: ProfessionalDocumentIdentityAssets) {
    this.ensure(190);
    this.sectionHeading("Assinatura e identificação");
    this.draw(this.document.executedBy.name, MARGIN_X + 12, this.y - 96, 9.5, this.bold, NAVY);
    this.draw(this.document.executedBy.position ?? "Cargo não informado", MARGIN_X + 12, this.y - 109, 8.2, this.regular, MUTED);
    this.draw(`CRM interno ${this.document.executedBy.identity?.crm_code ?? "Não informado"}`, MARGIN_X + 12, this.y - 122, 8.2, this.bold, BLUE);
    this.draw("RUBRICA DO RESPONSÁVEL", PAGE_WIDTH - MARGIN_X - 142, this.y - 111, 6.7, this.bold, MUTED);
    if (identity) {
      const signatureInkAsset = signatureInk(identity.signatureBytes);
      const rubricInkAsset = signatureInk(identity.rubricBytes);
      const signature = await this.pdf.embedPng(signatureInkAsset.bytes);
      const rubric = await this.pdf.embedPng(rubricInkAsset.bytes);
      this.page.drawImage(signature, { x: MARGIN_X + 17, y: this.y - 89, ...fitSignatureInk(signatureInkAsset, 258, 78) });
      this.page.drawImage(rubric, { x: PAGE_WIDTH - MARGIN_X - 139, y: this.y - 94, ...fitSignatureInk(rubricInkAsset, 121, 62) });
    }
    this.y -= 162;
  }

  finish() {
    const pages = this.pdf.getPages();
    pages.forEach((page, index) => {
      page.drawLine({ start: { x: MARGIN_X, y: 44 }, end: { x: PAGE_WIDTH - MARGIN_X, y: 44 }, color: LINE, thickness: 0.6 });
      const footerNotice = "Documento gerado exclusivamente para uso em RP.";
      page.drawText(footerNotice, { x: (PAGE_WIDTH - this.bold.widthOfTextAtSize(footerNotice, 7.8)) / 2, y: 31, size: 7.8, font: this.bold, color: NAVY });
      page.drawText("seu-hospital.example", { x: MARGIN_X, y: 16, size: 7.2, font: this.bold, color: NAVY });
      const center = `Cuidar de pessoas transforma realidades. · Página ${index + 1} de ${pages.length}`;
      page.drawText(center, { x: (PAGE_WIDTH - this.regular.widthOfTextAtSize(center, 7.2)) / 2, y: 16, size: 7.2, font: this.regular, color: MUTED });
      const issued = `Emitido em ${formatClinicalDateTime(this.document.issuedAt)}`;
      page.drawText(issued, { x: PAGE_WIDTH - MARGIN_X - this.regular.widthOfTextAtSize(issued, 7.2), y: 16, size: 7.2, font: this.regular, color: MUTED });
    });
  }

  private drawTableRow(values: string[], widths: number[], header: boolean) {
    const font = header ? this.bold : this.regular;
    const fontSize = header ? 7.5 : 8.4;
    const lineHeight = 10.5;
    const linesByCell = values.map((value, index) => wrapText(pdfSafe(value), font, fontSize, widths[index] - 10));
    const height = Math.max(header ? 25 : 28, Math.max(...linesByCell.map((lines) => lines.length)) * lineHeight + 13);
    if (this.y - height < CONTENT_BOTTOM) {
      this.continuationPage();
      if (!header) this.drawTableRow(["Parâmetro", "Resultado", "Unidade", "Referência", "Situação"], widths, true);
    }
    this.page.drawRectangle({ x: MARGIN_X, y: this.y - height, width: CONTENT_WIDTH, height, color: header ? SOFT_BLUE : WHITE, borderColor: LINE, borderWidth: 0.45 });
    let x = MARGIN_X;
    linesByCell.forEach((lines, column) => {
      if (column > 0) this.page.drawLine({ start: { x, y: this.y }, end: { x, y: this.y - height }, color: LINE, thickness: 0.35 });
      lines.forEach((line, lineIndex) => this.draw(line, x + 5, this.y - 12 - lineIndex * lineHeight, fontSize, font, header ? NAVY : INK));
      x += widths[column];
    });
    this.y -= height;
  }

  private sectionHeading(title: string) {
    this.ensure(31);
    this.draw(pdfSafe(title), MARGIN_X, this.y, 11.3, this.bold, NAVY);
    this.page.drawLine({ start: { x: MARGIN_X, y: this.y - 8 }, end: { x: PAGE_WIDTH - MARGIN_X, y: this.y - 8 }, color: LINE, thickness: 0.55 });
    this.y -= 25;
  }

  private labelValue(x: number, y: number, width: number, label: string, value: string, detail?: string) {
    this.draw(pdfSafe(label).toUpperCase(), x, y, 7.1, this.bold, MUTED);
    const valueLines = wrapText(pdfSafe(value), this.bold, 9.3, width);
    valueLines.slice(0, 2).forEach((line, index) => this.draw(line, x, y - 15 - index * 11, 9.3, this.bold, NAVY));
    if (detail) this.drawEllipsized(pdfSafe(detail), x, y - 18 - Math.min(2, valueLines.length) * 11, width, 7.7, this.regular, MUTED);
  }

  private drawLogo(centerX: number, centerY: number) {
    const scale = 0.32;
    const colors = { light: rgb(0.70, 0.90, 1), blue: rgb(0.20, 0.63, 0.93), navy: rgb(0.08, 0.40, 0.72) };
    for (const facet of HPSM_COMPASS_FACETS) {
      this.page.drawSvgPath(facet.d, {
        x: centerX - 60 * scale,
        y: centerY + 60 * scale,
        scale,
        color: colors[facet.tone],
      });
    }
  }

  private ensure(height: number) {
    if (this.y - height < CONTENT_BOTTOM) this.continuationPage();
  }

  private draw(value: string, x: number, y: number, size: number, font: PDFFont, color = INK) {
    this.page.drawText(pdfSafe(value), { x, y, size, font, color });
  }

  private drawRight(value: string, right: number, y: number, size: number, font: PDFFont, color = INK) {
    const safe = pdfSafe(value);
    this.draw(safe, right - font.widthOfTextAtSize(safe, size), y, size, font, color);
  }

  private drawEllipsized(value: string, x: number, y: number, width: number, size: number, font: PDFFont, color = INK) {
    const original = pdfSafe(value);
    let safe = original;
    let end = original.length;
    while (end > 1 && font.widthOfTextAtSize(safe, size) > width) {
      end -= 1;
      safe = `${original.slice(0, end).trimEnd()}...`;
    }
    this.draw(safe, x, y, size, font, color);
  }
}

function wrapText(value: string, font: PDFFont, size: number, maxWidth: number) {
  const lines: string[] = [];
  for (const paragraph of value.replace(/\r/g, "").split("\n")) {
    const words = paragraph.trim().split(/\s+/).filter(Boolean);
    if (!words.length) {
      lines.push("");
      continue;
    }
    let line = "";
    for (const word of words) {
      const candidate = line ? `${line} ${word}` : word;
      if (font.widthOfTextAtSize(candidate, size) <= maxWidth) {
        line = candidate;
        continue;
      }
      if (line) lines.push(line);
      if (font.widthOfTextAtSize(word, size) <= maxWidth) {
        line = word;
        continue;
      }
      let fragment = "";
      for (const character of word) {
        if (fragment && font.widthOfTextAtSize(fragment + character, size) > maxWidth) {
          lines.push(fragment);
          fragment = character;
        } else fragment += character;
      }
      line = fragment;
    }
    if (line) lines.push(line);
  }
  return lines;
}

function pdfSafe(value: string) {
  return value
    .normalize("NFC")
    .replace(/[–—]/g, "-")
    .replace(/[•·]/g, "-")
    .replace(/[“”]/g, '"')
    .replace(/[‘’]/g, "'")
    .replace(/[^\x09\x0A\x0D\x20-\xFF]/g, "?");
}

function isPng(bytes: Uint8Array, mimeType: string) {
  return mimeType === "image/png" || (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47);
}

function isJpeg(bytes: Uint8Array, mimeType: string) {
  return mimeType === "image/jpeg" || (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff);
}
