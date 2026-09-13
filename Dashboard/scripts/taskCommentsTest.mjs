import assert from "node:assert/strict";
import { test } from "node:test";
import { isTechnicalTaskComment } from "../src/views/Projects/taskComments.js";

test("service events are technical regardless of author or wording", () => {
  assert.equal(isTechnicalTaskComment({ kind: "technical", authorActorId: "worker", content: "Done" }), true);
});

test("explicit results and requests from the system remain in the discussion", () => {
  for (const kind of ["result", "action_required", "user_comment"]) {
    assert.equal(isTechnicalTaskComment({ kind, authorActorId: "system" }), false);
  }
});

test("legacy comments follow the backend compatibility policy", () => {
  for (const kind of [undefined, null]) {
    assert.equal(isTechnicalTaskComment({ kind, authorActorId: "system" }), true);
    assert.equal(isTechnicalTaskComment({ kind, authorActorId: "user" }), false);
    assert.equal(isTechnicalTaskComment({ kind, authorActorId: "agent", isAgentReply: true }), false);
  }
});
