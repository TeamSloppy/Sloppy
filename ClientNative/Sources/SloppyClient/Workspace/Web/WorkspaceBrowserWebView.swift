#if os(macOS)
import AppKit
import WebKit

/// Augments WebKit's native context menu without replacing link, image or text actions.
@MainActor
class WorkspaceBrowserWebView: WKWebView {
    private let contextLink = BrowserContextLink()
    private lazy var pageActions = WorkspaceBrowserPageActions(webView: self)

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        contextLink.install(in: self)
        isInspectable = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        contextLink.install(in: self)
        isInspectable = true
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        prepareContextMenu(menu, event: event)
    }

    func prepareContextMenu(_ menu: NSMenu, event: NSEvent? = nil) {
        // These identifiers describe WebKit's menu presentation; original item targets
        // and actions are retained, including system inspector actions when present.
        let navigationIDs: Set<String> = ["WKMenuItemIdentifierGoBack", "WKMenuItemIdentifierGoForward", "WKMenuItemIdentifierReload"]
        let original = menu.items.filter {
            let id = $0.identifier?.rawValue ?? ""
            return !id.hasPrefix("sloppy.browser.context.") && !navigationIDs.contains(id)
        }
        let inspector = original.filter { $0.identifier?.rawValue == "WKMenuItemIdentifierInspectElement" }
        var contextual = original.filter { $0.identifier?.rawValue != "WKMenuItemIdentifierInspectElement" }
        if let event, let url = contextLink.takeURL(for: event, in: self),
           (navigationDelegate as? WorkspaceBrowserToolRuntime)?.onOpenLinkInNewTab != nil,
           let index = contextual.firstIndex(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierOpenLinkInNewWindow" }) {
            let item = NSMenuItem(title: "Open Link in New Tab", action: #selector(openContextLinkInNewTab(_:)), keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier("sloppy.browser.context.open-in-new-tab")
            item.target = self
            item.representedObject = url
            contextual.insert(item, at: index)
        }
        menu.removeAllItems()
        menu.autoenablesItems = false
        menu.addItem(item("Back", "back", #selector(WorkspaceBrowserPageActions.goBack(_:)), enabled: canGoBack))
        menu.addItem(item("Forward", "forward", #selector(WorkspaceBrowserPageActions.goForward(_:)), enabled: canGoForward))
        menu.addItem(item("Reload", "reload", #selector(WorkspaceBrowserPageActions.reloadPage(_:)), enabled: url != nil))
        appendSection(contextual, to: menu)
        let hasDocument = url != nil || title?.isEmpty == false
        appendSection([
            item("Save As…", "save", #selector(WorkspaceBrowserPageActions.savePage(_:)), enabled: hasDocument),
            item("Print…", "print", #selector(WorkspaceBrowserPageActions.printPage(_:)), enabled: hasDocument),
        ], to: menu)
        appendSection([
            item("Create QR Code for this Page", "qr", #selector(WorkspaceBrowserPageActions.showQRCode(_:)),
                 enabled: BrowserSearchEngine.websiteURL(url) != nil),
            item("Translate to Russian (Google)", "translate", #selector(WorkspaceBrowserPageActions.translatePage(_:)),
                 enabled: WorkspaceBrowserPageActions.translationURL(for: url) != nil),
        ], to: menu)
        let inspection = inspector.isEmpty
            ? [item("Inspect in Safari…", "inspect", #selector(WorkspaceBrowserPageActions.inspectInSafari(_:)), enabled: hasDocument)]
            : inspector
        appendSection([
            item("View Page Source", "source", #selector(WorkspaceBrowserPageActions.showPageSource(_:)), enabled: hasDocument),
        ] + inspection, to: menu)
    }

    @objc private func openContextLinkInNewTab(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        (navigationDelegate as? WorkspaceBrowserToolRuntime)?.onOpenLinkInNewTab?(url)
    }

    private func item(_ title: String, _ id: String, _ action: Selector, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier("sloppy.browser.context." + id)
        item.target = pageActions
        item.isEnabled = enabled
        return item
    }

    private func appendSection(_ items: [NSMenuItem], to menu: NSMenu) {
        var section = items
        while section.first?.isSeparatorItem == true { section.removeFirst() }
        while section.last?.isSeparatorItem == true { section.removeLast() }
        guard !section.isEmpty else { return }
        menu.addItem(.separator())
        for item in section {
            if item.isSeparatorItem && menu.items.last?.isSeparatorItem == true { continue }
            menu.addItem(item)
        }
    }
}

/// Pairs an isolated world's trusted DOM context click with the native menu event.
@MainActor
private final class BrowserContextLink: NSObject, WKScriptMessageHandler {
    private static let world = WKContentWorld.world(name: "SloppyBrowserContextLink")
    private static let messageName = "sloppyBrowserContextLink"
    private weak var webView: WKWebView?
    private var hit: (url: URL, point: CGPoint, pageURL: URL?, time: ContinuousClock.Instant)?

    func install(in webView: WKWebView) {
        self.webView = webView
        let controller = webView.configuration.userContentController
        controller.add(self, contentWorld: Self.world, name: Self.messageName)
        controller.addUserScript(WKUserScript(source: """
        document.addEventListener("contextmenu", event => {
            if (!event.isTrusted) return;
            const link = event.composedPath().find(node => node.localName === "a" || node.localName === "area");
            const href = link?.getAttribute("href") ?? link?.getAttributeNS("http://www.w3.org/1999/xlink", "href");
            let url = "";
            if (href != null) {
                try { url = new URL(href, link.baseURI).href; } catch {}
            }
            window.webkit.messageHandlers.sloppyBrowserContextLink.postMessage({ url, x: event.screenX, y: event.screenY });
        }, true);
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: Self.world))
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView, message.webView === webView else { return }
        hit = nil
        guard let body = message.body as? [String: Any],
              let address = body["url"] as? String,
              let url = BrowserSearchEngine.websiteURL(URL(string: address)),
              let x = body["x"] as? Double, let y = body["y"] as? Double else { return }
        hit = (url, CGPoint(x: x, y: y), webView.url, .now)
    }

    func takeURL(for event: NSEvent, in webView: WKWebView) -> URL? {
        defer { hit = nil }
        guard let hit, hit.pageURL == webView.url, hit.time.duration(to: .now) < .seconds(2),
              let screen = event.window?.screen ?? NSScreen.screens.first else { return nil }
        let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        guard abs(point.x - hit.point.x) <= 2, abs(screen.frame.maxY - point.y - hit.point.y) <= 2 else { return nil }
        return hit.url
    }
}
#endif
