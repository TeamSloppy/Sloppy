import React from "react";

export interface GeneratedAgentFiles {
  agentsMarkdown: string;
  identityMarkdown: string;
  soulMarkdown: string;
  userMarkdown: string;
}

const PREVIEW_FILES = [
  { id: "agentsMarkdown" as keyof GeneratedAgentFiles, name: "AGENTS.md", icon: "smart_toy" },
  { id: "identityMarkdown" as keyof GeneratedAgentFiles, name: "Identity.md", icon: "badge" },
  { id: "soulMarkdown" as keyof GeneratedAgentFiles, name: "Soul.md", icon: "psychology" },
  { id: "userMarkdown" as keyof GeneratedAgentFiles, name: "User.md", icon: "person" }
];

interface AgentGeneratePreviewProps {
  files: GeneratedAgentFiles;
  onFilesChange: (files: GeneratedAgentFiles) => void;
  onBack: () => void;
  onDone: () => void;
  isSubmitting: boolean;
  submitLabel?: string;
}

export function AgentGeneratePreview({
  files,
  onFilesChange,
  onBack,
  onDone,
  isSubmitting,
  submitLabel = "Done"
}: AgentGeneratePreviewProps) {
  const [selectedFile, setSelectedFile] = React.useState<keyof GeneratedAgentFiles>("agentsMarkdown");

  const activeFile = PREVIEW_FILES.find((f) => f.id === selectedFile) || PREVIEW_FILES[0];

  function updateFile(id: keyof GeneratedAgentFiles, value: string) {
    onFilesChange({ ...files, [id]: value });
  }

  return (
    <div className="agent-modal-overlay" onClick={(e) => e.stopPropagation()}>
      <section className="agent-modal-card agent-generate-preview-card" onClick={(e) => e.stopPropagation()}>
        <div className="agent-modal-head">
          <h3>Review Generated Files</h3>
          <span className="agent-field-note">Review and edit the generated files before creating the agent.</span>
        </div>

        <div className="agent-doc-files">
          <nav className="agent-doc-files-nav">
            {PREVIEW_FILES.map((file) => {
              const isActive = file.id === activeFile.id;
              const hasContent = Boolean(files[file.id]?.trim());
              return (
                <button
                  key={file.id}
                  type="button"
                  className={`agent-doc-files-item ${isActive ? "active" : ""}`}
                  onClick={() => setSelectedFile(file.id)}
                >
                  <span className="material-symbols-rounded agent-doc-files-icon">{file.icon}</span>
                  <span className="agent-doc-files-name">{file.name}</span>
                  {!hasContent && <span className="agent-doc-files-empty">empty</span>}
                </button>
              );
            })}
          </nav>
          <div className="agent-doc-files-editor">
            <label>
              {activeFile.name}
              <textarea
                rows={16}
                value={files[activeFile.id]}
                onChange={(event) => updateFile(activeFile.id, event.target.value)}
              />
            </label>
          </div>
        </div>

        <div className="agent-modal-actions">
          <button type="button" onClick={onBack} disabled={isSubmitting}>
            Back
          </button>
          <button
            type="button"
            className="agent-create-confirm hover-levitate"
            onClick={onDone}
            disabled={isSubmitting}
          >
            {isSubmitting ? "Creating…" : submitLabel}
          </button>
        </div>
      </section>
    </div>
  );
}
