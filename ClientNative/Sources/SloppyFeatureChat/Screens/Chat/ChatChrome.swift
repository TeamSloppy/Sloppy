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
struct ChatChrome: View {
    let viewModel: ChatScreenViewModel
    let connectionMonitor: ConnectionMonitor
    let rootSafeAreaInsets: EdgeInsets
    let composerTabActions: ChatComposerTabActions?

    @Environment(\.isChatComposerInset) private var isChatComposerInset
    @Environment(\.safeAreaInsets) private var safeAreaInsets
    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if idiom == .phone {
                chromeLayout(contentWidth: phoneContentWidth)
            } else {
                GeometryReader { proxy in
                    chromeLayout(contentWidth: contentWidth(for: proxy.size.width))
                }
            }
        }
    }

    private func chromeLayout(contentWidth: CGFloat) -> some View {
        let heroWidth = heroWidth(for: contentWidth)

        return ZStack(alignment: .bottom) {
            if viewModel.isLoadingTranscript, viewModel.transcript.isEmpty {
                ChatTranscriptLoadingView()
            } else if viewModel.transcript.isEmpty, let error = viewModel.transcriptLoadError {
                VStack(spacing: theme.spacing.s) {
                    Text(error).font(.caption).foregroundStyle(theme.colors.textMuted)
                    Button("Retry", action: viewModel.retryTranscriptLoad)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.transcript.isEmpty, viewModel.activeInputRequest == nil {
                ChatEmptyChatRegion(
                    viewModel: viewModel,
                    contentWidth: contentWidth,
                    heroWidth: heroWidth,
                    bottomClearance: composerScrollInset
                )
#if os(macOS)
                .background {
                    ChatASCIIBackground(protectedWidth: heroWidth)
                }
#endif
            } else {
                ChatTranscriptRegion(
                    viewModel: viewModel,
                    contentWidth: contentWidth,
                    messagesTopInset: messagesTopInset,
                    composerScrollInset: composerScrollInset,
                    showsThinkingIndicator: showsThinkingIndicator,
                    isRunActive: viewModel.isAwaitingAgentResponse || viewModel.isStopping,
                    runStatusLabel: viewModel.activeRunStatusLabel,
                    runStatusDetails: viewModel.activeRunStatusDetails
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    if viewModel.isLoadingTranscript {
                        ProgressView().controlSize(.small)
                            .padding(.top, messagesTopInset)
                            .accessibilityLabel("Loading conversation")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#if os(macOS)
        .overlay(alignment: .bottomTrailing) {
            if let activity = viewModel.computerUseActivity,
               !viewModel.isComputerUsePreviewHidden {
                ChatComputerUsePictureInPictureView(
                    activity: activity,
                    onHide: viewModel.hideComputerUsePreview
                )
                .padding(.trailing, theme.spacing.l)
                .padding(.bottom, composerScrollInset + theme.spacing.m)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.24), value: viewModel.computerUseActivity)
        .animation(.snappy(duration: 0.2), value: viewModel.isComputerUsePreviewHidden)
#endif
//        .overlay(alignment: .topLeading) {
//            if idiom != .phone {
//                ChatSessionContextBar(viewModel: viewModel)
//                    .padding(.horizontal, theme.spacing.m)
//                    .padding(.top, theme.spacing.s)
//            }
//        }
    }

    private func contentWidth(for availableWidth: CGFloat) -> CGFloat {
        let horizontalInset = idiom == .phone ? theme.spacing.s * 2 : theme.spacing.l * 2
#if os(macOS)
        return max(0, min(ChatComposerView.desktopPanelWidth - theme.spacing.s * 2, availableWidth - horizontalInset))
#else
        return max(0, min(chatContentWidth, availableWidth - horizontalInset))
#endif
    }

    private func heroWidth(for contentWidth: CGFloat) -> CGFloat {
        min(contentWidth, chatHeroWidth)
    }

    private var pickerWidth: CGFloat {
        if idiom == .phone {
            return max(280, min(320, screenPointWidth - theme.spacing.m * 2))
        }
        return 320
    }

    private var phoneContentWidth: CGFloat {
        let available = max(0, screenPointWidth - rootSafeAreaInsets.leading - rootSafeAreaInsets.trailing)
        return max(0, available - theme.spacing.s * 2)
    }

    private var overlayTopInset: CGFloat {
        ChatOverlayLayout.pickerTopInset(
            isPhone: idiom == .phone,
            rootSafeAreaTop: rootSafeAreaInsets.top,
            effectiveSafeAreaTop: safeAreaInsets.top
        )
    }

    private var composerScrollInset: CGFloat {
        if isChatComposerInset {
            return (viewModel.composerPanelHeight ?? ChatComposerView.phonePanelHeight)
                + theme.spacing.s + composerScrollGap
        }
        let fallbackHeight = ChatComposerView.panelHeight(for: idiom)
            + (viewModel.composerAttachments.isEmpty
                ? 0
                : ChatComposerView.attachmentStripHeight + theme.spacing.s)
        return (viewModel.composerPanelHeight ?? fallbackHeight) + composerBottomInset + composerScrollGap
    }

    private var composerBottomInset: CGFloat {
        guard idiom == .phone else {
            return theme.spacing.m
        }

        return ChatComposerKeyboardLayout.phoneBottomInset(
            rootSafeAreaBottom: rootSafeAreaInsets.bottom,
            effectiveSafeAreaBottom: safeAreaInsets.bottom,
            normalMinimumSpacing: theme.spacing.s,
            keyboardSpacing: theme.spacing.s
        )
    }

    private var messagesTopInset: CGFloat {
        idiom == .phone ? theme.spacing.s : theme.spacing.l
    }

    private var composerScrollGap: CGFloat {
        idiom == .phone ? theme.spacing.l : theme.spacing.xxl + theme.spacing.l
    }

    private var showsThinkingIndicator: Bool {
        guard viewModel.isAwaitingAgentResponse else { return false }
        let messages = viewModel.transcript.messages
        guard let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) else {
            return true
        }
        let nextIndex = messages.index(after: lastUserIndex)
        guard nextIndex < messages.endIndex else { return true }
        return !messages[nextIndex...].contains(where: { $0.role != .user })
    }

    private var screenPointWidth: CGFloat {
        guard let screen = Screen.main else {
            return 390
        }
        return max(320, screen.size.width)
    }
}

@MainActor
struct ChatSessionContextBar: View {
    let viewModel: ChatScreenViewModel

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            HStack(spacing: theme.spacing.s) {
                Image(systemName: viewModel.selectedSessionId == nil ? "square.and.pencil" : "bubble.left.and.text.bubble.right")
                Text(viewModel.activeSessionTitle)
                    .lineLimit(1)
                    .contextMenu {
                        Button("Rename Chat…", systemImage: "pencil") { viewModel.requestRenameActiveSession() }
                            .disabled(viewModel.selectedSessionId == nil)
                    }
                if let sessionId = viewModel.selectedSessionId {
                    Text(String(sessionId.prefix(8)))
                        .foregroundColor(theme.colors.textMuted)
                        .monospaced()
                }
            }
            .font(.system(size: theme.typography.caption, weight: .medium))
            .foregroundColor(theme.colors.textSecondary)

            if let error = viewModel.sendErrorMessage {
                Text(error)
                    .font(.system(size: theme.typography.caption))
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, theme.spacing.m)
        .padding(.vertical, theme.spacing.s)
        .background(theme.colors.surfaceRaised.opacity(0.9 as CGFloat), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current session: \(viewModel.activeSessionTitle)")
    }
}

struct ChatComposerKeyboardLayout {
    private static let keyboardSafeAreaEpsilon: CGFloat = 1

    static func phoneBottomInset(
        rootSafeAreaBottom: CGFloat,
        effectiveSafeAreaBottom: CGFloat,
        normalMinimumSpacing: CGFloat,
        keyboardSpacing: CGFloat
    ) -> CGFloat {
        let keyboardSafeAreaIsActive = effectiveSafeAreaBottom > rootSafeAreaBottom + keyboardSafeAreaEpsilon
        if keyboardSafeAreaIsActive {
            return keyboardSpacing
        }

        return max(normalMinimumSpacing, rootSafeAreaBottom + keyboardSpacing)
    }
}

struct ChatOverlayLayout {
    static func pickerTopInset(
        isPhone: Bool,
        rootSafeAreaTop: CGFloat,
        effectiveSafeAreaTop: CGFloat
    ) -> CGFloat {
        if isPhone {
            return rootSafeAreaTop + 52
        }

        return effectiveSafeAreaTop
    }
}
