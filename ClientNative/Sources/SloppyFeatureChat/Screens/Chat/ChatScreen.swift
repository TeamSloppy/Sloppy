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

let chatHeroWidth: CGFloat = 720
let chatContentWidth: CGFloat = 960

@MainActor
public struct ChatScreen: View {
    @State private var viewModel: ChatScreenViewModel
    private let rootSafeAreaInsets: EdgeInsets
    private let onOpenSidebar: (@MainActor () -> Void)?
    private let showsContextToolbar: Bool
    private let showsNavigationToolbar: Bool
    private let onAskInSideChat: (@MainActor @Sendable (String) -> Void)?

    public init(
        apiClient: SloppyAPIClient,
        settings: ClientSettings,
        connectionMonitor: ConnectionMonitor,
        onOpenSettings: @escaping @MainActor (ClientSettingsDestination) -> Void,
        rootSafeAreaInsets: EdgeInsets = EdgeInsets(),
        onOpenSidebar: (@MainActor () -> Void)? = nil,
        showsContextToolbar: Bool = true,
        showsNavigationToolbar: Bool = true,
        onAskInSideChat: (@MainActor @Sendable (String) -> Void)? = nil
    ) {
        self.rootSafeAreaInsets = rootSafeAreaInsets
        self.onOpenSidebar = onOpenSidebar
        self.showsContextToolbar = showsContextToolbar
        self.showsNavigationToolbar = showsNavigationToolbar
        self.onAskInSideChat = onAskInSideChat
        self._viewModel = State(
            initialValue: ChatScreenViewModel(
                apiClient: apiClient,
                settings: settings,
                connectionMonitor: connectionMonitor,
                onOpenSettings: onOpenSettings
            )
        )
    }

    public init(
        viewModel: ChatScreenViewModel,
        rootSafeAreaInsets: EdgeInsets = EdgeInsets(),
        onOpenSidebar: (@MainActor () -> Void)? = nil,
        showsContextToolbar: Bool = true,
        showsNavigationToolbar: Bool = true,
        onAskInSideChat: (@MainActor @Sendable (String) -> Void)? = nil
    ) {
        self.rootSafeAreaInsets = rootSafeAreaInsets
        self.onOpenSidebar = onOpenSidebar
        self.showsContextToolbar = showsContextToolbar
        self.showsNavigationToolbar = showsNavigationToolbar
        self.onAskInSideChat = onAskInSideChat
        self.viewModel = viewModel
    }

    public var body: some View {
        ChatScreenContent(
            rootSafeAreaInsets: rootSafeAreaInsets,
            onOpenSidebar: onOpenSidebar,
            composerTabActions: nil
        )
        .modifier(ChatAttachmentDropZone(viewModel: viewModel))
        .modifier(ChatFileLinkModifier(viewModel: viewModel))
        .modifier(ChatContextToolbarModifier(viewModel: viewModel, isEnabled: showsContextToolbar))
        .modifier(
            ChatNavigationToolbarModifier(
                viewModel: viewModel,
                onOpenSidebar: onOpenSidebar,
                isEnabled: showsNavigationToolbar
            )
        )
        .sheet(item: $viewModel.sessionToRename) { session in
            ChatRenameSheet(title: session.title) { title in
                try await viewModel.renameSession(session, title: title)
            }
        }
        .environment(viewModel)
        .mobileScreenBackground()
        .environment(viewModel.connectionMonitor)
        .environment(
            \.chatTextSelectionActions,
            textSelectionActions
        )
        .fileImporter(
            isPresented: $viewModel.isAttachmentPickerShown,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                viewModel.attachFileURLs(urls)
            case .failure:
                break
            }
        }
#if canImport(PhotosUI) && !os(macOS)
        .modifier(ChatPhotoAttachmentPickerModifier(viewModel: viewModel))
#endif
#if os(iOS)
        .modifier(ChatCameraAttachmentPickerModifier(viewModel: viewModel))
#endif
    }

    private var textSelectionActions: ChatTextSelectionActions {
        var actions = ChatTextSelectionActions(addToChat: viewModel.addQuoteToComposer,
            moreDetails: viewModel.askForMoreDetails, askInSideChat: onAskInSideChat)
#if os(macOS)
        actions.addAnnotation = viewModel.addAnchoredQuoteToComposer
        actions.annotations = viewModel.composerQuotes
        actions.editAnnotation = viewModel.editAnchoredComposerQuote
        actions.resolveAnnotation = { [weak viewModel] id, context in
            viewModel?.quoteAnnotationPresenter.anchors[id] = context
        }
#endif
        return actions
    }
}

@MainActor
struct ChatScreenContent: View {
    let rootSafeAreaInsets: EdgeInsets
    let onOpenSidebar: (@MainActor () -> Void)?
    let composerTabActions: ChatComposerTabActions?

    @Environment(ChatScreenViewModel.self) private var viewModel
    @Environment(ConnectionMonitor.self) private var connectionMonitor

    var body: some View {
        ChatChrome(
            viewModel: viewModel,
            connectionMonitor: connectionMonitor,
            rootSafeAreaInsets: rootSafeAreaInsets,
            composerTabActions: composerTabActions
        )
#if os(macOS)
        .safeAreaInset(edge: .top, alignment: .leading, spacing: 0) {
            if viewModel.activeParentSessionID != nil {
                Button(action: viewModel.returnToParentChat) {
                    Label("Back to parent chat", systemImage: "chevron.left")
                        .font(.callout)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat.back-to-parent")
            }
        }
#endif
        .onAppear {
            viewModel.loadInitialData()
        }
        .task(id: "\(ObjectIdentifier(viewModel)):\(viewModel.selectedAgent?.id ?? ""):\(viewModel.selectedSessionId ?? "")") {
            await viewModel.parallelAgents.observe(agentID: viewModel.selectedAgent?.id, sessionID: viewModel.selectedSessionId)
        }
    }
}

#Preview {
    let viewModel = ChatScreenViewModel(
        apiClient: .init(baseURL: .debugURL),
        settings: .init(),
        connectionMonitor: .init(baseURL: URL.debugURL),
        onOpenSettings: { _ in }
    )
    NavigationStack {
        ChatScreen(viewModel: viewModel)
#if os(visionOS)
            .backportGlassEffect(.regular, in: .rect(cornerRadius: 24))
#endif
    }
}

#Preview {
    let viewModel = ChatScreenViewModel(
        apiClient: .init(baseURL: .debugURL),
        settings: .init(),
        connectionMonitor: .init(baseURL: URL.debugURL),
        onOpenSettings: { _ in }
    )
    viewModel.transcript.replaceAll([
        .init(role: .assistant, segments: [
            .init(kind: .text)
        ])
    ])
    return NavigationStack {
        ChatScreen(viewModel: viewModel)
#if os(visionOS)
            .backportGlassEffect(.regular, in: .rect(cornerRadius: 24))
#endif
    }
}
