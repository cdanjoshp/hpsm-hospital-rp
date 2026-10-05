export function pendingExamSuggestions<T extends { exam_type_id: number }>(
  suggestions: T[],
  linkedExams: Array<{ exam_type_id: number; status: string }>,
): T[] {
  // A solicitação já ocupa o lugar da sugestão; exames iniciados e concluídos também.
  const linkedTypes = new Set(linkedExams.map((exam) => exam.exam_type_id));
  const seen = new Set<number>();
  return suggestions.filter((suggestion) => {
    if (linkedTypes.has(suggestion.exam_type_id) || seen.has(suggestion.exam_type_id)) return false;
    seen.add(suggestion.exam_type_id);
    return true;
  });
}
