import Foundation
import SwiftUI
import Testing
@testable import SloppyFeatureChat

#if os(macOS)
import AppKit
#endif

@Suite("Native chat composer editor")
@MainActor
struct ChatNativeTextEditorTests {
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
    @Test("AppKit placeholder passes clicks through to the native editor")
    func appKitPlaceholderDoesNotInterceptFocus() {
        let textView = ComposerNSTextView(
            frame: NSRect(x: 0, y: 0, width: 480, height: 48),
            textContainer: nil
        )
        textView.placeholder = "Ask Sloppy"

        #expect(textView.placeholderLabel.hitTest(NSPoint(x: 2, y: 2)) == nil)
        #expect(textView.acceptsFirstResponder)
    }
    #endif
}
