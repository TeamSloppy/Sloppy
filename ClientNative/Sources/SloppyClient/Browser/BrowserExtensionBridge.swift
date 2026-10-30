#if os(macOS)
import Foundation
import AppKit
import WebKit

@MainActor
final class BrowserExtensionBridge: NSObject, WKWebExtensionControllerDelegate, WKWebExtensionWindow {
    weak var state: BrowserWorkspaceState?
    private var tabObjects: [UUID: BrowserExtensionTab] = [:]
    private struct TabSnapshot {
        var url: URL?
        var title: String?
        var isLoading: Bool
    }
    private var snapshots: [UUID: TabSnapshot] = [:]
    private var optionWindows: [UUID: NSWindowController] = [:]

    init(state: BrowserWorkspaceState) {
        self.state = state
        super.init()
        state.extensions.controller.delegate = self
        state.extensions.controller.didOpenWindow(self)
    }

    func tab(_ id: UUID) -> BrowserExtensionTab {
        if let tab = tabObjects[id] { return tab }
        let tab = BrowserExtensionTab(id: id, bridge: self)
        tabObjects[id] = tab
        return tab
    }

    func opened(_ id: UUID) { state?.extensions.controller.didOpenTab(tab(id)) }

    func closed(_ id: UUID) {
        guard let state else { return }
        state.extensions.controller.didCloseTab(tab(id))
        tabObjects.removeValue(forKey: id)
        snapshots.removeValue(forKey: id)
    }

    func selectionChanged(from previous: UUID?) {
        guard let state, previous != state.selectedID else { return }
        if let previous { state.extensions.controller.didDeselectTabs([tab(previous)]) }
        if let id = state.selectedID {
            state.extensions.controller.didSelectTabs([tab(id)])
            state.extensions.controller.didActivateTab(tab(id), previousActiveTab: previous.map(tab))
        }
    }

    func changed(_ id: UUID) {
        guard let state, let page = state.pages[id] else { return }
        let next = TabSnapshot(url: page.currentURL, title: page.pageTitle, isLoading: page.isLoading)
        let previous = snapshots[id]
        var properties: WKWebExtension.TabChangedProperties = []
        if previous?.url != next.url { properties.insert(.URL) }
        if previous?.title != next.title { properties.insert(.title) }
        if previous?.isLoading != next.isLoading { properties.insert(.loading) }
        snapshots[id] = next
        if !properties.isEmpty { state.extensions.controller.didChangeTabProperties(properties, for: tab(id)) }
    }

    func reordered(from previous: [UUID]) {
        guard let state else { return }
        for (index, id) in previous.enumerated() where state.tabs.firstIndex(where: { $0.id == id }) != index {
            state.extensions.controller.didMoveTab(tab(id), from: index, in: self)
        }
    }

    func performAction(_ id: UUID) {
        guard let state, let context = state.extensions.contexts[id], context.isLoaded else { return }
        context.performAction(for: state.selectedID.map(tab))
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { state?.tabs.map { tab($0.id) } ?? [] }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { state?.selectedID.map(tab) }
    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor context: WKWebExtensionContext) -> [any WKWebExtensionWindow] { [self] }

    func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                for context: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? {
        guard let state, let url = BrowserSearchEngine.websiteURL(configuration.url) else { throw BridgeError.unsupportedURL }
        let previous = state.selectedID
        state.open(url, inNewTab: true)
        guard let id = state.selectedID else { return nil }
        if configuration.index < state.tabs.count - 1 {
            state.move(from: IndexSet(integer: state.tabs.count - 1), to: configuration.index)
        }
        if !configuration.shouldBeActive {
            if let previous { state.select(previous) } else { state.showHome() }
        }
        return tab(id)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor context: WKWebExtensionContext) async throws {
        guard let url = context.optionsPageURL else { throw BridgeError.unsupportedURL }
        let config = WKWebViewConfiguration()
        config.webExtensionController = controller
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 650), configuration: config)
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = context.webExtension.displayName ?? "Extension settings"
        window.contentView = view
        window.isReleasedWhenClosed = false
        let id = UUID()
        let owner = BrowserExtensionOptionsWindow(window: window)
        owner.onClose = { [weak self] in self?.optionWindows.removeValue(forKey: id) }
        optionWindows[id] = owner
        window.delegate = owner
        view.load(URLRequest(url: url))
        owner.showWindow(nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action,
                                for context: WKWebExtensionContext) async throws {
        guard let view = state?.selectedPage?.nativeWebView, view.window != nil,
              let popover = action.popupPopover else { throw BridgeError.noVisibleTab }
        popover.behavior = .transient
        popover.show(relativeTo: NSRect(x: view.bounds.maxX - 30, y: 12, width: 20, height: 20), of: view, preferredEdge: .maxY)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                in tab: (any WKWebExtensionTab)?, for context: WKWebExtensionContext) async -> (Set<WKWebExtension.Permission>, Date?) {
        guard await approve(permissions.map(\.rawValue), context: context) else { return ([], nil) }
        for permission in permissions { context.setPermissionStatus(.grantedExplicitly, for: permission) }
        state?.extensions.saveGrants(for: context)
        return (permissions, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionMatchPatterns patterns: Set<WKWebExtension.MatchPattern>,
                                in tab: (any WKWebExtensionTab)?, for context: WKWebExtensionContext) async -> (Set<WKWebExtension.MatchPattern>, Date?) {
        guard await approve(patterns.map(\.string), context: context) else { return ([], nil) }
        for pattern in patterns { context.setPermissionStatus(.grantedExplicitly, for: pattern) }
        state?.extensions.saveGrants(for: context)
        return (patterns, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>,
                                in tab: (any WKWebExtensionTab)?, for context: WKWebExtensionContext) async -> (Set<URL>, Date?) {
        guard await approve(urls.map(\.absoluteString), context: context) else { return ([], nil) }
        for url in urls { context.setPermissionStatus(.grantedExplicitly, for: url) }
        state?.extensions.saveGrants(for: context)
        return (urls, nil)
    }

    private func approve(_ items: [String], context: WKWebExtensionContext) async -> Bool {
        guard let view = state?.selectedPage?.nativeWebView, let window = view.window else { return false }
        let alert = NSAlert()
        alert.messageText = "Allow \(context.webExtension.displayName ?? "extension") access?"
        alert.informativeText = items.sorted().joined(separator: "\n")
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }

    enum BridgeError: LocalizedError {
        case unsupportedURL, noVisibleTab
        var errorDescription: String? {
            switch self {
            case .unsupportedURL: "Sloppy extensions can open HTTP and HTTPS tabs. Open extension settings from Web Extensions."
            case .noVisibleTab: "Select a visible browser tab to use this extension."
            }
        }
    }
}

@MainActor
final class BrowserExtensionTab: NSObject, WKWebExtensionTab {
    let id: UUID
    weak var bridge: BrowserExtensionBridge?
    init(id: UUID, bridge: BrowserExtensionBridge) { self.id = id; self.bridge = bridge }
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { bridge }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { bridge?.state?.pages[id]?.ensureBrowserRuntime().webView }
    func title(for context: WKWebExtensionContext) -> String? { bridge?.state?.tabs.first { $0.id == id }?.title }
    func url(for context: WKWebExtensionContext) -> URL? { bridge?.state?.tabs.first { $0.id == id }?.url }
    func isSelected(for context: WKWebExtensionContext) -> Bool { bridge?.state?.selectedID == id }
    func activate(for context: WKWebExtensionContext) async throws { bridge?.state?.select(id) }
    func close(for context: WKWebExtensionContext) async throws { bridge?.state?.close(id) }
    func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws {
        guard BrowserSearchEngine.websiteURL(url) != nil else { throw BrowserExtensionBridge.BridgeError.unsupportedURL }
        bridge?.state?.navigate(url, inTab: id)
    }
}

@MainActor
private final class BrowserExtensionOptionsWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}
#endif
