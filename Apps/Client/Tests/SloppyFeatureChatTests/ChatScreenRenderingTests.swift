import Foundation
import Testing

@Suite("ChatScreen rendering")
struct ChatScreenRenderingTests {
    private var chatScreenSource: String {
        get throws {
            let packageRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let sourceURL = packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("SloppyFeatureChat")
                .appendingPathComponent("ChatScreen.swift")
            return try String(contentsOf: sourceURL, encoding: .utf8)
        }
    }

    @Test("root chat content does not subscribe to chat view model fields")
    func rootChatContentDoesNotSubscribeToViewModelFields() throws {
        let source = try chatScreenSource
        let contentStart = try #require(source.range(of: "private struct ChatScreenContent: View"))
        let chromeStart = try #require(source.range(of: "private struct ChatChrome: View"))
        let contentSource = source[contentStart.lowerBound..<chromeStart.lowerBound]

        #expect(!contentSource.contains("viewModel."))
    }

    @Test("phone navigation uses a dedicated mobile header capsule")
    func phoneNavigationUsesDedicatedMobileHeaderCapsule() throws {
        let source = try chatScreenSource

        #expect(source.contains("MobileChatNavigationHeader"))
        #expect(source.contains("MobileChatNavigationCenterCapsule"))
        #expect(source.contains("mobileNavigationCapsuleWidth"))
        #expect(source.contains(".frame(width: mobileNavigationCapsuleWidth"))
        #expect(source.contains(".glassEffect(.regular.tint(Color.white.opacity(0.03 as Float)), in: Capsule())"))
        #expect(source.contains("Icons.symbol(.menu"))
    }

    @Test("empty mobile chat keeps composer pinned to bottom")
    func emptyMobileChatKeepsComposerPinnedToBottom() throws {
        let source = try chatScreenSource

        #expect(source.contains("let showsComposer = true"))
        #expect(source.contains("bottomClearance: composerScrollInset"))
        #expect(source.contains("Spacer(minLength: bottomClearance)"))
    }
}
