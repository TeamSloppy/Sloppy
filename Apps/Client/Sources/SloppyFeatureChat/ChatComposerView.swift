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
    private static let panelWidth: Float = 900
    public static let panelHeight: Float = 64
    public static let phonePanelHeight: Float = 56
    private static let panelRadius: Float = 32
    private static let fieldHeight: Float = 48
    private static let phoneFieldHeight: Float = 36
    private static let sendSize: Float = 38

    @Environment(\.userInterfaceIdiom) private var idiom
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

    @ViewBuilder
    public var body: some View {
        if idiom == .phone {
            phoneBody
        } else {
            regularBody
        }
    }

    private var phoneBody: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let fieldInk = c.textPrimary
        let sendInk = Color.fromHex(0x0C0C0C)
        let sendFill = c.accentCyan.opacity(0.92 as Float)

        return HStack(spacing: sp.s) {
            Button(action: {}) {
                Icons.symbol(.add, size: ty.body)
                    .foregroundColor(c.textSecondary)
                    .frame(width: 28, height: 28)
            }

            TextField("Message \(agentName)...", text: Binding(
                get: { draft.text },
                set: { draft.text = $0 }
            ))
                .font(.system(size: ty.body))
                .foregroundColor(fieldInk)
                .textFieldStyle(PlainTextFieldStyle())
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: Self.phoneFieldHeight, maxHeight: Self.phoneFieldHeight, alignment: .leading)

            Button(action: submit) {
                Icons.symbol(.arrowUpward, size: 17)
                    .foregroundColor(sendInk)
                    .frame(width: Self.sendSize, height: Self.sendSize)
                    .glassEffect(.regular.tint(sendFill), in: .rect(cornerRadius: Self.sendSize / 2))
            }
        }
        .padding(.horizontal, sp.s)
        .padding(.vertical, sp.xs)
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: Self.phonePanelHeight,
            maxHeight: Self.phonePanelHeight,
            alignment: .leading
        )
        .background(c.surfaceGlass.opacity(0.72 as Float))
    }

    private var regularBody: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let fieldInk = c.textPrimary
        let actionInk = Color.fromHex(0x1C1D20)
        let actionFill = Color.fromHex(0xA7DFFF)

        return HStack(spacing: sp.m) {
            Button(action: {}) {
                Icons.symbol(.add, size: 28)
                    .foregroundColor(actionInk)
                    .frame(width: Self.sendSize, height: Self.sendSize)
            }

            TextField("Ask \(agentDisplayName)", text: Binding(
                get: { draft.text },
                set: { draft.text = $0 }
            ))
                .font(.system(size: ty.body))
                .foregroundColor(fieldInk)
                .textFieldStyle(PlainTextFieldStyle())
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: Self.fieldHeight, maxHeight: Self.fieldHeight, alignment: .leading)

            Text("Pro")
                .font(.system(size: ty.body))
                .foregroundColor(actionInk)
                .lineLimit(1)

            Button(action: {}) {
                Icons.symbol(.keyboardCommandKey, size: ty.heading)
                    .foregroundColor(actionInk)
                    .frame(width: 34, height: 34)
            }

            Button(action: submit) {
                Icons.symbol(.arrowUpward, size: ty.heading)
                    .foregroundColor(actionInk)
                    .frame(width: Self.sendSize, height: Self.sendSize)
                    .glassEffect(.regular.tint(actionFill), in: .rect(cornerRadius: Self.sendSize / 2))
            }
        }
        .padding(.leading, sp.l)
        .padding(.trailing, sp.s)
        .padding(.vertical, sp.s)
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: Self.panelHeight,
            maxHeight: Self.panelHeight,
            alignment: .leading
        )
        .background(c.surfaceGlass.opacity(0.72 as Float))
        .frame(maxWidth: Self.panelWidth)
    }

    private var agentDisplayName: String {
        agentName.isEmpty ? "Sloppy" : agentName
    }

    public static func panelHeight(for idiom: UserInterfaceIdiom) -> Float {
        idiom == .phone ? phonePanelHeight : panelHeight
    }

    private func submit() {
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        draft.text = ""
    }
}
