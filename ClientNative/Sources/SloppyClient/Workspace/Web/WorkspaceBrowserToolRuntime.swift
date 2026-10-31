import Foundation
import SloppyClientCore

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
#if os(macOS) || os(iOS)
import WebKit
#endif

struct WorkspaceBrowserActionResult: Sendable {
    var ok: Bool
    var message: String
}

struct WorkspaceBrowserScreenshotResult: Sendable {
    var imageData: Data
}

typealias WorkspaceBrowserReadResult = WorkspaceBrowserPage

@MainActor
final class WorkspaceBrowserToolRuntime: NSObject {
    let pageID = UUID().uuidString
#if os(macOS) || os(iOS)
    // The runtime owns the page so hiding the panel never destroys an agent's page.
    let webView: WKWebView
#if os(macOS)
    private(set) lazy var documentInset = BrowserDocumentInset(webView: webView)
#endif
    var onStateChange: (@MainActor (WKWebView, String?) -> Void)?
    var onNavigationFinished: (@MainActor (WKWebView) -> Void)?
    var onDownload: (@MainActor (WKDownload) -> Void)?
    var onNavigationStarted: (@MainActor () -> Void)?
    private var navigationError: Error?
    private var navigationPending = false
    private var titleObservation: NSKeyValueObservation?
    private var loadingObservations: [NSKeyValueObservation] = []

    init(webView: WKWebView? = nil, extensionController: WKWebExtensionController? = nil,
         textSelection: WorkspaceBrowserSelection? = nil) {
        let configuration = WKWebViewConfiguration()
#if os(macOS)
        configuration.webExtensionController = extensionController
#endif
        if webView == nil { textSelection?.install(in: configuration) }
#if os(macOS)
        self.webView = webView ?? WorkspaceBrowserWebView(frame: CGRect(x: 0, y: 0, width: 1000, height: 750), configuration: configuration)
#else
        self.webView = webView ?? WKWebView(frame: .zero, configuration: configuration)
        self.webView.allowsBackForwardNavigationGestures = true
#endif
        super.init()
        textSelection?.attach(to: self.webView)
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self
        titleObservation = self.webView.observe(\.title, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onStateChange?(self.webView, WorkspaceBrowserNavigationFailure.message(for: self.navigationError))
            }
        }
        loadingObservations = [
            self.webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.publishLoadingState() }
            },
            self.webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.publishLoadingState() }
            },
            self.webView.observe(\.hasOnlySecureContent, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.publishLoadingState() }
            },
        ]
#if os(iOS)
        loadingObservations.append(self.webView.observe(\.underPageBackgroundColor, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.publishLoadingState() }
        })
#endif
    }

    private func publishLoadingState() {
        onStateChange?(webView, WorkspaceBrowserNavigationFailure.message(for: navigationError))
    }

    func open(url: String) async throws -> WorkspaceBrowserReadResult {
        let resolvedURL = try Self.resolveURL(url)
        navigationError = nil
        navigationPending = true
        guard webView.load(URLRequest(url: resolvedURL)) != nil else {
            navigationPending = false
            throw WorkspaceBrowserRuntimeError.unavailable
        }
        try await waitForNavigation()
        return try await read()
    }

    static func resolveURL(_ address: String) throws -> URL {
        guard let url = WorkspaceBrowserAddress.resolve(address) else {
            throw WorkspaceBrowserRuntimeError.invalidURL
        }
        return url
    }

    func read() async throws -> WorkspaceBrowserReadResult {
        try await waitForNavigation()
        let raw = try await webView.evaluateJavaScript(Self.readScript)
        guard let raw else { throw WorkspaceBrowserRuntimeError.unavailable }
        let data = try JSONSerialization.data(withJSONObject: raw)
        struct Snapshot: Decodable {
            var url: String
            var title: String
            var visibleText: String
            var elements: [WorkspaceBrowserElement]
        }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        return .init(pageId: pageID, url: snapshot.url, title: snapshot.title,
                     visibleText: snapshot.visibleText, elements: snapshot.elements)
    }

    func click(selector: String) async throws -> WorkspaceBrowserActionResult {
        try await perform(Self.elementScript(selector: selector, action: "node.click();"))
        return .init(ok: true, message: "Clicked \(selector)")
    }

    func type(selector: String, text: String) async throws -> WorkspaceBrowserActionResult {
        let value = try Self.jsString(text)
        try await perform(Self.elementScript(selector: selector, action: """
        if (node.readOnly) throw new Error('element_read_only');
        node.focus();
        if (node instanceof HTMLInputElement || node instanceof HTMLTextAreaElement) {
          if (node.type === 'file') throw new Error('file_input_unsupported');
          const prototype = node instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
          Object.getOwnPropertyDescriptor(prototype, 'value').set.call(node, \(value));
        } else if (node.isContentEditable) {
          node.textContent = \(value);
        } else { throw new Error('element_not_editable'); }
        node.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: \(value) }));
        node.dispatchEvent(new Event('change', { bubbles: true }));
        """))
        return .init(ok: true, message: "Typed into \(selector)")
    }

    func scroll(x: Double, y: Double) async throws -> WorkspaceBrowserActionResult {
        guard x.isFinite, y.isFinite else { throw WorkspaceBrowserRuntimeError.invalidArguments }
        try await perform("window.scrollTo(\(x), \(y)); true;")
        return .init(ok: true, message: "Scrolled to \(x),\(y)")
    }

    func scrollTo(selector: String) async throws -> WorkspaceBrowserActionResult {
        try await perform(Self.elementScript(selector: selector, action: ""))
        return .init(ok: true, message: "Scrolled to \(selector)")
    }

    func screenshot() async throws -> WorkspaceBrowserScreenshotResult {
        try await waitForNavigation()
        let image = try await webView.takeSnapshot(configuration: nil)
#if os(macOS)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw WorkspaceBrowserRuntimeError.snapshotFailed
        }
#else
        guard let png = image.pngData() else { throw WorkspaceBrowserRuntimeError.snapshotFailed }
#endif
        return .init(imageData: png)
    }

    func stop() {
        webView.stopLoading()
        navigationPending = false
    }

    private func perform(_ script: String) async throws {
        try await waitForNavigation()
        _ = try await webView.evaluateJavaScript(script)
        // Let click-triggered navigations and framework updates enter the run loop.
        try await Task.sleep(for: .milliseconds(150))
        try await waitForNavigation()
    }

    private func waitForNavigation() async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while navigationPending || webView.isLoading {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else {
                stop()
                throw WorkspaceBrowserRuntimeError.navigationTimedOut
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        if let navigationError { throw navigationError }
        try Task.checkCancellation()
    }

    private static func jsString(_ value: String) throws -> String {
        // JSON quoting preserves newlines, quotes and backslashes without executing input.
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private static func elementScript(selector: String, action: String) throws -> String {
        """
        (() => {
          const nodes = document.querySelectorAll(\(try jsString(selector)));
          if (!nodes.length) throw new Error('selector_not_found');
          if (nodes.length !== 1) throw new Error('selector_ambiguous');
          const node = nodes[0];
          if (node.matches(':disabled') || node.getAttribute('aria-disabled') === 'true') throw new Error('element_disabled');
          if (!node.getClientRects().length || getComputedStyle(node).visibility === 'hidden') throw new Error('element_hidden');
          node.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
          \(action)
          return true;
        })();
        """
    }

    // Returned selectors are grounded in the current DOM. Call read again after page changes.
    static let readScript = """
    (() => {
      const selector = node => {
        if (node.id && document.querySelectorAll('#' + CSS.escape(node.id)).length === 1) return '#' + CSS.escape(node.id);
        const parts = [];
        for (let current = node; current && current.nodeType === 1; current = current.parentElement) {
          const tag = current.tagName.toLowerCase();
          const siblings = current.parentElement ? [...current.parentElement.children].filter(n => n.tagName === current.tagName) : [current];
          parts.unshift(tag + ':nth-of-type(' + (siblings.indexOf(current) + 1) + ')');
        }
        return parts.join(' > ');
      };
      const elements = [...document.querySelectorAll('a,button,input,textarea,select,[role="button"],[role="link"],[contenteditable="true"]')]
        .filter(node => node.getClientRects().length && getComputedStyle(node).visibility !== 'hidden')
        .slice(0, 150).map(node => ({
          selector: selector(node),
          role: node.getAttribute('role') || node.tagName.toLowerCase(),
          name: (node.getAttribute('aria-label') || node.labels?.[0]?.innerText || node.innerText || node.getAttribute('placeholder') || node.getAttribute('name') || '').trim().slice(0, 200),
          disabled: node.matches(':disabled') || node.getAttribute('aria-disabled') === 'true'
        }));
      return { url: location.href, title: document.title || '', visibleText: (document.body?.innerText || '').trim().slice(0, 12000), elements };
    })();
    """
#else
    init(webView: AnyObject? = nil) { super.init() }
    func open(url: String) async throws -> WorkspaceBrowserReadResult { throw WorkspaceBrowserRuntimeError.unavailable }
    func read() async throws -> WorkspaceBrowserReadResult { throw WorkspaceBrowserRuntimeError.unavailable }
    func click(selector: String) async throws -> WorkspaceBrowserActionResult { throw WorkspaceBrowserRuntimeError.unavailable }
    func type(selector: String, text: String) async throws -> WorkspaceBrowserActionResult { throw WorkspaceBrowserRuntimeError.unavailable }
    func scroll(x: Double, y: Double) async throws -> WorkspaceBrowserActionResult { throw WorkspaceBrowserRuntimeError.unavailable }
    func scrollTo(selector: String) async throws -> WorkspaceBrowserActionResult { throw WorkspaceBrowserRuntimeError.unavailable }
    func screenshot() async throws -> WorkspaceBrowserScreenshotResult { throw WorkspaceBrowserRuntimeError.unavailable }
    func stop() {}
#endif
}

#if os(macOS) || os(iOS)
extension WorkspaceBrowserToolRuntime: WKNavigationDelegate, WKUIDelegate, WorkspaceWebViewControlling {
    func open(_ address: String) {
        Task {
            do { _ = try await open(url: address) }
            catch { onStateChange?(webView, WorkspaceBrowserNavigationFailure.message(for: error)) }
        }
    }
    func reload() { navigationError = nil; webView.reload() }
    func goBack() { navigationError = nil; webView.goBack() }
    func goForward() { navigationError = nil; webView.goForward() }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        onNavigationStarted?()
        navigationError = nil
        navigationPending = true
        onStateChange?(webView, nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
#if os(macOS)
        documentInset.refresh()
#else
        webView.scrollView.refreshControl?.endRefreshing()
#endif
        navigationPending = false
        onStateChange?(webView, nil)
        onNavigationFinished?(webView)
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
#if os(macOS)
        documentInset.refresh()
#endif
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if WorkspaceBrowserNavigationFailure.isCancellation(error) {
            navigationPending = webView.isLoading
            publishLoadingState()
            return
        }
        navigationPending = false
        navigationError = error
#if os(iOS)
        webView.scrollView.refreshControl?.endRefreshing()
#endif
        onStateChange?(webView, WorkspaceBrowserNavigationFailure.message(for: error))
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if onDownload != nil, navigationAction.shouldPerformDownload,
           ["http", "https", "blob", "data"].contains(navigationAction.request.url?.scheme?.lowercased() ?? "") {
            return .download
        }
        guard let url = navigationAction.request.url,
              (try? Self.resolveURL(url.absoluteString)) != nil else {
            navigationPending = false
            navigationError = WorkspaceBrowserRuntimeError.invalidURL
            onStateChange?(webView, WorkspaceBrowserNavigationFailure.message(for: navigationError))
            return .cancel
        }
        return .allow
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        onDownload != nil && !navigationResponse.canShowMIMEType ? .download : .allow
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        receive(download)
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        receive(download)
    }
    private func receive(_ download: WKDownload) {
        navigationPending = false
        onStateChange?(webView, nil)
        onDownload?(download)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil,
           let url = navigationAction.request.url,
           (try? Self.resolveURL(url.absoluteString)) != nil {
            navigationPending = true
            webView.load(navigationAction.request)
        }
        return nil
    }
}
#endif

enum WorkspaceBrowserRuntimeError: Error, LocalizedError {
    case unavailable, invalidURL, invalidArguments, snapshotFailed, navigationTimedOut
    var errorDescription: String? {
        switch self {
        case .unavailable: "The in-app browser is unavailable."
        case .invalidURL: "Use an HTTP or HTTPS URL."
        case .invalidArguments: "Invalid browser command arguments."
        case .snapshotFailed: "Could not capture the browser page."
        case .navigationTimedOut: "The browser page did not finish loading within 20 seconds."
        }
    }
}
