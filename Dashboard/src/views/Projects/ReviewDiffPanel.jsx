import React, { useMemo, useState, useCallback } from "react";
import { DiffView, DiffModeEnum, DiffFile } from "@git-diff-view/react";
import "@git-diff-view/react/styles/diff-view.css";
import { ReviewCommentWidget, ReviewCommentBadge } from "./ReviewLineComments";

function parseDiffIntoFiles(rawDiff) {
  if (!rawDiff || !rawDiff.trim()) return [];

  const files = [];
  const sections = rawDiff.split(/(?=^diff --git )/m).filter(Boolean);

  for (const section of sections) {
    const lines = section.split("\n");
    const headerLine = lines[0] || "";
    const fileMatch = headerLine.match(/^diff --git a\/(.+) b\/(.+)$/);
    if (!fileMatch) continue;

    const oldFileName = fileMatch[1];
    const newFileName = fileMatch[2];

    let i = 1;
    while (i < lines.length && !lines[i].startsWith("@@")) {
      i++;
    }

    const hunksRaw = lines.slice(i).join("\n");
    const hunks = hunksRaw.split(/(?=^@@)/m).filter((h) => h.trim());

    if (hunks.length === 0) continue;

    let additions = 0;
    let deletions = 0;
    for (const line of lines) {
      if (line.startsWith("+") && !line.startsWith("+++")) additions++;
      if (line.startsWith("-") && !line.startsWith("---")) deletions++;
    }

    files.push({
      oldFileName,
      newFileName,
      hunks,
      additions,
      deletions
    });
  }

  return files;
}

function getFileExtension(fileName) {
  const ext = String(fileName || "").split(".").pop() || "";
  return ext.toLowerCase();
}

function FileTreeItem({ file, isSelected, onSelect, commentCount }) {
  const additions = file.additions || 0;
  const deletions = file.deletions || 0;

  return (
    <button
      type="button"
      className={`review-file-tree-item ${isSelected ? "active" : ""}`}
      onClick={() => onSelect(file.newFileName)}
      title={file.newFileName}
    >
      <span className="review-file-tree-name">{file.newFileName.split("/").pop()}</span>
      <div className="review-file-tree-meta">
        {additions > 0 && <span className="review-file-tree-add">+{additions}</span>}
        {deletions > 0 && <span className="review-file-tree-del">-{deletions}</span>}
        {commentCount > 0 && <ReviewCommentBadge count={commentCount} />}
      </div>
    </button>
  );
}

export function ReviewDiffPanel({ rawDiff, hasChanges, branchName, comments, onAddComment, onResolveComment, onDeleteComment }) {
  const [viewMode, setViewMode] = useState("unified");
  const [selectedFile, setSelectedFile] = useState(null);
  const [openWidgets, setOpenWidgets] = useState({});

  const files = useMemo(() => parseDiffIntoFiles(rawDiff), [rawDiff]);

  const activeFile = useMemo(() => {
    if (!files.length) return null;
    if (selectedFile) {
      return files.find((f) => f.newFileName === selectedFile) || files[0];
    }
    return files[0];
  }, [files, selectedFile]);

  const diffMode = viewMode === "split" ? DiffModeEnum.Split : DiffModeEnum.Unified;

  const diffFile = useMemo(() => {
    if (!activeFile) return null;
    try {
      const instance = DiffFile.createInstance({
        oldFile: { fileName: activeFile.oldFileName },
        newFile: { fileName: activeFile.newFileName },
        hunks: activeFile.hunks
      });
      instance.init();
      instance.buildSplitDiffLines();
      instance.buildUnifiedDiffLines();
      return instance;
    } catch {
      return null;
    }
  }, [activeFile]);

  const commentCountByFile = useMemo(() => {
    const counts = {};
    for (const c of comments || []) {
      const key = c.filePath;
      counts[key] = (counts[key] || 0) + 1;
    }
    return counts;
  }, [comments]);

  const widgetKey = useCallback((lineNumber, side) => `${lineNumber}:${side}`, []);

  function openWidget(lineNumber, side) {
    const key = widgetKey(lineNumber, side);
    setOpenWidgets((prev) => ({ ...prev, [key]: true }));
  }

  function closeWidget(lineNumber, side) {
    const key = widgetKey(lineNumber, side);
    setOpenWidgets((prev) => {
      const next = { ...prev };
      delete next[key];
      return next;
    });
  }

  function handleAddWidgetClick(lineNumber, side) {
    openWidget(lineNumber, side);
  }

  function renderWidgetLine({ lineNumber, side, onClose }) {
    const filePath = activeFile?.newFileName || "";
    const sideStr = side === 1 ? "old" : "new";
    const key = widgetKey(lineNumber, side);
    if (!openWidgets[key]) return null;

    return (
      <ReviewCommentWidget
        filePath={filePath}
        lineNumber={lineNumber}
        side={sideStr}
        comments={comments || []}
        onAdd={async (payload) => {
          await onAddComment(payload);
          closeWidget(lineNumber, side);
          onClose();
        }}
        onResolve={(commentId, resolved) => onResolveComment(commentId, resolved)}
        onDelete={(commentId) => onDeleteComment(commentId)}
        onClose={() => {
          closeWidget(lineNumber, side);
          onClose();
        }}
      />
    );
  }

  if (!rawDiff || files.length === 0) {
    const emptyMessage = branchName && !hasChanges
      ? `Branch ${branchName} exists but no changes were committed.`
      : "No diff available. The task may not have a git worktree branch.";
    return (
      <div className="review-diff-empty">
        <span className="material-symbols-rounded" aria-hidden="true">compare_arrows</span>
        <p>{emptyMessage}</p>
      </div>
    );
  }

  return (
    <div className="review-diff-panel">
      <div className="review-diff-toolbar">
        <div className="review-diff-file-count">
          <span className="material-symbols-rounded" aria-hidden="true">folder_open</span>
          {files.length} file{files.length !== 1 ? "s" : ""} changed
        </div>
        <div className="review-diff-mode-toggle">
          <button
            type="button"
            className={`review-mode-btn ${viewMode === "unified" ? "active" : ""}`}
            onClick={() => setViewMode("unified")}
            title="Unified diff"
          >
            <span className="material-symbols-rounded" aria-hidden="true">format_align_left</span>
            Unified
          </button>
          <button
            type="button"
            className={`review-mode-btn ${viewMode === "split" ? "active" : ""}`}
            onClick={() => setViewMode("split")}
            title="Side-by-side diff"
          >
            <span className="material-symbols-rounded" aria-hidden="true">view_column</span>
            Split
          </button>
        </div>
      </div>

      <div className="review-diff-layout">
        <aside className="review-file-tree">
          {files.map((file) => (
            <FileTreeItem
              key={file.newFileName}
              file={file}
              isSelected={activeFile?.newFileName === file.newFileName}
              onSelect={setSelectedFile}
              commentCount={commentCountByFile[file.newFileName] || 0}
            />
          ))}
        </aside>

        <div className="review-diff-content">
          {activeFile && (
            <div className="review-diff-file-header">
              <span className="material-symbols-rounded" aria-hidden="true">description</span>
              <span className="review-diff-file-path">{activeFile.newFileName}</span>
              <span className="review-file-tree-add">+{activeFile.additions}</span>
              <span className="review-file-tree-del">-{activeFile.deletions}</span>
            </div>
          )}

          {diffFile ? (
            <div className="review-diff-view-wrap">
              <DiffView
                key={`${activeFile?.newFileName}:${viewMode}`}
                diffFile={diffFile}
                diffViewMode={diffMode}
                diffViewTheme="dark"
                diffViewAddWidget={true}
                onAddWidgetClick={handleAddWidgetClick}
                renderWidgetLine={renderWidgetLine}
              />
            </div>
          ) : (
            <div className="review-diff-empty">
              <p className="placeholder-text">Could not render diff for this file.</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
