import { callSupabaseUserRpc } from "./supabase-user";

export type HrProductionDay = {
  attendance_count: number;
  date: string;
  employee_id: string;
  total_amount: number;
};

export type HrProductionData = {
  days: HrProductionDay[];
  month: string;
};

export async function getHrProductionData(accessToken: string, month: string): Promise<HrProductionData> {
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) throw new Error("Competência inválida.");
  return callSupabaseUserRpc<HrProductionData>(accessToken, "hpsm_hr_production", { p_month: month });
}

export function currentSaoPauloMonth() {
  const parts = new Intl.DateTimeFormat("en-US", {
    month: "2-digit",
    timeZone: "America/Sao_Paulo",
    year: "numeric",
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}`;
}
