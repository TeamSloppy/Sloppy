#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
import SloppyClientCore
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyClient
@testable import SloppyFeatureChat

@Suite("Pull Requests desktop layout", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct PullRequestsLayoutTests {
    @Test func reviewStaysInsideDetailWithSidebarAndToolDock() async throws {
        AppKitTestAccessibility.enable()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PullRequestsLayoutURLProtocol.self]
        let api = SloppyAPIClient(baseURL: try #require(URL(string: "https://pr-layout.invalid")),
            session: URLSession(configuration: configuration), authSessionStore: AuthSessionStore(persistence: .memory))
        let settings = ClientSettings()
        let monitor = ConnectionMonitor(baseURL: api.baseURL)
        let model = MainViewModel(endpoint: api.endpoint, settings: settings, connectionMonitor: monitor,
            cacheStore: ClientCacheStore(path: ":memory:"), apiClient: api,
            responseNotificationScheduler: PullRequestsLayoutNotifications(), onOpenSettings: { _ in }, onOpenWorkspace: {})
        model.selectPullRequests()
        let main = MainView(endpoint: api.endpoint, settings: settings, connectionMonitor: monitor,
            onOpenSettings: { _ in }, onOpenWorkspace: {}, viewModel: model)
        let host = NSHostingView(rootView: main.workspacePanelContainer
            .theme(.sloppyDark).desktopScreenStyle().preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 1840, height: 900),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer {
            model.chatViewModel.closeSession()
            window.contentView = nil
            window.close()
        }
        func element(_ identifier: String) async throws -> NSObject {
            for _ in 0..<100 {
                host.layoutSubtreeIfNeeded()
                if let element = AppKitTestAccessibility.element(in: host, identifier: identifier) { return element }
                try await Task.sleep(for: .milliseconds(30))
            }
            throw LayoutError.missingElement(identifier)
        }
        let row = try await element("code-review-open-github:team/repo#42")
        let wordmark = try await element("sidebar.wordmark")
        let rowFrame = try #require(AppKitTestAccessibility.frame(of: row))
        let wordmarkFrame = try #require(AppKitTestAccessibility.frame(of: wordmark))
        #expect(rowFrame.minX > wordmarkFrame.maxX)
        #expect(AppKitTestAccessibility.press(row))
        _ = try await element("code-review-diff")

        for (width, showsDock) in [(1840.0, false), (1120.0, false), (1840.0, true), (1120.0, true)] {
            window.setContentSize(NSSize(width: width, height: 900))
            if showsDock { model.workspaceDockState.open(.browser) } else { model.workspaceDockState.hide() }
            try await Task.sleep(for: .milliseconds(400))
            if let directory = ProcessInfo.processInfo.environment["SLOPPY_PR_SCREENSHOTS"] {
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: directory)
                        .appendingPathComponent("pr-\(Int(width))-dock-\(showsDock).png"))
                if CGPreflightScreenCaptureAccess() {
                    let capture = Process()
                    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    capture.arguments = ["-x", "-o", "-l", String(window.windowNumber),
                        directory + "/window-pr-\(Int(width))-dock-\(showsDock).png"]
                    try capture.run()
                    capture.waitUntilExit()
                }
            }
            let layout = try await element("code-review-diff-layout")
            let diff = try await element("code-review-diff")
            let send = try await element("code-review-send-review")
            var controls = [layout, send, diff]
            if width == 1120 {
                controls.append(try await element("code-review-files-menu"))
            }
            if width == 1120 || showsDock {
                _ = try await element("code-review-back")
            }
            let sidebar = try #require(AppKitTestAccessibility.frame(of: wordmark))
            let inspector = try await element("workspace.desktop-inspector")
            let inspectorFrame = try #require(AppKitTestAccessibility.frame(of: inspector))
            let bounds = host.convert(host.bounds, to: nil)
            let screenBounds = window.convertToScreen(bounds)
            for control in controls {
                let frame = try #require(AppKitTestAccessibility.frame(of: control))
                #expect(frame.minX >= sidebar.maxX)
                #expect(frame.maxX <= screenBounds.maxX + 1)
                #expect(frame.maxX <= inspectorFrame.minX + 1)
            }
        }
        let back = try await element("code-review-back")
        #expect(AppKitTestAccessibility.press(back))
        #expect(AppKitTestAccessibility.press(try await element("code-review-open-github:team/repo#42")))
        _ = try await element("code-review-diff")
    }

    private enum LayoutError: Error { case missingElement(String) }
}

@MainActor
private final class PullRequestsLayoutNotifications: AgentResponseNotificationScheduling {
    func prepareAuthorization() async {}
    func schedule(_ notification: AgentResponseCompletionNotification) async {}
}

private final class PullRequestsLayoutURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let item = #"{"id":"github:team/repo#42","providerId":"github","providerName":"GitHub","repository":"team/repo","number":42,"title":"Keep cancellation and review feedback scoped to the working task","url":"https://example.invalid/pr/42","state":"open","isDraft":false,"roles":[],"labels":[]}"#
        let json: String
        if request.url?.path == "/v1/code-reviews" {
            json = "{\"items\":[\(item)],\"providers\":[{\"id\":\"github\",\"displayName\":\"GitHub\",\"capabilities\":[]}],\"failures\":{}}"
        } else if request.url?.path.contains("/v1/code-reviews/") == true,
                  request.url?.path.hasSuffix("/sessions") != true {
            json = "{\"item\":\(item),\"reviewers\":[],\"comments\":[],\"diff\":\"diff --git a/Sources/Worker.swift b/Sources/Worker.swift\\n--- a/Sources/Worker.swift\\n+++ b/Sources/Worker.swift\\n@@ -1,3 +1,3 @@\\n func start() async {\\n-    await run()\\n+    let work = Task { await run() }\\n }\\n\",\"diffTruncated\":false}"
        } else { json = "[]" }
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
