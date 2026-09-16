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
        WorkspaceResizableSidePanel(state: viewModel.workspaceDockState) {
            contentView
        } panel: {
            workspaceSidePanel
        }
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
            WorkspaceBrowserPanelView(viewModel: viewModel.workspacePanelViewModel.webViewModel)
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
        .help(isWorkspacePanelPresented ? "Hide side panel" : "Show side panel")
        .accessibilityIdentifier("workspace.dock.toggle")
        .accessibilityLabel("Side panel")
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
        let dock = viewModel.workspaceDockState
        let tab: WorkspaceDockTab
        if let existing = dock.tabs.first(where: { $0.kind == .sideChat }) {
            dock.select(existing)
            tab = existing
        } else {
            tab = viewModel.openWorkspaceDockTab(.sideChat)
        }
        tab.chat?.addTextSelectionToComposer(selectedText)
    }
}

