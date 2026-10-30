import Foundation
import SloppyFeatureChat
import WebKit

typealias BrowserTextAnnotationReceiver = @MainActor (ChatComposerQuote) -> Bool
typealias BrowserTextAnnotationTarget = @MainActor () -> BrowserTextAnnotationReceiver?

@MainActor
final class WorkspaceBrowserSelection: NSObject, WKScriptMessageHandler {
    static let world = WKContentWorld.world(name: "SloppyBrowserTextSelection")
    static var script: String {
#if SWIFT_PACKAGE
        let bundle = Bundle.module
#else
        let bundle = Bundle.main
#endif
        guard let url = bundle.url(forResource: "BrowserSelection", withExtension: "js") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
    var onAsk: (@MainActor (String) -> Void)?
    var annotationTarget: BrowserTextAnnotationTarget?
    private weak var webView: WKWebView?
    private var pending: (id: Int, quote: ChatComposerQuote, receive: BrowserTextAnnotationReceiver?)?

    func install(in configuration: WKWebViewConfiguration) {
        configuration.userContentController.add(self, contentWorld: Self.world, name: "sloppyBrowserSelection")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.script,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Self.world))
    }

    func attach(to webView: WKWebView) { self.webView = webView }

    func dismiss() {
        pending = nil
        Task { [weak webView] in
            _ = try? await webView?.evaluateJavaScript("globalThis.__sloppyBrowserSelection?.hide()", in: nil, contentWorld: Self.world)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView, message.webView === webView, message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any], let action = body["action"] as? String,
              let requestID = body["requestID"] as? Int else { return }
        if action == "open" {
            guard let text = body["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.utf16.count <= 12000, let pageURL = body["pageURL"] as? String,
                  pageURL == webView.url?.absoluteString,
                  let url = BrowserSearchEngine.websiteURL(webView.url) else { return }
            let quote = ChatComposerQuote(text: text, browserSource: .init(url: url,
                title: String((body["title"] as? String ?? "Page").prefix(200))))
            pending = (requestID, quote, annotationTarget?())
            reply(requestID, available: pending?.receive != nil)
            return
        }
        guard let pending, pending.id == requestID,
              pending.quote.browserSource?.url == BrowserSearchEngine.websiteURL(webView.url) else { return }
        if action == "annotate" {
            var quote = pending.quote
            quote.comment = String((body["prompt"] as? String ?? "").prefix(4000)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard pending.receive?(quote) == true else {
                reply(requestID, available: false, error: "That chat is no longer available. Open the selection menu again.")
                return
            }
            dismiss()
        } else if action == "ask", let command = body["command"] as? String {
            let prompt: String
            switch command {
            case "fact-check": prompt = "Fact check this selection."
            case "define": prompt = "Explain this selection."
            case "summarize": prompt = "Summarize this selection."
            case "translate": prompt = "Translate this selection into my language."
            case "custom": prompt = String((body["prompt"] as? String ?? "").prefix(4000)).trimmingCharacters(in: .whitespacesAndNewlines)
            default: return
            }
            guard !prompt.isEmpty, let onAsk else {
                reply(requestID, available: pending.receive != nil, error: "Open a chat to ask about this selection.")
                return
            }
            let source = pending.quote.browserSource
            dismiss()
            onAsk("\(prompt)\n\nSelected text:\n\(pending.quote.text)\n\nPage URL: \(source?.url.absoluteString ?? "")\nPage title: \(source?.title ?? "")")
        }
    }

    private func reply(_ id: Int, available: Bool, error: String = "") {
        Task { [weak webView] in
            _ = try? await webView?.callAsyncJavaScript("globalThis.__sloppyBrowserSelection?.reply(id, available, error)",
                arguments: ["id": id, "available": available, "error": error], in: nil, contentWorld: Self.world)
        }
    }
}
