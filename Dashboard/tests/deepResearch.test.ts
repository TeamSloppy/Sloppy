import assert from "node:assert/strict";
import test from "node:test";

import {
  buildDeepResearchCommand,
  buildDeepResearchProcess,
  deepResearchSkillInvocation,
  parseDeepResearchCommand
} from "../src/features/agents/deepResearch.ts";

test("deep research command builder produces an editable slash command", () => {
  const command = buildDeepResearchCommand({
    mode: "compare",
    rounds: 3,
    prompt: "Compare OpenAI and Anthropic web research features"
  });

  assert.equal(command, "/deepresearch --mode compare --rounds 3 \"Compare OpenAI and Anthropic web research features\"");
  assert.deepEqual(parseDeepResearchCommand(command), {
    config: {
      mode: "compare",
      rounds: 3,
      prompt: "Compare OpenAI and Anthropic web research features"
    }
  });
});

test("deep research process derives state from typed session events", () => {
  const invocation = deepResearchSkillInvocation({
    mode: "review",
    rounds: 4,
    prompt: "Review Swift concurrency resources"
  });
  const process = buildDeepResearchProcess(
    [
      { id: "msg-1", type: "message", message: { role: "user", text: invocation } },
      { id: "tool-1", type: "tool_call", toolCall: { tool: "web.search", arguments: { query: "Swift concurrency review 2026" } } },
      { id: "result-1", type: "tool_result", toolResult: { tool: "web.search", data: [{ title: "Guide", url: "https://example.com/guide" }] } },
      { id: "tool-2", type: "tool_call", toolCall: { tool: "web.search", arguments: { query: "Swift structured concurrency pitfalls" } } },
      {
        id: "progress-1",
        type: "build_progress",
        buildProgress: { steps: [{ label: "Collect sources", status: "done" }, { label: "Review claims", status: "active" }] }
      }
    ],
    { stage: "searching" }
  );

  assert.equal(process?.config.mode, "review");
  assert.equal(process?.config.rounds, 4);
  assert.equal(process?.currentRound, 2);
  assert.equal(process?.stage, "searching");
  assert.deepEqual(process?.queries, ["Swift concurrency review 2026", "Swift structured concurrency pitfalls"]);
  assert.deepEqual(process?.urls, ["https://example.com/guide"]);
  assert.deepEqual(process?.progress, { steps: [{ label: "Collect sources", status: "done" }, { label: "Review claims", status: "active" }] });
});
