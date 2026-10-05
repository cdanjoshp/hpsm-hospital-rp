import { authenticatedHeaders } from "./operational-data";
import { getSupabaseConfig } from "./supabase-server";

export type RecruitmentStatus =
  | "submitted"
  | "under_review"
  | "interview"
  | "approved"
  | "rejected"
  | "withdrawn";

export type RecruitmentApplication = {
  availability: string[];
  birth_day: number;
  birth_month: number;
  city_phone: string;
  created_at: string;
  discord_id: string;
  experience_summary: string | null;
  external_calls: string;
  full_name: string;
  id: string;
  interest_area: string;
  initial_position_id: number | null;
  initial_position_name: string | null;
  motivation: string;
  passport: string;
  prior_experience: boolean;
  professional_created_at: string | null;
  professional_passport: string | null;
  professional_user_id: string | null;
  provisioning_error_code: string | null;
  provisioning_state: "completed" | "failed" | "in_progress" | "not_started";
  review_notes: string | null;
  reviewed_at: string | null;
  reviewed_by: string | null;
  status: RecruitmentStatus;
  updated_at: string;
};

export type RecruitmentDecision = {
  application_id: string;
  decided_at: string;
  decided_by: string;
  decision: "approved" | "rejected";
  director_name: string;
  director_passport: string;
  director_position: string;
  id: number;
  reason: string | null;
};

type ProfileReference = {
  display_name: string;
  passport: string;
  position_id: number | null;
  user_id: string;
};

type PositionReference = {
  id: number;
  name: string;
};

type DecisionRow = Omit<RecruitmentDecision, "director_name" | "director_passport" | "director_position">;

export async function getRecruitmentManagementData(accessToken: string) {
  const { url } = getSupabaseConfig();
  const headers = authenticatedHeaders(accessToken);
  const [applicationsResponse, decisionsResponse, profilesResponse, positionsResponse] = await Promise.all([
    fetch(
      `${url}/rest/v1/recruitment_applications?select=id,full_name,passport,birth_day,birth_month,city_phone,discord_id,availability,prior_experience,experience_summary,interest_area,motivation,external_calls,status,review_notes,reviewed_by,reviewed_at,professional_user_id,professional_passport,initial_position_id,professional_created_at,provisioning_state,provisioning_error_code,created_at,updated_at&order=created_at.desc&limit=500`,
      { headers, cache: "no-store" },
    ),
    fetch(
      `${url}/rest/v1/recruitment_decisions?select=id,application_id,decision,reason,decided_by,decided_at&order=decided_at.desc&limit=1000`,
      { headers, cache: "no-store" },
    ),
    fetch(
      `${url}/rest/v1/profiles?select=user_id,passport,display_name,position_id&order=display_name.asc&limit=500`,
      { headers, cache: "no-store" },
    ),
    fetch(
      `${url}/rest/v1/staff_positions?select=id,name&order=sort_order.asc&limit=50`,
      { headers, cache: "no-store" },
    ),
  ]);

  if (!applicationsResponse.ok) {
    throw new Error("Não foi possível consultar as candidaturas.");
  }

  const applicationRows = (await applicationsResponse.json()) as Omit<RecruitmentApplication, "initial_position_name">[];
  const decisionRows = decisionsResponse.ok ? (await decisionsResponse.json()) as DecisionRow[] : [];
  const profiles = profilesResponse.ok ? (await profilesResponse.json()) as ProfileReference[] : [];
  const positions = positionsResponse.ok ? (await positionsResponse.json()) as PositionReference[] : [];
  const profilesByUser = new Map(profiles.map((profile) => [profile.user_id, profile]));
  const positionsById = new Map(positions.map((position) => [position.id, position.name]));
  const applications: RecruitmentApplication[] = applicationRows.map((application) => ({
    ...application,
    initial_position_name: application.initial_position_id
      ? positionsById.get(application.initial_position_id) ?? "Cargo inicial não localizado"
      : null,
  }));

  const decisions: RecruitmentDecision[] = decisionRows.map((decision) => {
    const director = profilesByUser.get(decision.decided_by);
    return {
      ...decision,
      director_name: director?.display_name ?? "Membro da Diretoria",
      director_passport: director?.passport ?? "—",
      director_position: director?.position_id
        ? positionsById.get(director.position_id) ?? "Cargo não definido"
        : "Cargo não definido",
    };
  });

  return { applications, decisions };
}

export function recruitmentStatusLabel(status: RecruitmentStatus) {
  const labels: Record<RecruitmentStatus, string> = {
    approved: "Aprovada",
    interview: "Entrevista",
    rejected: "Recusada",
    submitted: "Aguardando análise",
    under_review: "Em análise",
    withdrawn: "Retirada",
  };
  return labels[status];
}

export function interestAreaLabel(value: string) {
  const labels: Record<string, string> = {
    clinical_care: "Atendimento clínico",
    emergency_rescue: "Emergência e resgate",
    health_management: "Gestão hospitalar",
    nursing: "Enfermagem",
    undecided: "Ainda não definiu",
  };
  return labels[value] ?? value;
}

export function externalCallsLabel(value: string) {
  const labels: Record<string, string> = {
    full: "Disponibilidade total",
    partial: "Disponibilidade com restrições",
    unavailable: "Sem disponibilidade no momento",
  };
  return labels[value] ?? value;
}

export function availabilityLabel(value: string) {
  const labels: Record<string, string> = {
    afternoon: "Tarde · 12h às 18h",
    evening: "Noite · 18h às 00h",
    morning: "Manhã · 06h às 12h",
    overnight: "Madrugada · 00h às 06h",
  };
  return labels[value] ?? value;
}
