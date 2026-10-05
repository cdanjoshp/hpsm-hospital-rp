import type { Patient } from "./operational-data";

type AttendanceBenefitPatient = Pick<Patient, "health_plan" | "partnerships">;

export function activeAttendancePartnerships(patient: Pick<Patient, "partnerships">) {
  return (patient.partnerships ?? []).filter((partnership) => partnership.status === "active");
}

export function automaticAttendanceBenefit(patient: AttendanceBenefitPatient) {
  if (patient.health_plan.status === "active") {
    return { benefitCode: "plano_saude" as const, partnershipId: null };
  }

  const partnerships = activeAttendancePartnerships(patient);
  if (!partnerships.length) {
    return { benefitCode: null, partnershipId: null };
  }

  return {
    benefitCode: "parceiros_hp" as const,
    partnershipId: partnerships.length === 1 ? partnerships[0].id : null,
  };
}
