import React, { useEffect, useMemo, useState } from "react";
import {
  createProjectWorkflow,
  deleteProjectWorkflow,
  fetchProjectWorkflowActions,
  fetchProjectWorkflowRuns,
  fetchProjectWorkflows,
  resolveProjectWorkflowAction,
  startProjectWorkflowRun
} from "../../api";
import { buildWorkflowGraphLayout, selectWorkflowAfterDelete } from "./projectWorkflows";

type AnyRecord = Record<string, any>;

interface ProjectWorkflowsTabProps {
  project: AnyRecord;
  selectedTask?: AnyRecord | null;
}

const STARTER_WORKFLOW = {
  name: "Dashboard Approval",
  enabled: true,
  lanes: [
    { id: "system", title: "System", kind: "system" },
    { id: "owner", title: "Owner", kind: "human", actorId: "human:admin" }
  ],
  nodes: [
    { id: "start", type: "trigger", title: "Manual start", laneId: "system", config: { mode: "manual" }, positionX: 80, positionY: 80 },
    { id: "approval", type: "human_approval", title: "Approve", laneId: "owner", config: { prompt: "Approve this workflow run?" }, positionX: 360, positionY: 80 },
    { id: "done", type: "end", title: "Done", laneId: "system", config: { status: "completed" }, positionX: 640, positionY: 80 }
  ],
  edges: [
    { id: "e_start_approval", sourceNodeId: "start", targetNodeId: "approval" },
    { id: "e_approval_done", sourceNodeId: "approval", targetNodeId: "done", conditionKey: "approved" }
  ]
};

function formatStatus(value: unknown) {
  return String(value || "unknown").replace(/_/g, " ");
}

function formatDate(value: unknown) {
  if (!value) return "";
  const date = new Date(String(value));
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleString();
}

function workflowNodeIcon(type: unknown) {
  switch (String(type || "")) {
    case "trigger":
      return "play_circle";
    case "human_approval":
    case "human_input":
      return "approval";
    case "condition":
      return "alt_route";
    case "update_task":
    case "project_task":
      return "task_alt";
    case "tool_check":
      return "fact_check";
    case "end":
      return "flag";
    default:
      return "adjust";
  }
}

export function ProjectWorkflowsTab({ project, selectedTask }: ProjectWorkflowsTabProps) {
  const [workflows, setWorkflows] = useState<AnyRecord[]>([]);
  const [runs, setRuns] = useState<AnyRecord[]>([]);
  const [actions, setActions] = useState<AnyRecord[]>([]);
  const [selectedWorkflowId, setSelectedWorkflowId] = useState("");
  const [isBusy, setIsBusy] = useState(false);

  const selectedWorkflow = useMemo(
    () => workflows.find((workflow) => workflow.id === selectedWorkflowId) || workflows[0] || null,
    [selectedWorkflowId, workflows]
  );

  async function load() {
    const [nextWorkflows, nextRuns, nextActions] = await Promise.all([
      fetchProjectWorkflows(project.id),
      fetchProjectWorkflowRuns(project.id),
      fetchProjectWorkflowActions(project.id)
    ]);
    setWorkflows(nextWorkflows || []);
    setRuns(nextRuns || []);
    setActions(nextActions || []);
    if (!selectedWorkflowId && nextWorkflows?.[0]?.id) {
      setSelectedWorkflowId(String(nextWorkflows[0].id));
    }
  }

  useEffect(() => {
    void load();
  }, [project.id]);

  async function createStarterWorkflow() {
    setIsBusy(true);
    try {
      const created = await createProjectWorkflow(project.id, STARTER_WORKFLOW);
      await load();
      if (created?.id) setSelectedWorkflowId(String(created.id));
    } finally {
      setIsBusy(false);
    }
  }

  async function startRun() {
    if (!selectedWorkflow?.id) return;
    setIsBusy(true);
    try {
      await startProjectWorkflowRun(project.id, String(selectedWorkflow.id), {
        taskId: selectedTask?.id || null,
        startedBy: "human:admin",
        input: { source: "dashboard" }
      });
      await load();
    } finally {
      setIsBusy(false);
    }
  }

  async function deleteSelectedWorkflow() {
    if (!selectedWorkflow?.id) return;
    const workflowId = String(selectedWorkflow.id);
    setIsBusy(true);
    try {
      const didDelete = await deleteProjectWorkflow(project.id, workflowId);
      if (didDelete) {
        setSelectedWorkflowId(selectWorkflowAfterDelete(workflows, workflowId));
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
      await load();
    } finally {
      setIsBusy(false);
    }
  }

  const lanes = Array.isArray(selectedWorkflow?.lanes) ? selectedWorkflow.lanes : [];
  const workflowGraph = useMemo(
    () => buildWorkflowGraphLayout(selectedWorkflow),
    [selectedWorkflow]
  );

  return (
    <section className="project-tab-layout project-workflows-shell">
      <header className="project-workflows-toolbar">
        <div>
          <h2>Workflows</h2>
          <p>{selectedTask ? `Task: ${selectedTask.title}` : "Manual project workflow runs"}</p>
        </div>
        <div className="project-workflows-actions">
          <button type="button" className="agents-secondary-button" onClick={createStarterWorkflow} disabled={isBusy}>
            <span className="material-symbols-rounded">account_tree</span>
            Starter
          </button>
          <button type="button" className="agents-create-inline" onClick={startRun} disabled={isBusy || !selectedWorkflow}>
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
              className={`project-workflow-row ${selectedWorkflow?.id === workflow.id ? "active" : ""}`}
              onClick={() => setSelectedWorkflowId(String(workflow.id))}
            >
              <span>{workflow.name}</span>
              <small>v{workflow.version}</small>
            </button>
          ))}
        </aside>

        <section className="project-workflows-board-pane" aria-label="Workflow board">
          <div className="project-workflows-board-scroller">
            <div
              className="project-workflows-board"
              style={{ width: workflowGraph.width, height: workflowGraph.height }}
            >
              {selectedWorkflow ? (
                <>
                  <div className="project-workflows-lane-strip" aria-label="Workflow lanes">
                    {lanes.map((lane: AnyRecord) => (
                      <span key={lane.id}>
                        <strong>{lane.title}</strong>
                        <small>{lane.kind}</small>
                      </span>
                    ))}
                  </div>

                  <svg className="project-workflows-links-layer" aria-hidden="true">
                    <defs>
                      <marker
                        id="project-workflow-arrow"
                        markerWidth="10"
                        markerHeight="10"
                        refX="8"
                        refY="5"
                        orient="auto"
                        markerUnits="strokeWidth"
                      >
                        <path d="M 0 0 L 10 5 L 0 10 z" />
                      </marker>
                    </defs>
                    {workflowGraph.links.map((link: AnyRecord) => (
                      <g key={link.id}>
                        <path d={link.path} className="project-workflow-link" markerEnd="url(#project-workflow-arrow)" />
                        <path d={link.path} className="project-workflow-link-flow" />
                        {link.label ? (
                          <text x={link.midX} y={link.midY} className="project-workflow-link-label">
                            {link.label}
                          </text>
                        ) : null}
                      </g>
                    ))}
                  </svg>

                  {workflowGraph.nodes.map((node: AnyRecord) => {
                    const lane = workflowGraph.laneMap.get(String(node.laneId || ""));
                    return (
                      <article
                        className={`project-workflow-node ${formatStatus(node.type).replace(/\s+/g, "-")}`}
                        key={node.id}
                        style={{ left: node.positionX, top: node.positionY }}
                      >
                        <span className="material-symbols-rounded">{workflowNodeIcon(node.type)}</span>
                        <div>
                          <strong>{node.title}</strong>
                          <small>{formatStatus(node.type)}</small>
                          <em>{lane?.title || node.laneId || "Unassigned"}</em>
                        </div>
                      </article>
                    );
                  })}
                </>
              ) : (
                <div className="project-workflows-empty-canvas">
                  <span className="material-symbols-rounded">account_tree</span>
                  <p>Create a starter workflow to begin.</p>
                </div>
              )}
            </div>
          </div>
        </section>

        <aside className="project-workflows-inspector">
          <section>
            <header className="project-workflows-panel-header">
              <strong>Selected</strong>
            </header>
            {selectedWorkflow ? (
              <article className="project-workflow-action">
                <strong>{selectedWorkflow.name}</strong>
                <small>v{selectedWorkflow.version} · {selectedWorkflow.enabled === false ? "disabled" : "enabled"}</small>
                <div>
                  <button type="button" onClick={deleteSelectedWorkflow} disabled={isBusy}>Delete</button>
                </div>
              </article>
            ) : (
              <p className="placeholder-text">No workflow selected.</p>
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
              <article className="project-workflow-run" key={run.id}>
                <span>{formatStatus(run.status)}</span>
                <small>{formatDate(run.startedAt)}</small>
              </article>
            ))}
          </section>
        </aside>
      </div>
    </section>
  );
}
