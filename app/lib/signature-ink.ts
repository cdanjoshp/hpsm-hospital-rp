import * as UPNGModule from "@pdf-lib/upng";

const packageModule = UPNGModule as typeof UPNGModule & { default?: typeof UPNGModule & { default?: typeof UPNGModule } };
const UPNG = packageModule.default?.default ?? packageModule.default ?? packageModule;

export type SignatureInk = { bytes: Uint8Array; width: number; height: number };

// As imagens originais são quadradas; o traço costuma ocupar só uma faixa no meio.
// Aparar apenas pixels transparentes evita que um encaixe horizontal corte hastes e remates.
export function signatureInk(bytes: Uint8Array): SignatureInk {
  const input = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
  const image = UPNG.decode(input);
  const { width, height } = image;
  if (!width || !height || width > 2048 || height > 2048) throw new Error("Dimensões da assinatura inválidas.");
  const rgba = new Uint8Array(UPNG.toRGBA8(image)[0]);
  if (rgba.length !== width * height * 4) throw new Error("Assinatura PNG inválida.");

  let left = width;
  let right = -1;
  let top = height;
  let bottom = -1;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (rgba[(y * width + x) * 4 + 3] <= 8) continue;
      left = Math.min(left, x);
      right = Math.max(right, x);
      top = Math.min(top, y);
      bottom = Math.max(bottom, y);
    }
  }
  if (right < left) return { bytes, width, height };
  const margin = Math.max(8, Math.ceil(Math.max(width, height) * 0.02));
  left = Math.max(0, left - margin);
  top = Math.max(0, top - margin);
  right = Math.min(width - 1, right + margin);
  bottom = Math.min(height - 1, bottom + margin);
  const trimmedWidth = right - left + 1;
  const trimmedHeight = bottom - top + 1;
  if (trimmedWidth === width && trimmedHeight === height) return { bytes, width, height };

  const cropped = new Uint8Array(trimmedWidth * trimmedHeight * 4);
  for (let y = 0; y < trimmedHeight; y += 1) {
    const start = ((top + y) * width + left) * 4;
    cropped.set(rgba.subarray(start, start + trimmedWidth * 4), y * trimmedWidth * 4);
  }
  return { bytes: new Uint8Array(UPNG.encode([cropped.buffer], trimmedWidth, trimmedHeight, 0)), width: trimmedWidth, height: trimmedHeight };
}

export function fitSignatureInk(ink: SignatureInk, maxWidth: number, maxHeight: number) {
  const scale = Math.min(maxWidth / ink.width, maxHeight / ink.height);
  return { width: ink.width * scale, height: ink.height * scale };
}
