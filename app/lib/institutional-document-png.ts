import { Resvg } from "@cf-wasm/resvg";
import sourceSansLatin from "@fontsource-variable/source-sans-3/files/source-sans-3-latin-wght-normal.woff2?inline";
import sourceSansLatinExt from "@fontsource-variable/source-sans-3/files/source-sans-3-latin-ext-wght-normal.woff2?inline";
import originalCompass from "../assets/hpsm-compass-original.png?inline";
import { HPSM_COMPASS_FACETS } from "./hpsm-brand";
import { fitSignatureInk, signatureInk } from "./signature-ink";

export const INSTITUTIONAL_DOCUMENT = {
  blue: "#1769a9", contentWidth: 1072, ink: "#0b0d10", line: "#aec3d1", margin: 64,
  maxBytes: 12 * 1024 * 1024, maxHeight: 14_000, muted: "#16191d", navy: "#082c52",
  pageHeight: 1697, softBlue: "#e7eff4", white: "#e7edf1", width: 1200,
} as const;

export type InstitutionalPngResult = { bytes: Uint8Array; height: number; width: number };
export type InstitutionalIdentityAssets = { personId: string; rubricBytes: Uint8Array; signatureBytes: Uint8Array };
export type InstitutionalDocumentBlock = { height: number; lastPageBottom?: boolean; render: (x: number, y: number, width: number) => string };
export type InstitutionalDocumentDefinition = {
  attendanceDate?: string | null;
  attendanceLabel?: string | null;
  documentNumber: string;
  documentTitle: string;
  issuedAt: string;
  patient: { birthDate?: string | null; name: string; passport: string; sex?: string | null };
  professional: { crmCode: string; id: string; name: string; role: string };
  recordNumber: string;
  subtitle: string;
};

const PAGE_HEIGHT = INSTITUTIONAL_DOCUMENT.pageHeight;
const FIRST_BODY_TOP = 654;
const CONTINUATION_BODY_TOP = 476;
const BODY_BOTTOM = 1510;
const BLOCK_GAP = 8;
const SIGNATURE_HEIGHT = 218;

export async function renderOfficialInstitutionalDocument(
  definition: InstitutionalDocumentDefinition,
  blocks: InstitutionalDocumentBlock[],
  identityInput: InstitutionalIdentityAssets | { bytes: Uint8Array; personId: string },
  documentLabel: string,
): Promise<InstitutionalPngResult> {
  const identity: InstitutionalIdentityAssets = "signatureBytes" in identityInput
    ? identityInput
    : { personId: identityInput.personId, rubricBytes: identityInput.bytes, signatureBytes: identityInput.bytes };
  if (identity.personId !== definition.professional.id) throw new Error(`A identidade profissional não pertence ao responsável pelo ${documentLabel}.`);
  const pages = paginate([...blocks, institutionalSignatureBlock(definition.professional, identity)]);
  const height = pages.length * PAGE_HEIGHT;
  if (height > INSTITUTIONAL_DOCUMENT.maxHeight) throw new Error(`O ${documentLabel} é extenso demais para emissão.`);
  const body = pages.map((page, pageIndex) => {
    const offset = pageIndex * PAGE_HEIGHT;
    let cursor = pageIndex === 0 ? FIRST_BODY_TOP : CONTINUATION_BODY_TOP;
    const content = page.map((block) => {
      const blockTop = block.lastPageBottom ? Math.max(cursor, BODY_BOTTOM - block.height) : cursor;
      const svg = block.render(INSTITUTIONAL_DOCUMENT.margin, offset + blockTop, INSTITUTIONAL_DOCUMENT.contentWidth);
      cursor = blockTop + block.height + BLOCK_GAP;
      return svg;
    }).join("");
    return `${officialPageShell(definition, pageIndex, pages.length, offset)}${content}`;
  }).join("");
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${INSTITUTIONAL_DOCUMENT.width}" height="${height}" viewBox="0 0 ${INSTITUTIONAL_DOCUMENT.width} ${height}">
    <rect width="${INSTITUTIONAL_DOCUMENT.width}" height="${height}" fill="#dfe8f0"/>
    <g font-family="Source Sans 3, sans-serif">${body}</g>
  </svg>`;
  return renderInstitutionalSvg(svg, height, documentLabel);
}

function paginate(blocks: InstitutionalDocumentBlock[]) {
  const pages: InstitutionalDocumentBlock[][] = [[]];
  let used = 0;
  for (const block of blocks) {
    const pageIndex = pages.length - 1;
    const available = BODY_BOTTOM - (pageIndex === 0 ? FIRST_BODY_TOP : CONTINUATION_BODY_TOP);
    if (block.height > BODY_BOTTOM - CONTINUATION_BODY_TOP) throw new Error("Um bloco do documento excede o espaço útil de uma página.");
    const required = (pages[pageIndex].length ? BLOCK_GAP : 0) + block.height;
    if (pages[pageIndex].length && used + required > available) {
      pages.push([block]);
      used = block.height;
    } else {
      pages[pageIndex].push(block);
      used += required;
    }
  }
  // Uma assinatura isolada produz uma página quase vazia. Leva os últimos
  // trechos clínicos para junto dela sem alterar a ordem nem criar nova página.
  const last = pages.at(-1);
  const previous = pages.at(-2);
  if (last?.length === 1 && last[0]?.lastPageBottom && previous?.length) {
    while (previous.length > 1 && pageHeightOf(last) < 430) {
      const candidate = previous.at(-1)!;
      if (pageHeightOf([candidate, ...last]) > BODY_BOTTOM - CONTINUATION_BODY_TOP) break;
      previous.pop();
      last.unshift(candidate);
    }
  }
  return pages;
}

function pageHeightOf(blocks: InstitutionalDocumentBlock[]) {
  return blocks.reduce((height, block, index) => height + (index ? BLOCK_GAP : 0) + block.height, 0);
}

function officialPageShell(definition: InstitutionalDocumentDefinition, pageIndex: number, pageCount: number, offset: number) {
  const y = (value: number) => offset + value;
  const gradient = `official-header-${pageIndex}`;
  const firstPage = pageIndex === 0;
  const patient = definition.patient;
  return `<g>
    <defs><linearGradient id="${gradient}" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#082c52"/><stop offset=".7" stop-color="#0d4679"/><stop offset="1" stop-color="#105b9d"/></linearGradient></defs>
    <rect x="0" y="${offset}" width="1200" height="${PAGE_HEIGHT}" fill="${INSTITUTIONAL_DOCUMENT.white}"/>
    <image x="-660" y="${y(222)}" width="1320" height="1320" preserveAspectRatio="xMidYMid meet" opacity=".12" href="${originalCompass}"/>
    <rect x="0" y="${offset}" width="1200" height="220" fill="url(#${gradient})"/>
    ${institutionalLogoSvg(126, y(105), 62)}
    <text x="211" y="${y(94)}" font-size="53" font-weight="850" letter-spacing=".6" fill="#ffffff" stroke="#ffffff" stroke-width="5" stroke-linejoin="round" paint-order="stroke">HPSM</text>
    <line x1="211" y1="${y(115)}" x2="565" y2="${y(115)}" stroke="#74b9ed" stroke-width="3"/>
    ${svgText(211, y(149), "HOSPITAL SANTA MARCELINA", 18, 700, "#ffffff", "start", 2.4)}
    ${svgText(1110, y(110), "CIDADE DOS ANJOS", 17, 700, "#a9d9f7", "end", 2.4)}
    <rect x="64" y="${y(245)}" width="1072" height="104" rx="15" fill="#eff4f7" stroke="#b2c8d7" stroke-width="2"/>
    ${metadataCell(86, y(267), 294, "DATA", definition.issuedAt)}
    ${metadataCell(419, y(267), 330, "Nº DO DOCUMENTO", definition.documentNumber)}
    ${metadataCell(788, y(267), 324, "PRONTUÁRIO", definition.recordNumber)}
    <line x1="392" y1="${y(266)}" x2="392" y2="${y(329)}" stroke="#bfd3e5"/>
    <line x1="762" y1="${y(266)}" x2="762" y2="${y(329)}" stroke="#bfd3e5"/>
    ${svgText(74, y(400), definition.documentTitle.toUpperCase(), firstPage ? 34 : 28, 790, INSTITUTIONAL_DOCUMENT.ink)}
    <line x1="74" y1="${y(419)}" x2="1126" y2="${y(419)}" stroke="#1877c9" stroke-width="2"/>
    ${svgText(74, y(449), firstPage ? definition.subtitle.toUpperCase() : `CONTINUAÇÃO · ${definition.subtitle.toUpperCase()}`, 14, 650, INSTITUTIONAL_DOCUMENT.muted, "start", 2.1)}
    ${firstPage ? `<rect x="64" y="${y(478)}" width="1072" height="160" rx="14" fill="#eef3f6" stroke="#b9cbd8"/>
      <rect x="64" y="${y(478)}" width="1072" height="45" rx="14" fill="#dceaf2"/>
      ${svgText(88, y(508), "DADOS DO PACIENTE", 17, 760, INSTITUTIONAL_DOCUMENT.ink, "start", 1.1)}
      ${patientCell(88, y(550), 490, "NOME COMPLETO", patient.name)}
      ${patientCell(608, y(550), 205, "DATA DE NASCIMENTO", patient.birthDate || "Não informado")}
      ${patientCell(841, y(550), 260, "SEXO", patient.sex || "Não informado")}
      ${patientCell(88, y(607), 250, "PASSAPORTE / PRONTUÁRIO", `${patient.passport} · ${definition.recordNumber}`)}
      ${patientCell(371, y(607), 395, "ATENDIMENTO / SETOR", definition.attendanceLabel || definition.subtitle)}
      ${patientCell(798, y(607), 303, "DATA DO ATENDIMENTO", definition.attendanceDate || definition.issuedAt)}` : ""}
    <line x1="64" y1="${y(1545)}" x2="1136" y2="${y(1545)}" stroke="#1877c9" stroke-width="1.5"/>
    ${svgText(76, y(1583), "seu-hospital.example", 16, 760, INSTITUTIONAL_DOCUMENT.ink)}
    ${svgText(600, y(1583), "Cuidar de pessoas transforma realidades.", 15, 650, INSTITUTIONAL_DOCUMENT.ink, "middle", 1.1)}
    ${svgText(1124, y(1583), `Página ${pageIndex + 1} de ${pageCount}`, 15, 600, INSTITUTIONAL_DOCUMENT.muted, "end")}
    ${svgText(600, y(1624), "Documento gerado exclusivamente para uso em RP.", 15, 650, INSTITUTIONAL_DOCUMENT.ink, "middle")}
  </g>`;
}

function metadataCell(x: number, y: number, width: number, label: string, value: string) {
  return `${svgText(x, y, label, 14, 650, INSTITUTIONAL_DOCUMENT.muted, "start", 1.1)}${svgText(x, y + 39, clipText(value, Math.floor(width / 10)), 20, 510, INSTITUTIONAL_DOCUMENT.ink)}`;
}
function patientCell(x: number, y: number, width: number, label: string, value: string) {
  return `${svgText(x, y, label, 12, 620, INSTITUTIONAL_DOCUMENT.muted, "start", .8)}${svgText(x, y + 24, clipText(value, Math.max(12, Math.floor(width / 9))), 16, 500, INSTITUTIONAL_DOCUMENT.ink)}`;
}

function institutionalSignatureBlock(professional: InstitutionalDocumentDefinition["professional"], identity: InstitutionalIdentityAssets): InstitutionalDocumentBlock {
  const signature = signatureInk(identity.signatureBytes);
  const rubric = signatureInk(identity.rubricBytes);
  const signatureSize = fitSignatureInk(signature, 560, 100);
  const rubricSize = fitSignatureInk(rubric, 290, 80);
  return {
    height: SIGNATURE_HEIGHT,
    lastPageBottom: true,
    render: (x, y, width) => `<g>
      ${institutionalSectionTitle(x, y, width, "ASSINATURA E IDENTIFICAÇÃO")}
      ${svgText(x + 24, y + 150, professional.name, 19, 650, INSTITUTIONAL_DOCUMENT.ink)}
      ${svgText(x + 24, y + 175, professional.role || "Cargo não informado", 16, 450, INSTITUTIONAL_DOCUMENT.muted)}
      ${svgText(x + 24, y + 199, `CRM interno ${professional.crmCode}`, 16, 580, INSTITUTIONAL_DOCUMENT.ink)}
      ${svgText(x + width - 180, y + 183, "RUBRICA DO RESPONSÁVEL", 12, 580, INSTITUTIONAL_DOCUMENT.muted, "middle", .8)}
      ${signature.width > 16 && signature.height > 16 ? svgImage(signature.bytes, x + 20, y + 40 + (100 - signatureSize.height) / 2, signatureSize.width, signatureSize.height, "image/png", "meet") : ""}
      ${rubric.width > 16 && rubric.height > 16 ? svgImage(rubric.bytes, x + width - 332, y + 45 + (90 - rubricSize.height) / 2, rubricSize.width, rubricSize.height, "image/png", "meet") : ""}
    </g>`,
  };
}

export function institutionalSectionTitle(x: number, y: number, width: number, title: string) {
  return `${svgText(x, y + 22, title.toUpperCase(), 19, 660, INSTITUTIONAL_DOCUMENT.ink, "start", .7)}<line x1="${x}" y1="${y + 35}" x2="${x + width}" y2="${y + 35}" stroke="#1769a9" stroke-width="1.3"/>`;
}

export function institutionalTextBlocks(title: string, value: string, options: { fontSize?: number; lineHeight?: number; maxCharacters?: number } = {}): InstitutionalDocumentBlock[] {
  const fontSize = options.fontSize ?? 19;
  const lineHeight = options.lineHeight ?? 26;
  const lines = wrapInstitutionalText(value, options.maxCharacters ?? 94);
  const chunks: string[][] = [];
  for (let index = 0; index < lines.length; index += 16) chunks.push(lines.slice(index, index + 16));
  return (chunks.length ? chunks : [["Não informado"]]).map((chunk, index) => ({
    height: 55 + chunk.length * lineHeight,
    render: (x, y, width) => `<g>${institutionalSectionTitle(x, y, width, index ? `${title} (continuação)` : title)}${svgMultiline(x + 4, y + 56, chunk, fontSize, lineHeight, 430, INSTITUTIONAL_DOCUMENT.ink)}</g>`,
  }));
}

export function institutionalCardBlocks(title: string, lines: string[], options: { tone?: "blue" | "warning" } = {}): InstitutionalDocumentBlock[] {
  const wrapped = lines.flatMap((line) => wrapInstitutionalText(line || "Não informado", 91));
  const chunks: string[][] = [];
  for (let index = 0; index < wrapped.length; index += 18) chunks.push(wrapped.slice(index, index + 18));
  const fill = options.tone === "warning" ? "#f3eddb" : "#edf3f6";
  const stroke = options.tone === "warning" ? "#d1b968" : "#b5c9d5";
  return (chunks.length ? chunks : [["Não informado"]]).map((chunk, index) => ({
    height: 65 + chunk.length * 26,
    render: (x, y, width) => `<g>${institutionalSectionTitle(x, y, width, index ? `${title} (continuação)` : title)}<rect x="${x}" y="${y + 43}" width="${width}" height="${19 + chunk.length * 26}" rx="12" fill="${fill}" stroke="${stroke}"/>${svgMultiline(x + 22, y + 72, chunk, 17, 26, 440, INSTITUTIONAL_DOCUMENT.ink)}</g>`,
  }));
}

export function institutionalFactsBlock(title: string, facts: Array<{ label: string; value: string }>): InstitutionalDocumentBlock {
  const columns = Math.max(1, Math.min(3, facts.length));
  const rows = Math.ceil(facts.length / columns);
  return {
    height: 49 + rows * 74,
    render: (x, y, width) => {
      const columnWidth = width / columns;
      const content = facts.map((fact, index) => {
        const cellX = x + (index % columns) * columnWidth;
        const cellY = y + 51 + Math.floor(index / columns) * 74;
        return `${svgText(cellX + 18, cellY + 20, fact.label.toUpperCase(), 13, 620, INSTITUTIONAL_DOCUMENT.muted, "start", .7)}${svgText(cellX + 18, cellY + 48, clipText(fact.value || "Não informado", Math.max(12, Math.floor((columnWidth - 34) / 9))), 18, 520, INSTITUTIONAL_DOCUMENT.ink)}`;
      }).join("");
      return `<g>${institutionalSectionTitle(x, y, width, title)}<rect x="${x}" y="${y + 43}" width="${width}" height="${rows * 74}" rx="12" fill="#edf3f6" stroke="#b5c9d5"/>${content}</g>`;
    },
  };
}

export function institutionalRawBlock(height: number, render: InstitutionalDocumentBlock["render"]): InstitutionalDocumentBlock { return { height, render }; }
export function wrapInstitutionalText(value: string, maxCharacters: number) {
  const lines: string[] = [];
  for (const paragraph of value.replace(/\r/g, "").split("\n")) {
    const words = paragraph.trim().split(/\s+/).filter(Boolean);
    if (!words.length) { lines.push(""); continue; }
    let line = "";
    for (const word of words) {
      const candidate = line ? `${line} ${word}` : word;
      if (candidate.length <= maxCharacters) line = candidate;
      else { if (line) lines.push(line); if (word.length <= maxCharacters) line = word; else { lines.push(`${word.slice(0, maxCharacters - 1)}…`); line = ""; } }
    }
    if (line) lines.push(line);
  }
  return lines;
}
export function svgText(x: number, y: number, value: string, size: number, weight: number, fill: string, anchor: "start" | "middle" | "end" = "start", spacing = 0) {
  return `<text x="${x}" y="${y}" font-size="${size}" font-weight="${weight}" fill="${fill}" text-anchor="${anchor}"${spacing ? ` letter-spacing="${spacing}"` : ""}>${xml(value)}</text>`;
}
export function svgMultiline(x: number, y: number, lines: string[], size: number, lineHeight: number, weight: number, fill: string) {
  return `<text x="${x}" y="${y}" font-size="${size}" font-weight="${weight}" fill="${fill}">${lines.map((line, index) => `<tspan x="${x}" dy="${index ? lineHeight : 0}">${xml(line)}</tspan>`).join("")}</text>`;
}
export function svgImage(bytes: Uint8Array, x: number, y: number, width: number, height: number, mimeType = "image/png", fit: "meet" | "slice" = "slice") {
  return `<image x="${x}" y="${y}" width="${width}" height="${height}" preserveAspectRatio="xMidYMid ${fit}" href="data:${xml(mimeType)};base64,${base64(bytes)}"/>`;
}
export function institutionalLogoSvg(centerX = 104, centerY = 82, outerRadius = 40) {
  const colors = { light: "#b7e9ff", blue: "#369fe9", navy: "#1163a8" };
  const facets = HPSM_COMPASS_FACETS.map(({ d, tone }) => `<path d="${d}" fill="${colors[tone]}"/>`).join("");
  return `<g transform="translate(${centerX - outerRadius} ${centerY - outerRadius}) scale(${outerRadius / 60})" stroke="#c7ecff" stroke-opacity=".18" stroke-width=".5" stroke-linejoin="round">${facets}</g>`;
}

export async function renderInstitutionalSvg(svg: string, expectedHeight: number, documentLabel: string): Promise<InstitutionalPngResult> {
  const resvg = await Resvg.async(svg, { background: INSTITUTIONAL_DOCUMENT.white, fitTo: { mode: "original" }, font: { defaultFontFamily: "Source Sans 3", fontBuffers: [decodeInlineAsset(sourceSansLatin), decodeInlineAsset(sourceSansLatinExt)] }, imageRendering: 0, shapeRendering: 2, textRendering: 1 });
  const rendered = resvg.render();
  const bytes = rendered.asPng().slice();
  const result = { bytes, height: rendered.height, width: rendered.width };
  rendered.free(); resvg.free();
  assertInstitutionalPng(result, expectedHeight, documentLabel);
  return result;
}
export function assertInstitutionalPng(result: InstitutionalPngResult, expectedHeight = result.height, documentLabel = "documento") {
  const { bytes, height, width } = result;
  if (!isInstitutionalPng(bytes)) throw new Error(`O ${documentLabel} gerado não é um PNG válido.`);
  if (bytes.byteLength < 32 || bytes.byteLength > INSTITUTIONAL_DOCUMENT.maxBytes) throw new Error(`A imagem do ${documentLabel} excede o limite seguro de 12 MB.`);
  const dimensions = institutionalPngDimensions(bytes);
  if (dimensions.width !== width || dimensions.height !== height || width !== INSTITUTIONAL_DOCUMENT.width || height !== expectedHeight) throw new Error(`As dimensões do ${documentLabel} gerado são inválidas.`);
  if (height < PAGE_HEIGHT || height > INSTITUTIONAL_DOCUMENT.maxHeight || height % PAGE_HEIGHT !== 0) throw new Error(`A paginação do ${documentLabel} é inválida.`);
}
export function isInstitutionalPng(bytes: Uint8Array) { return bytes.length >= 24 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47 && bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a; }
export function institutionalPngDimensions(bytes: Uint8Array) { if (!isInstitutionalPng(bytes) || ascii(bytes.slice(12, 16)) !== "IHDR") throw new Error("Cabeçalho PNG inválido."); const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength); return { width: view.getUint32(16), height: view.getUint32(20) }; }
function decodeInlineAsset(dataUrl: string) { const comma = dataUrl.indexOf(","); if (comma < 0 || !dataUrl.slice(0, comma).includes(";base64")) throw new Error("Fonte do documento indisponível."); const binary = atob(dataUrl.slice(comma + 1)); const bytes = new Uint8Array(binary.length); for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index); return bytes; }
function base64(bytes: Uint8Array) { let binary = ""; for (let index = 0; index < bytes.length; index += 0x8000) binary += String.fromCharCode(...bytes.subarray(index, Math.min(index + 0x8000, bytes.length))); return btoa(binary); }
function clipText(value: string, max: number) { return value.length <= max ? value : `${value.slice(0, Math.max(1, max - 1)).trimEnd()}…`; }
function xml(value: string) { return value.replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&apos;" })[character] ?? character); }
function ascii(bytes: Uint8Array) { return String.fromCharCode(...bytes); }
