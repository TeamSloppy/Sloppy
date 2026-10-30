#if os(macOS)
import AppKit
import WebKit

/// Augments WebKit's native context menu without replacing link, image or text actions.
@MainActor
class WorkspaceBrowserWebView: WKWebView {
    private lazy var pageActions = WorkspaceBrowserPageActions(webView: self)

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        isInspectable = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isInspectable = true
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        prepareContextMenu(menu)
    }

    func prepareContextMenu(_ menu: NSMenu) {
        // These identifiers describe WebKit's menu presentation; original item targets
        // and actions are retained, including system inspector actions when present.
        let navigationIDs: Set<String> = ["WKMenuItemIdentifierGoBack", "WKMenuItemIdentifierGoForward", "WKMenuItemIdentifierReload"]
        let original = menu.items.filter {
            let id = $0.identifier?.rawValue ?? ""
            return !id.hasPrefix("sloppy.browser.context.") && !navigationIDs.contains(id)
        }
        let inspector = original.filter { $0.identifier?.rawValue == "WKMenuItemIdentifierInspectElement" }
        let contextual = original.filter { $0.identifier?.rawValue != "WKMenuItemIdentifierInspectElement" }
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
#endif
