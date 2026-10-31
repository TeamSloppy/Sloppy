#if os(iOS)
import SwiftUI

@MainActor
struct MobileBrowserMenu: View {
    @Bindable var state: BrowserWorkspaceState
    let onLibrary: (BrowserLibrarySection) -> Void
    let onSettings: () -> Void
    let onWork: () -> Void
    let onCollect: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsNewGroup = false
    @State private var groupName = ""

    var body: some View {
        NavigationStack {
            List {
                if let tab = state.selectedTab, let url = tab.url {
                    Section {
                        ShareLink(item: url)
                        Button {
                            state.library.toggleBookmark(url: url, title: tab.title)
                        } label: {
                            Label(state.library.isBookmarked(url) ? "Remove bookmark" : "Bookmark page", systemImage: "bookmark")
                        }
                    } header: { Text(url.host ?? tab.title).textCase(nil) }
                }
                Section {
                    Button { onLibrary(.history) } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                    Button { onLibrary(.bookmarks) } label: { Label("Bookmarks", systemImage: "book") }
                    Button { onLibrary(.downloads) } label: { Label("Downloads", systemImage: "arrow.down.circle") }
                }
                Section {
                    Picker("Search engine", selection: $state.searchEngine) {
                        ForEach(BrowserSearchEngine.allCases) { Text($0.title).tag($0) }
                    }
                    Button { showsNewGroup = true } label: { Label("New tab group", systemImage: "folder.badge.plus") }
                    Button(action: onCollect) { Label("Collect tabs on canvas", systemImage: "square.grid.2x2") }
                        .disabled(state.tabs.isEmpty || state.isCollecting)
                }
                Section {
                    Button(action: onSettings) { Label("Settings", systemImage: "gearshape") }
                    Button(action: onWork) { Label("Return to Work", systemImage: "briefcase") }
                        .accessibilityIdentifier("browser-return-to-work")
                }
            }
            .navigationTitle("Browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("New tab group", isPresented: $showsNewGroup) {
                TextField("Group name", text: $groupName)
                Button("Cancel", role: .cancel) { groupName = "" }
                Button("Create") {
                    state.saveGroup(title: groupName, tabID: state.selectedID)
                    groupName = ""
                }
                .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
#endif
