import SwiftUI

struct BrowserFavoriteDraft: Identifiable {
    var id = UUID()
    var entryID: UUID?
    var parentID: UUID?
    var title = ""
    var favoriteIDs: Set<UUID> = []
    var tabIDs: Set<UUID> = []
}

@MainActor
struct BrowserFavoriteRows: View {
    let state: BrowserWorkspaceState
    var parentID: UUID?
    let onEdit: (BrowserFavoriteDraft) -> Void

    var body: some View {
        ForEach(state.favorites.children(in: parentID)) { item in
            if item.kind == .folder {
                DisclosureGroup(isExpanded: Binding(get: { !item.isCollapsed }, set: { state.favorites.setCollapsed(item.id, !$0) })) {
                    BrowserFavoriteRows(state: state, parentID: item.id, onEdit: onEdit)
                } label: {
                    Label(item.title, systemImage: "folder")
                        .contextMenu {
                            Button("New subfolder", systemImage: "folder.badge.plus") { onEdit(.init(parentID: item.id)) }
                            Button("Pin current page here", systemImage: "pin") {
                                if let id = state.selectedID { _ = state.pinTab(id, in: item.id) }
                            }.disabled(state.selectedTab?.url == nil)
                            Divider()
                            BrowserFavoriteActions(state: state, ids: [item.id], onEdit: onEdit)
                        }
                }
                .accessibilityIdentifier("browser-favorite-folder-\(item.id)")
            } else {
                favoritePage(item)
            }
        }
        .onMove { state.favorites.reorder(in: parentID, from: $0, to: $1) }
    }

    @ViewBuilder
    private func favoritePage(_ item: BrowserFavoriteEntry) -> some View {
#if os(macOS)
        Button {
            // A saved favorite remains clickable even after its live tab closes.
            if state.tab(forFavorite: item.id) == nil { state.openFavorite(item.id) }
        } label: {
            pageLabel(item).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .modifier(BrowserSidebarRowHover(isSelected: state.tab(forFavorite: item.id).map {
                state.selectedTabIDs.contains($0.id)
            } ?? false))
            .tag(BrowserSidebarSelection.favorite(item.id))
            .accessibilityIdentifier("browser-favorite-page-\(item.id)")
#else
        NavigationLink(value: BrowserSidebarSelection.favorite(item.id)) { pageLabel(item) }
            .tag(BrowserSidebarSelection.favorite(item.id))
            .accessibilityIdentifier("browser-favorite-page-\(item.id)")
            .contextMenu { BrowserFavoriteActions(state: state, ids: [item.id], onEdit: onEdit) }
#endif
    }

    private func pageLabel(_ item: BrowserFavoriteEntry) -> some View {
        Label { Text(item.title).lineLimit(1) } icon: { BrowserFaviconView(pageURL: item.url) }
            .help(item.url?.absoluteString ?? item.title)
    }
}

@MainActor
struct BrowserFavoriteActions: View {
    let state: BrowserWorkspaceState
    let ids: Set<UUID>
    let onEdit: (BrowserFavoriteDraft) -> Void

    private var selected: [BrowserFavoriteEntry] { state.favorites.entries.filter { ids.contains($0.id) } }

    var body: some View {
        if !selected.isEmpty {
            if selected.allSatisfy({ $0.kind == .page }) {
                Button(selected.count == 1 ? "Open favorite" : "Open favorites") {
                    for item in selected { state.openFavorite(item.id) }
                }
                if selected.contains(where: { state.tab(forFavorite: $0.id) != nil }) {
                    Button("Close page") {
                        for item in selected { if let tab = state.tab(forFavorite: item.id) { state.close(tab.id) } }
                    }
                }
            }
            if selected.count == 1, let item = selected.first {
                Button("Rename…", systemImage: "pencil") { onEdit(.init(entryID: item.id, parentID: item.parentID, title: item.title)) }
            }
            Menu("Move to folder") {
                Button("Favorites") { for id in ids { _ = state.favorites.move(id, into: nil) } }
                ForEach(state.favorites.folders.filter { folder in ids.allSatisfy { state.favorites.canMove($0, into: folder.id) } }) { folder in
                    Button(state.favorites.folderPath(folder.id)) { for id in ids { _ = state.favorites.move(id, into: folder.id) } }
                }
                Divider()
                Button("New folder…") { onEdit(.init(favoriteIDs: ids)) }
            }
            Button(selected.allSatisfy({ $0.kind == .folder }) ? "Remove folder (keep contents)" : "Unpin from Favorites", systemImage: "pin.slash") {
                state.removeFavorites(ids)
            }
        }
    }
}

@MainActor
struct BrowserFavoriteEditor: View {
    let state: BrowserWorkspaceState
    @State var draft: BrowserFavoriteDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $draft.title)
                    .accessibilityIdentifier("browser-favorite-name")
                    .onSubmit(save)
                Picker("Folder", selection: $draft.parentID) {
                    Text("Favorites").tag(Optional<UUID>.none)
                    ForEach(state.favorites.folders.filter { folder in
                        draft.entryID.map { state.favorites.canMove($0, into: folder.id) }
                            ?? draft.favoriteIDs.allSatisfy { state.favorites.canMove($0, into: folder.id) }
                    }) { folder in
                        Text(state.favorites.folderPath(folder.id)).tag(Optional(folder.id))
                    }
                }
            }
            .padding()
            .navigationTitle(draft.entryID == nil ? "New Favorites folder" : "Edit favorite")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("browser-favorite-save")
                }
            }
        }
#if os(macOS)
        .frame(width: 380, height: 220)
#endif
    }

    private func save() {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let id = draft.entryID {
            guard state.favorites.canMove(id, into: draft.parentID) else { return }
            state.favorites.rename(id, title: draft.title)
            _ = state.favorites.move(id, into: draft.parentID)
        } else {
            guard let folder = state.favorites.createFolder(title: draft.title, in: draft.parentID) else { return }
            for id in draft.favoriteIDs { _ = state.favorites.move(id, into: folder) }
            for id in draft.tabIDs { _ = state.pinTab(id, in: folder) }
        }
        dismiss()
    }
}
