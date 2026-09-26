import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import SloppyFeatureChat

#if os(macOS)
import AppKit
#endif

@Suite("Native chat composer editor")
@MainActor
struct ChatNativeTextEditorTests {
    @Test("fenced code spans stay separate from surrounding prose")
    func codeFenceRanges() throws {
        let text = "Intro 🙂\n```swift\nlet value = 1\n```\nAfter"
        let range = try #require(ChatComposerCodeFence.ranges(in: text).first)
        let code = (text as NSString).substring(with: range)

        #expect(code.hasPrefix("```swift\n"))
        #expect(code.contains("let value = 1"))
        #expect(!code.contains("After"))
        #expect(ChatComposerCodeFence.ranges(in: text).count == 1)
    }

    @Test("unfinished code fences remain styled while typing")
    func unfinishedCodeFenceRange() throws {
        let text = "~~~swift\nlet value = 1"
        let range = try #require(ChatComposerCodeFence.ranges(in: text).first)

        #expect(range == NSRange(location: 0, length: (text as NSString).length))
        #expect(ChatComposerCodeFence.ranges(in: "ordinary text").isEmpty)
    }

    @Test("selection converts through native UTF-16 ranges without losing emoji offsets")
    func selectionRoundTripsThroughUTF16() throws {
        let text = "A🙂B"
        let insertionPoint = text.index(text.startIndex, offsetBy: 2)
        let selection = TextSelection(insertionPoint: insertionPoint)

        let nativeRange = try #require(
            ChatComposerNativeSelection.nativeRange(from: selection, in: text)
        )
        #expect(nativeRange == NSRange(location: 3, length: 0))
        #expect(
            ChatComposerNativeSelection.characterOffset(
                forUTF16Location: nativeRange.location,
                in: text
            ) == 2
        )

        let roundTripped = try #require(
            ChatComposerNativeSelection.textSelection(from: nativeRange, in: text)
        )
        guard case .selection(let range) = roundTripped.indices else {
            Issue.record("Expected a single native selection")
            return
        }
        #expect(range.isEmpty)
        #expect(text.distance(from: text.startIndex, to: range.lowerBound) == 2)
    }

    @Test("plain text paste stays native instead of becoming an attachment")
    func plainTextPasteStaysNative() {
        #expect(!ChatComposerPasteboard.containsAttachmentType([UTType.plainText.identifier]))
        #expect(!ChatComposerPasteboard.containsAttachmentType([UTType.html.identifier]))
        #expect(!ChatComposerPasteboard.containsAttachmentType([UTType.url.identifier]))
    }

    @Test("binary and file paste is routed to attachments")
    func attachmentPasteIsIntercepted() {
        #expect(ChatComposerPasteboard.containsAttachmentType([UTType.png.identifier]))
        #expect(ChatComposerPasteboard.containsAttachmentType([UTType.pdf.identifier]))
        #expect(ChatComposerPasteboard.containsAttachmentType([UTType.zip.identifier]))
        #expect(ChatComposerPasteboard.containsAttachmentType([UTType.folder.identifier]))
        #expect(ChatComposerPasteboard.containsAttachmentType([UTType.fileURL.identifier]))
        #expect(
            ChatComposerPasteboard.containsAttachmentType([
                UTType.plainText.identifier,
                UTType.png.identifier,
            ])
        )
    }

    @Test("changing draft text clears indices owned by the previous string")
    func textChangeClearsStaleSelection() {
        let original = "old"
        let draft = ChatComposerDraft(
            text: original,
            selection: TextSelection(insertionPoint: original.endIndex)
        )

        draft.text = "new value"

        #expect(draft.selection == nil)
    }

    #if os(macOS)
    @Test("AppKit editor creates a writable TextKit stack")
    func appKitEditorAcceptsTextInput() throws {
        let textView = AppKitChatComposerTextEditor.makeTextView()

        _ = try #require(textView.textStorage)
        _ = try #require(textView.layoutManager)
        _ = try #require(textView.textContainer)

        textView.insertText("Hello", replacementRange: NSRange(location: 0, length: 0))

        #expect(textView.string == "Hello")
    }

    @Test("AppKit composer gives fenced code a monospaced face and background")
    func appKitFencedCodeIsStyled() throws {
        let textView = AppKitChatComposerTextEditor.makeTextView()
        let style = AppKitComposerTextStyle(
            font: .systemFont(ofSize: 14),
            primaryColor: .white,
            placeholderColor: .gray,
            commandColor: .red,
            mentionColor: .blue,
            tagColor: .green,
            codeBackgroundColor: .black
        )
        let text = "Prose\n```swift\nlet value = 1\n```"
        textView.setStyledText(text, style: style)
        let storage = try #require(textView.textStorage)
        let codeLocation = (text as NSString).range(of: "let value").location
        let codeFont = try #require(storage.attribute(.font, at: codeLocation, effectiveRange: nil) as? NSFont)
        let codeBackground = try #require(
            storage.attribute(.backgroundColor, at: codeLocation, effectiveRange: nil) as? NSColor
        )

        #expect(codeFont.isFixedPitch)
        #expect(codeBackground.isEqual(NSColor.black))
        #expect(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
    }

    @Test("AppKit placeholder passes clicks through to the native editor")
    func appKitPlaceholderDoesNotInterceptFocus() {
        let textView = AppKitChatComposerTextEditor.makeTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 480, height: 48)
        textView.placeholder = "Ask Sloppy"

        #expect(textView.placeholderLabel.hitTest(NSPoint(x: 2, y: 2)) == nil)
        #expect(textView.acceptsFirstResponder)
    }

    @Test("AppKit paste interception distinguishes images from plain text")
    func appKitPasteInterceptionDistinguishesImagesFromPlainText() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.setString("plain text", forType: .string)
        #expect(!ComposerNSTextView.pasteboardContainsAttachment(pasteboard))

        pasteboard.clearContents()
        pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        #expect(ComposerNSTextView.pasteboardContainsAttachment(pasteboard))

        pasteboard.clearContents()
        pasteboard.setData(Data("%PDF".utf8), forType: .pdf)
        #expect(ComposerNSTextView.pasteboardContainsAttachment(pasteboard))
    }

    @Test("AppKit enables native Paste commands for image attachments")
    func appKitEnablesAttachmentPasteCommand() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        let pasteMenuItem = NSMenuItem(
            title: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )

        #expect(
            ComposerNSTextView.shouldEnableAttachmentPaste(
                action: pasteMenuItem.action,
                pasteboard: pasteboard
            )
        )
        #expect(
            !ComposerNSTextView.shouldEnableAttachmentPaste(
                action: #selector(NSText.copy(_:)),
                pasteboard: pasteboard
            )
        )

        pasteboard.clearContents()
        pasteboard.setString("plain text", forType: .string)
        #expect(
            !ComposerNSTextView.shouldEnableAttachmentPaste(
                action: #selector(NSText.paste(_:)),
                pasteboard: pasteboard
            )
        )
    }
    #endif
}
