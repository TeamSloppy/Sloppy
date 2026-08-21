import SloppyClientCore
import SloppyClientUI
import SloppyFeatureChat
import SloppyFeatureProjects
import SwiftUI

@MainActor
struct ProjectModeView: View {
    let project: APIProjectRecord
    let state: ProjectKanbanTabState
    let rootSafeAreaInsets: EdgeInsets
    let onSelectSection: @MainActor (ProjectModeSection) -> Void
    let onOpenTask: @MainActor (ProjectKanbanCard) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            projectModeChrome
            projectContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("project-mode")
    }

    private var projectModeChrome: some View {
        ZStack {
            ViewThatFits(in: .horizontal) {
                projectModePicker(showsTitles: true)
                projectModePicker(showsTitles: false)
            }

            if state.selectedSection == .workspaces,
               !state.workspaceViewModel.isShowingLibrary {
                HStack {
                    Button {
                        state.workspaceViewModel.showLibrary()
                        Task { await state.workspaceViewModel.refreshLibrary() }
                    } label: {
                        Label("Workspaces", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.colors.textSecondary)
                    .accessibilityIdentifier("project-mode-workspaces-back")

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.colors.surface.opacity(0.7))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func projectModePicker(showsTitles: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(ProjectModeSection.allCases) { section in
                Button {
                    onSelectSection(section)
                } label: {
                    projectModeLabel(section, showsTitle: showsTitles)
                        .font(.system(size: theme.typography.caption, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, showsTitles ? 14 : 12)
                        .frame(minHeight: 32)
                        .contentShape(Capsule())
                        .background {
                            if state.selectedSection == section {
                                Capsule()
                                    .fill(theme.colors.surfaceRaised)
                                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    state.selectedSection == section
                        ? theme.colors.textPrimary
                        : theme.colors.textSecondary
                )
                .accessibilityIdentifier("project-mode-\(section.rawValue)")
            }
        }
        .padding(3)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(theme.colors.border.opacity(0.7), lineWidth: theme.borders.thin)
        }
    }

    @ViewBuilder
    private func projectModeLabel(_ section: ProjectModeSection, showsTitle: Bool) -> some View {
        if showsTitle {
            Label(section.title, systemImage: section.systemImage)
        } else {
            Label(section.title, systemImage: section.systemImage)
                .labelStyle(.iconOnly)
        }
    }

    private var projectContent: some View {
        ZStack {
            ProjectKanbanView(
                viewModel: state.viewModel,
                projectId: project.id,
                projectName: project.name,
                onOpenTask: onOpenTask
            )
            .projectModeVisibility(state.selectedSection == .kanban)

            CanvasWorkspaceSurface(
                viewModel: state.workspaceViewModel,
                allowsProjectSelection: false
            )
            .projectModeVisibility(state.selectedSection == .workspaces)

            ProjectAutomationView(
                viewModel: state.automationViewModel,
                projectId: project.id,
                projectName: project.name
            )
            .projectModeVisibility(state.selectedSection == .automation)

            ChatScreen(
                viewModel: state.chatViewModel,
                rootSafeAreaInsets: rootSafeAreaInsets,
                showsContextToolbar: false,
                showsNavigationToolbar: false
            )
            .id(ObjectIdentifier(state.chatViewModel))
            .projectModeVisibility(state.selectedSection == .chats)
        }
    }
}

private extension View {
    func projectModeVisibility(_ isVisible: Bool) -> some View {
        let opacityValue: Double = isVisible ? 1 : 0
        return opacity(opacityValue)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
    }
}
