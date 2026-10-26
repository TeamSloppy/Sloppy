import React, { useEffect, useRef, useState } from "react";
import type { CoreApi } from "../../shared/api/coreApi";
import type { TextSearchDocument, TextSearchHit, TextSearchMode, TextSearchResponse } from "../../shared/api/textSearchTypes";
import "./textSearch.css";

export function SearchSnippet({ text }: { text: string }) {
  return <>{text.split(/(\uE000[^\uE001]*\uE001)/u).map((part, index) => part.startsWith("\uE000")
    ? <mark key={index}>{part.slice(1, -1)}</mark> : <React.Fragment key={index}>{part}</React.Fragment>)}</>;
}

export function TextSearchDialog({ coreApi, onClose, onOpenSession }: {
  coreApi: CoreApi;
  onClose: () => void;
  onOpenSession: (hit: TextSearchHit) => void;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [query, setQuery] = useState("");
  const [mode, setMode] = useState<TextSearchMode>("text");
  const [offset, setOffset] = useState(0);
  const [response, setResponse] = useState<TextSearchResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [selected, setSelected] = useState<TextSearchHit | null>(null);
  const [document, setDocument] = useState<TextSearchDocument | null>(null);
  const [documentError, setDocumentError] = useState("");
  const [retry, setRetry] = useState(0);
  const normalized = query.trim();

  useEffect(() => { dialog.current?.showModal(); }, []);
  useEffect(() => {
    const abort = new AbortController();
    let timer: ReturnType<typeof setTimeout>;
    setResponse(null);
    setSelected(null);
    setError("");
    if (!normalized) { setLoading(false); return () => abort.abort(); }
    setLoading(true);
    async function search() {
      try {
        const next = await coreApi.searchText(normalized, { mode, offset, signal: abort.signal });
        if (abort.signal.aborted) return;
        setResponse(next);
        setLoading(false);
        if (next.indexing) timer = setTimeout(search, 700);
      } catch (failure) {
        if (abort.signal.aborted) return;
        setLoading(false);
        setError(failure instanceof Error ? failure.message : "Search failed.");
      }
    }
    timer = setTimeout(search, 100);
    return () => { abort.abort(); clearTimeout(timer); };
  }, [coreApi, normalized, mode, offset, retry]);

  useEffect(() => {
    const abort = new AbortController();
    setDocument(null);
    setDocumentError("");
    if (selected) {
      coreApi.fetchSearchDocument(selected.id, abort.signal).then((next) => {
        if (!abort.signal.aborted) setDocument(next);
      }).catch((failure) => {
        if (!abort.signal.aborted) setDocumentError(failure instanceof Error ? failure.message : "The match is unavailable.");
      });
    }
    return () => abort.abort();
  }, [coreApi, selected]);

  return (
    <dialog ref={dialog} className="text-search-dialog" aria-labelledby="text-search-title" onCancel={onClose} onClose={onClose}>
      <header>
        <h2 id="text-search-title">Search all conversations</h2>
        <button type="button" onClick={onClose} aria-label="Close search">✕</button>
      </header>
      <div className="text-search-controls">
        <input type="search" autoFocus aria-label="Search all messages and tool output" placeholder="Search messages, code, and tool output…"
          value={query} onChange={(event) => { setQuery(event.target.value); setOffset(0); }}
          onKeyDown={(event) => {
            if (event.key === "ArrowDown") { event.preventDefault(); dialog.current?.querySelector<HTMLButtonElement>(".text-search-hit")?.focus(); }
          }} />
        <div className="text-search-modes" aria-label="Search mode">
          {(["text", "words"] as const).map((value) => <button key={value} type="button" aria-pressed={mode === value}
            onClick={() => { setMode(value); setOffset(0); }}>{value === "text" ? "Text contains" : "Words"}</button>)}
        </div>
        <p className="text-search-status" role="status">
          {loading ? "Searching…" : response ? `${response.items.length}${response.hasMore ? "+" : ""} matches · ${Math.round(response.durationMs)} ms` : "Search across every agent, project chat, worker, and channel session."}
          {response?.indexing ? " · Indexing history; results are incomplete." : ""}
          {response?.failedSources ? ` · ${response.failedSources} journals could not be indexed.` : ""}
          {normalized.length > 0 && normalized.length < 3 ? " Short queries match the beginning of a word." : ""}
        </p>
      </div>
      {error ? <p className="text-search-error" role="alert">Search unavailable: {error} <button type="button" onClick={() => setRetry((value) => value + 1)}>Retry</button></p> : null}
      <div className={`text-search-body ${selected ? "has-preview" : ""}`}>
        <div className="text-search-results" aria-label="Search results">
          {response?.items.map((hit) => <button type="button" key={hit.id} className="text-search-hit" aria-pressed={selected?.id === hit.id} onClick={() => setSelected(hit)}>
            <strong>{hit.title}</strong>
            <span className="text-search-meta">{hit.agentId || "Channel"} · {hit.role || hit.kind.replace(/_/g, " ")} {hit.createdAt ? `· ${new Date(hit.createdAt).toLocaleDateString()}` : ""}</span>
            <span className="text-search-snippet"><SearchSnippet text={hit.snippet} /></span>
          </button>)}
          {response && !response.items.length && !loading ? <p className="text-search-empty">{response.indexing ? "Building the index…" : "No matching text found."}</p> : null}
          {response ? <div className="text-search-pagination">
            <button type="button" disabled={offset === 0 || loading} onClick={() => setOffset(Math.max(0, offset - 50))}>Previous</button>
            <button type="button" disabled={!response.hasMore || loading} onClick={() => setOffset(offset + 50)}>Next</button>
          </div> : null}
        </div>
        {selected ? <section className="text-search-preview" aria-label="Matched message">
          <div className="text-search-preview-title"><strong>{selected.title}</strong><button type="button" onClick={() => { onOpenSession(selected); onClose(); }}>Open chat ↗</button></div>
          {documentError ? <p role="alert">{documentError}</p> : document ? <pre>{document.text}</pre> : <p role="status">Loading message…</p>}
        </section> : null}
      </div>
    </dialog>
  );
}
