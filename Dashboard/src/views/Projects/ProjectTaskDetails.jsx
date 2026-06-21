import React, { useState, useRef, useEffect, useCallback, useMemo, forwardRef } from "react";
import { createPortal } from "react-dom";
import ReactMarkdown from "react-markdown";
import {
    TASK_STATUSES,
    TASK_PRIORITIES,
    TASK_PRIORITY_LABELS,
    TASK_STATUS_COLORS,
    TASK_PRIORITY_ICONS,
    TASK_KINDS,
    LOOP_MODES,
    formatRelativeTime
} from "./utils";
import { buildRelatedIssueGroups } from "./taskRelations";
import { taskDescriptionMode } from "./taskDescriptionMode";
import { linkifyTaskReferences, taskByReference } from "./taskReferenceLinks";
import { resolveLinkedAgentPet } from "./commentAvatars";
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
    searchProjectFiles,
    fetchSkillsRegistry,
    fetchMeshState,
    createMeshTask
} from "../../api";
import { AgentPetIcon } from "../../features/agents/components/AgentPetSprite";
import { ReviewDiffPanel } from "./ReviewDiffPanel";
import { LoadingSkeleton } from "../../components/LoadingSkeleton";

function LinkedMarkdown({ children, project, openTaskDetails }) {
    const source = linkifyTaskReferences(children, project);
    return (
        <ReactMarkdown
            components={{
                a({ href, children: linkChildren, ...props }) {
                    const rawHref = String(href || "");
                    if (rawHref.startsWith("sloppy-task:")) {
                        const taskId = decodeURIComponent(rawHref.slice("sloppy-task:".length));
                        const linkedTask = taskByReference(project, taskId);
                        return (
                            <button
                                type="button"
                                className="td-task-ref-link"
                                onClick={(event) => {
                                    event.stopPropagation();
                                    linkedTask && openTaskDetails?.(linkedTask);
                                }}
                                disabled={!linkedTask}
                                title={linkedTask?.title || taskId}
                            >
                                {linkChildren}
                            </button>
                        );
                    }
                    return <a href={href} {...props}>{linkChildren}</a>;
                }
            }}
        >
            {source}
        </ReactMarkdown>
    );
}

function currentMentionQuery(value, selectionStart) {
    const before = String(value || "").slice(0, selectionStart ?? 0);
    const match = before.match(/(?:^|\s)([#@/])([^#@/\s]{0,80})$/);
    if (!match) return null;
    return { trigger: match[1], query: match[2] || "", start: before.length - match[0].trimStart().length };
}

function normalizeFileResults(raw) {
    const list = Array.isArray(raw) ? raw : Array.isArray(raw?.items) ? raw.items : Array.isArray(raw?.results) ? raw.results : [];
    return list.map((file) => {
        const path = String(file?.path || file?.name || "").trim();
        if (!path) return null;
        return { type: "file", id: path, label: path, subtitle: "Project file", insertText: `\`${path}\`` };
    }).filter(Boolean);
}

function normalizeSkillResults(raw) {
    const list = Array.isArray(raw) ? raw : Array.isArray(raw?.items) ? raw.items : Array.isArray(raw?.results) ? raw.results : Array.isArray(raw?.skills) ? raw.skills : [];
    return list.map((skill) => {
        const id = String(skill?.id || skill?.name || skill?.repo || "").trim();
        if (!id) return null;
        const name = String(skill?.name || skill?.title || id).trim();
        return { type: "skill", id, label: name, subtitle: id, insertText: `\`skill:${id}\`` };
    }).filter(Boolean);
}

const ProjectMentionTextarea = forwardRef(function ProjectMentionTextarea({
    value,
    onChange,
    project,
    className,
    placeholder,
    rows,
    onInput,
    textareaRef,
    ...props
}, forwardedRef) {
    const localRef = useRef(null);
    const ref = textareaRef || forwardedRef || localRef;
    const [mention, setMention] = useState(null);
    const [suggestions, setSuggestions] = useState([]);
    const [loading, setLoading] = useState(false);

    function getNode() {
        return ref && typeof ref === "object" ? ref.current : null;
    }

    const updateMention = useCallback(() => {
        const node = getNode();
        if (!node) return;
        setMention(currentMentionQuery(node.value, node.selectionStart));
    }, [ref]);

    useEffect(() => {
        let cancelled = false;
        async function load() {
            if (!mention) {
                setSuggestions([]);
                return;
            }
            const query = mention.query.trim();
            const tasks = (project.tasks || [])
                .filter((task) => {
                    const haystack = `${task.id || ""} ${task.title || ""}`.toLowerCase();
                    return !query || haystack.includes(query.toLowerCase());
                })
                .slice(0, 8)
                .map((task) => ({
                    type: "task",
                    id: task.id,
                    label: `#${task.id}`,
                    subtitle: task.title || "Task",
                    insertText: `#${task.id}`
                }));
            setLoading(true);
            const [filesRaw, skillsRaw] = await Promise.all([
                mention.trigger === "#" ? Promise.resolve([]) : searchProjectFiles(project.id, query, 8).catch(() => []),
                mention.trigger === "#" ? Promise.resolve([]) : fetchSkillsRegistry(query || undefined, "installs", 8, 0).catch(() => [])
            ]);
            if (cancelled) return;
            const next = [...tasks, ...normalizeFileResults(filesRaw), ...normalizeSkillResults(skillsRaw)].slice(0, 12);
            setSuggestions(next);
            setLoading(false);
        }
        load();
        return () => { cancelled = true; };
    }, [mention?.trigger, mention?.query, project.id, project.tasks]);

    function insertSuggestion(item) {
        const node = getNode();
        if (!node || !mention) return;
        const current = String(value || "");
        const before = current.slice(0, mention.start);
        const after = current.slice(node.selectionStart ?? current.length);
        const next = `${before}${item.insertText} ${after}`;
        onChange({ target: { value: next } });
        setMention(null);
        setSuggestions([]);
        requestAnimationFrame(() => {
            node.focus();
            const pos = `${before}${item.insertText} `.length;
            node.setSelectionRange(pos, pos);
        });
    }

    return (
        <div className="td-mention-textarea-wrap">
            <textarea
                {...props}
                ref={ref}
                className={className}
                value={value}
                onChange={(event) => {
                    onChange(event);
                    requestAnimationFrame(updateMention);
                }}
                onKeyUp={updateMention}
                onClick={updateMention}
                onFocus={updateMention}
                placeholder={placeholder}
                rows={rows}
            />
            {mention && (suggestions.length > 0 || loading) ? (
                <div className="td-mention-suggestions">
                    {loading && suggestions.length === 0 ? <span className="td-mention-loading">Searching…</span> : null}
                    {suggestions.map((item) => (
                        <button key={`${item.type}:${item.id}`} type="button" onMouseDown={(e) => { e.preventDefault(); insertSuggestion(item); }}>
                            <span className={`td-mention-kind td-mention-kind--${item.type}`}>{item.type}</span>
                            <strong>{item.label}</strong>
                            <small>{item.subtitle}</small>
                        </button>
                    ))}
                </div>
            ) : null}
        </div>
    );
});

function CommentAvatar({ comment, author, agentDirectory }) {
    const avatar = resolveLinkedAgentPet(comment.authorActorId, author ? [author] : [], agentDirectory);
    if (avatar) {
        return (
            <span className="td-comment-avatar td-comment-avatar--pet" aria-hidden="true">
                <AgentPetIcon pet={avatar.pet} parts={avatar.parts} genomeHex={avatar.genomeHex} />
            </span>
        );
    }

    return (
        <span className="material-symbols-rounded td-comment-avatar" aria-hidden="true">
            {comment.isAgentReply ? "smart_toy" : "person"}
        </span>
    );
}

export function DetailDropdown({ label, icon, color, children }) {
    const [open, setOpen] = useState(false);
    const [menuStyle, setMenuStyle] = useState(null);
    const ref = useRef(null);
    const menuRef = useRef(null);

    const updateMenuPosition = useCallback(() => {
        const trigger = ref.current;
        if (!trigger) return;
        const rect = trigger.getBoundingClientRect();
        const gutter = 8;
        const menuWidth = Math.max(200, Math.ceil(rect.width));
        const viewportWidth = window.innerWidth || document.documentElement.clientWidth || menuWidth;
        const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 300;
        const left = Math.min(
            Math.max(gutter, rect.right - menuWidth),
            Math.max(gutter, viewportWidth - menuWidth - gutter)
        );
        const belowSpace = viewportHeight - rect.bottom - gutter;
        const aboveSpace = rect.top - gutter;
        const openAbove = belowSpace < 160 && aboveSpace > belowSpace;
        const maxHeight = Math.max(120, Math.min(300, openAbove ? aboveSpace - 4 : belowSpace - 4));
        const top = openAbove
            ? Math.max(gutter, rect.top - maxHeight - 4)
            : Math.min(rect.bottom + 4, viewportHeight - gutter);

        setMenuStyle({
            left: `${left}px`,
            top: `${top}px`,
            minWidth: `${menuWidth}px`,
            maxHeight: `${maxHeight}px`
        });
    }, []);

    useEffect(() => {
        if (!open) return;
        function handleClick(e) {
            if (
                ref.current &&
                !ref.current.contains(e.target) &&
                (!menuRef.current || !menuRef.current.contains(e.target))
            ) {
                setOpen(false);
            }
        }
        document.addEventListener("mousedown", handleClick);
        return () => document.removeEventListener("mousedown", handleClick);
    }, [open]);

    useEffect(() => {
        if (!open) {
            setMenuStyle(null);
            return;
        }
        updateMenuPosition();
        window.addEventListener("resize", updateMenuPosition);
        window.addEventListener("scroll", updateMenuPosition, true);
        return () => {
            window.removeEventListener("resize", updateMenuPosition);
            window.removeEventListener("scroll", updateMenuPosition, true);
        };
    }, [open, updateMenuPosition]);

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
            {open && menuStyle ? createPortal(
                <ul
                    ref={menuRef}
                    className="td-prop-dropdown td-prop-dropdown--floating"
                    style={menuStyle}
                    onClick={() => setOpen(false)}
                >
                    {children}
                </ul>,
                document.body
            ) : null}
        </div>
    );
}

function statusTitle(statusId) {
    return TASK_STATUSES.find((status) => status.id === statusId)?.title || statusId || "Backlog";
}

function taskAssigneeLabel(task, createModalActors, createModalTeams, agentDirectory) {
    if (task.actorId) {
        return createModalActors.find((actor) => actor.id === task.actorId)?.displayName || task.actorId;
    }
    if (task.teamId) {
        return createModalTeams.find((team) => team.id === task.teamId)?.name || task.teamId;
    }
    if (task.claimedActorId) {
        return createModalActors.find((actor) => actor.id === task.claimedActorId)?.displayName || task.claimedActorId;
    }
    if (task.claimedAgentId) {
        return agentDirectory[task.claimedAgentId]?.displayName || task.claimedAgentId;
    }
    return "Unassigned";
}

function RelatedIssuesTab({
    task,
    project,
    createModalActors,
    createModalTeams,
    agentDirectory,
    openTaskDetails
}) {
    const groups = buildRelatedIssueGroups(task, project.tasks);
    const total = groups.reduce((sum, group) => sum + group.items.length, 0);

    if (total === 0) {
        return <p className="placeholder-text">No related issues.</p>;
    }

    return (
        <div className="td-related-issues">
            <div className="td-related-issues-head">
                <strong>Related issues</strong>
                <span>{total}</span>
            </div>
            <div className="td-related-issues-table" role="table" aria-label="Related issues">
                <div className="td-related-issues-row td-related-issues-row--header" role="row">
                    <span>Key</span>
                    <span>Summary</span>
                    <span>Status</span>
                    <span>Assignee</span>
                    <span>Updated</span>
                </div>
                {groups.map((group) => (
                    <React.Fragment key={group.id}>
                        <div className="td-related-issues-group">
                            <strong>{group.title}</strong>
                            <span>{group.items.length}</span>
                        </div>
                        {group.items.map((item) => (
                            <button
                                type="button"
                                key={`${group.id}-${item.task.id}`}
                                className="td-related-issues-row td-related-issues-row--item"
                                onClick={() => openTaskDetails(item.task)}
                            >
                                <span className="td-related-key">
                                    <span className="material-symbols-rounded" aria-hidden="true">task_alt</span>
                                    #{item.task.id}
                                </span>
                                <span className="td-related-title">{item.task.title}</span>
                                <span className="td-related-status">
                                    <span className="tcm-status-dot" style={{ background: TASK_STATUS_COLORS[item.task.status] || "#94a3b8" }} />
                                    {statusTitle(item.task.status)}
                                </span>
                                <span>{taskAssigneeLabel(item.task, createModalActors, createModalTeams, agentDirectory)}</span>
                                <span>{formatRelativeTime(item.task.updatedAt)}</span>
                            </button>
                        ))}
                    </React.Fragment>
                ))}
            </div>
        </div>
    );
}

function TaskTagsValue({ tags }) {
    const normalizedTags = Array.isArray(tags)
        ? tags.map((tag) => String(tag || "").trim()).filter(Boolean)
        : [];

    if (normalizedTags.length === 0) {
        return <span className="td-prop-empty">—</span>;
    }

    return (
        <span className="td-prop-tags">
            {normalizedTags.map((tag) => (
                <span key={tag} className="project-task-tag-badge">{tag}</span>
            ))}
        </span>
    );
}

function commentCreatedAtMs(comment) {
    const createdAt = new Date(comment?.createdAt || "");
    return Number.isNaN(createdAt.getTime()) ? 0 : createdAt.getTime();
}

function formatAbsoluteDateTime(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
        return "Unknown date";
    }

    return new Intl.DateTimeFormat(undefined, {
        dateStyle: "medium",
        timeStyle: "short"
    }).format(date);
}

function CommentsTab({ project, task, createModalActors, agentDirectory, openTaskDetails }) {
    const [comments, setComments] = useState([]);
    const [loading, setLoading] = useState(true);
    const [commentText, setCommentText] = useState("");
    const [commentSortOrder, setCommentSortOrder] = useState("newest");
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

    const sortedComments = useMemo(() => {
        const direction = commentSortOrder === "oldest" ? 1 : -1;
        return [...comments].sort((left, right) => {
            const createdDelta = commentCreatedAtMs(left) - commentCreatedAtMs(right);
            if (createdDelta !== 0) {
                return createdDelta * direction;
            }

            return String(left.id || "").localeCompare(String(right.id || "")) * direction;
        });
    }, [comments, commentSortOrder]);

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
            <form className="td-comment-form" onSubmit={handleSubmit}>
                <ProjectMentionTextarea
                    className="td-comment-textarea"
                    value={commentText}
                    onChange={(e) => setCommentText(e.target.value)}
                    project={project}
                    placeholder="Leave a comment... use # for tasks, / for files and skills"
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

            <div className="td-comments-toolbar">
                <span>{comments.length === 1 ? "1 comment" : `${comments.length} comments`}</span>
                <div className="td-comment-sort" role="group" aria-label="Sort comments">
                    <button
                        type="button"
                        className={commentSortOrder === "newest" ? "active" : ""}
                        aria-pressed={commentSortOrder === "newest"}
                        onClick={() => setCommentSortOrder("newest")}
                    >
                        Newest
                    </button>
                    <button
                        type="button"
                        className={commentSortOrder === "oldest" ? "active" : ""}
                        aria-pressed={commentSortOrder === "oldest"}
                        onClick={() => setCommentSortOrder("oldest")}
                    >
                        Oldest
                    </button>
                </div>
            </div>

            {loading ? (
                <LoadingSkeleton label="Loading comments…" variant="list" rows={3} />
            ) : comments.length === 0 ? (
                <p className="placeholder-text">No comments yet.</p>
            ) : (
                <div className="td-comments-list">
                    {sortedComments.map((comment) => {
                        const author = createModalActors.find((a) => a.id === comment.authorActorId);
                        const authorLabel = author ? author.displayName : comment.authorActorId;
                        const mentionedActor = comment.mentionedActorId
                            ? createModalActors.find((a) => a.id === comment.mentionedActorId)
                            : null;
                        return (
                            <div key={comment.id} className={`td-comment-item ${comment.isAgentReply ? "td-comment-item--agent" : ""}`}>
                                <div className="td-comment-header">
                                    <CommentAvatar comment={comment} author={author} agentDirectory={agentDirectory} />
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
                                    <time className="td-comment-time" dateTime={comment.createdAt} title={formatAbsoluteDateTime(comment.createdAt)}>
                                        <span>{formatRelativeTime(comment.createdAt)}</span>
                                        <span className="td-comment-time-absolute">{formatAbsoluteDateTime(comment.createdAt)}</span>
                                    </time>
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
                                    <LinkedMarkdown project={project} openTaskDetails={openTaskDetails}>{comment.content}</LinkedMarkdown>
                                </div>
                            </div>
                        );
                    })}
                </div>
            )}
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
                <LoadingSkeleton label="Loading activity…" variant="list" rows={4} />
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
                <LoadingSkeleton label="Loading logs…" variant="code" rows={6} />
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
                <LoadingSkeleton label="Loading diff…" variant="code" rows={8} />
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

    if (loading) return <LoadingSkeleton label="Loading clarifications…" variant="list" rows={3} />;
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
export const TASK_SIDE_VIEW_STORAGE_KEY = "sloppy.taskSideView.widthPercent";
const TASK_SIDE_VIEW_DEFAULT_PERCENT = 42;
const TASK_SIDE_VIEW_MIN_PERCENT = 25;
const TASK_SIDE_VIEW_MAX_PERCENT = 80;

export function clampTaskSideViewWidthPercent(value) {
    const numeric = Number(value);
    if (!Number.isFinite(numeric)) return TASK_SIDE_VIEW_DEFAULT_PERCENT;
    return Math.min(TASK_SIDE_VIEW_MAX_PERCENT, Math.max(TASK_SIDE_VIEW_MIN_PERCENT, numeric));
}

export function readTaskSideViewWidthPercent() {
    if (typeof window === "undefined") return TASK_SIDE_VIEW_DEFAULT_PERCENT;
    try {
        return clampTaskSideViewWidthPercent(window.localStorage.getItem(TASK_SIDE_VIEW_STORAGE_KEY));
    } catch {
        return TASK_SIDE_VIEW_DEFAULT_PERCENT;
    }
}

export function TaskDetailView({
    project,
    task,
    editDraft,
    updateEditDraft,
    saveTaskEdit,
    revertTaskEdit,
    closeTaskDetails,
    updateDetailAssignee,
    deleteTaskFromModal,
    openTaskDetails,
    createModalActors,
    createModalTeams,
    agentDirectory,
    onOpenReview,
    isSideView = false,
    onExpand = null
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
    const [actionsOpen, setActionsOpen] = useState(false);
    const [meshState, setMeshState] = useState(null);
    const [meshSelectedNodeId, setMeshSelectedNodeId] = useState("");
    const [meshDispatchStatus, setMeshDispatchStatus] = useState("");
    const [meshDispatchBusy, setMeshDispatchBusy] = useState(false);
    const [isDescriptionEditing, setIsDescriptionEditing] = useState(() => !String(task.description || "").trim());
    const [propertiesCollapsed, setPropertiesCollapsed] = useState(false);
    const descriptionInputRef = useRef(null);
    const hasReviewDiff = Boolean(task.worktreeBranch);
    const canShowReviewTab = hasReviewDiff || task.status === "needs_review";
    const useInlineProperties = isSideView || isMobileTaskDetail;

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
        if (!actionsOpen) {
            return;
        }
        function closeActions() {
            setActionsOpen(false);
        }
        function onKeyDown(e) {
            if (e.key === "Escape") {
                setActionsOpen(false);
            }
        }
        window.addEventListener("mousedown", closeActions);
        window.addEventListener("keydown", onKeyDown);
        return () => {
            window.removeEventListener("mousedown", closeActions);
            window.removeEventListener("keydown", onKeyDown);
        };
    }, [actionsOpen]);

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
    const parentTask = task.parentTaskId
        ? project.tasks.find((candidate) => String(candidate.id || "").trim() === String(task.parentTaskId || "").trim())
        : null;
    const createdByLabel = task.createdBy || "—";
    const relatedIssueCount = buildRelatedIssueGroups(task, project.tasks).reduce((sum, group) => sum + group.items.length, 0);
    const descriptionMode = taskDescriptionMode(editDraft.description, isDescriptionEditing);
    const meshProject = useMemo(() => {
        const sharedProjects = Array.isArray(meshState?.sharedProjects) ? meshState.sharedProjects : [];
        const projectId = String(project?.id || "").trim();
        const projectName = String(project?.name || "").trim();
        return sharedProjects.find((item) => (
            String(item?.id || "") === projectId ||
            String(item?.name || "") === projectName
        )) || null;
    }, [meshState, project?.id, project?.name]);
    const meshNodes = useMemo(() => {
        const nodes = Array.isArray(meshState?.nodes) ? meshState.nodes : [];
        const memberIds = new Set((Array.isArray(meshProject?.members) ? meshProject.members : [])
            .map((member) => String(member?.nodeId || "").trim())
            .filter(Boolean));
        return nodes.filter((node) => memberIds.has(String(node?.id || "").trim()));
    }, [meshProject, meshState]);

    useEffect(() => {
        setIsDescriptionEditing(!String(task.description || "").trim());
        setPropertiesCollapsed(false);
    }, [task.id, task.description]);

    useEffect(() => {
        let cancelled = false;
        async function loadMesh() {
            const state = await fetchMeshState().catch(() => null);
            if (cancelled) return;
            setMeshState(state);
        }
        loadMesh();
        return () => { cancelled = true; };
    }, [project.id]);

    useEffect(() => {
        setMeshSelectedNodeId((current) => {
            if (current && meshNodes.some((node) => String(node?.id || "") === current)) {
                return current;
            }
            return String(meshNodes[0]?.id || "");
        });
    }, [meshNodes]);

    useEffect(() => {
        const input = descriptionInputRef.current;
        if (!input || descriptionMode !== "editor") return;
        input.style.height = "auto";
        input.style.height = `${input.scrollHeight}px`;
    }, [descriptionMode, editDraft.description, task.id]);

    function focusDescriptionEditor() {
        setIsDescriptionEditing(true);
        requestAnimationFrame(() => {
            const input = descriptionInputRef.current;
            if (!input) return;
            input.focus();
            const end = String(input.value || "").length;
            input.setSelectionRange(end, end);
        });
    }

    async function dispatchTaskToMesh() {
        if (!meshProject?.id || !meshSelectedNodeId || meshDispatchBusy) {
            return;
        }
        setMeshDispatchBusy(true);
        setMeshDispatchStatus("Dispatching to mesh...");
        try {
            const title = `#${task.id} ${String(editDraft.title || task.title || "Task").trim()}`;
            const result = await createMeshTask({
                projectId: meshProject.id,
                title,
                assignedNodeId: meshSelectedNodeId
            });
            if (!result) {
                setMeshDispatchStatus("Mesh dispatch failed.");
                return;
            }
            setMeshDispatchStatus(`Dispatched to ${meshSelectedNodeId}.`);
        } catch (error) {
            setMeshDispatchStatus(error?.message || "Mesh dispatch failed.");
        } finally {
            setMeshDispatchBusy(false);
        }
    }

    async function copyTaskReference() {
        const value = `#${task.id}`;
        try {
            await navigator.clipboard?.writeText(value);
        } catch {
            // Clipboard can be unavailable in non-secure contexts; keep this action quiet.
        }
    }

    function renderPropertiesBody() {
        return (
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
                        <span className="td-prop-label">Type</span>
                        <span className="td-prop-value td-prop-value--static">
                            <span className="material-symbols-rounded td-prop-value-icon" aria-hidden="true">task</span>
                            Task
                        </span>
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
                        <span className="td-prop-label">Author</span>
                        <span className="td-prop-value td-prop-value--static">{createdByLabel}</span>
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

                    <div className="td-mesh-dispatch-card">
                        <div className="td-mesh-dispatch-head">
                            <span className="material-symbols-rounded" aria-hidden="true">hub</span>
                            <div>
                                <strong>Mesh dispatch</strong>
                                <small>Send this task to a worker node.</small>
                            </div>
                        </div>
                        {!meshProject ? (
                            <p>Enable Mesh Sharing in this project's Settings before dispatching tasks to nodes.</p>
                        ) : meshNodes.length === 0 ? (
                            <p>Attach at least one mesh worker to this project in Settings.</p>
                        ) : (
                            <>
                                <div className="td-mesh-node-options" role="group" aria-label="Mesh worker nodes">
                                    {meshNodes.map((node) => {
                                        const nodeId = String(node?.id || "");
                                        const active = meshSelectedNodeId === nodeId;
                                        return (
                                            <button
                                                key={nodeId}
                                                type="button"
                                                className={active ? "active" : ""}
                                                onClick={() => setMeshSelectedNodeId(nodeId)}
                                            >
                                                <strong>{String(node?.name || nodeId)}</strong>
                                                <small>{String(node?.endpoint || node?.status || "offline")}</small>
                                            </button>
                                        );
                                    })}
                                </div>
                                <button
                                    type="button"
                                    className="td-mesh-dispatch-button"
                                    disabled={!meshSelectedNodeId || meshDispatchBusy}
                                    onClick={() => void dispatchTaskToMesh()}
                                >
                                    <span className="material-symbols-rounded" aria-hidden="true">send</span>
                                    {meshDispatchBusy ? "Dispatching" : "Dispatch to mesh"}
                                </button>
                            </>
                        )}
                        {meshDispatchStatus ? <p className="td-mesh-dispatch-status">{meshDispatchStatus}</p> : null}
                    </div>

                    <div className="td-prop-row td-prop-row--stacked">
                        <span className="td-prop-label">Tags</span>
                        <TaskTagsValue tags={task.tags} />
                    </div>

                    <div className="td-prop-row">
                        <span className="td-prop-label">Parent issue</span>
                        {parentTask ? (
                            <button
                                type="button"
                                className="td-prop-value td-prop-link"
                                onClick={() => openTaskDetails(parentTask)}
                            >
                                #{parentTask.id}
                            </button>
                        ) : (
                            <span className="td-prop-empty">—</span>
                        )}
                    </div>

                    <div className="td-prop-row">
                        <span className="td-prop-label">Related issues</span>
                        <span className="td-prop-value td-prop-value--static">{relatedIssueCount || "—"}</span>
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
        );
    }

    function renderInlineProperties() {
        return (
            <section
                id="td-task-properties"
                className={`td-inline-properties ${propertiesCollapsed ? "td-inline-properties--collapsed" : ""}`}
            >
                <button
                    type="button"
                    className="td-inline-properties-header"
                    onClick={() => setPropertiesCollapsed((collapsed) => !collapsed)}
                    aria-expanded={!propertiesCollapsed}
                    aria-controls="td-task-properties-body"
                >
                    <span>Properties</span>
                    <span className="material-symbols-rounded" aria-hidden="true">
                        {propertiesCollapsed ? "expand_more" : "expand_less"}
                    </span>
                </button>
                {!propertiesCollapsed ? (
                    <div id="td-task-properties-body" className="td-inline-properties-body">
                        {renderPropertiesBody()}
                    </div>
                ) : null}
            </section>
        );
    }

    return (
        <div
            className={`td-page ${isSideView ? "td-page--side-view" : ""} ${!useInlineProperties && !sidebarOpen ? "td-page--sidebar-closed" : ""}`}
        >
            <div className="td-main">
                <header className="td-toolbar">
                    <div className="td-toolbar-left">
                        <button type="button" className="td-toolbar-project" onClick={closeTaskDetails}>
                            {project.name}
                        </button>
                        <span className="td-toolbar-separator">/</span>
                        <span className="td-toolbar-status-token" title={currentStatus.title}>
                            <span className="tcm-status-dot" style={{ background: TASK_STATUS_COLORS[currentStatus.id] }} />
                        </span>
                        <span className="td-toolbar-task-id">{task.id}</span>
                        <button
                            type="button"
                            className="td-toolbar-action"
                            onClick={() => void copyTaskReference()}
                            aria-label="Copy task reference"
                            title="Copy task reference"
                        >
                            <span className="material-symbols-rounded" aria-hidden="true">content_copy</span>
                        </button>
                        {githubIssueURL ? (
                            <a
                                className="td-toolbar-action"
                                href={githubIssueURL}
                                target="_blank"
                                rel="noreferrer"
                                aria-label={githubIssueLabel}
                                title={githubIssueLabel}
                            >
                                <span className="material-symbols-rounded" aria-hidden="true">link</span>
                            </a>
                        ) : null}
                    </div>
                    <div className="td-toolbar-right">
                        {isSideView && onExpand ? (
                            <button
                                type="button"
                                className="td-toolbar-action"
                                onClick={onExpand}
                                aria-label="Open task fullscreen"
                                title="Open task fullscreen"
                            >
                                <span className="material-symbols-rounded" aria-hidden="true">open_in_full</span>
                            </button>
                        ) : null}
                        {task.status === "needs_review" && onOpenReview && (
                            <button
                                type="button"
                                className="td-toolbar-action"
                                onClick={() => onOpenReview(task)}
                                aria-label="Open review"
                                title="Open review"
                            >
                                <span className="material-symbols-rounded" aria-hidden="true">rate_review</span>
                            </button>
                        )}
                        {isMobileTaskDetail && (
                            <button
                                type="button"
                                className="td-toolbar-action"
                                onClick={() => setPropertiesCollapsed((collapsed) => !collapsed)}
                                aria-expanded={!propertiesCollapsed}
                                aria-controls="td-task-properties"
                                aria-label="Toggle properties"
                                title="Properties"
                            >
                                <span className="material-symbols-rounded" aria-hidden="true">tune</span>
                            </button>
                        )}
                        {!useInlineProperties && !sidebarOpen && (
                            <button
                                type="button"
                                className="td-toolbar-action"
                                onClick={() => setSidebarOpen(true)}
                                aria-label="Show properties"
                                title="Show properties"
                            >
                                <span className="material-symbols-rounded">right_panel_open</span>
                            </button>
                        )}
                        <div
                            className="td-actions-wrap"
                            onMouseDown={(event) => event.stopPropagation()}
                            onClick={(event) => event.stopPropagation()}
                        >
                            <button
                                type="button"
                                className="td-toolbar-action"
                                onClick={() => setActionsOpen((open) => !open)}
                                aria-haspopup="menu"
                                aria-expanded={actionsOpen}
                                aria-label="Task actions"
                                title="Task actions"
                            >
                                <span className="material-symbols-rounded" aria-hidden="true">more_horiz</span>
                            </button>
                            {actionsOpen ? (
                                <div className="td-actions-menu" role="menu">
                                    <button
                                        type="button"
                                        className="danger"
                                        role="menuitem"
                                        onClick={() => {
                                            setActionsOpen(false);
                                            deleteTaskFromModal();
                                        }}
                                    >
                                        <span className="material-symbols-rounded" aria-hidden="true">delete</span>
                                        Delete task
                                    </button>
                                </div>
                            ) : null}
                        </div>
                        <span className="td-toolbar-divider" aria-hidden="true" />
                        <button
                            type="button"
                            className="td-toolbar-action td-toolbar-action--close"
                            onClick={closeTaskDetails}
                            aria-label="Close task details"
                            title="Close"
                        >
                            <span className="material-symbols-rounded" aria-hidden="true">close</span>
                        </button>
                    </div>
                </header>

                <div className="td-id-row td-id-row--meta">
                    <span>Created {formatRelativeTime(task.createdAt)}</span>
                    <span>updated {formatRelativeTime(task.updatedAt)}</span>
                </div>

                <div className="td-content">
                    <input
                        className="td-title-input"
                        value={editDraft.title}
                        onChange={(e) => updateEditDraft("title", e.target.value)}
                        placeholder="Task title"
                    />
                    {descriptionMode === "editor" ? (
                        <ProjectMentionTextarea
                            textareaRef={descriptionInputRef}
                            className="td-desc-input"
                            value={editDraft.description}
                            onChange={(e) => updateEditDraft("description", e.target.value)}
                            onBlur={() => {
                                if (String(editDraft.description || "").trim()) {
                                    setIsDescriptionEditing(false);
                                }
                            }}
                            project={project}
                            placeholder="Add description... use # for tasks, / for files and skills"
                            rows={5}
                        />
                    ) : (
                        <div
                            role="button"
                            tabIndex={0}
                            className="td-desc-preview markdown-body"
                            onClick={focusDescriptionEditor}
                            onKeyDown={(event) => {
                                if (event.key === "Enter" || event.key === " ") {
                                    event.preventDefault();
                                    focusDescriptionEditor();
                                }
                            }}
                            aria-label="Edit description"
                        >
                            <LinkedMarkdown project={project} openTaskDetails={openTaskDetails}>
                                {editDraft.description}
                            </LinkedMarkdown>
                        </div>
                    )}
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

                {useInlineProperties ? renderInlineProperties() : null}

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
                            Related issues
                            {relatedIssueCount > 0 ? <span className="td-tab-count">{relatedIssueCount}</span> : null}
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
                                agentDirectory={agentDirectory}
                                openTaskDetails={openTaskDetails}
                            />
                        )}
                        {activeTab === "subtasks" && (
                            <RelatedIssuesTab
                                task={task}
                                project={project}
                                createModalActors={createModalActors}
                                createModalTeams={createModalTeams}
                                agentDirectory={agentDirectory}
                                openTaskDetails={openTaskDetails}
                            />
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

            {!useInlineProperties ? (
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

                    {renderPropertiesBody()}
                </aside>
            ) : null}

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
