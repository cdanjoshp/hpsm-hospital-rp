import { callSupabaseUserRpc, SupabaseUserRpcError } from "./supabase-user";

export type AcademyCourse = {
  id: number; slug: string | null; name: string; description?: string; short_description: string;
  category: string; cover_url: string | null; duration_minutes: number; status?: "draft" | "published" | "archived";
  required: boolean; sort_order?: number; started_at?: string | null; completed_at?: string | null;
  final_score?: number | null; passed?: boolean; lesson_count?: number; completed_lessons?: number;
  assessment_enabled?: boolean; students?: number; approved?: number; average_score?: number | null;
};
export type AcademyLesson = {
  id: number; course_id: number; title: string; description: string; body?: string;
  content_type: "text" | "video" | "mixed"; video_url?: string | null;
  image_url?: string | null; material_url?: string | null; duration_minutes: number;
  position: number; required: boolean; active: boolean;
};
export type AcademyAssessment = {
  id: number; enabled: boolean; question_count: number; passing_score: number; max_attempts: number;
  shuffle_questions: boolean; shuffle_options: boolean; reveal_policy: "immediate" | "after_final";
  updated_at?: string;
};
export type AcademyEnrollment = {
  id: number; course_id: number; professional_id: string; started_at: string; completed_at: string | null;
  final_score: number | null; passed: boolean; approved_attempt_id: number | null; extra_attempts: number;
};
export type AcademyAttempt = {
  id: number; attempt_number: number; status: "in_progress" | "submitted"; score: number | null;
  passed: boolean | null; started_at: string; submitted_at: string | null; passing_score_snapshot: number;
};
export type AcademyQuestion = {
  id: number; course_id: number; body: string; kind: "multiple_choice" | "true_false";
  explanation: string; weight: number; position: number; active: boolean;
  options: Array<{ id: number; label: string; correct: boolean; position: number }>;
};
export type AcademyAttemptItem = {
  id: number; position: number; body: string; kind: string;
  options: Array<{ id: number; label: string }>;
  selected_option_id: number | null; is_correct: boolean | null;
  correct_option_id: number | null; explanation: string | null;
};
export type AcademyCatalog = { courses: AcademyCourse[] };
export type AcademyCourseDetail = {
  course: AcademyCourse; lessons: AcademyLesson[]; enrollment: AcademyEnrollment | null;
  progress: Array<{ lesson_id: number; started_at: string; completed_at: string | null }>;
  assessment: AcademyAssessment | null; attempts: AcademyAttempt[];
};
export type AcademyAdminList = { courses: AcademyCourse[]; page: number; total: number };
export type AcademyAdminContent = { course: AcademyCourse; lessons: AcademyLesson[];
  assessment: AcademyAssessment | null; questions: AcademyQuestion[]; question_total: number; page: number };
export type AcademyAdminResult = AcademyEnrollment & { professional_name: string; passport: string; course_name: string;
  attempt_count: number; original_score: number | null; adjustments: number };
export type AcademyAdminResults = { results: AcademyAdminResult[]; page: number; total: number };
export type AcademyAdminResultHistory = {
  enrollment: AcademyEnrollment;
  attempts: AcademyAttempt[];
  grade_history: Array<{ id: number; original_score: number | null; previous_score: number | null; adjusted_score: number; reason: string; adjusted_at: string }>;
  extra_attempts: Array<{ id: number; reason: string; granted_at: string }>;
};

export async function readAcademy<T>(token: string, view: string, courseId?: number | null, refId?: number | null, page = 1, search = "") {
  return callSupabaseUserRpc<T>(token, "academy_read", {
    p_view: view, p_course_id: courseId ?? null, p_ref_id: refId ?? null,
    p_page: page, p_search: search,
  });
}

export function academyError(error: unknown) {
  if (error instanceof SupabaseUserRpcError) {
    return Response.json({ error: error.rpcMessage ?? "Não foi possível concluir a operação." },
      { status: error.status === 403 || error.code === "42501" ? 403 : 400 });
  }
  return Response.json({ error: "Não foi possível acessar a Academia agora." }, { status: 503 });
}
