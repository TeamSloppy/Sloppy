import { useEffect, useState } from "react";
import { createWorkspace, fetchWorkspaces } from "../../api";

interface ProjectWorkspacesTabProps {
  project: { id: string; name?: string };
}

export function ProjectWorkspacesTab({ project }: ProjectWorkspacesTabProps) {
  const [items, setItems] = useState<Record<string, unknown>[]>([]);
  const [creating, setCreating] = useState(false);

  const refresh = async () => {
    setItems(await fetchWorkspaces({ projectId: project.id }));
  };

  useEffect(() => {
    void refresh();
  }, [project.id]);

  const create = async () => {
    setCreating(true);
    const workspace = await createWorkspace({
      title: `${project.name || "Project"} workspace`,
      description: `Shared canvas for ${project.name || project.id}`,
      projectId: project.id
    });
    setCreating(false);
    if (workspace?.id) window.history.pushState({}, "", `/workspaces/${encodeURIComponent(String(workspace.id))}`);
    window.dispatchEvent(new PopStateEvent("popstate"));
  };

  return (
    <section className="project-tab-content">
      <header className="project-section-header">
        <div>
          <h2>Workspaces</h2>
          <p>Infinite canvases linked to this project. Access is still controlled by workspace membership.</p>
        </div>
        <button className="agents-create-inline hover-levitate" type="button" disabled={creating} onClick={() => void create()}>
          {creating ? "Creating…" : "New workspace"}
        </button>
      </header>
      <div className="workspaces-grid">
        {items.map((workspace) => (
          <button
            className="workspace-card"
            type="button"
            key={String(workspace.id)}
            onClick={() => {
              window.history.pushState({}, "", `/workspaces/${encodeURIComponent(String(workspace.id))}`);
              window.dispatchEvent(new PopStateEvent("popstate"));
            }}
          >
            <div className="workspace-card-cover">
              <span className="material-symbols-rounded">hub</span>
              <span className="workspace-card-revision">r{String(workspace.revision || 0)}</span>
            </div>
            <div className="workspace-card-copy">
              <strong>{String(workspace.title || "Workspace")}</strong>
              <p>{String(workspace.description || "Project canvas")}</p>
            </div>
          </button>
        ))}
      </div>
      {items.length === 0 && <p className="app-status-text">No workspaces linked to this project yet.</p>}
    </section>
  );
}
