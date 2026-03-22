import React, { useEffect, useMemo, useState } from "react";
import {
  createAgent as createAgentRequest,
  fetchAgent,
  fetchAgents,
} from "../../api";
import { AgentOverviewTab } from "./components/AgentOverviewTab";
import { AgentTasksTab } from "./components/AgentTasksTab";
import { AgentChatTab } from "./components/AgentChatTab";
import { AgentChannelsTab } from "./components/AgentChannelsTab";
import { AgentConfigTab } from "./components/AgentConfigTab";
import { AgentToolsTab } from "./components/AgentToolsTab";
import { AgentSkillsTab } from "./components/AgentSkillsTab";
import { AgentCronTab } from "./components/AgentCronTab";
import { AgentMemoriesTab } from "./components/AgentMemoriesTab";
import { Breadcrumbs } from "../../components/Breadcrumbs/Breadcrumbs";
import { AgentCreateForm, resolveSystemRole, emptyAgentFormValues } from "./components/AgentCreateForm";

const AGENT_TABS = [
  { id: "overview", title: "Overview" },
  { id: "chat", title: "Chat" },
  { id: "memories", title: "Memories" },
  { id: "tasks", title: "Tasks" },
  { id: "skills", title: "Skills" },
  { id: "tools", title: "Tools" },
  { id: "channels", title: "Channels" },
  { id: "cron", title: "Cron" },
  { id: "config", title: "Config" }
];

const AGENT_TAB_SET = new Set(AGENT_TABS.map((tab) => tab.id));

const emptyAgentForm = emptyAgentFormValues;

function agentInitials(name) {
  const parts = String(name || "?")
    .trim()
    .split(/[\s_-]+/)
    .filter(Boolean);
  if (parts.length === 0) return "??";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

function normalizeAgent(item, index = 0) {
  const id = String(item?.id || `agent-${index + 1}`).trim();
  return {
    id,
    displayName: String(item?.displayName || id).trim() || id,
    role: String(item?.role || "").trim(),
    createdAt: item?.createdAt || new Date().toISOString()
  };
}

function mergeAgent(previousAgents, incomingAgent) {
  const normalized = normalizeAgent(incomingAgent);
  const withoutOld = previousAgents.filter((item) => item.id !== normalized.id);
  return [...withoutOld, normalized].sort((left, right) =>
    left.displayName.localeCompare(right.displayName, undefined, { sensitivity: "base" })
  );
}

function tabTitle(tabId) {
  return AGENT_TABS.find((tab) => tab.id === tabId)?.title || "Overview";
}

function AgentCreateModal({ isOpen, form, createError, onFormChange, onClose, onSubmit }) {
  if (!isOpen) {
    return null;
  }

  return (
    <div className="agent-modal-overlay" onClick={onClose}>
      <section className="agent-modal-card" onClick={(event) => event.stopPropagation()}>
        <div className="agent-modal-head">
          <h3>Create Agent</h3>
          <button type="button" className="provider-close-button" onClick={onClose}>
            ×
          </button>
        </div>
        <AgentCreateForm
          form={form}
          error={createError}
          onFormChange={onFormChange}
          onSubmit={onSubmit}
          onCancel={onClose}
        />
      </section>
    </div>
  );
}

function AgentsIndexSection({
  agents,
  isLoadingAgents,
  statusText,
  onOpenCreateModal,
  onSelectAgent
}) {
  return (
    <section className="agents-index">
      {isLoadingAgents ? (
        <div className="agents-empty-stage">
          <p className="app-status-text">Loading agents from Sloppy...</p>
        </div>
      ) : agents.length === 0 ? (
        <div className="agents-empty-stage">
          <p className="project-new-action-subtitle">Create your first agent to start work</p>
          <button type="button" className="agent-empty-create hover-levitate" onClick={onOpenCreateModal}>
            Create Agent
          </button>
        </div>
      ) : (
        <div className="agent-list-container">
          {agents.map((agent) => (
            <button
              key={agent.id}
              type="button"
              className="agent-list-item-card hover-levitate"
              data-testid={`agent-list-item-${agent.id}`}
              onClick={() => onSelectAgent(agent.id)}
            >
              <span className="channel-agent-avatar agent-chart-avatar" aria-hidden="true" style={{ width: '40px', height: '40px', fontSize: '16px' }}>
                {agentInitials(agent.displayName || agent.id)}
              </span>
              <div className="agent-list-main">
                <div className="agent-list-head">
                  <h4>{agent.displayName}</h4>
                </div>
                <p>{agent.role || "General-purpose assistant"}</p>
                <span className="agent-list-id">ID: {agent.id}</span>
              </div>
            </button>
          ))}
        </div>
      )}

      {agents.length > 0 || statusText.startsWith("Failed") ? (
        <p className="app-status-text">{statusText}</p>
      ) : null}
    </section>
  );
}

export function AgentsView({ routeAgentId = null, routeTab = "overview", onRouteChange = null, onNavigateToChannelSession = null }) {
  const [agents, setAgents] = useState([]);
  const [isLoadingAgents, setIsLoadingAgents] = useState(true);
  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false);
  const [form, setForm] = useState(emptyAgentForm);
  const [createError, setCreateError] = useState("");
  const [statusText, setStatusText] = useState("Loading agents...");

  const activeAgent = useMemo(
    () => agents.find((agent) => agent.id === routeAgentId) || null,
    [agents, routeAgentId]
  );

  const activeTab = useMemo(() => {
    if (!activeAgent) {
      return "overview";
    }
    if (AGENT_TAB_SET.has(String(routeTab || "").toLowerCase())) {
      return String(routeTab).toLowerCase();
    }
    return "overview";
  }, [activeAgent, routeTab]);

  useEffect(() => {
    refreshAgents().catch(() => {
      setStatusText("Failed to load agents from Sloppy");
      setIsLoadingAgents(false);
    });
  }, []);

  useEffect(() => {
    if (!routeAgentId) {
      return;
    }
    if (agents.some((agent) => agent.id === routeAgentId)) {
      return;
    }

    fetchAgent(routeAgentId).then((agent) => {
      if (!agent) {
        return;
      }
      setAgents((previous) => mergeAgent(previous, agent));
    });
  }, [routeAgentId, agents]);

  async function refreshAgents() {
    setIsLoadingAgents(true);
    const response = await fetchAgents();
    if (!Array.isArray(response)) {
      setStatusText("Failed to load agents from Sloppy");
      setIsLoadingAgents(false);
      return;
    }

    const normalized = response
      .map((item, index) => normalizeAgent(item, index))
      .filter((item) => item.id.length > 0)
      .sort((left, right) => left.displayName.localeCompare(right.displayName, undefined, { sensitivity: "base" }));

    setAgents(normalized);
    setIsLoadingAgents(false);
    setStatusText(normalized.length > 0 ? `Loaded ${normalized.length} agents from Sloppy` : "No agents yet. Create one.");
  }

  function navigateToAgent(agentId, tab = "overview") {
    if (typeof onRouteChange === "function") {
      onRouteChange(agentId, tab);
    }
  }

  function navigateToAgentList() {
    if (typeof onRouteChange === "function") {
      onRouteChange(null, null);
    }
  }

  function updateForm(field, value) {
    setForm((previous) => ({
      ...previous,
      [field]: value
    }));
  }

  function openCreateModal() {
    setForm(emptyAgentForm());
    setCreateError("");
    setIsCreateModalOpen(true);
  }

  function closeCreateModal() {
    setCreateError("");
    setIsCreateModalOpen(false);
  }

  async function createAgent(event) {
    event.preventDefault();

    const rawId = String(form.id || "").trim();
    const normalizedId = rawId.replace(/\s+/g, "-");
    const displayName = String(form.displayName || "").trim();
    const role = String(form.role || "").trim();

    if (!normalizedId) {
      setCreateError("Agent ID is required.");
      return;
    }

    const response = await createAgentRequest({
      id: normalizedId,
      displayName: displayName || normalizedId,
      role: role || "General-purpose assistant",
      systemRole: resolveSystemRole(role) || undefined
    });

    if (!response) {
      setCreateError("Failed to create agent in Sloppy. Check ID format and duplicates.");
      return;
    }

    setAgents((previous) => mergeAgent(previous, response));
    setForm(emptyAgentForm());
    setStatusText(`Agent ${response.id} created in Sloppy`);
    setIsCreateModalOpen(false);
  }

  function renderAgentTabContent(agent, tab) {
    if (tab === "overview") {
      return <AgentOverviewTab agent={agent} navigateToAgent={navigateToAgent} />;
    }

    if (tab === "chat") {
      return <AgentChatTab agentId={agent.id} />;
    }

    if (tab === "memories") {
      return <AgentMemoriesTab agentId={agent.id} />;
    }

    if (tab === "tasks") {
      return <AgentTasksTab agentId={agent.id} />;
    }

    if (tab === "skills") {
      return <AgentSkillsTab agentId={agent.id} />;
    }

    if (tab === "cron") {
      return (
        <section className="entry-editor-card agent-content-card">
          <AgentCronTab agentId={agent.id} />
        </section>
      );
    }

    if (tab === "tools") {
      return (
        <section className="entry-editor-card agent-content-card">
          <AgentToolsTab agentId={agent.id} />
        </section>
      );
    }

    if (tab === "channels") {
      return (
        <section className="entry-editor-card agent-content-card">
          <AgentChannelsTab agentId={agent.id} agentDisplayName={agent.displayName} onNavigateToChannelSession={onNavigateToChannelSession} />
        </section>
      );
    }

    return (
      <section className="entry-editor-card agent-content-card">
        <AgentConfigTab agentId={agent.id} />
      </section>
    );
  }

  if (routeAgentId && !activeAgent) {
    return (
      <main className="agents-shell">
        <section className="entry-editor-card">
          <h2>{isLoadingAgents ? "Loading agent..." : "Agent Not Found"}</h2>
          <p className="placeholder-text">
            {isLoadingAgents ? "Synchronizing agent data from Sloppy." : `Agent with id ${routeAgentId} does not exist in Sloppy.`}
          </p>
          <div className="agent-inline-actions">
            <button type="button" onClick={navigateToAgentList}>
              Back To Agents
            </button>
          </div>
        </section>
      </main>
    );
  }

  if (!activeAgent) {
    return (
      <main className="agents-shell">
        <Breadcrumbs
          items={[
            { id: 'agents', label: 'Agents' }
          ]}
          style={{ marginBottom: '20px' }}
          action={
            <button type="button" className="agents-create-inline hover-levitate" onClick={openCreateModal}>
              Create Agent
            </button>
          }
        />

        <AgentsIndexSection
          agents={agents}
          isLoadingAgents={isLoadingAgents}
          statusText={statusText}
          onOpenCreateModal={openCreateModal}
          onSelectAgent={navigateToAgent}
        />

        <AgentCreateModal
          isOpen={isCreateModalOpen}
          form={form}
          createError={createError}
          onFormChange={updateForm}
          onClose={closeCreateModal}
          onSubmit={createAgent}
        />
      </main>
    );
  }

  const isChatLayout = activeTab === "chat";

  return (
    <main className={`agents-shell ${isChatLayout ? "chat-layout" : ""}`}>
      <Breadcrumbs
        items={[
          { id: 'agents', label: 'Agents', onClick: navigateToAgentList },
          { id: activeAgent.id, label: activeAgent.displayName }
        ]}
        style={{ marginBottom: '20px' }}
        action={
          <button type="button" className="agents-create-inline hover-levitate" onClick={openCreateModal}>
            Create Agent
          </button>
        }
      />

      <section className="agent-tabs" aria-label="Agent sections">
        {AGENT_TABS.map((tab) => (
          <button
            key={tab.id}
            type="button"
            className={`agent-tab ${activeTab === tab.id ? "active" : ""}`}
            data-testid={`agent-tab-${tab.id}`}
            onClick={() => navigateToAgent(activeAgent.id, tab.id)}
          >
            {tab.title}
          </button>
        ))}
      </section>

      <section className="agent-content-shell">
        {renderAgentTabContent(activeAgent, activeTab)}
      </section>
    </main>
  );
}
