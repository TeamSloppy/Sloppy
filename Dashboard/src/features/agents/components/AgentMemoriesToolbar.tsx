import React, { useEffect, useId, useRef, useState } from "react";

export type MemoryFilter = "all" | "persistent" | "temporary" | "todo";
export type MemoryView = "list" | "graph";

const FILTER_ORDER: MemoryFilter[] = ["all", "persistent", "temporary", "todo"];

function categoryLabel(value: Exclude<MemoryFilter, "all">) {
  if (value === "persistent") return "Persistent";
  if (value === "temporary") return "Temporary";
  return "Todo";
}

function filterLabel(value: MemoryFilter) {
  if (value === "all") return "All";
  return categoryLabel(value);
}

export interface AgentMemoriesToolbarProps {
  searchInput: string;
  onSearchInputChange: (value: string) => void;
  filter: MemoryFilter;
  onFilterChange: (value: MemoryFilter) => void;
  view: MemoryView;
  onViewChange: (value: MemoryView) => void;
}

export function AgentMemoriesToolbar({
  searchInput,
  onSearchInputChange,
  filter,
  onFilterChange,
  view,
  onViewChange,
}: AgentMemoriesToolbarProps) {
  const [filterOpen, setFilterOpen] = useState(false);
  const filterWrapRef = useRef<HTMLDivElement>(null);
  const listId = useId();

  useEffect(() => {
    if (!filterOpen) return;
    const onPointerDown = (event: MouseEvent) => {
      if (filterWrapRef.current && !filterWrapRef.current.contains(event.target as Node)) {
        setFilterOpen(false);
      }
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setFilterOpen(false);
    };
    document.addEventListener("mousedown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("mousedown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [filterOpen]);

  const toggleView = () => {
    onViewChange(view === "list" ? "graph" : "list");
  };

  return (
    <div className="agent-memories-toolbar">
      <div className="skills-search agent-memories-search">
        <span className="material-symbols-rounded">search</span>
        <input
          type="search"
          value={searchInput}
          onChange={(event) => onSearchInputChange(event.target.value)}
          placeholder="Search notes, summaries, or memory IDs"
        />
      </div>

      <div className="agent-memory-filter-dropdown" ref={filterWrapRef}>
        <button
          type="button"
          className="agent-memory-filter-trigger"
          id={`${listId}-filter`}
          aria-haspopup="listbox"
          aria-expanded={filterOpen}
          aria-controls={`${listId}-filter-menu`}
          onClick={() => setFilterOpen((open) => !open)}
        >
          <span className="agent-memory-filter-trigger-label">{filterLabel(filter)}</span>
          <span className={`material-symbols-rounded agent-memory-filter-chevron ${filterOpen ? "open" : ""}`}>expand_more</span>
        </button>
        {filterOpen ? (
          <ul
            className="agent-memory-filter-menu"
            id={`${listId}-filter-menu`}
            role="listbox"
            aria-labelledby={`${listId}-filter`}
          >
            {FILTER_ORDER.map((value) => (
              <li key={value} role="presentation">
                <button
                  type="button"
                  id={`${listId}-opt-${value}`}
                  role="option"
                  aria-selected={filter === value}
                  className={`agent-memory-filter-option ${filter === value ? "active" : ""}`}
                  onClick={() => {
                    onFilterChange(value);
                    setFilterOpen(false);
                  }}
                >
                  {filterLabel(value)}
                  {filter === value ? (
                    <span className="material-symbols-rounded agent-memory-filter-check" aria-hidden>
                      check
                    </span>
                  ) : null}
                </button>
              </li>
            ))}
          </ul>
        ) : null}
      </div>

      <button
        type="button"
        className="agent-memory-view-toggle"
        onClick={toggleView}
        title={view === "list" ? "Switch to graph view" : "Switch to list view"}
      >
        <span className="material-symbols-rounded" aria-hidden>
          {view === "list" ? "view_list" : "account_tree"}
        </span>
        <span>{view === "list" ? "List" : "Graph"}</span>
      </button>
    </div>
  );
}
