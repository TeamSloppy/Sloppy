import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { fetchAgents } from "../../api";
import { AgentChatTab } from "../agents/components/AgentChatTab";
import type { DashboardRoute } from "../../app/routing/dashboardRouteAdapter";

type AnyRecord = Record<string, unknown>;

function normalizeAgent(item: AnyRecord, index: number) {
  const id = String(item?.id || `agent-${index + 1}`).trim();
  return {
    id,
    displayName: String(item?.displayName || id).trim() || id
  };
}

function projectInitials(name: unknown, id: string) {
  const raw = String(name || id || "?").trim();
  const parts = raw.split(/[\s_-]+/).filter(Boolean);
  if (parts.length === 0) return "??";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

export function ProjectChatsView({
  route,
  setChatsRoute,
  projects
}: {
  route: DashboardRoute;
  setChatsRoute: (
    chatProjectId: string | null,
    chatAgentId?: string | null,
    chatSessionId?: string | null
  ) => void;
  projects: AnyRecord[];
}) {
  const chatProjectId = route.chatProjectId;
  const chatAgentId = route.chatAgentId;
  const chatSessionId = route.chatSessionId;

  const [agents, setAgents] = useState<{ id: string; displayName: string }[]>([]);
  const [agentSearch, setAgentSearch] = useState("");
  const [agentDropdownOpen, setAgentDropdownOpen] = useState(false);
  const agentSearchRef = useRef<HTMLInputElement | null>(null);

  const project = useMemo(() => {
    if (!chatProjectId) {
      return null;
    }
    const list = Array.isArray(projects) ? projects : [];
    return list.find((p) => String(p?.id || "").trim() === chatProjectId) || null;
  }, [chatProjectId, projects]);

  useEffect(() => {
    let cancelled = false;
    fetchAgents()
      .then((list) => {
        if (cancelled || !Array.isArray(list)) {
          return;
        }
        setAgents(list.map((item, index) => normalizeAgent(item as AnyRecord, index)));
      })
      .catch(() => {
        if (!cancelled) {
          setAgents([]);
        }
      });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    const a = agents.find((x) => x.id === chatAgentId);
    if (a) {
      setAgentSearch(a.displayName || a.id);
    } else if (!chatAgentId) {
      setAgentSearch("");
    }
  }, [chatAgentId, agents]);

  const onActiveSessionIdChange = useCallback(
    (sessionId: string | null) => {
      if (!chatProjectId || !chatAgentId) {
        return;
      }
      setChatsRoute(chatProjectId, chatAgentId, sessionId);
    },
    [chatAgentId, chatProjectId, setChatsRoute]
  );

  const filteredAgents = useMemo(() => {
    const q = agentSearch.toLowerCase();
    return agents.filter(
      (agent) =>
        agent.displayName.toLowerCase().includes(q) || agent.id.toLowerCase().includes(q)
    );
  }, [agentSearch, agents]);

  if (!chatProjectId) {
    return (
      <main className="project-chats-shell">
        <p className="app-status-text">Select a project in the sidebar to open project chat.</p>
      </main>
    );
  }

  return (
    <main className="project-chats-shell" data-testid="project-chats-view">
      <header className="project-chats-head">
        <div className="project-chats-title-row">
          <span className="project-chats-avatar" aria-hidden="true">
            {projectInitials(project?.name, chatProjectId)}
          </span>
          <div>
            <h1 className="project-chats-title">{String(project?.name || chatProjectId)}</h1>
            <p className="project-chats-sub">{chatProjectId}</p>
          </div>
        </div>

        <label className="project-chats-agent-label">
          <span className="project-chats-agent-label-text">Agent</span>
          <div className="actor-team-search-wrap project-chats-agent-search">
            <input
              ref={agentSearchRef}
              className="actor-team-search"
              value={agentSearch}
              onChange={(event) => {
                setAgentSearch(event.target.value);
                setAgentDropdownOpen(true);
              }}
              onFocus={() => setAgentDropdownOpen(true)}
              onBlur={() => setTimeout(() => setAgentDropdownOpen(false), 150)}
              placeholder="Search agents…"
              autoComplete="off"
            />
            {agentDropdownOpen ? (
              <ul className="actor-team-dropdown">
                {filteredAgents.map((agent) => {
                  const isSelected = chatAgentId === agent.id;
                  return (
                    <li
                      key={agent.id}
                      className={`actor-team-dropdown-item ${isSelected ? "selected" : ""}`}
                      onMouseDown={(event) => {
                        event.preventDefault();
                        setAgentSearch(agent.displayName || agent.id);
                        setAgentDropdownOpen(false);
                        setChatsRoute(chatProjectId, agent.id, null);
                      }}
                    >
                      <span className="actor-team-dropdown-name">{agent.displayName || agent.id}</span>
                      <span className="actor-team-dropdown-id">{agent.id}</span>
                      {isSelected ? <span className="actor-team-dropdown-check">✓</span> : null}
                    </li>
                  );
                })}
                {filteredAgents.length === 0 ? (
                  <li className="actor-team-dropdown-empty">No agents found</li>
                ) : null}
              </ul>
            ) : null}
          </div>
        </label>
      </header>

      {chatAgentId ? (
        <AgentChatTab
          key={`${chatProjectId}:${chatAgentId}`}
          agentId={chatAgentId}
          initialSessionId={chatSessionId}
          projectId={chatProjectId}
          onActiveSessionIdChange={onActiveSessionIdChange}
        />
      ) : (
        <p className="app-status-text">Choose an agent to load sessions and chat.</p>
      )}
    </main>
  );
}
