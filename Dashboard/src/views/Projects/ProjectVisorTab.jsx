import React from "react";

export function ProjectVisorTab({ project, chatSnapshots, bulletins }) {
    const decisions = project.chats
        .map((chat) => ({
            chat,
            decision: chatSnapshots[chat.channelId]?.lastDecision || null
        }))
        .filter((entry) => entry.decision);

    return (
        <section className="project-tab-layout">
            <section className="project-pane">
                <h4>Visor</h4>

                {decisions.length === 0 ? (
                    <p className="placeholder-text">No channel decisions available yet.</p>
                ) : (
                    <div className="project-created-list">
                        {decisions.map((entry) => (
                            <article key={entry.chat.id} className="project-created-item">
                                <strong>{entry.chat.title}</strong>
                                <p>Action: {String(entry.decision.action || "unknown")}</p>
                                <p>Reason: {String(entry.decision.reason || "unknown")}</p>
                                <p>
                                    Confidence:{" "}
                                    {typeof entry.decision.confidence === "number"
                                        ? entry.decision.confidence.toFixed(2)
                                        : String(entry.decision.confidence || "n/a")}
                                </p>
                            </article>
                        ))}
                    </div>
                )}
            </section>

            <section className="project-pane">
                <h4>Bulletins</h4>
                {Array.isArray(bulletins) && bulletins.length > 0 ? (
                    <div className="project-created-list">
                        {bulletins.slice(0, 8).map((bulletin, index) => (
                            <article key={String(bulletin?.id || `bulletin-${index}`)} className="project-created-item">
                                <strong>{String(bulletin?.headline || "Runtime bulletin")}</strong>
                                <p>{String(bulletin?.digest || "")}</p>
                            </article>
                        ))}
                    </div>
                ) : (
                    <p className="placeholder-text">No bulletins available.</p>
                )}
            </section>
        </section>
    );
}
