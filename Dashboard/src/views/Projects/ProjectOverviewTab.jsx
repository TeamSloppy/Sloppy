import React from "react";
import {
    TASK_PRIORITY_LABELS,
    TASK_STATUSES,
    TASK_STATUS_COLORS,
    buildAttentionTasks,
    buildChannelActivity,
    buildOverviewMetrics,
    buildProjectReadiness,
    formatRelativeTime
} from "./utils";

const ATTENTION_TASK_LIMIT = 6;
const CHANNEL_ACTIVITY_LIMIT = 4;
const RECENT_OUTPUT_LIMIT = 6;

const STATUS_LABELS = new Map(TASK_STATUSES.map((status) => [status.id, status.title]));

function SectionAction({ label, onClick }) {
    return (
        <button type="button" className="project-pane-link" onClick={onClick}>
            {label}
        </button>
    );
}

function MetricCard({ metric, onOpenTab }) {
    const clickable = typeof onOpenTab === "function" && metric.tabId;
    const Tag = clickable ? "button" : "article";

    return (
        <Tag
            type={clickable ? "button" : undefined}
            className={`project-metric-card ${clickable ? "project-metric-card--interactive" : ""}`}
            onClick={clickable ? () => onOpenTab(metric.tabId) : undefined}
        >
            <p>{metric.label}</p>
            <strong>{metric.value}</strong>
            <span className="project-metric-sub">{metric.sublabel}</span>
        </Tag>
    );
}

function DeliveryFunnel({ taskCounts }) {
    const total = Number(taskCounts?.total || 0);
    const done = Number(taskCounts?.done || 0);
    const donePercent = total > 0 ? Math.round((done / total) * 100) : 0;

    if (total === 0) {
        return (
            <div className="project-overview-empty">
                <p className="placeholder-text">
                    No tasks yet. Create a few work items and this project will start showing delivery flow.
                </p>
            </div>
        );
    }

    return (
        <div className="project-funnel">
            <div className="project-funnel-head">
                <strong>{donePercent}% complete</strong>
                <span className="placeholder-text">{done} of {total} done</span>
            </div>

            <div className="project-funnel-progress">
                <div className="project-funnel-progress-bar" style={{ width: `${donePercent}%` }} />
            </div>

            <div className="project-funnel-list">
                {TASK_STATUSES.map((status) => {
                    const count = Number(taskCounts?.[status.id] || 0);
                    const width = total > 0 ? Math.max((count / total) * 100, count > 0 ? 8 : 0) : 0;

                    return (
                        <div key={status.id} className="project-funnel-row">
                            <div className="project-funnel-row-head">
                                <span className="project-funnel-label">{status.title}</span>
                                <strong>{count}</strong>
                            </div>
                            <div className="project-funnel-track">
                                <div
                                    className="project-funnel-fill"
                                    style={{ width: `${width}%`, background: TASK_STATUS_COLORS[status.id] || "var(--accent)" }}
                                />
                            </div>
                        </div>
                    );
                })}
            </div>
        </div>
    );
}

function AttentionTaskRow({ task, onOpenTask }) {
    const statusLabel = STATUS_LABELS.get(task.status) || task.status;
    const priorityLabel = TASK_PRIORITY_LABELS[task.priority] || task.priority;
    const assignee = task.claimedActorId || task.actorId || task.teamId || "";

    return (
        <button type="button" className="project-overview-task" onClick={() => onOpenTask(task)}>
            <div className="project-overview-task-head">
                <strong>{task.title}</strong>
                <span
                    className="project-overview-task-status"
                    style={{ borderColor: TASK_STATUS_COLORS[task.status] || "var(--line)", color: TASK_STATUS_COLORS[task.status] || "var(--text)" }}
                >
                    {statusLabel}
                </span>
            </div>
            <div className="project-overview-task-meta">
                <span>{priorityLabel} priority</span>
                {assignee ? <span>{assignee}</span> : <span>Unassigned</span>}
                <span>{formatRelativeTime(task.updatedAt)}</span>
            </div>
        </button>
    );
}

function AttentionSection({ project, onOpenTask, onOpenTab }) {
    const attentionTasks = buildAttentionTasks(project.tasks).slice(0, ATTENTION_TASK_LIMIT);

    return (
        <section className="project-pane">
            <div className="project-pane-head">
                <h4>Attention Required</h4>
                <SectionAction label="Open Tasks" onClick={() => onOpenTab("tasks")} />
            </div>

            {project.tasks.length === 0 ? (
                <p className="placeholder-text">
                    No tasks yet. Add tasks to start tracking blockers and review work here.
                </p>
            ) : attentionTasks.length === 0 ? (
                <p className="placeholder-text">
                    Nothing is blocked or waiting for review right now.
                </p>
            ) : (
                <div className="project-overview-task-list">
                    {attentionTasks.map((task) => (
                        <AttentionTaskRow key={task.id} task={task} onOpenTask={onOpenTask} />
                    ))}
                </div>
            )}
        </section>
    );
}

function buildActivityPreview(channel) {
    if (channel.previewText) {
        if (channel.lastMessageUserId) {
            return `${channel.lastMessageUserId}: ${channel.previewText}`;
        }
        return channel.previewText;
    }

    if (channel.activeWorkerCount > 0) {
        return "Workers are actively processing this channel.";
    }

    return "No recent runtime activity.";
}

function LiveActivitySection({ channels, onOpenTab }) {
    const visibleChannels = channels.filter((channel) => channel.hasActivity).slice(0, CHANNEL_ACTIVITY_LIMIT);
    const [expandedChannelId, setExpandedChannelId] = React.useState(null);

    const expandedChannel = expandedChannelId
        ? visibleChannels.find((c) => c.channelId === expandedChannelId)
        : null;

    React.useEffect(() => {
        if (!expandedChannelId) {
            return undefined;
        }
        function onKeyDown(event) {
            if (event.key === "Escape") {
                setExpandedChannelId(null);
            }
        }
        window.addEventListener("keydown", onKeyDown);
        return () => window.removeEventListener("keydown", onKeyDown);
    }, [expandedChannelId]);

    return (
        <section className="project-pane">
            <div className="project-pane-head">
                <h4>Live Activity</h4>
                <SectionAction label="Open Chat" onClick={() => onOpenTab("chat")} />
            </div>

            {visibleChannels.length === 0 ? (
                <p className="placeholder-text">
                    Project is quiet right now. Start a conversation in one of its channels to see activity here.
                </p>
            ) : (
                <div className="project-overview-channel-list">
                    {visibleChannels.map((channel) => {
                        const preview = buildActivityPreview(channel);
                        return (
                            <article key={channel.channelId} className="project-overview-channel">
                                <div className="project-overview-channel-head">
                                    <strong>{channel.title}</strong>
                                    <span className="placeholder-text">
                                        {channel.lastMessageAt ? formatRelativeTime(channel.lastMessageAt) : "active now"}
                                    </span>
                                </div>
                                <div className="project-overview-channel-preview">
                                    <p>{preview}</p>
                                </div>
                                <div className="project-overview-channel-meta">
                                    <span>{channel.messageCount} messages</span>
                                    {channel.activeWorkerCount > 0 ? (
                                        <span>
                                            {channel.activeWorkerCount} worker{channel.activeWorkerCount !== 1 ? "s" : ""} active
                                        </span>
                                    ) : null}
                                    {channel.lastDecision?.action ? (
                                        <span>Decision: {String(channel.lastDecision.action)}</span>
                                    ) : null}
                                </div>
                                <button
                                    type="button"
                                    className="project-overview-channel-read"
                                    onClick={() => setExpandedChannelId(channel.channelId)}
                                >
                                    Read full
                                </button>
                            </article>
                        );
                    })}
                </div>
            )}

            {expandedChannel ? (
                <div
                    className="project-overview-channel-modal-backdrop"
                    role="presentation"
                    onClick={() => setExpandedChannelId(null)}
                >
                    <div
                        className="project-overview-channel-modal"
                        role="dialog"
                        aria-modal="true"
                        aria-labelledby="project-overview-channel-modal-title"
                        onClick={(event) => event.stopPropagation()}
                    >
                        <div className="project-overview-channel-modal-head">
                            <h4 id="project-overview-channel-modal-title">{expandedChannel.title}</h4>
                            <button
                                type="button"
                                className="project-overview-channel-modal-close"
                                onClick={() => setExpandedChannelId(null)}
                                aria-label="Close"
                            >
                                <span className="material-symbols-rounded" aria-hidden="true">
                                    close
                                </span>
                            </button>
                        </div>
                        <p className="project-overview-channel-modal-meta">
                            {expandedChannel.lastMessageAt
                                ? formatRelativeTime(expandedChannel.lastMessageAt)
                                : "active now"}{" "}
                            · {expandedChannel.messageCount} messages
                        </p>
                        <pre className="project-overview-channel-modal-body">{buildActivityPreview(expandedChannel)}</pre>
                    </div>
                </div>
            ) : null}
        </section>
    );
}

function ProjectReadinessSection({ project, onOpenTab }) {
    const readinessItems = buildProjectReadiness(project);

    return (
        <section className="project-pane">
            <div className="project-pane-head">
                <h4>Project Readiness</h4>
                <SectionAction label="Open Settings" onClick={() => onOpenTab("settings")} />
            </div>

            <div className="project-readiness-grid">
                {readinessItems.map((item) => (
                    <article key={item.id} className="project-readiness-item">
                        <span className="project-readiness-label">{item.label}</span>
                        <strong>{item.value}</strong>
                        <p>{item.detail}</p>
                    </article>
                ))}
            </div>
        </section>
    );
}

export function ProjectOverviewTab({
    project,
    taskCounts,
    activeWorkers,
    chatSnapshots,
    createdItems,
    onOpenTab,
    onOpenTask
}) {
    const metrics = buildOverviewMetrics(project, taskCounts, activeWorkers, chatSnapshots);
    const channelActivity = buildChannelActivity(project, chatSnapshots, activeWorkers);
    const recentOutput = [...createdItems].slice(-RECENT_OUTPUT_LIMIT).reverse();

    return (
        <section className="project-tab-layout">
            <section className="project-overview-metrics">
                {metrics.map((metric) => (
                    <MetricCard key={metric.id} metric={metric} onOpenTab={onOpenTab} />
                ))}
            </section>

            <section className="project-overview-grid">
                <AttentionSection project={project} onOpenTask={onOpenTask} onOpenTab={onOpenTab} />
                <section className="project-pane">
                    <div className="project-pane-head">
                        <h4>Delivery Funnel</h4>
                    </div>
                    <DeliveryFunnel taskCounts={taskCounts} />
                </section>
            </section>

            <section className="project-overview-grid">
                <LiveActivitySection channels={channelActivity} onOpenTab={onOpenTab} />
                <ProjectReadinessSection project={project} onOpenTab={onOpenTab} />
            </section>

            <section className="project-pane">
                <div className="project-pane-head">
                    <h4>Recent Output</h4>
                </div>

                {recentOutput.length === 0 ? (
                    <p className="placeholder-text">No files or artifacts detected in project runtime messages yet.</p>
                ) : (
                    <div className="project-created-list">
                        {recentOutput.map((item) => (
                            <article key={item.key} className="project-created-item">
                                <div className="project-overview-output-head">
                                    <strong>{item.type === "artifact" ? "Artifact" : "File"}</strong>
                                    <span className="placeholder-text">{item.channelId}</span>
                                </div>
                                <p>{item.value}</p>
                            </article>
                        ))}
                    </div>
                )}
            </section>
        </section>
    );
}
