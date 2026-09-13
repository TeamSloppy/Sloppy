import { useState } from "react";
import { fetchMemoryImportSource, fetchMemoryImportSourceLocations } from "../../shared/api/coreApi";

export function archivedSourceReference(source?: { type: string; id?: string | null } | null) {
  if (source?.type !== "memory_import" || !source.id) return null;
  const [version, agentId, jobId, sourceId, extra] = source.id.split("/");
  if (version !== "v1" || !agentId || !jobId || !sourceId || extra !== undefined) return null;
  return { agentId, jobId, sourceId };
}

export function MemorySourceLink({ source, label = "Open archived source", memoryId, agentId }: {
  source?: { type: string; id?: string | null } | null;
  label?: string;
  memoryId?: string;
  agentId?: string;
}) {
  const ref = archivedSourceReference(source);
  const [document, setDocument] = useState<{ name: string; content: string; sha256: string } | null>(null);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [locations, setLocations] = useState<Array<{ jobId: string; sourceId: string; name: string; startUTF8: number }>>([]);
  const legacy = !ref && source?.type === "memory_import" && memoryId && agentId;
  if (!ref && !legacy) return null;
  return <div className="memory-source-link">
    <button type="button" disabled={loading} onClick={async () => {
      setLoading(true); setError("");
      try {
        if (ref) setDocument(await fetchMemoryImportSource(ref.agentId, ref.jobId, ref.sourceId));
        else {
          const available = await fetchMemoryImportSourceLocations(agentId, memoryId);
          if (!available.length) throw new Error("No archived source is linked yet. Continue this import using its saved attachments first.");
          setLocations(available);
          setDocument(await fetchMemoryImportSource(agentId, available[0].jobId, available[0].sourceId));
        }
      }
      catch (cause) { setError((cause as Error).message); }
      finally { setLoading(false); }
    }}>{loading ? "Loading source…" : label}</button>
    {error && <p role="alert">{error}</p>}
    {document && <div className="memory-source-document">
      <div><strong>{document.name}</strong><button type="button" onClick={() => setDocument(null)}>Close source</button></div>
      <small>Archived snapshot · SHA-256 {document.sha256}</small>
      {locations.length > 1 && <details><summary>Other source passages</summary>{locations.map((location, index) => <button key={index} type="button" onClick={async () => {
        try { setDocument(await fetchMemoryImportSource(agentId, location.jobId, location.sourceId)); }
        catch (cause) { setError((cause as Error).message); }
      }}>{location.name} · byte {location.startUTF8}</button>)}</details>}
      <pre>{document.content}</pre>
    </div>}
  </div>;
}
