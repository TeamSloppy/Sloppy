import React, { useCallback, useEffect, useMemo, useState } from "react";
import type { CoreApi } from "../shared/api/coreApi";

type AnyRecord = Record<string, unknown>;

function text(value: unknown, fallback = "") {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function list(value: unknown) {
  return Array.isArray(value) ? value.map((item) => String(item || "").trim()).filter(Boolean) : [];
}

function statusLabel(value: unknown) {
  return text(value, "offline").replace(/_/g, " ");
}

function formatTime(value: unknown) {
  const raw = text(value);
  if (!raw) {
    return "never";
  }
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) {
    return raw;
  }
  return date.toLocaleString();
}

function projectMembers(project: AnyRecord) {
  return Array.isArray(project.members) ? (project.members as AnyRecord[]) : [];
}

function nodeName(nodes: AnyRecord[], nodeId: string) {
  return text(nodes.find((node) => text(node.id) === nodeId)?.name, nodeId);
}

export function NodesView({ coreApi }: { coreApi: CoreApi }) {
  const [nodes, setNodes] = useState<AnyRecord[]>([]);
  const [projects, setProjects] = useState<AnyRecord[]>([]);
  const [tasks, setTasks] = useState<AnyRecord[]>([]);
  const [auditLog, setAuditLog] = useState<AnyRecord[]>([]);
  const [selectedProjectId, setSelectedProjectId] = useState("");
  const [selectedNodeId, setSelectedNodeId] = useState("");
  const [taskTitle, setTaskTitle] = useState("");
  const [isLoading, setIsLoading] = useState(true);
  const [isDispatching, setIsDispatching] = useState(false);
  const [error, setError] = useState("");

  const selectedProject = useMemo(
    () => projects.find((project) => text(project.id) === selectedProjectId) || null,
    [projects, selectedProjectId]
  );
  const assignableNodes = useMemo(() => {
    const memberIds = new Set(projectMembers(selectedProject || {}).map((member) => text(member.nodeId)).filter(Boolean));
    return nodes.filter((node) => memberIds.has(text(node.id)));
  }, [nodes, selectedProject]);

  const refresh = useCallback(async () => {
    setIsLoading(true);
    setError("");
    try {
      const [nextNodes, nextProjects, nextTasks, nextAuditLog] = await Promise.all([
        coreApi.fetchMeshNodes(),
        coreApi.fetchMeshSharedProjects(),
        coreApi.fetchMeshTasks(),
        coreApi.fetchMeshAuditLog()
      ]);
      setNodes(nextNodes);
      setProjects(nextProjects);
      setTasks(nextTasks);
      setAuditLog(nextAuditLog.slice(0, 12));
      const firstProjectId = text(nextProjects[0]?.id);
      const activeProjectId = selectedProjectId && nextProjects.some((project) => text(project.id) === selectedProjectId)
        ? selectedProjectId
        : firstProjectId;
      setSelectedProjectId(activeProjectId);
      const activeProject = nextProjects.find((project) => text(project.id) === activeProjectId);
      const memberIds = new Set(projectMembers(activeProject || {}).map((member) => text(member.nodeId)).filter(Boolean));
      const firstNodeId = text(nextNodes.find((node) => memberIds.has(text(node.id)))?.id);
      setSelectedNodeId((current) => current && memberIds.has(current) ? current : firstNodeId);
    } catch {
      setError("Mesh state could not be loaded.");
    } finally {
      setIsLoading(false);
    }
  }, [coreApi, selectedProjectId]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  async function dispatchTask() {
    const title = taskTitle.trim();
    if (!title || !selectedProjectId || !selectedNodeId || isDispatching) {
      return;
    }
    setIsDispatching(true);
    setError("");
    try {
      const created = await coreApi.createMeshTask({
        projectId: selectedProjectId,
        title,
        assignedNodeId: selectedNodeId
      });
      if (!created) {
        setError("Task dispatch failed.");
        return;
      }
      setTaskTitle("");
      await refresh();
    } finally {
      setIsDispatching(false);
    }
  }

  return (
    <main className="nodes-shell">
      <header className="nodes-header">
        <div>
          <h1>Node Mesh</h1>
          <p>{nodes.length} nodes / {projects.length} shared projects / {tasks.length} remote tasks</p>
        </div>
        <button type="button" className="nodes-icon-button" onClick={() => void refresh()} disabled={isLoading} title="Refresh">
          <span className="material-symbols-rounded" aria-hidden="true">refresh</span>
        </button>
      </header>

      {error ? <div className="nodes-error">{error}</div> : null}

      <section className="nodes-grid">
        <div className="nodes-panel nodes-panel-wide">
          <div className="nodes-panel-head">
            <h2>Nodes</h2>
            <span>{isLoading ? "syncing" : "current"}</span>
          </div>
          <div className="nodes-list">
            {nodes.length === 0 ? <p className="nodes-empty">No mesh nodes registered.</p> : nodes.map((node) => (
              <button
                key={text(node.id)}
                type="button"
                className={`nodes-row ${selectedNodeId === text(node.id) ? "selected" : ""}`}
                onClick={() => setSelectedNodeId(text(node.id))}
              >
                <span className={`nodes-status-dot ${statusLabel(node.status)}`} />
                <span>
                  <strong>{text(node.name, text(node.id))}</strong>
                  <small>{list(node.roles).join(", ") || "node"} / {list(node.capabilities).join(", ") || "no capabilities"}</small>
                </span>
                <em>{statusLabel(node.status)}</em>
              </button>
            ))}
          </div>
        </div>

        <div className="nodes-panel">
          <div className="nodes-panel-head">
            <h2>Shared Projects</h2>
            <span>{projects.length}</span>
          </div>
          <div className="nodes-list">
            {projects.length === 0 ? <p className="nodes-empty">No shared projects attached.</p> : projects.map((project) => (
              <button
                key={text(project.id)}
                type="button"
                className={`nodes-row ${selectedProjectId === text(project.id) ? "selected" : ""}`}
                onClick={() => setSelectedProjectId(text(project.id))}
              >
                <span className="material-symbols-rounded nodes-row-icon" aria-hidden="true">folder_shared</span>
                <span>
                  <strong>{text(project.name, text(project.id))}</strong>
                  <small>{projectMembers(project).length} members / {text(project.defaultBranch, "main")}</small>
                </span>
              </button>
            ))}
          </div>
        </div>

        <div className="nodes-panel">
          <div className="nodes-panel-head">
            <h2>Dispatch</h2>
            <span>{selectedProject ? text(selectedProject.name, selectedProjectId) : "idle"}</span>
          </div>
          <div className="nodes-dispatch">
            <input
              type="text"
              value={taskTitle}
              onChange={(event) => setTaskTitle(event.target.value)}
              placeholder="Task title"
            />
            <div className="nodes-choice-list">
              {assignableNodes.map((node) => (
                <button
                  key={text(node.id)}
                  type="button"
                  className={selectedNodeId === text(node.id) ? "active" : ""}
                  onClick={() => setSelectedNodeId(text(node.id))}
                >
                  <span>{text(node.name, text(node.id))}</span>
                  <small>{statusLabel(node.status)}</small>
                </button>
              ))}
            </div>
            <button
              type="button"
              className="nodes-primary-button"
              disabled={!taskTitle.trim() || !selectedProjectId || !selectedNodeId || isDispatching}
              onClick={() => void dispatchTask()}
            >
              <span className="material-symbols-rounded" aria-hidden="true">send</span>
              {isDispatching ? "Dispatching" : "Assign Task"}
            </button>
          </div>
        </div>

        <div className="nodes-panel nodes-panel-wide">
          <div className="nodes-panel-head">
            <h2>Remote Lifecycle</h2>
            <span>{tasks.length}</span>
          </div>
          <div className="nodes-task-list">
            {tasks.length === 0 ? <p className="nodes-empty">No remote tasks dispatched.</p> : tasks.map((task) => (
              <article key={text(task.id)} className="nodes-task">
                <div className="nodes-task-main">
                  <strong>{text(task.title, text(task.id))}</strong>
                  <small>{text(task.projectId)} / {nodeName(nodes, text(task.assignedNodeId))}</small>
                </div>
                <span className={`nodes-task-status ${statusLabel(task.status)}`}>{statusLabel(task.status)}</span>
                <div className="nodes-task-review">
                  <span>{text(task.branch, "no branch")}</span>
                  <span>{text(task.commit, "no commit")}</span>
                  <span>{text(task.summary, "no summary")}</span>
                </div>
              </article>
            ))}
          </div>
        </div>

        <div className="nodes-panel">
          <div className="nodes-panel-head">
            <h2>Audit</h2>
            <span>{auditLog.length}</span>
          </div>
          <div className="nodes-audit-list">
            {auditLog.length === 0 ? <p className="nodes-empty">No audit events.</p> : auditLog.map((entry) => (
              <div key={text(entry.id, `${text(entry.action)}-${text(entry.time)}`)} className="nodes-audit-row">
                <strong>{text(entry.action)}</strong>
                <small>{text(entry.actor)} / {formatTime(entry.time)}</small>
              </div>
            ))}
          </div>
        </div>
      </section>
    </main>
  );
}
