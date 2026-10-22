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
struct ChatTranscriptRegion: View {
    let viewModel: ChatScreenViewModel
    let contentWidth: CGFloat
    let messagesTopInset: CGFloat
    let composerScrollInset: CGFloat
    let showsThinkingIndicator: Bool
    let isRunActive: Bool
    let runStatusLabel: String
    let runStatusDetails: String?

    var body: some View {
        ChatTranscriptPane(
            viewModel: viewModel,
            transcript: viewModel.transcript,
            isLoadingTranscript: viewModel.isLoadingTranscript,
            scrollToEndRequest: viewModel.transcriptScrollToEndRequest,
            contentWidth: contentWidth,
            messagesTopInset: messagesTopInset,
            composerScrollInset: composerScrollInset,
            showsThinkingIndicator: showsThinkingIndicator,
            isRunActive: isRunActive,
            runStatusLabel: runStatusLabel,
            runStatusDetails: runStatusDetails,
            workingTreeSourceControl: viewModel.workingTreeSourceControl,
            inputRequest: viewModel.activeInputRequest,
            isSubmittingInputResponse: viewModel.isSubmittingInputResponse,
            inputRequestErrorMessage: viewModel.inputRequestErrorMessage,
            providerSettingsRecoveryMessageIDs: viewModel.providerSettingsRecoveryMessageIDs,
            onSubmitInputResponse: viewModel.submitInputResponse,
            onCancelInputRequest: viewModel.cancelInputRequest,
            onForkFromMessage: viewModel.forkSession,
            onOpenProviderSettings: { viewModel.openSettings(.providers) },
            userBubbleAgentID: viewModel.isLongChat ? viewModel.selectedAgent?.id : nil,
            userBubblePaletteID: viewModel.selectedAgent?.pet?.visual?.paletteId
        )
        .id("\(viewModel.selectedAgent?.id ?? ""):\(viewModel.selectedSessionId ?? "")")
    }
}

@MainActor
struct ChatTranscriptLoadingView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ProgressView()
        .controlSize(.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Loading conversation")
        .accessibilityIdentifier("chat.transcript.loading")
    }
}

@MainActor
struct ChatEmptyChatRegion: View {
    let viewModel: ChatScreenViewModel
    let contentWidth: CGFloat
    let heroWidth: CGFloat
    let bottomClearance: CGFloat

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                ChatGreetingView(
                    projects: viewModel.projects,
                    selectedProjectId: viewModel.activeProjectIdForWorkspacePanel,
                    selectedProjectName: viewModel.activeProjectNameForWorkspacePanel,
                    onSelectPersonal: viewModel.pickPersonal,
                    onSelectProject: viewModel.pickProject,
                    onSelectPrompt: viewModel.useStarterPrompt
                )
                .frame(maxWidth: heroWidth)
                .padding(.horizontal, idiom == .phone ? theme.spacing.s : 0)
                .padding(.vertical, theme.spacing.m)
                .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - bottomClearance))
                .padding(.bottom, bottomClearance)
            }
        }

        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.dismissComposerFocus()
        }
    }
}
