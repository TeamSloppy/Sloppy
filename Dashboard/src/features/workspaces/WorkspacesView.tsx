import { useCallback, useEffect, useMemo, useRef, useState, type KeyboardEvent as ReactKeyboardEvent } from "react";
import type { CoreApi } from "../../shared/api/coreApi";
import { WorkspaceCanvas } from "./WorkspaceCanvas";
import type { WorkspaceRecord, WorkspaceTemplate } from "./types";

interface WorkspacesViewProps {
  coreApi: CoreApi;
  workspaceId: string | null;
  onWorkspaceRouteChange: (workspaceId: string | null) => void;
}

export function WorkspacesView({ coreApi, workspaceId, onWorkspaceRouteChange }: WorkspacesViewProps) {
  const isEmbeddedWorkspace = useMemo(
    () => new URLSearchParams(window.location.search).get("embed") === "workspace",
    []
  );
  const projectId = useMemo(() => {
    const value = new URLSearchParams(window.location.search).get("projectId");
    return value?.trim() || "";
  }, []);
  const [workspaces, setWorkspaces] = useState<WorkspaceRecord[]>([]);
  const [templates, setTemplates] = useState<WorkspaceTemplate[]>([]);
  const [query, setQuery] = useState("");
  const [createOpen, setCreateOpen] = useState(false);
  const [title, setTitle] = useState("");
  const [templateId, setTemplateId] = useState("");
  const [loading, setLoading] = useState(true);
  const createButtonRef = useRef<HTMLButtonElement | null>(null);
  const createDialogRef = useRef<HTMLElement | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    const [workspaceItems, templateItems] = await Promise.all([
      coreApi.fetchWorkspaces(projectId ? { projectId } : undefined),
      coreApi.fetchWorkspaceTemplates()
    ]);
    setWorkspaces(workspaceItems as unknown as WorkspaceRecord[]);
    setTemplates(templateItems as unknown as WorkspaceTemplate[]);
    setLoading(false);
  }, [coreApi, projectId]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    document.body.classList.add("workspace-native-route");
    return () => document.body.classList.remove("workspace-native-route");
  }, []);

  const closeCreateDialog = useCallback(() => {
    setCreateOpen(false);
    window.requestAnimationFrame(() => createButtonRef.current?.focus());
  }, []);

  const handleCreateDialogKeyDown = (event: ReactKeyboardEvent<HTMLElement>) => {
    if (event.key === "Escape") {
      event.preventDefault();
      closeCreateDialog();
      return;
    }
    if (event.key !== "Tab") return;
    const focusable = [...(createDialogRef.current?.querySelectorAll<HTMLElement>(
      "button:not([disabled]), input:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex='-1'])"
    ) || [])];
    if (!focusable.length) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  };

  const selectedWorkspace = workspaces.find((workspace) => workspace.id === workspaceId) || null;
  const filtered = useMemo(() => {
    const normalized = query.trim().toLowerCase();
    if (!normalized) return workspaces;
    return workspaces.filter((workspace) => `${workspace.title} ${workspace.description}`.toLowerCase().includes(normalized));
  }, [query, workspaces]);

  const createWorkspace = async () => {
    const normalizedTitle = title.trim() || "Untitled workspace";
    const created = await coreApi.createWorkspace({
      title: normalizedTitle,
      templateId: templateId || undefined,
      projectId: projectId || undefined
    }) as unknown as WorkspaceRecord | null;
    if (!created) return;
    setWorkspaces((items) => [created, ...items]);
    setTitle("");
    setTemplateId("");
    setCreateOpen(false);
    onWorkspaceRouteChange(created.id);
  };

  if (workspaceId && selectedWorkspace) {
    return (
      <WorkspaceCanvas
        coreApi={coreApi}
        workspace={selectedWorkspace}
        templates={templates}
        onBack={() => onWorkspaceRouteChange(null)}
        showsBackButton={!isEmbeddedWorkspace}
      />
    );
  }

  return (
    <main className="workspaces-page" data-testid="workspaces-gallery">
      <header className="workspaces-page-header">
        <div className="workspaces-title-group">
          <span className="workspaces-app-icon material-symbols-rounded" aria-hidden="true">space_dashboard</span>
          <div>
            <h1>{projectId ? "Project Workspaces" : "Workspaces"}</h1>
            <p>
              {projectId
                ? "Canvases connected to this project"
                : "Shared canvases for you and your agents"}
            </p>
          </div>
        </div>
        <button
          className="workspace-primary-button"
          type="button"
          ref={createButtonRef}
          onClick={() => setCreateOpen(true)}
          data-testid="workspace-create-button"
        >
          <span className="material-symbols-rounded" aria-hidden="true">add</span> New Workspace
        </button>
      </header>

      <section className="workspaces-command-row">
        <label className="workspaces-search">
          <span className="material-symbols-rounded" aria-hidden="true">search</span>
          <span className="visually-hidden">Search workspaces</span>
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search"
            aria-label="Search workspaces"
          />
          {query && (
            <button type="button" onClick={() => setQuery("")} aria-label="Clear search">
              <span className="material-symbols-rounded" aria-hidden="true">cancel</span>
            </button>
          )}
        </label>
        <span className="workspaces-count">{filtered.length} {filtered.length === 1 ? "workspace" : "workspaces"}</span>
      </section>

      {loading ? (
        <div className="workspace-loading">Loading workspaces…</div>
      ) : filtered.length === 0 ? (
        <section className="workspaces-empty">
          <div className="workspaces-empty-visual">
            <span className="material-symbols-rounded" aria-hidden="true">gesture</span>
            <i /><i /><i />
          </div>
          <h2>No Workspaces</h2>
          <p>Create a blank canvas or start from a template. Your agents can build on it with you.</p>
          <button className="workspace-primary-button" type="button" onClick={() => setCreateOpen(true)}>Create Workspace</button>
        </section>
      ) : (
        <section className="workspaces-grid" aria-label="Workspaces">
          {filtered.map((workspace) => (
            <button
              className="workspace-card"
              type="button"
              key={workspace.id}
              onClick={() => onWorkspaceRouteChange(workspace.id)}
              data-testid={`workspace-card-${workspace.id}`}
            >
              <div className="workspace-card-cover">
                <span className="workspace-card-paper workspace-card-paper-primary" />
                <span className="workspace-card-paper workspace-card-paper-secondary" />
                <span className="workspace-card-paper workspace-card-paper-tertiary" />
                <span className="workspace-card-revision">r{workspace.revision}</span>
              </div>
              <div className="workspace-card-copy">
                <strong title={workspace.title}>{workspace.title}</strong>
                <p>{workspace.description || "Open canvas"}</p>
                <span><span className="material-symbols-rounded" aria-hidden="true">schedule</span> Updated {new Date(workspace.updatedAt).toLocaleDateString()}</span>
              </div>
            </button>
          ))}
        </section>
      )}

      {createOpen && (
        <div className="workspace-modal-backdrop" role="presentation" onMouseDown={closeCreateDialog}>
          <section
            className="workspace-create-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="create-workspace-title"
            ref={createDialogRef}
            onKeyDown={handleCreateDialogKeyDown}
            onMouseDown={(event) => event.stopPropagation()}
            data-testid="workspace-create-dialog"
          >
            <header>
              <div>
                <span className="workspace-sheet-icon material-symbols-rounded" aria-hidden="true">dashboard_customize</span>
                <div>
                  <h2 id="create-workspace-title">New Workspace</h2>
                  <p>Choose a starting point for your canvas.</p>
                </div>
              </div>
              <button className="workspace-icon-button" type="button" onClick={closeCreateDialog} aria-label="Close">
                <span className="material-symbols-rounded" aria-hidden="true">close</span>
              </button>
            </header>
            <label className="workspace-name-field" htmlFor="workspace-name-input">
              <span>Name</span>
              <input
                id="workspace-name-input"
                autoFocus
                value={title}
                onChange={(event) => setTitle(event.target.value)}
                placeholder="Untitled Workspace"
                onKeyDown={(event) => {
                  if (event.key === "Enter") void createWorkspace();
                }}
              />
            </label>
            <div className="workspace-template-picker">
              <span>Start from</span>
              <button className={!templateId ? "active" : ""} type="button" onClick={() => setTemplateId("")}>
                <span className="material-symbols-rounded" aria-hidden="true">crop_square</span>
                <span><strong>Blank Canvas</strong><small>Start with an empty workspace</small></span>
              </button>
              {templates.map((template) => (
                <button className={templateId === template.id ? "active" : ""} type="button" key={template.id} onClick={() => setTemplateId(template.id)}>
                  <span className="material-symbols-rounded" aria-hidden="true">space_dashboard</span>
                  <span><strong>{template.title}</strong><small>{template.description || template.category}</small></span>
                </button>
              ))}
            </div>
            <footer>
              <button className="workspace-button" type="button" onClick={closeCreateDialog}>Cancel</button>
              <button className="workspace-primary-button" type="button" onClick={() => void createWorkspace()}>Create Workspace</button>
            </footer>
          </section>
        </div>
      )}
    </main>
  );
}
