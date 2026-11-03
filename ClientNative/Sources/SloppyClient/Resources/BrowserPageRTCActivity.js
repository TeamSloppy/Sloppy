(() => {
  const peers = new Set();
  const Native = window.RTCPeerConnection ?? window.webkitRTCPeerConnection;
  let Wrapped;
  const publish = () => {
    for (const reference of peers) {
      const peer = reference.deref();
      if (!peer || peer.connectionState === "closed") peers.delete(reference);
    }
    const known = !Native || window.RTCPeerConnection === Wrapped;
    document.dispatchEvent(new CustomEvent("sloppy-retention-rtc-state", { detail: known ? peers.size : -1 }));
  };
  if (typeof Native === "function") {
    Wrapped = new Proxy(Native, {
      construct(target, args, newTarget) {
        const peer = Reflect.construct(target, args, newTarget);
        const reference = new WeakRef(peer);
        peers.add(reference);
        peer.addEventListener("connectionstatechange", publish);
        publish();
        return peer;
      }
    });
    try {
      window.RTCPeerConnection = Wrapped;
      if (window.webkitRTCPeerConnection === Native) window.webkitRTCPeerConnection = Wrapped;
    } catch { }
  }
  document.addEventListener("sloppy-retention-rtc-request", publish);
  publish();
})();
