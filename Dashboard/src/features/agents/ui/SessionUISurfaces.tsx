import React, { useEffect, useRef, useState } from "react";
import { buildApiURL } from "../../../shared/api/httpClient";
import {
  fetchAgentUISurfaces,
  submitAgentUIAction,
} from "../../../shared/api/coreApi";
import {
  normalizedValues,
  reconcileDraft,
  validSurface,
  validationErrors,
  type UIDraft,
  type UISurface,
  type UIComponent,
} from "./uiSurface";
import "./uiSurface.css";

function Choices({
  field,
  value,
  disabled,
  onChange,
}: {
  field: UIComponent;
  value: unknown;
  disabled: boolean;
  onChange: (value: unknown) => void;
}) {
  const [open, setOpen] = useState(false);
  const trigger = useRef<HTMLButtonElement>(null);
  const options = field.options || [];
  return (
    <div
      className="actor-team-search a2ui-choice"
      onBlur={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget as Node))
          setOpen(false);
      }}
    >
      <button
        ref={trigger}
        type="button"
        className="actor-team-search-trigger"
        disabled={disabled}
        aria-haspopup="listbox"
        aria-expanded={open}
        onClick={() => setOpen(!open)}
        onKeyDown={(event) => {
          if (["ArrowDown", "ArrowUp"].includes(event.key)) {
            event.preventDefault();
            setOpen(true);
            requestAnimationFrame(() =>
              trigger.current?.parentElement
                ?.querySelector<HTMLButtonElement>("[role=option]")
                ?.focus(),
            );
          }
        }}
      >
        {options.find((option) => option.value === value)?.label || "Choose…"}
      </button>
      {open && (
        <div
          role="listbox"
          aria-label={field.label}
          className="actor-team-dropdown"
        >
          {options.map((option, index) => (
            <button
              key={option.value}
              type="button"
              role="option"
              aria-selected={value === option.value}
              className="actor-team-dropdown-item"
              onClick={() => {
                onChange(option.value);
                setOpen(false);
                trigger.current?.focus();
              }}
              onKeyDown={(event) => {
                if (event.key === "Escape") {
                  setOpen(false);
                  trigger.current?.focus();
                }
                if (
                  ["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)
                ) {
                  event.preventDefault();
                  const nodes =
                    event.currentTarget.parentElement?.querySelectorAll<HTMLButtonElement>(
                      "[role=option]",
                    );
                  const next =
                    event.key === "Home"
                      ? 0
                      : event.key === "End"
                        ? options.length - 1
                        : (index +
                            (event.key === "ArrowDown" ? 1 : -1) +
                            options.length) %
                          options.length;
                  nodes?.[next]?.focus();
                }
              }}
            >
              {option.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
function SurfaceForm({
  surface,
  agentId,
  sessionId,
  apiBase,
  refresh,
}: {
  apiBase: string;
  surface: UISurface;
  agentId: string;
  sessionId: string;
  refresh: () => Promise<void>;
}) {
  const key = `sloppy.a2ui:${apiBase}:${agentId}:${sessionId}:${surface.surfaceId}`;
  const [draft, setDraft] = useState<UIDraft>(() => {
    try {
      return reconcileDraft(
        surface,
        JSON.parse(localStorage.getItem(key) || "null") || undefined,
      );
    } catch {
      return reconcileDraft(surface);
    }
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  useEffect(() => {
    setDraft((previous) => reconcileDraft(surface, previous));
  }, [surface.revision, surface.submittedActionId]);
  useEffect(() => {
    try {
      if (surface.submittedActionId) localStorage.removeItem(key);
      else localStorage.setItem(key, JSON.stringify(draft));
    } catch {
      /* Editing remains available without storage. */
    }
  }, [draft, key, surface.submittedActionId]);
  const errors = validationErrors(surface, draft.values);
  const submitted = !!surface.submittedActionId;
  const locked = busy || submitted || !!draft.pending;
  function change(path: string, value: unknown) {
    setDraft((previous) => ({
      ...previous,
      values: { ...previous.values, [path]: value },
    }));
  }
  async function submit(componentId: string) {
    if (busy || submitted || Object.keys(errors).length) return;
    const pending = draft.pending || {
      actionId: crypto.randomUUID(),
      revision: surface.revision,
      componentId,
      values: normalizedValues(surface, draft.values),
    };
    const next = { ...draft, pending };
    setDraft(next);
    setBusy(true);
    setError("");
    try {
      localStorage.setItem(key, JSON.stringify(next));
    } catch {
      /* Optional persistence. */
    }
    try {
      await submitAgentUIAction(
        agentId,
        sessionId,
        surface.surfaceId,
        pending,
        apiBase,
      );
      await refresh();
    } catch (failure: any) {
      setError(failure.message || "Could not send response");
      if (failure.status === 400 || failure.status === 409) {
        setDraft((previous) => ({ ...previous, pending: undefined }));
        await refresh().catch(() => {});
      }
    } finally {
      setBusy(false);
    }
  }
  function render(id: string): React.ReactNode {
    const field = surface.components.find((c) => c.id === id);
    if (!field) return null;
    const path = field.binding || "";
    if (field.component === "Text") return <p key={id}>{field.text}</p>;
    if (field.component === "Column" || field.component === "Row")
      return (
        <div key={id} className={`a2ui-${field.component.toLowerCase()}`}>
          {field.children?.map(render)}
        </div>
      );
    if (field.component === "Button")
      return (
        <button
          key={id}
          type="button"
          className="a2ui-submit"
          disabled={busy || submitted || !!Object.keys(errors).length}
          onClick={() => void submit(id)}
        >
          {submitted
            ? "Response sent"
            : busy
              ? "Sending…"
              : draft.pending
                ? "Retry send"
                : field.label}
        </button>
      );
    return (
      <label key={id} className="a2ui-field">
        {field.label}
        {field.required ? " *" : ""}
        {field.component === "CheckBox" ? (
          <input
            data-testid={`a2ui-${id}`}
            type="checkbox"
            disabled={locked}
            checked={draft.values[path] === true}
            onChange={(event) => change(path, event.target.checked)}
          />
        ) : field.component === "ChoicePicker" ? (
          <Choices
            field={field}
            value={draft.values[path]}
            disabled={locked}
            onChange={(value) => change(path, value)}
          />
        ) : (
          <input
            data-testid={`a2ui-${id}`}
            type={field.inputType === "number" ? "number" : "text"}
            min={field.minimum}
            max={field.maximum}
            disabled={locked}
            aria-invalid={!!errors[path]}
            value={draft.values[path] == null ? "" : String(draft.values[path])}
            onChange={(event) =>
              change(
                path,
                field.inputType === "number" && event.target.validity.badInput
                  ? "Invalid number"
                  : event.target.value,
              )
            }
          />
        )}
        {errors[path] && <small role="status">{errors[path]}</small>}
      </label>
    );
  }
  return (
    <section className="a2ui-surface" aria-label="Interactive form">
      {render("root")}
      {error && <p role="alert">{error}</p>}
    </section>
  );
}
export function SessionUISurfaces({
  agentId,
  sessionId,
}: {
  agentId: string;
  sessionId?: string;
}) {
  const [surfaces, setSurfaces] = useState<UISurface[]>([]);
  const apiBase = buildApiURL("/").replace(/\/+$/, "");
  const current = useRef("");
  const sequence = useRef(0);
  async function refresh() {
    if (!sessionId) return;
    const scope = `${apiBase}:${agentId}:${sessionId}`;
    const request = ++sequence.current;
    const data = await fetchAgentUISurfaces(agentId, sessionId, apiBase);
    if (current.current === scope && request === sequence.current) {
      const valid = data.filter(validSurface);
      setSurfaces((previous) => {
        for (const old of previous)
          if (
            !valid.some(
              (s) => s.surfaceId === old.surfaceId && !s.submittedActionId,
            )
          ) {
            try {
              localStorage.removeItem(
                `sloppy.a2ui:${apiBase}:${agentId}:${sessionId}:${old.surfaceId}`,
              );
            } catch {
              /* Optional storage. */
            }
          }
        return valid.filter((surface) => !surface.submittedActionId);
      });
    }
  }
  useEffect(() => {
    current.current = `${apiBase}:${agentId}:${sessionId}`;
    sequence.current++;
    setSurfaces([]);
    let active = true;
    async function poll() {
      while (active && sessionId) {
        await refresh().catch(() => {});
        await new Promise((resolve) => setTimeout(resolve, 1500));
      }
    }
    void poll();
    return () => {
      active = false;
      current.current = "";
    };
  }, [apiBase, agentId, sessionId]);
  if (!surfaces.length) return null;
  return (
    <div className="a2ui-panel">
      {surfaces.map((surface) => (
        <SurfaceForm
          key={`${apiBase}:${agentId}:${sessionId}:${surface.surfaceId}`}
          apiBase={apiBase}
          surface={surface}
          agentId={agentId}
          sessionId={sessionId!}
          refresh={refresh}
        />
      ))}
    </div>
  );
}
