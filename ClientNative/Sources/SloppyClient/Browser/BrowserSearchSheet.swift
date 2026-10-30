import SwiftUI
import SloppyClientUI

@MainActor
struct BrowserSearchSheet: View {
    @Bindable var state: BrowserWorkspaceState
    let onAskAgent: (String) -> Void
    var maximumResultsHeight: CGFloat = 304
    @Environment(\.theme) private var theme
    @FocusState private var isFocused: Bool
    @State private var selectedID: String?

    private var results: [BrowserSearchResult] {
        BrowserSearchResult.make(query: state.searchText, engine: state.searchEngine, tabs: state.tabs,
              bookmarks: state.library.bookmarks, history: state.history.sites)
    }
    private var selection: BrowserSearchResult? { results.first { $0.id == selectedID } ?? results.first }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 23, weight: .regular)).foregroundStyle(.secondary)
#if os(macOS)
                BrowserSearchField(text: $state.searchText, selectsAddress: !state.searchInNewTab,
                                   onMove: move, onSubmit: submit, onAskAgent: askAgent, onClose: close)
                    .accessibilityLabel("Search or enter an address")
                    .accessibilityIdentifier("browser-search-input")
#else
                TextField("Search or enter an address", text: $state.searchText)
                    .textFieldStyle(.plain).font(.system(size: 22))
                    .focused($isFocused).onSubmit(submit)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.go)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
                    .accessibilityLabel("Search or enter an address")
                    .accessibilityIdentifier("browser-search-input")
#endif
                if !state.searchText.isEmpty {
                    Button { state.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .accessibilityLabel("Clear search")
                }
#if os(macOS)
                keyHint("esc")
#endif
            }
            .padding(.horizontal, 20)
            .frame(height: 68)
            if !results.isEmpty {
                Divider().opacity(0.5)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(results) { result in resultRow(result).id(result.id) }
                        }
                        .padding(8)
                    }
                    .frame(height: min(maximumResultsHeight, CGFloat(results.count) * 50 + 16))
                    .onChange(of: selectedID) { _, id in
                        if let id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            Divider().opacity(0.5)
            footer
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.colors.textPrimary)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-search-launcher")
        .onChange(of: state.searchText) { _, _ in selectedID = results.first?.id }
        .task { isFocused = true }
#if os(macOS)
        .onExitCommand(perform: close)
#endif
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Menu {
                Picker("Search engine", selection: $state.searchEngine) {
                    ForEach(BrowserSearchEngine.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                    Text(state.searchEngine.title)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
            }
#if os(macOS)
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
#endif
            .accessibilityLabel("Search engine")
            Spacer(minLength: 8)
#if os(macOS)
            if let selection {
                Text(selection.actionTitle).font(.system(size: 11))
                keyHint("↩")
            }
#endif
            Button(action: askAgent) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                    Text("Ask agent")
#if os(macOS)
                    keyHint("⌘↩")
#endif
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityIdentifier("browser-ask-agent")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    private func resultRow(_ result: BrowserSearchResult) -> some View {
        Button { activate(result) } label: {
            HStack(spacing: 12) {
                Image(systemName: result.symbol).font(.system(size: 17)).frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Text(result.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                Text(result.category).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .contentShape(Rectangle())
            .background(selection?.id == result.id ? theme.colors.textPrimary.opacity(0.09) : .clear,
                        in: RoundedRectangle(cornerRadius: 12))
        }
        .onHover { if $0 { selectedID = result.id } }
        .accessibilityIdentifier("browser-search-result-\(result.id)")
    }

    private func keyHint(_ text: String) -> some View {
        Text(text).font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary).padding(.horizontal, 4).padding(.vertical, 2)
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.08)) }
            .accessibilityHidden(true)
    }
    private func move(_ offset: Int) {
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selection?.id } ?? 0
        selectedID = results[min(max(index + offset, 0), results.count - 1)].id
    }
    private func submit() { if let selection { activate(selection) } }
    private func close() { state.isSearchPresented = false }
    private func askAgent() { let text = state.searchText; close(); onAskAgent(text) }
    private func activate(_ result: BrowserSearchResult) {
        switch result.target {
        case .tab(let id): state.select(id); state.isBrowsing = true
        case .destination(let url), .bookmark(let url), .history(let url): state.open(url, inNewTab: state.searchInNewTab)
        }
        close()
    }
}
