import React, { useEffect, useId, useMemo, useRef, useState } from "react";
import {
  createProjectWorkflow,
  deleteProjectWorkflow,
  fetchAgents,
  fetchProjectWorkflowActions,
  fetchProjectWorkflowRun,
  fetchProjectWorkflowRuns,
  fetchProjectWorkflows,
  resolveProjectWorkflowAction,
  startProjectWorkflowRun,
  updateProjectWorkflow
} from "../../api";
import {
  createBlankWorkflowRequest,
  buildWorkflowConnection,
  buildWorkflowLaneGroups,
  describeWorkflowStep,
  selectWorkflowAfterDelete,
  workflowBoardSurfaceStyle,
  workflowCanvasViewportStyle,
  workflowInputNodeReferences,
  workflowNodePorts,
  WORKFLOW_NODE_WIDTH,
  WORKFLOW_NODE_HEIGHT
} from "./projectWorkflows";
import "../../styles/workflows.css";

import { WorkflowOutputControls, WorkflowTransitionControls } from "./WorkflowContractControls";
import { WorkflowSessionControls } from "./WorkflowSessionControls";
import { WorkflowParallelControls } from "./WorkflowParallelControls";
import { WorkflowLaunchControls } from "./WorkflowLaunchControls";
import { WorkflowRunControls } from "./WorkflowRunControls";
import { WorkflowAgentQuestions } from "./WorkflowAgentQuestions";
import { WorkflowBlockControls } from "./WorkflowBlockControls";

type AnyRecord = Record<string, any>;

interface ProjectWorkflowsTabProps {
  project: AnyRecord;
  selectedTask?: AnyRecord | null;
  routeWorkflowId?: string | null;
  routeWorkflowRunId?: string | null;
}

interface WorkflowCanvasPanState {
  originClientX: number;
  originClientY: number;
  originX: number;
  originY: number;
}

interface WorkflowDragState {
  nodeId: string;
  originClientX: number;
  originClientY: number;
  originNodeX: number;
  originNodeY: number;
}

interface WorkflowPortDragState {
  sourceNodeId: string;
  sourceSocket: string;
  pointerX: number;
  pointerY: number;
}

const NODE_WIDTH = WORKFLOW_NODE_WIDTH;
const NODE_HEIGHT = WORKFLOW_NODE_HEIGHT;
const SOCKETS = ["top", "right", "bottom", "left", "input", "output", "true", "false"];
const HTTP_METHODS = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"];
const CODE_LANGUAGES = ["javascript", "python"];

const BLOCK_PRESETS = [
  { id: "project_task", title: "Project Task", type: "project_task", icon: "task_alt", laneKind: "system", laneTitle: "Task", description: "Read the task snapshot selected for this run.", config: { blockKind: "project_task" } },
  { id: "update_task", title: "Update Task", type: "update_task", icon: "edit_note", laneKind: "system", laneTitle: "Task", description: "Update the selected task status.", config: { blockKind: "update_task", status: "done" } },
  {
    id: "user_message",
    title: "User Message",
    type: "trigger",
    icon: "chat",
    laneKind: "system",
    laneTitle: "Input",
    description: "Manual input: text, attachment, artifact.",
    config: { mode: "manual", blockKind: "user_message", accepts: "text, attachment, artifact" }
  },
  {
    id: "agent",
    title: "Agent",
    type: "agent_step",
    icon: "smart_toy",
    laneKind: "agent",
    laneTitle: "Agent",
    description: "Send message or artifact to selected agent.",
    config: { blockKind: "agent", agentId: "", model: "", prompt: "Handle the workflow input." }
  },
  {
    id: "code",
    title: "Code",
    type: "tool_check",
    icon: "code",
    laneKind: "system",
    laneTitle: "Automation",
    description: "Run JavaScript/Python inline code or file path.",
    config: { blockKind: "code", language: "javascript", source: "", filePath: "" }
  },
  {
    id: "bash",
    title: "Bash",
    type: "tool_check",
    icon: "terminal",
    laneKind: "system",
    laneTitle: "Automation",
    description: "Run shell command through exec.",
    config: { blockKind: "bash", command: "" }
  },
  {
    id: "channel",
    title: "Channel",
    type: "notify",
    icon: "send",
    laneKind: "system",
    laneTitle: "Output",
    description: "Send final message to a channel.",
    config: { blockKind: "channel", channelId: "", message: "{{input}}" }
  },
  {
    id: "tool",
    title: "Tool",
    type: "tool_check",
    icon: "construction",
    laneKind: "system",
    laneTitle: "Automation",
    description: "Call a registered tool as workflow action.",
    config: { blockKind: "tool", toolName: "", arguments: "{}" }
  },
  {
    id: "web_request",
    title: "Web Request",
    type: "tool_check",
    icon: "http",
    laneKind: "system",
    laneTitle: "Network",
    description: "HTTP request with method, URL, body, headers.",
    config: { blockKind: "web_request", method: "GET", url: "", headers: "{}", body: "" }
  },
  {
    id: "expression",
    title: "Expression",
    type: "condition",
    icon: "alt_route",
    laneKind: "system",
    laneTitle: "Flow",
    description: "Check condition and route by edge label.",
    config: { blockKind: "expression", expression: "status == 'ok'" }
  },
  {
    id: "ai_transform",
    title: "AI Transform",
    type: "agent_step",
    icon: "auto_fix_high",
    laneKind: "agent",
    laneTitle: "Agent",
    description: "Generate transformation code from natural language.",
    config: { blockKind: "ai_transform", prompt: "Transform input into the required output.", model: "" }
  },
  {
    id: "wait",
    title: "Waiting",
    type: "human_input",
    icon: "hourglass",
    laneKind: "human",
    laneTitle: "Human",
    description: "Pause until human/action resolves.",
    config: { blockKind: "wait", prompt: "Continue workflow?", assignee: "human:admin" }
  },
  {
    id: "loop",
    title: "Loop",
    type: "condition",
    icon: "repeat",
    laneKind: "system",
    laneTitle: "Flow",
    description: "Route back while expression matches.",
    config: { blockKind: "loop", expression: "continue == true", maxIterations: "10" }
  },
  {
    id: "parallel",
    title: "Parallel",
    type: "parallel",
    icon: "call_split",
    laneKind: "system",
    laneTitle: "Flow",
    description: "Run branches together and wait at one Join.",
    config: { blockKind: "parallel", joinNodeId: "" }
  },
  {
    id: "join",
    title: "Join",
    type: "join",
    icon: "call_merge",
    laneKind: "system",
    laneTitle: "Flow",
    description: "Continue after every parallel branch succeeds.",
    config: { blockKind: "join", strategy: "all" }
  },
  {
    id: "sub_workflow",
    title: "Sub-workflow",
    type: "tool_check",
    icon: "account_tree",
    laneKind: "system",
    laneTitle: "Automation",
    description: "Execute another workflow by id.",
    config: { blockKind: "sub_workflow", workflowId: "" }
  },
  {
    id: "stop_success",
    title: "Stop",
    type: "end",
    icon: "flag",
    laneKind: "system",
    laneTitle: "Output",
    description: "Finish workflow successfully.",
    config: { blockKind: "stop", status: "completed" }
  },
  {
    id: "stop_error",
    title: "Error",
    type: "end",
    icon: "report",
    laneKind: "system",
    laneTitle: "Output",
    description: "Stop workflow with failed status.",
    config: { blockKind: "error", status: "failed", message: "" }
  }
];

const STARTER_WORKFLOW = {
  name: "Dashboard Approval",
  enabled: true,
  lanes: [
    { id: "input", title: "Input", kind: "system" },
    { id: "agent", title: "Agent", kind: "agent" },
    { id: "human", title: "Human", kind: "human", actorId: "human:admin" },
    { id: "output", title: "Output", kind: "system" }
  ],
  nodes: [
    { id: "start", type: "trigger", title: "User Message", laneId: "input", config: { mode: "manual", blockKind: "user_message" }, positionX: 120, positionY: 140 },
    { id: "agent-review", type: "agent_step", title: "Agent Review", laneId: "agent", config: { blockKind: "agent", prompt: "Review the incoming message and prepare a decision." }, positionX: 420, positionY: 140 },
    { id: "approval", type: "human_approval", title: "Approve", laneId: "human", config: { blockKind: "wait", prompt: "Approve this workflow run?", assignee: "human:admin" }, positionX: 720, positionY: 140 },
    { id: "done", type: "end", title: "Done", laneId: "output", config: { blockKind: "stop", status: "completed" }, positionX: 1020, positionY: 140 }
  ],
  edges: [
    { id: "edge-start-agent-review", sourceNodeId: "start", targetNodeId: "agent-review", sourceSocket: "right", targetSocket: "left" },
    { id: "edge-agent-review-approval", sourceNodeId: "agent-review", targetNodeId: "approval", sourceSocket: "right", targetSocket: "left" },
    { id: "edge-approval-done", sourceNodeId: "approval", targetNodeId: "done", conditionKey: "approved", sourceSocket: "right", targetSocket: "left" }
  ]
};

function asString(value: unknown, fallback = "") {
  const text = String(value ?? "").trim();
  return text || fallback;
}

function rawString(value: unknown, fallback = "") {
  return value == null ? fallback : String(value);
}

function asNumber(value: unknown, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function slugify(value: unknown) {
  return String(value || "")
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}

function uniqueId(prefix: string, existing: Set<string>) {
  if (!existing.has(prefix)) return prefix;
  let counter = 2;
  while (existing.has(`${prefix}-${counter}`)) counter += 1;
  return `${prefix}-${counter}`;
}

function normalizeWheelDelta(delta: number, deltaMode: number, pageSize: number) {
  if (deltaMode === 1) return delta * 16;
  if (deltaMode === 2) return delta * pageSize;
  return delta;
}

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value));
}

function formatStatus(value: unknown) {
  return String(value || "unknown").replace(/_/g, " ");
}

function formatDate(value: unknown) {
  if (!value) return "";
  const date = new Date(String(value));
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleString();
}

function normalizeSocket(value: unknown, fallback = "right") {
  const socket = asString(value, fallback);
  return SOCKETS.includes(socket) ? socket : fallback;
}

function workflowNodeIcon(type: unknown, config: AnyRecord = {}) {
  const blockKind = asString(config.blockKind || config.block_kind);
  const preset = BLOCK_PRESETS.find((entry) => entry.id === blockKind);
  if (preset) return preset.icon;
  switch (String(type || "")) {
    case "trigger":
      return "play_circle";
    case "agent_step":
      return "smart_toy";
    case "human_approval":
    case "human_input":
      return "approval";
    case "condition":
      return "alt_route";
    case "tool_check":
      return "construction";
    case "notify":
      return "send";
    case "end":
      return "flag";
    default:
      return "adjust";
  }
}

function socketPoint(node: AnyRecord, socket: string, direction = "output") {
  const ports = workflowNodePorts(node);
  const normalizedSocket = socket === "left" ? "input" : socket === "right" ? "output" : socket;
  const port = ports.find((entry: AnyRecord) => entry.id === normalizedSocket)
    || ports.find((entry: AnyRecord) => entry.socket === socket && entry.direction === direction)
    || ports.find((entry: AnyRecord) => entry.direction === direction)
    || ports[0];
  if (port?.socket === "left") {
    const inputPorts = ports.filter((entry: AnyRecord) => entry.socket === "left");
    const index = Math.max(0, inputPorts.findIndex((entry: AnyRecord) => entry.id === port.id));
    const gap = NODE_HEIGHT / (inputPorts.length + 1);
    return { x: node.positionX, y: node.positionY + gap * (index + 1) };
  }
  if (port?.socket === "right") {
    const outputPorts = ports.filter((entry: AnyRecord) => entry.socket === "right");
    const index = Math.max(0, outputPorts.findIndex((entry: AnyRecord) => entry.id === port.id));
    const gap = NODE_HEIGHT / (outputPorts.length + 1);
    return { x: node.positionX + NODE_WIDTH, y: node.positionY + gap * (index + 1) };
  }
  switch (socket) {
    case "top":
      return { x: node.positionX + NODE_WIDTH / 2, y: node.positionY };
    case "right":
      return { x: node.positionX + NODE_WIDTH, y: node.positionY + NODE_HEIGHT / 2 };
    case "bottom":
      return { x: node.positionX + NODE_WIDTH / 2, y: node.positionY + NODE_HEIGHT };
    case "left":
    default:
      return { x: node.positionX, y: node.positionY + NODE_HEIGHT / 2 };
  }
}

function oppositeSocket(socket: string) {
  const side = socket === "input" ? "left" : socket === "output" || socket === "true" || socket === "false" ? "right" : socket;
  switch (side) {
    case "top":
      return "bottom";
    case "right":
      return "left";
    case "bottom":
      return "top";
    case "left":
    default:
      return "right";
  }
}

function nodePrimaryTextKey(node: AnyRecord) {
  const blockKind = asString(node.config?.blockKind || node.config?.block_kind);
  if (blockKind === "bash") return "command";
  if (blockKind === "expression" || blockKind === "loop") return "expression";
  if (blockKind === "channel" || blockKind === "error") return "message";
  return "prompt";
}

function normalizeWorkflow(raw: AnyRecord | null) {
  const lanes = Array.isArray(raw?.lanes) && raw!.lanes.length > 0
    ? raw!.lanes.map((lane: AnyRecord, index: number) => ({
      id: asString(lane?.id, `lane-${index + 1}`),
      title: asString(lane?.title, `Lane ${index + 1}`),
      kind: asString(lane?.kind, "system"),
      actorId: lane?.actorId || null,
      teamId: lane?.teamId || null
    }))
    : [{ id: "system", title: "System", kind: "system" }];
  const laneIds = new Set(lanes.map((lane: AnyRecord) => lane.id));
  const nodes = (Array.isArray(raw?.nodes) ? raw!.nodes : []).map((node: AnyRecord, index: number) => ({
    id: asString(node?.id, `node-${index + 1}`),
    type: asString(node?.type, "condition"),
    title: asString(node?.title, `Node ${index + 1}`),
    laneId: laneIds.has(asString(node?.laneId)) ? asString(node?.laneId) : lanes[0].id,
    config: node?.config && typeof node.config === "object" && !Array.isArray(node.config) ? node.config : {},
    positionX: asNumber(node?.positionX, 120 + index * 280),
    positionY: asNumber(node?.positionY, 140)
  }));
  const nodeIds = new Set(nodes.map((node: AnyRecord) => node.id));
  const edges = (Array.isArray(raw?.edges) ? raw!.edges : [])
    .map((edge: AnyRecord, index: number) => ({
      id: asString(edge?.id, `edge-${index + 1}`),
      sourceNodeId: asString(edge?.sourceNodeId),
      targetNodeId: asString(edge?.targetNodeId),
      conditionKey: asString(edge?.conditionKey),
      condition: edge?.condition || undefined,
      sourceSocket: normalizeSocket(edge?.sourceSocket, "right"),
      targetSocket: normalizeSocket(edge?.targetSocket, "left")
    }))
    .filter((edge: AnyRecord) => nodeIds.has(edge.sourceNodeId) && nodeIds.has(edge.targetNodeId));
  return {
    id: raw?.id || "",
    name: asString(raw?.name, "Untitled workflow"),
    version: raw?.version || 1,
    enabled: raw?.enabled !== false,
    lanes,
    nodes,
    edges
  };
}

function workflowPayload(draft: AnyRecord) {
  return {
    name: draft.name,
    enabled: draft.enabled !== false,
    lanes: draft.lanes.map((lane: AnyRecord) => ({
      id: lane.id,
      title: lane.title,
      kind: lane.kind,
      actorId: lane.actorId || undefined,
      teamId: lane.teamId || undefined
    })),
    nodes: draft.nodes.map((node: AnyRecord) => ({
      id: node.id,
      type: node.type,
      title: node.title,
      laneId: node.laneId,
      config: node.config || {},
      positionX: node.positionX,
      positionY: node.positionY
    })),
    edges: draft.edges.map((edge: AnyRecord) => ({
      id: edge.id,
      sourceNodeId: edge.sourceNodeId,
      targetNodeId: edge.targetNodeId,
      conditionKey: edge.conditionKey || undefined,
      condition: edge.condition || undefined,
      sourceSocket: edge.sourceSocket || undefined,
      targetSocket: edge.targetSocket || undefined
    }))
  };
}

function isTypingTarget(target: EventTarget | null) {
  if (!target || typeof (target as HTMLElement).closest !== "function") return false;
  return Boolean((target as HTMLElement).closest("input, textarea, select, [contenteditable='true']"));
}

export function ProjectWorkflowsTab({ project, selectedTask, routeWorkflowId = null, routeWorkflowRunId = null }: ProjectWorkflowsTabProps) {
  const arrowMarkerId = `workflow-arrow-${useId().replace(/:/g, "")}`;
  const scrollerRef = useRef<HTMLDivElement | null>(null);
  const draftRef = useRef<AnyRecord | null>(null);
  const viewTransformRef = useRef({ x: 0, y: 0, scale: 1 });
  const dragMovedRef = useRef(false);
  const [workflows, setWorkflows] = useState<AnyRecord[]>([]);
  const [runs, setRuns] = useState<AnyRecord[]>([]);
  const [actions, setActions] = useState<AnyRecord[]>([]);
  const [agents, setAgents] = useState<AnyRecord[]>([]);
  const [selectedWorkflowId, setSelectedWorkflowId] = useState("");
  const [selectedRunId, setSelectedRunId] = useState("");
  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null);
  const [selectedEdgeId, setSelectedEdgeId] = useState<string | null>(null);
  const [contractError, setContractError] = useState("");
  const [nodeConfigError, setNodeConfigError] = useState("");
  const [blockError, setBlockError] = useState("");
  useEffect(() => { setContractError(""); setNodeConfigError(""); setBlockError(""); }, [selectedNodeId, selectedEdgeId, project.id]);
  const [draft, setDraft] = useState<AnyRecord | null>(null);
  const [selectedRunDetail, setSelectedRunDetail] = useState<AnyRecord | null>(null);
  const [viewTransform, setViewTransform] = useState({ x: 0, y: 0, scale: 1 });
  const [panState, setPanState] = useState<WorkflowCanvasPanState | null>(null);
  const [dragState, setDragState] = useState<WorkflowDragState | null>(null);
  const [portDrag, setPortDrag] = useState<WorkflowPortDragState | null>(null);
  const [hoverInputPort, setHoverInputPort] = useState<AnyRecord | null>(null);
  const [isBusy, setIsBusy] = useState(false);
  const [isDirty, setIsDirty] = useState(false);
  const [statusText, setStatusText] = useState("Loading workflows...");
  const [nodeConfigText, setNodeConfigText] = useState("{}");
  const [agentSearch, setAgentSearch] = useState("");
  const [agentDropdownOpen, setAgentDropdownOpen] = useState(false);
  const [actionResponses, setActionResponses] = useState<Record<string, string>>({});
  const [libraryPanel, setLibraryPanel] = useState<"definitions" | "blocks" | null>(null);
  const [inspectorOpen, setInspectorOpen] = useState(false);
  const [inspectorTab, setInspectorTab] = useState<"details" | "activity" | "run">("details");
  const [helpOpen, setHelpOpen] = useState(false);
  const [isExpanded, setIsExpanded] = useState(false);
  const [viewportSize, setViewportSize] = useState(() => ({
    width: typeof window !== "undefined" ? window.innerWidth : 0,
    height: typeof window !== "undefined" ? window.innerHeight : 0
  }));
  const agentSearchRef = useRef<HTMLDivElement | null>(null);

  const selectedWorkflow = useMemo(
    () => workflows.find((workflow) => String(workflow.id) === selectedWorkflowId) || workflows[0] || null,
    [selectedWorkflowId, workflows]
  );
  const selectedRun = useMemo(
    () => runs.find((run) => String(run.id) === selectedRunId) || null,
    [runs, selectedRunId]
  );
  const runSteps = useMemo(
    () => Array.isArray(selectedRunDetail?.steps) ? selectedRunDetail.steps : [],
    [selectedRunDetail]
  );
  const activeNodeIds = useMemo<Set<string>>(
    () => new Set<string>((Array.isArray(selectedRun?.currentNodeIds) ? selectedRun.currentNodeIds : []).map(String)),
    [selectedRun]
  );
  const stepStatusByNode = useMemo(() => {
    const map = new Map<string, string>();
    for (const step of runSteps) map.set(String(step.nodeId), String(step.status || ""));
    return map;
  }, [runSteps]);
  const nodeMap = useMemo<Map<string, AnyRecord>>(
    () => new Map<string, AnyRecord>((draft?.nodes || []).map((node: AnyRecord) => [String(node.id), node])),
    [draft]
  );
  const laneMap = useMemo<Map<string, AnyRecord>>(
    () => new Map<string, AnyRecord>((draft?.lanes || []).map((lane: AnyRecord) => [String(lane.id), lane])),
    [draft]
  );
  const laneGroups = useMemo(() => buildWorkflowLaneGroups(draft), [draft]);
  const loopRouteY = useMemo(
    () => draft?.nodes?.length ? Math.min(...draft.nodes.map((node: AnyRecord) => node.positionY)) - 80 : 0,
    [draft]
  );
  const selectedNode: AnyRecord | null = selectedNodeId ? nodeMap.get(selectedNodeId) || null : null;
  const selectedEdge: AnyRecord | null = selectedEdgeId ? (draft?.edges || []).find((edge: AnyRecord) => edge.id === selectedEdgeId) || null : null;
  const canvasViewportStyle = useMemo(
    () => workflowCanvasViewportStyle(viewportSize.width, viewportSize.height),
    [viewportSize.height, viewportSize.width]
  );
  const boardSurfaceStyle = useMemo(
    () => workflowBoardSurfaceStyle(draft),
    [draft]
  );

  function applyViewTransform(next: { x: number; y: number; scale: number }) {
    viewTransformRef.current = next;
    setViewTransform(next);
  }

  function zoomCanvas(factor: number) {
    const el = scrollerRef.current;
    if (!el) return;
    const current = viewTransformRef.current;
    const scale = clamp(current.scale * factor, 0.12, 4);
    const ratio = scale / current.scale;
    applyViewTransform({
      x: el.clientWidth / 2 - (el.clientWidth / 2 - current.x) * ratio,
      y: el.clientHeight / 2 - (el.clientHeight / 2 - current.y) * ratio,
      scale
    });
  }

  function inspectSelection() {
    setInspectorTab("details");
    setInspectorOpen(true);
    setLibraryPanel(null);
  }

  function setDraftAndMark(next: AnyRecord, dirty = true) {
    draftRef.current = next;
    setDraft(next);
    if (dirty) {
      setIsDirty(true);
      setStatusText("Unsaved changes");
    }
  }

  function fitToView(nodes: AnyRecord[]) {
    const el = scrollerRef.current;
    if (!el || nodes.length === 0) return;
    const rect = el.getBoundingClientRect();
    let minX = Infinity;
    let minY = Infinity;
    let maxX = -Infinity;
    let maxY = -Infinity;
    for (const node of nodes) {
      minX = Math.min(minX, node.positionX);
      minY = Math.min(minY, node.positionY);
      maxX = Math.max(maxX, node.positionX + NODE_WIDTH);
      maxY = Math.max(maxY, node.positionY + NODE_HEIGHT);
    }
    const pad = 120;
    const width = maxX - minX + pad * 2;
    const height = maxY - minY + pad * 2;
    const scale = Math.min(rect.width / width, rect.height / height, 1.4);
    applyViewTransform({
      x: (rect.width - width * scale) / 2 - (minX - pad) * scale,
      y: (rect.height - height * scale) / 2 - (minY - pad) * scale,
      scale
    });
  }

  async function load(options: { keepSelection?: boolean; silent?: boolean } = {}) {
    if (!options.silent) setStatusText("Loading workflows...");
    const [nextWorkflows, nextRuns, nextActions, nextAgents] = await Promise.all([
      fetchProjectWorkflows(project.id),
      fetchProjectWorkflowRuns(project.id),
      fetchProjectWorkflowActions(project.id),
      fetchAgents()
    ]);
    const workflowList = nextWorkflows || [];
    const runList = nextRuns || [];
    setWorkflows(workflowList);
    setRuns(runList);
    setActions(nextActions || []);
    setAgents(Array.isArray(nextAgents) ? nextAgents : []);

    const routeRun = routeWorkflowRunId
      ? runList.find((run) => String(run?.id || "") === String(routeWorkflowRunId))
      : null;
    const targetWorkflowId = routeRun?.workflowId || routeWorkflowId || (options.keepSelection ? selectedWorkflowId : "");
    const targetWorkflow = targetWorkflowId
      ? workflowList.find((workflow) => String(workflow?.id || "") === String(targetWorkflowId))
      : null;
    const nextSelected = targetWorkflow || workflowList.find((workflow) => String(workflow?.id || "") === selectedWorkflowId) || workflowList[0] || null;

    if (routeRun?.id) {
      setSelectedRunId(String(routeRun.id));
    } else if (!routeWorkflowRunId && !options.keepSelection) {
      setSelectedRunId("");
    }
    if (nextSelected?.id) {
      setSelectedWorkflowId(String(nextSelected.id));
      const normalized = normalizeWorkflow(nextSelected);
      draftRef.current = normalized;
      setDraft(normalized);
      setIsDirty(false);
      setSelectedNodeId(null);
      setSelectedEdgeId(null);
      requestAnimationFrame(() => fitToView(normalized.nodes));
    } else {
      draftRef.current = null;
      setDraft(null);
      setIsDirty(false);
    }
    setStatusText(`Loaded ${workflowList.length} workflows`);
  }

  useEffect(() => {
    void load();
  }, [project.id, routeWorkflowId, routeWorkflowRunId]);

  useEffect(() => {
    if (!selectedWorkflow) return;
    const normalized = normalizeWorkflow(selectedWorkflow);
    draftRef.current = normalized;
    setDraft(normalized);
    setIsDirty(false);
    setSelectedNodeId(null);
    setSelectedEdgeId(null);
    requestAnimationFrame(() => fitToView(normalized.nodes));
  }, [selectedWorkflowId]);

  useEffect(() => {
    if (!selectedRunId) {
      setSelectedRunDetail(null);
      return;
    }
    let isCancelled = false;
    let timer: number | undefined;
    async function refreshRun() {
      let status: string | undefined;
      try {
        const [detail, pending] = await Promise.all([
          fetchProjectWorkflowRun(project.id, selectedRunId), fetchProjectWorkflowActions(project.id)
        ]);
        if (isCancelled) return;
        const run = (detail as AnyRecord | null)?.run as AnyRecord | undefined;
        if (detail && run) {
          setSelectedRunDetail(detail);
          setRuns((previous) => previous.map((entry) => entry.id === run.id ? run : entry));
        }
        if (pending) setActions(pending);
        status = run?.status;
      } catch {
        // Retain the last snapshot and retry while the server is restarting.
      }
      if (!isCancelled && (!status || !["completed", "failed", "cancelled", "blocked"].includes(status))) {
        timer = window.setTimeout(refreshRun, status && ["waiting_for_agent", "waiting_for_human", "waiting_for_workflow"].includes(status) ? 2000 : 1000);
      }
    }
    void refreshRun();
    return () => {
      isCancelled = true;
      window.clearTimeout(timer);
    };
  }, [project.id, selectedRunId]);

  useEffect(() => {
    function handleResize() {
      setViewportSize({ width: window.innerWidth, height: window.innerHeight });
    }
    window.addEventListener("resize", handleResize);
    return () => window.removeEventListener("resize", handleResize);
  }, []);

  useEffect(() => {
    if (!selectedNode) {
      setNodeConfigText("{}");
      setAgentSearch("");
      return;
    }
    setNodeConfigText(JSON.stringify(selectedNode.config || {}, null, 2));
    const agentId = asString(selectedNode.config?.agentId);
    const agent = agents.find((entry) => String(entry.id) === agentId);
    setAgentSearch(agent?.displayName || agentId || "");
  }, [selectedNodeId, selectedNode?.id]);

  useEffect(() => {
    const el = scrollerRef.current;
    if (!el) return undefined;
    function handleWheel(event: WheelEvent) {
      event.preventDefault();
      const rect = el.getBoundingClientRect();
      const vt = viewTransformRef.current;
      const deltaX = normalizeWheelDelta(event.deltaX, event.deltaMode, rect.width);
      const deltaY = normalizeWheelDelta(event.deltaY, event.deltaMode, rect.height);
      const shouldZoom = event.shiftKey || event.ctrlKey;
      if (!shouldZoom) {
        applyViewTransform({ ...vt, x: vt.x - deltaX, y: vt.y - deltaY });
        return;
      }
      const dominantDelta = Math.abs(deltaY) >= Math.abs(deltaX) ? deltaY : deltaX;
      if (dominantDelta === 0) return;
      const mx = event.clientX - rect.left;
      const my = event.clientY - rect.top;
      const nextScale = clamp(vt.scale * (dominantDelta < 0 ? 1.08 : 1 / 1.08), 0.12, 4);
      const ratio = nextScale / vt.scale;
      applyViewTransform({
        x: mx - (mx - vt.x) * ratio,
        y: my - (my - vt.y) * ratio,
        scale: nextScale
      });
    }
    el.addEventListener("wheel", handleWheel, { passive: false });
    return () => el.removeEventListener("wheel", handleWheel);
  }, []);

  useEffect(() => {
    if (!panState) return undefined;
    function handlePointerMove(event: PointerEvent) {
      applyViewTransform({
        ...viewTransformRef.current,
        x: panState.originX + (event.clientX - panState.originClientX),
        y: panState.originY + (event.clientY - panState.originClientY)
      });
    }
    function handlePointerUp() {
      setPanState(null);
    }
    window.addEventListener("pointermove", handlePointerMove);
    window.addEventListener("pointerup", handlePointerUp);
    return () => {
      window.removeEventListener("pointermove", handlePointerMove);
      window.removeEventListener("pointerup", handlePointerUp);
    };
  }, [panState]);

  useEffect(() => {
    if (!dragState) return undefined;
    function handlePointerMove(event: PointerEvent) {
      const scale = viewTransformRef.current.scale;
      const deltaX = (event.clientX - dragState.originClientX) / scale;
      const deltaY = (event.clientY - dragState.originClientY) / scale;
      dragMovedRef.current = true;
      const current = draftRef.current;
      if (!current) return;
      setDraftAndMark({
        ...current,
        nodes: current.nodes.map((node: AnyRecord) =>
          node.id === dragState.nodeId
            ? { ...node, positionX: dragState.originNodeX + deltaX, positionY: dragState.originNodeY + deltaY }
            : node
        )
      });
    }
    function handlePointerUp() {
      dragMovedRef.current = false;
      setDragState(null);
    }
    window.addEventListener("pointermove", handlePointerMove);
    window.addEventListener("pointerup", handlePointerUp);
    return () => {
      window.removeEventListener("pointermove", handlePointerMove);
      window.removeEventListener("pointerup", handlePointerUp);
    };
  }, [dragState]);

  useEffect(() => {
    if (!portDrag) return undefined;
    function handlePointerMove(event: PointerEvent) {
      const pointer = toBoardCoordinates(event.clientX, event.clientY);
      setPortDrag((previous) => previous ? { ...previous, pointerX: pointer.x, pointerY: pointer.y } : previous);
    }
    function handlePointerUp() {
      setPortDrag(null);
      setHoverInputPort(null);
    }
    window.addEventListener("pointermove", handlePointerMove);
    window.addEventListener("pointerup", handlePointerUp);
    return () => {
      window.removeEventListener("pointermove", handlePointerMove);
      window.removeEventListener("pointerup", handlePointerUp);
    };
  }, [portDrag]);

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setLibraryPanel(null);
        setInspectorOpen(false);
        setHelpOpen(false);
        setIsExpanded(false);
        setPortDrag(null);
        setSelectedNodeId(null);
        setSelectedEdgeId(null);
        return;
      }
      if ((event.key !== "Backspace" && event.key !== "Delete") || isTypingTarget(event.target) || isBusy) return;
      if (selectedEdgeId) {
        event.preventDefault();
        deleteSelectedEdge();
      } else if (selectedNodeId) {
        event.preventDefault();
        deleteSelectedNode();
      }
    }
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [selectedNodeId, selectedEdgeId, isBusy]);

  function toBoardCoordinates(clientX: number, clientY: number) {
    const el = scrollerRef.current;
    if (!el) return { x: 0, y: 0 };
    const rect = el.getBoundingClientRect();
    const vt = viewTransformRef.current;
    return {
      x: (clientX - rect.left - vt.x) / vt.scale,
      y: (clientY - rect.top - vt.y) / vt.scale
    };
  }

  function ensureLane(current: AnyRecord, preset: AnyRecord) {
    const existing = current.lanes.find((lane: AnyRecord) => lane.title === preset.laneTitle || lane.kind === preset.laneKind);
    if (existing) return { laneId: existing.id, lanes: current.lanes };
    const existingIds = new Set<string>(current.lanes.map((lane: AnyRecord) => String(lane.id)));
    const laneId = uniqueId(slugify(preset.laneTitle) || preset.laneKind, existingIds);
    return {
      laneId,
      lanes: [...current.lanes, { id: laneId, title: preset.laneTitle, kind: preset.laneKind }]
    };
  }

  function addBlock(preset: AnyRecord) {
    const current = draftRef.current || normalizeWorkflow({ name: "Untitled workflow", lanes: [], nodes: [], edges: [] });
    const point = toBoardCoordinates(
      (scrollerRef.current?.getBoundingClientRect().left || 0) + (scrollerRef.current?.clientWidth || 800) / 2,
      (scrollerRef.current?.getBoundingClientRect().top || 0) + (scrollerRef.current?.clientHeight || 500) / 2
    );
    const ids = new Set<string>(current.nodes.map((node: AnyRecord) => String(node.id)));
    const nodeId = uniqueId(slugify(preset.title) || preset.id, ids);
    const lane = ensureLane(current, preset);
    const next = {
      ...current,
      lanes: lane.lanes,
      nodes: [
        ...current.nodes,
        {
          id: nodeId,
          type: preset.type,
          title: preset.title,
          laneId: lane.laneId,
          config: { ...preset.config },
          positionX: Math.round(point.x - NODE_WIDTH / 2),
          positionY: Math.round(point.y - NODE_HEIGHT / 2)
        }
      ]
    };
    setDraftAndMark(next);
    setSelectedNodeId(nodeId);
    setSelectedEdgeId(null);
    inspectSelection();
  }

  function createEdge(sourceNodeId: string, sourceSocket: string, targetNodeId: string, targetSocket: string) {
    const current = draftRef.current;
    if (!current || sourceNodeId === targetNodeId) return;
    const ids = new Set<string>(current.edges.map((edge: AnyRecord) => String(edge.id)));
    const edgeId = uniqueId(`edge-${slugify(sourceNodeId)}-${slugify(targetNodeId)}`, ids);
    setDraftAndMark({
      ...current,
      edges: [
        ...current.edges,
        {
          id: edgeId,
          sourceNodeId,
          targetNodeId,
          sourceSocket,
          targetSocket,
          conditionKey: sourceSocket === "true" || sourceSocket === "false" ? sourceSocket : ""
        }
      ]
    });
    setSelectedEdgeId(edgeId);
    setSelectedNodeId(null);
  }

  function updateSelectedNode(patch: AnyRecord) {
    const current = draftRef.current;
    if (!current || !selectedNode) return;
    setDraftAndMark({
      ...current,
      nodes: current.nodes.map((node: AnyRecord) => node.id === selectedNode.id ? { ...node, ...patch } : node)
    });
  }

  function updateSelectedNodeConfig(key: string, value: unknown) {
    if (!selectedNode) return;
    const config = { ...(selectedNode.config || {}), [key]: value };
    setNodeConfigText(JSON.stringify(config, null, 2));
    updateSelectedNode({ config });
  }

  function updateSelectedEdge(patch: AnyRecord) {
    const current = draftRef.current;
    if (!current || !selectedEdge) return;
    setDraftAndMark({
      ...current,
      edges: current.edges.map((edge: AnyRecord) => edge.id === selectedEdge.id ? { ...edge, ...patch } : edge)
    });
  }

  function deleteSelectedNode() {
    const current = draftRef.current;
    if (!current || !selectedNodeId) return;
    setDraftAndMark({
      ...current,
      nodes: current.nodes.filter((node: AnyRecord) => node.id !== selectedNodeId),
      edges: current.edges.filter((edge: AnyRecord) => edge.sourceNodeId !== selectedNodeId && edge.targetNodeId !== selectedNodeId)
    });
    setSelectedNodeId(null);
    setSelectedEdgeId(null);
  }

  function deleteSelectedEdge() {
    const current = draftRef.current;
    if (!current || !selectedEdgeId) return;
    setDraftAndMark({
      ...current,
      edges: current.edges.filter((edge: AnyRecord) => edge.id !== selectedEdgeId)
    });
    setSelectedEdgeId(null);
  }

  async function createStarterWorkflow() {
    setIsBusy(true);
    try {
      const created = await createProjectWorkflow(project.id, STARTER_WORKFLOW);
      await load({ keepSelection: true });
      if (created?.id) setSelectedWorkflowId(String(created.id));
      else setStatusText("Failed to create starter workflow");
    } finally {
      setIsBusy(false);
    }
  }

  async function createBlankWorkflow() {
    setIsBusy(true);
    try {
      const created = await createProjectWorkflow(project.id, createBlankWorkflowRequest(workflows.length + 1));
      await load({ keepSelection: true });
      if (created?.id) setSelectedWorkflowId(String(created.id));
      else setStatusText("Failed to create workflow");
    } finally {
      setIsBusy(false);
    }
  }

  async function saveWorkflow() {
    if (contractError || nodeConfigError || blockError) { setStatusText(contractError || nodeConfigError || blockError); return; }
    if (!draft?.id) return;
    setIsBusy(true);
    try {
      const updated = await updateProjectWorkflow(project.id, String(draft.id), workflowPayload(draft));
      if (updated) {
        setStatusText("Workflow saved");
        setIsDirty(false);
        await load({ keepSelection: true, silent: true });
        setSelectedWorkflowId(String(updated.id));
      } else {
        setStatusText("Save failed");
      }
    } finally {
      setIsBusy(false);
    }
  }

  async function startRun(payload: AnyRecord) {
    if (contractError || nodeConfigError || blockError) { setStatusText(contractError || nodeConfigError || blockError); return; }
    if (!draft?.id) return;
    if (isDirty) {
      await saveWorkflow();
    }
    setIsBusy(true);
    try {
      const detail = await startProjectWorkflowRun(project.id, String(draft.id), {
        ...payload,
        startedBy: "human:admin",
        background: true
      });
      await load({ keepSelection: true, silent: true });
      const run = (detail?.run || detail) as AnyRecord | null;
      if (!run?.id) throw new Error("Workflow did not start. Check the graph, task and environment.");
      if (run?.id) {
        setSelectedRunId(String(run.id));
        setInspectorTab("activity");
        setInspectorOpen(true);
        setSelectedRunDetail(detail);
      }
      setStatusText("Workflow run started");
    } catch (error) {
      setStatusText(error instanceof Error ? error.message : "Workflow did not start.");
    } finally {
      setIsBusy(false);
    }
  }

  async function deleteSelectedWorkflow() {
    if (!draft?.id) return;
    const workflowId = String(draft.id);
    setIsBusy(true);
    try {
      const didDelete = await deleteProjectWorkflow(project.id, workflowId);
      if (didDelete) {
        setSelectedWorkflowId(selectWorkflowAfterDelete(workflows, workflowId));
        setSelectedRunId("");
        await load();
      }
    } finally {
      setIsBusy(false);
    }
  }

  async function resolveAction(action: AnyRecord, decision: string) {
    setIsBusy(true);
    try {
      await resolveProjectWorkflowAction(project.id, String(action.id), {
        decision,
        background: true,
        comment: actionResponses[String(action.id)] || null,
        resolvedBy: "human:admin"
      });
      await load({ keepSelection: true, silent: true });
      if (selectedRunId) {
        const detail = await fetchProjectWorkflowRun(project.id, selectedRunId);
        setSelectedRunDetail(detail);
      }
    } finally {
      setIsBusy(false);
    }
  }

  function onNodePointerDown(event: React.PointerEvent, node: AnyRecord) {
    const target = event.target as HTMLElement;
    if (target.closest(".project-workflow-socket")) return;
    if (event.button !== 0) return;
    setSelectedNodeId(node.id);
    setSelectedEdgeId(null);
    dragMovedRef.current = false;
    setDragState({
      nodeId: node.id,
      originClientX: event.clientX,
      originClientY: event.clientY,
      originNodeX: node.positionX,
      originNodeY: node.positionY
    });
  }

  function onSocketPointerDown(event: React.PointerEvent, node: AnyRecord, socket: string) {
    event.preventDefault();
    event.stopPropagation();
    const point = socketPoint(node, socket);
    setPortDrag({
      sourceNodeId: node.id,
      sourceSocket: socket,
      pointerX: point.x,
      pointerY: point.y
    });
    setHoverInputPort(null);
    setSelectedNodeId(node.id);
    setSelectedEdgeId(null);
  }

  function onSocketPointerUp(event: React.PointerEvent, node: AnyRecord, socket: string) {
    if (!portDrag) return;
    event.preventDefault();
    event.stopPropagation();
    const sourceNodeId = portDrag.sourceNodeId;
    const sourceSocket = portDrag.sourceSocket;
    setPortDrag(null);
    setHoverInputPort(null);
    if (sourceNodeId === node.id && sourceSocket === socket) return;
    createEdge(sourceNodeId, sourceSocket, node.id, socket);
  }

  const previewLine = useMemo(() => {
    if (!portDrag) return null;
    const sourceNode = nodeMap.get(portDrag.sourceNodeId);
    if (!sourceNode) return null;
    const source = socketPoint(sourceNode, portDrag.sourceSocket, "output");
    const targetSocket = hoverInputPort?.targetSocket ? normalizeSocket(hoverInputPort.targetSocket, oppositeSocket(portDrag.sourceSocket)) : oppositeSocket(portDrag.sourceSocket);
    const target = hoverInputPort?.targetNodeId && nodeMap.get(hoverInputPort.targetNodeId)
      ? socketPoint(nodeMap.get(hoverInputPort.targetNodeId), targetSocket, "input")
      : { x: portDrag.pointerX, y: portDrag.pointerY };
    return { source, target, sourceSocket: portDrag.sourceSocket, targetSocket };
  }, [portDrag, hoverInputPort, nodeMap]);

  const filteredAgents = useMemo(() => {
    const query = agentSearch.trim().toLowerCase();
    return agents.filter((agent) => {
      const label = `${agent.displayName || ""} ${agent.id || ""}`.toLowerCase();
      return !query || label.includes(query);
    }).slice(0, 8);
  }, [agents, agentSearch]);
  const selectedNodeBlockKind = asString(selectedNode?.config?.blockKind || selectedNode?.config?.block_kind);
  const selectedNodeTextKey = selectedNode ? nodePrimaryTextKey(selectedNode) : "prompt";
  const selectedNodeTextValue = selectedNode ? rawString(selectedNode.config?.[selectedNodeTextKey]) : "";
  const selectedNodeReferences = useMemo(
    () => selectedNode ? workflowInputNodeReferences(draft || {}, selectedNode.id) : [],
    [draft, selectedNode?.id]
  );
  const availableInputNodeIds = useMemo(
    () => new Set<string>(selectedNodeReferences.map((entry: AnyRecord) => String(entry.nodeId))),
    [selectedNodeReferences]
  );

  return (
    <section className={`project-tab-layout project-workflows-shell ${isExpanded ? "is-expanded" : ""}`}>
      <header className="project-workflows-toolbar">
        <div className="project-workflows-heading">
          <button type="button" className="project-workflows-title" aria-label="Choose workflow" aria-expanded={libraryPanel === "definitions"} onClick={() => { setLibraryPanel(libraryPanel === "definitions" ? null : "definitions"); setInspectorOpen(false); }}>
            <span className="material-symbols-rounded" aria-hidden="true">account_tree</span>
            <strong>{draft?.name || "Workflows"}</strong>
            <span className="material-symbols-rounded" aria-hidden="true">expand_more</span>
          </button>
          {draft ? <span className="project-workflows-version">v{draft.version}</span> : null}
        </div>
        <div className="project-workflows-actions">
          <button type="button" className="agents-secondary-button project-workflows-history" onClick={() => { setInspectorTab("activity"); setInspectorOpen(true); setLibraryPanel(null); }}>
            <span className="material-symbols-rounded" aria-hidden="true">history</span>
            Activity{actions.length > 0 ? <span className="project-workflows-action-count">{actions.length}</span> : null}
          </button>
          <button type="button" className="agents-secondary-button" onClick={saveWorkflow} disabled={isBusy || !draft || !isDirty || Boolean(contractError || nodeConfigError || blockError)}>
            <span className="material-symbols-rounded" aria-hidden="true">save</span>
            Save
          </button>
          <button type="button" className="agents-create-inline" onClick={() => { setInspectorTab("run"); setInspectorOpen(true); setLibraryPanel(null); }} disabled={isBusy || !draft || Boolean(contractError || nodeConfigError || blockError)}>
            <span className="material-symbols-rounded" aria-hidden="true">play_arrow</span>
            Run
          </button>
          <button type="button" className="project-workflows-icon-button" aria-label={isExpanded ? "Collapse editor" : "Expand editor"} onClick={() => setIsExpanded(!isExpanded)}>
            <span className="material-symbols-rounded" aria-hidden="true">{isExpanded ? "close_fullscreen" : "open_in_full"}</span>
          </button>
        </div>
      </header>

      <div className="project-workflows-grid">
        <aside className="project-workflows-list" aria-label={libraryPanel === "blocks" ? "Add workflow step" : "Workflow definitions"} hidden={!libraryPanel}>
          <header className="project-workflows-panel-header">
            <strong>{libraryPanel === "blocks" ? "Add a step" : "Workflows"}</strong>
            <button type="button" className="project-workflows-icon-button" aria-label="Close library" onClick={() => setLibraryPanel(null)}><span className="material-symbols-rounded" aria-hidden="true">close</span></button>
          </header>
          {libraryPanel === "definitions" ? <>
            <div className="project-workflows-library-actions">
              <button type="button" onClick={createBlankWorkflow} disabled={isBusy}><span className="material-symbols-rounded" aria-hidden="true">add</span>New workflow</button>
              <button type="button" onClick={createStarterWorkflow} disabled={isBusy}>Use starter</button>
            </div>
          {workflows.length === 0 ? (
            <p className="placeholder-text">No workflows yet.</p>
          ) : workflows.map((workflow) => (
            <button
              key={workflow.id}
              type="button"
              className={`project-workflow-row ${draft?.id === workflow.id ? "active" : ""}`}
              onClick={() => { setSelectedWorkflowId(String(workflow.id)); setLibraryPanel(null); }}
            >
              <span>{workflow.name}</span>
              <small>v{workflow.version}</small>
            </button>
          ))}

          </> : null}
          {libraryPanel === "blocks" ? <>
          <div className="project-workflows-block-palette">
            {BLOCK_PRESETS.map((preset) => (
              <button key={preset.id} type="button" onClick={() => addBlock(preset)} disabled={!draft}>
                <span className="material-symbols-rounded">{preset.icon}</span>
                <span>
                  <strong>{preset.title}</strong>
                  <small>{preset.description}</small>
                </span>
              </button>
            ))}
          </div>
          </> : null}
        </aside>

        <section className="project-workflows-board-pane" aria-label="Workflow board" style={canvasViewportStyle}>
          <div
            className={`project-workflows-board-scroller ${panState ? "is-panning" : ""}`}
            ref={scrollerRef}
            style={{ backgroundPosition: `${viewTransform.x}px ${viewTransform.y}px`, backgroundSize: `${28 * viewTransform.scale}px ${28 * viewTransform.scale}px` }}
            onPointerDown={(event) => {
              if (event.target !== scrollerRef.current) return;
              setSelectedNodeId(null);
              setSelectedEdgeId(null);
              setInspectorOpen(false);
              setLibraryPanel(null);
              setHelpOpen(false);
              if (event.button === 0) {
                const vt = viewTransformRef.current;
                setPanState({
                  originClientX: event.clientX,
                  originClientY: event.clientY,
                  originX: vt.x,
                  originY: vt.y
                });
              }
            }}
          >
            <div
              className="project-workflows-board"
              style={{
                ...boardSurfaceStyle,
                transform: `translate(${viewTransform.x}px, ${viewTransform.y}px) scale(${viewTransform.scale})`,
                transformOrigin: "0 0"
              }}
            >
              {draft ? (
                <>
                  {laneGroups.map((group: AnyRecord) => (
                    <div key={group.id} className="project-workflow-lane-group" style={{ left: group.x, top: group.y, width: group.width, height: group.height }}>
                      <span>{group.title}</span>
                    </div>
                  ))}
                  <svg className="project-workflows-links-layer">
                    <defs>
                      <marker id={arrowMarkerId} viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 1 1 L 9 5 L 1 9 z" fill="#6b9aeb" /></marker>
                      <marker id={`${arrowMarkerId}-approval`} viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 1 1 L 9 5 L 1 9 z" fill="#d98e69" /></marker>
                    </defs>
                    {draft.edges.map((edge: AnyRecord) => {
                      const sourceNode = nodeMap.get(edge.sourceNodeId);
                      const targetNode = nodeMap.get(edge.targetNodeId);
                      if (!sourceNode || !targetNode) return null;
                      const sourceSocket = normalizeSocket(edge.sourceSocket, "right");
                      const targetSocket = normalizeSocket(edge.targetSocket, "left");
                      const source = socketPoint(sourceNode, sourceSocket, "output");
                      const target = socketPoint(targetNode, targetSocket, "input");
                      const connection = buildWorkflowConnection(source, target, sourceSocket, targetSocket, { loopY: loopRouteY });
                      const { path } = connection;
                      const conditionLabel = edge.condition ? `${edge.condition.path} = ${JSON.stringify(edge.condition.equals)}` : edge.conditionKey;
                      const labelWidth = Math.min(220, Math.max(56, asString(conditionLabel).length * 7 + 24));
                      const isSelected = selectedEdgeId === edge.id;
                      const isApproval = edge.conditionKey === "approved";
                      const selectEdge = () => { setSelectedEdgeId(edge.id); setSelectedNodeId(null); inspectSelection(); };
                      return (
                        <g key={edge.id}>
                          <path
                            d={path}
                            className="project-workflow-link-hit"
                            onClick={(event) => {
                              event.stopPropagation();
                              selectEdge();
                            }}
                          />
                          <path d={path} className={`project-workflow-link ${isSelected ? "selected" : ""} ${isApproval ? "approval" : ""}`} markerEnd={`url(#${arrowMarkerId}${isApproval ? "-approval" : ""})`} />
                          {activeNodeIds.has(edge.sourceNodeId) ? <path d={path} className="project-workflow-link-flow" /> : null}
                          {conditionLabel ? (
                            <foreignObject x={connection.labelX - labelWidth / 2} y={connection.labelY - 13} width={labelWidth} height={26} className="project-workflow-edge-label">
                              <button type="button" title={conditionLabel} aria-label={`Edit transition ${conditionLabel}`} onClick={(event) => { event.stopPropagation(); selectEdge(); }}>{conditionLabel}</button>
                            </foreignObject>
                          ) : null}
                        </g>
                      );
                    })}

                    {previewLine ? (
                      <path
                        d={buildWorkflowConnection(previewLine.source, previewLine.target, previewLine.sourceSocket, previewLine.targetSocket).path}
                        className="project-workflow-link preview"
                      />
                    ) : null}
                  </svg>

                  {draft.nodes.map((node: AnyRecord) => {
                    const lane = laneMap.get(String(node.laneId || ""));
                    const blockKind = asString(node.config?.blockKind || node.config?.block_kind, formatStatus(node.type));
                    const isSelected = selectedNodeId === node.id;
                    const isAvailableInput = selectedNodeId && availableInputNodeIds.has(String(node.id));
                    const isActive = activeNodeIds.has(String(node.id));
                    const stepStatus = stepStatusByNode.get(String(node.id));
                    return (
                      <article
                        className={`project-workflow-node ${formatStatus(node.type).replace(/\s+/g, "-")} ${isSelected ? "selected" : ""} ${isAvailableInput ? "available-input" : ""} ${isActive ? "active" : ""} ${stepStatus ? `step-${stepStatus}` : ""}`}
                        key={node.id}
                        tabIndex={0}
                        aria-label={`Edit ${node.title}`}
                        onKeyDown={(event) => {
                          if (event.target !== event.currentTarget || (event.key !== "Enter" && event.key !== " ")) return;
                          event.preventDefault();
                          setSelectedNodeId(node.id);
                          setSelectedEdgeId(null);
                          inspectSelection();
                        }}
                        style={{ left: node.positionX, top: node.positionY }}
                        onPointerDown={(event) => onNodePointerDown(event, node)}
                        onClick={(event) => {
                          event.stopPropagation();
                          setSelectedNodeId(node.id);
                          setSelectedEdgeId(null);
                          inspectSelection();
                        }}
                      >
                        {workflowNodePorts(node).map((port: AnyRecord) => {
                          const point = socketPoint({ ...node, positionX: 0, positionY: 0 }, port.id, port.direction);
                          const isHover = hoverInputPort?.targetNodeId === node.id && hoverInputPort?.targetSocket === port.id;
                          const isSource = portDrag?.sourceNodeId === node.id && portDrag?.sourceSocket === port.id;
                          return (
                            <button
                              key={port.id}
                              type="button"
                              className={`project-workflow-socket side-${port.socket} port-${port.direction} ${isSource ? "source" : ""} ${isHover ? "hover" : ""}`}
                              style={{ left: point.x, top: point.y }}
                              onPointerDown={(event) => {
                                if (port.direction === "output") {
                                  onSocketPointerDown(event, node, port.id);
                                  return;
                                }
                                event.stopPropagation();
                              }}
                              onPointerEnter={() => {
                                if (portDrag && port.direction === "input") setHoverInputPort({ targetNodeId: node.id, targetSocket: port.id });
                              }}
                              onPointerLeave={() => {
                                if (hoverInputPort?.targetNodeId === node.id && hoverInputPort?.targetSocket === port.id) setHoverInputPort(null);
                              }}
                              onPointerUp={(event) => onSocketPointerUp(event, node, port.id)}
                              title={`${port.direction}: ${port.label}`}
                              aria-label={`${port.direction}: ${port.label}`}
                            />
                          );
                        })}
                        <span className="material-symbols-rounded">{workflowNodeIcon(node.type, node.config)}</span>
                        <div>
                          <strong>{node.title}</strong>
                          <small>{blockKind.replace(/_/g, " ")}</small>
                          <em>{stepStatus || (agents.find((agent) => agent.id === node.config?.agentId)?.displayName || lane?.title || node.laneId || "Unassigned")}</em>
                        </div>
                      </article>
                    );
                  })}
                </>
              ) : (
                <div className="project-workflows-empty-canvas">
                  <span className="material-symbols-rounded">account_tree</span>
                  <p>Create a workflow to begin.</p>
                </div>
              )}
            </div>
          </div>

          <nav className="project-workflows-fast-actions" aria-label="Canvas controls" onPointerDown={(event) => event.stopPropagation()}>
            <button type="button" aria-label="Add step" title="Add step" aria-expanded={libraryPanel === "blocks"} onClick={() => { setLibraryPanel(libraryPanel === "blocks" ? null : "blocks"); setInspectorOpen(false); }} disabled={!draft}><span className="material-symbols-rounded" aria-hidden="true">add</span></button>
            <button type="button" aria-label="Workflow settings" title="Workflow settings" aria-expanded={inspectorOpen && inspectorTab === "details" && !selectedNodeId && !selectedEdgeId} onClick={() => { setSelectedNodeId(null); setSelectedEdgeId(null); setInspectorTab("details"); setInspectorOpen(!inspectorOpen || inspectorTab !== "details" || Boolean(selectedNodeId || selectedEdgeId)); setLibraryPanel(null); }} disabled={!draft}><span className="material-symbols-rounded" aria-hidden="true">settings</span></button>
            <span className="project-workflows-control-divider" />
            <button type="button" aria-label="Fit workflow to view" title="Fit workflow to view" onClick={() => draft?.nodes?.length && fitToView(draft.nodes)} disabled={!draft?.nodes?.length}><span className="material-symbols-rounded" aria-hidden="true">center_focus_strong</span></button>
            <button type="button" aria-label="Zoom in" title="Zoom in" onClick={() => zoomCanvas(1.2)}><span className="material-symbols-rounded" aria-hidden="true">zoom_in</span></button>
            <button type="button" aria-label="Zoom out" title="Zoom out" onClick={() => zoomCanvas(1 / 1.2)}><span className="material-symbols-rounded" aria-hidden="true">zoom_out</span></button>
            <button type="button" aria-label="Reset zoom to 100%" title="Reset zoom to 100%" onClick={() => zoomCanvas(1 / viewTransformRef.current.scale)} className="project-workflows-zoom-value">{Math.round(viewTransform.scale * 100)}%</button>
          </nav>
          <button type="button" className="project-workflows-help-button project-workflows-icon-button" aria-label="Canvas help" aria-expanded={helpOpen} onClick={() => setHelpOpen(!helpOpen)}><span className="material-symbols-rounded" aria-hidden="true">help</span></button>
          {helpOpen ? <div className="project-workflows-help" role="note"><strong>Make room for your process.</strong><p>Drag the canvas to pan. Drag a node to move it.</p><p>Connect an output handle to an input handle.</p><p>Wheel to pan · Ctrl/Shift + wheel to zoom.</p><p>Enter to inspect · Delete to remove · Esc to close.</p></div> : null}

          <div className={`project-workflows-board-status ${isDirty ? "is-dirty" : ""}`.trim()}>
            {isBusy ? "Working..." : isDirty ? "Unsaved changes" : statusText}
          </div>
        </section>

        <aside className="project-workflows-inspector" aria-label="Workflow inspector" hidden={!inspectorOpen}>
          <header className="project-workflows-panel-header">
            <strong>{inspectorTab === "activity" ? "Run activity" : inspectorTab === "run" ? "Start workflow" : selectedNode ? "Step settings" : selectedEdge ? "Transition" : "Workflow settings"}</strong>
            <button type="button" className="project-workflows-icon-button" aria-label="Close inspector" onClick={() => setInspectorOpen(false)}><span className="material-symbols-rounded" aria-hidden="true">close</span></button>
          </header>
          <section hidden={inspectorTab !== "details"}>
            {contractError ? <p role="alert">{contractError}</p> : null}
            {selectedNode ? (
              <article className="project-workflow-editor-card">
                <label>
                  Title
                  <input value={selectedNode.title} onChange={(event) => updateSelectedNode({ title: event.target.value })} />
                </label>
                <label>
                  Node ID
                  <input value={selectedNode.id} disabled />
                </label>
                <label>
                  Type
                  <input value={formatStatus(selectedNode.type)} disabled />
                </label>
                <label>
                  Lane
                  <div className="project-workflow-choice-grid">
                    {draft?.lanes.map((lane: AnyRecord) => (
                      <button
                        key={lane.id}
                        type="button"
                        className={selectedNode.laneId === lane.id ? "active" : ""}
                        onClick={() => updateSelectedNode({ laneId: lane.id })}
                      >
                        {lane.title}
                      </button>
                    ))}
                  </div>
                </label>
                {selectedNode.type === "agent_step" ? (
                  <label>
                    Agent
                    <div className="actor-team-search-wrap" ref={agentSearchRef}>
                      <input
                        className="actor-team-search"
                        value={agentSearch}
                        onChange={(event) => {
                          setAgentSearch(event.target.value);
                          setAgentDropdownOpen(true);
                        }}
                        onFocus={() => setAgentDropdownOpen(true)}
                        placeholder="Search agent"
                      />
                      {agentDropdownOpen ? (
                        <ul className="actor-team-dropdown">
                          {filteredAgents.length === 0 ? (
                            <li className="actor-team-dropdown-empty">No agents</li>
                          ) : filteredAgents.map((agent) => (
                            <li
                              key={agent.id}
                              className={`actor-team-dropdown-item ${selectedNode.config?.agentId === agent.id ? "selected" : ""}`}
                              onMouseDown={(event) => {
                                event.preventDefault();
                                updateSelectedNodeConfig("agentId", agent.id);
                                setAgentSearch(agent.displayName || agent.id);
                                setAgentDropdownOpen(false);
                              }}
                            >
                              <span className="actor-team-dropdown-name">{agent.displayName || agent.id}</span>
                              <span className="actor-team-dropdown-id">{agent.id}</span>
                              {selectedNode.config?.agentId === agent.id ? <span className="actor-team-dropdown-check">✓</span> : null}
                            </li>
                          ))}
                        </ul>
                      ) : null}
                    </div>
                  </label>
                ) : null}
                {!["parallel", "join", "project_task", "update_task"].includes(selectedNode.type) && !["tool", "sub_workflow", "code", "web_request", "merge"].includes(selectedNodeBlockKind) ? <label>
                  {selectedNodeTextKey === "command" ? "Command" : selectedNodeTextKey === "expression" ? "Expression" : selectedNodeTextKey === "message" ? "Message" : "Prompt"}
                  <textarea
                    value={selectedNodeTextValue}
                    onChange={(event) => updateSelectedNodeConfig(selectedNodeTextKey, event.target.value)}
                    rows={4}
                  />
                </label> : null}
                {(["parallel", "join"].includes(selectedNode.type) || selectedNodeBlockKind === "merge") ? <WorkflowParallelControls key={`parallel-${selectedNode.id}`} node={selectedNode} workflow={draft!} onChange={updateSelectedNodeConfig} /> : null}
                {selectedNode.type === "agent_step" ? <WorkflowSessionControls key={`session-${selectedNode.id}`} node={selectedNode} workflow={draft!} onChange={(config) => {
                  setNodeConfigText(JSON.stringify(config, null, 2));
                  updateSelectedNode({ config });
                }} /> : null}
                {selectedNode.type === "update_task" ? <label>Task status<input value={rawString(selectedNode.config?.status)} onChange={(event) => updateSelectedNodeConfig("status", event.target.value)} /></label> : null}
                {selectedNodeBlockKind === "loop" ? <label>Maximum iterations (1–24)<input type="number" min={1} max={24} value={selectedNode.config?.maxIterations || 10} onChange={(event) => updateSelectedNodeConfig("maxIterations", Number(event.target.value))} /></label> : null}
                {["expression", "loop"].includes(selectedNodeBlockKind) ? <small>Typed expressions support field paths, exists(path), comparisons, boolean operators and arithmetic. Loops can use iteration.</small> : null}
                <WorkflowBlockControls key={`block-${selectedNode.id}`} node={selectedNode} project={project} workflows={workflows} currentWorkflowId={draft!.id} onChange={updateSelectedNodeConfig} onError={setBlockError} />
                {blockError || nodeConfigError ? <p role="alert">{blockError || nodeConfigError}</p> : null}
                <WorkflowOutputControls key={selectedNode.id} node={selectedNode} onChange={updateSelectedNodeConfig} onError={setContractError} />
                <div className="project-workflow-data-hints">
                  <strong>Data</strong>
                  <code>{"{{input}}"}</code>
                  {selectedNodeReferences.map((entry: AnyRecord) => (
                    <span key={entry.nodeId}>
                      <small>{entry.title}</small>
                      <code>{entry.output}</code>
                    </span>
                  ))}
                </div>
                {selectedNodeBlockKind === "web_request" ? (
                  <>
                    <label>
                      HTTP method
                      <div className="project-workflow-choice-grid project-workflow-choice-grid--compact">
                        {HTTP_METHODS.map((method) => (
                          <button
                            key={method}
                            type="button"
                            className={asString(selectedNode.config?.method, "GET").toUpperCase() === method ? "active" : ""}
                            onClick={() => updateSelectedNodeConfig("method", method)}
                          >
                            {method}
                          </button>
                        ))}
                      </div>
                    </label>
                    <label>
                      URL
                      <input
                        value={rawString(selectedNode.config?.url)}
                        onChange={(event) => updateSelectedNodeConfig("url", event.target.value)}
                        placeholder="https://api.example.com"
                      />
                    </label>
                    <label>
                      Headers JSON
                      <textarea
                        value={rawString(selectedNode.config?.headers, "{}")}
                        onChange={(event) => updateSelectedNodeConfig("headers", event.target.value)}
                        rows={3}
                      />
                    </label>
                    <label>
                      Body
                      <textarea
                        value={rawString(selectedNode.config?.body)}
                        onChange={(event) => updateSelectedNodeConfig("body", event.target.value)}
                        rows={4}
                      />
                    </label>
                  </>
                ) : null}
                {selectedNodeBlockKind === "code" ? (
                  <>
                    <label>
                      Language
                      <div className="project-workflow-choice-grid project-workflow-choice-grid--compact">
                        {CODE_LANGUAGES.map((language) => (
                          <button
                            key={language}
                            type="button"
                            className={asString(selectedNode.config?.language, "javascript") === language ? "active" : ""}
                            onClick={() => updateSelectedNodeConfig("language", language)}
                          >
                            {language}
                          </button>
                        ))}
                      </div>
                    </label>
                    <label>
                      Local file path
                      <input
                        value={rawString(selectedNode.config?.filePath)}
                        onChange={(event) => updateSelectedNodeConfig("filePath", event.target.value)}
                        placeholder="/absolute/path/to/script"
                      />
                    </label>
                    <label>
                      Source code
                      <textarea
                        value={rawString(selectedNode.config?.source)}
                        onChange={(event) => updateSelectedNodeConfig("source", event.target.value)}
                        rows={6}
                      />
                    </label>
                  </>
                ) : null}
                <label>
                  Advanced JSON
                  <textarea
                    value={nodeConfigText}
                    onChange={(event) => {
                      const text = event.target.value; setNodeConfigText(text);
                      try {
                        const parsed = JSON.parse(text);
                        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
                        setNodeConfigError(""); updateSelectedNode({ config: parsed });
                      } catch { setNodeConfigError("Config JSON must be an object."); }
                    }}
                    rows={8}
                  />
                </label>
                <button type="button" className="project-workflow-danger" onClick={deleteSelectedNode}>
                  Delete node
                </button>
              </article>
            ) : selectedEdge ? (
              <article className="project-workflow-editor-card">
                <strong>{selectedEdge.sourceNodeId} → {selectedEdge.targetNodeId}</strong>
                <WorkflowTransitionControls key={selectedEdge.id} edge={selectedEdge} onChange={updateSelectedEdge} onError={setContractError} />
                <button type="button" className="project-workflow-danger" onClick={deleteSelectedEdge}>
                  Delete connection
                </button>
              </article>
            ) : draft ? (
              <article className="project-workflow-editor-card">
                <label>
                  Workflow name
                  <input value={draft.name} onChange={(event) => setDraftAndMark({ ...draft, name: event.target.value })} />
                </label>
                <div className="project-workflow-action">
                  <strong>{draft.name}</strong>
                  <small>v{draft.version} · {draft.enabled === false ? "disabled" : "enabled"} · {draft.nodes.length} nodes · {draft.edges.length} links</small>
                  <div>
                    <button type="button" onClick={deleteSelectedWorkflow} disabled={isBusy}>Delete</button>
                  </div>
                </div>
              </article>
            ) : (
              <p className="placeholder-text">No workflow selected.</p>
            )}
          </section>

          {inspectorTab === "run" && draft ? <WorkflowLaunchControls key={`${project.id}-${draft.id}`} project={project} workflow={draft} selectedTask={selectedTask} busy={isBusy} onLaunch={startRun} /> : null}
          <section hidden={inspectorTab !== "activity"}>
            <h3>Current run</h3>
            {selectedRun ? (
              <article className="project-workflow-action">
                <strong>{formatStatus(selectedRun.status)}</strong>
                <small>{formatDate(selectedRun.startedAt)}</small>
                {selectedRun.taskId ? <small>Task: {runSteps.find((step: AnyRecord) => step.input?.task?.id === selectedRun.taskId)?.input.task.title || selectedRun.taskId}</small> : null}
                {selectedRunDetail?.run?.environment ? <div className="project-workflow-binding"><small>{formatStatus(selectedRunDetail.run.environment.request.mode)} · {selectedRunDetail.run.environment.preparation}</small><code>{selectedRunDetail.run.environment.workingDirectory}</code>{selectedRunDetail.run.environment.branch ? <small>{selectedRunDetail.run.environment.branch}</small> : null}{selectedRunDetail.run.environment.baseRevision ? <small>Base revision: {selectedRunDetail.run.environment.baseRevision.slice(0, 12)}</small> : null}{selectedRunDetail.run.environment.error ? <p role="alert">{selectedRunDetail.run.environment.error}</p> : null}</div> : null}
                {selectedRunDetail?.run ? <WorkflowRunControls key={selectedRunDetail.run.id} projectId={project.id} detail={selectedRunDetail} onChange={(detail) => {
                  setSelectedRunDetail(detail);
                  setRuns((previous) => previous.map((run) => run.id === detail.run.id ? detail.run : run));
                }} /> : null}
                <WorkflowAgentQuestions steps={runSteps} />
                {selectedRunDetail?.reconciliations?.length ? <details><summary>Reconciliation history</summary>{selectedRunDetail.reconciliations.map((record: AnyRecord, index: number) => <p key={index}><strong>{record.request.userId} · {formatStatus(record.request.decision)}</strong><br />{record.request.evidence}</p>)}</details> : null}
                <div className="project-workflow-step-list">
                  {runSteps.length === 0 ? <small>No step detail.</small> : runSteps.map((step: AnyRecord) => {
                    const description = describeWorkflowStep(step);
                    return (
                      <span key={step.id} className={`project-workflow-step-pill ${step.status}`}>
                        <strong>{description.title}</strong>
                        {description.detail ? <small>{description.detail}</small> : null}
                        {description.output && description.output !== description.detail ? <code>{description.output}</code> : null}
                        {step.output?.childRunId ? <button type="button" onClick={() => { setSelectedRunId(step.output.childRunId); if (step.output.childWorkflowId) setSelectedWorkflowId(step.output.childWorkflowId); }}>Inspect child run</button> : null}
                      </span>
                    );
                  })}
                </div>
              </article>
            ) : (
              <p className="placeholder-text">Select or start a run.</p>
            )}
          </section>

          <section hidden={inspectorTab !== "activity"}>
            <h3>Pending actions</h3>
            {actions.length === 0 ? (
              <p className="placeholder-text">No pending actions.</p>
            ) : actions.map((action) => (
              <article className="project-workflow-action" key={action.id}>
                <strong>{action.prompt}</strong>
                <small>{action.assignee}</small>
                <label>
                  Response or comment
                  <textarea rows={3} value={actionResponses[String(action.id)] || ""}
                    aria-label={`Response for ${action.prompt}`}
                    onChange={(event) => setActionResponses((previous) => ({ ...previous, [String(action.id)]: event.target.value }))} />
                </label>
                <div>
                  {(action.decisions || ["approved", "rejected", "changes_requested"]).map((decision: string) => (
                    <button key={decision} type="button" onClick={() => resolveAction(action, decision)}
                      disabled={isBusy || (action.decisions?.length === 1 && !actionResponses[String(action.id)]?.trim())}>
                      {decision === "approved" ? (action.decisions?.length === 1 ? "Continue" : "Approve") : decision === "rejected" ? "Reject" : "Changes"}
                    </button>
                  ))}
                </div>
              </article>
            ))}
          </section>

          <section hidden={inspectorTab !== "activity"}>
            <h3>Recent runs</h3>
            {runs.length === 0 ? (
              <p className="placeholder-text">No runs yet.</p>
            ) : runs.slice(0, 8).map((run) => (
              <button
                type="button"
                className={`project-workflow-run ${selectedRunId === String(run.id) ? "active" : ""}`}
                key={run.id}
                onClick={() => {
                  setSelectedRunId(String(run.id));
                  if (run.workflowId) setSelectedWorkflowId(String(run.workflowId));
                }}
              >
                <span>{formatStatus(run.status)}</span>
                <small>{formatDate(run.startedAt)}</small>
              </button>
            ))}
          </section>
        </aside>
      </div>
    </section>
  );
}
