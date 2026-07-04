import Foundation
import Testing

@Suite("Chat markdown rendering source")
struct ChatMarkdownRenderingSourceTests {
    private func source(_ path: String...) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = path.reduce(packageRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("chat markdown text stack uses cached rendering helpers instead of parsing inline in body")
    func chatMarkdownTextStackUsesCachedRenderingHelpers() throws {
        let bubbleSource = try source("Sources", "SloppyFeatureChat", "ChatBubbleView.swift")
        let supportSource = try source("Sources", "SloppyFeatureChat", "ChatMessageRenderingSupport.swift")

        #expect(bubbleSource.contains("ChatMarkdownRenderer.blocks(for: text)"))
        #expect(bubbleSource.contains("ChatMarkdownRenderer.attributedString(for: text)"))
        #expect(!bubbleSource.contains("ChatMarkdownBlockParser.parse(text)"))
        #expect(!bubbleSource.contains("AttributedString(markdown: text)"))
        #expect(supportSource.contains("enum ChatMarkdownRenderer"))
        #expect(supportSource.contains("NSCache"))
    }
}
