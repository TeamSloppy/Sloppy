import React, { useCallback, useEffect, useRef, useState } from "react";
import type { CoreApi } from "../../shared/api/coreApi";
import { AgentChatTab } from "../agents/components/AgentChatTab";
import { ProjectSourceControlDiffPanel, type SourceControlComposeTagPayload } from "../agents/components/ProjectSourceControlDiffPanel";
import { ProjectFilesTab } from "../../views/Projects/ProjectFilesTab";
import { ProjectsView } from "../../views/ProjectsView";
import { WorkProjectChats } from "./WorkProjectChats";
import { WorkPicker } from "./WorkPicker";
import { WorkTerminal } from "./WorkTerminal";
import { closeWorkChat, readWorkState, writeWorkState, type WorkChat, type WorkPanel } from "./workState";
import "./work.css";

type RecordValue = Record<string, any>;
type ReviewTag = SourceControlComposeTagPayload & { id: string };
const PANELS: { id: WorkPanel; title: string; icon: string }[] = [
  { id: "files", title: "Files", icon: "folder_open" },
  { id: "kanban", title: "Kanban", icon: "view_kanban" },
  { id: "review", title: "Review", icon: "difference" }
];

function Icon({ name }: { name: string }) {
  return <span className="material-symbols-rounded" aria-hidden="true">{name}</span>;
}

// Each open chat owns its stream and draft even while a different tab is visible.
function WorkChatPane({ tab, active, reviewTag, onSessionChange, onReviewTagConsumed, composerExtras }: {
  tab: WorkChat;
  active: boolean;
  reviewTag: ReviewTag | null;
  onSessionChange: (key: string, sessionId: string) => void;
  onReviewTagConsumed: (key: string, id: string) => void;
  composerExtras: React.ReactNode;
}) {
  const sessionChanged = useCallback((id: string | null) => {
    if (id && id !== tab.sessionId) onSessionChange(tab.key, id);
  }, [onSessionChange, tab.key, tab.sessionId]);
  const tagConsumed = useCallback((id: string) => onReviewTagConsumed(tab.key, id), [onReviewTagConsumed, tab.key]);
  return <div className="work-chat-pane" hidden={!active} role="tabpanel" id={`work-chat-${tab.key}`} aria-label={tab.title}>
    <AgentChatTab agentId={tab.agentId} initialSessionId={tab.sessionId} projectId={tab.projectId}
      layout="work" composerExtras={composerExtras} showSessionSidebar={false} lockPageScroll={false} onActiveSessionIdChange={sessionChanged}
      modeStorageScope={`work:${tab.key}`} reviewTag={reviewTag} onReviewTagConsumed={tagConsumed} />
  </div>;
}

export function WorkView({ coreApi, projects, terminalEnabled, visible = true, channelState = {}, workers = [], bulletins = [], onWorkersChanged, onOpenProjects, onOpenTerminalSettings, onOpenChannelSession }: {
  coreApi: CoreApi;
  projects: RecordValue[];
  terminalEnabled: boolean;
  visible?: boolean;
  channelState?: any;
  workers?: any[];
  bulletins?: any[];
  onWorkersChanged?: () => void;
  onOpenProjects: () => void;
  onOpenTerminalSettings: () => void;
  onOpenChannelSession?: (id: string) => void;
}) {
  const [state, setState] = useState(readWorkState);
  const [sessions, setSessions] = useState<RecordValue[]>([]);
  const [agents, setAgents] = useState<RecordValue[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState("");
  const [actionError, setActionError] = useState("");
  const [creating, setCreating] = useState(false);
  const creatingRef = useRef(false);
  const [chatsVisible, setChatsVisible] = useState(() => window.innerWidth > 1000);
  const [terminalStarted, setTerminalStarted] = useState(state.terminalOpen);
  const [terminalHeight, setTerminalHeight] = useState(260);
  const [panelWidth, setPanelWidth] = useState(460);
  const [panelExpanded, setPanelExpanded] = useState(false);
  const [reviewTags, setReviewTags] = useState<Record<string, ReviewTag>>({});
  const [boardRoute, setBoardRoute] = useState({ projectId: "", tab: "tasks", task: null as string | null });
  const shellRef = useRef<HTMLElement | null>(null);
  const aliveRef = useRef(true);
  const refreshEpochRef = useRef(0);
  const project = projects.find((item) => item.id === state.projectId);
  const activeTab = state.tabs.find((tab) => tab.key === state.activeKey);
  const selectedAgentId = agents.some((agent) => agent.id === state.agentId) ? state.agentId : String(agents[0]?.id || "");
  const currentBoardRoute = boardRoute.projectId === state.projectId ? boardRoute : { tab: "tasks", task: null };

  useEffect(() => { writeWorkState(state); }, [state]);
  useEffect(() => {
    aliveRef.current = true;
    return () => { aliveRef.current = false; };
  }, []);

  const refresh = useCallback(async () => {
    const epoch = ++refreshEpochRef.current;
    try {
      const [sessionList, agentList] = await Promise.all([
        coreApi.fetchAllAgentSessions({ limit: 500 }), coreApi.fetchAgents()
      ]);
      if (!aliveRef.current || epoch !== refreshEpochRef.current) return;
      if (!Array.isArray(sessionList) || !Array.isArray(agentList)) throw new Error("Could not load chats and agents. Check the Core connection.");
      setSessions(sessionList);
      setAgents(agentList);
      setLoadError("");
      setState((previous) => {
        let changed = false;
        const tabs = previous.tabs.map((tab) => {
          const session = sessionList.find((item) => item.id === tab.sessionId && item.agentId === tab.agentId);
          if (!session?.title || session.title === tab.title) return tab;
          changed = true;
          return { ...tab, title: String(session.title) };
        });
        return changed ? { ...previous, tabs } : previous;
      });
    } catch (error) {
      if (aliveRef.current && epoch === refreshEpochRef.current) setLoadError(error instanceof Error ? error.message : "Could not load chats.");
    } finally {
      if (aliveRef.current && epoch === refreshEpochRef.current) setLoading(false);
    }
  }, [coreApi]);

  useEffect(() => {
    if (!visible) return;
    void refresh();
    const timer = window.setInterval(() => { if (!document.hidden) void refresh(); }, 8000);
    window.addEventListener("focus", refresh);
    return () => { window.clearInterval(timer); window.removeEventListener("focus", refresh); };
  }, [refresh, visible]);

  const reviewTagConsumed = useCallback((key: string, id: string) => {
    setReviewTags((previous) => {
      if (previous[key]?.id !== id) return previous;
      const next = { ...previous };
      delete next[key];
      return next;
    });
  }, []);

  const sessionChanged = useCallback((key: string, sessionId: string) => {
    setState((previous) => {
      const source = previous.tabs.find((tab) => tab.key === key);
      const duplicate = previous.tabs.find((tab) => tab.agentId === source?.agentId && tab.sessionId === sessionId && tab.key !== key);
      if (duplicate) return { ...closeWorkChat(previous, key), activeKey: duplicate.key, projectId: duplicate.projectId };
      return { ...previous, tabs: previous.tabs.map((tab) => tab.key === key ? { ...tab, sessionId, title: "New chat" } : tab) };
    });
    void refresh();
  }, [refresh]);

  function selectProject(id: string) {
    setState((previous) => ({ ...previous, projectId: id || null,
      activeKey: previous.tabs.find((tab) => tab.projectId === (id || null))?.key || null }));
    setActionError("");
  }

  function openChat(session: RecordValue) {
    const key = `${session.agentId}:${session.id}`;
    const tab: WorkChat = { key, sessionId: String(session.id), agentId: String(session.agentId),
      projectId: session.projectId || null, title: String(session.title || "Chat") };
    setState((previous) => {
      // A tab keeps its key when /clear creates a successor session.
      const existing = previous.tabs.find((item) => item.agentId === tab.agentId && item.sessionId === tab.sessionId);
      return { ...previous, activeKey: existing?.key || key, projectId: tab.projectId,
        tabs: existing ? previous.tabs : [...previous.tabs, tab] };
    });
    setActionError("");
  }

  async function createChat(projectId: string | null = state.projectId): Promise<WorkChat | null> {
    if (creatingRef.current || !selectedAgentId) return null;
    creatingRef.current = true;
    setCreating(true);
    setActionError("");
    try {
      const session = await coreApi.createAgentSession(selectedAgentId, { separateChat: true, ...(projectId ? { projectId } : {}) });
      if (!session?.id) throw new Error("Could not create chat. Try again.");
      if (!aliveRef.current) return null;
      const record = { ...session, agentId: selectedAgentId, projectId };
      const tab: WorkChat = { key: `${selectedAgentId}:${session.id}`, agentId: selectedAgentId,
        projectId, sessionId: String(session.id), title: String(session.title || "New chat") };
      setSessions((previous) => [record, ...previous]);
      setState((previous) => ({ ...previous, tabs: [...previous.tabs, tab], activeKey: tab.key, projectId }));
      return tab;
    } catch (error) {
      if (aliveRef.current) setActionError(error instanceof Error ? error.message : "Could not create chat.");
      return null;
    } finally {
      creatingRef.current = false;
      if (aliveRef.current) setCreating(false);
    }
  }

  async function addReviewTag(payload: SourceControlComposeTagPayload) {
    const target = activeTab || await createChat();
    if (!target) {
      setActionError("Choose an agent and open a chat to add a review note.");
      return;
    }
    setReviewTags((previous) => ({ ...previous, [target.key]: { ...payload, id: crypto.randomUUID() } }));
  }

  function togglePanel(panel: WorkPanel) {
    setPanelExpanded(false);
    setState((previous) => ({ ...previous, panel: previous.panel === panel ? null : panel }));
  }

  function toggleTerminal() {
    setTerminalStarted(true);
    setState((previous) => ({ ...previous, terminalOpen: !previous.terminalOpen }));
  }

  useEffect(() => {
    if (!visible) return;
    function onKeyDown(event: KeyboardEvent) {
      if ((event.ctrlKey || event.metaKey) && !event.altKey && !event.shiftKey && event.key.toLowerCase() === "j") {
        event.preventDefault();
        setTerminalStarted(true);
        setState((previous) => ({ ...previous, terminalOpen: !previous.terminalOpen }));
      }
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [visible]);

  function startResize(event: React.PointerEvent<HTMLDivElement>, target: "panel" | "terminal") {
    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    const origin = { x: event.clientX, y: event.clientY, panel: panelWidth, terminal: terminalHeight };
    const handle = event.currentTarget;
    const move = (next: PointerEvent) => {
      if (target === "panel") setPanelWidth(Math.max(320, Math.min((shellRef.current?.clientWidth || 1000) * 0.65, origin.panel + origin.x - next.clientX)));
      else setTerminalHeight(Math.max(140, Math.min((shellRef.current?.clientHeight || 800) * 0.65, origin.terminal + origin.y - next.clientY)));
    };
    const stop = () => { handle.removeEventListener("pointermove", move); handle.removeEventListener("pointerup", stop); handle.removeEventListener("pointercancel", stop); };
    handle.addEventListener("pointermove", move);
    handle.addEventListener("pointerup", stop);
    handle.addEventListener("pointercancel", stop);
  }

  const agentOptions = <WorkPicker label="Agent for new chats" value={selectedAgentId || ""}
    options={agents.map((agent) => ({ id: String(agent.id), label: String(agent.displayName || agent.id) }))}
    onChange={(agentId) => setState((previous) => ({ ...previous, agentId }))} />;

  return <main ref={shellRef} className={`work-shell ${chatsVisible ? "" : "work-chats-hidden"} ${state.panel ? "work-has-panel" : ""} ${panelExpanded ? "work-panel-expanded" : ""}`}
    data-testid="work-view" style={{ "--work-panel-width": `${panelWidth}px`, "--work-terminal-height": `${terminalHeight}px` } as React.CSSProperties}>
    <header className="work-header">
      <button type="button" className="work-icon-button" aria-label={chatsVisible ? "Hide chats" : "Show chats"} aria-pressed={chatsVisible} onClick={() => setChatsVisible((value) => !value)}><Icon name="left_panel_open" /></button>
      <h1>Work</h1><span className="work-header-divider">/</span><span className="work-header-project">{project?.name || (state.projectId ? state.projectId : "All projects")}</span>
      <button type="button" className="work-header-new" disabled={creating || !selectedAgentId} onClick={() => void createChat()}><Icon name="add" />{creating ? "Creating…" : "New chat"}</button>
    </header>
    <aside className="work-chats" aria-label="Work chats" hidden={!chatsVisible}>
      <div className="work-list-heading"><h2>Projects</h2><span>{projects.length}</span><button type="button" className="work-icon-button" onClick={() => void refresh()} aria-label="Refresh Work chats"><Icon name="refresh" /></button></div>
      {loadError ? <div className="work-error" role="alert">{loadError}<button type="button" onClick={() => void refresh()}>Retry</button></div> : null}
      <WorkProjectChats projects={projects} sessions={sessions} activeChat={activeTab} selectedProjectId={state.projectId}
        loading={loading} creating={creating || !selectedAgentId} onSelectProject={selectProject} onOpenChat={openChat}
        onCreateChat={(projectId) => void createChat(projectId)} />
      {!projects.length ? <button type="button" className="work-projects-link" onClick={onOpenProjects}><Icon name="create_new_folder" />Open projects</button> : null}
    </aside>
    <section className="work-center" aria-label="Chat workspace">
      <div className="work-chat-tabs" role="tablist" aria-label="Open chats" onKeyDown={(event) => {
        if ((event.target as HTMLElement).getAttribute("role") !== "tab" || !["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
        event.preventDefault();
        const current = state.tabs.findIndex((tab) => tab.key === state.activeKey);
        const index = event.key === "Home" ? 0 : event.key === "End" ? state.tabs.length - 1
          : (current + (event.key === "ArrowRight" ? 1 : -1) + state.tabs.length) % state.tabs.length;
        const tab = state.tabs[index];
        if (!tab) return;
        setState((previous) => ({ ...previous, activeKey: tab.key, projectId: tab.projectId }));
        event.currentTarget.querySelectorAll<HTMLButtonElement>('[role="tab"]')[index]?.focus();
      }}>
        {state.tabs.map((tab) => <div key={tab.key} className={`work-tab ${tab.key === state.activeKey ? "active" : ""}`}>
          <button type="button" role="tab" aria-selected={tab.key === state.activeKey} tabIndex={tab.key === state.activeKey ? 0 : -1} aria-controls={`work-chat-${tab.key}`}
            onClick={() => setState((previous) => ({ ...previous, activeKey: tab.key, projectId: tab.projectId }))} title={tab.title}><Icon name="chat_bubble_outline" /><span>{tab.title}</span></button>
          <button type="button" aria-label={`Close chat ${tab.title}`} title="Close tab" onClick={() => setState((previous) => closeWorkChat(previous, tab.key))}><Icon name="close" /></button>
        </div>)}
        <button type="button" className="work-icon-button" aria-label="Open new chat tab" title="New chat" disabled={!selectedAgentId || creating} onClick={() => void createChat()}><Icon name="add" /></button>
      </div>
      {actionError ? <div className="work-error" role="alert">{actionError}<button type="button" aria-label="Dismiss Work error" onClick={() => setActionError("")}><Icon name="close" /></button></div> : null}
      <div className="work-chat-stage">
        {state.tabs.map((tab) => <WorkChatPane key={tab.key} tab={tab} active={tab.key === state.activeKey}
          reviewTag={reviewTags[tab.key] || null} onSessionChange={sessionChanged} onReviewTagConsumed={reviewTagConsumed} composerExtras={agentOptions} />)}
        {!activeTab ? <div className="work-empty-state"><div className="work-empty"><Icon name="chat_bubble_outline" /><h2>Room to work.</h2><p>Open a chat, bring in your files,<br />and keep everything in one place.</p>
          {!loading && !agents.length && !loadError ? <p>Create an agent in Agents to start chatting.</p> : null}
          <div className="work-empty-tools">{PANELS.map((panel) => <button type="button" key={panel.id} onClick={() => togglePanel(panel.id)}><Icon name={panel.icon} />{panel.title}</button>)}</div>
        </div><div className="work-start-composer">{agentOptions}<button type="button" disabled={!selectedAgentId || creating} onClick={() => void createChat()}><Icon name="add" />New chat</button></div></div> : null}
      </div>
      <div className="work-terminal-slot" hidden={!state.terminalOpen}>
        <div className="work-resizer work-resizer-horizontal" role="separator" aria-label="Terminal height" aria-orientation="horizontal" tabIndex={0}
          onPointerDown={(event) => startResize(event, "terminal")} onKeyDown={(event) => {
            if (["ArrowUp", "ArrowDown"].includes(event.key)) { event.preventDefault(); setTerminalHeight((value) => Math.max(140, Math.min(500, value + (event.key === "ArrowUp" ? 20 : -20)))); }
          }} />
        {terminalStarted && terminalEnabled ? <WorkTerminal coreApi={coreApi} projectId={state.projectId} repoPath={project?.repoPath || null}
          visible={visible && state.terminalOpen} height={terminalHeight} onClose={() => setState((previous) => ({ ...previous, terminalOpen: false }))} /> : null}
        {!terminalEnabled ? <div className="work-terminal-unavailable"><Icon name="terminal" /><p>Enable the dashboard terminal to run commands here.</p><button type="button" onClick={onOpenTerminalSettings}>Terminal settings</button></div> : null}
      </div>
    </section>
    {state.panel && visible ? <aside className={`work-context work-context-${state.panel}`} aria-label={`${PANELS.find((panel) => panel.id === state.panel)?.title} panel`}>
      <div className="work-resizer work-resizer-vertical" role="separator" aria-label="Panel width" aria-orientation="vertical" tabIndex={0}
        onPointerDown={(event) => startResize(event, "panel")} onKeyDown={(event) => {
          if (["ArrowLeft", "ArrowRight"].includes(event.key)) { event.preventDefault(); setPanelWidth((value) => Math.max(320, Math.min(800, value + (event.key === "ArrowLeft" ? 20 : -20)))); }
        }} />
      <header className="work-panel-head"><Icon name={PANELS.find((panel) => panel.id === state.panel)?.icon || "folder"} /><h2>{PANELS.find((panel) => panel.id === state.panel)?.title}</h2>
        <button type="button" className="work-icon-button" aria-label={panelExpanded ? "Restore Work panel" : "Expand Work panel"} title={panelExpanded ? "Restore panel" : "Expand panel"} onClick={() => setPanelExpanded((value) => !value)}><Icon name={panelExpanded ? "close_fullscreen" : "open_in_full"} /></button>
        <button type="button" className="work-icon-button" aria-label="Close Work panel" onClick={() => setState((previous) => ({ ...previous, panel: null }))}><Icon name="close" /></button></header>
      <div className="work-panel-content">
        {!project ? <div className="work-panel-empty"><Icon name="folder_open" /><p>Choose a project to open {state.panel === "kanban" ? "its board" : state.panel === "review" ? "its changes" : "its files"}.</p><button type="button" onClick={() => setChatsVisible(true)}>Show projects</button></div> : null}
        {project && state.panel === "files" ? <ProjectFilesTab key={project.id} project={project} /> : null}
        {project && state.panel === "review" ? <ProjectSourceControlDiffPanel key={project.id} projectId={project.id} open
          onClose={() => setState((previous) => ({ ...previous, panel: null }))} onAddSourceControlComposeTag={(payload) => void addReviewTag(payload)} /> : null}
        {project && state.panel === "kanban" ? <ProjectsView key={project.id} embedded channelState={channelState} workers={workers} bulletins={bulletins}
          routeProjectId={project.id} routeProjectTab={currentBoardRoute.tab} routeProjectTaskReference={currentBoardRoute.task}
          onRouteProjectChange={(_id, tab, task) => setBoardRoute({ projectId: project.id, tab: tab === "review" ? "review" : "tasks", task: task || null })}
          onWorkersChanged={onWorkersChanged} onNavigateToChannelSession={onOpenChannelSession} /> : null}
      </div>
    </aside> : null}
    <nav className="work-tool-rail" aria-label="Work panels">
      {PANELS.map((panel) => <button type="button" key={panel.id} className={`work-icon-button ${state.panel === panel.id ? "active" : ""}`}
        aria-label={panel.title} title={panel.title} aria-pressed={state.panel === panel.id} onClick={() => togglePanel(panel.id)}><Icon name={panel.icon} /></button>)}
      <span className="work-tool-rail-separator" />
      <button type="button" className={`work-icon-button ${state.terminalOpen ? "active" : ""}`} aria-label="Terminal" aria-pressed={state.terminalOpen} title="Terminal (Ctrl/⌘ J)" onClick={toggleTerminal}><Icon name="terminal" /></button>
    </nav>
  </main>;
}
