import { adminHeaders } from "./admin-data";
import type { FinalExamDocumentImage } from "./final-exam-document";
import type { FinalExamPngImage } from "./final-exam-png";
import { getSupabaseAdminConfig } from "./supabase-server";

const SOURCE_IMAGE_MAX_BYTES = 10 * 1024 * 1024;
const SOURCE_IMAGES_TOTAL_MAX_BYTES = 24 * 1024 * 1024;

export async function loadPrivateExamImages(images: Pick<FinalExamDocumentImage, "id" | "mime_type" | "storage_path">[]) {
  const assets = await Promise.all(images.map(async (image): Promise<FinalExamPngImage> => {
    const response = await downloadStorageObject("clinical-exam-images", image.storage_path);
    if (!response.ok) throw new Error("Uma das imagens finais não pôde ser carregada para o documento.");
    const bytes = new Uint8Array(await response.arrayBuffer());
    const mimeType = (response.headers.get("content-type")?.split(";")[0] || image.mime_type).toLowerCase();
    if (bytes.byteLength < 16 || bytes.byteLength > SOURCE_IMAGE_MAX_BYTES) {
      throw new Error("As imagens finais excedem o limite seguro para emissão do documento.");
    }
    if (!validRasterImage(bytes, mimeType)) throw new Error("Uma imagem final possui formato inválido.");
    return { bytes, id: image.id, mimeType };
  }));
  if (assets.reduce((total, image) => total + image.bytes.byteLength, 0) > SOURCE_IMAGES_TOTAL_MAX_BYTES) {
    throw new Error("As imagens finais excedem o limite seguro para emissão do documento.");
  }
  return assets;
}

export async function uploadStoredExamDocument(path: string, bytes: Uint8Array) {
  const { serviceRoleKey, url } = getSupabaseAdminConfig();
  const body = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
  const response = await fetch(`${url}/storage/v1/object/clinical-exam-documents/${encodeStoragePath(path)}`, {
    body,
    headers: {
      apikey: serviceRoleKey,
      authorization: `Bearer ${serviceRoleKey}`,
      "cache-control": "no-store",
      "content-type": "image/png",
      "x-upsert": "false",
    },
    method: "POST",
    signal: AbortSignal.timeout(25_000),
  });
  if (!response.ok) throw new Error("Não foi possível guardar a imagem compartilhável.");
}

export function downloadStoredExamDocument(path: string) {
  return downloadStorageObject("clinical-exam-documents", path);
}

export async function downloadStorageObject(bucket: string, path: string) {
  const { serviceRoleKey, url } = getSupabaseAdminConfig();
  return fetch(`${url}/storage/v1/object/${bucket}/${encodeStoragePath(path)}`, {
    cache: "no-store",
    headers: adminHeaders(serviceRoleKey),
    signal: AbortSignal.timeout(25_000),
  });
}

export async function deleteStoredExamDocument(path: string) {
  const { serviceRoleKey, url } = getSupabaseAdminConfig();
  const response = await fetch(`${url}/storage/v1/object/clinical-exam-documents/${encodeStoragePath(path)}`, {
    headers: adminHeaders(serviceRoleKey),
    method: "DELETE",
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok && response.status !== 404) throw new Error("Não foi possível limpar a imagem temporária do documento.");
}

export function examDocumentStoragePath(examId: number, documentId: string) {
  return `clinical-exams/${examId}/documents/${documentId}.png`;
}

function encodeStoragePath(path: string) {
  return path.split("/").map(encodeURIComponent).join("/");
}

function validRasterImage(bytes: Uint8Array, mimeType: string) {
  if (mimeType === "image/png") return bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47;
  if (mimeType === "image/jpeg") return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[bytes.length - 2] === 0xff && bytes[bytes.length - 1] === 0xd9;
  if (mimeType === "image/webp") return ascii(bytes.slice(0, 4)) === "RIFF" && ascii(bytes.slice(8, 12)) === "WEBP";
  return false;
}

function ascii(bytes: Uint8Array) {
  return String.fromCharCode(...bytes);
}
