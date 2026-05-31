import assert from "node:assert/strict";
import test from "node:test";

import { getNotificationNavigationTarget } from "../src/features/notifications/notificationNavigation.ts";

test("notification navigation prefers task metadata over agent metadata", () => {
  const target = getNotificationNavigationTarget({
    taskId: " ADAENGINE-17 ",
    projectId: "adaengine",
    agentId: "worker",
    sessionId: "session-1"
  });

  assert.deepEqual(target, {
    kind: "task",
    taskReference: "ADAENGINE-17",
    label: "View task"
  });
});

test("notification navigation falls back to the agent session target", () => {
  const target = getNotificationNavigationTarget({
    agentId: "worker",
    sessionId: "session-1"
  });

  assert.deepEqual(target, {
    kind: "agent",
    agentId: "worker",
    sessionId: "session-1",
    label: "View session"
  });
});

test("notification navigation extracts an agent session from channel metadata", () => {
  const target = getNotificationNavigationTarget({
    agentId: "worker",
    channelId: "agent:worker:session:session-2"
  });

  assert.deepEqual(target, {
    kind: "agent",
    agentId: "worker",
    sessionId: "session-2",
    label: "View session"
  });
});

test("notification navigation ignores empty metadata", () => {
  assert.equal(getNotificationNavigationTarget({ taskId: "  " }), null);
  assert.equal(getNotificationNavigationTarget(undefined), null);
});
