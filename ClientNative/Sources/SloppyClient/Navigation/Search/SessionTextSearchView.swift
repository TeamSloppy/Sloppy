import Foundation
import SloppyClientCore
import SloppyClientUI
import SwiftUI

struct SessionTextSearchView: View {
    let endpoints: [SloppyInstanceEndpoint]
    let apiClient: SloppyAPIClient
    let onOpenSession: @MainActor (LocatedTextSearchHit) -> Void
    @State var query = ""
    @State private var mode = TextSearchMode.text
    @State private var state = SessionTextSearchState()
    @State private var offset = 0
    @State private var selected: LocatedTextSearchHit?
    @State private var document: TextSearchDocumentResponse?
    @State private var documentError: String?
    @Environment(\.dismiss) private var dismiss

    init(endpoints: [SloppyInstanceEndpoint], apiClient: SloppyAPIClient, onOpenSession: @escaping @MainActor (LocatedTextSearchHit) -> Void,
         query: String = "", selected: LocatedTextSearchHit? = nil) {
        self.endpoints = endpoints
        self.apiClient = apiClient
        self.onOpenSession = onOpenSession
        _query = State(initialValue: query)
        _selected = State(initialValue: selected)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
#if !os(iOS)
                    TextField("Search messages, code, and tool output", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("global-search.query")
#endif
                    Picker("Search mode", selection: $mode) {
                        Text("Text contains").tag(TextSearchMode.text)
                        Text("Words").tag(TextSearchMode.words)
                    }
                    .pickerStyle(.segmented)
#if !os(iOS)
                    .frame(maxWidth: 220)
#endif
                }
                .padding()
                if query.count > 0 && query.count < 3 {
                    Text("Short queries match the beginning of a word.").font(.caption).foregroundStyle(.secondary)
                }
                if state.isLoading { ProgressView("Searching…").padding(8) }
                if state.isIndexing { Text("Indexing history; results are incomplete.").font(.caption).padding(8) }
                if state.failedSources > 0 { Text("\(state.failedSources) journals could not be indexed.").font(.caption).padding(8) }
                if let error = state.error { Text("Search unavailable: \(error)").font(.caption).foregroundStyle(.red).padding() }
                List(state.items) { item in
                    Button { selected = item } label: { SessionTextSearchHitRow(hit: item.hit) }
                        .buttonStyle(.plain)
                }
                .overlay {
                    if !query.isEmpty && state.items.isEmpty && !state.isLoading && !state.isIndexing && state.error == nil {
                        ContentUnavailableView.search(text: query)
                    }
                }
                HStack {
                    Button("Previous") { offset = max(0, offset - 50) }.disabled(offset == 0 || state.isLoading)
                    Spacer()
                    Button("Next") { offset += 50 }.disabled(!state.hasMore || state.isLoading)
                }.padding()
            }
            .navigationTitle("Search all conversations")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .onChange(of: query) { _, _ in offset = 0 }
            .onChange(of: mode) { _, _ in offset = 0 }
            .task(id: "\(query)|\(mode.rawValue)|\(offset)|\(String(describing: endpoints))") {
                await state.search(query, endpoints: endpoints, primaryClient: apiClient, mode: mode, offset: offset)
            }
            .sheet(item: $selected) { item in
                NavigationStack {
                    ScrollView {
                        if let document { Text(document.text).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                        else if let documentError { Text(documentError).foregroundStyle(.red).padding() }
                        else { ProgressView("Loading message…").padding() }
                    }
                    .navigationTitle(item.hit.title)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Back") { selected = nil } }
                        if item.hit.source == "agent" {
                            ToolbarItem(placement: .primaryAction) { Button("Open chat") { onOpenSession(item); dismiss() } }
                        }
                    }
                    .task(id: item.id) {
                        document = nil
                        documentError = nil
                        do {
                            let client = item.endpoint == apiClient.endpoint ? apiClient : SloppyAPIClient(endpoint: item.endpoint)
                            let loaded = try await client.fetchSearchDocument(id: item.hit.id)
                            guard !Task.isCancelled else { return }
                            document = loaded
                        } catch { if !Task.isCancelled { documentError = error.localizedDescription } }
                    }
                }
                .mobileScreenBackground()
#if os(macOS)
                .frame(minWidth: 560, minHeight: 400)
#endif
            }
        }
#if os(iOS)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search all messages")
#endif
        .mobileScreenBackground()
#if os(macOS)
        .frame(minWidth: 680, minHeight: 500)
#endif
    }
}

struct SessionTextSearchHitRow: View {
    let hit: TextSearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hit.title).font(.headline).lineLimit(1)
            Text([hit.agentId ?? "Channel", hit.role ?? hit.kind.replacingOccurrences(of: "_", with: " ")].joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            Text(highlightedSnippet).font(.callout).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var highlightedSnippet: AttributedString {
        var result = AttributedString()
        let segments = hit.snippet.components(separatedBy: "\u{E000}")
        for (index, part) in segments.enumerated() {
            let pieces = part.components(separatedBy: "\u{E001}")
            var text = AttributedString(pieces[0])
            if index > 0 { text.font = .body.bold() }
            result += text
            if pieces.count > 1 { result += AttributedString(pieces.dropFirst().joined()) }
        }
        return result
    }
}
