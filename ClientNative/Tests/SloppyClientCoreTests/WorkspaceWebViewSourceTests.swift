import Foundation
import Testing

@Suite("Workspace webview source")
struct WorkspaceWebViewSourceTests {
    private func source(_ path: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("workspace panel exposes files reviews and web browser modes")
    func workspacePanelExposesFilesReviewsAndWebBrowserModes() throws {
        let panelVM = try source("Sources/SloppyClient/WorkspacePanelViewModel.swift")
        let panelView = try source("Sources/SloppyClient/WorkspacePanelView.swift")

        #expect(panelVM.contains("enum WorkspacePanelMode"))
        #expect(panelVM.contains("case files"))
        #expect(panelVM.contains("case reviews"))
        #expect(panelVM.contains("case webBrowser"))
        #expect(panelVM.contains("var mode: WorkspacePanelMode"))
        #expect(panelVM.contains("var webViewModel: WorkspaceWebViewModel"))
        #expect(panelView.contains("switch viewModel.mode"))
        #expect(panelView.contains("\"Files\""))
        #expect(panelView.contains("\"Reviews\""))
        #expect(panelView.contains("\"Web browser\""))
    }

    @Test("workspace web view model owns browser session state")
    func workspaceWebViewModelOwnsBrowserSessionState() throws {
        let sourceText = try source("Sources/SloppyClient/WorkspaceWebViewModel.swift")

        #expect(sourceText.contains("final class WorkspaceWebViewModel"))
        #expect(sourceText.contains("var currentURL"))
        #expect(sourceText.contains("var addressText"))
        #expect(sourceText.contains("var pageTitle"))
        #expect(sourceText.contains("var isLoading"))
        #expect(sourceText.contains("var canGoBack"))
        #expect(sourceText.contains("var canGoForward"))
        #expect(sourceText.contains("var lastError"))
    }

    @Test("workspace web view wraps WKWebView and syncs navigation state")
    func workspaceWebViewWrapsWKWebViewAndSyncsNavigationState() throws {
        let webViewSource = try source("Sources/SloppyClient/WorkspaceWebView.swift")
        let modelSource = try source("Sources/SloppyClient/WorkspaceWebViewModel.swift")

        #expect(webViewSource.contains("import WebKit"))
        #expect(webViewSource.contains("WKWebView"))
        #expect(webViewSource.contains("NSViewRepresentable"))
        #expect(modelSource.contains("func openAddress()"))
        #expect(modelSource.contains("func reload()"))
        #expect(modelSource.contains("func goBack()"))
        #expect(modelSource.contains("func goForward()"))
    }
}
