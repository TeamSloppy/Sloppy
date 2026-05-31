import React, { useState, useRef, useEffect, useCallback, useMemo } from "react";
import ReactMarkdown from "react-markdown";
import {
    TASK_STATUSES,
    TASK_PRIORITIES,
    TASK_PRIORITY_LABELS,
    TASK_STATUS_COLORS,
    TASK_PRIORITY_ICONS,
    TASK_KINDS,
    LOOP_MODES,
    buildTaskCounts,
    buildSwarmGroups,
    formatRelativeTime,
    sortTasksByDate
} from "./utils";
import {
    fetchTaskComments,
    addTaskComment,
    deleteTaskComment,
    fetchTaskActivities,
    fetchTaskLogs,
    fetchTaskClarifications,
    answerTaskClarification,
    fetchTaskDiff,
    fetchReviewComments,
    addReviewComment,
    updateReviewComment,
    deleteReviewComment,
    createAgentSession,
    postAgentSessionMessage,
    fetchAgentSessions,
    fetchAgents,
    fetchArchivedTasks
} from "../../api";
import { AgentPetIcon } from "../../features/agents/components/AgentPetSprite";
import { ReviewDiffPanel } from "./ReviewDiffPanel";

function assigneeInitials(name) {
    const parts = String(name || "?")
        .trim()
        .split(/[\s_-]+/)
        .filter(Boolean);
    if (parts.length === 0) return "??";
    if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
}

function TaskCardSloppieSlot({ parts, genomeHex, label }) {
    if (parts) {
        return (
            <span className="agent-kanban-sloppie">
                <AgentPetIcon parts={parts} genomeHex={genomeHex} />
            </span>
        );
    }
    if (label) {
        return (
            <span className="agent-kanban-sloppie-fallback" aria-hidden="true">
                {assigneeInitials(label)}
            </span>
        );
    }
    return null;
}

function resolveClaimedAgentSloppie(task, agentDirectory) {
    const agentId = String(task.claimedAgentId || "").trim();
    if (!agentId) return null;
    const entry = agentDirectory[agentId];
    return {
        parts: entry?.pet?.parts,
        genomeHex: entry?.pet?.genomeHex,
        label: entry?.displayName || agentId
    };
}

function resolveActorLinkedSloppie(actorId, createModalActors, agentDirectory) {
    const id = String(actorId || "").trim();
    if (!id) return null;
    const actor = createModalActors.find((a) => a.id === id);
    const linked = String(actor?.linkedAgentId || "").trim();
    if (!linked) return null;
    const entry = agentDirectory[linked];
    return {
        parts: entry?.pet?.parts,
        genomeHex: entry?.pet?.genomeHex,
        label: actor?.displayName || id
    };
}

function formatTaskAttachmentSize(bytes) {
    const size = Number(bytes || 0);
    if (size >= 1024 * 1024) return `${(size / (1024 * 1024)).toFixed(1)} MB`;
    if (size >= 1024) return `${Math.round(size / 1024)} KB`;
    return `${size} B`;
}

function ProjectKanbanClaimedAgentBadge({ task, agentDirectory }) {
    const ca = resolveClaimedAgentSloppie(task, agentDirectory);
    return (
        <span className="project-task-claim-badge project-task-claim-badge--with-sloppie">
            <TaskCardSloppieSlot parts={ca?.parts} genomeHex={ca?.genomeHex} label={ca?.label} />
            <span>Agent: {ca?.label || task.claimedAgentId}</span>
        </span>
    );
}

function ProjectKanbanClaimedActorBadge({ task, createModalActors, agentDirectory }) {
    const ar = resolveActorLinkedSloppie(task.claimedActorId, createModalActors, agentDirectory);
    const actorLabel =
        createModalActors.find((a) => a.id === task.claimedActorId)?.displayName || task.claimedActorId;
    return (
        <span className={`project-task-claim-badge ${ar ? "project-task-claim-badge--with-sloppie" : ""}`}>
            {ar ? (
                <TaskCardSloppieSlot parts={ar.parts} genomeHex={ar.genomeHex} label={ar.label} />
            ) : (
                <span className="material-symbols-rounded" aria-hidden="true">
                    person
                </span>
            )}
            <span>Actor: {actorLabel}</span>
        </span>
    );
}

function ProjectKanbanAssignedActorBadge({ task, createModalActors, agentDirectory }) {
    const ar = resolveActorLinkedSloppie(task.actorId, createModalActors, agentDirectory);
    const actorLabel = createModalActors.find((a) => a.id === task.actorId)?.displayName || task.actorId;
    return (
        <span className={`project-task-assignee-badge ${ar ? "project-task-assignee-badge--with-sloppie" : ""}`}>
            {ar ? (
                <TaskCardSloppieSlot parts={ar.parts} genomeHex={ar.genomeHex} label={ar.label} />
            ) : (
                <span className="material-symbols-rounded" aria-hidden="true">
                    assignment_ind
                </span>
            )}
            <span>Assigned actor: {actorLabel}</span>
        </span>
    );
}

function DetailDropdown({ label, icon, color, children }) {
    const [open, setOpen] = useState(false);
    const ref = useRef(null);

    useEffect(() => {
        if (!open) return;
        function handleClick(e) {
            if (ref.current && !ref.current.contains(e.target)) {
                setOpen(false);
            }
        }
        document.addEventListener("mousedown", handleClick);
        return () => document.removeEventListener("mousedown", handleClick);
    }, [open]);

    return (
        <div className="td-prop-dropdown-wrap" ref={ref}>
            <button
                type="button"
                className={`td-prop-value ${open ? "active" : ""}`}
                onClick={() => setOpen(!open)}
            >
                {color ? (
                    <span className="tcm-status-dot" style={{ background: color }} />
                ) : icon ? (
                    <span className="material-symbols-rounded td-prop-value-icon">{icon}</span>
                ) : null}
                <span>{label}</span>
            </button>
            {open && (
                <ul className="td-prop-dropdown" onClick={() => setOpen(false)}>
                    {children}
                </ul>
            )}
        </div>
    );
}

function normalizeBulkTag(value) {
    return String(value || "").trim().replace(/^#+/, "").trim();
}

function TaskBulkContextMenu({
    menu,
    selectedCount,
    tagOptions,
    createModalActors,
    createModalTeams,
    busy,
    onClose,
    onPanelChange,
    onMove,
    onAssign,
    onTag,
    onArchive,
    onDelete
}) {
    const [tagDraft, setTagDraft] = useState("");
    const inputRef = useRef(null);

    useEffect(() => {
        if (menu?.panel === "tag" && inputRef.current) {
            inputRef.current.focus();
        }
    }, [menu?.panel]);

    if (!menu) {
        return null;
    }

    const menuWidth = menu.panel === "tag" ? 280 : 260;
    const menuHeight = menu.panel === "assignee" ? 360 : menu.panel === "status" ? 330 : 300;
    const left = Math.min(menu.x, Math.max(8, window.innerWidth - menuWidth - 8));
    const top = Math.min(menu.y, Math.max(8, window.innerHeight - menuHeight - 8));
    const normalizedTag = normalizeBulkTag(tagDraft);

    return (
        <div
            className="project-task-context-menu"
            style={{ left, top, width: menuWidth }}
            role="menu"
            onMouseDown={(event) => event.stopPropagation()}
            onClick={(event) => event.stopPropagation()}
        >
            <div className="project-task-context-menu-head">
                {menu.panel === "main" ? (
                    <>
                        <strong>{selectedCount} selected</strong>
                        <button type="button" onClick={onClose} aria-label="Close menu">
                            <span className="material-symbols-rounded" aria-hidden="true">close</span>
                        </button>
                    </>
                ) : (
                    <>
                        <button type="button" onClick={() => onPanelChange("main")} aria-label="Back">
                            <span className="material-symbols-rounded" aria-hidden="true">arrow_back</span>
                        </button>
                        <strong>
                            {menu.panel === "status" ? "Move to" : menu.panel === "assignee" ? "Assign" : "Set tag"}
                        </strong>
                    </>
                )}
            </div>

            {menu.panel === "main" ? (
                <div className="project-task-context-menu-list">
                    <button type="button" onClick={() => onPanelChange("status")} disabled={busy}>
                        <span className="material-symbols-rounded" aria-hidden="true">drive_file_move</span>
                        <span>Move to...</span>
                        <span className="material-symbols-rounded project-task-context-chevron" aria-hidden="true">chevron_right</span>
                    </button>
                    <button type="button" onClick={() => onPanelChange("assignee")} disabled={busy}>
                        <span className="material-symbols-rounded" aria-hidden="true">assignment_ind</span>
                        <span>Assign...</span>
                        <span className="material-symbols-rounded project-task-context-chevron" aria-hidden="true">chevron_right</span>
                    </button>
                    <button type="button" onClick={() => onPanelChange("tag")} disabled={busy}>
                        <span className="material-symbols-rounded" aria-hidden="true">sell</span>
                        <span>Set tag...</span>
                        <span className="material-symbols-rounded project-task-context-chevron" aria-hidden="true">chevron_right</span>
                    </button>
                    <div className="project-task-context-menu-separator" />
                    <button type="button" onClick={onArchive} disabled={busy}>
                        <span className="material-symbols-rounded" aria-hidden="true">archive</span>
                        <span>Archive selected</span>
                    </button>
                    <button type="button" className="danger" onClick={onDelete} disabled={busy}>
                        <span className="material-symbols-rounded" aria-hidden="true">delete</span>
                        <span>Delete selected</span>
                    </button>
                </div>
            ) : null}

            {menu.panel === "status" ? (
                <div className="project-task-context-menu-list">
                    {TASK_STATUSES.map((status) => (
                        <button key={status.id} type="button" onClick={() => onMove(status.id)} disabled={busy}>
                            <span className="tcm-status-dot" style={{ background: TASK_STATUS_COLORS[status.id] }} />
                            <span>{status.title}</span>
                        </button>
                    ))}
                </div>
            ) : null}

            {menu.panel === "assignee" ? (
                <div className="project-task-context-menu-list project-task-context-menu-list--scroll">
                    <button type="button" onClick={() => onAssign("")} disabled={busy}>
                        <span className="material-symbols-rounded" aria-hidden="true">person_off</span>
                        <span>Unassigned</span>
                    </button>
                    {createModalActors.length > 0 ? <span className="project-task-context-label">Actors</span> : null}
                    {createModalActors.map((actor) => (
                        <button key={actor.id} type="button" onClick={() => onAssign(`actor:${actor.id}`)} disabled={busy}>
                            <span className="material-symbols-rounded" aria-hidden="true">person</span>
                            <span>{actor.displayName}</span>
                            <code>{actor.id}</code>
                        </button>
                    ))}
                    {createModalTeams.length > 0 ? <span className="project-task-context-label">Teams</span> : null}
                    {createModalTeams.map((team) => (
                        <button key={team.id} type="button" onClick={() => onAssign(`team:${team.id}`)} disabled={busy}>
                            <span className="material-symbols-rounded" aria-hidden="true">groups</span>
                            <span>{team.name}</span>
                            <code>{team.id}</code>
                        </button>
                    ))}
                </div>
            ) : null}

            {menu.panel === "tag" ? (
                <form
                    className="project-task-context-tag-form"
                    onSubmit={(event) => {
                        event.preventDefault();
                        if (normalizedTag) {
                            onTag(normalizedTag);
                            setTagDraft("");
                        }
                    }}
                >
                    <input
                        ref={inputRef}
                        value={tagDraft}
                        onChange={(event) => setTagDraft(event.target.value)}
                        placeholder="Tag name"
                    />
                    <button type="submit" disabled={busy || !normalizedTag}>
                        Apply
                    </button>
                    {tagOptions.length > 0 ? (
                        <div className="project-task-context-menu-list project-task-context-menu-list--scroll">
                            {tagOptions.map((tag) => (
                                <button key={tag} type="button" onClick={() => onTag(tag)} disabled={busy}>
                                    <span className="material-symbols-rounded" aria-hidden="true">sell</span>
                                    <span>{tag}</span>
                                </button>
                            ))}
                        </div>
                    ) : null}
                </form>
            ) : null}
        </div>
    );
}

function CommentsTab({ project, task, createModalActors }) {
    const [comments, setComments] = useState([]);
    const [loading, setLoading] = useState(true);
    const [commentText, setCommentText] = useState("");
    const [selectedActorId, setSelectedActorId] = useState("");
    const [actorDropdownOpen, setActorDropdownOpen] = useState(false);
    const [actorSearch, setActorSearch] = useState("");
    const [submitting, setSubmitting] = useState(false);
    const dropdownRef = useRef(null);

    const loadComments = useCallback(async () => {
        const result = await fetchTaskComments(project.id, task.id);
        if (result) setComments(result);
        setLoading(false);
    }, [project.id, task.id]);

    useEffect(() => {
        setLoading(true);
        loadComments();
    }, [loadComments]);

    useEffect(() => {
        if (!actorDropdownOpen) return;
        function handleClick(e) {
            if (dropdownRef.current && !dropdownRef.current.contains(e.target)) {
                setActorDropdownOpen(false);
            }
        }
        document.addEventListener("mousedown", handleClick);
        return () => document.removeEventListener("mousedown", handleClick);
    }, [actorDropdownOpen]);

    const selectedActor = createModalActors.find((a) => a.id === selectedActorId);
    const filteredActors = actorSearch.trim()
        ? createModalActors.filter(
            (a) =>
                a.displayName.toLowerCase().includes(actorSearch.toLowerCase()) ||
                a.id.toLowerCase().includes(actorSearch.toLowerCase())
        )
        : createModalActors;

    async function handleSubmit(e) {
        e.preventDefault();
        const text = commentText.trim();
        if (!text) return;
        setSubmitting(true);
        const payload = {
            content: text,
            authorActorId: "user",
            mentionedActorId: selectedActorId || null
        };
        await addTaskComment(project.id, task.id, payload);
        setCommentText("");
        setSelectedActorId("");
        setActorSearch("");
        await loadComments();
        setSubmitting(false);
    }

    async function handleDelete(commentId) {
        await deleteTaskComment(project.id, task.id, commentId);
        setComments((prev) => prev.filter((c) => c.id !== commentId));
    }

    return (
        <div className="td-comments">
            {loading ? (
                <p className="placeholder-text">Loading comments…</p>
            ) : comments.length === 0 ? (
                <p className="placeholder-text">No comments yet.</p>
            ) : (
                <div className="td-comments-list">
                    {comments.map((comment) => {
                        const author = createModalActors.find((a) => a.id === comment.authorActorId);
                        const authorLabel = author ? author.displayName : comment.authorActorId;
                        const mentionedActor = comment.mentionedActorId
                            ? createModalActors.find((a) => a.id === comment.mentionedActorId)
                            : null;
                        return (
                            <div key={comment.id} className={`td-comment-item ${comment.isAgentReply ? "td-comment-item--agent" : ""}`}>
                                <div className="td-comment-header">
                                    <span className="material-symbols-rounded td-comment-avatar">
                                        {comment.isAgentReply ? "smart_toy" : "person"}
                                    </span>
                                    <span className="td-comment-author">{authorLabel}</span>
                                    {comment.externalMetadata?.origin === "github" && (
                                        <span className="td-comment-agent-badge">GitHub{comment.sourceAuthor ? `: ${comment.sourceAuthor}` : ""}</span>
                                    )}
                                    {comment.isAgentReply && (
                                        <span className="td-comment-agent-badge">Agent reply</span>
                                    )}
                                    {mentionedActor && !comment.isAgentReply && (
                                        <span className="td-comment-mention">
                                            <span className="material-symbols-rounded">alternate_email</span>
                                            {mentionedActor.displayName}
                                            {mentionedActor.linkedAgentId && (
                                                <span className="td-comment-agent-badge">Agent</span>
                                            )}
                                        </span>
                                    )}
                                    <span className="td-comment-time">{formatRelativeTime(comment.createdAt)}</span>
                                    <button
                                        type="button"
                                        className="td-comment-delete-btn"
                                        onClick={() => handleDelete(comment.id)}
                                        aria-label="Delete comment"
                                    >
                                        <span className="material-symbols-rounded">delete</span>
                                    </button>
                                </div>
                                <div className="td-comment-body markdown-body">
                                    <ReactMarkdown>{comment.content}</ReactMarkdown>
                                </div>
                            </div>
                        );
                    })}
                </div>
            )}

            <form className="td-comment-form" onSubmit={handleSubmit}>
                <textarea
                    className="td-comment-textarea"
                    value={commentText}
                    onChange={(e) => setCommentText(e.target.value)}
                    placeholder="Leave a comment..."
                    rows={3}
                />
                <div className="td-comment-form-actions">
                    <span className="material-symbols-rounded td-comment-attach-icon">attachment</span>
                    <div className="td-comment-actor-wrap" ref={dropdownRef}>
                        <button
                            type="button"
                            className={`td-comment-actor-btn ${actorDropdownOpen ? "active" : ""}`}
                            onClick={() => setActorDropdownOpen((v) => !v)}
                        >
                            <span className="material-symbols-rounded">
                                {selectedActor?.linkedAgentId ? "smart_toy" : "person"}
                            </span>
                            <span>{selectedActor ? selectedActor.displayName : "No assignee"}</span>
                        </button>
                        {actorDropdownOpen && (
                            <div className="td-comment-actor-dropdown">
                                <input
                                    className="td-comment-actor-search"
                                    value={actorSearch}
                                    onChange={(e) => setActorSearch(e.target.value)}
                                    placeholder="Search assignees..."
                                    autoFocus
                                />
                                <ul>
                                    <li
                                        className={`tcm-dropdown-item ${!selectedActorId ? "selected" : ""}`}
                                        onMouseDown={(e) => {
                                            e.preventDefault();
                                            setSelectedActorId("");
                                            setActorDropdownOpen(false);
                                        }}
                                    >
                                        No assignee
                                        {!selectedActorId && <span className="tcm-dropdown-check">✓</span>}
                                    </li>
                                    {filteredActors.map((actor) => (
                                        <li
                                            key={actor.id}
                                            className={`tcm-dropdown-item ${selectedActorId === actor.id ? "selected" : ""}`}
                                            onMouseDown={(e) => {
                                                e.preventDefault();
                                                setSelectedActorId(actor.id);
                                                setActorDropdownOpen(false);
                                                setActorSearch("");
                                            }}
                                        >
                                            <span className="material-symbols-rounded tcm-dropdown-item-icon">
                                                {actor.linkedAgentId ? "smart_toy" : "person"}
                                            </span>
                                            <span>{actor.displayName}</span>
                                            <span className="tcm-dropdown-item-id">{actor.id}</span>
                                            {selectedActorId === actor.id && <span className="tcm-dropdown-check">✓</span>}
                                        </li>
                                    ))}
                                </ul>
                            </div>
                        )}
                    </div>
                    <button
                        type="submit"
                        className="td-comment-submit-btn"
                        disabled={!commentText.trim() || submitting}
                    >
                        {submitting ? "Sending…" : "Comment"}
                    </button>
                </div>
            </form>
        </div>
    );
}

const ACTIVITY_FIELD_LABELS = {
    status: "Status",
    priority: "Priority",
    assignee: "Assignee",
    title: "Title",
    description: "Description"
};

const ACTIVITY_FIELD_ICONS = {
    status: "swap_horiz",
    priority: "flag",
    assignee: "person",
    title: "title",
    description: "description"
};

const TASK_LOG_KIND_ICONS = {
    created: "add_circle",
    activity: "history",
    lifecycle: "route",
    tool_invocation: "terminal"
};

function formatActivityValue(field, value, actors) {
    if (!value) return "none";
    if (field === "status") {
        const s = TASK_STATUSES.find((st) => st.id === value);
        return s ? s.title : value;
    }
    if (field === "priority") {
        return TASK_PRIORITY_LABELS[value] || value;
    }
    if (field === "assignee") {
        const actor = actors.find((a) => a.id === value);
        return actor ? actor.displayName : value;
    }
    if (field === "description") {
        if (value.length > 60) return value.slice(0, 60) + "…";
        return value;
    }
    return value;
}

function buildAgentSessionURL(agentId, sessionId) {
    const agent = String(agentId || "").trim();
    const session = String(sessionId || "").trim();
    if (!agent || !session || typeof window === "undefined") return "";
    return `${window.location.origin}/agents/${encodeURIComponent(agent)}/chat/${encodeURIComponent(session)}`;
}

function buildAgentSessionComment(agentName, action, sessionName, sessionURL) {
    const safeAgentName = String(agentName || "Agent").trim() || "Agent";
    const safeSessionName = String(sessionName || "session").trim() || "session";
    return `${safeAgentName} ${action} session [${safeSessionName}](${sessionURL})`;
}

function ActivityTab({ project, task, createModalActors }) {
    const [activities, setActivities] = useState([]);
    const [loading, setLoading] = useState(true);

    const loadActivities = useCallback(async () => {
        const result = await fetchTaskActivities(project.id, task.id);
        if (result) setActivities(result);
        setLoading(false);
    }, [project.id, task.id, task.updatedAt]);

    useEffect(() => {
        setLoading(true);
        loadActivities();
    }, [loadActivities]);

    const resolveActorName = (actorId) => {
        if (!actorId || actorId === "user") return "User";
        const actor = createModalActors.find((a) => a.id === actorId);
        return actor ? actor.displayName : actorId;
    };

    const currentStatus = TASK_STATUSES.find((status) => status.id === task.status);
    const currentStatusLabel = currentStatus?.title || task.status || "Backlog";
    const currentStatusColor = TASK_STATUS_COLORS[task.status] || "#94a3b8";

    return (
        <div className="td-activity-list">
            <div className="td-activity-status-card">
                <span className="td-activity-status-label">Current status</span>
                <span className="td-activity-status-pill">
                    <span className="tcm-status-dot" style={{ background: currentStatusColor }} />
                    {currentStatusLabel}
                </span>
            </div>
            <div className="td-activity-item">
                <span className="td-activity-dot td-activity-dot--created" />
                <span className="td-activity-text">Task created</span>
                <span className="td-activity-time">{formatRelativeTime(task.createdAt)}</span>
            </div>
            {loading ? (
                <p className="placeholder-text">Loading activity…</p>
            ) : (
                activities.map((activity) => {
                    const icon = ACTIVITY_FIELD_ICONS[activity.field] || "edit";
                    const label = ACTIVITY_FIELD_LABELS[activity.field] || activity.field;
                    const oldVal = formatActivityValue(activity.field, activity.oldValue, createModalActors);
                    const newVal = formatActivityValue(activity.field, activity.newValue, createModalActors);
                    const actorName = resolveActorName(activity.actorId);

                    return (
                        <div key={activity.id} className="td-activity-item">
                            <span className="td-activity-dot" />
                            <span className="material-symbols-rounded td-activity-field-icon">{icon}</span>
                            <span className="td-activity-text">
                                <strong className="td-activity-actor">{actorName}</strong>
                                {" changed "}
                                <strong>{label}</strong>
                                {activity.oldValue != null && (
                                    <>
                                        {" from "}
                                        <span className="td-activity-value td-activity-value--old">{oldVal}</span>
                                    </>
                                )}
                                {" to "}
                                {activity.field === "status" && activity.newValue ? (
                                    <span
                                        className="td-activity-value td-activity-value--status"
                                        style={{ color: TASK_STATUS_COLORS[activity.newValue] }}
                                    >
                                        {newVal}
                                    </span>
                                ) : (
                                    <span className="td-activity-value td-activity-value--new">{newVal}</span>
                                )}
                            </span>
                            <span className="td-activity-time">{formatRelativeTime(activity.createdAt)}</span>
                        </div>
                    );
                })
            )}
        </div>
    );
}

function formatLogValue(field, value, actors) {
    if (!value) return "";
    if (field) {
        return formatActivityValue(field, value, actors);
    }
    return String(value);
}

function TaskLogsTab({ project, task, createModalActors }) {
    const [entries, setEntries] = useState([]);
    const [loading, setLoading] = useState(true);

    const loadLogs = useCallback(async () => {
        const result = await fetchTaskLogs(project.id, task.id);
        if (result) setEntries(result);
        setLoading(false);
    }, [project.id, task.id, task.updatedAt]);

    useEffect(() => {
        setLoading(true);
        loadLogs();
    }, [loadLogs]);

    function actorLabel(entry) {
        if (entry.agentId) return `Agent ${entry.agentId}`;
        if (!entry.actorId || entry.actorId === "user") return entry.actorId === "user" ? "User" : "";
        const actor = createModalActors.find((a) => a.id === entry.actorId);
        return actor ? actor.displayName : entry.actorId;
    }

    function renderMessage(entry) {
        if (entry.kind === "tool_invocation") {
            const bits = [
                entry.tool || "tool",
                entry.ok === false ? "failed" : "completed",
                entry.durationMs != null ? `${entry.durationMs} ms` : "",
                entry.message ? `session ${entry.message}` : ""
            ].filter(Boolean);
            return bits.join(" · ");
        }
        if (entry.kind === "activity") {
            const oldValue = formatLogValue(entry.field, entry.oldValue, createModalActors);
            const newValue = formatLogValue(entry.field, entry.newValue, createModalActors);
            if (oldValue && newValue) return `${oldValue} -> ${newValue}`;
            return newValue || oldValue || "";
        }
        return entry.message || "";
    }

    return (
        <div className="td-task-logs">
            {loading ? (
                <p className="placeholder-text">Loading logs…</p>
            ) : entries.length === 0 ? (
                <p className="placeholder-text">No task logs yet.</p>
            ) : (
                entries.map((entry) => {
                    const icon = TASK_LOG_KIND_ICONS[entry.kind] || "notes";
                    const meta = [
                        actorLabel(entry),
                        entry.channelId ? `channel ${entry.channelId}` : "",
                        entry.workerId ? `worker ${entry.workerId}` : ""
                    ].filter(Boolean);
                    return (
                        <div
                            key={entry.id}
                            className={`td-task-log-item td-task-log-item--${entry.kind || "log"} ${entry.ok === false ? "td-task-log-item--failed" : ""}`}
                        >
                            <span className="material-symbols-rounded td-task-log-icon">{icon}</span>
                            <div className="td-task-log-body">
                                <div className="td-task-log-head">
                                    <strong>{entry.title || entry.kind || "Log entry"}</strong>
                                    <span>{formatRelativeTime(entry.createdAt)}</span>
                                </div>
                                {renderMessage(entry) ? (
                                    <p>{renderMessage(entry)}</p>
                                ) : null}
                                {meta.length > 0 ? (
                                    <div className="td-task-log-meta">{meta.join(" · ")}</div>
                                ) : null}
                            </div>
                        </div>
                    );
                })
            )}
        </div>
    );
}

function ReviewTab({ project, task, createModalActors }) {
    const [diffData, setDiffData] = useState(null);
    const [comments, setComments] = useState([]);
    const [loadingDiff, setLoadingDiff] = useState(true);
    const [selectedActorId, setSelectedActorId] = useState("");
    const [actorDropdownOpen, setActorDropdownOpen] = useState(false);
    const [actorSearch, setActorSearch] = useState("");
    const [submitting, setSubmitting] = useState(false);
    const [submitStatus, setSubmitStatus] = useState("");
    const dropdownRef = useRef(null);

    const projectId = project.id;
    const taskId = task.id;

    useEffect(() => {
        let cancelled = false;
        setLoadingDiff(true);

        async function load() {
            const [diff, commentList] = await Promise.all([
                fetchTaskDiff(projectId, taskId),
                fetchReviewComments(projectId, taskId)
            ]);
            if (cancelled) return;
            setDiffData(diff);
            setComments(Array.isArray(commentList) ? commentList : []);
            setLoadingDiff(false);
        }

        load().catch(() => { if (!cancelled) setLoadingDiff(false); });
        return () => { cancelled = true; };
    }, [projectId, taskId]);

    useEffect(() => {
        if (!actorDropdownOpen) return;
        function handleClick(e) {
            if (dropdownRef.current && !dropdownRef.current.contains(e.target)) {
                setActorDropdownOpen(false);
            }
        }
        document.addEventListener("mousedown", handleClick);
        return () => document.removeEventListener("mousedown", handleClick);
    }, [actorDropdownOpen]);

    const handleAddComment = useCallback(async (payload) => {
        const comment = await addReviewComment(projectId, taskId, payload);
        if (comment) setComments((prev) => [...prev, comment]);
    }, [projectId, taskId]);

    const handleResolveComment = useCallback(async (commentId, resolved) => {
        const updated = await updateReviewComment(projectId, taskId, commentId, { resolved });
        if (updated) setComments((prev) => prev.map((c) => c.id === commentId ? updated : c));
    }, [projectId, taskId]);

    const handleDeleteComment = useCallback(async (commentId) => {
        const ok = await deleteReviewComment(projectId, taskId, commentId);
        if (ok) setComments((prev) => prev.filter((c) => c.id !== commentId));
    }, [projectId, taskId]);

    const agentActors = useMemo(
        () => createModalActors.filter((a) => a.linkedAgentId),
        [createModalActors]
    );

    const filteredActors = actorSearch.trim()
        ? agentActors.filter(
            (a) =>
                a.displayName.toLowerCase().includes(actorSearch.toLowerCase()) ||
                a.id.toLowerCase().includes(actorSearch.toLowerCase())
        )
        : agentActors;

    const selectedActor = agentActors.find((a) => a.id === selectedActorId);
    const unresolvedComments = comments.filter((c) => !c.resolved);

    async function handleSubmitReview() {
        if (submitting || !selectedActor?.linkedAgentId) return;

        setSubmitting(true);
        setSubmitStatus("Sending review...");

        const agentId = selectedActor.linkedAgentId;
        const sessionTitle = `task-review:${projectId}:${taskId}`;

        const lines = [
            `**Code review for task: ${task.title || taskId}**`,
            unresolvedComments.length > 0
                ? `\nReview comments (${unresolvedComments.length}):`
                : "\nNo inline comments — general review request.",
            ...unresolvedComments.map((c, i) =>
                `\n${i + 1}. **${c.filePath}** line ${c.lineNumber} (${c.side || "new"}):\n> ${c.content}`
            )
        ];
        const message = lines.join("\n");

        try {
            const sessions = await fetchAgentSessions(agentId).catch(() => null);
            const existingSession = Array.isArray(sessions)
                ? sessions.find((s) => String(s?.title || "") === sessionTitle)
                : null;
            const session = existingSession || await createAgentSession(agentId, {
                title: sessionTitle,
                kind: "chat",
                projectId
            });
            if (!session) {
                setSubmitStatus("Failed to create session.");
                setSubmitting(false);
                return;
            }
            await postAgentSessionMessage(agentId, session.id, {
                userId: "dashboard",
                content: message,
                spawnSubSession: false
            });
            const sessionId = String(session.id || "").trim();
            const sessionURL = buildAgentSessionURL(agentId, sessionId);
            if (sessionId && sessionURL) {
                await addTaskComment(projectId, taskId, {
                    content: buildAgentSessionComment(
                        selectedActor.displayName,
                        existingSession ? "continue" : "started",
                        session.title || sessionTitle,
                        sessionURL
                    ),
                    authorActorId: "system"
                });
            }
            setSubmitStatus("Review sent.");
        } catch {
            setSubmitStatus("Failed to send review.");
        }

        setSubmitting(false);
    }

    const rawDiff = diffData?.diff || "";

    return (
        <div className="td-review-tab">
            {loadingDiff ? (
                <p className="placeholder-text">Loading diff...</p>
            ) : (
                <ReviewDiffPanel
                    rawDiff={rawDiff}
                    hasChanges={Boolean(diffData?.hasChanges)}
                    branchName={String(diffData?.branchName || "")}
                    comments={comments}
                    onAddComment={handleAddComment}
                    onResolveComment={handleResolveComment}
                    onDeleteComment={handleDeleteComment}
                />
            )}

            <div className="td-review-submit-panel">
                <div className="td-review-submit-info">
                    {unresolvedComments.length > 0 ? (
                        <span className="td-review-comment-count">
                            <span className="material-symbols-rounded" aria-hidden="true">comment</span>
                            {unresolvedComments.length} unresolved comment{unresolvedComments.length !== 1 ? "s" : ""}
                        </span>
                    ) : (
                        <span className="placeholder-text">No unresolved comments</span>
                    )}
                </div>

                <div className="td-review-submit-actions">
                    <div className="td-comment-actor-wrap" ref={dropdownRef}>
                        <button
                            type="button"
                            className={`td-comment-actor-btn ${actorDropdownOpen ? "active" : ""}`}
                            onClick={() => setActorDropdownOpen((v) => !v)}
                        >
                            <span className="material-symbols-rounded">smart_toy</span>
                            <span>{selectedActor ? selectedActor.displayName : "Select actor"}</span>
                        </button>
                        {actorDropdownOpen && (
                            <div className="td-comment-actor-dropdown td-review-actor-dropdown">
                                <input
                                    className="td-comment-actor-search"
                                    value={actorSearch}
                                    onChange={(e) => setActorSearch(e.target.value)}
                                    placeholder="Search actors..."
                                    autoFocus
                                />
                                <ul>
                                    {filteredActors.length === 0 && (
                                        <li className="tcm-dropdown-item placeholder-text">No agents available</li>
                                    )}
                                    {filteredActors.map((actor) => (
                                        <li
                                            key={actor.id}
                                            className={`tcm-dropdown-item ${selectedActorId === actor.id ? "selected" : ""}`}
                                            onMouseDown={(e) => {
                                                e.preventDefault();
                                                setSelectedActorId(actor.id);
                                                setActorDropdownOpen(false);
                                                setActorSearch("");
                                            }}
                                        >
                                            <span className="material-symbols-rounded tcm-dropdown-item-icon">smart_toy</span>
                                            <span>{actor.displayName}</span>
                                            <span className="tcm-dropdown-item-id">{actor.id}</span>
                                            {selectedActorId === actor.id && <span className="tcm-dropdown-check">✓</span>}
                                        </li>
                                    ))}
                                </ul>
                            </div>
                        )}
                    </div>

                    {submitStatus && (
                        <span className="td-review-submit-status placeholder-text">{submitStatus}</span>
                    )}

                    <button
                        type="button"
                        className="td-review-submit-btn"
                        onClick={handleSubmitReview}
                        disabled={submitting || !selectedActor}
                    >
                        <span className="material-symbols-rounded" aria-hidden="true">send</span>
                        Submit Review
                    </button>
                </div>
            </div>
        </div>
    );
}

function ClarificationsTab({ project, task }) {
    const [clarifications, setClarifications] = useState([]);
    const [loading, setLoading] = useState(true);
    const [answerDrafts, setAnswerDrafts] = useState({});
    const [submitting, setSubmitting] = useState(null);

    const loadClarifications = useCallback(async () => {
        const result = await fetchTaskClarifications(project.id, task.id);
        if (result) setClarifications(result);
        setLoading(false);
    }, [project.id, task.id]);

    useEffect(() => {
        setLoading(true);
        loadClarifications();
    }, [loadClarifications]);

    async function handleAnswer(clarificationId) {
        const draft = answerDrafts[clarificationId];
        if (!draft) return;
        setSubmitting(clarificationId);
        const selectedOption = draft.selectedOptions?.[0] || null;
        await answerTaskClarification(project.id, task.id, clarificationId, {
            selectedOptionIds: selectedOption ? [selectedOption] : [],
            note: draft.notes || ""
        });
        setAnswerDrafts((prev) => {
            const next = { ...prev };
            delete next[clarificationId];
            return next;
        });
        await loadClarifications();
        setSubmitting(null);
    }

    function updateDraft(id, field, value) {
        setAnswerDrafts((prev) => ({
            ...prev,
            [id]: { ...(prev[id] || {}), [field]: value }
        }));
    }

    if (loading) return <p className="placeholder-text">Loading clarifications…</p>;
    if (clarifications.length === 0) return <p className="placeholder-text">No clarification requests.</p>;

    return (
        <div className="td-clarifications-list">
            {clarifications.map((c) => {
                const isPending = c.status === "pending";
                const draft = answerDrafts[c.id] || {};
                return (
                    <div key={c.id} className={`td-clarification-item td-clarification-item--${c.status}`}>
                        <div className="td-clarification-header">
                            <span className="material-symbols-rounded">help_outline</span>
                            <span className={`td-clarification-status td-clarification-status--${c.status}`}>
                                {c.status}
                            </span>
                            <span className="td-clarification-target">{c.targetType}</span>
                            <span className="td-comment-time">{formatRelativeTime(c.createdAt)}</span>
                        </div>
                        <p className="td-clarification-question">{c.questionText}</p>

                        {Array.isArray(c.options) && c.options.length > 0 && (
                            <div className="td-clarification-options">
                                {c.options.map((opt) => {
                                    const isSelected = isPending
                                        ? draft.selectedOptions?.includes(opt.id)
                                        : c.selectedOptionIds?.includes(opt.id);
                                    return (
                                        <button
                                            key={opt.id}
                                            type="button"
                                            className={`td-clarification-option ${isSelected ? "selected" : ""}`}
                                            disabled={!isPending}
                                            onClick={() => {
                                                if (!isPending) return;
                                                updateDraft(c.id, "selectedOptions", [opt.id]);
                                            }}
                                        >
                                            {opt.label}
                                        </button>
                                    );
                                })}
                            </div>
                        )}

                        {isPending && c.allowNote && (
                            <textarea
                                className="td-clarification-notes"
                                placeholder="Additional notes…"
                                value={draft.notes || ""}
                                onChange={(e) => updateDraft(c.id, "notes", e.target.value)}
                                rows={2}
                            />
                        )}

                        {!isPending && c.note && (
                            <p className="td-clarification-answer-notes">
                                <strong>Response:</strong> {c.note}
                            </p>
                        )}

                        {isPending && (
                            <button
                                type="button"
                                className="td-clarification-submit"
                                disabled={submitting === c.id}
                                onClick={() => handleAnswer(c.id)}
                            >
                                {submitting === c.id ? "Submitting…" : "Submit Answer"}
                            </button>
                        )}
                    </div>
                );
            })}
        </div>
    );
}

/** Same breakpoint as `.td-page` rules in `projects.css` (mobile task detail layout). */
const TASK_DETAIL_MOBILE_MAX_PX = 860;

function TaskDetailView({
    project,
    task,
    editDraft,
    updateEditDraft,
    saveTaskEdit,
    revertTaskEdit,
    closeTaskDetails,
    updateDetailAssignee,
    deleteTaskFromModal,
    createModalActors,
    createModalTeams,
    onOpenReview
}) {
    const [activeTab, setActiveTab] = useState("comments");
    const [isMobileTaskDetail, setIsMobileTaskDetail] = useState(() =>
        typeof window !== "undefined"
            ? window.matchMedia(`(max-width: ${TASK_DETAIL_MOBILE_MAX_PX}px)`).matches
            : false
    );
    const [sidebarOpen, setSidebarOpen] = useState(() =>
        typeof window !== "undefined"
            ? !window.matchMedia(`(max-width: ${TASK_DETAIL_MOBILE_MAX_PX}px)`).matches
            : true
    );
    const descriptionInputRef = useRef(null);
    const hasReviewDiff = Boolean(task.worktreeBranch);
    const canShowReviewTab = hasReviewDiff || task.status === "needs_review";

    useEffect(() => {
        if (!canShowReviewTab && activeTab === "review") {
            setActiveTab("comments");
        }
    }, [canShowReviewTab, activeTab]);

    useEffect(() => {
        const mq = window.matchMedia(`(max-width: ${TASK_DETAIL_MOBILE_MAX_PX}px)`);
        function syncLayout() {
            const mobile = mq.matches;
            setIsMobileTaskDetail(mobile);
            setSidebarOpen(mobile ? false : true);
        }
        syncLayout();
        mq.addEventListener("change", syncLayout);
        return () => mq.removeEventListener("change", syncLayout);
    }, []);

    useEffect(() => {
        if (!isMobileTaskDetail || !sidebarOpen) {
            return;
        }
        const previousOverflow = document.body.style.overflow;
        document.body.style.overflow = "hidden";
        return () => {
            document.body.style.overflow = previousOverflow;
        };
    }, [isMobileTaskDetail, sidebarOpen]);

    useEffect(() => {
        if (!isMobileTaskDetail || !sidebarOpen) {
            return;
        }
        function onKeyDown(e) {
            if (e.key === "Escape") {
                setSidebarOpen(false);
            }
        }
        window.addEventListener("keydown", onKeyDown);
        return () => window.removeEventListener("keydown", onKeyDown);
    }, [isMobileTaskDetail, sidebarOpen]);

    const resolvedActorId = task.claimedActorId || task.actorId || "";
    const isDirty =
        editDraft.title !== task.title ||
        editDraft.description !== (task.description || "") ||
        editDraft.priority !== task.priority ||
        editDraft.status !== task.status ||
        editDraft.actorId !== resolvedActorId ||
        editDraft.teamId !== (task.teamId || "") ||
        editDraft.kind !== (task.kind || "") ||
        editDraft.loopModeOverride !== (task.loopModeOverride || "");

    const currentStatus = TASK_STATUSES.find((s) => s.id === editDraft.status) || TASK_STATUSES[0];
    const currentPriorityLabel = TASK_PRIORITY_LABELS[editDraft.priority] || "Medium";

    const assigneeActor = createModalActors.find((a) => a.id === editDraft.actorId);
    const assigneeTeam = createModalTeams.find((t) => t.id === editDraft.teamId);
    const assigneeLabel = assigneeActor
        ? assigneeActor.displayName
        : assigneeTeam
            ? assigneeTeam.name
            : "Unassigned";

    const assigneeToken = editDraft.actorId
        ? `actor:${editDraft.actorId}`
        : editDraft.teamId
            ? `team:${editDraft.teamId}`
            : "";
    const githubIssueURL = task.externalMetadata?.externalIssueURL || "";
    const githubIssueLabel = task.externalMetadata?.externalIssueNumber
        ? `GitHub #${task.externalMetadata.externalIssueNumber}`
        : "Open GitHub Issue";
    const attachments = Array.isArray(task.attachments) ? task.attachments : [];

    useEffect(() => {
        const input = descriptionInputRef.current;
        if (!input) return;
        input.style.height = "auto";
        input.style.height = `${input.scrollHeight}px`;
    }, [editDraft.description, task.id]);

    return (
        <div
            className={`td-page ${sidebarOpen ? "" : "td-page--sidebar-closed"} ${isMobileTaskDetail ? "td-page--mobile-props" : ""}`}
        >
            <div className="td-main">
                {isMobileTaskDetail && sidebarOpen ? (
                    <button
                        type="button"
                        className="td-sidebar-backdrop"
                        aria-label="Close properties"
                        onClick={() => setSidebarOpen(false)}
                    />
                ) : null}
                <header className="td-header">
                    <div className="td-breadcrumbs">
                        <button type="button" className="td-breadcrumb-link" onClick={closeTaskDetails}>
                            Tasks
                        </button>
                        <span className="material-symbols-rounded td-breadcrumb-sep">chevron_right</span>
                        <span className="td-breadcrumb-current">{task.title || "Untitled"}</span>
                    </div>
                    <div className="td-header-actions">
                        {githubIssueURL ? (
                            <a
                                className="task-review-open-btn"
                                href={githubIssueURL}
                                target="_blank"
                                rel="noreferrer"
                            >
                                <span className="material-symbols-rounded" aria-hidden="true">open_in_new</span>
                                {githubIssueLabel}
                            </a>
                        ) : null}
                        {task.status === "needs_review" && onOpenReview && (
                            <button
                                type="button"
                                className="task-review-open-btn"
                                onClick={() => onOpenReview(task)}
                            >
                                <span className="material-symbols-rounded" aria-hidden="true">rate_review</span>
                                Review
                            </button>
                        )}
                        {isMobileTaskDetail && (
                            <button
                                type="button"
                                className="task-review-open-btn"
                                onClick={() => setSidebarOpen((open) => !open)}
                                aria-expanded={sidebarOpen}
                                aria-controls="td-task-properties"
                                title="Properties"
                            >
                                <span className="material-symbols-rounded" aria-hidden="true">tune</span>
                                Properties
                            </button>
                        )}
                        {!isMobileTaskDetail && !sidebarOpen && (
                            <button
                                type="button"
                                className="project-task-detail-icon-button"
                                onClick={() => setSidebarOpen(true)}
                                aria-label="Show properties"
                                title="Show properties"
                            >
                                <span className="material-symbols-rounded">right_panel_open</span>
                            </button>
                        )}
                    </div>
                </header>

                <div className="td-id-row">
                    <span className="project-task-id">#{task.id}</span>
                </div>

                <div className="td-content">
                    <input
                        className="td-title-input"
                        value={editDraft.title}
                        onChange={(e) => updateEditDraft("title", e.target.value)}
                        placeholder="Task title"
                    />
                    <textarea
                        ref={descriptionInputRef}
                        className="td-desc-input"
                        value={editDraft.description}
                        onChange={(e) => updateEditDraft("description", e.target.value)}
                        placeholder="Add description..."
                        rows={5}
                    />
                    {attachments.length > 0 ? (
                        <div className="td-attachments">
                            {attachments.map((attachment, index) => (
                                <div key={`${attachment.name}-${index}`} className="td-attachment">
                                    {String(attachment.mimeType || "").startsWith("image/") && attachment.contentBase64 ? (
                                        <img
                                            src={`data:${attachment.mimeType};base64,${attachment.contentBase64}`}
                                            alt=""
                                        />
                                    ) : (
                                        <span className="material-symbols-rounded" aria-hidden="true">draft</span>
                                    )}
                                    <div>
                                        <strong>{attachment.name}</strong>
                                        <span>{attachment.mimeType || "application/octet-stream"} / {formatTaskAttachmentSize(attachment.sizeBytes)}</span>
                                    </div>
                                </div>
                            ))}
                        </div>
                    ) : null}
                </div>

                <div className="td-tabs-section">
                    <div className="td-tabs-bar">
                        <button
                            type="button"
                            className={`td-tab ${activeTab === "comments" ? "active" : ""}`}
                            onClick={() => setActiveTab("comments")}
                        >
                            <span className="material-symbols-rounded td-tab-icon">chat_bubble_outline</span>
                            Comments
                        </button>
                        <button
                            type="button"
                            className={`td-tab ${activeTab === "subtasks" ? "active" : ""}`}
                            onClick={() => setActiveTab("subtasks")}
                        >
                            <span className="material-symbols-rounded td-tab-icon">account_tree</span>
                            Sub-issues
                        </button>
                        <button
                            type="button"
                            className={`td-tab ${activeTab === "activity" ? "active" : ""}`}
                            onClick={() => setActiveTab("activity")}
                        >
                            <span className="material-symbols-rounded td-tab-icon">history</span>
                            History
                        </button>
                        <button
                            type="button"
                            className={`td-tab ${activeTab === "logs" ? "active" : ""}`}
                            onClick={() => setActiveTab("logs")}
                        >
                            <span className="material-symbols-rounded td-tab-icon">terminal</span>
                            Logs
                        </button>
                        {canShowReviewTab && (
                            <button
                                type="button"
                                className={`td-tab ${activeTab === "review" ? "active" : ""}`}
                                onClick={() => setActiveTab("review")}
                            >
                                <span className="material-symbols-rounded td-tab-icon">rate_review</span>
                                Review
                            </button>
                        )}
                        <button
                            type="button"
                            className={`td-tab ${activeTab === "clarifications" ? "active" : ""}`}
                            onClick={() => setActiveTab("clarifications")}
                        >
                            <span className="material-symbols-rounded td-tab-icon">help_outline</span>
                            Clarifications
                        </button>
                    </div>

                    <div className="td-tab-content">
                        {activeTab === "comments" && (
                            <CommentsTab
                                project={project}
                                task={task}
                                createModalActors={createModalActors}
                            />
                        )}
                        {activeTab === "subtasks" && (
                            <div className="td-tab-placeholder">
                                {task.swarmId ? (
                                    <div className="td-subtasks-list">
                                        {project.tasks
                                            .filter((t) => t.swarmId === task.swarmId && t.swarmParentTaskId === (task.swarmTaskId || `task:${task.id}`))
                                            .map((sub) => (
                                                <div key={sub.id} className="td-subtask-row">
                                                    <span className="tcm-status-dot" style={{ background: TASK_STATUS_COLORS[sub.status] || "#94a3b8" }} />
                                                    <span className="td-subtask-title">{sub.title}</span>
                                                    <span className="td-subtask-id">#{sub.id}</span>
                                                </div>
                                            ))
                                        }
                                    </div>
                                ) : (
                                    <p className="placeholder-text">No sub-issues.</p>
                                )}
                            </div>
                        )}
                        {activeTab === "activity" && (
                            <ActivityTab
                                project={project}
                                task={task}
                                createModalActors={createModalActors}
                            />
                        )}
                        {activeTab === "logs" && (
                            <TaskLogsTab
                                project={project}
                                task={task}
                                createModalActors={createModalActors}
                            />
                        )}
                        {activeTab === "review" && canShowReviewTab && (
                            <ReviewTab
                                project={project}
                                task={task}
                                createModalActors={createModalActors}
                            />
                        )}
                        {activeTab === "clarifications" && (
                            <ClarificationsTab
                                project={project}
                                task={task}
                            />
                        )}
                    </div>
                </div>
            </div>

            <aside
                id="td-task-properties"
                className={`td-sidebar ${sidebarOpen ? "" : "td-sidebar--closed"}`}
            >
                <div className="td-sidebar-header">
                    <h4>Properties</h4>
                    <button type="button" className="project-task-detail-icon-button" onClick={() => setSidebarOpen(false)} aria-label="Hide properties">
                        <span className="material-symbols-rounded">close</span>
                    </button>
                </div>

                <div className="td-props">
                    <div className="td-prop-row">
                        <span className="td-prop-label">Status</span>
                        <DetailDropdown
                            label={currentStatus.title}
                            color={TASK_STATUS_COLORS[currentStatus.id]}
                        >
                            {TASK_STATUSES.map((status) => (
                                <li
                                    key={status.id}
                                    className={`tcm-dropdown-item ${editDraft.status === status.id ? "selected" : ""}`}
                                    onMouseDown={(e) => {
                                        e.preventDefault();
                                        updateEditDraft("status", status.id);
                                    }}
                                >
                                    <span className="tcm-status-dot" style={{ background: TASK_STATUS_COLORS[status.id] }} />
                                    <span>{status.title}</span>
                                    {editDraft.status === status.id && <span className="tcm-dropdown-check">✓</span>}
                                </li>
                            ))}
                        </DetailDropdown>
                    </div>

                    <div className="td-prop-row">
                        <span className="td-prop-label">Priority</span>
                        <DetailDropdown
                            label={currentPriorityLabel}
                            icon={TASK_PRIORITY_ICONS[editDraft.priority] || "remove"}
                        >
                            {TASK_PRIORITIES.map((priority) => (
                                <li
                                    key={priority}
                                    className={`tcm-dropdown-item ${editDraft.priority === priority ? "selected" : ""}`}
                                    onMouseDown={(e) => {
                                        e.preventDefault();
                                        updateEditDraft("priority", priority);
                                    }}
                                >
                                    <span className="material-symbols-rounded tcm-dropdown-item-icon">{TASK_PRIORITY_ICONS[priority]}</span>
                                    <span>{TASK_PRIORITY_LABELS[priority]}</span>
                                    {editDraft.priority === priority && <span className="tcm-dropdown-check">✓</span>}
                                </li>
                            ))}
                        </DetailDropdown>
                    </div>

                    <div className="td-prop-row">
                        <span className="td-prop-label">Assignee</span>
                        <DetailDropdown
                            label={assigneeLabel}
                            icon="person"
                        >
                            <li
                                className={`tcm-dropdown-item ${!editDraft.actorId && !editDraft.teamId ? "selected" : ""}`}
                                onMouseDown={(e) => {
                                    e.preventDefault();
                                    updateDetailAssignee("");
                                }}
                            >
                                <span className="material-symbols-rounded tcm-dropdown-item-icon">person_off</span>
                                <span>Unassigned</span>
                                {!editDraft.actorId && !editDraft.teamId && <span className="tcm-dropdown-check">✓</span>}
                            </li>
                            {createModalActors.length > 0 && <li className="tcm-dropdown-divider-label">Actors</li>}
                            {createModalActors.map((actor) => (
                                <li
                                    key={actor.id}
                                    className={`tcm-dropdown-item ${editDraft.actorId === actor.id ? "selected" : ""}`}
                                    onMouseDown={(e) => {
                                        e.preventDefault();
                                        updateDetailAssignee(`actor:${actor.id}`);
                                    }}
                                >
                                    <span className="material-symbols-rounded tcm-dropdown-item-icon">person</span>
                                    <span>{actor.displayName}</span>
                                    <span className="tcm-dropdown-item-id">{actor.id}</span>
                                    {editDraft.actorId === actor.id && <span className="tcm-dropdown-check">✓</span>}
                                </li>
                            ))}
                            {createModalTeams.length > 0 && <li className="tcm-dropdown-divider-label">Teams</li>}
                            {createModalTeams.map((team) => (
                                <li
                                    key={team.id}
                                    className={`tcm-dropdown-item ${editDraft.teamId === team.id ? "selected" : ""}`}
                                    onMouseDown={(e) => {
                                        e.preventDefault();
                                        updateDetailAssignee(`team:${team.id}`);
                                    }}
                                >
                                    <span className="material-symbols-rounded tcm-dropdown-item-icon">groups</span>
                                    <span>{team.name}</span>
                                    <span className="tcm-dropdown-item-id">{team.id}</span>
                                    {editDraft.teamId === team.id && <span className="tcm-dropdown-check">✓</span>}
                                </li>
                            ))}
                        </DetailDropdown>
                    </div>

                    <div className="td-prop-row">
                        <span className="td-prop-label">Kind</span>
                        <DetailDropdown
                            label={TASK_KINDS.find((k) => k.id === editDraft.kind)?.title || "None"}
                            icon="category"
                        >
                            <li
                                className={`tcm-dropdown-item ${!editDraft.kind ? "selected" : ""}`}
                                onMouseDown={(e) => {
                                    e.preventDefault();
                                    updateEditDraft("kind", "");
                                }}
                            >
                                <span>None</span>
                                {!editDraft.kind && <span className="tcm-dropdown-check">✓</span>}
                            </li>
                            {TASK_KINDS.map((kind) => (
                                <li
                                    key={kind.id}
                                    className={`tcm-dropdown-item ${editDraft.kind === kind.id ? "selected" : ""}`}
                                    onMouseDown={(e) => {
                                        e.preventDefault();
                                        updateEditDraft("kind", kind.id);
                                    }}
                                >
                                    <span>{kind.title}</span>
                                    {editDraft.kind === kind.id && <span className="tcm-dropdown-check">✓</span>}
                                </li>
                            ))}
                        </DetailDropdown>
                    </div>

                    <div className="td-prop-row">
                        <span className="td-prop-label">Loop mode</span>
                        <DetailDropdown
                            label={LOOP_MODES.find((m) => m.id === editDraft.loopModeOverride)?.title || "Project default"}
                            icon="sync"
                        >
                            <li
                                className={`tcm-dropdown-item ${!editDraft.loopModeOverride ? "selected" : ""}`}
                                onMouseDown={(e) => {
                                    e.preventDefault();
                                    updateEditDraft("loopModeOverride", "");
                                }}
                            >
                                <span>Project default</span>
                                {!editDraft.loopModeOverride && <span className="tcm-dropdown-check">✓</span>}
                            </li>
                            {LOOP_MODES.map((mode) => (
                                <li
                                    key={mode.id}
                                    className={`tcm-dropdown-item ${editDraft.loopModeOverride === mode.id ? "selected" : ""}`}
                                    onMouseDown={(e) => {
                                        e.preventDefault();
                                        updateEditDraft("loopModeOverride", mode.id);
                                    }}
                                >
                                    <span>{mode.title}</span>
                                    {editDraft.loopModeOverride === mode.id && <span className="tcm-dropdown-check">✓</span>}
                                </li>
                            ))}
                        </DetailDropdown>
                    </div>

                    <div className="td-prop-row">
                        <span className="td-prop-label">Project</span>
                        <span className="td-prop-value td-prop-value--static">{project.name}</span>
                    </div>

                    <div className="td-prop-row">
                        <span className="td-prop-label">Created</span>
                        <span className="td-prop-value td-prop-value--static">
                            {new Date(task.createdAt).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })}
                        </span>
                    </div>

                    <div className="td-prop-row">
                        <span className="td-prop-label">Updated</span>
                        <span className="td-prop-value td-prop-value--static">{formatRelativeTime(task.updatedAt)}</span>
                    </div>

                    {task.claimedAgentId && (
                        <div className="td-prop-row">
                            <span className="td-prop-label">Agent</span>
                            <span className="td-prop-value td-prop-value--static">{task.claimedAgentId}</span>
                        </div>
                    )}

                    {task.swarmId && (
                        <div className="td-prop-row">
                            <span className="td-prop-label">Swarm</span>
                            <span className="td-prop-value td-prop-value--static">{task.swarmId}</span>
                        </div>
                    )}

                    {githubIssueURL ? (
                        <div className="td-prop-row">
                            <span className="td-prop-label">GitHub</span>
                            <a
                                className="td-prop-value"
                                href={githubIssueURL}
                                target="_blank"
                                rel="noreferrer"
                            >
                                <span className="material-symbols-rounded td-prop-value-icon">open_in_new</span>
                                <span>{githubIssueLabel}</span>
                            </a>
                        </div>
                    ) : null}
                </div>

                <div className="td-sidebar-danger">
                    <button type="button" className="danger" onClick={deleteTaskFromModal}>
                        Delete task
                    </button>
                </div>
            </aside>

            <div className={`settings-toast ${isDirty ? "settings-toast--visible" : ""}`}>
                <span className="settings-toast-label">Unsaved changes</span>
                <div className="settings-toast-actions">
                    <button type="button" className="danger hover-levitate" onClick={revertTaskEdit}>
                        Cancel
                    </button>
                    <button
                        type="button"
                        className="hover-levitate"
                        onClick={saveTaskEdit}
                        disabled={!String(editDraft.title || "").trim()}
                    >
                        Apply
                    </button>
                </div>
            </div>
        </div>
    );
}

export function ProjectTasksTab({
    project,
    selectedTask,
    editDraft,
    isTaskDetailFullscreen,
    updateEditDraft,
    saveTaskEdit,
    revertTaskEdit,
    setIsTaskDetailFullscreen,
    closeTaskDetails,
    updateDetailAssignee,
    deleteTaskFromModal,
    openTaskDetails,
    openCreateTaskModal,
    moveTask,
    bulkUpdateTasks,
    bulkDeleteTasks,
    createModalActors,
    createModalTeams,
    onOpenReview
}) {
    const [agentDirectory, setAgentDirectory] = useState({});
    const [showArchive, setShowArchive] = useState(false);
    const [archivedTasks, setArchivedTasks] = useState([]);
    const [archiveLoading, setArchiveLoading] = useState(false);
    const [dragGhostTask, setDragGhostTask] = useState(null);
    const [dragOverColumnId, setDragOverColumnId] = useState(null);
    const [tagFilter, setTagFilter] = useState("");
    const [assigneeFilter, setAssigneeFilter] = useState("");
    const [selectionMode, setSelectionMode] = useState(false);
    const [selectedTaskIds, setSelectedTaskIds] = useState(() => new Set());
    const [contextMenu, setContextMenu] = useState(null);
    const [bulkBusy, setBulkBusy] = useState(false);

    useEffect(() => {
        let cancelled = false;
        (async () => {
            const agents = await fetchAgents();
            if (cancelled || !Array.isArray(agents)) return;
            const next = {};
            for (const a of agents) {
                const id = String(a?.id || "").trim();
                if (!id) continue;
                next[id] = {
                    displayName: String(a?.displayName || id).trim() || id,
                    pet: a?.pet
                };
            }
            setAgentDirectory(next);
        })();
        return () => {
            cancelled = true;
        };
    }, []);

    const loadArchivedTasks = useCallback(async () => {
        setArchiveLoading(true);
        const result = await fetchArchivedTasks(project.id);
        if (Array.isArray(result)) setArchivedTasks(result);
        setArchiveLoading(false);
    }, [project.id]);

    const handleToggleArchive = useCallback(() => {
        const next = !showArchive;
        setShowArchive(next);
        if (next) loadArchivedTasks();
    }, [showArchive, loadArchivedTasks]);

    const activeTasks = useMemo(
        () => project.tasks.filter((t) => !t.isArchived),
        [project.tasks]
    );

    const tagOptions = useMemo(() => {
        const tags = new Set();
        activeTasks.forEach((task) => {
            (task.tags || []).forEach((tag) => {
                const normalized = String(tag || "").trim();
                if (normalized) tags.add(normalized);
            });
        });
        return Array.from(tags).sort((a, b) => a.localeCompare(b));
    }, [activeTasks]);

    const assigneeOptions = useMemo(() => {
        const options = new Map();
        activeTasks.forEach((task) => {
            if (task.actorId) {
                const actor = createModalActors.find((a) => a.id === task.actorId);
                options.set(`actor:${task.actorId}`, `Actor: ${actor?.displayName || task.actorId}`);
            }
            if (task.teamId) {
                const team = createModalTeams.find((t) => t.id === task.teamId);
                options.set(`team:${task.teamId}`, `Team: ${team?.name || task.teamId}`);
            }
            if (task.claimedActorId) {
                const actor = createModalActors.find((a) => a.id === task.claimedActorId);
                options.set(`claimedActor:${task.claimedActorId}`, `Claimed actor: ${actor?.displayName || task.claimedActorId}`);
            }
            if (task.claimedAgentId) {
                const agent = agentDirectory[task.claimedAgentId];
                options.set(`agent:${task.claimedAgentId}`, `Agent: ${agent?.displayName || task.claimedAgentId}`);
            }
        });
        return Array.from(options, ([id, label]) => ({ id, label })).sort((a, b) => a.label.localeCompare(b.label));
    }, [activeTasks, createModalActors, createModalTeams, agentDirectory]);

    const filteredActiveTasks = useMemo(() => {
        return activeTasks.filter((task) => {
            if (tagFilter && !(task.tags || []).includes(tagFilter)) {
                return false;
            }
            if (assigneeFilter) {
                const matches =
                    (assigneeFilter.startsWith("actor:") && task.actorId === assigneeFilter.slice("actor:".length)) ||
                    (assigneeFilter.startsWith("team:") && task.teamId === assigneeFilter.slice("team:".length)) ||
                    (assigneeFilter.startsWith("claimedActor:") && task.claimedActorId === assigneeFilter.slice("claimedActor:".length)) ||
                    (assigneeFilter.startsWith("agent:") && task.claimedAgentId === assigneeFilter.slice("agent:".length));
                if (!matches) return false;
            }
            return true;
        });
    }, [activeTasks, tagFilter, assigneeFilter]);

    const activeTaskIdSet = useMemo(
        () => new Set(activeTasks.map((task) => String(task.id || "").trim()).filter(Boolean)),
        [activeTasks]
    );
    const selectedTaskIdList = useMemo(
        () => Array.from(selectedTaskIds).filter((id) => activeTaskIdSet.has(id)),
        [selectedTaskIds, activeTaskIdSet]
    );
    const selectedTaskCount = selectedTaskIdList.length;
    const selectedTaskIdSet = useMemo(() => new Set(selectedTaskIdList), [selectedTaskIdList]);

    useEffect(() => {
        setSelectedTaskIds((previous) => {
            let changed = false;
            const next = new Set();
            previous.forEach((id) => {
                if (activeTaskIdSet.has(id)) {
                    next.add(id);
                } else {
                    changed = true;
                }
            });
            return changed ? next : previous;
        });
    }, [activeTaskIdSet]);

    useEffect(() => {
        if (!contextMenu) {
            return;
        }
        function closeMenu() {
            setContextMenu(null);
        }
        function handleKeyDown(event) {
            if (event.key === "Escape") {
                setContextMenu(null);
            }
        }
        window.addEventListener("mousedown", closeMenu);
        window.addEventListener("scroll", closeMenu, true);
        window.addEventListener("resize", closeMenu);
        window.addEventListener("keydown", handleKeyDown);
        return () => {
            window.removeEventListener("mousedown", closeMenu);
            window.removeEventListener("scroll", closeMenu, true);
            window.removeEventListener("resize", closeMenu);
            window.removeEventListener("keydown", handleKeyDown);
        };
    }, [contextMenu]);

    const taskCounts = buildTaskCounts(filteredActiveTasks);
    const swarmGroups = buildSwarmGroups(filteredActiveTasks);
    const selectedTaskId = selectedTask ? String(selectedTask.id || "").trim() : "";
    const hasTaskFilters = Boolean(tagFilter || assigneeFilter);

    function clearSelection() {
        setSelectedTaskIds(new Set());
        setContextMenu(null);
    }

    function toggleTaskSelection(taskId, forceSelected = null) {
        const normalized = String(taskId || "").trim();
        if (!normalized) {
            return;
        }
        setSelectedTaskIds((previous) => {
            const next = new Set(previous);
            const shouldSelect = forceSelected == null ? !next.has(normalized) : forceSelected;
            if (shouldSelect) {
                next.add(normalized);
            } else {
                next.delete(normalized);
            }
            return next;
        });
    }

    function openTaskContextMenu(event, task) {
        event.preventDefault();
        event.stopPropagation();
        const taskId = String(task?.id || "").trim();
        if (!taskId) {
            return;
        }
        const taskIds = selectedTaskIdSet.has(taskId) && selectedTaskIdList.length > 0
            ? selectedTaskIdList
            : [taskId];
        setSelectionMode(true);
        setSelectedTaskIds(new Set(taskIds));
        setContextMenu({
            x: event.clientX,
            y: event.clientY,
            taskIds,
            panel: "main"
        });
    }

    async function runBulkUpdate(payloadBuilder, successMessage) {
        const taskIds = contextMenu?.taskIds?.length ? contextMenu.taskIds : selectedTaskIdList;
        if (!taskIds.length || typeof bulkUpdateTasks !== "function") {
            return;
        }
        setBulkBusy(true);
        const ok = await bulkUpdateTasks(taskIds, payloadBuilder, successMessage);
        setBulkBusy(false);
        if (ok !== false) {
            clearSelection();
            setSelectionMode(false);
        }
    }

    async function runBulkDelete() {
        const taskIds = contextMenu?.taskIds?.length ? contextMenu.taskIds : selectedTaskIdList;
        if (!taskIds.length || typeof bulkDeleteTasks !== "function") {
            return;
        }
        setBulkBusy(true);
        const ok = await bulkDeleteTasks(taskIds);
        setBulkBusy(false);
        if (ok !== false) {
            clearSelection();
            setSelectionMode(false);
        }
    }

    function assignSelectedTasks(token) {
        const value = String(token || "").trim();
        if (!value) {
            runBulkUpdate({ actorId: "", teamId: "" }, `${selectedTaskCount} task${selectedTaskCount === 1 ? "" : "s"} unassigned.`);
            return;
        }
        if (value.startsWith("actor:")) {
            runBulkUpdate(
                { actorId: value.slice("actor:".length), teamId: "" },
                `${selectedTaskCount} task${selectedTaskCount === 1 ? "" : "s"} assigned.`
            );
            return;
        }
        if (value.startsWith("team:")) {
            runBulkUpdate(
                { actorId: "", teamId: value.slice("team:".length) },
                `${selectedTaskCount} task${selectedTaskCount === 1 ? "" : "s"} assigned.`
            );
        }
    }

    function tagSelectedTasks(tag) {
        const normalizedTag = normalizeBulkTag(tag);
        if (!normalizedTag) {
            return;
        }
        runBulkUpdate((task) => {
            const existingTags = Array.isArray(task?.tags) ? task.tags : [];
            const nextTags = existingTags.some((item) => item.toLowerCase() === normalizedTag.toLowerCase())
                ? existingTags
                : [...existingTags, normalizedTag];
            return { tags: nextTags };
        }, `Tag "${normalizedTag}" applied to ${selectedTaskCount} task${selectedTaskCount === 1 ? "" : "s"}.`);
    }

    if (selectedTask) {
        return (
            <TaskDetailView
                project={project}
                task={selectedTask}
                editDraft={editDraft}
                updateEditDraft={updateEditDraft}
                saveTaskEdit={saveTaskEdit}
                revertTaskEdit={revertTaskEdit}
                closeTaskDetails={closeTaskDetails}
                updateDetailAssignee={updateDetailAssignee}
                deleteTaskFromModal={deleteTaskFromModal}
                createModalActors={createModalActors}
                createModalTeams={createModalTeams}
                onOpenReview={onOpenReview}
            />
        );
    }

    const renderSwarmNode = (task, group, level = 0, visited = new Set()) => {
        const taskKey = task.swarmTaskId || `task:${task.id}`;
        if (visited.has(taskKey)) {
            return null;
        }
        const nextVisited = new Set(visited);
        nextVisited.add(taskKey);

        const children = group.childrenByParent.get(taskKey) || [];
        return (
            <div key={task.id} className="project-swarm-node" style={{ marginLeft: `${Math.min(level, 8) * 16}px` }}>
                <button
                    type="button"
                    className="project-swarm-node-main"
                    onClick={() => openTaskDetails(task)}
                    title={`Open task ${task.id}`}
                >
                    <span className={`project-swarm-status project-swarm-status--${task.status}`}>{task.status}</span>
                    <span className="project-swarm-node-title">{task.title}</span>
                    <span className="project-task-id">#{task.id}</span>
                    {Number.isFinite(task.swarmDepth) ? <span className="project-swarm-node-meta">Depth {task.swarmDepth}</span> : null}
                    {task.swarmTaskId ? <span className="project-swarm-node-meta">{task.swarmTaskId}</span> : null}
                </button>
                {children.length > 0 ? (
                    <div className="project-swarm-node-children">
                        {children.map((child) => renderSwarmNode(child, group, level + 1, nextVisited))}
                    </div>
                ) : null}
            </div>
        );
    };

    return (
        <section className="project-tab-layout">
            <section className="project-pane project-kanban-pane">
                <div className="project-kanban-head">
                    <div className="project-kanban-summary">
                        <span>
                            <span className="material-symbols-rounded" aria-hidden="true">
                                list_alt
                            </span>
                            {taskCounts.total} task{taskCounts.total === 1 ? "" : "s"}
                        </span>
                        <span>
                            <span className="material-symbols-rounded" aria-hidden="true">
                                pending_actions
                            </span>
                            {taskCounts.in_progress} in progress
                        </span>
                    </div>
                    <div className="project-kanban-head-actions">
                        <button
                            type="button"
                            className={`project-task-selection-toggle${selectionMode ? " active" : ""}`}
                            onClick={() => {
                                setSelectionMode((value) => !value);
                                setContextMenu(null);
                                if (selectionMode) {
                                    clearSelection();
                                }
                            }}
                        >
                            <span className="material-symbols-rounded" aria-hidden="true">
                                {selectionMode ? "check_box" : "check_box_outline_blank"}
                            </span>
                            Select
                        </button>
                        <button
                            type="button"
                            className={`project-task-archive-toggle-btn${showArchive ? " active" : ""}`}
                            onClick={handleToggleArchive}
                        >
                            <span className="material-symbols-rounded" aria-hidden="true">archive</span>
                            Archive
                        </button>
                        <button type="button" className="project-primary hover-levitate" onClick={() => openCreateTaskModal("backlog")}>
                            Create Task
                        </button>
                    </div>
                </div>

                <div className="project-task-filter-bar">
                    <DetailDropdown
                        label={tagFilter || "All tags"}
                        icon="sell"
                    >
                        <li
                            className={`tcm-dropdown-item ${!tagFilter ? "selected" : ""}`}
                            onMouseDown={(e) => {
                                e.preventDefault();
                                setTagFilter("");
                            }}
                        >
                            <span className="material-symbols-rounded tcm-dropdown-item-icon">sell</span>
                            <span>All tags</span>
                            {!tagFilter && <span className="tcm-dropdown-check">✓</span>}
                        </li>
                        {tagOptions.map((tag) => (
                            <li
                                key={tag}
                                className={`tcm-dropdown-item ${tagFilter === tag ? "selected" : ""}`}
                                onMouseDown={(e) => {
                                    e.preventDefault();
                                    setTagFilter(tag);
                                }}
                            >
                                <span className="material-symbols-rounded tcm-dropdown-item-icon">sell</span>
                                <span>{tag}</span>
                                {tagFilter === tag && <span className="tcm-dropdown-check">✓</span>}
                            </li>
                        ))}
                    </DetailDropdown>
                    <DetailDropdown
                        label={assigneeOptions.find((option) => option.id === assigneeFilter)?.label || "All assignees"}
                        icon="person"
                    >
                        <li
                            className={`tcm-dropdown-item ${!assigneeFilter ? "selected" : ""}`}
                            onMouseDown={(e) => {
                                e.preventDefault();
                                setAssigneeFilter("");
                            }}
                        >
                            <span className="material-symbols-rounded tcm-dropdown-item-icon">person</span>
                            <span>All assignees</span>
                            {!assigneeFilter && <span className="tcm-dropdown-check">✓</span>}
                        </li>
                        {assigneeOptions.map((option) => (
                            <li
                                key={option.id}
                                className={`tcm-dropdown-item ${assigneeFilter === option.id ? "selected" : ""}`}
                                onMouseDown={(e) => {
                                    e.preventDefault();
                                    setAssigneeFilter(option.id);
                                }}
                            >
                                <span className="material-symbols-rounded tcm-dropdown-item-icon">person</span>
                                <span>{option.label}</span>
                                {assigneeFilter === option.id && <span className="tcm-dropdown-check">✓</span>}
                            </li>
                        ))}
                    </DetailDropdown>
                    {hasTaskFilters ? (
                        <button
                            type="button"
                            className="project-task-filter-clear"
                            onClick={() => {
                                setTagFilter("");
                                setAssigneeFilter("");
                            }}
                        >
                            <span className="material-symbols-rounded" aria-hidden="true">filter_alt_off</span>
                            Clear
                        </button>
                    ) : null}
                </div>

                {selectionMode ? (
                    <div className="project-task-selection-bar">
                        <span>
                            <span className="material-symbols-rounded" aria-hidden="true">checklist</span>
                            {selectedTaskCount} selected
                        </span>
                        <button
                            type="button"
                            onClick={() => {
                                if (selectedTaskCount > 0) {
                                    runBulkUpdate(
                                        { isArchived: true },
                                        `${selectedTaskCount} task${selectedTaskCount === 1 ? "" : "s"} archived.`
                                    );
                                }
                            }}
                            disabled={selectedTaskCount === 0 || bulkBusy}
                        >
                            <span className="material-symbols-rounded" aria-hidden="true">archive</span>
                            Archive
                        </button>
                        <button
                            type="button"
                            className="danger"
                            onClick={runBulkDelete}
                            disabled={selectedTaskCount === 0 || bulkBusy}
                        >
                            <span className="material-symbols-rounded" aria-hidden="true">delete</span>
                            Delete
                        </button>
                        <button type="button" onClick={clearSelection} disabled={selectedTaskCount === 0 || bulkBusy}>
                            Clear
                        </button>
                    </div>
                ) : null}

                {swarmGroups.length > 0 ? (
                    <section className="project-swarm-overview">
                        <div className="project-pane-head">
                            <h4>Swarm Tree</h4>
                        </div>
                        <div className="project-swarm-list">
                            {swarmGroups.map((group) => {
                                const counts = buildTaskCounts(group.tasks);
                                return (
                                    <article key={group.swarmId} className="project-swarm-card">
                                        <header className="project-swarm-card-head">
                                            <strong>{group.swarmId}</strong>
                                            <span>{counts.total} tasks</span>
                                            <span>{counts.blocked || 0} blocked</span>
                                        </header>
                                        <div className="project-swarm-tree">
                                            {group.roots.length === 0 ? (
                                                <p className="placeholder-text">No root nodes detected.</p>
                                            ) : (
                                                group.roots.map((rootNode) => renderSwarmNode(rootNode, group))
                                            )}
                                        </div>
                                    </article>
                                );
                            })}
                        </div>
                    </section>
                ) : null}

                <div className="project-kanban-board">
                    {TASK_STATUSES.map((column) => {
                        const tasks = sortTasksByDate(filteredActiveTasks.filter((task) => task.status === column.id)).sort((left, right) => {
                            if (left.swarmId && right.swarmId && left.swarmId !== right.swarmId) {
                                return left.swarmId.localeCompare(right.swarmId);
                            }
                            if (left.swarmId && !right.swarmId) {
                                return -1;
                            }
                            if (!left.swarmId && right.swarmId) {
                                return 1;
                            }
                            if ((left.swarmDepth ?? 0) !== (right.swarmDepth ?? 0)) {
                                return (left.swarmDepth ?? 0) - (right.swarmDepth ?? 0);
                            }
                            return new Date(left.createdAt).getTime() - new Date(right.createdAt).getTime();
                        });

                        return (
                            <section
                                key={column.id}
                                className="project-kanban-column"
                                onDragOver={(event) => {
                                    event.preventDefault();
                                    if (dragGhostTask) setDragOverColumnId(column.id);
                                }}
                                onDrop={(event) => {
                                    event.preventDefault();
                                    const taskId = event.dataTransfer.getData("text/project-task-id");
                                    if (taskId) {
                                        moveTask(taskId, column.id).finally(() => {
                                            setDragOverColumnId(null);
                                            setDragGhostTask(null);
                                        });
                                    }
                                }}
                            >
                                <header className={`project-kanban-column-head project-kanban-column-head--${column.id}`}>
                                    <span>{column.title}</span>
                                    <strong>{tasks.length}</strong>
                                </header>

                                <div
                                    className={`project-kanban-column-body${dragOverColumnId === column.id ? " project-kanban-column-body--dragover" : ""}`}
                                >
                                    {dragOverColumnId === column.id && dragGhostTask ? (
                                        <article className="project-kanban-task project-kanban-task--ghost" aria-hidden="true">
                                            <div className="project-task-card-top">
                                                <span className="project-task-id">#{dragGhostTask.id}</span>
                                                <span className="project-task-card-open">
                                                    <span className="material-symbols-rounded" aria-hidden="true">
                                                        open_in_new
                                                    </span>
                                                    Open
                                                </span>
                                            </div>
                                            <h5>{dragGhostTask.title}</h5>
                                            {dragGhostTask.description ? <p>{dragGhostTask.description}</p> : null}
                                            <div className="project-task-meta">
                                                <span className={`project-priority-badge ${dragGhostTask.priority || "medium"}`}>
                                                    <span className="material-symbols-rounded" aria-hidden="true">
                                                        flag
                                                    </span>
                                                    {TASK_PRIORITY_LABELS[dragGhostTask.priority] || "Medium"}
                                                </span>
                                                {Array.isArray(dragGhostTask.swarmDependencyIds) && dragGhostTask.swarmDependencyIds.length > 0 ? (
                                                    <span className="project-task-assignee-badge">
                                                        <span className="material-symbols-rounded" aria-hidden="true">
                                                            link
                                                        </span>
                                                        Deps: {dragGhostTask.swarmDependencyIds.join(", ")}
                                                    </span>
                                                ) : null}
                                                {Array.isArray(dragGhostTask.swarmActorPath) && dragGhostTask.swarmActorPath.length > 0 ? (
                                                    <span className="project-task-assignee-badge">
                                                        <span className="material-symbols-rounded" aria-hidden="true">
                                                            alt_route
                                                        </span>
                                                        Path: {dragGhostTask.swarmActorPath.join(" -> ")}
                                                    </span>
                                                ) : null}
                                            </div>
                                        </article>
                                    ) : null}
                                    {tasks.length === 0 ? (
                                        dragOverColumnId === column.id && dragGhostTask ? null : (
                                            <p className="placeholder-text">{hasTaskFilters ? "No tasks match filters" : "No tasks"}</p>
                                        )
                                    ) : (
                                        tasks.map((task, index) => {
                                            const previous = index > 0 ? tasks[index - 1] : null;
                                            const showSwarmHeader = task.swarmId && (!previous || previous.swarmId !== task.swarmId);
                                            return (
                                                <React.Fragment key={task.id}>
                                                    {showSwarmHeader ? (
                                                        <p className="project-task-assignee-badge">Swarm: {task.swarmId}</p>
                                                    ) : null}
                                                    <article
                                                        className={`project-kanban-task project-kanban-task--clickable hover-levitate ${selectedTaskId && selectedTaskId === String(task.id || "").trim() ? "project-kanban-task--selected" : ""
                                                            } ${selectedTaskIdSet.has(String(task.id || "").trim()) ? "project-kanban-task--multi-selected" : ""}`}
                                                        role="button"
                                                        tabIndex={0}
                                                        draggable={!selectionMode}
                                                        onClick={(event) => {
                                                            if (selectionMode || event.metaKey || event.ctrlKey) {
                                                                event.preventDefault();
                                                                setSelectionMode(true);
                                                                toggleTaskSelection(task.id);
                                                                return;
                                                            }
                                                            openTaskDetails(task);
                                                        }}
                                                        onContextMenu={(event) => openTaskContextMenu(event, task)}
                                                        onKeyDown={(event) => {
                                                            if (event.key === "Enter" || event.key === " ") {
                                                                event.preventDefault();
                                                                if (selectionMode) {
                                                                    toggleTaskSelection(task.id);
                                                                    return;
                                                                }
                                                                openTaskDetails(task);
                                                            }
                                                        }}
                                                        onDragStart={(event) => {
                                                            if (selectionMode) {
                                                                event.preventDefault();
                                                                return;
                                                            }
                                                            event.dataTransfer.setData("text/project-task-id", task.id);
                                                            event.dataTransfer.effectAllowed = "move";
                                                            setDragGhostTask(task);
                                                            setDragOverColumnId(null);
                                                        }}
                                                        onDragEnd={() => {
                                                            setDragOverColumnId(null);
                                                            setDragGhostTask(null);
                                                        }}
                                                    >
                                                        <div className="project-task-card-top">
                                                            <span className="project-task-card-left">
                                                                {selectionMode ? (
                                                                    <button
                                                                        type="button"
                                                                        className="project-task-select-box"
                                                                        aria-label={selectedTaskIdSet.has(String(task.id || "").trim()) ? "Deselect task" : "Select task"}
                                                                        onClick={(event) => {
                                                                            event.stopPropagation();
                                                                            toggleTaskSelection(task.id);
                                                                        }}
                                                                    >
                                                                        <span className="material-symbols-rounded" aria-hidden="true">
                                                                            {selectedTaskIdSet.has(String(task.id || "").trim()) ? "check_box" : "check_box_outline_blank"}
                                                                        </span>
                                                                    </button>
                                                                ) : null}
                                                                <span className="project-task-id">#{task.id}</span>
                                                            </span>
                                                            <span className="project-task-card-open">
                                                                <span className="material-symbols-rounded" aria-hidden="true">
                                                                    open_in_new
                                                                </span>
                                                                Open
                                                            </span>
                                                        </div>
                                                        <h5>{task.title}</h5>
                                                        {task.description ? <p>{task.description}</p> : null}

                                                        {task.status === "needs_review" && task.worktreeBranch && onOpenReview && (
                                                            <button
                                                                type="button"
                                                                className="task-review-open-btn"
                                                                onClick={(e) => {
                                                                    e.stopPropagation();
                                                                    onOpenReview(task);
                                                                }}
                                                            >
                                                                <span className="material-symbols-rounded" aria-hidden="true">rate_review</span>
                                                                Review Changes
                                                            </button>
                                                        )}

                                                        <div className="project-task-meta">
                                                            <span className={`project-priority-badge ${task.priority}`}>
                                                                <span className="material-symbols-rounded" aria-hidden="true">
                                                                    flag
                                                                </span>
                                                                {TASK_PRIORITY_LABELS[task.priority] || "Medium"}
                                                            </span>
                                                            {task.kind && (
                                                                <span className="project-task-kind-badge">
                                                                    <span className="material-symbols-rounded" aria-hidden="true">category</span>
                                                                    {TASK_KINDS.find((k) => k.id === task.kind)?.title || task.kind}
                                                                </span>
                                                            )}
                                                            {Array.isArray(task.tags) && task.tags.slice(0, 4).map((tag) => (
                                                                <span key={tag} className="project-task-tag-badge">
                                                                    <span className="material-symbols-rounded" aria-hidden="true">sell</span>
                                                                    {tag}
                                                                </span>
                                                            ))}
                                                            {Array.isArray(task.tags) && task.tags.length > 4 ? (
                                                                <span className="project-task-tag-badge">+{task.tags.length - 4}</span>
                                                            ) : null}
                                                            {task.externalMetadata?.providerId === "github" ? (
                                                                task.externalMetadata.externalIssueURL ? (
                                                                    <a
                                                                        className="project-task-assignee-badge"
                                                                        href={task.externalMetadata.externalIssueURL}
                                                                        target="_blank"
                                                                        rel="noreferrer"
                                                                        onClick={(e) => e.stopPropagation()}
                                                                    >
                                                                        <span className="material-symbols-rounded" aria-hidden="true">
                                                                            open_in_new
                                                                        </span>
                                                                        GitHub #{task.externalMetadata.externalIssueNumber || ""}
                                                                    </a>
                                                                ) : (
                                                                    <span className="project-task-assignee-badge">
                                                                        <span className="material-symbols-rounded" aria-hidden="true">
                                                                            sync
                                                                        </span>
                                                                        GitHub
                                                                    </span>
                                                                )
                                                            ) : null}
                                                            {task.externalMetadata?.syncState ? (
                                                                <span className="project-task-assignee-badge">
                                                                    <span className="material-symbols-rounded" aria-hidden="true">
                                                                        cloud_sync
                                                                    </span>
                                                                    {task.externalMetadata.syncState}
                                                                </span>
                                                            ) : null}
                                                            {task.swarmTaskId ? (
                                                                <span className="project-task-claim-badge">
                                                                    <span className="material-symbols-rounded" aria-hidden="true">
                                                                        route
                                                                    </span>
                                                                    Swarm task: {task.swarmTaskId}
                                                                </span>
                                                            ) : null}
                                                            {Number.isFinite(task.swarmDepth) ? (
                                                                <span className="project-task-assignee-badge">
                                                                    <span className="material-symbols-rounded" aria-hidden="true">
                                                                        account_tree
                                                                    </span>
                                                                    Depth: {task.swarmDepth}
                                                                </span>
                                                            ) : null}
                                                            {task.swarmParentTaskId ? (
                                                                <span className="project-task-assignee-badge">
                                                                    <span className="material-symbols-rounded" aria-hidden="true">
                                                                        call_split
                                                                    </span>
                                                                    Parent: {task.swarmParentTaskId}
                                                                </span>
                                                            ) : null}
                                                            {task.swarmDependencyIds.length > 0 ? (
                                                                <span className="project-task-assignee-badge">
                                                                    <span className="material-symbols-rounded" aria-hidden="true">
                                                                        link
                                                                    </span>
                                                                    Deps: {task.swarmDependencyIds.join(", ")}
                                                                </span>
                                                            ) : null}
                                                            {task.swarmActorPath.length > 0 ? (
                                                                <span className="project-task-assignee-badge">
                                                                    <span className="material-symbols-rounded" aria-hidden="true">
                                                                        alt_route
                                                                    </span>
                                                                    Path: {task.swarmActorPath.join(" -> ")}
                                                                </span>
                                                            ) : null}
                                                            {task.claimedAgentId ? (
                                                                <ProjectKanbanClaimedAgentBadge task={task} agentDirectory={agentDirectory} />
                                                            ) : null}
                                                            {!task.claimedAgentId && task.claimedActorId ? (
                                                                <ProjectKanbanClaimedActorBadge
                                                                    task={task}
                                                                    createModalActors={createModalActors}
                                                                    agentDirectory={agentDirectory}
                                                                />
                                                            ) : null}
                                                            {!task.claimedAgentId && !task.claimedActorId && task.actorId ? (
                                                                <ProjectKanbanAssignedActorBadge
                                                                    task={task}
                                                                    createModalActors={createModalActors}
                                                                    agentDirectory={agentDirectory}
                                                                />
                                                            ) : null}
                                                            {!task.claimedAgentId && !task.claimedActorId && !task.actorId && task.teamId ? (
                                                                <span className="project-task-assignee-badge">
                                                                    <span className="material-symbols-rounded" aria-hidden="true">
                                                                        groups
                                                                    </span>
                                                                    Assigned team: {task.teamId}
                                                                </span>
                                                            ) : null}
                                                            <span className="project-task-age">
                                                                <span className="material-symbols-rounded" aria-hidden="true">
                                                                    schedule
                                                                </span>
                                                                {formatRelativeTime(task.createdAt)}
                                                            </span>
                                                        </div>
                                                    </article>
                                                </React.Fragment>
                                            );
                                        })
                                    )}
                                </div>
                            </section>
                        );
                    })}
                </div>

                <TaskBulkContextMenu
                    menu={contextMenu}
                    selectedCount={contextMenu?.taskIds?.length || selectedTaskCount}
                    tagOptions={tagOptions}
                    createModalActors={createModalActors}
                    createModalTeams={createModalTeams}
                    busy={bulkBusy}
                    onClose={() => setContextMenu(null)}
                    onPanelChange={(panel) => setContextMenu((current) => current ? { ...current, panel } : current)}
                    onMove={(status) => runBulkUpdate(
                        { status },
                        `${contextMenu?.taskIds?.length || selectedTaskCount} task${(contextMenu?.taskIds?.length || selectedTaskCount) === 1 ? "" : "s"} moved.`
                    )}
                    onAssign={assignSelectedTasks}
                    onTag={tagSelectedTasks}
                    onArchive={() => runBulkUpdate(
                        { isArchived: true },
                        `${contextMenu?.taskIds?.length || selectedTaskCount} task${(contextMenu?.taskIds?.length || selectedTaskCount) === 1 ? "" : "s"} archived.`
                    )}
                    onDelete={runBulkDelete}
                />

                {showArchive && (
                    <section className="project-task-archive-section">
                        <div className="project-task-archive-header">
                            <span className="material-symbols-rounded" aria-hidden="true">archive</span>
                            <h4>Archived tasks</h4>
                            <button
                                type="button"
                                className="project-archive-back-btn"
                                onClick={handleToggleArchive}
                            >
                                <span className="material-symbols-rounded" style={{ fontSize: "1rem" }}>close</span>
                            </button>
                        </div>
                        {archiveLoading ? (
                            <p className="placeholder-text">Loading archived tasks...</p>
                        ) : archivedTasks.length === 0 ? (
                            <p className="placeholder-text">No archived tasks.</p>
                        ) : (
                            <div className="project-task-archive-list">
                                {archivedTasks.map((task) => (
                                    <article
                                        key={task.id}
                                        className="project-task-archive-item"
                                        role="button"
                                        tabIndex={0}
                                        onClick={() => openTaskDetails(task)}
                                        onKeyDown={(event) => {
                                            if (event.key === "Enter" || event.key === " ") {
                                                event.preventDefault();
                                                openTaskDetails(task);
                                            }
                                        }}
                                    >
                                        <span className="project-task-id">#{task.id}</span>
                                        <span className="project-task-archive-item-title">{task.title}</span>
                                        <span className="tcm-status-dot" style={{ background: TASK_STATUS_COLORS[task.status] || "#94a3b8" }} />
                                        <span className="project-task-archive-item-status">
                                            {TASK_STATUSES.find((s) => s.id === task.status)?.title || task.status}
                                        </span>
                                        <span className="project-task-age">
                                            <span className="material-symbols-rounded" aria-hidden="true">schedule</span>
                                            {formatRelativeTime(task.updatedAt)}
                                        </span>
                                    </article>
                                ))}
                            </div>
                        )}
                    </section>
                )}
            </section>
        </section>
    );
}
