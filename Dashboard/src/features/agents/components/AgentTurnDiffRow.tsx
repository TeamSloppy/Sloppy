import { useState } from "react";

export interface AgentTurnDiff {
  files: {
    path: string;
    attribution: "verified" | "interleaved" | "limited";
    patch?: string;
    additions: number;
    deletions: number;
  }[];
  truncated: boolean;
}

export function AgentTurnDiffRow({ diff }: { diff: AgentTurnDiff }) {
  const [open, setOpen] = useState(false);
  const added = diff.files.reduce((total, file) => total + file.additions, 0);
  const removed = diff.files.reduce((total, file) => total + file.deletions, 0);
  const interleaved = diff.files.some((file) => file.attribution === "interleaved");
  return (
    <details className="agent-chat-turn-diff" data-testid="agent-turn-diff" onToggle={(event) => setOpen(event.currentTarget.open)}>
      <summary>
        Changes this turn · {diff.files.length} files · +{added} −{removed}
        {interleaved ? " · Some files changed outside this turn" : null}
        {diff.truncated ? " · Diff limit reached" : null}
      </summary>
      {open ? diff.files.map((file) => (
        <section key={file.path} className="agent-chat-turn-diff-file">
          <code>{file.path}</code>
          {file.attribution === "interleaved" ? <p>The file changed outside this turn.</p> : null}
          {file.attribution === "limited" ? <p>This file exceeded the diff limit.</p> : null}
          {file.patch ? <pre className="agent-chat-expandable-pre">{file.patch}</pre> : null}
        </section>
      )) : null}
    </details>
  );
}
