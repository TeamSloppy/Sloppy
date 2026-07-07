import Foundation
import Observation
import SwiftUI
import SloppyClientUI
import SloppyClientCore

@Observable
@MainActor
public final class ChatComposerDraft {
    public var text: String
    public private(set) var dictationRequestToken: Int = 0
    
    public init(text: String = "") {
        self.text = text
    }

    public func requestDictation() {
        dictationRequestToken += 1
    }
}

public struct ChatComposerView: View {
    public static let panelWidth: CGFloat = 900
    public static let panelHeight: CGFloat = 45
    public static let phonePanelHeight: CGFloat = 72
    private static let panelRadius: CGFloat = 32
    private static let phoneFieldHeight: CGFloat = 48
    fileprivate static let phoneCircleSize: CGFloat = 36
    fileprivate static let buttonSize: CGFloat = 36

    @State private var viewModel: ChatScreenViewModel
    let tabs: [WorkspaceTab]

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    @Bindable public var draft: ChatComposerDraft
    public let tabActions: ChatComposerTabActions?

    public init(
        draft: ChatComposerDraft,
        tabs: [WorkspaceTab],
        viewModel: ChatScreenViewModel,
        tabActions: ChatComposerTabActions? = nil
    ) {
        self.draft = draft
        self.tabs = tabs
        self.tabActions = tabActions
        self._viewModel = State(initialValue: viewModel)
    }
    
    @ViewBuilder
    public var body: some View {
        #if os(visionOS)
        regularBody
        #else
        GlassEffectContainer {
            regularBody
        }
        #endif
    }
    
    private var regularBody: some View {
        let c = theme.colors
        let sp = theme.spacing
        
        return HStack(spacing: sp.s) {
            MobileComposerCircleButton(symbol: .add, action: {
                viewModel.isAttachmentPickerShown = true
            })

            textFieldConainer
                .simultaneousGesture(phoneTabGesture)

            MobileComposerCircleButton(
                symbol: trailingActionSymbol,
                foregroundColor: trailingActionForegroundColor,
                fillColor: c.surfaceRaised,
                action: handleTrailingAction
            )
        }
        .environment(viewModel)
        .padding(.horizontal, sp.s)
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: Self.panelHeight,
            maxHeight: Self.panelHeight,
            alignment: .leading
        )
        .frame(maxWidth: Self.panelWidth)
    }

    private var textFieldConainer: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(tabs, id: \.id) { tab in
                    CustomTabItem {
                        ChatTextField(
                            tab: tab,
                            draft: draft,
                            submit: submit
                        )
                    }
                }
            }
        }
        .frame(height: Self.panelHeight)
        .scrollTargetBehavior(.paging)
        .clipShape(Capsule())
        .onScrollGeometryChange(for: CGFloat.self, of: {
            let containerSize = $0.containerSize.width
            let offset = $0.contentOffset.x + $0.contentInsets.leading
            let progress = offset / containerSize
            return progress
        }, action: { _, newValue in
            tabActions?.tabProgress(newValue)
        })
        .textFieldStyle(.plain)
    }

    private var trimmedDraftText: String {
        draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trailingActionSymbol: MaterialSymbol {
        if viewModel.shouldShowStopButton {
            return .stop
        }

        if trimmedDraftText.isEmpty {
            return .microphone
        }

        return .arrowUpward
    }

    private var trailingActionForegroundColor: Color {
        if viewModel.shouldShowStopButton {
            return theme.colors.textPrimary
        }

        if trimmedDraftText.isEmpty {
            return theme.colors.textPrimary
        }

        return !viewModel.canSubmitMessage
            ? theme.colors.textMuted
            : theme.colors.textPrimary
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

                if vertical < -56, abs(vertical) > abs(horizontal) {
                    tabActions?.showOverview()
                }
            }
    }
    
    private func submit() {
        let trimmed = trimmedDraftText
        guard !trimmed.isEmpty, viewModel.canSubmitMessage else { return }
        viewModel.sendMessage(content: trimmed)
    }

    private func handleTrailingAction() {
        if viewModel.shouldShowStopButton {
            viewModel.stopActiveRun()
            return
        }

        if trimmedDraftText.isEmpty {
            draft.requestDictation()
            return
        }

        submit()
    }
}

public struct ChatComposerTabActions {
    public let tabProgress: @MainActor (CGFloat) -> Void
    public let showOverview: @MainActor () -> Void
    public let createTab: @MainActor () -> Void

    public init(
        tabProgress: @escaping @MainActor (CGFloat) -> Void,
        showOverview: @escaping @MainActor () -> Void,
        createTab: @escaping @MainActor () -> Void
    ) {
        self.tabProgress = tabProgress
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

struct ChatTextField: View {
    let tab: WorkspaceTab
    @Bindable var draft: ChatComposerDraft
    let submit: @MainActor () -> Void

    private static let fieldHeight: CGFloat = 48

    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.theme) private var theme
    @Environment(ChatScreenViewModel.self) private var viewModel

    private var agentDisplayName: String {
        return viewModel.selectedAgent?.displayName ?? "Sloppy"
    }

    var body: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let fieldInk = c.textPrimary

        return TextField(
            "Ask \(agentDisplayName)",
            text: $draft.text
        )
        .font(.system(size: ty.body))
        .foregroundColor(fieldInk)
        .accentColor(.white)
        .focused($isTextFieldFocused)
        .submitLabel(.send)
        .onSubmit {
            submit()
            isTextFieldFocused = false
        }
        .padding(.horizontal, sp.m)
        .containerRelativeFrame(.horizontal)
        .frame(
            minWidth: 0, maxWidth: .infinity, minHeight: Self.fieldHeight,
            maxHeight: Self.fieldHeight, alignment: .leading
        )
        .onChange(of: viewModel.composerFocusResetToken) { _, _ in
            isTextFieldFocused = false
        }
        .onChange(of: draft.dictationRequestToken) { _, _ in
            isTextFieldFocused = true
        }
    }

}

fileprivate struct CustomTabItem<Content: View>: View {
    @ViewBuilder var content: Content
    /// View Properties
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader {
            let rect = $0.frame(in: .scrollView(axis: .horizontal))
            let minX = rect.minX
            let minWidth: CGFloat = 60
            let distanceBetween: CGFloat = -rect.width / 4.5

            let width: CGFloat = minX <= 0 ? (rect.width + minX) : (rect.width - minX)
            let progress = 1 - (width / rect.width).clamp(0, 1)
            let cappedWidth: CGFloat = max((width + (progress * distanceBetween)), minWidth)

            let contentOpacity = calculateContainerOpacity(progress, minX: minX)
            let containerOpacity = calculateContainerOpacity(progress, minX: minX)

            content
                .foregroundStyle(foreground)
                .compositingGroup()
                .blur(radius: contentOpacity / 2)
                .opacity(1 - contentOpacity)
                .frame(width: rect.width, height: rect.height)
                .frame(width: cappedWidth)
                .clipShape(.capsule)
                .glassEffect(
                    .regular
                        .tint(background.opacity(0.1))
                        .interactive(contentOpacity != 1),
                    in: .capsule
                )
                .opacity(1 - containerOpacity)
                .offset(x: minX <= 0 ? -minX : (rect.width - minX - cappedWidth))
        }
        .containerRelativeFrame(.horizontal)
        .frame(maxHeight: .infinity)
    }

    func calculateContentOpacity(_ progress: CGFloat, minX: CGFloat) -> CGFloat {
        if minX < 0 {
            let limit: CGFloat = 0.35
            return progress > limit
            ? ((progress - limit) / 0.1).clamp(0, 1)
            : 0
        }
        let reversedProgress = abs(progress - 1)
        let limit: CGFloat = 0.5
        return reversedProgress > limit
        ? (1 - ((reversedProgress - limit) / 0.1).clamp(0, 1))
        : 1
    }

    func calculateContainerOpacity(_ progress: CGFloat, minX: CGFloat) -> CGFloat {
        let reversedProgress = abs(progress - 1)
        let limit: CGFloat = 0.35
        return reversedProgress > limit
        ? (1 - ((reversedProgress - limit) / 0.1).clamp(0, 1))
        : 1
    }

    var foreground: Color {
        return colorScheme == .dark ? .white : .black
    }

    var background: Color {
        return colorScheme == .dark ? .black : .white
    }
}

extension BinaryFloatingPoint {
    func clamp(_ minValue: Self, _ maxValue: Self) -> Self {
        max(min(self, maxValue), minValue)
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
#if os(visionOS)
        .glassBackgroundEffect()
#else
        .buttonStyle(.glass)
#endif
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
            .backportGlassEffect(
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
    viewModel.sessions = [
        .init(id: "1", agentId: "sloppy", title: "SLOPPY"),
        .init(id: "2", agentId: "sloppy", title: "SLOPPY"),
        .init(id: "3", agentId: "sloppy", title: "SLOPPY"),
    ]

    return VStack(spacing: 16) {
        Section("Phone") {
            ChatComposerView(draft: .init(), tabs: [], viewModel: viewModel)
                .environment(\.userInterfaceIdiom, .phone)
        }
        
        Divider()

        Section("Desktop") {
            ChatComposerView(draft: .init(), tabs: [], viewModel: viewModel)
                .environment(\.userInterfaceIdiom, .desktop)
        }
    }
}
