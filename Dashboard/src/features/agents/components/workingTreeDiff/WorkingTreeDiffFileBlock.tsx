import React, { useState } from "react";
import { DiffView, DiffModeEnum, SplitSide } from "@git-diff-view/react";
import type { DiffFile } from "@git-diff-view/file";
import type { SourceControlComposeTagPayload } from "./sourceControlComposeTypes";
import "@git-diff-view/react/styles/diff-view.css";

type Props = {
  displayPath: string;
  patchText: string;
  diffFile: DiffFile;
  onInsertLineReference: (payload: SourceControlComposeTagPayload) => void;
  onRestoreFile: (relativePath: string) => Promise<boolean>;
};

export function WorkingTreeDiffFileBlock({
  displayPath,
  patchText,
  diffFile,
  onInsertLineReference,
  onRestoreFile
}: Props) {
  const [expanded, setExpanded] = useState(true);
  const [restoring, setRestoring] = useState(false);
  const [restoreHint, setRestoreHint] = useState<string | null>(null);

  async function handleRestore() {
    setRestoreHint(null);
    setRestoring(true);
    try {
      const ok = await onRestoreFile(displayPath);
      setRestoreHint(ok ? null : "Could not restore (see server logs).");
    } finally {
      setRestoring(false);
    }
  }

  function handleAddWidgetClick(lineNumber: number, side: SplitSide) {
    const sideLabel = side === SplitSide.new ? "new" : "old";
    const label = `@${displayPath}:${lineNumber} (${sideLabel})`;
    const clip = patchText.length > 14_000 ? `${patchText.slice(0, 14_000)}\n…(truncated)` : patchText;
    const markdown = `${label}\n\n\`\`\`diff\n${clip}\n\`\`\`\n`;
    onInsertLineReference({ label, markdown });
  }

  return (
    <section
      className={`agent-chat-source-control-file${expanded ? "" : " agent-chat-source-control-file--collapsed"}`}
      data-testid={`source-control-diff-file-${encodeURIComponent(displayPath)}`}
    >
      <header className="agent-chat-source-control-file__head">
        <button
          type="button"
          className="agent-chat-source-control-file__collapse-btn"
          onClick={() => setExpanded((v) => !v)}
          aria-expanded={expanded}
          title={expanded ? "Collapse diff" : "Expand diff"}
        >
          <span className="material-symbols-rounded" aria-hidden="true">
            {expanded ? "expand_less" : "expand_more"}
          </span>
        </button>
        <span className="agent-chat-source-control-file__path" title={displayPath}>
          {displayPath}
        </span>
        <div className="agent-chat-source-control-file__actions">
          <button
            type="button"
            className="agent-chat-source-control-file__icon-btn"
            title="Copy path"
            onClick={() => {
              void navigator.clipboard.writeText(displayPath);
            }}
          >
            <span className="material-symbols-rounded" aria-hidden="true">
              content_copy
            </span>
          </button>
          <button
            type="button"
            className="agent-chat-source-control-file__icon-btn"
            title="Restore file through source control"
            disabled={restoring}
            onClick={() => void handleRestore()}
          >
            <span className="material-symbols-rounded" aria-hidden="true">
              undo
            </span>
          </button>
        </div>
      </header>
      {expanded ? (
        <>
          {restoreHint ? <p className="agent-chat-source-control-file__hint">{restoreHint}</p> : null}
          <div className="agent-chat-source-control-file__diff-wrap">
            <DiffView
              diffFile={diffFile}
              diffViewMode={DiffModeEnum.Unified}
              diffViewTheme="dark"
              diffViewHighlight
              diffViewWrap
              diffViewFontSize={12}
              diffViewAddWidget
              onAddWidgetClick={handleAddWidgetClick}
            />
          </div>
        </>
      ) : restoreHint ? (
        <p className="agent-chat-source-control-file__hint">{restoreHint}</p>
      ) : null}
    </section>
  );
}
