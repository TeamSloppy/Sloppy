import React, { useCallback, useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { FitAddon } from "@xterm/addon-fit";
import { Terminal } from "@xterm/xterm";
import "@xterm/xterm/css/xterm.css";
import type { CoreApi, DashboardTerminalConnection } from "../../shared/api/coreApi";

const DRAWER_OPEN_STORAGE_KEY = "sloppy_terminal_drawer_open";
const DRAWER_HEIGHT_STORAGE_KEY = "sloppy_terminal_drawer_height";
const DEFAULT_DRAWER_HEIGHT = 320;
const MIN_DRAWER_HEIGHT = 220;
const MAX_DRAWER_HEIGHT_RATIO = 0.78;

type TerminalStatus = "idle" | "connecting" | "ready" | "closed" | "error" | "exited";

interface TerminalDrawerProps {
  coreApi: CoreApi;
  currentProjectId: string | null;
  currentProjectRepoPath: string | null;
  closedHostElement?: HTMLElement | null;
  isSidebarCompact?: boolean;
}

interface TerminalTabState {
  id: string;
  label: string;
  projectId: string | null;
  projectRepoPath: string | null;
  status: TerminalStatus;
  statusText: string;
  sessionId: string | null;
  activeCwd: string | null;
  activeShell: string | null;
}

interface TerminalPaneProps {
  tab: TerminalTabState;
  coreApi: CoreApi;
  isActive: boolean;
  isDrawerOpen: boolean;
  drawerHeight: number;
  onUpdate: (tabId: string, patch: Partial<TerminalTabState>) => void;
}

function loadStoredDrawerOpen() {
  try {
    return window.localStorage.getItem(DRAWER_OPEN_STORAGE_KEY) === "true";
  } catch {
    return false;
  }
}

function loadStoredDrawerHeight() {
  try {
    const stored = Number(window.localStorage.getItem(DRAWER_HEIGHT_STORAGE_KEY) || "");
    return Number.isFinite(stored) && stored >= MIN_DRAWER_HEIGHT ? stored : DEFAULT_DRAWER_HEIGHT;
  } catch {
    return DEFAULT_DRAWER_HEIGHT;
  }
}

function clampDrawerHeight(value: number) {
  const viewportLimit = Math.floor(window.innerHeight * MAX_DRAWER_HEIGHT_RATIO);
  return Math.max(MIN_DRAWER_HEIGHT, Math.min(viewportLimit, Math.round(value)));
}

function isEditableTarget(target: EventTarget | null) {
  const element = target instanceof HTMLElement ? target : null;
  if (!element) return false;
  const tagName = element.tagName.toLowerCase();
  return (
    element.isContentEditable ||
    tagName === "input" ||
    tagName === "textarea" ||
    tagName === "select" ||
    element.closest("[contenteditable='true']") != null
  );
}

function createTerminalTabId() {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return `terminal-tab-${crypto.randomUUID()}`;
  }
  return `terminal-tab-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function lastPathComponent(value: string | null | undefined) {
  const trimmed = typeof value === "string" ? value.trim() : "";
  if (!trimmed) return "";
  const normalized = trimmed.replace(/[\\/]+$/, "");
  if (!normalized) return "";
  const segments = normalized.split(/[\\/]/).filter(Boolean);
  return segments.length > 0 ? segments[segments.length - 1] : normalized;
}

function makeTerminalTab(index: number, projectId: string | null, projectRepoPath: string | null): TerminalTabState {
  const baseLabel = lastPathComponent(projectRepoPath) || "workspace";
  return {
    id: createTerminalTabId(),
    label: index === 1 ? baseLabel : `${baseLabel}-${index}`,
    projectId,
    projectRepoPath,
    status: "idle",
    statusText: "Press Cmd+J to open the terminal drawer.",
    sessionId: null,
    activeCwd: null,
    activeShell: null
  };
}

function tabStatusClass(status: TerminalStatus) {
  return `terminal-tab-indicator terminal-tab-indicator-${status}`;
}

function TerminalPane({
  tab,
  coreApi,
  isActive,
  isDrawerOpen,
  drawerHeight,
  onUpdate
}: TerminalPaneProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const terminalRef = useRef<Terminal | null>(null);
  const fitAddonRef = useRef<FitAddon | null>(null);
  const connectionRef = useRef<DashboardTerminalConnection | null>(null);
  const sessionIdRef = useRef<string | null>(null);
  const statusRef = useRef<TerminalStatus>("idle");
  const pendingInputRef = useRef<string[]>([]);
  const connectionEpochRef = useRef(0);

  const emitUpdate = useCallback((patch: Partial<TerminalTabState>) => {
    onUpdate(tab.id, patch);
  }, [onUpdate, tab.id]);

  const printSystemLine = useCallback((text: string) => {
    const terminal = terminalRef.current;
    if (!terminal) return;
    terminal.writeln("");
    terminal.writeln(`> ${text}`);
  }, []);

  const ensureTerminal = useCallback(() => {
    if (terminalRef.current || !containerRef.current) {
      return terminalRef.current;
    }

    const terminal = new Terminal({
      cursorBlink: true,
      cursorStyle: "block",
      fontFamily: '"SF Mono", "Fira Code", monospace',
      fontSize: 13,
      lineHeight: 1.25,
      scrollback: 5000,
      convertEol: false,
      theme: {
        background: "#0a0d10",
        foreground: "#f3f7fb",
        cursor: "#ccff00",
        black: "#0a0d10",
        brightBlack: "#616d78",
        red: "#ff6b6b",
        brightRed: "#ff9f9f",
        green: "#83f28f",
        brightGreen: "#b5ffbe",
        yellow: "#ffd166",
        brightYellow: "#ffe09a",
        blue: "#64b5f6",
        brightBlue: "#9cd3ff",
        magenta: "#ff79c6",
        brightMagenta: "#ffb7df",
        cyan: "#7ce7ff",
        brightCyan: "#b9f4ff",
        white: "#dbe5ee",
        brightWhite: "#ffffff"
      }
    });

    const fitAddon = new FitAddon();
    fitAddonRef.current = fitAddon;
    terminal.loadAddon(fitAddon);
    terminal.open(containerRef.current);
    fitAddon.fit();

    terminal.onData((data) => {
      if (!sessionIdRef.current) {
        if (pendingInputRef.current.length < 256) {
          pendingInputRef.current.push(data);
        }
        return;
      }
      connectionRef.current?.send({ type: "input", data });
    });

    terminal.onResize(({ cols, rows }) => {
      if (!sessionIdRef.current) return;
      connectionRef.current?.send({ type: "resize", cols, rows });
    });

    terminalRef.current = terminal;
    return terminal;
  }, []);

  const handleServerMessage = useCallback((payload: Record<string, unknown>) => {
    const type = String(payload.type || "").toLowerCase();

    if (type === "ready") {
      const nextSessionId = String(payload.sessionId || "").trim() || null;
      const cwd = String(payload.cwd || "").trim() || null;
      const shell = String(payload.shell || "").trim() || null;
      sessionIdRef.current = nextSessionId;
      statusRef.current = "ready";
      emitUpdate({
        sessionId: nextSessionId,
        activeCwd: cwd,
        activeShell: shell,
        status: "ready",
        statusText: cwd ? `Connected to ${cwd}` : "Terminal connected."
      });
      if (isActive && isDrawerOpen) {
        terminalRef.current?.focus();
      }
      if (pendingInputRef.current.length > 0) {
        const buffered = pendingInputRef.current.splice(0, pendingInputRef.current.length);
        for (const chunk of buffered) {
          connectionRef.current?.send({ type: "input", data: chunk });
        }
      }
      return;
    }

    if (type === "output") {
      const data = String(payload.data || "");
      if (data) {
        terminalRef.current?.write(data);
      }
      return;
    }

    if (type === "error") {
      const message = String(payload.message || "Terminal error.");
      statusRef.current = "error";
      emitUpdate({ status: "error", statusText: message });
      printSystemLine(message);
      return;
    }

    if (type === "exit") {
      const exitCode = Number(payload.exitCode);
      const message = Number.isFinite(exitCode)
        ? `Terminal exited with code ${exitCode}.`
        : "Terminal session exited.";
      statusRef.current = "exited";
      sessionIdRef.current = null;
      emitUpdate({
        status: "exited",
        statusText: message,
        sessionId: null
      });
      printSystemLine(message);
      return;
    }

    if (type === "closed") {
      const nextStatus = statusRef.current === "exited" ? "exited" : "closed";
      statusRef.current = nextStatus;
      sessionIdRef.current = null;
      emitUpdate({
        status: nextStatus,
        statusText: nextStatus === "exited" ? "Terminal session exited." : "Terminal session closed.",
        sessionId: null
      });
      return;
    }
  }, [emitUpdate, isActive, isDrawerOpen, printSystemLine]);

  const disconnectTerminal = useCallback((announce = false) => {
    connectionEpochRef.current += 1;
    pendingInputRef.current = [];

    if (sessionIdRef.current) {
      connectionRef.current?.send({ type: "close" });
    }

    connectionRef.current?.close();
    connectionRef.current = null;
    sessionIdRef.current = null;

    if (announce) {
      statusRef.current = "closed";
      emitUpdate({
        status: "closed",
        statusText: "Terminal disconnected.",
        sessionId: null
      });
      printSystemLine("Terminal disconnected.");
    }
  }, [emitUpdate, printSystemLine]);

  const connectTerminal = useCallback(() => {
    if (connectionRef.current) {
      return;
    }

    const epoch = connectionEpochRef.current + 1;
    connectionEpochRef.current = epoch;
    statusRef.current = "connecting";
    emitUpdate({
      status: "connecting",
      statusText: "Connecting terminal..."
    });

    let terminal: Terminal | null;
    try {
      terminal = ensureTerminal() ?? null;
    } catch (error) {
      statusRef.current = "error";
      emitUpdate({
        status: "error",
        statusText: `Could not start terminal: ${error instanceof Error ? error.message : String(error)}.`
      });
      return;
    }

    if (!terminal || connectionRef.current) {
      if (!terminal) {
        statusRef.current = "error";
        emitUpdate({
          status: "error",
          statusText: "Terminal container is not ready. Try again."
        });
      }
      return;
    }

    printSystemLine("Connecting terminal...");
    let receivedStructuredMessage = false;

    const connection = coreApi.subscribeDashboardTerminal({
      onOpen: () => {
        if (connectionEpochRef.current !== epoch || connectionRef.current !== connection) {
          return;
        }
        fitAddonRef.current?.fit();
        const didSend = connection.send({
          type: "start",
          projectId: tab.projectId || undefined,
          cols: terminal.cols || 120,
          rows: terminal.rows || 24
        });
        if (!didSend) {
          statusRef.current = "error";
          emitUpdate({
            status: "error",
            statusText: "Could not start terminal session."
          });
          printSystemLine("Could not start terminal session.");
        }
      },
      onMessage: (payload) => {
        if (connectionEpochRef.current !== epoch || connectionRef.current !== connection) {
          return;
        }
        receivedStructuredMessage = true;
        handleServerMessage(payload);
      },
      onError: () => {
        if (connectionEpochRef.current !== epoch || connectionRef.current !== connection) {
          return;
        }
        if (statusRef.current === "ready") {
          statusRef.current = "error";
          emitUpdate({
            status: "error",
            statusText: "Terminal connection error."
          });
        }
      },
      onClose: (details) => {
        if (connectionEpochRef.current !== epoch || connectionRef.current !== connection) {
          return;
        }

        connectionRef.current = null;
        sessionIdRef.current = null;

        const closeCode = Number.isFinite(details?.code) ? String(details?.code) : "n/a";
        const closeReason = (details?.reason || "").trim();

        if (!receivedStructuredMessage && statusRef.current === "connecting") {
          statusRef.current = "error";
          const diagnostics = closeReason
            ? `WS closed before ready (code ${closeCode}, reason: ${closeReason}).`
            : `WS closed before ready (code ${closeCode}).`;
          emitUpdate({
            status: "error",
            statusText: diagnostics,
            sessionId: null
          });
          printSystemLine(diagnostics);
          return;
        }

        if (statusRef.current !== "exited" && statusRef.current !== "error") {
          statusRef.current = "closed";
          const diagnostics = closeReason
            ? `Terminal connection closed (code ${closeCode}, reason: ${closeReason}).`
            : `Terminal connection closed (code ${closeCode}).`;
          emitUpdate({
            status: "closed",
            statusText: diagnostics,
            sessionId: null
          });
        }
      }
    });

    connectionRef.current = connection;
  }, [coreApi, emitUpdate, ensureTerminal, handleServerMessage, printSystemLine, tab.projectId]);

  useEffect(() => {
    ensureTerminal();
    connectTerminal();
  }, [connectTerminal, ensureTerminal]);

  useEffect(() => {
    if (!isDrawerOpen || !isActive) return;
    window.setTimeout(() => {
      fitAddonRef.current?.fit();
      terminalRef.current?.focus();
    }, 30);
  }, [drawerHeight, isActive, isDrawerOpen]);

  useEffect(() => {
    const onWindowResize = () => {
      if (!isDrawerOpen || !isActive) return;
      fitAddonRef.current?.fit();
    };
    window.addEventListener("resize", onWindowResize);
    return () => window.removeEventListener("resize", onWindowResize);
  }, [isActive, isDrawerOpen]);

  useEffect(() => {
    const onBeforeUnload = () => {
      disconnectTerminal(false);
    };
    window.addEventListener("beforeunload", onBeforeUnload);
    return () => window.removeEventListener("beforeunload", onBeforeUnload);
  }, [disconnectTerminal]);

  useEffect(() => {
    return () => {
      disconnectTerminal(false);
      terminalRef.current?.dispose();
      terminalRef.current = null;
      fitAddonRef.current = null;
    };
  }, [disconnectTerminal]);

  return (
    <div className={`terminal-pane ${isActive ? "active" : "inactive"}`}>
      <div
        ref={containerRef}
        className="terminal-drawer-screen"
        onMouseDown={() => {
          terminalRef.current?.focus();
        }}
      />
    </div>
  );
}

export function TerminalDrawer({
  coreApi,
  currentProjectId,
  currentProjectRepoPath,
  closedHostElement = null,
  isSidebarCompact = true
}: TerminalDrawerProps) {
  const [isOpen, setIsOpen] = useState(loadStoredDrawerOpen);
  const [drawerHeight, setDrawerHeight] = useState(loadStoredDrawerHeight);
  const [tabs, setTabs] = useState<TerminalTabState[]>([]);
  const [activeTabId, setActiveTabId] = useState<string | null>(null);
  const [isResizing, setIsResizing] = useState(false);
  const drawerRef = useRef<HTMLDivElement | null>(null);
  const dragOriginRef = useRef<{ startY: number; startHeight: number } | null>(null);
  const tabCounterRef = useRef(0);

  useEffect(() => {
    try {
      window.localStorage.setItem(DRAWER_OPEN_STORAGE_KEY, String(isOpen));
    } catch {
      // Ignore local storage failures in private browsing contexts.
    }
  }, [isOpen]);

  useEffect(() => {
    try {
      window.localStorage.setItem(DRAWER_HEIGHT_STORAGE_KEY, String(drawerHeight));
    } catch {
      // Ignore local storage failures in private browsing contexts.
    }
  }, [drawerHeight]);

  const addTerminalTab = useCallback(() => {
    tabCounterRef.current += 1;
    const nextTab = makeTerminalTab(tabCounterRef.current, currentProjectId, currentProjectRepoPath);
    setTabs((current) => [...current, nextTab]);
    setActiveTabId(nextTab.id);
    setIsOpen(true);
  }, [currentProjectId, currentProjectRepoPath]);

  const updateTab = useCallback((tabId: string, patch: Partial<TerminalTabState>) => {
    setTabs((current) => current.map((tab) => (tab.id === tabId ? { ...tab, ...patch } : tab)));
  }, []);

  const closeTab = useCallback((tabId: string) => {
    setTabs((current) => {
      const index = current.findIndex((tab) => tab.id === tabId);
      if (index === -1) {
        return current;
      }
      const next = current.filter((tab) => tab.id !== tabId);
      if (next.length === 0) {
        setActiveTabId(null);
        setIsOpen(false);
        return next;
      }
      if (activeTabId === tabId) {
        const fallback = next[Math.max(0, index - 1)] ?? next[0];
        setActiveTabId(fallback.id);
      }
      return next;
    });
  }, [activeTabId]);

  useEffect(() => {
    if (!isOpen || tabs.length > 0) return;
    addTerminalTab();
  }, [addTerminalTab, isOpen, tabs.length]);

  useEffect(() => {
    if (tabs.length === 0) {
      if (activeTabId !== null) {
        setActiveTabId(null);
      }
      return;
    }
    if (!activeTabId || !tabs.some((tab) => tab.id === activeTabId)) {
      setActiveTabId(tabs[tabs.length - 1].id);
    }
  }, [activeTabId, tabs]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const isShortcut = (event.metaKey || event.ctrlKey) && !event.shiftKey && !event.altKey && event.key.toLowerCase() === "j";
      if (!isShortcut || isEditableTarget(event.target)) {
        return;
      }
      event.preventDefault();
      setIsOpen((current) => !current);
    };

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  useEffect(() => {
    if (!isResizing) return;

    const onMouseMove = (event: MouseEvent) => {
      const origin = dragOriginRef.current;
      if (!origin) return;
      const deltaY = origin.startY - event.clientY;
      setDrawerHeight(clampDrawerHeight(origin.startHeight + deltaY));
    };

    const onMouseUp = () => {
      dragOriginRef.current = null;
      setIsResizing(false);
    };

    window.addEventListener("mousemove", onMouseMove);
    window.addEventListener("mouseup", onMouseUp);
    return () => {
      window.removeEventListener("mousemove", onMouseMove);
      window.removeEventListener("mouseup", onMouseUp);
    };
  }, [isResizing]);

  const activeTab = tabs.find((tab) => tab.id === activeTabId) ?? null;
  const activeStatus = activeTab?.status ?? "idle";
  const statusText = activeTab?.statusText ?? "Press Cmd+J to open the terminal drawer.";
  const contextLabel = activeTab?.activeCwd || activeTab?.projectRepoPath || currentProjectRepoPath || "workspace root";
  const dockedToSidebarCollapsed = Boolean(closedHostElement && !isOpen);
  const closedChromeHeight = dockedToSidebarCollapsed ? 0 : 44;

  useEffect(() => {
    const reservedBottom = dockedToSidebarCollapsed ? 0 : isOpen ? drawerHeight : closedChromeHeight;
    document.documentElement.style.setProperty("--terminal-drawer-reserved-bottom", `${reservedBottom}px`);
    return () => {
      document.documentElement.style.removeProperty("--terminal-drawer-reserved-bottom");
    };
  }, [closedChromeHeight, dockedToSidebarCollapsed, drawerHeight, isOpen]);

  const compactTerminalDock = dockedToSidebarCollapsed ? (
    <button
      type="button"
      className="sidebar-terminal-dock"
      onClick={() => setIsOpen(true)}
      title={statusText}
      aria-label="Open terminal"
    >
      <span className="material-symbols-rounded" aria-hidden="true">
        terminal
      </span>
      {!isSidebarCompact ? (
        <span className="sidebar-terminal-dock-label">
          {tabs.length > 1 ? `Terminal (${tabs.length})` : "Terminal"}
        </span>
      ) : null}
      <span className={`sidebar-terminal-dock-status terminal-drawer-status terminal-drawer-status-${activeStatus}`}>
        {tabs.length > 1 ? `${tabs.length} tabs` : activeStatus}
      </span>
    </button>
  ) : null;

  return (
    <>
      {compactTerminalDock && closedHostElement
        ? createPortal(compactTerminalDock, closedHostElement)
        : null}
      <div
        ref={drawerRef}
        className={`terminal-drawer ${isOpen ? "open" : "closed"}${
          dockedToSidebarCollapsed ? " terminal-drawer--docked-collapsed" : ""
        }`}
        style={{ height: isOpen ? `${drawerHeight}px` : closedChromeHeight }}
      >
        <button
          type="button"
          className="terminal-drawer-resize-handle"
          aria-label="Resize terminal drawer"
          style={dockedToSidebarCollapsed ? { display: "none" } : undefined}
          onMouseDown={(event) => {
            if (dockedToSidebarCollapsed) {
              return;
            }
            event.preventDefault();
            dragOriginRef.current = {
              startY: event.clientY,
              startHeight: drawerHeight
            };
            setIsResizing(true);
          }}
        />
        <div className="terminal-drawer-header" style={dockedToSidebarCollapsed ? { display: "none" } : undefined}>
          <button
            type="button"
            className="terminal-drawer-window-action"
            onClick={() => setIsOpen((current) => !current)}
            aria-label={isOpen ? "Collapse terminal" : "Expand terminal"}
          >
            <span className="material-symbols-rounded" aria-hidden="true">
              terminal
            </span>
          </button>

          <div className="terminal-tab-strip" role="tablist" aria-label="Terminal tabs">
            {tabs.map((tab) => {
              const isSelected = tab.id === activeTabId;
              return (
                <div key={tab.id} className={`terminal-tab ${isSelected ? "active" : ""}`}>
                  <button
                    type="button"
                    role="tab"
                    aria-selected={isSelected}
                    className="terminal-tab-select"
                    onClick={() => {
                      setActiveTabId(tab.id);
                      setIsOpen(true);
                    }}
                  >
                    <span className={tabStatusClass(tab.status)} aria-hidden="true" />
                    <span className="terminal-tab-label">{tab.label}</span>
                  </button>
                  {tabs.length > 1 ? (
                    <button
                      type="button"
                      className="terminal-tab-close"
                      onClick={() => closeTab(tab.id)}
                      aria-label={`Close ${tab.label}`}
                    >
                      <span className="material-symbols-rounded" aria-hidden="true">
                        close
                      </span>
                    </button>
                  ) : null}
                </div>
              );
            })}
          </div>

          <button
            type="button"
            className="terminal-drawer-plus"
            onClick={addTerminalTab}
            aria-label="Open new terminal"
            title="Open new terminal"
          >
            <span className="material-symbols-rounded" aria-hidden="true">
              add
            </span>
          </button>

          <button
            type="button"
            className="terminal-drawer-window-action"
            onClick={() => setIsOpen(false)}
            aria-label="Close terminal drawer"
          >
            <span className="material-symbols-rounded" aria-hidden="true">
              close
            </span>
          </button>
        </div>

        <div className="terminal-drawer-body">
          <div className="terminal-drawer-info">
            <span className="terminal-drawer-status-text">{statusText}</span>
            <div className="terminal-drawer-info-trail">
              <span className="terminal-drawer-cwd" title={contextLabel}>{contextLabel}</span>
              {activeTab?.activeShell ? <span className="terminal-drawer-shell">{activeTab.activeShell}</span> : null}
              {activeTab?.sessionId ? <code>{activeTab.sessionId}</code> : null}
            </div>
          </div>

          <div className="terminal-drawer-stage">
            {tabs.map((tab) => (
              <TerminalPane
                key={tab.id}
                tab={tab}
                coreApi={coreApi}
                isActive={tab.id === activeTabId}
                isDrawerOpen={isOpen}
                drawerHeight={drawerHeight}
                onUpdate={updateTab}
              />
            ))}
          </div>
        </div>
      </div>
    </>
  );
}
