import Foundation
import Testing

@Suite("SloppyClientApp wiring")
struct SloppyClientAppWiringTests {
    private var appSource: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let appURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyClient")
                .appendingPathComponent("SloppyClientApp.swift")
            return try String(contentsOf: appURL, encoding: .utf8)
        }
    }

    @Test("app entry uses SwiftUI WindowGroup")
    func appEntryUsesSwiftUIWindowGroup() throws {
        let source = try appSource

        #expect(source.contains("@main"))
        #expect(source.contains("struct SloppyClientApp: App"))
        #expect(source.contains("WindowGroup"))
        #expect(source.contains("RootShellView()"))
    }
}
