import React from "react";

export function ProjectMemoriesTab({ project, chatSnapshots }) {
    return (
        <section className="project-tab-layout">
            <section className="project-pane">
                <h4>Memories</h4>

                {project.chats.map((chat) => {
                    const snapshot = chatSnapshots[chat.channelId];
                    const messages = Array.isArray(snapshot?.messages) ? snapshot.messages : [];
                    const recent = messages.slice(-5).reverse();

                    return (
                        <article key={chat.id} className="project-memory-channel">
                            <header>
                                <strong>{chat.title}</strong>
                                <span className="placeholder-text">{chat.channelId}</span>
                            </header>

                            {recent.length === 0 ? (
                                <p className="placeholder-text">No messages in this channel yet.</p>
                            ) : (
                                <div className="project-memory-messages">
                                    {recent.map((message, index) => (
                                        <div key={String(message?.id || `message-${chat.id}-${index}`)} className="project-memory-message">
                                            <strong>{String(message?.userId || "user")}</strong>
                                            <p>{String(message?.content || "")}</p>
                                        </div>
                                    ))}
                                </div>
                            )}
                        </article>
                    );
                })}
            </section>
        </section>
    );
}
