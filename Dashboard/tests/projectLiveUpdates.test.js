import assert from "node:assert/strict";
import test from "node:test";

import {
  projectNotificationTargetsLiveUpdates,
  resolveProjectLiveUpdatesId
} from "../src/views/Projects/projectLiveUpdates.js";

test("project live updates prefer the selected project id", () => {
  assert.equal(resolveProjectLiveUpdatesId("", { id: "p1" }), "p1");
  assert.equal(resolveProjectLiveUpdatesId("route-project", { id: "p1" }), "p1");
  assert.equal(resolveProjectLiveUpdatesId("route-project", null), "route-project");
});

test("project live updates refresh on task notifications for the active project", () => {
  assert.equal(
    projectNotificationTargetsLiveUpdates({
      type: "task_completed",
      metadata: { projectId: "p1", taskId: "t1" }
    }, "p1"),
    true
  );
  assert.equal(
    projectNotificationTargetsLiveUpdates({
      type: "input_required",
      metadata: { projectId: "p1", taskId: "t1" }
    }, "p1"),
    true
  );
  assert.equal(
    projectNotificationTargetsLiveUpdates({
      type: "agent_error",
      metadata: { projectId: "p1", taskId: "t1" }
    }, "p1"),
    true
  );
});

test("project live updates ignore unrelated notifications", () => {
  assert.equal(
    projectNotificationTargetsLiveUpdates({
      type: "task_completed",
      metadata: { projectId: "p2", taskId: "t1" }
    }, "p1"),
    false
  );
  assert.equal(
    projectNotificationTargetsLiveUpdates({
      type: "task_completed",
      metadata: { projectId: "p1" }
    }, "p1"),
    false
  );
  assert.equal(
    projectNotificationTargetsLiveUpdates({
      type: "confirmation",
      metadata: { projectId: "p1", taskId: "t1" }
    }, "p1"),
    false
  );
});
