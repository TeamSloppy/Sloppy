import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { fetchProjectWorkingTreeSourceControl, postProjectSourceControlRestore } from "../../../api";
import { createDiffFileFromPatch, splitUnifiedDiff } from "./workingTreeDiff/parseSourceControlDiff";
import { WorkingTreeDiffFileBlock } from "./workingTreeDiff/WorkingTreeDiffFileBlock";
import type { SourceControlComposeTagPayload } from "./workingTreeDiff/sourceControlComposeTypes";

export type { SourceControlComposeTagPayload };

type SourceControlPayload = {
  isRepository?: boolean;
  branch?: string | null;
  linesAdded?: number;
  linesDeleted?: number;
  diff?: string;
  diffTruncated?: boolean;
  message?: string | null;
};

export function ProjectSourceControlDiffPanel({
  projectId,
  open,
  onClose,
  onAddSourceControlComposeTag
}: {
  projectId: string;
  open: boolean;
  onClose: () => void;
  onAddSourceControlComposeTag: (payload: SourceControlComposeTagPayload) => void;
}) {
  const [data, setData] = useState<SourceControlPayload | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [comment, setComment] = useState("");
  const [hint, setHint] = useState<string | null>(null);
  const [fullscreen, setFullscreen] = useState(false);
  const panelRef = useRef<HTMLElement | null>(null);
  const lastDiffSelectionRef = useRef("");

  const load = useCallback(async () => {
    if (!projectId) {
      return;
    }
    setLoading(true);
    setLoadError(null);
    setHint(null);
    try {
      const res = (await fetchProjectWorkingTreeSourceControl(projectId)) as SourceControlPayload | null;
      setData(res || null);
      if (res && res.isRepository === false && res.message) {
        setLoadError(null);
      }
    } catch (e: unknown) {
      setData(null);
      setLoadError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [projectId]);

  useEffect(() => {
    if (open && projectId) {
      void load();
    }
  }, [open, projectId, load]);

  useEffect(() => {
    lastDiffSelectionRef.current = "";
  }, [data?.diff]);

  useEffect(() => {
    const onFullscreenChange = () => {
      setFullscreen(document.fullscreenElement === panelRef.current);
    };
    document.addEventListener("fullscreenchange", onFullscreenChange);
    return () => document.removeEventListener("fullscreenchange", onFullscreenChange);
  }, []);

  const canFullscreen =
    typeof document !== "undefined" && typeof document.fullscreenEnabled === "boolean" && document.fullscreenEnabled;

  const toggleFullscreen = useCallback(async () => {
    const el = panelRef.current;
    if (!el || !canFullscreen) {
      return;
    }
    try {
      if (document.fullscreenElement === el) {
        await document.exitFullscreen();
      } else {
        await el.requestFullscreen();
      }
    } catch {
      /* ignore */
    }
  }, [canFullscreen]);

  const handleClose = useCallback(() => {
    const el = panelRef.current;
    if (el && document.fullscreenElement === el) {
      void document.exitFullscreen().then(() => onClose()).catch(() => onClose());
    } else {
      onClose();
    }
  }, [onClose]);

  const diffText = typeof data?.diff === "string" ? data.diff : "";

  const diffBlocks = useMemo(() => {
    if (!diffText.trim()) {
      return [];
    }
    return splitUnifiedDiff(diffText).map((section) => ({
      ...section,
      diffFile: createDiffFileFromPatch(section.displayPath, section.patchText)
    }));
  }, [diffText]);

  const restoreFile = useCallback(
    async (relativePath: string) => {
      return postProjectSourceControlRestore(projectId, relativePath);
    },
    [projectId]
  );

  function appendSelectionToComposer() {
    const live =
      typeof window !== "undefined" && window.getSelection
        ? String(window.getSelection()?.toString() ?? "").trim()
        : "";
    const sel = live || lastDiffSelectionRef.current.trim();
    const note = comment.trim();
    if (!sel && !note) {
      setHint("Use + on a line, write a note, and/or select text in the diff.");
      return;
    }
    const parts: string[] = [];
    if (note) {
      parts.push(`Review (working tree vs last commit):`, "", note);
    }
    if (sel) {
      if (parts.length > 0) {
        parts.push("");
      }
      parts.push("```diff", sel, "```");
    }
    const markdown = `${parts.join("\n")}\n`;
    const label =
      note.length > 0
        ? note.length <= 48
          ? note
          : `${note.slice(0, 44)}…`
        : sel
          ? "Selected diff"
          : "Diff";
    onAddSourceControlComposeTag({ label, markdown });
    setComment("");
    setHint(null);
  }

  function insertFromWidget(payload: SourceControlComposeTagPayload) {
    const note = comment.trim();
    const markdown = note ? `${note}\n\n${payload.markdown}` : payload.markdown;
    onAddSourceControlComposeTag({ label: payload.label, markdown });
  }

  if (!open) {
    return null;
  }

  const isRepository = data?.isRepository === true;
  const branch = data?.branch ? String(data.branch) : null;
  const added = typeof data?.linesAdded === "number" ? data.linesAdded : 0;
  const deleted = typeof data?.linesDeleted === "number" ? data.linesDeleted : 0;
  const truncated = Boolean(data?.diffTruncated);
  const serverMsg = data?.message ? String(data.message) : null;

  return (
    <aside
      ref={panelRef}
      className="agent-chat-source-control-panel"
      data-testid="project-source-control-diff-panel"
      aria-label="Project source-control diff"
    >
      <div className="agent-chat-source-control-panel__head">
        <div className="agent-chat-source-control-panel__title">
          <span className="material-symbols-rounded" aria-hidden="true">
            difference
          </span>
          <div>
            <strong>Working tree</strong>
            <small>
              {loading
                ? "Loading…"
                : isRepository
                  ? [branch ? `branch: ${branch}` : "branch: —", `+${added} −${deleted}`].join(" · ")
                  : "Not a source-control repo"}
            </small>
          </div>
        </div>
        <div className="agent-chat-source-control-panel__head-actions">
          {canFullscreen ? (
            <button
              type="button"
              className="agent-chat-icon-button"
              title={fullscreen ? "Exit full screen" : "Full screen"}
              aria-pressed={fullscreen}
              aria-label={fullscreen ? "Exit full screen" : "Open full screen"}
              onClick={() => void toggleFullscreen()}
            >
              <span className="material-symbols-rounded" aria-hidden="true">
                {fullscreen ? "fullscreen_exit" : "fullscreen"}
              </span>
            </button>
          ) : null}
          <button type="button" className="agent-chat-icon-button" title="Refresh" onClick={() => void load()}>
            <span className="material-symbols-rounded" aria-hidden="true">
              refresh
            </span>
          </button>
          <button type="button" className="agent-chat-icon-button" title="Close" onClick={handleClose}>
            <span className="material-symbols-rounded" aria-hidden="true">
              close
            </span>
          </button>
        </div>
      </div>

      <div className="agent-chat-source-control-panel__body">
        {loadError ? <p className="agent-chat-source-control-panel__error">{loadError}</p> : null}
        {!isRepository && serverMsg ? <p className="placeholder-text">{serverMsg}</p> : null}
        {isRepository && serverMsg ? <p className="agent-chat-source-control-panel__error">{serverMsg}</p> : null}

        {isRepository && !loadError ? (
          <>
            <label className="agent-chat-source-control-panel__label">
              Note for the agent (optional, prepended to each + tag)
              <textarea
                className="agent-chat-source-control-panel__comment"
                value={comment}
                onChange={(e) => setComment(e.target.value)}
                placeholder="e.g. Please adjust…"
                rows={3}
              />
            </label>
            <p className="agent-chat-source-control-panel__select-hint placeholder-text">
              Hover a changed line and click <strong>+</strong> — a compact tag is added to the message box. Full diff is sent only when you press Send.
            </p>
            <div className="agent-chat-source-control-panel__diff-list">
              {loading && !diffText ? (
                <p className="placeholder-text">…</p>
              ) : diffBlocks.length > 0 ? (
                diffBlocks.map((block) => (
                  <WorkingTreeDiffFileBlock
                    key={`${block.displayPath}:${block.patchText.slice(0, 80)}`}
                    displayPath={block.displayPath}
                    patchText={block.patchText}
                    diffFile={block.diffFile}
                    onInsertLineReference={insertFromWidget}
                    onRestoreFile={async (path) => {
                      const ok = await restoreFile(path);
                      if (ok) {
                        await load();
                      }
                      return ok;
                    }}
                  />
                ))
              ) : (
                <pre
                  className="agent-chat-source-control-panel__diff agent-chat-source-control-panel__diff--fallback"
                  tabIndex={0}
                  onMouseUp={() => {
                    const t = String(window.getSelection()?.toString() ?? "").trim();
                    if (t) {
                      lastDiffSelectionRef.current = t;
                    }
                  }}
                >
                  {diffText || "(no local changes)"}
                </pre>
              )}
            </div>
            {truncated ? (
              <p className="placeholder-text">Diff was truncated on the server; refresh after committing or splitting changes.</p>
            ) : null}
          </>
        ) : null}
      </div>

      <div className="agent-chat-source-control-panel__footer">
        {hint ? <p className="agent-chat-source-control-panel__error">{hint}</p> : null}
        <button
          type="button"
          className="btn btn-secondary btn-sm agent-chat-source-control-panel__add-btn"
          onClick={appendSelectionToComposer}
          disabled={!isRepository || loading}
        >
          Add selection as tag
        </button>
      </div>
    </aside>
  );
}
