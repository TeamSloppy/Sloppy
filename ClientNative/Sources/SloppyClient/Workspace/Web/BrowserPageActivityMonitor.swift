#if os(macOS) || os(iOS)
import Foundation
import WebKit

/// Only booleans and frame identities cross the bridge; form contents stay in WebKit.
@MainActor
final class BrowserPageActivityMonitor: NSObject, WKScriptMessageHandler {
    enum Failure { case unavailable, capture, timeout, media, loading, edits, rtc, invalidFrames, cancelled }
    static let world = WKContentWorld.world(name: "SloppyPageRetention")
    private struct Frame {
        let parent: String?
        let children: Int
    }
    private struct Probe {
        let completion: CheckedContinuation<Bool, Never>
        var frames: [String: Frame] = [:]
        var root: String?
        var mediaStopped = false
        var timeout: Task<Void, Never>?
        var evaluation: Task<Void, Never>?
    }
    private weak var webView: WKWebView?
    private var probes: [String: Probe] = [:]
    private(set) var revision = 0
    private(set) var lastFailure: Failure?

    func install(in configuration: WKWebViewConfiguration) {
        configuration.userContentController.add(self, contentWorld: Self.world, name: "sloppyPageRetention")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.script("BrowserPageRetention"),
            injectionTime: .atDocumentStart, forMainFrameOnly: false, in: Self.world))
        configuration.userContentController.addUserScript(WKUserScript(source: Self.script("BrowserPageRTCActivity"),
            injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
    }

    func attach(to webView: WKWebView) { self.webView = webView }

    func inspect() async -> Bool {
        lastFailure = nil
        guard let webView, webView.cameraCaptureState == .none, webView.microphoneCaptureState == .none else { lastFailure = .capture; return false }
        let id = UUID().uuidString
        return await withTaskCancellationHandler {
            await withCheckedContinuation { completion in
                probes[id] = Probe(completion: completion)
                probes[id]?.timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    self?.finish(id, safe: false, failure: .timeout)
                }
                webView.requestMediaPlaybackState { [weak self] state in
                    guard let self, probes[id] != nil else { return }
                    guard state != .playing else { finish(id, safe: false, failure: .media); return }
                    probes[id]?.mediaStopped = true
                    completeIfReady(id)
                }
                probes[id]?.evaluation = Task { [weak self, weak webView] in
                    guard let webView else { self?.finish(id, safe: false); return }
                    do { _ = try await webView.evaluateJavaScript("globalThis.__sloppyPageRetention.probe('\(id)')", in: nil, contentWorld: Self.world) }
                    catch { self?.finish(id, safe: false, failure: .unavailable) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, safe: false, failure: .cancelled) }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === webView, let body = message.body as? [String: Any] else { return }
        if body["event"] as? String == "changed" { revision &+= 1; return }
        guard body["event"] as? String == "probe", let id = body["id"] as? String, probes[id] != nil,
              let doc = body["doc"] as? String, doc.count <= 100,
              let children = body["children"] as? Int, (0...1024).contains(children),
              let ready = body["ready"] as? Bool, let dirty = body["dirty"] as? Bool,
              let playing = body["playing"] as? Bool, let rtc = body["rtc"] as? Int else { return }
        guard ready else { finish(id, safe: false, failure: .loading); return }
        guard !dirty else { finish(id, safe: false, failure: .edits); return }
        guard !playing else { finish(id, safe: false, failure: .media); return }
        guard rtc == 0 else { finish(id, safe: false, failure: rtc < 0 ? .unavailable : .rtc); return }
        let parent = body["parent"] as? String
        guard message.frameInfo.isMainFrame == (parent == nil), (probes[id]?.frames.count ?? 0) < 2048 else {
            finish(id, safe: false, failure: .invalidFrames); return
        }
        probes[id]?.frames[doc] = Frame(parent: parent, children: children)
        if message.frameInfo.isMainFrame { probes[id]?.root = doc }
        completeIfReady(id)
    }

    private func completeIfReady(_ id: String) {
        guard let probe = probes[id], probe.mediaStopped, let root = probe.root else { return }
        var visited = Set<String>()
        func complete(_ doc: String) -> Bool {
            guard visited.insert(doc).inserted, let frame = probe.frames[doc] else { return false }
            let children = probe.frames.filter { $0.value.parent == doc }.map(\.key)
            return children.count == frame.children && children.allSatisfy(complete)
        }
        if complete(root), visited.count == probe.frames.count { finish(id, safe: true) }
    }

    private func finish(_ id: String, safe: Bool, failure: Failure? = nil) {
        guard let probe = probes.removeValue(forKey: id) else { return }
        lastFailure = failure
        probe.timeout?.cancel()
        probe.evaluation?.cancel()
        probe.completion.resume(returning: safe)
    }

    func detach() {
        for id in Array(probes.keys) { finish(id, safe: false) }
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "sloppyPageRetention", contentWorld: Self.world)
        webView = nil
    }

    private static func script(_ name: String) -> String {
#if SWIFT_PACKAGE
        let bundle = Bundle.module
#else
        let bundle = Bundle.main
#endif
        guard let url = bundle.url(forResource: name, withExtension: "js") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
#endif
