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
    fileprivate static let buttonSize: CGFloat = 36

    private let viewModel: ChatScreenViewModel
    @FocusState private var isTextFieldFocused: Bool

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme
    
    public let draft: ChatComposerDraft
    public var tabActions: ChatComposerTabActions?
    
    public init(
        draft: ChatComposerDraft,
        viewModel: ChatScreenViewModel,
        tabActions: ChatComposerTabActions? = nil
    ) {
        self.draft = draft
        self.tabActions = tabActions
        self.viewModel = viewModel
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
            MobileComposerCircleButton(symbol: .add, action: {
                tabActions?.createTab()
            })
            
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
            .focused($isTextFieldFocused)
            .submitLabel(.send)
            .onSubmit(submit)
            .textFieldStyle(PlainTextFieldStyle())
            .frame(
                minWidth: 0, maxWidth: .infinity, minHeight: Self.phoneFieldHeight,
                maxHeight: Self.phoneFieldHeight, alignment: .leading
            )
            .padding(.horizontal, sp.m)
            .glassEffect(.regular, in: .capsule)
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
        .contentShape(Rectangle())
        .simultaneousGesture(phoneTabGesture)
    }
    
    private var regularBody: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let fieldInk = c.textPrimary
        
        return HStack(spacing: sp.s) {
            MobileComposerCircleButton(symbol: .add, action: {
                tabActions?.createTab()
            })

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
            .focused($isTextFieldFocused)
            .submitLabel(.send)
            .onSubmit(submit)
            .textFieldStyle(.plain)
            .frame(
                minWidth: 0, maxWidth: .infinity, minHeight: Self.fieldHeight,
                maxHeight: Self.fieldHeight, alignment: .leading
            )
            .padding(.horizontal, sp.m)
            .glassEffect(.regular, in: .capsule)

            MobileComposerCircleButton(
                symbol: .arrowUpward,
                foregroundColor: draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? c.textMuted
                : c.textPrimary,
                fillColor: c.surfaceRaised,
                action: submit
            )
        }
        .padding(.horizontal, sp.l)
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: Self.panelHeight,
            maxHeight: Self.panelHeight,
            alignment: .leading
        )
        .frame(maxWidth: Self.panelWidth)
        .onChange(of: viewModel.composerFocusResetToken) { _, _ in
            isTextFieldFocused = false
        }
    }
    
    private var agentDisplayName: String {
        return viewModel.selectedAgent?.displayName ?? "Sloppy"
    }

    private var selectedModelSupportsReasoningEffort: Bool {
        guard let selectedModel = viewModel.availableModels.first(where: { $0.id == viewModel.selectedModelId }) else {
            return false
        }
        return selectedModel.supportsReasoningEffort
    }
    
    public static func panelHeight(for idiom: UserInterfaceIdiom) -> CGFloat {
        idiom == .phone ? phonePanelHeight : panelHeight
    }

    private var phoneTabGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height

                if abs(horizontal) > abs(vertical), abs(horizontal) > 44 {
                    if horizontal < 0 {
                        tabActions?.nextTab()
                    } else {
                        tabActions?.previousTab()
                    }
                    return
                }

                if vertical < -56, abs(vertical) > abs(horizontal) {
                    tabActions?.showOverview()
                }
            }
    }
    
    private func submit() {
        let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.sendMessage(content: trimmed)
        isTextFieldFocused = false
    }
}

public struct ChatComposerTabActions {
    public let previousTab: @MainActor () -> Void
    public let nextTab: @MainActor () -> Void
    public let showOverview: @MainActor () -> Void
    public let createTab: @MainActor () -> Void

    public init(
        previousTab: @escaping @MainActor () -> Void,
        nextTab: @escaping @MainActor () -> Void,
        showOverview: @escaping @MainActor () -> Void,
        createTab: @escaping @MainActor () -> Void
    ) {
        self.previousTab = previousTab
        self.nextTab = nextTab
        self.showOverview = showOverview
        self.createTab = createTab
    }
}

private struct ComposerOptionsMenuView: View {
    let selectedModelId: String
    let models: [ChatModelOption]
    let selectedEffort: ChatReasoningEffort
    let supportsReasoningEffort: Bool
    let selectedAgent: APIAgentRecord?
    let agents: [APIAgentRecord]
    let onSelectModel: (ChatModelOption) -> Void
    let onSelectEffort: (ChatReasoningEffort) -> Void
    let onSelectAgent: (APIAgentRecord) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Menu {
            Section("Model") {
                if models.isEmpty {
                    ComposerMenuItem(title: "No models", isSelected: false)
                } else {
                    ForEach(models) { model in
                        Button {
                            onSelectModel(model)
                        } label: {
                            ComposerMenuItem(
                                title: model.title,
                                subtitle: model.id == model.title ? nil : model.id,
                                isSelected: selectedModelId == model.id
                            )
                        }
                    }
                }
            }

            Section("Reasoning") {
                ForEach(ChatReasoningEffort.allCases) { effort in
                    Button {
                        onSelectEffort(effort)
                    } label: {
                        ComposerMenuItem(
                            title: effort.title,
                            isSelected: selectedEffort == effort
                        )
                    }
                    .disabled(!supportsReasoningEffort)
                }
            }

            Section("Agent") {
                if agents.isEmpty {
                    ComposerMenuItem(title: "No agents", isSelected: false)
                } else {
                    ForEach(agents) { agent in
                        Button {
                            onSelectAgent(agent)
                        } label: {
                            ComposerMenuItem(
                                title: agent.displayName,
                                isSelected: selectedAgent?.id == agent.id
                            )
                        }
                    }
                }
            }
        } label: {
            HStack(alignment: .bottom, spacing: theme.spacing.xs) {
                Text(selectedAgent?.displayName ?? "Sloppy")
                    .font(.system(size: theme.typography.caption, weight: .semibold))
                    .foregroundColor(theme.colors.textPrimary)
                    .lineLimit(1)

                Text(selectedEffort.title)
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(theme.colors.textMuted)
                    .lineLimit(1)

                Icons.symbol(.expandMore, size: 14)
                    .foregroundColor(theme.colors.textSecondary)
            }
            .padding(.horizontal, theme.spacing.m)
            .frame(height: 36)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var selectedModelTitle: String {
        guard let selected = models.first(where: { $0.id == selectedModelId }) else {
            return selectedModelId.isEmpty ? "Model" : selectedModelId
        }
        return selected.title
    }
}

private struct ComposerMenuChip: View {
    let title: String
    var isEnabled: Bool = true

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.xs) {
            Text(title)
                .font(.system(size: theme.typography.body, weight: .semibold))
                .foregroundColor(theme.colors.textPrimary.opacity(isEnabled ? 1 : 0.48))
                .lineLimit(1)

            Icons.symbol(.expandMore, size: 14)
                .foregroundColor(theme.colors.textSecondary.opacity(isEnabled ? 1 : 0.48))
        }
        .padding(.horizontal, theme.spacing.m)
        .frame(height: 36)
        .frame(minWidth: 136, maxWidth: 184)
        .background {
            Capsule()
                .fill(Color.fromHex(0x1C1C1E).opacity(isEnabled ? 0.96 : 0.48))
        }
    }
}

private struct ComposerMenuItem: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }
}

private struct MobileComposerCircleButton: View {
    let symbol: MaterialSymbol
    var foregroundColor: Color = Theme.sloppyDark.colors.textPrimary
    var fillColor: Color = Color.fromHex(0x1C1C1E).opacity(0.96 as CGFloat)
    let action: @MainActor () -> Void
    
    @Environment(\.theme) private var theme
    @Environment(\.userInterfaceIdiom) private var userInterfaceIdiom

    var body: some View {
        let circleSize = userInterfaceIdiom == .phone ? ChatComposerView.phoneCircleSize : ChatComposerView.buttonSize

        Button(action: action) {
            Icons.symbol(symbol, size: userInterfaceIdiom == .phone ? theme.typography.heading : 24)
                .foregroundColor(foregroundColor)
                .frame(width: circleSize, height: circleSize)
        }
        .buttonBorderShape(.circle)
        .buttonStyle(.glass)
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
    VStack {
        Section("Phone") {
            ChatComposerView(draft: .init(), viewModel: viewModel)
                .environment(\.userInterfaceIdiom, .phone)
        }
        Section("desktop") {
            ChatComposerView(draft: .init(), viewModel: viewModel)
                .environment(\.userInterfaceIdiom, .desktop)
        }
    }
}
