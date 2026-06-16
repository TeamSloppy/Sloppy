import React, { useEffect, useMemo, useRef, useState } from "react";
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
import { selectWorkflowAfterDelete } from "./projectWorkflows";

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

const NODE_WIDTH = 220;
const NODE_HEIGHT = 104;
const SOCKETS = ["top", "right", "bottom", "left"];

const BLOCK_PRESETS = [
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
    config: { blockKind: "loop", expression: "continue == true", maxIterations: "25" }
  },
  {
    id: "merge",
    title: "Merge",
    type: "condition",
    icon: "call_merge",
    laneKind: "system",
    laneTitle: "Flow",
    description: "Merge multiple incoming paths.",
    config: { blockKind: "merge", strategy: "first_completed" }
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

function socketPoint(node: AnyRecord, socket: string) {
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

function socketTangent(socket: string) {
  switch (socket) {
    case "top":
      return { x: 0, y: -1 };
    case "right":
      return { x: 1, y: 0 };
    case "bottom":
      return { x: 0, y: 1 };
    case "left":
    default:
      return { x: -1, y: 0 };
  }
}

function oppositeSocket(socket: string) {
  switch (socket) {
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

function buildBezierPath(source: AnyRecord, target: AnyRecord, sourceSocket: string, targetSocket: string) {
  const sourceTangent = socketTangent(sourceSocket);
  const targetTangent = socketTangent(targetSocket);
  const distance = Math.hypot(target.x - source.x, target.y - source.y);
  const handle = clamp(distance * 0.35, 42, 180);
  const c1 = { x: source.x + sourceTangent.x * handle, y: source.y + sourceTangent.y * handle };
  const c2 = { x: target.x + targetTangent.x * handle, y: target.y + targetTangent.y * handle };
  return `M ${source.x} ${source.y} C ${c1.x} ${c1.y}, ${c2.x} ${c2.y}, ${target.x} ${target.y}`;
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
  const selectedNode: AnyRecord | null = selectedNodeId ? nodeMap.get(selectedNodeId) || null : null;
  const selectedEdge: AnyRecord | null = selectedEdgeId ? (draft?.edges || []).find((edge: AnyRecord) => edge.id === selectedEdgeId) || null : null;

  function applyViewTransform(next: { x: number; y: number; scale: number }) {
    viewTransformRef.current = next;
    setViewTransform(next);
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
    fetchProjectWorkflowRun(project.id, selectedRunId).then((detail: AnyRecord | null) => {
      if (!isCancelled) setSelectedRunDetail(detail);
    });
    return () => {
      isCancelled = true;
    };
  }, [project.id, selectedRunId]);

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
          conditionKey: ""
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
    updateSelectedNode({ config: { ...(selectedNode.config || {}), [key]: value } });
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
    } finally {
      setIsBusy(false);
    }
  }

  async function createBlankWorkflow() {
    setIsBusy(true);
    try {
      const created = await createProjectWorkflow(project.id, {
        name: `Workflow ${workflows.length + 1}`,
        enabled: true,
        lanes: [{ id: "system", title: "System", kind: "system" }],
        nodes: [],
        edges: []
      });
      await load({ keepSelection: true });
      if (created?.id) setSelectedWorkflowId(String(created.id));
    } finally {
      setIsBusy(false);
    }
  }

  async function saveWorkflow() {
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

  async function startRun() {
    if (!draft?.id) return;
    if (isDirty) {
      await saveWorkflow();
    }
    setIsBusy(true);
    try {
      const detail = await startProjectWorkflowRun(project.id, String(draft.id), {
        taskId: selectedTask?.id || null,
        startedBy: "human:admin",
        input: { source: "dashboard", message: "Manual workflow run" }
      });
      await load({ keepSelection: true, silent: true });
      const run = (detail?.run || detail) as AnyRecord | null;
      if (run?.id) {
        setSelectedRunId(String(run.id));
        setSelectedRunDetail(detail);
      }
      setStatusText("Workflow run started");
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
    const source = socketPoint(sourceNode, portDrag.sourceSocket);
    const targetSocket = hoverInputPort?.targetSocket ? normalizeSocket(hoverInputPort.targetSocket, oppositeSocket(portDrag.sourceSocket)) : oppositeSocket(portDrag.sourceSocket);
    const target = hoverInputPort?.targetNodeId && nodeMap.get(hoverInputPort.targetNodeId)
      ? socketPoint(nodeMap.get(hoverInputPort.targetNodeId), targetSocket)
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

  return (
    <section className="project-tab-layout project-workflows-shell">
      <header className="project-workflows-toolbar">
        <div>
          <h2>Workflows</h2>
          <p>{selectedTask ? `Task: ${selectedTask.title}` : "Visual workflow editor and manual runs"}</p>
        </div>
        <div className="project-workflows-actions">
          <button type="button" className="agents-secondary-button" onClick={createBlankWorkflow} disabled={isBusy}>
            <span className="material-symbols-rounded">add</span>
            New
          </button>
          <button type="button" className="agents-secondary-button" onClick={createStarterWorkflow} disabled={isBusy}>
            <span className="material-symbols-rounded">account_tree</span>
            Starter
          </button>
          <button type="button" className="agents-secondary-button" onClick={saveWorkflow} disabled={isBusy || !draft || !isDirty}>
            <span className="material-symbols-rounded">save</span>
            Save
          </button>
          <button type="button" className="agents-create-inline" onClick={startRun} disabled={isBusy || !draft}>
            <span className="material-symbols-rounded">play_arrow</span>
            Run
          </button>
        </div>
      </header>

      <div className="project-workflows-grid">
        <aside className="project-workflows-list" aria-label="Workflow definitions">
          <header className="project-workflows-panel-header">
            <strong>Definitions</strong>
            <small>{workflows.length}</small>
          </header>
          {workflows.length === 0 ? (
            <p className="placeholder-text">No workflows yet.</p>
          ) : workflows.map((workflow) => (
            <button
              key={workflow.id}
              type="button"
              className={`project-workflow-row ${draft?.id === workflow.id ? "active" : ""}`}
              onClick={() => setSelectedWorkflowId(String(workflow.id))}
            >
              <span>{workflow.name}</span>
              <small>v{workflow.version}</small>
            </button>
          ))}

          <header className="project-workflows-panel-header project-workflows-blocks-header">
            <strong>Blocks</strong>
            <small>{BLOCK_PRESETS.length}</small>
          </header>
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
        </aside>

        <section className="project-workflows-board-pane" aria-label="Workflow board">
          <div
            className={`project-workflows-board-scroller ${panState ? "is-panning" : ""}`}
            ref={scrollerRef}
            onPointerDown={(event) => {
              if (event.target !== scrollerRef.current) return;
              setSelectedNodeId(null);
              setSelectedEdgeId(null);
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
                transform: `translate(${viewTransform.x}px, ${viewTransform.y}px) scale(${viewTransform.scale})`,
                transformOrigin: "0 0"
              }}
            >
              {draft ? (
                <>
                  <div className="project-workflows-lane-strip" aria-label="Workflow lanes">
                    {draft.lanes.map((lane: AnyRecord) => (
                      <span key={lane.id}>
                        <strong>{lane.title}</strong>
                        <small>{lane.kind}</small>
                      </span>
                    ))}
                  </div>

                  <svg className="project-workflows-links-layer">
                    {draft.edges.map((edge: AnyRecord) => {
                      const sourceNode = nodeMap.get(edge.sourceNodeId);
                      const targetNode = nodeMap.get(edge.targetNodeId);
                      if (!sourceNode || !targetNode) return null;
                      const sourceSocket = normalizeSocket(edge.sourceSocket, "right");
                      const targetSocket = normalizeSocket(edge.targetSocket, "left");
                      const source = socketPoint(sourceNode, sourceSocket);
                      const target = socketPoint(targetNode, targetSocket);
                      const path = buildBezierPath(source, target, sourceSocket, targetSocket);
                      const midX = (source.x + target.x) / 2;
                      const midY = (source.y + target.y) / 2;
                      const isSelected = selectedEdgeId === edge.id;
                      return (
                        <g key={edge.id}>
                          <path
                            d={path}
                            className="project-workflow-link-hit"
                            onClick={(event) => {
                              event.stopPropagation();
                              setSelectedEdgeId(edge.id);
                              setSelectedNodeId(null);
                            }}
                          />
                          <path d={path} className={`project-workflow-link ${isSelected ? "selected" : ""}`} />
                          <path d={path} className="project-workflow-link-flow" />
                          {edge.conditionKey ? (
                            <text x={midX} y={midY} className="project-workflow-link-label">
                              {edge.conditionKey}
                            </text>
                          ) : null}
                        </g>
                      );
                    })}

                    {previewLine ? (
                      <path
                        d={buildBezierPath(previewLine.source, previewLine.target, previewLine.sourceSocket, previewLine.targetSocket)}
                        className="project-workflow-link preview"
                      />
                    ) : null}
                  </svg>

                  {draft.nodes.map((node: AnyRecord) => {
                    const lane = laneMap.get(String(node.laneId || ""));
                    const blockKind = asString(node.config?.blockKind || node.config?.block_kind, formatStatus(node.type));
                    const isSelected = selectedNodeId === node.id;
                    const isActive = activeNodeIds.has(String(node.id));
                    const stepStatus = stepStatusByNode.get(String(node.id));
                    return (
                      <article
                        className={`project-workflow-node ${formatStatus(node.type).replace(/\s+/g, "-")} ${isSelected ? "selected" : ""} ${isActive ? "active" : ""} ${stepStatus ? `step-${stepStatus}` : ""}`}
                        key={node.id}
                        style={{ left: node.positionX, top: node.positionY }}
                        onPointerDown={(event) => onNodePointerDown(event, node)}
                        onClick={(event) => {
                          event.stopPropagation();
                          setSelectedNodeId(node.id);
                          setSelectedEdgeId(null);
                        }}
                      >
                        {SOCKETS.map((socket) => {
                          const isHover = hoverInputPort?.targetNodeId === node.id && hoverInputPort?.targetSocket === socket;
                          const isSource = portDrag?.sourceNodeId === node.id && portDrag?.sourceSocket === socket;
                          return (
                            <button
                              key={socket}
                              type="button"
                              className={`project-workflow-socket side-${socket} ${isSource ? "source" : ""} ${isHover ? "hover" : ""}`}
                              onPointerDown={(event) => onSocketPointerDown(event, node, socket)}
                              onPointerEnter={() => {
                                if (portDrag) setHoverInputPort({ targetNodeId: node.id, targetSocket: socket });
                              }}
                              onPointerLeave={() => {
                                if (hoverInputPort?.targetNodeId === node.id && hoverInputPort?.targetSocket === socket) setHoverInputPort(null);
                              }}
                              onPointerUp={(event) => onSocketPointerUp(event, node, socket)}
                              title={`Socket ${socket}`}
                            />
                          );
                        })}
                        <span className="material-symbols-rounded">{workflowNodeIcon(node.type, node.config)}</span>
                        <div>
                          <strong>{node.title}</strong>
                          <small>{blockKind}</small>
                          <em>{stepStatus || (lane?.title || node.laneId || "Unassigned")}</em>
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

          <div className="project-workflows-fast-actions" onPointerDown={(event) => event.stopPropagation()}>
            <button type="button" onClick={() => draft?.nodes?.length && fitToView(draft.nodes)} disabled={!draft?.nodes?.length}>
              Fit
            </button>
            <button type="button" onClick={() => applyViewTransform({ x: 0, y: 0, scale: 1 })}>
              100%
            </button>
            <p>Drag handles to connect</p>
            <p>Wheel pans · Shift/Ctrl wheel zooms</p>
          </div>

          <div className="project-workflows-board-status">
            {isBusy ? "Working..." : isDirty ? "Unsaved changes" : statusText}
          </div>
        </section>

        <aside className="project-workflows-inspector">
          <section>
            <header className="project-workflows-panel-header">
              <strong>Inspector</strong>
            </header>
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
                <label>
                  Prompt / Expression / Command
                  <textarea
                    value={asString(selectedNode.config?.prompt || selectedNode.config?.expression || selectedNode.config?.command || selectedNode.config?.message)}
                    onChange={(event) => {
                      const blockKind = asString(selectedNode.config?.blockKind);
                      const key = blockKind === "bash" ? "command" : blockKind === "expression" || blockKind === "loop" ? "expression" : "prompt";
                      updateSelectedNodeConfig(key, event.target.value);
                    }}
                    rows={4}
                  />
                </label>
                <label>
                  Config JSON
                  <textarea
                    value={nodeConfigText}
                    onChange={(event) => setNodeConfigText(event.target.value)}
                    onBlur={() => {
                      try {
                        const parsed = JSON.parse(nodeConfigText);
                        updateSelectedNode({ config: parsed && typeof parsed === "object" ? parsed : {} });
                      } catch {
                        setStatusText("Config JSON invalid");
                      }
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
                <label>
                  Condition label
                  <input
                    value={selectedEdge.conditionKey || ""}
                    onChange={(event) => updateSelectedEdge({ conditionKey: event.target.value })}
                    placeholder="approved / failed / ok"
                  />
                </label>
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

          <section>
            <h3>Run</h3>
            {selectedRun ? (
              <article className="project-workflow-action">
                <strong>{formatStatus(selectedRun.status)}</strong>
                <small>{formatDate(selectedRun.startedAt)}</small>
                <div className="project-workflow-step-list">
                  {runSteps.length === 0 ? <small>No step detail.</small> : runSteps.map((step: AnyRecord) => (
                    <span key={step.id} className={`project-workflow-step-pill ${step.status}`}>
                      {step.nodeId}: {formatStatus(step.status)}
                    </span>
                  ))}
                </div>
              </article>
            ) : (
              <p className="placeholder-text">Select or start a run.</p>
            )}
          </section>

          <section>
            <h3>Pending Actions</h3>
            {actions.length === 0 ? (
              <p className="placeholder-text">No pending actions.</p>
            ) : actions.map((action) => (
              <article className="project-workflow-action" key={action.id}>
                <strong>{action.prompt}</strong>
                <small>{action.assignee}</small>
                <div>
                  <button type="button" onClick={() => resolveAction(action, "approved")} disabled={isBusy}>Approve</button>
                  <button type="button" onClick={() => resolveAction(action, "rejected")} disabled={isBusy}>Reject</button>
                  <button type="button" onClick={() => resolveAction(action, "changes_requested")} disabled={isBusy}>Changes</button>
                </div>
              </article>
            ))}
          </section>

          <section>
            <h3>Recent Runs</h3>
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
