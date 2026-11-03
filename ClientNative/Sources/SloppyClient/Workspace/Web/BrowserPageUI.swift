#if os(macOS)
import AppKit
import WebKit

/// Owns one page-controlled sheet and completes its WebKit callback exactly once.
@MainActor
final class BrowserPageUI {
    var makeOpenPanel: () -> NSOpenPanel = { NSOpenPanel() }
    private var activeID: UUID?
    private var cancelPending: (() -> Void)?
    private var closeObserver: NSObjectProtocol?
    private(set) var sheet: NSWindow?

    func dialog(message: String, origin: String, prompt: String? = nil, allowsCancel: Bool,
                in webView: WKWebView, completion: @escaping (Bool, String?) -> Void) {
        guard let window = webView.window, activeID == nil, window.attachedSheet == nil else {
            completion(false, nil)
            return
        }
        let alert = NSAlert()
        alert.messageText = origin
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if allowsCancel { alert.addButton(withTitle: "Cancel") }
        let field = prompt.map { NSTextField(string: $0) }
        if let field {
            field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
            field.setAccessibilityLabel(message)
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
        }
        let id = begin(sheet: alert.window, parent: window) { completion(false, nil) }
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.finish(id) {
                let accepted = response == .alertFirstButtonReturn
                completion(accepted, accepted ? field?.stringValue : nil)
            }
        }
    }

    func upload(parameters: WKOpenPanelParameters, origin: String, in webView: WKWebView,
                completion: @escaping ([URL]?) -> Void) {
        guard let window = webView.window, activeID == nil, window.attachedSheet == nil else {
            completion(nil)
            return
        }
        let panel = makeOpenPanel()
        panel.message = "Choose files for \(origin)"
        panel.canChooseFiles = !parameters.allowsDirectories
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canCreateDirectories = false
        let id = begin(sheet: panel, parent: window) { completion(nil) }
        panel.beginSheetModal(for: window) { [weak self] response in
            self?.finish(id) { completion(response == .OK ? panel.urls : nil) }
        }
    }

    private func begin(sheet: NSWindow, parent: NSWindow, cancel: @escaping () -> Void) -> UUID {
        let id = UUID()
        activeID = id
        self.sheet = sheet
        cancelPending = { [weak self] in self?.finish(id, action: cancel) }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                               object: parent, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
        return id
    }

    private func finish(_ id: UUID, action: () -> Void) {
        guard activeID == id else { return }
        activeID = nil
        sheet = nil
        cancelPending = nil
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        action()
    }

    func cancel() {
        let pending = cancelPending
        if let sheet, let parent = sheet.sheetParent { parent.endSheet(sheet, returnCode: .cancel) }
        pending?()
    }
}

extension WorkspaceBrowserToolRuntime {
    private func dialogOrigin(_ frame: WKFrameInfo) -> String {
        BrowserSiteOrigin(frame.securityOrigin)?.id ?? "Web page"
    }

    @objc func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
        pageUI.dialog(message: message, origin: dialogOrigin(frame), allowsCancel: false, in: webView) { _, _ in completionHandler() }
    }

    @objc func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        pageUI.dialog(message: message, origin: dialogOrigin(frame), allowsCancel: true, in: webView) { accepted, _ in completionHandler(accepted) }
    }

    @objc func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
        pageUI.dialog(message: prompt, origin: dialogOrigin(frame), prompt: defaultText ?? "", allowsCancel: true, in: webView) { _, text in completionHandler(text) }
    }

    @objc func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        pageUI.upload(parameters: parameters, origin: dialogOrigin(frame), in: webView, completion: completionHandler)
    }
}
#endif
