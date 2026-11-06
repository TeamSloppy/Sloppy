import assert from "node:assert/strict";
import test from "node:test";

import { findPendingToolCallRecordIds } from "../src/features/agents/sessionActivity.ts";

const call = (id: string) => ({ id, type: "tool_call", toolCall: { tool: "files.read" } });
const result = { id: "result", type: "tool_result", toolResult: { tool: "files.read", ok: true } };
const pending = (events: unknown) => [...findPendingToolCallRecordIds(events)];
const origins = [
  { importOrigin: { source: "codex", sourceID: "import", externalID: "old", jobID: "job", archived: true } },
  { forkOrigin: { sourceAgentId: "agent", sourceSessionId: "source", sourceEventId: "old" } },
];

test("live tool calls settle in FIFO order and terminal delivery clears remaining calls", () => {
  assert.deepEqual(pending([call("a"), call("b"), result]), ["b-tool-call"]);
  for (const stage of ["done", "interrupted"]) {
    assert.deepEqual(pending([call("a"), { type: "run_status", runStatus: { stage } }]), []);
  }
  assert.deepEqual(pending([call("a"), { type: "run_status", runStatus: { stage: "paused" } }]), ["a-tool-call"]);
  assert.deepEqual(pending(null), []);
});

test("a correlated out-of-order result settles its own invocation", () => {
  assert.deepEqual(pending([call("a"), call("b"), { ...result, toolResult: { ...result.toolResult, callEventId: "b" } }]), ["a-tool-call"]);
});

test("an orphan correlated result does not consume a live invocation", () => {
  assert.deepEqual(pending([call("live"), { ...result, toolResult: { ...result.toolResult, callEventId: "not-this-call" } }]), ["live-tool-call"]);
});

for (const origin of origins) {
  const kind = "forkOrigin" in origin ? "fork" : "import";
  test(`${kind} history without an outcome has no active tool indicator`, () => {
    assert.deepEqual(pending([{ ...call("history"), ...origin }]), []);
  });
  test(`${kind} result cannot settle a live invocation`, () => {
    assert.deepEqual(pending([call("live"), { ...result, ...origin }]), ["live-tool-call"]);
  });
  test(`${kind} terminal status cannot clear live activity`, () => {
    assert.deepEqual(pending([call("live"), { type: "run_status", runStatus: { stage: "done" }, ...origin }]), ["live-tool-call"]);
  });
  test(`${kind} call cannot consume the result belonging to the current invocation`, () => {
    assert.deepEqual(pending([{ ...call("history"), ...origin }, call("live"), result]), []);
  });
}
