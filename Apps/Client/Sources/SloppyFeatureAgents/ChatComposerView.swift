import AdaEngine
import SloppyClientUI

struct ChatComposerView: View {
    @State private var text: String = ""
    let onSend: (String) -> Void

    var body: some View {
        HStack(spacing: Theme.spacingS) {
            TextField("Message...", text: $text)
                .font(.system(size: Theme.fontBody))
                .foregroundColor(Theme.textPrimary)
                .padding(Theme.spacingS)
                .background(Theme.surface)
                .border(Theme.border, lineWidth: Theme.borderThin)

            Spacer(minLength: 0)

            Button("SEND") {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onSend(trimmed)
                text = ""
            }
            .foregroundColor(Theme.accentCyan)
            .padding(.horizontal, Theme.spacingM)
            .padding(.vertical, Theme.spacingS)
            .border(Theme.accentCyan, lineWidth: Theme.borderThin)
        }
        .padding(Theme.spacingM)
        .background(Theme.bg)
        .border(Theme.border, lineWidth: Theme.borderThin)
    }
}
