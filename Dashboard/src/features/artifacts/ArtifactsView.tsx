import { useEffect, useMemo, useState } from "react";
import type { CSSProperties } from "react";

type AnyRecord = Record<string, any>;
type WidgetLoadState = "idle" | "loading" | "ready" | "broken";

interface ArtifactsViewProps {
  coreApi: {
    fetchArtifacts: () => Promise<AnyRecord[]>;
    fetchWidgetArtifact: (id: string) => Promise<AnyRecord | null>;
  };
}

export function ArtifactsView({ coreApi }: ArtifactsViewProps) {
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

  const visibleArtifacts = useMemo(() => {
    if (filter === "widgets") {
      return artifacts.filter((artifact) => artifact?.kind === "widget");
    }
    return artifacts;
  }, [artifacts, filter]);

  return (
    <section className="artifacts-view">
      <header className="artifacts-header">
        <h1>Artifacts</h1>
        <div className="artifacts-filters" role="tablist" aria-label="Artifact filters">
          <button type="button" className={filter === "all" ? "active" : ""} onClick={() => setFilter("all")}>All</button>
          <button type="button" className={filter === "widgets" ? "active" : ""} onClick={() => setFilter("widgets")}>Widgets</button>
        </div>
      </header>
      {loading ? <p className="placeholder-text">Loading artifacts...</p> : null}
      {error ? <p className="app-status-text">{error}</p> : null}
      {!loading && !error && visibleArtifacts.length === 0 ? (
        <p className="placeholder-text">No artifacts yet.</p>
      ) : null}
      <div className="artifacts-grid">
        {visibleArtifacts.map((artifact) => (
          <ArtifactCard key={artifact.id} artifact={artifact} coreApi={coreApi} />
        ))}
      </div>
    </section>
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
  const description = artifactId
    ? `ID: ${artifactId}`
    : kind === "widget"
      ? "Interactive widget artifact"
      : "Stored artifact";

  return (
    <article className="artifact-card skill-card hover-levitate">
      <div className="skill-card-header">
        <h4 className="skill-name">{title}</h4>
        <span className="skill-owner">{kind}</span>
      </div>
      <div className="artifact-preview" style={previewStyle}>
        {artifact.kind !== "widget" ? <span className="artifact-preview-label">Artifact</span> : null}
        {artifact.kind === "widget" && widgetState === "loading" ? (
          <span className="artifact-preview-state artifact-preview-state--loading">Loading widget...</span>
        ) : null}
        {artifact.kind === "widget" && widgetState === "broken" ? (
          <span className="artifact-preview-state artifact-preview-state--broken">{widgetError || "Widget failed to load."}</span>
        ) : null}
        {artifact.kind === "widget" && widgetState === "ready" && widget?.html ? (
          <iframe title={artifact.title || artifact.id} sandbox="allow-scripts" srcDoc={String(widget.html)} />
        ) : null}
      </div>
      <p className="skill-description artifact-card-description">{description}</p>
      <div className="skill-card-footer artifact-card-footer">
        <span className="skill-installs artifact-card-meta">{artifactId || "No identifier"}</span>
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
