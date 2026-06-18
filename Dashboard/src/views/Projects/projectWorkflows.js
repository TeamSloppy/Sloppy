export function selectWorkflowAfterDelete(workflows, deletedWorkflowId) {
  const list = Array.isArray(workflows) ? workflows : [];
  const index = list.findIndex((workflow) => String(workflow?.id || "") === String(deletedWorkflowId || ""));
  const remaining = list.filter((workflow) => String(workflow?.id || "") !== String(deletedWorkflowId || ""));
  if (remaining.length === 0) {
    return "";
  }
  return String(remaining[Math.min(index, remaining.length - 1)]?.id || "");
}

const NODE_WIDTH = 190;
const NODE_HEIGHT = 92;
const CANVAS_PADDING = 96;
const WORKFLOW_COMPACT_BREAKPOINT = 1040;

function asString(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text || fallback;
}

function asNumber(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function workflowBlockKind(node) {
  return asString(node?.config?.blockKind || node?.config?.block_kind);
}

export function workflowNodePorts(node) {
  const blockKind = workflowBlockKind(node);
  const type = asString(node?.type);
  const input = { id: "input", label: "input", direction: "input", socket: "left" };
  const output = { id: "output", label: "output", direction: "output", socket: "right" };

  if (type === "condition" || blockKind === "expression" || blockKind === "loop") {
    return [
      input,
      { id: "true", label: "true", direction: "output", socket: "right" },
      { id: "false", label: "false", direction: "output", socket: "right" }
    ];
  }

  if (type === "end" || blockKind === "stop" || blockKind === "error") {
    return [input];
  }

  return [input, output];
}

export function workflowDataReferences(nodes, currentNodeId) {
  const list = Array.isArray(nodes) ? nodes : [];
  const currentIndex = list.findIndex((node) => String(node?.id || "") === String(currentNodeId || ""));
  const candidates = currentIndex >= 0 ? list.slice(0, currentIndex) : list.filter((node) => String(node?.id || "") !== String(currentNodeId || ""));
  return workflowNodeReferences(candidates);
}

export function workflowInputNodeReferences(workflow, currentNodeId) {
  const nodes = Array.isArray(workflow?.nodes) ? workflow.nodes : [];
  const edges = Array.isArray(workflow?.edges) ? workflow.edges : [];
  const nodeById = new Map(nodes.map((node) => [String(node?.id || ""), node]));
  const incomingByTarget = new Map();
  for (const edge of edges) {
    const sourceNodeId = asString(edge?.sourceNodeId);
    const targetNodeId = asString(edge?.targetNodeId);
    if (!sourceNodeId || !targetNodeId) continue;
    incomingByTarget.set(targetNodeId, [...(incomingByTarget.get(targetNodeId) || []), sourceNodeId]);
  }

  const ordered = [];
  const visited = new Set();
  function visit(nodeId) {
    for (const sourceNodeId of incomingByTarget.get(nodeId) || []) {
      if (visited.has(sourceNodeId)) continue;
      visited.add(sourceNodeId);
      visit(sourceNodeId);
      const node = nodeById.get(sourceNodeId);
      if (node) ordered.push(node);
    }
  }
  visit(asString(currentNodeId));
  return workflowNodeReferences(ordered);
}

function workflowNodeReferences(nodes) {
  const candidates = Array.isArray(nodes) ? nodes : [];
  return candidates.map((node) => {
    const nodeId = asString(node?.id);
    return {
      nodeId,
      title: asString(node?.title, nodeId),
      output: `{{nodes.${nodeId}.output}}`,
      error: `{{nodes.${nodeId}.error}}`
    };
  }).filter((entry) => entry.nodeId);
}

function formatWorkflowValue(value) {
  if (value == null) return "";
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  if (Array.isArray(value)) {
    return value.map(formatWorkflowValue).filter(Boolean).join(", ");
  }
  if (typeof value === "object") {
    return Object.entries(value)
      .slice(0, 4)
      .map(([key, entry]) => `${key}: ${formatWorkflowValue(entry)}`)
      .filter(Boolean)
      .join(", ");
  }
  return String(value);
}

export function describeWorkflowStep(step) {
  const nodeId = asString(step?.nodeId, "node");
  const status = asString(step?.status, "unknown").replace(/_/g, " ");
  const error = asString(step?.error);
  const output = formatWorkflowValue(step?.output);
  return {
    title: `${nodeId}: ${status}`,
    detail: error || output || "",
    output
  };
}

export function workflowCanvasViewportStyle(viewportWidth, viewportHeight) {
  const width = asNumber(viewportWidth, 0);
  const height = asNumber(viewportHeight, 0);
  if (width <= 0 || height <= 0 || width > WORKFLOW_COMPACT_BREAKPOINT) {
    return {};
  }
  return { height: `${Math.round(height)}px` };
}

export function workflowBoardSurfaceStyle(workflow) {
  const nodes = Array.isArray(workflow?.nodes) ? workflow.nodes : [];
  if (nodes.length === 0) {
    return { width: "100%", height: "100%" };
  }
  const maxX = nodes.reduce((value, node) => Math.max(value, asNumber(node?.positionX, 0) + NODE_WIDTH), 0);
  const maxY = nodes.reduce((value, node) => Math.max(value, asNumber(node?.positionY, 0) + NODE_HEIGHT), 0);
  return {
    width: `${Math.max(900, maxX + CANVAS_PADDING)}px`,
    height: `${Math.max(420, maxY + CANVAS_PADDING)}px`
  };
}

export function createBlankWorkflowRequest(nextIndex) {
  const index = Math.max(1, asNumber(nextIndex, 1));
  return {
    name: `Workflow ${index}`,
    enabled: true,
    lanes: [{ id: "system", title: "System", kind: "system" }],
    nodes: [{
      id: "start",
      type: "trigger",
      title: "User Message",
      laneId: "system",
      config: { mode: "manual", blockKind: "user_message", accepts: "text, attachment, artifact" },
      positionX: 120,
      positionY: 140
    }],
    edges: []
  };
}

function workflowNodePoint(node, side) {
  if (side === "left") {
    return { x: node.positionX, y: node.positionY + NODE_HEIGHT / 2 };
  }
  return { x: node.positionX + NODE_WIDTH, y: node.positionY + NODE_HEIGHT / 2 };
}

function buildWorkflowLinkPath(source, target) {
  const distance = Math.max(80, Math.abs(target.x - source.x) * 0.45);
  return [
    `M ${source.x} ${source.y}`,
    `C ${source.x + distance} ${source.y}`,
    `${target.x - distance} ${target.y}`,
    `${target.x} ${target.y}`
  ].join(" ");
}

export function buildWorkflowGraphLayout(workflow) {
  const lanes = Array.isArray(workflow?.lanes) ? workflow.lanes : [];
  const nodes = (Array.isArray(workflow?.nodes) ? workflow.nodes : []).map((node, index) => ({
    ...node,
    id: String(node?.id || `node-${index}`),
    positionX: asNumber(node?.positionX, 80 + index * 280),
    positionY: asNumber(node?.positionY, 80)
  }));
  const nodeMap = new Map(nodes.map((node) => [node.id, node]));
  const laneMap = new Map(lanes.map((lane) => [String(lane?.id || ""), lane]));
  const maxX = nodes.reduce((value, node) => Math.max(value, node.positionX + NODE_WIDTH), 0);
  const maxY = nodes.reduce((value, node) => Math.max(value, node.positionY + NODE_HEIGHT), 0);

  const links = (Array.isArray(workflow?.edges) ? workflow.edges : []).flatMap((edge, index) => {
    const sourceNode = nodeMap.get(String(edge?.sourceNodeId || ""));
    const targetNode = nodeMap.get(String(edge?.targetNodeId || ""));
    if (!sourceNode || !targetNode) {
      return [];
    }
    const source = workflowNodePoint(sourceNode, "right");
    const target = workflowNodePoint(targetNode, "left");
    return [{
      id: String(edge?.id || `edge-${index}`),
      label: edge?.conditionKey ? String(edge.conditionKey) : "",
      path: buildWorkflowLinkPath(source, target),
      midX: (source.x + target.x) / 2,
      midY: (source.y + target.y) / 2
    }];
  });

  return {
    lanes,
    laneMap,
    nodes,
    links,
    width: Math.max(900, maxX + CANVAS_PADDING),
    height: Math.max(420, maxY + CANVAS_PADDING)
  };
}
