import AdaEngine
import SloppyClientUI

struct ChatComposerView: View {
    @State private var text: String = ""
    @Environment(\.theme) private var theme
    let onSend: (String) -> Void

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography

        return HStack(spacing: sp.s) {
            TextField("Message...", text: $text)
                .font(.system(size: ty.body))
                .foregroundColor(c.textPrimary)
                .padding(sp.s)
                .background(c.surface)
                .border(c.border, lineWidth: bo.thin)

            Spacer(minLength: 0)

            Button("SEND") {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onSend(trimmed)
                text = ""
            }
            .foregroundColor(c.accentCyan)
            .padding(.horizontal, sp.m)
            .padding(.vertical, sp.s)
            .border(c.accentCyan, lineWidth: bo.thin)
        }
        .padding(sp.m)
        .background(c.background)
        .border(c.border, lineWidth: bo.thin)
    }
}
