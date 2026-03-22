import React from "react";
import { workersForProject, activeWorkersForProject, buildTaskCounts, formatRelativeTime } from "./utils";

export function ProjectList({ projects, isLoadingProjects, openProject, openCreateProjectModal, workers }) {
    if (isLoadingProjects) {
        return (
            <section className="project-board-list">
                <article className="project-board-card">
                    <p className="app-status-text">Loading projects from Sloppy...</p>
                </article>
            </section>
        );
    }

    if (projects.length === 0) {
        return (
            <section className="project-board-list project-board-list--empty">
                <article className="project-board-empty">
                    <div className="project-board-empty-actions">
                        <p className="project-new-action-subtitle">
                            Start your first project!
                        </p>
                        <button type="button" className="project-new-action hover-levitate" onClick={openCreateProjectModal}>
                            New Projects
                        </button>
                    </div>
                </article>
            </section>
        );
    }

    return (
        <section className="project-board-list" data-testid="project-list">
            {projects.map((project) => {
                const relatedWorkers = workersForProject(project, workers);
                const activeWorkers = activeWorkersForProject(project, workers);
                const taskCounts = buildTaskCounts(project.tasks);

                return (
                    <article
                        key={project.id}
                        className="project-board-card project-board-card--clickable"
                        data-testid={`project-list-item-${project.id}`}
                        role="button"
                        tabIndex={0}
                        onClick={() => openProject(project.id)}
                        onKeyDown={(event) => {
                            if (event.key === "Enter" || event.key === " ") {
                                event.preventDefault();
                                openProject(project.id);
                            }
                        }}
                    >
                        <div className="project-board-card-head">
                            <h3>{project.name}</h3>
                            <span className="project-board-updated">{formatRelativeTime(project.updatedAt)}</span>
                        </div>

                        <p className="project-board-description placeholder-text">
                            {project.description || "No description"}
                        </p>

                        <div className="project-board-stats">
                            <span className="project-badge project-badge--tasks">{taskCounts.total} tasks</span>
                            <span className="project-badge project-badge--progress">{taskCounts.in_progress} in progress</span>
                            <span className="project-badge project-badge--active">{activeWorkers.length} active workers</span>
                            <span className="project-badge project-badge--workers">{relatedWorkers.length} workers total</span>
                        </div>
                    </article>
                );
            })}
        </section>
    );
}
