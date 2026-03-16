import React, { useState, useMemo, useEffect, useRef } from "react";

const SETTINGS_TABS = [
    { id: "general", title: "General", icon: "settings" },
    { id: "actors", title: "Actors", icon: "group" },
    { id: "review", title: "Git Worktree & Review", icon: "rate_review" }
];

const APPROVAL_MODES = [
    {
        id: "human",
        label: "Human Approve",
        icon: "person_check",
        description: "Notify the dashboard and task creator. Requires manual approval."
    },
    {
        id: "auto",
        label: "Auto Approve",
        icon: "check_circle",
        description: "Automatically merge and mark as done when the task reaches review."
    },
    {
        id: "agent",
        label: "Agent Approve",
        icon: "smart_toy",
        description: "Delegate review to the actor with the Reviewer system role in the team."
    }
];

const PROJECT_ICONS = [
    "folder", "rocket_launch", "code", "terminal", "science",
    "deployed_code", "bug_report", "psychology", "smart_toy", "extension",
    "database", "cloud", "language", "brush", "analytics",
    "school", "build", "architecture", "api", "hub",
    "storage", "monitoring", "security", "memory", "web"
];

function cloneDraft(project) {
    return {
        name: project?.name ?? "",
        icon: project?.icon ?? "",
        models: Array.isArray(project?.models) ? [...project.models] : [],
        agentFiles: Array.isArray(project?.agentFiles) ? [...project.agentFiles] : [],
        heartbeat: {
            enabled: Boolean(project?.heartbeat?.enabled),
            intervalMinutes: Number.isFinite(Number(project?.heartbeat?.intervalMinutes))
                ? Number(project.heartbeat.intervalMinutes)
                : 5
        },
        repoPath: project?.repoPath ?? "",
        reviewSettings: {
            enabled: Boolean(project?.reviewSettings?.enabled),
            approvalMode: project?.reviewSettings?.approvalMode ?? "human"
        },
        actors: Array.isArray(project?.actors) ? [...project.actors] : [],
        teams: Array.isArray(project?.teams) ? [...project.teams] : []
    };
}

export function ProjectSettingsTab({
    project,
    onUpdateProject,
    deleteProject,
    openAddChannelModal,
    removeProjectChannel,
    availableActors = [],
    availableTeams = []
}) {
    const [selectedSettings, setSelectedSettings] = useState("general");
    const [draft, setDraft] = useState(() => cloneDraft(project));
    const [statusText, setStatusText] = useState("");
    const [deleteConfirmOpen, setDeleteConfirmOpen] = useState(false);
    const [deleteConfirmText, setDeleteConfirmText] = useState("");
    const [actorSearch, setActorSearch] = useState("");
    const [actorDropdownOpen, setActorDropdownOpen] = useState(false);
    const actorSearchRef = useRef(null);

    useEffect(() => {
        setDraft(cloneDraft(project));
    }, [project?.id, project?.updatedAt]);

    const hasChanges = useMemo(() => {
        const saved = cloneDraft(project);
        return JSON.stringify(draft) !== JSON.stringify(saved);
    }, [draft, project]);

    function mutateDraft(mutator) {
        setDraft((prev) => {
            const next = JSON.parse(JSON.stringify(prev));
            mutator(next);
            return next;
        });
    }

    async function saveSettings() {
        const result = await onUpdateProject({
            name: draft.name.trim() || undefined,
            icon: draft.icon.trim() || null,
            models: draft.models,
            agentFiles: draft.agentFiles,
            heartbeat: draft.heartbeat,
            repoPath: draft.repoPath.trim() || null,
            reviewSettings: draft.reviewSettings,
            actors: draft.actors,
            teams: draft.teams
        });
        if (result) {
            setStatusText("Settings saved");
        } else {
            setStatusText("Failed to save settings");
        }
    }

    function cancelChanges() {
        setDraft(cloneDraft(project));
        setStatusText("Changes cancelled");
    }

    function renderGeneral() {
        return (
            <>
                <section className="entry-editor-card">
                    <h3>Project Identity</h3>
                    <div className="entry-form-grid">
                        <label style={{ gridColumn: "1 / -1" }}>
                            Project Name
                            <input
                                type="text"
                                value={draft.name}
                                onChange={(e) => mutateDraft((d) => { d.name = e.target.value; })}
                                placeholder="My Project"
                            />
                        </label>
                    </div>

                    <div style={{ marginTop: 16 }}>
                        <p className="settings-general-label">Project Icon</p>
                        <div className="settings-icon-grid">
                            {PROJECT_ICONS.map((iconName) => {
                                const active = draft.icon === iconName;
                                return (
                                    <button
                                        key={iconName}
                                        type="button"
                                        className={`settings-icon-option ${active ? "active" : ""}`}
                                        onClick={() => mutateDraft((d) => { d.icon = active ? "" : iconName; })}
                                        title={iconName}
                                    >
                                        <span className="material-symbols-rounded">{iconName}</span>
                                    </button>
                                );
                            })}
                        </div>
                        {draft.icon && (
                            <div className="settings-icon-preview">
                                <span className="material-symbols-rounded" style={{ fontSize: "2rem" }}>{draft.icon}</span>
                                <span>{draft.icon}</span>
                            </div>
                        )}
                    </div>
                </section>

                <section className="entry-editor-card settings-danger-zone">
                    <h3 style={{ color: "var(--danger, #ef4444)" }}>Danger Zone</h3>
                    <div className="settings-danger-block">
                        <div className="settings-danger-info">
                            <strong>Delete this project</strong>
                            <p>
                                Once you delete a project, there is no going back. All tasks will be cancelled and all project data will be permanently removed.
                            </p>
                        </div>
                        {!deleteConfirmOpen ? (
                            <button
                                type="button"
                                className="danger hover-levitate"
                                onClick={() => {
                                    setDeleteConfirmOpen(true);
                                    setDeleteConfirmText("");
                                }}
                            >
                                Delete Project
                            </button>
                        ) : (
                            <div className="settings-danger-confirm">
                                <p className="settings-danger-warning">
                                    <span className="material-symbols-rounded" style={{ fontSize: "1rem", verticalAlign: "middle" }}>warning</span>
                                    {" "}This action is irreversible. All jobs for this project will be cancelled.
                                </p>
                                <label>
                                    Type <strong>{project.name}</strong> to confirm
                                    <input
                                        type="text"
                                        value={deleteConfirmText}
                                        onChange={(e) => setDeleteConfirmText(e.target.value)}
                                        placeholder={project.name}
                                        autoFocus
                                    />
                                </label>
                                <div className="settings-danger-confirm-actions">
                                    <button
                                        type="button"
                                        onClick={() => {
                                            setDeleteConfirmOpen(false);
                                            setDeleteConfirmText("");
                                        }}
                                    >
                                        Cancel
                                    </button>
                                    <button
                                        type="button"
                                        className="danger hover-levitate"
                                        disabled={deleteConfirmText.trim() !== project.name}
                                        onClick={() => deleteProject(project.id)}
                                    >
                                        I understand, delete this project
                                    </button>
                                </div>
                            </div>
                        )}
                    </div>
                </section>
            </>
        );
    }

    function renderActors() {
        const projectActors = draft.actors;
        const projectTeams = draft.teams;

        const q = actorSearch.trim().toLowerCase();
        const filteredActors = availableActors.filter(
            (node) =>
                node.displayName.toLowerCase().includes(q) || node.id.toLowerCase().includes(q)
        );
        const listToShow = q && filteredActors.length > 0 ? filteredActors : availableActors;

        function addActor(node) {
            mutateDraft((d) => {
                if (!d.actors.includes(node.displayName)) {
                    d.actors.push(node.displayName);
                }
            });
            setActorSearch("");
        }

        function removeActor(actorName) {
            mutateDraft((d) => {
                d.actors = d.actors.filter((a) => a !== actorName);
            });
        }

        function removeTeam(teamName) {
            mutateDraft((d) => {
                d.teams = d.teams.filter((t) => t !== teamName);
            });
        }

        return (
            <section className="entry-editor-card">
                <h3>Actors</h3>
                <p style={{ margin: "0 0 12px", fontSize: "0.85rem", color: "var(--muted)" }}>
                    Choose which actors can interact with this project. Actors will be able to receive tasks and work within this project scope.
                </p>

                <div className="actor-team-members-picker">
                    <div className="actor-team-search-wrap">
                        <input
                            ref={actorSearchRef}
                            className="actor-team-search"
                            value={actorSearch}
                            onChange={(e) => {
                                setActorSearch(e.target.value);
                                setActorDropdownOpen(true);
                            }}
                            onFocus={() => setActorDropdownOpen(true)}
                            onBlur={() => setTimeout(() => setActorDropdownOpen(false), 150)}
                            placeholder="Search actors…"
                            autoComplete="off"
                        />
                        {actorDropdownOpen && (
                            <ul className="actor-team-dropdown">
                                {listToShow.length === 0 ? (
                                    <li className="actor-team-dropdown-empty">No actors available</li>
                                ) : (
                                    listToShow.map((node) => {
                                        const isSelected = projectActors.includes(node.displayName);
                                        return (
                                            <li
                                                key={node.id}
                                                className={`actor-team-dropdown-item ${isSelected ? "selected" : ""}`}
                                                onMouseDown={(e) => {
                                                    e.preventDefault();
                                                    if (isSelected) {
                                                        removeActor(node.displayName);
                                                    } else {
                                                        addActor(node);
                                                    }
                                                }}
                                            >
                                                <span className="actor-team-dropdown-name">{node.displayName}</span>
                                                <span className="actor-team-dropdown-id">{node.id}</span>
                                                {isSelected && (
                                                    <span className="actor-team-dropdown-check">✓</span>
                                                )}
                                            </li>
                                        );
                                    })
                                )}
                            </ul>
                        )}
                    </div>
                </div>

                {projectActors.length > 0 && (
                    <div className="project-created-list" style={{ marginTop: 16 }}>
                        {projectActors.map((actorName) => (
                            <article key={actorName} className="project-created-item" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                                <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                                    <span className="material-symbols-rounded" style={{ fontSize: "1.1rem", color: "var(--accent)" }}>person</span>
                                    <strong>{actorName}</strong>
                                </div>
                                <button
                                    type="button"
                                    className="agent-channel-remove"
                                    style={{ color: "var(--warn)", border: "none", background: "transparent", cursor: "pointer", padding: "4px" }}
                                    onClick={() => removeActor(actorName)}
                                >
                                    <span className="material-symbols-rounded">close</span>
                                </button>
                            </article>
                        ))}
                    </div>
                )}

                {projectTeams.length > 0 && (
                    <>
                        <h3 style={{ marginTop: 24 }}>Teams</h3>
                        <div className="project-created-list" style={{ marginTop: 8 }}>
                            {projectTeams.map((teamName) => (
                                <article key={teamName} className="project-created-item" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                                    <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                                        <span className="material-symbols-rounded" style={{ fontSize: "1.1rem", color: "var(--accent)" }}>groups</span>
                                        <strong>{teamName}</strong>
                                    </div>
                                    <button
                                        type="button"
                                        className="agent-channel-remove"
                                        style={{ color: "var(--warn)", border: "none", background: "transparent", cursor: "pointer", padding: "4px" }}
                                        onClick={() => removeTeam(teamName)}
                                    >
                                        <span className="material-symbols-rounded">close</span>
                                    </button>
                                </article>
                            ))}
                        </div>
                    </>
                )}

                {projectActors.length === 0 && projectTeams.length === 0 && (
                    <p className="placeholder-text" style={{ marginTop: 12 }}>No actors or teams assigned to this project.</p>
                )}
            </section>
        );
    }

    function renderModels() {
        return (
            <section className="entry-editor-card">
                <h3>Models</h3>
                <div className="entry-form-grid">
                    <label style={{ gridColumn: "1 / -1" }}>
                        Model identifiers
                        <textarea
                            rows={5}
                            placeholder={"gpt-4.1-mini\nopenai:gpt-4.1\nollama:qwen3"}
                            value={draft.models.join("\n")}
                            onChange={(e) => {
                                mutateDraft((d) => {
                                    d.models = e.target.value
                                        .split("\n")
                                        .map((s) => s.trim())
                                        .filter(Boolean);
                                });
                            }}
                        />
                        <span className="entry-form-hint">
                            One model per line. These models will be available for agents in this project.
                        </span>
                    </label>
                </div>

                {draft.models.length > 0 && (
                    <div className="project-created-list" style={{ marginTop: 16 }}>
                        {draft.models.map((model, idx) => (
                            <article key={idx} className="project-created-item" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                                <div>
                                    <strong>{model}</strong>
                                </div>
                                <button
                                    type="button"
                                    className="agent-channel-remove"
                                    style={{ color: "var(--warn)", border: "none", background: "transparent", cursor: "pointer", padding: "4px" }}
                                    onClick={() => {
                                        mutateDraft((d) => {
                                            d.models.splice(idx, 1);
                                        });
                                    }}
                                >
                                    <span className="material-symbols-rounded">delete</span>
                                </button>
                            </article>
                        ))}
                    </div>
                )}
            </section>
        );
    }

    function renderAgentFiles() {
        return (
            <section className="entry-editor-card">
                <h3>Agent Files</h3>
                <div className="entry-form-grid">
                    <label style={{ gridColumn: "1 / -1" }}>
                        File paths
                        <textarea
                            rows={5}
                            placeholder={"docs/spec.md\nREADME.md\nsrc/prompts/system.txt"}
                            value={draft.agentFiles.join("\n")}
                            onChange={(e) => {
                                mutateDraft((d) => {
                                    d.agentFiles = e.target.value
                                        .split("\n")
                                        .map((s) => s.trim())
                                        .filter(Boolean);
                                });
                            }}
                        />
                        <span className="entry-form-hint">
                            One file path per line. These files will be included as context for agents working on this project.
                        </span>
                    </label>
                </div>

                {draft.agentFiles.length > 0 && (
                    <div className="project-created-list" style={{ marginTop: 16 }}>
                        {draft.agentFiles.map((file, idx) => (
                            <article key={idx} className="project-created-item" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                                <div>
                                    <strong>{file}</strong>
                                </div>
                                <button
                                    type="button"
                                    className="agent-channel-remove"
                                    style={{ color: "var(--warn)", border: "none", background: "transparent", cursor: "pointer", padding: "4px" }}
                                    onClick={() => {
                                        mutateDraft((d) => {
                                            d.agentFiles.splice(idx, 1);
                                        });
                                    }}
                                >
                                    <span className="material-symbols-rounded">delete</span>
                                </button>
                            </article>
                        ))}
                    </div>
                )}
            </section>
        );
    }

    function renderChannels() {
        return (
            <section className="entry-editor-card">
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                    <h3>Channels</h3>
                    <button type="button" className="hover-levitate" onClick={openAddChannelModal}>
                        Add Channel
                    </button>
                </div>

                {project.chats.length > 0 ? (
                    <div className="project-created-list" style={{ marginTop: 16 }}>
                        {project.chats.map((chat) => (
                            <article key={chat.id} className="project-created-item" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                                <div>
                                    <strong>{chat.title}</strong>
                                    <p style={{ margin: 0, fontSize: "0.85rem", color: "var(--muted)" }}>{chat.channelId}</p>
                                </div>
                                <button
                                    type="button"
                                    className="agent-channel-remove"
                                    style={{ color: "var(--warn)", border: "none", background: "transparent", cursor: "pointer", padding: "4px" }}
                                    disabled={project.chats.length <= 1}
                                    onClick={() => removeProjectChannel(chat.id)}
                                >
                                    <span className="material-symbols-rounded">delete</span>
                                </button>
                            </article>
                        ))}
                    </div>
                ) : (
                    <p className="placeholder-text" style={{ marginTop: 12 }}>No channels configured.</p>
                )}
            </section>
        );
    }

    function renderHeartbeat() {
        return (
            <section className="entry-editor-card">
                <h3>Heartbeat</h3>
                <div className="entry-form-grid">
                    <label>
                        Enable Heartbeat
                        <select
                            value={draft.heartbeat.enabled ? "enabled" : "disabled"}
                            onChange={(e) =>
                                mutateDraft((d) => {
                                    d.heartbeat.enabled = e.target.value === "enabled";
                                })
                            }
                        >
                            <option value="disabled">Disabled</option>
                            <option value="enabled">Enabled</option>
                        </select>
                    </label>
                    <label>
                        Interval (minutes)
                        <input
                            type="number"
                            min={1}
                            disabled={!draft.heartbeat.enabled}
                            value={draft.heartbeat.intervalMinutes}
                            onChange={(e) =>
                                mutateDraft((d) => {
                                    const val = parseInt(e.target.value, 10);
                                    d.heartbeat.intervalMinutes = Number.isFinite(val) && val > 0 ? val : 5;
                                })
                            }
                        />
                        <span className="entry-form-hint">
                            How often agents in this project will run heartbeat checks.
                        </span>
                    </label>
                </div>
            </section>
        );
    }

    function renderReview() {
        const isEnabled = draft.reviewSettings.enabled;
        const repoPath = draft.repoPath.trim();
        return (
            <section className="entry-editor-card">
                <h3>Git Worktree &amp; Review</h3>

                <div className="review-toggle-row">
                    <div className="review-toggle-label">
                        <span className="material-symbols-rounded review-toggle-icon">account_tree</span>
                        <div>
                            <strong>Git Worktree Isolation</strong>
                            <p className="review-toggle-desc">
                                Each task runs in a dedicated git branch and worktree. Changes go through review before merging into the main branch.
                            </p>
                        </div>
                    </div>
                    <label className="agent-tools-switch">
                        <input
                            type="checkbox"
                            checked={isEnabled}
                            onChange={(e) => mutateDraft((d) => {
                                d.reviewSettings.enabled = e.target.checked;
                                if (e.target.checked && !d.repoPath.trim()) {
                                    d.repoPath = `/projects/${project.id}`;
                                }
                            })}
                        />
                        <span className="agent-tools-switch-track" />
                    </label>
                </div>

                <div className="entry-form-grid" style={{ marginTop: 16 }}>
                    <label style={{ gridColumn: "1 / -1" }}>
                        Repository path
                        <input
                            type="text"
                            placeholder="e.g. /home/user/my-project"
                            value={draft.repoPath}
                            onChange={(e) => mutateDraft((d) => { d.repoPath = e.target.value; })}
                        />
                        <span className="entry-form-hint">
                            {repoPath
                                ? <>Worktrees will be created at <code>{repoPath}/.sloppy-worktrees/</code></>
                                : "Absolute path to the local git repository. Leave empty to disable worktree isolation."}
                        </span>
                    </label>
                </div>

                <div className="review-section-divider" />
                <div className="review-approval-section">
                    <p className="review-approval-title">Approval mode</p>
                    <p className="review-approval-subtitle">
                        Choose how tasks are approved when they reach the Review stage.
                    </p>
                    <div className="review-approval-options">
                        {APPROVAL_MODES.map((mode) => {
                            const active = draft.reviewSettings.approvalMode === mode.id;
                            return (
                                <button
                                    key={mode.id}
                                    type="button"
                                    className={`review-approval-option ${active ? "active" : ""}`}
                                    onClick={() => mutateDraft((d) => { d.reviewSettings.approvalMode = mode.id; })}
                                >
                                    <span className="material-symbols-rounded review-approval-icon">{mode.icon}</span>
                                    <strong className="review-approval-name">{mode.label}</strong>
                                    <span className="review-approval-desc">{mode.description}</span>
                                    {active && (
                                        <span className="material-symbols-rounded review-approval-check">check_circle</span>
                                    )}
                                </button>
                            );
                        })}
                    </div>
                </div>

                {draft.reviewSettings.approvalMode === "agent" && (
                    <div className="review-agent-hint">
                        <span className="material-symbols-rounded" style={{ fontSize: "1rem", color: "var(--accent)" }}>info</span>
                        <span>
                            Add an actor with the <strong>Reviewer</strong> system role to the team in the Actor Board. The task will be handed off to that actor for review.
                        </span>
                    </div>
                )}
            </section>
        );
    }

    function renderSettingsContent() {
        switch (selectedSettings) {
            case "general":
                return renderGeneral();
            case "actors":
                return renderActors();
            case "models":
                return renderModels();
            case "agent_files":
                return renderAgentFiles();
            case "channels":
                return renderChannels();
            case "heartbeat":
                return renderHeartbeat();
            case "review":
                return renderReview();
            default:
                return null;
        }
    }

    return (
        <section className="settings-shell">
            <aside className="settings-side">
                <div className="settings-title-row">
                    <h2>Project Settings</h2>
                </div>

                <div className="settings-nav">
                    {SETTINGS_TABS.map((item) => (
                        <button
                            key={item.id}
                            type="button"
                            className={`settings-nav-item ${selectedSettings === item.id ? "active" : ""}`}
                            onClick={() => setSelectedSettings(item.id)}
                        >
                            <span className="material-symbols-rounded settings-nav-icon">{item.icon}</span>
                            <span>{item.title}</span>
                        </button>
                    ))}
                </div>
            </aside>

            <section className="settings-main">
                <header className="settings-main-head">
                    <div className="settings-main-status">
                        <span>{statusText}</span>
                    </div>
                </header>

                <div className={`settings-toast ${hasChanges ? "settings-toast--visible" : ""}`}>
                    <span className="settings-toast-label">Unsaved changes</span>
                    <div className="settings-toast-actions">
                        <button type="button" className="danger hover-levitate" onClick={cancelChanges}>
                            Cancel
                        </button>
                        <button type="button" className="hover-levitate" onClick={saveSettings}>
                            Apply
                        </button>
                    </div>
                </div>

                {renderSettingsContent()}
            </section>
        </section>
    );
}
