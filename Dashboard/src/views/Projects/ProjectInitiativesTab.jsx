import React, { useEffect, useMemo, useState } from "react";
import {
  fetchInitiativeActivities,
  createProjectInitiative,
  fetchInitiativeArtifacts,
  fetchInitiativeDecisionPackets,
  fetchProjectInitiatives,
  updateInitiativeDecisionPacket,
  updateProjectInitiative
} from "../../api";
import { LoadingSkeleton } from "../../components/LoadingSkeleton";

const PHASE_LABELS = {
  intake: "Intake",
  framing: "Framing",
  researching: "Researching",
  planning: "Planning",
  executing: "Executing",
  verifying: "Verifying",
  reviewing: "Reviewing",
  needs_user_decision: "Needs User Decision",
  blocked: "Blocked",
  done: "Done",
  abandoned: "Abandoned"
};

const MODE_LABELS = {
  single_agent: "Single Agent",
  delegation: "Delegation",
  swarm: "Swarm",
  council_review: "Council Review"
};

const PHASE_OPTIONS = [
  "intake",
  "framing",
  "researching",
  "planning",
  "executing",
  "verifying",
  "reviewing",
  "needs_user_decision",
  "blocked",
  "done",
  "abandoned"
];

const MODE_OPTIONS = ["single_agent", "delegation", "swarm", "council_review"];

function asString(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text || fallback;
}

function normalizeInitiative(item, index = 0) {
  const id = asString(item?.id, `initiative-${index + 1}`);
  return {
    id,
    title: asString(item?.title, `Initiative ${index + 1}`),
    goal: asString(item?.goal),
    phase: asString(item?.phase, "intake"),
    executionMode: asString(item?.executionMode ?? item?.execution_mode, "single_agent"),
    resumePoint: asString(item?.resumePoint ?? item?.resume_point),
    blocker: asString(item?.blocker),
    successMetrics: Array.isArray(item?.successMetrics) ? item.successMetrics.map((entry) => asString(entry)).filter(Boolean) : [],
    constraints: Array.isArray(item?.constraints) ? item.constraints.map((entry) => asString(entry)).filter(Boolean) : [],
    metadata: item?.metadata && typeof item.metadata === "object" ? item.metadata : {},
    createdAt: asString(item?.createdAt ?? item?.created_at),
    updatedAt: asString(item?.updatedAt ?? item?.updated_at)
  };
}

function normalizeDecisionPacket(item, index = 0) {
  return {
    id: asString(item?.id, `packet-${index + 1}`),
    summary: asString(item?.summary, `Decision ${index + 1}`),
    rationale: asString(item?.rationale),
    requestedAction: asString(item?.requestedAction ?? item?.requested_action),
    resumePoint: asString(item?.resumePoint ?? item?.resume_point),
    status: asString(item?.status, "open"),
    tradeoffs: Array.isArray(item?.tradeoffs) ? item.tradeoffs.map((entry) => asString(entry)).filter(Boolean) : [],
    updatedAt: asString(item?.updatedAt ?? item?.updated_at)
  };
}

function formatDateTime(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "";
  }
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short"
  }).format(date);
}

function previewText(value, limit = 220) {
  const normalized = asString(value).replace(/\s+/g, " ").trim();
  if (!normalized) {
    return "";
  }
  return normalized.length > limit ? `${normalized.slice(0, limit)}...` : normalized;
}

function ProjectInitiativeCard({
  initiative,
  isSelected,
  onSelect,
  onAdvancePhase,
  onAdvanceMode,
  isSaving
}) {
  return (
    <article className={`project-pane ${isSelected ? "project-pane--active" : ""}`}>
      <div className="project-pane-head">
        <div>
          <h4>{initiative.title}</h4>
          <p className="placeholder-text">{previewText(initiative.goal, 140) || "No goal provided."}</p>
        </div>
        <button type="button" className="project-pane-link" onClick={() => onSelect(initiative.id)}>
          {isSelected ? "Selected" : "Open"}
        </button>
      </div>

      <div className="project-overview-task-meta">
        <span>{PHASE_LABELS[initiative.phase] || initiative.phase}</span>
        <span>{MODE_LABELS[initiative.executionMode] || initiative.executionMode}</span>
        {initiative.updatedAt ? <span>{formatDateTime(initiative.updatedAt)}</span> : null}
      </div>

      {initiative.resumePoint ? (
        <p className="placeholder-text"><strong>Resume:</strong> {initiative.resumePoint}</p>
      ) : null}
      {initiative.blocker ? (
        <p className="placeholder-text"><strong>Blocker:</strong> {initiative.blocker}</p>
      ) : null}

      <div className="project-worker-modal-actions">
        <button
          type="button"
          className="secondary-action"
          disabled={isSaving}
          onClick={() => onAdvancePhase(initiative)}
        >
          Advance Phase
        </button>
        <button
          type="button"
          className="secondary-action"
          disabled={isSaving}
          onClick={() => onAdvanceMode(initiative)}
        >
          Advance Mode
        </button>
      </div>
    </article>
  );
}

export function ProjectInitiativesTab({ project }) {
  const projectId = asString(project?.id);
  const [initiatives, setInitiatives] = useState([]);
  const [selectedInitiativeId, setSelectedInitiativeId] = useState("");
  const [decisionPackets, setDecisionPackets] = useState([]);
  const [artifacts, setArtifacts] = useState([]);
  const [activities, setActivities] = useState([]);
  const [statusText, setStatusText] = useState("Loading initiatives...");
  const [isLoading, setIsLoading] = useState(false);
  const [isCreating, setIsCreating] = useState(false);
  const [savingInitiativeId, setSavingInitiativeId] = useState("");
  const [resolvingPacketId, setResolvingPacketId] = useState("");

  useEffect(() => {
    if (!projectId) {
      return undefined;
    }
    let cancelled = false;

    async function load() {
      setIsLoading(true);
      setStatusText("Loading initiatives...");
      try {
        const items = await fetchProjectInitiatives(projectId);
        if (cancelled) return;
        const normalized = items.map(normalizeInitiative);
        setInitiatives(normalized);
        setSelectedInitiativeId((current) => {
          if (current && normalized.some((initiative) => initiative.id === current)) {
            return current;
          }
          return normalized[0]?.id || "";
        });
        setStatusText(normalized.length > 0 ? `Loaded ${normalized.length} initiatives` : "No initiatives yet.");
      } catch (error) {
        if (!cancelled) {
          setStatusText(`Failed to load initiatives: ${error instanceof Error ? error.message : "Unknown error"}`);
          setInitiatives([]);
          setSelectedInitiativeId("");
        }
      } finally {
        if (!cancelled) {
          setIsLoading(false);
        }
      }
    }

    load();
    return () => {
      cancelled = true;
    };
  }, [projectId]);

  const selectedInitiative = useMemo(
    () => initiatives.find((initiative) => initiative.id === selectedInitiativeId) || initiatives[0] || null,
    [initiatives, selectedInitiativeId]
  );

  const packetCounts = useMemo(() => {
    let open = 0;
    let resolved = 0;
    for (const packet of decisionPackets) {
      if (packet.status === "resolved") {
        resolved += 1;
      } else {
        open += 1;
      }
    }
    return { open, resolved };
  }, [decisionPackets]);

  const linkedTasks = useMemo(() => {
    if (!selectedInitiative?.id) {
      return [];
    }
    const tasks = Array.isArray(project?.tasks) ? project.tasks : [];
    return tasks.filter((task) => String(task?.initiativeID || task?.initiativeId || "").trim() === selectedInitiative.id);
  }, [project?.tasks, selectedInitiative?.id]);

  const linkedTaskCounts = useMemo(() => {
    const counts = {
      total: linkedTasks.length,
      done: 0,
      blocked: 0,
      active: 0
    };
    for (const task of linkedTasks) {
      const status = asString(task?.status).toLowerCase();
      if (status === "done") {
        counts.done += 1;
      } else if (status === "blocked") {
        counts.blocked += 1;
      } else {
        counts.active += 1;
      }
    }
    return counts;
  }, [linkedTasks]);

  useEffect(() => {
    if (!projectId || !selectedInitiative?.id) {
      setDecisionPackets([]);
      setArtifacts([]);
      setActivities([]);
      return undefined;
    }
    let cancelled = false;

    async function loadRelated() {
      try {
        const [packetItems, artifactItems, activityItems] = await Promise.all([
          fetchInitiativeDecisionPackets(projectId, selectedInitiative.id),
          fetchInitiativeArtifacts(projectId, selectedInitiative.id),
          fetchInitiativeActivities(projectId, selectedInitiative.id)
        ]);
        if (!cancelled) {
          setDecisionPackets(packetItems.map(normalizeDecisionPacket));
          setArtifacts(
            artifactItems.map((item, index) => ({
              id: asString(item?.path, `artifact-${index + 1}`),
              path: asString(item?.path, `artifact-${index + 1}`)
            }))
          );
          setActivities(
            activityItems.map((item, index) => ({
              id: asString(item?.id, `activity-${index + 1}`),
              kind: asString(item?.kind, "activity"),
              title: asString(item?.title, `Activity ${index + 1}`),
              message: asString(item?.message),
              createdAt: asString(item?.createdAt ?? item?.created_at)
            }))
          );
        }
      } catch {
        if (!cancelled) {
          setDecisionPackets([]);
          setArtifacts([]);
          setActivities([]);
        }
      }
    }

    loadRelated();
    return () => {
      cancelled = true;
    };
  }, [projectId, selectedInitiative?.id]);

  async function handleCreateInitiative() {
    if (!projectId || isCreating) {
      return;
    }
    setIsCreating(true);
    try {
      const created = await createProjectInitiative(projectId, {
        title: "New initiative",
        goal: "Describe the goal and refine it from the Dashboard.",
        successMetrics: [],
        constraints: []
      });
      if (!created) {
        setStatusText("Failed to create initiative.");
        return;
      }
      const normalized = normalizeInitiative(created, initiatives.length);
      setInitiatives((current) => [...current, normalized]);
      setSelectedInitiativeId(normalized.id);
      setStatusText(`Created initiative ${normalized.title}`);
    } finally {
      setIsCreating(false);
    }
  }

  async function handleAdvancePhase(initiative) {
    if (!projectId || !initiative?.id) {
      return;
    }
    const currentIndex = PHASE_OPTIONS.indexOf(initiative.phase);
    const nextPhase = PHASE_OPTIONS[Math.min(currentIndex + 1, PHASE_OPTIONS.length - 1)] || initiative.phase;
    if (nextPhase === initiative.phase) {
      return;
    }
    setSavingInitiativeId(initiative.id);
    try {
      const updated = await updateProjectInitiative(projectId, initiative.id, { phase: nextPhase });
      if (!updated) {
        setStatusText(`Failed to update ${initiative.title}.`);
        return;
      }
      const normalized = normalizeInitiative(updated);
      setInitiatives((current) => current.map((item) => (item.id === normalized.id ? normalized : item)));
      setStatusText(`Moved ${initiative.title} to ${PHASE_LABELS[nextPhase] || nextPhase}`);
    } finally {
      setSavingInitiativeId("");
    }
  }

  async function handleAdvanceMode(initiative) {
    if (!projectId || !initiative?.id) {
      return;
    }
    const currentIndex = MODE_OPTIONS.indexOf(initiative.executionMode);
    const nextMode = MODE_OPTIONS[Math.min(currentIndex + 1, MODE_OPTIONS.length - 1)] || initiative.executionMode;
    if (nextMode === initiative.executionMode) {
      return;
    }
    setSavingInitiativeId(initiative.id);
    try {
      const updated = await updateProjectInitiative(projectId, initiative.id, { executionMode: nextMode });
      if (!updated) {
        setStatusText(`Failed to update ${initiative.title}.`);
        return;
      }
      const normalized = normalizeInitiative(updated);
      setInitiatives((current) => current.map((item) => (item.id === normalized.id ? normalized : item)));
      setStatusText(`Moved ${initiative.title} to ${MODE_LABELS[nextMode] || nextMode}`);
    } finally {
      setSavingInitiativeId("");
    }
  }

  async function handleResolvePacket(packet) {
    if (!projectId || !selectedInitiative?.id || !packet?.id || resolvingPacketId) {
      return;
    }
    setResolvingPacketId(packet.id);
    try {
      const resolved = await updateInitiativeDecisionPacket(projectId, selectedInitiative.id, packet.id, {
        status: "resolved",
        resumePoint: packet.resumePoint || `Resume ${selectedInitiative.title}`
      });
      if (!resolved) {
        setStatusText(`Failed to resolve ${packet.summary}.`);
        return;
      }
      setDecisionPackets((current) =>
        current.map((item) => (item.id === packet.id ? normalizeDecisionPacket(resolved) : item))
      );
      const refreshedInitiatives = await fetchProjectInitiatives(projectId);
      const normalized = refreshedInitiatives.map(normalizeInitiative);
      setInitiatives(normalized);
      const refreshedActivities = await fetchInitiativeActivities(projectId, selectedInitiative.id);
      setActivities(
        refreshedActivities.map((item, index) => ({
          id: asString(item?.id, `activity-${index + 1}`),
          kind: asString(item?.kind, "activity"),
          title: asString(item?.title, `Activity ${index + 1}`),
          message: asString(item?.message),
          createdAt: asString(item?.createdAt ?? item?.created_at)
        }))
      );
      setStatusText(`Resolved ${packet.summary}`);
    } finally {
      setResolvingPacketId("");
    }
  }

  return (
    <section className="project-tab-layout">
      <section className="project-pane">
        <div className="project-pane-head">
          <div>
            <h4>Initiatives</h4>
            <p className="placeholder-text">Long-lived goals with explicit phase, execution mode, and decision packets.</p>
          </div>
          <button type="button" className="project-pane-link" onClick={handleCreateInitiative} disabled={isCreating}>
            {isCreating ? "Creating..." : "New Initiative"}
          </button>
        </div>
        <p className="placeholder-text">{statusText}</p>
      </section>

      {isLoading ? (
        <LoadingSkeleton label="Loading initiatives…" variant="cards" cards={3} />
      ) : initiatives.length === 0 ? (
        <section className="project-pane">
          <p className="placeholder-text">No initiatives yet. Create one to start tracking long-lived autonomous work.</p>
        </section>
      ) : (
        <div className="project-analytics-grid">
          <div>
            {initiatives.map((initiative) => (
              <ProjectInitiativeCard
                key={initiative.id}
                initiative={initiative}
                isSelected={initiative.id === selectedInitiative?.id}
                onSelect={setSelectedInitiativeId}
                onAdvancePhase={handleAdvancePhase}
                onAdvanceMode={handleAdvanceMode}
                isSaving={savingInitiativeId === initiative.id}
              />
            ))}
          </div>

          <section className="project-pane">
            <div className="project-pane-head">
              <h4>{selectedInitiative?.title || "Initiative details"}</h4>
            </div>
            {selectedInitiative ? (
              <>
                <p>{selectedInitiative.goal || "No goal provided."}</p>

                <div className="project-overview-task-meta">
                  <span>{PHASE_LABELS[selectedInitiative.phase] || selectedInitiative.phase}</span>
                  <span>{MODE_LABELS[selectedInitiative.executionMode] || selectedInitiative.executionMode}</span>
                  {selectedInitiative.updatedAt ? <span>{formatDateTime(selectedInitiative.updatedAt)}</span> : null}
                </div>

                <div className="project-overview-card-list">
                  <article className="project-overview-card">
                    <strong>Success metrics</strong>
                    {selectedInitiative.successMetrics.length === 0 ? (
                      <p className="placeholder-text">No success metrics defined.</p>
                    ) : (
                      <ul className="project-overview-list">
                        {selectedInitiative.successMetrics.map((metric) => <li key={metric}>{metric}</li>)}
                      </ul>
                    )}
                  </article>
                  <article className="project-overview-card">
                    <strong>Constraints</strong>
                    {selectedInitiative.constraints.length === 0 ? (
                      <p className="placeholder-text">No constraints defined.</p>
                    ) : (
                      <ul className="project-overview-list">
                        {selectedInitiative.constraints.map((constraint) => <li key={constraint}>{constraint}</li>)}
                      </ul>
                    )}
                  </article>
                  <article className="project-overview-card">
                    <strong>Decision packets</strong>
                    <p className="placeholder-text">Open: {packetCounts.open}</p>
                    <p className="placeholder-text">Resolved: {packetCounts.resolved}</p>
                  </article>
                  <article className="project-overview-card">
                    <strong>Linked tasks</strong>
                    <p className="placeholder-text">Total: {linkedTaskCounts.total}</p>
                    <p className="placeholder-text">Done: {linkedTaskCounts.done}</p>
                    <p className="placeholder-text">Blocked: {linkedTaskCounts.blocked}</p>
                    <p className="placeholder-text">Active: {linkedTaskCounts.active}</p>
                  </article>
                  <article className="project-overview-card">
                    <strong>Artifacts</strong>
                    <p className="placeholder-text">{artifacts.length} linked artifact file{artifacts.length === 1 ? "" : "s"}</p>
                  </article>
                </div>

                <article className="project-pane">
                  <div className="project-pane-head">
                    <h4>Activity</h4>
                  </div>
                  {activities.length === 0 ? (
                    <p className="placeholder-text">No initiative activity yet.</p>
                  ) : (
                    <div className="project-overview-task-list">
                      {activities
                        .slice()
                        .reverse()
                        .map((activity) => (
                          <article key={activity.id} className="project-overview-task">
                            <div className="project-overview-task-head">
                              <strong>{activity.title}</strong>
                              <span className="project-overview-task-status">{activity.kind}</span>
                            </div>
                            {activity.message ? <p className="placeholder-text">{activity.message}</p> : null}
                            {activity.createdAt ? (
                              <div className="project-overview-task-meta">
                                <span>{formatDateTime(activity.createdAt)}</span>
                              </div>
                            ) : null}
                          </article>
                        ))}
                    </div>
                  )}
                </article>

                <article className="project-pane">
                  <div className="project-pane-head">
                    <h4>Decision packets</h4>
                  </div>
                  {decisionPackets.length === 0 ? (
                    <p className="placeholder-text">No decision packets for this initiative yet.</p>
                  ) : (
                    <div className="project-overview-task-list">
                      {decisionPackets.map((packet) => (
                        <article key={packet.id} className="project-overview-task">
                          <div className="project-overview-task-head">
                            <strong>{packet.summary}</strong>
                            <span className="project-overview-task-status">{packet.status}</span>
                          </div>
                          <p className="placeholder-text">{previewText(packet.rationale, 180) || "No rationale provided."}</p>
                          {packet.requestedAction ? (
                            <div className="project-overview-task-meta">
                              <span>{packet.requestedAction}</span>
                              {packet.resumePoint ? <span>Resume: {packet.resumePoint}</span> : null}
                            </div>
                          ) : null}
                          {packet.status !== "resolved" ? (
                            <div className="project-worker-modal-actions">
                              <button
                                type="button"
                                className="secondary-action"
                                disabled={resolvingPacketId === packet.id}
                                onClick={() => handleResolvePacket(packet)}
                              >
                                {resolvingPacketId === packet.id ? "Resolving..." : "Resolve"}
                              </button>
                            </div>
                          ) : null}
                        </article>
                      ))}
                    </div>
                  )}
                </article>

                <article className="project-pane">
                  <div className="project-pane-head">
                    <h4>Linked Tasks</h4>
                  </div>
                  {linkedTasks.length === 0 ? (
                    <p className="placeholder-text">No linked tasks for this initiative yet.</p>
                  ) : (
                    <div className="project-overview-task-list">
                      {linkedTasks.map((task) => (
                        <article key={asString(task?.id)} className="project-overview-task">
                          <div className="project-overview-task-head">
                            <strong>{asString(task?.title, asString(task?.id, "Task"))}</strong>
                            <span className="project-overview-task-status">{asString(task?.status, "unknown")}</span>
                          </div>
                          <p className="placeholder-text">{previewText(task?.description, 180) || "No description provided."}</p>
                        </article>
                      ))}
                    </div>
                  )}
                </article>

                <article className="project-pane">
                  <div className="project-pane-head">
                    <h4>Artifacts</h4>
                  </div>
                  {artifacts.length === 0 ? (
                    <p className="placeholder-text">No initiative-local artifacts yet.</p>
                  ) : (
                    <div className="project-created-list">
                      {artifacts.map((artifact) => (
                        <article key={artifact.id} className="project-created-item">
                          <div className="project-overview-output-head">
                            <strong>Artifact</strong>
                          </div>
                          <p>{artifact.path}</p>
                        </article>
                      ))}
                    </div>
                  )}
                </article>
              </>
            ) : (
              <p className="placeholder-text">Select an initiative to inspect its details.</p>
            )}
          </section>
        </div>
      )}
    </section>
  );
}
