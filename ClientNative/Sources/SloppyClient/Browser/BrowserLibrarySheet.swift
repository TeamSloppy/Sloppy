import SwiftUI
import SloppyClientUI
#if os(macOS)
import AppKit
#endif

@MainActor
struct BrowserLibrarySheet: View {
    let section: BrowserLibrarySection
    let state: BrowserWorkspaceState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                switch section {
                case .history:
                    List {
                        ForEach(state.history.sites.filter { matches($0.title, $0.url) }) { site in
                            pageRow(title: site.title, url: site.url)
                        }
                    }
                    .overlay { if state.history.sites.isEmpty { empty("No browsing history yet", icon: "clock") } }
                case .bookmarks:
                    List {
                        if let tab = state.selectedTab, let url = tab.url {
                            Button(state.library.isBookmarked(url) ? "Remove current bookmark" : "Bookmark current page") {
                                state.library.toggleBookmark(url: url, title: tab.title)
                            }
                        }
                        ForEach(state.library.bookmarks.filter { matches($0.title, $0.url) }) { bookmark in
                            HStack {
                                pageRow(title: bookmark.title, url: bookmark.url)
                                Button { state.library.removeBookmark(bookmark.id) } label: { Image(systemName: "trash") }
                                    .accessibilityLabel("Remove bookmark")
                            }
                        }
                    }
                    .overlay { if state.library.bookmarks.isEmpty && state.selectedTab == nil { empty("No bookmarks yet", icon: "bookmark") } }
                case .downloads:
                    List(state.library.downloads.filter { query.isEmpty || $0.filename.localizedCaseInsensitiveContains(query) }) { item in
                        HStack(spacing: 12) {
                            Image(systemName: "doc")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.filename).lineLimit(1)
                                Text(item.error ?? item.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.status == .downloading {
                                ProgressView().controlSize(.small)
                                Button("Cancel") { state.library.cancel(item.id) }
                            } else if item.status == .completed, let url = item.fileURL {
#if os(macOS)
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
#else
                                ShareLink(item: url)
#endif
                            } else if let url = item.sourceURL {
                                Button("Try again") { open(url) }
                            }
                        }
                    }
                    .overlay { if state.library.downloads.isEmpty { empty("No downloads yet", icon: "arrow.down.circle") } }
                }
            }
            .searchable(text: $query)
            .navigationTitle(section.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .automatic) {
                    if section == .history {
                        Button("Clear history") { state.history.clear() }.disabled(state.history.sites.isEmpty)
                    } else if section == .downloads {
                        Button("Clear finished") { state.library.clearFinishedDownloads() }
                            .help("Remove finished entries from the list. Downloaded files are kept.")
                    }
                }
            }
        }
#if os(macOS)
        .frame(width: 660, height: 480)
#else
        .presentationDetents([.large])
#endif
    }

    private func matches(_ title: String, _ url: URL) -> Bool {
        query.isEmpty || title.localizedCaseInsensitiveContains(query) || url.absoluteString.localizedCaseInsensitiveContains(query)
    }

    private func pageRow(title: String, url: URL) -> some View {
        Button { open(url) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).lineLimit(1)
                Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open(_ url: URL) { state.open(url, inNewTab: true); dismiss() }
    private func empty(_ title: String, icon: String) -> some View {
        ContentUnavailableView(title, systemImage: icon)
    }
}
