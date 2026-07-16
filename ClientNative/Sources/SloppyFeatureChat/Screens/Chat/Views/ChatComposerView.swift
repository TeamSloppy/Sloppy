import Foundation
import Observation
import SwiftUI
import SloppyClientUI
import SloppyClientCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

@Observable
@MainActor
public final class ChatComposerDraft {
    public var text: String
    
    public init(text: String = "") {
        self.text = text
    }
}

public struct ChatComposerView: View {
    public static let panelWidth: CGFloat = 900
    public static let panelHeight: CGFloat = 45
    public static let phonePanelHeight: CGFloat = 72
    public static let attachmentStripHeight: CGFloat = 42
    private static let panelRadius: CGFloat = 18
    private static let phoneFieldHeight: CGFloat = 48
    fileprivate static let phoneCircleSize: CGFloat = 36
    fileprivate static let buttonSize: CGFloat = 36
    private static let overviewGestureDistance: CGFloat = 220

    @State private var viewModel: ChatScreenViewModel
    @State private var isOverviewGestureActive = false
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

        return VStack(spacing: sp.s) {
            if !viewModel.composerAttachments.isEmpty {
                ChatComposerAttachmentStrip(
                    attachments: viewModel.composerAttachments,
                    remove: viewModel.removeComposerAttachment
                )
                .frame(height: Self.attachmentStripHeight)
            }

            ZStack {
                if viewModel.isShowingDictationComposer {
                    DictationComposerBar(
                        phase: viewModel.dictationPhase,
                        levels: viewModel.dictationLevels,
                        elapsed: viewModel.dictationDuration,
                        stop: viewModel.stopDictation
                    )
                } else {
                    HStack(spacing: sp.s) {
                        ComposerAddMenu(
                            viewModel: viewModel,
                            supportsReasoningEffort: selectedModelSupportsReasoningEffort
                        )

                        #if os(macOS)
                            ChatTextField(
                                draft: draft,
                                submit: submit
                            )
                            .clipShape(.rect(cornerRadius: Self.panelRadius))
                            .glassEffect(.regular, in: .rect(cornerRadius: Self.panelRadius))
                        #else
                        textFieldConainer
                            .simultaneousGesture(phoneTabGesture)
                        #endif

                        MobileComposerCircleButton(
                            symbol: trailingActionSymbol,
                            foregroundColor: trailingActionForegroundColor,
                            fillColor: c.surfaceRaised,
                            action: handleTrailingAction
                        )
                    }
                }
            }
        }
        .environment(viewModel)
        .padding(.horizontal, sp.s)
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: Self.panelHeight(for: idiom),
            alignment: .leading
        )
        .frame(maxWidth: Self.panelWidth)
        .overlay(alignment: .bottom) {
            if !viewModel.composerSuggestions.isEmpty {
                ComposerSuggestionsView(
                    suggestions: viewModel.composerSuggestions,
                    selectedSuggestionID: viewModel.composerSuggestionSelection.selectedID,
                    select: viewModel.applyComposerSuggestion
                )
                .offset(y: -composerSuggestionsOffset)
            }
        }
    }

    private var composerSuggestionsOffset: CGFloat {
        Self.panelHeight
            + theme.spacing.s
            + (viewModel.composerAttachments.isEmpty ? 0 : Self.attachmentStripHeight + theme.spacing.s)
    }

    private var textFieldConainer: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(tabs, id: \.id) { tab in
                    CustomTabItem {
                        ChatTextField(
                            draft: draft,
                            submit: submit
                        )
                    }
                }
            }
        }
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
    }

    private var trimmedDraftText: String {
        draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trailingActionSymbol: MaterialSymbol {
        if viewModel.shouldShowStopButton {
            return .stop
        }

        if trimmedDraftText.isEmpty && viewModel.composerAttachments.isEmpty {
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
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let isOverviewGesture = vertical < 0 && abs(vertical) > abs(horizontal)

                guard isOverviewGesture else {
                    if isOverviewGestureActive {
                        tabActions?.updateOverviewGesture(0)
                    }
                    return
                }

                if !isOverviewGestureActive {
                    isOverviewGestureActive = true
                    tabActions?.beginOverviewGesture()
                }

                let progress = (-vertical / Self.overviewGestureDistance).clamp(0, 1)
                tabActions?.updateOverviewGesture(progress)
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height

                if isOverviewGestureActive {
                    let progress = (-vertical / Self.overviewGestureDistance).clamp(0, 1)
                    let velocity = -(value.predictedEndTranslation.height - value.translation.height)
                    tabActions?.endOverviewGesture(progress, velocity)
                    isOverviewGestureActive = false
                } else if vertical < -56, abs(vertical) > abs(horizontal) {
                    tabActions?.showOverview()
                }
            }
    }
    
    private func submit() {
        let trimmed = trimmedDraftText
        guard (!trimmed.isEmpty || !viewModel.composerAttachments.isEmpty), viewModel.canSubmitMessage else { return }
        viewModel.sendMessage(content: trimmed)
    }

    private func handleTrailingAction() {
        if viewModel.shouldShowStopButton {
            viewModel.stopActiveRun()
            return
        }

        if trimmedDraftText.isEmpty && viewModel.composerAttachments.isEmpty {
            viewModel.startDictation()
            return
        }

        submit()
    }
}

public struct ChatComposerTabActions {
    public let tabProgress: @MainActor (CGFloat) -> Void
    public let showOverview: @MainActor () -> Void
    public let beginOverviewGesture: @MainActor () -> Void
    public let updateOverviewGesture: @MainActor (CGFloat) -> Void
    public let endOverviewGesture: @MainActor (CGFloat, CGFloat) -> Void
    public let createTab: @MainActor () -> Void

    public init(
        tabProgress: @escaping @MainActor (CGFloat) -> Void,
        showOverview: @escaping @MainActor () -> Void,
        beginOverviewGesture: @escaping @MainActor () -> Void = {},
        updateOverviewGesture: @escaping @MainActor (CGFloat) -> Void = { _ in },
        endOverviewGesture: @escaping @MainActor (CGFloat, CGFloat) -> Void = { _, _ in },
        createTab: @escaping @MainActor () -> Void
    ) {
        self.tabProgress = tabProgress
        self.showOverview = showOverview
        self.beginOverviewGesture = beginOverviewGesture
        self.updateOverviewGesture = updateOverviewGesture
        self.endOverviewGesture = endOverviewGesture
        self.createTab = createTab
    }
}

public struct ChatAgentToolbarMenu: View {
    public let selectedAgent: APIAgentRecord?
    public let agents: [APIAgentRecord]
    public let onSelectAgent: (APIAgentRecord) -> Void

    @Environment(\.theme) private var theme

    public init(
        selectedAgent: APIAgentRecord?,
        agents: [APIAgentRecord],
        onSelectAgent: @escaping (APIAgentRecord) -> Void
    ) {
        self.selectedAgent = selectedAgent
        self.agents = agents
        self.onSelectAgent = onSelectAgent
    }

    public var body: some View {
        Menu {
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
            Label(selectedAgent?.displayName ?? "Agent", systemImage: "person.fill")
                .disabled(agents.isEmpty)
                .labelStyle(.titleOnly)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}

#Preview {
    ChatAgentToolbarMenu(
        selectedAgent: .init(
            id: "",
            displayName: "Anton"
        ),
        agents: [],
        onSelectAgent: { _ in }
    )
}

public struct ChatModelToolbarMenu: View {
    public let selectedModelId: String
    public let models: [ChatModelOption]
    public let onSelectModel: (ChatModelOption) -> Void

    public init(
        selectedModelId: String,
        models: [ChatModelOption],
        onSelectModel: @escaping (ChatModelOption) -> Void
    ) {
        self.selectedModelId = selectedModelId
        self.models = models
        self.onSelectModel = onSelectModel
    }

    public var body: some View {
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
        } label: {
            Label(selectedModelTitle, systemImage: "brain")
                .disabled(models.isEmpty)
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
    @Bindable var draft: ChatComposerDraft
    let submit: @MainActor () -> Void

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
            text: $draft.text,
            axis: .vertical
        )
        .lineLimit(1...6)
        .scrollIndicators(.visible, axes: .vertical)
        .font(.system(size: ty.body))
        .foregroundColor(fieldInk)
        .accentColor(.white)
        .focused($isTextFieldFocused)
        .focusable()
        .submitLabel(.send)
        .onKeyPress(.upArrow) {
            viewModel.moveComposerSuggestionSelection(.previous) ? .handled : .ignored
        }
        .onKeyPress(.downArrow) {
            viewModel.moveComposerSuggestionSelection(.next) ? .handled : .ignored
        }
        .onKeyPress(.return, phases: .down) { keyPress in
            if keyPress.modifiers.contains(.shift) {
                return .ignored
            }
            return viewModel.applySelectedComposerSuggestion() ? .handled : .ignored
        }
        .onSubmit {
            submit()
            isTextFieldFocused = false
        }
        .onPasteCommand(of: [.fileURL, .image]) { providers in
            viewModel.attachItemProviders(providers)
        }
        .padding(.horizontal, sp.m)
        .textFieldStyle(.plain)
        .frame(
            minWidth: 0, maxWidth: .infinity, minHeight: Constants.fieldHeight,
            alignment: .leading
        )
        .clipped()
        .layoutPriority(1)
        .onChange(of: viewModel.composerFocusResetToken) { _, _ in
            isTextFieldFocused = false
        }
        .onChange(of: draft.text) { _, newValue in
            viewModel.updateComposerSuggestions(for: newValue)
        }
    }
}

private struct ChatComposerAttachmentStrip: View {
    let attachments: [ChatComposerAttachment]
    let remove: @MainActor (ChatComposerAttachment.ID) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing.s) {
                ForEach(attachments) { attachment in
                    attachmentChip(attachment)
                }
            }
            .padding(.horizontal, theme.spacing.xs)
        }
        .scrollClipDisabled()
        .accessibilityLabel("Attachments")
    }

    private func attachmentChip(_ attachment: ChatComposerAttachment) -> some View {
        HStack(spacing: theme.spacing.s) {
            Image(systemName: attachment.mimeType.hasPrefix("image/") ? "photo" : "doc")
                .foregroundColor(theme.colors.accentCyan)

            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.name)
                    .font(.system(size: theme.typography.caption, weight: .medium))
                    .foregroundColor(theme.colors.textPrimary)
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.sizeBytes), countStyle: .file))
                    .font(.system(size: theme.typography.micro))
                    .foregroundColor(theme.colors.textMuted)
            }

            Button {
                remove(attachment.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: theme.typography.micro, weight: .bold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundColor(theme.colors.textSecondary)
            .accessibilityLabel("Remove \(attachment.name)")
        }
        .padding(.leading, theme.spacing.s)
        .padding(.trailing, theme.spacing.xs)
        .padding(.vertical, theme.spacing.xs)
        .background(theme.colors.surfaceRaised.opacity(0.96), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.colors.border, lineWidth: theme.borders.thin)
        }
    }
}

private struct DictationComposerBar: View {
    let phase: ChatComposerDictationPhase
    let levels: [CGFloat]
    let elapsed: TimeInterval
    let stop: @MainActor () -> Void

    @Environment(\.theme) private var theme

    private let elapsedTextWidth: CGFloat = 64
    private let stopButtonSize: CGFloat = 32

    private var trailingControlsWidth: CGFloat {
        elapsedTextWidth + theme.spacing.s + stopButtonSize
    }

    private var isRecording: Bool {
        phase == .recording
    }

    private var elapsedText: String {
        let totalSeconds = Int(elapsed.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: theme.spacing.s) {
            if isRecording {
                waveformViewport
                    .scaleEffect(x: -1)
            } else {
                Spacer(minLength: 0)
            }
            trailingControls
        }
        .padding(.trailing, theme.spacing.s)
        .padding(.leading, theme.spacing.m)
        .frame(
            maxWidth: .infinity,
            minHeight: ChatComposerView.panelHeight,
            maxHeight: ChatComposerView.panelHeight
        )
        .backportGlassEffect(
            .regular.tint(Color.fromHex(0x1C1C1E)),
            in: .capsule
        )
    }

    private var waveformViewport: some View {
        Color.clear
            .frame(maxWidth: .infinity, alignment: .trailing)
            .overlay(alignment: .trailing) {
                waveformView
                    .allowsHitTesting(false)
            }
            .clipped()
    }

    @ViewBuilder
    private var trailingControls: some View {
        if isRecording {
            HStack(spacing: theme.spacing.s) {
                Text(elapsedText)
                    .font(.system(size: theme.typography.body, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.fromHex(0xFF5A64))
                    .monospacedDigit()
                    .frame(width: elapsedTextWidth, alignment: .trailing)

                Button(action: stop) {
                    ZStack {
                        Circle()
                            .fill(Color.fromHex(0x8E2F35))
                        Icons.symbol(.stop, size: theme.typography.body)
                            .foregroundColor(Color.fromHex(0xFF7078))
                    }
                    .frame(
                        width: stopButtonSize,
                        height: stopButtonSize
                    )
                }
                .buttonStyle(.plain)
                
            }
            .frame(width: trailingControlsWidth, alignment: .trailing)
        } else {
            Text("Transcribing…")
                .font(.system(size: theme.typography.body, weight: .semibold))
                .foregroundColor(Color.fromHex(0xFF5A64))
        }
    }

    private var waveformView: some View {
        HStack(spacing: 3) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.fromHex(0xFF4D57).opacity(isRecording ? 0.92 : 0.38))
                    .frame(width: 3, height: 6 + levels[index] * 14)
            }
        }
        .animation(.easeOut(duration: 0.12), value: levels)
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
                .clipShape(RoundedRectangle(cornerRadius: Constants.fieldHeight / 2, style: .continuous))
                .backportGlassEffect(
                    .regular
                        .tint(background.opacity(0.1))
                        .interactive(contentOpacity != 1),
                    in: RoundedRectangle(cornerRadius: Constants.fieldHeight / 2, style: .continuous)
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

    var body: some View {
        Button(action: action) {
            Icons.symbol(symbol, size: theme.typography.heading)
                .foregroundColor(foregroundColor)
                .frame(
                    width: ChatComposerView.phoneCircleSize,
                    height: ChatComposerView.phoneCircleSize
                )
        }
        .buttonBorderShape(.circle)
#if os(visionOS)
        .glassBackgroundEffect()
#else
        .buttonStyle(.glass)
#endif
    }
}

private struct ComposerAddMenu: View {
    let viewModel: ChatScreenViewModel
    let supportsReasoningEffort: Bool

    @Environment(\.theme) private var theme

    var body: some View {
        Menu {
#if os(macOS)
            Button {
                viewModel.isAttachmentPickerShown = true
            } label: {
                Label("Files and Attach", systemImage: "paperclip")
            }

            modelMenu
#else
            Button {
                viewModel.isCameraPickerShown = true
            } label: {
                Label("Camera", systemImage: "camera")
            }
#if os(visionOS)
            .disabled(true)
#endif

            Button {
                viewModel.isPhotoPickerShown = true
            } label: {
                Label("Photos", systemImage: "photo.on.rectangle")
            }

            Button {
                viewModel.isAttachmentPickerShown = true
            } label: {
                Label("Files", systemImage: "folder")
            }

            agentMenu
            effortMenu
#endif
        } label: {
            Color.clear
                .clipShape(.circle)
        }
        .menuStyle(CustomMenuButtonStyle())
        .accessibilityLabel("Add")
    }

    private var modelMenu: some View {
        Menu {
            if viewModel.availableModels.isEmpty {
                Text("No models")
            } else {
                ForEach(viewModel.availableModels) { model in
                    Button {
                        viewModel.pickModel(model)
                    } label: {
                        ComposerMenuItem(
                            title: model.title,
                            subtitle: model.id == model.title ? nil : model.id,
                            isSelected: viewModel.selectedModelId == model.id
                        )
                    }
                }
            }
        } label: {
            Label("Model", systemImage: "brain")
        }
    }

    private var agentMenu: some View {
        Menu {
            if viewModel.agents.isEmpty {
                Text("No agents")
            } else {
                ForEach(viewModel.agents) { agent in
                    Button {
                        viewModel.pickAgent(agent)
                    } label: {
                        ComposerMenuItem(
                            title: agent.displayName,
                            isSelected: viewModel.selectedAgent?.id == agent.id
                        )
                    }
                }
            }
        } label: {
            Label("Agent", systemImage: "person")
        }
    }

    private var effortMenu: some View {
        Menu {
            ForEach(ChatReasoningEffort.allCases) { effort in
                Button {
                    viewModel.pickReasoningEffort(effort)
                } label: {
                    ComposerMenuItem(
                        title: effort.title,
                        isSelected: viewModel.selectedReasoningEffort == effort
                    )
                }
            }
        } label: {
            Label("Effort", systemImage: "gauge.with.dots.needle.50percent")
        }
        .disabled(!supportsReasoningEffort)
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
        onOpenSettings: { _ in }
    )
    viewModel.sessions = [
        .init(id: "1", agentId: "sloppy", title: "SLOPPY"),
        .init(id: "2", agentId: "sloppy", title: "SLOPPY"),
        .init(id: "3", agentId: "sloppy", title: "SLOPPY"),
    ]

    return VStack(spacing: 16) {
        Section("Phone") {
            ChatComposerView(draft: .init(), tabs: [
                .init(
                    key: .chatSession(""),
                    kind: .chat,
                    title: "ew",
                    payload: .chatSession(sessionID: "", title: "")
                )
            ], viewModel: viewModel)
                .environment(\.userInterfaceIdiom, .phone)
        }
        
        Divider()

        Section("Desktop") {
            ChatComposerView(draft: .init(), tabs: [
                .init(
                    key: .chatSession(""),
                    kind: .chat,
                    title: "ew",
                    payload: .chatSession(sessionID: "", title: "")
                )
            ], viewModel: viewModel)
                .environment(\.userInterfaceIdiom, .desktop)
        }

        Divider()

        Section("Dictation") {
            DictationComposerBar(
                phase: .recording,
                levels: Array(0..<900).map { _ in CGFloat.random(in: 0...1) },
                elapsed: 0.2,
                stop: {}
            )
        }
    }
}

struct CustomMenuButtonStyle: MenuStyle {

    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Menu(configuration)
                .frame(width: 42, height: 42)
                .contentShape(.circle)
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)

            Icons.symbol(.add, size: theme.typography.heading)
                .foregroundColor(theme.colors.textPrimary)
                .allowsHitTesting(false)
        }
        .buttonBorderShape(.circle)
        .buttonSizing(.flexible)
        .backportGlassEffect(.regular.interactive(), in: .circle)
    }
}

private enum Constants {
    static let fieldHeight: CGFloat = 48
}
