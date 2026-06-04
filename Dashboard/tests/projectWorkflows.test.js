import assert from "node:assert/strict";
import test from "node:test";

import {
  buildWorkflowGraphLayout,
  selectWorkflowAfterDelete
} from "../src/views/Projects/projectWorkflows.js";

test("selectWorkflowAfterDelete picks the next workflow after deleting the selected one", () => {
  const workflows = [
    { id: "wf-a" },
    { id: "wf-b" },
    { id: "wf-c" }
  ];

  assert.equal(selectWorkflowAfterDelete(workflows, "wf-b"), "wf-c");
});

test("selectWorkflowAfterDelete falls back to previous workflow at the end", () => {
  const workflows = [
    { id: "wf-a" },
    { id: "wf-b" }
  ];

  assert.equal(selectWorkflowAfterDelete(workflows, "wf-b"), "wf-a");
});

test("selectWorkflowAfterDelete clears selection when no workflows remain", () => {
  assert.equal(selectWorkflowAfterDelete([{ id: "wf-a" }], "wf-a"), "");
});

test("buildWorkflowGraphLayout creates canvas paths and edge labels from workflow edges", () => {
  const layout = buildWorkflowGraphLayout({
    lanes: [
      { id: "system", title: "System", kind: "system" },
      { id: "owner", title: "Owner", kind: "human" }
    ],
    nodes: [
      { id: "start", title: "Manual start", laneId: "system", positionX: 80, positionY: 80 },
      { id: "approval", title: "Approve", laneId: "owner", positionX: 360, positionY: 120 },
      { id: "done", title: "Done", laneId: "system", positionX: 640, positionY: 80 }
    ],
    edges: [
      { id: "e_start_approval", sourceNodeId: "start", targetNodeId: "approval" },
      { id: "e_approval_done", sourceNodeId: "approval", targetNodeId: "done", conditionKey: "approved" }
    ]
  });

  assert.equal(layout.nodes.length, 3);
  assert.equal(layout.links.length, 2);
  assert.match(layout.links[0].path, /^M \d+ \d+ C /);
  assert.equal(layout.links[1].label, "approved");
  assert.ok(layout.width > 820);
  assert.ok(layout.height > 260);
});
