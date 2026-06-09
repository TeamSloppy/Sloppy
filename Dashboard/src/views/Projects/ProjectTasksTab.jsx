import React, { useState, useRef, useEffect, useCallback, useMemo } from "react";
import {
    TASK_STATUSES,
    TASK_PRIORITIES,
    TASK_PRIORITY_LABELS,
    TASK_STATUS_COLORS,
    buildTaskCounts,
    buildSwarmGroups,
    formatRelativeTime
} from "./utils";
import {
    buildProjectTaskSelectionOrder,
    sortProjectKanbanColumnTasks,
    taskSelectionRangeIds
} from "./taskSelection";
import {
    fetchAgents,
    fetchArchivedTasks
} from "../../api";
import { AgentPetIcon } from "../../features/agents/components/AgentPetSprite";
import { LoadingSkeleton } from "../../components/LoadingSkeleton";
import { DetailDropdown, TaskDetailView, TASK_SIDE_VIEW_STORAGE_KEY, clampTaskSideViewWidthPercent, readTaskSideViewWidthPercent } from "./ProjectTaskDetails";

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

export function ProjectTasksTab({
    project,
    selectedTask,
    sideTask,
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
    openTaskSideView,
    expandTaskDetails,
    closeTaskSideView,
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
    const [lastSelectedTaskId, setLastSelectedTaskId] = useState("");
    const [contextMenu, setContextMenu] = useState(null);
    const [bulkBusy, setBulkBusy] = useState(false);
    const [sideViewWidthPercent, setSideViewWidthPercent] = useState(readTaskSideViewWidthPercent);
    const [isResizingSideView, setIsResizingSideView] = useState(false);

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
    const visibleTaskSelectionOrder = useMemo(
        () => buildProjectTaskSelectionOrder(filteredActiveTasks, TASK_STATUSES),
        [filteredActiveTasks]
    );

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
        setLastSelectedTaskId((previous) => (
            previous && visibleTaskSelectionOrder.includes(previous) ? previous : ""
        ));
    }, [visibleTaskSelectionOrder]);

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
    const selectedTaskId = (selectedTask || sideTask) ? String((selectedTask || sideTask).id || "").trim() : "";
    const hasTaskFilters = Boolean(tagFilter || assigneeFilter);

    useEffect(() => {
        if (!isResizingSideView) {
            return;
        }
        function updateWidth(event) {
            const width = window.innerWidth || document.documentElement.clientWidth || 1;
            const nextPercent = clampTaskSideViewWidthPercent(((width - event.clientX) / width) * 100);
            setSideViewWidthPercent(nextPercent);
        }
        function stopResize() {
            setIsResizingSideView(false);
        }
        document.body.classList.add("task-side-view-resizing");
        window.addEventListener("pointermove", updateWidth);
        window.addEventListener("pointerup", stopResize);
        return () => {
            document.body.classList.remove("task-side-view-resizing");
            window.removeEventListener("pointermove", updateWidth);
            window.removeEventListener("pointerup", stopResize);
        };
    }, [isResizingSideView]);

    useEffect(() => {
        if (typeof window === "undefined") return;
        try {
            window.localStorage.setItem(TASK_SIDE_VIEW_STORAGE_KEY, String(clampTaskSideViewWidthPercent(sideViewWidthPercent)));
        } catch {
            // Ignore storage failures; resizing should keep working for this session.
        }
    }, [sideViewWidthPercent]);

    function clearSelection() {
        setSelectedTaskIds(new Set());
        setLastSelectedTaskId("");
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
        setLastSelectedTaskId(normalized);
        setContextMenu(null);
    }

    function selectTaskRange(taskId) {
        const normalized = String(taskId || "").trim();
        if (!normalized) {
            return;
        }
        const anchorTaskId = lastSelectedTaskId || (selectedTaskIdList.length === 1 ? selectedTaskIdList[0] : "");
        const rangeIds = taskSelectionRangeIds(visibleTaskSelectionOrder, anchorTaskId, normalized);
        if (rangeIds.length === 0) {
            return;
        }
        setSelectionMode(true);
        setSelectedTaskIds((previous) => {
            const next = new Set(previous);
            rangeIds.forEach((id) => next.add(id));
            return next;
        });
        setLastSelectedTaskId(normalized);
        setContextMenu(null);
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
        setLastSelectedTaskId(taskId);
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
                openTaskDetails={openTaskDetails}
                createModalActors={createModalActors}
                createModalTeams={createModalTeams}
                agentDirectory={agentDirectory}
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
        <section className={`project-tab-layout project-tab-layout--tasks${sideTask ? " project-tab-layout--with-task-side-view" : ""}`}>
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
                        const tasks = sortProjectKanbanColumnTasks(filteredActiveTasks.filter((task) => task.status === column.id));

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
                                                            if (event.shiftKey) {
                                                                event.preventDefault();
                                                                selectTaskRange(task.id);
                                                                return;
                                                            }
                                                            if (selectionMode || event.metaKey || event.ctrlKey) {
                                                                event.preventDefault();
                                                                setSelectionMode(true);
                                                                toggleTaskSelection(task.id);
                                                                return;
                                                            }
                                                            openTaskSideView(task);
                                                        }}
                                                        onContextMenu={(event) => openTaskContextMenu(event, task)}
                                                        onKeyDown={(event) => {
                                                            if (event.key === "Enter" || event.key === " ") {
                                                                event.preventDefault();
                                                                if (selectionMode) {
                                                                    toggleTaskSelection(task.id);
                                                                    return;
                                                                }
                                                                openTaskSideView(task);
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
                                                                            if (event.shiftKey) {
                                                                                selectTaskRange(task.id);
                                                                                return;
                                                                            }
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
                            <LoadingSkeleton label="Loading archived tasks…" variant="list" rows={5} />
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
            {sideTask ? (
                <aside
                    className="task-side-view"
                    style={{ width: `${clampTaskSideViewWidthPercent(sideViewWidthPercent)}vw` }}
                    aria-label="Selected task details"
                >
                    <div
                        className="task-side-view-resize-handle"
                        role="separator"
                        aria-orientation="vertical"
                        aria-label="Resize task details panel"
                        tabIndex={0}
                        onPointerDown={(event) => {
                            event.preventDefault();
                            setIsResizingSideView(true);
                        }}
                    />
                    <TaskDetailView
                        project={project}
                        task={sideTask}
                        editDraft={editDraft}
                        updateEditDraft={updateEditDraft}
                        saveTaskEdit={saveTaskEdit}
                        revertTaskEdit={revertTaskEdit}
                        closeTaskDetails={closeTaskSideView}
                        updateDetailAssignee={updateDetailAssignee}
                        deleteTaskFromModal={deleteTaskFromModal}
                        openTaskDetails={openTaskSideView}
                        createModalActors={createModalActors}
                        createModalTeams={createModalTeams}
                        agentDirectory={agentDirectory}
                        onOpenReview={onOpenReview}
                        isSideView
                        onExpand={() => expandTaskDetails(sideTask)}
                    />
                </aside>
            ) : null}
        </section>
    );
}
