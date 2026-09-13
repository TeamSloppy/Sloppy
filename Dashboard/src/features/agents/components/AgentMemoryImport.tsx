import { useEffect, useRef, useState } from "react";
import { createAgentSession } from "../../../api";
import { isMemoryImportComplete, prepareMemoryAttachments, validateMemoryFiles } from "../memoryImport";
import { startMemoryImport, fetchMemoryImports, fetchMemoryImport, resumeMemoryImport, cancelMemoryImport, importSessionAttachments, type MemoryImportJob } from "../../../shared/api/coreApi";
import { MemorySourceLink } from "../../memory/MemorySourceLink";
import exportPrompt from "../../../../../Sources/sloppy/Resources/Skills/memory-import/references/export-prompt.md?raw";
import "../../../styles/memory-import.css";

export function AgentMemoryImport({ agentId, onUpdated }: { agentId: string; onUpdated: () => void }) {
  const [open, setOpen] = useState(false);
  const [files, setFiles] = useState<File[]>([]);
  const [error, setError] = useState("");
  const [copied, setCopied] = useState(false);
  const [busy, setBusy] = useState(false);
  const [job, setJob] = useState<MemoryImportJob | null>(null);
  const [history, setHistory] = useState<MemoryImportJob[]>([]);
  const [revision, setRevision] = useState(0);
  const [statusUnavailable, setStatusUnavailable] = useState(false);
  const [legacySession] = useState(() => {
    try { return localStorage.getItem(`sloppy:memory-import:${agentId}`); } catch { return null; }
  });
  const input = useRef<HTMLInputElement>(null);
  const pendingSession = useRef<string | null>(null);
  const updated = useRef(onUpdated);
  updated.current = onUpdated;

  function selectJob(next: MemoryImportJob) {
    setJob(next);
    setHistory((items) => [next, ...items.filter((item) => item.id !== next.id)]);
    try { localStorage.setItem(`sloppy:memory-import-job:${agentId}`, next.id); } catch { /* Server history remains available. */ }
  }

  useEffect(() => {
    let cancelled = false;
    fetchMemoryImports(agentId).then((jobs) => {
      if (cancelled) return;
      setHistory(jobs);
      setStatusUnavailable(false);
      let remembered: string | null = null;
      try { remembered = localStorage.getItem(`sloppy:memory-import-job:${agentId}`); } catch {}
      setJob(jobs.find((item) => item.id === remembered) || jobs.find((item) => ["queued", "running"].includes(item.status)) || jobs[0] || null);
    }).catch((cause) => { if (!cancelled) { setError(cause.message); setStatusUnavailable(true); } });
    return () => { cancelled = true; };
  }, [agentId]);

  useEffect(() => {
    if (!job) return;
    let cancelled = false;
    let timer: ReturnType<typeof setTimeout>;
    let lastSaved = -1;
    async function poll() {
      try {
        const next = await fetchMemoryImport(agentId, job.id);
        if (cancelled) return;
        setJob(next);
        setStatusUnavailable(false);
        setHistory((items) => items.map((item) => item.id === next.id ? next : item));
        if (next.savedCount !== lastSaved) { lastSaved = next.savedCount; updated.current(); }
        if (["completed", "failed", "cancelled"].includes(next.status)) return;
      } catch (cause) { if (!cancelled) { setError((cause as Error).message); setStatusUnavailable(true); } }
      if (!cancelled) timer = setTimeout(poll, 2000);
    }
    void poll();
    const onFocus = () => { if (!document.hidden) setRevision((value) => value + 1); };
    window.addEventListener("focus", onFocus);
    return () => { cancelled = true; clearTimeout(timer); window.removeEventListener("focus", onFocus); };
  }, [agentId, job?.id, revision]);

  function addFiles(incoming: File[]) {
    if (busy) return;
    try {
      const next = [...files, ...incoming]; validateMemoryFiles(next);
      setFiles(next); setError(""); pendingSession.current = null;
    } catch (cause) { setError((cause as Error).message); }
  }

  async function perform(action: () => Promise<MemoryImportJob>) {
    setBusy(true); setError("");
    try { selectJob(await action()); setRevision((value) => value + 1); }
    catch (cause) { setError((cause as Error).message + " Check import history before starting another job."); }
    finally { setBusy(false); }
  }

  async function upload() {
    await perform(async () => {
      const attachments = await prepareMemoryAttachments(files);
      if (!pendingSession.current) {
        const session = await createAgentSession(agentId, { title: "Memory import" });
        if (!session || typeof session.id !== "string") throw new Error("Could not create an import session.");
        pendingSession.current = session.id;
      }
      const result = await startMemoryImport(agentId, attachments, pendingSession.current);
      setFiles([]); pendingSession.current = null;
      return result;
    });
  }

  const active = job && ["queued", "running", "cancelling"].includes(job.status);
  const complete = job && isMemoryImportComplete(job);
  return <div className="memory-import">
    <button type="button" className="agent-memory-action-btn" aria-expanded={open} onClick={() => setOpen(!open)}>
      <span className="material-symbols-rounded" aria-hidden="true">upload_file</span> Import memory
    </button>
    {open && <div className="memory-import-panel">
      <h4>Bring memory from another assistant</h4>
      <p>Send this prompt to your other assistant, then upload its Markdown files. Sloppy archives the sources and processes every part in a persistent background job.</p>
      <details><summary>Export prompt</summary><textarea aria-label="Memory export prompt" readOnly value={exportPrompt} rows={10} /></details>
      <button type="button" className="agent-memory-action-btn" onClick={async () => {
        try { await navigator.clipboard.writeText(exportPrompt); setCopied(true); }
        catch { setError("Expand the export prompt and copy it manually."); }
      }}>{copied ? "Copied" : "Copy export prompt"}</button>
      <div className="memory-import-drop" onDragOver={(event) => event.preventDefault()} onDrop={(event) => { event.preventDefault(); addFiles(Array.from(event.dataTransfer.files)); }}>
        <p>Drop Markdown files here</p>
        <button type="button" className="agent-memory-action-btn" disabled={busy} onClick={() => input.current?.click()}>Choose files</button>
        <input ref={input} type="file" hidden multiple accept=".md,.markdown,text/markdown" onChange={(event) => { addFiles(Array.from(event.target.files || [])); event.target.value = ""; }} />
        <small>Up to 20 files · 1 MB per file · 5 MB total · UTF-8</small>
      </div>
      {files.length > 0 && <ul className="memory-import-files">{files.map((file, index) => <li key={`${file.name}-${index}`}>
        <span>{file.name} <small>({Math.ceil(file.size / 1024)} KB)</small></span>
        <button type="button" className="agent-memory-action-btn" disabled={busy} aria-label={`Remove ${file.name}`} onClick={() => { setFiles(files.filter((_, i) => i !== index)); pendingSession.current = null; }}>Remove</button>
      </li>)}</ul>}
      <p className="memory-import-hint">Destination: <strong>{agentId}</strong>. Sources remain available after the original file or chat attachment is deleted. Notes contain facts; provenance is stored separately.</p>
      <button type="button" className="agent-memory-save-btn" disabled={busy || !files.length} onClick={upload}>{busy ? "Starting…" : "Import into this agent"}</button>
      {legacySession && !history.some((item) => item.sessionId === legacySession) && <button type="button" disabled={busy} onClick={() => perform(() => importSessionAttachments(agentId, legacySession))}>Continue previous import from saved attachments</button>}
      {history.length > 1 && <details><summary>Import history</summary><ul>{history.map((item) => <li key={item.id}><button type="button" onClick={() => selectJob(item)}>{item.sources.map((source) => source.name).join(", ")} · {item.status} · {item.completedUnits}/{item.totalUnits}</button></li>)}</ul></details>}
    </div>}
    {error && <p role="alert" className="memory-import-error">{error}</p>}
    {job && <div className="memory-import-job">
      <div role="status"><strong>{statusUnavailable ? "Import status unavailable" : complete ? "Import complete" : job.status === "cancelling" ? "Stopping import…" : active ? "Import continues in the background" : job.status === "cancelled" ? "Import cancelled" : "Import needs attention"}</strong>
        <p>{job.completedUnits}/{job.totalUnits} parts verified · {job.savedCount} records saved · {job.duplicateCount} duplicates · {job.ignoredCount} parts excluded after review</p>
      </div>
      <progress aria-label="Verified import coverage" value={job.completedUnits} max={Math.max(1, job.totalUnits)} />
      {job.error && <p role="alert">{job.error}</p>}
      <div className="memory-import-progress">
        <a href={`/agents/${encodeURIComponent(agentId)}/chat/${encodeURIComponent(job.sessionId)}`} target="_blank" rel="noreferrer">Open import session</a>
        {active ? <button type="button" disabled={busy || job.status === "cancelling"} onClick={() => perform(() => cancelMemoryImport(agentId, job.id))}>Cancel import</button>
          : !complete && <button type="button" disabled={busy} onClick={() => perform(() => resumeMemoryImport(agentId, job.id))}>Resume remaining work</button>}
      </div>
      <details><summary>Archived source files ({job.sources.length})</summary>{job.sources.map((source) => <div key={source.id}>
        <MemorySourceLink source={{ type: "memory_import", id: `v1/${agentId}/${job.id}/${source.id}` }} label={`${source.name} · ${source.completedUnits}/${source.totalUnits} parts`} />
      </div>)}</details>
      {job.parts?.length > 0 && <details><summary>Coverage report ({job.completedUnits}/{job.totalUnits})</summary>
        <ul className="memory-import-coverage">{job.parts.map((part) => <li key={part.id}>
          <strong>{job.sources.find((source) => source.id === part.sourceId)?.name} · bytes {part.startUTF8}–{part.endUTF8}</strong>
          <p>{part.completed ? part.disposition === "retained" ? "Retained / verified duplicate" : "Excluded after review" : "Pending"}{part.reason ? ` — ${part.reason}` : ""}</p>
          {part.memoryIds.length > 0 && <small>Records: {part.memoryIds.join(", ")}</small>}
        </li>)}</ul>
      </details>}
    </div>}
  </div>;
}
