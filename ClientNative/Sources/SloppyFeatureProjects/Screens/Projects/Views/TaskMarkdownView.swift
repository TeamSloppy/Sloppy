import SwiftUI
import Textual
import SloppyClientUI
import SloppyClientCore

struct TaskMarkdownView: View {
    let text: String
    @State private var preparedText: String?
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let preparedText {
                markdown(preparedText)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<3) { _ in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.colors.textMuted.opacity(0.18))
                            .frame(height: 12)
                    }
                }
                .accessibilityLabel("Loading text")
            }
        }
        .task(id: text) {
            do {
                preparedText = nil
                let source = text
                let prepared = try await ClientBackgroundWork.run { TaskMarkdown.normalized(source) }
                guard !Task.isCancelled else { return }
                preparedText = prepared
            } catch { }
        }
    }

    private func markdown(_ text: String) -> some View {
        StructuredText(markdown: text)
            .textual.structuredTextStyle(.gitHub)
            .textual.textSelection(.enabled)
            .font(.system(size: theme.typography.body))
            .foregroundStyle(theme.colors.textPrimary)
            .tint(theme.colors.accentCyan)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}
