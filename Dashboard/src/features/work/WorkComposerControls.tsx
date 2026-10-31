import React, { useEffect, useLayoutEffect, useRef, useState } from "react";
import { ChatApprovalModePicker } from "../agents/components/ChatApprovalModePicker";

type Choice = { id: string; label: string; icon: string };

export function WorkComposerControls({
  modelPicker, extraOptions, approvalPolicy, disabled, canSend, hasContent,
  busy, stopping, onStop, onAttach, onDeepResearch, modes, mode, onModeChange,
  reasoningOptions, reasoning, onReasoningChange, voice, voiceTitle,
  voicePlayback, autoSpeak, onAutoSpeakChange, handsFree, onHandsFreeToggle,
  liveVoice, onLiveToggle
}: {
  modelPicker: React.ReactNode;
  extraOptions?: React.ReactNode;
  approvalPolicy: any;
  disabled: boolean;
  canSend: boolean;
  hasContent: boolean;
  busy: boolean;
  stopping: boolean;
  onStop: () => void;
  onAttach: () => void;
  onDeepResearch: () => void;
  modes: Choice[];
  mode: string;
  onModeChange: (id: string) => void;
  reasoningOptions: Choice[];
  reasoning: string;
  onReasoningChange: (id: string) => void;
  voice: any;
  voiceTitle: string;
  voicePlayback: any;
  autoSpeak: boolean;
  onAutoSpeakChange?: (value: boolean) => void;
  handsFree: any;
  onHandsFreeToggle: () => void;
  liveVoice: any;
  onLiveToggle: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [position, setPosition] = useState({ left: 16, bottom: 60 });
  const root = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);
  const recording = voice.state === "recording";
  const transcribing = voice.state === "transcribing";
  const live = liveVoice.state === "live" || liveVoice.state === "connecting";
  const action = busy ? "stop" : recording ? "recording" : transcribing ? "transcribing" : hasContent ? "send" : "dictate";
  const actionLabel = action === "stop" ? (stopping ? "Stopping…" : "Stop")
    : action === "recording" ? "Stop recording" : action === "transcribing" ? "Transcribing…"
      : action === "send" ? "Send message" : "Dictate message";
  const actionIcon = action === "stop" ? "stop" : action === "recording" ? "stop_circle"
    : action === "transcribing" ? "hourglass_top" : action === "send" ? "arrow_upward" : "mic";
  const actionDisabled = action === "stop" ? stopping : action === "send" ? !canSend
    : action === "transcribing" || disabled || !voice.available || handsFree.active;

  useLayoutEffect(() => {
    if (!open) return;
    const update = () => {
      const bounds = trigger.current?.getBoundingClientRect();
      if (!bounds) return;
      const width = Math.min(300, window.innerWidth - 24);
      setPosition({ left: Math.max(12, Math.min(bounds.left, window.innerWidth - width - 12)), bottom: window.innerHeight - bounds.top + 8 });
    };
    update();
    window.addEventListener("resize", update);
    window.addEventListener("scroll", update, true);
    return () => { window.removeEventListener("resize", update); window.removeEventListener("scroll", update, true); };
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const dismiss = (event: PointerEvent) => {
      if (!root.current?.contains(event.target as Node)) setOpen(false);
    };
    document.addEventListener("pointerdown", dismiss);
    return () => document.removeEventListener("pointerdown", dismiss);
  }, [open]);

  function choose(action: () => void) {
    setOpen(false);
    trigger.current?.focus();
    action();
  }

  return <div className="work-composer-controls">
    <div className="work-composer-options" ref={root} onKeyDown={(event) => {
      if (event.key === "Escape") { setOpen(false); trigger.current?.focus(); }
      if ((event.target as HTMLElement).tagName === "INPUT" || !open || !["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) return;
      event.preventDefault();
      const items = Array.from(root.current?.querySelectorAll<HTMLButtonElement>('[role="menuitem"], [role="menuitemradio"]') || []).filter((item) => !item.disabled);
      const current = items.indexOf(document.activeElement as HTMLButtonElement);
      const index = event.key === "Home" ? 0 : event.key === "End" ? items.length - 1
        : (current + (event.key === "ArrowDown" ? 1 : -1) + items.length) % items.length;
      items[index]?.focus();
    }}>
      <button type="button" className="work-composer-plus" ref={trigger} aria-label="Composer options" aria-haspopup="menu" aria-expanded={open} onClick={() => setOpen((value) => !value)}>
        <span className="material-symbols-rounded" aria-hidden="true">add</span>
      </button>
      {open ? <div className="work-composer-menu" role="menu" aria-label="Composer options" style={position}>
        <button type="button" role="menuitem" disabled={disabled} onClick={() => choose(onAttach)}><span className="material-symbols-rounded" aria-hidden="true">attach_file</span>Attach files</button>
        <button type="button" role="menuitem" disabled={disabled} onClick={() => choose(onDeepResearch)}><span className="material-symbols-rounded" aria-hidden="true">travel_explore</span>Deep Research</button>
        <div className="work-composer-menu-group" role="group" aria-label="Chat mode">
          <span className="work-composer-menu-label">Mode</span>
          {modes.map((item) => <button type="button" role="menuitemradio" key={item.id} aria-checked={mode === item.id} disabled={disabled} onClick={() => choose(() => onModeChange(item.id))}>
            <span className="material-symbols-rounded" aria-hidden="true">{item.icon}</span>{item.label}
            {mode === item.id ? <span className="material-symbols-rounded work-menu-check" aria-hidden="true">check</span> : null}
          </button>)}
        </div>
        {reasoningOptions.length ? <div className="work-composer-menu-group" role="group" aria-label="Reasoning effort">
          <span className="work-composer-menu-label">Reasoning</span>
          {reasoningOptions.map((item) => <button type="button" role="menuitemradio" key={item.id} aria-checked={reasoning === item.id} disabled={disabled} onClick={() => choose(() => onReasoningChange(item.id))}>{item.label}{reasoning === item.id ? " ✓" : ""}</button>)}
        </div> : null}
        {voicePlayback?.available && onAutoSpeakChange ? <button type="button" role="menuitem" onClick={() => choose(() => { if (autoSpeak) voicePlayback.stop(); onAutoSpeakChange(!autoSpeak); })}>{autoSpeak ? "Turn off reading replies aloud" : "Read replies aloud"}</button> : null}
        {handsFree.available || handsFree.active ? <button type="button" role="menuitem" onClick={() => choose(onHandsFreeToggle)}>{handsFree.active ? "Turn off hands-free" : "Turn on hands-free"}</button> : null}
        {liveVoice.available || liveVoice.state !== "idle" ? <button type="button" role="menuitem" onClick={() => choose(onLiveToggle)}>{live ? "End live conversation" : "Start live conversation"}</button> : null}
        {extraOptions ? <div className="work-composer-menu-group work-composer-extra-options">{extraOptions}</div> : null}
      </div> : null}
    </div>
    <ChatApprovalModePicker mode={approvalPolicy.mode} busy={approvalPolicy.busy} disabled={stopping}
      error={approvalPolicy.error} unavailable={!approvalPolicy.known} onSelect={(value) => void approvalPolicy.select(value)} onRetry={approvalPolicy.retry} />
    <div className="work-composer-model">{modelPicker}<span className="material-symbols-rounded work-model-chevron" aria-hidden="true">expand_more</span></div>
    <button type={action === "send" ? "submit" : "button"} className={`work-composer-action ${busy || recording ? "recording" : ""}`}
      data-testid="work-composer-action" aria-label={actionLabel} aria-pressed={recording || undefined} disabled={actionDisabled}
      title={action === "dictate" || recording || transcribing ? voiceTitle : actionLabel}
      onClick={action === "stop" ? onStop : action === "dictate" || action === "recording" ? voice.toggle : undefined}>
      <span className="material-symbols-rounded" aria-hidden="true">{actionIcon}</span>
    </button>
  </div>;
}
