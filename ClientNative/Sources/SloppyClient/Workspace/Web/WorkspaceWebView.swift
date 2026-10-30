import SwiftUI
import SloppyClientUI

#if os(macOS)
import WebKit

@MainActor
struct WorkspaceWebView: NSViewRepresentable {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let viewModel: WorkspaceWebViewModel?
    let artifactHTML: String?
    let artifactTitle: String
    private var topContentInset: CGFloat = 0
    private var onFocus: (@MainActor () -> Void)?

    init(viewModel: WorkspaceWebViewModel, topContentInset: CGFloat = 0, onFocus: (@MainActor () -> Void)? = nil) {
        self.viewModel = viewModel
        self.topContentInset = topContentInset
        self.onFocus = onFocus
        artifactHTML = nil
        artifactTitle = "Web content"
    }

    init(html: String, title: String) {
        viewModel = nil
        artifactHTML = html
        artifactTitle = title
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> WKWebView {
        if let viewModel {
            let webView = viewModel.ensureBrowserRuntime().webView
            viewModel.nativeWebView = webView
            webView.underPageBackgroundColor = nil
            context.coordinator.observePageBackground(webView)
            context.coordinator.updateFocusTracking(webView, onFocus: onFocus)
            context.coordinator.updateToolbarBlur(webView, height: topContentInset, enabled: !reduceTransparency)
            viewModel.browserRuntime?.documentInset.update(BrowserToolbarBackdrop.unobscuredContentInset(for: topContentInset))
            webView.obscuredContentInsets = NSEdgeInsetsZero
            return webView
        }
        let configuration = WKWebViewConfiguration()
        if artifactHTML != nil {
            configuration.websiteDataStore = .nonPersistent()
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(webView)
        if let artifactHTML {
            webView.loadHTMLString(Self.sandboxedDocument(artifactHTML), baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.updateFocusTracking(nsView, onFocus: onFocus)
        nsView.underPageBackgroundColor = viewModel == nil ? NSColor(theme.colors.surface) : nil
        if viewModel != nil { context.coordinator.updateToolbarBlur(nsView, height: topContentInset, enabled: !reduceTransparency) }
        viewModel?.browserRuntime?.documentInset.update(BrowserToolbarBackdrop.unobscuredContentInset(for: topContentInset))
        let insets = NSEdgeInsetsZero
        if !NSEdgeInsetsEqual(nsView.obscuredContentInsets, insets) { nsView.obscuredContentInsets = insets }
        guard let artifactHTML,
              context.coordinator.loadedArtifactHTML != artifactHTML else { return }
        context.coordinator.loadedArtifactHTML = artifactHTML
        nsView.loadHTMLString(Self.sandboxedDocument(artifactHTML), baseURL: nil)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.detachToolbarBlur()
        coordinator.stopFocusTracking()
    }

    private static func sandboxedDocument(_ html: String) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: blob:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; font-src data:">
        <style>html,body{margin:0;min-height:100%;background:transparent;color-scheme:light dark}</style>
        </head><body>\(html)</body></html>
        """
    }
}

@MainActor
final class Coordinator: NSObject, WKNavigationDelegate, WorkspaceWebViewControlling {
    private var backgroundObservation: NSKeyValueObservation?
    private var toolbarBackdrop: BrowserToolbarBackdrop?
    private var focusMonitor: Any?
    private var onFocus: (@MainActor () -> Void)?
    private let viewModel: WorkspaceWebViewModel?
    private weak var webView: WKWebView?
    var loadedArtifactHTML: String?

    init(viewModel: WorkspaceWebViewModel?) {
        self.viewModel = viewModel
    }

    func updateFocusTracking(_ webView: WKWebView, onFocus: (@MainActor () -> Void)?) {
        self.onFocus = onFocus
        guard onFocus != nil else { stopFocusTracking(); return }
        guard focusMonitor == nil else { return }
        focusMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self, weak webView] event in
            MainActor.assumeIsolated {
                if let webView { self?.focusIfNeeded(for: event, in: webView) }
            }
            return event
        }
    }

    func focusIfNeeded(for event: NSEvent, in webView: WKWebView) {
        guard let window = webView.window, event.window === window else { return }
        let isInside: Bool
        if event.type == .keyDown {
            isInside = (window.firstResponder as? NSView)?.isDescendant(of: webView) == true
        } else {
            isInside = webView.visibleRect.contains(webView.convert(event.locationInWindow, from: nil))
        }
        if isInside { onFocus?() }
    }

    func stopFocusTracking() {
        if let focusMonitor { NSEvent.removeMonitor(focusMonitor) }
        focusMonitor = nil
        onFocus = nil
    }

    func observePageBackground(_ webView: WKWebView) {
        webView.wantsLayer = true
        webView.layer?.backgroundColor = webView.underPageBackgroundColor?.cgColor
        backgroundObservation = webView.observe(\.underPageBackgroundColor, options: [.new]) { [weak webView] _, _ in
            Task { @MainActor [weak webView] in
                guard let webView else { return }
                webView.layer?.backgroundColor = webView.underPageBackgroundColor?.cgColor
            }
        }
    }

    func updateToolbarBlur(_ webView: WKWebView, height: CGFloat, enabled: Bool) {
        guard height > 0, enabled else {
            detachToolbarBlur()
            return
        }
        if toolbarBackdrop == nil { toolbarBackdrop = BrowserToolbarBackdrop(webView: webView) }
        toolbarBackdrop?.update(toolbarHeight: height, enabled: enabled)
    }

    func detachToolbarBlur() {
        toolbarBackdrop?.detach()
        toolbarBackdrop = nil
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
        viewModel?.controller = self
        syncState(from: webView)
    }

    func open(_ address: String) {
        guard let url = WorkspaceBrowserAddress.resolve(address) else {
            viewModel?.lastError = "Invalid URL."
            return
        }

        viewModel?.addressText = url.absoluteString
        viewModel?.lastError = nil
        webView?.load(URLRequest(url: url))
    }

    func reload() {
        webView?.reload()
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        syncState(from: webView, isLoading: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncState(from: webView, isLoading: false)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        viewModel?.lastError = error.localizedDescription
        syncState(from: webView, isLoading: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        viewModel?.lastError = error.localizedDescription
        syncState(from: webView, isLoading: false)
    }

    private func syncState(from webView: WKWebView, isLoading: Bool? = nil) {
        guard let viewModel else { return }
        viewModel.currentURL = webView.url
        viewModel.addressText = webView.url?.absoluteString ?? viewModel.addressText
        viewModel.pageTitle = webView.title
        viewModel.canGoBack = webView.canGoBack
        viewModel.canGoForward = webView.canGoForward
        if let isLoading {
            viewModel.isLoading = isLoading
        } else {
            viewModel.isLoading = webView.isLoading
        }
    }
}
#elseif os(iOS) || os(visionOS)
import UIKit
import WebKit

@MainActor
struct WorkspaceWebView: UIViewRepresentable {
    let viewModel: WorkspaceWebViewModel?
    let artifactHTML: String?
    let artifactTitle: String

    init(viewModel: WorkspaceWebViewModel) {
        self.viewModel = viewModel
        artifactHTML = nil
        artifactTitle = "Web content"
    }

    init(html: String, title: String) {
        viewModel = nil
        artifactHTML = html
        artifactTitle = title
    }

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel) }

    func makeUIView(context: Context) -> WKWebView {
        if let webView = viewModel?.nativeWebView {
            context.coordinator.webView = webView
            context.coordinator.observeLoading(webView)
            webView.navigationDelegate = context.coordinator
            webView.uiDelegate = context.coordinator
            viewModel?.controller = context.coordinator
            viewModel?.retainedController = context.coordinator
#if os(iOS)
            webView.scrollView.refreshControl?.removeTarget(nil, action: nil, for: .valueChanged)
            webView.scrollView.refreshControl?.addTarget(context.coordinator, action: #selector(Coordinator.refreshPage), for: .valueChanged)
#endif
            return webView
        }
        let configuration = WKWebViewConfiguration()
        viewModel?.textSelection.install(in: configuration)
        if artifactHTML != nil {
            configuration.websiteDataStore = .nonPersistent()
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        viewModel?.textSelection.attach(to: webView)
        context.coordinator.webView = webView
        context.coordinator.observeLoading(webView)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
#if os(iOS)
        if viewModel != nil {
            let refreshControl = UIRefreshControl()
            refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.refreshPage), for: .valueChanged)
            webView.scrollView.refreshControl = refreshControl
            webView.scrollView.alwaysBounceVertical = true
        }
#endif
        viewModel?.controller = context.coordinator
        viewModel?.nativeWebView = webView
        viewModel?.retainedController = context.coordinator
        if let artifactHTML {
            context.coordinator.load(html: artifactHTML, in: webView)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if let artifactHTML, context.coordinator.loadedHTML != artifactHTML {
            context.coordinator.load(html: artifactHTML, in: webView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, WorkspaceWebViewControlling, WKNavigationDelegate, WKUIDelegate {
        weak var viewModel: WorkspaceWebViewModel?
        weak var webView: WKWebView?
        var loadedHTML: String?
        private var loadingObservations: [NSKeyValueObservation] = []

        init(viewModel: WorkspaceWebViewModel?) { self.viewModel = viewModel }

        func observeLoading(_ webView: WKWebView) {
            loadingObservations = [
                webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.syncLoading() }
                },
                webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.syncLoading() }
                },
                webView.observe(\.hasOnlySecureContent, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.syncLoading() }
                },
            ]
        }

        private func syncLoading() {
            guard let webView else { return }
            viewModel?.estimatedProgress = webView.estimatedProgress
            viewModel?.hasOnlySecureContent = webView.hasOnlySecureContent
            viewModel?.isLoading = webView.isLoading
        }

        func load(html: String, in webView: WKWebView) {
            loadedHTML = html
            webView.loadHTMLString("<meta name='viewport' content='width=device-width,initial-scale=1'><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; img-src data: blob:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; font-src data:\"><style>html,body{margin:0;color-scheme:light dark}</style>\(html)", baseURL: nil)
        }

        func open(_ address: String) {
            guard let url = WorkspaceBrowserAddress.resolve(address) else { return }
            viewModel?.lastError = nil
            webView?.load(URLRequest(url: url))
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil,
               let url = BrowserSearchEngine.websiteURL(navigationAction.request.url) {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if viewModel?.onDownload != nil, navigationAction.shouldPerformDownload,
               ["http", "https", "blob", "data"].contains(navigationAction.request.url?.scheme?.lowercased() ?? "") { return .download }
            if viewModel == nil || navigationAction.request.url?.absoluteString == "about:blank" { return .allow }
            return BrowserSearchEngine.websiteURL(navigationAction.request.url) != nil ? .allow : .cancel
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            viewModel?.onDownload != nil && !navigationResponse.canShowMIMEType ? .download : .allow
        }
        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            viewModel?.onDownload?(download)
        }
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            viewModel?.onDownload?(download)
        }

        func reload() { webView?.reload() }
        func goBack() { webView?.goBack() }
        func goForward() { webView?.goForward() }

#if os(iOS)
        @objc func refreshPage() {
            guard let webView, webView.reload() != nil else {
                webView?.scrollView.refreshControl?.endRefreshing()
                return
            }
        }
#endif

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            viewModel?.textSelection.dismiss()
            viewModel?.lastError = nil
            viewModel?.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finishNavigation(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard !WorkspaceBrowserNavigationFailure.isCancellation(error) else { syncLoading(); return }
            viewModel?.lastError = WorkspaceBrowserNavigationFailure.message(for: error)
            finishNavigation(webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard !WorkspaceBrowserNavigationFailure.isCancellation(error) else { syncLoading(); return }
            viewModel?.lastError = WorkspaceBrowserNavigationFailure.message(for: error)
            finishNavigation(webView)
        }

        private func finishNavigation(_ webView: WKWebView) {
            viewModel?.isLoading = false
            viewModel?.currentURL = webView.url
            viewModel?.addressText = webView.url?.absoluteString ?? ""
            viewModel?.canGoBack = webView.canGoBack
            viewModel?.canGoForward = webView.canGoForward
            viewModel?.pageTitle = webView.title
            if viewModel?.lastError == nil { viewModel?.history.record(url: webView.url, title: webView.title) }
#if os(iOS)
            webView.scrollView.refreshControl?.endRefreshing()
#endif
        }
    }
}
#else
@MainActor
struct WorkspaceWebView: View {
    init(viewModel: WorkspaceWebViewModel) {}
    init(html: String, title: String) {}

    var body: some View {
        Text("Web view is unavailable on this platform.")
    }
}
#endif
