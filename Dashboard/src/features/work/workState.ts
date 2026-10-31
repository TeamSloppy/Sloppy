export interface WorkChat {
  key: string;
  agentId: string;
  sessionId: string;
  projectId: string | null;
  title: string;
}

export type WorkPanel = "files" | "kanban" | "review";
export interface WorkState {
  projectId: string | null;
  agentId: string | null;
  tabs: WorkChat[];
  activeKey: string | null;
  panel: WorkPanel | null;
  terminalOpen: boolean;
}

const STORAGE_KEY = "sloppy.work.v1";
const EMPTY_STATE: WorkState = {
  projectId: null, agentId: null, tabs: [], activeKey: null, panel: null, terminalOpen: false
};

export function readWorkState(): WorkState {
  try {
    const value = JSON.parse(window.localStorage.getItem(STORAGE_KEY) || "null");
    if (!value || typeof value !== "object") return { ...EMPTY_STATE, tabs: [] };
    const keys = new Set<string>();
    const tabs: WorkChat[] = (Array.isArray(value.tabs) ? value.tabs : []).flatMap((tab) => {
      if (!tab || typeof tab.agentId !== "string" || !tab.agentId || typeof tab.sessionId !== "string" || !tab.sessionId) return [];
      const key = `${tab.agentId}:${tab.sessionId}`;
      if (keys.has(key)) return [];
      keys.add(key);
      return [{ key, agentId: tab.agentId, sessionId: tab.sessionId,
        projectId: typeof tab.projectId === "string" ? tab.projectId : null,
        title: typeof tab.title === "string" && tab.title ? tab.title : "Chat" }];
    });
    const activeKey = value.activeKey === null ? null
      : tabs.some((tab) => tab.key === value.activeKey) ? value.activeKey : tabs[0]?.key || null;
    const active = tabs.find((tab) => tab.key === activeKey);
    return {
      projectId: active ? active.projectId : (typeof value.projectId === "string" ? value.projectId : null),
      agentId: typeof value.agentId === "string" ? value.agentId : null,
      tabs, activeKey,
      panel: ["files", "kanban", "review"].includes(value.panel) ? value.panel : null,
      terminalOpen: value.terminalOpen === true
    };
  } catch {
    return { ...EMPTY_STATE, tabs: [] };
  }
}

export function writeWorkState(state: WorkState) {
  try {
    // Keys are normalized to the current session when a chat creates a successor.
    const active = state.tabs.find((tab) => tab.key === state.activeKey);
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify({
      ...state,
      activeKey: active ? `${active.agentId}:${active.sessionId}` : null,
      tabs: state.tabs.map((tab) => ({ ...tab, key: `${tab.agentId}:${tab.sessionId}` }))
    }));
  } catch {
    // Private browsing and full storage must not prevent working.
  }
}

export function closeWorkChat(state: WorkState, key: string): WorkState {
  const index = state.tabs.findIndex((tab) => tab.key === key);
  if (index < 0) return state;
  const tabs = state.tabs.filter((tab) => tab.key !== key);
  const active = state.activeKey === key
    ? tabs[Math.max(0, index - 1)] || null
    : tabs.find((tab) => tab.key === state.activeKey) || null;
  return { ...state, tabs, activeKey: active?.key || null, projectId: active ? active.projectId : state.projectId };
}
