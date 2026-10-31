import SwiftUI
import SloppyClientUI
import SloppyFeatureChat

@MainActor
extension MainView {
    var workAndBrowseContent: some View {
        ZStack {
            if embedsBrowser && browserWorkspace.isBrowsing {
                BrowserWorkspaceView(state: browserWorkspace, onAskAgent: startBrowserChat, onCollect: collectBrowserTabs,
                                     onSettings: { viewModel.onOpenSettings(.general) },
                                     onAnnotateSelection: browserTextAnnotationTarget,
                                     agentChat: browserAgentChat)
            } else {
                workspaceWithInstanceDiscoveryUpdates
            }
        }
        .task(id: browserChatConnectionID) {
            guard embedsBrowser else { return }
            await browserAgentChat.synchronizeBrowser(browserWorkspace)
        }
        .onDisappear { if embedsBrowser { browserAgentChat.stopBrowserConnection() } }
        .task(id: browserCollectionRequest?.id) {
            guard let request = browserCollectionRequest else { return }
            onConsumeBrowserCollection()
            collectBrowserTabs(request.tabs)
        }
#if os(macOS)
        .focusedSceneValue(\.toggleMainSidebar, ToggleMainSidebarAction(perform: toggleMainSidebar))
#endif
    }

    private var browserChatConnectionID: String {
        "\(browserWorkspace.isBrowsing)|\(browserWorkspace.selectedID?.uuidString ?? "")|\(browserAgentChat.chat.selectedAgent?.id ?? "")|\(browserAgentChat.chat.selectedSessionId ?? "")"
    }

    var shouldShowWorkspaceContent: Bool {
        viewModel.hasLoadedInitialContent
    }

    var workBrowsePicker: some View {
        Picker("Mode", selection: $browserWorkspace.isBrowsing) {
            Label("Work", systemImage: "briefcase").tag(false)
            Label("Browse", systemImage: "globe").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 220)
#if os(macOS)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .padding(.bottom, 8)
#endif
        .accessibilityIdentifier("workspace-mode-picker")
        .onChange(of: browserWorkspace.isBrowsing) { _, _ in browserWorkspace.checkpoint() }
    }

    func startBrowserChat(_ text: String) {
        browserWorkspace.checkpoint()
        browserWorkspace.isBrowsing = true
        browserAgentChat.show(prompt: text)
    }

    var browserTextAnnotationTarget: BrowserTextAnnotationTarget {
        {
            if browserWorkspace.isBrowsing, let receive = browserAgentChat.makeAnnotationReceiver() {
                return { quote in
                    guard browserWorkspace.isBrowsing else { return false }
                    return receive(quote)
                }
            }
            if let receive = onBrowserTextAnnotationTarget?() { return receive }
            guard !browserWorkspace.isBrowsing,
                  viewModel.selectedAppSection == .chats || viewModel.selectedAppSection == .projects,
                  let chat = activeChatViewModel else { return nil }
            let tabID = viewModel.selectedTabID
            let section = viewModel.selectedAppSection
            let receive = chat.makeBrowserTextAnnotationReceiver()
            return { [weak chat] quote in
                guard let chat, !browserWorkspace.isBrowsing,
                      viewModel.selectedTabID == tabID, viewModel.selectedAppSection == section,
                      activeChatViewModel === chat else { return false }
                return receive(quote)
            }
        }
    }

    func collectBrowserTabs(_ tabs: [BrowserTabRecord]) {
        guard !browserWorkspace.isCollecting else { return }
        browserWorkspace.isCollecting = true
        Task {
            defer { browserWorkspace.isCollecting = false }
            do {
                collectedBrowserCanvas = try await canvasWorkspaceViewModel.collectBrowserTabs(tabs)
                browserWorkspace.isBrowsing = false
                viewModel.selectWorkspace()
            } catch {
                browserCanvasError = error.localizedDescription
            }
        }
    }
}
