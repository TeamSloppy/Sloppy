import Foundation
import SwiftUI
import SloppyClientCore

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct ChatTranscriptNativeItem: Identifiable, Equatable {
    enum Content: Equatable {
        case revealEarlier(count: Int)
        case historyLoading(isLoading: Bool, error: String?)
        case dateSeparator(Date)
        case entry(
            ChatTranscriptEntry,
            bottomSpacing: CGFloat,
            activeMessageIDs: Set<ChatMessage.ID>,
            providerRecoveryMessageIDs: Set<ChatMessage.ID>
        )
        case changeSummary(ProjectWorkingTreeSourceControlResponse)
        case thinking(label: String, details: String?)
        case inputRequest(
            request: ChatPlanInputRequest,
            isSubmitting: Bool,
            errorMessage: String?
        )
    }

    let id: String
    let content: Content
}

@MainActor
struct ChatNativeTranscriptView: View {
    let items: [ChatTranscriptNativeItem]
    let contentWidth: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat
    let scrollToEndRequest: Int
    let autoFollowAppendedItems: Bool
    let autoFollowChangingTail: Bool
    let scrollTarget: ChatTranscriptScrollTarget?
    let renderRevision: UInt
    var presentationRevision: UInt = 0
    let reduceMotion: Bool
    let onVisibleItemChange: @MainActor (String?) -> Void
    var onReachedTop: @MainActor () -> Void = {}
    let renderer: @MainActor (ChatTranscriptNativeItem) -> AnyView

    var body: some View {
        #if os(macOS)
        AppKitChatTranscriptCollection(
            items: items,
            contentWidth: contentWidth,
            topInset: topInset,
            bottomInset: bottomInset,
            scrollToEndRequest: scrollToEndRequest,
            autoFollowAppendedItems: autoFollowAppendedItems,
            autoFollowChangingTail: autoFollowChangingTail,
            scrollTarget: scrollTarget,
            renderRevision: renderRevision,
            presentationRevision: presentationRevision,
            reduceMotion: reduceMotion,
            onVisibleItemChange: onVisibleItemChange,
            onReachedTop: onReachedTop,
            renderer: renderer
        )
        #else
        UIKitChatTranscriptCollection(
            items: items,
            contentWidth: contentWidth,
            topInset: topInset,
            bottomInset: bottomInset,
            scrollToEndRequest: scrollToEndRequest,
            scrollTarget: scrollTarget,
            renderRevision: renderRevision,
            reduceMotion: reduceMotion,
            onVisibleItemChange: onVisibleItemChange,
            onReachedTop: onReachedTop,
            renderer: renderer
        )
        #endif
    }
}

/// Layout and programmatic scrolling must never trigger history downloads.
struct ChatHistoryScrollTrigger {
    private var didTrigger = false

    mutating func didScroll(distanceFromTop: CGFloat, isUserInitiated: Bool) -> Bool {
        if distanceFromTop > 120 { didTrigger = false }
        guard isUserInitiated, distanceFromTop <= 80, !didTrigger else { return false }
        didTrigger = true
        return true
    }
}
