(() => {
  const state = { dirty: false, rtc: -1 };
  const doc = crypto.randomUUID?.() ?? `${Date.now()}-${Math.random()}`;
  const send = body => window.webkit.messageHandlers.sloppyPageRetention.postMessage(body);
  const changed = () => send({ event: "changed" });
  const dirty = () => {
    if (!state.dirty) { state.dirty = true; changed(); }
  };
  document.addEventListener("input", dirty, true);
  document.addEventListener("change", dirty, true);
  new MutationObserver(records => {
    if (records.some(record => record.target instanceof HTMLIFrameElement
        || [...record.addedNodes, ...record.removedNodes].some(node => node instanceof Element && (node.matches("iframe,frame") || node.querySelector("iframe,frame"))))) changed();
  }).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ["src"] });
  document.addEventListener("pointerdown", event => {
    if (event.target instanceof Element && event.target.closest("canvas,[contenteditable]")) dirty();
  }, true);
  document.addEventListener("sloppy-retention-rtc-state", event => {
    if (typeof event.detail === "number" && state.rtc !== event.detail) {
      state.rtc = event.detail;
      if (state.rtc !== 0) changed();
    }
  });
  const probe = (id, parent = null) => {
    document.dispatchEvent(new Event("sloppy-retention-rtc-request"));
    const playing = [...document.querySelectorAll("audio,video")].some(media => !media.paused && !media.ended);
    send({ event: "probe", id, doc, parent, children: window.frames.length,
      ready: document.readyState !== "loading", dirty: state.dirty, rtc: state.rtc, playing });
    for (let index = 0; index < window.frames.length; index++) {
      window.frames[index].postMessage({ type: "sloppy-retention-probe", id, parent: doc }, "*");
    }
  };
  window.addEventListener("message", event => {
    const data = event.data;
    if (event.source === window.parent && data?.type === "sloppy-retention-probe"
        && typeof data.id === "string" && typeof data.parent === "string") probe(data.id, data.parent);
  });
  globalThis.__sloppyPageRetention = { probe };
})();
