import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import SloppyClientCore
import SloppyClientUI
import SloppyFeatureAgents
import SloppyFeatureChat
import SloppyFeatureProjects
import SloppyFeatureSettings
import SloppyFeatureSites

@MainActor
extension MainView {
    @ViewBuilder
    var workspacePanelContainer: some View {
#if os(macOS)
        contentView
            .focusedSceneValue(\.projectModeCommands, projectModeCommandContext)
#else
        contentView
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .inspector(isPresented: Binding(get: { isWorkspacePanelPresented }, set: { isWorkspacePanelPresented = $0 })) {
                workspaceSidePanel
                    .inspectorColumnWidth(min: 240, ideal: viewModel.workspaceDockState.preferredWidth, max: 1200)
            }
#endif
    }

#if os(macOS)
    /// Keep the native sidebar and toolbar outside the dock's clipping boundary.
    var desktopWorkspaceDetail: some View {
        WorkspaceResizableSidePanel(state: viewModel.workspaceDockState, reservedContentWidth: 304) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    contentArea()
                        .frame(width: max(0, geometry.size.width - 304))
                        .clipped()
                    desktopWorkspaceInspector
                        .frame(width: 280)
                        .padding(.horizontal, 12)
                }
            }
        } panel: {
            workspaceSidePanel
        }
    }
#endif

#if os(macOS)
    private var desktopWorkspaceInspector: some View {
        let chat = activeChatViewModel ?? viewModel.selectedTabID.flatMap {
            viewModel.tabStates[$0]?.projectKanbanState?.chatViewModel
        }
        let isChatVisible = (viewModel.selectedAppSection == .chats || viewModel.selectedAppSection == .projects)
            && activeChatViewModel != nil
        let endpoint = chat?.sessionEndpoint
            ?? viewModel.selectedTabID.flatMap { viewModel.tabEndpoints[$0] }
            ?? viewModel.endpoint
        return DesktopWorkspaceInspector(
            apiClient: SloppyAPIClient(endpoint: endpoint),
            chat: chat,
            context: viewModel.workspaceContext,
            projectNavigation: projectModeCommandContext,
            observesWorkers: !isChatVisible,
            onOpenWorker: { session in viewModel.openSessionChatTab(session, endpointOverride: endpoint) },
            onOpenTool: selectWorkspaceSidePanelItem,
            onOpenOutput: { path in
                if let chat { viewModel.openSourceFile(SourceFileReference(path: path), from: chat) }
            }
        )
        .id("\(endpoint.cacheNamespace)|\(viewModel.workspaceContext?.projectId ?? "")")
    }
#endif

    @ViewBuilder
    func workspaceBottomPanelOverlay(maximumHeight: CGFloat) -> some View {
        if let selectedTabID = viewModel.selectedTabID,
           let terminalState = viewModel.tabStates[selectedTabID]?.terminalState,
           terminalState.isPresented {
            WorkspaceBottomPanelDrawerView(
                height: min(terminalState.height, maximumHeight),
                maximumHeight: maximumHeight,
                selectedPanel: terminalState.selectedPanel,
                onSelectPanel: { panel in
                    viewModel.openBottomPanel(panel)
                    switch panel {
                    case .review:
                        viewModel.workspacePanelViewModel.switchMode(.environment)
                    case .browser:
                        isWorkspacePanelPresented = false
                        viewModel.workspacePanelViewModel.switchMode(.webBrowser)
                    case .files:
                        viewModel.workspacePanelViewModel.switchMode(.files)
                    case .terminal:
                        break
                    }
                },
                onClose: viewModel.closeTerminalForSelectedTab,
                onHeightChange: {
                    terminalState.height = min(max($0, 120), maximumHeight)
                }
            ) {
                workspaceBottomPanelContent(
                    selectedPanel: terminalState.selectedPanel,
                    selectedTabID: selectedTabID
                )
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(20)
        }
    }

    @ViewBuilder
    func workspaceBottomPanelContent(
        selectedPanel: WorkspaceBottomPanelKind,
        selectedTabID: WorkspaceTab.ID
    ) -> some View {
        switch selectedPanel {
        case .terminal:
            if viewModel.terminalSessions[selectedTabID] != nil {
                viewModel.makeTerminalHostView(for: selectedTabID)
            } else {
                WorkspaceBottomPanelUnavailableView(
                    title: "Project directory unavailable",
                    detail: "Open the terminal from a project-backed tab to start a shell."
                )
            }
        case .browser:
            WorkspaceBrowserPanelView(viewModel: viewModel.workspacePanelViewModel.webViewModel,
                                      onAnnotate: browserAnnotationReceiver)
        case .review, .files:
            if let workspaceContext = viewModel.workspaceContext {
                WorkspacePanelView(
                    viewModel: viewModel.workspacePanelViewModel,
                    context: workspaceContext,
                    onOpenTerminal: { viewModel.openBottomPanel(.terminal) },
                    showsHeader: false
                )
            } else {
                WorkspaceBottomPanelUnavailableView(
                    title: "Project unavailable",
                    detail: "Open a project-backed tab to use \(selectedPanel.title.lowercased())."
                )
            }
        }
    }

#if os(macOS)
    var projectModeCommandContext: ProjectModeCommandContext? {
        guard let tabID = viewModel.selectedTabID,
              let state = viewModel.tabStates[tabID]?.projectKanbanState,
              let tab = viewModel.tabs.first(where: { $0.id == tabID }),
              case .projectKanban(let context) = tab.payload else { return nil }
        let project = viewModel.project(for: tabID, localProjectID: context.projectId)
            ?? APIProjectRecord(id: context.projectId, name: context.projectName)
        return ProjectModeCommandContext(selectedSection: state.selectedSection) { section in
            viewModel.selectProjectModeSection(section, project: project)
        }
    }
#endif

    var workspaceSidePanelButton: some View {
        Button(action: toggleWorkspaceSidePanelPicker) {
            Image(systemName: "sidebar.right")
                .frame(width: 24, height: 24)
        }
        .help(sidePanelHelp)
        .accessibilityIdentifier("workspace.dock.toggle")
        .accessibilityLabel("Side panel")
#if os(macOS)
        .contextMenu {
            ForEach(WorkspaceSidePanelItem.allCases) { item in
                Button { selectWorkspaceSidePanelItem(item) } label: { Label(item.title, systemImage: item.systemImage) }
                    .disabled(item.requiresProject && viewModel.workspaceContext == nil)
            }
        }
#endif
    }

    private var sidePanelHelp: String {
        isWorkspacePanelPresented ? "Hide side panel" : "Show side panel"
    }

    func openWorkspacePanel(mode: WorkspacePanelMode) {
        switch mode {
        case .environment: viewModel.openWorkspaceDockTab(.review)
        case .files: viewModel.openWorkspaceDockTab(.files)
        case .webBrowser:
            if let tabID = viewModel.selectedTabID,
               viewModel.tabStates[tabID]?.terminalState.selectedPanel == .browser {
                viewModel.closeTerminalForSelectedTab()
            }
            viewModel.openWorkspaceDockTab(.browser, browser: viewModel.workspacePanelViewModel.webViewModel)
        }
    }

    func toggleWorkspaceSidePanelPicker() {
        viewModel.workspaceDockState.toggleVisibility()
    }

    func selectWorkspaceSidePanelItem(_ item: WorkspaceSidePanelItem) {
        viewModel.openWorkspaceDockTab(item)
    }

    func askInSideChat(_ selectedText: String) {
        viewModel.addToSideChat(selectedText)
    }
}
