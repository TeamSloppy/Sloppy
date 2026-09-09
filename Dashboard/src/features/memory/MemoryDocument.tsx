import { useEffect, useState } from "react";
import { fetchAgentConfig } from "../../api";

export function MemoryDocument({ agentId }: { agentId: string }) {
  const [text, setText] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    fetchAgentConfig(agentId).then((config) => {
      if (cancelled) return;
      const documents = config?.documents as Record<string, unknown> | undefined;
      setText(config ? String(documents?.memoryMarkdown || "") : null);
      setLoading(false);
    });
    return () => { cancelled = true; };
  }, [agentId, revision]);
  return <details className="memory-record memory-document"><summary><strong>MEMORY.md</strong><span>Long-form context for this agent</span></summary>
    {loading ? <p>Loading document…</p> : text === null ? <p role="alert">Could not load MEMORY.md.</p> : <p className="memory-record-note">{text || "This agent has no long-form memory yet."}</p>}
    <button type="button" onClick={() => setRevision((value) => value + 1)}>Refresh document</button>
  </details>;
}
