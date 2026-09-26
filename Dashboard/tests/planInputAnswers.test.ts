import assert from "node:assert/strict";
import test from "node:test";

import { collectPlanInputAnswers, hasPlanInputAnswer } from "../src/components/PlanInputPanel/planInputAnswers.ts";

test("plan input collects every answer in one ordered payload", () => {
  const questions = [{ id: "scope" }, { id: "timeline" }, { id: "risk" }];
  const selected = { scope: "pilot", timeline: "soon", risk: "low" };
  const custom = { timeline: "After the release" };

  assert.deepEqual(collectPlanInputAnswers(questions, selected, custom), [
    { questionId: "scope", selectedOptionId: "pilot" },
    { questionId: "timeline", customAnswer: "After the release" },
    { questionId: "risk", selectedOptionId: "low" }
  ]);
  assert.equal(hasPlanInputAnswer("scope", selected, custom), true);
  assert.equal(hasPlanInputAnswer("missing", selected, custom), false);
});
