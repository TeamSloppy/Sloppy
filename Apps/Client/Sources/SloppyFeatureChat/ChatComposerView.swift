import AdaEngine
import SloppyClientUI

public struct ChatComposerView: View {
    private static let panelRadius: Float = 22
    private static let sendSize: Float = 32

    @State private var text: String = ""
    @Environment(\.theme) private var theme

    public let agentName: String
    public let onSend: (String) -> Void

    public init(agentName: String = "Agent", onSend: @escaping (String) -> Void) {
        self.agentName = agentName
        self.onSend = onSend
    }

    public var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let bo = theme.borders
        let ty = theme.typography
        let fieldInk = Color.fromHex(0xEAEAEA)
        let sendInk = Color.fromHex(0x0C0C0C)
        let sendFill = Color.white.opacity(0.3)

        return VStack(alignment: .leading, spacing: sp.m) {
            TextField("Message \(agentName)...", text: $text)
                .font(.system(size: ty.body))
                .foregroundColor(fieldInk)
                .textFieldStyle(PlainTextFieldStyle())

            HStack(spacing: sp.m) {
                Button(action: {}) {
                    Text("+")
                        .font(.system(size: ty.heading))
                        .foregroundColor(c.textSecondary)
                }
                .frame(width: 36, height: 36)

                Spacer(minLength: 0)

                Button(action: submit) {
                    ZStack {
                        CircleShape()
                            .fill(sendFill)
                        Text("↑")
                            .font(.system(size: 17))
                            .foregroundColor(sendInk)
                    }
                    .frame(width: Self.sendSize, height: Self.sendSize)
                }
            }
        }
        .padding(.horizontal, sp.m)
        .padding(.vertical, sp.m)
        .glassEffect(.regular, in: .rect(cornerRadius: Self.panelRadius))
        .padding(.horizontal, sp.m)
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        text = ""
    }
}
