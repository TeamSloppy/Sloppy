import Foundation
import Observation
import SwiftUI
import SloppyClientUI
import SloppyClientCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Observable
@MainActor
public final class ChatComposerDraft {
    public var references: [ChatComposerReference] = []

    public func registerReferences(_ references: [ChatComposerReference]) {
        for reference in references {
            self.references.removeAll { $0.rawText == reference.rawText }
            self.references.append(reference)
        }
    }

    public var text: String {
        didSet {
            if text != oldValue {
                selection = nil
            }
        }
    }
    public var selection: TextSelection?
    
    public init(text: String = "", selection: TextSelection? = nil) {
        self.text = text
        self.selection = selection
    }
}

public struct ChatComposerView: View {
#if os(macOS)
    public static let desktopPanelWidth: CGFloat = 900
#else
    public static let desktopPanelWidth: CGFloat = 800
#endif
    public static let panelWidth: CGFloat = 900
    public static let panelHeight: CGFloat = Constants.fieldHeight
    public static let phonePanelHeight: CGFloat = 56
    public static let expandedPhonePanelHeight: CGFloat = 196
    public static let attachmentStripHeight: CGFloat = 112
    private static let panelRadius: CGFloat = panelHeight / 2
    private static let expandedPhonePanelRadius: CGFloat = 28
    private static let phoneFieldHeight: CGFloat = 48
    static let phoneCircleSize: CGFloat = 36
    static let buttonSize: CGFloat = panelHeight
    private static let overviewGestureDistance: CGFloat = 220

    private let viewModel: ChatScreenViewModel
    @State private var isOverviewGestureActive = false
    @State private var imageToAnnotate: ChatComposerAttachment?
    let tabs: [WorkspaceTab]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme
    @Environment(\.chatComposerConnectionActions) private var connectionActions
    @Environment(\.mobileComposerAvailableHeight) private var mobileComposerAvailableHeight

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
        self.viewModel = viewModel
    }
    
    @ViewBuilder
    public var body: some View {
        Group {
            #if os(visionOS)
            regularBody
            #else
            GlassEffectContainer {
                regularBody
            }
            #endif
        }
        .sheet(item: $imageToAnnotate, onDismiss: viewModel.requestComposerFocus) { attachment in
            ChatImageAnnotationEditor(attachment: attachment) { annotations in
                viewModel.updateImageAnnotations(id: attachment.id, annotations: annotations)
            }
        }
    }
    
    private var usesDesktopComposer: Bool {
#if os(macOS)
        true
#elseif os(iOS)
        idiom != .phone
#else
        false
#endif
    }

    private var regularBody: some View {
        let c = theme.colors
        let sp = theme.spacing
#if !os(macOS)
        let autocompleteGap = theme.spacing.s
#endif

        return VStack(spacing: sp.s) {
            if !usesDesktopComposer {
                if !viewModel.composerQuotes.isEmpty {
                    ChatComposerQuoteStrip(
                        quotes: viewModel.composerQuotes,
                        update: viewModel.updateComposerQuote,
                        remove: viewModel.removeComposerQuote
                    )
                }
                if !viewModel.composerAttachments.isEmpty {
                    ChatComposerAttachmentStrip(
                        attachments: viewModel.composerAttachments,
                        annotate: { imageToAnnotate = $0 },
                        remove: viewModel.removeComposerAttachment
                    )
                    .frame(height: Self.attachmentStripHeight)
                }
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
                    if usesDesktopComposer {
#if os(macOS)
                        desktopComposer
#else
                        HStack(alignment: .bottom, spacing: sp.s) {
                            ComposerAddMenu(
                                viewModel: viewModel,
                                supportsReasoningEffort: selectedModelSupportsReasoningEffort
                            )

                            desktopComposerInputSurface

                            MobileComposerCircleButton(
                                symbol: trailingActionSymbol,
                                foregroundColor: trailingActionForegroundColor,
                                fillColor: c.surfaceRaised,
                                action: handleTrailingAction
                            )
                            .accessibilityLabel(trailingActionLabel)
                            .help(trailingActionLabel)
                        }
#endif
                    } else {
#if !os(macOS)
                        mobileComposer
#endif
                    }
                }
            }
            .frame(minHeight: currentPanelHeight, alignment: .bottom)
#if !os(macOS)
            ChatApprovalModePicker(viewModel: viewModel)
                .padding(.horizontal, sp.m)
#endif
        }
        .environment(viewModel)
        .padding(.horizontal, sp.s)
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: currentPanelHeight,
            alignment: .leading
        )
        .frame(maxWidth: maximumPanelWidth)
#if !os(macOS)
        .overlay(alignment: .top) {
            if !viewModel.composerSuggestions.isEmpty {
                ComposerSuggestionsView(
                    suggestions: viewModel.composerSuggestions,
                    selectedSuggestionID: viewModel.composerSuggestionSelection.selectedID,
                    select: viewModel.applyComposerSuggestion
                )
                .offset(y: -(ComposerSuggestionsView.panelHeight + autocompleteGap))
            }
        }
#endif
        .disabled(viewModel.activeInputRequest != nil)
        .accessibilityHint(
            viewModel.activeInputRequest == nil
                ? ""
                : "Answer the agent’s question before sending another message."
        )
        .onDisappear { viewModel.updateMobileComposerExpansion(false) }
        .animation(
            reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.08),
            value: viewModel.isMobileComposerExpanded
        )
    }

    private var maximumPanelWidth: CGFloat {
        usesDesktopComposer ? Self.desktopPanelWidth : Self.panelWidth
    }

    private var desktopComposerInputSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.composerQuotes.isEmpty {
                ChatComposerQuoteStrip(
                    quotes: viewModel.composerQuotes,
                    update: viewModel.updateComposerQuote,
                    remove: viewModel.removeComposerQuote,
                    edit: viewModel.editComposerQuote,
                    finish: viewModel.finishComposerQuoteEditing
                )
                .padding(.horizontal, theme.spacing.s)
                .padding(.top, theme.spacing.s)
            }

            if !viewModel.composerAttachments.isEmpty {
                ChatComposerAttachmentStrip(
                    attachments: viewModel.composerAttachments,
                    annotate: { imageToAnnotate = $0 },
                    remove: viewModel.removeComposerAttachment
                )
                .frame(height: Self.attachmentStripHeight)
                .padding(.horizontal, theme.spacing.s)
                .padding(.top, theme.spacing.s)
            }

#if os(macOS)
            HStack(alignment: .bottom, spacing: 0) {
                ComposerAddMenu(
                    viewModel: viewModel,
                    supportsReasoningEffort: selectedModelSupportsReasoningEffort
                )
                .padding(.bottom, 6)

                ChatTextField(draft: draft, submit: submit)

                desktopTrailingAction
                    .padding(.bottom, 6)
            }
            .padding(.horizontal, theme.spacing.s)
#else
            HStack(alignment: .bottom, spacing: 0) {
                ChatTextField(
                    draft: draft,
                    submit: submit
                )

                HStack(spacing: theme.spacing.s) {
                    ComposerContextUsageView(usage: viewModel.contextUsage, turnUsage: viewModel.contextTokenUsage)

                    ComposerOptionsMenuView(
                        selectedModelId: viewModel.selectedModelId,
                        models: viewModel.modelPickerOptions,
                        selectedEffort: viewModel.selectedReasoningEffort,
                        supportsReasoningEffort: selectedModelSupportsReasoningEffort,
                        selectedAgent: viewModel.selectedAgent,
                        agents: viewModel.agents,
                        onSelectModel: viewModel.pickModel,
                        onSelectEffort: viewModel.pickReasoningEffort,
                        onSelectAgent: viewModel.pickAgent,
                        onRefreshModels: viewModel.refreshAvailableModels,
                        onEditModels: { viewModel.openSettings(.providers) }
                    )
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, theme.spacing.s)
                .padding(.bottom, theme.spacing.s)
            }
#endif
        }
#if os(macOS)
        .fixedSize(horizontal: false, vertical: true)
        .background(theme.colors.surfaceGlow, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.composer.input-surface")
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(theme.colors.borderBold, lineWidth: 1)
                .allowsHitTesting(false)
        }
#else
        .clipShape(RoundedRectangle(cornerRadius: Self.panelRadius, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Self.panelRadius, style: .continuous))
#endif
    }

#if os(macOS)
    private var desktopComposer: some View {
        VStack(spacing: theme.spacing.s) {
            desktopComposerInputSurface
            HStack(spacing: theme.spacing.s) {
                desktopServerPicker
                ChatApprovalModePicker(viewModel: viewModel)
                Spacer(minLength: theme.spacing.s)
                desktopModelPicker.layoutPriority(1)
                ComposerContextUsageView(usage: viewModel.contextUsage, turnUsage: viewModel.contextTokenUsage)
            }
            .frame(minHeight: 30)
            .padding(.horizontal, 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chat.composer.settings")
        }
    }

    private var desktopTrailingAction: some View {
        let isPrimary = !trimmedDraftText.isEmpty || !viewModel.composerAttachments.isEmpty
            || !viewModel.composerQuotes.isEmpty || viewModel.shouldShowStopButton
        return Button(action: handleTrailingAction) {
            Icons.symbol(trailingActionSymbol, size: 18)
                .foregroundStyle(isPrimary ? theme.colors.background : theme.colors.textSecondary)
                .frame(width: 36, height: 36)
                .background(isPrimary ? theme.colors.textPrimary : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(trailingActionLabel)
        .accessibilityIdentifier("chat.composer.trailing-action")
        .help(trailingActionLabel)
    }
#endif

    private var desktopServerPicker: some View {
        let endpoint = viewModel.sessionEndpoint
        let title = connectionActions?.instances.first(where: { $0.endpoint == endpoint })?.displayName
            ?? endpoint.coordinatorBaseURL.host ?? "Server"
        return Menu {
            ForEach(connectionActions?.instances ?? []) { instance in
                Button { connectionActions?.selectInstance(instance) } label: {
                    Label(instance.displayName, systemImage: instance.endpoint == endpoint ? "checkmark" : "desktopcomputer")
                }
            }
        } label: {
            Label(title, systemImage: "desktopcomputer")
                .font(.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 180, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .help(title)
        .disabled(connectionActions?.instances.isEmpty ?? true)
        .accessibilityIdentifier("chat.composer.server-picker")
    }

    private var desktopModelPicker: some View {
        ComposerOptionsMenuView(
            selectedModelId: viewModel.selectedModelId,
            models: viewModel.modelPickerOptions,
            selectedEffort: viewModel.selectedReasoningEffort,
            supportsReasoningEffort: selectedModelSupportsReasoningEffort,
            selectedAgent: viewModel.selectedAgent,
            agents: viewModel.agents,
            onSelectModel: viewModel.pickModel,
            onSelectEffort: viewModel.pickReasoningEffort,
            onSelectAgent: viewModel.pickAgent,
            onRefreshModels: viewModel.refreshAvailableModels,
            onEditModels: { viewModel.openSettings(.providers) }
        )
    }

    #if !os(macOS)
    private var mobileComposer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isExpandedPhoneLayout {
                Button {
                    viewModel.dismissComposerFocus()
                } label: {
                    Capsule()
                        .fill(theme.colors.textMuted.opacity(0.35 as CGFloat))
                        .frame(width: 36, height: 5)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse composer")
                .simultaneousGesture(phoneTabGesture)

                HStack(spacing: theme.spacing.m) {
                    MobileComposerAgentPicker(
                        selectedAgent: viewModel.selectedAgent,
                        agents: viewModel.agents,
                        selectedProjectID: viewModel.activeProjectIdForWorkspacePanel,
                        selectedProjectName: viewModel.activeProjectNameForWorkspacePanel,
                        projects: viewModel.projects,
                        onSelectAgent: viewModel.pickAgent,
                        onSelectProject: viewModel.pickProject,
                        onSelectPersonal: viewModel.pickPersonal
                    )
                    MobileComposerServerPicker(endpoint: viewModel.sessionEndpoint)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, theme.spacing.m)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: theme.spacing.s) {
                if !isExpandedPhoneLayout {
                    composerAddMenu
                }

                textFieldContainer(showsGlassBackground: false)
                    .frame(
                        minHeight: Self.phoneFieldHeight,
                        maxHeight: isExpandedPhoneLayout ? .infinity : Self.phoneFieldHeight,
                        alignment: .top
                    )

                if !isExpandedPhoneLayout {
                    trailingActionButton
                }
            }
            .padding(.horizontal, isExpandedPhoneLayout ? theme.spacing.m : theme.spacing.s)

            if isExpandedPhoneLayout {
                HStack(spacing: theme.spacing.s) {
                    composerAddMenu

                    MobileComposerModelPicker(
                        selectedModelId: viewModel.selectedModelId,
                        models: viewModel.modelPickerOptions,
                        selectedEffort: viewModel.selectedReasoningEffort,
                        supportsReasoningEffort: selectedModelSupportsReasoningEffort,
                        onSelectModel: viewModel.pickModel,
                        onSelectEffort: viewModel.pickReasoningEffort
                    )

                    Spacer(minLength: 0)

                    trailingActionButton
                }
                .padding(theme.spacing.s)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(height: currentPanelHeight)
        .highPriorityGesture(phoneTabGesture, including: tabActions != nil || isExpandedPhoneLayout ? .all : .subviews)
        .background(
            theme.colors.surfaceRaised.opacity(0.65 as CGFloat),
            in: RoundedRectangle(cornerRadius: isExpandedPhoneLayout ? Self.expandedPhonePanelRadius : Self.phonePanelHeight / 2)
        )
        .backportGlassEffect(
            .regular.tint(theme.colors.surfaceRaised.opacity(0.3 as CGFloat)).interactive(),
            in: RoundedRectangle(
                cornerRadius: isExpandedPhoneLayout ? Self.expandedPhonePanelRadius : Self.phonePanelHeight / 2,
                style: .continuous
            )
        )
        .accessibilityIdentifier(
            isExpandedPhoneLayout
                ? "chat.composer.expanded"
                : "chat.composer.compact"
        )
    }

    private var composerAddMenu: some View {
        ComposerAddMenu(
            viewModel: viewModel,
            supportsReasoningEffort: selectedModelSupportsReasoningEffort,
            tabActions: tabActions
        )
    }

    private var trailingActionButton: some View {
        MobileComposerCircleButton(
            symbol: trailingActionSymbol,
            foregroundColor: trailingActionForegroundColor,
            fillColor: theme.colors.surfaceRaised,
            action: handleTrailingAction
        )
        .accessibilityLabel(trailingActionLabel)
        .help(trailingActionLabel)
    }
    #endif

    @ViewBuilder
    private func textFieldContainer(showsGlassBackground: Bool) -> some View {
        let field = ChatTextField(
            draft: draft,
            submit: submit,
            onFocusChanged: updatePhoneComposerExpansion
        )
        if showsGlassBackground {
            field.backportGlassEffect(.regular.interactive(), in: Capsule())
        } else {
            field
        }
    }

    private var currentPanelHeight: CGFloat {
        if isExpandedPhoneLayout {
            return viewModel.isMobileComposerFullscreen
                ? max(Self.expandedPhonePanelHeight, mobileComposerAvailableHeight)
                : Self.expandedPhonePanelHeight
        }
        return Self.panelHeight(for: idiom)
    }

    private var isExpandedPhoneLayout: Bool {
        idiom == .phone && viewModel.isMobileComposerExpanded
    }

    private func updatePhoneComposerExpansion(_ isFocused: Bool) {
        guard idiom == .phone else { return }
        viewModel.updateMobileComposerExpansion(isFocused)
    }

    private var trimmedDraftText: String {
        draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trailingActionSymbol: MaterialSymbol {
        if !trimmedDraftText.isEmpty || !viewModel.composerAttachments.isEmpty
            || !viewModel.composerQuotes.isEmpty {
            return viewModel.willQueueMessage ? .timer : .arrowUpward
        }

        return viewModel.shouldShowStopButton ? .stop : .microphone
    }

    private var trailingActionLabel: String {
        if !trimmedDraftText.isEmpty || !viewModel.composerAttachments.isEmpty
            || !viewModel.composerQuotes.isEmpty {
            return viewModel.willQueueMessage ? "Queue message after current turn" : "Send message"
        }
        return viewModel.shouldShowStopButton ? "Stop agent" : "Start dictation"
    }

    private var trailingActionForegroundColor: Color {
        if viewModel.shouldShowStopButton,
           trimmedDraftText.isEmpty,
           viewModel.composerAttachments.isEmpty,
           viewModel.composerQuotes.isEmpty {
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
                guard !isExpandedPhoneLayout, tabActions != nil else { return }
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

                if isExpandedPhoneLayout {
                    if vertical < -40, abs(vertical) > abs(horizontal) {
                        viewModel.expandMobileComposerFullscreen()
                    } else if vertical > 40, vertical > abs(horizontal) {
                        viewModel.dismissComposerFocus()
                    }
                    return
                }

                if isOverviewGestureActive {
                    let progress = (-vertical / Self.overviewGestureDistance).clamp(0, 1)
                    let velocity = -(value.predictedEndTranslation.height - value.translation.height)
                    tabActions?.endOverviewGesture(progress, velocity)
                    isOverviewGestureActive = false
                } else if vertical < -56, abs(vertical) > abs(horizontal) {
                    tabActions?.showOverview()
                } else if vertical > 40, vertical > abs(horizontal), isExpandedPhoneLayout {
                    viewModel.dismissComposerFocus()
                } else if abs(horizontal) > 56, abs(horizontal) > abs(vertical) {
                    tabActions?.selectAdjacentTab(horizontal < 0 ? 1 : -1)
                }
            }
    }
    
    private func submit() {
        let trimmed = trimmedDraftText
        guard (!trimmed.isEmpty || !viewModel.composerAttachments.isEmpty
            || !viewModel.composerQuotes.isEmpty), viewModel.canSubmitMessage else { return }
        if viewModel.sendMessage(content: trimmed) {
            connectionActions?.didSubmit(viewModel)
        }
    }

    private func handleTrailingAction() {
        guard viewModel.activeInputRequest == nil else { return }
        let hasMessage = !trimmedDraftText.isEmpty || !viewModel.composerAttachments.isEmpty
            || !viewModel.composerQuotes.isEmpty
        if hasMessage {
            submit()
        } else if viewModel.shouldShowStopButton {
            viewModel.stopActiveRun()
        } else {
            viewModel.startDictation()
        }
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

enum Constants {
    static let fieldHeight: CGFloat = 48
    static let fieldHorizontalPadding: CGFloat = fieldHeight / 2
    static let editorMinimumHeight: CGFloat = 31
    static let editorContentHorizontalInset: CGFloat = 8
    static let editorNativeTextContainerInset: CGFloat = 5
    static let editorContentVerticalInset: CGFloat = 7
    static let maximumVisibleLines = 6
    static let modelPickerRowHeight: CGFloat = 30
}
