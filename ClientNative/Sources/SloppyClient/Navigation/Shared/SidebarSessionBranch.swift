import SloppyClientCore
import SloppyClientUI
import SwiftUI

@MainActor
struct SidebarSessionBranch: View {
    let viewModel: MainViewModel
    let session: ChatSessionSummary
    let tree: ChatSidebarSessionTree
    var approvalRequiredSessionIDs: Set<String> = []
    var showsProjectName = true
    var depth = 0
    @State private var expansion: Bool?
    @Environment(\.theme) private var theme

    private var expanded: Bool {
        expansion ?? (containsSelection(viewModel.selectedChatStorageID) || containsSelection(viewModel.selectedSideChatStorageID))
    }

    private func containsSelection(_ storageID: String?) -> Bool {
        storageID == session.storageID || tree.contains(storageID, under: session)
    }

    var body: some View {
        let children = tree.children(of: session)
        VStack(alignment: .leading, spacing: 2) {
            SidebarSessionItem(viewModel: viewModel, session: session,
                requiresApproval: approvalRequiredSessionIDs.contains(session.id) || approvalRequiredSessionIDs.contains(session.storageID),
                showsProjectName: showsProjectName)
                .overlay(alignment: .leading) {
                    if !children.isEmpty {
                        Button { expansion = !expanded } label: {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.colors.textMuted)
                                .frame(width: 24, height: MainSidebarView.rowMinimumHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).padding(.leading, theme.spacing.s)
                        .accessibilityLabel("\(expanded ? "Collapse" : "Expand") subchats of \(session.displayTitle)")
                        .accessibilityIdentifier("sidebar.session.\(session.storageID).children")
                    }
                }
                .padding(.leading, CGFloat(depth) * 16)
            if expanded {
                ForEach(children, id: \.storageID) { child in
                    AnyView(SidebarSessionBranch(viewModel: viewModel, session: child, tree: tree,
                        approvalRequiredSessionIDs: approvalRequiredSessionIDs, showsProjectName: showsProjectName, depth: depth + 1))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .onChange(of: viewModel.selectedChatStorageID) { _, selected in
            if containsSelection(selected) { expansion = true }
        }
        .onChange(of: viewModel.selectedSideChatStorageID) { _, selected in
            if containsSelection(selected) { expansion = true }
        }
    }
}
