import React, { useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { filterModelsByQuery } from "../../agents/utils/aggregateProviderModels";
import type { AggregatedModelOption } from "../../agents/utils/aggregateProviderModels";

type Props = {
  label: React.ReactNode;
  value: string;
  onChange: (nextId: string) => void;
  aggregatedModels: AggregatedModelOption[];
  placeholder?: string;
  disabled?: boolean;
  hint?: React.ReactNode;
};

/**
 * Searchable floating model picker matching AgentConfigTab "Default Model" (provider-model-picker).
 */
export function AggregatedModelPicker({
  label,
  value,
  onChange,
  aggregatedModels,
  placeholder = "Select model id...",
  disabled = false,
  hint = null
}: Props) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [menuRect, setMenuRect] = useState<{
    top: number;
    left: number;
    width: number;
    maxHeight: number;
  } | null>(null);
  const [query, setQuery] = useState("");
  const pickerRef = useRef<HTMLDivElement | null>(null);
  const menuRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!menuOpen) {
      setQuery(String(value || ""));
    }
  }, [menuOpen, value]);

  useEffect(() => {
    if (!menuOpen) {
      return;
    }

    function syncMenuRect() {
      const picker = pickerRef.current;
      if (!picker) {
        return;
      }
      const rect = picker.getBoundingClientRect();
      const viewportHeight = window.innerHeight || document.documentElement.clientHeight;
      const viewportPadding = 10;
      const menuGap = 6;
      const defaultMaxHeight = 260;
      const minMaxHeight = 140;
      const spaceBelow = viewportHeight - rect.bottom - viewportPadding;
      const spaceAbove = rect.top - viewportPadding;

      let maxHeight = Math.max(minMaxHeight, Math.min(defaultMaxHeight, spaceBelow));
      let top = rect.bottom + menuGap;
      if (spaceBelow < minMaxHeight && spaceAbove > spaceBelow) {
        maxHeight = Math.max(minMaxHeight, Math.min(defaultMaxHeight, spaceAbove - menuGap));
        top = rect.top - menuGap - maxHeight;
      }
      top = Math.max(viewportPadding, Math.round(top));

      setMenuRect({
        top,
        left: Math.round(rect.left),
        width: Math.round(rect.width),
        maxHeight: Math.round(maxHeight)
      });
    }

    function handlePointerDown(event: PointerEvent) {
      const target = event.target as Node;
      const pickerContainsTarget = pickerRef.current?.contains(target);
      const menuContainsTarget = menuRef.current?.contains(target);
      if (!pickerContainsTarget && !menuContainsTarget) {
        setMenuOpen(false);
        setMenuRect(null);
      }
    }

    syncMenuRect();
    window.addEventListener("resize", syncMenuRect);
    window.addEventListener("scroll", syncMenuRect, true);
    window.addEventListener("pointerdown", handlePointerDown);
    return () => {
      window.removeEventListener("resize", syncMenuRect);
      window.removeEventListener("scroll", syncMenuRect, true);
      window.removeEventListener("pointerdown", handlePointerDown);
    };
  }, [menuOpen]);

  const modelOptions = useMemo(() => {
    const selected = String(value || "").trim();
    const base = aggregatedModels.slice();
    if (selected && !base.some((m) => m.id === selected)) {
      base.unshift({ id: selected, title: selected });
    }
    return base;
  }, [aggregatedModels, value]);

  const filteredModels = useMemo(() => filterModelsByQuery(modelOptions, query), [modelOptions, query]);

  return (
    <>
      <label style={{ gridColumn: "1 / -1" }}>
        {label}
        <div ref={pickerRef} className="provider-model-picker">
          <input
            value={query}
            onFocus={() => setMenuOpen(true)}
            onClick={() => setMenuOpen(true)}
            onChange={(event) => setQuery(event.target.value)}
            placeholder={placeholder}
            disabled={disabled}
            autoComplete="off"
          />
        </div>
        {hint ? (
          <span className="entry-form-hint" style={{ gridColumn: "1 / -1" }}>
            {hint}
          </span>
        ) : null}
      </label>

      {menuOpen && menuRect
        ? createPortal(
            <div
              ref={menuRef}
              className="provider-model-picker-menu provider-model-picker-menu-floating"
              style={{
                top: `${menuRect.top}px`,
                left: `${menuRect.left}px`,
                width: `${menuRect.width}px`
              }}
            >
              <div className="provider-model-picker-group">Available models</div>
              <div className="provider-model-options" style={{ maxHeight: `${menuRect.maxHeight}px` }}>
                <button
                  type="button"
                  className={`provider-model-option ${!value ? "active" : ""}`}
                  onMouseDown={(event) => event.preventDefault()}
                  onClick={() => {
                    onChange("");
                    setQuery("");
                    setMenuOpen(false);
                    setMenuRect(null);
                  }}
                >
                  <div className="provider-model-option-main">
                    <strong>None</strong>
                  </div>
                  <span className="placeholder-text">Clear alias</span>
                </button>
                {filteredModels.length === 0 ? (
                  <div className="placeholder-text" style={{ padding: "10px 12px" }}>
                    No matching models
                  </div>
                ) : (
                  filteredModels.map((model) => (
                    <button
                      key={model.id}
                      type="button"
                      className={`provider-model-option ${value === model.id ? "active" : ""}`}
                      onMouseDown={(event) => event.preventDefault()}
                      onClick={() => {
                        onChange(model.id);
                        setQuery(model.id);
                        setMenuOpen(false);
                        setMenuRect(null);
                      }}
                    >
                      <div className="provider-model-option-main">
                        <strong>{model.title || model.id}</strong>
                        {model.contextWindow ? (
                          <span className="provider-model-context">{model.contextWindow}</span>
                        ) : null}
                      </div>
                      <span>{model.id}</span>
                      {Array.isArray(model.capabilities) && model.capabilities.length > 0 ? (
                        <div className="provider-model-capabilities">
                          {model.capabilities.map((capability) => (
                            <span key={`${model.id}-${capability}`}>{capability}</span>
                          ))}
                        </div>
                      ) : null}
                    </button>
                  ))
                )}
              </div>
            </div>,
            document.body
          )
        : null}
    </>
  );
}
