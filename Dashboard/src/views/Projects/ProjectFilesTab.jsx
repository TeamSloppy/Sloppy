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

const MOBILE_FILES_BREAKPOINT_PX = 1000;

function useNarrowProjectFilesLayout() {
  const [narrow, setNarrow] = useState(
    () => typeof window !== "undefined" && window.innerWidth <= MOBILE_FILES_BREAKPOINT_PX
  );

  useEffect(() => {
    const mq = window.matchMedia(`(max-width: ${MOBILE_FILES_BREAKPOINT_PX}px)`);
    const sync = () => setNarrow(mq.matches);
    sync();
    mq.addEventListener("change", sync);
    return () => mq.removeEventListener("change", sync);
  }, []);

  return narrow;
}

function FileSyntaxBlock({ language, fileLoading, fileError, fileContent }) {
  if (fileLoading) {
    return <div className="pft-status">Loading…</div>;
  }
  if (fileError) {
    return <div className="pft-status pft-status-error">{fileError}</div>;
  }
  if (!fileContent) {
    return null;
  }
  return (
    <SyntaxHighlighter
      language={language}
      style={oneDark}
      showLineNumbers
      customStyle={{ margin: 0, borderRadius: 0, background: "transparent", fontSize: "0.82rem" }}
      lineNumberStyle={{ color: "var(--muted)", minWidth: "2.5em" }}
    >
      {fileContent.content}
    </SyntaxHighlighter>
  );
}

function FileTreeNode({ projectId, name, type, path, depth, selectedPath, onSelectFile, narrowLayout }) {
  const [isExpanded, setIsExpanded] = useState(false);
  const [children, setChildren] = useState(null);
  const [isLoading, setIsLoading] = useState(false);

  const isSelected = type === "file" && path === selectedPath;
  const rowPadLeft = narrowLayout ? 12 + depth * 22 : 8 + depth * 16;

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
        className={`pft-node-row ${isSelected ? "selected" : ""} ${narrowLayout ? "pft-node-row--touch" : ""}`}
        style={{ paddingLeft: `${rowPadLeft}px` }}
        onClick={handleClick}
        title={name}
      >
        <span className={`material-symbols-rounded pft-node-icon ${type === "directory" ? "pft-icon-dir" : "pft-icon-file"}`}>
          {icon}
        </span>
        <span className="pft-node-name">{name}</span>
        {isLoading && <span className="pft-node-spinner" />}
        {narrowLayout && (
          <span
            className={`pft-node-chevron ${type === "directory" && isExpanded ? "pft-node-chevron--expanded" : ""}`}
            aria-hidden
          >
            <span className="material-symbols-rounded">chevron_right</span>
          </span>
        )}
      </button>
      {isExpanded && children !== null && (
        <div className="pft-children">
          {children.length === 0 ? (
            <div
              className="pft-empty-dir"
              style={{ paddingLeft: `${(narrowLayout ? 12 : 8) + (depth + 1) * (narrowLayout ? 22 : 16)}px` }}
            >
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
                narrowLayout={narrowLayout}
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
  const narrowLayout = useNarrowProjectFilesLayout();

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

  const closeMobileFile = useCallback(() => {
    if (abortRef.current) abortRef.current.cancelled = true;
    setSelectedPath(null);
    setFileContent(null);
    setFileError(null);
    setFileLoading(false);
  }, []);

  useEffect(() => {
    if (!narrowLayout || !selectedPath) return undefined;
    function onKeyDown(e) {
      if (e.key === "Escape") {
        e.preventDefault();
        closeMobileFile();
      }
    }
    window.addEventListener("keydown", onKeyDown);
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = prevOverflow;
    };
  }, [narrowLayout, selectedPath, closeMobileFile]);

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

  const showMobileFileOverlay = narrowLayout && Boolean(selectedPath);

  const viewerPanel = !selectedPath ? (
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
        <FileSyntaxBlock
          language={language}
          fileLoading={fileLoading}
          fileError={fileError}
          fileContent={fileContent}
        />
      </div>
    </>
  );

  return (
    <section className={`pft-shell${narrowLayout ? " pft-shell--narrow" : ""}`}>
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
                narrowLayout={narrowLayout}
              />
            ))
          )}
        </div>
      </div>

      {!narrowLayout && (
        <div className="pft-viewer-panel">{viewerPanel}</div>
      )}

      {showMobileFileOverlay && (
        <div
          className="pft-mobile-file-overlay"
          role="dialog"
          aria-modal="true"
          aria-labelledby="pft-mobile-file-title"
        >
          <div className="pft-mobile-file-overlay-inner">
            <div className="pft-viewer-head pft-mobile-file-head">
              <button
                type="button"
                className="pft-mobile-file-back"
                onClick={closeMobileFile}
                aria-label="Close file"
              >
                <span className="material-symbols-rounded">arrow_back</span>
              </button>
              <span className="material-symbols-rounded pft-viewer-path-icon">description</span>
              <span className="pft-viewer-path" id="pft-mobile-file-title">
                {selectedPath}
              </span>
            </div>
            <div className="pft-viewer-body pft-mobile-file-body">
              <FileSyntaxBlock
                language={language}
                fileLoading={fileLoading}
                fileError={fileError}
                fileContent={fileContent}
              />
            </div>
          </div>
        </div>
      )}
    </section>
  );
}
