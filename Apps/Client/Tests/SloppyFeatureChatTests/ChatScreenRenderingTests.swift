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
}
