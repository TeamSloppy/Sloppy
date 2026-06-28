// Start page and widget customization helpers for contentScript.js.
function renderStartPageSurface(frame) {
  const thread = frame.querySelector("[data-sloppy-thread]");
  const settings = state.settings || {};
  const theme = settings.startPageTheme === "light" ? "light" : "dark";
  frame.classList.toggle("sloppy-theme-light", theme === "light");
  frame.style.setProperty("--sloppy-start-background-image", settings.startPageBackgroundImage ? `url("${settings.startPageBackgroundImage}")` : "none");
  thread.innerHTML = `
    <section class="sloppy-start-surface" data-sloppy-start-surface data-sloppy-start-theme="${escapeHTML(theme)}">
    </section>
  `;
  renderStartPageItems(frame);
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
          ${html
            ? `<iframe title="${escapeHTML(item.title || "Widget")}" sandbox="allow-scripts" srcdoc="${escapeHTML(html)}"></iframe>`
            : `<div class="sloppy-start-widget-placeholder">${escapeHTML(t("loadingArtifacts"))}</div>`}
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
        <label>${escapeHTML(t("backgroundImage"))}<input data-sloppy-start-page-background type="file" accept="image/png,image/jpeg,image/gif,image/webp"></label>
        <button class="sloppy-settings-save" type="button" data-sloppy-start-page-clear-background>${escapeHTML(t("clearBackground"))}</button>
        <p class="sloppy-settings-note" data-sloppy-start-page-error></p>
      </div>
    </section>
  `;
  root.querySelector("[data-sloppy-start-page-enabled]").checked = state.settings?.startPageEnabled !== false;
  root.querySelector("[data-sloppy-start-page-theme]").value = state.settings?.startPageTheme || "dark";
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
  state.customizeNavigation = {
    ...(state.customizeNavigation || {}),
    screen: "widgets",
    editing: false,
    widgetDraft: null,
    widgetDraftSourceId: null
  };
  state.gridDrag = {
    activeId: null,
    overId: null,
    dropPosition: null,
    dropIndex: null
  };
  const customizeDialog = frame.querySelector("[data-sloppy-customize-dialog]");
  customizeDialog?.classList.remove("sloppy-customize-dialog-open");
  requestAnimationFrame?.(() => animateCustomizeMotion(frame, motionRects));
}

function closeCustomize(frame) {
  exitCustomizeMode(frame);
  const customizeDialog = frame.querySelector("[data-sloppy-customize-dialog]");
  if (customizeDialog?.open && typeof customizeDialog.close === "function") {
    customizeDialog.close();
  }
}

async function saveCustomize(frame) {
  const startPageEnabled = frame.querySelector("[data-sloppy-start-page-enabled]")?.checked;
  const startPageTheme = frame.querySelector("[data-sloppy-start-page-theme]")?.value;
  const settings = {
    ...(state.settings || {}),
    startPageEnabled: startPageEnabled ?? state.settings?.startPageEnabled !== false,
    startPageTheme: startPageTheme || state.settings?.startPageTheme || "dark",
    startPageBackgroundImage: state.settings?.startPageBackgroundImage || "",
    startPageShortcuts: startPageShortcutItems(state.settings),
    startPageItems: state.settings?.startPageItems || []
  };
  state.settings = await chrome.runtime.sendMessage({ type: "sloppy.settings.save", settings });
  closeCustomize(frame);
  syncStartPagePreview(frame, { animate: false });
  render(frame);
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
