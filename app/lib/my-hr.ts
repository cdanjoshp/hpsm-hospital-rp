import type {
  CareerSelfData,
  Course,
  PositionHistory,
  ProgressionStatus,
  StaffCourseRecord,
} from "./career";
import {
  buildWeeklyProgress,
  type HrAbsenceRequest,
  type HrHourJustification,
  type HrHourSnapshot,
  type HrLeaveWeekAdjustment,
  type HrSelfData,
  type HrWarning,
  type HrWeeklyRecord,
} from "./hr";
import type { StaffPosition } from "./access";
import { callSupabaseUserRpc } from "./supabase-user";

type MyHrSnapshot = {
  absences: HrAbsenceRequest[];
  courseRecords: StaffCourseRecord[];
  courses: Course[];
  history: PositionHistory[];
  hourJustifications: HrHourJustification[];
  leaveAdjustments: HrLeaveWeekAdjustment[];
  positions: StaffPosition[];
  progression: ProgressionStatus;
  snapshots: HrHourSnapshot[];
  warnings: HrWarning[];
  weeklyRecords: HrWeeklyRecord[];
};

export async function getMyHrData(accessToken: string): Promise<{
  careerData: CareerSelfData;
  data: HrSelfData;
}> {
  const snapshot = await callSupabaseUserRpc<MyHrSnapshot>(accessToken, "hpsm_my_hr_snapshot");
  const currentPositionId = snapshot.history[0]?.to_position_id ?? snapshot.progression.position_id ?? null;
  return {
    careerData: {
      courseRecords: snapshot.courseRecords,
      courses: snapshot.courses,
      history: snapshot.history,
      position: snapshot.positions.find((position) => position.id === currentPositionId) ?? null,
      positions: snapshot.positions,
      progression: snapshot.progression,
    },
    data: {
      absences: snapshot.absences,
      hourJustifications: snapshot.hourJustifications,
      leaveAdjustments: snapshot.leaveAdjustments,
      progress: buildWeeklyProgress(
        snapshot.snapshots,
        snapshot.leaveAdjustments,
        snapshot.warnings,
        snapshot.weeklyRecords,
      ),
      snapshots: snapshot.snapshots,
      warnings: snapshot.warnings,
      weeklyRecords: snapshot.weeklyRecords,
    },
  };
}
