import Foundation
import SwiftUI
import SloppyClientUI
import SloppyClientCore

@MainActor
public final class ChatComposerDraft {
    public var text: String
    
    public init(text: String = "") {
        self.text = text
    }
}

public struct ChatComposerView: View {
    public static let panelWidth: CGFloat = 900
    public static let panelHeight: CGFloat = 64
    public static let phonePanelHeight: CGFloat = 72
    private static let panelRadius: CGFloat = 32
    private static let fieldHeight: CGFloat = 48
    private static let phoneFieldHeight: CGFloat = 48
    fileprivate static let phoneCircleSize: CGFloat = 48

    @State private var viewModel: ChatScreenViewModel

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme
    
    public let draft: ChatComposerDraft
    
    public init(
        draft: ChatComposerDraft,
        viewModel: ChatScreenViewModel,
    ) {
        self.draft = draft
        self._viewModel = State(initialValue: viewModel)
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
        
        return HStack(spacing: sp.s) {
            MobileComposerCircleButton(symbol: .add, action: {})
            
            TextField(
                "Ask \(agentDisplayName)",
                text: Binding(
                    get: { draft.text },
                    set: { draft.text = $0 }
                )
            )
            .font(.system(size: ty.body))
            .foregroundColor(fieldInk)
            .accentColor(.white)
            .textFieldStyle(PlainTextFieldStyle())
            .frame(
                minWidth: 0, maxWidth: .infinity, minHeight: Self.phoneFieldHeight,
                maxHeight: Self.phoneFieldHeight, alignment: .leading
            )
            .padding(.horizontal, sp.m)
            .glassEffect(.regular, in: GlassShape.capsule)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            MobileComposerCircleButton(
                symbol: .arrowUpward,
                foregroundColor: draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? c.textMuted
                : c.textPrimary,
                fillColor: c.surfaceRaised,
                action: submit
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, sp.xs)
        .padding(.vertical, sp.s)
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: Self.phonePanelHeight,
            maxHeight: Self.phonePanelHeight,
            alignment: .leading
        )
    }
    
    private var regularBody: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let fieldInk = c.textPrimary
        let actionInk = c.textPrimary
        
        return HStack(spacing: sp.m) {
            Button {

            } label: {
                Icons.symbol(.add, size: 24)
            }
            .buttonStyle(.plain)

            TextField(
                "Ask \(agentDisplayName)",
                text: Binding(
                    get: { draft.text },
                    set: { draft.text = $0 }
                )
            )
            .font(.system(size: ty.body))
            .foregroundColor(fieldInk)
            .accentColor(.white)
            .textFieldStyle(.plain)
            .frame(
                minWidth: 0, maxWidth: .infinity, minHeight: Self.fieldHeight,
                maxHeight: Self.fieldHeight, alignment: .leading
            )

            AgentPickerView(
                selectedAgent: viewModel.selectedAgent,
                agents: viewModel.agents,
                onSelectAgent: viewModel.pickAgent
            )

            Button(action: submit) {
                Icons.symbol(.arrowUpward, size: ty.heading)
            }
            .buttonStyle(SubmitButton())
        }
        .padding(EdgeInsets(top: 0, leading: sp.l, bottom: 0, trailing: sp.l))
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: Self.panelHeight,
            maxHeight: Self.panelHeight,
            alignment: .leading
        )
        .background {
            ChatComposerCapsuleChrome(
                height: Self.panelHeight,
                aspectRatio: Self.panelWidth / Self.panelHeight,
                accentColor: c.accentCyan
            )
        }
        .frame(maxWidth: Self.panelWidth)
    }
    
    private var agentDisplayName: String {
        return viewModel.selectedAgent?.displayName ?? "Sloppy"
    }
    
    public static func panelHeight(for idiom: UserInterfaceIdiom) -> CGFloat {
        idiom == .phone ? phonePanelHeight : panelHeight
    }
    
    private func submit() {
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.sendMessage(content: trimmed)
        draft.text = ""
    }
}

struct AgentPickerView: View {

    let selectedAgent: APIAgentRecord?
    let agents: [APIAgentRecord]
    let onSelectAgent: (APIAgentRecord) -> Void

    @Environment(\.userInterfaceIdiom) private var idiom

    var body: some View {
        Picker("", selection: selectedAgentId) {
            if agents.isEmpty {
                Text("Select Agent").tag("")
            } else {
                ForEach(agents) { agent in
                    Text(agent.displayName).tag(agent.id)
                }
            }
        }
        .labelsHidden()
        .tint(.white)
        .pickerStyle(.menu)

    }

    private var selectedAgentId: Binding<String> {
        Binding(
            get: { selectedAgent?.id ?? agents.first?.id ?? "" },
            set: { nextId in
                guard let agent = agents.first(where: { $0.id == nextId }) else {
                    return
                }
                onSelectAgent(agent)
            }
        )
    }
}

private struct MobileComposerCircleButton: View {
    let symbol: MaterialSymbol
    var foregroundColor: Color = Theme.sloppyDark.colors.textPrimary
    var fillColor: Color = Color.fromHex(0x1C1C1E).opacity(0.96 as CGFloat)
    let action: @MainActor () -> Void
    
    @Environment(\.theme) private var theme
    
    var body: some View {
        Button(action: action) {
            Icons.symbol(symbol, size: theme.typography.heading)
                .foregroundColor(foregroundColor)
                .frame(width: ChatComposerView.phoneCircleSize, height: ChatComposerView.phoneCircleSize)
                .background {
                    Circle()
                        .fill(fillColor)
                }
        }
        .glassEffect(.regular, in: Circle())
        .buttonStyle(DefaultButtonStyle())
    }
}

private struct ChatComposerCapsuleChrome: View {
    let height: CGFloat
    let aspectRatio: CGFloat
    let accentColor: Color

    var body: some View {
        Capsule()
            .fill(Color.black)
    }
}

struct SubmitButton: ButtonStyle {

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    private static let sendSize: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        let actionFill = Color.accentColor

        configuration.label
            .foregroundColor(theme.colors.textPrimary)
            .frame(width: Self.sendSize, height: Self.sendSize)
            .padding(4)
            .glassEffect(
                .regular.tint(actionFill.opacity(isEnabled ? 1 : 0.4)),
                in: Circle()
            )
    }
}

#Preview {
    let viewModel = ChatScreenViewModel(
        apiClient: .init(),
        settings: .init(),
        connectionMonitor: .init(baseURL: URL.debugURL),
        onOpenSettings: {}
    )
    ChatComposerView(draft: .init(), viewModel: viewModel)
}

