import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Prism as SyntaxHighlighter } from "react-syntax-highlighter";
import { oneDark } from "react-syntax-highlighter/dist/esm/styles/prism";
import { fetchProjectFiles, fetchProjectFileContent } from "../../api";

const EXTENSION_LANGUAGE_MAP = {
  js: "javascript",
  jsx: "jsx",
  ts: "typescript",
  tsx: "tsx",
  swift: "swift",
  py: "python",
  rb: "ruby",
  go: "go",
  rs: "rust",
  java: "java",
  kt: "kotlin",
  cs: "csharp",
  cpp: "cpp",
  c: "c",
  h: "c",
  hpp: "cpp",
  sh: "bash",
  bash: "bash",
  zsh: "bash",
  json: "json",
  yaml: "yaml",
  yml: "yaml",
  toml: "toml",
  md: "markdown",
  mdx: "markdown",
  html: "html",
  htm: "html",
  xml: "xml",
  css: "css",
  scss: "scss",
  sass: "sass",
  sql: "sql",
  graphql: "graphql",
  tf: "hcl",
  dockerfile: "dockerfile",
  makefile: "makefile",
  txt: "text"
};

function languageForPath(path) {
  if (!path) return "text";
  const filename = path.split("/").pop() || "";
  const lower = filename.toLowerCase();
  if (lower === "dockerfile") return "dockerfile";
  if (lower === "makefile") return "makefile";
  const dotIdx = filename.lastIndexOf(".");
  if (dotIdx < 0) return "text";
  const ext = filename.slice(dotIdx + 1).toLowerCase();
  return EXTENSION_LANGUAGE_MAP[ext] || "text";
}

function FileTreeNode({ projectId, name, type, path, depth, selectedPath, onSelectFile }) {
  const [isExpanded, setIsExpanded] = useState(false);
  const [children, setChildren] = useState(null);
  const [isLoading, setIsLoading] = useState(false);

  const isSelected = type === "file" && path === selectedPath;

  async function handleExpand() {
    if (type !== "directory") return;
    const next = !isExpanded;
    setIsExpanded(next);
    if (next && children === null) {
      setIsLoading(true);
      const entries = await fetchProjectFiles(projectId, path);
      setChildren(entries || []);
      setIsLoading(false);
    }
  }

  function handleClick() {
    if (type === "directory") {
      handleExpand();
    } else {
      onSelectFile(path);
    }
  }

  const icon = type === "directory"
    ? (isExpanded ? "folder_open" : "folder")
    : "description";

  return (
    <div className="pft-node">
      <button
        type="button"
        className={`pft-node-row ${isSelected ? "selected" : ""}`}
        style={{ paddingLeft: `${8 + depth * 16}px` }}
        onClick={handleClick}
        title={name}
      >
        <span className={`material-symbols-rounded pft-node-icon ${type === "directory" ? "pft-icon-dir" : "pft-icon-file"}`}>
          {icon}
        </span>
        <span className="pft-node-name">{name}</span>
        {isLoading && <span className="pft-node-spinner" />}
      </button>
      {isExpanded && children !== null && (
        <div className="pft-children">
          {children.length === 0 ? (
            <div className="pft-empty-dir" style={{ paddingLeft: `${8 + (depth + 1) * 16}px` }}>
              Empty
            </div>
          ) : (
            children.map((child) => (
              <FileTreeNode
                key={child.name}
                projectId={projectId}
                name={child.name}
                type={child.type}
                path={path ? `${path}/${child.name}` : child.name}
                depth={depth + 1}
                selectedPath={selectedPath}
                onSelectFile={onSelectFile}
              />
            ))
          )}
        </div>
      )}
    </div>
  );
}

export function ProjectFilesTab({ project }) {
  const [rootEntries, setRootEntries] = useState(null);
  const [rootLoading, setRootLoading] = useState(true);
  const [selectedPath, setSelectedPath] = useState(null);
  const [fileContent, setFileContent] = useState(null);
  const [fileLoading, setFileLoading] = useState(false);
  const [fileError, setFileError] = useState(null);
  const abortRef = useRef(null);

  useEffect(() => {
    let cancelled = false;
    setRootLoading(true);
    fetchProjectFiles(project.id, "").then((entries) => {
      if (!cancelled) {
        setRootEntries(entries || []);
        setRootLoading(false);
      }
    });
    return () => { cancelled = true; };
  }, [project.id]);

  const loadFile = useCallback(async (path) => {
    if (abortRef.current) abortRef.current.cancelled = true;
    const token = { cancelled: false };
    abortRef.current = token;

    setSelectedPath(path);
    setFileContent(null);
    setFileError(null);
    setFileLoading(true);

    const result = await fetchProjectFileContent(project.id, path);
    if (token.cancelled) return;

    if (!result) {
      setFileError("Unable to load file. It may be binary or too large.");
    } else {
      setFileContent(result);
    }
    setFileLoading(false);
  }, [project.id]);

  const language = useMemo(() => languageForPath(selectedPath), [selectedPath]);

  return (
    <section className="pft-shell">
      <div className="pft-tree-panel">
        <div className="pft-tree-head">
          <span className="material-symbols-rounded pft-tree-head-icon">folder</span>
          <span className="pft-tree-head-label">{project.name}</span>
        </div>
        <div className="pft-tree-body">
          {rootLoading ? (
            <div className="pft-status">Loading…</div>
          ) : rootEntries === null ? (
            <div className="pft-status pft-status-error">Failed to load files.</div>
          ) : rootEntries.length === 0 ? (
            <div className="pft-status">No files found.</div>
          ) : (
            rootEntries.map((entry) => (
              <FileTreeNode
                key={entry.name}
                projectId={project.id}
                name={entry.name}
                type={entry.type}
                path={entry.name}
                depth={0}
                selectedPath={selectedPath}
                onSelectFile={loadFile}
              />
            ))
          )}
        </div>
      </div>

      <div className="pft-viewer-panel">
        {!selectedPath ? (
          <div className="pft-viewer-empty">
            <span className="material-symbols-rounded pft-viewer-empty-icon">description</span>
            <p>Select a file to view its contents</p>
          </div>
        ) : (
          <>
            <div className="pft-viewer-head">
              <span className="material-symbols-rounded pft-viewer-path-icon">description</span>
              <span className="pft-viewer-path">{selectedPath}</span>
            </div>
            <div className="pft-viewer-body">
              {fileLoading ? (
                <div className="pft-status">Loading…</div>
              ) : fileError ? (
                <div className="pft-status pft-status-error">{fileError}</div>
              ) : fileContent ? (
                <SyntaxHighlighter
                  language={language}
                  style={oneDark}
                  showLineNumbers
                  customStyle={{ margin: 0, borderRadius: 0, background: "transparent", fontSize: "0.82rem" }}
                  lineNumberStyle={{ color: "var(--muted)", minWidth: "2.5em" }}
                >
                  {fileContent.content}
                </SyntaxHighlighter>
              ) : null}
            </div>
          </>
        )}
      </div>
    </section>
  );
}
