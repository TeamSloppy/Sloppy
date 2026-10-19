#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyClientCore
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient
@testable import SloppyFeatureSettings

@Suite("Usage in Settings", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct UsageSettingsTests {
    @Test func usageLoadsInSettingsAndKeepsPeriodAndChatActions() async throws {
        AppKitTestAccessibility.enable()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UsageSettingsURLProtocol.self]
        let api = SloppyAPIClient(baseURL: try #require(URL(string: "https://usage-settings.invalid")),
            session: URLSession(configuration: configuration), authSessionStore: AuthSessionStore(persistence: .memory))
        var opened: ChatSessionSummary?
        let host = NSHostingView(rootView: SettingsScreen(initialDestination: .usage,
            onOpenUsageSession: { opened = $0 }, apiClient: api)
            .theme(.sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1200, height: 900),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        func element(_ identifier: String) async throws -> NSObject {
            for _ in 0..<100 {
                host.layoutSubtreeIfNeeded()
                if let found = AppKitTestAccessibility.element(in: host, identifier: identifier) { return found }
                for view in descendants(host) {
                    if let found = AppKitTestAccessibility.element(in: view, identifier: identifier) { return found }
                }
                try await Task.sleep(for: .milliseconds(30))
            }
            if let directory = ProcessInfo.processInfo.environment["SLOPPY_USAGE_SCREENSHOTS"],
               let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("usage-diagnostic.png"))
            }
            throw UsageSettingsError.missingElement(identifier)
        }
        _ = try await element("usage.period")
        let chat = try await element("usage.open-session.review")
        #expect(AppKitTestAccessibility.press(chat))
        #expect(opened?.id == "review")
        #expect(opened?.agentId == "worker")
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        let period = try #require(descendants(host).compactMap { $0 as? NSSegmentedControl }.first {
            $0.segmentCount == 4 && $0.label(forSegment: 3) == "Custom"
        })
        period.selectedSegment = 3
        #expect(period.sendAction(period.action, to: period.target))
        try await Task.sleep(for: .milliseconds(250))
        #expect(descendants(host).compactMap { $0 as? NSDatePicker }.count == 2)
        period.selectedSegment = 1
        #expect(period.sendAction(period.action, to: period.target))
        let refresh = try await element("usage.refresh")
        try await Task.sleep(for: .milliseconds(250))
        #expect(AppKitTestAccessibility.press(refresh))
        _ = try await element("usage.open-session.review")
        if let directory = ProcessInfo.processInfo.environment["SLOPPY_USAGE_SCREENSHOTS"] {
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("settings-usage.png"))
            if CGPreflightScreenCaptureAccess() {
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), directory + "/window-settings-usage.png"]
                try capture.run(); capture.waitUntilExit()
            }
        }
    }

    private enum UsageSettingsError: Error { case missingElement(String) }
}

private final class UsageSettingsURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let json: String
        switch request.url?.path {
        case "/v1/token-usage":
            json = #"{"items":[{"id":"one","channelId":"agent:worker:session:review","promptTokens":12000,"completionTokens":1300,"totalTokens":13300,"cachedInputTokens":9000,"reasoningTokens":400,"createdAt":"2026-10-19T00:00:00Z"}]}"#
        case "/v1/agents":
            json = #"[{"id":"worker","displayName":"Worker","role":"Engineer"}]"#
        case "/v1/agents/worker/sessions":
            json = #"[{"id":"review","agentId":"worker","title":"Review workspace changes","messageCount":4,"updatedAt":"2026-10-19T00:00:00Z","kind":"chat"}]"#
        case "/v1/usage/breakdown":
            json = #"{"requestCount":7,"reportedRequestCount":6,"completeRequestCount":5,"providerUsage":{"prompt":12000,"completion":1300,"cachedInput":9000,"cacheCreationInput":0,"reasoning":400},"groups":[{"id":"files.read","calls":2,"failures":0,"argumentsTokens":120,"resultTokens":1200,"replayTokens":2400,"schemaTokens":1800,"catalogTokens":0,"tokenizerMeasurements":5,"estimatedMeasurements":0,"unavailableMeasurements":0}],"calls":[]}"#
        default:
            json = #"{"error":"Unexpected request in Usage settings"}"#
        }
        if let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"]) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
#endif
