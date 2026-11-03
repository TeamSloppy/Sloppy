#if os(macOS) || os(iOS)
import Foundation
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The page must be visible; background pages cannot grant themselves access.
@MainActor
final class BrowserSitePrompt {
    private var activeID: UUID?
    private var continuation: CheckedContinuation<BrowserSiteConsent, Never>?
#if os(macOS)
    private var alert: NSAlert?
#else
    private var alert: UIAlertController?
#endif
    var isPending: Bool { activeID != nil }

    func request(_ origin: BrowserSiteOrigin, resource: BrowserSiteResource, in webView: WKWebView) async -> BrowserSiteConsent {
        guard activeID == nil else { return .cancel }
        let id = UUID()
        activeID = id
        // First navigation may precede SwiftUI attaching its retained WebKit view.
        for _ in 0..<20 where webView.window == nil && activeID == id && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard activeID == id, !Task.isCancelled, webView.window != nil else {
            if activeID == id { activeID = nil }
            return .cancel
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                show(id: id, origin: origin, resource: resource, in: webView)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(id: id) }
        }
    }

    private func show(id: UUID, origin: BrowserSiteOrigin, resource: BrowserSiteResource, in webView: WKWebView) {
        let title = resource == .http ? "Visit without HTTPS?" : "Allow \(resource.title.lowercased()) access?"
        let message = resource == .http
            ? "\(origin.id)\n\nThis connection is not encrypted. Other people on the network may read or change information sent to this site."
            : "\(origin.id)\n\nThis site is requesting access to your \(resource.title.lowercased()). System privacy settings also apply."
        let onceTitle = resource == .http ? "Continue Once" : "Allow Once"
#if os(macOS)
        guard let window = webView.window, window.attachedSheet == nil else { finish(id: id, choice: .cancel); return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: onceTitle)
        alert.addButton(withTitle: "Always Allow This Site")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[2].keyEquivalent = "\u{1b}"
        self.alert = alert
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.finish(id: id, choice: response == .alertFirstButtonReturn ? .once : response == .alertSecondButtonReturn ? .always : .cancel)
        }
#else
        guard var presenter = webView.window?.rootViewController else { finish(id: id, choice: .cancel); return }
        while let presented = presenter.presentedViewController { presenter = presented }
        guard !(presenter is UIAlertController) else { finish(id: id, choice: .cancel); return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: onceTitle, style: .default) { [weak self] _ in self?.finish(id: id, choice: .once) })
        alert.addAction(UIAlertAction(title: "Always Allow This Site", style: .default) { [weak self] _ in self?.finish(id: id, choice: .always) })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.finish(id: id, choice: .cancel) })
        self.alert = alert
        presenter.present(alert, animated: true)
#endif
    }

    private func finish(id: UUID, choice: BrowserSiteConsent) {
        guard activeID == id else { return }
        let pending = continuation
        continuation = nil
        activeID = nil
        alert = nil
        pending?.resume(returning: choice)
    }
    func cancel() { if let activeID { cancel(id: activeID) } }
    private func cancel(id: UUID) {
        guard activeID == id else { return }
#if os(macOS)
        if let alert, let parent = alert.window.sheetParent { parent.endSheet(alert.window, returnCode: .alertThirdButtonReturn) }
#else
        alert?.dismiss(animated: false)
#endif
        finish(id: id, choice: .cancel)
    }
}
#endif
