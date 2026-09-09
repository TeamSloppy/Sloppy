import SloppyClientCore
import SwiftUI

@MainActor
struct PullRequestsScreen: View {
    private enum RoleFilter: String, CaseIterable, Identifiable {
        case all
        case authored
        case reviewRequested

        var id: Self { self }

        var title: String {
            switch self {
            case .all: "All"
            case .authored: "Mine"
            case .reviewRequested: "Review requested"
            }
        }

        var roles: [CodeReviewRole] {
            switch self {
            case .all: CodeReviewRole.allCases
            case .authored: [.authored]
            case .reviewRequested: [.reviewRequested]
            }
        }
    }

    let apiClient: SloppyAPIClient

    @Environment(\.openURL) private var openURL
    @State private var response = CodeReviewInboxResponse(items: [], providers: [])
    @State private var state: CodeReviewState = .open
    @State private var roleFilter: RoleFilter = .all
    @State private var selectedProviderID: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var recoveryMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            filters
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Pull Requests")
        .task(id: requestKey) { await load() }
        .refreshable { await load() }
    }

    private var requestKey: String {
        [state.rawValue, roleFilter.rawValue, selectedProviderID ?? "all"].joined(separator: ":")
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Picker("State", selection: $state) {
                ForEach(CodeReviewState.allCases) { state in
                    Text(state.title).tag(state)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            Picker("Role", selection: $roleFilter) {
                ForEach(RoleFilter.allCases) { role in
                    Text(role.title).tag(role)
                }
            }
            .frame(maxWidth: 190)

            if response.providers.count > 1 {
                Picker("Provider", selection: $selectedProviderID) {
                    Text("All providers").tag(String?.none)
                    ForEach(response.providers) { provider in
                        Text(provider.displayName).tag(Optional(provider.id))
                    }
                }
                .frame(maxWidth: 180)
            }

            Spacer(minLength: 0)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(isLoading)
            .accessibilityLabel("Refresh pull requests")
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage, response.items.isEmpty {
            ContentUnavailableView {
                Label("Couldn’t Load Pull Requests", systemImage: "exclamationmark.triangle")
            } description: {
                VStack(spacing: 8) {
                    Text(errorMessage)
                        .textSelection(.enabled)
                    if let recoveryMessage {
                        Text(recoveryMessage)
                            .foregroundStyle(.secondary)
                    }
                    Text("Server: \(apiClient.baseURL.absoluteString)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            } actions: {
                Button("Try Again") {
                    Task { await load() }
                }
                .disabled(isLoading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !isLoading, response.providers.isEmpty {
            ContentUnavailableView(
                "No Pull Request Providers",
                systemImage: "puzzlepiece.extension",
                description: Text("Connect GitHub or install a code-review plugin.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !isLoading, response.items.isEmpty {
            ContentUnavailableView(
                "No Pull Requests",
                systemImage: "arrow.triangle.branch",
                description: Text("Nothing matches the selected state, role, and provider.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if !response.failures.isEmpty {
                    Section("Provider issues") {
                        ForEach(response.failures.sorted(by: { $0.key < $1.key }), id: \.key) { entry in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(providerName(for: entry.key))
                                        .font(.headline)
                                    Text(entry.value)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                Section {
                    ForEach(response.items) { item in
                        Button { open(item) } label: {
                            PullRequestRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(response.items.count) pull requests")
                }
            }
            .listStyle(.inset)
        }
    }

    private func providerName(for id: String) -> String {
        response.providers.first(where: { $0.id == id })?.displayName ?? id
    }

    private func open(_ item: CodeReviewItem) {
        guard let url = URL(string: item.url) else { return }
        openURL(url)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            response = try await apiClient.fetchCodeReviews(
                state: state,
                roles: roleFilter.roles,
                providerIDs: selectedProviderID.map { [$0] } ?? []
            )
            errorMessage = nil
            recoveryMessage = nil
            if let selectedProviderID,
               !response.providers.contains(where: { $0.id == selectedProviderID }) {
                self.selectedProviderID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
            recoveryMessage = recoverySuggestion(for: error)
        }
    }

    private func recoverySuggestion(for error: Error) -> String {
        guard let apiError = error as? APIError else {
            return "Check that Sloppy Core is running and reachable, then try again."
        }
        switch apiError {
        case .httpError(statusCode: 404, _):
            return "The connected Sloppy Core does not expose the Pull Requests API. Update or restart Core so it matches this client."
        case .httpError(statusCode: 401, _), .httpError(statusCode: 403, _):
            return "The server rejected this session. Reconnect the client and verify the GitHub account permissions."
        case .decodingFailed:
            return "The client and Core use incompatible response formats. Update or restart both components."
        case .invalidResponse, .httpError:
            return "Check the Core status and server logs, then try again."
        }
    }
}

@MainActor
private struct PullRequestRow: View {
    let item: CodeReviewItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.isDraft ? "circle.dashed" : stateImage)
                .foregroundStyle(stateColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(repositoryLabel)
                    Text("·")
                    Text(item.providerName)
                    if let author = item.author {
                        Text("·")
                        Text(author)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    if item.roles.contains(.reviewRequested) {
                        badge("Review requested", color: .orange)
                    }
                    if item.isDraft {
                        badge("Draft", color: .secondary)
                    }
                    if let decision = item.reviewDecision, !decision.isEmpty {
                        badge(decision.replacingOccurrences(of: "_", with: " ").capitalized, color: .blue)
                    }
                    ForEach(item.labels.prefix(3), id: \.self) { label in
                        badge(label, color: .secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            if let updatedAt = item.updatedAt {
                Text(updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private var stateImage: String {
        switch item.state {
        case .open, .all: "arrow.triangle.branch"
        case .closed: "xmark.circle"
        case .merged: "arrow.triangle.merge"
        }
    }

    private var repositoryLabel: String {
        guard let number = item.number else { return item.repository }
        return "\(item.repository) #\(number)"
    }

    private var stateColor: Color {
        switch item.state {
        case .open, .all: .green
        case .closed: .red
        case .merged: .purple
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}
