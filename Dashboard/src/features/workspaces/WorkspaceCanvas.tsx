import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Background,
  BackgroundVariant,
  Controls,
  Handle,
  MiniMap,
  NodeResizer,
  Position,
  ReactFlow,
  type Connection,
  type Edge,
  type Node,
  type NodeProps,
  type OnSelectionChangeParams
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import type { CoreApi } from "../../shared/api/coreApi";
import { buildWebSocketURL } from "../../shared/api/httpClient";
import {
  applyOperations,
  makeElement,
  type WorkspaceConnection,
  type WorkspaceDocument,
  type WorkspaceElement,
  type WorkspaceElementKind,
  type WorkspaceOperation,
  type WorkspaceRecord,
  type WorkspaceTemplate,
  type WorkspaceTransaction
} from "./types";

type CanvasNode = Node<{
  element: WorkspaceElement;
  onPatch: (element: WorkspaceElement) => void;
  widgetHtml?: string;
}, "workspace">;

function textValue(element: WorkspaceElement) {
  return String(element.data.text || element.data.title || "");
}

function elementIcon(kind: WorkspaceElementKind) {
  switch (kind) {
  case "sticky": return "sticky_note_2";
  case "text": return "text_fields";
  case "shape": return "shapes";
  case "table": return "table";
  case "frame": return "crop_free";
  case "image": return "image";
  case "widget": return "widgets";
  }
}

function isEditableTarget(target: EventTarget | null) {
  if (!(target instanceof HTMLElement)) return false;
  return Boolean(target.closest("input, textarea, select, [contenteditable='true'], iframe"));
}

const workspaceTools: ReadonlyArray<readonly [WorkspaceElementKind, string, string]> = [
  ["sticky", "sticky_note_2", "Sticky Note"],
  ["text", "text_fields", "Text"],
  ["shape", "shapes", "Shape"],
  ["table", "table", "Table"],
  ["frame", "crop_free", "Frame"],
  ["image", "image", "Image"]
];

function sandboxedWidgetDocument(html: string) {
  const policy = "default-src 'none'; img-src data: blob:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; font-src data:";
  return `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="${policy}"><style>html,body{margin:0;width:100%;height:100%;overflow:auto}</style></head><body>${html}</body></html>`;
}

function WorkspaceNode({ data, selected }: NodeProps<CanvasNode>) {
  const { element, onPatch, widgetHtml } = data;
  const [editingTarget, setEditingTarget] = useState<string | null>(null);
  const color = element.style.background
    ? String(element.style.background)
    : element.kind === "sticky" ? "#ffd970" : undefined;
  const rows = Array.isArray(element.data.rows) ? element.data.rows as unknown[][] : [];
  const columns = Array.isArray(element.data.columns) ? element.data.columns as unknown[] : [];

  return (
    <div
      className={`workspace-node workspace-node-${element.kind} ${selected ? "is-selected" : ""}`}
      style={{ background: color, transform: `rotate(${element.rotation || 0}deg)` }}
    >
      <NodeResizer
        minWidth={120}
        minHeight={72}
        isVisible={selected}
        onResizeEnd={(_, params) => onPatch({
          ...element,
          bounds: { x: params.x, y: params.y, width: params.width, height: params.height }
        })}
      />
      {element.kind !== "frame" && <Handle className="workspace-node-handle" type="target" position={Position.Left} />}
      {element.kind === "table" ? (
        <div className="workspace-table">
          <div className="workspace-table-row is-header">
            {columns.map((column, index) => <span key={index}>{String(column)}</span>)}
          </div>
          {rows.map((row, rowIndex) => (
            <div className="workspace-table-row" key={rowIndex}>
              {columns.map((_, columnIndex) => {
                const cellKey = `cell-${rowIndex}-${columnIndex}`;
                const cellValue = String(row[columnIndex] ?? "");
                return editingTarget === cellKey ? (
                  <input
                    className="nodrag nowheel"
                    key={columnIndex}
                    autoFocus
                    value={cellValue}
                    aria-label={`Row ${rowIndex + 1}, column ${columnIndex + 1}`}
                    onBlur={() => setEditingTarget(null)}
                    onKeyDown={(event) => {
                      if (event.key === "Escape") {
                        event.preventDefault();
                        event.currentTarget.blur();
                      }
                    }}
                    onChange={(event) => {
                      const nextRows = rows.map((item) => [...item]);
                      nextRows[rowIndex][columnIndex] = event.target.value;
                      onPatch({ ...element, data: { ...element.data, rows: nextRows } });
                    }}
                  />
                ) : (
                  <span
                    className="workspace-table-cell-preview"
                    key={columnIndex}
                    role="textbox"
                    tabIndex={0}
                    title="Double-click to edit"
                    aria-label={`Row ${rowIndex + 1}, column ${columnIndex + 1}. Double-click or press Enter to edit.`}
                    aria-readonly="true"
                    onDoubleClick={(event) => {
                      event.stopPropagation();
                      setEditingTarget(cellKey);
                    }}
                    onKeyDown={(event) => {
                      if (event.key === "Enter") {
                        event.preventDefault();
                        setEditingTarget(cellKey);
                      }
                    }}
                  >
                    {cellValue}
                  </span>
                );
              })}
            </div>
          ))}
        </div>
      ) : element.kind === "image" ? (
        element.data.url ? (
          <img className="workspace-image" src={String(element.data.url)} alt={textValue(element) || "Workspace asset"} />
        ) : (
          <div className="workspace-image-placeholder">
            <span className="material-symbols-rounded" aria-hidden="true">add_photo_alternate</span>
            <strong>Image</strong>
            <small>Ask an agent to add a visual</small>
          </div>
        )
      ) : element.kind === "widget" && widgetHtml ? (
        <iframe
          className="workspace-widget-frame nodrag"
          title={textValue(element) || element.id}
          sandbox="allow-scripts"
          srcDoc={sandboxedWidgetDocument(widgetHtml)}
        />
      ) : element.kind === "widget" ? (
        <div className="workspace-widget-placeholder">
          <span className="material-symbols-rounded">widgets</span>
          <strong>{textValue(element) || "HTML widget"}</strong>
          <small>Sandboxed artifact</small>
        </div>
      ) : editingTarget === "text" ? (
        <textarea
          className="workspace-node-text nodrag nowheel"
          autoFocus
          value={textValue(element)}
          aria-label={`${element.kind} content`}
          onBlur={() => setEditingTarget(null)}
          onKeyDown={(event) => {
            if (event.key === "Escape") {
              event.preventDefault();
              event.currentTarget.blur();
            }
          }}
          onChange={(event) => onPatch({ ...element, data: { ...element.data, text: event.target.value } })}
        />
      ) : (
        <div
          className="workspace-node-text workspace-node-text-preview"
          role="textbox"
          tabIndex={0}
          title="Double-click to edit"
          aria-label={`${element.kind} content. Double-click or press Enter to edit.`}
          aria-readonly="true"
          onDoubleClick={(event) => {
            event.stopPropagation();
            setEditingTarget("text");
          }}
          onKeyDown={(event) => {
            if (event.key === "Enter") {
              event.preventDefault();
              setEditingTarget("text");
            }
          }}
        >
          {textValue(element)}
        </div>
      )}
      {element.kind !== "frame" && <Handle className="workspace-node-handle" type="source" position={Position.Right} />}
    </div>
  );
}

const workspaceNodeTypes = { workspace: WorkspaceNode };

function hasSameSelection(current: string[], next: string[]) {
  return current.length === next.length && current.every((id) => next.includes(id));
}

interface WorkspaceCanvasProps {
  coreApi: CoreApi;
  workspace: WorkspaceRecord;
  templates: WorkspaceTemplate[];
  onBack: () => void;
  showsBackButton?: boolean;
}

export function WorkspaceCanvas({ coreApi, workspace, templates, onBack, showsBackButton = true }: WorkspaceCanvasProps) {
  const [document, setDocument] = useState<WorkspaceDocument | null>(null);
  const [history, setHistory] = useState<WorkspaceTransaction[]>([]);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [presence, setPresence] = useState<Record<string, string>>({});
  const [connectionState, setConnectionState] = useState<"connecting" | "live" | "offline">("connecting");
  const [activeInspector, setActiveInspector] = useState<"templates" | "layers">("layers");
  const [inspectorOpen, setInspectorOpen] = useState(true);
  const [agents, setAgents] = useState<Record<string, unknown>[]>([]);
  const [agentId, setAgentId] = useState("");
  const [agentPrompt, setAgentPrompt] = useState("");
  const [agentStatus, setAgentStatus] = useState("Ready");
  const [agentBusy, setAgentBusy] = useState(false);
  const [showAgentPicker, setShowAgentPicker] = useState(false);
  const [widgetHtml, setWidgetHtml] = useState<Record<string, string>>({});
  const socketRef = useRef<WebSocket | null>(null);
  const documentRef = useRef<WorkspaceDocument | null>(null);
  const pendingRef = useRef<Record<string, unknown>[]>([]);
  const reconnectRef = useRef<number | null>(null);
  const agentPickerRef = useRef<HTMLDivElement | null>(null);
  const agentPromptRef = useRef<HTMLTextAreaElement | null>(null);

  const replaceDocument = useCallback((next: WorkspaceDocument) => {
    documentRef.current = next;
    setDocument(next);
  }, []);

  const loadDocument = useCallback(async () => {
    const response = await coreApi.fetchWorkspaceDocument(workspace.id);
    const next = response?.document as WorkspaceDocument | undefined;
    if (next) {
      replaceDocument(next);
      setHistory(Array.isArray(response?.transactions) ? response.transactions as unknown as WorkspaceTransaction[] : []);
    }
  }, [coreApi, replaceDocument, workspace.id]);

  useEffect(() => {
    void loadDocument();
    coreApi.fetchAgents({ includeSystem: false }).then((items) => {
      const next = Array.isArray(items) ? items : [];
      setAgents(next);
      setAgentId(String(next[0]?.id || ""));
    });
  }, [coreApi, loadDocument]);

  useEffect(() => {
    if (!showAgentPicker) return;
    const dismissPicker = (event: PointerEvent) => {
      if (!agentPickerRef.current?.contains(event.target as globalThis.Node)) {
        setShowAgentPicker(false);
      }
    };
    window.addEventListener("pointerdown", dismissPicker);
    return () => window.removeEventListener("pointerdown", dismissPicker);
  }, [showAgentPicker]);

  useEffect(() => {
    const textarea = agentPromptRef.current;
    if (!textarea) return;
    textarea.style.height = "0px";
    textarea.style.height = `${Math.min(112, Math.max(34, textarea.scrollHeight))}px`;
  }, [agentPrompt]);

  useEffect(() => {
    const artifactIds = (document?.elements || [])
      .filter((element) => element.kind === "widget")
      .map((element) => String(element.data.artifactId || ""))
      .filter((id) => id && widgetHtml[id] === undefined);
    for (const artifactId of [...new Set(artifactIds)]) {
      coreApi.fetchWidgetArtifact(artifactId).then((artifact) => {
        setWidgetHtml((items) => ({
          ...items,
          [artifactId]: String(artifact?.html || "")
        }));
      });
    }
  }, [coreApi, document?.elements, widgetHtml]);

  useEffect(() => {
    let closed = false;
    let retry = 0;
    const connect = async () => {
      setConnectionState("connecting");
      const ticketResponse = await coreApi.createWorkspaceRealtimeTicket(workspace.id);
      const ticket = String(ticketResponse?.ticket || "");
      if (!ticket || closed) {
        setConnectionState("offline");
        return;
      }
      const revision = documentRef.current?.revision ?? 0;
      const socket = new WebSocket(buildWebSocketURL(
        `/v1/workspaces/${encodeURIComponent(workspace.id)}/ws?ticket=${encodeURIComponent(ticket)}&revision=${revision}`
      ));
      socketRef.current = socket;
      socket.onopen = () => {
        retry = 0;
        setConnectionState("live");
        for (const message of pendingRef.current) socket.send(JSON.stringify(message));
        pendingRef.current = [];
      };
      socket.onmessage = (event) => {
        const message = JSON.parse(String(event.data)) as Record<string, unknown>;
        if (message.kind === "ready" && message.document) {
          replaceDocument(message.document as WorkspaceDocument);
        } else if (message.kind === "transaction_committed" && message.transaction) {
          const transaction = message.transaction as unknown as WorkspaceTransaction;
          const current = documentRef.current;
          if (current) replaceDocument(applyOperations(current, transaction.operations, transaction.revision));
          setHistory((items) => [transaction, ...items.filter((item) => item.id !== transaction.id)]);
        } else if (message.kind === "transaction_rejected") {
          setAgentStatus("A canvas edit conflicted and was reloaded.");
          void loadDocument();
        } else if (message.kind === "presence" && message.presence) {
          const item = message.presence as { actor?: { id?: string; displayName?: string }; status?: string };
          const id = String(item.actor?.id || "");
          if (id) setPresence((items) => ({ ...items, [id]: String(item.actor?.displayName || id) }));
        } else if (message.kind === "agent_status") {
          setAgentStatus(String(message.message || "Agent is editing"));
        }
      };
      socket.onclose = () => {
        if (closed) return;
        setConnectionState("offline");
        retry += 1;
        reconnectRef.current = window.setTimeout(connect, Math.min(8000, 700 * 2 ** retry));
      };
      socket.onerror = () => socket.close();
    };
    void connect();
    return () => {
      closed = true;
      if (reconnectRef.current) window.clearTimeout(reconnectRef.current);
      socketRef.current?.close();
    };
  }, [coreApi, loadDocument, replaceDocument, workspace.id]);

  const commit = useCallback(async (operations: WorkspaceOperation[], summary: string) => {
    const current = documentRef.current;
    if (!current || operations.length === 0) return;
    const expectedElementRevisions: Record<string, number> = {};
    for (const operation of operations) {
      const element = operation.element;
      const existing = element ? current.elements.find((item) => item.id === element.id) : undefined;
      if (existing && operation.kind !== "element.create") expectedElementRevisions[existing.id] = existing.revision;
      if (operation.targetId) {
        const target = current.elements.find((item) => item.id === operation.targetId);
        if (target) expectedElementRevisions[target.id] = target.revision;
      }
    }
    const request = {
      id: `tx-${crypto.randomUUID()}`,
      baseRevision: current.revision,
      expectedElementRevisions,
      operations,
      summary
    };
    replaceDocument(applyOperations(current, operations));
    const message = { kind: "transaction", transactionRequest: request };
    if (socketRef.current?.readyState === WebSocket.OPEN) {
      socketRef.current.send(JSON.stringify(message));
    } else {
      pendingRef.current.push(message);
      const committed = await coreApi.applyWorkspaceTransaction(workspace.id, request);
      if (committed) {
        const transaction = committed as unknown as WorkspaceTransaction;
        const latest = documentRef.current;
        if (latest) replaceDocument(applyOperations(latest, transaction.operations, transaction.revision));
        setHistory((items) => [transaction, ...items]);
      } else {
        await loadDocument();
      }
    }
  }, [coreApi, loadDocument, replaceDocument, workspace.id]);

  const patchElement = useCallback((element: WorkspaceElement) => {
    void commit([{ kind: "element.update", element }], `Updated ${element.kind}`);
  }, [commit]);

  const nodes = useMemo<CanvasNode[]>(() => (document?.elements || []).map((element) => ({
    id: element.id,
    type: "workspace",
    position: { x: element.bounds.x, y: element.bounds.y },
    style: { width: element.bounds.width, height: element.bounds.height, zIndex: element.zIndex },
    parentId: element.parentId || undefined,
    extent: element.parentId ? "parent" : undefined,
    data: {
      element,
      onPatch: patchElement,
      widgetHtml: element.kind === "widget"
        ? widgetHtml[String(element.data.artifactId || "")]
        : undefined
    },
    selected: selectedIds.includes(element.id)
  })), [document?.elements, patchElement, selectedIds, widgetHtml]);

  const edges = useMemo<Edge[]>(() => (document?.connections || []).map((connection) => ({
    id: connection.id,
    source: connection.sourceElementId,
    target: connection.targetElementId,
    label: connection.label || undefined,
    animated: Boolean(connection.style.animated),
    style: { stroke: String(connection.style.stroke || "#7c8cff") }
  })), [document?.connections]);

  const addElement = (kind: WorkspaceElementKind) => {
    const element = makeElement(kind, document?.elements.length || 0);
    void commit([{ kind: "element.create", element }], `Added ${kind}`);
  };

  const deleteSelection = () => {
    void commit(selectedIds.map((targetId) => ({ kind: "element.delete" as const, targetId })), `Deleted ${selectedIds.length} element(s)`);
    setSelectedIds([]);
  };

  const duplicateSelection = () => {
    const selected = (document?.elements || []).filter((element) => selectedIds.includes(element.id));
    const operations = selected.map((element) => ({
      kind: "element.create" as const,
      element: {
        ...element,
        id: `el-${crypto.randomUUID()}`,
        bounds: { ...element.bounds, x: element.bounds.x + 32, y: element.bounds.y + 32 },
        revision: 0
      }
    }));
    void commit(operations, `Duplicated ${operations.length} element(s)`);
  };

  const groupSelection = () => {
    const groupId = `group-${crypto.randomUUID()}`;
    const operations = (document?.elements || [])
      .filter((element) => selectedIds.includes(element.id))
      .map((element) => ({ kind: "element.update" as const, element: { ...element, groupId } }));
    void commit(operations, `Grouped ${operations.length} element(s)`);
  };

  const ungroupSelection = () => {
    const operations = (document?.elements || [])
      .filter((element) => selectedIds.includes(element.id) && element.groupId)
      .map((element) => ({ kind: "element.update" as const, element: { ...element, groupId: null } }));
    void commit(operations, `Ungrouped ${operations.length} element(s)`);
  };

  const alignSelection = () => {
    const selected = (document?.elements || []).filter((element) => selectedIds.includes(element.id));
    if (selected.length < 2) return;
    const x = Math.min(...selected.map((element) => element.bounds.x));
    void commit(selected.map((element) => ({
      kind: "element.update" as const,
      element: { ...element, bounds: { ...element.bounds, x } }
    })), "Aligned selection");
  };

  const distributeSelection = () => {
    const selected = (document?.elements || [])
      .filter((element) => selectedIds.includes(element.id))
      .sort((a, b) => a.bounds.x - b.bounds.x);
    if (selected.length < 3) return;
    const first = selected[0].bounds.x;
    const last = selected[selected.length - 1].bounds.x;
    const step = (last - first) / (selected.length - 1);
    void commit(selected.map((element, index) => ({
      kind: "element.update" as const,
      element: { ...element, bounds: { ...element.bounds, x: first + step * index } }
    })), "Distributed selection");
  };

  const bringToFront = () => {
    const maxZ = Math.max(0, ...(document?.elements || []).map((element) => element.zIndex));
    const selected = (document?.elements || []).filter((element) => selectedIds.includes(element.id));
    void commit(selected.map((element, index) => ({
      kind: "element.update" as const,
      element: { ...element, zIndex: maxZ + index + 1 }
    })), "Brought selection to front");
  };

  const undoLatest = async () => {
    const transaction = history[0];
    if (!transaction) return;
    await coreApi.undoWorkspaceTransaction(workspace.id, transaction.id);
    await loadDocument();
  };

  const onConnect = (connection: Connection) => {
    if (!connection.source || !connection.target) return;
    const item: WorkspaceConnection = {
      id: `edge-${crypto.randomUUID()}`,
      sourceElementId: connection.source,
      targetElementId: connection.target,
      style: {},
      revision: 0
    };
    void commit([{ kind: "connection.create", connection: item }], "Connected elements");
  };

  const onSelectionChange = useCallback(({ nodes: nextNodes }: OnSelectionChangeParams) => {
    const ids = nextNodes.map((node) => node.id);
    setSelectedIds((current) => hasSameSelection(current, ids) ? current : ids);
    const socket = socketRef.current;
    if (socket?.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify({
        kind: "presence",
        presence: {
          actor: { kind: "user", id: "dashboard", displayName: "You" },
          selectedElementIds: ids,
          status: "active"
        }
      }));
    }
  }, []);

  const sendAgentPrompt = async () => {
    const prompt = agentPrompt.trim();
    if (!agentId || !prompt || agentBusy) return;
    setAgentBusy(true);
    setAgentStatus("Creating workspace session…");
    try {
      const session = await coreApi.createAgentSession(agentId, {
        title: workspace.title,
        workspaceId: workspace.id,
        projectId: workspace.projectId || undefined
      });
      const sessionId = String(session?.id || "");
      if (!sessionId) {
        setAgentStatus("Could not create agent session.");
        return;
      }
      setAgentPrompt("");
      setAgentStatus("Agent is working…");
      const response = await coreApi.postAgentSessionMessage(agentId, sessionId, {
        userId: "dashboard",
        content: prompt,
        attachments: [],
        spawnSubSession: false,
        mode: "auto"
      });
      setAgentStatus(response ? "Agent run completed" : "Agent run failed");
      await loadDocument();
    } catch {
      setAgentStatus("Agent run failed");
    } finally {
      setAgentBusy(false);
    }
  };

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (isEditableTarget(event.target)) return;
      const command = event.metaKey || event.ctrlKey;
      if (command && event.key.toLowerCase() === "z" && !event.shiftKey) {
        event.preventDefault();
        void undoLatest();
      } else if (command && event.key.toLowerCase() === "d" && selectedIds.length) {
        event.preventDefault();
        duplicateSelection();
      } else if ((event.key === "Delete" || event.key === "Backspace") && selectedIds.length) {
        event.preventDefault();
        deleteSelection();
      } else if (event.key === "Escape") {
        if (showAgentPicker) {
          setShowAgentPicker(false);
        } else if (selectedIds.length) {
          setSelectedIds([]);
        } else if (inspectorOpen) {
          setInspectorOpen(false);
        }
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  });

  if (!document) {
    return (
      <div className="workspace-loading workspace-loading-editor" role="status">
        <span className="workspace-spinner" aria-hidden="true" />
        <span>Loading Workspace…</span>
      </div>
    );
  }

  return (
    <section className={`workspace-editor ${inspectorOpen ? "has-inspector" : ""}`} data-testid="workspace-editor">
      <main className="workspace-canvas" aria-label={`${workspace.title} canvas`}>
        <ReactFlow
          nodes={nodes}
          edges={edges}
          nodeTypes={workspaceNodeTypes}
          onConnect={onConnect}
          onSelectionChange={onSelectionChange}
          onNodeDragStop={(_, node) => {
            const element = documentRef.current?.elements.find((item) => item.id === node.id);
            if (element) patchElement({ ...element, bounds: { ...element.bounds, x: node.position.x, y: node.position.y } });
          }}
          fitView
          minZoom={0.08}
          maxZoom={3}
          deleteKeyCode={null}
          multiSelectionKeyCode={["Meta", "Shift"]}
        >
          <Background variant={BackgroundVariant.Dots} color="var(--workspace-canvas-dot)" gap={24} size={1} />
          <Controls position="bottom-left" showInteractive={false} />
          <MiniMap
            pannable
            zoomable
            nodeColor={(node) => (node.data as CanvasNode["data"]).element.kind === "sticky" ? "#d7ad35" : "#8b8b93"}
          />
        </ReactFlow>
      </main>

      <header className="workspace-editor-topbar">
        {showsBackButton && (
          <>
            <button className="workspace-icon-button" type="button" onClick={onBack} aria-label="Back to workspaces">
              <span className="material-symbols-rounded" aria-hidden="true">arrow_back</span>
            </button>
            <span className="workspace-toolbar-divider" aria-hidden="true" />
          </>
        )}
        <div className="workspace-title-block">
          <strong>{workspace.title}</strong>
          <span>{document.elements.length} elements · Revision {document.revision}</span>
        </div>
        <div className="workspace-presence">
          {Object.entries(presence).slice(0, 4).map(([id, name]) => (
            <span className="workspace-avatar" title={name} key={id}>{name.slice(0, 1).toUpperCase()}</span>
          ))}
          <span className={`workspace-live-state is-${connectionState}`} role="status">
            {connectionState === "live" ? "Live" : connectionState === "connecting" ? "Connecting" : "Offline"}
          </span>
        </div>
        <button className="workspace-button workspace-toolbar-action" type="button" disabled={!history[0]} onClick={() => void undoLatest()} title="Undo (⌘Z)">
          <span className="material-symbols-rounded" aria-hidden="true">undo</span><span>Undo</span>
        </button>
        <button
          className={`workspace-icon-button ${inspectorOpen ? "is-active" : ""}`}
          type="button"
          onClick={() => setInspectorOpen((value) => !value)}
          aria-label={inspectorOpen ? "Hide inspector" : "Show inspector"}
          aria-pressed={inspectorOpen}
          data-testid="workspace-inspector-toggle"
        >
          <span className="material-symbols-rounded" aria-hidden="true">right_panel_open</span>
        </button>
      </header>

      <aside className="workspace-tool-palette" aria-label="Canvas tools" data-testid="workspace-tool-palette">
        {workspaceTools.map(([kind, icon, title]) => (
          <button type="button" key={kind} onClick={() => addElement(kind)} title={title} aria-label={`Add ${title}`} data-testid={`workspace-add-${kind}`}>
            <span className="material-symbols-rounded" aria-hidden="true">{icon}</span>
            <span>{title}</span>
          </button>
        ))}
      </aside>

      {inspectorOpen && (
        <aside className="workspace-inspector" aria-label="Workspace inspector" data-testid="workspace-inspector">
          <header className="workspace-inspector-header">
            <strong>Inspector</strong>
            <button className="workspace-icon-button" type="button" onClick={() => setInspectorOpen(false)} aria-label="Close inspector">
              <span className="material-symbols-rounded" aria-hidden="true">close</span>
            </button>
          </header>
          <nav className="workspace-inspector-tabs" aria-label="Inspector sections">
            {(["layers", "templates"] as const).map((panel) => (
              <button
                className={activeInspector === panel ? "active" : ""}
                type="button"
                onClick={() => setActiveInspector(panel)}
                aria-pressed={activeInspector === panel}
                key={panel}
              >
                {panel === "layers" ? "Layers" : "Templates"}
              </button>
            ))}
          </nav>
          {activeInspector === "templates" && (
            <div className="workspace-template-list">
              {templates.length ? templates.map((template) => (
                <button type="button" key={template.id} onClick={() => void coreApi.applyWorkspaceTemplate(workspace.id, template.id).then(loadDocument)}>
                  <span className="workspace-inspector-row-icon material-symbols-rounded" aria-hidden="true">space_dashboard</span>
                  <span><strong>{template.title}</strong><small>{template.description || template.category}</small></span>
                </button>
              )) : <p className="workspace-inspector-empty">No templates available.</p>}
            </div>
          )}
          {activeInspector === "layers" && (
            <div className="workspace-layer-list">
              {document.elements.length ? [...document.elements].sort((a, b) => b.zIndex - a.zIndex).map((element) => (
                <button
                  type="button"
                  className={selectedIds.includes(element.id) ? "active" : ""}
                  onClick={() => setSelectedIds([element.id])}
                  key={element.id}
                  data-testid="workspace-layer"
                >
                  <span className="workspace-inspector-row-icon material-symbols-rounded" aria-hidden="true">{elementIcon(element.kind)}</span>
                  <span><strong>{textValue(element) || element.kind}</strong><small>{element.kind}</small></span>
                  <span className="workspace-layer-index">{element.zIndex}</span>
                </button>
              )) : <p className="workspace-inspector-empty">Add something to see it here.</p>}
            </div>
          )}
        </aside>
      )}

      {selectedIds.length > 0 && (
        <div className="workspace-selection-bar" role="toolbar" aria-label={`Actions for ${selectedIds.length} selected elements`} data-testid="workspace-selection-bar">
          <span className="workspace-selection-count">{selectedIds.length} selected</span>
          <span className="workspace-toolbar-divider" aria-hidden="true" />
          <button type="button" onClick={duplicateSelection} aria-label="Duplicate selection" title="Duplicate (⌘D)">
            <span className="material-symbols-rounded" aria-hidden="true">content_copy</span>
          </button>
          <button type="button" disabled={selectedIds.length < 2} onClick={groupSelection} aria-label="Group selection" title="Group">
            <span className="material-symbols-rounded" aria-hidden="true">select_all</span>
          </button>
          <button type="button" onClick={ungroupSelection} aria-label="Ungroup selection" title="Ungroup">
            <span className="material-symbols-rounded" aria-hidden="true">deselect</span>
          </button>
          <button type="button" disabled={selectedIds.length < 2} onClick={alignSelection} aria-label="Align selection left" title="Align left">
            <span className="material-symbols-rounded" aria-hidden="true">format_align_left</span>
          </button>
          <button type="button" disabled={selectedIds.length < 3} onClick={distributeSelection} aria-label="Distribute selection" title="Distribute horizontally">
            <span className="material-symbols-rounded" aria-hidden="true">horizontal_distribute</span>
          </button>
          <button type="button" onClick={bringToFront} aria-label="Bring selection to front" title="Bring to front">
            <span className="material-symbols-rounded" aria-hidden="true">flip_to_front</span>
          </button>
          <span className="workspace-toolbar-divider" aria-hidden="true" />
          <button className="is-danger" type="button" onClick={deleteSelection} aria-label="Delete selection" title="Delete">
            <span className="material-symbols-rounded" aria-hidden="true">delete</span>
          </button>
        </div>
      )}

      <div className={`workspace-agent-dock ${agentBusy ? "is-working" : ""}`} data-testid="workspace-agent-composer">
        <div className="workspace-agent-picker actor-team-search" ref={agentPickerRef}>
          <button type="button" onClick={() => setShowAgentPicker((value) => !value)} aria-haspopup="listbox" aria-expanded={showAgentPicker}>
            <span className="workspace-agent-avatar material-symbols-rounded" aria-hidden="true">auto_awesome</span>
            <span>{String(agents.find((agent) => agent.id === agentId)?.name || agentId || "Choose Agent")}</span>
            <span className="material-symbols-rounded" aria-hidden="true">expand_more</span>
          </button>
          {showAgentPicker && (
            <div className="actor-team-search-results" role="listbox" aria-label="Workspace agent">
              {agents.map((agent) => (
                <button type="button" role="option" aria-selected={String(agent.id) === agentId} key={String(agent.id)} onClick={() => { setAgentId(String(agent.id)); setShowAgentPicker(false); }}>
                  {String(agent.name || agent.id)}
                </button>
              ))}
            </div>
          )}
          </div>
        <div className="workspace-agent-input">
          <textarea
            ref={agentPromptRef}
            rows={1}
            value={agentPrompt}
            onChange={(event) => setAgentPrompt(event.target.value)}
            onKeyDown={(event) => {
              if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
                event.preventDefault();
                void sendAgentPrompt();
              }
            }}
            placeholder="Ask an agent to build on this canvas…"
            aria-label="Message workspace agent"
          />
          <button type="button" disabled={!agentId || !agentPrompt.trim() || agentBusy} onClick={() => void sendAgentPrompt()} aria-label="Send to agent">
            <span className="material-symbols-rounded" aria-hidden="true">arrow_upward</span>
          </button>
        </div>
        <div className="workspace-agent-meta">
          <span className="workspace-agent-status" role="status" aria-live="polite">
            {agentBusy && <span className="workspace-status-pulse" aria-hidden="true" />}{agentStatus}
          </span>
          <span className="workspace-agent-shortcut">⌘↵</span>
        </div>
      </div>
    </section>
  );
}
