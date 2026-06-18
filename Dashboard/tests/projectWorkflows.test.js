import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  buildWorkflowGraphLayout,
  createBlankWorkflowRequest,
  describeWorkflowStep,
  workflowInputNodeReferences,
  workflowDataReferences,
  workflowNodePorts,
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

test("workflow canvas does not render a separate lane strip label", () => {
  assert.doesNotMatch(projectWorkflowsTabSource, /project-workflows-lane-strip/);
  assert.match(projectWorkflowsTabSource, /lane\?\.title \|\| node\.laneId \|\| "Unassigned"/);
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

test("workflow node ports default to one input and one output", () => {
  assert.deepEqual(workflowNodePorts({ type: "tool_check", config: { blockKind: "bash" } }), [
    { id: "input", label: "input", direction: "input", socket: "left" },
    { id: "output", label: "output", direction: "output", socket: "right" }
  ]);
});

test("workflow condition nodes expose named route outputs without adding extra inputs", () => {
  assert.deepEqual(workflowNodePorts({ type: "condition", config: { blockKind: "expression" } }), [
    { id: "input", label: "input", direction: "input", socket: "left" },
    { id: "true", label: "true", direction: "output", socket: "right" },
    { id: "false", label: "false", direction: "output", socket: "right" }
  ]);
});

test("workflow data references show how to address previous node outputs", () => {
  assert.deepEqual(
    workflowDataReferences(
      [
        { id: "user-message", title: "User Message" },
        { id: "web-request", title: "Web Request" },
        { id: "bash", title: "Bash" }
      ],
      "bash"
    ),
    [
      { nodeId: "user-message", title: "User Message", output: "{{nodes.user-message.output}}", error: "{{nodes.user-message.error}}" },
      { nodeId: "web-request", title: "Web Request", output: "{{nodes.web-request.output}}", error: "{{nodes.web-request.error}}" }
    ]
  );
});

test("workflow input node references follow incoming graph edges for editor suggestions", () => {
  assert.deepEqual(
    workflowInputNodeReferences({
      nodes: [
        { id: "user-message", title: "User Message" },
        { id: "web-request", title: "Web Request" },
        { id: "code", title: "Code" },
        { id: "unrelated", title: "Unrelated" }
      ],
      edges: [
        { id: "e1", sourceNodeId: "user-message", targetNodeId: "web-request" },
        { id: "e2", sourceNodeId: "web-request", targetNodeId: "code" }
      ]
    }, "code"),
    [
      { nodeId: "user-message", title: "User Message", output: "{{nodes.user-message.output}}", error: "{{nodes.user-message.error}}" },
      { nodeId: "web-request", title: "Web Request", output: "{{nodes.web-request.output}}", error: "{{nodes.web-request.error}}" }
    ]
  );
});

test("workflow editor marks connected input nodes on the canvas", () => {
  assert.match(projectWorkflowsTabSource, /availableInputNodeIds\.has\(String\(node\.id\)\)/);
  assert.match(projectsCss, /\.project-workflow-node\.available-input/);
});

test("describeWorkflowStep includes output and error detail instead of only failed", () => {
  assert.deepEqual(
    describeWorkflowStep({
      nodeId: "web-request",
      status: "failed",
      output: { status: 404, body: "Not found" },
      error: "HTTP 404"
    }),
    {
      title: "web-request: failed",
      detail: "HTTP 404",
      output: "status: 404, body: Not found"
    }
  );
});
