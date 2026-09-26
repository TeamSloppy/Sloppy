import { useEffect, useMemo, useState } from "react";
import type { CSSProperties } from "react";
import { sandboxedArtifactDocument } from "../../shared/ui/sandboxedArtifactDocument";

type AnyRecord = Record<string, any>;
type WidgetLoadState = "idle" | "loading" | "ready" | "broken";

interface ArtifactsViewProps {
  artifactId?: string | null;
  coreApi: {
    fetchArtifacts: () => Promise<AnyRecord[]>;
    fetchArtifactMetadata: (id: string) => Promise<AnyRecord | null>;
    fetchWidgetArtifact: (id: string) => Promise<AnyRecord | null>;
  };
}

export function ArtifactsView({ coreApi, artifactId }: ArtifactsViewProps) {
  return artifactId
    ? <ArtifactDetailView artifactId={artifactId} coreApi={coreApi} />
    : <ArtifactListView coreApi={coreApi} />;
}

function ArtifactDetailView({ artifactId, coreApi }: { artifactId: string; coreApi: ArtifactsViewProps["coreApi"] }) {
  const [widget, setWidget] = useState<AnyRecord | null>(null);
  const [metadata, setMetadata] = useState<AnyRecord | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    let cancelled = false;
    setWidget(null);
    setMetadata(null);
    setError("");
    coreApi.fetchArtifactMetadata(artifactId)
      .then((result) => { if (!cancelled) setMetadata(result); })
      .catch(() => { /* The visual remains available without metadata. */ });
    coreApi.fetchWidgetArtifact(artifactId)
      .then((result) => { if (!cancelled) setWidget(result); })
      .catch((cause) => { if (!cancelled) setError(cause?.message || "Visual unavailable."); });
    return () => { cancelled = true; };
  }, [artifactId, coreApi]);

  return (
    <section className="artifacts-view artifact-detail-view">
      <header className="artifacts-header">
        <div>
          <a href="/artifacts" className="agent-chat-technical-link">← All artifacts</a>
          <h1>{String(metadata?.title || "Web visual")}</h1>
        </div>
        <span className="artifact-detail-id">{artifactId}</span>
      </header>
      {metadata?.previewText ? <p className="artifact-detail-summary">{String(metadata.previewText)}</p> : null}
      {error ? <p className="app-status-text" role="alert">{error}</p> : null}
      {!widget && !error ? <p className="placeholder-text">Loading visual...</p> : null}
      {widget?.html ? (
        <iframe
          className="artifact-detail-frame"
          title="Web visual"
          sandbox="allow-scripts"
          srcDoc={sandboxedArtifactDocument(String(widget.html))}
        />
      ) : null}
    </section>
  );
}

function ArtifactListView({ coreApi }: ArtifactsViewProps) {
  const [artifacts, setArtifacts] = useState<AnyRecord[]>([]);
  const [filter, setFilter] = useState("all");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError("");
    coreApi.fetchArtifacts()
      .then((items) => {
        if (!cancelled) {
          setArtifacts(items);
        }
      })
      .catch((err) => {
        if (!cancelled) {
          setError(err?.message || "Artifacts are unavailable.");
        }
      })
      .finally(() => {
        if (!cancelled) {
          setLoading(false);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [coreApi]);

  const widgets = useMemo(() => artifacts.filter((artifact) => artifact?.kind === "widget"), [artifacts]);
  const documents = useMemo(() => artifacts.filter((artifact) => artifact?.kind !== "widget"), [artifacts]);
  const visibleCount = filter === "widgets" ? widgets.length : filter === "documents" ? documents.length : artifacts.length;

  return (
    <section className="artifacts-view">
      <header className="artifacts-header">
        <h1>Artifacts</h1>
        <div className="artifacts-filters" role="tablist" aria-label="Artifact filters">
          <button type="button" className={filter === "all" ? "active" : ""} onClick={() => setFilter("all")}>All</button>
          <button type="button" className={filter === "documents" ? "active" : ""} onClick={() => setFilter("documents")}>Documents</button>
          <button type="button" className={filter === "widgets" ? "active" : ""} onClick={() => setFilter("widgets")}>Widgets</button>
        </div>
      </header>
      {loading ? <p className="placeholder-text">Loading artifacts...</p> : null}
      {error ? <p className="app-status-text">{error}</p> : null}
      {!loading && !error && visibleCount === 0 ? (
        <p className="placeholder-text">No artifacts yet.</p>
      ) : null}
      {!loading && !error && documents.length > 0 && filter !== "widgets" ? (
        <section className="artifacts-section" aria-label="Documents">
          <h2>Documents <span>{documents.length}</span></h2>
          <div className="artifacts-document-list">
            {documents.map((artifact) => <DocumentRow key={artifact.id} artifact={artifact} />)}
          </div>
        </section>
      ) : null}
      {!loading && !error && widgets.length > 0 && filter !== "documents" ? (
        <section className="artifacts-section" aria-label="Widgets">
          <h2>Widgets <span>{widgets.length}</span></h2>
          <div className="artifacts-grid">
            {widgets.map((artifact) => <ArtifactCard key={artifact.id} artifact={artifact} coreApi={coreApi} />)}
          </div>
        </section>
      ) : null}
    </section>
  );
}

function DocumentRow({ artifact }: { artifact: AnyRecord }) {
  const title = String(artifact?.title || artifact?.id || "Document");
  const id = String(artifact?.id || "");
  return (
    <article className="artifact-document-row">
      <span className="material-symbols-rounded" aria-hidden="true">description</span>
      <div>
        <strong>{title}</strong>
        {id && id !== title ? <small>{id}</small> : null}
      </div>
      <span className="artifact-document-kind">{String(artifact?.kind || "document")}</span>
    </article>
  );
}

function ArtifactCard({ artifact, coreApi }: { artifact: AnyRecord; coreApi: ArtifactsViewProps["coreApi"] }) {
  const [widgetState, setWidgetState] = useState<WidgetLoadState>("idle");
  const [widget, setWidget] = useState<AnyRecord | null>(null);
  const [widgetError, setWidgetError] = useState("");

  useEffect(() => {
    let cancelled = false;
    if (artifact?.kind !== "widget" || !artifact?.id) {
      setWidgetState("idle");
      setWidget(null);
      setWidgetError("");
      return () => {
        cancelled = true;
      };
    }
    setWidgetState("loading");
    setWidget(null);
    setWidgetError("");
    coreApi.fetchWidgetArtifact(String(artifact.id))
      .then((payload) => {
        if (cancelled) {
          return;
        }
        if (!payload) {
          setWidgetState("broken");
          setWidgetError("Widget content is unavailable.");
          return;
        }
        setWidget(payload);
        setWidgetState("ready");
      })
      .catch((err) => {
        if (cancelled) {
          return;
        }
        setWidgetState("broken");
        setWidgetError(err?.message || "Widget failed to load.");
      });
    return () => {
      cancelled = true;
    };
  }, [artifact?.id, artifact?.kind, coreApi]);

  const width = normalizeDimension(widget?.width || artifact?.widget?.width, 160);
  const height = normalizeDimension(widget?.height || artifact?.widget?.height, 120);
  const previewStyle = {
    "--artifact-preview-width": String(width),
    "--artifact-preview-height": String(height)
  } as CSSProperties;
  const title = String(artifact?.title || artifact?.id || "Artifact");
  const kind = String(artifact?.kind || "artifact");
  const artifactId = typeof artifact?.id === "string" ? artifact.id : "";
  const description = artifactId ? `ID: ${artifactId}` : "Interactive widget artifact";

  return (
    <article className="artifact-card skill-card hover-levitate">
      <div className="skill-card-header">
        <h4 className="skill-name">{title}</h4>
        <span className="skill-owner">{kind}</span>
      </div>
      <div className="artifact-preview" style={previewStyle}>
        {artifact.kind === "widget" && widgetState === "loading" ? (
          <span className="artifact-preview-state artifact-preview-state--loading">Loading widget...</span>
        ) : null}
        {artifact.kind === "widget" && widgetState === "broken" ? (
          <span className="artifact-preview-state artifact-preview-state--broken">{widgetError || "Widget failed to load."}</span>
        ) : null}
        {artifact.kind === "widget" && widgetState === "ready" && widget?.html ? (
          <iframe title={artifact.title || artifact.id} sandbox="allow-scripts" srcDoc={sandboxedArtifactDocument(String(widget.html))} />
        ) : null}
      </div>
      <p className="skill-description artifact-card-description">{description}</p>
      <div className="skill-card-footer artifact-card-footer">
        <span className="skill-installs artifact-card-meta">{artifactId || "No identifier"}</span>
        {artifactId ? <a href={`/artifacts/${encodeURIComponent(artifactId)}`}>Open</a> : null}
      </div>
    </article>
  );
}

function normalizeDimension(value: unknown, fallback: number) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }
  return Math.round(parsed);
}
