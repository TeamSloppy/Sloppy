import React, { useMemo, useState } from "react";
import { selectDirectories } from "../../api";

export function WorkspaceDirectoriesEditor({ paths = [], onChange, minimum = 1 }) {
  const [status, setStatus] = useState("");
  const normalizedPaths = useMemo(
    () => Array.from(new Set((Array.isArray(paths) ? paths : []).map((path) => String(path || "").trim()).filter(Boolean))),
    [paths]
  );

  function move(index, offset) {
    const destination = index + offset;
    if (destination < 0 || destination >= normalizedPaths.length) return;
    const next = [...normalizedPaths];
    [next[index], next[destination]] = [next[destination], next[index]];
    onChange(next);
  }

  async function pick() {
    setStatus("Opening directory picker…");
    const result = await selectDirectories();
    const selected = Array.isArray(result?.paths) ? result.paths : [];
    if (selected.length === 0) {
      setStatus("No directories selected.");
      return;
    }
    onChange(Array.from(new Set([...normalizedPaths, ...selected.map(String)])));
    setStatus("");
  }

  return (
    <div className="workspace-directories-editor">
      <div className="workspace-directories-list">
        {normalizedPaths.map((path, index) => {
          const basename = path.split(/[\\/]/).filter(Boolean).at(-1) || path;
          return (
            <div className="workspace-directory-row" key={path}>
              <span className="material-symbols-rounded" aria-hidden="true">
                {index === 0 ? "looks_one" : "folder"}
              </span>
              <span className="workspace-directory-label">
                <strong>{basename}</strong>
                <small>{index === 0 ? `Primary · ${path}` : path}</small>
              </span>
              <button type="button" onClick={() => move(index, -1)} disabled={index === 0} aria-label="Move up">↑</button>
              <button type="button" onClick={() => move(index, 1)} disabled={index === normalizedPaths.length - 1} aria-label="Move down">↓</button>
              <button type="button" onClick={() => onChange(normalizedPaths.filter((_, itemIndex) => itemIndex !== index))} aria-label="Remove">×</button>
            </div>
          );
        })}
      </div>
      <button type="button" className="secondary" onClick={pick}>
        <span className="material-symbols-rounded" aria-hidden="true">create_new_folder</span>
        Add directories
      </button>
      <span className="project-path-hint">
        The first directory is Primary. {minimum > 1 ? `A workspace requires at least ${minimum}.` : ""} {status}
      </span>
    </div>
  );
}
