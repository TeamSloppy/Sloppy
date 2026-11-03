#if os(macOS)
import AppKit
import Testing
import SloppyUITestSupport
import WebKit
@testable import SloppyClient

@Suite("Browser picture in picture", .serialized, .appKitIsolation)
@MainActor
struct BrowserPictureInPictureTests {
    @Test(arguments: [false, true])
    func enablesPictureInPictureForOwnedAndSuppliedPages(supplied: Bool) async throws {
        let view = supplied ? WKWebView(frame: .zero, configuration: WKWebViewConfiguration()) : nil
        let runtime = WorkspaceBrowserToolRuntime(webView: view)
        let preferences = runtime.webView.configuration.preferences
        try #require(preferences.responds(to: NSSelectorFromString("_allowsPictureInPictureMediaPlayback")))
        #expect(preferences.value(forKey: "_allowsPictureInPictureMediaPlayback") as? Bool == true)
        runtime.webView.loadHTMLString("<!doctype html><video controls></video>", baseURL: nil)
        _ = try await runtime.read()
        #expect(try await runtime.evaluate(expression: "document.pictureInPictureEnabled") == .bool(true))
        #expect(try await runtime.evaluate(expression: "typeof document.querySelector('video').webkitSetPresentationMode") == .string("function"))
    }
}
#endif
