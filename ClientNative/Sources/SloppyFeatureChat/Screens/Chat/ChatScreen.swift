import Foundation
import SwiftUI
import SloppyClientCore
import SloppyClientUI
#if canImport(PhotosUI)
import PhotosUI
#endif
#if os(iOS)
import UIKit
#endif

fileprivate let chatHeroWidth: CGFloat = 720
fileprivate let chatContentWidth: CGFloat = 840

@MainActor
public struct ChatScreen: View {
    @State private var viewModel: ChatScreenViewModel
    private let rootSafeAreaInsets: EdgeInsets
    private let onOpenSidebar: (@MainActor () -> Void)?
    private let showsContextToolbar: Bool

    public init(
        apiClient: SloppyAPIClient,
        settings: ClientSettings,
        connectionMonitor: ConnectionMonitor,
        onOpenSettings: @escaping @MainActor () -> Void,
        rootSafeAreaInsets: EdgeInsets = EdgeInsets(),
        onOpenSidebar: (@MainActor () -> Void)? = nil,
        showsContextToolbar: Bool = true
    ) {
        self.rootSafeAreaInsets = rootSafeAreaInsets
        self.onOpenSidebar = onOpenSidebar
        self.showsContextToolbar = showsContextToolbar
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
        showsContextToolbar: Bool = true
    ) {
        self.rootSafeAreaInsets = rootSafeAreaInsets
        self.onOpenSidebar = onOpenSidebar
        self.showsContextToolbar = showsContextToolbar
        self.viewModel = viewModel
    }

    public var body: some View {
        ChatScreenContent(
            rootSafeAreaInsets: rootSafeAreaInsets,
            onOpenSidebar: onOpenSidebar,
            composerTabActions: nil
        )
        .modifier(ChatContextToolbarModifier(viewModel: viewModel, isEnabled: showsContextToolbar))
        .environment(viewModel)
        .environment(viewModel.connectionMonitor)
        .overlay(anchor: .top, content: {
            ChatConnectionBar(connectionMonitor: viewModel.connectionMonitor)
        })
        .fileImporter(
            isPresented: $viewModel.isAttachmentPickerShown,
            allowedContentTypes: [],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                viewModel.attachFileURLs(urls)
            case .failure:
                break
            }
        }
#if canImport(PhotosUI)
        .modifier(ChatPhotoAttachmentPickerModifier(viewModel: viewModel))
#endif
#if os(iOS)
        .modifier(ChatCameraAttachmentPickerModifier(viewModel: viewModel))
#endif
    }
}

#if canImport(PhotosUI)
@MainActor
private struct ChatPhotoAttachmentPickerModifier: ViewModifier {
    let viewModel: ChatScreenViewModel
    @State private var photoItems: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $viewModel.isPhotoPickerShown,
                selection: $photoItems,
                maxSelectionCount: 10,
                matching: .images
            )
            .onChange(of: photoItems) { _, items in
                Task { @MainActor in
                    let urls = await attachmentURLs(from: items)
                    viewModel.attachFileURLs(urls)
                    photoItems = []
                }
            }
    }

    private func attachmentURLs(from items: [PhotosPickerItem]) async -> [URL] {
        var urls: [URL] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                continue
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("sloppy-photo-\(UUID().uuidString)")
                .appendingPathExtension("jpg")
            guard (try? data.write(to: url, options: .atomic)) != nil else {
                continue
            }
            urls.append(url)
        }
        return urls
    }
}
#endif

#if os(iOS)
@MainActor
private struct ChatCameraAttachmentPickerModifier: ViewModifier {
    let viewModel: ChatScreenViewModel

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $viewModel.isCameraPickerShown) {
            CameraAttachmentPicker { url in
                viewModel.isCameraPickerShown = false
                if let url {
                    viewModel.attachFileURLs([url])
                }
            }
            .ignoresSafeArea()
        }
    }
}

private struct CameraAttachmentPicker: UIViewControllerRepresentable {
    let onComplete: @MainActor (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onComplete: @MainActor (URL?) -> Void

        init(onComplete: @escaping @MainActor (URL?) -> Void) {
            self.onComplete = onComplete
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let url: URL? = {
                guard let image = info[.originalImage] as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.9) else {
                    return nil
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("sloppy-camera-\(UUID().uuidString)")
                    .appendingPathExtension("jpg")
                return (try? data.write(to: url, options: .atomic)) == nil ? nil : url
            }()
            Task { @MainActor in onComplete(url) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            Task { @MainActor in onComplete(nil) }
        }
    }
}
#endif

@MainActor
private struct ChatContextToolbarModifier: ViewModifier {
    let viewModel: ChatScreenViewModel
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.toolbar(id: "agent.settings") {
                ToolbarItem(id: "agent", placement: .secondaryAction) {
                    ChatAgentToolbarMenu(
                        selectedAgent: viewModel.selectedAgent,
                        agents: viewModel.agents,
                        onSelectAgent: viewModel.pickAgent
                    )
                }
                ToolbarItem(id: "model", placement: .secondaryAction) {
                    ChatModelToolbarMenu(
                        selectedModelId: viewModel.selectedModelId,
                        models: viewModel.availableModels,
                        onSelectModel: viewModel.pickModel
                    )
                }
            }
        } else {
            content
        }
    }
}

@MainActor
private struct ChatScreenContent: View {
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
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ChatNavigationLeadingItems(
                    viewModel: viewModel,
                    onOpenSidebar: onOpenSidebar
                )
            }
        }
        .onAppear {
            viewModel.loadInitialData()
        }
    }
}

@MainActor
private struct ChatChrome: View {
    let viewModel: ChatScreenViewModel
    let connectionMonitor: ConnectionMonitor
    let rootSafeAreaInsets: EdgeInsets
    let composerTabActions: ChatComposerTabActions?

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
            if viewModel.transcript.isEmpty {
                ChatEmptyChatRegion(
                    viewModel: viewModel,
                    contentWidth: contentWidth,
                    heroWidth: heroWidth,
                    bottomClearance: composerScrollInset
                )
            } else {
                ChatTranscriptRegion(
                    viewModel: viewModel,
                    contentWidth: contentWidth,
                    heroWidth: heroWidth,
                    messagesTopInset: messagesTopInset,
                    composerScrollInset: composerScrollInset
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func contentWidth(for availableWidth: CGFloat) -> CGFloat {
        let horizontalInset = idiom == .phone ? theme.spacing.s * 2 : theme.spacing.l * 2
        return max(0, min(chatContentWidth, availableWidth - horizontalInset))
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
        ChatComposerView.panelHeight(for: idiom) + composerScrollGap
    }

    private var composerBottomInset: CGFloat {
        guard idiom == .phone else {
            return theme.spacing.m
        }

        return ChatComposerKeyboardLayout.phoneBottomInset(
            rootSafeAreaBottom: rootSafeAreaInsets.bottom,
            effectiveSafeAreaBottom: safeAreaInsets.bottom,
            normalMinimumSpacing: theme.spacing.s,
            keyboardSpacing: theme.spacing.xs
        )
    }

    private var messagesTopInset: CGFloat {
        idiom == .phone ? theme.spacing.s : theme.spacing.xxl
    }

    private var composerScrollGap: CGFloat {
        idiom == .phone ? theme.spacing.l : theme.spacing.xxl
    }

    private var screenPointWidth: CGFloat {
        guard let screen = Screen.main else {
            return 390
        }
        return max(320, screen.size.width)
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

@MainActor
private struct ChatNavigationLeadingItems: View {
    let viewModel: ChatScreenViewModel
    let onOpenSidebar: (@MainActor () -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.userInterfaceIdiom) private var idiom

    var body: some View {
        if idiom == .phone {
            MobileChatNavigationHeader(
                viewModel: viewModel,
                onOpenSidebar: onOpenSidebar
            )
        } else {
            desktopBody
        }
    }

    private var desktopBody: some View {
        HStack(spacing: 8) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72 as CGFloat))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            if let onOpenSidebar {
                Button(action: onOpenSidebar) {
                    Icons.symbol(.menu, size: 15)
                        .foregroundColor(.white.opacity(0.72 as CGFloat))
                        .frame(width: 30, height: 30)
                }
            }

            if let activeContextTitle = viewModel.activeContextTitle {
                Text(activeContextTitle)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.7 as CGFloat))
                    .lineLimit(1)
            }
        }
    }

}

@MainActor
private struct MobileChatNavigationHeader: View {
    let viewModel: ChatScreenViewModel
    let onOpenSidebar: (@MainActor () -> Void)?

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.s) {
            if let onOpenSidebar {
                MobileChatNavigationIconButton(symbol: .menu, action: onOpenSidebar)
            }

            MobileChatNavigationCenterCapsule(viewModel: viewModel)
        }
    }
}

@MainActor
private struct MobileChatNavigationCenterCapsule: View {
    let viewModel: ChatScreenViewModel

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Picker("", selection: selectedAgentId) {
                if viewModel.agents.isEmpty {
                    Text("Agent").tag("")
                } else {
                    ForEach(viewModel.agents) { agent in
                        Text(agent.displayName).tag(agent.id)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(theme.colors.textPrimary)

            Text(sessionLabel)
                .font(.system(size: theme.typography.micro))
                .foregroundColor(theme.colors.textMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, theme.spacing.s)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 46, maxHeight: 46, alignment: .leading)
    }

    private var sessionLabel: String {
        viewModel.selectedSessionId == nil ? (viewModel.activeContextTitle ?? "New chat") : "Recent session"
    }

    private var selectedAgentId: Binding<String> {
        Binding(
            get: { viewModel.selectedAgent?.id ?? viewModel.agents.first?.id ?? "" },
            set: { nextId in
                guard let agent = viewModel.agents.first(where: { $0.id == nextId }) else {
                    return
                }
                viewModel.pickAgent(agent)
            }
        )
    }

    private var mobileNavigationCapsuleWidth: CGFloat {
        let horizontalMargins = theme.spacing.l * 2
        let leftClusterWidth: CGFloat = 44 + theme.spacing.s
        let rightClusterWidth: CGFloat = 44 * 2 + theme.spacing.xs + theme.spacing.s
        let available: CGFloat = screenPointWidth - horizontalMargins - leftClusterWidth - rightClusterWidth
        return max(150, min(236, available))
    }

    private var screenPointWidth: CGFloat {
        guard let screen = Screen.main else {
            return 390
        }
        return max(320, screen.size.width)
    }
}

@MainActor
private struct MobileChatNavigationIconButton: View {
    let symbol: MaterialSymbol
    let action: @MainActor () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Icons.symbol(symbol, size: theme.typography.heading)
                .foregroundColor(theme.colors.textPrimary)
                .frame(width: 44, height: 44)
        }
    }
}

@MainActor
private struct ChatConnectionBar: View {
    let connectionMonitor: ConnectionMonitor

    @ViewBuilder
    var body: some View {
        if connectionMonitor.state != .connected {
            ConnectionBanner(
                state: connectionMonitor.state,
                endpoint: connectionMonitor.checkedURL?.absoluteString,
                message: connectionMonitor.lastFailureMessage
            )
        }
    }
}

@MainActor
private struct ChatTranscriptRegion: View {
    let viewModel: ChatScreenViewModel
    let contentWidth: CGFloat
    let heroWidth: CGFloat
    let messagesTopInset: CGFloat
    let composerScrollInset: CGFloat

    var body: some View {
        ChatTranscriptPane(
            transcript: viewModel.transcript,
            agentName: viewModel.selectedAgent?.displayName ?? "Agent",
            contentWidth: contentWidth,
            heroWidth: heroWidth,
            messagesTopInset: messagesTopInset,
            composerScrollInset: composerScrollInset
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.dismissComposerFocus()
        }
    }
}

@MainActor
private struct ChatEmptyChatRegion: View {
    let viewModel: ChatScreenViewModel
    let contentWidth: CGFloat
    let heroWidth: CGFloat
    let bottomClearance: CGFloat

    @Environment(\.userInterfaceIdiom) private var idiom
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.xl) {
            Spacer(minLength: idiom == .phone ? theme.spacing.xxl : theme.spacing.l)
            if let activeContextTitle = viewModel.activeContextTitle {
                Text(activeContextTitle)
                    .font(.system(size: idiom == .phone ? theme.typography.caption : theme.typography.body))
                    .foregroundColor(theme.colors.textMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: heroWidth)
            }
            ChatGreetingView(agentName: viewModel.selectedAgent?.displayName ?? "Agent")
                .frame(width: heroWidth)
            Spacer(minLength: bottomClearance)
        }
        .padding(.horizontal, idiom == .phone ? theme.spacing.s : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.dismissComposerFocus()
        }
    }
}

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
//                .frame(width: contentWidth)
#if os(visionOS)
                .padding3D(.front)
#endif
            Spacer(minLength: 0)
        }
        .padding(.horizontal, idiom == .phone ? theme.spacing.xs : 0)
        .padding(.bottom, composerBottomInset)
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
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.attachFileURLs(urls)
            return !urls.isEmpty
        }
#if !os(visionOS)
        .background(
            LinearGradient(colors: [
                Color.black.opacity(0.01),
                Color.black.opacity(0.4),
                Color.black
            ], startPoint: .top, endPoint: .bottom)
        )
#endif
    }

    @ViewBuilder
    private var composerBar: some View {
        ChatComposerView(
            draft: viewModel.composerDraft,
            tabs: tabs,
            viewModel: viewModel,
            tabActions: tabActions
        )
    }
}

@MainActor
private struct ChatTranscriptPane: View {
    let transcript: ChatTranscriptState
    let agentName: String
    let contentWidth: CGFloat
    let heroWidth: CGFloat
    let messagesTopInset: CGFloat
    let composerScrollInset: CGFloat

    @Environment(\.theme) private var theme

    var body: some View {
        if transcript.isEmpty {
            VStack(spacing: theme.spacing.xl) {
                Color.clear
                    .frame(height: 300)
                ChatGreetingView(agentName: agentName)
                    .frame(width: heroWidth)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if transcript.hasEarlierMessages {
                            revealEarlierButton
                                .padding(.top, messagesTopInset)
                                .padding(.bottom, theme.spacing.m)
                        }

                        LazyVStack(alignment: .leading, spacing: theme.spacing.xl) {
                            ForEach(transcript.messages) { msg in
                                ChatBubbleView(message: msg)
                                    .frame(minWidth: 0, maxWidth: .infinity)
                            }
                        }
                        .frame(width: contentWidth)
                        .padding(.top, transcript.hasEarlierMessages ? 0 : messagesTopInset)
                        .padding(.bottom, composerScrollInset)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .onChange(of: transcript.messages.count) { oldCount, newCount in
                    guard newCount > oldCount,
                          oldCount == 0 || proxy.isNearBottom(threshold: 220),
                          let lastMessageId = transcript.lastMessage?.id else {
                        return
                    }

                    Task { @MainActor in
                        proxy.scrollTo(lastMessageId, anchor: .bottom)
                    }
                }
                .onChange(of: latestAssistantMessageLayoutKey) { _, _ in
                    guard proxy.isNearBottom(threshold: 480),
                          let lastMessage = transcript.lastMessage,
                          lastMessage.role == .assistant else {
                        return
                    }

                    Task { @MainActor in
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var latestAssistantMessageLayoutKey: String {
        guard let message = transcript.lastMessage,
              message.role == .assistant else {
            return ""
        }
        return "\(message.id):\(message.textContent.count)"
    }

    private var revealEarlierButton: some View {
        let c = theme.colors
        let sp = theme.spacing
        let ty = theme.typography
        let count = min(64, transcript.hiddenMessageCount)

        return HStack {
            Spacer(minLength: 0)
            Button("Show \(count) earlier") {
                transcript.revealEarlierMessages()
            }
            .font(.system(size: ty.caption))
            .foregroundColor(c.textSecondary)
            .padding(.horizontal, sp.m)
            .padding(.vertical, sp.s)
            .background(c.surface.opacity(0.74 as CGFloat))
            .backportGlassEffect(.regular, in: .rect(cornerRadius: 14))

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    let viewModel = ChatScreenViewModel(
        apiClient: .init(baseURL: .debugURL),
        settings: .init(),
        connectionMonitor: .init(baseURL: URL.debugURL),
        onOpenSettings: {}
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
        onOpenSettings: {}
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
