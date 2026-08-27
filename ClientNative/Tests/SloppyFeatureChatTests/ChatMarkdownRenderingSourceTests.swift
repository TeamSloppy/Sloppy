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

    @Test("chat markdown keeps Textual's structured renderer")
    func chatMarkdownTextStackUsesCachedRenderingHelpers() throws {
        let bubbleSource = try source("Sources", "SloppyFeatureChat", "Screens", "Chat", "Views", "ChatBubbleView.swift")
        let supportSource = try source("Sources", "SloppyFeatureChat", "Support", "ChatMessageRenderingSupport.swift")

        #expect(bubbleSource.contains("import Textual"))
        #expect(bubbleSource.contains("StructuredText(markdown: text)"))
        #expect(bubbleSource.contains(".textual.structuredTextStyle(.gitHub)"))
        #expect(!bubbleSource.contains("ChatMarkdownRenderer.blocks(for: text)"))
        #expect(!bubbleSource.contains("ChatMarkdownRenderer.attributedString(for: text)"))
        #expect(!bubbleSource.contains("AttributedString(markdown: text)"))
        #expect(!supportSource.contains("ChatMarkdownBlockParser"))
        #expect(!supportSource.contains("enum ChatMarkdownRenderer"))
        #expect(!supportSource.contains("NSCache"))
    }

    @Test("package wires the locally patched Textual renderer into chat")
    func packageWiresTextualIntoChatFeatureTarget() throws {
        let packageSource = try source("Package.swift")
        let textBuilderSource = try source(
            "Vendor", "Textual", "Sources", "Textual", "Internal", "TextFragment", "TextBuilder.swift"
        )
        let selectionBackgroundSource = try source(
            "Vendor", "Textual", "Sources", "Textual", "Internal", "TextInteraction", "Shared",
            "TextSelectionBackground.swift"
        )
        let selectionViewSource = try source(
            "Vendor", "Textual", "Sources", "Textual", "Internal", "TextInteraction", "AppKit",
            "AppKitTextSelectionView.swift"
        )
        let interactionViewSource = try source(
            "Vendor", "Textual", "Sources", "Textual", "Internal", "TextInteraction", "AppKit",
            "NSTextInteractionView.swift"
        )
        let structuredTextSource = try source(
            "Vendor", "Textual", "Sources", "Textual", "StructuredText", "StructuredText.swift"
        )

        #expect(packageSource.contains(#".package(path: "Vendor/Textual")"#))
        #expect(packageSource.contains(#".product(name: "Textual", package: "textual")"#))
        #expect(textBuilderSource.contains("guard attachmentSizes != currentAttachmentSizes else { return }"))
        #expect(selectionBackgroundSource.contains("if textSelectionModel != nil"))
        #expect(selectionViewSource.contains("guard updatedSelectionRects != selectionRects else { return }"))
        #expect(interactionViewSource.contains("performSelectionAction"))
        #expect(interactionViewSource.contains("selectionActions[sender.tag].perform"))
        #expect(interactionViewSource.contains("didDragSelection"))
        #expect(interactionViewSource.contains("NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: self)"))
        #expect(structuredTextSource.contains("actor BackgroundMarkdownParser"))
        #expect(structuredTextSource.contains(".task(id: markup)"))
        #expect(structuredTextSource.contains("guard !Task.isCancelled else { return }"))
        #expect(!structuredTextSource.contains(".onChange(of: markup, initial: true)"))
    }
}
