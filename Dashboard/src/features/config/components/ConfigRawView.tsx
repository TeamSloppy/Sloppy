import React, { useState } from "react";
import ReactDiffViewer, { DiffMethod } from "react-diff-viewer-continued";
import Prism from "prismjs";
import "prismjs/components/prism-json";

interface ConfigRawViewProps {
  rawConfig: string;
  savedConfig: object;
  onChange: (value: string) => void;
}

export function ConfigRawView({ rawConfig, savedConfig, onChange }: ConfigRawViewProps) {
  const [showDiff, setShowDiff] = useState(false);

  return (
    <div className="settings-raw-pane">
      <div className="settings-raw-toolbar">
        <div className="settings-raw-toggle-group">
          <span>Show Diff</span>
          <label className="agent-tools-switch">
            <input type="checkbox" checked={showDiff} onChange={(e) => setShowDiff(e.target.checked)} />
            <div className="agent-tools-switch-track" />
          </label>
        </div>
      </div>
      {showDiff ? (
        <div className="settings-raw-diff-container">
          <ReactDiffViewer
            oldValue={JSON.stringify(savedConfig, null, 2)}
            newValue={rawConfig}
            splitView={true}
            useDarkTheme={true}
            compareMethod={DiffMethod.LINES}
            renderContent={(str) => (
              <pre
                style={{ display: "inline" }}
                dangerouslySetInnerHTML={{
                  __html: Prism.highlight(str || "", Prism.languages.json, "json")
                }}
              />
            )}
          />
        </div>
      ) : (
        <div className="settings-raw-editor-container">
          <div
            className="settings-raw-editor-highlight"
            dangerouslySetInnerHTML={{
              __html: Prism.highlight(rawConfig, Prism.languages.json, "json") + "\n"
            }}
          />
          <textarea
            className="settings-raw-editor-input"
            value={rawConfig}
            spellCheck={false}
            onChange={(event) => onChange(event.target.value)}
            onScroll={(e) => {
              const highlight = e.currentTarget.parentElement?.querySelector(".settings-raw-editor-highlight");
              if (highlight) {
                (highlight as HTMLElement).scrollTop = e.currentTarget.scrollTop;
                (highlight as HTMLElement).scrollLeft = e.currentTarget.scrollLeft;
              }
            }}
          />
        </div>
      )}
    </div>
  );
}
