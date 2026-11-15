import Foundation
import Testing

@Suite("Mobile composer Return")
struct ChatUIKitComposerNewlineSourceTests {
    @Test func returnUsesNativeEditingRatherThanSendOrSuggestionActions() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "Sources/SloppyFeatureChat/Screens/Chat/Views/ChatUIKitComposerTextEditor.swift"), encoding: .utf8)
        #expect(source.contains("textView.returnKeyType = .default"))
        #expect(!source.contains("parent.submit()"))
        #expect(!source.contains("onSubmit?()"))
        #expect(!source.contains("case \"\\r\", \"\\n\":"))
    }
}

#if canImport(UIKit) && !os(macOS)
import SwiftUI
import UIKit
@testable import SloppyFeatureChat

@Suite("UIKit composer newline", .serialized)
@MainActor
struct ChatUIKitComposerNewlineTests {
    @MainActor final class State {
        var text = ""
        var selection: TextSelection?
        var focused = false
        var height: CGFloat = 24
        var sends: [String] = []
        var suggestions = 0
        var commits: [String] = []
    }

    private func editor(_ state: State) -> UIKitChatComposerTextEditor {
        UIKitChatComposerTextEditor(
            text: Binding(get: { state.text }, set: { state.text = $0 }),
            selection: Binding(get: { state.selection }, set: { state.selection = $0 }),
            isFocused: Binding(get: { state.focused }, set: { state.focused = $0 }),
            measuredHeight: Binding(get: { state.height }, set: { state.height = $0 }),
            placeholder: "Message", fontSize: 17, primaryColor: .black,
            placeholderColor: .gray, commandColor: .blue, mentionColor: .green,
            tagColor: .orange, maximumVisibleLines: 6,
            textContainerInset: .init(), lineFragmentPadding: 0,
            cursorOffsetChanged: { _ in }, moveSuggestionSelection: { _ in false },
            applySelectedSuggestion: { state.suggestions += 1; return true },
            submit: { state.sends.append(state.text) }, pasteItemProviders: { _ in false },
            onCommittedText: { state.commits.append($0) }
        )
    }

    @Test func nativeReturnReplacesSelectionWithoutSendingOrApplyingSuggestion() {
        let state = State()
        let parent = editor(state)
        let coordinator = parent.makeCoordinator()
        let view = ComposerUITextView(frame: CGRect(x: 0, y: 0, width: 320, height: 150), textContainer: nil)
        view.delegate = coordinator
        view.text = "one🙂two"
        view.selectedRange = NSRange(location: 3, length: 2)
        view.insertText("\n")
        #expect(view.text == "one\ntwo")
        #expect(view.selectedRange == NSRange(location: 4, length: 0))
        #expect(state.text == "one\ntwo")
        #expect(state.commits.last == "one\ntwo")
        #expect(state.sends.isEmpty)
        #expect(state.suggestions == 0)
        parent.submit() // Same callback used by the separate send button.
        #expect(state.sends == ["one\ntwo"])
    }

    @Test func consecutiveReturnsAndMultilinePasteStayInDraft() {
        let state = State()
        let parent = editor(state)
        let coordinator = parent.makeCoordinator()
        let view = ComposerUITextView(frame: .zero, textContainer: nil)
        view.delegate = coordinator
        view.insertText("first")
        view.insertText("\n")
        view.insertText("\n")
        view.insertText("second\nthird")
        #expect(view.text == "first\n\nsecond\nthird")
        #expect(state.text == view.text)
        #expect(state.sends.isEmpty)
        #expect(state.suggestions == 0)
    }

    @Test func markedTextCompositionIsNotSubmitted() {
        let state = State()
        let parent = editor(state)
        let coordinator = parent.makeCoordinator()
        let view = ComposerUITextView(frame: .zero, textContainer: nil)
        view.delegate = coordinator
        view.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0))
        #expect(view.markedTextRange != nil)
        view.unmarkText()
        view.insertText("\n")
        #expect(view.text.hasSuffix("\n"))
        #expect(state.sends.isEmpty)
        #expect(state.suggestions == 0)
    }
}
#endif
