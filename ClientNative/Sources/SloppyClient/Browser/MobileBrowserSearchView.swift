#if os(iOS)
import SwiftUI
import SloppyClientUI

@MainActor
struct MobileBrowserSearchView: View {
    @Bindable var state: BrowserWorkspaceState
    let onAskAgent: (String) -> Void
    @State private var isFocused = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var query: String { state.searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var showsLibrary: Bool {
        query.isEmpty || (!state.searchInNewTab && state.searchText == state.selectedTab?.url?.absoluteString)
    }
    private var results: [BrowserSearchResult] {
        BrowserSearchResult.make(query: showsLibrary ? "" : state.searchText, engine: state.searchEngine,
                                 tabs: state.tabs.filter { $0.url != nil }, bookmarks: state.library.bookmarks, history: state.history.sites)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .medium))
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("Cancel")
                .accessibilityIdentifier("browser-search-close")
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if showsLibrary { topSites }
                    if !results.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(showsLibrary ? "Open tabs & bookmarks" : "Suggestions")
                                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                            ForEach(results) { result in resultRow(result) }
                        }
                    } else if state.history.frequentSites().isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Where to next?").font(.largeTitle.bold()).tracking(-1)
                            Text("Search the web, open a website or ask Sloppy.")
                                .font(.body).foregroundStyle(.secondary)
                        }
                        .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 20)
                .frame(maxWidth: 720).frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            searchDock
                .frame(maxWidth: 760)
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { backdrop.ignoresSafeArea(.container) }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-search-overlay")
        .task {
            await Task.yield()
            isFocused = true
        }
        .onDisappear { isFocused = false }
    }

    private var backdrop: some View {
        ZStack {
            if reduceTransparency {
                Color(uiColor: .systemBackground)
            } else {
                Rectangle().fill(.ultraThinMaterial)
                Color(uiColor: .systemBackground).opacity(colorScheme == .dark ? 0.78 : 0.8)
            }
        }
    }

    @ViewBuilder
    private var topSites: some View {
        let sites = state.history.frequentSites()
        if !sites.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Top sites").font(.title3.weight(.medium)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 116), spacing: 12)], spacing: 18) {
                    ForEach(sites) { site in
                        Button { open(site.url) } label: {
                            VStack(spacing: 8) {
                                BrowserFaviconView(pageURL: site.url, size: 32)
                                    .frame(width: 76, height: 76)
                                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.08)) }
                                Text(site.id).font(.caption).lineLimit(1).truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(site.id)")
                        .accessibilityIdentifier("browser-search-site-\(site.id)")
                    }
                }
            }
        }
    }

    private func resultRow(_ result: BrowserSearchResult) -> some View {
        Button { activate(result) } label: {
            HStack(spacing: 14) {
                Image(systemName: result.symbol).font(.system(size: 19)).foregroundStyle(.secondary).frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title).font(.body.weight(.medium)).lineLimit(1)
                    Text("\(result.category) · \(result.subtitle)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 9).frame(minHeight: 56).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("browser-search-result-\(result.id)")
    }

    private var searchDock: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 10) {
                HStack {
                    Menu {
                        Picker("Search engine", selection: $state.searchEngine) {
                            ForEach(BrowserSearchEngine.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                            Text(state.searchEngine.title)
                            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                        }
                        .font(.subheadline).padding(.horizontal, 14).frame(minHeight: 44).contentShape(Capsule())
                    }
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .accessibilityLabel("Search engine")
                    Spacer(minLength: 12)
                    Button {
                        let text = state.searchText
                        onAskAgent(text)
                        close()
                    } label: {
                        HStack(spacing: 7) {
                            SloppyAssets.projectLogo.renderingMode(.template).resizable().scaledToFit().frame(width: 18, height: 18)
                            Text("Ask Sloppy")
                        }
                        .font(.subheadline.weight(.medium)).padding(.horizontal, 14)
                        .frame(minHeight: 44).contentShape(Capsule())
                    }
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .disabled(query.isEmpty)
                    .accessibilityLabel("Ask agent")
                    .accessibilityIdentifier("browser-ask-agent")
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(.secondary)
                    MobileBrowserSearchField(text: $state.searchText,
                        isFocused: $isFocused,
                        selectsAddress: !state.searchInNewTab && state.searchText == state.selectedTab?.url?.absoluteString,
                        onSubmit: submit, onCancel: close)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 44)
                    if !state.searchText.isEmpty {
                        Button { state.searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Clear search")
                    }
                    Button(action: submit) {
                        Image(systemName: "arrow.right").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white).frame(width: 44, height: 44)
                            .background(Color.accentColor, in: Circle()).contentShape(Circle())
                    }
                    .disabled(query.isEmpty).opacity(query.isEmpty ? 0.45 : 1)
                    .accessibilityLabel("Go")
                    .accessibilityIdentifier("browser-search-go")
                }
                .padding(.leading, 16).padding(.trailing, 6)
                .frame(minHeight: 56)
                .glassEffect(.regular, in: Capsule())
            }
        }
        .buttonStyle(.plain)
    }

    private func close() { isFocused = false; state.isSearchPresented = false }
    private func submit() { if let url = state.searchEngine.destination(for: state.searchText) { open(url) } }
    private func open(_ url: URL) { state.open(url, inNewTab: state.searchInNewTab); close() }
    private func activate(_ result: BrowserSearchResult) {
        switch result.target {
        case .tab(let id): state.select(id); close()
        case .destination(let url), .bookmark(let url), .history(let url): open(url)
        }
    }
}
#endif
