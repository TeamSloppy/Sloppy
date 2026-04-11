import React, { useEffect, useMemo, useState } from "react";
import { createDependencies } from "./app/di/createDependencies";
import { DEFAULT_AGENT_TAB, DEFAULT_PROJECT_TAB } from "./app/routing/dashboardRouteAdapter";
import { useDashboardRoute } from "./app/routing/useDashboardRoute";
import { SidebarView } from "./components/SidebarView";
import { NotificationProvider } from "./features/notifications/NotificationContext";
import { NotificationBell } from "./features/notifications/NotificationBell";
import { NotificationToastContainer } from "./features/notifications/NotificationToast";
import { useNotificationSocket } from "./features/notifications/useNotificationSocket";
import { OnboardingView } from "./features/onboarding/OnboardingView";
import { useRuntimeOverview } from "./features/runtime-overview/model/useRuntimeOverview";
import { UpdateBanner } from "./features/updates/UpdateBanner";
import { useUpdateCheck } from "./features/updates/useUpdateCheck";
import { AgentsView } from "./views/AgentsView";
import { ActorsView } from "./views/ActorsView";
import { VisorChatView } from "./features/visor/VisorChatView";
import { ConfigView } from "./views/ConfigView";
import { LogsView } from "./views/LogsView";
import { DebugView } from "./views/DebugView";
import { NotFoundView } from "./views/NotFoundView";
import { ProjectsView } from "./views/ProjectsView";
import { ChannelSessionView } from "./views/ChannelSessionView";
import { RuntimeOverviewView } from "./views/RuntimeOverviewView";
import {
  getStoredApiBaseOverride,
  normalizeApiBaseInput,
  resolveApiBase,
  setStoredApiBaseOverride
} from "./shared/api/httpClient";
import { fetchProjects } from "./api";
import { ProjectChatsView } from "./features/project-chats/ProjectChatsView";

interface SidebarItem {
  id: string;
  label: {
    icon: string;
    title: string;
  };
  content: React.ReactNode;
}

type AnyRecord = Record<string, unknown>;

function DashboardShell({ dependencies, debugEnabled }: { dependencies: ReturnType<typeof createDependencies>; debugEnabled: boolean }) {
  const runtime = useRuntimeOverview(dependencies.coreApi);
  const { route, setSection, setConfigSection, setProjectRoute, setAgentRoute, setSessionRoute, setChatsRoute } =
    useDashboardRoute();
  const [sidebarCompact, setSidebarCompact] = useState(true);
  const [mobileSidebarOpen, setMobileSidebarOpen] = useState(false);
  const [sidebarProjects, setSidebarProjects] = useState<AnyRecord[]>([]);
  const { status: updateStatus } = useUpdateCheck();
  useNotificationSocket();

  useEffect(() => {
    document.body.classList.toggle("mobile-menu-open", mobileSidebarOpen);
    return () => {
      document.body.classList.remove("mobile-menu-open");
    };
  }, [mobileSidebarOpen]);

  useEffect(() => {
    let cancelled = false;
    fetchProjects()
      .then((list) => {
        if (!cancelled && Array.isArray(list)) {
          setSidebarProjects(list);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setSidebarProjects([]);
        }
      });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    const mediaQuery = window.matchMedia("(min-width: 1001px)");
    function handleChange(event: MediaQueryListEvent | MediaQueryList) {
      if (event.matches) {
        setMobileSidebarOpen(false);
      }
    }
    handleChange(mediaQuery);

    if (typeof mediaQuery.addEventListener === "function") {
      mediaQuery.addEventListener("change", handleChange);
      return () => mediaQuery.removeEventListener("change", handleChange);
    }

    mediaQuery.addListener(handleChange);
    return () => mediaQuery.removeListener(handleChange);
  }, []);

  function onSelectSidebar(nextSection: string) {
    setSection(nextSection);
    setMobileSidebarOpen(false);
  }

  function onAgentRouteChange(
    agentId: string | null,
    agentTab: string | null = DEFAULT_AGENT_TAB,
    initialChatSessionId: string | null = null
  ) {
    setAgentRoute(agentId, agentTab, initialChatSessionId);
  }

  function onProjectRouteChange(
    projectId: string | null,
    projectTab: string | null = DEFAULT_PROJECT_TAB,
    projectTaskReference: string | null = null
  ) {
    setProjectRoute(projectId, projectTab, projectTaskReference);
  }

  const runtimeContent = (
    <RuntimeOverviewView
      workers={runtime.workers}
      events={runtime.events}
      onNavigateToProject={(projectId: string) => {
        setSection("projects");
        if (projectId) {
          onProjectRouteChange(projectId, DEFAULT_PROJECT_TAB, null);
        }
      }}
      onNavigateToChannelSession={(sessionId: string) => {
        setSessionRoute(sessionId);
      }}
      onNavigateToBots={() => setSection("agents")}
      onNavigateToAgent={(agentId: string) => {
        setSection("agents");
        onAgentRouteChange(agentId, "overview");
      }}
    />
  );

  const sidebarItems: SidebarItem[] = [
    {
      id: "overview",
      label: { icon: "dashboard", title: "Overview" },
      content: runtimeContent
    },
    {
      id: "projects",
      label: { icon: "folder", title: "Projects" },
      content: (
        <ProjectsView
          channelState={runtime.channelState}
          workers={runtime.workers}
          bulletins={runtime.bulletins}
          routeProjectId={route.projectId}
          routeProjectTab={route.projectTab}
          routeProjectTaskReference={route.projectTaskReference}
          onRouteProjectChange={onProjectRouteChange as any}
          onNavigateToChannelSession={(sessionId: string) => {
            setSessionRoute(sessionId);
          }}
          onNavigateToAgentChatSession={(agentId: string, sessionId: string) => {
            onAgentRouteChange(agentId, "chat", sessionId);
          }}
        />
      )
    },
    {
      id: "agents",
      label: { icon: "support_agent", title: "Agents" },
      content: (
        <AgentsView
          routeAgentId={route.agentId}
          routeTab={route.agentTab}
          routeAgentInitialChatSessionId={route.agentInitialChatSessionId}
          onRouteChange={onAgentRouteChange}
          onNavigateToChannelSession={(sessionId: string) => {
            setSessionRoute(sessionId);
          }}
        />
      )
    },
    {
      id: "actors",
      label: { icon: "group", title: "Actors" },
      content: <ActorsView />
    },
    {
      id: "visor",
      label: { icon: "visibility", title: "Visor" },
      content: <VisorChatView />
    },
    {
      id: "config",
      label: { icon: "settings", title: "Settings" },
      content: <ConfigView sectionId={route.configSection} onSectionChange={setConfigSection} />
    },
    {
      id: "logs",
      label: { icon: "description", title: "Logs" },
      content: <LogsView coreApi={dependencies.coreApi} />
    },
    ...(debugEnabled
      ? [{
          id: "debug" as const,
          label: { icon: "bug_report", title: "Debug" },
          content: <DebugView coreApi={dependencies.coreApi} />
        }]
      : [])
  ];

  const isNotFound = route.section === "not_found";
  const navHighlightItem =
    sidebarItems.find((item) => item.id === (route.section === "chats" ? "projects" : route.section)) ||
    sidebarItems[0];
  const pageContent = isNotFound ? (
    <NotFoundView />
  ) : route.section === "sessions" ? (
    <ChannelSessionView
      sessionId={route.sessionId}
      onNavigateBack={() => setSection("overview")}
    />
  ) : route.section === "chats" ? (
    <ProjectChatsView route={route} setChatsRoute={setChatsRoute} projects={sidebarProjects} />
  ) : (
    (sidebarItems.find((item) => item.id === route.section) || sidebarItems[0]).content
  );

  return (
    <div className="layout">
      <SidebarView
        items={sidebarItems}
        activeItemId={navHighlightItem.id}
        isCompact={sidebarCompact}
        onToggleCompact={() => setSidebarCompact((value) => !value)}
        onSelect={onSelectSidebar}
        isMobileOpen={mobileSidebarOpen}
        onRequestClose={() => setMobileSidebarOpen(false)}
        projectRailProjects={sidebarProjects}
        selectedChatProjectId={route.section === "chats" ? route.chatProjectId : null}
        onSelectChatProject={(projectId: string) => {
          setChatsRoute(projectId, null, null);
        }}
        footer={
          <>
            <a
              href="https://docs.sloppy.team"
              target="_blank"
              rel="noopener noreferrer"
              className="sidebar-docs-link"
              title="Documentation"
            >
              <span className="material-symbols-rounded sidebar-icon" aria-hidden="true">
                menu_book
              </span>
              {!sidebarCompact && <span className="sidebar-docs-label">[ DOCS ]</span>}
            </a>
            <NotificationBell
              isCompact={sidebarCompact}
              onNavigateToAgent={(agentId: string, sessionId?: string) => {
                onAgentRouteChange(agentId, "chat", sessionId ?? null);
              }}
            />
          </>
        }
      />
      <button
        type="button"
        className={`sidebar-mobile-overlay ${mobileSidebarOpen ? "open" : ""}`}
        onClick={() => setMobileSidebarOpen(false)}
        aria-label="Close menu"
      />

      <div className={`page ${navHighlightItem.id === "config" ? "page-config" : ""}`} style={{ position: "relative" }}>
        <div
          style={{
            position: "absolute",
            top: "2px",
            right: "20px",
            fontSize: "10px",
            color: "var(--accent)",
            zIndex: 1000,
            pointerEvents: "none",
            opacity: 0.6,
            letterSpacing: "0.1em"
          }}
        >
          [&gt;_ SECURE_SESSION_ACTIVE // PID: 9284]
        </div>
        <div
          style={{
            position: "absolute",
            bottom: "10px",
            right: "20px",
            fontSize: "10px",
            color: "var(--muted)",
            zIndex: 1000,
            pointerEvents: "none",
            opacity: 0.5
          }}
        >
          UPLINK: ESTABLISHED / LATENCY: 12MS
        </div>
        <button
          type="button"
          className="mobile-page-menu-button"
          onClick={() =>
            setMobileSidebarOpen((value) => {
              const next = !value;
              if (next) {
                setSidebarCompact(false);
              }
              return next;
            })
          }
          aria-label={mobileSidebarOpen ? "Close menu" : "Open menu"}
          aria-expanded={mobileSidebarOpen}
        >
          <span className="material-symbols-rounded" aria-hidden="true">
            menu
          </span>
        </button>
        {updateStatus && <UpdateBanner status={updateStatus} />}
        {pageContent}
      </div>
      <NotificationToastContainer />
    </div>
  );
}

export function App() {
  const dependencies = useMemo(() => createDependencies(), []);
  const [bootState, setBootState] = useState<{
    isLoading: boolean;
    config: AnyRecord | null;
    error: string;
  }>({
    isLoading: true,
    config: null,
    error: ""
  });
  const [apiBaseInput, setApiBaseInput] = useState(() => getStoredApiBaseOverride() || resolveApiBase());
  const [apiBaseError, setApiBaseError] = useState("");
  const [bootAttempt, setBootAttempt] = useState(0);

  useEffect(() => {
    let isCancelled = false;

    async function runBootstrap() {
      setBootState((current) => ({
        ...current,
        isLoading: true,
        error: ""
      }));

      try {
        const config = await dependencies.coreApi.fetchRuntimeConfig();
        if (isCancelled) {
          return;
        }

        if (!config) {
          setBootState({
            isLoading: false,
            config: null,
            error: "Failed to load runtime config."
          });
          return;
        }

        setBootState({
          isLoading: false,
          config,
          error: ""
        });
      } catch {
        if (isCancelled) {
          return;
        }
        setBootState({
          isLoading: false,
          config: null,
          error: "Failed to load runtime config."
        });
      }
    }

    void runBootstrap();

    return () => {
      isCancelled = true;
    };
  }, [dependencies, bootAttempt]);

  function retryBootstrap() {
    setApiBaseError("");
    setBootAttempt((value) => value + 1);
  }

  function handleApiBaseConnect() {
    const trimmed = apiBaseInput.trim();
    if (!trimmed) {
      setStoredApiBaseOverride("");
      setApiBaseInput(resolveApiBase());
      setApiBaseError("");
      retryBootstrap();
      return;
    }

    const normalized = normalizeApiBaseInput(trimmed);
    if (!normalized) {
      setApiBaseError("Enter host:port or full http(s) URL.");
      return;
    }

    setStoredApiBaseOverride(normalized);
    setApiBaseInput(normalized);
    setApiBaseError("");
    retryBootstrap();
  }

  if (bootState.isLoading) {
    return (
      <div className="onboarding-loading-shell">
        <div className="onboarding-loading-card">
          <span className="onboarding-loading-kicker">Sloppy init</span>
          <strong>Loading runtime config...</strong>
        </div>
      </div>
    );
  }

  if (bootState.error || !bootState.config) {
    return (
      <div className="onboarding-loading-shell">
        <div className="onboarding-loading-card onboarding-loading-card-error">
          <span className="onboarding-loading-kicker">Sloppy init</span>
          <strong>{bootState.error || "Runtime config is unavailable."}</strong>
          <div className="onboarding-loading-form">
            <label className="onboarding-loading-label" htmlFor="sloppy-api-base">
              Core API URL
            </label>
            <input
              id="sloppy-api-base"
              className="onboarding-loading-input"
              type="text"
              inputMode="url"
              autoCapitalize="off"
              autoCorrect="off"
              spellCheck={false}
              placeholder="192.168.1.50:25101"
              value={apiBaseInput}
              onChange={(event) => {
                setApiBaseInput(event.target.value);
                if (apiBaseError) {
                  setApiBaseError("");
                }
              }}
              onKeyDown={(event) => {
                if (event.key === "Enter") {
                  event.preventDefault();
                  handleApiBaseConnect();
                }
              }}
            />
            <span className="onboarding-loading-hint">
              Enter `ip:port` or a full `http://` / `https://` URL for `sloppy-core`.
            </span>
            {apiBaseError ? <span className="onboarding-loading-error">{apiBaseError}</span> : null}
          </div>
          <div className="onboarding-loading-actions">
            <button
              type="button"
              className="onboarding-ghost-button"
              onClick={retryBootstrap}
            >
              Retry
            </button>
            <button
              type="button"
              className="onboarding-primary-button"
              onClick={handleApiBaseConnect}
            >
              Connect
            </button>
          </div>
        </div>
      </div>
    );
  }

  if (!Boolean((bootState.config.onboarding as AnyRecord | undefined)?.completed)) {
    return (
      <OnboardingView
        coreApi={dependencies.coreApi}
        initialConfig={bootState.config}
        onCompleted={(config) =>
          setBootState({
            isLoading: false,
            config,
            error: ""
          })
        }
      />
    );
  }

  return (
    <NotificationProvider>
      <DashboardShell
        dependencies={dependencies}
        debugEnabled={Boolean((bootState.config as Record<string, unknown> | null)?.debugEnabled)}
      />
    </NotificationProvider>
  );
}
