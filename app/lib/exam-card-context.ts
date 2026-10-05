import type { ClinicalExamListItem } from "./exams";
import { FINAL_EXAM_PNG_RENDER_VERSION } from "./exam-document-version";
import { castBodyRegionLabel, castLateralityLabel } from "./cast-types";
import type { CastBodyRegion, CastLaterality } from "./cast-types";
import { getSupabaseAdminConfig } from "./supabase-server";

export type ExamCardContext = {
  consultationId: number | null;
  pageCount: number | null;
  cast: { id: number; status: "in_use" | "removed" | "cancelled"; location: string } | null;
  hospitalization: { id: number; status: "active" | "discharged" | "cancelled"; reason: string } | null;
  suggestedAction: "CAST" | "HOSPITALIZATION" | null;
};

type ExamLink = { id: number; consultation_id: number | null; attendance_id: number | null };
type CastRow = { id: number; consultation_id: number | null; attendance_id: number | null; body_region: string; laterality: string; status: "in_use" | "removed" | "cancelled" };
type HospitalRow = { id: number; consultation_id: number | null; reason: string; status: "active" | "discharged" | "cancelled" };
type ConsultationRow = { id: number; complementary_action: "NONE" | "CAST" | "HOSPITALIZATION" };
type DocumentRow = { exam_id: number; pixel_height: number };

export async function getExamCardContexts(items: ClinicalExamListItem[], permissions: Set<string>): Promise<Record<number, ExamCardContext>> {
  const result: Record<number, ExamCardContext> = {};
  for (const item of items) result[item.id] = { consultationId: null, pageCount: null, cast: null, hospitalization: null, suggestedAction: null };
  if (!items.length) return result;
  const ids = items.map((item) => item.id);
  const exams = await rows<ExamLink>("clinical_exams", "id,consultation_id,attendance_id", `id=in.(${ids.join(",")})`);
  const consultationIds = [...new Set(exams.map((row) => row.consultation_id).filter((id): id is number => id !== null))];
  const attendanceIds = [...new Set(exams.map((row) => row.attendance_id).filter((id): id is number => id !== null))];
  const connected = [consultationIds.length ? `consultation_id.in.(${consultationIds.join(",")})` : "", attendanceIds.length ? `attendance_id.in.(${attendanceIds.join(",")})` : ""].filter(Boolean).join(",");
  const [documents, casts, hospitalizations, consultations] = await Promise.all([
    rows<DocumentRow>("clinical_exam_documents", "exam_id,pixel_height", `exam_id=in.(${ids.join(",")})&render_version=eq.${FINAL_EXAM_PNG_RENDER_VERSION}`),
    permissions.has("casts.view") && connected ? rows<CastRow>("clinical_casts", "id,consultation_id,attendance_id,body_region,laterality,status", `or=(${connected})&order=id.desc`) : [],
    permissions.has("hospitalizations.view") && consultationIds.length ? rows<HospitalRow>("hospitalizations", "id,consultation_id,reason,status", `consultation_id=in.(${consultationIds.join(",")})&order=id.desc`) : [],
    permissions.has("consultations.view") && consultationIds.length ? rows<ConsultationRow>("clinical_consultations", "id,complementary_action", `id=in.(${consultationIds.join(",")})`) : [],
  ]);
  for (const document of documents) if (result[document.exam_id]) result[document.exam_id].pageCount = document.pixel_height / 1697;
  for (const exam of exams) {
    const context = result[exam.id];
    if (!context) continue;
    context.consultationId = exam.consultation_id;
    const cast = casts.find((row) => row.status !== "cancelled" && (exam.consultation_id !== null ? row.consultation_id === exam.consultation_id : exam.attendance_id !== null && row.attendance_id === exam.attendance_id));
    if (cast) context.cast = { id: cast.id, status: cast.status, location: `${castBodyRegionLabel(cast.body_region as CastBodyRegion)} · ${castLateralityLabel(cast.laterality as CastLaterality)}` };
    const hospital = hospitalizations.find((row) => row.status !== "cancelled" && row.consultation_id === exam.consultation_id);
    if (hospital) context.hospitalization = { id: hospital.id, status: hospital.status, reason: hospital.reason };
    const consultation = consultations.find((row) => row.id === exam.consultation_id);
    if (consultation?.complementary_action === "CAST" && !cast) context.suggestedAction = "CAST";
    if (consultation?.complementary_action === "HOSPITALIZATION" && !hospital) context.suggestedAction = "HOSPITALIZATION";
  }
  return result;
}

async function rows<T>(table: string, select: string, filter: string): Promise<T[]> {
  const { serviceRoleKey, url } = getSupabaseAdminConfig();
  const response = await fetch(`${url}/rest/v1/${table}?select=${select}&${filter}`, {
    cache: "no-store", headers: { apikey: serviceRoleKey, authorization: `Bearer ${serviceRoleKey}` }, signal: AbortSignal.timeout(12000),
  });
  if (!response.ok) throw new Error("Não foi possível carregar os vínculos dos exames.");
  return response.json() as Promise<T[]>;
}
