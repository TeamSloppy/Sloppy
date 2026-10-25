import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  buildWorkflowGraphLayout,
  buildWorkflowConnection,
  buildWorkflowLaneGroups,
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

test("workflow routes keep straight connections and their labels between the ports", () => {
  assert.deepEqual(buildWorkflowConnection({ x: 220, y: 52 }, { x: 420, y: 52 }), {
    path: "M 220 52 L 420 52", labelX: 320, labelY: 52
  });
});

test("workflow review loops route above the nodes with their label on the return segment", () => {
  const result = buildWorkflowConnection({ x: 900, y: 252 }, { x: 400, y: 252 });
  assert.match(result.path, /^M 900 252 L /);
  assert.match(result.path, / Q /);
  assert.match(result.path, / L 400 252$/);
  assert.equal(result.labelY, 164);
  assert.ok(result.labelX > 400 && result.labelX < 900);
  assert.doesNotMatch(result.path, /NaN|Infinity/);
  const cleared = buildWorkflowConnection({ x: 900, y: 252 }, { x: 400, y: 252 }, "right", "left", { loopY: 20 });
  assert.equal(cleared.labelY, 20);
});

test("workflow routes preserve named and vertical socket endpoints", () => {
  for (const [sourceSocket, targetSocket] of [["true", "input"], ["bottom", "top"], ["right", "top"]]) {
    const result = buildWorkflowConnection({ x: 100, y: 80 }, { x: 350, y: 240 }, sourceSocket, targetSocket);
    assert.match(result.path, /^M 100 80 L /);
    assert.match(result.path, / L 350 240$/);
    assert.doesNotMatch(result.path, /NaN|Infinity/);
  }
});

test("team frames enclose only their own nodes and omit single-member lanes", () => {
  const groups = buildWorkflowLaneGroups({
    lanes: [{ id: "review", title: "Review team", kind: "team" }, { id: "owner", title: "Owner", kind: "team" }],
    nodes: [
      { laneId: "review", positionX: 400, positionY: 100 },
      { laneId: "review", positionX: 400, positionY: 300 },
      { laneId: "owner", positionX: 1000, positionY: 800 }
    ]
  });
  assert.deepEqual(groups, [{ id: "review", title: "Review team", x: 374, y: 46, width: 272, height: 384 }]);
  assert.deepEqual(buildWorkflowLaneGroups(null), []);
});

function cssRule(selector) {
  const escapedSelector = selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = projectsCss.match(new RegExp(`${escapedSelector}\\s*\\{([^}]*)\\}`));
  assert.ok(match, `Missing CSS rule for ${selector}`);
  return match[1];
}

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

test("workflow shell stays within the workspace while side panels own vertical scroll", () => {
  const shellRule = cssRule(".project-workflows-shell");
  const gridRule = cssRule(".project-workflows-grid");

  assert.doesNotMatch(shellRule, /height:\s*100%/);
  assert.doesNotMatch(gridRule, /height:\s*100%/);
  assert.match(shellRule, /overflow:\s*hidden/);
  assert.match(gridRule, /flex:\s*1 1 0/);
  assert.match(projectsCss, /\.project-workflows-list,\n\.project-workflows-inspector\s*\{[\s\S]*?overflow-y:\s*auto/);
  assert.match(projectsCss, /\.project-workflows-list,\n\.project-workflows-inspector\s*\{[\s\S]*?overscroll-behavior:\s*contain/);
});

test("workflow board status highlights unsaved changes with the accent treatment", () => {
  assert.match(projectWorkflowsTabSource, /className=\{`project-workflows-board-status \$\{isDirty \? "is-dirty" : ""\}`\.trim\(\)\}/);
  assert.match(projectsCss, /\.project-workflows-board-status\.is-dirty\s*\{[\s\S]*?color:\s*var\(--accent\)/);
});

test("workflow board surface lets blank canvas pointer events reach the scroller", () => {
  const boardRule = cssRule(".project-workflows-board");
  const nodeRule = cssRule(".project-workflow-node");
  const linkHitRule = cssRule(".project-workflow-link-hit");

  assert.match(boardRule, /pointer-events:\s*none/);
  assert.match(nodeRule, /pointer-events:\s*auto/);
  assert.match(linkHitRule, /pointer-events:\s*auto/);
});

test("workflow node ports default to one input and one output", () => {
  assert.deepEqual(workflowNodePorts({ type: "tool_check", config: { blockKind: "bash" } }), [
    { id: "input", label: "input", direction: "input", socket: "left" },
    { id: "output", label: "output", direction: "output", socket: "right" }
  ]);
});

test("workflow sockets render as color coded ports without visible labels", () => {
  assert.doesNotMatch(projectWorkflowsTabSource, /<span>\{port\.label\}<\/span>/);
  assert.match(projectWorkflowsTabSource, /aria-label=\{`\$\{port\.direction\}: \$\{port\.label\}`\}/);
  assert.match(projectsCss, /\.project-workflow-socket\.port-input\s*\{[\s\S]*?border-color:\s*#4ade80/);
  assert.match(projectsCss, /\.project-workflow-socket\.port-output\s*\{[\s\S]*?border-color:\s*#fb7185/);
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

test("agent step preview shows the answer ahead of execution metadata", () => {
  const description = describeWorkflowStep({
    nodeId: "review", status: "succeeded",
    output: { agentId: "reviewer", sessionId: "session", agentOutcome: "completed", model: "mock", text: "Verified the implementation." }
  });
  assert.equal(description.output, "Verified the implementation.");
  assert.equal(description.detail, "Verified the implementation.");
});

test("process and structured outputs take priority over execution metadata", () => {
  assert.equal(describeWorkflowStep({ nodeId: "qa", status: "succeeded", output: {
    command: "bash", arguments: ["-lc", "check"], exitCode: 0, status: "succeeded", stdout: "Checks passed"
  } }).detail, "Checks passed");
  assert.equal(describeWorkflowStep({ nodeId: "result", status: "succeeded", output: { result: false, status: "succeeded" } }).output, "false");
});

test("nearby forward ports stay straight instead of drawing return spikes", () => {
  for (const gap of [2, 30, 60, 64]) {
    assert.deepEqual(buildWorkflowConnection({ x: 270, y: 292 }, { x: 270 + gap, y: 292 }, "output", "input"), {
      path: `M 270 292 L ${270 + gap} 292`, labelX: 270 + gap / 2, labelY: 292
    });
  }
});

test("legacy Merge exposes join ports rather than boolean routes", () => {
  assert.deepEqual(workflowNodePorts({ type: "condition", config: { block_kind: "merge" } }).map((port) => port.id), ["input", "output"]);
});
