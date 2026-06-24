import { useEffect, useMemo, useState } from "react";

type AnyRecord = Record<string, any>;

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
  const [widget, setWidget] = useState<AnyRecord | null>(null);

  useEffect(() => {
    let cancelled = false;
    if (artifact?.kind !== "widget" || !artifact?.id) {
      setWidget(null);
      return () => {
        cancelled = true;
      };
    }
    coreApi.fetchWidgetArtifact(String(artifact.id)).then((payload) => {
      if (!cancelled) {
        setWidget(payload);
      }
    });
    return () => {
      cancelled = true;
    };
  }, [artifact?.id, artifact?.kind, coreApi]);

  const width = Number(widget?.width || artifact?.widget?.width || 160);
  const height = Number(widget?.height || artifact?.widget?.height || 120);

  return (
    <article className="artifact-card">
      <div className="artifact-preview" style={{ width, height }}>
        {widget?.html ? (
          <iframe title={artifact.title || artifact.id} sandbox="" srcDoc={String(widget.html)} />
        ) : (
          <span>{artifact.kind === "widget" ? "Widget" : "Artifact"}</span>
        )}
      </div>
      <strong>{artifact.title || artifact.id}</strong>
      <span>{artifact.kind || "artifact"}</span>
    </article>
  );
}
