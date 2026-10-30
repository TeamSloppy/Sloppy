// Runs in a private content world and modifies only main-document layout.
(() => {
  const initialInset = __SLOPPY_DOCUMENT_INSET__;
  if (globalThis.__sloppyBrowserDocumentInset) {
    globalThis.__sloppyBrowserDocumentInset.setInset(initialInset);
    return true;
  }

  let inset = 0;
  let scheduled = false;
  const pending = new Set();
  const owned = new Map();
  const observer = new MutationObserver(records => {
    for (const record of records) {
      if (record.type === "attributes") schedule(record.target);
      else {
        for (const node of record.addedNodes) if (node.nodeType === Node.ELEMENT_NODE) schedule(node);
        if (record.removedNodes.length) schedule(record.target);
      }
    }
  });

  function schedule(root = document.documentElement) {
    if (!inset) return;
    if (root) pending.add(root);
    if (!scheduled) {
      scheduled = true;
      queueMicrotask(() => { if (scheduled) apply(); });
    }
  }

  function restore(includeRoot) {
    for (const [element, properties] of owned) {
      if (!includeRoot && element === document.documentElement) continue;
      for (const [name, property] of properties) {
        const value = element.style.getPropertyValue(name);
        const priority = element.style.getPropertyPriority(name);
        if (value === property.applied && priority === "important") {
          if (property.original) element.style.setProperty(name, property.original, property.priority);
          else element.style.removeProperty(name);
        } else {
          // A site may update its own inline layout after our previous pass.
          property.original = value;
          property.priority = priority;
        }
        property.applied = null;
      }
    }
  }

  function set(element, name, value) {
    let properties = owned.get(element);
    if (!properties) { properties = new Map(); owned.set(element, properties); }
    let property = properties.get(name);
    if (!property) {
      property = { original: element.style.getPropertyValue(name), priority: element.style.getPropertyPriority(name) };
      properties.set(name, property);
    }
    element.style.setProperty(name, value, "important");
    property.applied = element.style.getPropertyValue(name);
  }

  function usesViewport(element, fixed) {
    for (let parent = element.parentElement; parent && parent !== document.documentElement; parent = parent.parentElement) {
      const style = getComputedStyle(parent);
      if (fixed) {
        if (style.transform !== "none" || style.perspective !== "none" || style.filter !== "none" ||
            /(?:layout|paint|strict|content)/.test(style.contain) ||
            /(?:transform|perspective|filter)/.test(style.willChange)) return false;
      } else if (parent !== document.body && /^(auto|scroll|overlay|hidden)$/.test(style.overflowY)) {
        return false;
      }
    }
    return true;
  }

  function adjust(element, updates) {
    if (!(element instanceof HTMLElement) || element === document.documentElement ||
        element.closest("[data-sloppy-browser-overlay]")) return;
    const style = getComputedStyle(element);
    if (style.position !== "fixed" && style.position !== "sticky") return;
    if (!/^-?[\d.]+px$/.test(style.top)) return;
    const top = parseFloat(style.top);
    if (style.position === "fixed" && top < inset && usesViewport(element, true)) {
      updates.push([element, "margin-top", `${(parseFloat(style.marginTop) || 0) + inset}px`]);
    } else if (style.position === "sticky" && usesViewport(element, false)) {
      updates.push([element, "top", `${top + inset}px`]);
    }
  }

  function apply() {
    scheduled = false;
    observer.disconnect();
    const candidates = new Set(owned.keys());
    const root = document.documentElement;
    const measureRoot = !inset || !owned.has(root) || pending.has(root) || pending.has(document) || pending.has(document.body);
    restore(measureRoot);
    if (inset && root) {
      if (measureRoot) {
        const style = getComputedStyle(root);
        const padding = parseFloat(style.paddingTop) || 0;
        const scrollPadding = parseFloat(style.scrollPaddingTop) || 0;
        set(root, "padding-top", `${padding + inset}px`);
        set(root, "scroll-padding-top", `${scrollPadding + inset}px`);
      }
      const roots = [...pending].filter(node => node.isConnected);
      for (const node of roots) {
        if (roots.some(other => other !== node && other.contains(node))) continue;
        const walker = document.createTreeWalker(node, NodeFilter.SHOW_ELEMENT);
        candidates.add(node);
        while (walker.nextNode()) candidates.add(walker.currentNode);
      }
      const updates = [];
      for (const element of candidates) if (element.isConnected) adjust(element, updates);
      for (const [element, name, value] of updates) set(element, name, value);
    }
    pending.clear();
    for (const [element, properties] of owned) {
      for (const [name, property] of properties) if (property.applied === null) properties.delete(name);
      if (!properties.size || !element.isConnected) owned.delete(element);
    }
    if (inset) observer.observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ["class", "style"] });
  }

  globalThis.__sloppyBrowserDocumentInset = {
    setInset(value) {
      scheduled = false;
      inset = Math.max(0, Number(value) || 0);
      if (!inset) {
        observer.disconnect();
        apply();
      } else {
        // Apply root padding before first paint; newly parsed nodes are handled
        // incrementally, without scanning the whole document on every mutation.
        pending.add(document.documentElement || document);
        apply();
      }
    }
  };
  window.addEventListener("resize", () => schedule());
  window.addEventListener("pageshow", () => schedule());
  document.addEventListener("DOMContentLoaded", () => schedule(), { once: true });
  document.addEventListener("load", event => { if (event.target instanceof HTMLLinkElement) schedule(); }, true);
  globalThis.__sloppyBrowserDocumentInset.setInset(initialInset);
  return true;
})();
