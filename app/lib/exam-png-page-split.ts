import * as UPNGModule from "@pdf-lib/upng";

const packageModule = UPNGModule as typeof UPNGModule & { default?: typeof UPNGModule & { default?: typeof UPNGModule } };
const UPNG = packageModule.default?.default ?? packageModule.default ?? packageModule;

export function extractExamPagePng(bytes: Uint8Array, page: number, pageHeight = 1697, expectedWidth = 1200) {
  if (bytes.length < 24 || bytes[0] !== 0x89 || bytes[1] !== 0x50 || bytes[2] !== 0x4e || bytes[3] !== 0x47) throw new Error("Imagem de exame inválida.");
  const header = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const width = header.getUint32(16);
  const height = header.getUint32(20);
  if (width !== expectedWidth || height % pageHeight || page < 1 || !Number.isSafeInteger(page) || page > height / pageHeight) {
    throw new Error("Página do exame inválida.");
  }
  const input = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
  const decoded = UPNG.decode(input);
  const rgba = new Uint8Array(UPNG.toRGBA8(decoded)[0]);
  const rowBytes = width * 4;
  const offset = (page - 1) * pageHeight * rowBytes;
  const slice = rgba.slice(offset, offset + pageHeight * rowBytes);
  return new Uint8Array(UPNG.encode([slice.buffer], width, pageHeight, 0));
}
