import SloppyClientCore
import SloppyClientUI
import SwiftUI

@MainActor
struct CodeReviewChatLinkSheet: View {
    let apiClient: SloppyAPIClient
    let onLink: @MainActor (ChatSessionSummary) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var sessions: [ChatSessionSummary] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        content
            .task(id: query) { await loadSessions() }
    }

    @ViewBuilder
    private var content: some View {
#if os(iOS)
        NavigationStack {
            sessionList
                .listStyle(.insetGrouped)
                .mobileScreenBackground()
                .navigationTitle("Link Working Chat")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Search chats or agent IDs")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .overlay {
                    if isLoading && sessions.isEmpty {
                        ProgressView()
                    } else if let errorMessage, sessions.isEmpty {
                        ContentUnavailableView("Chats unavailable", systemImage: "wifi.exclamationmark",
                            description: Text(errorMessage))
                    } else if sessions.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
        }
#else
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Link working chat").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
            }
            TextField("Search chats or agent IDs", text: $query).textFieldStyle(.roundedBorder)
            if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
            if isLoading { ProgressView() }
            sessionList
        }
        .padding(20)
        .frame(minWidth: 320, idealWidth: 500, minHeight: 380)
#endif
    }

    private var sessionList: some View {
        List(sessions) { session in
                Button {
                    onLink(session)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title)
                        Text([session.agentId, session.taskId].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }
    }

    private func loadSessions() async {
            isLoading = true
            defer { isLoading = false }
            do {
                let result = try await apiClient.fetchSessionMentions(query: query)
                guard !Task.isCancelled else { return }
                sessions = result
                errorMessage = nil
            } catch is CancellationError {
            } catch { errorMessage = error.localizedDescription }
    }
}
