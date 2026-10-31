#if os(iOS)
import SwiftUI
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureSettings

@MainActor
struct MobileRootShellView<ConnectionContent: View>: View {
    let root: RootShellViewModel
    let safeAreaInsets: EdgeInsets
    private let endpointOverride: SloppyInstanceEndpoint?
    @ViewBuilder let connectionContent: () -> ConnectionContent
    @State private var launch: MobileBrowserLaunchState
    @State private var workspace: MainViewModel?
    @State private var agentChat: BrowserAgentChatState?
    @State private var collectionRequest: BrowserTabCollectionRequest?
    @State private var endpointKey: String?
    @State private var hasOpenedWork = false
    @Environment(\.scenePhase) private var scenePhase

    init(root: RootShellViewModel, safeAreaInsets: EdgeInsets,
         launch: MobileBrowserLaunchState? = nil,
         endpointOverride: SloppyInstanceEndpoint? = nil,
         @ViewBuilder connectionContent: @escaping () -> ConnectionContent) {
        self.root = root
        self.safeAreaInsets = safeAreaInsets
        self.endpointOverride = endpointOverride
        self.connectionContent = connectionContent
        _launch = State(initialValue: launch ?? MobileBrowserLaunchState())
    }

    var body: some View {
        ZStack {
            // Keep one browser surface mounted even as relay/authentication state changes.
            BrowserWorkspaceView(state: launch.browser, onAskAgent: askAgent, onCollect: collect,
                onSettings: { root.presentSettings(.general) },
                onAnnotateSelection: {
                    guard connected, launch.browser.isBrowsing else { return nil }
                    return agentChat?.makeAnnotationReceiver()
                }, agentChat: connected ? agentChat : nil)
                .opacity(launch.browser.isBrowsing ? Double(1) : Double(0))
                .allowsHitTesting(launch.browser.isBrowsing)
                .accessibilityHidden(!launch.browser.isBrowsing)

            if connected, let workspace, let agentChat,
               !launch.browser.isBrowsing || hasOpenedWork || collectionRequest != nil {
                MainView(endpoint: workspaceEndpoint, settings: root.settings,
                    connectionMonitor: root.connectionMonitor, rootSafeAreaInsets: safeAreaInsets,
                    onOpenSettings: { root.presentSettings($0) }, onOpenWorkspace: { root.showConnectionSetup() },
                    menuBarQuickActionRequest: root.menuBarQuickActionRequest,
                    onConsumeMenuBarQuickAction: root.consumeMenuBarAction,
                    deepLinkRequest: root.appDeepLinkRequest, onConsumeDeepLink: root.consumeDeepLink,
                    approvalRequiredSessionIDs: root.pendingApprovalSessionIDs,
                    viewModel: workspace, browserWorkspace: launch.browser, browserAgentChat: agentChat,
                    embedsBrowser: false, browserCollectionRequest: collectionRequest,
                    onConsumeBrowserCollection: { collectionRequest = nil })
                    .safeAreaInset(edge: .top, spacing: 0) {
                        BackendUpdateReminder(endpoint: workspaceEndpoint)
                            .id(workspaceEndpoint.cacheNamespace)
                    }
                    .id(endpointKey)
                    .environment(\.mobileWorkBrowseSelection, modeSelection)
                    .opacity(launch.browser.isBrowsing ? Double(0) : Double(1))
                    .allowsHitTesting(!launch.browser.isBrowsing)
                    .accessibilityHidden(launch.browser.isBrowsing)
                    .onAppear { hasOpenedWork = true }
            } else if !launch.browser.isBrowsing {
                NavigationStack {
                    connectionContent()
                        .navigationTitle("Work")
                        .navigationBarTitleDisplayMode(.inline)
                        .mobileWorkBrowseNavigationBar()
                }
                .environment(\.mobileWorkBrowseSelection, modeSelection)
            }
        }
        .task(id: workspaceKey) { prepareWorkspace() }
        .task(id: browserConnectionKey) {
            if connected { await agentChat?.synchronizeBrowser(launch.browser) }
            else { agentChat?.stopBrowserConnection() }
        }
        .task(id: scenePhase) {
            launch.browser.checkpoint()
            guard scenePhase == .active else { return }
            await root.restoreMobileConnectionInBackground(whileBrowsing: { launch.browser.isBrowsing })
        }
        .onDisappear { launch.browser.checkpoint(); agentChat?.stopBrowserConnection() }
    }

    private var connected: Bool { if case .chat = root.appState { true } else { false } }
    private var workspaceEndpoint: SloppyInstanceEndpoint { endpointOverride ?? root.settings.activeInstanceEndpoint }
    private var workspaceKey: String? { connected ? workspaceEndpoint.cacheNamespace : nil }
    private var modeSelection: Binding<Bool> {
        Binding(get: { launch.browser.isBrowsing }, set: { browsing in
            if browsing { launch.showBrowser() }
            else { launch.browser.isBrowsing = false }
        })
    }
    private var browserConnectionKey: String {
        "\(workspaceKey ?? "offline")|\(launch.browser.isBrowsing)|\(launch.browser.selectedID?.uuidString ?? "")|\(agentChat?.chat.selectedAgent?.id ?? "")|\(agentChat?.chat.selectedSessionId ?? "")"
    }

    private func prepareWorkspace() {
        guard connected, let key = workspaceKey else {
            hasOpenedWork = false
            endpointKey = nil
            agentChat?.hide()
            agentChat?.stopBrowserConnection()
            return
        }
        if endpointKey != key {
            agentChat?.stopBrowserConnection()
            let endpoint = workspaceEndpoint
            let model = MainViewModel(endpoint: endpoint, settings: root.settings,
                connectionMonitor: root.connectionMonitor,
                onOpenSettings: { root.presentSettings($0) }, onOpenWorkspace: { root.showConnectionSetup() })
            workspace = model
            let chat = BrowserAgentChatState(chat: model.makeStandaloneChatViewModel(), apiClient: model.apiClient)
            chat.chat.applyNavigationRequest(.init(id: 1, context: .blank))
            agentChat = chat
            endpointKey = key
        }
        if let action = launch.takeConnectedAction() {
            switch action {
            case .assistant(let prompt): askAgent(prompt)
            case .collect(let tabs): collect(tabs)
            }
        }
    }

    private func askAgent(_ prompt: String) {
        guard connected, let agentChat else { launch.requireConnection(for: .assistant(prompt)); return }
        launch.browser.isBrowsing = true
        agentChat.show(prompt: prompt)
    }

    private func collect(_ tabs: [BrowserTabRecord]) {
        guard connected, workspace != nil else { launch.requireConnection(for: .collect(tabs)); return }
        collectionRequest = BrowserTabCollectionRequest(tabs: tabs)
    }
}
#endif
