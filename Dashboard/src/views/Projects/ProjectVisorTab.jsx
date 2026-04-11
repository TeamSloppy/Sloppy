import React from "react";

function formatDecisionPreview(entry) {
    const action = String(entry.decision.action || "unknown");
    const reason = String(entry.decision.reason || "unknown");
    const conf =
        typeof entry.decision.confidence === "number"
            ? entry.decision.confidence.toFixed(2)
            : String(entry.decision.confidence || "n/a");
    return `Action: ${action}\nReason: ${reason}\nConfidence: ${conf}`;
}

export function ProjectVisorTab({ project, chatSnapshots, bulletins }) {
    const [previewOpen, setPreviewOpen] = React.useState(null);

    React.useEffect(() => {
        if (!previewOpen) {
            return undefined;
        }
        function onKeyDown(event) {
            if (event.key === "Escape") {
                setPreviewOpen(null);
            }
        }
        window.addEventListener("keydown", onKeyDown);
        return () => window.removeEventListener("keydown", onKeyDown);
    }, [previewOpen]);

    const decisions = project.chats
        .map((chat) => ({
            chat,
            decision: chatSnapshots[chat.channelId]?.lastDecision || null
        }))
        .filter((entry) => entry.decision);

    return (
        <>
            <section className="project-tab-layout">
                <section className="project-pane">
                    <h4>Visor</h4>

                    {decisions.length === 0 ? (
                        <p className="placeholder-text">No channel decisions available yet.</p>
                    ) : (
                        <div className="project-visor-card-grid">
                            {decisions.map((entry) => {
                                const body = formatDecisionPreview(entry);
                                return (
                                    <article key={entry.chat.id} className="project-visor-card">
                                        <div className="project-visor-card-head">
                                            <strong>{entry.chat.title}</strong>
                                        </div>
                                        <div className="project-visor-card-preview">
                                            <p>{body}</p>
                                        </div>
                                        <button
                                            type="button"
                                            className="project-visor-card-read"
                                            onClick={() =>
                                                setPreviewOpen({
                                                    title: entry.chat.title,
                                                    body
                                                })
                                            }
                                        >
                                            Read full
                                        </button>
                                    </article>
                                );
                            })}
                        </div>
                    )}
                </section>

                <section className="project-pane">
                    <h4>Bulletins</h4>
                    {Array.isArray(bulletins) && bulletins.length > 0 ? (
                        <div className="project-visor-card-grid">
                            {bulletins.slice(0, 8).map((bulletin, index) => {
                                const headline = String(bulletin?.headline || "Runtime bulletin");
                                const digest = String(bulletin?.digest || "");
                                return (
                                    <article
                                        key={String(bulletin?.id || `bulletin-${index}`)}
                                        className="project-visor-card"
                                    >
                                        <div className="project-visor-card-head">
                                            <strong>{headline}</strong>
                                        </div>
                                        <div className="project-visor-card-preview">
                                            <p>{digest}</p>
                                        </div>
                                        <button
                                            type="button"
                                            className="project-visor-card-read"
                                            onClick={() =>
                                                setPreviewOpen({
                                                    title: headline,
                                                    body: digest
                                                })
                                            }
                                        >
                                            Read full
                                        </button>
                                    </article>
                                );
                            })}
                        </div>
                    ) : (
                        <p className="placeholder-text">No bulletins available.</p>
                    )}
                </section>
            </section>

            {previewOpen ? (
                <div
                    className="project-visor-preview-modal-backdrop"
                    role="presentation"
                    onClick={() => setPreviewOpen(null)}
                >
                    <div
                        className="project-visor-preview-modal"
                        role="dialog"
                        aria-modal="true"
                        aria-labelledby="project-visor-preview-modal-title"
                        onClick={(event) => event.stopPropagation()}
                    >
                        <div className="project-visor-preview-modal-head">
                            <h4 id="project-visor-preview-modal-title">{previewOpen.title}</h4>
                            <button
                                type="button"
                                className="project-visor-preview-modal-close"
                                onClick={() => setPreviewOpen(null)}
                                aria-label="Close"
                            >
                                <span className="material-symbols-rounded" aria-hidden="true">
                                    close
                                </span>
                            </button>
                        </div>
                        <pre className="project-visor-preview-modal-body">{previewOpen.body}</pre>
                    </div>
                </div>
            ) : null}
        </>
    );
}
