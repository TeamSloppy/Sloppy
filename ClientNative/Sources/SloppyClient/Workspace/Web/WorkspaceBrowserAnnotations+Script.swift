#if os(macOS)
extension WorkspaceBrowserAnnotations {
    static let inspectorScript = #"""
    const element = document.elementFromPoint(x * innerWidth, y * innerHeight);
    if (!element) return null;
    const path = [];
    for (let node = element; node && path.length < 6; node = node.parentElement) {
      if (node.id && document.querySelectorAll('#' + CSS.escape(node.id)).length === 1) {
        path.unshift('#' + CSS.escape(node.id)); break;
      }
      const siblings = node.parentElement ? [...node.parentElement.children].filter(n => n.tagName === node.tagName) : [node];
      path.unshift(node.localName + ':nth-of-type(' + (siblings.indexOf(node) + 1) + ')');
    }
    const r = element.getBoundingClientRect();
    const left = Math.max(0, r.left), top = Math.max(0, r.top);
    return { nonce, pageURL: location.href, title: document.title.slice(0, 200), selector: path.join(' > '), tag: element.localName,
      elementID: element.id.slice(0, 1024), classNames: [...element.classList].slice(0, 64).map(name => name.slice(0, 128)),
      x: left / innerWidth, y: top / innerHeight,
      width: Math.max(0, Math.min(innerWidth, r.right) - left) / innerWidth,
      height: Math.max(0, Math.min(innerHeight, r.bottom) - top) / innerHeight };
    """#
}
#endif
