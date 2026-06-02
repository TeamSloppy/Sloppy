import assert from "node:assert/strict";
import test from "node:test";

import {
  buildProjectTaskSelectionOrder,
  taskSelectionRangeIds
} from "../src/views/Projects/taskSelection.js";

test("project task selection order follows the visible kanban columns", () => {
  const taskIds = buildProjectTaskSelectionOrder([
    { id: "done-1", status: "done", createdAt: "2026-01-01T10:00:00.000Z" },
    { id: "backlog-2", status: "backlog", createdAt: "2026-01-01T11:00:00.000Z" },
    { id: "ready-1", status: "ready", createdAt: "2026-01-01T09:00:00.000Z" },
    { id: "backlog-1", status: "backlog", createdAt: "2026-01-01T10:00:00.000Z" }
  ], [
    { id: "backlog" },
    { id: "ready" },
    { id: "done" }
  ]);

  assert.deepEqual(taskIds, ["backlog-1", "backlog-2", "ready-1", "done-1"]);
});

test("task selection range includes both anchor and clicked task", () => {
  assert.deepEqual(
    taskSelectionRangeIds(["a", "b", "c", "d"], "b", "d"),
    ["b", "c", "d"]
  );
  assert.deepEqual(
    taskSelectionRangeIds(["a", "b", "c", "d"], "d", "b"),
    ["b", "c", "d"]
  );
});

test("task selection range falls back to the clicked task without an anchor", () => {
  assert.deepEqual(
    taskSelectionRangeIds(["a", "b", "c"], "", "b"),
    ["b"]
  );
});
