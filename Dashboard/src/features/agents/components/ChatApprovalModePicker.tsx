import React, { useEffect, useLayoutEffect, useRef, useState } from "react";
import { CHAT_APPROVAL_MODES } from "../model/useChatApprovalPolicy";
import type { SessionApprovalMode } from "../../../shared/api/coreApi";
import "./chatApprovalMode.css";

export function ChatApprovalModePicker({ mode, busy, disabled, error, unavailable, onSelect, onRetry }: {
  mode: SessionApprovalMode;
  busy: boolean;
  disabled: boolean;
  error: string;
  unavailable: boolean;
  onSelect: (mode: SessionApprovalMode) => void;
  onRetry: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [position, setPosition] = useState({ left: 16, bottom: 0 });
  const root = useRef<HTMLDivElement>(null);
  const button = useRef<HTMLButtonElement>(null);
  const selected = CHAT_APPROVAL_MODES.find((item) => item.mode === mode) || CHAT_APPROVAL_MODES[0];

  useLayoutEffect(() => {
    if (!open) return;
    function reposition() {
      const bounds = button.current?.getBoundingClientRect();
      if (!bounds) return;
      const width = Math.min(320, window.innerWidth - 32);
      setPosition({ left: Math.max(16, Math.min(bounds.right - width, window.innerWidth - width - 16)), bottom: window.innerHeight - bounds.top + 8 });
    }
    reposition();
    window.addEventListener("resize", reposition);
    window.addEventListener("scroll", reposition, true);
    return () => {
      window.removeEventListener("resize", reposition);
      window.removeEventListener("scroll", reposition, true);
    };
  }, [open]);

  useEffect(() => {
    if (!open) return;
    function dismiss(event: PointerEvent) {
      if (!root.current?.contains(event.target as Node)) setOpen(false);
    }
    document.addEventListener("pointerdown", dismiss);
    return () => document.removeEventListener("pointerdown", dismiss);
  }, [open]);

  return <div className="actor-team-search-wrap chat-approval-mode" ref={root} onKeyDown={(event) => {
    if (event.key === "Escape") { setOpen(false); button.current?.focus(); }
    if (open && ["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) {
      event.preventDefault();
      const items = Array.from(root.current?.querySelectorAll<HTMLButtonElement>("[role=menuitemradio]") || []);
      const current = items.indexOf(document.activeElement as HTMLButtonElement);
      const index = event.key === "Home" ? 0 : event.key === "End" || (current < 0 && event.key === "ArrowUp") ? items.length - 1
        : (current + (event.key === "ArrowDown" ? 1 : -1) + items.length) % items.length;
      items[index]?.focus();
    }
  }}>
    <button type="button" ref={button} className="actor-team-search chat-approval-mode-trigger" aria-haspopup="menu" aria-expanded={open}
      aria-label={`Approval mode: ${unavailable && error ? "unavailable" : selected.title}`} disabled={disabled || busy}
      title={selected.detail} onClick={() => setOpen(!open)}>
      <span className="material-symbols-rounded" aria-hidden="true">{mode === "approve_for_me" ? "verified_user" : "shield"}</span>
      <span>{busy ? "Updating approvals…" : unavailable && error ? "Approval mode unavailable" : selected.title}</span>
      <span aria-hidden="true">▾</span>
    </button>
    {open && !busy && !disabled && <div className="actor-team-dropdown chat-approval-mode-dropdown" style={position} role="menu" aria-label="Chat approval mode">
      {CHAT_APPROVAL_MODES.map((item) => <button type="button" key={item.mode} role="menuitemradio" aria-checked={mode === item.mode}
        className="actor-team-dropdown-item chat-approval-mode-option" onClick={() => {
          setOpen(false); button.current?.focus(); onSelect(item.mode);
        }}>
        <strong>{item.title}</strong><span>{item.detail}</span>
      </button>)}
    </div>}
    {error && <div className="chat-approval-mode-error" role="alert">{error} <button type="button" disabled={busy} onClick={onRetry}>Retry</button></div>}
  </div>;
}
