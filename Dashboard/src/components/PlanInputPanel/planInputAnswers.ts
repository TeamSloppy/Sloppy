export interface PlanInputAnswer {
  questionId: string;
  selectedOptionId?: string;
  customAnswer?: string;
}

export function hasPlanInputAnswer(
  questionId: string,
  selectedByQuestion: Record<string, string>,
  customByQuestion: Record<string, string>
): boolean {
  return Boolean(String(selectedByQuestion[questionId] || "").trim() || String(customByQuestion[questionId] || "").trim());
}

export function collectPlanInputAnswers(
  questions: Array<{ id?: string }>,
  selectedByQuestion: Record<string, string>,
  customByQuestion: Record<string, string>
): PlanInputAnswer[] {
  return questions.map((question) => {
    const questionId = String(question.id || "");
    const customAnswer = String(customByQuestion[questionId] || "").trim();
    if (customAnswer) return { questionId, customAnswer };
    return { questionId, selectedOptionId: String(selectedByQuestion[questionId] || "").trim() };
  });
}
