import { useEffect, useState } from "react";
import { emptyFilterState, emptyTaskFilter, filterError, filtersEqual, newFilterRule, normalizeTaskFilter, parseFilterState } from "./taskFilters";

function readState(key) {
  try { return { state: parseFilterState(window.localStorage.getItem(key)), error: "" }; }
  catch { return { state: emptyFilterState(), error: "Saved filters could not be loaded. Showing all tasks." }; }
}

// The owning board is keyed by server/project, so preferences never cross boards.
export function useTaskFilters(storageKey) {
  const [initial] = useState(() => readState(storageKey));
  const [state, setState] = useState(initial.state);
  const [changed, setChanged] = useState(false);
  const [storageError, setStorageError] = useState(initial.error);
  useEffect(() => {
    if (!changed) return;
    try {
      window.localStorage.setItem(storageKey, JSON.stringify(state));
      setStorageError("");
    } catch { setStorageError("Filters are active, but this browser could not save them. They may be lost after reload."); }
  }, [storageKey, state, changed]);
  const commit = (update) => { setState(update); setChanged(true); };
  const active = state.saved.find((entry) => entry.id === state.activeId);
  return {
    state, storageError, active,
    modified: Boolean(active && !filtersEqual(active.filter, state.filter)),
    setFilter: (filter) => commit((previous) => ({ ...previous, filter: normalizeTaskFilter(filter) })),
    clear: () => commit((previous) => ({ ...previous, filter: emptyTaskFilter(), activeId: "" })),
    select: (id) => commit((previous) => ({ ...previous, activeId: id,
      filter: normalizeTaskFilter(previous.saved.find((entry) => entry.id === id)?.filter || emptyTaskFilter()) })),
    save: (rawName, update) => {
      const name = rawName.trim();
      if (!name) return "Enter a filter name.";
      if (name.length > 80) return "Use a name of up to 80 characters.";
      if (filterError(state.filter)) return filterError(state.filter);
      const id = update && active ? active.id : newFilterRule().id;
      if (state.saved.some((entry) => entry.id !== id && entry.name.toLowerCase() === name.toLowerCase())) return "A filter with this name already exists.";
      const entry = { id, name, filter: normalizeTaskFilter(state.filter) };
      commit((previous) => ({ ...previous, activeId: id, saved: previous.saved.some((item) => item.id === id)
        ? previous.saved.map((item) => item.id === id ? entry : item) : [...previous.saved, entry] }));
      return "";
    },
    remove: () => commit((previous) => ({ ...previous, saved: previous.saved.filter((entry) => entry.id !== previous.activeId), activeId: "", filter: emptyTaskFilter() }))
  };
}
