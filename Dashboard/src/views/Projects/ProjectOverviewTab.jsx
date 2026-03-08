import React from "react";

export function ProjectOverviewTab({ project, taskCounts, activeWorkers, relatedWorkers, createdItems }) {
    return (
        <section className="project-tab-layout">
            <section className="project-overview-metrics">
                <article className="project-metric-card">
                    <p>Total tasks</p>
                    <strong>{taskCounts.total}</strong>
                </article>
                <article className="project-metric-card">
                    <p>In progress</p>
                    <strong>{taskCounts.in_progress}</strong>
                </article>
                <article className="project-metric-card">
                    <p>Active agents</p>
                    <strong>{activeWorkers.length}</strong>
                </article>
                <article className="project-metric-card">
                    <p>Channels</p>
                    <strong>{project.chats?.length || 0}</strong>
                </article>
            </section>

            <section className="project-pane">
                <div className="project-pane-head">
                    <h4>Working Agents</h4>
                </div>

                {activeWorkers.length === 0 ? (
                    <p className="placeholder-text">No active workers for this project right now.</p>
                ) : (
                    <div className="project-workers-list">
                        {activeWorkers.map((worker, index) => (
                            <article key={String(worker?.workerId || `worker-${index}`)} className="project-worker-item">
                                <strong>{String(worker?.workerId || "worker")}</strong>
                                <p>Task: {String(worker?.taskId || "unknown")}</p>
                                <p>Status: {String(worker?.status || "unknown")}</p>
                                <p>Mode: {String(worker?.mode || "unknown")}</p>
                                {worker?.latestReport ? <p>Report: {String(worker.latestReport)}</p> : null}
                            </article>
                        ))}
                    </div>
                )}

                {activeWorkers.length === 0 && relatedWorkers.length > 0 ? (
                    <p className="placeholder-text">Workers exist, but none are currently active.</p>
                ) : null}
            </section>

            <section className="project-pane">
                <div className="project-pane-head">
                    <h4>Created Files / Artifacts</h4>
                </div>

                {createdItems.length === 0 ? (
                    <p className="placeholder-text">No files or artifacts detected in project runtime messages yet.</p>
                ) : (
                    <div className="project-created-list">
                        {createdItems.map((item) => (
                            <article key={item.key} className="project-created-item">
                                <strong>{item.type === "artifact" ? "Artifact" : "File"}</strong>
                                <p>{item.value}</p>
                                <p className="placeholder-text">Channel: {item.channelId}</p>
                            </article>
                        ))}
                    </div>
                )}
            </section>
        </section>
    );
}
