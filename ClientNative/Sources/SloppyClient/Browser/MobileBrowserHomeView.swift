#if os(iOS)
import SwiftUI

@MainActor
struct MobileBrowserHomeView: View {
    let state: BrowserWorkspaceState
    let onLibrary: (BrowserLibrarySection) -> Void
    let onSearch: () -> Void
    let onAskAgent: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                HStack {
                    Label("Browse", systemImage: "globe").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button { onLibrary(.history) } label: { Image(systemName: "clock.arrow.circlepath").frame(width: 44, height: 44) }
                        .accessibilityLabel("History")
                    Button { onLibrary(.bookmarks) } label: { Image(systemName: "book").frame(width: 44, height: 44) }
                        .accessibilityLabel("Bookmarks")
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Where to next?").font(.largeTitle.bold()).tracking(-1)
                    Text("A new idea. A useful find. Your next project.")
                        .font(.body).foregroundStyle(.secondary)
                    Button(action: onAskAgent) {
                        Label("Explore with your assistant", systemImage: "sparkles")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("browser-home-ask-agent")
                }
                if !state.history.frequentSites().isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Top sites").font(.title2.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 110))], spacing: 20) {
                            ForEach(state.history.frequentSites()) { site in
                                Button { state.open(site.url, inNewTab: state.selectedTab?.url != nil) } label: {
                                    VStack(spacing: 10) {
                                        BrowserFaviconView(pageURL: site.url, size: 30)
                                            .frame(width: 60, height: 60)
                                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                                        Text(site.id).font(.caption).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("browser-frequent-site-\(site.id)")
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recently visited").font(.title2.bold())
                    if state.history.sites.isEmpty {
                        Text("Pages you visit will appear here.").foregroundStyle(.secondary)
                        Button("Search the web", action: onSearch).frame(minHeight: 44)
                    } else {
                        ForEach(state.history.sites.prefix(5)) { site in
                            Button { state.open(site.url, inNewTab: state.selectedTab?.url != nil) } label: {
                                HStack(spacing: 12) {
                                    BrowserFaviconView(pageURL: site.url, size: 24)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(site.title).font(.body).lineLimit(1)
                                        Text(site.url.host ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(minHeight: 52).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-mobile-home")
    }
}
#endif
