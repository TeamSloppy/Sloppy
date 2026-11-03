#if os(macOS)
import SwiftUI
import WebKit

extension FocusedValues {
    @Entry var workBrowseWorkspace: BrowserWorkspaceState?
}

struct WorkBrowseToggleButton: View {
    let workspace: BrowserWorkspaceState?

    var body: some View {
        Button(workspace?.isBrowsing == true ? "Switch to Work" : "Switch to Browse") {
            workspace?.isBrowsing.toggle()
            workspace?.checkpoint()
        }
        .keyboardShortcut("b", modifiers: [.command, .shift])
        .disabled(workspace == nil)
    }
}
struct BrowserReloadWithoutCacheButton: View {
    let workspace: BrowserWorkspaceState?

    var body: some View {
        Button("Reload Without Cache") {
            if let page = workspace?.selectedPage { Task { await page.reloadWithoutCache() } }
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(workspace?.isBrowsing != true || workspace?.selectedPage?.currentURL == nil
                  || workspace?.selectedPage?.isReloadingWithoutCache == true)
        .help("Clear cached files for this browser profile and reload the active page. Cookies and sign-in data are kept.")
        .accessibilityIdentifier("browser-reload-without-cache")
    }
}

enum BrowserPageCommand: CaseIterable {
    case back, forward, zoomIn, zoomOut, actualSize

    private static let zoomLevels: [Double] = [0.5, 0.67, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    var title: String {
        switch self {
        case .back: "Back"
        case .forward: "Forward"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .actualSize: "Actual Size"
        }
    }

    var key: KeyEquivalent {
        switch self {
        case .back: "["
        case .forward: "]"
        case .zoomIn: "="
        case .zoomOut: "-"
        case .actualSize: "0"
        }
    }

    @MainActor
    func isEnabled(in workspace: BrowserWorkspaceState?) -> Bool {
        guard let workspace, workspace.isBrowsing, !workspace.isSearchPresented,
              let page = workspace.selectedPage else { return false }
        switch self {
        case .back: return page.canGoBack
        case .forward: return page.canGoForward
        case .zoomIn, .zoomOut, .actualSize: return page.nativeWebView != nil
        }
    }

    @MainActor
    func perform(in workspace: BrowserWorkspaceState?) {
        guard isEnabled(in: workspace), let page = workspace?.selectedPage else { return }
        switch self {
        case .back: page.goBack()
        case .forward: page.goForward()
        case .zoomIn:
            guard let webView = page.nativeWebView else { return }
            webView.pageZoom = Self.zoomLevels.first { $0 > webView.pageZoom + 0.001 } ?? 3
        case .zoomOut:
            guard let webView = page.nativeWebView else { return }
            webView.pageZoom = Self.zoomLevels.last { $0 < webView.pageZoom - 0.001 } ?? 0.5
        case .actualSize: page.nativeWebView?.pageZoom = 1
        }
    }
}

struct BrowserPageCommandButton: View {
    let command: BrowserPageCommand
    let workspace: BrowserWorkspaceState?
    var key: KeyEquivalent?

    var body: some View {
        Button(command.title) { command.perform(in: workspace) }
            .keyboardShortcut(key ?? command.key, modifiers: .command)
            .disabled(!command.isEnabled(in: workspace))
    }
}

struct BrowserPageCommandButtons: View {
    let workspace: BrowserWorkspaceState?

    var body: some View {
        Group {
            BrowserPageCommandButton(command: .back, workspace: workspace)
            BrowserPageCommandButton(command: .forward, workspace: workspace)
            Divider()
            BrowserPageCommandButton(command: .zoomIn, workspace: workspace)
            BrowserPageCommandButton(command: .zoomOut, workspace: workspace)
            BrowserPageCommandButton(command: .actualSize, workspace: workspace)
        }
    }
}
#endif
