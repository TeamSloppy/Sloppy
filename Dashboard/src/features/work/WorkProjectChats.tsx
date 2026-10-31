import React, { useId, useState } from "react";

type RecordValue = Record<string, any>;

export function WorkProjectChats({ projects, sessions, activeChat, selectedProjectId, loading, creating, onSelectProject, onOpenChat, onCreateChat }: {
  projects: RecordValue[];
  sessions: RecordValue[];
  activeChat?: { sessionId: string; agentId: string };
  selectedProjectId: string | null;
  loading: boolean;
  creating: boolean;
  onSelectProject: (id: string) => void;
  onOpenChat: (session: RecordValue) => void;
  onCreateChat: (id: string | null) => void;
}) {
  const id = useId();
  const [query, setQuery] = useState("");
  const [collapsed, setCollapsed] = useState<Set<string>>(() => new Set());
  const chats = sessions.filter((session) => session.id && session.agentId && (!session.kind || session.kind === "chat" || session.kind === "long_chat"));
  const known = new Set(projects.map((project) => String(project.id)));
  const missing = [...new Set(chats.map((chat) => String(chat.projectId || "")).filter((projectId) => projectId && !known.has(projectId)))];
  const groups = [
    ...projects.map((project) => ({ id: String(project.id), name: String(project.name || project.id) })),
    ...missing.map((projectId) => ({ id: projectId, name: projectId })),
    ...(chats.some((chat) => !chat.projectId) || !projects.length ? [{ id: "", name: "Personal" }] : [])
  ];
  const search = query.trim().toLowerCase();

  return <>
    <label className="work-search"><span className="material-symbols-rounded" aria-hidden="true">search</span><input type="search" aria-label="Search Work chats" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search projects and chats…" /></label>
    <div className="work-chat-list" aria-label="Projects and chats">
      {loading ? <p className="work-muted" role="status">Loading chats…</p> : null}
      {groups.map((project) => {
        const matchesProject = project.name.toLowerCase().includes(search);
        const projectChats = chats.filter((chat) => (chat.projectId || "") === project.id
          && (matchesProject || `${chat.title || ""} ${chat.lastMessagePreview || ""}`.toLowerCase().includes(search)));
        if (search && !matchesProject && !projectChats.length) return null;
        const expanded = search || !collapsed.has(project.id);
        const listId = `${id}-project-${encodeURIComponent(project.id || "personal")}`;
        return <section className="work-project-group" key={project.id} aria-label={`${project.name} chats`}>
          <header className={`work-project-head ${selectedProjectId === (project.id || null) ? "active" : ""}`}>
            <button type="button" className="work-project-toggle" aria-label={`${expanded ? "Collapse" : "Expand"} project ${project.name}`} aria-expanded={Boolean(expanded)} aria-controls={listId}
              onClick={() => setCollapsed((previous) => { const next = new Set(previous); if (next.has(project.id)) next.delete(project.id); else next.add(project.id); return next; })}>
              <span className="material-symbols-rounded" aria-hidden="true">{expanded ? "expand_more" : "chevron_right"}</span>
            </button>
            <button type="button" className="work-project-select" aria-label={`Select project ${project.name}`} onClick={() => onSelectProject(project.id)}>
              <span className="material-symbols-rounded" aria-hidden="true">{project.id ? "folder_open" : "chat_bubble_outline"}</span><span>{project.name}</span>
            </button>
            <button type="button" className="work-icon-button" aria-label={`New chat in ${project.name}`} title="New chat" disabled={creating} onClick={() => onCreateChat(project.id || null)}><span className="material-symbols-rounded" aria-hidden="true">add</span></button>
          </header>
          <div id={listId} hidden={!expanded} className="work-project-chats">
            {projectChats.map((session) => <button type="button" key={`${session.agentId}:${session.id}`}
              className={`work-chat-row ${activeChat?.sessionId === session.id && activeChat?.agentId === session.agentId ? "active" : ""}`}
              aria-current={activeChat?.sessionId === session.id && activeChat?.agentId === session.agentId ? "true" : undefined}
              onClick={() => onOpenChat(session)} title={String(session.title || "Chat")}><span>{session.title || "Untitled chat"}</span></button>)}
            {!projectChats.length && !loading ? <p className="work-project-empty">{search ? "No matching chats" : "No chats yet"}</p> : null}
          </div>
        </section>;
      })}
      {search && !groups.some((project) => project.name.toLowerCase().includes(search)) && !chats.some((chat) => `${chat.title || ""} ${chat.lastMessagePreview || ""}`.toLowerCase().includes(search)) ? <p className="work-muted">No matching projects or chats.</p> : null}
    </div>
  </>;
}
