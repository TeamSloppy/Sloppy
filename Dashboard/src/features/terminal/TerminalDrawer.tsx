import React, { useCallback, useEffect, useRef, useState } from "react";
import type { CoreApi, DashboardTerminalConnection } from "../../shared/api/coreApi";

const DRAWER_OPEN_STORAGE_KEY = "sloppy_terminal_drawer_open";
const DRAWER_HEIGHT_STORAGE_KEY = "sloppy_terminal_drawer_height";
const DEFAULT_DRAWER_HEIGHT = 320;
const MIN_DRAWER_HEIGHT = 220;
const MAX_DRAWER_HEIGHT_RATIO = 0.78;

type TerminalStatus = "idle" | "connecting" | "ready" | "closed" | "error" | "exited";

interface BrowserTerminal {
  cols: number;
  rows: number;
  open: (element: HTMLElement) => void;
  focus: () => void;
  write: (data: string) => void;
  writeln: (data: string) => void;
  clear: () => void;
  dispose: () => void;
  loadAddon: (addon: BrowserFitAddon) => void;
  onData: (handler: (data: string) => void) => void;
  onResize: (handler: (size: { cols: number; rows: number }) => void) => void;
}

interface BrowserFitAddon {
  fit: () => void;
}

let terminalAssetsPromise: Promise<void> | null = null;

interface TerminalDrawerProps {
  coreApi: CoreApi;
  currentProjectId: string | null;
  currentProjectRepoPath: string | null;
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

function ensureTerminalStyles() {
  if (document.head.querySelector("link[data-sloppy-xterm='true']")) {
    return;
  }
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = "/vendor/xterm/xterm.css";
  link.dataset.sloppyXterm = "true";
  document.head.appendChild(link);
}

function loadScript(src: string) {
  return new Promise<void>((resolve, reject) => {
    const existing = document.querySelector(`script[data-sloppy-src="${src}"]`) as HTMLScriptElement | null;
    if (existing) {
      if (existing.dataset.loaded === "true") {
        resolve();
        return;
      }
      existing.addEventListener("load", () => resolve(), { once: true });
      existing.addEventListener("error", () => reject(new Error(`Failed to load ${src}`)), { once: true });
      return;
    }

    const script = document.createElement("script");
    script.src = src;
    script.async = true;
    script.dataset.sloppySrc = src;
    script.addEventListener("load", () => {
      script.dataset.loaded = "true";
      resolve();
    }, { once: true });
    script.addEventListener("error", () => reject(new Error(`Failed to load ${src}`)), { once: true });
    document.head.appendChild(script);
  });
}

function ensureTerminalAssets() {
  if (window.Terminal && window.FitAddon) {
    ensureTerminalStyles();
    return Promise.resolve();
  }
  if (!terminalAssetsPromise) {
    ensureTerminalStyles();
    terminalAssetsPromise = Promise.all([
      loadScript("/vendor/xterm/xterm.js"),
      loadScript("/vendor/xterm/addon-fit.js")
    ]).then(() => undefined);
  }
  return terminalAssetsPromise;
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

export function TerminalDrawer({ coreApi, currentProjectId, currentProjectRepoPath }: TerminalDrawerProps) {
  const [isOpen, setIsOpen] = useState(loadStoredDrawerOpen);
  const [drawerHeight, setDrawerHeight] = useState(loadStoredDrawerHeight);
  const [status, setStatus] = useState<TerminalStatus>("idle");
  const [statusText, setStatusText] = useState("Press Cmd+J to open the terminal drawer.");
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [activeCwd, setActiveCwd] = useState<string | null>(null);
  const [activeShell, setActiveShell] = useState<string | null>(null);
  const [isResizing, setIsResizing] = useState(false);
  const containerRef = useRef<HTMLDivElement | null>(null);
  const drawerRef = useRef<HTMLDivElement | null>(null);
  const terminalRef = useRef<BrowserTerminal | null>(null);
  const fitAddonRef = useRef<BrowserFitAddon | null>(null);
  const connectionRef = useRef<DashboardTerminalConnection | null>(null);
  const statusRef = useRef<TerminalStatus>("idle");
  const sessionIdRef = useRef<string | null>(null);
  const projectIdRef = useRef<string | null>(currentProjectId);
  const projectRepoPathRef = useRef<string | null>(currentProjectRepoPath);
  const dragOriginRef = useRef<{ startY: number; startHeight: number } | null>(null);
  const reconnectTimerRef = useRef<number | null>(null);

  useEffect(() => {
    statusRef.current = status;
  }, [status]);

  useEffect(() => {
    sessionIdRef.current = sessionId;
  }, [sessionId]);

  useEffect(() => {
    projectIdRef.current = currentProjectId;
  }, [currentProjectId]);

  useEffect(() => {
    projectRepoPathRef.current = currentProjectRepoPath;
  }, [currentProjectRepoPath]);

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
    if (!window.Terminal || !window.FitAddon) {
      return null;
    }

    const terminal = new window.Terminal({
      cursorBlink: true,
      cursorStyle: "block",
      fontFamily: "\"SF Mono\", \"Fira Code\", monospace",
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
    const fitAddon = new window.FitAddon();
    fitAddonRef.current = fitAddon;
    terminal.loadAddon(fitAddon);
    terminal.open(containerRef.current);
    fitAddon.fit();
    terminal.focus();

    terminal.onData((data) => {
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
      setSessionId(nextSessionId);
      setActiveCwd(cwd);
      setActiveShell(shell);
      setStatus("ready");
      setStatusText(cwd ? `Connected to ${cwd}` : "Terminal connected.");
      terminalRef.current?.focus();
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
      setStatus("error");
      setStatusText(message);
      printSystemLine(message);
      return;
    }

    if (type === "exit") {
      const exitCode = Number(payload.exitCode);
      const message = Number.isFinite(exitCode)
        ? `Terminal exited with code ${exitCode}.`
        : "Terminal session exited.";
      setStatus("exited");
      setStatusText(message);
      setSessionId(null);
      printSystemLine(message);
      return;
    }

    if (type === "closed") {
      setStatus((current) => (current === "exited" ? current : "closed"));
      setStatusText((current) => (current === "Terminal session exited." ? current : "Terminal session closed."));
      setSessionId(null);
      return;
    }

    if (type === "pong") {
      return;
    }
  }, [printSystemLine]);

  const disconnectTerminal = useCallback((announce = false) => {
    if (reconnectTimerRef.current != null) {
      window.clearTimeout(reconnectTimerRef.current);
      reconnectTimerRef.current = null;
    }

    if (sessionIdRef.current) {
      connectionRef.current?.send({ type: "close" });
    }
    connectionRef.current?.close();
    connectionRef.current = null;
    setSessionId(null);
    setActiveCwd(null);
    setActiveShell(null);
    if (announce) {
      setStatus("closed");
      setStatusText("Terminal disconnected.");
      printSystemLine("Terminal disconnected.");
    }
  }, [printSystemLine]);

  const connectTerminal = useCallback(() => {
    if (connectionRef.current) {
      return;
    }

    setStatus("connecting");
    setStatusText("Connecting terminal...");

    void ensureTerminalAssets()
      .then(() => {
        const terminal = ensureTerminal();
        if (!terminal || connectionRef.current) {
          return;
        }

        printSystemLine("Connecting terminal...");
        let receivedStructuredMessage = false;
        const connection = coreApi.subscribeDashboardTerminal({
          onOpen: () => {
            fitAddonRef.current?.fit();
            const didSend = connection.send({
              type: "start",
              projectId: projectIdRef.current || undefined,
              cols: terminal.cols || 120,
              rows: terminal.rows || 24
            });
            if (!didSend) {
              setStatus("error");
              setStatusText("Could not start terminal session.");
              printSystemLine("Could not start terminal session.");
            }
          },
          onMessage: (payload) => {
            receivedStructuredMessage = true;
            handleServerMessage(payload);
          },
          onError: () => {
            if (statusRef.current === "ready") {
              setStatus("error");
              setStatusText("Terminal connection error.");
            }
          },
          onClose: () => {
            connectionRef.current = null;
            setSessionId(null);
            if (!receivedStructuredMessage && statusRef.current === "connecting") {
              setStatus("error");
              setStatusText("Terminal is unavailable. Enable it in Settings > UI, then reconnect.");
              printSystemLine("Terminal is unavailable. Enable it in Settings > UI, then reconnect.");
              return;
            }
            if (statusRef.current !== "exited" && statusRef.current !== "error") {
              setStatus("closed");
              setStatusText("Terminal connection closed.");
            }
          }
        });

        connectionRef.current = connection;
      })
      .catch(() => {
        setStatus("error");
        setStatusText("Failed to load terminal assets.");
      });
  }, [coreApi, ensureTerminal, handleServerMessage, printSystemLine]);

  const reconnectTerminal = useCallback(() => {
    disconnectTerminal(false);
    reconnectTimerRef.current = window.setTimeout(() => {
      reconnectTimerRef.current = null;
      connectTerminal();
    }, 60);
  }, [connectTerminal, disconnectTerminal]);

  useEffect(() => {
    if (!isOpen) return;
    fitAddonRef.current?.fit();
    if (!connectionRef.current) {
      connectTerminal();
    }
    window.setTimeout(() => {
      fitAddonRef.current?.fit();
      terminalRef.current?.focus();
    }, 30);
  }, [connectTerminal, isOpen, drawerHeight]);

  useEffect(() => {
    const onWindowResize = () => {
      fitAddonRef.current?.fit();
    };
    window.addEventListener("resize", onWindowResize);
    return () => window.removeEventListener("resize", onWindowResize);
  }, []);

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
    const onBeforeUnload = () => {
      disconnectTerminal(false);
    };
    window.addEventListener("beforeunload", onBeforeUnload);
    return () => window.removeEventListener("beforeunload", onBeforeUnload);
  }, [disconnectTerminal]);

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
      fitAddonRef.current?.fit();
    };

    window.addEventListener("mousemove", onMouseMove);
    window.addEventListener("mouseup", onMouseUp);
    return () => {
      window.removeEventListener("mousemove", onMouseMove);
      window.removeEventListener("mouseup", onMouseUp);
    };
  }, [isResizing]);

  useEffect(() => {
    return () => {
      disconnectTerminal(false);
      terminalRef.current?.dispose();
      terminalRef.current = null;
      fitAddonRef.current = null;
    };
  }, [disconnectTerminal]);

  const contextLabel = activeCwd || projectRepoPathRef.current || "workspace root";

  return (
    <div
      ref={drawerRef}
      className={`terminal-drawer ${isOpen ? "open" : "closed"}`}
      style={{ height: isOpen ? `${drawerHeight}px` : "44px" }}
    >
      <button
        type="button"
        className="terminal-drawer-resize-handle"
        aria-label="Resize terminal drawer"
        onMouseDown={(event) => {
          event.preventDefault();
          dragOriginRef.current = {
            startY: event.clientY,
            startHeight: drawerHeight
          };
          setIsResizing(true);
        }}
      />
      <div className="terminal-drawer-header">
        <button
          type="button"
          className="terminal-drawer-toggle"
          onClick={() => setIsOpen((current) => !current)}
        >
          <span className="material-symbols-rounded" aria-hidden="true">
            {isOpen ? "keyboard_arrow_down" : "terminal"}
          </span>
          <span className="terminal-drawer-title">Terminal</span>
          <span className={`terminal-drawer-status terminal-drawer-status-${status}`}>{status}</span>
        </button>
        <div className="terminal-drawer-meta">
          <span className="terminal-drawer-cwd" title={contextLabel}>{contextLabel}</span>
          {activeShell ? <span className="terminal-drawer-shell">{activeShell}</span> : null}
        </div>
        <div className="terminal-drawer-actions">
          <button type="button" className="text-button" onClick={() => terminalRef.current?.clear()}>
            Clear
          </button>
          <button type="button" className="text-button" onClick={reconnectTerminal}>
            Reconnect
          </button>
          <button type="button" className="text-button" onClick={() => disconnectTerminal(true)}>
            Disconnect
          </button>
        </div>
      </div>
      <div className="terminal-drawer-body">
        <div className="terminal-drawer-info">
          <span>{statusText}</span>
          {sessionId ? <code>{sessionId}</code> : <span>`Cmd+J`</span>}
        </div>
        <div ref={containerRef} className="terminal-drawer-screen" />
      </div>
    </div>
  );
}
