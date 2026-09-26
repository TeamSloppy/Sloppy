import Foundation
import Testing

@Suite("Chat conversation navigator layout")
struct ChatConversationNavigatorLayoutTests {
    private func source(_ path: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("dense markers live at the left edge without a transcript scroller")
    func denseMarkersOnLeft() throws {
        let screen = try source("Sources/SloppyFeatureChat/Screens/Chat/ChatScreen.swift")
        let navigator = try source("Sources/SloppyFeatureChat/Screens/Chat/Views/ChatConversationNavigator.swift")
        let transcript = try source("Sources/SloppyFeatureChat/Screens/Chat/Views/ChatNativeTranscriptView.swift")

        #expect(screen.contains(".overlay(alignment: .leading)"))
        #expect(screen.contains(".padding(.leading, theme.spacing.m)"))
        #expect(navigator.contains("VStack(spacing: 0)"))
        #expect(navigator.contains(".frame(width: 26, height: 4, alignment: .leading)"))
        #expect(!navigator.contains(".fill(theme.colors.borderBold.opacity(0.42))"))
        #expect(transcript.contains("scrollView.hasVerticalScroller = false"))
    }
}
