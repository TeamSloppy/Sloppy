#if os(iOS)
import Foundation
import SloppyClientCore
import SloppyClientUI
import SwiftUI

struct IOSInboxSearchPresentation: Identifiable {
    let id = UUID()
    let query: String
    var selected: LocatedTextSearchHit?
}

@MainActor
struct IOSInboxSearchResults: View {
    let query: String
    let sessions: [ChatSessionSummary]
    let projects: [APIProjectRecord]
    let endpoints: [SloppyInstanceEndpoint]
    let apiClient: SloppyAPIClient
    let onOpenSession: @MainActor (ChatSessionSummary) -> Void
    let onOpenMessage: @MainActor (LocatedTextSearchHit) -> Void
    let onSearchText: @MainActor () -> Void
    let onOpenProject: @MainActor (APIProjectRecord) -> Void

    @State private var messageSearch = SessionTextSearchState()
    @Environment(\.theme) private var theme

    private var chatResults: [ChatSessionSummary] {
        sessions.filter { $0.title.localizedStandardContains(query) }
    }

    private var projectResults: [APIProjectRecord] {
        projects.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        List {
            if !chatResults.isEmpty {
                Section("Chats") {
                    ForEach(chatResults, id: \.storageID) { session in
                        Button { onOpenSession(session) } label: {
                            Label(session.displayTitle, systemImage: "bubble.left")
                                .foregroundStyle(theme.colors.textPrimary)
                        }
                        .accessibilityIdentifier("inbox.search.chat.\(session.storageID)")
                    }
                }
            }

            if !projectResults.isEmpty {
                Section("Projects") {
                    ForEach(projectResults, id: \.storageID) { project in
                        Button { onOpenProject(project) } label: {
                            Label(project.name, systemImage: project.semanticIconName)
                                .foregroundStyle(theme.colors.textPrimary)
                        }
                    }
                }
            }

            Section("Messages") {
                if messageSearch.isLoading && messageSearch.items.isEmpty {
                    ProgressView("Searching all chats…")
                        .accessibilityIdentifier("inbox.search.loading")
                }
                if messageSearch.isIndexing {
                    Text("Indexing chat history; more results may appear.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if messageSearch.failedSources > 0 {
                    Text("Some conversations could not be searched.")
                        .font(.caption).foregroundStyle(theme.colors.statusWarning)
                }
                if let error = messageSearch.error {
                    Text("Message search unavailable: \(error)")
                        .font(.caption).foregroundStyle(theme.colors.statusBlocked)
                    Button("Try again") { Task { await searchMessages() } }
                }
                ForEach(messageSearch.items.prefix(8)) { item in
                    Button { onOpenMessage(item) } label: {
                        SessionTextSearchHitRow(hit: item.hit)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("inbox.search.message.\(item.hit.id)")
                }
                Button(action: onSearchText) {
                    Label("See all message results", systemImage: "text.magnifyingglass")
                }
            }

            if chatResults.isEmpty, projectResults.isEmpty, messageSearch.items.isEmpty,
               !messageSearch.isLoading, !messageSearch.isIndexing, messageSearch.error == nil {
                ContentUnavailableView.search(text: query)
            }
        }
        .listStyle(.insetGrouped)
        .mobileScreenBackground()
        .task(id: "\(query)|\(String(describing: endpoints))") {
            await searchMessages()
        }
        .accessibilityIdentifier("inbox.search.results")
    }

    private func searchMessages() async {
        await messageSearch.search(query, endpoints: endpoints, primaryClient: apiClient)
    }
}
#endif
