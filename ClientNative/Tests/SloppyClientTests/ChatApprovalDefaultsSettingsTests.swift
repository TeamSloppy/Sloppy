#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyUITestSupport
import SloppyClientCore
import SloppyClientUI
@testable import SloppyFeatureSettings

@Suite("Chat approval defaults settings", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct ChatApprovalDefaultsSettingsTests {
    @Test func settingsShowTheSavedServerDefault() async throws {
        _ = NSApplication.shared
        AppKitTestAccessibility.enable()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DefaultsSettingsURLProtocol.self]
        let api = SloppyAPIClient(baseURL: URL(string: "https://defaults-ui.invalid")!,
            session: URLSession(configuration: configuration), authSessionStore: AuthSessionStore(persistence: .memory))
        let host = NSHostingView(rootView: ChatApprovalDefaultsSection(apiClient: api)
            .environment(\.theme, .sloppyDark).preferredColorScheme(.dark)
            .padding(24).frame(width: 680, height: 360, alignment: .topLeading).background(Color(white: 0.098)))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 360),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        for _ in 0..<20 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        let picker = try #require(AppKitTestAccessibility.element(in: host, identifier: "settings.default-chat-approval-mode"))
        let valueSelector = NSSelectorFromString("accessibilityValue")
        #expect(picker.responds(to: valueSelector))
        let value = picker.responds(to: valueSelector) ? picker.perform(valueSelector)?.takeUnretainedValue() as? String : nil
        #expect(value == "Approve for me")
        #expect(AppKitTestAccessibility.element(in: host, identifier: "settings.default-chat-approval-save") != nil)
        if let output = ProcessInfo.processInfo.environment["SLOPPY_APPROVAL_DEFAULTS_PROOF"] {
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: output))
        }
    }
}

private final class DefaultsSettingsURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "defaults-ui.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"mode":"approve_for_me"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
