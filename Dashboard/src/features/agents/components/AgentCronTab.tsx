import React, { useEffect, useState } from "react";
import {
    fetchAgentCronTasks,
    createAgentCronTask,
    updateAgentCronTask,
    deleteAgentCronTask
} from "../../../api";

export function AgentCronTab({ agentId }) {
    const [tasks, setTasks] = useState([]);
    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState("");

    const [isFormOpen, setIsFormOpen] = useState(false);
    const [editingId, setEditingId] = useState(null);

    const [form, setForm] = useState({
        schedule: "",
        command: "",
        channelId: "",
        enabled: true
    });

    useEffect(() => {
        loadTasks();
    }, [agentId]);

    async function loadTasks() {
        setIsLoading(true);
        setError("");
        const result = await fetchAgentCronTasks(agentId);
        if (!result) {
            setError("Failed to fetch cron tasks.");
            setTasks([]);
        } else {
            setTasks(result);
        }
        setIsLoading(false);
    }

    function handleOpenCreate() {
        setForm({ schedule: "*/5 * * * *", command: "", channelId: "", enabled: true });
        setEditingId(null);
        setIsFormOpen(true);
    }

    function handleEdit(task) {
        setForm({
            schedule: task.schedule,
            command: task.command,
            channelId: task.channelId,
            enabled: task.enabled
        });
        setEditingId(task.id);
        setIsFormOpen(true);
    }

    async function handleDelete(taskId) {
        if (!window.confirm("Are you sure you want to delete this cron task?")) return;
        const success = await deleteAgentCronTask(agentId, taskId);
        if (success) {
            loadTasks();
        } else {
            alert("Failed to delete cron task.");
        }
    }

    async function handleToggle(task) {
        const success = await updateAgentCronTask(agentId, task.id, {
            ...task,
            enabled: !task.enabled
        });
        if (success) {
            loadTasks();
        } else {
            alert("Failed to toggle cron task.");
        }
    }

    async function handleSubmit(e) {
        e.preventDefault();
        if (!form.schedule || !form.command || !form.channelId) {
            alert("Schedule, Command, and Channel ID are required.");
            return;
        }

        if (editingId) {
            const success = await updateAgentCronTask(agentId, editingId, form);
            if (success) {
                setIsFormOpen(false);
                loadTasks();
            } else {
                alert("Failed to update task.");
            }
        } else {
            const success = await createAgentCronTask(agentId, form);
            if (success) {
                setIsFormOpen(false);
                loadTasks();
            } else {
                alert("Failed to create task.");
            }
        }
    }

    return (
        <div className="agent-content-card entry-editor-card">
            <div className="flex-center gap-2" style={{ justifyContent: "space-between", marginBottom: "1rem" }}>
                <h3>Cron Tasks</h3>
                <button type="button" className="text-button" onClick={handleOpenCreate}>
                    + Create Task
                </button>
            </div>

            {error ? <p className="agent-field-note" style={{ color: "red" }}>{error}</p> : null}

            {isFormOpen && (
                <form onSubmit={handleSubmit} style={{ marginBottom: "2rem", padding: "1rem", border: "1px solid var(--border-light)", borderRadius: "8px" }}>
                    <h4>{editingId ? "Edit Cron Task" : "New Cron Task"}</h4>
                    <div style={{ display: "flex", flexDirection: "column", gap: "1rem", marginTop: "1rem" }}>
                        <label>
                            Schedule (Cron expression)
                            <input
                                value={form.schedule}
                                onChange={e => setForm({ ...form, schedule: e.target.value })}
                                placeholder="*/5 * * * *"
                            />
                        </label>
                        <label>
                            Command
                            <input
                                value={form.command}
                                onChange={e => setForm({ ...form, command: e.target.value })}
                                placeholder="ping"
                            />
                        </label>
                        <label>
                            Channel ID
                            <input
                                value={form.channelId}
                                onChange={e => setForm({ ...form, channelId: e.target.value })}
                                placeholder="ch_123"
                            />
                        </label>
                        <label style={{ flexDirection: "row", alignItems: "center", gap: "0.5rem" }}>
                            <input
                                type="checkbox"
                                checked={form.enabled}
                                onChange={e => setForm({ ...form, enabled: e.target.checked })}
                            />
                            Enabled
                        </label>
                        <div style={{ display: "flex", gap: "1rem" }}>
                            <button type="submit">{editingId ? "Save" : "Create"}</button>
                            <button type="button" className="text-button" onClick={() => setIsFormOpen(false)}>Cancel</button>
                        </div>
                    </div>
                </form>
            )}

            {isLoading ? (
                <p className="placeholder-text">Loading...</p>
            ) : tasks.length === 0 ? (
                <p className="placeholder-text">No cron tasks found.</p>
            ) : (
                <div style={{ display: "flex", flexDirection: "column", gap: "1rem" }}>
                    {tasks.map(task => (
                        <div key={task.id} style={{ padding: "1rem", border: "1px solid var(--border-light)", borderRadius: "8px", display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                            <div>
                                <strong>{task.schedule}</strong> - <code>{task.command}</code>
                                <div style={{ fontSize: "0.85rem", color: "var(--text-muted)", marginTop: "4px" }}>
                                    Channel: {task.channelId}
                                </div>
                            </div>
                            <div style={{ display: "flex", gap: "1rem", alignItems: "center" }}>
                                <label style={{ display: "flex", alignItems: "center", gap: "4px", margin: 0 }}>
                                    <input type="checkbox" checked={task.enabled} onChange={() => handleToggle(task)} />
                                    {task.enabled ? "Active" : "Disabled"}
                                </label>
                                <button type="button" className="text-button" onClick={() => handleEdit(task)}>Edit</button>
                                <button type="button" className="text-button" style={{ color: "var(--critical)" }} onClick={() => handleDelete(task.id)}>Delete</button>
                            </div>
                        </div>
                    ))}
                </div>
            )}
        </div>
    );
}
