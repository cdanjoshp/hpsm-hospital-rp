export function eligibleWarningSuggestions<T extends {
  id: number;
  employee_id: string;
  closure_status: string;
  remaining_deficit_minutes: number;
  warning_suggestion_dismissed_at?: string | null;
}>(
  records: T[],
  warnings: Array<{ weekly_record_id: number | null }>,
  ineligibleEmployeeIds: ReadonlySet<string>,
  locallyDismissed: ReadonlySet<number> = new Set(),
): T[] {
  const warnedRecords = new Set(warnings.map((warning) => warning.weekly_record_id));
  return records.filter((record) =>
    record.closure_status === "closed"
    && record.remaining_deficit_minutes > 0
    && !record.warning_suggestion_dismissed_at
    && !locallyDismissed.has(record.id)
    && !warnedRecords.has(record.id)
    && !ineligibleEmployeeIds.has(record.employee_id)
  );
}
