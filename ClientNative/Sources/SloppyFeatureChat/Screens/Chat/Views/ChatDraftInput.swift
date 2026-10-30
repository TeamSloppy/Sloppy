import SwiftUI
import SloppyClientUI

/// The chat's native text editor without session/provider controls, for new-message entry points.
@MainActor
public struct ChatDraftInput: View {
    @Bindable private var draft: ChatComposerDraft
    private let placeholder: String
    private let onCommittedText: @MainActor (String) -> Void
    @State private var isFocused = false
    @State private var measuredHeight: CGFloat = 32
    @Environment(\.theme) private var theme

    public init(draft: ChatComposerDraft, placeholder: String = "Message an agent…",
                onCommittedText: @MainActor @escaping (String) -> Void) {
        self.draft = draft
        self.placeholder = placeholder
        self.onCommittedText = onCommittedText
    }

    public var body: some View {
#if os(macOS)
        AppKitChatComposerTextEditor(
            text: $draft.text, selection: $draft.selection, isFocused: $isFocused, measuredHeight: $measuredHeight,
            placeholder: placeholder, fontSize: 16, primaryColor: theme.colors.textPrimary,
            placeholderColor: theme.colors.textMuted, commandColor: theme.colors.accent,
            mentionColor: theme.colors.accent, tagColor: theme.colors.accent, codeBackgroundColor: theme.colors.surfaceRaised,
            maximumVisibleLines: 4, textContainerInset: .init(width: 0, height: 6), lineFragmentPadding: 0,
            cursorOffsetChanged: { _ in }, moveSuggestionSelection: { _ in false }, applySelectedSuggestion: { false },
            submit: { onCommittedText(draft.text) }, pasteAttachment: { false }, references: draft.references,
            registerReferences: draft.registerReferences, onCommittedText: onCommittedText
        )
        .frame(height: max(32, min(100, measuredHeight)))
#elseif canImport(UIKit)
        UIKitChatComposerTextEditor(
            text: $draft.text, selection: $draft.selection, isFocused: $isFocused, measuredHeight: $measuredHeight,
            placeholder: placeholder, fontSize: 17, primaryColor: theme.colors.textPrimary,
            placeholderColor: theme.colors.textMuted, commandColor: theme.colors.accent,
            mentionColor: theme.colors.accent, tagColor: theme.colors.accent,
            maximumVisibleLines: 4, textContainerInset: .init(top: 6, leading: 0, bottom: 6, trailing: 0), lineFragmentPadding: 0,
            cursorOffsetChanged: { _ in }, moveSuggestionSelection: { _ in false }, applySelectedSuggestion: { false },
            submit: { onCommittedText(draft.text) }, pasteItemProviders: { _ in false }, onCommittedText: onCommittedText
        )
        .frame(height: max(44, min(120, measuredHeight)))
#else
        TextField(placeholder, text: $draft.text).onChange(of: draft.text) { _, text in onCommittedText(text) }
#endif
    }
}
