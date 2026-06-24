import Foundation
import Testing

@Suite("Settings view layout")
struct SettingsViewLayoutTests {
    private var settingsViewSource: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppySafariCore")
                .appendingPathComponent("SettingsView.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    @Test("iPhone layout keeps action buttons inline with scroll content")
    func iphoneLayoutKeepsActionsInline() throws {
        let source = try settingsViewSource

        #expect(source.contains("contentBody"))
        #expect(source.contains("settingsActionButtons"))
        #expect(source.contains("ScrollView {\n            VStack(spacing: 24) {\n                settingsContent\n                settingsActionButtons"))
        #expect(source.contains("#if canImport(UIKit)"))
    }
}
