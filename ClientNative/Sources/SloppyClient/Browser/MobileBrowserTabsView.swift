#if os(iOS)
import SwiftUI

@MainActor
struct MobileBrowserTabsView: View {
    let state: BrowserWorkspaceState
    let snapshots: [UUID: UIImage]
    let onNewTab: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var groupID: UUID?
    @State private var confirmsClosingTabs = false

    private var tabs: [BrowserTabRecord] {
        state.tabs.filter { tab in
            (groupID == nil || tab.groupID == groupID) &&
                (query.isEmpty || tab.title.localizedCaseInsensitiveContains(query) ||
                 tab.url?.absoluteString.localizedCaseInsensitiveContains(query) == true)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 16)], spacing: 24) {
                    ForEach(tabs) { tab in tabCard(tab) }
                }
                .padding(20)
                .frame(maxWidth: 1040).frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .overlay {
                if tabs.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "No open tabs" : "No matching tabs",
                                           systemImage: "square.on.square",
                                           description: Text(query.isEmpty ? "Open a new tab to start browsing." : "Try a different title or address."))
                }
            }
            .navigationTitle("Tabs")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Find a tab")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Tab group", selection: $groupID) {
                            Text("All tabs").tag(UUID?.none)
                            ForEach(state.groups) { Text($0.title).tag(Optional($0.id)) }
                        }
                        Divider()
                        Button("Close \(tabs.count) tabs", systemImage: "trash", role: .destructive) {
                            confirmsClosingTabs = true
                        }
                        .disabled(tabs.isEmpty)
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Tab options")
                    .accessibilityIdentifier("browser-tab-options")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    Button { onNewTab() } label: { Label("New tab", systemImage: "plus") }
                        .accessibilityIdentifier("browser-overview-new-tab")
                }
            }
            .confirmationDialog("Close \(tabs.count) tabs?", isPresented: $confirmsClosingTabs, titleVisibility: .visible) {
                Button("Close tabs", role: .destructive) { tabs.map(\.id).forEach(state.close) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-mobile-tabs")
    }

    private func tabCard(_ tab: BrowserTabRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Button {
                    state.select(tab.id)
                    dismiss()
                } label: {
                    GeometryReader { geometry in
                        ZStack {
                            Color(uiColor: .secondarySystemGroupedBackground)
                            if let image = snapshots[tab.id] {
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .clipped()
                            } else {
                                VStack(spacing: 14) {
                                    BrowserFaviconView(pageURL: tab.url, size: 36)
                                    Text(tab.url?.host ?? "New tab").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                .padding(20)
                            }
                        }
                    }
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(tab.id == state.selectedID ? Color.blue : .clear, lineWidth: 3)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(tab.title)")
                .accessibilityAddTraits(tab.id == state.selectedID ? .isSelected : [])
                .accessibilityIdentifier("browser-tab-\(tab.id)")
                Button { state.close(tab.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                        .frame(width: 36, height: 36).background(.regularMaterial, in: Circle())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("Close \(tab.title)")
                .accessibilityIdentifier("browser-close-tab-\(tab.id)")
            }
            HStack(spacing: 6) {
                BrowserFaviconView(pageURL: tab.url, size: 16)
                Text(tab.title).font(.subheadline).lineLimit(1)
            }
            .accessibilityHidden(true)
        }
        .contextMenu {
            Menu("Move to group") {
                Button("No group") { state.assign(tab.id, to: nil) }
                ForEach(state.groups) { group in
                    Button(group.title) { state.assign(tab.id, to: group.id) }
                }
            }
            if let url = tab.url { ShareLink(item: url) }
            Button("Close tab", systemImage: "xmark", role: .destructive) { state.close(tab.id) }
        }
    }
}
#endif
