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
public struct ChatComposerOverlay: View {
    public let viewModel: ChatScreenViewModel
    public let contentWidth: CGFloat
    public let composerBottomInset: CGFloat
    public let tabs: [WorkspaceTab]
    public let tabActions: ChatComposerTabActions?

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    public init(
        viewModel: ChatScreenViewModel,
        contentWidth: CGFloat,
        composerBottomInset: CGFloat,
        tabs: [WorkspaceTab],
        tabActions: ChatComposerTabActions?
    ) {
        self.viewModel = viewModel
        self.contentWidth = contentWidth
        self.composerBottomInset = composerBottomInset
        self.tabs = tabs
        self.tabActions = tabActions
    }

    public var body: some View {
        HStack {
            Spacer(minLength: 0)
            composerBar
#if os(visionOS)
                .padding3D(.front)
#endif
            Spacer(minLength: 0)
        }
        .padding(.horizontal, idiom == .phone ? theme.spacing.m : 0)
        .padding(.bottom, composerBottomInset)
        #if os(macOS)
        .background(alignment: .bottom) {
            ComposerBackdrop(
                height: (viewModel.composerPanelHeight ?? ChatComposerView.panelHeight)
                    + composerBottomInset + 40
            )
        }
        #endif
        .dropDestination(for: String.self) { items, _ in
            guard let encoded = items.first,
                  let payload = WorkspacePanelDragPayload.decode(from: encoded) else {
                return false
            }
            viewModel.attachProjectFileReference(
                projectId: payload.projectId,
                path: payload.path,
                type: payload.type
            )
            return true
        }
        .modifier(ChatAttachmentDropZone(viewModel: viewModel))
        .task(id: ObjectIdentifier(viewModel)) {
            viewModel.requestComposerFocus()
        }
    }

    @ViewBuilder
    private var composerBar: some View {
#if os(macOS)
        VStack(spacing: theme.spacing.s) {
            if !viewModel.composerSuggestions.isEmpty {
                ComposerSuggestionsView(
                    suggestions: viewModel.composerSuggestions,
                    selectedSuggestionID: viewModel.composerSuggestionSelection.selectedID,
                    select: viewModel.applyComposerSuggestion
                )
                .frame(maxWidth: maximumComposerWidth)
                .disabled(viewModel.activeInputRequest != nil)
            }
            composerControls
        }
#else
        composerControls
#endif
    }

    private var composerControls: some View {
        VStack(spacing: theme.spacing.s) {
            if let approval = viewModel.pendingToolApproval {
                ChatToolApprovalCard(
                    approval: approval,
                    isResolving: viewModel.isResolvingToolApproval,
                    errorMessage: viewModel.toolApprovalErrorMessage,
                    decide: viewModel.resolvePendingToolApproval
                )
                .frame(maxWidth: maximumComposerWidth)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if !viewModel.queuedMessages.isEmpty {
                ChatQueuedMessagesCard(
                    messages: viewModel.queuedMessages,
                    cancel: viewModel.cancelQueuedMessage
                )
                .frame(maxWidth: maximumComposerWidth)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

#if !os(macOS)
            if !viewModel.parallelAgents.agents.isEmpty {
                ChatWorkerActivityCard(viewModel: viewModel)
                    .frame(maxWidth: maximumComposerWidth)
            }
#endif

            ChatComposerView(
                draft: viewModel.composerDraft,
                tabs: tabs,
                viewModel: viewModel,
                tabActions: tabActions
            )
            .frame(maxWidth: maximumComposerWidth)

        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
            viewModel.updateComposerPanelHeight(height)
        }
        .animation(
            .easeInOut(duration: 0.18),
            value: viewModel.workingTreeSourceControl?.diff
        )
        .animation(.easeInOut(duration: 0.18), value: viewModel.pendingToolApproval?.id)
        .animation(.easeInOut(duration: 0.18), value: viewModel.queuedMessages.map(\.id))
    }

    private var maximumComposerWidth: CGFloat {
#if os(macOS)
        min(contentWidth, ChatComposerView.desktopPanelWidth)
#else
        contentWidth
#endif
    }
}
