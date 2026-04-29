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
    private static let panelRadius: Float = 22
    private static let fieldHeight: Float = 36
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
        let sendFill = Color.white.opacity(0.3)

        return VStack(alignment: .leading, spacing: sp.m) {
            HStack(spacing: sp.s) {
                Text("Message \(agentName)")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)
                Spacer(minLength: 0)
                Text("⌘↩")
                    .font(.system(size: ty.micro))
                    .foregroundColor(c.textMuted)
            }

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
                    Text("＋")
                        .font(.system(size: ty.heading))
                        .foregroundColor(c.textSecondary)
                }
                .frame(width: 36, height: 36)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))

                Text("Workspace attached")
                    .font(.system(size: ty.caption))
                    .foregroundColor(c.textMuted)

                Spacer(minLength: 0)

                Button(action: submit) {
                    Text("↑")
                        .font(.system(size: 17))
                        .foregroundColor(sendInk)
                        .frame(width: Self.sendSize, height: Self.sendSize)
                        .background(sendFill)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity)
        }
        .padding(.horizontal, sp.l)
        .padding(.vertical, sp.l)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.panelRadius))
    }

    private func submit() {
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        draft.text = ""
    }
}
