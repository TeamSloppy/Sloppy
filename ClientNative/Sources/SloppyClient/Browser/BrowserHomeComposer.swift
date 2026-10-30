import SwiftUI
import SloppyClientUI
import SloppyFeatureChat

/// An entry into a new work conversation; the full chat keeps the committed text.
@MainActor
struct BrowserHomeComposer: View {
    let onStartChat: (String) -> Void
    @State private var draft = ChatComposerDraft()
    @State private var hasActivated = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            ChatDraftInput(draft: draft, placeholder: "Message an agent…", onCommittedText: activate)
                .accessibilityIdentifier("browser-home-composer")
            Button { activate(draft.text) } label: {
                Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.background)
                    .frame(width: 32, height: 32)
                    .background(draft.text.isEmpty ? theme.colors.textMuted.opacity(0.4) : theme.colors.textPrimary, in: Circle())
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .disabled(draft.text.isEmpty)
            .accessibilityLabel("Start chat")
        }
        .padding(14)
        .background(theme.colors.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(theme.colors.border, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-home-composer-container")
    }

    private func activate(_ text: String) {
        guard !hasActivated, !text.isEmpty else { return }
        hasActivated = true
        onStartChat(text)
    }
}
