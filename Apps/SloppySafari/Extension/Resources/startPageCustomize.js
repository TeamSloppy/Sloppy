// Start page and widget customization helpers for contentScript.js.
function renderStartPageSurface(frame) {
  const thread = frame.querySelector("[data-sloppy-thread]");
  const settings = state.settings || {};
  const theme = settings.startPageTheme === "light" ? "light" : "dark";
  const layoutMode = startPageLayoutMode(settings);
  frame.classList.toggle("sloppy-theme-light", theme === "light");
  frame.classList.toggle("is-start-canvas", layoutMode === "canvas");
  frame.style.setProperty("--sloppy-start-background-image", settings.startPageBackgroundImage ? `url("${settings.startPageBackgroundImage}")` : "none");
  thread.innerHTML = `
    <section class="sloppy-start-surface" data-sloppy-start-surface data-sloppy-start-theme="${escapeHTML(theme)}">
    </section>
  `;
  if (layoutMode === "canvas") {
    renderStartPageCanvas(frame);
    void loadStartPageBoard(frame);
  } else {
    renderStartPageItems(frame);
  }
}

function startPageLayoutMode(settings = state.settings || {}) {
  return String(settings?.startPageLayoutMode || "grid").trim() === "canvas" ? "canvas" : "grid";
}

function startPageShortcutItems(settings = state.settings || {}) {
  if (Array.isArray(settings.startPageItems) && settings.startPageItems.length) {
    return settings.startPageItems
      .filter((item) => String(item?.kind || "").trim() === "shortcut")
      .map((item) => ({
        title: String(item.title || "").trim(),
        url: String(item.url || "").trim()
      }));
  }
  return Array.isArray(settings.startPageShortcuts) ? settings.startPageShortcuts : [];
}

function startPageWidgetItems(settings = state.settings || {}) {
  return Array.isArray(settings.startPageItems)
    ? settings.startPageItems.filter((item) => String(item?.kind || "").trim() === "widget")
    : [];
}

function startPageItemsForMutation(settings = state.settings || {}) {
  if (Array.isArray(settings.startPageItems) && settings.startPageItems.length) {
    return settings.startPageItems;
  }
  return (settings.startPageShortcuts || []).map((shortcut) => ({ kind: "shortcut", ...shortcut }));
}

function applyLegacyWidgetSize(size) {
  if (size === "medium") {
    return { colSpan: 2, rowSpan: 1 };
  }
  if (size === "large") {
    return { colSpan: 2, rowSpan: 2 };
  }
  return { colSpan: 1, rowSpan: 1 };
}

function normalizeStartPageItem(record, fallbackOrder) {
  const kind = String(record?.kind || "").trim() === "widget" ? "widget" : "shortcut";
  const legacySpan = kind === "widget"
    ? applyLegacyWidgetSize(String(record?.size || "").trim())
    : { colSpan: 1, rowSpan: 1 };
  return {
    ...record,
    id: String(record?.id || record?.artifactId || record?.url || `${kind}-${fallbackOrder}`),
    kind,
    order: Number.isFinite(Number(record?.order)) ? Number(record.order) : fallbackOrder,
    colSpan: kind === "shortcut" ? 1 : Math.max(1, Number(record?.colSpan) || legacySpan.colSpan),
    rowSpan: kind === "shortcut" ? 1 : Math.max(1, Number(record?.rowSpan) || legacySpan.rowSpan)
  };
}

function normalizedStartPageItems(settings = state.settings || {}) {
  const sourceSettings = settings || {};
  const records = Array.isArray(sourceSettings.startPageItems) && sourceSettings.startPageItems.length
    ? sourceSettings.startPageItems
    : (sourceSettings.startPageShortcuts || []).map((shortcut) => ({ kind: "shortcut", ...shortcut }));
  return records.map((record, index) => normalizeStartPageItem(record, index));
}

function defaultStartPageBoard() {
  const items = normalizedStartPageItems(state.settings).map((item, index) => {
    const x = 40 + (index % 3) * 260;
    const y = 40 + Math.floor(index / 3) * 180;
    if (item.kind === "widget") {
      return {
        id: item.id || item.artifactId || `widget-${index}`,
        type: "widget",
        x,
        y,
        width: Math.max(220, (Number(item.colSpan) || 2) * 160),
        height: Math.max(120, (Number(item.rowSpan) || 1) * 120),
        title: item.title || item.artifactId || "Widget",
        zIndex: index + 1,
        artifactId: item.artifactId || item.id
      };
    }
    return {
      id: item.id || item.url || `shortcut-${index}`,
      type: "shortcut",
      x,
      y,
      width: 220,
      height: 96,
      title: item.title || item.url || "Shortcut",
      zIndex: index + 1,
      url: item.url
    };
  });
  return {
    id: "start-page-canvas",
    version: 1,
    viewport: { x: 0, y: 0, scale: 1 },
    items,
    groups: []
  };
}

function normalizeStartPageBoard(board = null) {
  const source = board && typeof board === "object" ? board : defaultStartPageBoard();
  const viewport = source.viewport && typeof source.viewport === "object" ? source.viewport : {};
  const finiteNumber = (value, fallback) => Number.isFinite(Number(value)) ? Number(value) : fallback;
  return {
    id: String(source.id || "start-page-canvas").trim() || "start-page-canvas",
    version: 1,
    viewport: {
      x: finiteNumber(viewport.x, 0),
      y: finiteNumber(viewport.y, 0),
      scale: Math.min(3, Math.max(0.2, finiteNumber(viewport.scale, 1)))
    },
    items: (Array.isArray(source.items) ? source.items : [])
      .map((item, index) => {
        const type = String(item?.type || "").trim();
        if (!["widget", "shortcut", "text", "image"].includes(type)) {
          return null;
        }
        const id = String(item?.id || `${type}-${index}-${Date.now()}`).trim();
        return {
          id,
          type,
          x: finiteNumber(item?.x, 40 + index * 24),
          y: finiteNumber(item?.y, 40 + index * 24),
          width: Math.max(40, finiteNumber(item?.width, type === "shortcut" ? 220 : 240)),
          height: Math.max(40, finiteNumber(item?.height, type === "shortcut" ? 96 : 140)),
          title: String(item?.title || type).trim(),
          zIndex: Number.isFinite(Number(item?.zIndex)) ? Number(item.zIndex) : index + 1,
          groupId: String(item?.groupId || "").trim() || undefined,
          artifactId: String(item?.artifactId || "").trim() || undefined,
          url: String(item?.url || "").trim() || undefined,
          text: item?.text == null ? undefined : String(item.text),
          assetPath: String(item?.assetPath || "").trim() || undefined,
          mediaType: String(item?.mediaType || "").trim() || undefined
        };
      })
      .filter(Boolean),
    groups: (Array.isArray(source.groups) ? source.groups : [])
      .map((group, index) => {
        const id = String(group?.id || `group-${index}-${Date.now()}`).trim();
        const color = normalizeCanvasGroupColor(group?.color);
        return {
          id,
          title: String(group?.title || "Group").trim(),
          x: finiteNumber(group?.x, 0),
          y: finiteNumber(group?.y, 0),
          width: Math.max(80, finiteNumber(group?.width, 360)),
          height: Math.max(80, finiteNumber(group?.height, 220)),
          collapsed: Boolean(group?.collapsed),
          color
        };
      })
      .filter((group) => group.id)
  };
}

function normalizeCanvasGroupColor(value) {
  const color = String(value || "").trim();
  return /^#[0-9a-f]{6}$/i.test(color) ? color.toLowerCase() : "#b7ff00";
}

function currentStartPageBoard() {
  state.startPageBoard = normalizeStartPageBoard(state.startPageBoard);
  return state.startPageBoard;
}

function filterCanvasItems(board, query) {
  const normalized = normalizeStartPageBoard(board);
  const needle = String(query || "").trim().toLowerCase();
  if (!needle) {
    return normalized.items;
  }
  return normalized.items.filter((item) => [
    item.title,
    item.text,
    item.url,
    item.artifactId,
    item.assetPath
  ].some((value) => String(value || "").toLowerCase().includes(needle)));
}

function canvasItemSearchMatches(item, query) {
  return filterCanvasItems({ ...currentStartPageBoard(), items: [item] }, query).length > 0;
}

function canvasAssetURL(path) {
  const value = String(path || "").trim();
  if (!value) {
    return "";
  }
  if (/^https?:|^data:|^blob:/.test(value)) {
    return value;
  }
  return value.startsWith(".sloppy/")
    ? `/${value}`
    : value;
}

function canvasItemStyle(item) {
  return `left:${Number(item.x) || 0}px;top:${Number(item.y) || 0}px;width:${Number(item.width) || 220}px;height:${Number(item.height) || 140}px;z-index:${Number(item.zIndex) || 1};`;
}

function canvasGroupStyle(group) {
  return `${canvasItemStyle({ ...group, zIndex: 0 })}--sloppy-canvas-group-color:${escapeHTML(normalizeCanvasGroupColor(group.color))};`;
}

function canvasEditingEnabled() {
  return Boolean(state.customizeNavigation?.editing);
}

function renderCanvasItem(item, searchQuery = "") {
  const hiddenClass = searchQuery && !canvasItemSearchMatches(item, searchQuery) ? " is-search-hidden" : "";
  const matchClass = searchQuery && !hiddenClass ? " is-search-match" : "";
  const isSelected = state.selectedCanvasEntity?.type === "item" && state.selectedCanvasEntity?.id === item.id;
  const selectedClass = isSelected ? " is-selected" : "";
  const deleteButton = isSelected && canvasEditingEnabled()
    ? `<button class="sloppy-canvas-delete-entity" type="button" data-sloppy-canvas-delete-entity aria-label="${escapeHTML(t("deleteItem"))}">${icon("close")}</button>`
    : "";
  const attrs = `class="sloppy-canvas-item sloppy-canvas-${escapeHTML(item.type)}${hiddenClass}${matchClass}${selectedClass}" data-sloppy-canvas-item="${escapeHTML(item.id)}" style="${escapeHTML(canvasItemStyle(item))}"`;
  if (item.type === "widget") {
    const html = widgetHTMLForItem({ artifactId: item.artifactId, id: item.id, title: item.title });
    return `<article ${attrs} data-sloppy-canvas-widget="${escapeHTML(item.artifactId || "")}">${deleteButton}${widgetFrameMarkupForItem({ ...item, artifactId: item.artifactId }, html)}</article>`;
  }
  if (item.type === "shortcut") {
    return `
      <article ${attrs}>
        ${deleteButton}
        <a href="${escapeHTML(item.url || "#")}" draggable="false">
          <img class="sloppy-canvas-shortcut-icon" src="${escapeHTML(shortcutIconURL(item.url))}" alt="" aria-hidden="true">
          <span class="sloppy-canvas-shortcut-copy">
            <strong>${escapeHTML(item.title || item.url || "Shortcut")}</strong>
            <span>${escapeHTML(item.url || "")}</span>
          </span>
        </a>
      </article>
    `;
  }
  if (item.type === "image") {
    return `
      <figure ${attrs}>
        ${deleteButton}
        <img src="${escapeHTML(canvasAssetURL(item.assetPath))}" alt="${escapeHTML(item.title || "")}">
        <figcaption>${escapeHTML(item.title || "Image")}</figcaption>
      </figure>
    `;
  }
  return `
    <article ${attrs} contenteditable="true" spellcheck="true">
      ${deleteButton}
      <strong>${escapeHTML(item.title || "Note")}</strong>
      <p>${escapeHTML(item.text || "")}</p>
    </article>
  `;
}

function renderCanvasGroup(group) {
  const isSelected = state.selectedCanvasEntity?.type === "group" && state.selectedCanvasEntity?.id === group.id;
  const resizeHandle = canvasEditingEnabled() && isSelected
    ? `<button class="sloppy-canvas-group-resize" type="button" data-sloppy-canvas-group-resize="${escapeHTML(group.id)}" aria-label="${escapeHTML(t("resizeItem"))}"></button>`
    : "";
  const deleteButton = canvasEditingEnabled() && isSelected
    ? `<button class="sloppy-canvas-delete-entity" type="button" data-sloppy-canvas-delete-entity aria-label="${escapeHTML(t("deleteItem"))}">${icon("close")}</button>`
    : "";
  return `
    <section class="sloppy-canvas-group${isSelected ? " is-selected" : ""}" data-sloppy-canvas-group="${escapeHTML(group.id)}" style="${canvasGroupStyle(group)}">
      ${deleteButton}
      <strong>${escapeHTML(group.title || "Group")}</strong>
      ${resizeHandle}
    </section>
  `;
}

function renderStartPageCanvas(frame, options = {}) {
  const surface = frame.querySelector("[data-sloppy-start-surface]") || frame.querySelector("[data-sloppy-thread]")?.querySelector?.("[data-sloppy-start-surface]");
  if (!surface) {
    return;
  }
  const board = currentStartPageBoard();
  normalizeCanvasSelection(board);
  const query = String(state.canvasSearchQuery || "").trim();
  const viewport = board.viewport || { x: 0, y: 0, scale: 1 };
  const isEditing = canvasEditingEnabled();
  const hasSelection = Boolean(state.selectedCanvasEntity) && isEditing;
  const selectedGroup = isEditing && state.selectedCanvasEntity?.type === "group"
    ? board.groups.find((group) => group.id === state.selectedCanvasEntity.id)
    : null;
  surface.innerHTML = `
    <section class="sloppy-start-canvas" data-sloppy-start-canvas tabindex="0">
      <div class="sloppy-canvas-toolbar${selectedGroup ? " has-group-controls" : ""}">
        <input data-sloppy-canvas-search placeholder="${escapeHTML(t("search") || "Search")}" value="${escapeHTML(query)}">
        ${selectedGroup ? `
          <input class="sloppy-canvas-group-title-input" data-sloppy-canvas-group-title value="${escapeHTML(selectedGroup.title || "Group")}">
          <input class="sloppy-canvas-group-color-input" data-sloppy-canvas-group-color type="color" value="${escapeHTML(normalizeCanvasGroupColor(selectedGroup.color))}">
        ` : ""}
        ${isEditing ? `<button type="button" data-sloppy-canvas-add-text>${icon("plus")}</button>` : ""}
        ${isEditing ? `<button type="button" data-sloppy-canvas-group-selected>${icon("group")}</button>` : ""}
        ${isEditing ? `<button type="button" data-sloppy-canvas-delete ${hasSelection ? "" : "disabled"}>${icon("trash")}</button>` : ""}
        <button type="button" data-sloppy-canvas-zoom-out>-</button>
        <button type="button" data-sloppy-canvas-zoom-in>+</button>
      </div>
      <div class="sloppy-canvas-viewport" data-sloppy-canvas-viewport>
        <div class="sloppy-canvas-world" data-sloppy-canvas-world style="transform:translate(${Number(viewport.x) || 0}px, ${Number(viewport.y) || 0}px) scale(${Number(viewport.scale) || 1});">
          ${(board.groups || []).map((group) => renderCanvasGroup(group)).join("")}
          ${(board.items || []).sort((lhs, rhs) => (Number(lhs.zIndex) || 0) - (Number(rhs.zIndex) || 0)).map((item) => renderCanvasItem(item, query)).join("")}
        </div>
      </div>
    </section>
  `;
  renderCanvasHandlers(frame, surface);
  if (options.restoreSearchFocus) {
    const search = surface.querySelector("[data-sloppy-canvas-search]");
    search?.focus?.();
    const length = String(search?.value || "").length;
    search?.setSelectionRange?.(length, length);
  }
  void hydrateCanvasWidgets(frame);
}

async function loadStartPageBoard(frame) {
  if (state.startPageBoardLoaded || state.startPageBoardLoading || typeof chrome === "undefined" || typeof chrome.runtime?.sendMessage !== "function") {
    return;
  }
  state.startPageBoardLoading = true;
  const response = await chrome.runtime.sendMessage({ type: "sloppy.board.get", boardId: "start-page-canvas" }).catch(() => null);
  state.startPageBoardLoading = false;
  if (response?.board) {
    state.startPageBoard = normalizeStartPageBoard(response.board);
    state.startPageBoardLoaded = true;
    renderStartPageCanvas(frame);
  } else if (!state.startPageBoard) {
    state.startPageBoard = defaultStartPageBoard();
    renderStartPageCanvas(frame);
  }
}

async function hydrateCanvasWidgets(frame) {
  const board = currentStartPageBoard();
  const widgetIds = board.items
    .filter((item) => item.type === "widget" && item.artifactId)
    .map((item) => item.artifactId)
    .filter((artifactId) => !state.widgetHTMLByArtifactId?.[artifactId]);
  const uniqueIds = [...new Set(widgetIds)];
  if (!uniqueIds.length || typeof chrome === "undefined" || typeof chrome.runtime?.sendMessage !== "function") {
    return;
  }
  let loaded = false;
  await Promise.all(uniqueIds.map(async (artifactId) => {
    const response = await chrome.runtime.sendMessage({
      type: "sloppy.artifacts.widget",
      artifactId
    }).catch(() => null);
    if (response?.html) {
      state.widgetHTMLByArtifactId = {
        ...(state.widgetHTMLByArtifactId || {}),
        [artifactId]: String(response.html || "")
      };
      loaded = true;
    }
  }));
  if (loaded) {
    renderStartPageCanvas(frame);
  }
}

function renderCanvasHandlers(frame, surface) {
  let dragState = null;
  const eventPoint = (event) => ({
    x: Number(event.clientX) || 0,
    y: Number(event.clientY) || 0
  });
  const endDrag = () => {
    if (dragState?.changed) {
      void persistStartPageCanvas();
    }
    dragState = null;
    document.removeEventListener?.("pointermove", onPointerMove);
    document.removeEventListener?.("pointerup", endDrag);
    document.removeEventListener?.("pointercancel", endDrag);
  };
  const onPointerMove = (event) => {
    if (!dragState) {
      return;
    }
    const point = eventPoint(event);
    const scale = Number(currentStartPageBoard().viewport.scale) || 1;
    const dx = (point.x - dragState.x) / scale;
    const dy = (point.y - dragState.y) / scale;
    if (Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5) {
      return;
    }
    dragState.x = point.x;
    dragState.y = point.y;
    dragState.changed = true;
    if (dragState.type === "item") {
      moveCanvasItem(dragState.id, dx, dy);
    } else if (dragState.type === "group") {
      moveCanvasGroup(dragState.id, dx, dy);
    } else if (dragState.type === "group-resize") {
      resizeCanvasGroup(dragState.id, dx, dy);
    } else if (dragState.type === "pan") {
      const board = currentStartPageBoard();
      board.viewport.x = (Number(board.viewport.x) || 0) + point.x - dragState.previousScreenX;
      board.viewport.y = (Number(board.viewport.y) || 0) + point.y - dragState.previousScreenY;
      dragState.previousScreenX = point.x;
      dragState.previousScreenY = point.y;
    }
    renderStartPageCanvas(frame);
  };
  surface.querySelector("[data-sloppy-canvas-search]")?.addEventListener("input", (event) => {
    state.canvasSearchQuery = event.target?.value || "";
    renderStartPageCanvas(frame, { restoreSearchFocus: true });
  });
  surface.querySelector("[data-sloppy-canvas-group-title]")?.addEventListener("input", (event) => {
    updateSelectedCanvasGroup({
      title: event.target?.value || "Group"
    });
    const groupNode = surface.querySelector?.(`[data-sloppy-canvas-group="${state.selectedCanvasEntity?.id || ""}"] strong`);
    if (groupNode) {
      groupNode.textContent = event.target?.value || "Group";
    }
  });
  surface.querySelector("[data-sloppy-canvas-group-title]")?.addEventListener("change", () => {
    void persistStartPageCanvas();
  });
  surface.querySelector("[data-sloppy-canvas-group-color]")?.addEventListener("input", (event) => {
    const color = normalizeCanvasGroupColor(event.target?.value);
    updateSelectedCanvasGroup({ color });
    const groupNode = surface.querySelector?.(`[data-sloppy-canvas-group="${state.selectedCanvasEntity?.id || ""}"]`);
    groupNode?.style?.setProperty?.("--sloppy-canvas-group-color", color);
  });
  surface.querySelector("[data-sloppy-canvas-group-color]")?.addEventListener("change", () => {
    void persistStartPageCanvas();
  });
  surface.querySelector("[data-sloppy-canvas-add-text]")?.addEventListener("click", () => {
    if (!canvasEditingEnabled()) {
      return;
    }
    addCanvasTextItem();
    void persistStartPageCanvas();
    renderStartPageCanvas(frame);
  });
  surface.querySelector("[data-sloppy-canvas-zoom-in]")?.addEventListener("click", () => {
    zoomStartPageCanvas(1.1);
    void persistStartPageCanvas();
    renderStartPageCanvas(frame);
  });
  surface.querySelector("[data-sloppy-canvas-zoom-out]")?.addEventListener("click", () => {
    zoomStartPageCanvas(0.9);
    void persistStartPageCanvas();
    renderStartPageCanvas(frame);
  });
  surface.querySelector("[data-sloppy-canvas-group-selected]")?.addEventListener("click", () => {
    if (!canvasEditingEnabled()) {
      return;
    }
    createCanvasFrameForVisibleItems();
    void persistStartPageCanvas();
    renderStartPageCanvas(frame);
  });
  surface.querySelector("[data-sloppy-canvas-delete]")?.addEventListener("click", () => {
    if (!canvasEditingEnabled()) {
      return;
    }
    if (deleteSelectedCanvasEntity()) {
      void persistStartPageCanvas();
      renderStartPageCanvas(frame);
    }
  });
  surface.querySelectorAll?.("[data-sloppy-canvas-delete-entity]")?.forEach((button) => {
    button.addEventListener("click", (event) => {
      event.preventDefault?.();
      event.stopPropagation?.();
      if (deleteSelectedCanvasEntity()) {
        void persistStartPageCanvas();
        renderStartPageCanvas(frame);
      }
    });
  });
  surface.querySelector("[data-sloppy-start-canvas]")?.addEventListener("keydown", (event) => {
    if (!canvasEditingEnabled()) {
      return;
    }
    if (event.key !== "Delete" && event.key !== "Backspace") {
      return;
    }
    if (event.target?.closest?.("input, textarea, [contenteditable='true']")) {
      return;
    }
    if (deleteSelectedCanvasEntity()) {
      event.preventDefault?.();
      void persistStartPageCanvas();
      renderStartPageCanvas(frame);
    }
  });
  surface.querySelector("[data-sloppy-canvas-viewport]")?.addEventListener("wheel", (event) => {
    event.preventDefault?.();
    zoomStartPageCanvas((Number(event.deltaY) || 0) > 0 ? 0.92 : 1.08);
    void persistStartPageCanvas();
    renderStartPageCanvas(frame);
  });
  surface.querySelector("[data-sloppy-canvas-viewport]")?.addEventListener("pointerdown", (event) => {
    if (event.target?.closest?.("[data-sloppy-canvas-item]") || event.target?.closest?.("[data-sloppy-canvas-group]")) {
      return;
    }
    const point = eventPoint(event);
    state.selectedCanvasEntity = null;
    dragState = { type: "pan", x: point.x, y: point.y, previousScreenX: point.x, previousScreenY: point.y, changed: false };
    renderStartPageCanvas(frame);
    document.addEventListener?.("pointermove", onPointerMove);
    document.addEventListener?.("pointerup", endDrag);
    document.addEventListener?.("pointercancel", endDrag);
  });
  surface.querySelectorAll?.("[data-sloppy-canvas-item]")?.forEach((node) => {
    node.addEventListener("pointerdown", (event) => {
      if (!canvasEditingEnabled()) {
        return;
      }
      if (event.button != null && event.button !== 0) {
        return;
      }
      if (event.target?.closest?.("[data-sloppy-canvas-delete-entity]")) {
        return;
      }
      event.preventDefault?.();
      const point = eventPoint(event);
      selectCanvasEntity("item", node.dataset.sloppyCanvasItem);
      dragState = { type: "item", id: node.dataset.sloppyCanvasItem, x: point.x, y: point.y, changed: false };
      renderStartPageCanvas(frame);
      document.addEventListener?.("pointermove", onPointerMove);
      document.addEventListener?.("pointerup", endDrag);
      document.addEventListener?.("pointercancel", endDrag);
    });
  });
  surface.querySelectorAll?.("[data-sloppy-canvas-group]")?.forEach((node) => {
    node.addEventListener("pointerdown", (event) => {
      if (!canvasEditingEnabled()) {
        return;
      }
      if (event.button != null && event.button !== 0) {
        return;
      }
      if (event.target?.closest?.("[data-sloppy-canvas-delete-entity]")) {
        return;
      }
      const resizeHandle = event.target?.closest?.("[data-sloppy-canvas-group-resize]");
      if (resizeHandle) {
        event.preventDefault?.();
        event.stopPropagation?.();
        const point = eventPoint(event);
        selectCanvasEntity("group", resizeHandle.dataset.sloppyCanvasGroupResize || node.dataset.sloppyCanvasGroup);
        dragState = { type: "group-resize", id: resizeHandle.dataset.sloppyCanvasGroupResize || node.dataset.sloppyCanvasGroup, x: point.x, y: point.y, changed: false };
        document.addEventListener?.("pointermove", onPointerMove);
        document.addEventListener?.("pointerup", endDrag);
        document.addEventListener?.("pointercancel", endDrag);
        return;
      }
      event.preventDefault?.();
      const point = eventPoint(event);
      selectCanvasEntity("group", node.dataset.sloppyCanvasGroup);
      dragState = { type: "group", id: node.dataset.sloppyCanvasGroup, x: point.x, y: point.y, changed: false };
      renderStartPageCanvas(frame);
      document.addEventListener?.("pointermove", onPointerMove);
      document.addEventListener?.("pointerup", endDrag);
      document.addEventListener?.("pointercancel", endDrag);
    });
  });
}

function addCanvasTextItem(position = {}) {
  const board = currentStartPageBoard();
  const item = {
    id: `text-${Date.now()}`,
    type: "text",
    x: Number(position.x) || 80,
    y: Number(position.y) || 80,
    width: 240,
    height: 140,
    title: "Note",
    zIndex: nextCanvasZIndex(board),
    text: ""
  };
  board.items.push(item);
  selectCanvasEntity("item", item.id);
  return item;
}

function selectCanvasEntity(type, id) {
  const normalizedType = type === "group" ? "group" : "item";
  const entityId = String(id || "").trim();
  state.selectedCanvasEntity = entityId ? { type: normalizedType, id: entityId } : null;
  return state.selectedCanvasEntity;
}

function normalizeCanvasSelection(board = currentStartPageBoard()) {
  const selection = state.selectedCanvasEntity;
  if (!selection) {
    return null;
  }
  const exists = selection.type === "group"
    ? board.groups.some((group) => group.id === selection.id)
    : board.items.some((item) => item.id === selection.id);
  if (!exists) {
    state.selectedCanvasEntity = null;
  }
  return state.selectedCanvasEntity;
}

function deleteSelectedCanvasEntity() {
  if (!canvasEditingEnabled()) {
    return false;
  }
  const board = currentStartPageBoard();
  const selection = normalizeCanvasSelection(board);
  if (!selection) {
    return false;
  }
  if (selection.type === "group") {
    const before = board.groups.length;
    board.groups = board.groups.filter((group) => group.id !== selection.id);
    board.items = board.items.map((item) => item.groupId === selection.id ? { ...item, groupId: undefined } : item);
    state.selectedCanvasEntity = null;
    return board.groups.length !== before;
  }
  const before = board.items.length;
  board.items = board.items.filter((item) => item.id !== selection.id);
  state.selectedCanvasEntity = null;
  return board.items.length !== before;
}

function updateSelectedCanvasGroup(patch = {}) {
  if (!canvasEditingEnabled() || state.selectedCanvasEntity?.type !== "group") {
    return null;
  }
  const board = currentStartPageBoard();
  const group = board.groups.find((candidate) => candidate.id === state.selectedCanvasEntity.id);
  if (!group) {
    return null;
  }
  if (Object.prototype.hasOwnProperty.call(patch, "title")) {
    group.title = String(patch.title || "Group").trim() || "Group";
  }
  if (Object.prototype.hasOwnProperty.call(patch, "color")) {
    group.color = normalizeCanvasGroupColor(patch.color);
  }
  return group;
}

function nextCanvasZIndex(board = currentStartPageBoard()) {
  return Math.max(0, ...board.items.map((item) => Number(item.zIndex) || 0)) + 1;
}

function nextCanvasPosition(board = currentStartPageBoard()) {
  const index = board.items.length;
  return {
    x: 80 + (index % 4) * 36,
    y: 80 + Math.floor(index / 4) * 36
  };
}

function addShortcutToCanvas(shortcut = {}) {
  const board = currentStartPageBoard();
  const position = nextCanvasPosition(board);
  const url = String(shortcut.url || "").trim();
  const title = String(shortcut.title || url || "Shortcut").trim();
  const item = {
    id: String(shortcut.id || `shortcut-${Date.now()}`),
    type: "shortcut",
    x: position.x,
    y: position.y,
    width: 220,
    height: 96,
    title,
    zIndex: nextCanvasZIndex(board),
    url
  };
  board.items.push(item);
  return item;
}

function addWidgetArtifactToCanvas(widget = {}) {
  const board = currentStartPageBoard();
  const position = nextCanvasPosition(board);
  const artifactId = String(widget.artifactId || widget.id || "").trim();
  const item = {
    id: String(widget.id || artifactId || `widget-${Date.now()}`),
    type: "widget",
    x: position.x,
    y: position.y,
    width: Math.max(180, Number(widget.width) || 320),
    height: Math.max(120, Number(widget.height) || 180),
    title: String(widget.title || artifactId || "Widget").trim(),
    zIndex: nextCanvasZIndex(board),
    artifactId
  };
  board.items = board.items.filter((candidate) => candidate.type !== "widget" || candidate.artifactId !== artifactId);
  board.items.push(item);
  return item;
}

function moveCanvasItem(itemId, deltaX, deltaY) {
  if (!canvasEditingEnabled()) {
    return;
  }
  const board = currentStartPageBoard();
  const item = board.items.find((candidate) => candidate.id === itemId);
  if (!item) {
    return;
  }
  item.x = (Number(item.x) || 0) + (Number(deltaX) || 0);
  item.y = (Number(item.y) || 0) + (Number(deltaY) || 0);
}

function canvasItemCenter(item = {}) {
  return {
    x: (Number(item.x) || 0) + (Number(item.width) || 0) / 2,
    y: (Number(item.y) || 0) + (Number(item.height) || 0) / 2
  };
}

function canvasItemIsInsideGroup(item = {}, group = {}) {
  const center = canvasItemCenter(item);
  const left = Number(group.x) || 0;
  const top = Number(group.y) || 0;
  const right = left + (Number(group.width) || 0);
  const bottom = top + (Number(group.height) || 0);
  return center.x >= left && center.x <= right && center.y >= top && center.y <= bottom;
}

function syncCanvasGroupMembership(groupId, board = currentStartPageBoard()) {
  const group = board.groups.find((candidate) => candidate.id === groupId);
  if (!group) {
    return [];
  }
  board.items.forEach((item) => {
    if (canvasItemIsInsideGroup(item, group)) {
      item.groupId = groupId;
    }
  });
  return board.items.filter((item) => item.groupId === groupId);
}

function moveCanvasGroup(groupId, deltaX, deltaY) {
  if (!canvasEditingEnabled()) {
    return;
  }
  const board = currentStartPageBoard();
  const group = board.groups.find((candidate) => candidate.id === groupId);
  if (!group) {
    return;
  }
  const dx = Number(deltaX) || 0;
  const dy = Number(deltaY) || 0;
  const containedItems = syncCanvasGroupMembership(groupId, board);
  group.x = (Number(group.x) || 0) + dx;
  group.y = (Number(group.y) || 0) + dy;
  containedItems.forEach((item) => {
    item.x = (Number(item.x) || 0) + dx;
    item.y = (Number(item.y) || 0) + dy;
  });
}

function resizeCanvasGroup(groupId, deltaX, deltaY) {
  if (!canvasEditingEnabled()) {
    return;
  }
  const board = currentStartPageBoard();
  const group = board.groups.find((candidate) => candidate.id === groupId);
  if (!group) {
    return;
  }
  group.width = Math.max(120, (Number(group.width) || 0) + (Number(deltaX) || 0));
  group.height = Math.max(120, (Number(group.height) || 0) + (Number(deltaY) || 0));
  syncCanvasGroupMembership(groupId, board);
}

function zoomStartPageCanvas(multiplier) {
  const board = currentStartPageBoard();
  board.viewport.scale = Math.min(3, Math.max(0.2, (Number(board.viewport.scale) || 1) * (Number(multiplier) || 1)));
}

function createCanvasFrameForVisibleItems() {
  const board = currentStartPageBoard();
  const items = filterCanvasItems(board, state.canvasSearchQuery);
  if (!items.length) {
    return null;
  }
  const minX = Math.min(...items.map((item) => Number(item.x) || 0));
  const minY = Math.min(...items.map((item) => Number(item.y) || 0));
  const maxX = Math.max(...items.map((item) => (Number(item.x) || 0) + (Number(item.width) || 0)));
  const maxY = Math.max(...items.map((item) => (Number(item.y) || 0) + (Number(item.height) || 0)));
  const id = `group-${Date.now()}`;
  const group = {
    id,
    title: "Group",
    x: minX - 24,
    y: minY - 44,
    width: Math.max(120, maxX - minX + 48),
    height: Math.max(120, maxY - minY + 68),
    collapsed: false,
    color: "#b7ff00"
  };
  board.groups.push(group);
  items.forEach((item) => {
    item.groupId = id;
  });
  return group;
}

async function persistStartPageCanvas() {
  if (typeof chrome === "undefined" || typeof chrome.runtime?.sendMessage !== "function") {
    return null;
  }
  const board = currentStartPageBoard();
  const response = await chrome.runtime.sendMessage({
    type: "sloppy.board.save",
    boardId: board.id,
    board
  }).catch(() => null);
  if (response?.board) {
    state.startPageBoard = normalizeStartPageBoard(response.board);
    state.startPageBoardLoaded = true;
  }
  return response;
}

function readCanvasImageFile(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ""));
    reader.onerror = () => reject(new Error("image_read_failed"));
    reader.readAsDataURL(file);
  });
}

async function addCanvasImageItem(file, position = {}) {
  const dataURL = await readCanvasImageFile(file);
  const dataBase64 = String(dataURL).split(",")[1] || "";
  const mediaType = String(file?.type || dataURL.match(/^data:([^;]+);/)?.[1] || "image/png");
  const response = await chrome.runtime.sendMessage({
    type: "sloppy.board.asset.upload",
    boardId: currentStartPageBoard().id,
    filename: String(file?.name || "image.png"),
    mediaType,
    dataBase64
  });
  if (!response?.path) {
    return null;
  }
  const board = currentStartPageBoard();
  const maxZ = Math.max(0, ...board.items.map((item) => Number(item.zIndex) || 0));
  const item = {
    id: `image-${Date.now()}`,
    type: "image",
    x: Number(position.x) || 80,
    y: Number(position.y) || 80,
    width: 320,
    height: 220,
    title: String(file?.name || "Image"),
    zIndex: maxZ + 1,
    assetPath: response.path,
    mediaType: response.mediaType || mediaType
  };
  board.items.push(item);
  await persistStartPageCanvas();
  return item;
}

function updateStartPageItems(mutator) {
  const nextItems = mutator(normalizedStartPageItems(state.settings))
    .map((item, index) => normalizeStartPageItem({ ...item, order: index }, index));
  state.settings = {
    ...(state.settings || {}),
    startPageItems: nextItems,
    startPageShortcuts: nextItems
      .filter((item) => item.kind === "shortcut")
      .map((item) => ({
        title: item.title,
        url: item.url
      }))
  };
}

function resizeStartPageItem(itemId, colSpan, rowSpan) {
  updateStartPageItems((items) => items.map((item) => item.id === itemId
    ? { ...item, colSpan, rowSpan }
    : item));
}

const startPageResizeSpans = [
  { colSpan: 1, rowSpan: 1 },
  { colSpan: 2, rowSpan: 1 },
  { colSpan: 2, rowSpan: 2 }
];

function startPageResizeSpanIndex(item = {}) {
  const colSpan = Math.max(1, Number(item.colSpan) || 1);
  const rowSpan = Math.max(1, Number(item.rowSpan) || 1);
  const index = startPageResizeSpans.findIndex((span) => span.colSpan === colSpan && span.rowSpan === rowSpan);
  return index >= 0 ? index : 0;
}

function startPageResizeSpanForDrag(item = {}, deltaX = 0, deltaY = 0, edge = "bottom-right") {
  const threshold = 56;
  const currentIndex = startPageResizeSpanIndex(item);
  const horizontalDirection = edge.includes("left") ? -1 : edge.includes("right") ? 1 : 0;
  const verticalDirection = edge.includes("top") ? -1 : edge.includes("bottom") ? 1 : 0;
  const projectedDelta = Math.max(
    horizontalDirection ? deltaX * horizontalDirection : 0,
    verticalDirection ? deltaY * verticalDirection : 0
  );
  const dragSteps = Math.trunc(Math.abs(projectedDelta) / threshold);
  if (!dragSteps) {
    return startPageResizeSpans[currentIndex];
  }
  const direction = projectedDelta >= 0 ? 1 : -1;
  const nextIndex = Math.min(startPageResizeSpans.length - 1, Math.max(0, currentIndex + direction * dragSteps));
  return startPageResizeSpans[nextIndex];
}

function resizeEdgeForPointer(node, event) {
  const rect = node?.getBoundingClientRect?.();
  if (!rect || !Number.isFinite(rect.width) || !Number.isFinite(rect.height)) {
    return "bottom-right";
  }
  const cornerActivationInset = 36;
  const x = event.clientX - rect.left;
  const y = event.clientY - rect.top;
  const horizontalEdge = x <= rect.width / 2 ? "left" : "right";
  const verticalEdge = y <= rect.height / 2 ? "top" : "bottom";
  const isNearHorizontalEdge = horizontalEdge === "left" ? x <= cornerActivationInset : rect.width - x <= cornerActivationInset;
  const isNearVerticalEdge = verticalEdge === "top" ? y <= cornerActivationInset : rect.height - y <= cornerActivationInset;
  if (isNearHorizontalEdge && isNearVerticalEdge) {
    return `${verticalEdge}-${horizontalEdge}`;
  }
  const horizontalDistance = horizontalEdge === "left" ? x : rect.width - x;
  const verticalDistance = verticalEdge === "top" ? y : rect.height - y;
  if (verticalDistance <= horizontalDistance) {
    return verticalEdge;
  }
  return horizontalEdge;
}

function applyResizeHandleEdge(handle, edge) {
  if (!handle) {
    return;
  }
  const nextEdge = edge || "bottom-right";
  const previousEdge = handle.dataset.sloppyResizeEdge || "";
  if (previousEdge && previousEdge !== nextEdge) {
    handle.classList.add("is-moving");
    window.setTimeout?.(() => handle.classList.remove("is-moving"), 180);
  }
  handle.dataset.sloppyResizeEdge = nextEdge;
  ["top", "right", "bottom", "left"].forEach((part) => {
    handle.classList.toggle(`is-edge-${part}`, nextEdge.includes(part));
  });
}

function removeStartPageItem(itemId) {
  updateStartPageItems((items) => items.filter((item) => item.id !== itemId));
}

async function deleteCreatedWidget(frame, artifactId, options = {}) {
  const id = String(artifactId || "").trim();
  if (!id) {
    return;
  }
  state.artifacts = (state.artifacts || []).filter((artifact) => String(artifact?.id || "") !== id);
  const nextWidgetHTML = { ...(state.widgetHTMLByArtifactId || {}) };
  delete nextWidgetHTML[id];
  state.widgetHTMLByArtifactId = nextWidgetHTML;
  updateStartPageItems((items) => items.filter((item) => String(item?.artifactId || item?.id || "") !== id));
  renderStartPageItems(frame);
  renderWidgetsGrid(frame);
  renderWidgetPicker(frame);
  if (options.persist) {
    await chrome.runtime.sendMessage({ type: "sloppy.artifacts.delete", artifactId: id }).catch(() => null);
    state.settings = await chrome.runtime.sendMessage({ type: "sloppy.settings.save", settings: state.settings });
  }
}

function moveStartPageItem(itemId, direction) {
  const ordered = normalizedStartPageItems(state.settings).sort((lhs, rhs) => lhs.order - rhs.order);
  if (!ordered.length) {
    return;
  }
  const index = ordered.findIndex((item) => item.id === itemId);
  const targetIndex = direction === "backward" ? index - 1 : index + 1;
  if (index < 0 || !ordered[targetIndex]) {
    return;
  }
  moveStartPageItemRelative(itemId, ordered[targetIndex]?.id || "", direction === "forward" ? "after" : "before");
}

function moveStartPageItemRelative(activeId, targetId, dropPosition) {
  const normalizedPosition = dropPosition === "before" || dropPosition === "after" ? dropPosition : "after";
  updateStartPageItems((items) => {
    const ordered = [...items].sort((lhs, rhs) => lhs.order - rhs.order);
    const sourceIndex = ordered.findIndex((item) => item.id === activeId);
    const targetIndex = ordered.findIndex((item) => item.id === targetId);
    if (sourceIndex < 0 || targetIndex < 0 || sourceIndex === targetIndex) {
      return ordered;
    }
    const [movedItem] = ordered.splice(sourceIndex, 1);
    const adjustedTargetIndex = targetIndex > sourceIndex ? targetIndex - 1 : targetIndex;
    const insertIndex = normalizedPosition === "before" ? adjustedTargetIndex : adjustedTargetIndex + 1;
    ordered.splice(insertIndex, 0, movedItem);
    return ordered;
  });
}

function moveStartPageItemToIndex(activeId, targetIndex) {
  updateStartPageItems((items) => {
    const ordered = [...items].sort((lhs, rhs) => lhs.order - rhs.order);
    const sourceIndex = ordered.findIndex((item) => item.id === activeId);
    if (sourceIndex < 0) {
      return ordered;
    }
    const [movedItem] = ordered.splice(sourceIndex, 1);
    const insertIndex = Math.max(0, Math.min(Number(targetIndex) || 0, ordered.length));
    ordered.splice(insertIndex, 0, movedItem);
    return ordered;
  });
}

function startPageDropIndexForEvent(root, event) {
  const activeId = String(state.gridDrag?.activeId || "").trim();
  const nodes = Array.from(root.querySelectorAll?.("[data-sloppy-grid-item]") || [])
    .filter((node) => {
      const itemId = String(node.dataset?.sloppyGridItem || "").trim();
      return itemId && itemId !== activeId;
    });
  if (!nodes.length) {
    return 0;
  }
  const pointerX = Number(event.clientX) || 0;
  const pointerY = Number(event.clientY) || 0;
  const targetIndex = nodes.findIndex((node) => {
    const rect = node.getBoundingClientRect?.();
    if (!rect) {
      return false;
    }
    const centerY = rect.top + rect.height / 2;
    const centerX = rect.left + rect.width / 2;
    return pointerY < centerY || (Math.abs(pointerY - centerY) < rect.height / 2 && pointerX < centerX);
  });
  return targetIndex >= 0 ? targetIndex : nodes.length;
}

function captureStartPageLayout(frame) {
  const root = frame.querySelector("[data-sloppy-start-shortcuts]");
  if (!root) {
    return new Map();
  }
  return new Map(Array.from(root.querySelectorAll?.("[data-sloppy-grid-item]") || [])
    .map((node) => {
      const itemId = String(node.dataset?.sloppyGridItem || "").trim();
      const rect = node.getBoundingClientRect?.();
      return itemId && rect
        ? [itemId, { left: rect.left, top: rect.top }]
        : null;
    })
    .filter(Boolean));
}

function animateStartPageLayout(frame, beforeRects) {
  const root = frame.querySelector("[data-sloppy-start-shortcuts]");
  if (!root || !beforeRects?.size) {
    return;
  }
  if (window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches) {
    return;
  }
  Array.from(root.querySelectorAll?.("[data-sloppy-grid-item]") || []).forEach((node) => {
    const itemId = String(node.dataset?.sloppyGridItem || "").trim();
    const before = beforeRects.get(itemId);
    const after = node.getBoundingClientRect?.();
    if (!before || !after) {
      node.animate?.([
        { opacity: 0, transform: "scale(0.96)" },
        { opacity: 1, transform: "scale(1)" }
      ], {
        duration: 180,
        easing: "cubic-bezier(0.22, 1, 0.36, 1)"
      });
      return;
    }
    const deltaX = before.left - after.left;
    const deltaY = before.top - after.top;
    if (Math.abs(deltaX) < 0.5 && Math.abs(deltaY) < 0.5) {
      return;
    }
    node.animate?.([
      { transform: `translate(${deltaX}px, ${deltaY}px)` },
      { transform: "translate(0, 0)" }
    ], {
      duration: 220,
      easing: "cubic-bezier(0.22, 1, 0.36, 1)"
    });
  });
}

const customizeMotionSelectors = [
  ".sloppy-app-layout > .sloppy-shell",
  "[data-sloppy-start-shortcuts]",
  "[data-sloppy-composer]",
  ".sloppy-start-config-panel"
];

function captureCustomizeMotion(frame) {
  if (window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches) {
    return new Map();
  }
  return new Map(customizeMotionSelectors
    .map((selector) => {
      const node = frame.querySelector?.(selector);
      const rect = node?.getBoundingClientRect?.();
      return node && rect
        ? [selector, { left: rect.left, top: rect.top }]
        : null;
    })
    .filter(Boolean));
}

function animateCustomizeMotion(frame, beforeRects) {
  if (!beforeRects?.size || window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches) {
    return;
  }
  customizeMotionSelectors.forEach((selector) => {
    const before = beforeRects.get(selector);
    const node = frame.querySelector?.(selector);
    const after = node?.getBoundingClientRect?.();
    if (!before || !node || !after) {
      return;
    }
    const deltaX = before.left - after.left;
    const deltaY = before.top - after.top;
    if (Math.abs(deltaX) < 0.5 && Math.abs(deltaY) < 0.5) {
      return;
    }
    const computedTransform = window.getComputedStyle?.(node)?.transform || "";
    const finalTransform = computedTransform && computedTransform !== "none"
      ? computedTransform
      : "";
    const fromTransform = finalTransform
      ? `translate(${deltaX}px, ${deltaY}px) ${finalTransform}`
      : `translate(${deltaX}px, ${deltaY}px)`;
    const toTransform = finalTransform || "translate(0, 0)";
    node.animate?.([
      { transform: fromTransform },
      { transform: toTransform }
    ], {
      duration: 280,
      easing: "cubic-bezier(0.22, 1, 0.36, 1)"
    });
  });
}

function renderStartPageItemsAnimated(frame, mutate) {
  const beforeRects = captureStartPageLayout(frame);
  mutate?.();
  renderStartPageItems(frame);
  requestAnimationFrame?.(() => animateStartPageLayout(frame, beforeRects));
}

function renderWidgetsGrid(frame) {
  const root = frame.querySelector("[data-sloppy-widgets-grid]");
  if (!root) {
    return;
  }
  const widgets = (state.artifacts || []).filter((artifact) => String(artifact?.kind || "").trim() === "widget");
  root.innerHTML = `
      <button class="sloppy-widget-create-card" type="button" data-sloppy-create-widget-card>
        <span aria-hidden="true">+</span>
        <strong>${escapeHTML(t("createWidgetCard"))}</strong>
      </button>
      <button class="sloppy-widget-picker-card" type="button" data-sloppy-pick-shortcut-widget>
        <strong>${escapeHTML(t("shortcutWidget"))}</strong>
        <span>${escapeHTML(t("shortcutWidgetHint"))}</span>
      </button>
      ${widgets.map((artifact) => `
        <article class="sloppy-widget-picker-card sloppy-widget-picker-card-with-action">
          <button class="sloppy-widget-picker-main" type="button" data-sloppy-pick-ready-widget="${escapeHTML(artifact.id || "")}">
            <strong>${escapeHTML(artifact.title || artifact.id || "Widget")}</strong>
            <span>${escapeHTML(widgetSizeFromArtifact(artifact, artifact.kind || "widget"))}</span>
          </button>
          <button class="sloppy-widget-picker-delete" type="button" data-sloppy-delete-ready-widget="${escapeHTML(artifact.id || "")}" aria-label="${escapeHTML(t("deleteItem"))}">${icon("trash")}</button>
        </article>
      `).join("")}
    `;
}

function renderStartPageShortcutDragHandlers(frame, root) {
  const clearDragPreview = () => {
    Array.from(root.querySelectorAll?.("[data-sloppy-grid-drop-target]") || []).forEach((node) => {
      node.classList.remove("sloppy-grid-drop-preview");
    });
  };
  const isEditing = Boolean(state.customizeNavigation?.screen === "widgets" && state.customizeNavigation?.editing);
  if (!isEditing) {
    state.gridDrag = {
      activeId: null,
      overId: null,
      dropPosition: null,
      dropIndex: null
    };
    return;
  }
  const closeStartItemMenus = (exceptId = "") => {
    root.querySelectorAll?.("[data-sloppy-start-item-menu-panel]")?.forEach((panel) => {
      const panelId = String(panel.dataset.sloppyStartItemMenuPanel || "").trim();
      if (panelId !== exceptId) {
        panel.hidden = true;
      }
    });
    root.querySelectorAll?.("[data-sloppy-start-item-menu]")?.forEach((button) => {
      const buttonId = String(button.dataset.sloppyStartItemMenu || "").trim();
      if (buttonId !== exceptId) {
        button.setAttribute?.("aria-expanded", "false");
      }
    });
  };
  root.querySelectorAll?.("[data-sloppy-start-item-menu]")?.forEach((button) => {
    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      const itemId = String(button.dataset.sloppyStartItemMenu || "").trim();
      const panel = root.querySelector?.(`[data-sloppy-start-item-menu-panel="${itemId}"]`);
      if (!panel) {
        return;
      }
      const nextHidden = !panel.hidden;
      closeStartItemMenus(itemId);
      panel.hidden = nextHidden;
      button.setAttribute?.("aria-expanded", nextHidden ? "false" : "true");
    });
  });
  root.querySelectorAll?.("[data-sloppy-grid-menu]")?.forEach((button) => {
    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      closeStartItemMenus();
      const itemId = String(button.dataset.sloppyGridMenu || "").trim();
      const item = normalizedStartPageItems(state.settings).find((candidate) => String(candidate.id || "") === itemId);
      if (!item?.id) {
        return;
      }
      if (String(item.kind || "").trim() === "shortcut") {
        void openShortcutEditor(frame, item.id);
        return;
      }
      if (String(item.kind || "").trim() === "widget") {
        openWidgetEditor(frame, item.id);
      }
    });
  });
  root.querySelectorAll?.("[data-sloppy-resize-handle]")?.forEach((handle) => {
    const itemNode = handle.closest?.("[data-sloppy-grid-item]");
    applyResizeHandleEdge(handle, "bottom-right");
    itemNode?.addEventListener("pointermove", (event) => {
      if (event.target?.closest?.("[data-sloppy-resize-handle]")) {
        return;
      }
      const edge = resizeEdgeForPointer(itemNode, event);
      if (edge) {
        applyResizeHandleEdge(handle, edge);
      }
    });
    itemNode?.addEventListener("pointerleave", () => {
      if (!handle.classList.contains("is-resizing")) {
        applyResizeHandleEdge(handle, "bottom-right");
      }
    });
    let resizeDrag = null;
    const endResize = () => {
      handle.classList.remove("is-resizing");
      resizeDrag = null;
      document.removeEventListener("pointermove", onResizeMove);
      document.removeEventListener("pointerup", endResize);
      document.removeEventListener("pointercancel", endResize);
    };
    const onResizeMove = (event) => {
      if (!resizeDrag) {
        return;
      }
      const nextSpan = startPageResizeSpanForDrag(
        resizeDrag.item,
        event.clientX - resizeDrag.x,
        event.clientY - resizeDrag.y,
        resizeDrag.edge
      );
      if (nextSpan.colSpan === resizeDrag.lastColSpan && nextSpan.rowSpan === resizeDrag.lastRowSpan) {
        return;
      }
      resizeDrag.lastColSpan = nextSpan.colSpan;
      resizeDrag.lastRowSpan = nextSpan.rowSpan;
      renderStartPageItemsAnimated(frame, () => {
        resizeStartPageItem(resizeDrag.item.id, nextSpan.colSpan, nextSpan.rowSpan);
      });
      renderCustomizeDialog(frame, { skipStartPageItems: true });
    };
    handle.addEventListener("pointerdown", (event) => {
      event.preventDefault();
      event.stopPropagation();
      const itemId = String(handle.dataset.sloppyResizeHandle || "").trim();
      const item = normalizedStartPageItems(state.settings).find((candidate) => candidate.id === itemId);
      if (!item) {
        return;
      }
      const edge = handle.dataset.sloppyResizeEdge || "bottom-right";
      applyResizeHandleEdge(handle, edge);
      resizeDrag = {
        item,
        edge,
        x: event.clientX,
        y: event.clientY,
        lastColSpan: item.colSpan,
        lastRowSpan: item.rowSpan
      };
      handle.classList.add("is-resizing");
      handle.setPointerCapture?.(event.pointerId);
      document.addEventListener("pointermove", onResizeMove);
      document.addEventListener("pointerup", endResize);
      document.addEventListener("pointercancel", endResize);
    });
  });
  root.querySelectorAll?.("[data-sloppy-delete-item]")?.forEach((button) => {
    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      closeStartItemMenus();
      renderStartPageItemsAnimated(frame, () => {
        removeStartPageItem(button.dataset.sloppyDeleteItem);
      });
      renderCustomizeDialog(frame, { skipStartPageItems: true });
    });
  });
  Array.from(root.querySelectorAll?.("[data-sloppy-grid-draggable]") || []).forEach((node) => {
    node.addEventListener("dragstart", (event) => {
      const itemId = node.dataset.sloppyGridDraggable;
      if (!itemId) {
        event.preventDefault();
        return;
      }
      state.gridDrag = {
        activeId: itemId,
        overId: null,
        dropPosition: "after",
        dropIndex: null
      };
      event.dataTransfer?.setData?.("text/plain", itemId);
      node.classList.add("is-dragging");
    });
    node.addEventListener("dragend", () => {
      state.gridDrag = {
        activeId: null,
        overId: null,
        dropPosition: null,
        dropIndex: null
      };
      clearDragPreview();
      node.classList.remove("is-dragging");
      renderStartPageItems(frame);
    });
  });
  root.addEventListener("dragover", (event) => {
    if (!state.gridDrag.activeId) {
      return;
    }
    event.preventDefault();
    const dropIndex = startPageDropIndexForEvent(root, event);
    if (dropIndex === state.gridDrag.dropIndex) {
      return;
    }
    state.gridDrag = {
      ...state.gridDrag,
      overId: null,
      dropPosition: "at",
      dropIndex
    };
    renderStartPageItemsAnimated(frame, () => {
      moveStartPageItemToIndex(state.gridDrag.activeId, dropIndex);
    });
    renderCustomizeDialog(frame, { skipStartPageItems: true });
  });
  root.addEventListener("drop", (event) => {
    event.preventDefault();
    clearDragPreview();
    const droppedURL = readDroppedURL(event);
    if (droppedURL) {
      closeWidgetPickerSheet(frame);
      void openShortcutEditor(frame, null, { title: droppedURL, url: droppedURL });
      return;
    }
    state.gridDrag = {
      activeId: null,
      overId: null,
      dropPosition: null,
      dropIndex: null
    };
    renderStartPageItems(frame);
  });
}

function renderStartPageItems(frame) {
  const settings = state.settings || {};
  const items = normalizedStartPageItems(settings);
  renderStartPageShortcuts(frame, items);
  void hydrateStartPageWidgets(frame, items);
}

function syncStartPagePreview(frame, options = {}) {
  if (startPageLayoutMode(state.settings) === "canvas") {
    renderStartPageCanvas(frame);
    return;
  }
  if (options.animate === false) {
    renderStartPageItems(frame);
    return;
  }
  renderStartPageItemsAnimated(frame, () => {});
}

function normalizedWidgetSize(size) {
  return size === "medium" || size === "large" ? size : "small";
}

function widgetDimensionsForSize(size) {
  if (normalizedWidgetSize(size) === "medium") {
    return { width: 320, height: 180 };
  }
  if (normalizedWidgetSize(size) === "large") {
    return { width: 320, height: 320 };
  }
  return { width: 160, height: 120 };
}

function widgetSizeFromArtifact(artifact = {}, fallback = "small") {
  return normalizedWidgetSize(String(artifact?.widget?.size || artifact?.size || fallback || "small").trim());
}

function widgetHTMLForItem(item = {}) {
  const artifactId = String(item?.artifactId || item?.id || "").trim();
  return artifactId ? String(state.widgetHTMLByArtifactId?.[artifactId] || "").trim() : "";
}

function widgetFrameMarkupForItem(item = {}, html = "") {
  const title = escapeHTML(item.title || "Widget");
  const trimmedHTML = String(html || "").trim();
  if (!trimmedHTML) {
    return `<div class="sloppy-start-widget-placeholder">${escapeHTML(t("loadingArtifacts"))}</div>`;
  }
  const artifactId = String(item?.artifactId || item?.id || "").trim();
  const cachedRecord = artifactId ? state.widgetFrameURLByArtifactId?.[artifactId] : null;
  if (
    artifactId
    && typeof Blob === "function"
    && typeof URL?.createObjectURL === "function"
  ) {
    if (cachedRecord?.html === trimmedHTML && cachedRecord?.url) {
      return `<iframe title="${title}" sandbox="allow-scripts" src="${escapeHTML(cachedRecord.url)}"></iframe>`;
    }
    const scriptURLs = [];
    const rewrittenHTML = trimmedHTML.replace(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi, (match, attributes = "", source = "") => {
      if (/\bsrc\s*=/.test(attributes)) {
        return match;
      }
      const scriptSource = String(source || "").trim();
      if (!scriptSource) {
        return "";
      }
      const scriptURL = URL.createObjectURL(new Blob([scriptSource], { type: "text/javascript" }));
      scriptURLs.push(scriptURL);
      return `<script${attributes} src="${scriptURL}"></script>`;
    });
    const blobURL = URL.createObjectURL(new Blob([rewrittenHTML], { type: "text/html" }));
    if (typeof URL?.revokeObjectURL === "function") {
      if (cachedRecord?.url) {
        URL.revokeObjectURL(cachedRecord.url);
      }
      (cachedRecord?.scriptURLs || []).forEach((scriptURL) => {
        URL.revokeObjectURL(scriptURL);
      });
    }
    state.widgetFrameURLByArtifactId = {
      ...(state.widgetFrameURLByArtifactId || {}),
      [artifactId]: { html: trimmedHTML, url: blobURL, scriptURLs }
    };
    return `<iframe title="${title}" sandbox="allow-scripts" src="${escapeHTML(blobURL)}"></iframe>`;
  }
  return `<iframe title="${title}" sandbox="allow-scripts" srcdoc="${escapeHTML(trimmedHTML)}"></iframe>`;
}

async function hydrateStartPageWidgets(frame, items = []) {
  if (typeof chrome === "undefined" || typeof chrome.runtime?.sendMessage !== "function") {
    return;
  }
  const missingIds = Array.from(new Set((items || [])
    .filter((item) => String(item?.kind || "").trim() === "widget")
    .map((item) => String(item?.artifactId || "").trim())
    .filter((artifactId) => artifactId && !state.widgetHTMLByArtifactId?.[artifactId])));
  if (!missingIds.length) {
    return;
  }
  const loaded = {};
  await Promise.all(missingIds.map(async (artifactId) => {
    const response = await chrome.runtime.sendMessage({
      type: "sloppy.artifacts.widget",
      artifactId
    }).catch(() => null);
    const html = String(response?.html || "").trim();
    if (html) {
      loaded[artifactId] = html;
    }
  }));
  if (!Object.keys(loaded).length) {
    return;
  }
  state.widgetHTMLByArtifactId = {
    ...(state.widgetHTMLByArtifactId || {}),
    ...loaded
  };
  renderStartPageShortcuts(frame, items);
}

function renderStartPageShortcuts(frame, items) {
  const root = frame.querySelector("[data-sloppy-start-shortcuts]");
  if (!root) {
    return;
  }
  const isEditing = Boolean(state.customizeNavigation?.screen === "widgets" && state.customizeNavigation?.editing);
  const orderedItems = [...(items || [])].sort((lhs, rhs) => (Number(lhs.order) || 0) - (Number(rhs.order) || 0));
  const activeDragId = isEditing ? String(state.gridDrag?.activeId || "").trim() : "";
  const landingIndex = activeDragId ? Math.max(0, Number(state.gridDrag?.dropIndex) || 0) : -1;
  const renderedItems = [];
  orderedItems.forEach((item, index) => {
    if (activeDragId && index === landingIndex) {
      renderedItems.push({ kind: "landing-slot" });
    }
    renderedItems.push(item);
  });
  if (activeDragId && landingIndex >= orderedItems.length) {
    renderedItems.push({ kind: "landing-slot" });
  }
  root.innerHTML = renderedItems.map((item) => {
    if (String(item?.kind || "").trim() === "landing-slot") {
      return `<div class="sloppy-grid-landing-slot" data-sloppy-grid-landing-slot aria-hidden="true"></div>`;
    }
    const itemId = String(item?.id || "").trim();
    const itemKind = String(item?.kind || "").trim() === "widget" ? "widget" : "shortcut";
    const draggingClass = activeDragId && itemId === activeDragId ? " is-dragging" : "";
    const colSpan = itemKind === "shortcut" ? 1 : Math.max(1, Number(item?.colSpan) || 1);
    const rowSpan = itemKind === "shortcut" ? 1 : Math.max(1, Number(item?.rowSpan) || 1);
    const dragAttrs = isEditing && itemId
      ? `data-sloppy-grid-item="${escapeHTML(itemId)}" data-sloppy-grid-draggable="${escapeHTML(itemId)}" data-sloppy-grid-drop-target="${escapeHTML(itemId)}" draggable="true"`
      : `data-sloppy-grid-item="${escapeHTML(itemId)}" draggable="false"`;
    const editControls = isEditing && itemId
      ? `
        <div class="sloppy-start-item-controls">
          <button class="sloppy-icon-button sloppy-grid-menu-trigger" type="button" data-sloppy-start-item-menu="${escapeHTML(itemId)}" aria-label="${escapeHTML(t("editWidgets"))}" aria-haspopup="menu" aria-expanded="false">${icon("more")}</button>
          <div class="sloppy-start-item-menu" data-sloppy-start-item-menu-panel="${escapeHTML(itemId)}" role="menu" hidden>
            <button type="button" data-sloppy-grid-menu="${escapeHTML(itemId)}" role="menuitem">${escapeHTML(t("editWidgets"))}</button>
            <button type="button" data-sloppy-delete-item="${escapeHTML(itemId)}" role="menuitem">${escapeHTML(t("deleteItem"))}</button>
          </div>
        </div>
        ${itemKind === "widget" ? `<button class="sloppy-start-resize-handle" type="button" data-sloppy-resize-handle="${escapeHTML(itemId)}" aria-label="${escapeHTML(t("resizeItem"))}"></button>` : ""}
      `
      : "";
    if (itemKind === "widget") {
      const html = widgetHTMLForItem(item);
      return `
        <article class="sloppy-start-widget${draggingClass}" data-sloppy-start-widget="${escapeHTML(item.artifactId || "")}" ${dragAttrs} style="--sloppy-col-span:${colSpan};--sloppy-row-span:${rowSpan};">
          ${editControls}
          ${widgetFrameMarkupForItem(item, html)}
        </article>
      `;
    }
    return `
      <article class="sloppy-start-shortcut-card${draggingClass}" ${dragAttrs} style="--sloppy-col-span:${colSpan};--sloppy-row-span:${rowSpan};">
        ${editControls}
        <a href="${escapeHTML(item.url)}" data-sloppy-start-shortcut="${escapeHTML(item.url)}" draggable="false">
          <img class="sloppy-start-shortcut-icon" src="${escapeHTML(shortcutIconURL(item.url))}" alt="" aria-hidden="true">
          <span aria-hidden="true"></span>
          <span class="sloppy-start-shortcut-copy">
            <strong>${escapeHTML(item.title)}</strong>
            <span>${escapeHTML(item.url)}</span>
          </span>
        </a>
      </article>
    `;
  }).join("");
  renderStartPageShortcutDragHandlers(frame, root);
  root.querySelectorAll?.("img").forEach((image) => {
    image.addEventListener("error", () => {
      image.hidden = true;
    });
  });
}

function shortcutIconURL(url) {
  try {
    const parsed = new URL(url);
    return `${parsed.origin}/favicon.ico`;
  } catch (_error) {
    return "";
  }
}

function navigateCustomize(frame, screen) {
  state.customizeNavigation = {
    ...state.customizeNavigation,
    screen
  };
  renderCustomizeDialog(frame);
}

function renderCustomizeHomeScreen(frame) {
  const root = frame.querySelector("[data-sloppy-customize-body]");
  if (!root) {
    return;
  }
  root.innerHTML = `
    <section class="sloppy-customize-nav" data-sloppy-customize-screen="home">
      <button class="sloppy-customize-nav-card" type="button" data-sloppy-open-general>
        <strong>${escapeHTML(t("generalSection"))}</strong>
        <span>${escapeHTML(t("generalSectionHint"))}</span>
      </button>
      <button class="sloppy-customize-nav-card" type="button" data-sloppy-open-widgets>
        <strong>${escapeHTML(t("widgetsSection"))}</strong>
        <span>${escapeHTML(t("widgetsSectionHint"))}</span>
      </button>
    </section>
  `;
}

function renderCustomizeGeneralScreen(frame) {
  const root = frame.querySelector("[data-sloppy-customize-body]");
  if (!root) {
    return;
  }
  root.innerHTML = `
    <section class="sloppy-customize-screen" data-sloppy-customize-screen="general">
      <div class="sloppy-customize-toolbar">
        <button class="sloppy-settings-save" type="button" data-sloppy-customize-back>${escapeHTML(t("back"))}</button>
        <strong>${escapeHTML(t("generalSection"))}</strong>
      </div>
      <div class="sloppy-settings-section">
        <label class="sloppy-settings-toggle">
          <input data-sloppy-start-page-enabled type="checkbox">
          <span>${escapeHTML(t("enableStartPage"))}</span>
        </label>
        <label>${escapeHTML(t("theme"))}
          <select data-sloppy-start-page-theme>
            <option value="dark">${escapeHTML(t("darkTheme"))}</option>
            <option value="light">${escapeHTML(t("lightTheme"))}</option>
          </select>
        </label>
        <label>Layout
          <select data-sloppy-start-page-layout-mode>
            <option value="grid">Grid</option>
            <option value="canvas">Canvas</option>
          </select>
        </label>
        <label>${escapeHTML(t("backgroundImage"))}<input data-sloppy-start-page-background type="file" accept="image/png,image/jpeg,image/gif,image/webp"></label>
        <button class="sloppy-settings-save" type="button" data-sloppy-start-page-clear-background>${escapeHTML(t("clearBackground"))}</button>
        <p class="sloppy-settings-note" data-sloppy-start-page-error></p>
      </div>
    </section>
  `;
  root.querySelector("[data-sloppy-start-page-enabled]").checked = state.settings?.startPageEnabled !== false;
  root.querySelector("[data-sloppy-start-page-theme]").value = state.settings?.startPageTheme || "dark";
  root.querySelector("[data-sloppy-start-page-layout-mode]").value = startPageLayoutMode(state.settings);
}

function renderCustomizeWidgetsScreen(frame) {
  const root = frame.querySelector("[data-sloppy-customize-body]");
  if (!root) {
    return;
  }
  root.innerHTML = `
    <section class="sloppy-customize-screen" data-sloppy-customize-screen="widgets">
      <div class="sloppy-customize-toolbar">
        <button class="sloppy-settings-save" type="button" data-sloppy-open-general aria-label="${escapeHTML(t("generalSection"))}">
          ${icon("settings")}
        </button>
        <strong>${escapeHTML(t("widgetsSection"))}</strong>
        <span aria-hidden="true"></span>
      </div>
      <div class="sloppy-settings-section">
        <div class="sloppy-widgets-grid" data-sloppy-widgets-grid></div>
        ${renderWidgetPickerSheet(frame)}
        <p class="sloppy-settings-note" data-sloppy-start-page-error></p>
      </div>
    </section>
  `;
  renderWidgetsGrid(frame);
}

function renderCustomizeBottomAction(frame) {
  const root = frame.querySelector("[data-sloppy-customize-body]");
  if (!root) {
    return;
  }
  const screen = state.customizeNavigation?.screen || "widgets";
  const existingFooter = root.querySelector("[data-sloppy-customize-footer]");
  if (existingFooter) {
    existingFooter.remove();
  }
  if (screen !== "general" && screen !== "widgets") {
    return;
  }
  root.insertAdjacentHTML("beforeend", `
    <footer class="sloppy-customize-footer" data-sloppy-customize-footer>
      <button class="sloppy-settings-save" type="button" data-sloppy-save-customize>${escapeHTML(t("widgetEditorDone"))}</button>
    </footer>
  `);
}

function openWidgetEditor(frame, sourceItemId = null) {
  const sourceItem = normalizedStartPageItems(state.settings).find((item) => item.id === sourceItemId) || null;
  state.customizeNavigation = {
    ...state.customizeNavigation,
    widgetPickerSheet: { open: false },
    screen: "widget-editor",
    widgetDraftSourceId: sourceItemId,
    widgetSessionId: null,
    widgetChatExpanded: false,
    widgetDraft: sourceItem
      ? { ...sourceItem, html: widgetHTMLForItem(sourceItem) || "" }
      : { id: `widget-${Date.now()}`, kind: "widget", title: "", artifactId: "", colSpan: 2, rowSpan: 1, html: "" }
  };
  renderCustomizeDialog(frame);
}

function openWidgetPickerSheet(frame) {
  state.widgetPickerSheet = { open: true };
  renderCustomizeDialog(frame);
}

function closeWidgetPickerSheet(frame) {
  state.widgetPickerSheet = { open: false };
  renderCustomizeDialog(frame);
}

function renderWidgetPickerSheet(frame) {
  if (!state.widgetPickerSheet?.open) {
    return "";
  }
  const widgets = (state.artifacts || []).filter((artifact) => String(artifact?.kind || "").trim() === "widget");
  return `
    <section class="sloppy-widget-picker-sheet" data-sloppy-widget-picker-sheet>
      <header>
        <strong>${escapeHTML(t("createWidgetCard"))}</strong>
        <button class="sloppy-settings-save" type="button" data-sloppy-widget-picker-done>${escapeHTML(t("finishEditing"))}</button>
      </header>
      <div class="sloppy-widget-picker-grid">
        <button class="sloppy-widget-create-card" type="button" data-sloppy-create-widget-card>
          <span>+</span>
          <strong>${escapeHTML(t("createWidgetCard"))}</strong>
        </button>
        <button class="sloppy-widget-picker-card" type="button" data-sloppy-pick-shortcut-widget>${escapeHTML(t("shortcutWidget"))}</button>
        ${widgets.map((artifact) => `
          <article class="sloppy-widget-picker-card sloppy-widget-picker-card-with-action">
            <button class="sloppy-widget-picker-main" type="button" data-sloppy-pick-ready-widget="${escapeHTML(artifact.id || "")}">
              <strong>${escapeHTML(artifact.title || artifact.id || "Widget")}</strong>
              <span>${escapeHTML(widgetSizeFromArtifact(artifact, artifact.kind || "widget"))}</span>
            </button>
            <button class="sloppy-widget-picker-delete" type="button" data-sloppy-delete-ready-widget="${escapeHTML(artifact.id || "")}" aria-label="${escapeHTML(t("deleteItem"))}">${icon("trash")}</button>
          </article>
        `).join("")}
      </div>
    </section>
  `;
}

function openShortcutEditor(frame, sourceItemId = null, seed = null) {
  const sourceItem = normalizedStartPageItems(state.settings).find((item) => item.id === sourceItemId) || null;
  const nextSeed = sourceItem || null;
  const draft = nextSeed
    ? { ...nextSeed, kind: "shortcut" }
    : {
      id: `shortcut-${Date.now()}`,
      kind: "shortcut",
      title: "",
      url: "",
      colSpan: 1,
      rowSpan: 1,
      ...seed
    };
  state.customizeNavigation = {
    ...state.customizeNavigation,
    widgetPickerSheet: { open: false },
    screen: "shortcut-editor",
    widgetDraftSourceId: sourceItemId,
    widgetDraft: {
      ...draft,
      title: String(draft.title || "").trim() || String(draft.url || "").trim(),
      url: String(draft.url || "").trim() || String(seed?.url || "").trim(),
      colSpan: Math.max(1, Number(draft.colSpan) || 1),
      rowSpan: Math.max(1, Number(draft.rowSpan) || 1)
    }
  };
  void loadBookmarksIfAvailable(frame);
  renderCustomizeDialog(frame);
}

function commitShortcutDraft(frame) {
  const draft = state.customizeNavigation?.widgetDraft;
  if (!draft?.url) {
    navigateCustomize(frame, "widgets");
    return;
  }
  if (startPageLayoutMode(state.settings) === "canvas") {
    addShortcutToCanvas(draft);
    void persistStartPageCanvas();
    state.customizeNavigation = {
      ...state.customizeNavigation,
      screen: "widgets",
      widgetDraft: null,
      widgetDraftSourceId: null
    };
    syncStartPagePreview(frame);
    renderCustomizeDialog(frame);
    return;
  }
  updateStartPageItems((items) => {
    const nextItem = {
      id: draft.id,
      kind: "shortcut",
      title: draft.title || draft.url,
      url: draft.url,
      colSpan: draft.colSpan || 1,
      rowSpan: draft.rowSpan || 1
    };
    if (state.customizeNavigation?.widgetDraftSourceId) {
      return items.map((item) => item.id === state.customizeNavigation.widgetDraftSourceId ? nextItem : item);
    }
    return [...items, { ...nextItem, order: items.length }];
  });
  state.customizeNavigation = {
    ...state.customizeNavigation,
    screen: "widgets",
    widgetDraft: null,
    widgetDraftSourceId: null
  };
  syncStartPagePreview(frame);
  renderCustomizeDialog(frame);
}

function renderShortcutEditor(frame) {
  const root = frame.querySelector("[data-sloppy-customize-body]");
  if (!root) {
    return;
  }
  const draft = state.customizeNavigation?.widgetDraft || {};
  root.innerHTML = `
    <section class="sloppy-customize-screen" data-sloppy-customize-screen="shortcut-editor">
      <div class="sloppy-customize-toolbar">
        <button class="sloppy-settings-save" type="button" data-sloppy-shortcut-editor-cancel>${escapeHTML(t("widgetEditorCancel"))}</button>
        <strong>${escapeHTML(t("shortcutWidget"))}</strong>
        <button class="sloppy-settings-save" type="button" data-sloppy-shortcut-editor-done>${escapeHTML(t("widgetEditorDone"))}</button>
      </div>
      <label>${escapeHTML(t("shortcutTitle"))}
        <input data-sloppy-shortcut-title value="${escapeHTML(draft.title || "")}" />
      </label>
      <label>${escapeHTML(t("shortcutUrl"))}
        <input data-sloppy-shortcut-url value="${escapeHTML(draft.url || "")}" placeholder="https://example.com" />
      </label>
      ${state.availableBookmarks?.length ? `
        <section class="sloppy-shortcut-bookmarks" data-sloppy-shortcut-bookmarks>
          <div class="sloppy-shortcut-bookmarks-header">
            <strong>${escapeHTML(t("shortcutBookmarks"))}</strong>
            <span>${escapeHTML(t("shortcutBookmarksHint"))}</span>
          </div>
          ${state.availableBookmarks.map((bookmark) => `
            <button type="button" class="sloppy-shortcut-bookmark-card" data-sloppy-pick-bookmark="${escapeHTML(bookmark.id)}">
              <strong>${escapeHTML(bookmark.title || bookmark.url)}</strong>
              <span>${escapeHTML(bookmark.url)}</span>
            </button>
          `).join("")}
        </section>
      ` : ""}
      <p class="sloppy-settings-note" data-sloppy-start-page-error></p>
    </section>
  `;
}

async function loadBookmarksIfAvailable(frame) {
  const response = await chrome.runtime.sendMessage({ type: "sloppy.bookmarks.list" }).catch(() => ({ error: "bookmarks_unavailable" }));
  state.availableBookmarks = Array.isArray(response)
    ? response
      .map((bookmark) => ({
        id: String(bookmark?.id || "").trim(),
        title: String(bookmark?.title || bookmark?.url || "").trim(),
        url: String(bookmark?.url || "").trim()
      }))
      .filter((bookmark) => bookmark.id && bookmark.url)
    : [];
  const screen = state.customizeNavigation?.screen;
  if (screen === "shortcut-editor") {
    renderCustomizeDialog(frame);
  }
}

function widgetEditorPreviewDimensions(colSpan, rowSpan) {
  const gap = 8;
  const column = (620 - (gap * 3)) / 4;
  const row = 88;
  const columns = Math.max(1, Number(colSpan) || 1);
  const rows = Math.max(1, Number(rowSpan) || 1);
  return {
    width: Math.round((column * columns) + (gap * Math.max(0, columns - 1))),
    height: Math.round((row * rows) + (gap * Math.max(0, rows - 1)))
  };
}

function renderWidgetEditor(frame) {
  const root = frame.querySelector("[data-sloppy-customize-body]");
  if (!root) {
    return;
  }
  const draft = state.customizeNavigation?.widgetDraft || {};
  const previewDimensions = widgetEditorPreviewDimensions(draft.colSpan || 2, draft.rowSpan || 1);
  root.innerHTML = `
    <section class="sloppy-customize-screen sloppy-widget-editor-screen" data-sloppy-customize-screen="widget-editor">
      <header class="sloppy-widget-editor-topbar">
        <div class="sloppy-widget-editor-actions">
          <button class="sloppy-settings-save" type="button" data-sloppy-widget-editor-done>${escapeHTML(t("saveChanges"))}</button>
          <button class="sloppy-settings-save" type="button" data-sloppy-widget-editor-cancel>${escapeHTML(t("widgetEditorCancel"))}</button>
        </div>
        <strong class="sloppy-widget-editor-title">${escapeHTML(draft.title || t("createWidget"))}</strong>
      </header>
      <div class="sloppy-widget-editor-layout">
        <section class="sloppy-widget-editor-canvas">
          <div class="sloppy-widget-editor-preview-pane">
            <article class="sloppy-widget-editor-preview" data-sloppy-widget-preview style="--sloppy-col-span:${draft.colSpan || 2};--sloppy-row-span:${draft.rowSpan || 1};--sloppy-widget-preview-width:${previewDimensions.width}px;--sloppy-widget-preview-height:${previewDimensions.height}px;">
              ${draft.html
                ? `<iframe title="${escapeHTML(draft.title || "Widget draft")}" sandbox="allow-scripts" srcdoc="${escapeHTML(draft.html)}"></iframe>`
                : `<div class="sloppy-widget-editor-empty">${escapeHTML(t("describeWidget"))}</div>`}
            </article>
          </div>
          <div class="sloppy-widget-editor-controls">
            <button class="sloppy-settings-save" type="button" data-sloppy-widget-editor-resize="2x1">2x1</button>
            <button class="sloppy-settings-save" type="button" data-sloppy-widget-editor-resize="2x2">2x2</button>
            <button class="sloppy-settings-save" type="button" data-sloppy-widget-editor-resize="3x2">3x2</button>
          </div>
          <p class="sloppy-settings-note" role="alert" data-sloppy-start-page-error></p>
        </section>
      </div>
    </section>
  `;
}

function renderCustomizeDialog(frame, options = {}) {
  const motionRects = options.animateMotion === false ? null : captureCustomizeMotion(frame);
  if (!options.skipStartPageItems) {
    renderStartPageItems(frame);
  }
  const screen = state.customizeNavigation?.screen || "widgets";
  const customizeDialog = frame.querySelector("[data-sloppy-customize-dialog]");
  customizeDialog?.classList?.toggle?.("is-widget-editor", screen === "widget-editor");
  frame.classList?.toggle?.("is-widget-editing", screen === "widget-editor");
  frame.classList?.toggle?.("is-widget-chat-expanded", screen === "widget-editor" && Boolean(state.customizeNavigation?.widgetChatExpanded));
  frame.querySelector("[data-sloppy-widget-chat-sheet-toggle]")?.setAttribute?.(
    "aria-expanded",
    screen === "widget-editor" && state.customizeNavigation?.widgetChatExpanded ? "true" : "false"
  );
  if (screen === "general") {
    renderCustomizeGeneralScreen(frame);
    renderCustomizeBottomAction(frame);
  } else if (screen === "widgets") {
    renderCustomizeWidgetsScreen(frame);
    renderCustomizeBottomAction(frame);
  } else if (screen === "widget-editor") {
    renderWidgetEditor(frame);
  } else if (screen === "shortcut-editor") {
    renderShortcutEditor(frame);
  }
  else {
    renderCustomizeWidgetsScreen(frame);
    renderCustomizeBottomAction(frame);
  }
  if (motionRects) {
    requestAnimationFrame?.(() => animateCustomizeMotion(frame, motionRects));
  }
}

function openCustomize(frame) {
  const motionRects = captureCustomizeMotion(frame);
  const customizeButton = frame.querySelector("[data-sloppy-customize]");
  if (customizeButton) {
    customizeButton.hidden = true;
  }
  frame.classList.add("is-start-customizing");
  state.customizeNavigation = {
    screen: "widgets",
    editing: true,
    widgetDraft: null,
    widgetDraftSourceId: null
  };
  state.widgetPickerSheet = { open: false };
  state.availableBookmarks = [];
  state.gridDrag = {
    activeId: null,
    overId: null,
    dropPosition: null
  };
  if (!state.artifacts.length) {
    void loadArtifacts(frame);
  }
  renderCustomizeDialog(frame, { animateMotion: false });
  const customizeDialog = frame.querySelector("[data-sloppy-customize-dialog]");
  if (!customizeDialog) {
    return;
  }
  const openDialog = customizeDialog.show || customizeDialog.showModal;
  if (typeof openDialog !== "function") {
    return;
  }
  if (customizeDialog.open) {
    state.ignoreCustomizeCloseReset = true;
    customizeDialog.close();
    state.ignoreCustomizeCloseReset = false;
  }
  customizeDialog.classList.remove("sloppy-customize-dialog-open");
  openDialog.call(customizeDialog);
  requestAnimationFrame(() => {
    customizeDialog?.classList.add("sloppy-customize-dialog-open");
    animateCustomizeMotion(frame, motionRects);
  });
}

function exitCustomizeMode(frame) {
  const motionRects = captureCustomizeMotion(frame);
  const customizeButton = frame.querySelector("[data-sloppy-customize]");
  if (customizeButton) {
    customizeButton.hidden = false;
  }
  frame.classList.remove("is-start-customizing");
  frame.classList.remove("is-widget-editing");
  frame.classList.remove("is-widget-chat-expanded");
  state.customizeNavigation = {
    ...(state.customizeNavigation || {}),
    screen: "widgets",
    editing: false,
    widgetDraft: null,
    widgetDraftSourceId: null,
    widgetChatExpanded: false
  };
  state.gridDrag = {
    activeId: null,
    overId: null,
    dropPosition: null,
    dropIndex: null
  };
  const customizeDialog = frame.querySelector("[data-sloppy-customize-dialog]");
  customizeDialog?.classList.remove("sloppy-customize-dialog-open");
  customizeDialog?.classList.remove("is-widget-editor");
  frame.querySelector("[data-sloppy-widget-chat-sheet-toggle]")?.setAttribute?.("aria-expanded", "false");
  requestAnimationFrame?.(() => animateCustomizeMotion(frame, motionRects));
}

function closeCustomize(frame) {
  exitCustomizeMode(frame);
  const customizeDialog = frame.querySelector("[data-sloppy-customize-dialog]");
  if (customizeDialog?.open && typeof customizeDialog.close === "function") {
    customizeDialog.close();
  }
}

function updateStartPageLayoutToggle(frame) {
  const button = frame.querySelector("[data-sloppy-start-layout-toggle]");
  if (!button) {
    return;
  }
  const isCanvas = startPageLayoutMode(state.settings) === "canvas";
  button.classList.toggle("is-active", isCanvas);
  button.setAttribute("aria-pressed", isCanvas ? "true" : "false");
  button.setAttribute("aria-label", isCanvas ? t("gridMode") : t("canvasMode"));
  const iconSlot = button.querySelector("[data-sloppy-start-layout-icon]");
  if (iconSlot && typeof startPageLayoutToggleIconName === "function" && typeof icon === "function") {
    iconSlot.innerHTML = icon(startPageLayoutToggleIconName(state.settings));
  }
  const label = button.querySelector("[data-sloppy-start-layout-label]");
  if (label) {
    label.textContent = isCanvas ? t("gridMode") : t("canvasMode");
  }
}

async function toggleStartPageLayoutMode(frame) {
  const nextMode = startPageLayoutMode(state.settings) === "canvas" ? "grid" : "canvas";
  const settings = {
    ...(state.settings || {}),
    startPageLayoutMode: nextMode,
    startPageShortcuts: startPageShortcutItems(state.settings),
    startPageItems: state.settings?.startPageItems || []
  };
  const savedSettings = await chrome.runtime.sendMessage({ type: "sloppy.settings.save", settings });
  const responseSettings = savedSettings
      && typeof savedSettings === "object"
      && !savedSettings.error
      && !Array.isArray(savedSettings)
      && Object.prototype.hasOwnProperty.call(savedSettings, "startPageLayoutMode")
    ? savedSettings
    : settings;
  state.settings = {
    ...responseSettings,
    startPageLayoutMode: nextMode
  };
  syncStartPagePreview(frame, { animate: false });
  renderStartPageSurface(frame);
  updateStartPageLayoutToggle(frame);
}

async function saveCustomize(frame) {
  const startPageEnabled = frame.querySelector("[data-sloppy-start-page-enabled]")?.checked;
  const startPageTheme = frame.querySelector("[data-sloppy-start-page-theme]")?.value;
  const startPageLayout = frame.querySelector("[data-sloppy-start-page-layout-mode]")?.value;
  const settings = {
    ...(state.settings || {}),
    startPageEnabled: startPageEnabled ?? state.settings?.startPageEnabled !== false,
    startPageTheme: startPageTheme || state.settings?.startPageTheme || "dark",
    startPageBackgroundImage: state.settings?.startPageBackgroundImage || "",
    startPageLayoutMode: startPageLayoutMode({ startPageLayoutMode: startPageLayout || state.settings?.startPageLayoutMode }),
    startPageShortcuts: startPageShortcutItems(state.settings),
    startPageItems: state.settings?.startPageItems || []
  };
  if (startPageLayoutMode(settings) === "canvas") {
    await persistStartPageCanvas();
  }
  state.settings = await chrome.runtime.sendMessage({ type: "sloppy.settings.save", settings });
  closeCustomize(frame);
  syncStartPagePreview(frame, { animate: false });
  render(frame);
  updateStartPageLayoutToggle(frame);
}

function parseGridSpan(value) {
  const [colSpan, rowSpan] = String(value || "")
    .split("x")
    .map((part) => Math.max(1, Number(part) || 1));
  return { colSpan, rowSpan };
}

function isSupportedShortcutURL(value) {
  try {
    const url = new URL(String(value || "").trim());
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

function readDroppedURL(event) {
  const text = String(event.dataTransfer?.getData?.("text/uri-list") || event.dataTransfer?.getData?.("text/plain") || "").trim();
  return isSupportedShortcutURL(text) ? text : "";
}

function widgetSessionPrompt(prompt) {
  const trimmed = String(prompt || "").trim();
  const command = trimmed.toLowerCase().startsWith("/widget") ? trimmed : `/widget ${trimmed}`;
  const draft = state.customizeNavigation?.widgetDraft || {};
  const sourceId = String(state.customizeNavigation?.widgetDraftSourceId || "").trim();
  const details = [
    "",
    "Widget session context:",
    "- This session is dedicated only to generating and iterating the start-page widget preview.",
    "- Do not answer as a normal page chat; update the widget artifact for the preview.",
    "- Create or update the preview only with the `artifacts.widget.generate` tool.",
    "- Never use `files.write`, `files.edit`, or any arbitrary filesystem path for widget output.",
    "- Persist the result as a widget artifact under the artifact system, not as a standalone file.",
    `- Widget title: ${String(draft.title || "Widget draft").trim()}`,
    `- Widget size: ${Math.max(1, Number(draft.colSpan) || 2)}x${Math.max(1, Number(draft.rowSpan) || 1)}`,
    `- Widget source item id: ${sourceId || "new-widget"}`
  ];
  if (draft.artifactId) {
    details.push(`- Existing artifact id: ${String(draft.artifactId).trim()}`);
  }
  return `${command}\n${details.join("\n")}`;
}

function widgetEditorContext() {
  if (state.context?.page?.url) {
    return state.context;
  }
  if (typeof extractPageContext === "function") {
    return extractPageContext(document, typeof selectedText === "function" ? selectedText() : "");
  }
  return {
    page: {
      url: document?.location?.href || "",
      title: document?.title || null
    },
    selection: ""
  };
}

function widgetEditorSessionMetadata() {
  const draft = state.customizeNavigation?.widgetDraft || {};
  const sourceId = String(state.customizeNavigation?.widgetDraftSourceId || "").trim();
  const colSpan = Math.max(1, Number(draft.colSpan) || 2);
  const rowSpan = Math.max(1, Number(draft.rowSpan) || 1);
  return {
    mode: "widget_editor",
    isolated: true,
    sessionId: state.customizeNavigation?.widgetSessionId || null,
    sourceItemId: sourceId || null,
    widget: {
      kind: "widget",
      title: String(draft.title || "Widget draft").trim(),
      size: `${colSpan}x${rowSpan}`,
      colSpan,
      rowSpan,
      artifactId: draft.artifactId || null,
      sourceItemId: sourceId || null
    }
  };
}

async function latestWidgetArtifactAfterSession(previousWidgetIds) {
  const listResponse = await chrome.runtime.sendMessage({ type: "sloppy.artifacts.list" }).catch(() => null);
  const artifacts = Array.isArray(listResponse)
    ? listResponse
    : Array.isArray(listResponse?.artifacts)
      ? listResponse.artifacts
      : [];
  const widgets = artifacts.filter((artifact) => String(artifact?.kind || "").trim() === "widget");
  const createdWidget = [...widgets].reverse().find((artifact) => !previousWidgetIds.has(String(artifact?.id || "")));
  return createdWidget || widgets.at(-1) || null;
}

async function updateWidgetDraftFromPrompt(frame, prompt) {
  const previousWidgetIds = new Set((state.artifacts || [])
    .filter((artifact) => String(artifact?.kind || "").trim() === "widget")
    .map((artifact) => String(artifact?.id || "").trim())
    .filter(Boolean));
  state.customizeNavigation = {
    ...state.customizeNavigation,
    widgetDraft: {
      ...(state.customizeNavigation?.widgetDraft || {}),
      userPrompt: prompt,
      assistantText: t("thinking"),
      isGenerating: true
    }
  };
  renderCustomizeDialog(frame);
  const context = widgetEditorContext();
  const response = await chrome.runtime.sendMessage({
    type: "sloppy.browserContext.stream",
    requestId: globalThis.crypto?.randomUUID?.() || `${Date.now()}-widget`,
    sessionId: state.customizeNavigation?.widgetSessionId || "",
    page: context.page,
    selection: context.selection || "",
    prompt: widgetSessionPrompt(prompt),
    widgetSession: widgetEditorSessionMetadata(),
    tabs: state.tabs || [],
    attachments: [],
    model: state.settings?.selectedModel || "default"
  }).catch((error) => ({ error: error.message }));
  if (response?.sessionId) {
    state.customizeNavigation = {
      ...(state.customizeNavigation || {}),
      widgetSessionId: response.sessionId
    };
  }
  const artifact = response?.artifact || await latestWidgetArtifactAfterSession(previousWidgetIds);
  if (response?.error || !artifact?.id) {
    const startPageError = frame.querySelector("[data-sloppy-start-page-error]");
    const message = response?.error || response?.text || "Widget generation failed.";
    if (startPageError) {
      startPageError.textContent = message;
    }
    state.customizeNavigation = {
      ...state.customizeNavigation,
      widgetDraft: {
        ...(state.customizeNavigation?.widgetDraft || {}),
        assistantText: message,
        isGenerating: false
      }
    };
    renderCustomizeDialog(frame);
    return {
      error: message,
      text: message
    };
  }
  let html = String(response?.html || artifact?.html || "").trim();
  if (!html) {
    const widgetResponse = await chrome.runtime.sendMessage({
      type: "sloppy.artifacts.widget",
      artifactId: artifact.id
    }).catch(() => null);
    html = String(widgetResponse?.html || "").trim();
  }
  state.artifactError = "";
  state.artifacts = [artifact, ...(state.artifacts || []).filter((candidate) => candidate?.id !== artifact.id)];
  state.widgetHTMLByArtifactId = {
    ...(state.widgetHTMLByArtifactId || {}),
    [artifact.id]: html
  };
  state.customizeNavigation = {
    ...state.customizeNavigation,
    widgetDraft: {
      ...(state.customizeNavigation.widgetDraft || {}),
      artifactId: artifact.id,
      title: artifact.title || artifact.id,
      html,
      userPrompt: prompt,
      assistantText: response?.text || t("widgetPreviewUpdated"),
      isGenerating: false
    }
  };
  renderCustomizeDialog(frame);
  return {
    artifact,
    response,
    text: response?.text || t("widgetPreviewUpdated")
  };
}

function commitWidgetDraft(frame) {
  const draft = state.customizeNavigation?.widgetDraft;
  if (!draft?.artifactId) {
    navigateCustomize(frame, "widgets");
    return;
  }
  if (startPageLayoutMode(state.settings) === "canvas") {
    addWidgetArtifactToCanvas({
      artifactId: draft.artifactId,
      title: draft.title || draft.artifactId,
      width: widgetEditorPreviewDimensions(draft.colSpan || 2, draft.rowSpan || 1).width,
      height: widgetEditorPreviewDimensions(draft.colSpan || 2, draft.rowSpan || 1).height
    });
    if (draft.html && draft.artifactId) {
      state.widgetHTMLByArtifactId = {
        ...(state.widgetHTMLByArtifactId || {}),
        [draft.artifactId]: draft.html
      };
    }
    void persistStartPageCanvas();
    state.customizeNavigation = {
      ...state.customizeNavigation,
      screen: "widgets",
      widgetDraft: null,
      widgetDraftSourceId: null
    };
    syncStartPagePreview(frame);
    renderCustomizeDialog(frame);
    return;
  }
  updateStartPageItems((items) => {
    const nextItem = {
      id: draft.id || draft.artifactId,
      kind: "widget",
      artifactId: draft.artifactId,
      title: draft.title || draft.artifactId,
      colSpan: draft.colSpan || 2,
      rowSpan: draft.rowSpan || 1
    };
    if (state.customizeNavigation?.widgetDraftSourceId) {
      return items.map((item) => item.id === state.customizeNavigation.widgetDraftSourceId ? nextItem : item);
    }
    return [...items, { ...nextItem, order: items.length }];
  });
  if (draft.html && draft.artifactId) {
    state.widgetHTMLByArtifactId = {
      ...(state.widgetHTMLByArtifactId || {}),
      [draft.artifactId]: draft.html
    };
  }
  state.customizeNavigation = {
    ...state.customizeNavigation,
    screen: "widgets",
    widgetDraft: null,
    widgetDraftSourceId: null
  };
  syncStartPagePreview(frame);
  renderCustomizeDialog(frame);
}

async function loadArtifacts(frame) {
  const response = await chrome.runtime.sendMessage({ type: "sloppy.artifacts.list" }).catch((error) => ({
    error: error?.message || t("noArtifacts")
  }));
  if (response?.error) {
    state.artifacts = [];
    state.artifactError = String(response.error || "").trim() || t("noArtifacts");
  } else {
    const artifacts = Array.isArray(response)
      ? response
      : Array.isArray(response?.artifacts)
        ? response.artifacts
        : [];
    state.artifacts = artifacts;
    state.artifactError = "";
  }
  renderWidgetPicker(frame);
  renderWidgetsGrid(frame);
}

function renderWidgetPicker(frame) {
  const root = frame.querySelector("[data-sloppy-widget-picker]");
  if (!root) {
    return;
  }
  const widgets = (state.artifacts || []).filter((artifact) => String(artifact?.kind || "").trim() === "widget");
  if (!widgets.length) {
    root.innerHTML = "";
    return;
  }
  root.innerHTML = widgets.map((artifact) => `
    <button class="sloppy-session-row" type="button" data-sloppy-pick-widget="${escapeHTML(artifact.id || "")}">
      <strong>${escapeHTML(artifact.title || artifact.id || "Widget")}</strong>
      <span>${escapeHTML(widgetSizeFromArtifact(artifact, artifact.kind || "widget"))}</span>
    </button>
  `).join("");
}

async function addWidgetToStartPage(frame, artifactId, options = {}) {
  const id = String(artifactId || "").trim();
  if (!id) {
    return;
  }
  const requestedSize = normalizedWidgetSize(String(frame.querySelector("[data-sloppy-widget-size]")?.value || "small").trim());
  const artifact = (state.artifacts || []).find((candidate) => candidate?.id === id) || {};
  const response = await chrome.runtime.sendMessage({
    type: "sloppy.artifacts.widget",
    artifactId: id
  }).catch((error) => ({ error: error.message }));
  if (response?.error) {
    frame.querySelector("[data-sloppy-start-page-error]").textContent = response.error;
    return;
  }
  const size = normalizedWidgetSize(String(response?.size || artifact?.widget?.size || artifact.size || requestedSize).trim());
  const dimensions = widgetDimensionsForSize(size);
  state.widgetHTMLByArtifactId = {
    ...(state.widgetHTMLByArtifactId || {}),
    [id]: String(response?.html || "").trim()
  };
  const widget = {
    kind: "widget",
    artifactId: id,
    title: String(response?.title || artifact.title || id).trim() || id,
    size,
    width: dimensions.width,
    height: dimensions.height
  };
  if (startPageLayoutMode(state.settings) === "canvas") {
    addWidgetArtifactToCanvas({
      artifactId: id,
      title: widget.title,
      width: dimensions.width,
      height: dimensions.height
    });
    void persistStartPageCanvas();
    renderStartPageCanvas(frame);
    renderWidgetPicker(frame);
    return;
  }
  renderStartPageItemsAnimated(frame, () => {
    const baseItems = startPageItemsForMutation(state.settings);
    state.settings = {
      ...(state.settings || {}),
      startPageItems: [
        ...baseItems.filter((item) => String(item?.artifactId || "") !== id),
        widget
      ]
    };
    state.settings.startPageShortcuts = startPageShortcutItems(state.settings);
  });
  const startPageError = frame.querySelector("[data-sloppy-start-page-error]");
  if (startPageError) {
    startPageError.textContent = "";
  }
  if (options.persist) {
    state.settings = await chrome.runtime.sendMessage({ type: "sloppy.settings.save", settings: state.settings });
  }
  renderWidgetPicker(frame);
}

function readStartPageBackgroundImage(file, frame) {
  const error = frame.querySelector("[data-sloppy-start-page-error]");
  if (!file) {
    return Promise.resolve();
  }
  if (!/^image\/(png|jpe?g|gif|webp)$/i.test(file.type || "")) {
    error.textContent = t("unsupportedBackgroundImage");
    return Promise.resolve();
  }
  if (file.size > 560000) {
    error.textContent = t("backgroundImageTooLarge");
    return Promise.resolve();
  }
  return new Promise((resolve) => {
    const reader = new FileReader();
    reader.addEventListener("load", () => {
      state.settings = {
        ...(state.settings || {}),
        startPageBackgroundImage: String(reader.result || "")
      };
      error.textContent = "";
      resolve();
    });
    reader.addEventListener("error", () => {
      error.textContent = t("backgroundImageReadFailed");
      resolve();
    });
    reader.readAsDataURL(file);
  });
}
