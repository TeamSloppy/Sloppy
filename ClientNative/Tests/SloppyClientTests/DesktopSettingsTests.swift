#if os(macOS)
import AppKit
import SwiftUI
import Testing
import SloppyClientCore
import SloppyClientUI
import SloppyUITestSupport
@testable import SloppyFeatureSettings

@Suite("Desktop settings dialog", .serialized, .appKitUI, .appKitIsolation)
@MainActor
struct DesktopSettingsTests {
    @Test func editingSearchSelectionAndDismissalWorkInCompactDialog() async throws {
        AppKitTestAccessibility.enable()
        await DesktopSettingsRequests.shared.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DesktopSettingsURLProtocol.self]
        let api = SloppyAPIClient(baseURL: try #require(URL(string: "https://desktop-settings.invalid")),
            session: URLSession(configuration: configuration), authSessionStore: AuthSessionStore(persistence: .memory))
        var dismissed = 0
        let host = NSHostingView(rootView: SettingsScreen(initialDestination: .account,
            onDismiss: { dismissed += 1 }, apiClient: api)
            .theme(.sloppyDark).preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 980, height: 740),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        func descendants(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + descendants($0) } }
        func find(_ identifier: String) -> NSObject? {
            for view in [host] + descendants(host) {
                if let found = AppKitTestAccessibility.element(in: view, identifier: identifier) { return found }
            }
            return nil
        }
        func element(_ identifier: String) async throws -> NSObject {
            for _ in 0..<100 {
                host.layoutSubtreeIfNeeded()
                if let found = find(identifier) { return found }
                try await Task.sleep(for: .milliseconds(30))
            }
            try? capture("dialog-diagnostic")
            throw DialogError.missing(identifier)
        }
        func capture(_ name: String) throws {
            guard let directory = ProcessInfo.processInfo.environment["SLOPPY_SETTINGS_SCREENSHOTS"] else { return }
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
        }
        _ = try await element("settings.account.save-profile")
        var nameField: NSTextField?
        for _ in 0..<100 {
            nameField = descendants(host).compactMap { $0 as? NSTextField }.first { $0.isEditable && $0.stringValue == "Test Profile" }
            if nameField != nil { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        let name = try #require(nameField)
        #expect(descendants(host).compactMap { $0 as? NSSecureTextField }.count == 3)
        #expect(window.makeFirstResponder(name))
        let editor = try #require(name.currentEditor() as? NSTextView)
        editor.string = "Updated Profile"
        editor.didChangeText()
        try await Task.sleep(for: .milliseconds(100))
        #expect(window.firstResponder === editor)
        window.makeFirstResponder(nil)
        #expect(await DesktopSettingsRequests.shared.names.isEmpty)
        let save = try await element("settings.account.save-profile")
        #expect(AppKitTestAccessibility.press(save))
        for _ in 0..<100 {
            if await DesktopSettingsRequests.shared.names == ["Updated Profile"] { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(await DesktopSettingsRequests.shared.names == ["Updated Profile"])
        for width in [980.0, 860.0] {
            window.setContentSize(NSSize(width: width, height: 740))
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
            let bounds = name.convert(name.bounds, to: host)
            #expect(bounds.minX >= 216)
            #expect(bounds.maxX <= host.bounds.maxX - 16)
            try capture("account-\(Int(width))")
        }
        #expect(find("settings.section.mcp") == nil)
        let search = try #require(descendants(host).compactMap { $0 as? NSTextField }.first {
            $0.placeholderString?.contains("Search settings") == true
        })
        window.makeFirstResponder(search)
        let searchEditor = try #require(search.currentEditor() as? NSTextView)
        searchEditor.string = "MCP"
        searchEditor.didChangeText()
        _ = try await element("settings.section.mcp")
        try capture("settings-search")
        searchEditor.string = ""
        searchEditor.didChangeText()
        window.makeFirstResponder(nil)
        #expect(AppKitTestAccessibility.press(try await element("settings.section.client")))
        try await Task.sleep(for: .milliseconds(200))
        try capture("general-860")
        #expect(AppKitTestAccessibility.press(try await element("settings.close")))
        #expect(dismissed == 1)
    }

    private enum DialogError: Error { case missing(String) }
}

private actor DesktopSettingsRequests {
    static let shared = DesktopSettingsRequests()
    var names: [String] = []
    func reset() { names = [] }
    func record(_ name: String) { names.append(name) }
}

private final class DesktopSettingsURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task {
            var name = "Test Profile"
            if request.httpMethod == "PATCH" {
                var data = request.httpBody ?? Data()
                if let stream = request.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 1024)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        guard count > 0 else { break }
                        data.append(contentsOf: buffer.prefix(count))
                    }
                }
                name = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["name"] as? String ?? "Missing name"
                await DesktopSettingsRequests.shared.record(name)
            }
            let json: Data
            if request.url?.path == "/v1/auth/me" {
                json = (try? JSONSerialization.data(withJSONObject: ["id": "fixture", "login": "testuser", "name": name,
                    "role": "admin", "status": "active"])) ?? Data()
            } else {
                json = Data("[]".utf8)
            }
            if let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"]) {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: json)
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }
    override func stopLoading() {}
}
#endif
