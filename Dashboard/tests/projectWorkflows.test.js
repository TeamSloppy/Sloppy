import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  buildWorkflowGraphLayout,
  createBlankWorkflowRequest,
  workflowBoardSurfaceStyle,
  selectWorkflowAfterDelete,
  workflowCanvasViewportStyle
} from "../src/views/Projects/projectWorkflows.js";

const dashboardRoot = dirname(dirname(fileURLToPath(import.meta.url)));
const projectWorkflowsTabSource = readFileSync(join(dashboardRoot, "src", "views", "Projects", "ProjectWorkflowsTab.tsx"), "utf8");
const projectsCss = readFileSync(join(dashboardRoot, "src", "styles", "projects.css"), "utf8");

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

test("workflowCanvasViewportStyle matches the screen height in the compact workflow layout", () => {
  assert.deepEqual(workflowCanvasViewportStyle(891, 998), { height: "998px" });
});

test("workflowCanvasViewportStyle leaves the desktop workflow layout flexible", () => {
  assert.deepEqual(workflowCanvasViewportStyle(1280, 720), {});
});

test("createBlankWorkflowRequest builds a valid new workflow with a trigger node", () => {
  const workflow = createBlankWorkflowRequest(2);

  assert.equal(workflow.name, "Workflow 2");
  assert.equal(workflow.lanes.length, 1);
  assert.equal(workflow.nodes.length, 1);
  assert.equal(workflow.nodes[0].type, "trigger");
  assert.equal(workflow.nodes[0].laneId, "system");
  assert.deepEqual(workflow.edges, []);
});

test("workflowBoardSurfaceStyle keeps an empty board aligned to its pane", () => {
  assert.deepEqual(workflowBoardSurfaceStyle(null), { height: "100%", width: "100%" });
  assert.deepEqual(workflowBoardSurfaceStyle({ nodes: [] }), { height: "100%", width: "100%" });
});

test("workflowBoardSurfaceStyle expands to the workflow graph bounds when nodes exist", () => {
  assert.deepEqual(
    workflowBoardSurfaceStyle({
      nodes: [
        { positionX: 120, positionY: 140 },
        { positionX: 520, positionY: 220 }
      ]
    }),
    { height: "420px", width: "900px" }
  );
});

test("workflow lane strip shows only the lane title without duplicating the kind label", () => {
  assert.match(projectWorkflowsTabSource, /<strong>\{lane.title\}<\/strong>/);
  assert.doesNotMatch(projectWorkflowsTabSource, /<small>\{lane.kind\}<\/small>/);
});

test("workflow side panels use the custom thin scrollbar styling", () => {
  assert.match(projectsCss, /\.project-workflows-list,\n\.project-workflows-inspector\s*\{[\s\S]*?scrollbar-width:\s*thin/);
  assert.match(projectsCss, /\.project-workflows-list,\n\.project-workflows-inspector\s*\{[\s\S]*?scrollbar-color:\s*var\(--line-strong\) transparent/);
  assert.match(projectsCss, /\.project-workflows-list::-webkit-scrollbar,\n\.project-workflows-inspector::-webkit-scrollbar\s*\{[\s\S]*?width:\s*10px/);
  assert.match(projectsCss, /\.project-workflows-list::-webkit-scrollbar-thumb,\n\.project-workflows-inspector::-webkit-scrollbar-thumb\s*\{[\s\S]*?background:\s*rgba\(138, 153, 180, 0\.45\)/);
});

test("workflow board status highlights unsaved changes with the accent treatment", () => {
  assert.match(projectWorkflowsTabSource, /className=\{`project-workflows-board-status \$\{isDirty \? "is-dirty" : ""\}`\.trim\(\)\}/);
  assert.match(projectsCss, /\.project-workflows-board-status\.is-dirty\s*\{[\s\S]*?color:\s*var\(--accent\)/);
});
