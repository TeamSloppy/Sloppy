import React, { useEffect, useMemo, useState } from "react";
import {
    fetchAgentCronTasks,
    createAgentCronTask,
    updateAgentCronTask,
    deleteAgentCronTask,
    fetchActorsBoard
} from "../../../api";

function CronFormModal({
    isOpen,
    editingId,
    form,
    availableChannels,
    isLoadingChannels,
    onFormChange,
    onClose,
    onSubmit
}) {
    if (!isOpen) {
        return null;
    }

    const selectedChannel = availableChannels.find((channel) => channel.channelId === form.channelId) || null;
    const hasAvailableChannels = availableChannels.length > 0;

    return (
        <div className="project-modal-overlay" onClick={onClose}>
            <section className="project-modal" onClick={(e) => e.stopPropagation()}>
                <div className="project-modal-head">
                    <h3>{editingId ? "Edit Cron Job" : "New Cron Job"}</h3>
                    <button type="button" className="project-modal-close" aria-label="Close" onClick={onClose}>
                        ×
                    </button>
                </div>

                <form className="project-task-form" onSubmit={onSubmit}>
                    <label>
                        Schedule (Cron expression)
                        <input
                            value={form.schedule}
                            onChange={(e) => onFormChange("schedule", e.target.value)}
                            placeholder="*/5 * * * *"
                            autoFocus
                        />
                    </label>

                    <label>
                        Command
                        <input
                            value={form.command}
                            onChange={(e) => onFormChange("command", e.target.value)}
                            placeholder="ping"
                        />
                    </label>

                    <label>
                        Channel ID
                        <div className="tg-select-wrap">
                            <select
                                value={form.channelId}
                                onChange={(e) => onFormChange("channelId", e.target.value)}
                                disabled={isLoadingChannels || !hasAvailableChannels}
                            >
                                <option value="">
                                    {isLoadingChannels ? "Loading channels..." : "Select a channel"}
                                </option>
                                {availableChannels.map((channel) => (
                                    <option key={channel.channelId} value={channel.channelId}>
                                        {channel.label}
                                    </option>
                                ))}
                            </select>
                            <span className="material-symbols-rounded tg-select-chevron">expand_more</span>
                        </div>
                        {isLoadingChannels ? (
                            <span className="agent-field-note">Loading agent channels...</span>
                        ) : hasAvailableChannels ? (
                            <span className="agent-field-note">
                                {selectedChannel
                                    ? `Selected channel ID: ${selectedChannel.channelId}`
                                    : "Choose one of the linked channels available to this agent."}
                            </span>
                        ) : (
                            <span className="agent-field-note">
                                No linked channels found for this agent. Add one in the Channels tab first.
                            </span>
                        )}
                    </label>

                    <label className="cron-form-toggle">
                        <span>Enabled</span>
                        <span className="agent-tools-switch">
                            <input
                                type="checkbox"
                                checked={form.enabled}
                                onChange={(e) => onFormChange("enabled", e.target.checked)}
                            />
                            <span className="agent-tools-switch-track" />
                        </span>
                    </label>

                    <div className="project-modal-actions">
                        <button type="button" onClick={onClose}>
                            Cancel
                        </button>
                        <button
                            type="submit"
                            className="project-primary hover-levitate"
                            disabled={!form.schedule.trim() || !form.command.trim() || !form.channelId.trim()}
                        >
                            {editingId ? "Save Changes" : "Create Job"}
                        </button>
                    </div>
                </form>
            </section>
        </div>
    );
}

function emptyForm() {
    return { schedule: "*/5 * * * *", command: "", channelId: "", enabled: true };
}

function normalizeChannels(board, agentId) {
    const nodes = Array.isArray(board?.nodes) ? board.nodes : [];
    const byId = new Map();

    for (const node of nodes) {
        if (String(node?.linkedAgentId || "") !== agentId) {
            continue;
        }

        const channelId = String(node?.channelId || "").trim();
        if (!channelId) {
            continue;
        }

        const displayName = String(node?.displayName || "").trim();
        byId.set(channelId, {
            channelId,
            label: displayName || channelId
        });
    }

    return Array.from(byId.values()).sort((left, right) => {
        const labelCompare = left.label.localeCompare(right.label, undefined, { sensitivity: "base" });
        if (labelCompare !== 0) {
            return labelCompare;
        }
        return left.channelId.localeCompare(right.channelId, undefined, { sensitivity: "base" });
    });
}

export function AgentCronTab({ agentId }) {
    const [tasks, setTasks] = useState([]);
    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState("");
    const [availableChannels, setAvailableChannels] = useState([]);
    const [isLoadingChannels, setIsLoadingChannels] = useState(true);

    const [isModalOpen, setIsModalOpen] = useState(false);
    const [editingId, setEditingId] = useState<string | null>(null);
    const [form, setForm] = useState(emptyForm());

    useEffect(() => {
        loadData();
    }, [agentId]);

    useEffect(() => {
        if (!isModalOpen || editingId || form.channelId.trim() || availableChannels.length === 0) {
            return;
        }

        setForm((previous) => ({
            ...previous,
            channelId: availableChannels[0].channelId
        }));
    }, [availableChannels, editingId, form.channelId, isModalOpen]);

    const modalChannels = useMemo(() => {
        if (!form.channelId.trim()) {
            return availableChannels;
        }

        const hasSelectedChannel = availableChannels.some((channel) => channel.channelId === form.channelId);
        if (hasSelectedChannel) {
            return availableChannels;
        }

        return [
            ...availableChannels,
            {
                channelId: form.channelId,
                label: `${form.channelId} (unlinked)`
            }
        ];
    }, [availableChannels, form.channelId]);

    async function loadData() {
        setIsLoading(true);
        setIsLoadingChannels(true);
        setError("");

        try {
            const [tasksResult, boardResult] = await Promise.all([
                fetchAgentCronTasks(agentId),
                fetchActorsBoard()
            ]);

            if (!tasksResult) {
                setError("Failed to fetch cron tasks.");
                setTasks([]);
            } else {
                setTasks(tasksResult);
            }

            if (!boardResult) {
                setAvailableChannels([]);
            } else {
                setAvailableChannels(normalizeChannels(boardResult, agentId));
            }
        } catch {
            setError("Failed to fetch cron tasks.");
            setTasks([]);
            setAvailableChannels([]);
        } finally {
            setIsLoading(false);
            setIsLoadingChannels(false);
        }
    }

    function handleOpenCreate() {
        setForm({
            ...emptyForm(),
            channelId: availableChannels[0]?.channelId || ""
        });
        setEditingId(null);
        setIsModalOpen(true);
    }

    function handleEdit(task) {
        setForm({
            schedule: task.schedule,
            command: task.command,
            channelId: task.channelId,
            enabled: task.enabled
        });
        setEditingId(task.id);
        setIsModalOpen(true);
    }

    function handleCloseModal() {
        setIsModalOpen(false);
        setEditingId(null);
    }

    function handleFormChange(field: string, value: string | boolean) {
        setForm((prev) => ({ ...prev, [field]: value }));
    }

    async function handleDelete(taskId) {
        if (!window.confirm("Are you sure you want to delete this cron job?")) return;
        const success = await deleteAgentCronTask(agentId, taskId);
        if (success) {
            loadData();
        } else {
            alert("Failed to delete cron job.");
        }
    }

    async function handleToggle(task) {
        const success = await updateAgentCronTask(agentId, task.id, {
            ...task,
            enabled: !task.enabled
        });
        if (success) {
            loadData();
        } else {
            alert("Failed to toggle cron job.");
        }
    }

    async function handleSubmit(e) {
        e.preventDefault();

        if (editingId) {
            const success = await updateAgentCronTask(agentId, editingId, form);
            if (success) {
                handleCloseModal();
                loadData();
            } else {
                alert("Failed to update cron job.");
            }
        } else {
            const success = await createAgentCronTask(agentId, form);
            if (success) {
                handleCloseModal();
                loadData();
            } else {
                alert("Failed to create cron job.");
            }
        }
    }

    return (
        <>
            <CronFormModal
                isOpen={isModalOpen}
                editingId={editingId}
                form={form}
                availableChannels={modalChannels}
                isLoadingChannels={isLoadingChannels}
                onFormChange={handleFormChange}
                onClose={handleCloseModal}
                onSubmit={handleSubmit}
            />

            <div className="agent-content-card entry-editor-card">
                <div className="agent-content-header">
                    <h3>Cron Jobs</h3>
                    {tasks.length > 0 && (
                        <button type="button" className="text-button" onClick={handleOpenCreate}>
                            + New Job
                        </button>
                    )}
                </div>

                {error ? (
                    <p className="agent-field-note" style={{ color: "var(--critical)" }}>{error}</p>
                ) : null}

                {isLoading ? (
                    <p className="placeholder-text">Loading...</p>
                ) : tasks.length === 0 ? (
                    <div className="cron-empty-stage">
                        <span className="material-symbols-rounded cron-empty-icon">timer</span>
                        <h4 className="cron-empty-title">No cron jobs yet</h4>
                        <p className="cron-empty-desc">
                            Schedule automated tasks that run on a timer and<br />
                            deliver results to messaging channels
                        </p>
                        <button type="button" className="agent-empty-create hover-levitate" onClick={handleOpenCreate}>
                            + New Job
                        </button>
                    </div>
                ) : (
                    <div style={{ display: "flex", flexDirection: "column", gap: "0.5rem" }}>
                        {tasks.map((task) => (
                            <div key={task.id} className="cron-task-row">
                                <div className="cron-task-info">
                                    <code className="cron-task-schedule">{task.schedule}</code>
                                    <span className="cron-task-command">{task.command}</span>
                                    <span className="cron-task-channel">
                                        <span className="material-symbols-rounded" style={{ fontSize: 13 }}>send</span>
                                        {task.channelId}
                                    </span>
                                </div>
                                <div className="cron-task-actions">
                                    <label className="cron-task-toggle">
                                        <span className="agent-tools-switch">
                                            <input
                                                type="checkbox"
                                                checked={task.enabled}
                                                onChange={() => handleToggle(task)}
                                            />
                                            <span className="agent-tools-switch-track" />
                                        </span>
                                        <span>{task.enabled ? "Active" : "Paused"}</span>
                                    </label>
                                    <button
                                        type="button"
                                        className="text-button"
                                        onClick={() => handleEdit(task)}
                                    >
                                        Edit
                                    </button>
                                    <button
                                        type="button"
                                        className="text-button"
                                        style={{ color: "var(--critical)" }}
                                        onClick={() => handleDelete(task.id)}
                                    >
                                        Delete
                                    </button>
                                </div>
                            </div>
                        ))}
                    </div>
                )}
            </div>
        </>
    );
}
