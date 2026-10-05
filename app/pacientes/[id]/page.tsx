import { redirect } from "next/navigation";
import { AppFrame } from "../../components/app-frame";
import { PatientProfile } from "../../components/patient-profile";
import { getPatientCardPage, getPatientDirectoryEntry } from "../../lib/patient-center";
import { getSessionBootstrap } from "../../lib/session";

export const dynamic = "force-dynamic";

export default async function PatientProfilePage({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<{ editar?: string }> }) {
  const context = await getSessionBootstrap();
  if (!context) redirect("/");
  if (context.profile.must_change_password) redirect("/primeiro-acesso");

  const permissions = context.permissionCodes;
  if (!permissions.includes("patients.view")) redirect("/painel");
  const patientId = Number((await params).id);
  if (!Number.isInteger(patientId) || patientId <= 0) redirect("/pacientes");
  const patient = await getPatientDirectoryEntry(context.accessToken, patientId);
  if (!patient) redirect("/pacientes");
  const cardPage = await getPatientCardPage(context.accessToken, { search: patient.passport, pageSize: 1 });
  const benefit = cardPage.patients.find((entry) => entry.id === patientId)?.benefit ?? "none";

  return (
    <AppFrame
      active="patients"
      profile={context.profile}
      title="Perfil do Paciente"
      description="Histórico clínico-administrativo consolidado a partir dos registros reais do HPSM."
    >
      <PatientProfile
        initialPatient={patient}
        initialEditing={(await searchParams).editar === "1" && permissions.includes("patients.manage")}
        benefit={benefit}
        canCreateAttendance={permissions.includes("attendances.create")}
        canCreateConsultation={permissions.includes("consultations.view") && permissions.includes("consultations.create")}
        canCreateHospitalization={permissions.includes("hospitalizations.view") && permissions.includes("hospitalizations.create")}
        canCreateCertificate={permissions.includes("atestados.create") && permissions.includes("atestados.view")}
        canViewRecords={permissions.includes("consultations.view")}
        canAdminHealthPlan={permissions.includes("healthplans.review") && context.positionLevel !== null && context.positionLevel >= 11 && context.positionLevel <= 14}
        canCreateExams={permissions.includes("exams.create")}
        canCreateCasts={permissions.includes("casts.create")}
        canManageCasts={permissions.includes("casts.manage")}
        canManage={permissions.includes("patients.manage")}
        canRemoveCasts={permissions.includes("casts.remove")}
        canResetPortalPin={context.positionLevel !== null && context.positionLevel >= 11 && context.positionLevel <= 14}
        canViewCasts={permissions.includes("casts.view")}
        canViewCertificates={permissions.includes("atestados.view")}
        canViewExams={permissions.includes("exams.view")}
        canViewHospitalizations={permissions.includes("hospitalizations.history")}
        currentPositionName={context.positionDisplayName}
        currentUserId={context.profile.user_id}
        currentUserName={context.profile.display_name}
      />
    </AppFrame>
  );
}
