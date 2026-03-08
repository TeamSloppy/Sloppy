import React, { useEffect, useState } from "react";
import { fetchAgentTasks } from "../../../api";

export function AgentTasksTab({ agentId }) {
    const [items, setItems] = useState([]);
    const [statusText, setStatusText] = useState("Loading tasks...");

    useEffect(() => {
        let cancelled = false;

        async function loadTasks() {
            const response = await fetchAgentTasks(agentId);
            if (cancelled) {
                return;
            }

            if (!Array.isArray(response)) {
                setItems([]);
                setStatusText("Failed to load tasks for this agent.");
                return;
            }

            setItems(response);
            setStatusText(response.length === 0 ? "No tasks claimed by this agent." : `Loaded ${response.length} task(s).`);
        }

        loadTasks().catch(() => {
            if (!cancelled) {
                setItems([]);
                setStatusText("Failed to load tasks for this agent.");
            }
        });

        return () => {
            cancelled = true;
        };
    }, [agentId]);

    return (
        <section className="entry-editor-card agent-content-card">
            <h3>Tasks</h3>
            {items.length === 0 ? (
                <p className="app-status-text">{statusText}</p>
            ) : (
                <div className="project-workers-list">
                    {items.map((item, index) => {
                        const projectId = String(item?.projectId || "");
                        const projectName = String(item?.projectName || projectId || "Project");
                        const task = item?.task || {};
                        return (
                            <article key={String(task.id || `${projectId}-${index}`)} className="project-worker-item">
                                <strong>{String(task.title || "Task")}</strong>
                                <p>Project: {projectName}</p>
                                <p>Status: {String(task.status || "unknown")}</p>
                                {task?.claimedAgentId ? <p>Taken by: {String(task.claimedAgentId)}</p> : null}
                                {task?.description ? <p>{String(task.description)}</p> : null}
                            </article>
                        );
                    })}
                </div>
            )}
            {items.length > 0 ? <p className="placeholder-text">{statusText}</p> : null}
        </section>
    );
}
