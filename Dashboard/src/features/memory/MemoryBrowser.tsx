import { useEffect, useState } from "react";
import { fetchMemories } from "../../api";
import type { MemoryBrowserResponse } from "../../shared/api/coreApi";

export function MemoryBrowser({ sharedOnly = false }: { sharedOnly?: boolean }) {
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [offset, setOffset] = useState(0);
  const [response, setResponse] = useState<MemoryBrowserResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    const timer = setTimeout(() => { setQuery(search.trim()); setOffset(0); }, 250);
    return () => clearTimeout(timer);
  }, [search]);
  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    fetchMemories({ scope: sharedOnly ? "global" : "all", search: query, offset, limit: 20 }).then((data) => {
      if (!cancelled) { setResponse(data); setLoading(false); }
    });
    return () => { cancelled = true; };
  }, [sharedOnly, query, offset, revision]);
  return <section className="memory-browser">
    <div className="memory-browser-tools"><input aria-label="Search all memory" placeholder="Search memory…" value={search} onChange={(event) => setSearch(event.target.value)} />
      <button type="button" onClick={() => setRevision((value) => value + 1)}>Refresh</button></div>
    {loading ? <p role="status">Loading memory…</p> : !response ? <p role="alert">Could not load the memory index. Try Refresh.</p> : <>
      <p className="placeholder-text">{response.total} matching records. Select an agent or project for its graph and available editing tools.</p>
      {!response.items.length && <p>No memories match this scope and search.</p>}
      <div className="memory-records">{response.items.map((item) => <details key={item.id} className="memory-record">
        <summary><strong>{item.summary || item.note.slice(0, 140)}</strong><span>{item.scope.type} · {item.scope.id}</span></summary>
        <p className="memory-record-note">{item.note}</p>
        <small>{item.kind} · {item.id}{item.source ? ` · Source: ${item.source.type}${item.source.id ? ` / ${item.source.id}` : ""}` : ""}</small>
      </details>)}</div>
      <div className="memory-browser-tools"><button type="button" disabled={!offset} onClick={() => setOffset(Math.max(0, offset - 20))}>Previous</button>
        <span>{response.total ? `${offset + 1}–${offset + response.items.length}` : "0"} of {response.total}</span>
        <button type="button" disabled={offset + response.items.length >= response.total} onClick={() => setOffset(offset + 20)}>Next</button></div>
    </>}
  </section>;
}
