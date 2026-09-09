import { useEffect, useRef, useState } from "react";
import { createAgentSession, fetchAgentSession, submitAgentMemoryImport } from "../../../api";
import { memoryImportProgress, prepareMemoryAttachments, validateMemoryFiles } from "../memoryImport";
import exportPrompt from "../../../../../Sources/sloppy/Resources/Skills/memory-import/references/export-prompt.md?raw";
import "../../../styles/memory-import.css";

export function AgentMemoryImport({ agentId, onUpdated }: { agentId: string; onUpdated: () => void }) {
  const [open, setOpen] = useState(false);
  const [files, setFiles] = useState<File[]>([]);
  const [error, setError] = useState("");
  const [copied, setCopied] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [submissionFailed, setSubmissionFailed] = useState(false);
  const [statusUnavailable, setStatusUnavailable] = useState(false);
  const storageKey = `sloppy:memory-import:${agentId}`;
  const [sessionId, setSessionId] = useState<string | null>(() => {
    try { return localStorage.getItem(storageKey); } catch { return null; }
  });
  const [progress, setProgress] = useState<ReturnType<typeof memoryImportProgress> | null>(null);
  const [refresh, setRefresh] = useState(0);
  const input = useRef<HTMLInputElement>(null);
  const updated = useRef(onUpdated);
  updated.current = onUpdated;

  useEffect(() => {
    if (!sessionId) return;
    let cancelled = false;
    let timer: ReturnType<typeof setTimeout>;
    let lastSaved = -1;
    async function poll() {
      const detail = await fetchAgentSession(agentId, sessionId);
      if (cancelled) return;
      setStatusUnavailable(!detail);
      if (detail && Array.isArray(detail.events)) {
        const next = memoryImportProgress(detail.events);
        setProgress(next);
        if (next.saved !== lastSaved) {
          lastSaved = next.saved;
          updated.current();
        }
        if (["done", "paused", "interrupted"].includes(next.stage)) return;
      }
      timer = setTimeout(poll, 2000);
    }
    void poll();
    const refreshOnReturn = () => {
      if (!document.hidden) setRefresh((value) => value + 1);
    };
    window.addEventListener("focus", refreshOnReturn);
    document.addEventListener("visibilitychange", refreshOnReturn);
    return () => {
      cancelled = true;
      clearTimeout(timer);
      window.removeEventListener("focus", refreshOnReturn);
      document.removeEventListener("visibilitychange", refreshOnReturn);
    };
  }, [agentId, sessionId, refresh]);

  function addFiles(incoming: File[]) {
    if (submitting) return;
    const next = [...files, ...incoming];
    try {
      validateMemoryFiles(next);
      setFiles(next);
      setError("");
    } catch (cause) {
      setError((cause as Error).message);
    }
  }

  async function importFiles() {
    setSubmitting(true);
    setError("");
    let started = false;
    try {
      const attachments = await prepareMemoryAttachments(files);
      const session = await createAgentSession(agentId, { title: "Memory import" });
      if (!session || typeof session.id !== "string") throw new Error("Could not create an import session. Your files are still selected.");
      setProgress(null);
      setSubmissionFailed(false);
      setStatusUnavailable(false);
      setSessionId(session.id);
      started = true;
      try { localStorage.setItem(storageKey, session.id); } catch { /* The session remains available in chat history. */ }
      await submitAgentMemoryImport(agentId, session.id, attachments);
      setFiles([]);
      setRefresh((value) => value + 1);
      updated.current();
    } catch (cause) {
      setError((cause as Error).message);
      if (started) setSubmissionFailed(true);
    } finally {
      setSubmitting(false);
    }
  }

  const stageLabel = progress?.stage === "done" ? "Processing finished — review the report"
    : progress?.stage === "paused" ? "Needs your input — open the session"
    : progress?.stage === "interrupted" ? "Import interrupted — open the session"
    : submissionFailed ? "Request failed — check the session"
    : statusUnavailable ? "Session status unavailable — open the session"
    : !progress || progress.stage === "pending" ? "Waiting for session activity…"
    : "Processing memory…";

  return (
    <div className="memory-import">
      <button type="button" className="agent-memory-action-btn" aria-expanded={open} onClick={() => setOpen(!open)}>
        <span className="material-symbols-rounded" aria-hidden="true">upload_file</span> Import memory
      </button>
      {open && (
        <div className="memory-import-panel">
          <h4>Bring memory from another assistant</h4>
          <p>Send this prompt to your other assistant, then upload the Markdown files it returns. Sloppy will organize useful facts and add them to this agent’s searchable memory.</p>
          <details>
            <summary>Export prompt</summary>
            <textarea aria-label="Memory export prompt" readOnly value={exportPrompt} rows={10} />
          </details>
          <button type="button" className="agent-memory-action-btn" onClick={async () => {
            try { await navigator.clipboard.writeText(exportPrompt); setCopied(true); }
            catch { setError("Clipboard unavailable. Expand the export prompt and copy it manually."); }
          }}>{copied ? "Copied" : "Copy export prompt"}</button>

          <div className="memory-import-drop" onDragOver={(event) => event.preventDefault()} onDrop={(event) => {
            event.preventDefault();
            addFiles(Array.from(event.dataTransfer.files));
          }}>
            <p>Drop Markdown files here</p>
            <button type="button" className="agent-memory-action-btn" disabled={submitting} onClick={() => input.current?.click()}>Choose files</button>
            <input ref={input} type="file" hidden multiple accept=".md,.markdown,text/markdown" onChange={(event) => {
              addFiles(Array.from(event.target.files || []));
              event.target.value = "";
            }} />
            <small>Up to 20 files · 1 MB per file · 5 MB total · UTF-8</small>
          </div>
          {files.length > 0 && <ul className="memory-import-files">{files.map((file, index) => (
            <li key={`${file.name}-${index}`}><span>{file.name} <small>({Math.ceil(file.size / 1024)} KB)</small></span>
              <button type="button" className="agent-memory-action-btn" disabled={submitting} aria-label={`Remove ${file.name}`} onClick={() => setFiles(files.filter((_, position) => position !== index))}>Remove</button>
            </li>
          ))}</ul>}
          <p className="memory-import-hint">Destination: <strong>{agentId}</strong>. You can also attach files in chat or ask Sloppy: “Use @memory-import to import the Markdown files in [path].”</p>
          <button type="button" className="agent-memory-save-btn" disabled={submitting || !files.length} onClick={importFiles}>{submitting ? "Importing…" : "Import into this agent"}</button>
          {error && <p role="alert" className="memory-import-error">{error}</p>}
        </div>
      )}
      {sessionId && <div className="memory-import-progress" role="status">
        <span>{stageLabel}{progress ? ` · ${progress.saved} memory records saved${progress.failures ? ` · ${progress.failures} failed writes` : ""}` : ""}</span>
        <a href={`/agents/${encodeURIComponent(agentId)}/chat/${encodeURIComponent(sessionId)}`} target="_blank" rel="noreferrer">Open import session</a>
      </div>}
    </div>
  );
}
