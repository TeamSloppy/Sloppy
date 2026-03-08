import React from "react";
import { workersForProject } from "./utils";

export function ProjectWorkersTab({ project, workers }) {
    const projectWorkers = workersForProject(project, workers);

    if (projectWorkers.length === 0) {
        return (
            <div className="project-tab-placeholder">
                <h3>Workers</h3>
                <p>No workers are linked to this project yet.</p>
            </div>
        );
    }

    return (
        <section className="project-tab-layout">
            <section className="project-pane">
                <h4>Workers</h4>
                <div className="project-workers-list">
                    {projectWorkers.map((worker, index) => (
                        <article key={String(worker?.workerId || `worker-${index}`)} className="project-worker-item">
                            <strong>{String(worker?.workerId || "worker")}</strong>
                            <p>Task: {String(worker?.taskId || "unknown")}</p>
                            <p>Status: {String(worker?.status || "unknown")}</p>
                            <p>Mode: {String(worker?.mode || "unknown")}</p>
                            {Array.isArray(worker?.tools) ? <p>Tools: {worker.tools.join(", ") || "none"}</p> : null}
                            {worker?.latestReport ? <p>Report: {String(worker.latestReport)}</p> : null}
                        </article>
                    ))}
                </div>
            </section>
        </section>
    );
}
