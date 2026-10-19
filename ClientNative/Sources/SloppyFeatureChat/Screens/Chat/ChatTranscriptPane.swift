import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI
import UniformTypeIdentifiers
#if canImport(PhotosUI) && !os(macOS)
import PhotosUI
#endif
#if os(iOS)
import UIKit
#endif

@MainActor
struct ChatTranscriptPane: View {
    let viewModel: ChatScreenViewModel
    let transcript: ChatTranscriptState
    let isLoadingTranscript: Bool
    let scrollToEndRequest: Int
    let contentWidth: CGFloat
    let messagesTopInset: CGFloat
    let composerScrollInset: CGFloat
    let showsThinkingIndicator: Bool
    let isRunActive: Bool
    let runStatusLabel: String
    let runStatusDetails: String?
    let workingTreeSourceControl: ProjectWorkingTreeSourceControlResponse?
    let inputRequest: ChatPlanInputRequest?
    let isSubmittingInputResponse: Bool
    let inputRequestErrorMessage: String?
    let providerSettingsRecoveryMessageIDs: Set<String>
    let onSubmitInputResponse: @MainActor ([ChatPlanInputAnswer]) -> Void
    let onCancelInputRequest: @MainActor () -> Void
    let onForkFromMessage: @MainActor (ChatMessage) -> Void
    let onOpenProviderSettings: @MainActor () -> Void
    var agentAvatarID: String? = nil
    var agentPaletteID: String? = nil
    var userBubbleAgentID: String? = nil
    var userBubblePaletteID: String? = nil

    @Environment(\.theme) private var theme
    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.chatTextSelectionActions) private var textSelectionActions
    @Environment(\.chatFileOpenHandler) private var fileOpenHandler
    @State private var visibleTranscriptItemID: String?
    @State private var scrollTarget: ChatTranscriptScrollTarget?
    @State private var scrollTargetRequestID: UInt = 0

    var body: some View {
        GeometryReader { proxy in
            ChatNativeTranscriptView(
                items: nativeItems,
                contentWidth: contentWidth,
                topInset: viewModel.hasEarlierTranscriptMessages ? 0 : messagesTopInset,
                bottomInset: composerScrollInset,
                scrollToEndRequest: scrollToEndRequest,
                autoFollowAppendedItems: !isLoadingTranscript,
                autoFollowChangingTail: isRunActive && !isLoadingTranscript,
                scrollTarget: scrollTarget,
                renderRevision: nativeRenderRevision,
                presentationRevision: nativePresentationRevision,
                reduceMotion: reduceMotion,
                onVisibleItemChange: { itemID in
                    visibleTranscriptItemID = itemID
                },
                onReachedTop: viewModel.loadEarlierMessages,
                renderer: renderNativeItem
            )
#if os(macOS)
            .overlay(alignment: .leading) {
                if !conversationWaypoints.isEmpty,
                   proxy.size.width >= contentWidth + 2 * (30 + theme.spacing.m) {
                    ChatConversationNavigator(
                        waypoints: conversationWaypoints,
                        activeWaypointID: activeWaypointID,
                        onSelect: scroll(to:)
                    )
                    .padding(.leading, theme.spacing.m)
                }
            }
#endif
        }
    }

    private var conversationWaypoints: [ChatConversationWaypoint] {
        ChatConversationWaypoint.build(from: transcript.messages)
    }

    private var activeWaypointID: ChatConversationWaypoint.ID? {
        guard let visibleTranscriptItemID,
              let visibleIndex = nativeItems.firstIndex(where: { $0.id == visibleTranscriptItemID }) else {
            return conversationWaypoints.last?.id
        }

        return conversationWaypoints.last { waypoint in
            guard let waypointIndex = nativeItems.firstIndex(where: { $0.id == waypoint.targetItemID }) else {
                return false
            }
            return waypointIndex <= visibleIndex
        }?.id ?? conversationWaypoints.first?.id
    }

    private func scroll(to waypoint: ChatConversationWaypoint) {
        scrollTargetRequestID &+= 1
        scrollTarget = ChatTranscriptScrollTarget(
            itemID: waypoint.targetItemID,
            requestID: scrollTargetRequestID
        )
    }

    private var nativeItems: [ChatTranscriptNativeItem] {
        let activeRunMessageIDs = ChatActiveRunMessages.messageIDs(
            in: transcript.messages,
            isRunActive: isRunActive
        )
        var items: [ChatTranscriptNativeItem] = []

        if viewModel.hasEarlierTranscriptMessages || viewModel.isLoadingEarlierMessages || viewModel.transcriptLoadError != nil {
            items.append(ChatTranscriptNativeItem(
                id: "reveal-earlier",
                content: .historyLoading(
                    isLoading: viewModel.isLoadingEarlierMessages,
                    error: viewModel.transcriptLoadError
                )
            ))
        }

        var previousEntryDate: Date?
        for (index, entry) in transcript.entries.enumerated() {
            if let previousEntryDate,
               ChatTranscriptDateSeparators.shouldInsert(
                   between: previousEntryDate,
                   and: entry.createdAt
               ) {
                items.append(ChatTranscriptNativeItem(
                    id: "date-separator:\(entry.id)",
                    content: .dateSeparator(entry.createdAt)
                ))
            }

            let bottomSpacing: CGFloat
            if index < transcript.entries.index(before: transcript.entries.endIndex) {
                bottomSpacing = ChatTranscriptGrouping.usesCompactSpacing(
                    between: entry,
                    and: transcript.entries[index + 1]
                ) ? theme.spacing.s : theme.spacing.xl
            } else {
                bottomSpacing = 0
            }

            let entryMessageIDs: Set<ChatMessage.ID>
            switch entry {
            case .message(let message):
                entryMessageIDs = activeRunMessageIDs.contains(message.id) ? [message.id] : []
            case .systemGroup(let messages):
                entryMessageIDs = Set(messages.map(\.id)).intersection(activeRunMessageIDs)
            }
            items.append(ChatTranscriptNativeItem(
                id: "entry:\(entry.id)",
                content: .entry(
                    entry,
                    bottomSpacing: bottomSpacing,
                    activeMessageIDs: entryMessageIDs,
                    providerRecoveryMessageIDs: entryProviderRecoveryMessageIDs(entry)
                )
            ))
            previousEntryDate = entry.createdAt
        }

        if let workingTreeSourceControl {
            items.append(ChatTranscriptNativeItem(
                id: "change-summary",
                content: .changeSummary(workingTreeSourceControl)
            ))
        }
        if showsThinkingIndicator {
            items.append(ChatTranscriptNativeItem(
                id: "thinking-indicator",
                content: .thinking(label: runStatusLabel, details: runStatusDetails)
            ))
        }
        if let inputRequest {
            items.append(ChatTranscriptNativeItem(
                id: "input-request:\(inputRequest.id)",
                content: .inputRequest(
                    request: inputRequest,
                    isSubmitting: isSubmittingInputResponse,
                    errorMessage: inputRequestErrorMessage
                )
            ))
        }
        return items
    }

    private var nativeRenderRevision: UInt {
        var hasher = Hasher()
        hasher.combine(transcript.renderRevision)
        hasher.combine(isRunActive)
        hasher.combine(showsThinkingIndicator)
        hasher.combine(runStatusLabel)
        hasher.combine(runStatusDetails)
        hasher.combine(workingTreeSourceControl?.diff)
        hasher.combine(inputRequest?.id)
        hasher.combine(isSubmittingInputResponse)
        hasher.combine(inputRequestErrorMessage)
        hasher.combine(nativePresentationRevision)
        return UInt(bitPattern: hasher.finalize())
    }

    private var nativePresentationRevision: UInt {
        var hasher = Hasher()
        hasher.combine(agentAvatarID)
        hasher.combine(agentPaletteID)
        hasher.combine(userBubbleAgentID)
        hasher.combine(userBubblePaletteID)
#if os(macOS)
        for quote in viewModel.composerQuotes where quote.source != nil {
            hasher.combine(quote.id)
        }
#endif
        return UInt(bitPattern: hasher.finalize())
    }

    private func renderNativeItem(_ item: ChatTranscriptNativeItem) -> AnyView {
        let rendered: AnyView
        switch item.content {
        case .revealEarlier(let count):
            rendered = AnyView(Text("\(count) earlier messages"))
        case .historyLoading(let isLoading, let error):
            rendered = AnyView(
                VStack(spacing: theme.spacing.s) {
                    if isLoading {
                        ProgressView().controlSize(.small)
                            .accessibilityLabel("Loading earlier messages")
                            .accessibilityIdentifier("chat.history.loading")
                    } else if let error {
                        Text(error).font(.caption).foregroundStyle(theme.colors.textMuted)
                        Button("Retry", action: viewModel.retryTranscriptLoad)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 24)
                .padding(.top, messagesTopInset)
                .padding(.bottom, theme.spacing.m)
            )
        case .dateSeparator(let date):
            rendered = AnyView(
                Text(ChatTranscriptDateSeparators.title(for: date))
                    .font(.system(size: theme.typography.caption, weight: .medium))
                    .foregroundColor(theme.colors.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, theme.spacing.xl)
                    .accessibilityLabel("Conversation continued \(ChatTranscriptDateSeparators.title(for: date))")
            )
        case .entry(
            let entry,
            let bottomSpacing,
            let activeRunMessageIDs,
            let recoveryMessageIDs
        ):
            switch entry {
            case .message(let message):
                rendered = AnyView(
                    HStack(alignment: .top, spacing: 8) {
                        if message.role == .assistant, let agentAvatarID {
                            AgentBotAvatar(
                                agentID: agentAvatarID,
                                size: 28,
                                paletteID: agentPaletteID,
                                emotion: isRunActive ? .working : .idle,
                                isAnimated: isRunActive
                            )
                        }
                        ChatBubbleView(
                            message: message,
                            isActivelyWorking: activeRunMessageIDs.contains(message.id),
                            userBubbleTint: userBubbleAgentID.map {
                                Color.fromHex(AgentBotIdentity.palette(for: $0, paletteID: userBubblePaletteID).body)
                            },
                            onOpenProviderSettings: recoveryMessageIDs.contains(message.id)
                                ? onOpenProviderSettings
                                : nil,
                            onForkFromMessage: onForkFromMessage
                        )
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .padding(.bottom, bottomSpacing)
                )
            case .systemGroup(let messages):
                rendered = AnyView(
                    VStack(alignment: .leading, spacing: theme.spacing.s) {
                        ForEach(messages.filter { $0.longChatTask != nil || $0.workerSession != nil }) { message in
                            if let event = message.longChatTask {
                                LongChatWorkerCard(event: event, viewModel: viewModel)
                            } else if let child = message.workerSession {
                                ChatWorkerSessionCard(child: child, viewModel: viewModel)
                            }
                        }
                        if !messages.filter({ $0.longChatTask == nil && $0.workerSession == nil }).isEmpty {
                            ChatSystemMessageGroupView(messages: messages.filter { $0.longChatTask == nil && $0.workerSession == nil }, activeRunMessageIDs: activeRunMessageIDs)
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .padding(.bottom, bottomSpacing)
                )
            }
        case .changeSummary(let sourceControl):
            rendered = AnyView(
                ChatChangeSummaryView(sourceControl: sourceControl)
                    .padding(.top, theme.spacing.m)
            )
        case .thinking(let label, let details):
            rendered = AnyView(
                ChatThinkingIndicator(label: label, details: details)
                    .padding(.top, theme.spacing.s)
            )
        case .inputRequest(let request, let isSubmitting, let errorMessage):
            rendered = AnyView(
                ChatInputRequestView(
                    request: request,
                    isSubmitting: isSubmitting,
                    errorMessage: errorMessage,
                    onSubmit: onSubmitInputResponse,
                    onCancel: onCancelInputRequest
                )
                .padding(.top, theme.spacing.m)
            )
        }
        return AnyView(
            rendered
                // Native transcript rows have separate hosting roots and do not
                // inherit the screen's observable environment automatically.
                .environment(viewModel)
                .environment(\.theme, theme)
                .environment(\.userInterfaceIdiom, idiom)
                .modifier(ChatFileLinkModifier(viewModel: viewModel))
                .environment(\.chatAttachmentPreviewContext, viewModel.attachmentPreviewContext)
                .environment(\.chatFileOpenHandler, fileOpenHandler)
                .environment(\.chatTextSelectionActions, textSelectionActions)
        )
    }

    private func entryProviderRecoveryMessageIDs(
        _ entry: ChatTranscriptEntry
    ) -> Set<ChatMessage.ID> {
        switch entry {
        case .message(let message):
            return providerSettingsRecoveryMessageIDs.contains(message.id) ? [message.id] : []
        case .systemGroup(let messages):
            return Set(messages.map(\.id)).intersection(providerSettingsRecoveryMessageIDs)
        }
    }

}
