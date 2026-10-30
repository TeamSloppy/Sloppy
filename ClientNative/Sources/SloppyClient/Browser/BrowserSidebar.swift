import SwiftUI
import SloppyClientUI

enum BrowserSidebarSelection: Hashable { case home, tab(UUID) }
enum BrowserLibrarySection: String, Identifiable {
    case history, downloads, bookmarks
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private struct BrowserGroupDraft: Identifiable {
    var id = UUID()
    var groupID: UUID?
    var tabIDs: [UUID] = []
    var title = ""
}

@MainActor
struct BrowserSidebar: View {
    @Bindable var state: BrowserWorkspaceState
    let onLibrary: (BrowserLibrarySection) -> Void
    let onSettings: () -> Void
    let onCollect: ([BrowserTabRecord]) -> Void
    @State private var groupDraft: BrowserGroupDraft?
#if os(macOS)
    @State private var showsExtensions = false
    @State private var hoveredTabID: UUID?
#endif

    var body: some View {
        sidebarList
        .listStyle(.sidebar)
#if os(macOS)
        .scrollEdgeEffectStyle(.hard, for: .top)
#endif
        .safeAreaInset(edge: .top, spacing: 0) {
            BrowserNavigationControls(state: state)
#if os(macOS)
                .background(.bar, ignoresSafeAreaEdges: .top)
#endif
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    Menu {
                        Button("Settings", systemImage: "gearshape", action: onSettings)
                        Button("History", systemImage: "clock") { onLibrary(.history) }
                        Button("Downloads", systemImage: "arrow.down.circle") { onLibrary(.downloads) }
                        Button("Bookmarks", systemImage: "bookmark") { onLibrary(.bookmarks) }
#if os(macOS)
                        Button("Web Extensions…", systemImage: "puzzlepiece.extension") { showsExtensions = true }
#endif
                        Divider()
                        Button("New tab group", systemImage: "folder.badge.plus") { groupDraft = .init() }
                        Button("Collect tabs on canvas", systemImage: "square.grid.2x2") { onCollect(state.tabs) }
                            .disabled(state.isCollecting || state.tabs.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis").font(.body.weight(.medium))
                    }
#if os(macOS)
                    .menuIndicator(.hidden)
                    .menuStyle(.borderlessButton)
#endif
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Browser menu")
                    .accessibilityIdentifier("browser-menu")
                }
                .frame(height: 52)
                .padding(.horizontal, 12)
            }
        }
        .sheet(item: $groupDraft) { draft in
            BrowserGroupNameSheet(state: state, groupID: draft.groupID, tabIDs: draft.tabIDs, title: draft.title)
        }
#if os(macOS)
        .sheet(isPresented: $showsExtensions) { BrowserExtensionsSheet(extensions: state.extensions) }
#endif
    }


    @ViewBuilder
    private var sidebarList: some View {
#if os(macOS)
        List(selection: Binding<Set<BrowserSidebarSelection>>(get: {
            state.selectedID == nil ? [.home] : Set(state.selectedTabIDs.map(BrowserSidebarSelection.tab))
        }, set: { selection in
            let ids = Set(selection.compactMap { item -> UUID? in
                if case .tab(let id) = item { return id }
                return nil
            })
            if !ids.isEmpty { state.selectTabs(ids) }
            else if selection.contains(.home) { state.showHome() }
        })) { sidebarRows }
        .contextMenu(forSelectionType: BrowserSidebarSelection.self) { selection in
            let ids = Set(selection.compactMap { item -> UUID? in
                if case .tab(let id) = item { return id }
                return nil
            })
            tabContextMenu(ids)
        }
#else
        List(selection: Binding<BrowserSidebarSelection?>(get: {
            state.selectedID.map(BrowserSidebarSelection.tab) ?? .home
        }, set: { selection in
            switch selection {
            case .home: state.showHome()
            case .tab(let id): state.select(id)
            case nil: break
            }
        })) { sidebarRows }
#endif
    }

    @ViewBuilder
    private var homeRow: some View {
#if os(macOS)
        Label("Home", systemImage: "house")
#else
        NavigationLink(value: BrowserSidebarSelection.home) { Label("Home", systemImage: "house") }
#endif
    }

    @ViewBuilder
    private var sidebarRows: some View {
        homeRow
            .tag(BrowserSidebarSelection.home)
            .accessibilityIdentifier("browser-home-button")
        Section {
            tabRows(groupID: nil)
            ForEach(state.groups) { group in
                DisclosureGroup(isExpanded: Binding(get: { !group.isCollapsed }, set: { _ in state.toggleGroup(group.id) })) {
                    tabRows(groupID: group.id)
                } label: {
                    Label(group.title, systemImage: "folder")
                        .contextMenu {
                            Button("Rename group") { groupDraft = .init(groupID: group.id, title: group.title) }
                            Button("Remove group") { state.removeGroup(group.id) }
                        }
                }
            }
        } header: {
            HStack {
                Text("Tabs")
                Spacer()
                Button { state.presentSearch(newTab: true) } label: {
                    Image(systemName: "plus").frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New tab")
                .accessibilityIdentifier("browser-new-tab")
                .help("New tab (⌘T)")
            }
        }
    }

    @ViewBuilder
    func tabContextMenu(_ ids: Set<UUID>) -> some View {
        if !ids.isEmpty {
#if os(macOS)
            if ids.count >= 2 {
                Button("Combine in Split View", systemImage: "rectangle.split.2x1") { state.combineTabsInSplit(ids) }
                    .accessibilityIdentifier("browser-combine-split")
            }
            let member = state.tabs.first(where: { tab in
                ids.contains(tab.id) && state.splits.contains { $0.tabIDs.contains(tab.id) }
            })
            if let member {
                Button("Separate Split View", systemImage: "rectangle") { state.separateSplit(containing: member.id) }
            }
            if ids.count >= 2 || member != nil { Divider() }
#endif
            Menu("Move to group") {
                Button("Ungrouped") { for id in ids { state.assign(id, to: nil) } }
                ForEach(state.groups) { group in
                    Button(group.title) { for id in ids { state.assign(id, to: group.id) } }
                }
                Divider()
                Button("New group…") { groupDraft = .init(tabIDs: Array(ids)) }
            }
            Button(ids.count == 1 ? "Close tab" : "Close tabs", role: .destructive) {
                for tab in state.tabs where ids.contains(tab.id) { state.close(tab.id) }
            }
        }
    }

    @ViewBuilder
    private func tabLink(_ tab: BrowserTabRecord) -> some View {
#if os(macOS)
        tabLabel(tab)
#else
        NavigationLink(value: BrowserSidebarSelection.tab(tab.id)) {
            tabLabel(tab)
        }
#endif
    }

    private func tabLabel(_ tab: BrowserTabRecord) -> some View {
        Label {
            Text(tab.title).lineLimit(1)
        } icon: {
            BrowserFaviconView(pageURL: tab.url)
        }
    }

    @ViewBuilder private func tabRow(_ tab: BrowserTabRecord) -> some View {
#if os(macOS)
        HStack(spacing: 4) {
            tabLink(tab)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAction(named: "Close tab") { state.close(tab.id) }
            if state.splits.contains(where: { $0.tabIDs.contains(tab.id) }) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .help("Part of a split view")
            }
            Button {
                hoveredTabID = nil
                state.close(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .opacity(hoveredTabID == tab.id ? 1.0 : 0.0)
            .allowsHitTesting(hoveredTabID == tab.id)
            .accessibilityHidden(hoveredTabID != tab.id)
            .help("Close tab")
            .accessibilityLabel("Close tab: \(tab.title)")
            .accessibilityIdentifier("browser-close-tab-\(tab.id)")
        }
        .onHover { hovering in
            if hovering { hoveredTabID = tab.id }
            else if hoveredTabID == tab.id { hoveredTabID = nil }
        }
#else
        tabLink(tab)
#endif
    }

    private func tabRows(groupID: UUID?) -> some View {
        ForEach(state.tabs.filter { $0.groupID == groupID }) { tab in
            tabRow(tab)
            .tag(BrowserSidebarSelection.tab(tab.id))
            .accessibilityIdentifier("browser-tab-\(tab.id)")
#if !os(macOS)
            .contextMenu {
                tabContextMenu([tab.id])
            }
#endif
        }
        .onMove { state.move(in: groupID, from: $0, to: $1) }
        .onDelete { offsets in
            let tabs = state.tabs.filter { $0.groupID == groupID }
            offsets.map { tabs[$0].id }.forEach { state.close($0) }
        }
    }
}

@MainActor
private struct BrowserGroupNameSheet: View {
    let state: BrowserWorkspaceState
    let groupID: UUID?
    let tabIDs: [UUID]
    @State var title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form { TextField("Group name", text: $title).onSubmit(save) }
                .navigationTitle(groupID == nil ? "New tab group" : "Rename group")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
        .frame(minWidth: 320, minHeight: 160)
    }
    private func save() {
        if let group = state.saveGroup(title: title, id: groupID) {
            for id in tabIDs { state.assign(id, to: group) }
            dismiss()
        }
    }
}
