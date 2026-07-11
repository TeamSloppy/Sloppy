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
        let bubbleSource = try source("Sources", "SloppyFeatureChat", "Screens", "Chat", "Views", "ChatBubbleView.swift")
        let supportSource = try source("Sources", "SloppyFeatureChat", "Support", "ChatMessageRenderingSupport.swift")

        #expect(bubbleSource.contains("import Textual"))
        #expect(bubbleSource.contains("StructuredText(markdown: text)"))
        #expect(!bubbleSource.contains("ChatMarkdownRenderer.blocks(for: text)"))
        #expect(!bubbleSource.contains("ChatMarkdownRenderer.attributedString(for: text)"))
        #expect(!bubbleSource.contains("AttributedString(markdown: text)"))
        #expect(!supportSource.contains("ChatMarkdownBlockParser"))
        #expect(!supportSource.contains("enum ChatMarkdownRenderer"))
        #expect(!supportSource.contains("NSCache"))
    }

    @Test("package wires Textual into chat feature target")
    func packageWiresTextualIntoChatFeatureTarget() throws {
        let packageSource = try source("Package.swift")

        #expect(packageSource.contains(#".package(url: "https://github.com/gonzalezreal/textual", from: "0.5.0")"#))
        #expect(packageSource.contains(#".product(name: "Textual", package: "textual")"#))
    }
}
