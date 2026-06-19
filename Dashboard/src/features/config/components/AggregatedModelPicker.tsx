import React, { useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { filterModelsByQuery } from "../../agents/utils/aggregateProviderModels";
import type { AggregatedModelOption } from "../../agents/utils/aggregateProviderModels";
import { groupModelsForPicker } from "../../agents/utils/modelPickerSections";

type Props = {
  label: React.ReactNode;
  value: string;
  onChange: (nextId: string) => void;
  aggregatedModels: AggregatedModelOption[];
  placeholder?: string;
  disabled?: boolean;
  hint?: React.ReactNode;
  className?: string;
  inputClassName?: string;
  menuClassName?: string;
  floating?: boolean;
  includeEmptyOption?: boolean;
  emptyOptionTitle?: React.ReactNode;
  emptyOptionSubtitle?: React.ReactNode;
  groupTitle?: string;
  "aria-label"?: string;
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
  hint = null,
  className = "provider-model-picker",
  inputClassName = "",
  menuClassName = "",
  floating = true,
  includeEmptyOption = true,
  emptyOptionTitle = "None",
  emptyOptionSubtitle = "Clear alias",
  groupTitle = "",
  "aria-label": ariaLabel
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
  const groupedModels = useMemo(
    () => groupModelsForPicker(filteredModels, value, groupTitle),
    [filteredModels, groupTitle, value]
  );

  const picker = (
    <div ref={pickerRef} className={className}>
      <input
        className={inputClassName}
        value={query}
        onFocus={() => setMenuOpen(true)}
        onClick={() => setMenuOpen(true)}
        onChange={(event) => setQuery(event.target.value)}
        placeholder={placeholder}
        disabled={disabled}
        autoComplete="off"
        aria-label={ariaLabel}
      />
      {!floating && menuOpen ? renderMenu(null) : null}
    </div>
  );

  return (
    <>
      {label ? (
        <label style={{ gridColumn: "1 / -1" }}>
          {label}
          {picker}
          {hint ? (
            <span className="entry-form-hint" style={{ gridColumn: "1 / -1" }}>
              {hint}
            </span>
          ) : null}
        </label>
      ) : (
        picker
      )}

      {floating && menuOpen && menuRect
        ? createPortal(renderMenu(menuRect), document.body)
        : null}
    </>
  );

  function renderMenu(rect: typeof menuRect) {
    return (
      <div
        ref={menuRef}
        className={`provider-model-picker-menu ${floating ? "provider-model-picker-menu-floating" : ""} ${menuClassName}`.trim()}
        style={rect
          ? {
              top: `${rect.top}px`,
              left: `${rect.left}px`,
              width: `${rect.width}px`
            }
          : undefined}
      >
        <div className="provider-model-options" style={rect ? { maxHeight: `${rect.maxHeight}px` } : undefined}>
          {includeEmptyOption ? (
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
                <strong>{emptyOptionTitle}</strong>
              </div>
              {emptyOptionSubtitle ? <span className="placeholder-text">{emptyOptionSubtitle}</span> : null}
            </button>
          ) : null}
          {filteredModels.length === 0 ? (
            <div className="placeholder-text" style={{ padding: "10px 12px" }}>
              No matching models
            </div>
          ) : (
            groupedModels.map((group) => (
              <React.Fragment key={group.title}>
                <div className="provider-model-picker-group">
                  {group.title}
                  <span className="provider-model-picker-group-count">({group.models.length})</span>
                </div>
                {group.models.map((model) => (
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
                ))}
              </React.Fragment>
            ))
          )}
        </div>
      </div>
    );
  }
}
