import React from "react";
import { ChatApprovalModePicker } from "../../agents/components/ChatApprovalModePicker";
import type { SessionApprovalMode } from "../../../shared/api/coreApi";
import "./chatApprovalDefaults.css";

export function ChatApprovalDefaultsEditor({ mode, onChange }: {
  mode: SessionApprovalMode;
  onChange: (mode: SessionApprovalMode) => void;
}) {
  return <section className="chat-approval-default-settings" aria-label="New chat defaults">
    <h3>Default approval mode</h3>
    <ChatApprovalModePicker mode={mode} busy={false} disabled={false} error="" unavailable={false}
      onSelect={onChange} onRetry={() => {}} />
    <p>Applies to new chats on this server in ClientNative, Dashboard and TUI. Existing chats keep their mode; delegated sessions inherit their parent chat.</p>
  </section>;
}
