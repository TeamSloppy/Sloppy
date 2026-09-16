import SwiftUI

extension ProjectModeSection {
    var shortcutCharacter: Character {
        switch self {
        case .kanban: "1"
        case .workspaces: "2"
        case .automation: "3"
        case .chats: "4"
        }
    }
}

#if os(macOS)
struct ProjectModeCommandContext {
    let selectedSection: ProjectModeSection
    let select: @MainActor (ProjectModeSection) -> Void
}

extension FocusedValues {
    @Entry var projectModeCommands: ProjectModeCommandContext?
}

/// Registered once in the app menu, using only the active window's selected project.
struct ProjectModeSelectionButtons: View {
    let context: ProjectModeCommandContext?

    var body: some View {
        ForEach(ProjectModeSection.allCases) { section in
            Button(section.title) { context?.select(section) }
                .keyboardShortcut(KeyEquivalent(section.shortcutCharacter), modifiers: .command)
                .disabled(context == nil)
        }
    }
}
#endif
