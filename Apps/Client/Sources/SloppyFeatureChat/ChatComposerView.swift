import AdaEngine
import SloppyClientUI

@MainActor
public final class ChatComposerDraft {
    public var text: String

    public init(text: String = "") {
        self.text = text
    }
}

public struct ChatComposerView: View {
    private static let panelWidth: Float = 840
    public static let panelHeight: Float = 118
    private static let panelRadius: Float = 18
    private static let fieldHeight: Float = 52
    private static let sendSize: Float = 32

    @Environment(\.theme) private var theme

    public let draft: ChatComposerDraft
    public let agentName: String
    public let onSend: (String) -> Void

    public init(
        draft: ChatComposerDraft,
        agentName: String = "Agent",
        onSend: @escaping (String) -> Void
    ) {
        self.draft = draft
        self.agentName = agentName
        self.onSend = onSend
    }

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let fieldInk = c.textPrimary
        let sendInk = Color.fromHex(0x0C0C0C)
        let sendFill = Color.white.opacity(0.92 as Float)

        return VStack(alignment: .leading, spacing: sp.s) {
            TextField("Message \(agentName)...", text: Binding(
                get: { draft.text },
                set: { draft.text = $0 }
            ))
                .font(.system(size: ty.body))
                .foregroundColor(fieldInk)
                .textFieldStyle(PlainTextFieldStyle())
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: Self.fieldHeight, alignment: .leading)

            HStack(spacing: sp.m) {
                Button(action: {}) {
                    Icons.symbol(.add, size: ty.body)
                        .foregroundColor(c.textSecondary)
                }
                .frame(width: 28, height: 28)

                HStack(spacing: sp.xs) {
                    Icons.symbol(.keyboardCommandKey, size: ty.micro)
                        .foregroundColor(c.textMuted)
                    Icons.symbol(.keyboardReturn, size: ty.micro)
                        .foregroundColor(c.textMuted)
                }

                Spacer(minLength: 0)
                
                Text("Send")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)


                Button(action: submit) {
                    Icons.symbol(.arrowUpward, size: 17)
                        .foregroundColor(sendInk)
                        .frame(width: Self.sendSize, height: Self.sendSize)
                        .glassEffect(.regular.tint(sendFill), in: .rect(cornerRadius: Self.sendSize / 2))
                }
            }
            .frame(maxWidth: .infinity)
            .debugOverlay()
        }
        .padding(.horizontal, sp.l)
        .padding(.vertical, sp.l)
        .frame(maxWidth: Self.panelWidth, minHeight: Self.panelHeight, maxHeight: Self.panelHeight, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.panelRadius))
    }

    private func submit() {
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        draft.text = ""
    }
}
