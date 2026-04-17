import AdaEngine
import SloppyClientUI

public struct ChatComposerView: View {
    private static let panelRadius: Float = 22
    private static let sendSize: Float = 44

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
        let sendFill = Color.fromHex(0xF6F6F6)

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
                .background(Color.white.opacity(0.07 as Float))
                .border(c.border.opacity(0.45 as Float), lineWidth: bo.thin)

                Spacer(minLength: 0)

                Button(action: submit) {
                    ZStack {
                        CircleShape()
                            .foregroundColor(sendFill)
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
