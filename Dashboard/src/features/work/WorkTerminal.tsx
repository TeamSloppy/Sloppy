import React, { useCallback, useEffect, useRef, useState } from "react";
import { TerminalPane, makeTerminalTab, type TerminalTabState } from "../terminal/TerminalDrawer";
import type { CoreApi } from "../../shared/api/coreApi";

export function WorkTerminal({ coreApi, projectId, repoPath, visible, height, onClose }: {
  coreApi: CoreApi;
  projectId: string | null;
  repoPath: string | null;
  visible: boolean;
  height: number;
  onClose: () => void;
}) {
  const counter = useRef(1);
  const [tabs, setTabs] = useState<TerminalTabState[]>(() => [makeTerminalTab(1, projectId, repoPath)]);
  const [activeId, setActiveId] = useState(() => tabs[0].id);
  const updateTab = useCallback((id: string, patch: Partial<TerminalTabState>) => {
    setTabs((previous) => previous.map((tab) => tab.id === id ? { ...tab, ...patch } : tab));
  }, []);
  const active = tabs.find((tab) => tab.id === activeId);
  function addTab() {
    const tab = makeTerminalTab(++counter.current, projectId, repoPath);
    setTabs((previous) => [...previous, tab]);
    setActiveId(tab.id);
  }
  useEffect(() => {
    if (visible && !tabs.length) {
      const tab = makeTerminalTab(++counter.current, projectId, repoPath);
      setTabs([tab]);
      setActiveId(tab.id);
    }
  }, [visible, tabs.length, projectId, repoPath]);
  function closeTab(id: string) {
    const next = tabs.filter((tab) => tab.id !== id);
    setTabs(next);
    if (id === activeId) setActiveId(next[next.length - 1]?.id || "");
    if (!next.length) onClose();
  }
  return <section className="work-terminal" aria-label="Work terminal">
    <header className="work-panel-head">
      <span className="material-symbols-rounded" aria-hidden="true">terminal</span>
      <div className="work-terminal-tabs" role="tablist" aria-label="Work terminal tabs">
        {tabs.map((tab) => <div key={tab.id} className={`work-tab ${tab.id === activeId ? "active" : ""}`}>
          <button type="button" role="tab" aria-selected={tab.id === activeId} onClick={() => setActiveId(tab.id)}>{tab.label}</button>
          <button type="button" aria-label={`Close terminal ${tab.label}`} onClick={() => closeTab(tab.id)}><span className="material-symbols-rounded" aria-hidden="true">close</span></button>
        </div>)}
      </div>
      <button className="work-icon-button" type="button" onClick={addTab} aria-label="New Work terminal"><span className="material-symbols-rounded" aria-hidden="true">add</span></button>
      <button className="work-icon-button" type="button" onClick={onClose} aria-label="Hide Work terminal"><span className="material-symbols-rounded" aria-hidden="true">close</span></button>
    </header>
    <div className="work-terminal-context" role="status">{active?.statusText || "Open a terminal with +"}<span>{active?.activeCwd || active?.projectRepoPath}</span></div>
    <div className="terminal-drawer-stage">
      {tabs.map((tab) => <TerminalPane key={tab.id} tab={tab} coreApi={coreApi}
        appearance="dashboard" isActive={tab.id === activeId} isDrawerOpen={visible} drawerHeight={height} onUpdate={updateTab} />)}
    </div>
  </section>;
}
