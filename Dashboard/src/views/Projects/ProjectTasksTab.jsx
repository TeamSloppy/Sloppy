import React from "react";
import {
    TASK_STATUSES,
    TASK_PRIORITIES,
    TASK_PRIORITY_LABELS,
    buildTaskCounts,
    buildSwarmGroups,
    formatRelativeTime,
    sortTasksByDate
} from "./utils";

export function ProjectTasksTab({
    project,
    selectedTask,
    editDraft,
    isTaskDetailFullscreen,
    updateEditDraft,
    saveTaskEdit,
    setIsTaskDetailFullscreen,
    closeTaskDetails,
    updateDetailAssignee,
    deleteTaskFromModal,
    openTaskDetails,
    openCreateTaskModal,
    moveTask,
    createModalActors,
    createModalTeams
}) {
    const taskCounts = buildTaskCounts(project.tasks);
    const swarmGroups = buildSwarmGroups(project.tasks);
    const selectedTaskId = selectedTask ? String(selectedTask.id || "").trim() : "";

    const renderTaskDetail = (task, isFullscreen = false) => {
        const taskReference = String(task.id || "").trim();
        const statusTitle = TASK_STATUSES.find((status) => status.id === editDraft.status)?.title || editDraft.status;
        const priorityTitle = TASK_PRIORITY_LABELS[editDraft.priority] || "Medium";
        const assigneeToken = editDraft.actorId
            ? `actor:${editDraft.actorId}`
            : editDraft.teamId
                ? `team:${editDraft.teamId}`
                : "";
        const assigneeLabel = editDraft.actorId || editDraft.teamId || "Unassigned";

        return (
            <article className={`project-task-composer ${isFullscreen ? "project-task-composer--fullscreen" : ""}`}>
                <header className="project-task-composer-head">
                    <div className="project-task-composer-breadcrumbs">
                        <span className="project-task-composer-badge">{project.id}</span>
                        <span className="material-symbols-rounded" aria-hidden="true">
                            chevron_right
                        </span>
                        <span className="project-task-composer-badge">Task</span>
                    </div>

                    <div className="project-task-composer-actions">
                        <button
                            type="button"
                            className="project-task-composer-save"
                            onClick={saveTaskEdit}
                            disabled={!String(editDraft.title || "").trim()}
                        >
                            Save as draft
                        </button>
                        <button
                            type="button"
                            className="project-task-detail-icon-button"
                            onClick={() => setIsTaskDetailFullscreen((value) => !value)}
                            aria-label={isTaskDetailFullscreen ? "Exit fullscreen task card" : "Expand task card fullscreen"}
                            title={isTaskDetailFullscreen ? "Exit fullscreen" : "Fullscreen"}
                        >
                            <span className="material-symbols-rounded" aria-hidden="true">
                                {isTaskDetailFullscreen ? "close_fullscreen" : "open_in_full"}
                            </span>
                        </button>
                        <button
                            type="button"
                            className="project-task-detail-icon-button"
                            onClick={closeTaskDetails}
                            aria-label="Close task detail"
                            title="Close task detail"
                        >
                            <span className="material-symbols-rounded" aria-hidden="true">
                                close
                            </span>
                        </button>
                    </div>
                </header>

                <div className="project-task-composer-editor">
                    <input
                        className="project-task-composer-title-input"
                        value={editDraft.title}
                        onChange={(event) => updateEditDraft("title", event.target.value)}
                        placeholder="Task title..."
                        autoFocus
                    />
                    <textarea
                        className="project-task-composer-desc-input"
                        value={editDraft.description}
                        onChange={(event) => updateEditDraft("description", event.target.value)}
                        rows={2}
                        placeholder="Write a task note..."
                    />
                </div>

                <div className="project-task-composer-row">
                    <label className="project-task-composer-chip">
                        <span className="material-symbols-rounded" aria-hidden="true">
                            radio_button_unchecked
                        </span>
                        <select value={editDraft.status} onChange={(event) => updateEditDraft("status", event.target.value)} aria-label="Task status">
                            {TASK_STATUSES.map((status) => (
                                <option key={status.id} value={status.id}>
                                    {status.title}
                                </option>
                            ))}
                        </select>
                    </label>

                    <label className="project-task-composer-chip">
                        <span className="material-symbols-rounded" aria-hidden="true">
                            flag
                        </span>
                        <select value={editDraft.priority} onChange={(event) => updateEditDraft("priority", event.target.value)} aria-label="Task priority">
                            {TASK_PRIORITIES.map((priority) => (
                                <option key={priority} value={priority}>
                                    {TASK_PRIORITY_LABELS[priority]}
                                </option>
                            ))}
                        </select>
                    </label>

                    <label className="project-task-composer-chip">
                        <span className="material-symbols-rounded" aria-hidden="true">
                            person
                        </span>
                        <select value={assigneeToken} onChange={(event) => updateDetailAssignee(event.target.value)} aria-label="Task assignee">
                            <option value="">Unassigned</option>
                            {createModalActors.map((actor) => (
                                <option key={`actor-${actor.id}`} value={`actor:${actor.id}`}>
                                    {actor.displayName}
                                </option>
                            ))}
                            {createModalTeams.map((team) => (
                                <option key={`team-${team.id}`} value={`team:${team.id}`}>
                                    {team.name}
                                </option>
                            ))}
                        </select>
                    </label>
                </div>

                <footer className="project-task-composer-footer">
                    <span className="project-task-composer-meta">/tasks/{taskReference}</span>
                    <span className="project-task-composer-meta">{statusTitle}</span>
                    <span className="project-task-composer-meta">{priorityTitle}</span>
                    <span className="project-task-composer-meta">{assigneeLabel}</span>
                    <button type="button" className="danger" onClick={deleteTaskFromModal}>
                        Delete task
                    </button>
                </footer>
            </article>
        );
    };

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
                    <button type="button" className="project-primary hover-levitate" onClick={() => openCreateTaskModal("backlog")}>
                        Create Task
                    </button>
                </div>

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
                        const tasks = sortTasksByDate(project.tasks.filter((task) => task.status === column.id)).sort((left, right) => {
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
                                onDragOver={(event) => event.preventDefault()}
                                onDrop={(event) => {
                                    event.preventDefault();
                                    const taskId = event.dataTransfer.getData("text/project-task-id");
                                    if (taskId) {
                                        moveTask(taskId, column.id);
                                    }
                                }}
                            >
                                <header className={`project-kanban-column-head project-kanban-column-head--${column.id}`}>
                                    <span>{column.title}</span>
                                    <strong>{tasks.length}</strong>
                                </header>

                                <div className="project-kanban-column-body">
                                    {tasks.length === 0 ? (
                                        <p className="placeholder-text">No tasks</p>
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
                                                            }`}
                                                        role="button"
                                                        tabIndex={0}
                                                        draggable
                                                        onClick={() => openTaskDetails(task)}
                                                        onKeyDown={(event) => {
                                                            if (event.key === "Enter" || event.key === " ") {
                                                                event.preventDefault();
                                                                openTaskDetails(task);
                                                            }
                                                        }}
                                                        onDragStart={(event) => {
                                                            event.dataTransfer.setData("text/project-task-id", task.id);
                                                            event.dataTransfer.effectAllowed = "move";
                                                        }}
                                                    >
                                                        <div className="project-task-card-top">
                                                            <span className="project-task-id">#{task.id}</span>
                                                            <span className="project-task-card-open">
                                                                <span className="material-symbols-rounded" aria-hidden="true">
                                                                    open_in_new
                                                                </span>
                                                                Open
                                                            </span>
                                                        </div>
                                                        <h5>{task.title}</h5>
                                                        {task.description ? <p>{task.description}</p> : null}

                                                        <div className="project-task-meta">
                                                            <span className={`project-priority-badge ${task.priority}`}>
                                                                <span className="material-symbols-rounded" aria-hidden="true">
                                                                    flag
                                                                </span>
                                                                {TASK_PRIORITY_LABELS[task.priority] || "Medium"}
                                                            </span>
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
                                                                <span className="project-task-claim-badge">
                                                                    <span className="material-symbols-rounded" aria-hidden="true">
                                                                        smart_toy
                                                                    </span>
                                                                    Agent: {task.claimedAgentId}
                                                                </span>
                                                            ) : null}
                                                            {!task.claimedAgentId && task.claimedActorId ? (
                                                                <span className="project-task-claim-badge">
                                                                    <span className="material-symbols-rounded" aria-hidden="true">
                                                                        person
                                                                    </span>
                                                                    Actor: {task.claimedActorId}
                                                                </span>
                                                            ) : null}
                                                            {!task.claimedAgentId && !task.claimedActorId && task.actorId ? (
                                                                <span className="project-task-assignee-badge">
                                                                    <span className="material-symbols-rounded" aria-hidden="true">
                                                                        assignment_ind
                                                                    </span>
                                                                    Assigned actor: {task.actorId}
                                                                </span>
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
            </section>

            {selectedTask ? (
                <div className={`project-task-detail-overlay ${isTaskDetailFullscreen ? "project-task-detail-overlay--fullscreen" : ""}`} onClick={closeTaskDetails}>
                    <div onClick={(event) => event.stopPropagation()}>{renderTaskDetail(selectedTask, isTaskDetailFullscreen)}</div>
                </div>
            ) : null}
        </section>
    );
}
