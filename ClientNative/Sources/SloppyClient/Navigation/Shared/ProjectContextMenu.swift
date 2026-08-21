import SloppyClientCore
import SwiftUI

@MainActor
private struct ProjectContextMenuModifier: ViewModifier {
    let viewModel: MainViewModel
    let project: APIProjectRecord

    @State private var isRemovalConfirmationPresented = false

    private var hasVisibleChats: Bool {
        viewModel.hasVisibleChats(in: project)
    }

    private var hasArchivedChats: Bool {
        viewModel.hasArchivedChats(in: project)
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    viewModel.toggleProjectPinned(project)
                } label: {
                    Label(
                        project.isFavorite ? "Unpin" : "Pin",
                        systemImage: project.isFavorite ? "pin.slash" : "pin"
                    )
                }

                Button {
                    viewModel.presentProjectEditor(project)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Divider()

                Button {
                    viewModel.revealProjectInFinder(project)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .disabled(project.projectRootPath?.isEmpty != false)

                Button {
                    viewModel.createPermanentWorktree(for: project)
                } label: {
                    Label("Create permanent worktree", systemImage: "arrow.triangle.branch")
                }

                Divider()

                Button {
                    viewModel.toggleProjectChatsArchived(project)
                } label: {
                    Label(
                        hasVisibleChats ? "Archive chats" : "Unarchive chats",
                        systemImage: "archivebox"
                    )
                }
                .disabled(!hasVisibleChats && !hasArchivedChats)

                Divider()

                Button(role: .destructive) {
                    isRemovalConfirmationPresented = true
                } label: {
                    Label("Remove project", systemImage: "xmark")
                }
            }
            .confirmationDialog(
                "Remove \(project.name)?",
                isPresented: $isRemovalConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Remove project", role: .destructive) {
                    viewModel.removeProject(project)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the project and cancels its active tasks. Its local folder is not deleted.")
            }
    }
}

extension View {
    @MainActor
    func projectContextMenu(viewModel: MainViewModel, project: APIProjectRecord) -> some View {
        modifier(ProjectContextMenuModifier(viewModel: viewModel, project: project))
    }
}
