import React from "react";

export function ProjectSettingsTab({
    project,
    projectNameDraft,
    setProjectNameDraft,
    saveProjectSettings,
    deleteProject,
    openAddChannelModal,
    removeProjectChannel
}) {
    return (
        <section className="project-tab-layout">
            <section className="project-pane">
                <h4>Project Settings</h4>

                <form
                    className="project-settings-form"
                    onSubmit={(event) => {
                        event.preventDefault();
                        saveProjectSettings();
                    }}
                >
                    <label>
                        Project name
                        <input value={projectNameDraft} onChange={(event) => setProjectNameDraft(event.target.value)} />
                    </label>

                    <div className="project-settings-actions">
                        <button type="submit" className="project-primary hover-levitate">
                            Save Name
                        </button>
                        <button type="button" className="danger" onClick={() => deleteProject(project.id)}>
                            Delete Project
                        </button>
                    </div>
                </form>
            </section>

            <section className="project-pane">
                <div className="project-pane-head">
                    <h4>Channels</h4>
                    <button type="button" onClick={openAddChannelModal}>
                        Add Channel
                    </button>
                </div>

                <div className="project-created-list">
                    {project.chats.map((chat) => (
                        <article key={chat.id} className="project-created-item">
                            <strong>{chat.title}</strong>
                            <p>{chat.channelId}</p>
                            <div className="project-settings-actions">
                                <button
                                    type="button"
                                    className="danger"
                                    disabled={project.chats.length <= 1}
                                    onClick={() => removeProjectChannel(chat.id)}
                                >
                                    Remove
                                </button>
                            </div>
                        </article>
                    ))}
                </div>
            </section>
        </section>
    );
}
