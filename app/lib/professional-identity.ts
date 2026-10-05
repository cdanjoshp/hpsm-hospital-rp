import { adminHeaders } from "./admin-data";
import type { ClinicalExamDetail, ExamProfessional, ProfessionalIdentityDocument } from "./exams";
import { adminRest } from "./hr-server";
import { getSupabaseAdminConfig, getSupabaseConfig } from "./supabase-server";

export const PROFESSIONAL_IDENTITY_BUCKET = "professional-identities";

export type ProfessionalIdentityRow = {
  crm_code: string;
  generation_version: number;
  identity_locked: boolean;
  last_failure_code: string | null;
  registration_date: string;
  rubric_file_size: number | null;
  rubric_image_path: string | null;
  signature_file_size: number | null;
  signature_generated_at: string | null;
  signature_generated_by: string | null;
  signature_image_path: string | null;
  signature_regenerated_at: string | null;
  signature_regenerated_by: string | null;
  signature_regeneration_reason: string | null;
  status: "pending" | "generating" | "active" | "failed";
  updated_at: string;
  user_id: string;
};

export type ProfessionalIdentityAsset = {
  bytes: Uint8Array;
  mimeType: "image/png";
  personId: string;
};

export type ProfessionalDocumentIdentityAssets = {
  personId: string;
  rubricBytes: Uint8Array;
  signatureBytes: Uint8Array;
};

type ProfilePositionRow = {
  position_id: number | null;
  user_id: string;
};
type PositionRow = { id: number; name: string };

export async function enrichClinicalExamIdentities(exam: ClinicalExamDetail): Promise<ClinicalExamDetail> {
  const professionals = [exam.requested_by, exam.responsible_professional, exam.reviewed_by, exam.final_report_snapshot?.requested_by, exam.final_report_snapshot?.executed_by, exam.final_report_snapshot?.reviewed_by]
    .filter((person): person is ExamProfessional => Boolean(person));
  const ids = [...new Set(professionals.map((person) => person.id).filter(Boolean))];
  if (!ids.length) return exam;
  const filter = ids.join(",");
  const [identities, profiles, positions] = await Promise.all([
    adminRest<ProfessionalIdentityRow[]>(`professional_identities?select=user_id,crm_code,registration_date,signature_image_path,rubric_image_path,status,generation_version,identity_locked,last_failure_code,signature_file_size,rubric_file_size,signature_generated_at,signature_generated_by,signature_regenerated_at,signature_regenerated_by,signature_regeneration_reason,updated_at&user_id=in.(${filter})`),
    adminRest<ProfilePositionRow[]>(`profiles?select=user_id,position_id&user_id=in.(${filter})`),
    adminRest<PositionRow[]>("staff_positions?select=id,name&active=is.true&limit=50"),
  ]);
  const identityByUser = new Map(identities.map((identity) => [identity.user_id, identity]));
  const profileByUser = new Map(profiles.map((profile) => [profile.user_id, profile]));
  const positionById = new Map(positions.map((position) => [position.id, position.name]));
  const signedUrlCache = new Map<string, Promise<string>>();
  const signedUrl = (path: string) => {
    let value = signedUrlCache.get(path);
    if (!value) {
      value = createProfessionalIdentitySignedUrl(path);
      signedUrlCache.set(path, value);
    }
    return value;
  };

  async function enrich(person: ExamProfessional | null): Promise<ExamProfessional | null> {
    if (!person) return null;
    const profile = profileByUser.get(person.id);
    const currentPosition = profile?.position_id ? positionById.get(profile.position_id) ?? null : null;
    const current = identityByUser.get(person.id);
    const frozen = validDocumentIdentity(person.identity) ? person.identity : null;
    const identity = frozen ?? rowDocumentIdentity(current);
    if (!identity) return { ...person, identity: null, position: currentPosition ?? person.position };
    const [signatureUrl, rubricUrl] = await Promise.all([
      signedUrl(identity.signature_image_path),
      signedUrl(identity.rubric_image_path),
    ]);
    return {
      ...person,
      identity: { ...identity, rubric_image_url: rubricUrl, signature_image_url: signatureUrl },
      position: currentPosition ?? person.position,
    };
  }

  const [requestedBy, responsible, reviewedBy, snapshotRequested, snapshotExecuted, snapshotReviewed] = await Promise.all([
    enrich(exam.requested_by),
    enrich(exam.responsible_professional),
    enrich(exam.reviewed_by),
    enrich(exam.final_report_snapshot?.requested_by ?? null),
    enrich(exam.final_report_snapshot?.executed_by ?? null),
    enrich(exam.final_report_snapshot?.reviewed_by ?? null),
  ]);
  const snapshot = exam.final_report_snapshot ? {
    ...exam.final_report_snapshot,
    executed_by: snapshotExecuted ?? exam.final_report_snapshot.executed_by,
    requested_by: snapshotRequested ?? exam.final_report_snapshot.requested_by,
    reviewed_by: snapshotReviewed,
  } : null;
  return {
    ...exam,
    final_report_snapshot: snapshot,
    requested_by: requestedBy ?? exam.requested_by,
    responsible_professional: responsible ?? exam.responsible_professional,
    reviewed_by: reviewedBy,
  };
}

export async function loadProfessionalSignatureAssets(professionals: Array<ExamProfessional | null>): Promise<ProfessionalIdentityAsset[]> {
  const unique = new Map<string, { path: string; personId: string }>();
  for (const person of professionals) {
    const path = person?.identity?.signature_image_path;
    if (!person) continue;
    if (!path || !person.identity?.crm_code) {
      throw new Error(`A identidade profissional de ${person.name} ainda está sendo preparada.`);
    }
    if (!unique.has(person.id)) unique.set(person.id, { path, personId: person.id });
  }
  return Promise.all([...unique.values()].map(async ({ path, personId }) => {
    const response = await downloadProfessionalIdentity(path);
    if (!response.ok) throw new Error("A assinatura profissional não pôde ser carregada para o documento.");
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (!validPng(bytes) || bytes.byteLength > 5 * 1024 * 1024) throw new Error("A assinatura profissional armazenada é inválida.");
    return { bytes, mimeType: "image/png" as const, personId };
  }));
}

export async function loadProfessionalDocumentIdentity(professional: ExamProfessional): Promise<ProfessionalDocumentIdentityAssets> {
  const identity = professional.identity;
  if (!identity?.crm_code || !identity.signature_image_path || !identity.rubric_image_path) {
    throw new Error(`A identidade profissional de ${professional.name} ainda está sendo preparada.`);
  }
  const [signature, rubric] = await Promise.all([
    downloadProfessionalIdentity(identity.signature_image_path),
    downloadProfessionalIdentity(identity.rubric_image_path),
  ]);
  if (!signature.ok || !rubric.ok) throw new Error("A assinatura ou rubrica profissional não pôde ser carregada para o documento.");
  const [signatureBytes, rubricBytes] = await Promise.all([
    signature.arrayBuffer().then((value) => new Uint8Array(value)),
    rubric.arrayBuffer().then((value) => new Uint8Array(value)),
  ]);
  if (!validPng(signatureBytes) || !validPng(rubricBytes) || signatureBytes.byteLength > 5 * 1024 * 1024 || rubricBytes.byteLength > 5 * 1024 * 1024) {
    throw new Error("A assinatura ou rubrica profissional armazenada é inválida.");
  }
  return { personId: professional.id, rubricBytes, signatureBytes };
}

export async function createProfessionalIdentitySignedUrl(path: string, expiresIn = 300) {
  if (!isProfessionalIdentityPath(path)) throw new Error("Caminho de identidade inválido.");
  const { serviceRoleKey, url } = getSupabaseAdminConfig();
  const response = await fetch(`${url}/storage/v1/object/sign/${PROFESSIONAL_IDENTITY_BUCKET}/${encodeStoragePath(path)}`, {
    method: "POST",
    headers: adminHeaders(serviceRoleKey),
    body: JSON.stringify({ expiresIn }),
    cache: "no-store",
    signal: AbortSignal.timeout(15_000),
  });
  const payload = await response.json().catch(() => null) as { signedURL?: string; signedUrl?: string } | null;
  if (!response.ok || !payload) throw new Error("Não foi possível abrir a identidade profissional.");
  const signed = payload.signedURL ?? payload.signedUrl ?? "";
  if (!signed) throw new Error("Não foi possível abrir a identidade profissional.");
  return signed.startsWith("http") ? signed : `${url}/storage/v1${signed.startsWith("/") ? "" : "/"}${signed}`;
}

export async function callProfessionalIdentityGeneration(accessToken: string, payload: { action: "ensure" | "regenerate" | "reprocess"; reason?: string; targetUserId?: string }) {
  const { anonKey, url } = getSupabaseConfig();
  const response = await fetch(`${url}/functions/v1/professional-identity`, {
    method: "POST",
    headers: { apikey: anonKey, authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
    body: JSON.stringify(payload),
    cache: "no-store",
    signal: AbortSignal.timeout(85_000),
  });
  const result = await response.json().catch(() => null) as { error?: string; status?: string } | null;
  if (!response.ok && response.status !== 202) throw new ProfessionalIdentityError(result?.error ?? "Não foi possível preparar a identidade profissional.", response.status);
  return result ?? { status: response.status === 202 ? "generating" : "active" };
}

function rowDocumentIdentity(identity: ProfessionalIdentityRow | undefined): ProfessionalIdentityDocument | null {
  if (!identity || identity.status !== "active" || !identity.signature_image_path || !identity.rubric_image_path) return null;
  return {
    crm_code: identity.crm_code,
    registration_date: identity.registration_date,
    rubric_image_path: identity.rubric_image_path,
    signature_image_path: identity.signature_image_path,
  };
}

function validDocumentIdentity(value: ProfessionalIdentityDocument | null | undefined): value is ProfessionalIdentityDocument {
  return Boolean(value
    && /^\d{8}$/.test(value.crm_code)
    && /^\d{4}-\d{2}-\d{2}$/.test(value.registration_date)
    && isProfessionalIdentityPath(value.signature_image_path)
    && isProfessionalIdentityPath(value.rubric_image_path));
}

function isProfessionalIdentityPath(path: string) {
  return /^professionals\/[0-9a-f-]{36}\/[0-9a-f-]{36}\/(?:signature|rubric)\.png$/i.test(path);
}

function downloadProfessionalIdentity(path: string) {
  if (!isProfessionalIdentityPath(path)) throw new Error("Caminho de identidade inválido.");
  const { serviceRoleKey, url } = getSupabaseAdminConfig();
  return fetch(`${url}/storage/v1/object/${PROFESSIONAL_IDENTITY_BUCKET}/${encodeStoragePath(path)}`, {
    cache: "no-store",
    headers: adminHeaders(serviceRoleKey),
    signal: AbortSignal.timeout(20_000),
  });
}

function encodeStoragePath(path: string) { return path.split("/").map(encodeURIComponent).join("/"); }
function validPng(bytes: Uint8Array) { return bytes.byteLength >= 32 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47; }

export class ProfessionalIdentityError extends Error {
  constructor(message: string, public status = 400) { super(message); }
}
