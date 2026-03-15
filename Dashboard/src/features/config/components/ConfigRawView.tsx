import React, { useState, useMemo, useRef } from "react";
import { DiffView, DiffModeEnum } from "@git-diff-view/react";
import { generateDiffFile } from "@git-diff-view/file";
import { Prism as SyntaxHighlighter } from "react-syntax-highlighter";
import { oneDark } from "react-syntax-highlighter/dist/esm/styles/prism";
import "@git-diff-view/react/styles/diff-view.css";

interface ConfigRawViewProps {
  rawConfig: string;
  savedConfig: object;
  onChange: (value: string) => void;
}

export function ConfigRawView({ rawConfig, savedConfig, onChange }: ConfigRawViewProps) {
  const [showDiff, setShowDiff] = useState(false);
  const highlightRef = useRef<HTMLDivElement>(null);

  const diffFile = useMemo(() => {
    if (!showDiff) return null;
    const oldContent = JSON.stringify(savedConfig, null, 2);
    const file = generateDiffFile(
      "config.json", oldContent,
      "config.json", rawConfig,
      "json", "json"
    );
    file.initTheme("dark");
    file.init();
    file.buildSplitDiffLines();
    file.buildUnifiedDiffLines();
    return file;
  }, [showDiff, savedConfig, rawConfig]);

  const handleScroll = (e: React.UIEvent<HTMLTextAreaElement>) => {
    if (highlightRef.current) {
      highlightRef.current.scrollTop = e.currentTarget.scrollTop;
      highlightRef.current.scrollLeft = e.currentTarget.scrollLeft;
    }
  };

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
      {showDiff && diffFile ? (
        <div className="settings-raw-diff-container">
          <DiffView
            diffFile={diffFile}
            diffViewMode={DiffModeEnum.Split}
            diffViewTheme="dark"
            diffViewHighlight
            diffViewWrap
            diffViewFontSize={13}
          />
        </div>
      ) : (
        <div className="settings-raw-editor-container">
          <div ref={highlightRef} className="settings-raw-editor-highlight">
            <SyntaxHighlighter
              language="json"
              style={oneDark}
              customStyle={{
                margin: 0,
                padding: 0,
                background: "transparent",
                fontSize: "inherit",
                lineHeight: "inherit",
                fontFamily: "inherit",
              }}
            >
              {rawConfig}
            </SyntaxHighlighter>
          </div>
          <textarea
            className="settings-raw-editor-input"
            value={rawConfig}
            spellCheck={false}
            onChange={(event) => onChange(event.target.value)}
            onScroll={handleScroll}
          />
        </div>
      )}
    </div>
  );
}
